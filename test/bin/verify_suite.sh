#!/bin/bash
#
# Master Verification Suite for ZimaOS Privacy Hub.
# Orchestrates static analysis, log checking, UI interactions, and system operations.
#
# Usage:
#   ./test/bin/verify_suite.sh
#

set -euo pipefail

# Constants
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly LIB_DIR="${PROJECT_ROOT}/test/lib/verification"
readonly REPORT_FILE="${PROJECT_ROOT}/REPORT.md"

# Colors for output
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Init Report
echo "# Verification Report" > "${REPORT_FILE}"
echo "Date: $(date)" >> "${REPORT_FILE}"
echo "" >> "${REPORT_FILE}"

# Helper for printing section headers
print_header() {
  echo ""
  echo -e "${BLUE}=== $1 ===${NC}"
  echo "## $1" >> "${REPORT_FILE}"
}

report_result() {
    if [[ "$1" -eq 0 ]]; then
        echo "- Status: **PASSED**" >> "${REPORT_FILE}"
    else
        echo "- Status: **FAILED**" >> "${REPORT_FILE}"
    fi
    echo "" >> "${REPORT_FILE}"
}

# Main execution function
main() {
  local tests_passed=0
  local tests_failed=0

  echo "=================================================="
  echo "  ZimaOS Privacy Hub - Verification Suite"
  echo "=================================================="

  # 1. Static Verification
  print_header "Static Verification"
  if bash "${LIB_DIR}/static_check.sh" "${PROJECT_ROOT}"; then
    tests_passed=$((tests_passed + 1))
    report_result 0
  else
    tests_failed=$((tests_failed + 1))
    report_result 1
  fi

  # 2. UI Interactions (Guest)
  print_header "UI Interactions & Visual Verification"
  if command -v node >/dev/null; then
    if node "${LIB_DIR}/ui_interactions.js"; then
      tests_passed=$((tests_passed + 1))
      report_result 0
    else
      echo -e "${RED}❌ UI checks failed${NC}"
      tests_failed=$((tests_failed + 1))
      report_result 1
    fi
  else
    echo "⚠ Node.js not found. Skipping UI checks."
  fi

  # 3. Targeted Functional Tests (New)
  print_header "Targeted Functional Tests"
  if command -v node >/dev/null; then
    if node "${LIB_DIR}/targeted_functional_tests.js"; then
        tests_passed=$((tests_passed + 1))
        report_result 0
    else
        echo -e "${RED}❌ Targeted tests failed${NC}"
        tests_failed=$((tests_failed + 1))
        report_result 1
    fi
  else
    echo "⚠ Node.js not found. Skipping targeted tests."
  fi

  # 4. Admin API Verification
  print_header "Admin API Verification"
  if command -v node >/dev/null; then
    if node "${LIB_DIR}/api_admin_test.js"; then
        tests_passed=$((tests_passed + 1))
        report_result 0
    else
        echo -e "${RED}❌ Admin API checks failed${NC}"
        tests_failed=$((tests_failed + 1))
        report_result 1
    fi
  else
    echo "⚠ Node.js not found. Skipping Admin API tests."
  fi

  # 5. System Operations
  print_header "System Operations"
  if bash "${LIB_DIR}/system_ops.sh"; then
    tests_passed=$((tests_passed + 1))
    report_result 0
  else
    echo -e "${RED}❌ System operations check failed${NC}"
    tests_failed=$((tests_failed + 1))
    report_result 1
  fi

  # 6. Log Verification
  print_header "Container Log Analysis"
  if command -v node >/dev/null && command -v docker >/dev/null; then
    if node "${LIB_DIR}/log_analyzer.js"; then
      tests_passed=$((tests_passed + 1))
      report_result 0
    else
      echo -e "${RED}❌ Log checks failed${NC}"
      tests_failed=$((tests_failed + 1))
      report_result 1
    fi
  else
    echo "⚠ Docker or Node.js not found. Skipping log checks."
  fi

  # Summary
  echo ""
  echo "=================================================="
  echo "  SUMMARY"
  echo "=================================================="
  echo -e "Passed: ${GREEN}${tests_passed}${NC}"
  echo -e "Failed: ${RED}${tests_failed}${NC}"
  echo "=================================================="
  
  echo "## Summary" >> "${REPORT_FILE}"
  echo "Passed: ${tests_passed}" >> "${REPORT_FILE}"
  echo "Failed: ${tests_failed}" >> "${REPORT_FILE}"

  if (( tests_failed == 0 )); then
    echo -e "${GREEN}✓ All checks passed!${NC}"
    exit 0
  else
    echo -e "${RED}✗ One or more checks failed.${NC}"
    exit 1
  fi
}

main "$@"
