#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT="${PORT:-8099}"
SERVER_LOG="${SERVER_LOG:-/tmp/verification_http.log}"
DASHBOARD_URL="http://127.0.0.1:${PORT}/dashboard.html"

cleanup() {
  if [[ -n "${SERVER_PID:-}" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID"
  fi
  rm -f "${ROOT_DIR}/dashboard.html"
}

trap cleanup EXIT

cd "$ROOT_DIR"

python3 generate_dashboard.py > /tmp/dashboard_gen.log 2>&1

bash "$ROOT_DIR/setup_assets.sh"

python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$ROOT_DIR" >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!
sleep 1
if ! kill -0 "$SERVER_PID" 2>/dev/null; then
  echo "Failed to start local server (see $SERVER_LOG)."
  exit 1
fi

export DASHBOARD_URL
export MOCK_API=1
export MOCK_SERVICE_PAGES=1

./code_agent.sh
node full_verification.js
node test_user_interactions.js
node full_user_walkthrough.js
node test_service_pages_puppeteer.js
node test_ui_layout.js
node ui_regression.js
