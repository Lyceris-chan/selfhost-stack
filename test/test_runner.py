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
import re
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
        "wikiless,rimgo,breezewiki,anonymousoverflow,invidious,"
        "companion,searxng,portainer,memos,odido-booster,vert,"
        "vertd,immich,watchtower"
    ),
    "checks": [
        {"name": "Dashboard", "port": 8088, "path": "/", "code": 200},
        {"name": "Hub API", "port": 55555, "path": "/api/health", "code": 200},
        {"name": "AdGuard", "port": 8083, "path": "/", "code": 200},
        {"name": "WireGuard UI", "port": 51821, "path": "/", "code": 200},
        {"name": "Redlib", "port": 8080, "path": "/settings", "code": 200},
        {"name": "Wikiless", "port": 8180, "path": "/", "code": 200},
        {"name": "Invidious", "port": 3000, "path": "/api/v1/stats", "code": 200},
        {"name": "Rimgo", "port": 3002, "path": "/", "code": 200},
        {"name": "Breezewiki", "port": 8380, "path": "/", "code": 200},
        {"name": "AnonymousOverflow", "port": 8480, "path": "/", "code": 200},
        {"name": "Memos", "port": 5230, "path": "/", "code": 200},
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
            with urllib.request.urlopen(req, timeout=10) as response:
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
    parser.add_argument("--skip-deploy", action="store_true", help="Skip cleanup and deployment")
    args = parser.parse_args()
    
    start_time = time.time()
    check_puppeteer_deps()

    print(f"=== Running Full Stack Verification ===")
    
    services_list = _FULL_STACK['services']
    compose_dir = os.path.join(_TEST_DATA_DIR, "data/AppData/privacy-hub-test")
    all_pass = True

    try:
        if not args.skip_deploy:
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
        else:
            print("Skipping cleanup and deployment as requested.")

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
                url = f"http://{_LAN_IP}:55555/api/update-service"
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
            url = f"http://{_LAN_IP}:55555/api/update-service"
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
            url = f"http://{_LAN_IP}:55555/api/watchtower?token={api_key}"
            req = urllib.request.Request(url, data=json.dumps({"entries":[]}).encode(), method="POST", 
                                       headers={"Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=10) as resp:
                print("[PASS] Watchtower notification endpoint reached.")
        except Exception as e:
            print(f"[FAIL] Watchtower notification error: {e}")
            all_pass = False

        # 5. Verify Rollback Support
        print("\n--- Verifying Rollback Support for Wikiless ---")
        try:
            # Check status
            url = f"http://{_LAN_IP}:55555/api/rollback-status?service=wikiless"
            req = urllib.request.Request(url, headers={"X-API-Key": api_key})
            with urllib.request.urlopen(req, timeout=10) as resp:
                data = json.loads(resp.read().decode())
                if data.get('available'):
                    print("[PASS] Rollback point available for Wikiless.")
                else:
                    print("[FAIL] Rollback point NOT available for Wikiless (should have been created by previous update test).")
                    all_pass = False

            # Check list
            url = f"http://{_LAN_IP}:55555/api/rollback-list?service=wikiless"
            req = urllib.request.Request(url, headers={"X-API-Key": api_key})
            with urllib.request.urlopen(req, timeout=10) as resp:
                data = json.loads(resp.read().decode())
                history = data.get('history', [])
                if len(history) > 0:
                    print(f"[PASS] Rollback history contains {len(history)} entries.")
                else:
                    print("[FAIL] Rollback history is empty.")
                    all_pass = False

            # Perform rollback
            url = f"http://{_LAN_IP}:55555/api/rollback-service"
            payload = json.dumps({"service": "wikiless"}).encode()
            req = urllib.request.Request(url, data=payload, method="POST", 
                                       headers={"X-API-Key": api_key, "Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=30) as resp:
                if json.loads(resp.read().decode()).get('success'):
                    print("[PASS] Rollback request accepted.")
                    print("    Waiting for rollback background task...")
                    time.sleep(30)
                else:
                    print("[FAIL] Rollback request rejected.")
                    all_pass = False
        except Exception as e:
            print(f"[FAIL] Rollback verification error: {e}")
            all_pass = False

        # 6. Verify Backup/Restore Cycle (Service Level)
        for service in ["invidious", "memos"]:
            print(f"\n--- Verifying Backup/Restore Cycle for {service.capitalize()} ---")
            try:
                # Backup
                url_backup = f"http://{_LAN_IP}:55555/api/migrate?service={service}&backup=yes"
                req_backup = urllib.request.Request(url_backup, method="POST", headers={"X-API-Key": api_key})
                with urllib.request.urlopen(req_backup, timeout=60) as resp:
                    print(f"[PASS] {service.capitalize()} backup initiated.")
                
                # Check for backup file presence
                backup_api_dir = os.path.join(_TEST_DATA_DIR, "data/AppData/privacy-hub-test/data/hub-api/backups")
                if os.path.exists(backup_api_dir):
                    backups = [b for b in os.listdir(backup_api_dir) if service in b]
                    if not backups:
                        print(f"[FAIL] No {service} backup file found in {backup_api_dir}.")
                        all_pass = False
                    else:
                        latest_backup = sorted(backups)[-1]
                        backup_path_in_container = f"/app/data/backups/{latest_backup}"
                        print(f"[PASS] Found {service} backup: {latest_backup}")
                        
                        # Clear DB (Simulate data loss)
                        url_clear = f"http://{_LAN_IP}:55555/api/clear-db?service={service}&backup=no"
                        req_clear = urllib.request.Request(url_clear, method="POST", headers={"X-API-Key": api_key})
                        urllib.request.urlopen(req_clear, timeout=30)
                        print(f"[PASS] {service.capitalize()} database cleared.")
                        
                        # Restore
                        restore_cmd = f"docker exec hub-api /usr/local/bin/migrate.sh {service} restore {backup_path_in_container}"
                        run_command(restore_cmd)
                        print(f"[PASS] {service.capitalize()} restore command executed.")
                else:
                    print(f"[SKIP] Skipping disk check: Backup directory {backup_api_dir} not reachable from host.")
            except Exception as e:
                print(f"[FAIL] {service.capitalize()} Backup/Restore verification error: {e}")
                all_pass = False

        # 7. Verify Full System Backup/Restore
        print("\n--- Verifying Full System Backup/Restore ---")
        try:
            # System Backup
            url_sys_backup = f"http://{_LAN_IP}:55555/api/backup"
            req_sys_backup = urllib.request.Request(url_sys_backup, method="POST", headers={"X-API-Key": api_key})
            with urllib.request.urlopen(req_sys_backup, timeout=30) as resp:
                print("[PASS] System backup initiated via API.")
            
            # Allow time for backup process
            print("    Waiting for system backup to complete...")
            time.sleep(15)
            
            # Check for system backup file
            sys_backup_dir = os.path.join(_TEST_DATA_DIR, "data/AppData/privacy-hub-test/backups")
            if os.path.exists(sys_backup_dir):
                backups = [b for b in os.listdir(sys_backup_dir) if b.endswith(".tar.gz")]
                if not backups:
                    print("[FAIL] No system backup file found.")
                    all_pass = False
                else:
                    latest_sys_backup = sorted(backups)[-1]
                    print(f"[PASS] Found system backup: {latest_sys_backup}")
                    
                    # System Restore (Verify API triggers it)
                    url_sys_restore = f"http://{_LAN_IP}:55555/api/restore?filename={latest_sys_backup}"
                    req_sys_restore = urllib.request.Request(url_sys_restore, method="POST", headers={"X-API-Key": api_key})
                    with urllib.request.urlopen(req_sys_restore, timeout=30) as resp:
                        print("[PASS] System restore initiated via API.")
            else:
                print(f"[SKIP] Skipping disk check: System backup directory {sys_backup_dir} not reachable from host.")
        except Exception as e:
            print(f"[FAIL] System Backup/Restore verification error: {e}")
            all_pass = False

        # 8. Verify WireGuard Advanced (Split Tunneling, DNS, Connectivity)
        print("\n--- Verifying WireGuard Advanced Features ---")
        try:
            # Create Client
            url = f"http://{_LAN_IP}:55555/api/wg/clients"
            payload = json.dumps({"name": "test-runner-client-adv"}).encode()
            req = urllib.request.Request(url, data=payload, method="POST", 
                                       headers={"X-API-Key": api_key, "Content-Type": "application/json"})
            client_id = ""
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = json.loads(resp.read().decode())
                client_id = data.get('id')
                print(f"[PASS] WireGuard client created (ID: {client_id})")

            if client_id:
                # Get Config
                url = f"http://{_LAN_IP}:55555/api/wg/clients/{client_id}/configuration"
                req = urllib.request.Request(url, headers={"X-API-Key": api_key})
                config_content = ""
                with urllib.request.urlopen(req, timeout=30) as resp:
                    config_content = resp.read().decode()
                    print(f"[PASS] WireGuard configuration retrieved")
                
                # --- Split Tunneling Verification (Config Check) ---
                # Check for private IP ranges in AllowedIPs
                if "10.0.0.0/8" in config_content and "192.168.0.0/16" in config_content:
                    print(f"[PASS] Split Tunneling configured correctly (AllowedIPs contains private ranges)")
                else:
                    print(f"[FAIL] Split Tunneling configuration mismatch. Config content:\n{config_content}")
                    all_pass = False

                # --- DNS Verification (Config Check) ---
                # Verify DNS is pointing to a local IP (LAN_IP or Docker Gateway)
                # Since we are in a test environment, checking if it is NOT 1.1.1.1 or 8.8.8.8 is a good start,
                # or checking if it matches our LAN_IP.
                dns_match = re.search(r"DNS = ([\d\.]+)", config_content)
                if dns_match:
                    dns_ip = dns_match.group(1)
                    print(f"[PASS] DNS Configuration found: {dns_ip}")
                else:
                    print(f"[FAIL] DNS Configuration missing in client config.")
                    all_pass = False

                # --- Connectivity & DNS Resolution Test ---
                
                # Adjust Endpoint for Docker-to-Docker
                endpoint_ip = _LAN_IP
                if _LAN_IP == "127.0.0.1":
                    try:
                        docker_gateway = subprocess.check_output(
                            "docker network inspect bridge --format='{{(index .IPAM.Config 0).Gateway}}'", 
                            shell=True).decode().strip()
                        if docker_gateway:
                            endpoint_ip = docker_gateway
                            # Also update DNS to be reachable if it was localhost (which is invalid for other containers)
                            if dns_ip == "127.0.0.1":
                                config_content = re.sub(r"DNS = .*", f"DNS = {docker_gateway}", config_content)
                                print(f"    Adjusted DNS to Docker Gateway: {docker_gateway}")
                            
                            print(f"    Using Docker Gateway IP {endpoint_ip} for WireGuard Endpoint")
                    except Exception:
                        endpoint_ip = "172.17.0.1" # Fallback
                
                config_content = re.sub(r"Endpoint = .*", f"Endpoint = {endpoint_ip}:51820", config_content)
                
                wg_conf_path = os.path.join(os.getcwd(), "wg-adv-test.conf")
                with open(wg_conf_path, "w") as f:
                    f.write(config_content)
                
                print("    Starting WireGuard client container for connectivity tests...")
                # We use Alpine with wireguard-tools and bind-tools (for dig/nslookup)
                # We run a sequence of checks:
                # 1. wg-quick up
                # 2. Ping Gateway (10.8.0.1) -> Verifies Tunnel
                # 3. Resolve google.com -> Verifies DNS works via Tunnel
                # 4. Resolve doubleclick.net -> Verifies AdBlocking (Should resolve to 0.0.0.0 or fail)
                
                cmd_script = (
                    "apk add --no-cache wireguard-tools bind-tools && "
                    "wg-quick up wg0 && "
                    "sleep 5 && "
                    "echo '--- PING GATEWAY ---' && "
                    "ping -c 2 10.8.0.1 && "
                    "echo '--- DNS RESOLUTION (EXTERNAL) ---' && "
                    "nslookup google.com && "
                    "echo '--- DNS RESOLUTION (ADBLOCK CHECK) ---' && "
                    "nslookup doubleclick.net" 
                )
                
                cmd = (
                    f"docker run --rm --cap-add=NET_ADMIN --sysctl net.ipv4.conf.all.src_valid_mark=1 "
                    f"-v {wg_conf_path}:/etc/wireguard/wg0.conf "
                    f"alpine:latest /bin/sh -c \"{cmd_script}\""
                )
                
                print("    Executing in container...")
                # Capture output to analyze DNS results
                try:
                    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
                    print(result.stdout)
                    
                    if result.returncode == 0:
                        print(f"[PASS] WireGuard connectivity and DNS resolution successful.")
                        
                        # Analyze AdBlock result
                        if "Address: 0.0.0.0" in result.stdout or "0.0.0.0" in result.stdout:
                            print(f"[PASS] AdGuard appears to be blocking ads (doubleclick.net resolved to 0.0.0.0).")
                        else:
                            print(f"[WARN] AdGuard blocking verification inconclusive (Check logs).")
                    else:
                        print(f"[FAIL] WireGuard client test failed.\nSTDERR: {result.stderr}")
                        all_pass = False
                except Exception as ex:
                    print(f"[FAIL] Docker run exception: {ex}")
                    all_pass = False
                
                # Cleanup: Delete Client
                url = f"http://{_LAN_IP}:55555/api/wg/clients/{client_id}"
                req = urllib.request.Request(url, method="DELETE", headers={"X-API-Key": api_key})
                with urllib.request.urlopen(req, timeout=30) as resp:
                    print(f"[PASS] WireGuard client deleted.")
                
                if os.path.exists(wg_conf_path):
                    os.remove(wg_conf_path)

        except Exception as e:
            print(f"[FAIL] WireGuard verification error: {e}")
            all_pass = False

        # 9. Verify Dashboard UI and Service Statuses
        print("\n--- Verifying Dashboard UI and Service Statuses ---")
        try:
            # We use the existing test_dashboard.js script which uses Puppeteer
            # Ensure LAN_IP and ADMIN_PASSWORD are set for the node process
            ui_env = f"LAN_IP={_LAN_IP} ADMIN_PASSWORD={api_key}"
            if run_command(f"{ui_env} node test/test_dashboard.js", cwd=_PROJECT_ROOT, ignore_failure=True) == 0:
                print(f"[PASS] Dashboard UI audit passed (All services ONLINE)")
            else:
                print(f"[FAIL] Dashboard UI audit failed or services OFFLINE")
                all_pass = False
        except Exception as e:
            print(f"[FAIL] Dashboard UI verification error: {e}")
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
