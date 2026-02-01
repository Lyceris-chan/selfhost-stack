#!/bin/bash
set -euo pipefail

# ==============================================================================
# 🛡️ ZIMAOS PRIVACY HUB: STAGED TEST RUNNER (GRANULAR)
# ==============================================================================
# Runs tests in 7 stages to manage resources and verify specific components.
# Usage: ./test/run_staged_tests.sh [stage_number]
# ==============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly TEST_DATA_DIR="${PROJECT_ROOT}/test/test_data"
readonly REPORT_DIR="${PROJECT_ROOT}/test/reports"
readonly SCREENSHOT_DIR="${PROJECT_ROOT}/test/screenshots"

stage="${1:-1}"

mkdir -p "${TEST_DATA_DIR}" "${REPORT_DIR}" "${SCREENSHOT_DIR}"

# Determine LAN IP for Node tests
export TEST_LAN_IP=$(python3 -c "import socket; s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.connect(('9.9.9.9', 80)); print(s.getsockname()[0]); s.close()")
export TEST_BASE_URL="http://${TEST_LAN_IP}:8088"
export API_URL="http://${TEST_LAN_IP}:55555"
export APP_NAME="privacy-hub-test"
export PROJECT_ROOT_DIR="${TEST_DATA_DIR}"

echo "=========================================================="
echo " 🛡️  PRIVACY HUB: STAGED TEST RUNNER - STAGE $stage"
echo "=========================================================="

case "$stage" in
  1)
    echo -e "\e[34m--- Stage 1: Setup & Integrity ---\e[0m"
    rm -f "${REPORT_DIR}"/*.json
    rm -rf "${SCREENSHOT_DIR}"/*
    cd "${PROJECT_ROOT}"
    python3 test/verify_integrity.py
    echo -e "\e[32m✅ Stage 1 Complete.\e[0m"
    ;;

  2)
    echo -e "\e[34m--- Stage 2: Environment Cleanup & Image Preparation ---\e[0m"
    cd "${PROJECT_ROOT}"
    echo "Performing aggressive cleanup..."
    
    # Explicitly stop and remove hub containers
    echo "Stopping existing hub containers..."
    docker ps -q --filter "name=hub-" | while read -r id; do docker stop "$id"; done || true
    docker ps -aq --filter "name=hub-" | while read -r id; do docker rm -f "$id"; done || true
    
    # Remove the network if it exists
    docker network rm privacy-hub-test_frontend || true
    
    docker system prune -f --volumes || true
    rm -rf "${TEST_DATA_DIR}"
    mkdir -p "${TEST_DATA_DIR}"
    
    echo "Pre-pulling critical images..."
    # Pull images manually to avoid timeouts during zima.sh execution
    docker pull nginx:alpine
    docker pull python:3.11-alpine
    docker pull alpine:latest
    docker pull redis:alpine
    docker pull postgres:14
    echo -e "\e[32m✅ Stage 2 Complete.\e[0m"
    ;;

  3)
    echo -e "\e[34m--- Stage 3: Core Infrastructure Deployment ---\e[0m"
    cd "${PROJECT_ROOT}"
    
    # Targeted cleanup to ensure network can be recreated
    docker ps -q --filter "name=hub-" | while read -r id; do docker stop "$id"; done || true
    docker ps -aq --filter "name=hub-" | while read -r id; do docker rm -f "$id"; done || true
    docker network rm privacy-hub-test_frontend || true

    # Deploy only the control plane and networking
    set -a; . test/test_config.env; set +a
    TEST_MODE=true LAN_IP_OVERRIDE="${TEST_LAN_IP}" ./zima.sh -p -y -s hub-api,dashboard,gluetun,adguard,unbound,wg-easy,docker-proxy
    
    echo "Verifying Core Infrastructure..."
    python3 test/verify_containers.py
    echo -e "\e[32m✅ Stage 3 Complete.\e[0m"
    ;;

  4)
    echo -e "\e[34m--- Stage 4: Application Services Deployment ---\e[0m"
    cd "${PROJECT_ROOT}"

    # Targeted cleanup to ensure network can be recreated
    docker ps -q --filter "name=hub-" | while read -r id; do docker stop "$id"; done || true
    docker ps -aq --filter "name=hub-" | while read -r id; do docker rm -f "$id"; done || true
    docker network rm privacy-hub-test_frontend || true

    # Deploy the remaining apps + dependencies
    set -a; . test/test_config.env; set +a
    # We must include hub-api and others if they are dependencies
    TEST_MODE=true LAN_IP_OVERRIDE="${TEST_LAN_IP}" ./zima.sh -p -y -s hub-api,dashboard,gluetun,adguard,unbound,wg-easy,docker-proxy,redlib,wikiless,rimgo,breezewiki,anonymousoverflow,invidious,companion,searxng,portainer,odido-booster,vert,vertd,immich,watchtower,cobalt,cobalt-web,scribe

    
    echo "Verifying All Containers..."
    python3 test/verify_containers.py
    echo -e "\e[32m✅ Stage 4 Complete.\e[0m"
    ;;

  5)
    echo -e "\e[34m--- Stage 5: Functional & Integration Tests ---\e[0m"
    cd "${PROJECT_ROOT}"
    
    echo "Running Integration Tests..."
    if [ -f test/test_integration.js ]; then
        node test/test_integration.js
    fi

    echo "Running Functional Operations Tests..."
    if [ -f test/test_functional_ops.js ]; then
        node test/test_functional_ops.js
    fi
    echo -e "\e[32m✅ Stage 5 Complete.\e[0m"
    ;;

  6)
    echo -e "\e[34m--- Stage 6: UI/UX Audit & Visuals ---\e[0m"
    cd "${PROJECT_ROOT}"
    
    # Restore dashboard assets before UI tests
    echo "Restoring dashboard assets..."
    mkdir -p "${TEST_DATA_DIR}/data/AppData/privacy-hub-test/assets"
    cp test/assets/*.js test/assets/*.css test/assets/*.woff2 "${TEST_DATA_DIR}/data/AppData/privacy-hub-test/assets/" 2>/dev/null || true
    cp test/assets/privacy-hub.svg "${TEST_DATA_DIR}/data/AppData/privacy-hub-test/assets/icon.svg" 2>/dev/null || true

    # Extract Admin Password
    SECRETS_FILE="${TEST_DATA_DIR}/data/AppData/privacy-hub-test/.secrets"
    if [ -f "$SECRETS_FILE" ]; then
        export ADMIN_PASSWORD=$(grep "ADMIN_PASS_RAW=" "$SECRETS_FILE" | cut -d'=' -f2 | tr -d '"' | tr -d "'")
    fi

    echo "Running Dashboard Tests..."
    node test/test_dashboard.js || echo -e "\e[31m❌ UI Audit Failed\e[0m"

    echo "Capturing Service Screenshots..."
    if [ -f test/test_service_screenshots.js ]; then
        node test/test_service_screenshots.js || true
    fi
    echo -e "\e[32m✅ Stage 6 Complete.\e[0m"
    ;;

  7)
    echo -e "\e[34m--- Stage 7: Logs Analysis & Final Cleanup ---\e[0m"
    cd "${PROJECT_ROOT}"
    
    echo "Checking Container Logs..."
    CONTAINERS=$(docker ps --filter "name=hub-" --format "{{.Names}}" 2>/dev/null || echo "")
    if [ -n "$CONTAINERS" ]; then
        for container in $CONTAINERS; do
            echo "  Checking $container..."
            ERROR_COUNT=$(docker logs "$container" --tail 100 2>&1 | grep -iE "error|critical|fatal|exception" | grep -v "404" | wc -l || echo "0")
            if [ "$ERROR_COUNT" -gt 0 ]; then
                echo -e "    \e[33m⚠️  Found $ERROR_COUNT potential errors in $container\e[0m"
            else
                echo -e "    \e[32m✓ Clean\e[0m"
            fi
        done
    fi

    echo "Performing Final Cleanup..."
    docker system prune -f || true
    echo -e "\e[32m✅ Stage 7 Complete.\e[0m"
    ;;

  *)
    echo "Invalid stage selected. Use 1-7."
    exit 1
    ;;
esac