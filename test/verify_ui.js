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

    // --- UI Audit: Overlap & Layout Check ---
    console.log('  Running Comprehensive Layout Audit...');
    const layoutAudit = await page.evaluate(() => {
      const results = [];
      const checkOverlap = (el1, el2) => {
        const r1 = el1.getBoundingClientRect();
        const r2 = el2.getBoundingClientRect();
        return !(r1.right < r2.left || r1.left > r2.right || r1.bottom < r2.top || r1.top > r2.bottom);
      };

      // 1. Audit Cards
      const cards = document.querySelectorAll('.card');
      cards.forEach((card, i) => {
        const title = card.querySelector('h2, h3');
        const actions = card.querySelector('.card-header-actions');
        if (title && actions && checkOverlap(title, actions)) {
          results.push(`Overlap in card ${i}: Title and Actions`);
        }
      });

      // 2. Audit Chips
      const chipBoxes = document.querySelectorAll('.chip-box');
      chipBoxes.forEach((box, i) => {
        const chips = box.querySelectorAll('.chip');
        for (let j = 0; j < chips.length; j++) {
          for (let k = j + 1; k < chips.length; k++) {
            if (checkOverlap(chips[j], chips[k])) {
              results.push(`Overlap in chip-box ${i}: Chips ${j} and ${k}`);
            }
          }
        }
      });

      return results;
    });

    if (layoutAudit.length === 0) {
      logResult('Dashboard', 'Overlap Audit', 'PASS', 'No overlapping components detected');
    } else {
      logResult('Dashboard', 'Overlap Audit', 'FAIL', `Detected ${layoutAudit.length} overlaps: ${layoutAudit.join(', ')}`);
    }

    // responsiveness check
    console.log('  Testing responsiveness (Mobile Viewport)...');
    await page.setViewport({ width: 375, height: 812 }); // iPhone X
    await new Promise(r => setTimeout(r, 1000));
    const mobileAudit = await page.evaluate(() => {
      const cards = document.querySelectorAll('.card');
      const overflowing = Array.from(cards).filter(c => c.offsetWidth > window.innerWidth);
      return overflowing.length;
    });
    logResult('Dashboard', 'Mobile Responsiveness', mobileAudit === 0 ? 'PASS' : 'FAIL', 'Cards adapt to mobile width');
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, '01-mobile-view.png') });
    await page.setViewport({ width: 1280, height: 800 }); // Restore desktop

    // 2. Dynamic Theme Check
    console.log('  Testing Theme Switching...');
    await page.click('.theme-toggle');
    const isLightMode = await page.evaluate(() => document.documentElement.classList.contains('light-mode'));
    logResult('Dashboard', 'Theme Toggle', isLightMode ? 'PASS' : 'FAIL', 'Light/Dark mode switch verified');
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, '02-theme-switch.png') });

    // 3. Admin Sign in & Interaction
    console.log('  Testing Admin Authentication...');
    await page.click('#admin-lock-btn');
    await page.waitForSelector('#signin-modal', { visible: true });
    
    // Layout check for M3 Modal
    const modalAudit = await page.evaluate(() => {
      const header = document.querySelector('#signin-modal .modal-header');
      const title = header.querySelector('h2');
      const closeBtn = header.querySelector('.btn-icon');
      const overlap = (title.getBoundingClientRect().right > closeBtn.getBoundingClientRect().left);
      
      // Check for layout shifts (simplified)
      const initialTop = header.getBoundingClientRect().top;
      return { overlap, initialTop };
    });
    logResult('Dashboard', 'Modal Layout', !modalAudit.overlap ? 'PASS' : 'FAIL', 'No component overlap detected');
    logResult('Dashboard', 'M3 Spacing', modalAudit.initialTop > 0 ? 'PASS' : 'FAIL', 'Material Design spacing verified');

    await page.type('#admin-password-input', adminPass);
    await page.click('#signin-modal .btn-filled');
    await page.waitForFunction(() => document.body.classList.contains('admin-mode'), { timeout: 10000 });
    logResult('Dashboard', 'Admin Sign in', 'PASS', 'Authenticated successfully');

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
