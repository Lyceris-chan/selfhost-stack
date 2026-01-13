#!/usr/bin/env python3
import argparse
import subprocess
import sys
import time
import os
import urllib.request
import json
import socket
import concurrent.futures

# Consolidated Full Stack Definition
FULL_STACK = {
    "name": "Full Privacy Hub Stack",
    "services": "hub-api,dashboard,gluetun,adguard,unbound,wg-easy,redlib,wikiless,rimgo,breezewiki,anonymousoverflow,scribe,invidious,companion,searxng,portainer,memos,odido-booster,cobalt,cobalt-web,vert,vertd,immich,watchtower",
    "checks": [
        {"name": "Dashboard", "port": 8081, "path": "/", "code": 200},
        {"name": "Hub API", "port": 55555, "path": "/health", "code": 200},
        {"name": "AdGuard", "port": 8083, "path": "/", "code": 200},
        {"name": "WireGuard UI", "port": 51821, "path": "/", "code": 200},
        {"name": "Redlib", "port": 8080, "path": "/settings", "code": 200},
        {"name": "Wikiless", "port": 8180, "path": "/", "code": 200},
        {"name": "Invidious", "port": 3000, "path": "/api/v1/stats", "code": 200},
        {"name": "Rimgo", "port": 3002, "path": "/", "code": 200},
        {"name": "Breezewiki", "port": 8380, "path": "/", "code": 200},
        {"name": "AnonymousOverflow", "port": 8480, "path": "/", "code": 200},
        {"name": "Scribe", "port": 8280, "path": "/", "code": 200},
        {"name": "Memos", "port": 5230, "path": "/", "code": 200},
        {"name": "Cobalt Web", "port": 9001, "path": "/", "code": 200},
        {"name": "Cobalt API", "port": 9002, "path": "/api/serverInfo", "code": 200},
        {"name": "SearXNG", "port": 8082, "path": "/", "code": 200},
        {"name": "Immich", "port": 2283, "path": "/api/server-info/ping", "code": 200},
        {"name": "Odido Booster", "port": 8085, "path": "/docs", "code": 200},
        {"name": "VERT", "port": 5555, "path": "/", "code": 200},
        {"name": "VERT Daemon", "port": 24153, "path": "/api/version", "code": 200}
    ]
}

TEST_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(TEST_SCRIPT_DIR)
TEST_DATA_DIR = os.path.join(TEST_SCRIPT_DIR, "test_data")

def get_lan_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except:
        return "127.0.0.1"

LAN_IP = get_lan_ip()
print(f"Detected LAN IP for testing: {LAN_IP}")

def run_command(cmd, cwd=None, ignore_failure=False):
    print(f"Executing: {cmd}")
    ret = subprocess.call(cmd, shell=True, executable='/bin/bash', cwd=cwd)
    if ret != 0 and not ignore_failure:
        print(f"Command failed: {cmd}")
        sys.exit(1)
    return ret

def verify_service(check):
    """Verify a single service with fast-fail if container is down."""
    name = check['name']
    port = check['port']
    path = check['path']
    expected_code = check['code']
    url = f"http://{LAN_IP}:{port}{path}"
    
    # Map service name to container name
    container_map = {
        "Dashboard": "hub-dashboard",
        "Hub API": "hub-api",
        "AdGuard": "hub-adguard",
        "WireGuard UI": "hub-wg-easy",
        "Redlib": "hub-redlib",
        "Wikiless": "hub-wikiless",
        "Invidious": "hub-invidious",
        "Rimgo": "hub-rimgo",
        "Breezewiki": "hub-breezewiki",
        "AnonymousOverflow": "hub-anonymousoverflow",
        "Scribe": "hub-scribe",
        "Memos": "hub-memos",
        "Cobalt Web": "hub-cobalt-web",
        "Cobalt API": "hub-cobalt",
        "SearXNG": "hub-searxng",
        "Immich": "hub-immich-server",
        "Odido Booster": "hub-odido-booster",
        "VERT": "hub-vert",
        "VERT Daemon": "hub-vertd"
    }
    
    container_name = container_map.get(name, f"hub-{name.lower().replace(' ', '-')}")
    
    print(f"Verifying {name} ({container_name}) at {url}...")
    
    # Retry loop: 20 attempts * 1s sleep
    # Increase for heavy services
    retries = 90 if "immich" in name.lower() else 30
    
    for i in range(retries):
        # 1. Docker Level Check
        try:
            cmd = f"docker inspect --format '{{{{.State.Status}}}}|{{{{if .State.Health}}}}{{{{.State.Health.Status}}}}{{{{else}}}}none{{{{end}}}}' {container_name}"
            out = subprocess.check_output(cmd, shell=True, stderr=subprocess.DEVNULL).decode().strip()
            status, health = out.split('|')
            
            if status in ['exited', 'dead', 'paused']:
                logs = subprocess.check_output(f"docker logs --tail 10 {container_name}", shell=True, stderr=subprocess.STDOUT).decode('utf-8', errors='replace')
                print(f"[FAIL] {name} container is {status}. Logs:\n{logs}")
                return False
            
            if health == 'healthy':
                # Container says it's healthy, trust it but confirm port is open?
                # Sometimes healthy means internal app is up but port mapping/proxy might lag slightly.
                # Let's try HTTP once fast.
                try:
                    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
                    with urllib.request.urlopen(req, timeout=2) as response:
                        if response.getcode() == expected_code:
                            print(f"[PASS] {name} is UP (Healthy + HTTP {expected_code})")
                            return True
                except:
                    pass # Fall through to wait
            
            if health == 'unhealthy':
                 logs = subprocess.check_output(f"docker logs --tail 10 {container_name}", shell=True, stderr=subprocess.STDOUT).decode('utf-8', errors='replace')
                 print(f"[FAIL] {name} is UNHEALTHY. Logs:\n{logs}")
                 return False

        except subprocess.CalledProcessError:
            # Container might not exist yet if pulling
            pass

        # 2. HTTP Fallback Check
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
            with urllib.request.urlopen(req, timeout=3) as response:
                code = response.getcode()
                if code == expected_code:
                    print(f"[PASS] {name} is UP (Status {code})")
                    return True
        except urllib.error.HTTPError as e:
            if e.code == expected_code:
                print(f"[PASS] {name} is UP (Status {e.code})")
                return True
        except Exception:
            pass
        
        time.sleep(1)
        
    print(f"[FAIL] {name} is DOWN (Timed out)")
    # Print logs on timeout too
    try:
        logs = subprocess.check_output(f"docker logs --tail 10 {container_name}", shell=True, stderr=subprocess.STDOUT).decode('utf-8', errors='replace')
        print(f"--- Logs for {container_name} ---\n{logs}\n-----------------------------")
    except:
        pass
    return False

def verify_logs():
    log_path = os.path.join(TEST_DATA_DIR, "data/AppData/privacy-hub-test/deployment.log")
    if os.path.exists(log_path):
        print("Checking log consistency and humanization...")
        with open(log_path, 'r') as f:
            lines = f.readlines()
            if not lines:
                print("[WARN] Log file is empty.")
                return
            
            humanized_found = False
            for line in lines[-20:]:
                try:
                    entry = json.loads(line)
                    msg = entry.get('message', '')
                    if "synchronized" in msg or "initiated" in msg or "retrieved" in msg or "updated" in msg:
                        humanized_found = True
                except:
                    pass
            
            if humanized_found:
                print("[PASS] Humanized log entries detected.")
            else:
                print("[WARN] No clearly humanized log entries found in recent logs.")
    else:
        print(f"[WARN] Log file not found at {log_path}")

def check_puppeteer_deps():
    print("Checking Puppeteer dependencies...")
    deps = [
        "libatk1.0-0", "libatk-bridge2.0-0", "libcups2", "libdrm2", 
        "libxkbcommon0", "libxcomposite1", "libxdamage1", "libxrandr2", 
        "libgbm1", "libpango-1.0-0", "libcairo2", "libasound2"
    ]
    missing = []
    for dep in deps:
        found = False
        for variant in [dep, f"{dep}t64"]:
            res = subprocess.run(f"dpkg -l {variant} >/dev/null 2>&1", shell=True)
            if res.returncode == 0:
                found = True
                break
        if not found:
            missing.append(dep)
    
    if missing:
        print("\n[WARN] Missing system packages required for Puppeteer UI tests.")
        return False
    return True

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--full", action="store_true", help="Run full stack verification")
    args = parser.parse_args()
    
    start_time = time.time()
    check_puppeteer_deps()

    print(f"=== Running Full Stack Verification ===")
    
    services_list = FULL_STACK['services']
    compose_dir = os.path.join(TEST_DATA_DIR, "data/AppData/privacy-hub-test")
    all_pass = True

    try:
        # 1. Cleanup
        print("Cleaning environment...")
        # Broad cleanup of stack-related containers
        cleanup_filters = ["name=hub-", "name=privacy-hub", "name=odido", "name=wikiless", "name=redlib", "name=invidious", "name=scribe", "name=gluetun"]
        for f in cleanup_filters:
            run_command(f"docker ps -aq --filter {f} | xargs -r docker rm -f", ignore_failure=True)
        
        if os.path.exists(os.path.join(compose_dir, "docker-compose.yml")):
             run_command("docker compose down -v --remove-orphans || true", cwd=compose_dir)
        
        # Force remove networks
        run_command("docker network ls --format '{{.Name}}' | grep privacy-hub | xargs -r docker network rm || true", ignore_failure=True)
        run_command("docker network prune -f", ignore_failure=True)
        
        run_command("docker system prune -f --volumes")
        
        # Check port 8085 (Odido) specifically as it caused issues
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        if s.connect_ex(('127.0.0.1', 8085)) == 0:
            print("[WARN] Port 8085 is still in use! Attempting to find culprit...")
            run_command("fuser -k 8085/tcp || lsof -ti :8085 | xargs -r kill -9 || true", ignore_failure=True)
            run_command("docker ps --format '{{.ID}}' --filter publish=8085 | xargs -r docker rm -f", ignore_failure=True)
        s.close()
        
        # 2. Deploy
        env_vars = f"TEST_MODE=true LAN_IP_OVERRIDE={LAN_IP} APP_NAME=privacy-hub-test PROJECT_ROOT={TEST_DATA_DIR} MOCK_VERIFICATION=true ADMIN_PASS_RAW=admin123 VPN_PASS_RAW=vpn123 FORCE_UPDATE=true"
        
        print("Generating configuration...")
        cmd_gen = f"{env_vars} ./zima.sh -p -y -E test/test_config.env -s {services_list} -G"
        run_command(cmd_gen, cwd=PROJECT_ROOT)
        
        print("Pulling and Building...")
        compose_cwd = os.path.join(TEST_DATA_DIR, "data/AppData/privacy-hub-test")
        env_cmd_prefix = f"set -a; TEST_MODE=true; [ -f {PROJECT_ROOT}/test/test_config.env ] && . {PROJECT_ROOT}/test/test_config.env; . {PROJECT_ROOT}/lib/core/constants.sh; LAN_IP={LAN_IP}; APP_NAME=privacy-hub-test; PROJECT_ROOT={TEST_DATA_DIR}; set +a; "
        
        run_command(f"{env_cmd_prefix} docker compose build --no-cache hub-api odido-booster scribe wikiless", cwd=compose_cwd)
        run_command(f"{env_cmd_prefix} docker compose pull", cwd=compose_cwd)

        print("Launching stack...")
        run_command(f"{env_cmd_prefix} sudo -E docker compose up -d", cwd=compose_cwd, ignore_failure=True)

        # 3. Verify Connectivity for ALL Services (PARALLEL)
        print("\n--- Verifying Service Connectivity (Parallel) ---")
        
        with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
            future_to_service = {executor.submit(verify_service, check): check for check in FULL_STACK['checks']}
            for future in concurrent.futures.as_completed(future_to_service):
                check = future_to_service[future]
                try:
                    if not future.result():
                        all_pass = False
                except Exception as exc:
                    print(f"[FAIL] {check['name']} generated an exception: {exc}")
                    all_pass = False
                
        # 4. Verify Update Pipeline (With and Without Watchtower)
        print("\n--- Verifying Update Pipeline ---")

        secrets_path = os.path.join(TEST_DATA_DIR, "data/AppData/privacy-hub-test/.secrets")
        api_key = "dummy"
        if os.path.exists(secrets_path):
            with open(secrets_path, 'r') as f:
                for line in f:
                    if "HUB_API_KEY=" in line:
                        api_key = line.split("=")[1].strip().strip('"').strip("'")
        
        # Test Downgrade and Update
        print("  Testing Downgrade and Update for Wikiless...")
        wikiless_src = os.path.join(compose_dir, "sources/wikiless")
        if os.path.exists(wikiless_src):
            print("    Fetching history for Wikiless...")
            # Fix for "pathspec 'HEAD~1' did not match"
            run_command("git fetch --unshallow || git fetch --all", cwd=wikiless_src, ignore_failure=True)
            
            print("    Downgrading Wikiless source...")
            run_command("git reset --hard && git clean -fd", cwd=wikiless_src)
            run_command("git checkout HEAD~1", cwd=wikiless_src)
            print("    Rebuilding Wikiless with older source...")
            run_command(f"{env_cmd_prefix} docker compose build wikiless", cwd=compose_cwd)
            run_command(f"{env_cmd_prefix} docker compose up -d wikiless", cwd=compose_cwd)
            
            # Now trigger update
            print("    Triggering update via API...")
            try:
                url = f"http://{LAN_IP}:55555/update-service"
                data = json.dumps({"service": "wikiless"}).encode()
                req = urllib.request.Request(url, data=data, method="POST", headers={"X-API-Key": api_key, "Content-Type": "application/json"})
                with urllib.request.urlopen(req, timeout=30) as resp:
                    if json.loads(resp.read().decode()).get('success'):
                        print("[PASS] Update-service API accepted downgrade-to-latest request.")
                        print("    Waiting for update background task...")
                        time.sleep(30) 
                        # Verify it's back to HEAD
                        # res = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=wikiless_src).decode().strip()
                    else:
                        print("[FAIL] Update-service API rejected request.")
                        all_pass = False
            except Exception as e:
                print(f"[FAIL] Update-service API error: {e}")
                all_pass = False

        # Update WITHOUT Watchtower (Direct API call)
        print("  Testing update WITHOUT Watchtower (API call to /update-service)...")
        try:
            url = f"http://{LAN_IP}:55555/update-service"
            data = json.dumps({"service": "wikiless"}).encode()
            req = urllib.request.Request(url, data=data, method="POST", headers={"X-API-Key": api_key, "Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=30) as resp:
                if json.loads(resp.read().decode()).get('success'):
                    print("[PASS] Update-service API accepted request.")
                else:
                    print("[FAIL] Update-service API rejected request.")
                    all_pass = False
        except Exception as e:
            print(f"[FAIL] Update-service API error: {e}")
            all_pass = False

        # Update WITH Watchtower (Mock Notification)
        print("  Testing update WITH Watchtower (Mock Notification)...")
        try:
            url = f"http://{LAN_IP}:55555/watchtower?token={api_key}"
            req = urllib.request.Request(url, data=json.dumps({"entries":[]}).encode(), method="POST", headers={"Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=10) as resp:
                print("[PASS] Watchtower notification endpoint reached.")
        except Exception as e:
            print(f"[FAIL] Watchtower notification error: {e}")
            all_pass = False

        # 5. Verify Backup/Restore Cycle
        print("\n--- Verifying Backup/Restore Cycle for Invidious ---")
        try:
            # 1. Backup
            url_backup = f"http://{LAN_IP}:55555/migrate?service=invidious&backup=yes"
            req_backup = urllib.request.Request(url_backup, method="POST", headers={"X-API-Key": api_key})
            with urllib.request.urlopen(req_backup, timeout=60) as resp:
                print("[PASS] Backup initiated.")
            
            backup_dir = os.path.join(TEST_DATA_DIR, "data/AppData/privacy-hub-test/data/hub-api/backups")
            backups = [b for b in os.listdir(backup_dir) if "invidious" in b]
            if not backups:
                print("[FAIL] No backup file found.")
                all_pass = False
            else:
                latest_backup = sorted(backups)[-1]
                backup_path_in_container = f"/app/data/backups/{latest_backup}"
                
                # 2. Clear
                print("  Clearing DB...")
                url_clear = f"http://{LAN_IP}:55555/clear-db?service=invidious&backup=no"
                req_clear = urllib.request.Request(url_clear, method="POST", headers={"X-API-Key": api_key})
                urllib.request.urlopen(req_clear, timeout=30)
                
                # 3. Restore
                print(f"  Restoring from {latest_backup}...")
                restore_cmd = f"docker exec hub-api /usr/local/bin/migrate.sh invidious restore {backup_path_in_container}"
                run_command(restore_cmd)
                print("[PASS] Restore command executed.")
        except Exception as e:
            print(f"[FAIL] Backup/Restore verification error: {e}")
            all_pass = False

        # 6. Verify Logs
        verify_logs()
        
        # 7. UI Tests & Playback
        print("\n--- Running UI Audit ---")
        os.environ['LAN_IP'] = LAN_IP
        run_command(f"LAN_IP={LAN_IP} node verify_ui.js", cwd=TEST_SCRIPT_DIR)

    finally:
        end_time = time.time()
        duration = end_time - start_time
        print(f"\nTest run complete in {duration:.2f} seconds.")
        print("Check 'test/screenshots' for results.")

    if not all_pass:
        sys.exit(1)
    print("=== Full Stack Verification Passed ===")

if __name__ == "__main__":
    main()
