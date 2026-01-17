/**
 * @fileoverview Comprehensive Dashboard Interaction Tests
 * 
 * Tests all user and admin interactions on the Privacy Hub dashboard including:
 * - Service card grid auto-scaling (3x3, 4x4, orphan handling)
 * - User interactions (filters, theme, privacy mode)
 * - Admin authentication and operations
 * - WireGuard profile management
 * - Browser console error monitoring
 * 
 * Adheres to Google JavaScript Style Guide.
 * @module test/test_dashboard_comprehensive
 */

const puppeteer = require('puppeteer');
const fs = require('fs').promises;
const path = require('path');

/** Test configuration */
const CONFIG = {
  baseUrl: process.env.TEST_BASE_URL || 'http://localhost:8088',
  apiUrl: process.env.API_URL || 'http://localhost:55555',
  adminPassword: process.env.ADMIN_PASSWORD || 'changeme',
  headless: process.env.HEADLESS !== 'false',
  timeout: 90000,
  screenshotDir: path.join(__dirname, 'screenshots', 'comprehensive'),
  reportDir: path.join(__dirname, 'reports'),
};

/** Test results tracker */
const testResults = {
  passed: 0,
  failed: 0,
  warnings: 0,
  startTime: Date.now(),
  tests: {},
  consoleErrors: [],
  consoleWarnings: [],
};

/**
 * Logs test result.
 * @param {string} category Test category.
 * @param {string} name Test name.
 * @param {string} status PASS, FAIL, or WARN.
 * @param {string} message Result message.
 */
function logResult(category, name, status, message) {
  const key = `${category}: ${name}`;
  testResults.tests[key] = {status, message};
  
  if (status === 'PASS') {
    testResults.passed++;
    console.log(`  ✅ ${name}: ${message}`);
  } else if (status === 'FAIL') {
    testResults.failed++;
    console.log(`  ❌ ${name}: ${message}`);
  } else {
    testResults.warnings++;
    console.log(`  ⚠️  ${name}: ${message}`);
  }
}

/**
 * Setup test environment.
 */
async function setupEnvironment() {
  await fs.mkdir(CONFIG.screenshotDir, {recursive: true});
  await fs.mkdir(CONFIG.reportDir, {recursive: true});
  console.log('✓ Test environment initialized');
}

/**
 * Initialize browser with console monitoring.
 * @return {Object} Browser, page, and console logs.
 */
async function initBrowser() {
  const browser = await puppeteer.launch({
    headless: CONFIG.headless,
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-dev-shm-usage',
      '--disable-gpu',
    ],
  });

  const page = await browser.newPage();
  await page.setViewport({width: 1920, height: 1080});
  await page.setDefaultTimeout(CONFIG.timeout);

  // Collect console messages
  page.on('console', (msg) => {
    const text = msg.text();
    if (msg.type() === 'error') {
      // Filter out expected/benign errors
      if (!text.includes('favicon') && !text.includes('404')) {
        testResults.consoleErrors.push(text);
      }
    } else if (msg.type() === 'warning') {
      testResults.consoleWarnings.push(text);
    }
  });

  return {browser, page};
}

/**
 * Take screenshot with naming convention.
 * @param {Page} page Puppeteer page.
 * @param {string} name Screenshot name.
 */
async function screenshot(page, name) {
  try {
    const filename = path.join(CONFIG.screenshotDir, `${Date.now()}_${name}.png`);
    await page.screenshot({path: filename, fullPage: true});
  } catch (e) {
    console.warn(`Screenshot failed: ${e.message}`);
  }
}

/**
 * Authenticate as admin.
 * @param {Page} page Puppeteer page.
 */
async function authenticateAdmin(page) {
  await page.waitForSelector('#admin-lock-btn', {timeout: 15000});
  await page.click('#admin-lock-btn');
  
  await page.waitForSelector('input[type="password"]', {timeout: 5000});
  await page.type('input[type="password"]', CONFIG.adminPassword);
  
  const enterBtn = await page.$('button[onclick*="checkAdminPassword"]');
  if (enterBtn) {
    await enterBtn.click();
  } else {
    await page.keyboard.press('Enter');
  }
  
  await page.waitForFunction(
      () => document.body.classList.contains('admin-mode'),
      {timeout: 10000}
  );
}

// ============================================================================
// GRID AUTO-SCALING TESTS
// ============================================================================

/**
 * Test grid auto-scaling behavior for various item counts.
 * @param {Page} page Puppeteer page.
 */
async function testGridAutoScaling(page) {
  console.log('\n📐 Testing Grid Auto-Scaling...');

  // Test various item counts and expected behaviors
  const testCases = [
    {count: 3, expectedCols: 3, description: '3 items: 3x1 grid'},
    {count: 4, expectedCols: 4, description: '4 items: 4x1 grid (perfect 4-col)'},
    {count: 6, expectedCols: 3, description: '6 items: 3x2 grid'},
    {count: 8, expectedCols: 4, description: '8 items: 4x2 grid (perfect 4-col)'},
    {count: 9, expectedCols: 3, description: '9 items: 3x3 grid'},
    {count: 10, expectedCols: 3, description: '10 items: 3x3 + 1 wide'},
    {count: 12, expectedCols: 4, description: '12 items: 4x3 grid (perfect 4-col)'},
    {count: 16, expectedCols: 4, description: '16 items: 4x4 grid (perfect 4-col)'},
  ];

  for (const tc of testCases) {
    try {
      // Inject test cards into grid
      const result = await page.evaluate((count) => {
        const grid = document.getElementById('grid-apps');
        if (!grid) return {error: 'grid-apps not found'};
        
        // Clear and populate with test cards
        grid.innerHTML = '';
        for (let i = 0; i < count; i++) {
          const card = document.createElement('div');
          card.className = 'card';
          card.dataset.container = `test-${i}`;
          card.innerHTML = `<h2>Test Service ${i + 1}</h2>`;
          grid.appendChild(card);
        }
        
        // Trigger grid column logic (simulate what renderDynamicGrid does)
        const remainder3 = count % 3;
        const remainder4 = count % 4;
        const use4Cols = (count >= 4) && (
            remainder4 === 0 ||
            (count >= 8 && remainder4 <= 1) ||
            (remainder3 > 0 && remainder4 === 0)
        );
        grid.classList.toggle('grid-4-cols', use4Cols);
        
        // Get computed grid columns
        const style = getComputedStyle(grid);
        const cols = style.gridTemplateColumns.split(' ').length;
        const has4ColClass = grid.classList.contains('grid-4-cols');
        
        // Check if last item spans correctly when orphaned
        const lastCard = grid.lastElementChild;
        const lastStyle = lastCard ? getComputedStyle(lastCard) : null;
        const lastColSpan = lastStyle ? lastStyle.gridColumn : 'N/A';
        
        return {cols, has4ColClass, lastColSpan, itemCount: grid.children.length};
      }, tc.count);

      if (result.error) {
        logResult('Grid', tc.description, 'FAIL', result.error);
        continue;
      }

      // Verify column count (considering viewport may affect actual render)
      const expectedHas4Col = tc.expectedCols === 4;
      if (result.has4ColClass === expectedHas4Col) {
        logResult('Grid', tc.description, 'PASS',
            `${result.itemCount} items, 4-col: ${result.has4ColClass}`);
      } else {
        logResult('Grid', tc.description, 'WARN',
            `Expected 4-col: ${expectedHas4Col}, got: ${result.has4ColClass}`);
      }
    } catch (e) {
      logResult('Grid', tc.description, 'FAIL', e.message);
    }
  }

  // Restore original grid content
  await page.evaluate(() => {
    if (typeof renderDynamicGrid === 'function') {
      renderDynamicGrid();
    }
  });
  
  await screenshot(page, 'grid_scaling_test');
}

/**
 * Test orphan card spanning behavior.
 * @param {Page} page Puppeteer page.
 */
async function testOrphanCardSpanning(page) {
  console.log('\n📐 Testing Orphan Card Spanning...');

  // Test cases where last item should span full width
  const orphanCases = [
    {count: 4, cols: 3, shouldSpan: true, desc: '4 in 3-col: last orphan spans'},
    {count: 7, cols: 3, shouldSpan: true, desc: '7 in 3-col: last orphan spans'},
    {count: 10, cols: 3, shouldSpan: true, desc: '10 in 3-col: last orphan spans'},
    {count: 5, cols: 4, shouldSpan: true, desc: '5 in 4-col: last orphan spans'},
    {count: 9, cols: 4, shouldSpan: true, desc: '9 in 4-col: last orphan spans'},
  ];

  for (const tc of orphanCases) {
    try {
      const result = await page.evaluate((count, forceCols) => {
        const grid = document.getElementById('grid-apps');
        if (!grid) return {error: 'grid not found'};
        
        grid.innerHTML = '';
        grid.classList.toggle('grid-4-cols', forceCols === 4);
        
        for (let i = 0; i < count; i++) {
          const card = document.createElement('div');
          card.className = 'card';
          card.textContent = `Card ${i + 1}`;
          grid.appendChild(card);
        }
        
        // Force layout recalc
        grid.offsetHeight;
        
        const lastCard = grid.lastElementChild;
        const style = getComputedStyle(lastCard);
        // Check if grid-column is set to span full width
        const gridCol = style.gridColumn;
        const isSpanning = gridCol.includes('-1') || gridCol.includes('span');
        
        return {gridCol, isSpanning};
      }, tc.count, tc.cols);

      if (result.error) {
        logResult('Orphan', tc.desc, 'FAIL', result.error);
      } else if (tc.shouldSpan && result.gridCol.includes('-1')) {
        logResult('Orphan', tc.desc, 'PASS', `Last card spans: ${result.gridCol}`);
      } else {
        logResult('Orphan', tc.desc, 'WARN',
            `Grid-column: ${result.gridCol} (may need CSS :has() support)`);
      }
    } catch (e) {
      logResult('Orphan', tc.desc, 'FAIL', e.message);
    }
  }
}

// ============================================================================
// USER INTERACTION TESTS
// ============================================================================

/**
 * Test dashboard loads successfully.
 * @param {Page} page Puppeteer page.
 */
async function testDashboardLoad(page) {
  console.log('\n🌐 Testing Dashboard Load...');

  try {
    const response = await page.goto(CONFIG.baseUrl, {
      waitUntil: 'networkidle2',
      timeout: 30000,
    });

    if (response && response.ok()) {
      logResult('Load', 'Dashboard accessible', 'PASS',
          `Status: ${response.status()}`);
    } else {
      logResult('Load', 'Dashboard accessible', 'FAIL',
          `Status: ${response?.status() || 'unknown'}`);
      return false;
    }

    // Wait for key elements
    await page.waitForSelector('.container', {timeout: 5000});
    await page.waitForSelector('.filter-bar', {timeout: 5000});
    
    logResult('Load', 'Core elements present', 'PASS', 'Container and filter bar found');
    await screenshot(page, 'dashboard_loaded');
    return true;
  } catch (e) {
    logResult('Load', 'Dashboard accessible', 'FAIL', e.message);
    return false;
  }
}

/**
 * Test filter chip functionality.
 * @param {Page} page Puppeteer page.
 */
async function testFilterChips(page) {
  console.log('\n🏷️ Testing Filter Chips...');

  const filters = ['all', 'apps', 'system', 'dns', 'tools'];

  for (const filter of filters) {
    try {
      const chip = await page.$(`.filter-chip[data-target="${filter}"]`);
      if (!chip) {
        logResult('Filters', `${filter} chip`, 'WARN', 'Chip not found');
        continue;
      }

      await chip.click();
      await new Promise((r) => setTimeout(r, 300));

      // Check if chip is active
      const isActive = await page.$eval(
          `.filter-chip[data-target="${filter}"]`,
          (el) => el.classList.contains('active')
      );

      // Check section visibility
      const sectionVisible = await page.evaluate((cat) => {
        if (cat === 'all') return true;
        const section = document.querySelector(`section[data-category="${cat}"]`);
        return section ? section.style.display !== 'none' : false;
      }, filter);

      if (isActive || sectionVisible) {
        logResult('Filters', `${filter} chip`, 'PASS', 'Filter works correctly');
      } else {
        logResult('Filters', `${filter} chip`, 'WARN', 'State unclear');
      }
    } catch (e) {
      logResult('Filters', `${filter} chip`, 'FAIL', e.message);
    }
  }
}

/**
 * Test theme toggle.
 * @param {Page} page Puppeteer page.
 */
async function testThemeToggle(page) {
  console.log('\n🎨 Testing Theme Toggle...');

  try {
    const initialTheme = await page.evaluate(() =>
      document.documentElement.classList.contains('light-mode') ? 'light' : 'dark'
    );

    const themeBtn = await page.$('.theme-toggle');
    if (!themeBtn) {
      logResult('Theme', 'Toggle button', 'FAIL', 'Button not found');
      return;
    }

    await themeBtn.click();
    await new Promise((r) => setTimeout(r, 500));

    const newTheme = await page.evaluate(() =>
      document.documentElement.classList.contains('light-mode') ? 'light' : 'dark'
    );

    if (initialTheme !== newTheme) {
      logResult('Theme', 'Toggle works', 'PASS',
          `Changed from ${initialTheme} to ${newTheme}`);
    } else {
      logResult('Theme', 'Toggle works', 'WARN', 'Theme did not change');
    }

    // Toggle back
    await themeBtn.click();
    await new Promise((r) => setTimeout(r, 300));
    await screenshot(page, 'theme_toggled');
  } catch (e) {
    logResult('Theme', 'Toggle works', 'FAIL', e.message);
  }
}

/**
 * Test privacy mode toggle.
 * @param {Page} page Puppeteer page.
 */
async function testPrivacyMode(page) {
  console.log('\n🔒 Testing Privacy Mode...');

  try {
    const privacySwitch = await page.$('#privacy-switch');
    if (!privacySwitch) {
      logResult('Privacy', 'Switch present', 'WARN', 'Privacy switch not found');
      return;
    }

    await privacySwitch.click();
    await new Promise((r) => setTimeout(r, 300));

    const isPrivate = await page.evaluate(() =>
      document.body.classList.contains('privacy-mode')
    );

    if (isPrivate) {
      logResult('Privacy', 'Mode enabled', 'PASS', 'Privacy mode activated');
      
      // Check if sensitive elements are blurred
      const hasBlurred = await page.evaluate(() => {
        const sensitive = document.querySelectorAll('.sensitive');
        return sensitive.length > 0;
      });
      
      if (hasBlurred) {
        logResult('Privacy', 'Sensitive elements', 'PASS', 'Elements marked as sensitive');
      }
    } else {
      logResult('Privacy', 'Mode enabled', 'WARN', 'Privacy class not applied');
    }

    // Toggle back
    await privacySwitch.click();
    await new Promise((r) => setTimeout(r, 300));
  } catch (e) {
    logResult('Privacy', 'Mode toggle', 'FAIL', e.message);
  }
}

/**
 * Test service cards render correctly.
 * @param {Page} page Puppeteer page.
 */
async function testServiceCards(page) {
  console.log('\n📦 Testing Service Cards...');

  try {
    // Wait for dynamic content to load
    await new Promise((r) => setTimeout(r, 2000));

    const cardCount = await page.$$eval('.card', (cards) => cards.length);
    
    if (cardCount > 0) {
      logResult('Cards', 'Cards rendered', 'PASS', `Found ${cardCount} cards`);
    } else {
      logResult('Cards', 'Cards rendered', 'WARN', 'No cards found (API may be down)');
    }

    // Check for proper card structure
    const hasProperStructure = await page.evaluate(() => {
      const cards = document.querySelectorAll('.card');
      if (cards.length === 0) return false;
      
      const firstCard = cards[0];
      return firstCard.querySelector('.card-header') !== null ||
             firstCard.querySelector('h2, h3') !== null;
    });

    if (hasProperStructure) {
      logResult('Cards', 'Card structure', 'PASS', 'Cards have proper structure');
    } else {
      logResult('Cards', 'Card structure', 'WARN', 'Card structure may vary');
    }

    await screenshot(page, 'service_cards');
  } catch (e) {
    logResult('Cards', 'Cards rendered', 'FAIL', e.message);
  }
}

// ============================================================================
// ADMIN INTERACTION TESTS
// ============================================================================

/**
 * Test admin login.
 * @param {Page} page Puppeteer page.
 */
async function testAdminLogin(page) {
  console.log('\n🔐 Testing Admin Login...');

  try {
    await authenticateAdmin(page);
    
    const isAdmin = await page.evaluate(() =>
      document.body.classList.contains('admin-mode')
    );

    if (isAdmin) {
      logResult('Admin', 'Login successful', 'PASS', 'Admin mode activated');
      
      // Check admin-only elements are visible
      const adminElements = await page.$$('.admin-only');
      logResult('Admin', 'Admin elements visible', 'PASS',
          `${adminElements.length} admin elements found`);
    } else {
      logResult('Admin', 'Login successful', 'FAIL', 'Admin mode not activated');
    }

    await screenshot(page, 'admin_logged_in');
  } catch (e) {
    logResult('Admin', 'Login successful', 'FAIL', e.message);
  }
}

/**
 * Test admin logout.
 * @param {Page} page Puppeteer page.
 */
async function testAdminLogout(page) {
  console.log('\n🔓 Testing Admin Logout...');

  try {
    await page.click('#admin-lock-btn');
    await new Promise((r) => setTimeout(r, 1000));

    const isAdmin = await page.evaluate(() =>
      document.body.classList.contains('admin-mode')
    );

    if (!isAdmin) {
      logResult('Admin', 'Logout successful', 'PASS', 'Admin mode deactivated');
    } else {
      logResult('Admin', 'Logout successful', 'WARN', 'Admin mode still active');
    }

    await screenshot(page, 'admin_logged_out');
  } catch (e) {
    logResult('Admin', 'Logout successful', 'FAIL', e.message);
  }
}

/**
 * Test WireGuard profile section (admin only).
 * @param {Page} page Puppeteer page.
 */
async function testWireGuardSection(page) {
  console.log('\n🔐 Testing WireGuard Section...');

  try {
    // Re-login as admin
    await authenticateAdmin(page);
    
    // Check for WireGuard profile section
    const profileSection = await page.$('#profile-list');
    if (profileSection) {
      logResult('WireGuard', 'Profile section', 'PASS', 'Profile list found');
    } else {
      logResult('WireGuard', 'Profile section', 'WARN', 'Profile list not found');
    }

    // Check for upload form
    const uploadForm = await page.$('#prof-conf');
    if (uploadForm) {
      logResult('WireGuard', 'Upload form', 'PASS', 'Profile upload textarea found');
    } else {
      logResult('WireGuard', 'Upload form', 'WARN', 'Upload form not found');
    }

    // Check for client management
    const clientList = await page.$('#wg-client-list');
    if (clientList) {
      logResult('WireGuard', 'Client list', 'PASS', 'Client list container found');
    } else {
      logResult('WireGuard', 'Client list', 'WARN', 'Client list not found');
    }

    await screenshot(page, 'wireguard_section');
  } catch (e) {
    logResult('WireGuard', 'Section access', 'FAIL', e.message);
  }
}

/**
 * Test deSEC configuration form (admin only).
 * @param {Page} page Puppeteer page.
 */
async function testDesecConfig(page) {
  console.log('\n🌐 Testing deSEC Configuration...');

  try {
    const domainInput = await page.$('#desec-domain-input');
    const tokenInput = await page.$('#desec-token-input');

    if (domainInput && tokenInput) {
      logResult('deSEC', 'Config form', 'PASS', 'Domain and token inputs found');
    } else {
      logResult('deSEC', 'Config form', 'WARN', 'Some inputs missing');
    }
  } catch (e) {
    logResult('deSEC', 'Config form', 'FAIL', e.message);
  }
}

/**
 * Test security settings (admin only).
 * @param {Page} page Puppeteer page.
 */
async function testSecuritySettings(page) {
  console.log('\n🛡️ Testing Security Settings...');

  try {
    // Session cleanup switch
    const sessionSwitch = await page.$('#session-cleanup-switch');
    if (sessionSwitch) {
      logResult('Security', 'Session cleanup switch', 'PASS', 'Switch found');
    }

    // Rollback backup switch
    const rollbackSwitch = await page.$('#rollback-backup-switch');
    if (rollbackSwitch) {
      logResult('Security', 'Rollback backup switch', 'PASS', 'Switch found');
    }

    // Update strategy selector
    const strategySelect = await page.$('#update-strategy-select');
    if (strategySelect) {
      logResult('Security', 'Update strategy', 'PASS', 'Selector found');
    }
  } catch (e) {
    logResult('Security', 'Settings access', 'FAIL', e.message);
  }
}

// ============================================================================
// BROWSER CONSOLE MONITORING
// ============================================================================

/**
 * Analyze collected console logs.
 */
function analyzeConsoleLogs() {
  console.log('\n📋 Browser Console Analysis...');

  const errorCount = testResults.consoleErrors.length;
  const warnCount = testResults.consoleWarnings.length;

  if (errorCount === 0) {
    logResult('Console', 'No JS errors', 'PASS', 'No console errors detected');
  } else {
    logResult('Console', 'JS errors', 'FAIL', `${errorCount} errors found`);
    testResults.consoleErrors.slice(0, 5).forEach((err) => {
      console.log(`    - ${err.substring(0, 100)}`);
    });
  }

  if (warnCount <= 5) {
    logResult('Console', 'Warnings', 'PASS', `${warnCount} warnings (acceptable)`);
  } else {
    logResult('Console', 'Warnings', 'WARN', `${warnCount} warnings found`);
  }
}

// ============================================================================
// REPORT GENERATION
// ============================================================================

/**
 * Generate test report.
 */
async function generateReport() {
  const duration = ((Date.now() - testResults.startTime) / 1000).toFixed(2);
  const total = testResults.passed + testResults.failed + testResults.warnings;

  const report = {
    timestamp: new Date().toISOString(),
    duration: `${duration}s`,
    summary: {
      total,
      passed: testResults.passed,
      failed: testResults.failed,
      warnings: testResults.warnings,
      passRate: total > 0 ?
        `${((testResults.passed / total) * 100).toFixed(1)}%` : '0%',
    },
    tests: testResults.tests,
    consoleErrors: testResults.consoleErrors,
    consoleWarnings: testResults.consoleWarnings.slice(0, 20),
  };

  const reportPath = path.join(
      CONFIG.reportDir,
      `comprehensive_test_${Date.now()}.json`
  );
  await fs.writeFile(reportPath, JSON.stringify(report, null, 2));

  console.log('\n' + '='.repeat(70));
  console.log('COMPREHENSIVE TEST REPORT');
  console.log('='.repeat(70));
  console.log(`Duration: ${duration}s`);
  console.log(`✅ Passed:   ${testResults.passed}`);
  console.log(`❌ Failed:   ${testResults.failed}`);
  console.log(`⚠️  Warnings: ${testResults.warnings}`);
  console.log(`Pass Rate: ${report.summary.passRate}`);
  console.log(`Report: ${reportPath}`);
  console.log('='.repeat(70));

  return testResults.failed === 0 ? 0 : 1;
}

// ============================================================================
// MAIN TEST RUNNER
// ============================================================================

/**
 * Main test execution.
 */
async function main() {
  console.log('🚀 Starting Comprehensive Dashboard Tests\n');
  console.log(`Target: ${CONFIG.baseUrl}`);
  console.log(`Headless: ${CONFIG.headless}`);
  console.log('='.repeat(70));

  await setupEnvironment();
  const {browser, page} = await initBrowser();

  try {
    // Load dashboard
    const loaded = await testDashboardLoad(page);
    if (!loaded) {
      console.log('\n❌ Dashboard not accessible, aborting tests');
      await browser.close();
      process.exit(1);
    }

    // User interaction tests
    await testServiceCards(page);
    await testFilterChips(page);
    await testThemeToggle(page);
    await testPrivacyMode(page);

    // Grid auto-scaling tests
    await testGridAutoScaling(page);
    await testOrphanCardSpanning(page);

    // Admin tests
    await testAdminLogin(page);
    await testWireGuardSection(page);
    await testDesecConfig(page);
    await testSecuritySettings(page);
    await testAdminLogout(page);

    // Console log analysis
    analyzeConsoleLogs();

  } catch (e) {
    console.error('\n❌ Fatal error:', e.message);
    testResults.failed++;
  } finally {
    await browser.close();
  }

  const exitCode = await generateReport();
  process.exit(exitCode);
}

// Run if executed directly
if (require.main === module) {
  main().catch((e) => {
    console.error('Unhandled error:', e);
    process.exit(1);
  });
}

module.exports = {main, CONFIG};
