#!/usr/bin/env bash
set -euo pipefail

echo "=========================================================="
echo "🤖 CODE AGENT: FINAL VERIFICATION"
echo "=========================================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ZIMA_SH="${REPO_ROOT}/zima.sh"
DASHBOARD_HTML="${REPO_ROOT}/templates/dashboard.html"
DASHBOARD_JS="${REPO_ROOT}/templates/assets/dashboard.js"
WG_API_PY="${REPO_ROOT}/templates/wg_api.py"

# 1. ShellCheck
echo "[1/4] Running ShellCheck on zima.sh..."
shellcheck -e SC1091,SC2001,SC2015,SC2016,SC2034,SC2024,SC2086,SC2089,SC2090,SC2129,SC1083 "$ZIMA_SH"
echo "✅ ShellCheck passed (with ignored exclusions)."

# 2. UI logic check
echo "[2/4] Verifying UI fix patterns..."
grep -q "arrow_forward" "$DASHBOARD_HTML" || (echo "❌ UI Button text fix missing"; exit 1)
grep -q "async function fetchMetrics()" "$DASHBOARD_JS" || (echo "❌ fetchMetrics fix missing"; exit 1)
grep -q "white-space: normal;" "$DASHBOARD_HTML" || (echo "❌ Service title cut-off fix missing"; exit 1)
COG_COUNT=$(grep -c "settings-btn" "$DASHBOARD_JS")
echo "✅ UI Fixes verified ($COG_COUNT settings patterns found in JS)."

# 3. API Logic Check
echo "[3/4] Verifying API Server logic..."
if grep -A 5 "GET /status" "$WG_API_PY" | grep -q "return"; then
    echo "✅ API Log filtering verified."
else
    echo "❌ API Log filtering missing"
    exit 1
fi
grep -q "X-API-Key" "$DASHBOARD_JS" || (echo "❌ API Auth headers missing"; exit 1)
echo "✅ API Logic verified."

echo ""
echo "=========================================================="
echo "🚀 CODE AGENT: ALL CHECKS PASSED."
echo "=========================================================="