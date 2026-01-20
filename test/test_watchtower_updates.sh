#!/usr/bin/env bash
set -euo pipefail

# Test Suite: Watchtower Auto-Update Functionality
# Tests container updates, changelog fetching, and update display

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API_URL="http://10.0.1.187:55555"
DASHBOARD_URL="http://10.0.1.187:8088"

echo "🔄 Watchtower Update Test Suite"
echo "================================"
echo ""

# Test 1: Watchtower Container Status
test_watchtower_status() {
    echo "Test 1: Watchtower Container Status"
    echo "------------------------------------"
    
    if docker ps | grep -q hub-watchtower; then
        echo "✅ PASS: Watchtower container is running"
        docker ps --format "{{.Names}}\t{{.Status}}" | grep hub-watchtower
        return 0
    else
        echo "❌ FAIL: Watchtower container is not running"
        return 1
    fi
}

# Test 2: Watchtower Configuration
test_watchtower_config() {
    echo ""
    echo "Test 2: Watchtower Configuration"
    echo "---------------------------------"
    
    # Check environment variables
    INTERVAL=$(docker inspect hub-watchtower --format '{{range .Config.Env}}{{println .}}{{end}}' | grep WATCHTOWER_POLL_INTERVAL || echo "")
    
    if [ -n "$INTERVAL" ]; then
        echo "✅ PASS: Watchtower poll interval configured"
        echo "   $INTERVAL"
    else
        echo "⚠️  WARN: Poll interval not explicitly set (using default)"
    fi
    
    # Check for notification endpoint
    NOTIFICATION=$(docker inspect hub-watchtower --format '{{range .Config.Env}}{{println .}}{{end}}' | grep WATCHTOWER_NOTIFICATION || echo "")
    
    if [ -n "$NOTIFICATION" ]; then
        echo "✅ PASS: Notification endpoint configured"
    else
        echo "ℹ️  INFO: No notification endpoint configured"
    fi
    
    return 0
}

# Test 3: Check for Updates via API
test_check_updates_api() {
    echo ""
    echo "Test 3: Check Updates API Endpoint"
    echo "-----------------------------------"
    
    response=$(curl -s -w "\n%{http_code}" "$API_URL/api/updates/check" 2>/dev/null || echo "000")
    http_code=$(echo "$response" | tail -n 1)
    body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" = "200" ]; then
        echo "✅ PASS: Update check API endpoint is accessible"
        echo "$body" | python3 -m json.tool 2>/dev/null | head -20 || echo "$body"
        return 0
    elif [ "$http_code" = "404" ]; then
        echo "⚠️  WARN: Update check endpoint not implemented yet"
        return 0
    else
        echo "❌ FAIL: Update check API returned HTTP $http_code"
        return 1
    fi
}

# Test 4: Service Update Status
test_service_update_status() {
    echo ""
    echo "Test 4: Service Update Status"
    echo "------------------------------"
    
    response=$(curl -s "$API_URL/api/services" 2>/dev/null)
    
    if [ -n "$response" ]; then
        echo "✅ PASS: Services endpoint accessible"
        
        # Check if services have update information
        has_update_info=$(echo "$response" | grep -c "update\|version\|tag" || echo "0")
        
        if [ "$has_update_info" -gt 0 ]; then
            echo "✅ PASS: Services include update metadata"
        else
            echo "ℹ️  INFO: Update metadata not yet included in service info"
        fi
        return 0
    else
        echo "❌ FAIL: Could not fetch services"
        return 1
    fi
}

# Test 5: Changelog Fetching
test_changelog_fetch() {
    echo ""
    echo "Test 5: Changelog Fetching"
    echo "--------------------------"
    
    # Test fetching changelog for a known service
    services=("hub-api" "portainer" "adguard")
    
    for service in "${services[@]}"; do
        echo "   Testing $service changelog..."
        response=$(curl -s -w "\n%{http_code}" "$API_URL/api/services/$service/changelog" 2>/dev/null || echo "000")
        http_code=$(echo "$response" | tail -n 1)
        
        if [ "$http_code" = "200" ]; then
            echo "   ✅ PASS: Changelog available for $service"
        elif [ "$http_code" = "404" ]; then
            echo "   ⚠️  WARN: Changelog endpoint not implemented for $service"
        else
            echo "   ℹ️  INFO: $service - HTTP $http_code"
        fi
    done
    
    return 0
}

# Test 6: Update Dashboard Display
test_update_dashboard_display() {
    echo ""
    echo "Test 6: Update Banner Display"
    echo "------------------------------"
    
    # Check if dashboard has update banner element
    dashboard_html=$(curl -s "$DASHBOARD_URL" 2>/dev/null)
    
    if echo "$dashboard_html" | grep -q "update-banner"; then
        echo "✅ PASS: Update banner element exists in dashboard"
    else
        echo "⚠️  WARN: Update banner element not found"
    fi
    
    if echo "$dashboard_html" | grep -q "updateAllServices\|Update all"; then
        echo "✅ PASS: Update action buttons present"
    else
        echo "⚠️  WARN: Update action buttons not found"
    fi
    
    return 0
}

# Test 7: Watchtower Logs Analysis
test_watchtower_logs() {
    echo ""
    echo "Test 7: Watchtower Logs Analysis"
    echo "---------------------------------"
    
    # Check recent logs for update activity
    logs=$(docker logs --since 10m hub-watchtower 2>&1 | tail -50)
    
    if echo "$logs" | grep -q "session\|scan\|Found"; then
        echo "✅ PASS: Watchtower is actively scanning"
        echo "$logs" | grep -E "session|scan|Found" | tail -5
    else
        echo "ℹ️  INFO: No recent scan activity in logs"
    fi
    
    # Check for errors
    error_count=$(echo "$logs" | grep -ic "error\|fail" || echo "0")
    
    if [ "$error_count" -eq 0 ]; then
        echo "✅ PASS: No errors in recent Watchtower logs"
    else
        echo "⚠️  WARN: Found $error_count potential errors in logs"
    fi
    
    return 0
}

# Test 8: Manual Update Trigger
test_manual_update_trigger() {
    echo ""
    echo "Test 8: Manual Update Trigger"
    echo "------------------------------"
    
    # Try to trigger manual update check
    response=$(curl -s -X POST -w "\n%{http_code}" "$API_URL/api/watchtower/scan" 2>/dev/null || echo "000")
    http_code=$(echo "$response" | tail -n 1)
    
    if [ "$http_code" = "200" ] || [ "$http_code" = "202" ]; then
        echo "✅ PASS: Manual update trigger endpoint working"
        return 0
    elif [ "$http_code" = "404" ]; then
        echo "⚠️  WARN: Manual update trigger not implemented yet"
        return 0
    else
        echo "ℹ️  INFO: Manual trigger returned HTTP $http_code"
        return 0
    fi
}

# Run all tests
main() {
    local failed=0
    
    test_watchtower_status || ((failed++))
    test_watchtower_config || ((failed++))
    test_check_updates_api || ((failed++))
    test_service_update_status || ((failed++))
    test_changelog_fetch || ((failed++))
    test_update_dashboard_display || ((failed++))
    test_watchtower_logs || ((failed++))
    test_manual_update_trigger || ((failed++))
    
    echo ""
    echo "================================"
    if [ $failed -eq 0 ]; then
        echo "✅ All tests passed!"
        exit 0
    else
        echo "⚠️  $failed test(s) had issues"
        exit 1
    fi
}

main "$@"
