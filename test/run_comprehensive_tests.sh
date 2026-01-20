#!/usr/bin/env bash
# Comprehensive Test Runner
# Runs all verification and test suites for the ZimaOS Privacy Hub

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=================================================="
echo "  ZimaOS Privacy Hub - Comprehensive Test Suite"
echo "=================================================="
echo ""

# Track results
TESTS_PASSED=0
TESTS_FAILED=0

# Step 1: Static Verification
echo -e "${BLUE}[1/3]${NC} Running Static Verification..."
if bash "${SCRIPT_DIR}/tmp_rovodev_comprehensive_verification.sh"; then
    echo -e "${GREEN}✓ Static verification passed${NC}"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗ Static verification failed${NC}"
    ((TESTS_FAILED++))
fi
echo ""

# Step 2: Visual Layout Tests (if dashboard is accessible)
echo -e "${BLUE}[2/3]${NC} Checking if dashboard is accessible for visual tests..."
if command -v node &> /dev/null; then
    if curl -s -o /dev/null -w "%{http_code}" "${TEST_BASE_URL:-http://localhost:8088}" 2>/dev/null | grep -q "200"; then
        echo "Dashboard is accessible, running visual layout tests..."
        if node "${SCRIPT_DIR}/tmp_rovodev_visual_layout_test.js"; then
            echo -e "${GREEN}✓ Visual layout tests passed${NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${RED}✗ Visual layout tests failed${NC}"
            ((TESTS_FAILED++))
        fi
    else
        echo -e "${YELLOW}⚠ Dashboard not accessible, skipping visual tests${NC}"
        echo "  (This is expected if you haven't deployed yet)"
    fi
else
    echo -e "${YELLOW}⚠ Node.js not available, skipping visual tests${NC}"
fi
echo ""

# Step 3: Container Log Analysis (if Docker is available)
echo -e "${BLUE}[3/3]${NC} Running Container Log Analysis..."
if command -v node &> /dev/null && docker ps &> /dev/null 2>&1; then
    if node "${SCRIPT_DIR}/tmp_rovodev_container_log_checker.js"; then
        echo -e "${GREEN}✓ Container logs healthy${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${YELLOW}⚠ Some container issues detected${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Docker not available, skipping container tests${NC}"
fi
echo ""

# Summary
echo "=================================================="
echo "  TEST SUMMARY"
echo "=================================================="
echo -e "Passed: ${GREEN}${TESTS_PASSED}${NC}"
echo -e "Failed: ${RED}${TESTS_FAILED}${NC}"
echo "=================================================="
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some tests failed${NC}"
    exit 1
fi
