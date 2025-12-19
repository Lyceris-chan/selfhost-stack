#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")"/.. && pwd)"
TESTS_DIR="$ROOT_DIR/tests/puppeteer"

print_header() {
  printf "\n=== %s ===\n" "$1"
}

if ! command -v shellcheck >/dev/null 2>&1; then
  printf "shellcheck is required but not installed.\nInstall it with your package manager (apt/yum/brew).\n"
  exit 1
fi

print_header "ShellCheck"
shellcheck "$ROOT_DIR/zima.sh"

print_header "Puppeteer Tests"
cd "$TESTS_DIR"
npm install

# Build environment overrides; empty by default but allow the caller to set values
BREEZEWIKI_TEST_URL=${BREEZEWIKI_TEST_URL:-}
BREEZEWIKI_EXPECTED_TEXT=${BREEZEWIKI_EXPECTED_TEXT:-}
RIMGO_TEST_URL=${RIMGO_TEST_URL:-}
WIKILESS_TEST_URL=${WIKILESS_TEST_URL:-}
INVIDIOUS_TEST_URL=${INVIDIOUS_TEST_URL:-}

# Similar for other envs? Node script uses env var not CLI, so just export
export BREEZEWIKI_TEST_URL BREEZEWIKI_EXPECTED_TEXT RIMGO_TEST_URL WIKILESS_TEST_URL INVIDIOUS_TEST_URL

# npm test itself uses run-tests.js; we rely on env vars being set above
npm test
