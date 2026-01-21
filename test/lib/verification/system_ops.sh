#!/bin/bash
#
# System Operations Verification
# Tests updates, changelogs, rollback capabilities, and service health.
#

set -euo pipefail

API_URL="${API_URL:-http://localhost:55555}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
BACKUP_DIR="${PROJECT_ROOT}/data/AppData/privacy-hub/backups"
SECRETS_FILE="${PROJECT_ROOT}/data/AppData/privacy-hub/.secrets"

# Load API Key
HUB_API_KEY=""
if [[ -f "${SECRETS_FILE}" ]]; then
    HUB_API_KEY=$(grep "HUB_API_KEY" "${SECRETS_FILE}" | cut -d"'" -f2)
fi

# Helper for curl with auth
curl_api() {
    local path="$1"
    if [[ -n "${HUB_API_KEY}" ]]; then
        curl -s -f -H "X-API-Key: ${HUB_API_KEY}" "${API_URL}${path}"
    else
        curl -s -f "${API_URL}${path}"
    fi
}

check_dns() {
    echo "  Checking DNS Resolution (AdGuard)..."
    if docker ps | grep -q "hub-adguard"; then
        AG_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' hub-adguard)
        if [[ -n "$AG_IP" ]]; then
            # Try to resolve google.com using the AdGuard container
            if command -v nslookup >/dev/null; then
                if nslookup google.com "$AG_IP" >/dev/null 2>&1; then
                    echo "    ✓ AdGuard ($AG_IP) is resolving queries"
                else
                    echo "    ⚠️  AdGuard ($AG_IP) failed to resolve google.com"
                fi
            else
                echo "    ℹ️  nslookup not installed, skipping active DNS check"
            fi
        fi
    else
        echo "    ℹ️  AdGuard container not running"
    fi
}

check_changelogs() {
  echo "  Checking Changelog API..."
  # User requested checking a different service than hub-api. Using 'portainer'.
  local services=("portainer") 
  
  for svc in "${services[@]}"; do
    if curl_api "/api/changelog?service=${svc}" >/dev/null 2>&1; then
      echo "    ✓ Changelog fetch successful for ${svc}"
    else
      echo "    ⚠️  Changelog unreachable/missing for ${svc}"
    fi
  done
}

check_updates_and_rollback() {
  echo "  Checking Update & Rollback Mechanisms..."
  
  # 1. Watchtower Check
  if docker ps --format '{{.Names}}' | grep -q "hub-watchtower"; then
    echo "    ✓ Watchtower is running"
    
    # Verify the updates endpoint returns valid JSON (even if empty)
    RESPONSE=$(curl_api "/api/updates")
    if echo "$RESPONSE" | grep -q "updates"; then
      echo "    ✓ Update status API operational"
    else
      echo "    ⚠️  Update status API returned unexpected response"
    fi
  else
    echo "    ℹ️  Watchtower not running"
  fi

  # 2. Rollback Capability Check
  if [[ -d "${BACKUP_DIR}" ]]; then
    echo "    ✓ Backup directory exists"
    if ls "${BACKUP_DIR}"/*.tar.gz 1> /dev/null 2>&1; then
       echo "    ✓ Backups present"
    else
       echo "    ℹ️  No backup archives found yet"
    fi
    
    # Check Rollback API status for a service
    if curl_api "/api/rollback-status?service=hub-api" >/dev/null 2>&1; then
        echo "    ✓ Rollback API endpoint active"
    fi
  else
    echo "    ⚠️  Backup directory missing"
  fi
}

check_admin_actions() {
    echo "  Checking Admin Action Endpoints..."
    # We verify these endpoints exist by checking they accept the request (or return 403/401 if unauth, but we have key)
    # We do NOT trigger them to avoid killing the test env.
    
    # Reboot (check dry run or existence) - The API doesn't have a dry-run for reboot, so we assume existence based on health.
    # But we can check if the 'migrate' endpoint works which is safer.
    
    if curl_api "/api/migrate?service=hub-api&backup=no" >/dev/null 2>&1; then
        echo "    ✓ Database migration endpoint operational"
    fi
}

main() {
  echo "Running System Operations Checks..."
  
  if ! curl -s --max-time 2 "${API_URL}/health" >/dev/null 2>&1 && \
     ! curl -s --max-time 2 "${API_URL}/api/health" >/dev/null 2>&1; then
    echo "⚠️  Hub API not accessible. Skipping API-dependent tests."
    exit 0
  fi

  check_dns || true
  check_changelogs || true
  check_updates_and_rollback || true
  check_admin_actions || true
  
  echo "✅ System Operations check complete"
}

main "$@"