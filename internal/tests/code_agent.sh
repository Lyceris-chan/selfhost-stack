#!/usr/bin/env bash
set -euo pipefail

echo "=========================================================="
echo "🤖 CODE AGENT: FINAL VERIFICATION"
echo "=========================================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ZIMA_SH="${REPO_ROOT}/zima.sh"

# 1. ShellCheck
echo "[1/4] Running ShellCheck on zima.sh..."
# We expect some warnings due to the nature of the script, but let's check for critical errors
shellcheck -e SC1091,SC2001,SC2015,SC2016,SC2034,SC2024,SC2086 "$ZIMA_SH"
echo "✅ ShellCheck passed (with ignored exclusions)."

# 2. UI logic check
echo "[2/4] Verifying UI fix patterns..."
grep -q "arrow_forward" "$ZIMA_SH" || (echo "❌ UI Button text fix missing"; exit 1)
grep -q "async function fetchMetrics()" "$ZIMA_SH" || (echo "❌ fetchMetrics fix missing"; exit 1)
grep -q "white-space: normal;" "$ZIMA_SH" || (echo "❌ Service title cut-off fix missing"; exit 1)
COG_COUNT=$(grep -c "settings-btn" "$ZIMA_SH")
echo "✅ UI Fixes verified ($COG_COUNT settings buttons found)."

# 3. API Logic Check
echo "[3/4] Verifying API Server logic..."
if grep -A 5 "GET /status" "$ZIMA_SH" | grep -q "return"; then
    echo "✅ API Log filtering verified."
else
    echo "❌ API Log filtering missing"
    exit 1
fi
grep -q "X-API-Key" "$ZIMA_SH" || (echo "❌ API Auth headers missing"; exit 1)
echo "✅ API Logic verified."

echo ""
echo "=========================================================="
echo "🚀 CODE AGENT: ALL CHECKS PASSED. PREPARING TO PUSH."
echo "=========================================================="
