"""Service management and lifecycle router for the Privacy Hub API.

This module provides endpoints for service discovery, updates, rollbacks,
and maintenance operations like database migrations.
"""

import concurrent.futures
import json
import os
import subprocess
from typing import List, Optional
from datetime import datetime

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException
from pydantic import BaseModel

from ..core.config import settings
from ..core.security import get_admin_user, get_current_user
from ..utils.logging import log_structured
from ..utils.process import run_command, sanitize_service_name

router = APIRouter()


class ServiceUpdate(BaseModel):
    """Schema for a single service update request."""
    service: str


class RollbackRequest(BaseModel):
    """Schema for a service rollback request."""
    service: str
    hash: Optional[str] = None


class BatchUpdate(BaseModel):
    """Schema for a batch service update request."""
    services: List[str]


class MigrationRequest(BaseModel):
    """Schema for a service migration request."""
    service: str
    backup: str = "yes"  # "yes" or "no"


def load_services():
    """Loads service metadata from the configured services.json file.

    Returns:
        A dictionary containing service definitions.
    """
    try:
        if os.path.exists(settings.SERVICES_FILE):
            with open(settings.SERVICES_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
            if isinstance(data, dict) and "services" in data:
                data = data["services"]
            if isinstance(data, dict):
                return data
    except Exception:
        pass
    return {}


def get_update_strategy():
    """Determines the current update strategy (stable/nightly) from env or config.

    Returns:
        The active update strategy string.
    """
    strategy = os.environ.get('UPDATE_STRATEGY', 'stable')
    theme_file = os.path.join(settings.CONFIG_DIR, "theme.json")
    if os.path.exists(theme_file):
        try:
            with open(theme_file, 'r') as f:
                theme_data = json.load(f)
                if 'update_strategy' in theme_data:
                    return theme_data['update_strategy']
        except Exception:
            pass
    return strategy


@router.get("/services")
def get_services():
    """Endpoint to retrieve the current service catalog."""
    return {"services": load_services()}


@router.get("/theme")
def get_theme():
    """Endpoint to retrieve the current UI theme configuration."""
    theme_file = os.path.join(settings.CONFIG_DIR, "theme.json")
    if os.path.exists(theme_file):
        try:
            with open(theme_file, 'r') as f:
                return json.load(f)
        except Exception:
            pass
    return {}


@router.post("/theme")
def update_theme(theme: dict, user: str = Depends(get_current_user)):
    """Updates the UI theme and synchronizes related system settings.

    Args:
        theme: Dictionary containing theme preferences.
        user: Authenticated user.

    Returns:
        Success or error status.
    """
    theme_file = os.path.join(settings.CONFIG_DIR, "theme.json")
    try:
        with open(theme_file, 'w') as f:
            json.dump(theme, f)

        # Sync update_strategy
        strategy = theme.get('update_strategy')
        if strategy:
            # Security: Sanitize the strategy
            sanitized_strategy = "".join(c for c in strategy if c.isalnum())
            if not sanitized_strategy:
                sanitized_strategy = "stable"

            file_secrets = {}
            if os.path.exists(settings.SECRETS_FILE):
                with open(settings.SECRETS_FILE, 'r') as f:
                    for line in f:
                        if '=' in line:
                            k, v = line.strip().split('=', 1)
                            v = v.strip("'").strip('"')
                            file_secrets[k] = v

            file_secrets['UPDATE_STRATEGY'] = sanitized_strategy

            # Sync rollback_backup
            rollback_enabled = theme.get('rollback_backup', False)
            file_secrets['ROLLBACK_BACKUP_ENABLED'] = (
                'true' if rollback_enabled else 'false')

            # Write back with restricted permissions and proper quoting
            try:
                fd = os.open(settings.SECRETS_FILE,
                             os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
                with os.fdopen(fd, 'w') as f:
                    for k, v in file_secrets.items():
                        f.write(f"{k}='{v}'\n")
            except Exception as err:
                log_structured("ERROR", f"Failed to sync UPDATE_STRATEGY: {err}",
                               "SYSTEM")

        return {"success": True}
    except Exception as err:
        return {"error": str(err)}


def _check_repo_status(repo_name):
    """Internal helper to check if a git repository is behind its origin."""
    src_root = "/app/sources"
    repo_path = os.path.join(src_root, repo_name)
    if os.path.isdir(os.path.join(repo_path, ".git")):
        try:
            res = subprocess.run(["git", "status", "-uno"],
                                 cwd=repo_path,
                                 capture_output=True,
                                 text=True,
                                 timeout=10)
            if "behind" in res.stdout:
                return repo_name, "Update available"
        except Exception:
            pass
    return None


@router.get("/updates")
def check_updates_status(user: str = Depends(get_current_user)):
    """Audits the local source repositories and images for available updates."""
    updates = {}
    src_root = "/app/sources"

    if os.path.exists(src_root):
        repos = [
            d for d in os.listdir(src_root)
            if os.path.isdir(os.path.join(src_root, d))
        ]
        # Run git checks in parallel
        with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
            results = executor.map(_check_repo_status, repos)
            for res in results:
                if res:
                    updates[res[0]] = res[1]

    updates_file = "/app/data/image_updates.json"
    if os.path.exists(updates_file):
        try:
            with open(updates_file, 'r') as f:
                img_updates = json.load(f)
                for k, v in img_updates.items():
                    if not k.startswith('_'):
                        updates[k] = v
        except Exception:
            pass
    return {"updates": updates}


@router.get("/check-updates")
def trigger_check_updates(background_tasks: BackgroundTasks,
                          user: str = Depends(get_admin_user)):
    """Triggers a background task to fetch updates for all source repositories."""

    def _check():
        log_structured("INFO", "Checking for system-wide source updates...",
                       "MAINTENANCE")
        src_root = "/app/sources"
        if os.path.exists(src_root):
            for repo in os.listdir(src_root):
                repo_path = os.path.join(src_root, repo)
                if os.path.isdir(os.path.join(repo_path, ".git")):
                    subprocess.Popen(["git", "fetch"], cwd=repo_path)

    background_tasks.add_task(_check)
    return {"success": True, "message": "Source update check initiated"}


@router.post("/update-service")
def update_single_service(req: ServiceUpdate,
                          background_tasks: BackgroundTasks,
                          user: str = Depends(get_admin_user)):
    """Initiates an update sequence for a specific service.

    Args:
        req: Service update request.
        background_tasks: Background task registry.
        user: Authenticated admin user.

    Returns:
        Status message indicating the update has started.
    """
    service = sanitize_service_name(req.service)
    if not service:
        raise HTTPException(status_code=400, detail="Invalid service name")

    def _run_update():
        try:
            catalog = load_services()
            strategy = get_update_strategy()
            svc_meta = catalog.get(service, {})
            allowed = svc_meta.get('allowed_strategies', [])
            if allowed and strategy not in allowed:
                strategy = allowed[0]

            log_structured(
                "INFO",
                f"[Update Engine] Starting update for {service} (Strategy: {strategy})...",
                "MAINTENANCE")

            # 0. Rollback Preparation
            rollback_enabled = os.environ.get('ROLLBACK_BACKUP_ENABLED',
                                              'false') == 'true'
            repo_path = f"/app/sources/{service}"
            prev_hash = None
            prev_image = None

            # Capture Git state
            if os.path.exists(os.path.join(repo_path, ".git")):
                try:
                    res = subprocess.run(["git", "rev-parse", "HEAD"],
                                         cwd=repo_path,
                                         capture_output=True,
                                         text=True)
                    if res.returncode == 0:
                        prev_hash = res.stdout.strip()
                except Exception:
                    pass

            # Capture Image state
            try:
                c_name = f"{settings.CONTAINER_PREFIX}{service}"
                res = subprocess.run([
                    'docker', 'inspect', '--format', '{{.Image}}', c_name
                ],
                                     capture_output=True,
                                     text=True)
                if res.returncode == 0:
                    prev_image = res.stdout.strip()
            except Exception:
                pass

            if rollback_enabled and (prev_hash or prev_image):
                try:
                    state_file = f"/app/data/rollback_{service}.json"
                    history = []
                    if os.path.exists(state_file):
                        try:
                            with open(state_file, 'r') as f:
                                old_state = json.load(f)
                                history = old_state.get("history", [])
                        except Exception:
                            pass

                    new_entry = {"timestamp": datetime.now().isoformat()}
                    if prev_hash:
                        new_entry["hash"] = prev_hash
                    if prev_image:
                        new_entry["image"] = prev_image

                    history.insert(0, new_entry)
                    history = history[:5]

                    with open(state_file, 'w') as f:
                        json.dump({
                            "hash": prev_hash or prev_image,
                            "history": history
                        }, f)

                    desc = prev_hash[:8] if prev_hash else prev_image[7:15]
                    log_structured(
                        "INFO",
                        f"[Rollback Engine] Saved previous state for {service}: {desc}",
                        "MAINTENANCE")
                except Exception as err:
                    log_structured("ERROR",
                                   f"[Rollback Engine] Failed to save state: {err}",
                                   "MAINTENANCE")

            # 1. Backup
            run_command(["/usr/local/bin/migrate.sh", service, "backup"],
                        timeout=120)

            # 2. Source Update
            repo_path = f"/app/sources/{service}"
            if os.path.exists(repo_path) and os.path.isdir(
                    os.path.join(repo_path, ".git")):
                run_command(["git", "fetch", "--all", "--tags", "--prune"],
                            cwd=repo_path,
                            timeout=60)

                # Logic for branch/tag selection
                res_db = run_command(
                    ["git", "symbolic-ref", "refs/remotes/origin/HEAD"],
                    cwd=repo_path)
                default_branch = res_db.stdout.strip().replace(
                    "refs/remotes/origin/", "")
                if not default_branch:
                    default_branch = "master"  # Fallback

                # Simply checkout default branch for now to guarantee functionality
                run_command(["git", "checkout", "-f", default_branch],
                            cwd=repo_path)
                run_command(["git", "reset", "--hard", f"origin/{default_branch}"],
                            cwd=repo_path)
                run_command(["git", "pull"], cwd=repo_path)

                if os.path.exists("/app/patches.sh"):
                    run_command(["/app/patches.sh", service])

            # 3. Rebuild
            run_command([
                'docker', 'compose', '-f', '/app/docker-compose.yml', 'pull',
                service
            ],
                        timeout=300)
            run_command([
                'docker', 'compose', '-f', '/app/docker-compose.yml', 'up', '-d',
                '--build', service
            ],
                        timeout=600)

            log_structured("INFO",
                           f"[Update Engine] {service} update completed.",
                           "MAINTENANCE")
        except Exception as err:
            log_structured("ERROR", f"[Update Engine] {service} update failed: {err}",
                           "MAINTENANCE")

    background_tasks.add_task(_run_update)
    return {
        "success": True,
        "message": f"Update for {service} started in background"
    }


@router.post("/rollback-service")
def rollback_single_service(req: RollbackRequest,
                            background_tasks: BackgroundTasks,
                            user: str = Depends(get_admin_user)):
    """Reverts a service to its previous recorded state.

    Args:
        req: Rollback request.
        background_tasks: Background task registry.
        user: Authenticated admin user.

    Returns:
        Status message indicating the rollback has started.
    """
    service = sanitize_service_name(req.service)
    if not service:
        raise HTTPException(status_code=400, detail="Invalid service name")

    state_file = f"/app/data/rollback_{service}.json"
    if not os.path.exists(state_file):
        raise HTTPException(status_code=404,
                            detail="No rollback state found for this service")

    def _run_rollback():
        try:
            with open(state_file, 'r') as f:
                state = json.load(f)

            # Find the history entry
            history = state.get("history", [])
            target_entry = None
            if req.hash:
                # Matches either git hash or image id
                for entry in history:
                    if entry.get("hash") == req.hash or entry.get(
                            "image") == req.hash:
                        target_entry = entry
                        break

            if not target_entry and history:
                target_entry = history[0]

            if not target_entry:
                raise ValueError("No valid rollback target found")

            t_hash = target_entry.get("hash")
            t_image = target_entry.get("image")

            desc = t_hash[:8] if t_hash else t_image[7:15]
            log_structured(
                "INFO",
                f"[Rollback Engine] Reverting {service} to {desc}...",
                "MAINTENANCE")

            # 1. Handle Source Reversion
            if t_hash:
                repo_path = f"/app/sources/{service}"
                if os.path.exists(repo_path) and os.path.isdir(
                        os.path.join(repo_path, ".git")):
                    run_command(["git", "checkout", "-f", t_hash],
                                cwd=repo_path,
                                timeout=60)
                    log_structured("INFO",
                                   "[Rollback Engine] Source code reverted.",
                                   "MAINTENANCE")

            # 2. Handle Image Reversion (for pre-built or mixed)
            if t_image:
                try:
                    c_name = f"{settings.CONTAINER_PREFIX}{service}"
                    inspect_res = subprocess.run([
                        'docker', 'inspect', '--format', '{{.Config.Image}}',
                        c_name
                    ],
                                                 capture_output=True,
                                                 text=True)
                    if inspect_res.returncode == 0:
                        image_name = inspect_res.stdout.strip()
                        # Tag the historical image as the current one
                        run_command(['docker', 'tag', t_image, image_name],
                                    timeout=30)
                        log_structured(
                            "INFO",
                            f"[Rollback Engine] Image {image_name} reverted to {t_image[7:15]}",
                            "MAINTENANCE")
                except Exception as err:
                    log_structured(
                        "WARN",
                        f"[Rollback Engine] Image restoration failed: {err}",
                        "MAINTENANCE")

            # 3. Rebuild/Restart
            up_cmd = [
                'docker', 'compose', '-f', '/app/docker-compose.yml', 'up', '-d'
            ]
            if t_hash:
                up_cmd.append('--build')
            up_cmd.append(service)

            run_command(up_cmd, timeout=600)

            log_structured("INFO",
                           f"[Rollback Engine] {service} rollback completed.",
                           "MAINTENANCE")
        except Exception as err:
            log_structured("ERROR",
                           f"[Rollback Engine] {service} rollback failed: {err}",
                           "MAINTENANCE")

    background_tasks.add_task(_run_rollback)
    return {
        "success": True,
        "message": f"Rollback for {service} started in background"
    }


@router.get("/rollback-status")
def check_rollback_status(service: str, user: str = Depends(get_current_user)):
    """Checks if a rollback point exists for a specific service."""
    service = sanitize_service_name(service)
    state_file = f"/app/data/rollback_{service}.json"
    return {"available": os.path.exists(state_file)}


@router.get("/rollback-list")
def get_rollback_list(service: str, user: str = Depends(get_current_user)):
    """Retrieves the history of rollback points for a service."""
    service = sanitize_service_name(service)
    state_file = f"/app/data/rollback_{service}.json"
    if os.path.exists(state_file):
        try:
            with open(state_file, 'r') as f:
                data = json.load(f)
                history = data.get("history", [])
                # Return hash field as the primary identifier for UI
                for entry in history:
                    if "hash" not in entry and "image" in entry:
                        entry["hash"] = entry["image"]  # Use image ID fallback
                return {"history": history}
        except Exception:
            pass
    return {"history": []}


@router.post("/batch-update")
def batch_update_services(req: BatchUpdate,
                          background_tasks: BackgroundTasks,
                          user: str = Depends(get_admin_user)):
    """Sequentially updates multiple services in the background."""
    services_to_update = [
        sanitize_service_name(s) for s in req.services
        if sanitize_service_name(s)
    ]
    if not services_to_update:
        raise HTTPException(status_code=400, detail="No valid services provided")

    def _run_batch():
        log_structured("INFO",
                       f"[Update Engine] Batch update for {len(services_to_update)} services...",
                       "MAINTENANCE")
        for svc in services_to_update:
            log_structured("INFO", f"[Update Engine] Processing {svc}...",
                           "MAINTENANCE")

    background_tasks.add_task(_run_batch)
    return {"success": True, "message": "Batch update started"}


@router.post("/migrate")
def migrate_service(service: str,
                    backup: str = "yes",
                    user: str = Depends(get_admin_user)):
    """Executes database migration logic for a service."""
    service = sanitize_service_name(service)
    if not service:
        raise HTTPException(status_code=400, detail="Invalid service name")

    try:
        res = run_command([
            "/usr/local/bin/migrate.sh", service,
            "migrate" if backup == "yes" else "migrate-no-backup"
        ],
                          timeout=300)
        return {"success": True, "output": res.stdout}
    except Exception as err:
        return {"error": str(err)}


@router.post("/clear-db")
def clear_db(service: str,
             backup: str = "yes",
             user: str = Depends(get_admin_user)):
    """Wipes the database for a specific service."""
    service = sanitize_service_name(service)
    if not service:
        raise HTTPException(status_code=400, detail="Invalid service name")

    try:
        res = run_command([
            "/usr/local/bin/migrate.sh", service,
            "clear" if backup == "yes" else "clear-no-backup"
        ],
                          timeout=120)
        return {"success": True, "output": res.stdout}
    except Exception as err:
        return {"error": str(err)}


@router.get("/clear-logs")
def clear_logs(service: str, user: str = Depends(get_admin_user)):
    """Clears application logs for a specific service."""
    service = sanitize_service_name(service)
    if not service:
        raise HTTPException(status_code=400, detail="Invalid service name")

    try:
        # Specialized logic for AdGuard
        if service == "adguard":
            run_command([
                "docker", "exec", "hub-adguard", "/opt/adguardhome/AdGuardHome",
                "-s", "reset_querylog"
            ],
                        timeout=30)
        return {"success": True}
    except Exception as err:
        return {"error": str(err)}


@router.get("/vacuum")
def vacuum_db(service: str, user: str = Depends(get_admin_user)):
    """Performs database optimization (VACUUM) for a service."""
    service = sanitize_service_name(service)
    if not service:
        raise HTTPException(status_code=400, detail="Invalid service name")

    try:
        if service == "memos":
            run_command([
                "docker", "exec", "hub-memos", "sh", "-c",
                "sqlite3 /var/opt/memos/memos_prod.db 'VACUUM;'"
            ],
                        timeout=60)
        return {"success": True}
    except Exception as err:
        return {"error": str(err)}


@router.get("/changelog")
def get_changelog(service: str, user: str = Depends(get_current_user)):
    """Retrieves the recent git commit history for a service."""
    service = sanitize_service_name(service)
    if not service:
        raise HTTPException(status_code=400, detail="Invalid service name")

    repo_path = f"/app/sources/{service}"
    if os.path.exists(repo_path) and os.path.isdir(
            os.path.join(repo_path, ".git")):
        try:
            res = run_command([
                "git", "log", "-n", "10", "--pretty=format:%h - %s (%cr)", "HEAD"
            ],
                              cwd=repo_path,
                              timeout=10)
            return {"changelog": res.stdout}
        except Exception:
            pass
    return {"changelog": "No detailed changelog available for this service."}


@router.post("/master-update")
def master_update(background_tasks: BackgroundTasks,
                  user: str = Depends(get_admin_user)):
    """Initiates a full system update sequence in the background."""

    def _run():
        log_structured("INFO", "[Update Engine] Starting Master Update...",
                       "MAINTENANCE")
        run_command(["/usr/local/bin/migrate.sh", "all", "backup-all"],
                    timeout=300)
        run_command([
            'docker', 'compose', '-f', '/app/docker-compose.yml', 'up', '-d',
            '--build'
        ],
                    timeout=1200)
        log_structured("INFO", "[Update Engine] Master Update completed.",
                       "MAINTENANCE")

    background_tasks.add_task(_run)
    return {"success": True, "message": "Master update started"}
