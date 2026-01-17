# Privacy Hub - Master Testing Suite

Comprehensive automated testing framework for the Privacy Hub project. This suite ensures system integrity, service functionality, and privacy compliance.

## 📋 Test Coverage Structure

The testing pipeline consists of 6 sequential stages:

### 1. Integrity Audit
**File**: `test/verify_integrity.py`
- Verifies project directory structure (lib, config, data).
- Checks file permissions and existence of critical assets.
- Validates configuration file syntax.

### 2. Functional & API Suite
**File**: `test/test_runner.py`
- Python-based health check for all 30+ services.
- Validates HTTP response codes (200 OK) for service endpoints.
- Checks API health endpoints (e.g., `/api/health`, `/api/server/ping`).

### 3. Integration Tests (User Simulation)
**File**: `test/test_integration.js`
- **Technology**: Puppeteer (Headless Chrome).
- **Scope**: Simulates real user interactions with privacy frontends.
- **Key Tests**:
    - **Invidious**: Search for "privacy" and verify video player loads.
    - **SearXNG**: Execute search queries and verify result rendering.
    - **Breezewiki/Redlib**: Navigate to articles/subreddits and check content.
    - **DNS**: Verifies internal DNS resolution for containers.

### 4. UI/UX Audit
**File**: `test/test_dashboard.js`
- Validates the Management Dashboard.
- Checks **Material Design 3** compliance (grid layout, spacing).
- Tests responsive behavior (mobile vs desktop).
- Verifies theme toggling (Light/Dark mode) and admin login flows.

### 5. Specialized Interaction Tests
**File**: `test/test_extended_interactions.js`
- Deep-dive tests for complex workflows.
- Verifies WireGuard client creation and config download.
- Checks specific application logic beyond basic loading.

### 6. Functional Operations (Admin)
**File**: `test/test_functional_ops.js`
- Tests backend administrative endpoints.
- Verifies:
    - **Updates**: Triggering service updates.
    - **Migrations**: Database migration logic.
    - **Rollbacks**: Reverting to previous versions.
    - **Authentication**: Admin session validation.

## 🚀 Running Tests

### Option 1: Full Deployment Test (Recommended)
This script simulates a fresh install, deploys the stack, and runs all test suites in order.

```bash
# Export your WireGuard config (base64 encoded)
export WG_CONF_B64=$(cat your-wg-config.conf | base64 -w0)

# Run the master test runner
./test/full_deployment_test.sh
```

### Option 2: Run Individual Suites
You can run specific test layers against an already running deployment.

```bash
# 1. Integrity
python3 test/verify_integrity.py

# 2. Integration (Frontends)
node test/test_integration.js

# 3. Dashboard UI
node test/test_dashboard.js

# 4. Functional Ops (Admin)
node test/test_functional_ops.js
```

## 📊 Test Results & Reports

After a full run, reports are generated in `test/reports/`:

*   **`integration_test_report_*.json`**: Detailed pass/fail status for every service.
*   **`container_logs_*.json`**: Captured logs from all containers for debugging.
*   **`FINAL_TEST_REPORT.md`**: Summary of the entire deployment and test cycle.

### Common Failure Scenarios

*   **Gluetun Unhealthy**: Often due to missing or invalid WireGuard configuration. Check `wg.conf`.
*   **DNS Resolution Failed**: If Invidious/Redlib fail to load, the VPN tunnel might be blocking UDP.
*   **Timeout**: Services like Immich take longer to start on slow hardware.

## 🛠️ Development

### Adding a New Test
1.  Open `test/test_integration.js`.
2.  Add your service to the `SERVICES` object.
3.  Define a new test function (e.g., `testMyService`).
4.  Add the test function name to your service's `tests` array.

---

**Test Suite Version**: 3.0.0
**Last Updated**: 2026-01-17