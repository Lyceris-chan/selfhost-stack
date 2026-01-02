#!/usr/bin/env python3
import http.server
import socketserver
import json
import os
import re
import subprocess
import time
import sqlite3
import threading
import urllib.request
import urllib.parse
import psutil
import socket
import secrets
import uuid

# Global session tracking for authorized browser sessions (cookie-free)
# Dictionary: {token: expiry_timestamp}
valid_sessions = {}
session_cleanup_enabled = True
CONTAINER_PREFIX = "__CONTAINER_PREFIX__"

def cleanup_sessions_thread():
    """Background thread to purge expired auth sessions."""
    global valid_sessions
    while True:
        if session_cleanup_enabled:
            now = time.time()
            expired = [t for t, expiry in valid_sessions.items() if now > expiry]
            for t in expired:
                del valid_sessions[t]
        time.sleep(60)

# Start cleanup thread
threading.Thread(target=cleanup_sessions_thread, daemon=True).start()

PORT = 55555
CONFIG_DIR = "/app"
PROFILES_DIR = "/profiles"
CONTROL_SCRIPT = "/usr/local/bin/wg-control.sh"
LOG_FILE = "/app/deployment.log"
DB_FILE = "/app/data/logs.db"
ASSETS_DIR = "/assets"
SERVICES_FILE = os.path.join(CONFIG_DIR, "services.json")
DATA_USAGE_FILE = "/app/.data_usage"
WGE_DATA_USAGE_FILE = "/app/.wge_data_usage"

def get_total_usage(path):
    try:
        if os.path.exists(path):
            with open(path, 'r') as f:
                data = json.load(f)
                return int(data.get('rx', 0)), int(data.get('tx', 0))
    except: pass
    return 0, 0

def save_total_usage(path, rx, tx):
    try:
        with open(path, 'w') as f:
            json.dump({'rx': int(rx), 'tx': int(tx)}, f)
    except: pass

FONT_SOURCES = {
    "gs.css": [
        "https://fontlay.com/css2?family=Google+Sans+Flex:wght@400;500;600;700&display=swap",
    ],
    "cc.css": [
        "https://fontlay.com/css2?family=Cascadia+Code:ital,wght@0,200..700;1,200..700&display=swap",
    ],
    "ms.css": [
        "https://fontlay.com/css2?family=Material+Symbols+Rounded:opsz,wght,FILL,GRAD@20..48,100..700,0..1,-50..200&display=swap",
    ],
    "qrcode.js": [
        "https://cdn.jsdelivr.net/npm/qrcode@1.5.4/build/qrcode.min.js",
    ],
}
FONT_ORIGINS = [
    "https://fontlay.com",
    "https://cdn.jsdelivr.net",
]

def extract_profile_name(config):
    """Extract profile name from WireGuard config."""
    lines = config.split('\n')
    in_peer = False
    for line in lines:
        stripped = line.strip()
        if stripped.lower() == '[peer]':
            in_peer = True
            continue
        if in_peer and stripped.startswith('#'):
            name = stripped.lstrip('#').strip()
            if name:
                return name
        if in_peer and stripped.startswith('['):
            break
    for line in lines:
        stripped = line.strip()
        if stripped.startswith('#'):
            name = stripped.lstrip('#').strip()
            if name and '=' not in name:
                return name
    return None

def init_db():
    """Initialize the SQLite database for logs and metrics."""
    os.makedirs(os.path.dirname(DB_FILE), exist_ok=True)
    conn = sqlite3.connect(DB_FILE)
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

last_metrics_request = 0

def metrics_collector():
    """Background thread to collect container metrics. Pauses if no requests received."""
    global last_metrics_request
    while True:
        try:
            # Only collect if someone requested metrics recently (e.g. last 60s)
            if time.time() - last_metrics_request < 60:
                res = subprocess.run(
                    ['docker', 'stats', '--no-stream', '--format', '{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}'],
                    capture_output=True, text=True, timeout=30
                )
                if res.returncode == 0:
                    conn = sqlite3.connect(DB_FILE)
                    c = conn.cursor()
                    for line in res.stdout.strip().split('\n'):
                        if not line: continue
                        parts = line.split('\t')
                        if len(parts) == 3:
                            name, cpu_str, mem_combined = parts
                            if CONTAINER_PREFIX and name.startswith(CONTAINER_PREFIX):
                                name = name[len(CONTAINER_PREFIX):]
                            cpu = float(cpu_str.replace('%', ''))
                            
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
        except Exception as e:
            print(f"Metrics Error: {e}")
        time.sleep(30)

def log_structured(level, message, category="SYSTEM"):
    """Log to both file and SQLite."""
    # Humanize common logs
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
        "GET /services": "Service catalog synchronized"
    }
    
    for k, v in HUMAN_LOGS.items():
        if k in message:
            message = v
            break

    # Filter noisy logs
    if any(x in message for x in ['GET /status', 'GET /metrics', 'GET /containers', 'GET /updates', 'GET /certificate-status']):
        return
        
    entry = {
        "timestamp": time.strftime('%Y-%m-%d %H:%M:%S'),
        "level": level,
        "category": category,
        "message": message
    }
    # Log to file
    try:
        with open(LOG_FILE, 'a') as f:
            f.write(json.dumps(entry) + "\n")
    except: pass
    
    # Log to DB
    try:
        conn = sqlite3.connect(DB_FILE)
        c = conn.cursor()
        c.execute("INSERT INTO logs (level, category, message) VALUES (?, ?, ?)",
                  (level, category, message))
        conn.commit()
        conn.close()
    except Exception as e:
        print(f"DB Log Error: {e}")
    
    print(f"[{level}] {message}")

def log_fonts(message, level="SYSTEM"):
    try:
        log_structured(level, message, "FONTS")
    except Exception:
        print(f"[{level}] {message}")

def load_services():
    try:
        if os.path.exists(SERVICES_FILE):
            with open(SERVICES_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
            if isinstance(data, dict) and "services" in data:
                data = data["services"]
            if isinstance(data, dict):
                return data
    except Exception as e:
        print(f"[WARN] Service catalog load failed: {e}")
    return {}

def get_proxy_opener():
    # Gluetun proxy is usually available at gluetun:8888 within the same docker network
    # We use the literal name 'gluetun' because hub-api and gluetun are in the same docker compose project
    proxy_url = f"http://{CONTAINER_PREFIX}gluetun:8888"
    proxy_handler = urllib.request.ProxyHandler({'http': proxy_url, 'https': proxy_url})
    opener = urllib.request.build_opener(proxy_handler)
    return opener

def download_content(url, as_text=False):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"})
    try:
        opener = get_proxy_opener()
        with opener.open(req, timeout=30) as resp:
            data = resp.read()
    except Exception as e:
        log_fonts(f"Proxy download failed for {url}: {e}. Retrying direct...", "WARN")
        # Fallback to direct if proxy fails
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = resp.read()
            
    return data.decode("utf-8", errors="replace") if as_text else data

def download_text(url):
    return download_content(url, as_text=True)

def download_binary(url):
    return download_content(url, as_text=False)

def ensure_assets():
    if os.path.exists(ASSETS_DIR) and not os.path.isdir(ASSETS_DIR):
        log_fonts(f"Asset path is not a directory: {ASSETS_DIR}", "WARN")
        return
    os.makedirs(ASSETS_DIR, exist_ok=True)

    for css_name, sources in FONT_SOURCES.items():
        css_path = os.path.join(ASSETS_DIR, css_name)
        css_text = ""

        if not os.path.exists(css_path) or os.path.getsize(css_path) == 0:
            css_text = None
            for url in sources:
                try:
                    css_text = download_text(url)
                    with open(css_path, "w", encoding="utf-8") as f:
                        f.write(css_text)
                    log_fonts(f"Downloaded {css_name} from {url}")
                    break
                except Exception as e:
                    log_fonts(f"Failed to download {css_name} from {url}: {e}", "WARN")
            if not css_text:
                continue

        if not css_text:
            try:
                with open(css_path, "r", encoding="utf-8") as f:
                    css_text = f.read()
            except Exception as e:
                log_fonts(f"Failed to read {css_name}: {e}", "WARN")
                continue

        if "url(" not in css_text:
            continue

        urls_in_css = re.findall(r"url\(([^)]+)\)", css_text)
        if not urls_in_css:
            continue

        updated = False
        for raw in urls_in_css:
            cleaned = raw.strip().strip("\"'")
            if not cleaned or cleaned.startswith("data:"):
                continue

            filename = os.path.basename(cleaned.split("?")[0])
            if not filename:
                continue

            local_path = os.path.join(ASSETS_DIR, filename)
            if not os.path.exists(local_path):
                candidates = []
                if cleaned.startswith("//"):
                    candidates = [f"https:{cleaned}"]
                elif cleaned.startswith("http"):
                    candidates = [cleaned]
                else:
                    for origin in FONT_ORIGINS:
                        candidates.append(urllib.parse.urljoin(origin + "/", cleaned.lstrip("/")))

                last_err = None
                for candidate in candidates:
                    try:
                        data = download_binary(candidate)
                        with open(local_path, "wb") as f:
                            f.write(data)
                        log_fonts(f"Downloaded asset {filename} from {candidate}")
                        last_err = None
                        break
                    except Exception as e:
                        last_err = e

                if last_err is not None and not os.path.exists(local_path):
                    log_fonts(f"Failed to download asset {filename}: {last_err}", "WARN")
                    continue

            if raw != filename:
                css_text = css_text.replace(raw, filename)
                updated = True

        if updated:
            try:
                with open(css_path, "w", encoding="utf-8") as f:
                    f.write(css_text)
            except Exception as e:
                log_fonts(f"Failed to update {css_name}: {e}", "WARN")

    # Ensure MCU library
    mcu_path = os.path.join(ASSETS_DIR, "mcu.js")
    if not os.path.exists(mcu_path):
        try:
            # Use verified ESM bundle
            url = "https://cdn.jsdelivr.net/npm/@material/material-color-utilities@0.2.7/+esm"
            data = download_binary(url)
            with open(mcu_path, "wb") as f:
                f.write(data)
            log_fonts(f"Downloaded mcu.js from {url}")
        except Exception as e:
            log_fonts(f"Failed to download mcu.js: {e}", "WARN")

    # Ensure local SVG icon
    svg_path = os.path.join(ASSETS_DIR, "__APP_NAME__.svg")
    if not os.path.exists(svg_path):
        try:
            svg = """<svg xmlns="http://www.w3.org/2000/svg" height="128" viewBox="0 -960 960 960" width="128" fill="#D0BCFF">
    <path d="M480-80q-139-35-229.5-159.5S160-516 160-666v-134l320-120 320 120v134q0 151-90.5 275.5T480-80Zm0-84q104-33 172-132t68-210v-105l-240-90-240 90v105q0 111 68 210t172 132Zm0-316Z"/>
</svg>"""
            with open(svg_path, "w", encoding="utf-8") as f:
                f.write(svg)
            log_fonts("Generated __APP_NAME__.svg")
        except Exception as e:
            log_fonts(f"Failed to generate __APP_NAME__.svg: {e}", "WARN")

class ThreadingHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True

def get_update_strategy():
    strategy = os.environ.get('UPDATE_STRATEGY', 'stable')
    theme_file = os.path.join(CONFIG_DIR, "theme.json")
    if os.path.exists(theme_file):
        try:
            with open(theme_file, 'r') as f:
                t = json.load(f)
                if 'update_strategy' in t:
                    return t['update_strategy']
        except: pass
    return strategy

class APIHandler(http.server.BaseHTTPRequestHandler):
    def _proxy_wgeasy(self, method, path, body=None):
        try:
            password = os.environ.get('VPN_PASS_RAW', '')
            if not password:
                # Fallback to ADMIN_PASS_RAW if VPN pass not set (e.g. initial setup)
                password = os.environ.get('ADMIN_PASS_RAW', '')
            
            # Auth flow: 1. Get Session, 2. Execute Request
            # Note: newer wg-easy versions might use a simple password auth or cookie
            # We'll try to get a session cookie first
            
            opener = urllib.request.build_opener()
            login_url = f"http://{CONTAINER_PREFIX}wg-easy:51821/api/session"
            login_data = json.dumps({"password": password}).encode('utf-8')
            req = urllib.request.Request(login_url, data=login_data, headers={'Content-Type': 'application/json'})
            
            cookie = ""
            try:
                with opener.open(req, timeout=5) as resp:
                    headers = resp.info()
                    # Extract Set-Cookie
                    if 'Set-Cookie' in headers:
                        cookie = headers['Set-Cookie'].split(';')[0]
            except Exception as e:
                return {"error": f"WG-Easy Login Failed: {str(e)}"}, 500

            # Execute actual request
            target_url = f"http://{CONTAINER_PREFIX}wg-easy:51821/api/wireguard/client"
            if path: target_url += path
            
            req = urllib.request.Request(target_url, method=method)
            if cookie:
                req.add_header('Cookie', cookie)
            if body:
                req.add_header('Content-Type', 'application/json')
                req.data = json.dumps(body).encode('utf-8')
            
            with opener.open(req, timeout=10) as resp:
                if resp.status == 204: return {}, 204
                return json.loads(resp.read().decode()), resp.status
        except urllib.error.HTTPError as e:
            return {"error": str(e)}, e.code
        except Exception as e:
            return {"error": str(e)}, 500

    def log_message(self, format, *args):
        # Filter out common health check and static asset logs to reduce noise
        msg = format % args

        # Humanize common logs
        if "GET /system-health" in msg:
            log_structured("INFO", "UI health telemetry synchronized", "NETWORK")
        elif "GET /project-details" in msg:
            log_structured("INFO", "Storage utilization breakdown fetched", "NETWORK")
        elif "POST /purge-images" in msg:
            log_structured("INFO", "Unused Docker assets purged", "NETWORK")
        elif "POST /update-service" in msg:
            log_structured("INFO", "Service update sequence initiated", "NETWORK")
            return
        elif "POST /verify-admin" in msg:
            log_structured("SECURITY", "Administrative session authorized", "AUTH")
            return
        elif "POST /toggle-session-cleanup" in msg:
            log_structured("SECURITY", "Session security policy updated", "AUTH")
            return
        elif "POST /theme" in msg:
            log_structured("INFO", "UI theme preferences updated", "NETWORK")
            return
        elif "GET /theme" in msg:
            log_structured("INFO", "UI theme configuration synchronized", "NETWORK")
            return
        elif "POST /restart-stack" in msg:
            log_structured("INFO", "Full system stack restart triggered", "ORCHESTRATION")
            return
        elif "POST /rotate-api-key" in msg:
            log_structured("SECURITY", "Dashboard API security key rotated", "AUTH")
            return
        elif "POST /batch-update" in msg:
            log_structured("INFO", "Batch service update sequence started", "MAINTENANCE")
            return
        elif "POST /activate" in msg:
            log_structured("INFO", "VPN profile switch triggered", "NETWORK")
            return
        elif "POST /upload" in msg:
            log_structured("INFO", "VPN configuration profile uploaded", "NETWORK")
            return
        elif "POST /delete" in msg:
            log_structured("INFO", "VPN configuration profile deleted", "NETWORK")
            return
        elif "GET /check-updates" in msg:
            log_structured("INFO", "Update availability check requested", "MAINTENANCE")
            return
        elif "GET /changelog" in msg:
            log_structured("INFO", "Service changelog retrieved", "MAINTENANCE")
            return
        elif "GET /services" in msg:
            log_structured("INFO", "Service catalog synchronized", "NETWORK")
            return

        if any(x in msg for x in ['GET /status', 'GET /metrics', 'GET /containers', 'GET /services', 'GET /updates', 'GET /logs', 'GET /certificate-status', 'GET /odido-api/api/status', 'HTTP/1.1" 200', 'HTTP/1.1" 304']):
            return
        log_structured("INFO", msg, "NETWORK")
    
    def _send_json(self, data, code=200):
        try:
            body = json.dumps(data).encode('utf-8')
            self.send_response(code)
            self.send_header('Content-type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.send_header('Access-Control-Allow-Origin', '*')
            self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
            self.send_header('Access-Control-Allow-Headers', 'Content-Type, X-API-Key')
            self.end_headers()
            self.wfile.write(body)
        except Exception as e:
            print(f"Error sending JSON: {e}")

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, X-API-Key')
        self.end_headers()

    def _check_auth(self):
        # Allow certain GET endpoints without auth for the dashboard
        base_path = self.path.split('?')[0]
        if self.command == 'GET' and base_path in ['/', '/status', '/profiles', '/containers', '/services', '/certificate-status', '/events', '/updates', '/metrics', '/check-updates', '/master-update', '/logs', '/system-health', '/theme', '/project-details']:
            return True
        
        # Watchtower notification (comes from sudo docker network, simple path check)
        if self.path.startswith('/watchtower'):
            return True

        # Check for Session Token (per-session authorization)
        session_token = self.headers.get('X-Session-Token')
        if session_token and session_token in valid_sessions:
            if not session_cleanup_enabled or time.time() < valid_sessions[session_token]:
                return True
            else:
                # Token expired
                del valid_sessions[session_token]

        # Check for API Key in headers (permanent automation key)
        api_key = self.headers.get('X-API-Key')
        expected_key = os.environ.get('HUB_API_KEY')
        
        if expected_key and api_key == expected_key:
            return True
            
        return False

    def do_GET(self):
        if not self._check_auth():
            self._send_json({"error": "Unauthorized"}, 401)
            return

        path_clean = self.path.split('?')[0]

        if path_clean == '/project-details':
            try:
                # Source Size
                source_size = 0
                res = subprocess.run(['du', '-sk', '/app/sources'], capture_output=True, text=True, timeout=10)
                if res.returncode == 0: source_size = int(res.stdout.split()[0]) * 1024
                
                # Config Size
                config_size = 0
                res = subprocess.run(['du', '-sk', '/app/config'], capture_output=True, text=True, timeout=10)
                if res.returncode == 0: config_size = int(res.stdout.split()[0]) * 1024

                # Data Size
                data_size = 0
                res = subprocess.run(['du', '-sk', '/app/data'], capture_output=True, text=True, timeout=10)
                if res.returncode == 0: data_size = int(res.stdout.split()[0]) * 1024

                # Images Size
                images_size = 0
                img_res = subprocess.run(['docker', 'images', '--format', '{{.Size}}\t{{.Repository}}'], capture_output=True, text=True, timeout=10)
                if img_res.returncode == 0:
                    for line in img_res.stdout.strip().split('\n'):
                        if not line: continue
                        parts = line.split('\t')
                        if len(parts) < 2: continue
                        size_str, repo = parts[0], parts[1]
                        if any(x in repo for x in ['__APP_NAME__', CONTAINER_PREFIX + 'gluetun', CONTAINER_PREFIX + 'adguard', CONTAINER_PREFIX + 'unbound', CONTAINER_PREFIX + 'redlib', CONTAINER_PREFIX + 'wikiless', CONTAINER_PREFIX + 'invidious', CONTAINER_PREFIX + 'rimgo', CONTAINER_PREFIX + 'breezewiki', CONTAINER_PREFIX + 'memos', CONTAINER_PREFIX + 'vert', CONTAINER_PREFIX + 'scribe', CONTAINER_PREFIX + 'anonymousoverflow', CONTAINER_PREFIX + 'odido-booster', CONTAINER_PREFIX + 'portainer', CONTAINER_PREFIX + 'wg-easy']):
                            mult = 1
                            if 'GB' in size_str.upper(): mult = 1024*1024*1024
                            elif 'MB' in size_str.upper(): mult = 1024*1024
                            elif 'KB' in size_str.upper(): mult = 1024
                            sz_val = float(re.sub(r'[^0-9.]', '', size_str))
                            images_size += int(sz_val * mult)

                # Volumes & Containers Size
                volumes_size = 0
                containers_size = 0
                dangling_size = 0
                vol_res = subprocess.run(['docker', 'system', 'df', '--format', '{{.Type}}\t{{.Size}}'], capture_output=True, text=True, timeout=10)
                if vol_res.returncode == 0:
                    for line in vol_res.stdout.strip().split('\n'):
                        if '\t' not in line: continue
                        dtype, dsize = line.split('\t')[0], line.split('\t')[1]
                        
                        mult = 1
                        if 'GB' in dsize.upper(): mult = 1024*1024*1024
                        elif 'MB' in dsize.upper(): mult = 1024*1024
                        elif 'KB' in dsize.upper(): mult = 1024
                        try:
                            sz_val = float(re.sub(r'[^0-9.]', '', dsize))
                            val_bytes = int(sz_val * mult)
                            if dtype == 'Local Volumes': volumes_size = val_bytes
                            elif dtype == 'Containers': containers_size = val_bytes
                            elif dtype == 'Build Cache': dangling_size += val_bytes
                        except: continue

                # Dangling Images (Reclaimable)
                # dangling_size is already initialized and may contain Build Cache size
                dang_res = subprocess.run(['docker', 'images', '-f', 'dangling=true', '--format', '{{.Size}}'], capture_output=True, text=True, timeout=10)
                if dang_res.returncode == 0:
                    for s_line in dang_res.stdout.strip().split('\n'):
                        if not s_line: continue
                        mult = 1
                        if 'GB' in s_line.upper(): mult = 1024*1024*1024
                        elif 'MB' in s_line.upper(): mult = 1024*1024
                        elif 'KB' in s_line.upper(): mult = 1024
                        try:
                            v = float(re.sub(r'[^0-9.]', '', s_line))
                            dangling_size += int(v * mult)
                        except: continue

                self._send_json({
                    "source_size": (source_size + config_size) / (1024 * 1024),
                    "data_size": data_size / (1024 * 1024),
                    "images_size": images_size / (1024 * 1024),
                    "volumes_size": volumes_size / (1024 * 1024),
                    "containers_size": containers_size / (1024 * 1024),
                    "dangling_size": dangling_size / (1024 * 1024)
                })
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif path_clean == '/system-health':
            try:
                # System Uptime
                uptime_seconds = time.time() - psutil.boot_time()
                
                # CPU & RAM
                cpu_usage = psutil.cpu_percent(interval=None)
                ram = psutil.virtual_memory()
                
                # Disk Health (Root Partition)
                disk = psutil.disk_usage('/')
                
                # Project Size (Comprehensive)
                project_size_bytes = 0
                try:
                    # Sum up BASE_DIR (mounted as /project_root), and check volume sizes via docker
                    res = subprocess.run(['du', '-sk', '/project_root'], capture_output=True, text=True, timeout=15)
                    if res.returncode == 0:
                        project_size_bytes += int(res.stdout.split()[0]) * 1024
                    
                    # Also include ALL Docker images related to this stack
                    img_res = subprocess.run(['docker', 'images', '--format', '{{.Size}}\t{{.Repository}}'], capture_output=True, text=True, timeout=10)
                    if img_res.returncode == 0:
                        for line in img_res.stdout.strip().split('\n'):
                            size_str, repo = line.split('\t')
                            # Check if it belongs to our stack
                            if any(x in repo for x in ['__APP_NAME__', CONTAINER_PREFIX + 'gluetun', CONTAINER_PREFIX + 'adguard', CONTAINER_PREFIX + 'unbound', CONTAINER_PREFIX + 'redlib', CONTAINER_PREFIX + 'wikiless', CONTAINER_PREFIX + 'invidious', CONTAINER_PREFIX + 'rimgo', CONTAINER_PREFIX + 'breezewiki', CONTAINER_PREFIX + 'memos', CONTAINER_PREFIX + 'vert', CONTAINER_PREFIX + 'scribe', CONTAINER_PREFIX + 'anonymousoverflow', CONTAINER_PREFIX + 'odido-booster', CONTAINER_PREFIX + 'portainer', CONTAINER_PREFIX + 'wg-easy']):
                                mult = 1
                                if 'GB' in size_str.upper(): mult = 1024*1024*1024
                                elif 'MB' in size_str.upper(): mult = 1024*1024
                                elif 'KB' in size_str.upper(): mult = 1024
                                sz_val = float(re.sub(r'[^0-9.]', '', size_str))
                                project_size_bytes += int(sz_val * mult)
                except: pass

                # Drive Health Logic (SMART-lite)
                drive_health_pct = 100 - disk.percent
                drive_status = "Healthy"
                smart_alerts = []
                
                if disk.percent > 90:
                    drive_status = "Warning (High Usage)"
                    smart_alerts.append("Disk space is critical (>90%)")
                
                # Try to get real SMART info if smartctl is available
                try:
                    s_res = subprocess.run(['smartctl', '-H', '/dev/sda'], capture_output=True, text=True, timeout=5)
                    if s_res.returncode == 0:
                        if "PASSED" not in s_res.stdout:
                            drive_status = "Action Required"
                            smart_alerts.append("SMART health check failed")
                except: pass

                health_data = {
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
                self._send_json(health_data)
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif path_clean == '/purge-images':
            try:
                # Purge dangling images
                res = subprocess.run(['docker', 'image', 'prune', '-f'], capture_output=True, text=True, timeout=60)
                reclaimed_msg = "Unused images and build cache cleared."
                if "Total reclaimed space:" in res.stdout:
                    reclaimed = res.stdout.split("Total reclaimed space:")[1].strip().split('\n')[0]
                    reclaimed_msg = f"Successfully reclaimed {reclaimed} of storage space."
                
                # Purge build cache
                subprocess.run(['docker', 'builder', 'prune', '-f'], capture_output=True, text=True, timeout=60)
                self._send_json({"success": True, "message": reclaimed_msg})
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif path_clean == '/status':
            try:
                result = subprocess.run([CONTROL_SCRIPT, "status"], capture_output=True, text=True, timeout=30)
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
                    total_rx, total_tx = get_total_usage(DATA_USAGE_FILE)
                    current_rx = int(g.get('session_rx', 0))
                    current_tx = int(g.get('session_tx', 0))
                    # Only add if current is greater than saved (prevents double counting if script restarts)
                    # Simple heuristic: if current is less than saved, it means a new session started.
                    # We actually want to keep track of increments. 
                    # For simplicity, we'll just store the total.
                    # In a real system we'd track deltas. 
                    save_total_usage(DATA_USAGE_FILE, total_rx + current_rx, total_tx + current_tx)
                    status_data['gluetun']['total_rx'], status_data['gluetun']['total_tx'] = get_total_usage(DATA_USAGE_FILE)
                
                # Update total usage for WG-Easy
                w = status_data.get('wgeasy', {})
                if w.get('status') == 'up':
                    total_rx, total_tx = get_total_usage(WGE_DATA_USAGE_FILE)
                    current_rx = int(w.get('session_rx', 0))
                    current_tx = int(w.get('session_tx', 0))
                    save_total_usage(WGE_DATA_USAGE_FILE, total_rx + current_rx, total_tx + current_tx)
                    status_data['wgeasy']['total_rx'], status_data['wgeasy']['total_tx'] = get_total_usage(WGE_DATA_USAGE_FILE)

                self._send_json(status_data)
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif path_clean == '/theme':
            theme_file = os.path.join(CONFIG_DIR, "theme.json")
            if os.path.exists(theme_file):
                try:
                    with open(theme_file, 'r') as f:
                        self._send_json(json.load(f))
                except:
                    self._send_json({})
            else:
                self._send_json({})
        elif path_clean == '/master-update':
            try:
                def run_master_update():
                    try:
                        # 1. Start Logging
                        log_structured("INFO", "[Update Engine] Starting Master Update process.", "MAINTENANCE")
                        
                        # 2. Perform Full Backup
                        log_structured("INFO", "[Update Engine] Creating pre-update backup...", "MAINTENANCE")
                        subprocess.run(["/usr/local/bin/migrate.sh", "all", "backup-all"], timeout=300)
                        
                        # 3. Trigger source updates for all
                        src_root = "/app/sources"
                        if os.path.exists(src_root):
                            log_structured("INFO", "[Update Engine] Refreshing service source code...", "MAINTENANCE")
                            for repo in os.listdir(src_root):
                                repo_path = os.path.join(src_root, repo)
                                if os.path.isdir(os.path.join(repo_path, ".git")):
                                    subprocess.run(["git", "fetch", "--all"], cwd=repo_path)
                        
                        # 4. Trigger rebuilds for all services
                        log_structured("INFO", "[Update Engine] Rebuilding all services from source...", "MAINTENANCE")
                        subprocess.run(['docker', 'compose', '-f', '/app/docker-compose.yml', 'up', '-d', '--build'], timeout=1200)
                        
                        log_structured("INFO", "[Update Engine] Master Update successfully completed.", "MAINTENANCE")
                    except Exception as e:
                        log_structured("ERROR", f"[Update Engine] Master Update failed: {str(e)}", "MAINTENANCE")

                import threading
                threading.Thread(target=run_master_update).start()
                self._send_json({"success": True, "message": "Master update process started in background"})
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif path_clean == '/check-updates':
            try:
                log_structured("INFO", "Checking for system-wide source updates...", "MAINTENANCE")
                
                # Also trigger git fetch for sources in background
                src_root = "/app/sources"
                if os.path.exists(src_root):
                    for repo in os.listdir(src_root):
                        repo_path = os.path.join(src_root, repo)
                        if os.path.isdir(os.path.join(repo_path, ".git")):
                            subprocess.Popen(["git", "fetch"], cwd=repo_path)
                
                self._send_json({"success": True, "message": "Source update check initiated"})
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif path_clean == '/updates':
            try:
                updates = {}
                
                # 1. Check Git Sources
                src_root = "/app/sources"
                if os.path.exists(src_root):
                    for repo in os.listdir(src_root):
                        repo_path = os.path.join(src_root, repo)
                        if os.path.isdir(os.path.join(repo_path, ".git")):
                            # Fetch remote and check status (already fetched by check-updates)
                            res = subprocess.run(["git", "status", "-uno"], cwd=repo_path, capture_output=True, text=True, timeout=10)
                            if "behind" in res.stdout:
                                updates[repo] = "Update Available"
                
                # 2. Check Pending Image Updates
                updates_file = "/app/data/image_updates.json"
                if os.path.exists(updates_file):
                    try:
                        with open(updates_file, 'r') as f:
                            img_updates = json.load(f)
                            # Merge, ignoring timestamp keys
                            for k, v in img_updates.items():
                                if not k.startswith('_'):
                                    updates[k] = v
                    except: pass

                self._send_json({"updates": updates})
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        def run_migration_task(service, action, backup_flag=None):
            cmd = ["/usr/local/bin/migrate.sh", service, action]
            if backup_flag:
                cmd.append(backup_flag)
            
            try:
                res = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
                return {"success": True, "output": res.stdout}
            except subprocess.TimeoutExpired:
                return {"error": "Operation timed out"}, 504
            except Exception as e:
                return {"error": str(e)}, 500

        if self.path.startswith('/migrate'):
            try:
                from urllib.parse import urlparse, parse_qs
                query = urlparse(self.path).query
                params = parse_qs(query)
                service = params.get('service', [''])[0]
                do_backup = params.get('backup', ['yes'])[0]
                if service:
                    result, code = run_migration_task(service, "migrate", do_backup), 200
                    if isinstance(result, tuple): result, code = result
                    self._send_json(result, code)
                else:
                    self._send_json({"error": "Service parameter missing"}, 400)
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path.startswith('/clear-db'):
            try:
                from urllib.parse import urlparse, parse_qs
                query = urlparse(self.path).query
                params = parse_qs(query)
                service = params.get('service', [''])[0]
                do_backup = params.get('backup', ['yes'])[0]
                if service:
                    result, code = run_migration_task(service, "clear", do_backup), 200
                    if isinstance(result, tuple): result, code = result
                    self._send_json(result, code)
                else:
                    self._send_json({"error": "Service parameter missing"}, 400)
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path.startswith('/clear-logs'):
            try:
                from urllib.parse import urlparse, parse_qs
                query = urlparse(self.path).query
                params = parse_qs(query)
                service = params.get('service', [''])[0]
                if service:
                    result, code = run_migration_task(service, "clear-logs"), 200
                    if isinstance(result, tuple): result, code = result
                    self._send_json(result, code)
                else:
                    self._send_json({"error": "Service parameter missing"}, 400)
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path.startswith('/vacuum'):
            try:
                from urllib.parse import urlparse, parse_qs
                query = urlparse(self.path).query
                params = parse_qs(query)
                service = params.get('service', [''])[0]
                if service:
                    result, code = run_migration_task(service, "vacuum"), 200
                    if isinstance(result, tuple): result, code = result
                    self._send_json(result, code)
                else:
                    self._send_json({"error": "Service parameter missing"}, 400)
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif path_clean == '/containers':
            try:
                # Get container IDs and labels
                result = subprocess.run(
                    ['docker', 'ps', '-a', '--no-trunc', '--format', '{{.Names}}\t{{.ID}}\t{{.Labels}}'],
                    capture_output=True, text=True, timeout=10
                )
                containers = {}
                for line in result.stdout.strip().split('\n'):
                    parts = line.split('\t')
                    if len(parts) >= 2:
                        name, cid = parts[0], parts[1]
                        if CONTAINER_PREFIX and name.startswith(CONTAINER_PREFIX):
                            name = name[len(CONTAINER_PREFIX):]
                        labels = parts[2] if len(parts) > 2 else ""
                        is_hardened = "io.dhi.hardened=true" in labels
                        containers[name] = {"id": cid, "hardened": is_hardened}
                self._send_json({"containers": containers})
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif path_clean == '/services':
            try:
                self._send_json({"services": load_services()})
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif path_clean == '/certificate-status':
            try:
                cert_file = "/etc/adguard/conf/ssl.crt"
                status = {"type": "None", "subject": "--", "issuer": "--", "expires": "--", "status": "No Certificate"}
                if os.path.exists(cert_file):
                    res = subprocess.run(['openssl', 'x509', '-in', cert_file, '-noout', '-subject', '-issuer', '-dates'], capture_output=True, text=True)
                    if res.returncode == 0:
                        lines = res.stdout.split('\n')
                        status["type"] = "RSA/ECC"
                        for line in lines:
                            if line.startswith('subject='): status['subject'] = line.replace('subject=', '').strip()
                            if line.startswith('issuer='): status['issuer'] = line.replace('issuer=', '').strip()
                            if line.startswith('notAfter='): status['expires'] = line.replace('notAfter=', '').strip()
                        
                        # Check for self-signed
                        if status['subject'] == status['issuer'] or "PrivacyHub" in status['issuer']:
                            status["status"] = "Self-Signed (Local)"
                        else:
                            status["status"] = "Valid (Trusted)"
                
                # Check for acme.sh failure logs for more info
                log_file = "/etc/adguard/conf/certbot/last_run.log"
                if os.path.exists(log_file):
                    with open(log_file, 'r') as f:
                        log_content = f.read()
                        if "Verify error" in log_content or "Challenge failed" in log_content:
                            status["error"] = "deSEC verification failed. Check your token and domain."
                            status["status"] = "Issuance Failed"
                        elif "Rate limit" in log_content or "too many certificates" in log_content:
                            # Attempt to extract "retry after" timestamp if present
                            retry_match = re.search(r"retry after ([0-9:\- ]+ UTC)", log_content)
                            if retry_match:
                                status["error"] = f"Let's Encrypt rate limit reached. Next attempt after: {retry_match.group(1)}"
                            else:
                                status["error"] = "Let's Encrypt rate limit reached. Retrying automatically in 24h."
                            status["status"] = "Rate Limited"
                        elif "Invalid token" in log_content:
                            status["error"] = "Invalid deSEC token."
                            status["status"] = "Auth Error"
                
                self._send_json(status)
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path.startswith('/logs'):
            try:
                from urllib.parse import urlparse, parse_qs
                query = urlparse(self.path).query
                params = parse_qs(query)
                level = params.get('level', [None])[0]
                category = params.get('category', [None])[0]
                
                # Filter out "ALL" if it sneaks in
                if level == "ALL": level = None
                if category == "ALL": category = None

                conn = sqlite3.connect(DB_FILE)
                c = conn.cursor()
                sql = "SELECT timestamp, level, category, message FROM logs"
                args = []
                if level or category:
                    sql += " WHERE"
                    if level:
                        sql += " level = ?"
                        args.append(level)
                    if category:
                        if level: sql += " AND"
                        sql += " category = ?"
                        args.append(category)
                sql += " ORDER BY id DESC LIMIT 100"
                c.execute(sql, tuple(args))
                rows = c.fetchall()
                conn.close()
                
                logs = [{"timestamp": r[0], "level": r[1], "category": r[2], "message": r[3]} for r in rows]
                logs.reverse() # Sort chronological (Oldest -> Newest) to match stream behavior
                self._send_json({"logs": logs})
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif path_clean == '/metrics':
            try:
                global last_metrics_request
                last_metrics_request = time.time()
                conn = sqlite3.connect(DB_FILE)
                c = conn.cursor()
                # Get latest metrics for each container
                c.execute('''SELECT container, cpu_percent, mem_usage, mem_limit 
                             FROM metrics WHERE id IN (SELECT MAX(id) FROM metrics GROUP BY container)''')
                rows = c.fetchall()
                conn.close()
                metrics = {r[0]: {"cpu": r[1], "mem": r[2], "limit": r[3]} for r in rows}
                self._send_json({"metrics": metrics})
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path == '/config-desec' and self.command == 'POST':
            try:
                content_length = int(self.headers['Content-Length'])
                post_data = json.loads(self.rfile.read(content_length))
                domain = post_data.get('domain')
                token = post_data.get('token')
                
                if domain or token:
                    # Update .secrets or similar file
                    secrets_file = "/app/.secrets"
                    file_secrets = {}
                    if os.path.exists(secrets_file):
                        with open(secrets_file, 'r') as f:
                            for line in f:
                                if '=' in line:
                                    k, v = line.strip().split('=', 1)
                                    file_secrets[k] = v
                    
                    if domain: file_secrets['DESEC_DOMAIN'] = domain
                    if token: file_secrets['DESEC_TOKEN'] = token
                    
                    with open(secrets_file, 'w') as f:
                        for k, v in file_secrets.items():
                            f.write(f"{k}={v}\n")
                    
                    self._send_json({"success": True})
                else:
                    self._send_json({"error": "Missing domain or token"}, 400)
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif path_clean == '/profiles':
            try:
                files = [f.replace('.conf', '') for f in os.listdir(PROFILES_DIR) if f.endswith('.conf')]
                self._send_json({"profiles": files})
            except:
                self._send_json({"error": "Failed to list profiles"}, 500)
        elif path_clean == '/events':
            self.send_response(200)
            self.send_header('Content-type', 'text/event-stream')
            self.send_header('Cache-Control', 'no-cache')
            self.send_header('Connection', 'keep-alive')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.send_header('X-Accel-Buffering', 'no')
            self.end_headers()
            try:
                for _ in range(10):
                    if os.path.exists(LOG_FILE):
                        break
                    time.sleep(1)
                if not os.path.exists(LOG_FILE):
                    self.wfile.write(b"data: Log file initializing...\n\n")
                    self.wfile.flush()
                f = open(LOG_FILE, 'r')
                f.seek(0, 2)
                # Send initial keepalive
                self.wfile.write(b": keepalive\n\n")
                self.wfile.flush()
                keepalive_counter = 0
                while True:
                    line = f.readline()
                    if line:
                        self.wfile.write(f"data: {line.strip()}\n\n".encode('utf-8'))
                        self.wfile.flush()
                        keepalive_counter = 0
                    else:
                        time.sleep(1)
                        keepalive_counter += 1
                        # Send keepalive comment every 15 seconds to prevent timeout
                        if keepalive_counter >= 15:
                            self.wfile.write(b": keepalive\n\n")
                            self.wfile.flush()
                            keepalive_counter = 0
            except (BrokenPipeError, ConnectionResetError):
                pass
            except Exception:
                pass

    
    def do_DELETE(self):
        if not self._check_auth():
            self._send_json({"error": "Unauthorized"}, 401)
            return

        if self.path.startswith('/wg/clients/'):
            client_id = self.path.split('/')[-1]
            if client_id:
                resp, code = self._proxy_wgeasy('DELETE', f"/{client_id}")
                self._send_json(resp, code)
            else:
                self._send_json({"error": "Client ID missing"}, 400)
        else:
            self._send_json({"error": "Method not allowed"}, 405)

    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length).decode('utf-8')
        
        try:
            data = json.loads(post_data)
        except:
            data = {}

        if self.path == '/toggle-session-cleanup':
            global session_cleanup_enabled
            session_cleanup_enabled = data.get('enabled', True)
            self._send_json({"success": True, "enabled": session_cleanup_enabled})
            return

        if self.path == '/uninstall':
            try:
                def run_uninstall():
                    log_structured("INFO", "Uninstall sequence started", "MAINTENANCE")
                    time.sleep(10) # Give enough time for response to flush
                    subprocess.run(["bash", "/app/zima.sh", "-x"], cwd="/app")

                import threading
                threading.Thread(target=run_uninstall).start()
                self._send_json({"success": True, "message": "Uninstall sequence started"})
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
            return

        if self.path == '/verify-admin':
            try:
                password = data.get('password')
                expected_admin = os.environ.get('ADMIN_PASS_RAW')
                if expected_admin and password == expected_admin:
                    # Generate a new session token for this browser session
                    token = secrets.token_hex(24)
                    
                    # Determine timeout
                    timeout_seconds = 1800
                    theme_file = os.path.join(CONFIG_DIR, "theme.json")
                    if os.path.exists(theme_file):
                        try:
                            with open(theme_file, 'r') as f:
                                t = json.load(f)
                                # Timeout in minutes
                                if 'session_timeout' in t:
                                    timeout_seconds = int(t['session_timeout']) * 60
                        except: pass
                    
                    valid_sessions[token] = time.time() + timeout_seconds
                    self._send_json({"success": True, "token": token, "cleanup": session_cleanup_enabled})
                else:
                    self._send_json({"error": "Invalid admin password"}, 401)
            except Exception as e:
                log_structured("ERROR", f"Verify admin failed: {e}", "AUTH")
                self._send_json({"error": "Internal Server Error"}, 500)
            return

        if not self._check_auth():
            self._send_json({"error": "Unauthorized"}, 401)
            return

        if self.path == '/theme':
            theme_file = os.path.join(CONFIG_DIR, "theme.json")
            try:
                with open(theme_file, 'w') as f:
                    json.dump(data, f)
                
                # Sync update_strategy to .secrets for zima.sh
                strategy = data.get('update_strategy')
                if strategy:
                    secrets_file = "/app/.secrets"
                    file_secrets = {}
                    if os.path.exists(secrets_file):
                        with open(secrets_file, 'r') as f:
                            for line in f:
                                if '=' in line:
                                    k, v = line.strip().split('=', 1)
                                    file_secrets[k] = v
                    file_secrets['UPDATE_STRATEGY'] = strategy
                


                with open(secrets_file, 'w') as f:
                        for k, v in file_secrets.items():
                            f.write(f"{k}={v}\n")

                self._send_json({"success": True})
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path == '/upload':
            try:
                l = int(self.headers['Content-Length'])
                data = json.loads(self.rfile.read(l).decode('utf-8'))
                raw_name = data.get('name', '').strip()
                config = data.get('config')
                if not raw_name:
                    extracted = extract_profile_name(config)
                    raw_name = extracted if extracted else f"Imported_{int(time.time())}"
                safe = "".join([c for c in raw_name if c.isalnum() or c in ('-', '_', '#')])
                with open(os.path.join(PROFILES_DIR, f"{safe}.conf"), "w") as f:
                    f.write(config.replace('\r', ''))
                self._send_json({"success": True, "name": safe})
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path == '/activate':
            try:
                l = int(self.headers['Content-Length'])
                name = json.loads(self.rfile.read(l).decode('utf-8')).get('name')
                safe = "".join([c for c in name if c.isalnum() or c in ('-', '_', '#')])
                subprocess.run([CONTROL_SCRIPT, "activate", safe], check=True, timeout=60)
                self._send_json({"success": True})
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path == '/delete':
            try:
                l = int(self.headers['Content-Length'])
                name = json.loads(self.rfile.read(l).decode('utf-8')).get('name')
                safe = "".join([c for c in name if c.isalnum() or c in ('-', '_', '#')])
                subprocess.run([CONTROL_SCRIPT, "delete", safe], check=True, timeout=30)
                self._send_json({"success": True})
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path == '/restart-stack':
            try:
                # Trigger a full stack restart in the background
                log_structured("SYSTEM", "Full stack restart triggered via Dashboard", "ORCHESTRATION")
                
                # We use a detached process to avoid killing the API before it responds
                # The restart will take 20-30 seconds.
                subprocess.Popen(["/bin/sh", "-c", "sleep 2 && docker compose -f /app/docker-compose.yml restart"])
                self._send_json({"success": True, "message": "Stack restart initiated"})
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path == '/batch-update':
            try:
                l = int(self.headers['Content-Length'])
                data = json.loads(self.rfile.read(l).decode('utf-8'))
                services = data.get('services', [])
                if not services or not isinstance(services, list):
                    self._send_json({"error": "List of services required"}, 400)
                    return

                def run_batch_update(svc_list):
                    try:
                        strategy = get_update_strategy()
                        log_structured("INFO", f"[Update Engine] Starting batch update (Strategy: {strategy}) for {len(svc_list)} services...", "MAINTENANCE")
                        for name in svc_list:
                            try:
                                log_structured("INFO", f"[Update Engine] Processing {name}...", "MAINTENANCE")
                                
                                # 1. Backup
                                subprocess.run(["/usr/local/bin/migrate.sh", name, "backup", "yes"], timeout=120)
                                
                                # 2. Refresh source
                                repo_path = f"/app/sources/{name}"
                                if os.path.exists(repo_path) and os.path.isdir(os.path.join(repo_path, ".git")):
                                    log_structured("INFO", f"[Update Engine] Refreshing source for {name}...", "MAINTENANCE")
                                    subprocess.run(["git", "fetch", "--all", "--tags", "--prune"], cwd=repo_path, check=True, timeout=60)
                                    
                                    # Detect default branch
                                    res_db = subprocess.run(["git", "symbolic-ref", "refs/remotes/origin/HEAD"], cwd=repo_path, capture_output=True, text=True, timeout=10)
                                    default_branch = res_db.stdout.strip().replace("refs/remotes/origin/", "")
                                    if not default_branch:
                                        # Fallback check
                                        res_db = subprocess.run(["git", "branch", "-r"], cwd=repo_path, capture_output=True, text=True)
                                        if "origin/main" in res_db.stdout: default_branch = "main"
                                        else: default_branch = "master"

                                    if strategy == 'stable':
                                        # Find latest semver tag using ls-remote
                                        res_tags = subprocess.run("git ls-remote --tags origin | grep -o 'refs/tags/v\?[0-9]\+\.[0-9]\+\.[0-9]\+$' | cut -d'/' -f3 | sort -V | tail -n 1", cwd=repo_path, shell=True, capture_output=True, text=True)
                                        latest_tag = res_tags.stdout.strip()
                                        
                                        # Fallback to any tag
                                        if not latest_tag:
                                            res_tags = subprocess.run("git ls-remote --tags origin | cut -d'/' -f3 | grep -v '\^{}' | tail -n 1", cwd=repo_path, shell=True, capture_output=True, text=True)
                                            latest_tag = res_tags.stdout.strip()

                                        if latest_tag:
                                            log_structured("INFO", f"[Update Engine] Switching {name} to stable tag: {latest_tag}", "MAINTENANCE")
                                            subprocess.run(["git", "checkout", "-f", latest_tag], cwd=repo_path, check=True, timeout=30)
                                        else:
                                            log_structured("WARN", f"[Update Engine] No tags found for {name}, using {default_branch}", "MAINTENANCE")
                                            subprocess.run(["git", "checkout", "-f", default_branch], cwd=repo_path, check=True, timeout=30)
                                            subprocess.run(["git", "reset", "--hard", f"origin/{default_branch}"], cwd=repo_path, check=True, timeout=30)
                                            subprocess.run(["git", "pull"], cwd=repo_path, check=True, timeout=60)
                                    else:
                                        log_structured("INFO", f"[Update Engine] Switching {name} to latest branch: {default_branch}", "MAINTENANCE")
                                        subprocess.run(["git", "checkout", "-f", default_branch], cwd=repo_path, check=True, timeout=30)
                                        subprocess.run(["git", "reset", "--hard", f"origin/{default_branch}"], cwd=repo_path, check=True, timeout=30)
                                        subprocess.run(["git", "pull"], cwd=repo_path, check=True, timeout=60)

                                    if os.path.exists("/app/patches.sh"):
                                        subprocess.run(["/app/patches.sh", name], check=True, timeout=30)
                                
                                # 3. Rebuild and restart
                                log_structured("INFO", f"[Update Engine] Rebuilding {name}...", "MAINTENANCE")
                                subprocess.run(['docker', 'compose', '-f', '/app/docker-compose.yml', 'pull', name], timeout=300)
                                subprocess.run(['docker', 'compose', '-f', '/app/docker-compose.yml', 'up', '-d', '--build', name], timeout=600)
                                
                                # 4. Migrate
                                log_structured("INFO", f"[Update Engine] Running migrations for {name}...", "MAINTENANCE")
                                subprocess.run(["/usr/local/bin/migrate.sh", name, "migrate", "no"], timeout=120)
                                
                                # 5. Vacuum
                                log_structured("INFO", f"[Update Engine] Optimizing database for {name}...", "MAINTENANCE")
                                subprocess.run(["/usr/local/bin/migrate.sh", name, "vacuum"], timeout=60)
                                
                                log_structured("INFO", f"[Update Engine] {name} update complete.", "MAINTENANCE")
                            except Exception as ex:
                                log_structured("ERROR", f"[Update Engine] Failed to update {name}: {str(ex)}", "MAINTENANCE")
                        
                        log_structured("INFO", "[Update Engine] Batch update finished.", "MAINTENANCE")
                    except Exception as e:
                        log_structured("ERROR", f"[Update Engine] Batch update crashed: {str(e)}", "MAINTENANCE")

                import threading
                threading.Thread(target=run_batch_update, args=(services,)).start()
                self._send_json({"success": True, "message": "Batch update started in background"})
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path == '/update-service':
            try:
                l = int(self.headers['Content-Length'])
                data = json.loads(self.rfile.read(l).decode('utf-8'))
                service = data.get('service')
                if not service:
                    self._send_json({"error": "Service name required"}, 400)
                    return
                
                def run_service_update(name):
                    try:
                        strategy = get_update_strategy()
                        log_structured("INFO", f"[Update Engine] Starting update for {name} (Strategy: {strategy})...", "MAINTENANCE")
                        
                        # 1. Pre-update Backup
                        log_structured("INFO", f"[Update Engine] Creating safety backup for {name}...", "MAINTENANCE")
                        subprocess.run(["/usr/local/bin/migrate.sh", name, "backup"], timeout=120)
                        
                        # 2. Refresh source
                        repo_path = f"/app/sources/{name}"
                        if os.path.exists(repo_path) and os.path.isdir(os.path.join(repo_path, ".git")):
                            subprocess.run(["git", "fetch", "--all", "--tags", "--prune"], cwd=repo_path, check=True, timeout=60)
                            
                            # Detect default branch
                            res_db = subprocess.run(["git", "symbolic-ref", "refs/remotes/origin/HEAD"], cwd=repo_path, capture_output=True, text=True, timeout=10)
                            default_branch = res_db.stdout.strip().replace("refs/remotes/origin/", "")
                            if not default_branch:
                                res_db = subprocess.run(["git", "branch", "-r"], cwd=repo_path, capture_output=True, text=True)
                                if "origin/main" in res_db.stdout: default_branch = "main"
                                else: default_branch = "master"

                            if strategy == 'stable':
                                # Find latest semver tag using ls-remote
                                res_tags = subprocess.run("git ls-remote --tags origin | grep -o 'refs/tags/v\?[0-9]\+\.[0-9]\+\.[0-9]\+$' | cut -d'/' -f3 | sort -V | tail -n 1", cwd=repo_path, shell=True, capture_output=True, text=True)
                                latest_tag = res_tags.stdout.strip()
                                
                                # Fallback to any tag
                                if not latest_tag:
                                    res_tags = subprocess.run("git ls-remote --tags origin | cut -d'/' -f3 | grep -v '\^{}' | tail -n 1", cwd=repo_path, shell=True, capture_output=True, text=True)
                                    latest_tag = res_tags.stdout.strip()

                                if latest_tag:
                                    log_structured("INFO", f"[Update Engine] Switching {name} to stable tag: {latest_tag}", "MAINTENANCE")
                                    subprocess.run(["git", "checkout", "-f", latest_tag], cwd=repo_path, check=True, timeout=30)
                                else:
                                    log_structured("WARN", f"[Update Engine] No tags found for {name}, using {default_branch}", "MAINTENANCE")
                                    subprocess.run(["git", "checkout", "-f", default_branch], cwd=repo_path, check=True, timeout=30)
                                    subprocess.run(["git", "reset", "--hard", f"origin/{default_branch}"], cwd=repo_path, check=True, timeout=30)
                                    subprocess.run(["git", "pull"], cwd=repo_path, check=True, timeout=60)
                            else:
                                log_structured("INFO", f"[Update Engine] Switching {name} to latest branch: {default_branch}", "MAINTENANCE")
                                subprocess.run(["git", "checkout", "-f", default_branch], cwd=repo_path, check=True, timeout=30)
                                subprocess.run(["git", "reset", "--hard", f"origin/{default_branch}"], cwd=repo_path, check=True, timeout=30)
                                subprocess.run(["git", "pull"], cwd=repo_path, check=True, timeout=60)

                            if os.path.exists("/app/patches.sh"):
                                subprocess.run(["/app/patches.sh", name], check=True, timeout=30)
                        
                        # 3. Rebuild and restart
                        log_structured("INFO", f"[Update Engine] Build process for {name} initiated...", "MAINTENANCE")
                        subprocess.run(['docker', 'compose', '-f', '/app/docker-compose.yml', 'pull', name], timeout=300)
                        subprocess.run(['docker', 'compose', '-f', '/app/docker-compose.yml', 'up', '-d', '--build', name], timeout=600)
                        log_structured("INFO", f"[Update Engine] {name} update completed successfully.", "MAINTENANCE")
                    except Exception as ex:
                        log_structured("ERROR", f"[Update Engine] {name} update failed: {str(ex)}", "MAINTENANCE")

                import threading
                threading.Thread(target=run_service_update, args=(service,)).start()
                self._send_json({"success": True, "message": f"Update for {service} started in background"})
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        
        elif self.path == '/wg/clients':
            try:
                l = int(self.headers['Content-Length'])
                data = json.loads(self.rfile.read(l).decode('utf-8'))
                # wg-easy expects {name: "..."}
                resp, code = self._proxy_wgeasy('POST', '', data)
                self._send_json(resp, code)
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path == '/rotate-api-key' and self.command == 'POST':
            try:
                content_length = int(self.headers['Content-Length'])
                post_data = json.loads(self.rfile.read(content_length))
                new_key = post_data.get('new_key')
                if new_key:
                    secrets_file = "/app/.secrets"
                    file_secrets = {}
                    if os.path.exists(secrets_file):
                        with open(secrets_file, 'r') as f:
                            for line in f:
                                if '=' in line:
                                    k, v = line.strip().split('=', 1)
                                    file_secrets[k] = v
                    file_secrets['HUB_API_KEY'] = new_key
                    with open(secrets_file, 'w') as f:
                        for k, v in file_secrets.items():
                            f.write(f"{k}={v}\n")
                    
                    log_structured("SECURITY", "Dashboard API key rotated", "AUTH")
                    self._send_json({"success": True})
                else:
                    self._send_json({"error": "New key required"}, 400)
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path.startswith('/changelog'):
            try:
                from urllib.parse import urlparse, parse_qs
                query = urlparse(self.path).query
                params = parse_qs(query)
                service = params.get('service', [''])[0]
                
                if not service:
                    self._send_json({"error": "Service required"}, 400)
                    return

                SERVICE_REPOS = {
                    "adguard": {"repo": "AdguardTeam/AdGuardHome", "type": "github"},
                    "portainer": {"repo": "portainer/portainer", "type": "github"},
                    "memos": {"repo": "usememos/memos", "type": "github"},
                    "watchtower": {"repo": "containrrr/watchtower", "type": "github"},
                    "unbound": {"repo": "NLnetLabs/unbound", "type": "github"}
                }

                # Check if it's a source-based service
                repo_path = f"/app/sources/{service}"
                if os.path.exists(repo_path) and os.path.isdir(os.path.join(repo_path, ".git")):
                    # Fetch first
                    subprocess.run(["git", "fetch"], cwd=repo_path, timeout=15)
                    branch = "origin/master"
                    if subprocess.run(["git", "rev-parse", "--verify", "origin/main"], cwd=repo_path).returncode == 0:
                        branch = "origin/main"
                    
                    res = subprocess.run(
                        ["git", "log", "--pretty=format:%h - %s (%cr)", f"HEAD..{branch}"], 
                        cwd=repo_path, capture_output=True, text=True, timeout=5
                    )
                    
                    if res.returncode == 0 and res.stdout.strip():
                        self._send_json({"changelog": res.stdout})
                    else:
                        self._send_json({"changelog": "No new commits found in source repo."})
                
                # Check if it's a known image-based service
                elif service in SERVICE_REPOS:
                    meta = SERVICE_REPOS[service]
                    try:
                        url = ""
                        if meta["type"] == "github":
                            url = f"https://api.github.com/repos/{meta['repo']}/releases/latest"
                        elif meta["type"] == "codeberg":
                            url = f"https://codeberg.org/api/v1/repos/{meta['repo']}/releases/latest"
                        
                        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"})
                        opener = get_proxy_opener()
                        with opener.open(req, timeout=10) as resp:
                            data = json.loads(resp.read().decode())
                            body = data.get("body", "No description available.")
                            name = data.get("name") or data.get("tag_name") or "Latest Release"
                            self._send_json({"changelog": f"## {name}\n\n{body}"})
                    except Exception as e:
                        self._send_json({"changelog": f"Failed to fetch release notes: {str(e)}"})
                else:
                    self._send_json({"changelog": "Changelog not available for this service."})
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        
        elif path_clean == '/wg/clients':
            resp, code = self._proxy_wgeasy('GET', '')
            self._send_json(resp, code)
        
        elif path_clean.startswith('/wg/clients/') and path_clean.endswith('/configuration'):
            try:
                # Extract ID: /wg/clients/UUID/configuration
                parts = path_clean.split('/')
                client_id = parts[3]
                
                # We need to return text/plain for this one
                # _proxy_wgeasy returns json decoded, we might need raw for config file if it's not JSON
                # Let's use a specialized call or modify _proxy_wgeasy to handle non-json?
                # For simplicity, let's implement a specific proxy call here or adjust _proxy_wgeasy.
                # Actually _proxy_wgeasy parses JSON. We need raw text.
                
                # Let's do it manually here reusing logic:
                password = os.environ.get('VPN_PASS_RAW', '') or os.environ.get('ADMIN_PASS_RAW', '')
                import urllib.request
                opener = urllib.request.build_opener()
                login_url = f"http://{CONTAINER_PREFIX}wg-easy:51821/api/session"
                login_data = json.dumps({"password": password}).encode('utf-8')
                req = urllib.request.Request(login_url, data=login_data, headers={'Content-Type': 'application/json'})
                
                cookie = ""
                try:
                    with opener.open(req, timeout=5) as resp:
                        if 'Set-Cookie' in resp.info():
                            cookie = resp.info()['Set-Cookie'].split(';')[0]
                except: pass

                target_url = f"http://{CONTAINER_PREFIX}wg-easy:51821/api/wireguard/client/{client_id}/configuration"
                req = urllib.request.Request(target_url)
                if cookie: req.add_header('Cookie', cookie)
                
                with opener.open(req, timeout=10) as resp:
                    config_content = resp.read()
                    self.send_response(200)
                    self.send_header('Content-type', 'text/plain')
                    self.send_header('Content-Length', str(len(config_content)))
                    self.end_headers()
                    self.wfile.write(config_content)
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif path_clean == '/odido-userid':
            try:
                l = int(self.headers['Content-Length'])
                data = json.loads(self.rfile.read(l).decode('utf-8'))
                oauth_token = data.get('oauth_token', '').strip()
                if not oauth_token:
                    self._send_json({"error": "oauth_token is required"}, 400)
                    return
                # Use curl to fetch the User ID from Odido API
                result = subprocess.run([
                    'curl', '-sL', '-o', '/dev/null', '-w', '%{url_effective}',
                    '-H', f'Authorization: Bearer {oauth_token}',
                    '-H', 'User-Agent: T-Mobile 5.3.28 (Android 10; 10)',
                    'https://capi.odido.nl/account/current'
                ], capture_output=True, text=True, timeout=30)
                redirect_url = result.stdout.strip()
                # Extract 12-character hex User ID from URL (case-insensitive)
                match = re.search(r'capi.odido.nl/([0-9a-fA-F]{12})', redirect_url, re.IGNORECASE)
                if match:
                    user_id = match.group(1)
                    self._send_json({"success": True, "user_id": user_id})
                else:
                    # Fallback: extract first path segment after capi.odido.nl/
                    match = re.search(r'capi.odido.nl/([^/]+)/', redirect_url, re.IGNORECASE)
                    if match and match.group(1).lower() != 'account':
                        user_id = match.group(1)
                        self._send_json({"success": True, "user_id": user_id})
                    else:
                        self._send_json({"error": "Could not extract User ID from Odido API response", "url": redirect_url}, 400)
            except Exception as e:
                self._send_json({"error": str(e)}, 500)

if __name__ == "__main__":
    print(f"Starting API server on port {PORT}...")
    init_db()

    def background_init():
        # Wait for Gluetun proxy to be ready
        print("Waiting for proxy...", flush=True)
        proxy_ready = False
        for _ in range(60):
            try:
                with socket.create_connection((f"{CONTAINER_PREFIX}gluetun", 8888), timeout=2):
                    proxy_ready = True
                    break
            except (OSError, ConnectionRefusedError):
                time.sleep(2)
        
        if proxy_ready:
            print("Proxy available. Syncing assets...", flush=True)
            try:
                ensure_assets()
            except Exception as e:
                log_structured("WARN", f"Asset sync failed: {e}", "FONTS")
        else:
            log_structured("WARN", "Proxy unavailable after 60s. Asset sync skipped.", "FONTS")

    # Start initialization in background so API is immediately available
    threading.Thread(target=background_init, daemon=True).start()
    
    # Start metrics collector thread
    t = threading.Thread(target=metrics_collector, daemon=True)
    t.start()
    
    if not os.path.exists(LOG_FILE):
        os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
        open(LOG_FILE, 'a').close()
    with ThreadingHTTPServer(("", PORT), APIHandler) as httpd:
        print(f"API server running on port {PORT}")
        httpd.serve_forever()
