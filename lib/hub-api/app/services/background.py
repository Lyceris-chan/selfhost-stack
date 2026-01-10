import time
import subprocess
import threading
import sqlite3
import os
import json
from ..core.config import settings
from ..utils.logging import log_structured

last_metrics_request = 0

def metrics_collector_thread():
    """Background thread to collect container metrics."""
    global last_metrics_request
    while True:
        try:
            # Only collect if someone requested metrics recently (e.g. last 60s)
            # We can expose a function to update 'last_metrics_request'
            if time.time() - last_metrics_request < 60:
                res = subprocess.run(
                    ['docker', 'stats', '--no-stream', '--format', '{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}'],
                    capture_output=True, text=True, timeout=30
                )
                if res.returncode == 0:
                    conn = sqlite3.connect(settings.DB_FILE)
                    c = conn.cursor()
                    for line in res.stdout.strip().split('\n'):
                        if not line: continue
                        parts = line.split('\t')
                        if len(parts) == 3:
                            name, cpu_str, mem_combined = parts
                            if settings.CONTAINER_PREFIX and name.startswith(settings.CONTAINER_PREFIX):
                                name = name[len(settings.CONTAINER_PREFIX):]
                            try:
                                cpu = float(cpu_str.replace('%', ''))
                            except: cpu = 0.0
                            
                            def to_mb(val):
                                val = val.upper()
                                if 'GIB' in val: return float(val.replace('GIB', '')) * 1024
                                if 'MIB' in val: return float(val.replace('MIB', ''))
                                if 'KIB' in val: return float(val.replace('KIB', '')) / 1024
                                if 'B' in val: return float(val.replace('B', '')) / 1024 / 1024
                                return 0.0

                            mem_parts = mem_combined.split(' / ')
                            mem_usage = to_mb(mem_parts[0])
                            mem_limit = to_mb(mem_parts[1]) if len(mem_parts) > 1 else 0.0
                            
                            c.execute("INSERT INTO metrics (container, cpu_percent, mem_usage, mem_limit) VALUES (?, ?, ?, ?)",
                                      (name, cpu, mem_usage, mem_limit))
                    
                    c.execute("DELETE FROM metrics WHERE timestamp < datetime('now', '-1 hour')")
                    conn.commit()
                    conn.close()
            time.sleep(30)
        except Exception as e:
            print(f"Metrics Error: {e}")
            time.sleep(30)

def log_sync_thread():
    """Sync logs from deployment.log into SQLite."""
    if not os.path.exists(settings.LOG_FILE):
        time.sleep(5)
        if not os.path.exists(settings.LOG_FILE): return

    try:
        f = open(settings.LOG_FILE, 'r')
        f.seek(0, 2)
        
        while True:
            line = f.readline()
            if not line:
                time.sleep(1)
                continue
            
            try:
                data = json.loads(line)
                if data.get("source") == "orchestrator":
                    level = data.get("level", "INFO")
                    category = data.get("category", "SYSTEM")
                    message = data.get("message", "")
                    
                    conn = sqlite3.connect(settings.DB_FILE)
                    c = conn.cursor()
                    c.execute("INSERT INTO logs (level, category, message) VALUES (?, ?, ?)",
                              (level, category, message))
                    conn.commit()
                    conn.close()
            except:
                continue
    except Exception as e:
        print(f"Log Sync Error: {e}")

def update_metrics_activity():
    global last_metrics_request
    last_metrics_request = time.time()
