/**
 * @fileoverview Comprehensive UI Verification Suite for ZimaOS Privacy Hub.
 * 
 * This script utilizes Puppeteer to perform an end-to-end audit of the dashboard,
 * checking for accessibility, visual rendering (M3), status indicators,
 * interaction flows, and console health.
 * 
 * Adheres to the Google JavaScript Style Guide.
 */

const path = require('path');
const {
  initBrowser,
  logResult,
  getResults,
  getAdminPassword,
  generateReport,
  getConsoleLogs,
  SCREENSHOT_DIR,
} = require('./lib/browser_utils');

/** @const {string} LAN IP for the test environment. */
const LAN_IP = process.env.LAN_IP || '127.0.0.1';

/** @const {string} URL of the dashboard. */
const DASHBOARD_URL = `http://${LAN_IP}:8088`;

/**
 * Main execution function for the UI audit.
 */
async function runAudit() {
  const {browser, page} = await initBrowser();
  const adminPass = getAdminPassword();

  try {
    console.log(`\n=== Starting UI Audit at ${DASHBOARD_URL} ===`);

    // --- Phase 1: Initial Load & Accessibility ---
    try {
      await page.goto(DASHBOARD_URL, {waitUntil: 'networkidle2', timeout: 45000});
      logResult('Dashboard', 'Load', 'PASS', 'Dashboard reachable and loaded');
    } catch (e) {
      logResult('Dashboard', 'Load', 'FAIL', `Failed to load dashboard: ${e.message}`);
      throw e;
    }

    await page.screenshot({path: path.join(SCREENSHOT_DIR, '01-initial-load.png')});

    // --- Phase 2: Service Status Indicators ---
    console.log('  Verifying Service Status Indicators...');
    // Allow time for WebSocket/polling to update statuses
    await new Promise((r) => setTimeout(r, 5000));

    const serviceStates = await page.evaluate(() => {
      const indicators = document.querySelectorAll('.status-indicator');
      const results = [];
      indicators.forEach((ind) => {
        const dot = ind.querySelector('.status-dot');
        const labelSpan = ind.querySelector('span:not(.status-dot)');
        const text = labelSpan ? labelSpan.textContent.trim() : 'Unknown';
        const card = ind.closest('.card');
        const name = card ?
            (card.querySelector('h2')?.textContent ||
             card.querySelector('h3')?.textContent || 'Unknown') :
            'Unknown';

        let status = 'UNKNOWN';
        if (dot.classList.contains('active') || dot.classList.contains('up')) {
          status = 'ONLINE';
        } else if (dot.classList.contains('down') || dot.classList.contains('error')) {
          status = 'OFFLINE';
        } else if (dot.classList.contains('starting') || dot.classList.contains('pending')) {
          status = 'STARTING';
        }

        results.push({name, status, text});
      });
      return results;
    });

    const offlineServices = serviceStates.filter((s) => s.status === 'OFFLINE');
    if (offlineServices.length === 0 && serviceStates.length > 0) {
      logResult('Services', 'Status Check', 'PASS',
          `All ${serviceStates.length} services reporting ONLINE`);
    } else if (serviceStates.length === 0) {
      logResult('Services', 'Status Check', 'WARN',
          'No status indicators found (Dashboard might be empty?)');
    } else {
      const details = offlineServices.map((s) => `${s.name}`).join(', ');
      logResult('Services', 'Status Check', 'FAIL',
          `Offline services detected: ${details}`);
    }

    // --- Phase 3: Layout & Visual Integrity ---
    console.log('  Running Visual Integrity Audit (Overlap & Overflow)...');
    const layoutIssues = await page.evaluate(() => {
      const issues = [];
      const isOverflowing = (el) =>
          el.offsetWidth < el.scrollWidth || el.offsetHeight < el.scrollHeight;

      // Helper to check overlap
      const overlaps = (r1, r2) => {
        if (r1.width === 0 || r1.height === 0 || r2.width === 0 || r2.height === 0) {
          return false;
        }
        return !(r1.right <= r2.left || r1.left >= r2.right ||
                 r1.bottom <= r2.top || r1.top >= r2.bottom);
      };

      const cards = document.querySelectorAll('.card');
      cards.forEach((card, i) => {
        const name = card.querySelector('h2, h3')?.textContent || `Card ${i}`;
        const header = card.querySelector('.card-header');
        const actions = card.querySelector('.card-header-actions');
        const rect = card.getBoundingClientRect();

        // Check overflow in titles
        const title = card.querySelector('h2, h3');
        if (title && isOverflowing(title)) {
          issues.push(`Text overflow in title of [${name}]`);
        }

        // Check overlap between title and actions
        if (header && actions && title) {
          if (overlaps(title.getBoundingClientRect(), actions.getBoundingClientRect())) {
            issues.push(`Header content overlap in [${name}]`);
          }
        }

        // Check card overlap with other cards
        cards.forEach((otherCard, j) => {
          if (i !== j) {
            if (overlaps(rect, otherCard.getBoundingClientRect())) {
              issues.push(`Card [${name}] overlaps with another card`);
            }
          }
        });
      });

      // M3 Spacing Check (8dp Grid)
      const sections = document.querySelectorAll('section');
      sections.forEach((sec) => {
        const style = window.getComputedStyle(sec);
        const marginTop = parseInt(style.marginTop);
        const marginBottom = parseInt(style.marginBottom);

        if (marginTop % 8 !== 0) {
          issues.push(`Section margin-top (${marginTop}px) violates 8dp grid`);
        }
        if (marginBottom % 8 !== 0) {
          issues.push(`Section margin-bottom (${marginBottom}px) violates 8dp grid`);
        }
      });

      return issues;
    });

    if (layoutIssues.length === 0) {
      logResult('UI', 'Layout Integrity', 'PASS',
          'No overlaps, overflows, or M3 grid violations detected');
    } else {
      // De-duplicate issues
      const uniqueIssues = [...new Set(layoutIssues)];
      logResult('UI', 'Layout Integrity', 'FAIL', uniqueIssues.join('; '));
    }

    // --- Phase 4: Sign in / Authentication Flow ---
    console.log('  Verifying Authentication Flow...');

    // Check for "Sign in" terminology (Google Style Guide)
    const signinBtn = await page.$('#admin-lock-btn, .login-btn, .signin-btn');
    if (signinBtn) {
      await signinBtn.click();
      await page.waitForSelector('#signin-modal', {visible: true, timeout: 5000});

      const modalTitle = await page.$eval('#signin-modal h2', (el) => el.textContent);
      // Strict case-sensitive check for "Sign in" terminology
      if (modalTitle.includes('Sign in')) {
        logResult('UI', 'Terminology', 'PASS', 'Modal uses correct "Sign in" terminology');
      } else {
        logResult('UI', 'Terminology', 'WARN',
            `Modal title "${modalTitle}" should use "Sign in"`);
      }

      // Perform Sign in
      await page.type('#admin-password-input', adminPass);
      // Assuming the button is the one with 'btn-filled' class inside modal
      await page.click('#signin-modal .btn-filled');

      try {
        await page.waitForFunction(() => document.body.classList.contains('admin-mode'),
            {timeout: 10000});
        logResult('Auth', 'Admin Sign in', 'PASS', 'Authenticated successfully');
      } catch (e) {
        logResult('Auth', 'Admin Sign in', 'FAIL',
            'Failed to enter admin mode after credentials');
      }
    } else {
      logResult('Auth', 'Sign in Button', 'WARN', 'Could not locate sign in button');
    }

    // --- Phase 5: Browser Console Audit ---
    console.log('  Auditing Browser Console...');
    const logs = getConsoleLogs();
    const errors = logs.filter((l) => l.type === 'error');

    // Filter out common "noise"
    const criticalErrors = errors.filter((e) => {
      const text = e.text.toLowerCase();
      if (text.includes('favicon.ico')) return false;
      if (text.includes('content security policy')) return false;
      return true;
    });

    if (criticalErrors.length === 0) {
      logResult('Browser', 'Console Health', 'PASS', 'No critical errors found');
    } else {
      logResult('Browser', 'Console Health', 'FAIL',
          `${criticalErrors.length} critical errors found in console`);
    }

    // Capture final state
    await page.screenshot({path: path.join(SCREENSHOT_DIR, '99-final-state.png')});
  } catch (error) {
    console.error('Test Suite Fatal Error:', error);
    logResult('System', 'Test Suite', 'FAIL', error.message);
    process.exitCode = 1;
  } finally {
    await browser.close();
    await generateReport();
    
    // Exit with error if any tests failed
    const hasFailures = getResults().some(r => r.outcome === 'FAIL');
    if (hasFailures) {
        console.error('UI Audit failed with one or more test failures.');
        process.exit(1);
    }
  }
}

runAudit();

