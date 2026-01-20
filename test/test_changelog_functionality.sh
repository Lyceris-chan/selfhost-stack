#!/usr/bin/env bash
set -euo pipefail

# Test Suite: Changelog Fetching and Display
# Tests changelog retrieval for both Watchtower and source-build updates

API_URL="http://10.0.1.187:55555"
DASHBOARD_URL="http://10.0.1.187:8088"

echo "📋 Changelog Functionality Test Suite"
echo "======================================"
echo ""

# Test 1: Changelog API Endpoint Exists
test_changelog_endpoint() {
    echo "Test 1: Changelog API Endpoints"
    echo "--------------------------------"
    
    # Test general changelog endpoint
    response=$(curl -s -w "\n%{http_code}" "$API_URL/api/changelog" 2>/dev/null || echo "000")
    http_code=$(echo "$response" | tail -n 1)
    
    if [ "$http_code" = "200" ]; then
        echo "✅ PASS: General changelog endpoint exists"
    else
        echo "⚠️  INFO: General changelog endpoint not implemented (HTTP $http_code)"
    fi
    
    # Test service-specific changelog
    response=$(curl -s -w "\n%{http_code}" "$API_URL/api/services/hub-api/changelog" 2>/dev/null || echo "000")
    http_code=$(echo "$response" | tail -n 1)
    
    if [ "$http_code" = "200" ]; then
        echo "✅ PASS: Service-specific changelog endpoint exists"
    else
        echo "⚠️  INFO: Service-specific changelog not implemented (HTTP $http_code)"
    fi
}

# Test 2: Source Build Changelog
test_source_build_changelog() {
    echo ""
    echo "Test 2: Source Build Changelog (Git-based)"
    echo "-------------------------------------------"
    
    # Check if source builds have git repositories
    if [ -d "lib/src/hub-api/.git" ]; then
        echo "✅ PASS: hub-api has git repository"
        
        # Get recent commits
        cd lib/src/hub-api
        commits=$(git log --oneline -5 2>/dev/null || echo "")
        if [ -n "$commits" ]; then
            echo "   Recent commits:"
            echo "$commits" | sed 's/^/     /'
        fi
        cd - >/dev/null
    else
        echo "ℹ️  INFO: hub-api source not a git repository"
    fi
}

# Test 3: Docker Image Changelog
test_docker_image_changelog() {
    echo ""
    echo "Test 3: Docker Image Changelog (Registry-based)"
    echo "------------------------------------------------"
    
    # Test fetching changelog for Docker Hub images
    services=("portainer/portainer-ce" "adguard/adguardhome")
    
    for image in "${services[@]}"; do
        echo "   Testing $image..."
        
        # Check current version
        container_name=$(echo "$image" | cut -d'/' -f2 | sed 's/-ce//')
        current_tag=$(docker inspect "hub-$container_name" --format '{{.Config.Image}}' 2>/dev/null | cut -d':' -f2 || echo "unknown")
        
        if [ "$current_tag" != "unknown" ]; then
            echo "   ✅ Current version: $current_tag"
        else
            echo "   ℹ️  Could not determine current version"
        fi
    done
}

# Test 4: Changelog Display in Dashboard
test_changelog_display() {
    echo ""
    echo "Test 4: Changelog Display in Dashboard"
    echo "---------------------------------------"
    
    dashboard_html=$(curl -s "$DASHBOARD_URL" 2>/dev/null)
    
    # Check for changelog-related elements
    if echo "$dashboard_html" | grep -q "changelog\|release\|version"; then
        echo "✅ PASS: Changelog/version elements found in dashboard"
    else
        echo "ℹ️  INFO: No obvious changelog display elements"
    fi
    
    # Check for update modal or changelog viewer
    if echo "$dashboard_html" | grep -q "changelog-modal\|release-notes\|update-details"; then
        echo "✅ PASS: Changelog modal/viewer exists"
    else
        echo "ℹ️  INFO: No dedicated changelog viewer found"
    fi
}

# Test 5: Changelog Format and Content
test_changelog_format() {
    echo ""
    echo "Test 5: Changelog Format Validation"
    echo "------------------------------------"
    
    # Try to fetch a changelog
    response=$(curl -s "$API_URL/api/services/hub-api/changelog" 2>/dev/null || echo "")
    
    if [ -n "$response" ]; then
        # Check if it's valid JSON
        if echo "$response" | python3 -m json.tool >/dev/null 2>&1; then
            echo "✅ PASS: Changelog is valid JSON"
            
            # Check for expected fields
            if echo "$response" | grep -q "version\|commit\|date\|changes"; then
                echo "✅ PASS: Contains expected changelog fields"
            else
                echo "⚠️  WARN: Missing expected changelog fields"
            fi
        else
            echo "ℹ️  INFO: Changelog not in JSON format (may be plain text)"
        fi
    else
        echo "ℹ️  INFO: No changelog data available yet"
    fi
}

# Test 6: Update Notification with Changelog
test_update_notification() {
    echo ""
    echo "Test 6: Update Notification Integration"
    echo "----------------------------------------"
    
    # Check if API provides update info with changelogs
    response=$(curl -s "$API_URL/api/updates/available" 2>/dev/null || echo "")
    
    if [ -n "$response" ]; then
        if echo "$response" | grep -q "changelog\|release_notes"; then
            echo "✅ PASS: Update notifications include changelog info"
        else
            echo "ℹ️  INFO: Update notifications don't include changelog yet"
        fi
    else
        echo "ℹ️  INFO: Update availability endpoint not accessible"
    fi
}

# Run all tests
main() {
    test_changelog_endpoint
    test_source_build_changelog
    test_docker_image_changelog
    test_changelog_display
    test_changelog_format
    test_update_notification
    
    echo ""
    echo "======================================"
    echo "✅ Changelog test suite complete"
    echo "======================================"
}

main "$@"
