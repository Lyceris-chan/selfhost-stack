# Privacy Hub Test Suite

This directory contains the comprehensive test suite for the Privacy Hub project.

## Test Structure

The test suite is organized into three main test files:

### 1. Dashboard Tests (`test_dashboard.js`)
Comprehensive end-to-end testing for the dashboard web interface.

**Coverage:**
- User interface interactions (theme, filters, search, privacy mode)
- Admin authentication and authorization
- Service management (updates, rollbacks, migrations)
- System operations (backups, restores, certificates)
- Container monitoring and logs
- Settings and configuration

**Run:**
```bash
npm run test:dashboard
```

### 2. Integration Tests (`test_integration.js`)
Full-stack integration testing with service connectivity verification.

**Coverage:**
- HTTP connectivity checks for all services
- Browser-based UI verification
- Screenshot capture for visual validation
- Console log monitoring
- Functional tests (search, navigation)

**Run:**
```bash
npm run test:integration
```

### 3. WireGuard Tests (`test_wireguard.js`)
WireGuard VPN management and dashboard integration tests.

**Coverage:**
- Profile listing and display
- Profile switching functionality
- Active profile indicators
- VPN status monitoring
- Client connection tracking

**Run:**
```bash
npm run test:wireguard
```

## Running Tests

### Run All Tests
```bash
npm run test:all
```

### Run Individual Test Suites
```bash
# Dashboard tests only
npm run test:dashboard

# Integration tests only
npm run test:integration

# WireGuard tests only
npm run test:wireguard
```

### Environment Configuration

Tests can be configured via environment variables:

```bash
# Custom dashboard URL
TEST_BASE_URL=http://localhost:8088 npm run test:dashboard

# Custom API URL
API_URL=http://localhost:55555 npm run test:dashboard

# Admin password
ADMIN_PASSWORD=your_password npm run test:dashboard

# Show browser (disable headless mode)
HEADLESS=false npm run test:dashboard
```

## Test Output

### Screenshots
Test screenshots are saved to:
- Dashboard tests: `test/screenshots/admin_complete/`
- Integration tests: `test/screenshots/`

### Reports
JSON test reports are saved to:
- `test/reports/`

### Logs
Console output is displayed during test execution and can be redirected:
```bash
npm run test:dashboard 2>&1 | tee test_output.log
```

## Requirements

- Node.js 14+
- npm or bun package manager
- Running Privacy Hub deployment

## Installation

```bash
cd test
npm install
```

## Test Development

### Adding New Tests

1. Add test function to appropriate test file
2. Follow existing naming conventions: `testFeatureName()`
3. Use `runTest()` wrapper for automatic pass/fail tracking
4. Add screenshot capture with `screenshot(page, 'description')`
5. Document test purpose with JSDoc comments

### Test Best Practices

- Use explicit waits instead of arbitrary timeouts
- Capture screenshots for visual verification
- Check for both positive and negative cases
- Handle async operations properly
- Clean up resources in finally blocks
- Log meaningful error messages

## Troubleshooting

### Tests Failing

1. Verify Privacy Hub is deployed and running:
   ```bash
   docker ps | grep hub-
   ```

2. Check service health:
   ```bash
   curl http://localhost:8088/
   curl http://localhost:55555/health
   ```

3. Verify correct URLs in test configuration

4. Check browser console logs in test output

### Permission Errors

Ensure test directories have proper permissions:
```bash
chmod -R 755 test/screenshots test/reports
```

## Contributing

When adding new tests:
1. Follow Google JavaScript Style Guide
2. Add comprehensive JSDoc documentation
3. Include usage examples
4. Update this README with new test coverage

## License

MIT
