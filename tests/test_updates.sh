#!/usr/bin/env bash
# 🧪 TEST: Updates & Migration Logic
# This script verifies that hub-api correctly detects source updates and handles migrations.

set -euo pipefail

BASE_DIR="/DATA/AppData/privacy-hub"
SRC_DIR="$BASE_DIR/sources"
API_URL="http://localhost:8081/api"

log() { echo -e "\e[34m[TEST]\e[0m $1"; }

# 1. Setup Mock Repo Update
log "Setting up mock repository update..."
rm -rf "$SRC_DIR/mock-service"
mkdir -p "$SRC_DIR/mock-service"
cd "$SRC_DIR/mock-service"
git init -q
git config user.email "test@example.com"
git config user.name "Tester"
echo "v1" > version.txt
git add version.txt
git commit -m "initial v1" -q

# Create a "remote" by cloning locally
mkdir -p /tmp/mock-remote
cd /tmp/mock-remote
git init --bare -q

cd "$SRC_DIR/mock-service"
git remote add origin /tmp/mock-remote
git push origin HEAD -q

# Make a change in the "remote"
cd /tmp
git clone /tmp/mock-remote /tmp/mock-temp -q
cd /tmp/mock-temp
echo "v2" > version.txt
git add . && git commit -m "v2" -q
git push origin HEAD -q

# 2. Check hub-api detection
log "Checking hub-api /updates detection..."
# We need to ensure hub-api container is running.
# In a real environment, we'd wait for it.
# For this test, we assume the environment is already deployed.

UPDATES=$(curl -s "$API_URL/updates")
if echo "$UPDATES" | grep -q "mock-service"; then
    log "✅ PASS: hub-api detected pending update for mock-service."
else
    log "❌ FAIL: hub-api did not detect update. Output: $UPDATES"
    # Note: Hub-api runs inside container, it won't see /tmp/mock-remote unless mounted.
    # This test might need adjustment for containerized execution.
fi

# 3. Test Migration Endpoint
log "Testing foolproof migration for Invidious..."
MIGRATE_RES=$(curl -s "$API_URL/migrate?service=invidious")
if echo "$MIGRATE_RES" | grep -q '"success":true'; then
    log "✅ PASS: Invidious migration triggered successfully."
else
    log "❌ FAIL: Migration failed. Output: $MIGRATE_RES"
fi

# 4. Cleanup
log "Cleaning up mock artifacts..."
rm -rf /tmp/mock-remote /tmp/mock-temp "$SRC_DIR/mock-service"

log "Update & Migration tests complete."
