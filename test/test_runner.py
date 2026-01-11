#!/usr/bin/env python3
import argparse
import subprocess
import sys
import time
import os
import urllib.request
import json

# Consolidated Full Stack Definition
FULL_STACK = {
    "name": "Full Privacy Hub Stack",
        "services": "hub-api,dashboard,gluetun,adguard,unbound,wg-easy,redlib,wikiless,rimgo,breezewiki,anonymousoverflow,scribe,invidious,companion,searxng,portainer,memos,odido-booster,cobalt,cobalt-web,vert,vertd,immich,watchtower",
    "checks": [
        {"name": "Dashboard", "url": "http://127.0.0.1:8081", "code": 200},
        {"name": "Hub API", "url": "http://127.0.0.1:55555/health", "code": 200},
        {"name": "AdGuard", "url": "http://127.0.0.1:8083", "code": 200},
        {"name": "WireGuard UI", "url": "http://127.0.0.1:51821", "code": 200}
    ]
}

TEST_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(TEST_SCRIPT_DIR)
TEST_DATA_DIR = os.path.join(TEST_SCRIPT_DIR, "test_data")

def run_command(cmd, cwd=None, ignore_failure=False):
    print(f"Executing: {cmd}")
    ret = subprocess.call(cmd, shell=True, executable='/bin/bash', cwd=cwd)
    if ret != 0 and not ignore_failure:
        print(f"Command failed: {cmd}")
        sys.exit(1)
    return ret

def verify_url(name, url, expected_code=200, retries=120):
    print(f"Verifying {name} at {url}...")
    for i in range(retries):
        try:
            code = urllib.request.urlopen(url, timeout=30).getcode()
            if code == expected_code:
                print(f"[PASS] {name} is UP (Status {code})")
                return True
        except Exception as e:
            if i == retries - 1:
                print(f"[WARN] Final retry failed with error: {e}")
            pass
        time.sleep(2)
        if i % 5 == 0:
            print(f"Waiting for {name}...")
    print(f"[FAIL] {name} is DOWN")
    return False

def verify_logs():
    log_path = os.path.join(TEST_DATA_DIR, "data/AppData/privacy-hub-test/deployment.log")
    if os.path.exists(log_path):
        print("Checking log consistency...")
        with open(log_path, 'r') as f:
            lines = f.readlines()
            if not lines:
                print("[WARN] Log file is empty.")
                return
            last_line = lines[-1]
            try:
                json.loads(last_line)
                print("[PASS] Last log line is valid JSON.")
            except:
                print(f"[FAIL] Last log line is NOT valid JSON: {last_line}")
    else:
        print(f"[WARN] Log file not found at {log_path}")

def verify_docker_logs(services_list):
    print("Verifying Docker logs for services...")
    all_clean = True
    prefix = "hub-"
    
    for service in services_list.split(','):
        service = service.strip()
        if not service or service == "dashboard": continue
        
        container_name = f"{prefix}{service}"
        print(f"  Checking {container_name} logs...")
        try:
            res = subprocess.run(['docker', 'logs', '--tail', '50', container_name], capture_output=True, text=True)
            if res.returncode == 0:
                logs = (res.stdout + res.stderr).lower()
                critical_errors = [
                    line for line in logs.split('\n') 
                    if ('critical' in line or 'fatal' in line or 'panic' in line) 
                    and 'fatal: false' not in line
                ]
                if critical_errors:
                    print(f"  [FAIL] {container_name} contains critical errors in logs!")
                    all_clean = False
                else:
                    print(f"  [PASS] {container_name} logs appear clean.")
            else:
                 print(f"  [WARN] Could not retrieve logs for {container_name}.")
        except Exception as e:
            print(f"  [WARN] Error checking logs for {service}: {e}")
            
    return all_clean

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

    check_puppeteer_deps()

    print(f"=== Running Full Stack Verification ===")
    
    services_list = FULL_STACK['services']
    compose_dir = os.path.join(TEST_DATA_DIR, "data/AppData/privacy-hub-test")
    all_pass = True

    try:
        # 1. Cleanup
        print("Cleaning environment...")
        # Force cleanup of potential zombie containers from previous runs
        run_command("docker ps -aq --filter name=hub- | xargs -r docker rm -f", ignore_failure=True)
        run_command("docker ps -aq --filter label=io.dhi.hardened=true | xargs -r docker rm -f", ignore_failure=True)
        
        if os.path.exists(os.path.join(compose_dir, "docker-compose.yml")):
             run_command("docker compose down -v || true", cwd=compose_dir)
        run_command("docker system prune -f --volumes")
        
        # 2. Deploy
        env_vars = f"APP_NAME=privacy-hub-test PROJECT_ROOT={TEST_DATA_DIR} MOCK_VERIFICATION=true"
        
        print("Generating configuration...")
        cmd_gen = f"{env_vars} ./zima.sh -p -y -E test/test_config.env -s {services_list} -G"
        run_command(cmd_gen, cwd=PROJECT_ROOT)
        
        # --- PATCH: Bypass VPN for Test Environment Screenshots ---
        print("Patching compose file to bypass VPN for screenshots...")
        compose_file = os.path.join(compose_dir, "docker-compose.yml")
        if os.path.exists(compose_file):
            with open(compose_file, "r") as f:
                lines = f.readlines()
            
            with open(compose_file, "w") as f:
                current_service = None
                in_gluetun_ports = False
                
                for line in lines:
                    stripped = line.strip()
                    
                    # Detect service
                    if line.startswith("  ") and not line.startswith("    ") and ":" in line:
                        current_service = stripped.split(":")[0]
                        in_gluetun_ports = False # Reset on new service
                    
                    # Handle Gluetun Ports (Comment them out to avoid conflicts)
                    if current_service == "gluetun":
                        if stripped.startswith("ports:"):
                            in_gluetun_ports = True
                            f.write(f"# {line}")
                            continue
                        if in_gluetun_ports:
                            if line.startswith("      -"):
                                f.write(f"# {line}")
                                continue
                            else:
                                in_gluetun_ports = False
                    
                    # Handle Service Patching
                    if "network_mode: \"service:gluetun\"" in line:
                        f.write(line.replace("network_mode: \"service:gluetun\"", "networks: [dhi-frontnet]"))
                        
                        # Inject ports based on service
                        indent = "    "
                        if current_service == "redlib":
                            f.write(f"{indent}ports: [\"127.0.0.1:8080:8081\"]\n")
                        elif current_service == "wikiless":
                            f.write(f"{indent}ports: [\"127.0.0.1:8180:8180\"]\n")
                        elif current_service == "invidious":
                            f.write(f"{indent}ports: [\"127.0.0.1:3000:3000\"]\n")
                        elif current_service == "rimgo":
                            f.write(f"{indent}ports: [\"127.0.0.1:3002:3002\"]\n")
                        elif current_service == "scribe":
                            f.write(f"{indent}ports: [\"127.0.0.1:8280:8280\"]\n")
                        elif current_service == "breezewiki":
                            f.write(f"{indent}ports: [\"127.0.0.1:8380:10416\"]\n")
                        elif current_service == "anonymousoverflow":
                            f.write(f"{indent}ports: [\"127.0.0.1:8480:8480\"]\n")
                        elif current_service == "searxng":
                            f.write(f"{indent}ports: [\"127.0.0.1:8082:8080\"]\n")
                        elif current_service == "immich-server":
                            f.write(f"{indent}ports: [\"127.0.0.1:2283:2283\"]\n")
                        elif current_service == "odido-booster":
                            f.write(f"{indent}ports: [\"127.0.0.1:8085:8085\"]\n")
                        elif current_service == "companion":
                            f.write(f"{indent}ports: [\"127.0.0.1:8282:8282\"]\n")
                        elif current_service == "cobalt":
                            f.write(f"{indent}ports: [\"127.0.0.1:9002:9000\"]\n")
                        elif current_service == "cobalt-web":
                            f.write(f"{indent}ports: [\"127.0.0.1:9001:80\"]\n")
                        elif current_service == "adguard":
                            f.write(f"{indent}ports: [\"127.0.0.1:8083:8083\", \"127.0.0.1:5353:53/udp\", \"127.0.0.1:5353:53/tcp\"]\n")
                    
                    # Fix internal connections when bypassing VPN
                    elif current_service == "wikiless" and "REDIS_URL: \"redis://127.0.0.1:6379\"" in line:
                        f.write(line.replace("127.0.0.1", "hub-wikiless_redis"))
                    elif current_service == "invidious" and "invidious-db:5432" in line and "hub-" not in line:
                        f.write(line.replace("invidious-db", "hub-invidious-db"))
                    elif current_service == "immich-server" and "DB_HOSTNAME=" in line and "hub-" not in line:
                        f.write(line.replace("DB_HOSTNAME=", "DB_HOSTNAME=hub-immich-db"))
                    elif current_service == "immich-server" and "REDIS_HOSTNAME=" in line and "hub-" not in line:
                        f.write(line.replace("REDIS_HOSTNAME=", "REDIS_HOSTNAME=hub-immich-redis"))
                    else:
                        f.write(line)
        # ----------------------------------------------------------

        print("Pulling and Building...")
        compose_cwd = os.path.join(TEST_DATA_DIR, "data/AppData/privacy-hub-test")
        # Source constants.sh to ensure port variables are available for docker-compose interpolation
        env_cmd_prefix = f"set -a; [ -f {PROJECT_ROOT}/test/test_config.env ] && . {PROJECT_ROOT}/test/test_config.env; . {PROJECT_ROOT}/lib/constants.sh; APP_NAME=privacy-hub-test; PROJECT_ROOT={TEST_DATA_DIR}; set +a; "
        
        # Explicitly build internal services
        local_builds = ["hub-api", "odido-booster", "scribe", "wikiless"]
        for svc in local_builds:
            if svc in services_list:
                print(f"Building {svc}...")
                run_command(f"{env_cmd_prefix} docker compose build {svc}", cwd=compose_cwd)

        print("Pulling other services...")
        subprocess.call(f"{env_cmd_prefix} docker compose pull", shell=True, cwd=compose_cwd)

        print("Launching stack...")
        # Use docker compose directly to preserve patched configuration
        # Use sudo -E to ensure permissions for reading root-owned env files
        cmd_deploy = f"{env_cmd_prefix} sudo -E docker compose up -d"
        run_command(cmd_deploy, cwd=compose_cwd, ignore_failure=True)

        # 3. Verify Basic Connectivity
        for check in FULL_STACK['checks']:
            if not verify_url(check['name'], check['url'], check['code']):
                all_pass = False
                
        # 4. Verify Logs
        verify_logs()
        
        # 5. Unified Puppeteer Verification (Verified + Screenshots)
        print("Waiting for containers to stabilize before UI tests...")
        time.sleep(120)
        print("Running Unified Puppeteer Verification & Screenshots...")
        if not os.path.exists(os.path.join(TEST_SCRIPT_DIR, "node_modules")):
            print("Installing test dependencies...")
            run_command("bun install", cwd=TEST_SCRIPT_DIR)
            
        try:
            run_command("bun unified_test.js", cwd=TEST_SCRIPT_DIR)
            print("[PASS] Unified UI tests passed.")
        except Exception:
            print("[FAIL] Unified UI tests failed.")
            all_pass = False

    finally:
        print("Test run complete. Check 'test/screenshots' for results.")

    if not all_pass:
        sys.exit(1)
    
    print("=== Full Stack Verification Passed ===")

if __name__ == "__main__":
    main()
