# Privacy Hub - Testing Suite

Comprehensive integration testing framework for the Privacy Hub project.

## 📋 Test Coverage

### Services Tested (31 total)

**Core Infrastructure:**
- Dashboard (Nginx + HTML/CSS/JS)
- Hub API (FastAPI backend)
- AdGuard Home (DNS filtering)
- Unbound (DNS resolver)
- Docker Socket Proxy
- Gluetun (VPN gateway)
- WG-Easy (WireGuard VPN server)

**Privacy Frontend Services:**
- Invidious (YouTube) - Search + Video Playback
- Breezewiki (Wikipedia) - Wiki lookup + Search
- Redlib (Reddit) - Subreddit viewing
- SearXNG (Search) - Search functionality
- Scribe (Medium) - Article viewing
- AnonymousOverflow (StackOverflow) - Question search
- Rimgo (Imgur) - Image viewing
- Cobalt (Video Downloader)

**Productivity:**
- Memos (Note-taking)
- Portainer (Container management)
- Immich (Photo management)
- VERT (Transcription)

**Supporting Services:**
- PostgreSQL, Redis, Watchtower, etc.

## 🚀 Quick Start

### Prerequisites

```bash
# Install Node.js and npm
sudo apt-get install nodejs npm

# Install test dependencies
cd test
npm install
```

### Running Tests

**Option 1: Full Deployment Test (Recommended)**
```bash
# Set your WireGuard config
export WG_CONF_B64=$(cat your-wg-config.conf | base64 -w0)

# Run complete deployment + integration tests
./test/full_deployment_test.sh
```

**Option 2: Test Running Deployment**
```bash
# Test already deployed services
cd test
npm test
```

**Option 3: Dashboard Tests Only**
```bash
cd test
npm run test:dashboard
```

**Option 4: Extended Interactions**
```bash
cd test
npm run test:extended
```

## 📊 Test Types

### 1. Integration Tests (`integration_test_suite.js`)

**What it tests:**
- Service availability and loading
- HTTP status codes
- Page rendering
- Functional workflows (search, video playback, etc.)
- Browser console errors
- Container log analysis

**Services with functional tests:**
- ✅ Invidious: Search + video player validation
- ✅ Breezewiki: Wiki article lookup + search
- ✅ SearXNG: Search query execution
- ✅ Redlib: Subreddit page loading
- ✅ Dashboard: UI responsiveness + API connectivity

**Example test flow for Invidious:**
1. Navigate to homepage
2. Enter search query
3. Click first result
4. Verify video player loaded
5. Check video readyState
6. Capture screenshots at each step

### 2. Dashboard Tests (`test_dashboard_comprehensive.js`)

- Layout rendering
- Chip grid responsiveness (3x3/4x4)
- Filter functionality
- Theme toggling
- Admin authentication
- Certificate status display
- WireGuard management UI

### 3. Extended Interactions (`test_extended_interactions.js`)

- All user/admin interactions
- WireGuard tunnel generation
- Certificate validation
- Container status monitoring
- API endpoint validation

### 4. Full Deployment Test (`full_deployment_test.sh`)

Complete end-to-end workflow:
1. Clean previous deployment
2. Deploy with `zima.sh`
3. Wait for services to stabilize
4. Collect container logs
5. Run integration tests
6. Analyze logs for errors
7. Generate comprehensive report

## 📁 Test Outputs

### Directory Structure
```
test/
├── reports/
│   ├── integration_test_report_<timestamp>.json
│   ├── container_logs_<timestamp>.json
│   ├── log_analysis.txt
│   └── FINAL_TEST_REPORT.md
├── screenshots/
│   ├── <timestamp>_invidious_home.png
│   ├── <timestamp>_invidious_search_results.png
│   ├── <timestamp>_invidious_video_page.png
│   └── ... (screenshots for each test)
└── logs/
    ├── deployment.log
    ├── integration_tests.log
    └── containers/
        ├── hub-invidious.log
        ├── hub-dashboard.log
        └── ...
```

### Report Contents

**JSON Report (`integration_test_report_*.json`):**
```json
{
  "summary": {
    "total": 15,
    "passed": 13,
    "failed": 1,
    "skipped": 1,
    "duration": "245.3s",
    "passRate": "92.9%"
  },
  "services": {
    "invidious": {
      "tests": {
        "load": { "success": true, "loadTime": 1234 },
        "videoPlayback": { "success": true, "message": "..." }
      },
      "containerRunning": true,
      "logs": { "errors": [], "warnings": [...] },
      "consoleErrors": 0,
      "overall": "passed"
    }
  }
}
```

## 🔍 Understanding Test Results

### Success Criteria

**Service Passes When:**
- ✅ Container is running
- ✅ HTTP endpoint returns 2xx status
- ✅ Page loads within timeout
- ✅ No critical JavaScript errors
- ✅ Service-specific tests pass (search, video, etc.)
- ✅ Container logs show no critical errors

**Service Fails When:**
- ❌ Container not running
- ❌ HTTP 4xx/5xx status
- ❌ Timeout loading page
- ❌ JavaScript errors in console
- ❌ Functional test fails (can't search, video won't load, etc.)
- ❌ Critical errors in container logs

**Service Skipped When:**
- ⏭️  Container not deployed
- ⏭️  Service not enabled in deployment

### Common Issues

**Gluetun Unhealthy:**
- **Expected** in restricted network environments
- VPN can't establish external connection
- Dependent services may not start
- **Fix**: Ensure proper network access or disable health check dependency

**Invidious Video Playback Fails:**
- Often due to YouTube API rate limits
- Check container logs for "429 Too Many Requests"
- **Fix**: Wait or configure different instance

**Service Timeout:**
- Service taking too long to start
- Check container logs for startup errors
- **Fix**: Increase timeout or investigate container issue

## 🛠️ Advanced Usage

### Environment Variables

```bash
# Base URL for testing
export TEST_BASE_URL="http://10.0.10.225"

# Run browser in visible mode (not headless)
export HEADLESS=false

# Custom test directory
export TEST_BASE_DIR="/tmp/my-test"

# Deployment timeout (seconds)
export TIMEOUT=1800
```

### Testing Specific Services

```javascript
// In Node.js
const { testService } = require('./integration_test_suite');

const serviceConfig = {
  port: 3000,
  container: 'hub-invidious',
  healthEndpoint: '/',
  tests: ['loads', 'search', 'video-playback']
};

testService('invidious', serviceConfig).then(result => {
  console.log(result);
});
```

### Custom Test Scenarios

```javascript
// Add custom test to integration_test_suite.js

async function testCustomFeature(page, baseUrl) {
  try {
    await page.goto(baseUrl);
    // Your custom test logic
    return { success: true, message: 'Feature works' };
  } catch (error) {
    return { success: false, error: error.message };
  }
}

// Add to SERVICES configuration
SERVICES.myservice = {
  port: 8080,
  container: 'hub-myservice',
  healthEndpoint: '/',
  tests: ['loads', 'custom-feature']
};
```

## 📈 Continuous Integration

### GitHub Actions Example

```yaml
name: Integration Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Setup Node
        uses: actions/setup-node@v2
        with:
          node-version: '18'
      - name: Install Dependencies
        run: cd test && npm install
      - name: Run Tests
        env:
          WG_CONF_B64: ${{ secrets.WG_CONF_B64 }}
          HEADLESS: true
        run: ./test/full_deployment_test.sh
      - name: Upload Reports
        if: always()
        uses: actions/upload-artifact@v2
        with:
          name: test-reports
          path: |
            test/reports/
            test/screenshots/
```

## 🐛 Debugging Tests

### View Browser UI

```bash
# Run tests with visible browser
export HEADLESS=false
npm test
```

### Check Container Logs

```bash
# View logs for specific container
docker logs hub-invidious

# Follow logs in real-time
docker logs -f hub-invidious

# View last 100 lines
docker logs --tail 100 hub-invidious
```

### Debug Test Script

```javascript
// Add to test file
console.log('Debug: Current URL:', page.url());
await page.screenshot({ path: 'debug.png' });
await page.evaluate(() => console.log(document.body.innerHTML));
```

### Manual Service Testing

```bash
# Test service endpoint directly
curl -v http://10.0.10.225:3000

# Check service health
docker inspect hub-invidious --format='{{.State.Health.Status}}'

# Enter container
docker exec -it hub-invidious sh
```

## 📚 Test Development Guidelines

### Adding New Tests

1. **Define service in SERVICES object**
2. **Create test function** (e.g., `testMyServiceFeature`)
3. **Add test to service config** in `tests` array
4. **Handle in testService()** function
5. **Test locally** before committing
6. **Document** in this README

### Test Best Practices

- ✅ Use descriptive test names
- ✅ Take screenshots for visual verification
- ✅ Handle timeouts gracefully
- ✅ Check both UI and logs
- ✅ Clean up after tests
- ✅ Make tests idempotent
- ❌ Don't hardcode URLs (use CONFIG)
- ❌ Don't assume service order
- ❌ Don't ignore errors silently

## 🎯 Test Metrics

### Performance Benchmarks

| Service | Expected Load Time | Timeout |
|---------|-------------------|---------|
| Dashboard | < 2s | 10s |
| Invidious | < 3s | 30s |
| SearXNG | < 2s | 10s |
| Breezewiki | < 3s | 20s |
| Redlib | < 3s | 20s |

### Coverage Goals

- ✅ 100% of deployed services tested
- ✅ All critical user workflows tested
- ✅ All container logs analyzed
- ✅ All browser console logs checked

## 📞 Support

### Test Failures?

1. Check `test/reports/FINAL_TEST_REPORT.md`
2. Review container logs in `test/logs/containers/`
3. Look at screenshots in `test/screenshots/`
4. Check log analysis in `test/reports/log_analysis.txt`

### Contributing Tests

Pull requests welcome! Please:
- Add tests for new services
- Update this README
- Ensure tests pass locally
- Follow existing code style

---

**Last Updated**: 2026-01-16  
**Test Suite Version**: 2.0.0  
**Maintainer**: Privacy Hub Team
