#!/usr/bin/env python3
import subprocess
import sys
import os
import time
import json

TEST_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(TEST_SCRIPT_DIR)
TEST_DATA_DIR = os.path.join(TEST_SCRIPT_DIR, "test_data_ab")
BASE_DIR = os.path.join(TEST_DATA_DIR, "data/AppData/privacy-hub-test-ab")

def run_command(cmd, cwd=None, env=None):
    print(f"Executing: {cmd}")
    full_env = os.environ.copy()
    if env:
        full_env.update(env)
    ret = subprocess.call(cmd, shell=True, cwd=cwd, env=full_env)
    if ret != 0:
        print(f"Command failed: {cmd}")
        return False
    return True

def get_active_slot():
    slot_file = os.path.join(BASE_DIR, ".active_slot")
    if os.path.exists(slot_file):
        with open(slot_file, 'r') as f:
            return f.read().strip()
    return None

def main():
    # 1. Setup
    print("=== Testing A/B Swap Logic ===")
    if os.path.exists(TEST_DATA_DIR):
        subprocess.call(f"rm -rf {TEST_DATA_DIR}", shell=True)
    os.makedirs(TEST_DATA_DIR, exist_ok=True)

    dummy_wg_path = os.path.join(TEST_SCRIPT_DIR, "dummy_wg.conf")
    with open(dummy_wg_path, 'r') as f:
        dummy_wg_b64 = subprocess.check_output(f"base64 -w0 {dummy_wg_path}", shell=True).decode().strip()

    test_env = {
        "APP_NAME": "privacy-hub-test-ab",
        "PROJECT_ROOT": TEST_DATA_DIR,
        "AUTO_CONFIRM": "true",
        "AUTO_PASSWORD": "true",
        "WG_CONF_B64": dummy_wg_b64
    }

    # 2. Initial Deployment (Slot A)
    print("\n--- Phase 1: Initial Deployment (Slot A) ---")
    # Using small service list to keep it fast, but must include dependencies
    cmd = "./zima.sh -p -y -s hub-api,dashboard,gluetun,docker-proxy"
    if not run_command(cmd, cwd=PROJECT_ROOT, env=test_env):
        sys.exit(1)

    slot = get_active_slot()
    print(f"Active slot after initial deploy: {slot}")
    if slot != 'a':
        print(f"Error: Expected slot 'a', got {slot}")
        sys.exit(1)

    # 3. Swap Slots and Deploy (Slot B)
    print("\n--- Phase 2: Swap Slots and Deploy (Slot B) ---")
    cmd = "./zima.sh -p -y -S -s hub-api,dashboard,gluetun,docker-proxy"
    if not run_command(cmd, cwd=PROJECT_ROOT, env=test_env):
        sys.exit(1)

    slot = get_active_slot()
    print(f"Active slot after swap deploy: {slot}")
    if slot != 'b':
        print(f"Error: Expected slot 'b', got {slot}")
        sys.exit(1)

    # 4. Verify Slot A containers are gone
    print("\n--- Phase 3: Verifying Slot A Cleanup ---")
    res = subprocess.run(['docker', 'ps', '-a', '--format', '{{.Names}}'], capture_output=True, text=True)
    containers = res.stdout.split('\n')
    for c in containers:
        if c.startswith("dhi-a-"):
            print(f"Error: Found container from inactive slot: {c}")
            sys.exit(1)
    print("Verified: No Slot A containers found.")

    # 5. Verify Slot B containers are running
    print("\n--- Phase 4: Verifying Slot B Containers ---")
    found_b = False
    for c in containers:
        if c.startswith("dhi-b-"):
            print(f"Found active container: {c}")
            found_b = True
    if not found_b:
        print("Error: No Slot B containers found!")
        sys.exit(1)

    print("\n=== A/B Swap Logic Test PASSED ===")

    # Cleanup
    run_command(f"rm -rf {TEST_DATA_DIR}")
    subprocess.call("docker compose -f " + os.path.join(BASE_DIR, "docker-compose.yml") + " down -v", shell=True)

if __name__ == "__main__":
    main()
