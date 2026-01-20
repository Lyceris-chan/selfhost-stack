# Testing Guide

This directory contains comprehensive test suites for the ZimaOS Privacy Hub dashboard and infrastructure.

## Test Files

### Core Test Suites

1. **test_dashboard.js**
   - Comprehensive dashboard interaction tests
   - Tests all user and admin interactions
   - Verifies all services show up on dashboard
   - Monitors browser console for errors
   - Checks container logs for issues

2. **test_integration.js**
   - Integration tests for the full stack
   - Tests API endpoints
   - Validates service interactions

### Temporary Test Utilities (auto-created during testing)

3. **tmp_rovodev_container_log_checker.js**
   - Analyzes Docker container logs for errors
   - Filters out benign messages
   - Provides detailed error reporting

4. **tmp_rovodev_visual_layout_test.js**
   - Tests dashboard visual layout
   - Verifies category button visibility and outlines
   - Checks card stretching behavior
   - Validates responsive design

5. **tmp_rovodev_comprehensive_verification.sh**
   - Static verification of code changes
   - Validates CSS, shell scripts, and README
   - Checks Docker environment

### Test Runners

- **run_comprehensive_tests.sh** - Runs all test suites in sequence
- **run_tests.sh** - Original test runner

## Running Tests

### Quick Start

```bash
# Run all tests
./run_comprehensive_tests.sh

# Or use the original runner
./run_tests.sh
```

### Individual Test Suites

```bash
# Static verification only
bash tmp_rovodev_comprehensive_verification.sh

# Visual layout tests (requires dashboard to be running)
node tmp_rovodev_visual_layout_test.js

# Container log analysis
node tmp_rovodev_container_log_checker.js

# Full dashboard tests
node test_dashboard.js
```

## Configuration

Tests use environment variables for configuration:

```bash
export TEST_BASE_URL="http://localhost:8088"  # Dashboard URL
export API_URL="http://localhost:55555"        # Hub API URL
export ADMIN_PASSWORD="your-password"          # Admin password
export HEADLESS="true"                         # Run browser tests headless
```

## Test Results

- **Screenshots**: Saved to `test/screenshots/`
- **Reports**: Saved to `test/reports/`
- **Logs**: Output to console and log files

## Cleanup

Temporary test files (prefixed with `tmp_rovodev_`) can be safely deleted after testing:

```bash
rm -f tmp_rovodev_*
```

These files are automatically created during testing and are not committed to version control.

## Requirements

- **Node.js**: For JavaScript tests
- **Puppeteer**: Browser automation (installed via npm)
- **Docker**: For container tests
- **curl**: For HTTP checks
- **bash**: For shell scripts

Install dependencies:

```bash
npm install
```

## Style Guide Compliance

All test code follows:
- **Google JavaScript Style Guide** for .js files
- **Google Shell Style Guide** for .sh files
- Proper JSDoc comments
- Error handling best practices
- No hardcoded secrets

## Verification Checklist

The test suite verifies:

- ✅ All expected services appear on dashboard
- ✅ Category buttons have proper outlines (2px borders)
- ✅ Card layout stretches to fill rows
- ✅ No duplicate log messages
- ✅ Browser console has no errors
- ✅ Container logs are healthy
- ✅ Dashboard is accessible
- ✅ API endpoints respond correctly
- ✅ Responsive design works at multiple viewports
- ✅ Visual consistency across components
