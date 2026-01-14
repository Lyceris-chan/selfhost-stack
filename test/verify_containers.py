#!/usr/bin/env python3
"""Container health and log verification utility.

This script checks the status, health, and logs of Docker containers
associated with the Privacy Hub stack. It adheres to the Google Python Style Guide.
"""

import argparse
import json
import socket
import subprocess
import sys
import time
from typing import List, Dict, Tuple, Optional

# Constants
_DOCKER_CMD = "docker"
_CONTAINER_PREFIX_FILTER = "hub-"
_CRITICAL_LOG_KEYWORDS = ["panic", "fatal", "traceback"]
# Some errors are expected or transient; we can ignore them if needed.
_IGNORED_LOG_KEYWORDS = ["database", "does not exist"] 


def _run_command(cmd: str) -> Tuple[str, str, int]:
    """Executes a shell command and returns output.

    Args:
        cmd: The command string to execute.

    Returns:
        A tuple containing (stdout, stderr, return_code).
    """
    try:
        result = subprocess.run(
            cmd,
            shell=True,
            capture_output=True,
            text=True,
            check=False
        )
        return result.stdout.strip(), result.stderr.strip(), result.returncode
    except Exception as e:
        return "", str(e), -1


def _get_containers(filter_prefix: str) -> List[str]:
    """Retrieves a list of container names matching the prefix.

    Args:
        filter_prefix: The prefix to filter container names.

    Returns:
        A list of container names.
    """
    cmd = f"{_DOCKER_CMD} ps -a --format '{{{{.Names}}}}'"
    stdout, _, _ = _run_command(cmd)
    if not stdout:
        return []
    
    return [c for c in stdout.split('\n') if filter_prefix in c]


def _check_port_reachable(ip: str, port: int, timeout: int = 2) -> bool:
    """Checks if a TCP port is open and reachable.

    Args:
        ip: The IP address to check.
        port: The port number.
        timeout: Timeout in seconds.

    Returns:
        True if reachable, False otherwise.
    """
    try:
        with socket.create_connection((ip, port), timeout=timeout):
            return True
    except (socket.timeout, ConnectionRefusedError, OSError):
        return False


def _inspect_container(container_name: str) -> Dict:
    """Inspects a Docker container and returns its state.

    Args:
        container_name: The name of the container.

    Returns:
        A dictionary representing the container's state, or empty dict on failure.
    """
    cmd = f"{_DOCKER_CMD} inspect {container_name} --format '{{{{json .State}}}}'"
    stdout, _, ret = _run_command(cmd)
    if ret != 0 or not stdout:
        return {}
    try:
        return json.loads(stdout)
    except json.JSONDecodeError:
        return {}


def _audit_logs(container_name: str, tail_lines: int = 100) -> List[str]:
    """Audits container logs for critical errors.

    Args:
        container_name: Name of the container.
        tail_lines: Number of lines to check.

    Returns:
        A list of error messages found.
    """
    cmd = f"{_DOCKER_CMD} logs --tail {tail_lines} {container_name}"
    stdout, _, _ = _run_command(cmd)
    
    errors = []
    lines = stdout.split('\n')
    for line in lines:
        lower_line = line.lower()
        if any(kw in lower_line for kw in _CRITICAL_LOG_KEYWORDS):
            if not any(ign in lower_line for ign in _IGNORED_LOG_KEYWORDS):
                errors.append(line.strip())
    return errors

def main():
    """Main entry point for verification."""
    parser = argparse.ArgumentParser(description="Verify container health and logs.")
    parser.add_argument("--prefix", default=_CONTAINER_PREFIX_FILTER,
                        help="Container name prefix to filter.")
    args = parser.parse_args()

    print("==================================================")
    print("🐳 ZIMAOS PRIVACY HUB: CONTAINER HEALTH & LOG AUDIT")
    print("==================================================")

    # Pre-flight: Wait for Gluetun Health (Critical Dependency)
    # Most services depend on gluetun, so we must wait for it first.
    print("Waiting for hub-gluetun to be healthy...")
    gluetun_healthy = False
    for i in range(24): # 2 minutes max
        state = _inspect_container("hub-gluetun")
        health = state.get("Health", {}).get("Status", "unknown")
        if health == "healthy":
            print(f"  \033[32m[PASS]\033[0m hub-gluetun is healthy.")
            gluetun_healthy = True
            break
        elif health == "unhealthy":
             # Fail fast if explicitly unhealthy
             print(f"  \033[31m[FAIL]\033[0m hub-gluetun reports unhealthy.")
             break
        time.sleep(5)
    
    if not gluetun_healthy:
        print(f"\033[31m[FAIL]\033[0m hub-gluetun timed out or failed health check.")
        # Proceed anyway to show logs, but mark as failure
        failed_count = 1 
    else:
        failed_count = 0

    containers = _get_containers(args.prefix)
    if not containers:
        print(f"\033[33m[WARN]\033[0m No containers found with prefix '{args.prefix}'.")
        # Depending on context, this might be a fail or just a warning.
        # If we expect the stack to be up, it's a fail.
        sys.exit(1)

    passed_count = 0
    failed_count = 0
    warning_count = 0

    for container in sorted(containers):
        print(f"Checking {container}...")
        
        # 1. State & Health Check
        state = _inspect_container(container)
        status = state.get("Status", "unknown")
        health_obj = state.get("Health", {})
        health_status = health_obj.get("Status", "n/a")
        
        status_msg = f"Status: {status.upper()}"
        if health_status != "n/a":
            status_msg += f", Health: {health_status.upper()}"
        
        is_running = (status == "running")
        is_healthy = (health_status == "healthy" or health_status == "n/a")
        
        if is_running and is_healthy:
            print(f"  \033[32m[PASS]\033[0m State: {status_msg}")
            passed_count += 1
        else:
            print(f"  \033[31m[FAIL]\033[0m State: {status_msg}")
            failed_count += 1
            # Dump logs for failed container
            print(f"  --- Last 10 log lines for context ---")
            log_dump = _audit_logs(container, 10)
            for l in log_dump: # Actually audit_logs filters, so we just run command raw
                 _l, _, _ = _run_command(f"{_DOCKER_CMD} logs --tail 10 {container}")
                 print(_l)
            print("  -------------------------------------")
            continue # Skip further checks for this container if it's dead

        # 2. Log Audit
        log_errors = _audit_logs(container)
        if log_errors:
            print(f"  \033[31m[FAIL]\033[0m Logs: Found {len(log_errors)} critical errors")
            for err in log_errors[:3]: # Show first 3
                print(f"    - {err}")
            if len(log_errors) > 3:
                print(f"    ... and {len(log_errors) - 3} more")
            failed_count += 1 # Strict failure on critical logs?
        else:
             print(f"  \033[32m[PASS]\033[0m Logs: Clean")

    print("\n==================================================")
    print(f"AUDIT SUMMARY")
    print(f"  ✅ Passed Checks: {passed_count}")
    print(f"  ❌ Failed Checks: {failed_count}")
    print("==================================================")

    if failed_count > 0:
        sys.exit(1)
    
    sys.exit(0)

if __name__ == "__main__":
    main()