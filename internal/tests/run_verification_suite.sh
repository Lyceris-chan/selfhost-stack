#!/usr/bin/env bash
# ==============================================================================
# 🛡️ PRIVACY HUB: PROFESSIONAL VERIFICATION SUITE
# ==============================================================================
# Orchestrates full stack verification including:
# 1. Static Analysis (ShellCheck)
# 2. Build Pipeline Integrity (Dashboard/Compose generation)
# 3. UI/UX Functional Requirements (Puppeteer/Headless Chrome)
# 4. API Logic & Filtering Verification
# ==============================================================================

set -euo pipefail

# Configuration
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${ROOT_DIR}/../.." && pwd)"
PORT="${PORT:-8099}"
DASHBOARD_URL="http://127.0.0.1:${PORT}/dashboard.html"
REPORT_FILE="${ROOT_DIR}/VERIFICATION_REPORT.md"

# Colors for professional output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_status() { echo -e "${BLUE}[TEST]${NC} $1"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; }

cleanup() {
  log_status "Cleaning up test environment..."
  if [[ -n "${SERVER_PID:-}" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID"
  fi
  rm -f "${ROOT_DIR}/dashboard.html"
}

trap cleanup EXIT

# 1. Initialization
cd "$ROOT_DIR"
echo "# System Verification Report" > "$REPORT_FILE"
echo "Generated: $(date)" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# 2. Setup Assets
log_status "Setting up local test assets..."
bash "$ROOT_DIR/setup_assets.sh" > /dev/null

# 3. Build Verification
log_status "Verifying dashboard generation pipeline..."
if python3 generate_dashboard.py > /dev/null 2>&1; then
    log_pass "Dashboard generated successfully."
    echo "- [x] Dashboard Build Pipeline: PASS" >> "$REPORT_FILE"
else
    log_fail "Dashboard generation failed."
    echo "- [ ] Dashboard Build Pipeline: FAIL" >> "$REPORT_FILE"
    exit 1
fi

# 4. Start Mock Environment
log_status "Starting local mock server on port $PORT..."
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$ROOT_DIR" > /tmp/verification_http.log 2>&1 &
SERVER_PID=$!
sleep 2

if ! kill -0 "$SERVER_PID" 2>/dev/null; then
  log_fail "Failed to start local server."
  exit 1
fi

# 5. Execute Component Tests
export DASHBOARD_URL
export MOCK_API=1
export MOCK_SERVICE_PAGES=1

log_status "Running Static Analysis & Pattern Matching..."
if bash "$ROOT_DIR/code_agent.sh"; then
    log_pass "Code Agent checks passed."
    echo "- [x] Static Analysis (ShellCheck): PASS" >> "$REPORT_FILE"
    echo "- [x] UI Pattern Matching: PASS" >> "$REPORT_FILE"
else
    log_fail "Code Agent checks failed."
    echo "- [ ] Static Analysis / Pattern Matching: FAIL" >> "$REPORT_FILE"
    exit 1
fi

log_status "Running Full UI Functional Suite..."
if node test_user_interactions.js; then
    log_pass "UI Functional tests passed."
    echo "- [x] UI Interaction Suite: PASS" >> "$REPORT_FILE"
else
    log_fail "UI Functional tests failed."
    echo "- [ ] UI Interaction Suite: FAIL" >> "$REPORT_FILE"
    exit 1
fi

log_status "Verifying Layout & Responsiveness..."
if node test_ui_layout.js; then
    log_pass "Layout verification passed."
    echo "- [x] Responsive Layout Verification: PASS" >> "$REPORT_FILE"
else
    log_fail "Layout verification failed."
    echo "- [ ] Responsive Layout Verification: FAIL" >> "$REPORT_FILE"
    exit 1
fi

log_status "Verifying Service Detail Interactions..."
if node test_service_pages_puppeteer.js; then
    log_pass "Service detail tests passed."
    echo "- [x] Service Management Logic: PASS" >> "$REPORT_FILE"
else
    log_fail "Service detail tests failed."
    echo "- [ ] Service Management Logic: FAIL" >> "$REPORT_FILE"
    exit 1
fi

echo ""
echo "=========================================================="
log_pass "VERIFICATION COMPLETE: ALL SYSTEMS NOMINAL"
echo "=========================================================="
echo "Detailed results available in: $REPORT_FILE"