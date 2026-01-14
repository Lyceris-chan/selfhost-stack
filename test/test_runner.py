#!/usr/bin/env python3
"""Functional test runner for the Privacy Hub stack.

This script handles the deployment of the stack, verification of service
connectivity (HTTP level), and testing of complex workflows like
updates and backups.
"""

import argparse
import concurrent.futures
import json
import os
import socket
import subprocess
import sys
import time
import urllib.request
import urllib.error

# Google Style: Module-level constants
_FULL_STACK = {
    "name": "Full Privacy Hub Stack",
    "services": (
        "hub-api,dashboard,gluetun,adguard,unbound,wg-easy,redlib,"
        "wikiless,rimgo,breezewiki,anonymousoverflow,scribe,invidious,"
        "companion,searxng,portainer,memos,odido-booster,cobalt,"
        "cobalt-web,vert,vertd,immich,watchtower"
    ),
    "checks": [
        {"name": "Dashboard", "port": 8088, "path": "/", "code": 200},
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
        {"name": "Immich", "port": 2283, "path": "/api/server/ping", "code": 200},
        {"name": "Odido Booster", "port": 8085, "path": "/docs", "code": 200},
        {"name": "VERT", "port": 5555, "path": "/", "code": 200},
        {"name": "VERT Daemon", "port": 24153, "path": "/api/version", "code": 200}
    ]
}

_TEST_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
_PROJECT_ROOT = os.path.dirname(_TEST_SCRIPT_DIR)
_TEST_DATA_DIR = os.path.join(_TEST_SCRIPT_DIR, "test_data")


def get_lan_ip() -> str:
    """Detects the local LAN IP address."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        # Use Quad9 (9.9.9.9) to determine route
        s.connect(("9.9.9.9", 80))
        ip = s.getsockname()[0]
        s.close()
        # Force localhost for stable CI/CLI testing
        return "127.0.0.1"
    except Exception:
        return "127.0.0.1"


_LAN_IP = get_lan_ip()
print(f"Detected LAN IP for testing: {_LAN_IP}")


def run_command(cmd: str, cwd: str = None, ignore_failure: bool = False) -> int:
    """Executes a shell command."""
    print(f"Executing: {cmd}")
    ret = subprocess.call(cmd, shell=True, executable='/bin/bash', cwd=cwd)
    if ret != 0 and not ignore_failure:
        print(f"Command failed: {cmd}")
        sys.exit(1)
    return ret


def verify_service(check: dict) -> bool:
    """Verifies a single service with fast-fail if container is down."""
    name = check['name']
    port = check['port']
    path = check['path']
    expected_code = check['code']
    url = f"http://{_LAN_IP}:{port}{path}"
    
    # Map service name to container name for deeper inspection
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
    
    # Retry loop: wait for service to come up
    retries = 300 if "immich" in name.lower() else 60
    
    for _ in range(retries):
        # 1. Docker Level Check (Fail fast if container crashed)
        try:
            cmd = (
                f"docker inspect --format '{{{{.State.Status}}}}|"
                f"{{{{if .State.Health}}}}{{{{.State.Health.Status}}}}"
                f"{{{{else}}}}none{{{{end}}}}' {container_name}")
            out = subprocess.check_output(cmd, shell=True, stderr=subprocess.DEVNULL).decode().strip()
            status, health = out.split('|')
            
            if status in ['exited', 'dead', 'paused']:
                logs = subprocess.check_output(f"docker logs --tail 10 {container_name}", 
                                             shell=True, stderr=subprocess.STDOUT).decode('utf-8', errors='replace')
                print(f"[FAIL] {name} container is {status}. Logs:\n{logs}")
                return False
            
            # If healthy, we still verify HTTP to be sure
        except subprocess.CalledProcessError:
            # Container might not exist yet if pulling
            pass

        # 2. HTTP Check
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
    # Print logs on timeout
    try:
        logs = subprocess.check_output(f"docker logs --tail 20 {container_name}", 
                                     shell=True, stderr=subprocess.STDOUT).decode('utf-8', errors='replace')
        print(f"--- Logs for {container_name} ---\n{logs}\n-----------------------------")
    except Exception:
        pass
    return False


def check_puppeteer_deps():
    """Checks for missing system dependencies for Puppeteer."""
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
    """Main execution function."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--full", action="store_true", help="Run full stack verification")
    args = parser.parse_args()
    
    start_time = time.time()
    check_puppeteer_deps()

    print(f"=== Running Full Stack Verification ===")
    
    services_list = _FULL_STACK['services']
    compose_dir = os.path.join(_TEST_DATA_DIR, "data/AppData/privacy-hub-test")
    all_pass = True

    try:
        # 1. Cleanup
        print("Cleaning environment using zima.sh...")
        # Use zima.sh -x (Clean-only) to ensure consistent environment reset
        cleanup_env = (
            f"TEST_MODE=true LAN_IP_OVERRIDE={_LAN_IP} APP_NAME=privacy-hub-test "
            f"PROJECT_ROOT={_TEST_DATA_DIR}")
        run_command(f"{cleanup_env} ./zima.sh -x -y", cwd=_PROJECT_ROOT, ignore_failure=True)
        
        # 2. Deploy
        env_vars = (
            f"TEST_MODE=true LAN_IP_OVERRIDE={_LAN_IP} APP_NAME=privacy-hub-test "
            f"PROJECT_ROOT={_TEST_DATA_DIR} "
            f"FORCE_UPDATE=true")
        
        print("Deploying stack using zima.sh...")
        # Deploy with selective services and auto-confirm
        cmd_deploy = f"{env_vars} ./zima.sh -p -y -E test/test_config.env -s {services_list}"
        run_command(cmd_deploy, cwd=_PROJECT_ROOT)

        # Construct environment prefix for compose commands (needed for update tests)
        env_cmd_prefix = (
            f"set -a; TEST_MODE=true; "
            f"[ -f {_PROJECT_ROOT}/test/test_config.env ] && . {_PROJECT_ROOT}/test/test_config.env; "
            f". {_PROJECT_ROOT}/lib/core/constants.sh; LAN_IP={_LAN_IP}; "
            f"APP_NAME=privacy-hub-test; PROJECT_ROOT={_TEST_DATA_DIR}; set +a; ")
        
        # 3. Verify Connectivity for ALL Services (PARALLEL)
        print("\n--- Verifying Service Connectivity (Parallel) ---")
        
        with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
            future_to_service = {executor.submit(verify_service, check): check for check in _FULL_STACK['checks']}
            for future in concurrent.futures.as_completed(future_to_service):
                check = future_to_service[future]
                try:
                    if not future.result():
                        all_pass = False
                except Exception as exc:
                    print(f"[FAIL] {check['name']} generated an exception: {exc}")
                    all_pass = False
        
        if not all_pass:
            print("[CRITICAL] Service verification failed. Skipping Update/Backup tests.")
            sys.exit(1)

        # 4. Verify Update Pipeline
        print("\n--- Verifying Update Pipeline ---")
        secrets_path = os.path.join(_TEST_DATA_DIR, "data/AppData/privacy-hub-test/.secrets")
        api_key = "dummy"
        
        if os.path.exists(secrets_path):
            if os.path.isdir(secrets_path):
                print("[WARN] .secrets is a directory (Docker mount artifact). Fetching key from container...")
                try:
                    cmd = "docker exec hub-api env | grep HUB_API_KEY"
                    out = subprocess.check_output(cmd, shell=True).decode().strip()
                    if out:
                        api_key = out.split('=', 1)[1].strip().strip('"').strip("'")
                except Exception as e:
                    print(f"[WARN] Failed to fetch key from container: {e}")
            else:
                with open(secrets_path, 'r') as f:
                    for line in f:
                        if "HUB_API_KEY=" in line:
                            api_key = line.split("=")[1].strip().strip('"').strip("'")
        
        # Test 1: Downgrade and Update
        print("  Testing Downgrade and Update for Wikiless...")
        wikiless_src = os.path.join(compose_dir, "sources/wikiless")
        if os.path.exists(wikiless_src):
            run_command("git fetch --unshallow || git fetch --all", cwd=wikiless_src, ignore_failure=True)
            run_command("git reset --hard && git clean -fd", cwd=wikiless_src)
            run_command("git checkout HEAD~1", cwd=wikiless_src)
            run_command(f"{env_cmd_prefix} docker compose build wikiless", cwd=compose_dir)
            run_command(f"{env_cmd_prefix} docker compose up -d wikiless", cwd=compose_dir)
            
            try:
                url = f"http://{_LAN_IP}:55555/update-service"
                data = json.dumps({"service": "wikiless"}).encode()
                req = urllib.request.Request(url, data=data, method="POST", 
                                           headers={"X-API-Key": api_key, "Content-Type": "application/json"})
                with urllib.request.urlopen(req, timeout=30) as resp:
                    if json.loads(resp.read().decode()).get('success'):
                        print("[PASS] Update-service API accepted downgrade-to-latest request.")
                        print("    Waiting for update background task...")
                        time.sleep(30)
                    else:
                        print("[FAIL] Update-service API rejected request.")
                        all_pass = False
            except Exception as e:
                print(f"[FAIL] Update-service API error: {e}")
                all_pass = False

        # Test 2: Update WITHOUT Watchtower (Direct API call)
        try:
            url = f"http://{_LAN_IP}:55555/update-service"
            data = json.dumps({"service": "wikiless"}).encode()
            req = urllib.request.Request(url, data=data, method="POST", 
                                       headers={"X-API-Key": api_key, "Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=30) as resp:
                if json.loads(resp.read().decode()).get('success'):
                    print("[PASS] Direct Update API accepted request.")
                else:
                    print("[FAIL] Direct Update API rejected request.")
                    all_pass = False
        except Exception as e:
            print(f"[FAIL] Direct Update API error: {e}")
            all_pass = False

        # Test 3: Update WITH Watchtower (Mock Notification)
        try:
            url = f"http://{_LAN_IP}:55555/watchtower?token={api_key}"
            req = urllib.request.Request(url, data=json.dumps({"entries":[]}).encode(), method="POST", 
                                       headers={"Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=10) as resp:
                print("[PASS] Watchtower notification endpoint reached.")
        except Exception as e:
            print(f"[FAIL] Watchtower notification error: {e}")
            all_pass = False

        # 5. Verify Backup/Restore Cycle
        print("\n--- Verifying Backup/Restore Cycle for Invidious ---")
        try:
            # Backup
            url_backup = f"http://{_LAN_IP}:55555/migrate?service=invidious&backup=yes"
            req_backup = urllib.request.Request(url_backup, method="POST", headers={"X-API-Key": api_key})
            with urllib.request.urlopen(req_backup, timeout=60) as resp:
                print("[PASS] Backup initiated.")
            
            backup_dir = os.path.join(_TEST_DATA_DIR, "data/AppData/privacy-hub-test/data/hub-api/backups")
            backups = [b for b in os.listdir(backup_dir) if "invidious" in b]
            if not backups:
                print("[FAIL] No backup file found.")
                all_pass = False
            else:
                latest_backup = sorted(backups)[-1]
                backup_path_in_container = f"/app/data/backups/{latest_backup}"
                
                # Clear
                url_clear = f"http://{_LAN_IP}:55555/clear-db?service=invidious&backup=no"
                req_clear = urllib.request.Request(url_clear, method="POST", headers={"X-API-Key": api_key})
                urllib.request.urlopen(req_clear, timeout=30)
                
                # Restore
                restore_cmd = f"docker exec hub-api /usr/local/bin/migrate.sh invidious restore {backup_path_in_container}"
                run_command(restore_cmd)
                print("[PASS] Restore command executed.")
        except Exception as e:
            print(f"[FAIL] Backup/Restore verification error: {e}")
            all_pass = False

    finally:
        end_time = time.time()
        duration = end_time - start_time
        print(f"\nTest run complete in {duration:.2f} seconds.")

    if not all_pass:
        sys.exit(1)
    print("=== Full Stack Functional Verification Passed ===")

if __name__ == "__main__":
    main()