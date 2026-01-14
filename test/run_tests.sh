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

  # 4. UI/UX Audit
  echo -e "\e[34m--- Step 4: UI/UX Audit ---\e[0m"
  if node test/verify_ui.js; then
    echo -e "\e[32m✅ UI/UX Audit Passed\e[0m"
  else
    echo -e "\e[31m❌ Step 4 (UI/UX) Failed\e[0m"
    exit 1
  fi
  echo ""

  echo "=========================================================="
  echo -e "\e[1;32m🎉 ALL VERIFICATIONS PASSED SUCCESSFULLY\e[0m"
  echo "=========================================================="
}

main "$@"