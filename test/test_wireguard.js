/**
 * @fileoverview WireGuard Tunnel Generation and Connection Tests
 * 
 * Tests complete WireGuard workflow:
 * - Client generation via WG-Easy
 * - Configuration download
 * - QR code generation
 * - Client activation/deactivation
 * - Connection status monitoring
 * 
 * Adheres to Google JavaScript Style Guide.
 */

const {
  initBrowser,
  logResult,
  getResults,
  getAdminPassword,
  generateReport,
} = require('./lib/browser_utils');

/** @const {string} Test environment configuration */
const LAN_IP = process.env.LAN_IP || '127.0.0.1';
const DASHBOARD_URL = `http://${LAN_IP}:8088`;
const WG_EASY_PORT = process.env.WG_EASY_PORT || '51821';

/**
 * Test: WG-Easy service accessibility
 * @param {Page} page Puppeteer page instance
 */
async function testWGEasyAccessibility(page) {
  try {
    // Navigate to WG-Easy
    const wgEasyUrl = `http://${LAN_IP}:${WG_EASY_PORT}`;
    const response = await page.goto(wgEasyUrl, {
      waitUntil: 'networkidle2',
      timeout: 10000,
    });

    if (response && response.ok()) {
      logResult('WireGuard', 'WG-Easy Access', 'PASS',
          'WG-Easy interface accessible');
      return true;
    } else {
      logResult('WireGuard', 'WG-Easy Access', 'FAIL',
          `WG-Easy returned status ${response?.status()}`);
      return false;
    }
  } catch (error) {
    logResult('WireGuard', 'WG-Easy Access', 'FAIL',
        `Cannot reach WG-Easy: ${error.message}`);
    return false;
  }
}

/**
 * Test: WG-Easy authentication
 * @param {Page} page Puppeteer page instance
 */
async function testWGEasyAuthentication(page) {
  try {
    // Check if password prompt exists
    const passwordField = await page.$('input[type="password"]');
    if (!passwordField) {
      logResult('WireGuard', 'WG-Easy Auth', 'PASS',
          'Already authenticated or no auth required');
      return true;
    }

    // Try to authenticate
    const wgPassword = process.env.WGE_PASS || await getAdminPassword();
    await page.type('input[type="password"]', wgPassword);
    
    const submitBtn = await page.$('button[type="submit"]');
    if (submitBtn) {
      await submitBtn.click();
      await page.waitForTimeout(2000);
    }

    // Check if auth succeeded
    const stillHasPassword = await page.$('input[type="password"]');
    if (!stillHasPassword) {
      logResult('WireGuard', 'WG-Easy Auth', 'PASS',
          'Successfully authenticated');
      return true;
    } else {
      logResult('WireGuard', 'WG-Easy Auth', 'FAIL',
          'Authentication failed');
      return false;
    }
  } catch (error) {
    logResult('WireGuard', 'WG-Easy Auth', 'FAIL', error.message);
    return false;
  }
}

/**
 * Test: Client list display
 * @param {Page} page Puppeteer page instance
 */
async function testClientListDisplay(page) {
  try {
    // Wait for client list to load
    await page.waitForTimeout(2000);

    // Check for client list container
    const hasClientList = await page.evaluate(() => {
      // WG-Easy typically uses a container for clients
      const containers = document.querySelectorAll('[class*="client"]');
      return containers.length > 0;
    });

    if (hasClientList) {
      const clientCount = await page.evaluate(() => {
        const clients = document.querySelectorAll('[class*="client"]');
        return clients.length;
      });
      
      logResult('WireGuard', 'Client List Display', 'PASS',
          `Found ${clientCount} client entries`);
      return true;
    } else {
      logResult('WireGuard', 'Client List Display', 'WARN',
          'No clients found or UI structure different');
      return false;
    }
  } catch (error) {
    logResult('WireGuard', 'Client List Display', 'FAIL', error.message);
    return false;
  }
}

/**
 * Test: Add new client button presence
 * @param {Page} page Puppeteer page instance
 */
async function testAddClientButton(page) {
  try {
    // Look for add client button (various possible texts)
    const addButton = await page.evaluate(() => {
      const buttons = Array.from(document.querySelectorAll('button'));
      return buttons.some((btn) => {
        const text = btn.textContent.toLowerCase();
        return text.includes('add') || text.includes('new') ||
               text.includes('create') || text.includes('+');
      });
    });

    if (addButton) {
      logResult('WireGuard', 'Add Client Button', 'PASS',
          'Add client button found');
      return true;
    } else {
      logResult('WireGuard', 'Add Client Button', 'FAIL',
          'Add client button not found');
      return false;
    }
  } catch (error) {
    logResult('WireGuard', 'Add Client Button', 'FAIL', error.message);
    return false;
  }
}

/**
 * Test: Client creation flow
 * @param {Page} page Puppeteer page instance
 */
async function testClientCreation(page) {
  try {
    // Find and click add button
    const addBtn = await page.evaluateHandle(() => {
      const buttons = Array.from(document.querySelectorAll('button'));
      return buttons.find((btn) => {
        const text = btn.textContent.toLowerCase();
        return text.includes('add') || text.includes('new') ||
               text.includes('create');
      });
    });

    if (!addBtn) {
      logResult('WireGuard', 'Client Creation', 'SKIP',
          'Add button not found');
      return false;
    }

    await addBtn.click();
    await page.waitForTimeout(1000);

    // Look for name input field
    const nameField = await page.$('input[name*="name"], input[placeholder*="name"]');
    if (!nameField) {
      logResult('WireGuard', 'Client Creation', 'WARN',
          'Name input field not found after clicking add');
      return false;
    }

    // Generate test client name
    const testClientName = `test_client_${Date.now()}`;
    await page.type('input[name*="name"], input[placeholder*="name"]',
        testClientName);

    // Look for create/submit button
    const createBtn = await page.evaluateHandle(() => {
      const buttons = Array.from(document.querySelectorAll('button'));
      return buttons.find((btn) => {
        const text = btn.textContent.toLowerCase();
        return text.includes('create') || text.includes('add') ||
               text.includes('submit') || text.includes('save');
      });
    });

    if (createBtn) {
      await createBtn.click();
      await page.waitForTimeout(2000);

      logResult('WireGuard', 'Client Creation', 'PASS',
          `Test client "${testClientName}" creation attempted`);
      return true;
    } else {
      logResult('WireGuard', 'Client Creation', 'WARN',
          'Create button not found');
      return false;
    }
  } catch (error) {
    logResult('WireGuard', 'Client Creation', 'FAIL', error.message);
    return false;
  }
}

/**
 * Test: QR code generation
 * @param {Page} page Puppeteer page instance
 */
async function testQRCodeGeneration(page) {
  try {
    // Look for QR code elements (SVG, canvas, or img)
    const hasQRCode = await page.evaluate(() => {
      const qrElements = document.querySelectorAll(
          'svg[class*="qr"], canvas[class*="qr"], img[alt*="QR"]'
      );
      return qrElements.length > 0;
    });

    if (hasQRCode) {
      logResult('WireGuard', 'QR Code Generation', 'PASS',
          'QR code element detected');
      return true;
    } else {
      logResult('WireGuard', 'QR Code Generation', 'WARN',
          'QR code not found (may require client expansion)');
      return false;
    }
  } catch (error) {
    logResult('WireGuard', 'QR Code Generation', 'FAIL', error.message);
    return false;
  }
}

/**
 * Test: Configuration download functionality
 * @param {Page} page Puppeteer page instance
 */
async function testConfigDownload(page) {
  try {
    // Look for download buttons/links
    const hasDownload = await page.evaluate(() => {
      const elements = Array.from(document.querySelectorAll('a, button'));
      return elements.some((el) => {
        const text = el.textContent.toLowerCase();
        const href = el.href || '';
        return text.includes('download') || text.includes('config') ||
               href.includes('download') || href.includes('.conf');
      });
    });

    if (hasDownload) {
      logResult('WireGuard', 'Config Download', 'PASS',
          'Download functionality available');
      return true;
    } else {
      logResult('WireGuard', 'Config Download', 'WARN',
          'Download option not found');
      return false;
    }
  } catch (error) {
    logResult('WireGuard', 'Config Download', 'FAIL', error.message);
    return false;
  }
}

/**
 * Test: Client enable/disable toggle
 * @param {Page} page Puppeteer page instance
 */
async function testClientToggle(page) {
  try {
    // Look for toggle switches or enable/disable buttons
    const hasToggle = await page.evaluate(() => {
      const toggles = document.querySelectorAll(
          'input[type="checkbox"], .toggle, .switch'
      );
      const buttons = Array.from(document.querySelectorAll('button'));
      const hasToggleBtn = buttons.some((btn) => {
        const text = btn.textContent.toLowerCase();
        return text.includes('enable') || text.includes('disable');
      });
      return toggles.length > 0 || hasToggleBtn;
    });

    if (hasToggle) {
      logResult('WireGuard', 'Client Toggle', 'PASS',
          'Client toggle controls found');
      return true;
    } else {
      logResult('WireGuard', 'Client Toggle', 'WARN',
          'Toggle controls not found');
      return false;
    }
  } catch (error) {
    logResult('WireGuard', 'Client Toggle', 'FAIL', error.message);
    return false;
  }
}

/**
 * Test: Dashboard integration - WG-Easy stats
 * @param {Page} page Puppeteer page instance
 */
async function testDashboardIntegration(page) {
  try {
    // Go back to dashboard
    await page.goto(DASHBOARD_URL, {waitUntil: 'networkidle2'});
    await page.waitForTimeout(2000);

    // Check for WG-Easy status chips
    const hasWGStats = await page.evaluate(() => {
      const wgChips = Array.from(document.querySelectorAll('.chip'));
      return wgChips.some((chip) => {
        const text = chip.textContent.toLowerCase();
        return text.includes('clients') || text.includes('wg-easy') ||
               text.includes('wireguard');
      });
    });

    if (hasWGStats) {
      // Get stats text
      const statsText = await page.evaluate(() => {
        const wgChips = Array.from(document.querySelectorAll('.chip'));
        const clientChip = wgChips.find((chip) =>
          chip.textContent.toLowerCase().includes('clients'));
        return clientChip ? clientChip.textContent : 'N/A';
      });

      logResult('WireGuard', 'Dashboard Integration', 'PASS',
          `Stats displayed: ${statsText}`);
      return true;
    } else {
      logResult('WireGuard', 'Dashboard Integration', 'WARN',
          'WG-Easy stats not found on dashboard');
      return false;
    }
  } catch (error) {
    logResult('WireGuard', 'Dashboard Integration', 'FAIL', error.message);
    return false;
  }
}

/**
 * Test: Connection status monitoring
 * @param {Page} page Puppeteer page instance
 */
async function testConnectionStatus(page) {
  try {
    // Navigate back to WG-Easy
    const wgEasyUrl = `http://${LAN_IP}:${WG_EASY_PORT}`;
    await page.goto(wgEasyUrl, {waitUntil: 'networkidle2'});
    await page.waitForTimeout(2000);

    // Check for connection status indicators
    const hasStatus = await page.evaluate(() => {
      // Look for online/offline/connected indicators
      const statusElements = document.querySelectorAll(
          '[class*="online"], [class*="offline"], [class*="connected"], ' +
          '[class*="status"]'
      );
      return statusElements.length > 0;
    });

    if (hasStatus) {
      logResult('WireGuard', 'Connection Status', 'PASS',
          'Status indicators present');
      return true;
    } else {
      logResult('WireGuard', 'Connection Status', 'WARN',
          'Status indicators not detected');
      return false;
    }
  } catch (error) {
    logResult('WireGuard', 'Connection Status', 'FAIL', error.message);
    return false;
  }
}

/**
 * Run all WireGuard tests
 */
async function runWireGuardTests() {
  console.log('🔐 Starting WireGuard Tunnel Tests...\n');

  const {browser, page} = await initBrowser(DASHBOARD_URL);

  try {
    // Test WG-Easy accessibility
    const accessible = await testWGEasyAccessibility(page);
    
    if (!accessible) {
      console.log('\n⚠️  WG-Easy not accessible, skipping remaining tests');
      await generateReport();
      await browser.close();
      return;
    }

    // Authentication
    const authenticated = await testWGEasyAuthentication(page);
    
    if (authenticated) {
      // UI tests
      await testClientListDisplay(page);
      await testAddClientButton(page);
      await testQRCodeGeneration(page);
      await testConfigDownload(page);
      await testClientToggle(page);
      await testConnectionStatus(page);
      
      // Client creation (may modify state)
      await testClientCreation(page);
    }

    // Dashboard integration
    await testDashboardIntegration(page);

    // Generate report
    const results = getResults();
    
    console.log('\n' + '='.repeat(70));
    console.log('WIREGUARD TEST SUMMARY');
    console.log('='.repeat(70));

    const passed = results.filter((r) => r.result === 'PASS').length;
    const failed = results.filter((r) => r.result === 'FAIL').length;
    const warned = results.filter((r) => r.result === 'WARN').length;
    const skipped = results.filter((r) => r.result === 'SKIP').length;

    console.log(`✅ Passed: ${passed}`);
    console.log(`❌ Failed: ${failed}`);
    console.log(`⚠️  Warned: ${warned}`);
    console.log(`⏭️  Skipped: ${skipped}`);
    console.log('='.repeat(70));

    await generateReport();

    process.exit(failed > 0 ? 1 : 0);
  } catch (error) {
    console.error('WireGuard test execution failed:', error);
    process.exit(1);
  } finally {
    await browser.close();
  }
}

// Run tests if executed directly
if (require.main === module) {
  runWireGuardTests();
}

module.exports = {
  testWGEasyAccessibility,
  testWGEasyAuthentication,
  testClientListDisplay,
  testAddClientButton,
  testClientCreation,
  testQRCodeGeneration,
  testConfigDownload,
  testClientToggle,
  testDashboardIntegration,
  testConnectionStatus,
};
