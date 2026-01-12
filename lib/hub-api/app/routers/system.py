import os
import json
import time
import psutil
import subprocess
import re
import sqlite3
import threading
from fastapi import APIRouter, Depends, BackgroundTasks
from ..core.security import get_current_user, get_admin_user
from ..core.config import settings
from ..utils.logging import log_structured
from ..utils.process import run_command

router = APIRouter()

def get_total_usage(path):
    try:
        if os.path.exists(path) and os.path.getsize(path) > 0:
            with open(path, 'r') as f:
                data = json.load(f)
                return int(data.get('rx', 0)), int(data.get('tx', 0))
    except Exception:
        pass
    return 0, 0

def save_total_usage(path, rx, tx):
    try:
        import tempfile
        dirname = os.path.dirname(path)
        with tempfile.NamedTemporaryFile('w', dir=dirname, delete=False) as tf:
            json.dump({'rx': int(rx), 'tx': int(tx)}, tf)
            temp_name = tf.name
        os.replace(temp_name, path)
    except Exception:
        if 'temp_name' in locals() and os.path.exists(temp_name):
            os.remove(temp_name)

@router.get("/health")
def health_check():
    """Lightweight health check for Docker orchestration."""
    return {"status": "ok"}

@router.get("/status")
def get_status(user: str = Depends(get_current_user)):
    try:
        result = run_command([settings.CONTROL_SCRIPT, "status"], check=False)
        output = result.stdout.strip()
        output = re.sub(r'[\x00-\x1f\x7f-\x9f]', '', output)
        json_start = output.find('{')
        json_end = output.rfind('}')
        if json_start != -1 and json_end != -1:
            output = output[json_start:json_end+1]
        
        status_data = json.loads(output)
        
        # Update total usage for Gluetun
        g = status_data.get('gluetun', {})
        if g.get('status') == 'up':
            total_rx, total_tx = get_total_usage(settings.DATA_USAGE_FILE)
            current_rx = int(g.get('session_rx', 0))
            current_tx = int(g.get('session_tx', 0))
            save_total_usage(settings.DATA_USAGE_FILE, total_rx + current_rx, total_tx + current_tx)
            status_data['gluetun']['total_rx'], status_data['gluetun']['total_tx'] = get_total_usage(settings.DATA_USAGE_FILE)
        
        # Update total usage for WG-Easy
        w = status_data.get('wgeasy', {})
        if w.get('status') == 'up':
            total_rx, total_tx = get_total_usage(settings.WGE_DATA_USAGE_FILE)
            current_rx = int(w.get('session_rx', 0))
            current_tx = int(w.get('session_tx', 0))
            save_total_usage(settings.WGE_DATA_USAGE_FILE, total_rx + current_rx, total_tx + current_tx)
            status_data['wgeasy']['total_rx'], status_data['wgeasy']['total_tx'] = get_total_usage(settings.WGE_DATA_USAGE_FILE)

        return status_data
    except Exception as e:
        log_structured("ERROR", f"Status check failed: {e}")
        return {"error": str(e)}

@router.get("/system-health")
def get_system_health(user: str = Depends(get_current_user)):
    try:
        uptime_seconds = time.time() - psutil.boot_time()
        cpu_usage = psutil.cpu_percent(interval=0.1)
        ram = psutil.virtual_memory()
        disk = psutil.disk_usage('/')
        
        project_size_bytes = 0
        try:
            for d in ['/app/sources', '/app/config', '/app/data']:
                if os.path.exists(d):
                    res = subprocess.run(['du', '-sk', d], capture_output=True, text=True, timeout=5)
                    if res.returncode == 0:
                        project_size_bytes += int(res.stdout.split()[0]) * 1024
            
            # Docker images size logic omitted for brevity/performance in sync call? 
            # Replicating original logic:
            img_res = subprocess.run(['docker', 'images', '--format', '{{.Size}}\t{{.Repository}}'], capture_output=True, text=True, timeout=5)
            if img_res.returncode == 0:
                for line in img_res.stdout.strip().split('\n'):
                    if not line: continue
                    parts = line.split('\t')
                    if len(parts) < 2: continue
                    size_str, repo = parts[0], parts[1]
                    if repo.startswith('selfhost/') or any(x in repo for x in ['immich', 'gluetun', 'postgres', 'redis', 'adguard', 'unbound', 'portainer']):
                        mult = 1
                        if 'GB' in size_str.upper(): mult = 1024*1024*1024
                        elif 'MB' in size_str.upper(): mult = 1024*1024
                        elif 'KB' in size_str.upper(): mult = 1024
                        try:
                            sz_val = float(re.sub(r'[^0-9.]', '', size_str))
                            project_size_bytes += int(sz_val * mult)
                        except:
                            pass
        except:
            pass

        drive_health_pct = 100 - disk.percent
        drive_status = "Healthy"
        smart_alerts = []
        if disk.percent > 90:
            drive_status = "Warning (High Usage)"
            smart_alerts.append("Disk space is critical (>90%)")

        return {
            "uptime": uptime_seconds,
            "cpu_percent": cpu_usage,
            "ram_used": ram.used / (1024 * 1024),
            "ram_total": ram.total / (1024 * 1024),
            "disk_used": disk.used / (1024 * 1024 * 1024),
            "disk_total": disk.total / (1024 * 1024 * 1024),
            "disk_percent": disk.percent,
            "project_size": project_size_bytes / (1024 * 1024),
            "drive_status": drive_status,
            "drive_health_pct": drive_health_pct,
            "smart_alerts": smart_alerts
        }
    except Exception as e:
        return {"error": str(e)}

@router.get("/metrics")
def get_metrics(user: str = Depends(get_current_user)):
    try:
        conn = sqlite3.connect(settings.DB_FILE)
        c = conn.cursor()
        c.execute('''SELECT container, cpu_percent, mem_usage, mem_limit 
                     FROM metrics WHERE id IN (SELECT MAX(id) FROM metrics GROUP BY container)''')
        rows = c.fetchall()
        conn.close()
        metrics = {r[0]: {"cpu": r[1], "mem": r[2], "limit": r[3]} for r in rows}
        return {"metrics": metrics}
    except Exception as e:
        return {"error": str(e)}

@router.get("/containers")
def get_containers(user: str = Depends(get_current_user)):
    try:
        result = run_command(
            ['docker', 'ps', '-a', '--no-trunc', '--format', '{{.Names}}\t{{.ID}}\t{{.Labels}}'],
            timeout=10
        )
        containers = {}
        for line in result.stdout.strip().split('\n'):
            parts = line.split('\t')
            if len(parts) >= 2:
                name, cid = parts[0], parts[1]
                if settings.CONTAINER_PREFIX and name.startswith(settings.CONTAINER_PREFIX):
                    name = name[len(settings.CONTAINER_PREFIX):]
                labels = parts[2] if len(parts) > 2 else ""
                is_hardened = "io.privacyhub.hardened=true" in labels
                containers[name] = {"id": cid, "hardened": is_hardened}
        return {"containers": containers}
    except Exception as e:
        return {"error": str(e)}

@router.post("/purge-images")
def purge_images(user: str = Depends(get_admin_user)):
    try:
        res = run_command(['docker', 'image', 'prune', '-f'], timeout=60)
        reclaimed_msg = "Unused images and build cache cleared."
        if "Total reclaimed space:" in res.stdout:
            reclaimed = res.stdout.split("Total reclaimed space:")[1].strip().split('\n')[0]
            reclaimed_msg = f"Successfully reclaimed {reclaimed} of storage space."
        
        run_command(['docker', 'builder', 'prune', '-f'], timeout=60)
        return {"success": True, "message": reclaimed_msg}
    except Exception as e:
        return {"error": str(e)}

@router.post("/restart-stack")
def restart_stack(background_tasks: BackgroundTasks, user: str = Depends(get_admin_user)):
    def _restart():
        time.sleep(2)
        subprocess.run(["docker", "compose", "-f", "/app/docker-compose.yml", "restart"])
    
    background_tasks.add_task(_restart)
    log_structured("SYSTEM", "Full stack restart triggered via Dashboard", "ORCHESTRATION")
    return {"success": True, "message": "Stack restart initiated"}

@router.post("/uninstall")
def uninstall(background_tasks: BackgroundTasks, user: str = Depends(get_admin_user)):
    def _uninstall():
        log_structured("INFO", "Uninstall sequence started", "MAINTENANCE")
        time.sleep(5)
        subprocess.run(["bash", "/app/zima.sh", "-x"], cwd="/app")
    
    background_tasks.add_task(_uninstall)
    return {"success": True, "message": "Uninstall sequence started"}
