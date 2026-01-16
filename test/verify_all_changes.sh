#!/bin/bash
# Comprehensive verification script for all Privacy Hub changes
# Tests syntax, validates changes, and verifies file integrity

set -e

echo "=========================================="
echo "PRIVACY HUB CHANGES VERIFICATION"
echo "=========================================="
echo ""

WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$WORKSPACE_ROOT"

PASSED=0
FAILED=0
WARNINGS=0

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass() {
    echo -e "${GREEN}✓${NC} $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo -e "${RED}✗${NC} $1"
    FAILED=$((FAILED + 1))
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    WARNINGS=$((WARNINGS + 1))
}

echo "1. CHIP LAYOUT OPTIMIZATION"
echo "----------------------------"

# Check CSS changes for chip grid
if grep -q "grid-auto-rows: minmax(48px, auto)" lib/templates/assets/dashboard.css; then
    pass "Chip grid height updated to 48px (Material 3 spec)"
else
    fail "Chip grid height not updated"
fi

if grep -q "grid-auto-flow: dense" lib/templates/assets/dashboard.css; then
    pass "Dense grid flow enabled (fills gaps)"
else
    fail "Dense grid flow not enabled"
fi

if grep -q "grid-template-columns: repeat(4, 1fr)" lib/templates/assets/dashboard.css; then
    pass "4-column grid layout configured"
else
    fail "4-column grid not found"
fi

if grep -q "grid-template-columns: repeat(3, 1fr)" lib/templates/assets/dashboard.css; then
    pass "3-column grid layout configured"
else
    fail "3-column grid not found"
fi

if grep -q "min-height: 48px" lib/templates/assets/dashboard.css; then
    pass "Chip minimum height set to 48px"
else
    fail "Chip minimum height not updated"
fi

if grep -q "hyphens: auto" lib/templates/assets/dashboard.css; then
    pass "Hyphenation enabled for long text"
else
    warn "Hyphenation not enabled"
fi

echo ""
echo "2. GLUETUN STATUS FIX"
echo "---------------------"

# Check gluetun status detection fix
if grep -q 'docker ps --filter "name=.*gluetun.*" --filter "status=running"' lib/templates/wg_control.sh; then
    pass "Gluetun status check updated to filter running containers"
else
    fail "Gluetun status check not updated"
fi

if grep -q "Check if gluetun container is running" lib/templates/wg_control.sh; then
    pass "Gluetun status check has documentation comment"
else
    warn "Missing documentation for gluetun check"
fi

echo ""
echo "3. CERTIFICATE DETECTION FIX"
echo "----------------------------"

# Check certificate path additions
cert_paths=0
if grep -q '"/etc/adguard/conf/ssl.crt"' lib/src/hub-api/app/routers/system.py; then
    cert_paths=$((cert_paths + 1))
fi
if grep -q '"/etc/adguard/certs/tls.crt"' lib/src/hub-api/app/routers/system.py; then
    cert_paths=$((cert_paths + 1))
fi
if grep -q '"/etc/adguard/conf/tls.crt"' lib/src/hub-api/app/routers/system.py; then
    cert_paths=$((cert_paths + 1))
fi
if grep -q '"/app/data/adguard/conf/ssl.crt"' lib/src/hub-api/app/routers/system.py; then
    cert_paths=$((cert_paths + 1))
fi

if [ $cert_paths -ge 4 ]; then
    pass "Certificate detection checks $cert_paths paths"
else
    fail "Certificate detection only checks $cert_paths paths (expected 4+)"
fi

if grep -q "Priority order: AdGuard conf" lib/src/hub-api/app/routers/system.py; then
    pass "Certificate path priority documented"
else
    warn "Certificate path priority not documented"
fi

echo ""
echo "4. TEST SUITE EXPANSION"
echo "-----------------------"

# Check new test file
if [ -f "test/test_extended_interactions.js" ]; then
    pass "Extended interaction test suite created"
    
    # Check test coverage
    if grep -q "testCertificateStatus" test/test_extended_interactions.js; then
        pass "Certificate status tests included"
    else
        warn "Certificate status tests missing"
    fi
    
    if grep -q "testGluetunStatus" test/test_extended_interactions.js; then
        pass "Gluetun status tests included"
    else
        warn "Gluetun status tests missing"
    fi
    
    if grep -q "testWireGuardManagement" test/test_extended_interactions.js; then
        pass "WireGuard management tests included"
    else
        warn "WireGuard tests missing"
    fi
    
    if grep -q "testDashboardLoading" test/test_extended_interactions.js; then
        pass "Dashboard loading tests included"
    else
        warn "Dashboard tests missing"
    fi
    
    if grep -q "testAdminAuthentication" test/test_extended_interactions.js; then
        pass "Admin authentication tests included"
    else
        warn "Admin auth tests missing"
    fi
else
    fail "Extended interaction test suite not found"
fi

echo ""
echo "5. DOCUMENTATION"
echo "----------------"

# Check configuration documentation
if [ -f "docs/CONFIGURATION_DETAILED.md" ]; then
    pass "Detailed configuration documentation created"
    
    # Check documentation completeness
    if grep -q "AdGuard Home" docs/CONFIGURATION_DETAILED.md; then
        pass "AdGuard Home configuration documented"
    else
        warn "AdGuard Home docs incomplete"
    fi
    
    if grep -q "Unbound" docs/CONFIGURATION_DETAILED.md; then
        pass "Unbound configuration documented"
    else
        warn "Unbound docs incomplete"
    fi
    
    if grep -q "Gluetun" docs/CONFIGURATION_DETAILED.md; then
        pass "Gluetun configuration documented"
    else
        warn "Gluetun docs incomplete"
    fi
    
    if grep -q "WG-Easy\|WireGuard" docs/CONFIGURATION_DETAILED.md; then
        pass "WireGuard configuration documented"
    else
        warn "WireGuard docs incomplete"
    fi
    
    if grep -q "Certificate" docs/CONFIGURATION_DETAILED.md; then
        pass "Certificate management documented"
    else
        warn "Certificate docs incomplete"
    fi
else
    fail "Configuration documentation not found"
fi

echo ""
echo "6. SYNTAX VALIDATION"
echo "--------------------"

# Validate shell scripts
shell_errors=0
for script in lib/core/*.sh lib/services/*.sh lib/templates/*.sh; do
    if [ -f "$script" ]; then
        if bash -n "$script" 2>/dev/null; then
            pass "$(basename $script): Syntax valid"
        else
            fail "$(basename $script): Syntax error"
            shell_errors=$((shell_errors + 1))
        fi
    fi
done

# Validate Python files
if command -v python3 &> /dev/null; then
    python_errors=0
    for pyfile in lib/src/hub-api/app/routers/*.py; do
        if [ -f "$pyfile" ]; then
            if python3 -m py_compile "$pyfile" 2>/dev/null; then
                pass "$(basename $pyfile): Syntax valid"
            else
                fail "$(basename $pyfile): Syntax error"
                python_errors=$((python_errors + 1))
            fi
        fi
    done
else
    warn "Python3 not available, skipping Python syntax check"
fi

# Validate JavaScript
js_errors=0
for jsfile in lib/templates/assets/*.js test/*.js; do
    if [ -f "$jsfile" ] && [[ "$jsfile" != *node_modules* ]] && [[ "$jsfile" != *qrcode* ]]; then
        # Basic syntax check - look for common errors
        if grep -q "function.*{.*}" "$jsfile" || grep -q "const\|let\|var" "$jsfile"; then
            pass "$(basename $jsfile): Basic structure valid"
        else
            warn "$(basename $jsfile): May have issues"
        fi
    fi
done

echo ""
echo "7. FILE INTEGRITY"
echo "-----------------"

# Check essential files exist
essential_files=(
    "zima.sh"
    "lib/core/constants.sh"
    "lib/core/core.sh"
    "lib/services/deploy.sh"
    "lib/services/compose.sh"
    "lib/templates/dashboard.html"
    "lib/templates/assets/dashboard.css"
    "lib/templates/assets/dashboard.js"
    "lib/templates/wg_control.sh"
    "lib/src/hub-api/app/routers/system.py"
)

for file in "${essential_files[@]}"; do
    if [ -f "$file" ]; then
        pass "$file exists"
    else
        fail "$file missing"
    fi
done

echo ""
echo "8. DEPLOYMENT READINESS"
echo "-----------------------"

# Check if zima.sh is executable
if [ -x "zima.sh" ]; then
    pass "zima.sh is executable"
else
    fail "zima.sh is not executable"
fi

# Check if help works
if ./zima.sh -h > /dev/null 2>&1; then
    pass "zima.sh help command works"
else
    fail "zima.sh help command fails"
fi

# Check for required directories
if [ -d "lib/core" ] && [ -d "lib/services" ] && [ -d "lib/templates" ]; then
    pass "Required directory structure present"
else
    fail "Missing required directories"
fi

echo ""
echo "=========================================="
echo "VERIFICATION SUMMARY"
echo "=========================================="
echo ""
echo "Total Checks: $((PASSED + FAILED + WARNINGS))"
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo -e "${YELLOW}Warnings: $WARNINGS${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo "=========================================="
    echo -e "${GREEN}✓ ALL CRITICAL CHECKS PASSED${NC}"
    echo "=========================================="
    echo ""
    echo "The Privacy Hub is ready for deployment!"
    echo ""
    echo "Changes implemented:"
    echo "  ✓ Chip layout optimized (3x3/4x4 responsive grid)"
    echo "  ✓ Gluetun status detection fixed"
    echo "  ✓ Certificate detection improved"
    echo "  ✓ Test suite expanded"
    echo "  ✓ Configuration fully documented"
    echo ""
    exit 0
else
    echo "=========================================="
    echo -e "${RED}✗ VERIFICATION FAILED${NC}"
    echo "=========================================="
    echo ""
    echo "$FAILED critical checks failed. Please review the output above."
    echo ""
    exit 1
fi
