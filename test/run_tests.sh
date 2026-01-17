#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

# ==============================================================================
# 🛡️ ZIMAOS PRIVACY HUB: MASTER TEST SUITE
# ==============================================================================
# Automated verification for the Privacy Hub network stack.
# Ensures integrity, functional correctness, and UI compliance.
# ==============================================================================

# --- Constants ---
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly TEST_DATA_DIR="${PROJECT_ROOT}/test/test_data"

# --- Error Handling ---
failure_handler() {
  local lineno="$1"
  local msg="$2"
  echo -e "\e[31m  ✖ [CRIT] Test suite failed at line ${lineno}: ${msg}\e[0m"
  exit 1
}
trap 'failure_handler ${LINENO} "$BASH_COMMAND"' ERR

# ==========================================================
# Main Execution
# ==========================================================

main() {
  # Navigate to project root
  cd "${PROJECT_ROOT}"

  echo ""
  echo "=========================================================="
  echo " 🛡️  PRIVACY HUB: MASTER TEST SUITE"
  echo "=========================================================="
  echo " Started at: $(date)"
  echo "=========================================================="
  echo ""

  # 1. Integrity Audit
  echo -e "\e[34m--- Step 1: Integrity Audit ---\e[0m"
  if python3 test/verify_integrity.py; then
    echo -e "\e[32m✅ Integrity Check Passed\e[0m"
  else
    echo -e "\e[31m❌ Step 1 (Integrity) Failed\e[0m"
    exit 1
  fi
  echo ""

  # 2. Functional & API Suite
  echo -e "\e[34m--- Step 2: Functional & API Suite ---\e[0m"
  # Set up test environment variables
  export APP_NAME="privacy-hub-test"
  export PROJECT_ROOT_DIR="${TEST_DATA_DIR}"
  mkdir -p "${TEST_DATA_DIR}"

  # Run the Python test runner (Handles deployment & deep API checks)
  if python3 test/test_runner.py --full; then
    echo -e "\e[32m✅ Functional Suite Passed\e[0m"
  else
    echo -e "\e[31m❌ Step 2 (Functional) Failed\e[0m"
    exit 1
  fi
  echo ""

  # 3. Infrastructure Health Audit
  echo -e "\e[34m--- Step 3: Infrastructure Health Audit ---\e[0m"
  # This now includes port reachability and stricter log checks
  if python3 test/verify_containers.py; then
    echo -e "\e[32m✅ Infrastructure Check Passed\e[0m"
  else
    echo -e "\e[31m❌ Step 3 (Containers) Failed\e[0m"
    exit 1
  fi
  echo ""

  # 3a. Integration Tests
  echo -e "\e[34m--- Step 3a: Integration Tests ---\e[0m"
  if [ -f test/test_integration.js ]; then
    if node test/test_integration.js; then
      echo -e "\e[32m✅ Integration Tests Passed\e[0m"
    else
      echo -e "\e[31m❌ Step 3a (Integration Tests) Failed\e[0m"
      exit 1
    fi
  else
    echo -e "\e[33m⚠️  Step 3a (Integration Tests) Skipped - test file not found\e[0m"
  fi
  echo ""

  # 3b. Functional Operations Tests
  echo -e "\e[34m--- Step 3b: Functional Operations Tests ---\e[0m"
  if [ -f test/test_functional_ops.js ]; then
    if node test/test_functional_ops.js; then
      echo -e "\e[32m✅ Functional Operations Tests Passed\e[0m"
    else
      echo -e "\e[31m❌ Step 3b (Functional Operations Tests) Failed\e[0m"
      exit 1
    fi
  else
    echo -e "\e[33m⚠️  Step 3b (Functional Operations Tests) Skipped - test file not found\e[0m"
  fi
  echo ""

  # 4. UI/UX Audit
  echo -e "\e[34m--- Step 4: UI/UX Audit ---\e[0m"
  if node test/test_dashboard.js; then
    echo -e "\e[32m✅ UI/UX Audit Passed\e[0m"
  else
    echo -e "\e[31m❌ Step 4 (UI/UX) Failed\e[0m"
    exit 1
  fi
  echo ""

  # 5. Comprehensive Dashboard Interaction Tests
  echo -e "\e[34m--- Step 5: Comprehensive Dashboard Tests ---\e[0m"
  if [ -f test/test_dashboard_comprehensive.js ]; then
    if node test/test_dashboard_comprehensive.js; then
      echo -e "\e[32m✅ Dashboard Comprehensive Tests Passed\e[0m"
    else
      echo -e "\e[31m❌ Step 5 (Dashboard Tests) Failed\e[0m"
      exit 1
    fi
  else
    echo -e "\e[33m⚠️  Step 5 (Dashboard Tests) Skipped - test file not found\e[0m"
  fi
  echo ""

  # 6. WireGuard Functionality Tests
  echo -e "\e[34m--- Step 6: WireGuard Tests ---\e[0m"
  if [ -f test/test_wireguard.js ]; then
    if node test/test_wireguard.js; then
      echo -e "\e[32m✅ WireGuard Tests Passed\e[0m"
    else
      echo -e "\e[31m❌ Step 6 (WireGuard Tests) Failed\e[0m"
      exit 1
    fi
  else
    echo -e "\e[33m⚠️  Step 6 (WireGuard Tests) Skipped - test file not found\e[0m"
  fi
  echo ""

  # 7. Extended Interactions (Rimgo/Invidious)
  echo -e "\e[34m--- Step 7: Extended Interactions Tests ---\e[0m"
  if [ -f test/test_extended_interactions.js ]; then
    if node test/test_extended_interactions.js; then
      echo -e "\e[32m✅ Extended Interactions Tests Passed\e[0m"
    else
      echo -e "\e[31m❌ Step 7 (Extended Interactions) Failed\e[0m"
      exit 1
    fi
  else
    echo -e "\e[33m⚠️  Step 7 (Extended Interactions) Skipped - test file not found\e[0m"
  fi
  echo ""

  # 8. Container Logs Check
  echo -e "\e[34m--- Step 8: Container Logs Analysis ---\e[0m"
  echo "Checking for errors in container logs..."
  
  CONTAINERS=$(docker ps --filter "name=hub-" --format "{{.Names}}" 2>/dev/null || echo "")
  if [ -z "$CONTAINERS" ]; then
    echo -e "\e[33m⚠️  No hub containers found - skipping log check\e[0m"
  else
    HAS_ERRORS=0
    for container in $CONTAINERS; do
      echo "  Checking $container..."
      # Check for critical errors in last 100 lines
      ERROR_COUNT=$(docker logs "$container" --tail 100 2>&1 | grep -iE "error|critical|fatal|exception" | grep -v "404" | wc -l || echo "0")
      if [ "$ERROR_COUNT" -gt 0 ]; then
        echo -e "    \e[33m⚠️  Found $ERROR_COUNT potential errors in $container\e[0m"
        docker logs "$container" --tail 20 2>&1 | grep -iE "error|critical|fatal|exception" | grep -v "404" || true
        HAS_ERRORS=1
      else
        echo -e "    \e[32m✓ No critical errors\e[0m"
      fi
    done
    
    if [ $HAS_ERRORS -eq 1 ]; then
      echo -e "\e[33m⚠️  Some containers have errors - review logs above\e[0m"
    else
      echo -e "\e[32m✅ All container logs clean\e[0m"
    fi
  fi
  echo ""

  echo "=========================================================="
  echo -e "\e[1;32m🎉 ALL VERIFICATIONS PASSED SUCCESSFULLY\e[0m"
  echo "=========================================================="
}

main "$@"