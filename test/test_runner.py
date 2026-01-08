#!/usr/bin/env python3
import argparse
import subprocess
import sys
import time
import os
import urllib.request
import json

# Define Stages
STAGES = {
    1: {
        "name": "Core Infrastructure & Networking",
        "services": "hub-api,dashboard,gluetun,adguard,unbound,wg-easy",
        "checks": [
            {"name": "Dashboard", "url": "http://127.0.0.1:8081", "code": 200},
            {"name": "Hub API", "url": "http://127.0.0.1:55555/status", "code": 200},
            {"name": "AdGuard", "url": "http://127.0.0.1:8083", "code": 200},
            {"name": "WireGuard UI", "url": "http://127.0.0.1:51821", "code": 200}
        ]
    },
    2: {
        "name": "Standard Privacy Frontends",
        "services": "redlib,gluetun,wikiless,rimgo,breezewiki,anonymousoverflow,scribe,wg-easy",
        "checks": [
            {"name": "Redlib", "url": "http://127.0.0.1:8080/settings", "code": 200},
            {"name": "Wikiless", "url": "http://127.0.0.1:8180", "code": 200},
            {"name": "Rimgo", "url": "http://127.0.0.1:3002", "code": 200},
            {"name": "BreezeWiki", "url": "http://127.0.0.1:8380", "code": 200},
            {"name": "AnonOverflow", "url": "http://127.0.0.1:8480", "code": 200},
            {"name": "Scribe", "url": "http://127.0.0.1:8280", "code": 200}
        ]
    },
    3: {
        "name": "Invidious & Search Stack",
        "services": "invidious,invidious-db,companion,gluetun,searxng,searxng-redis,wg-easy",
        "checks": [
            {"name": "Invidious", "url": "http://127.0.0.1:3000/api/v1/stats", "code": 200},
            {"name": "SearXNG", "url": "http://127.0.0.1:8082", "code": 200}
        ]
    },
    4: {
        "name": "Management & Utilities",
        "services": "portainer,memos,gluetun,odido-booster,wg-easy",
        "checks": [
             {"name": "Portainer", "url": "http://127.0.0.1:9000", "code": 200},
             {"name": "Memos", "url": "http://127.0.0.1:5230", "code": 200},
             {"name": "Odido Booster", "url": "http://127.0.0.1:8085/docs", "code": 200}
        ]
    },
    5: {
        "name": "Media & Downloads",
        "services": "cobalt,gluetun,vert,vertd,wg-easy",
        "checks": [
             {"name": "Cobalt", "url": "http://127.0.0.1:9001", "code": 200},
             {"name": "VERT", "url": "http://127.0.0.1:5555", "code": 200},
             {"name": "VERTd", "url": "http://127.0.0.1:24153/api/version", "code": 200}
        ]
    },
    6: {
        "name": "Heavy Media (Immich)",
        "services": "immich-server,immich-db,immich-redis,immich-machine-learning,gluetun,wg-easy",
        "checks": [
             {"name": "Immich", "url": "http://127.0.0.1:2283", "code": 200}
        ]
    }
}

# Dynamically determine project root and test data paths
TEST_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(TEST_SCRIPT_DIR)
TEST_DATA_DIR = os.path.join(TEST_SCRIPT_DIR, "test_data")

def run_command(cmd, cwd=None):
    print(f"Executing: {cmd}")
    ret = subprocess.call(cmd, shell=True, cwd=cwd)
    if ret != 0:
        print(f"Command failed: {cmd}")
        sys.exit(1)

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
    # Helper to inspect the deployment log
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
                # We don't fail the stage for this yet, just warn
    else:
        print(f"[WARN] Log file not found at {log_path}")

def verify_docker_logs(services_list):
    print("Verifying Docker logs for services...")
    all_clean = True
    # Identify container prefix from environment (consistent with server.py and zima.sh)
    slot = os.environ.get('SLOT', 'a')
    prefix = f"dhi-{slot}-"
    
    for service in services_list.split(','):
        service = service.strip()
        if not service or service == "dashboard": continue
        
        container_name = f"{prefix}{service}"
        print(f"  Checking {container_name} logs...")
        try:
            res = subprocess.run(['docker', 'logs', '--tail', '50', container_name], capture_output=True, text=True)
            if res.returncode == 0:
                # Combine stdout and stderr for checking
                logs = (res.stdout + res.stderr).lower()
                critical_errors = [line for line in logs.split('\n') if 'critical' in line or 'fatal' in line or 'panic' in line]
                if critical_errors:
                    print(f"  [FAIL] {container_name} contains critical errors in logs!")
                    for err in critical_errors[:3]:
                        print(f"    -> {err}")
                    print(f"--- Full Log Tail for {container_name} ---")
                    print(res.stdout)
                    print(res.stderr)
                    print("------------------------------------------")
                    all_clean = False
                else:
                    print(f"  [PASS] {container_name} logs appear clean.")
                    # Optional: print logs if it was a service that failed URL check?
                    # For now, let's just print BreezeWiki logs specifically if we are in stage 2 and it failed
                    if "breezewiki" in container_name:
                         print(f"--- Log Tail for {container_name} (Debug) ---")
                         print(res.stdout)
                         print(res.stderr)
                         print("---------------------------------------------")
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
        # Check both the standard name and the t64 variant used in Ubuntu 24.04+
        found = False
        for variant in [dep, f"{dep}t64"]:
            res = subprocess.run(f"dpkg -l {variant} >/dev/null 2>&1", shell=True)
            if res.returncode == 0:
                found = True
                break
        if not found:
            missing.append(dep)
    
    if missing:
        print("\n[WARN] Missing system packages required for Puppeteer UI tests:")
        print(f"       {', '.join(missing)}")
        print("       Run: sudo apt-get update && sudo apt-get install -y <missing-packages>")
        print("       (Note: You may need to append 't64' to some package names on newer Ubuntu versions)\n")
        return False
    return True

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--stage", type=int, required=True)
    args = parser.parse_args()

    # Pre-flight check for Puppeteer deps
    check_puppeteer_deps()

    stage_conf = STAGES.get(args.stage)
    if not stage_conf:
        print(f"Stage {args.stage} not found.")
        sys.exit(1)

    print(f"=== Running Stage {args.stage}: {stage_conf['name']} ===")
    
    # Ensure Dashboard and Hub API are included for integration testing
    services_list = stage_conf['services']
    if "dashboard" not in services_list:
        services_list += ",dashboard"
    if "hub-api" not in services_list:
        services_list += ",hub-api"
        
    compose_dir = os.path.join(TEST_DATA_DIR, "data/AppData/privacy-hub-test")
    all_pass = True

    try:
        # 1. Cleanup Pre-Flight
        print("Cleaning environment (Pre-flight)...")
        if os.path.exists(os.path.join(compose_dir, "docker-compose.yml")):
             run_command("docker compose down -v || true", cwd=compose_dir)
        else:
             print("No previous compose file found, skipping cleanup.")
        
        # Ensure we start with a clean slate
        run_command("docker system prune -f --volumes")
        
        # 2. Deploy
        # Note: We must ensure test_config.env path is correct relative to execution
        env_vars = f"APP_NAME=privacy-hub-test PROJECT_ROOT={TEST_DATA_DIR}"
        
        # Step 2a: Generate Config Only
        print("Generating configuration...")
        cmd_gen = f"{env_vars} ./zima.sh -p -y -E test/test_config.env -s {services_list} -G"
        run_command(cmd_gen, cwd=PROJECT_ROOT)
        
        # Step 2b: Sequential Build with Pruning
        print("Building services sequentially to optimize storage...")
        compose_cwd = os.path.join(TEST_DATA_DIR, "data/AppData/privacy-hub-test")
        env_cmd_prefix = f"set -a; [ -f {PROJECT_ROOT}/test/test_config.env ] && . {PROJECT_ROOT}/test/test_config.env; APP_NAME=privacy-hub-test; PROJECT_ROOT={TEST_DATA_DIR}; set +a; "
        
        # Explicitly rebuild BreezeWiki to pick up Racket 8.15 update (Alpine 3.21)
        # We skip others to avoid Docker Hub rate limits
        if "breezewiki" in services_list:
            print("Rebuilding BreezeWiki...")
            run_command(f"{env_cmd_prefix} docker compose build breezewiki", cwd=compose_cwd)
            run_command("docker builder prune -f", cwd=compose_cwd)

        # Get list of valid services from the generated compose file
        try:
            res = subprocess.run([f"{env_cmd_prefix} docker compose config --services"], cwd=compose_cwd, capture_output=True, text=True, check=True, shell=True)
            valid_services = res.stdout.strip().split('\n')
        except subprocess.CalledProcessError as e:
            print(f"Failed to list services: {e.stderr}")
            sys.exit(1)

        for service in valid_services:
            service = service.strip()
            if not service: continue
            
            print(f"Building {service}...")
            run_command(f"{env_cmd_prefix} docker compose build {service}", cwd=compose_cwd)
            print(f"Pruning build cache after {service}...")
            run_command("docker builder prune -f", cwd=compose_cwd)

        # Step 2c: Deploy (Up)
        print("Launching stack...")
        # We call zima.sh again (without -G) to let it handle the final 'up' logic 
        # (it includes some other checks/waits). 
        cmd_deploy = f"{env_vars} ./zima.sh -p -y -E test/test_config.env -s {services_list}"
        run_command(cmd_deploy, cwd=PROJECT_ROOT)

        # 3. Verify URLs
        for check in stage_conf['checks']:
            if not verify_url(check['name'], check['url'], check['code']):
                all_pass = False
                
        # 4. Verify Logs
        verify_logs()
        
        # 4.1 Verify Docker Logs
        if not verify_docker_logs(services_list):
            all_pass = False
        
        # 5. Puppeteer Verification (Dashboard Interactions)
        print("Running Puppeteer UI Verification...")
        # Ensure dependencies are installed
        if not os.path.exists(os.path.join(TEST_SCRIPT_DIR, "node_modules")): 
            print("Installing test dependencies...")
            run_command("bun install", cwd=TEST_SCRIPT_DIR)
            
        try:
            run_command("bun test_service_pages_puppeteer.js", cwd=TEST_SCRIPT_DIR)
            print("[PASS] Puppeteer UI tests passed.")
        except Exception:
            print("[FAIL] Puppeteer UI tests failed.")
            all_pass = False

    finally:
        # 6. Cleanup Post-Flight
        print("Skipping post-test cleanup for debugging...")
        # if os.path.exists(os.path.join(compose_dir, "docker-compose.yml")): 
        #    run_command("docker compose down -v", cwd=compose_dir)
        
        # Aggressive cleanup to prevent disk exhaustion
        # run_command("docker system prune -f --volumes")

    if not all_pass:
        sys.exit(1)
    
    print(f"=== Stage {args.stage} Passed ===")

if __name__ == "__main__":
    main()