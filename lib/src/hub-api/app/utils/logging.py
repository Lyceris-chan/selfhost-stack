"""Logging utilities for the Privacy Hub API.

This module handles structured logging to both a flat file and a SQLite database,
including human-friendly message mapping and noise filtering.
"""

import json
import logging
import os
import sqlite3
import time

from ..core.config import settings

# Configure standard logging
logging.basicConfig(level=logging.INFO, format="%(message)s")
logger = logging.getLogger("api")

# Human-friendly messages for common API requests to improve log readability.
HUMAN_LOGS = {
    "GET /system-health": "System health telemetry synchronized",
    "GET /project-details": "Storage utilization breakdown fetched",
    "POST /purge-images": "Unused Docker assets purged",
    "POST /update-service": "Service update sequence initiated",
    "POST /theme": "UI theme preferences updated",
    "GET /theme": "UI theme configuration synchronized",
    "GET /profiles": "VPN profile list retrieved",
    "POST /activate": "VPN profile activation triggered",
    "POST /upload": "VPN configuration profile uploaded",
    "POST /delete": "VPN configuration profile deleted",
    "POST /restart-stack": "Full system stack restart triggered",
    "POST /batch-update": "Batch service update sequence started",
    "POST /rotate-api-key": "Dashboard API security key rotated",
    "GET /check-updates": "Update availability check requested",
    "GET /changelog": "Service changelog retrieved",
    "GET /services": "Service catalog synchronized",
    "GET /wg/clients": "VPN client catalog synchronized",
    "POST /wg/clients": "New VPN client access authorized",
    "DELETE /wg/clients": "VPN client access revoked",
    "configuration": "VPN client configuration retrieved",
    "POST /toggle-session-cleanup": "Session security policy updated",
    "POST /verify-admin": "Administrative session authorized",
    "POST /uninstall": "System uninstallation sequence started",
    "GET /odido-api/api/status": "Odido Booster status synchronized",
    "POST /odido-api/api/config": "Odido Booster configuration updated",
    "POST /odido-api/api/odido/buy-bundle": "Odido data bundle purchase triggered",
    "GET /odido-api/api/odido/remaining": "Odido live data balance queried",
    "POST /odido-userid": "Odido User ID extraction initiated",
    "GET /metrics": "Performance metrics updated",
    "GET /containers": "Container orchestration state audited",
    "POST /migrate": "Service database migration triggered",
    "POST /vacuum": "Service database optimization (vacuum) started",
    "POST /clear-logs": "Service log cleanup initiated",
    "POST /clear-db": "Service database reset requested",
    "POST /master-update": "Full system update sequence authorized",
}

# Patterns to filter out frequent or uninformative logs.
NOISY_PATTERNS = [
    "GET /status",
    "GET /metrics",
    "GET /containers",
    "GET /services",
    "GET /wg/clients",
    "GET /updates",
    "GET /certificate-status",
    'HTTP/1.1" 200',
    'HTTP/1.1" 304',
]


def log_structured(
    level: str, message: str, category: str = "SYSTEM", source: str = "api"
):
    """Logs a structured message to the history file and SQLite database.

    Args:
        level: The severity level (e.g., INFO, WARN, ERROR).
        message: The message to log.
        category: The functional category of the log entry.
        source: The component generating the log.
    """
    # Humanize message if it matches a known pattern
    for pattern, replacement in HUMAN_LOGS.items():
        if pattern in message:
            message = replacement
            break

    # Filter noisy logs
    if any(pattern in message for pattern in NOISY_PATTERNS):
        return

    entry = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "level": level,
        "category": category,
        "source": source,
        "message": message,
    }

    # Log to flat file
    try:
        with open(settings.LOG_FILE, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry) + "\n")
    except Exception as err:
        logger.error("Log file write failed: %s", err)

    # Log to SQLite database
    try:
        conn = sqlite3.connect(settings.DB_FILE)
        with conn:
            conn.execute(
                "INSERT INTO logs (level, category, message) VALUES (?, ?, ?)",
                (level, category, message),
            )
    except Exception as err:
        logger.error("Database log insertion failed: %s", err)

    # Output to console
    if level in ["ERROR", "CRIT", "SECURITY"]:
        logger.error("[%s] %s", level, message)
    else:
        logger.info("[%s] %s", level, message)


def init_db():
    """Initializes the SQLite database and ensures the schema is correct."""
    db_dir = os.path.dirname(settings.DB_FILE)
    try:
        if not os.path.exists(db_dir):
            os.makedirs(db_dir, exist_ok=True)

        # Verify write access
        test_file = os.path.join(db_dir, ".write_test")
        with open(test_file, "w", encoding="utf-8") as f:
            f.write("test")
        os.remove(test_file)

        conn = sqlite3.connect(settings.DB_FILE)
        with conn:
            conn.execute("""CREATE TABLE IF NOT EXISTS logs
                             (id INTEGER PRIMARY KEY AUTOINCREMENT,
                              timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                              level TEXT, category TEXT, message TEXT)""")
            conn.execute("""CREATE TABLE IF NOT EXISTS metrics
                             (id INTEGER PRIMARY KEY AUTOINCREMENT,
                              timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                              container TEXT, cpu_percent REAL, mem_usage REAL, mem_limit REAL)""")
    except Exception as err:
        logger.error("FATAL: Database initialization failed: %s", err)
        # Recovery fallback to /tmp if persistent storage is unavailable
        if "unable to open database file" in str(err).lower():
            logger.warning("RECOVERY: Falling back to volatile /tmp for database.")
            settings.DB_FILE = "/tmp/logs.db"
            init_db()
        else:
            raise err
