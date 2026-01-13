/**
 * @fileoverview Expanded UI audit suite for ZimaOS Privacy Hub.
 * Verifies Material Design 3 compliance, interactions, and service status.
 */

const { initBrowser, logResult, getAdminPassword, generateReport, SCREENSHOT_DIR } = require('./lib/browser_utils');
const path = require('path');

const LAN_IP = process.env.LAN_IP || '127.0.0.1';
const DASHBOARD_URL = `http://${LAN_IP}:8088`;

/**
 * Executes the full UI audit suite.
 */
async function runAudit() {
  const { browser, page } = await initBrowser();
  const adminPass = getAdminPassword();

  try {
    console.log('--- Phase 1: Initial Dashboard Audit ---');
    await page.goto(DASHBOARD_URL, { waitUntil: 'networkidle2', timeout: 30000 });
    
    // 1. Basic Page Load
    logResult('Dashboard', 'Load', 'PASS', 'Dashboard reachable');
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, '01-initial-load.png') });

    // 2. Dynamic Theme Check
    console.log('  Testing Theme Switching...');
    await page.click('.theme-toggle');
    const isLightMode = await page.evaluate(() => document.documentElement.classList.contains('light-mode'));
    logResult('Dashboard', 'Theme Toggle', isLightMode ? 'PASS' : 'FAIL', 'Light/Dark mode switch verified');
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, '02-theme-switch.png') });

    // 3. Admin Login & Interaction
    console.log('  Testing Admin Authentication...');
    await page.click('#admin-lock-btn');
    await page.waitForSelector('#signin-modal', { visible: true });
    
    // Layout check for M3 Modal
    const modalOverlap = await page.evaluate(() => {
      const header = document.querySelector('#signin-modal .modal-header');
      const title = header.querySelector('h2');
      const closeBtn = header.querySelector('.btn-icon');
      return (title.getBoundingClientRect().right > closeBtn.getBoundingClientRect().left);
    });
    logResult('Dashboard', 'Modal Layout', !modalOverlap ? 'PASS' : 'FAIL', 'No component overlap detected');

    await page.type('#admin-password-input', adminPass);
    await page.click('#signin-modal .btn-filled');
    await page.waitForFunction(() => document.body.classList.contains('admin-mode'), { timeout: 10000 });
    logResult('Dashboard', 'Admin Login', 'PASS', 'Authenticated successfully');

    // 4. Service Status Integrity
    console.log('  Verifying Service Status Indicators...');
    const statusPass = await page.evaluate(() => {
      const indicators = document.querySelectorAll('.status-indicator');
      return Array.from(indicators).every(i => i.textContent.includes('Connected') || i.textContent.includes('Online') || i.textContent.includes('Running'));
    });
    logResult('Dashboard', 'Service Integrity', statusPass ? 'PASS' : 'FAIL', 'All core services reporting healthy');

    // 5. Functional Spot Check (Invidious)
    console.log('--- Phase 2: Privacy Frontend Audit (Invidious) ---');
    try {
      await page.goto(`http://${LAN_IP}:3000`, { waitUntil: 'domcontentloaded' });
      await page.waitForSelector('input[name="q"]', { timeout: 10000 });
      await page.type('input[name="q"]', 'Privacy Hub Audit');
      await page.keyboard.press('Enter');
      await page.waitForSelector('a[href*="watch?v="]', { timeout: 10000 });
      logResult('Invidious', 'Search & Scrape', 'PASS', 'VPN-gated results returned');
    } catch (err) {
      logResult('Invidious', 'Search & Scrape', 'FAIL', err.message);
    }

  } catch (e) {
    console.error('Audit Error:', e);
    logResult('Global', 'Audit Execution', 'FAIL', e.message);
  } finally {
    await browser.close();
    await generateReport();
  }
}

runAudit();
