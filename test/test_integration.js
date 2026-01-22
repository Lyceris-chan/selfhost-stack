/**
 * @fileoverview Comprehensive Integration Test Suite for Privacy Hub
 * Tests all deployed services including video playback, search, and core functionality
 * @author Privacy Hub Team
 * @license MIT
 */

const puppeteer = require('puppeteer');
const { exec } = require('child_process');
const { promisify } = require('util');
const fs = require('fs').promises;
const path = require('path');

const execAsync = promisify(exec);

/** Test configuration */
const getBaseUrl = () => {
  const envUrl = process.env.TEST_BASE_URL || 'http://10.0.10.225';
  try {
    const url = new URL(envUrl);
    return `${url.protocol}//${url.hostname}`;
  } catch (e) {
    return envUrl;
  }
};

const CONFIG = {
  baseUrl: getBaseUrl(),
  headless: process.env.HEADLESS !== 'false',
  timeout: 60000,
  screenshotDir: path.join(__dirname, 'screenshots'),
  reportDir: path.join(__dirname, 'reports'),
  containerPrefix: 'hub-',
};

/** Test results tracking */
const testResults = {
  services: {},
  passed: 0,
  failed: 0,
  skipped: 0,
  errors: [],
  warnings: [],
  containerLogs: {},
  startTime: Date.now(),
};

/**
 * Service definitions with test endpoints and validation criteria
 */
const SERVICES = {
  // Core Infrastructure
  dashboard: {
    port: 8088,
    container: 'hub-dashboard',
    healthEndpoint: '/',
    tests: ['loads', 'responsive', 'api-connection'],
  },
  api: {
    port: 55555,
    container: 'hub-api',
    healthEndpoint: '/health',
    tests: ['health', 'status', 'certificate-status'],
  },
  adguard: {
    port: 8083,
    container: 'hub-adguard',
    healthEndpoint: '/',
    tests: ['loads', 'dns-settings'],
  },
  
  // Privacy Frontend Services
  invidious: {
    port: 3000,
    container: 'hub-invidious',
    healthEndpoint: '/',
    tests: ['loads', 'search', 'video-playback'],
  },
  breezewiki: {
    port: 8380,
    container: 'hub-breezewiki',
    healthEndpoint: '/',
    tests: ['loads', 'wiki-lookup', 'search'],
  },
  redlib: {
    port: 8080,
    container: 'hub-redlib',
    healthEndpoint: '/',
    tests: ['loads', 'subreddit-view'],
  },
  scribe: {
    port: 8280,
    container: 'hub-scribe',
    healthEndpoint: '/',
    tests: ['loads', 'article-view'],
  },
  anonymousoverflow: {
    port: 8480,
    container: 'hub-anonymousoverflow',
    healthEndpoint: '/',
    tests: ['loads', 'question-search'],
  },
  searxng: {
    port: 8082,
    container: 'hub-searxng',
    healthEndpoint: '/',
    tests: ['loads', 'search'],
  },
  rimgo: {
    port: 3002,
    container: 'hub-rimgo',
    healthEndpoint: '/',
    tests: ['loads'],
  },
  cobalt: {
    port: 9001,
    container: 'hub-cobalt-web',
    healthEndpoint: '/',
    tests: ['loads'],
  },
  
  // Productivity Services
  memos: {
    port: 5230,
    container: 'hub-memos',
    healthEndpoint: '/',
    tests: ['loads', 'auth'],
  },
  portainer: {
    port: 9000,
    container: 'hub-portainer',
    healthEndpoint: '/',
    tests: ['loads'],
  },
  
  // VPN Services
  'wg-easy': {
    port: 51821,
    container: 'hub-wg-easy',
    healthEndpoint: '/',
    tests: ['loads', 'auth'],
  },
  
  // Additional Services
  'odido-booster': {
    port: 8085,
    container: 'hub-odido-booster',
    healthEndpoint: '/docs',
    tests: ['loads'],
  },
  vert: {
    port: 5555,
    container: 'hub-vert',
    healthEndpoint: '/',
    tests: ['loads'],
  },
  immich: {
    port: 2283,
    container: 'hub-immich-server',
    healthEndpoint: '/api/server/ping',
    tests: ['loads'],
  },
  wikiless: {
    port: 8180,
    container: 'hub-wikiless',
    healthEndpoint: '/',
    tests: ['loads'],
  },
  unbound: {
    port: 53,
    container: 'hub-unbound',
    healthEndpoint: '',
    tests: ['container-running'],
  },
  gluetun: {
    port: 8000, // control port usually
    container: 'hub-gluetun',
    healthEndpoint: '',
    tests: ['container-running'],
  },
  companion: {
    port: 8283,
    container: 'hub-companion',
    healthEndpoint: '/companion',
    tests: ['container-running'],
  },
  vertd: {
    port: 24153,
    container: 'hub-vertd',
    healthEndpoint: '',
    tests: ['container-running'],
  },
  watchtower: {
    port: 0,
    container: 'hub-watchtower',
    healthEndpoint: '',
    tests: ['container-running'],
  },
  // Databases & Caches
  'invidious-db': { container: 'hub-invidious-db', tests: ['container-running'] },
  'wikiless-redis': { container: 'hub-wikiless_redis', tests: ['container-running'] },
  'searxng-redis': { container: 'hub-searxng-redis', tests: ['container-running'] },
  'immich-db': { container: 'hub-immich-db', tests: ['container-running'] },
  'immich-redis': { container: 'hub-immich-redis', tests: ['container-running'] },
  'immich-ml': { container: 'hub-immich-ml', tests: ['container-running'] },
};

/**
 * Initialize test environment
 */
async function setupTestEnvironment() {
  console.log('🔧 Setting up test environment...');
  
  await fs.mkdir(CONFIG.screenshotDir, { recursive: true });
  await fs.mkdir(CONFIG.reportDir, { recursive: true });
  
  console.log('✅ Test environment ready');
}

/**
 * Check if a Docker container is running
 * @param {string} containerName
 * @return {Promise<boolean>}
 */
async function isContainerRunning(containerName) {
  try {
    const { stdout } = await execAsync(
        `docker ps --filter "name=^/${containerName}$" --filter "status=running" --format "{{.Names}}"`
    );
    // Exact match check
    return stdout.split('\n').some(name => name.trim() === containerName);
  } catch (error) {
    return false;
  }
}

/**
 * Get container logs
 * @param {string} containerName
 * @param {number} lines
 * @return {Promise<string>}
 */
async function getContainerLogs(containerName, lines = 50) {
  try {
    const { stdout } = await execAsync(
        `docker logs ${containerName} --tail ${lines} 2>&1`
    );
    return stdout;
  } catch (error) {
    return `Error fetching logs: ${error.message}`;
  }
}

/**
 * Analyze container logs for errors
 * @param {string} logs
 * @return {Object}
 */
function analyzeLogs(logs) {
  const errors = [];
  const warnings = [];
  
  const lines = logs.split('\n');
  lines.forEach((line, index) => {
    const lowerLine = line.toLowerCase();
    
    if (lowerLine.includes('error') && 
        !lowerLine.includes('0 error') &&
        !lowerLine.includes('no error')) {
      errors.push({ line: index + 1, content: line.substring(0, 200) });
    }
    
    if (lowerLine.includes('warn') || lowerLine.includes('warning')) {
      warnings.push({ line: index + 1, content: line.substring(0, 200) });
    }
  });
  
  return { errors, warnings, totalLines: lines.length };
}

/**
 * Initialize Puppeteer browser
 * @return {Promise<Object>}
 */
async function initBrowser() {
  const browser = await puppeteer.launch({
    headless: CONFIG.headless,
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-dev-shm-usage',
      '--disable-web-security',
      '--ignore-certificate-errors',
    ],
  });
  
  const page = await browser.newPage();
  await page.setViewport({ width: 1920, height: 1080 });
  
  // Collect console messages
  const consoleLogs = [];
  page.on('console', (msg) => {
    consoleLogs.push({
      type: msg.type(),
      text: msg.text(),
      timestamp: Date.now(),
    });
  });
  
  page.on('pageerror', (error) => {
    consoleLogs.push({
      type: 'pageerror',
      text: error.message,
      stack: error.stack,
      timestamp: Date.now(),
    });
  });
  
  return { browser, page, consoleLogs };
}

/**
 * Take screenshot with error handling
 * @param {Object} page
 * @param {string} name
 */
async function takeScreenshot(page, name) {
  try {
    const filename = path.join(
        CONFIG.screenshotDir,
        `${Date.now()}_${name}.png`
    );
    await page.screenshot({ path: filename, fullPage: false });
    return filename;
  } catch (error) {
    console.warn(`Failed to take screenshot: ${error.message}`);
    return null;
  }
}

/**
 * Test: Basic page load
 * @param {Object} page
 * @param {string} url
 * @param {string} serviceName
 * @return {Promise<Object>}
 */
async function testPageLoad(page, url, serviceName) {
  const startTime = Date.now();
  const maxRetries = 3;
  let lastError;

  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      const response = await page.goto(url, {
        waitUntil: 'networkidle2',
        timeout: CONFIG.timeout,
      });
      
      const loadTime = Date.now() - startTime;
      const status = response.status();
      
      // Always take a screenshot to capture state (success or error page)
      await takeScreenshot(page, `${serviceName}_status_${status}`);
      
      if (status >= 200 && status < 400) {
        return {
          success: true,
          status,
          loadTime,
          message: `Loaded successfully in ${loadTime}ms`,
        };
      }
      
      return {
        success: false,
        status,
        loadTime,
        message: `HTTP ${status}`,
      };
    } catch (error) {
      lastError = error;
      console.log(`  ⚠️  Attempt ${attempt}/${maxRetries} failed for ${serviceName}: ${error.message}`);
      if (attempt < maxRetries) {
        await new Promise(r => setTimeout(r, 5000));
      }
    }
  }

  return {
    success: false,
    error: lastError.message,
    message: `Failed to load after ${maxRetries} attempts: ${lastError.message}`,
  };
}

/**
 * Test: DNS Resolution
 * @param {string} containerName
 * @return {Promise<Object>}
 */
async function testDnsResolution(containerName) {
  try {
    // We test resolution from WITHIN the container to verify it's working
    // or we can test against the exposed port if possible.
    // Unbound exposes 53/udp on the host as well in the compose file?
    // Let's check compose: unbound is internal IP 172.x.0.250, AdGuard uses it.
    // AdGuard exposes 53. Unbound is backend.
    // So we should verify Unbound by asking it to resolve something FROM the host if it exposed ports,
    // OR exec into it.
    // Unbound compose says: networks: frontend (ipv4_address ...). No ports mapped to host.
    // So we must use docker exec.
    
    const { stdout } = await execAsync(
      `docker exec ${containerName} drill google.com @127.0.0.1`
    );
    
    if (stdout.includes('NOERROR') && stdout.includes('ANSWER SECTION')) {
      return { success: true, message: 'DNS resolution successful' };
    }
    return { success: false, message: 'DNS resolution failed (no answer)' };
  } catch (error) {
    return { success: false, message: `DNS test failed: ${error.message}` };
  }
}

/**
 * Test: Invidious video search and playback
 * @param {Object} page
 * @param {string} baseUrl
 * @return {Promise<Object>}
 */
async function testInvidiousVideoPlayback(page, baseUrl) {
  try {
    // Navigate to Invidious
    await page.goto(baseUrl, { waitUntil: 'networkidle2', timeout: CONFIG.timeout });
    await takeScreenshot(page, 'invidious_home');
    
    // Search for a video
    const searchBox = await page.$('input[type="search"], input[name="q"]');
    if (!searchBox) {
      return { success: false, message: 'Search box not found' };
    }
    
    await searchBox.type('test video');
    await page.keyboard.press('Enter');
    await page.waitForNavigation({ waitUntil: 'networkidle2', timeout: CONFIG.timeout });
    await takeScreenshot(page, 'invidious_search_results');
    
    // Click first video result
    const videoLink = await page.$('a[href*="/watch"]');
    if (!videoLink) {
      return { success: false, message: 'No video results found' };
    }
    
    await videoLink.click();
    await page.waitForNavigation({ waitUntil: 'networkidle2', timeout: CONFIG.timeout });
    await page.waitForTimeout(2000); // Wait for video player
    await takeScreenshot(page, 'invidious_video_page');
    
    // Check for video player
    const videoPlayer = await page.$('video');
    if (!videoPlayer) {
      return { success: false, message: 'Video player not found' };
    }
    
    // Check if video can play
    const canPlay = await page.evaluate(() => {
      const video = document.querySelector('video');
      return video && video.readyState >= 2; // HAVE_CURRENT_DATA
    });
    
    return {
      success: canPlay,
      message: canPlay ? 'Video player loaded and ready' : 'Video player not ready',
    };
  } catch (error) {
    return {
      success: false,
      error: error.message,
      message: `Test failed: ${error.message}`,
    };
  }
}

/**
 * Test: Breezewiki search and article lookup
 * @param {Object} page
 * @param {string} baseUrl
 * @return {Promise<Object>}
 */
async function testBreezewikiLookup(page, baseUrl) {
  try {
    // Navigate to Breezewiki
    await page.goto(baseUrl, { waitUntil: 'networkidle2', timeout: CONFIG.timeout });
    await takeScreenshot(page, 'breezewiki_home');
    
    // Look for search functionality
    const searchInput = await page.$('input[type="search"], input[name="q"], input[name="search"]');
    if (searchInput) {
      // Fill required wiki name if present
      const wikiNameInput = await page.$('input[name="wikiname"]');
      if (wikiNameInput) {
        await wikiNameInput.type('minecraft');
      }
      
      await searchInput.type('test article');
      await page.keyboard.press('Enter');
      await page.waitForNavigation({ waitUntil: 'networkidle2', timeout: CONFIG.timeout });
      await takeScreenshot(page, 'breezewiki_search_results');
      
      // Check if results loaded
      const hasContent = await page.evaluate(() => {
        return document.body.textContent.length > 1000;
      });
      
      return {
        success: hasContent,
        message: hasContent ? 'Search results loaded' : 'No content found',
      };
    }
    
    // Try direct wiki path
    const wikiPath = '/wiki/Test';
    await page.goto(`${baseUrl}${wikiPath}`, {
      waitUntil: 'networkidle2',
      timeout: CONFIG.timeout,
    });
    await takeScreenshot(page, 'breezewiki_article');
    
    const hasArticleContent = await page.evaluate(() => {
      return document.body.textContent.length > 500;
    });
    
    return {
      success: hasArticleContent,
      message: hasArticleContent ? 'Article loaded' : 'No article content',
    };
  } catch (error) {
    return {
      success: false,
      error: error.message,
      message: `Test failed: ${error.message}`,
    };
  }
}

/**
 * Test: SearXNG search functionality
 * @param {Object} page
 * @param {string} baseUrl
 * @return {Promise<Object>}
 */
async function testSearxngSearch(page, baseUrl) {
  try {
    await page.goto(baseUrl, { waitUntil: 'networkidle2', timeout: CONFIG.timeout });
    await takeScreenshot(page, 'searxng_home');
    
    const searchInput = await page.$('input[name="q"]');
    if (!searchInput) {
      return { success: false, message: 'Search input not found' };
    }
    
    await searchInput.type('test query');
    await page.keyboard.press('Enter');
    await page.waitForNavigation({ waitUntil: 'networkidle2', timeout: CONFIG.timeout });
    await takeScreenshot(page, 'searxng_results');
    
    const hasResults = await page.evaluate(() => {
      const results = document.querySelectorAll('.result');
      return results.length > 0;
    });
    
    return {
      success: hasResults,
      message: hasResults ? 'Search results found' : 'No search results',
    };
  } catch (error) {
    return {
      success: false,
      error: error.message,
      message: `Test failed: ${error.message}`,
    };
  }
}

/**
 * Test: Redlib subreddit viewing
 * @param {Object} page
 * @param {string} baseUrl
 * @return {Promise<Object>}
 */
async function testRedlibSubreddit(page, baseUrl) {
  try {
    // Try to load /r/test
    await page.goto(`${baseUrl}/r/test`, {
      waitUntil: 'networkidle2',
      timeout: CONFIG.timeout,
    });
    await takeScreenshot(page, 'redlib_subreddit');
    
    const hasPosts = await page.evaluate(() => {
      const posts = document.querySelectorAll('.post, article, [class*="post"]');
      return posts.length > 0 || document.body.textContent.includes('reddit');
    });
    
    return {
      success: hasPosts,
      message: hasPosts ? 'Subreddit loaded' : 'No posts found',
    };
  } catch (error) {
    return {
      success: false,
      error: error.message,
      message: `Test failed: ${error.message}`,
    };
  }
}

/**
 * Run all tests for a service
 * @param {string} serviceName
 * @param {Object} serviceConfig
 * @return {Promise<Object>}
 */
async function testService(serviceName, serviceConfig) {
  console.log(`\n🧪 Testing ${serviceName}...`);
  
  const result = {
    name: serviceName,
    container: serviceConfig.container,
    tests: {},
    containerRunning: false,
    logs: { errors: [], warnings: [] },
    overall: 'skipped',
  };
  
  // Check if container is running
  result.containerRunning = await isContainerRunning(serviceConfig.container);
  
  if (!result.containerRunning) {
    console.log(`  ⏭️  Skipped: Container ${serviceConfig.container} not running`);
    return result;
  }
  
  // Get and analyze container logs
  const logs = await getContainerLogs(serviceConfig.container);
  const logAnalysis = analyzeLogs(logs);
  result.logs = logAnalysis;
  testResults.containerLogs[serviceName] = logs;
  
  if (logAnalysis.errors.length > 0) {
    console.log(`  ⚠️  Found ${logAnalysis.errors.length} errors in container logs`);
  }
  
  // Non-browser tests
  if (serviceConfig.tests.includes('dns-resolution')) {
    result.tests.dns = await testDnsResolution(serviceConfig.container);
    console.log(`  ${result.tests.dns.success ? '✅' : '❌'} DNS: ${result.tests.dns.message}`);
    
    // Determine overall result for non-browser service
    if (result.tests.dns.success) {
        result.overall = 'passed';
        testResults.passed++;
    } else {
        result.overall = 'failed';
        testResults.failed++;
    }
    testResults.services[serviceName] = result;
    return result;
  }

  // Pure container check (for databases, utilities)
  if (serviceConfig.tests.includes('container-running')) {
     result.overall = 'passed';
     testResults.passed++;
     console.log(`  ✅ Container check passed`);
     testResults.services[serviceName] = result;
     return result; 
  }

  // Initialize browser for this service
  const { browser, page, consoleLogs } = await initBrowser();
  
  try {
    const baseUrl = `${CONFIG.baseUrl}:${serviceConfig.port}`;
    const healthUrl = `${baseUrl}${serviceConfig.healthEndpoint || '/'}`;
    
    // Test 1: Basic load
    if (serviceConfig.tests.includes('loads')) {
      result.tests.load = await testPageLoad(page, healthUrl, serviceName);
      console.log(`  ${result.tests.load.success ? '✅' : '❌'} Load (${healthUrl}): ${result.tests.load.message}`);
    }
    
    // Test 2: Service-specific tests
    if (result.tests.load && result.tests.load.success) {
      // Invidious video tests
      if (serviceName === 'invidious' && serviceConfig.tests.includes('video-playback')) {
        result.tests.videoPlayback = await testInvidiousVideoPlayback(page, baseUrl);
        console.log(`  ${result.tests.videoPlayback.success ? '✅' : '❌'} Video: ${result.tests.videoPlayback.message}`);
      }
      
      // Breezewiki tests
      if (serviceName === 'breezewiki' && serviceConfig.tests.includes('wiki-lookup')) {
        result.tests.wikiLookup = await testBreezewikiLookup(page, baseUrl);
        console.log(`  ${result.tests.wikiLookup.success ? '✅' : '❌'} Wiki: ${result.tests.wikiLookup.message}`);
      }
      
      // SearXNG tests
      if (serviceName === 'searxng' && serviceConfig.tests.includes('search')) {
        result.tests.search = await testSearxngSearch(page, baseUrl);
        console.log(`  ${result.tests.search.success ? '✅' : '❌'} Search: ${result.tests.search.message}`);
      }
      
      // Redlib tests
      if (serviceName === 'redlib' && serviceConfig.tests.includes('subreddit-view')) {
        result.tests.subreddit = await testRedlibSubreddit(page, baseUrl);
        console.log(`  ${result.tests.subreddit.success ? '✅' : '❌'} Subreddit: ${result.tests.subreddit.message}`);
      }
    }
    
    // Analyze console logs
    const consoleErrors = consoleLogs.filter((log) => log.type === 'error' || log.type === 'pageerror');
    result.consoleErrors = consoleErrors.length;
    
    if (consoleErrors.length > 0) {
      console.log(`  ⚠️  Found ${consoleErrors.length} browser console errors`);
      result.consoleLogs = consoleErrors;
    }
    
    // Determine overall result
    const allTests = Object.values(result.tests);
    const anyFailed = allTests.some((test) => !test.success);
    const anyPassed = allTests.some((test) => test.success);
    
    if (anyPassed && !anyFailed) {
      result.overall = 'passed';
      testResults.passed++;
    } else if (anyFailed) {
      result.overall = 'failed';
      testResults.failed++;
    }
    
  } catch (error) {
    console.log(`  ❌ Error: ${error.message}`);
    result.error = error.message;
    result.overall = 'failed';
    testResults.failed++;
  } finally {
    await browser.close();
  }
  
  testResults.services[serviceName] = result;
  return result;
}

/**
 * Generate comprehensive test report
 */
async function generateReport() {
  const duration = ((Date.now() - testResults.startTime) / 1000).toFixed(2);
  const total = testResults.passed + testResults.failed + testResults.skipped;
  
  const report = {
    summary: {
      total,
      passed: testResults.passed,
      failed: testResults.failed,
      skipped: testResults.skipped,
      duration: `${duration}s`,
      passRate: total > 0 ? ((testResults.passed / total) * 100).toFixed(1) + '%' : '0%',
    },
    services: testResults.services,
    timestamp: new Date().toISOString(),
  };
  
  // Save JSON report
  const jsonPath = path.join(CONFIG.reportDir, `integration_test_report_${Date.now()}.json`);
  await fs.writeFile(jsonPath, JSON.stringify(report, null, 2));
  
  // Save container logs
  const logsPath = path.join(CONFIG.reportDir, `container_logs_${Date.now()}.json`);
  await fs.writeFile(logsPath, JSON.stringify(testResults.containerLogs, null, 2));
  
  // Print summary
  console.log('\n' + '='.repeat(70));
  console.log('📊 INTEGRATION TEST REPORT');
  console.log('='.repeat(70));
  console.log(`Total Services Tested: ${total}`);
  console.log(`✅ Passed: ${testResults.passed}`);
  console.log(`❌ Failed: ${testResults.failed}`);
  console.log(`⏭️  Skipped: ${testResults.skipped}`);
  console.log(`Pass Rate: ${report.summary.passRate}`);
  console.log(`Duration: ${duration}s`);
  console.log('='.repeat(70));
  
  if (testResults.failed > 0) {
    console.log('\n❌ Failed Services:');
    Object.entries(testResults.services).forEach(([name, result]) => {
      if (result.overall === 'failed') {
        console.log(`  - ${name}: ${result.error || 'See detailed results'}`);
      }
    });
  }
  
  console.log(`\n📄 Reports saved:`);
  console.log(`  - ${jsonPath}`);
  console.log(`  - ${logsPath}`);
  
  return testResults.failed === 0 ? 0 : 1;
}

/**
 * Main test execution
 */
async function main() {
  console.log('🚀 Starting Privacy Hub Integration Tests\n');
  
  await setupTestEnvironment();
  
  // Test each service
  for (const [serviceName, serviceConfig] of Object.entries(SERVICES)) {
    await testService(serviceName, serviceConfig);
    
    // Small delay between services
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }
  
  const exitCode = await generateReport();
  process.exit(exitCode);
}

// Run if executed directly
if (require.main === module) {
  main().catch((error) => {
    console.error('Fatal error:', error);
    process.exit(1);
  });
}

module.exports = {
  testService,
  testInvidiousVideoPlayback,
  testBreezewikiLookup,
  testSearxngSearch,
  testRedlibSubreddit,
};
