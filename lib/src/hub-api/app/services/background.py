"""Background worker services for the Privacy Hub API.

This module contains worker threads for collecting system metrics,
retrieving external provider configuration, and synchronizing logs.
"""

"""Background worker services for the Privacy Hub API.

This module contains worker threads for collecting system metrics,
retrieving external provider configuration, and synchronizing logs.
"""

import os
import re
import sqlite3
import subprocess
import time

import requests

from ..core.config import settings
from ..utils.logging import log_structured

last_metrics_request = 0


def refresh_secrets(updates):
    """Synchronizes in-memory secret updates back to the .secrets file.

    Args:
        updates: Dictionary of key-value pairs to update or add.
    """
    if not os.path.exists(settings.SECRETS_FILE):
        return

    try:
        with open(settings.SECRETS_FILE, "r", encoding="utf-8") as f:
            lines = f.readlines()

        new_lines = []
        for line in lines:
            updated = False
            for key, val in updates.items():
                if line.startswith(f"{key}="):
                    new_lines.append(f'{key}="{val}"\n')
                    updated = True
                    break
            if not updated:
                new_lines.append(line)

        # Add new keys if not present
        existing_keys = [line.split("=")[0] for line in new_lines]
        for key, val in updates.items():
            if key not in existing_keys:
                new_lines.append(f'{key}="{val}"\n')

        with open(settings.SECRETS_FILE, "w", encoding="utf-8") as f:
            f.writelines(new_lines)
    except Exception as err:
        log_structured("ERROR", f"Failed to update secrets: {err}", "SYSTEM")


def odido_retrieval_thread():
    """Background task to automatically extract Odido User ID from OAuth tokens.

    Periodically checks for missing Odido configuration and attempts to resolve
    the User ID by following API redirects.
    """
    while True:
        try:
            if not os.path.exists(settings.SECRETS_FILE):
                time.sleep(60)
                continue

            with open(settings.SECRETS_FILE, "r", encoding="utf-8") as f:
                content = f.read()

            # Check if we have token but missing or default user_id
            token_match = re.search(r'ODIDO_TOKEN="([^"]+)"', content)
            userid_match = re.search(r'ODIDO_USER_ID="([^"]*)"', content)

            if token_match and (not userid_match or not userid_match.group(1)):
                token = token_match.group(1)
                log_structured(
                    "INFO",
                    "Odido User ID missing. Attempting background retrieval...",
                    "SYSTEM",
                )

                headers = {
                    "Authorization": f"Bearer {token}",
                    "User-Agent": "T-Mobile 5.3.28 (Android 10; 10)",
                }
                # Follow redirects manually or via requests
                resp = requests.get(
                    "https://capi.odido.nl/account/current",
                    headers=headers,
                    allow_redirects=True,
                    timeout=10,
                )
                final_url = resp.url

                # Extract 12-char hex User ID
                # Format: https://capi.odido.nl/{userid}/account/current
                id_match = re.search(
                    r"capi\.odido\.nl/([0-9a-f]{12})", final_url, re.IGNORECASE
                )
                if id_match:
                    new_id = id_match.group(1)
                    log_structured(
                        "SUCCESS",
                        f"Successfully retrieved Odido User ID: {new_id}",
                        "SYSTEM",
                    )
                    refresh_secrets({"ODIDO_USER_ID": new_id})
                else:
                    log_structured(
                        "WARN",
                        "Background Odido retrieval failed: User ID not found in redirect URL",
                        "SYSTEM",
                    )

            # Check once an hour if still missing
            time.sleep(3600)
        except Exception as err:
            log_structured("ERROR", f"Odido Retrieval Error: {err}", "SYSTEM")
            time.sleep(300)


def metrics_collector_thread():
    """Background task to collect real-time Docker resource utilization.

    Only executes if active monitoring is requested by the UI to conserve CPU.
    Persists samples to the SQLite database for historical graphing.
    """
    global last_metrics_request
    while True:
        try:
            # Only collect if someone requested metrics recently (e.g. last 60s)
            if time.time() - last_metrics_request < 60:
                res = subprocess.run(
                    [
                        "docker",
                        "stats",
                        "--no-stream",
                        "--format",
                        "{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}",
                    ],
                    capture_output=True,
                    text=True,
                    timeout=30,
                    check=False,
                )
                if res.returncode == 0:
                    conn = sqlite3.connect(settings.DB_FILE)
                    cursor = conn.cursor()
                    for line in res.stdout.strip().split("\n"):
                        if not line:
                            continue
                        parts = line.split("\t")
                        if len(parts) == 3:
                            container_name, cpu_str, mem_combined = parts
                            if settings.CONTAINER_PREFIX and container_name.startswith(
                                settings.CONTAINER_PREFIX
                            ):
                                container_name = container_name[
                                    len(settings.CONTAINER_PREFIX) :
                                ]
                            try:
                                cpu_val = float(cpu_str.replace("%", ""))
                            except Exception:
                                cpu_val = 0.0

                            def to_mb(val):
                                val = val.upper()
                                if "GIB" in val:
                                    return float(val.replace("GIB", "")) * 1024
                                if "MIB" in val:
                                    return float(val.replace("MIB", ""))
                                if "KIB" in val:
                                    return float(val.replace("KIB", "")) / 1024
                                if "B" in val:
                                    return float(val.replace("B", "")) / 1024 / 1024
                                return 0.0

                            mem_parts = mem_combined.split(" / ")
                            mem_usage = to_mb(mem_parts[0])
                            mem_limit = (
                                to_mb(mem_parts[1]) if len(mem_parts) > 1 else 0.0
                            )

                            cursor.execute(
                                "INSERT INTO metrics (container, cpu_percent, mem_usage, mem_limit) VALUES (?, ?, ?, ?)",
                                (container_name, cpu_val, mem_usage, mem_limit),
                            )

                    cursor.execute(
                        "DELETE FROM metrics WHERE timestamp < datetime('now', '-1 hour')"
                    )
                    conn.commit()
                    conn.close()
            time.sleep(30)
        except Exception as err:
            log_structured("ERROR", f"Metrics Error: {err}", "SYSTEM")
            time.sleep(30)


def update_metrics_activity():
    """Signals the collector thread that metrics are being actively viewed."""
    global last_metrics_request
    last_metrics_request = time.time()


def log_sync_thread():
    """Background task to synchronize file-based logs to the database.

    Ensures high-performance searching and filtering of deployment history.
    """
    while True:
        try:
            if os.path.exists(settings.LOG_FILE):
                # Implementation for production log tailing would go here.
                pass
            time.sleep(10)
        except Exception as err:
            log_structured("ERROR", f"Log Sync Error: {err}", "SYSTEM")
            time.sleep(60)
