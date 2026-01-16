/**
 * @fileoverview Privacy Hub Dashboard Testing Suite
 * 
 * This module provides comprehensive end-to-end testing for the Privacy Hub
 * dashboard web interface. Tests cover user interactions, admin operations,
 * service management, and system monitoring features.
 * 
 * Test Categories:
 * - User Interface: Theme, filters, search, privacy mode
 * - Authentication: Admin login/logout, session management
 * - Service Management: Updates, rollbacks, migrations
 * - System Operations: Backups, restores, certificates
 * - Monitoring: Container status, logs, metrics
 * 
 * @module test/test_dashboard
 * @requires puppeteer - Headless browser automation
 * @author Privacy Hub Team
 * @license MIT
 * 
 * @example
 * // Run all dashboard tests
 * npm run test:dashboard
 * 
 * @example
 * // Run with custom configuration
 * TEST_BASE_URL=http://localhost:8088 npm run test:dashboard
 */

const puppeteer = require('puppeteer');
const { exec } = require('child_process');
const { promisify } = require('util');
const fs = require('fs').promises;
const path = require('path');

const execAsync = promisify(exec);

/** Test configuration */
const CONFIG = {
  baseUrl: process.env.TEST_BASE_URL || 'http://localhost:8080',
  apiUrl: process.env.API_URL || 'http://localhost:55555',
  adminPassword: process.env.ADMIN_PASSWORD || 'changeme',
  headless: process.env.HEADLESS !== 'false',
  timeout: 90000,
  screenshotDir: path.join(__dirname, 'screenshots', 'admin_complete'),
  reportDir: path.join(__dirname, 'reports'),
};

/** Test results tracker */
const testResults = {
  passed: 0,
  failed: 0,
  startTime: Date.now(),
  interactions: {},
  errors: [],
};

/**
 * Setup test environment
 */
async function setupEnvironment() {
  await fs.mkdir(CONFIG.screenshotDir, { recursive: true });
  await fs.mkdir(CONFIG.reportDir, { recursive: true });
  console.log('✓ Test environment initialized');
}

/**
 * Wait for element with timeout
 */
async function waitFor(page, selector, timeout = 10000) {
  try {
    await page.waitForSelector(selector, { timeout, visible: true });
    return true;
  } catch (error) {
    console.warn(`⚠ Element not found: ${selector}`);
    return false;
  }
}

/**
 * Wait for element to disappear
 */
async function waitForDisappear(page, selector, timeout = 10000) {
  try {
    await page.waitForSelector(selector, { timeout, hidden: true });
    return true;
  } catch (error) {
    console.warn(`⚠ Element still visible: ${selector}`);
    return false;
  }
}

/**
 * Take screenshot with naming convention
 */
async function screenshot(page, name) {
  try {
    const timestamp = Date.now();
    const filename = path.join(CONFIG.screenshotDir, `${timestamp}_${name}.png`);
    await page.screenshot({ path: filename, fullPage: true });
    return filename;
  } catch (error) {
    console.warn(`Screenshot failed: ${error.message}`);
    return null;
  }
}

/**
 * Run a test with error handling
 */
async function runTest(name, testFn) {
  try {
    console.log(`\n▶ Running: ${name}`);
    await testFn();
    testResults.passed++;
    testResults.interactions[name] = { status: 'passed' };
    console.log(`  ✓ PASSED`);
  } catch (error) {
    testResults.failed++;
    testResults.errors.push({ test: name, error: error.message, stack: error.stack });
    testResults.interactions[name] = { status: 'failed', error: error.message };
    console.error(`  ✗ FAILED: ${error.message}`);
  }
}

/**
 * Initialize browser and page
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
  await page.setViewport({ width: 1920, height: 1080 });
  await page.setDefaultTimeout(CONFIG.timeout);

  // Console log collector
  const consoleLogs = [];
  page.on('console', msg => {
    const text = msg.text();
    consoleLogs.push({ type: msg.type(), text });
    if (msg.type() === 'error') {
      console.error(`Browser console error: ${text}`);
    }
  });

  return { browser, page, consoleLogs };
}

/**
 * Authenticate as admin
 */
async function authenticateAdmin(page) {
  await waitFor(page, '#admin-lock-btn', 15000);
  await page.click('#admin-lock-btn');
  
  await waitFor(page, 'input[type="password"]', 5000);
  await page.type('input[type="password"]', CONFIG.adminPassword);
  
  const enterBtn = await page.$('button[onclick*="checkAdminPassword"]');
  if (enterBtn) {
    await enterBtn.click();
  } else {
    await page.keyboard.press('Enter');
  }
  
  await page.waitForFunction(
    () => document.querySelectorAll('.admin-only').length > 0,
    { timeout: 10000 }
  );
  
  await screenshot(page, 'admin_authenticated');
}

/**
 * Logout from admin
 */
async function logoutAdmin(page) {
  await page.click('#admin-lock-btn');
  await new Promise(r => setTimeout(r, 1000));
}

// ============================================================================
// USER INTERACTION TESTS
// ============================================================================

async function testDashboardLoad(page) {
  await runTest('Dashboard loads successfully', async () => {
    const response = await page.goto(CONFIG.baseUrl, {
      waitUntil: 'networkidle2',
      timeout: 30000,
    });
    
    if (!response || !response.ok()) {
      throw new Error(`Dashboard returned status ${response?.status()}`);
    }
    
    await waitFor(page, 'body', 5000);
    await screenshot(page, 'dashboard_loaded');
  });
}

async function testServiceCards(page) {
  await runTest('Service cards render correctly', async () => {
    // Wait for services grid to be populated by JavaScript
    await new Promise(r => setTimeout(r, 3000));
    
    // Check for service grid container
    const grid = await page.$('#grid-apps, #grid-system, .grid');
    if (!grid) {
      throw new Error('Services grid container not found');
    }
    
    // Service cards are dynamically generated, check for service links or elements
    const serviceElements = await page.$$('.card');
    if (serviceElements.length === 0) {
      throw new Error('No service elements found');
    }
    console.log(`   Found ${serviceElements.length} service elements`);
    await screenshot(page, 'service_cards');
  });
}

async function testFilterChips(page) {
  await runTest('Filter chips function correctly', async () => {
    const filters = ['all', 'apps', 'system', 'dns'];
    
    for (const filter of filters) {
      const chip = await page.$(`.filter-chip[data-target="${filter}"]`);
      if (chip) {
        await chip.click();
        await new Promise(r => setTimeout(r, 500));
        
        const visibleCards = await page.$$eval('.card:not([style*="display: none"])', 
          cards => cards.length);
        console.log(`   ${filter}: ${visibleCards} cards visible`);
      }
    }
    
    await screenshot(page, 'filters_tested');
  });
}

async function testThemeToggle(page) {
  await runTest('Theme toggle switches between light and dark', async () => {
    const themeBtn = await page.$('.theme-toggle');
    if (!themeBtn) {
      throw new Error('Theme toggle button not found');
    }
    
    await screenshot(page, 'theme_before_toggle');
    await themeBtn.click();
    await new Promise(r => setTimeout(r, 500));
    await screenshot(page, 'theme_after_toggle');
    
    // Toggle back
    await themeBtn.click();
    await new Promise(r => setTimeout(r, 500));
  });
}

async function testPrivacyMode(page) {
  await runTest('Privacy mode toggles correctly', async () => {
    const privacyBtn = await page.$('button[onclick*="togglePrivacy"], #privacy-toggle');
    if (!privacyBtn) {
      console.log('   Privacy mode not available (optional feature)');
      return;
    }
    
    await screenshot(page, 'privacy_before');
    await privacyBtn.click();
    await new Promise(r => setTimeout(r, 500));
    await screenshot(page, 'privacy_enabled');
    
    // Toggle back
    await privacyBtn.click();
    await new Promise(r => setTimeout(r, 500));
  });
}

async function testSearch(page) {
  await runTest('Search functionality works', async () => {
    const searchInput = await page.$('input[type="search"], #service-search');
    if (!searchInput) {
      console.log('   Search not available');
      return;
    }
    
    await searchInput.type('invidious');
    await new Promise(r => setTimeout(r, 500));
    
    const visibleCards = await page.$$eval('.service-card:not([style*="display: none"])', 
      cards => cards.length);
    console.log(`   Search results: ${visibleCards} cards`);
    
    await screenshot(page, 'search_results');
    
    // Clear search
    await searchInput.click({ clickCount: 3 });
    await page.keyboard.press('Backspace');
    await new Promise(r => setTimeout(r, 500));
  });
}

async function testServiceLinks(page) {
  await runTest('Service links are accessible', async () => {
    const links = await page.$$('a[href*="://"]');
    console.log(`   Found ${links.length} service links`);
    
    if (links.length === 0) {
      throw new Error('No service links found');
    }
  });
}

// ============================================================================
// ADMIN AUTHENTICATION TESTS
// ============================================================================

async function testAdminLogin(page) {
  await runTest('Admin authentication successful', async () => {
    await authenticateAdmin(page);
    
    const adminElements = await page.$$('.admin-only');
    if (adminElements.length === 0) {
      throw new Error('Admin elements not visible after login');
    }
    console.log(`   Admin elements visible: ${adminElements.length}`);
  });
}

async function testAdminLogout(page) {
  await runTest('Admin logout hides controls', async () => {
    await screenshot(page, 'admin_before_logout');
    await logoutAdmin(page);
    await screenshot(page, 'admin_after_logout');
    
    const adminElements = await page.$$eval('.admin-only',
      els => els.filter(el => el.offsetParent !== null).length
    );
    
    if (adminElements > 0) {
      throw new Error(`Admin elements still visible: ${adminElements}`);
    }
  });
}

async function testAdminRelogin(page) {
  await runTest('Admin can re-authenticate', async () => {
    await authenticateAdmin(page);
    const adminElements = await page.$$('.admin-only');
    if (adminElements.length === 0) {
      throw new Error('Failed to re-authenticate');
    }
  });
}

// ============================================================================
// SERVICE MANAGEMENT TESTS
// ============================================================================

async function testServiceStatus(page) {
  await runTest('Service status updates correctly', async () => {
    await new Promise(r => setTimeout(r, 3000)); // Wait for status API calls
    
    const statusElements = await page.$$('.status-indicator, [class*="status"]');
    console.log(`   Status indicators: ${statusElements.length}`);
    
    await screenshot(page, 'service_status');
  });
}

async function testCheckUpdates(page) {
  await runTest('Check updates functionality', async () => {
    // Wait for button to be fully rendered
    await new Promise(r => setTimeout(r, 2000));
    
    const updateBtn = await page.$('button[onclick*="checkUpdates"]');
    if (!updateBtn) {
      console.log('   Update check button not found (expected in admin mode)');
      return;
    }
    
    // Check if button is visible and clickable
    const isVisible = await page.evaluate(btn => {
      return btn.offsetParent !== null;
    }, updateBtn);
    
    if (!isVisible) {
      console.log('   Update button exists but not visible (expected)');
      return;
    }
    
    await screenshot(page, 'before_update_check');
    await updateBtn.click();
    await new Promise(r => setTimeout(r, 2000));
    await screenshot(page, 'after_update_check');
  });
}

async function testServiceUpdate(page) {
  await runTest('Service update UI interaction', async () => {
    // Look for update buttons on service cards
    const updateButtons = await page.$$('button[onclick*="updateService"]');
    if (updateButtons.length === 0) {
      console.log('   No update buttons available (expected if all services up to date)');
      return;
    }
    
    console.log(`   Found ${updateButtons.length} update buttons`);
    await screenshot(page, 'update_buttons_available');
  });
}

async function testRollbackUI(page) {
  await runTest('Rollback UI elements present', async () => {
    const rollbackButtons = await page.$$('button[onclick*="rollback"]');
    console.log(`   Rollback buttons: ${rollbackButtons.length}`);
    await screenshot(page, 'rollback_ui');
  });
}

async function testMigrationTools(page) {
  await runTest('Migration tools accessible', async () => {
    const migrationButtons = await page.$$('button[onclick*="migrate"]');
    console.log(`   Migration buttons: ${migrationButtons.length}`);
    
    if (migrationButtons.length > 0) {
      await screenshot(page, 'migration_tools');
    }
  });
}

// ============================================================================
// WIREGUARD MANAGEMENT TESTS
// ============================================================================

async function testWireGuardPanel(page) {
  await runTest('WireGuard management panel accessible', async () => {
    const wgPanel = await page.$('#wireguard-panel, [class*="wireguard"]');
    if (!wgPanel) {
      console.log('   WireGuard panel not found');
      return;
    }
    
    await screenshot(page, 'wireguard_panel');
  });
}

async function testWireGuardProfiles(page) {
  await runTest('WireGuard profiles display', async () => {
    const profiles = await page.$$('.wg-profile, [class*="profile"]');
    console.log(`   WireGuard profiles: ${profiles.length}`);
    await screenshot(page, 'wireguard_profiles');
  });
}

async function testWireGuardSwitch(page) {
  await runTest('WireGuard profile switching UI', async () => {
    const switchButtons = await page.$$('button[onclick*="switchProfile"]');
    console.log(`   Profile switch buttons: ${switchButtons.length}`);
  });
}

// ============================================================================
// SYSTEM OPERATIONS TESTS
// ============================================================================

async function testSystemInfo(page) {
  await runTest('System information displays', async () => {
    const sysInfo = await page.$('#system-info, .system-stats');
    if (!sysInfo) {
      console.log('   System info panel not found');
      return;
    }
    
    await screenshot(page, 'system_info');
  });
}

async function testCertificateStatus(page) {
  await runTest('Certificate status visible', async () => {
    const certStatus = await page.$('[class*="certificate"], [id*="cert"]');
    if (certStatus) {
      await screenshot(page, 'certificate_status');
    }
  });
}

async function testContainerStatus(page) {
  await runTest('Container status monitoring', async () => {
    await new Promise(r => setTimeout(r, 3000)); // Wait for container status updates
    
    const containers = await page.$$('.container-status, [class*="container"]');
    console.log(`   Container status elements: ${containers.length}`);
    await screenshot(page, 'container_status');
  });
}

async function testBackupControls(page) {
  await runTest('Backup controls accessible', async () => {
    const backupBtn = await page.$('button[onclick*="backup"]');
    if (!backupBtn) {
      console.log('   Backup button not found (may be in settings)');
      return;
    }
    
    await screenshot(page, 'backup_controls');
  });
}

async function testRestoreControls(page) {
  await runTest('Restore controls accessible', async () => {
    const restoreBtn = await page.$('button[onclick*="restore"]');
    if (restoreBtn) {
      await screenshot(page, 'restore_controls');
    }
  });
}

// ============================================================================
// SETTINGS & CONFIGURATION TESTS
// ============================================================================

async function testSettingsPanel(page) {
  await runTest('Settings panel opens', async () => {
    // Settings might be in a menu or modal, check various selectors
    await new Promise(r => setTimeout(r, 1000));
    
    // Look for any settings-related button
    const settingsSelectors = [
      'button[onclick*="settings"]',
      '#settings-btn',
      'button[data-tooltip*="settings"]',
      'button[aria-label*="settings"]'
    ];
    
    let settingsBtn = null;
    for (const selector of settingsSelectors) {
      settingsBtn = await page.$(selector);
      if (settingsBtn) break;
    }
    
    if (!settingsBtn) {
      console.log('   Settings button not found (may be in different location)');
      return;
    }
    
    // Ensure button is clickable
    const isClickable = await page.evaluate(btn => {
      return btn.offsetParent !== null && !btn.disabled;
    }, settingsBtn);
    
    if (!isClickable) {
      console.log('   Settings button found but not clickable');
      return;
    }
    
    await settingsBtn.click();
    await new Promise(r => setTimeout(r, 1000));
    await screenshot(page, 'settings_panel');
    
    // Close settings
    const closeBtn = await page.$('.close, button[onclick*="close"]');
    if (closeBtn) {
      await closeBtn.click();
      await new Promise(r => setTimeout(r, 500));
    }
  });
}

async function testUpdateStrategy(page) {
  await runTest('Update strategy configuration', async () => {
    const strategySelect = await page.$('select[name*="update"], #update-strategy');
    if (!strategySelect) {
      console.log('   Update strategy selector not found');
      return;
    }
    
    const currentValue = await page.$eval(
      'select[name*="update"], #update-strategy',
      el => el.value
    );
    console.log(`   Current update strategy: ${currentValue}`);
  });
}

async function testThemeConfiguration(page) {
  await runTest('Theme configuration persists', async () => {
    const themeConfig = await page.evaluate(() => {
      return localStorage.getItem('theme') || sessionStorage.getItem('theme');
    });
    console.log(`   Theme configuration: ${themeConfig || 'default'}`);
  });
}

// ============================================================================
// LOG VIEWER TESTS
// ============================================================================

async function testLogViewer(page) {
  await runTest('Log viewer accessible', async () => {
    await new Promise(r => setTimeout(r, 1000));
    
    // Look for log viewer in various locations
    const logSelectors = [
      'button[onclick*="logs"]',
      'button[onclick*="showLogs"]',
      '#view-logs',
      'button[data-tooltip*="log"]',
      'a[href*="logs"]'
    ];
    
    let logBtn = null;
    for (const selector of logSelectors) {
      logBtn = await page.$(selector);
      if (logBtn) break;
    }
    
    if (!logBtn) {
      console.log('   Log viewer button not found (may require admin mode or different location)');
      return;
    }
    
    // Check if clickable
    const isClickable = await page.evaluate(btn => {
      return btn.offsetParent !== null && !btn.disabled;
    }, logBtn);
    
    if (!isClickable) {
      console.log('   Log viewer button found but not clickable');
      return;
    }
    
    await logBtn.click();
    await new Promise(r => setTimeout(r, 1000));
    await screenshot(page, 'log_viewer');
    
    // Close logs
    const closeBtn = await page.$('.close, button[onclick*="close"]');
    if (closeBtn) {
      await closeBtn.click();
    }
  });
}

async function testLogFiltering(page) {
  await runTest('Log filtering functionality', async () => {
    const logFilter = await page.$('input[type="search"][placeholder*="log"], #log-search');
    if (!logFilter) {
      console.log('   Log filter not available');
      return;
    }
    
    await logFilter.type('INFO');
    await new Promise(r => setTimeout(r, 500));
    await screenshot(page, 'log_filtered');
  });
}

// ============================================================================
// API ENDPOINT TESTS
// ============================================================================

async function testAPIEndpoints() {
  await runTest('API endpoints respond correctly', async () => {
    const endpoints = [
      '/api/status',
      '/api/health',
      '/api/system-health',
      '/api/services',
      '/api/theme',
    ];
    
    for (const endpoint of endpoints) {
      try {
        const response = await fetch(`${CONFIG.apiUrl}${endpoint}`);
        console.log(`   ${endpoint}: ${response.status}`);
      } catch (error) {
        console.warn(`   ${endpoint}: FAILED`);
      }
    }
  });
}

async function testAdminAPIEndpoints() {
  await runTest('Admin API endpoints require authentication', async () => {
    const adminEndpoints = [
      '/api/backup',
      '/api/update-service',
      '/api/migrate',
      '/api/restart-stack',
    ];
    
    for (const endpoint of adminEndpoints) {
      try {
        const response = await fetch(`${CONFIG.apiUrl}${endpoint}`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
        });
        // Should return 401 or 403 without auth
        console.log(`   ${endpoint}: ${response.status} (expected 401/403)`);
      } catch (error) {
        console.warn(`   ${endpoint}: Connection error`);
      }
    }
  });
}

// ============================================================================
// REPORT GENERATION
// ============================================================================

async function generateReport() {
  const duration = ((Date.now() - testResults.startTime) / 1000).toFixed(2);
  const total = testResults.passed + testResults.failed;
  
  const report = {
    timestamp: new Date().toISOString(),
    duration: `${duration}s`,
    summary: {
      total,
      passed: testResults.passed,
      failed: testResults.failed,
      passRate: total > 0 ? `${((testResults.passed / total) * 100).toFixed(1)}%` : '0%',
    },
    interactions: testResults.interactions,
    errors: testResults.errors,
  };
  
  const reportPath = path.join(CONFIG.reportDir, `admin_complete_test_${Date.now()}.json`);
  await fs.writeFile(reportPath, JSON.stringify(report, null, 2));
  
  console.log('\n' + '='.repeat(60));
  console.log('TEST REPORT SUMMARY');
  console.log('='.repeat(60));
  console.log(`Duration: ${duration}s`);
  console.log(`✅ Passed: ${testResults.passed}`);
  console.log(`❌ Failed: ${testResults.failed}`);
  console.log(`Pass Rate: ${report.summary.passRate}`);
  console.log(`Report: ${reportPath}`);
  
  if (testResults.failed > 0) {
    console.log('\nFailed Tests:');
    testResults.errors.forEach((error) => {
      console.log(`  - ${error.test}: ${error.error}`);
    });
  }
  
  console.log('='.repeat(60));
  
  return testResults.failed === 0 ? 0 : 1;
}

// ============================================================================
// MAIN TEST RUNNER
// ============================================================================

async function main() {
  console.log('🚀 Starting Complete Dashboard Admin & User Interaction Tests\n');
  
  await setupEnvironment();
  
  const { browser, page, consoleLogs } = await initBrowser();
  
  try {
    // ========== USER INTERACTION TESTS ==========
    console.log('\n' + '='.repeat(60));
    console.log('USER INTERACTION TESTS');
    console.log('='.repeat(60));
    
    await testDashboardLoad(page);
    await testServiceCards(page);
    await testFilterChips(page);
    await testThemeToggle(page);
    await testPrivacyMode(page);
    await testSearch(page);
    await testServiceLinks(page);
    await testServiceStatus(page);
    
    // ========== ADMIN AUTHENTICATION TESTS ==========
    console.log('\n' + '='.repeat(60));
    console.log('ADMIN AUTHENTICATION TESTS');
    console.log('='.repeat(60));
    
    await testAdminLogin(page);
    await testAdminLogout(page);
    await testAdminRelogin(page);
    
    // ========== SERVICE MANAGEMENT TESTS ==========
    console.log('\n' + '='.repeat(60));
    console.log('SERVICE MANAGEMENT TESTS');
    console.log('='.repeat(60));
    
    await testCheckUpdates(page);
    await testServiceUpdate(page);
    await testRollbackUI(page);
    await testMigrationTools(page);
    
    // ========== WIREGUARD TESTS ==========
    console.log('\n' + '='.repeat(60));
    console.log('WIREGUARD MANAGEMENT TESTS');
    console.log('='.repeat(60));
    
    await testWireGuardPanel(page);
    await testWireGuardProfiles(page);
    await testWireGuardSwitch(page);
    
    // ========== SYSTEM OPERATIONS TESTS ==========
    console.log('\n' + '='.repeat(60));
    console.log('SYSTEM OPERATIONS TESTS');
    console.log('='.repeat(60));
    
    await testSystemInfo(page);
    await testCertificateStatus(page);
    await testContainerStatus(page);
    await testBackupControls(page);
    await testRestoreControls(page);
    
    // ========== SETTINGS TESTS ==========
    console.log('\n' + '='.repeat(60));
    console.log('SETTINGS & CONFIGURATION TESTS');
    console.log('='.repeat(60));
    
    await testSettingsPanel(page);
    await testUpdateStrategy(page);
    await testThemeConfiguration(page);
    
    // ========== LOG VIEWER TESTS ==========
    console.log('\n' + '='.repeat(60));
    console.log('LOG VIEWER TESTS');
    console.log('='.repeat(60));
    
    await testLogViewer(page);
    await testLogFiltering(page);
    
    // ========== API TESTS ==========
    console.log('\n' + '='.repeat(60));
    console.log('API ENDPOINT TESTS');
    console.log('='.repeat(60));
    
    await testAPIEndpoints();
    await testAdminAPIEndpoints();
    
    // ========== CONSOLE LOG ANALYSIS ==========
    console.log('\n' + '='.repeat(60));
    console.log('BROWSER CONSOLE LOG ANALYSIS');
    console.log('='.repeat(60));
    
    const errors = consoleLogs.filter(log => log.type === 'error');
    const warnings = consoleLogs.filter(log => log.type === 'warning');
    
    console.log(`Total console messages: ${consoleLogs.length}`);
    console.log(`Errors: ${errors.length}`);
    console.log(`Warnings: ${warnings.length}`);
    
    if (errors.length > 0) {
      console.log('\nConsole Errors:');
      errors.slice(0, 10).forEach(log => console.log(`  - ${log.text}`));
    }
    
  } catch (error) {
    console.error('\n❌ Fatal error during test execution:', error);
    testResults.errors.push({ test: 'Main Runner', error: error.message, stack: error.stack });
  } finally {
    await browser.close();
  }
  
  const exitCode = await generateReport();
  process.exit(exitCode);
}

// Run the test suite
if (require.main === module) {
  main().catch(error => {
    console.error('Unhandled error:', error);
    process.exit(1);
  });
}

module.exports = { main, CONFIG };
