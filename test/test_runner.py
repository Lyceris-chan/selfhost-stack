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
            {"name": "Dashboard", "url": "http://localhost:8081", "code": 200},
            {"name": "Hub API", "url": "http://localhost:55555/status", "code": 200},
            {"name": "AdGuard", "url": "http://localhost:8083", "code": 200},
            {"name": "WireGuard UI", "url": "http://localhost:51821", "code": 200}
        ]
    },
    2: {
        "name": "Standard Privacy Frontends",
        "services": "redlib,gluetun,wikiless,rimgo,breezewiki,anonymousoverflow,scribe",
        "checks": [
            {"name": "Redlib", "url": "http://localhost:8080/settings", "code": 200},
            {"name": "Wikiless", "url": "http://localhost:8180", "code": 200},
            {"name": "Rimgo", "url": "http://localhost:3002", "code": 200},
            {"name": "BreezeWiki", "url": "http://localhost:8380", "code": 200},
            {"name": "AnonOverflow", "url": "http://localhost:8480", "code": 200},
            {"name": "Scribe", "url": "http://localhost:8280", "code": 200}
        ]
    },
    3: {
        "name": "Invidious & Search Stack",
        "services": "invidious,invidious-db,companion,gluetun,searxng,searxng-redis",
        "checks": [
            {"name": "Invidious", "url": "http://localhost:3000/api/v1/stats", "code": 200},
            {"name": "SearXNG", "url": "http://localhost:8082", "code": 200}
        ]
    },
    4: {
        "name": "Management, Utilities & Media",
        "services": "portainer,memos,gluetun,cobalt,odido-booster,vert,vertd,immich-server,immich-db,immich-redis,immich-machine-learning",
        "checks": [
             {"name": "Portainer", "url": "http://localhost:9000", "code": 200},
             {"name": "Memos", "url": "http://localhost:5230", "code": 200},
             {"name": "Cobalt", "url": "http://localhost:9001", "code": 200},
             {"name": "Odido Booster", "url": "http://localhost:8085", "code": 200},
             {"name": "VERT", "url": "http://localhost:5555", "code": 200},
             {"name": "VERTd", "url": "http://localhost:24153/api/v1/health", "code": 200},
             {"name": "Immich", "url": "http://localhost:2283/api/server-info", "code": 200}
        ]
    }
}

def run_command(cmd, cwd=None):
    print(f"Executing: {cmd}")
    ret = subprocess.call(cmd, shell=True, cwd=cwd)
    if ret != 0:
        print(f"Command failed: {cmd}")
        sys.exit(1)

def verify_url(name, url, expected_code=200, retries=45):
    print(f"Verifying {name} at {url}...")
    for i in range(retries):
        try:
            code = urllib.request.urlopen(url, timeout=5).getcode()
            if code == expected_code:
                print(f"[PASS] {name} is UP (Status {code})")
                return True
        except Exception as e:
            pass
        time.sleep(2)
        if i % 5 == 0:
            print(f"Waiting for {name}...")
    print(f"[FAIL] {name} is DOWN")
    return False

def verify_logs():
    # Helper to inspect the deployment log
    # Path corrected to include /data/ as per lib/init.sh structure
    log_path = "/workspaces/selfhost-stack/test/test_data/data/AppData/privacy-hub-test/deployment.log"
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

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--stage", type=int, required=True)
    args = parser.parse_args()

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
        
    # 1. Cleanup Pre-Flight
    print("Cleaning environment (Pre-flight)...")
    # Path corrected to include /data/
    compose_dir = "/workspaces/selfhost-stack/test/test_data/data/AppData/privacy-hub-test"
    if os.path.exists(os.path.join(compose_dir, "docker-compose.yml")):
         run_command("docker compose down -v || true", cwd=compose_dir)
    else:
         print("No previous compose file found, skipping cleanup.")
    
    # 2. Deploy
    # We assume we are in project root
    # Note: We must ensure test_config.env path is correct relative to execution
    env_vars = "APP_NAME=privacy-hub-test PROJECT_ROOT=/workspaces/selfhost-stack/test/test_data"
    cmd = f"{env_vars} ./zima.sh -p -y -E test/test_config.env -s {services_list}"
    run_command(cmd, cwd="/workspaces/selfhost-stack")

    # 3. Verify URLs
    all_pass = True
    for check in stage_conf['checks']:
        if not verify_url(check['name'], check['url'], check['code']):
            all_pass = False
            
    # 4. Verify Logs
    verify_logs()
    
    # 5. Puppeteer Verification (Dashboard Interactions)
    print("Running Puppeteer UI Verification...")
    test_dir = "/workspaces/selfhost-stack/test"
    # Ensure dependencies are installed
    if not os.path.exists(os.path.join(test_dir, "node_modules")): 
        print("Installing test dependencies...")
        run_command("npm install", cwd=test_dir)
        
    try:
        run_command("node test_service_pages_puppeteer.js", cwd=test_dir)
        print("[PASS] Puppeteer UI tests passed.")
    except Exception:
        print("[FAIL] Puppeteer UI tests failed.")
        all_pass = False

    # 6. Cleanup Post-Flight
    print("Post-test cleanup and storage optimization...")
    if os.path.exists(os.path.join(compose_dir, "docker-compose.yml")): 
        run_command("docker compose down -v", cwd=compose_dir)
    
    print("Performing global storage prune...")
    run_command("docker system prune -af")

    if not all_pass:
        sys.exit(1)
    
    print(f"=== Stage {args.stage} Passed ===")

if __name__ == "__main__":
    main()