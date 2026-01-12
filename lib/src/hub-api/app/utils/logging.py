import logging
import json
import time
import sqlite3
import threading
import os
from ..core.config import settings

# Configure standard logging
logging.basicConfig(level=logging.INFO, format='%(message)s')
logger = logging.getLogger("api")

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
    "POST /master-update": "Full system update sequence authorized"
}

NOISY_PATTERNS = [
    'GET /status', 'GET /metrics', 'GET /containers', 'GET /services', 
    'GET /wg/clients', 'GET /updates', 'GET /certificate-status',
    'HTTP/1.1" 200', 'HTTP/1.1" 304'
]

def log_structured(level: str, message: str, category: str = "SYSTEM", source: str = "api"):
    """Log to both file and SQLite."""
    
    # Humanize
    for k, v in HUMAN_LOGS.items():
        if k in message:
            message = v
            break

    # Filter noisy
    if any(x in message for x in NOISY_PATTERNS):
        return

    entry = {
        "timestamp": time.strftime('%Y-%m-%d %H:%M:%S'),
        "level": level,
        "category": category,
        "source": source,
        "message": message
    }
    
    # Log to file
    try:
        with open(settings.LOG_FILE, 'a') as f:
            f.write(json.dumps(entry) + "\n")
    except Exception as e:
        logger.error(f"Log File Error: {e}")
    
    # Log to DB
    try:
        conn = sqlite3.connect(settings.DB_FILE)
        c = conn.cursor()
        c.execute("INSERT INTO logs (level, category, message) VALUES (?, ?, ?)",
                  (level, category, message))
        conn.commit()
        conn.close()
    except Exception as e:
        logger.error(f"DB Log Error: {e}")
    
    if level in ["ERROR", "CRIT", "SECURITY"]:
        logger.error(f"[{level}] {message}")
    elif level == "INFO":
        logger.info(f"[{level}] {message}")

def init_db():
    """Initialize the SQLite database."""
    db_dir = os.path.dirname(settings.DB_FILE)
    try:
        if not os.path.exists(db_dir):
            os.makedirs(db_dir, exist_ok=True)
        
        # Test writable
        test_file = os.path.join(db_dir, ".write_test")
        with open(test_file, "w") as f:
            f.write("test")
        os.remove(test_file)
        
        conn = sqlite3.connect(settings.DB_FILE)
        c = conn.cursor()
        c.execute('''CREATE TABLE IF NOT EXISTS logs
                     (id INTEGER PRIMARY KEY AUTOINCREMENT, 
                      timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                      level TEXT, category TEXT, message TEXT)''')
        c.execute('''CREATE TABLE IF NOT EXISTS metrics
                     (id INTEGER PRIMARY KEY AUTOINCREMENT,
                      timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                      container TEXT, cpu_percent REAL, mem_usage REAL, mem_limit REAL)''')
        conn.commit()
        conn.close()
    except Exception as e:
        logger.error(f"FATAL: Database Initialization Failed: {e}")
        # Fallback
        if "/app/data" in str(e) or "unable to open database file" in str(e):
            logger.warning("RECOVERY: Attempting fallback to volatile /tmp for database.")
            settings.DB_FILE = "/tmp/logs.db"
            try:
                conn = sqlite3.connect(settings.DB_FILE)
                c = conn.cursor()
                c.execute('''CREATE TABLE IF NOT EXISTS logs
                             (id INTEGER PRIMARY KEY AUTOINCREMENT, 
                              timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                              level TEXT, category TEXT, message TEXT)''')
                c.execute('''CREATE TABLE IF NOT EXISTS metrics
                             (id INTEGER PRIMARY KEY AUTOINCREMENT,
                              timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                              container TEXT, cpu_percent REAL, mem_usage REAL, mem_limit REAL)''')
                conn.commit()
                conn.close()
            except:
                pass
        else:
            raise e
