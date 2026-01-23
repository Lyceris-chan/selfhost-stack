"""System health and infrastructure monitoring router for the Privacy Hub API.

This module provides endpoints for retrieving system metrics, SSL certificate
status, container health, and triggering system-level operations like backups.
"""

import json
import os
import re
import sqlite3
import subprocess
import time
from datetime import datetime
import tempfile

import psutil
import requests
import urllib.parse
from fastapi import APIRouter, BackgroundTasks, Depends
from cryptography.fernet import Fernet

from ..core.config import settings
from ..core.security import get_admin_user, get_optional_user
from ..utils.logging import log_structured
from ..utils.process import run_command

router = APIRouter()

ODIDO_FERNET_KEY = b"afIqRZm6iSev4zWysNGAjR6fCrOMf5GQqhKFfmXkgOU="
ODIDO_CLIENT_KEY = "9havvat6hm0b962i"
ODIDO_DOMAIN = "odido.nl"


@router.get("/certificate-status")
def get_certificate_status():
    """Returns the status and details of the current SSL certificate.

    This endpoint checks multiple certificate locations and provides detailed
    information about SSL certificate installation and validity.

    Returns:
        A dictionary containing certificate details or error information.
    """
    # Check multiple possible certificate locations
    # Priority order: AdGuard conf, AdGuard certs, generic SSL location
    cert_paths = [
        "/etc/adguard/conf/ssl.crt",
        "/etc/adguard/certs/tls.crt",
        "/etc/adguard/conf/tls.crt",
        "/etc/ssl/certs/hub.crt",
        "/app/data/adguard/conf/ssl.crt",
    ]

    cert_path = None
    for path in cert_paths:
        if os.path.exists(path):
            cert_path = path
            break

    if not cert_path:
        return {
            "error": "Certificate not found in any expected location",
            "installed": False,
            "checked_paths": cert_paths,
        }

    try:
        # Use openssl to parse cert info
        cmd = ["openssl", "x509", "-in", cert_path, "-noout", "-text"]
        result = subprocess.run(
            cmd, capture_output=True, text=True, timeout=5, check=False
        )
        if result.returncode != 0:
            return {
                "error": f"Failed to parse certificate at {cert_path}: {result.stderr}",
                "installed": False,
            }

        output = result.stdout

        # Extract fields with improved regex patterns
        subject = ""
        issuer = ""
        not_after = ""

        # More flexible CN extraction
        sub_match = re.search(
            r"Subject:.*?CN\s*=\s*([^,/\n]+)", output, re.IGNORECASE
        )
        if sub_match:
            subject = sub_match.group(1).strip()

        iss_match = re.search(r"Issuer:.*?CN\s*=\s*([^,/\n]+)", output, re.IGNORECASE)
        if iss_match:
            issuer = iss_match.group(1).strip()

        exp_match = re.search(r"Not After\s*:\s*(.*?)(?:\n|$)", output)
        if exp_match:
            not_after = exp_match.group(1).strip()

        # Determine type
        cert_type = "Self-Signed"
        trusted_issuers = [
            "Let's Encrypt", "R3", "R10", "R11", "E1", "E2", "E5", "E6",
            "ZeroSSL", "Sectigo", "DigiCert", "GTS", "ISRG", "DST Root"
        ]
        # Check if issuer matches any trusted CA (case-insensitive)
        issuer_lower = issuer.lower() if issuer else ""
        if any(ti.lower() in issuer_lower for ti in trusted_issuers):
            cert_type = "Trusted"
        elif issuer and issuer != subject:
            # Check if it's not a self-signed cert (issuer != subject)
            cert_type = f"Trusted (via {issuer})"

        log_structured(
            "INFO", f"Certificate check successful: {cert_type} for {subject}"
        )

        return {
            "installed": True,
            "subject": subject,
            "issuer": issuer,
            "expires": not_after,
            "type": cert_type,
            "status": cert_type,
            "path": cert_path,
        }
    except subprocess.TimeoutExpired:
        return {"error": "Certificate parsing timed out", "installed": False}
    except Exception as err:
        log_structured("ERROR", f"Certificate status check failed: {err}")
        return {"error": str(err), "installed": False}


def get_total_usage(path):
    """Retrieves accumulated data usage from a JSON file.

    Args:
        path: Path to the JSON usage file.

    Returns:
        A tuple of (rx, tx) bytes.
    """
    try:
        if os.path.exists(path) and os.path.getsize(path) > 0:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
                return int(data.get("rx", 0)), int(data.get("tx", 0))
    except Exception:
        pass
    return 0, 0


def save_total_usage(path, rx, tx):
    """Saves accumulated data usage to a JSON file atomically.

    Args:
        path: Path to the JSON usage file.
        rx: Received bytes.
        tx: Transmitted bytes.
    """
    temp_name = None
    try:
        dirname = os.path.dirname(path)
        with tempfile.NamedTemporaryFile("w", dir=dirname, delete=False) as tf:
            json.dump({"rx": int(rx), "tx": int(tx)}, tf)
            temp_name = tf.name
        os.replace(temp_name, path)
    except Exception:
        if temp_name and os.path.exists(temp_name):
            os.remove(temp_name)


@router.get("/health")
def health_check():
    """Lightweight health check for Docker orchestration."""
    return {"status": "ok"}


@router.get("/status")
def get_status(user: str = Depends(get_optional_user)):
    """Aggregates infrastructure and VPN status from the orchestrator."""
    try:
        result = run_command([settings.CONTROL_SCRIPT, "status"], check=False)
        output = result.stdout.strip()
        output = re.sub(r"[\x00-\x1f\x7f-\x9f]", "", output)
        json_start = output.find("{")
        json_end = output.rfind("}")
        if json_start != -1 and json_end != -1:
            output = output[json_start : json_end + 1]

        status_data = json.loads(output)

        # Update total usage for Gluetun
        gluetun_status = status_data.get("gluetun", {})
        if gluetun_status.get("status") == "up":
            total_rx, total_tx = get_total_usage(settings.DATA_USAGE_FILE)
            current_rx = int(gluetun_status.get("session_rx", 0))
            current_tx = int(gluetun_status.get("session_tx", 0))
            save_total_usage(
                settings.DATA_USAGE_FILE, total_rx + current_rx, total_tx + current_tx
            )
            status_data["gluetun"]["total_rx"], status_data["gluetun"]["total_tx"] = (
                get_total_usage(settings.DATA_USAGE_FILE)
            )

        # Update total usage for WG-Easy
        wgeasy_status = status_data.get("wgeasy", {})
        if wgeasy_status.get("status") == "up":
            total_rx, total_tx = get_total_usage(settings.WGE_DATA_USAGE_FILE)
            current_rx = int(wgeasy_status.get("session_rx", 0))
            current_tx = int(wgeasy_status.get("session_tx", 0))
            save_total_usage(
                settings.WGE_DATA_USAGE_FILE,
                total_rx + current_rx,
                total_tx + current_tx,
            )
            status_data["wgeasy"]["total_rx"], status_data["wgeasy"]["total_tx"] = (
                get_total_usage(settings.WGE_DATA_USAGE_FILE)
            )

        # Redaction for guests
        if user == "guest":
            if "gluetun" in status_data:
                # Keep status and health, remove identity/usage
                status_data["gluetun"] = {
                    "status": status_data["gluetun"].get("status"),
                    "healthy": status_data["gluetun"].get("healthy"),
                    "public_ip": "[REDACTED]",
                    "active_profile": "[REDACTED]",
                }
            if "wgeasy" in status_data:
                status_data["wgeasy"] = {
                    "status": status_data["wgeasy"].get("status"),
                    "clients": status_data["wgeasy"].get("clients"),
                    "connected": status_data["wgeasy"].get("connected"),
                }

        return status_data
    except Exception as err:
        log_structured("ERROR", f"Status check failed: {err}")
        return {"error": str(err)}


@router.get("/system-health")
def get_system_health(user: str = Depends(get_optional_user)):
    """Retrieves hardware and host-level health metrics."""
    try:
        uptime_seconds = time.time() - psutil.boot_time()
        cpu_usage = psutil.cpu_percent(interval=0.1)
        ram = psutil.virtual_memory()
        disk = psutil.disk_usage("/")

        project_size_bytes = 0
        if user != "guest":
            try:
                for directory in ["/app/sources", "/app/config", "/app/data"]:
                    if os.path.exists(directory):
                        res = subprocess.run(
                            ["du", "-sk", directory],
                            capture_output=True,
                            text=True,
                            timeout=5,
                            check=False,
                        )
                        if res.returncode == 0:
                            project_size_bytes += int(res.stdout.split()[0]) * 1024

                img_res = subprocess.run(
                    ["docker", "images", "--format", "{{.Size}}\t{{.Repository}}"],
                    capture_output=True,
                    text=True,
                    timeout=5,
                    check=False,
                )
                if img_res.returncode == 0:
                    for line in img_res.stdout.strip().split("\n"):
                        if not line:
                            continue
                        parts = line.split("\t")
                        if len(parts) < 2:
                            continue
                        size_str, repo = parts[0], parts[1]
                        monitored_images = [
                            "immich",
                            "gluetun",
                            "postgres",
                            "redis",
                            "adguard",
                            "unbound",
                            "portainer",
                        ]
                        if repo.startswith("selfhost/") or any(
                            x in repo for x in monitored_images
                        ):
                            mult = 1
                            if "GB" in size_str.upper():
                                mult = 1024 * 1024 * 1024
                            elif "MB" in size_str.upper():
                                mult = 1024 * 1024
                            elif "KB" in size_str.upper():
                                mult = 1024
                            try:
                                sz_val = float(re.sub(r"[^0-9.]", "", size_str))
                                project_size_bytes += int(sz_val * mult)
                            except Exception:
                                pass
            except Exception:
                pass

        drive_health_pct = 100 - disk.percent
        drive_status = "Healthy"
        smart_alerts = []
        if disk.percent > 90:
            drive_status = "Warning (High Usage)"
            smart_alerts.append("Disk space is critical (>90%)")

        data = {
            "uptime": uptime_seconds,
            "cpu_percent": cpu_usage,
            "ram_used": ram.used / (1024 * 1024),
            "ram_total": ram.total / (1024 * 1024),
            "disk_used": disk.used / (1024 * 1024 * 1024),
            "disk_total": disk.total / (1024 * 1024 * 1024),
            "disk_percent": disk.percent,
            "drive_status": drive_status,
            "drive_health_pct": drive_health_pct,
            "smart_alerts": smart_alerts,
        }
        if user != "guest":
            data["project_size"] = project_size_bytes / (1024 * 1024)

        return data
    except Exception as err:
        return {"error": str(err)}


@router.get("/metrics")
def get_metrics(user: str = Depends(get_optional_user)):
    """Retrieves container-level performance metrics from the database."""
    try:
        conn = sqlite3.connect(settings.DB_FILE)
        cursor = conn.cursor()
        cursor.execute(
            """SELECT container, cpu_percent, mem_usage, mem_limit
               FROM metrics WHERE id IN
               (SELECT MAX(id) FROM metrics GROUP BY container)"""
        )
        rows = cursor.fetchall()
        conn.close()
        container_metrics = {
            r[0]: {"cpu": r[1], "mem": r[2], "limit": r[3]} for r in rows
        }
        return {"metrics": container_metrics}
    except Exception as err:
        return {"error": str(err)}


@router.get("/containers")
def get_containers(user: str = Depends(get_optional_user)):
    """Lists all stack containers and their hardening status."""
    try:
        result = run_command(
            [
                "docker",
                "ps",
                "-a",
                "--no-trunc",
                "--format",
                "{{.Names}}\t{{.ID}}\t{{.Labels}}",
            ],
            timeout=10,
        )
        containers_info = {}
        for line in result.stdout.strip().split("\n"):
            parts = line.split("\t")
            if len(parts) >= 2:
                name, cid = parts[0], parts[1]
                if settings.CONTAINER_PREFIX and name.startswith(
                    settings.CONTAINER_PREFIX
                ):
                    name = name[len(settings.CONTAINER_PREFIX) :]
                labels = parts[2] if len(parts) > 2 else ""
                is_hardened = "io.privacyhub.hardened=true" in labels

                # Redact CID for guest
                c_data = {"hardened": is_hardened}
                if user != "guest":
                    c_data["id"] = cid

                containers_info[name] = c_data
        return {"containers": containers_info}
    except Exception as err:
        return {"error": str(err)}


@router.get("/project-details")
def get_project_details(user: str = Depends(get_admin_user)):
    """Returns a detailed storage breakdown of the project."""
    breakdown = []
    total_size = 0
    reclaimable = 0

    paths = [
        {"path": "/app/sources", "category": "Source code", "icon": "code"},
        {"path": "/app/data", "category": "Application data", "icon": "database"},
        {"path": "/etc/adguard/conf", "category": "Configuration", "icon": "settings"},
    ]

    for p in paths:
        if os.path.exists(p["path"]):
            try:
                res = subprocess.run(
                    ["du", "-sk", p["path"]],
                    capture_output=True,
                    text=True,
                    timeout=5,
                    check=False,
                )
                if res.returncode == 0:
                    size_mb = int(res.stdout.split()[0]) / 1024
                    breakdown.append(
                        {"category": p["category"], "size": size_mb, "icon": p["icon"]}
                    )
                    total_size += size_mb
            except Exception:
                pass

    # Docker storage
    try:
        img_res = subprocess.run(
            ["docker", "images", "--format", "{{.Size}}"],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
        docker_size = 0
        if img_res.returncode == 0:
            for line in img_res.stdout.strip().split("\n"):
                if not line:
                    continue
                mult = 1
                if "GB" in line.upper():
                    mult = 1024
                elif "MB" in line.upper():
                    mult = 1
                elif "KB" in line.upper():
                    mult = 1 / 1024
                try:
                    val = float(re.sub(r"[^0-9.]", "", line))
                    docker_size += val * mult
                except Exception:
                    pass

        if docker_size > 0:
            breakdown.append(
                {"category": "Container images", "size": docker_size, "icon": "layers"}
            )
            total_size += docker_size

        prune_res = subprocess.run(
            ["docker", "system", "df", "--format", "{{.Reclaimable}}"],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
        if prune_res.returncode == 0:
            for line in prune_res.stdout.strip().split("\n"):
                if not line:
                    continue
                mult = 1
                if "GB" in line.upper():
                    mult = 1024
                elif "MB" in line.upper():
                    mult = 1
                elif "KB" in line.upper():
                    mult = 1 / 1024
                try:
                    val = float(re.sub(r"[^0-9.]", "", line))
                    reclaimable += val * mult
                except Exception:
                    pass
    except Exception:
        pass

    # Only show reclaimable if it's significant (> 100 MB)
    if reclaimable < 100:
        reclaimable = 0

    return {"breakdown": breakdown, "total": total_size, "reclaimable": reclaimable}


@router.post("/purge-images")
def purge_images(user: str = Depends(get_admin_user)):
    """Triggers a cleanup of unused Docker images and build cache."""
    try:
        res = run_command(["docker", "image", "prune", "-f"], timeout=60)
        reclaimed_msg = "Unused images and build cache cleared."
        if "Total reclaimed space:" in res.stdout:
            reclaimed = (
                res.stdout.split("Total reclaimed space:")[1].strip().split("\n")[0]
            )
            reclaimed_msg = f"Successfully reclaimed {reclaimed} of storage space."

        run_command(["docker", "builder", "prune", "-f"], timeout=60)
        return {"success": True, "message": reclaimed_msg}
    except Exception as err:
        return {"error": str(err)}


@router.post("/restart-stack")
def restart_stack(
    background_tasks: BackgroundTasks, user: str = Depends(get_admin_user)
):
    """Triggers a restart of all containers in the stack."""

    def _restart():
        time.sleep(2)
        subprocess.run(
            ["docker", "compose", "-f", "/app/docker-compose.yml", "restart"],
            check=False,
        )

    background_tasks.add_task(_restart)
    log_structured(
        "SYSTEM", "Full stack restart triggered via Dashboard", "ORCHESTRATION"
    )
    return {"success": True, "message": "Stack restart initiated"}


@router.get("/backups")
def list_backups(user: str = Depends(get_admin_user)):
    """Lists all available system backup archives."""
    backup_dir = "/app/backups"
    if not os.path.exists(backup_dir):
        return {"backups": []}

    backups_list = []
    for filename in os.listdir(backup_dir):
        if filename.endswith(".tar.gz"):
            path = os.path.join(backup_dir, filename)
            file_stat = os.stat(path)
            backups_list.append(
                {
                    "filename": filename,
                    "size": file_stat.st_size / (1024 * 1024),
                    "timestamp": datetime.fromtimestamp(file_stat.st_mtime).strftime(
                        "%Y-%m-%d %H:%M:%S"
                    ),
                }
            )

    return {"backups": sorted(backups_list, key=lambda x: x["timestamp"], reverse=True)}


@router.post("/backup")
def trigger_backup(
	background_tasks: BackgroundTasks, user: str = Depends(get_admin_user)
):
	"""Triggers a background system backup task."""

	def _backup():
		log_structured("INFO", "System backup initiated", "MAINTENANCE")
		env = os.environ.copy()
		env["PROJECT_ROOT"] = "/app"
		env["BASE_DIR"] = "/app"
		env["SKIP_SUDO_CHECK"] = "true"
		subprocess.run(["bash", "/app/zima.sh", "-b"], env=env, cwd="/app", check=False)

	background_tasks.add_task(_backup)
	return {"success": True, "message": "Backup sequence started in background"}


@router.post("/restore")
def trigger_restore(
    filename: str,
    background_tasks: BackgroundTasks,
    user: str = Depends(get_admin_user),
):
    """Triggers a system restoration from a specific backup file."""
    backup_path = os.path.join("/app/backups", filename)
    if not os.path.exists(backup_path):
        return {"error": "Backup file not found"}

    def _restore():
        log_structured(
            "INFO", f"System restore initiated from {filename}", "MAINTENANCE"
        )
        env = os.environ.copy()
        env["SKIP_SUDO_CHECK"] = "true"
        # Restoring might disrupt the API itself, but zima.sh -r just extracts files.
        subprocess.run(
            ["bash", "/app/zima.sh", "-r", backup_path], env=env, cwd="/app", check=False
        )
        # After restore, we should probably restart everything
        subprocess.run(
            ["docker", "compose", "-f", "/app/docker-compose.yml", "restart"],
            check=False,
        )

    background_tasks.add_task(_restore)
    return {"success": True, "message": "Restore sequence started in background"}


@router.post("/uninstall")
def uninstall(background_tasks: BackgroundTasks, user: str = Depends(get_admin_user)):
    """Triggers the full uninstallation sequence."""

    def _uninstall():
        log_structured("INFO", "Uninstall sequence started", "MAINTENANCE")
        time.sleep(5)
        env = os.environ.copy()
        env["SKIP_SUDO_CHECK"] = "true"
        subprocess.run(["bash", "/app/zima.sh", "-x"], env=env, cwd="/app", check=False)

    background_tasks.add_task(_uninstall)
    return {"success": True, "message": "Uninstall sequence started"}


@router.get("/odido-login-url")
def get_odido_login_url(user: str = Depends(get_admin_user)):
    """Generates the proprietary Odido login URL with encrypted token."""
    try:
        f = Fernet(ODIDO_FERNET_KEY)
        encrypted_client_key = f.encrypt(ODIDO_CLIENT_KEY.encode()).decode()
        # Ensure URL safe encoding if needed, but C# just puts it in query.
        # However, Fernet output is URL safe base64.
        url = f"https://www.{ODIDO_DOMAIN}/login?returnSystem=app&nav=off&token={encrypted_client_key}"
        return {"url": url}
    except Exception as e:
        log_structured("ERROR", f"Failed to generate Odido URL: {e}", "ODIDO")
        return {"error": str(e)}


@router.post("/odido-exchange-token")
def exchange_odido_token(request: dict, user: str = Depends(get_admin_user)):
    """Exchanges Odido callback token for OAuth token.

    This endpoint processes the encrypted token received from the Odido sign-in
    callback URL and exchanges it for a usable OAuth access token. This
    replicates the functionality of the Odido.Authenticator tool directly in
    the dashboard.

    Args:
        request: Dictionary containing 'callback_token' (the token parameter
                 from the callback URL).
        user: Authenticated admin user.

    Returns:
        Dictionary with 'oauth_token' or 'error'.
    """
    import base64
    import json as json_lib

    callback_token = request.get("callback_token", "").strip()
    if not callback_token:
        return {"error": "Callback token is required"}

    try:
        refresh_token = None

        # New Flow: Decrypt using Fernet
        try:
            f = Fernet(ODIDO_FERNET_KEY)

            # Extract token from URL if full URL is pasted
            token_to_decrypt = callback_token
            if "token=" in callback_token:
                match = re.search(r"token=([^&]+)", callback_token)
                if match:
                    token_to_decrypt = match.group(1)

            # URL Decode
            token_to_decrypt = urllib.parse.unquote(token_to_decrypt)

            # First Decryption
            decrypted_bytes = f.decrypt(token_to_decrypt.encode())
            decrypted_str = decrypted_bytes.decode()
            login_response = json_lib.loads(decrypted_str)

            # Second Decryption (AccessToken -> Refresh Token)
            encrypted_refresh_token = login_response.get("AccessToken")
            if encrypted_refresh_token:
                decrypted_refresh_bytes = f.decrypt(encrypted_refresh_token.encode())
                refresh_token = decrypted_refresh_bytes.decode()

        except Exception as fernet_err:
            log_structured(
                "WARN",
                f"Fernet decryption failed, trying legacy flow: {fernet_err}",
                "ODIDO",
            )
            # Legacy/Fallback Flow
            try:
                decoded = base64.b64decode(callback_token).decode("utf-8")
                token_data = json_lib.loads(decoded)
                refresh_token = token_data.get("refresh_token") or token_data.get(
                    "token"
                )
            except Exception:
                refresh_token = callback_token

        if not refresh_token:
            return {"error": "Could not extract refresh token"}

        # Exchange refresh token for access token via Odido token endpoint
        token_url = "https://login.odido.nl/connect/token"
        token_data = {
            "grant_type": "refresh_token",
            "refresh_token": refresh_token,
            "client_id": "OdidoMobileApp",
        }

        headers = {
            "Content-Type": "application/x-www-form-urlencoded",
            "User-Agent": "T-Mobile 5.3.28 (Android 10; 10)",
        }

        resp = requests.post(token_url, data=token_data, headers=headers, timeout=10)

        if resp.status_code != 200:
            log_structured(
                "ERROR",
                f"Odido token exchange failed: {resp.status_code} - {resp.text}",
                "ODIDO",
            )
            return {"error": f"Token exchange failed: {resp.status_code}"}

        result = resp.json()
        access_token = result.get("access_token")

        if not access_token:
            return {"error": "No access token in response"}

        log_structured("SUCCESS", "Odido OAuth token exchanged successfully", "ODIDO")
        return {"oauth_token": access_token}

    except Exception as err:
        log_structured("ERROR", f"Odido token exchange error: {err}", "ODIDO")
        return {"error": str(err)}


@router.post("/odido-userid")
def fetch_odido_userid(request: dict, user: str = Depends(get_admin_user)):
    """Fetches Odido User ID from OAuth token via API redirect.

    This endpoint automatically extracts the User ID by following the Odido
    API redirect chain, eliminating manual token configuration. The
    Odido.Authenticator tool generates the OAuth token, which this endpoint
    then uses to automatically retrieve the User ID.

    Args:
        request: Dictionary containing 'oauth_token'.
        user: Authenticated admin user.

    Returns:
        Dictionary with 'user_id' or 'error'.
    """
    oauth_token = request.get("oauth_token", "").strip()
    if not oauth_token:
        return {"error": "OAuth token is required"}

    try:
        headers = {
            "Authorization": f"Bearer {oauth_token}",
            "User-Agent": "T-Mobile 5.3.28 (Android 10; 10)",
        }
        resp = requests.get(
            "https://capi.odido.nl/account/current",
            headers=headers,
            allow_redirects=True,
            timeout=10,
        )
        final_url = resp.url

        # Extract 12-char hex User ID from redirect URL
        # Format: https://capi.odido.nl/{userid}/account/current
        id_match = re.search(
            r"capi\.odido\.nl/([0-9a-f]{12})", final_url, re.IGNORECASE
        )
        if id_match:
            user_id = id_match.group(1)
            log_structured(
                "SUCCESS", f"Odido User ID retrieved via API: {user_id}", "ODIDO"
            )
            return {"user_id": user_id}
        else:
            log_structured(
                "WARN", "Failed to extract User ID from Odido API redirect", "ODIDO"
            )
            return {"error": "Could not extract User ID from API response"}
    except Exception as err:
        log_structured("ERROR", f"Odido User ID fetch error: {err}", "ODIDO")
        return {"error": str(err)}
