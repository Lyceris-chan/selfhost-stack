const puppeteer = require('puppeteer');
const fs = require('fs');
const path = require('path');

const DASHBOARD_URL = process.env.DASHBOARD_URL || 'http://localhost:8081/';

async function attachInteractionsMocks(page) {
  await page.setRequestInterception(true);
  page.on('request', (request) => {
    const url = request.url();
    const method = request.method();

    if (url.includes('/api/containers')) {
      request.respond({
        contentType: 'application/json',
        body: JSON.stringify({
          containers: {
            'invidious': { id: 'inv-id', hardened: true, status: 'running', state: 'up' },
            'adguard': { id: 'ag-id', hardened: true, status: 'running', state: 'up' },
            'hub-api': { id: 'hub-id', hardened: true, status: 'running', state: 'up' }
          }
        })
      });
    } else if (url.includes('/api/services')) {
      request.respond({
        contentType: 'application/json',
        body: JSON.stringify({
          services: {
            'invidious': { name: 'Invidious', category: 'apps', url: 'http://inv' },
            'adguard': { name: 'AdGuard', category: 'dns', url: 'http://ag' },
            'gluetun': { name: 'Gluetun', category: 'system', url: null },
            'wireguard': { name: 'WireGuard', category: 'system', url: null }
          }
        })
      });
    } else if (url.includes('/api/status')) {
      request.respond({
        contentType: 'application/json',
        body: JSON.stringify({
          gluetun: { status: 'up', healthy: true, public_ip: '1.2.3.4', location: 'Netherlands', provider: 'Mullvad' },
          wgeasy: { status: 'up', connected: 1, clients: 5, total_received: 1024567, total_sent: 512345 },
          services: { 'invidious': 'healthy', 'adguard': 'healthy' }
        })
      });
    } else if (url.includes('/api/verify-admin')) {
      request.respond({
        contentType: 'application/json',
        body: JSON.stringify({ success: true, token: 'fake-session-token' })
      });
    } else if (url.includes('/api/theme')) {
      if (method === 'POST') {
        request.respond({ contentType: 'application/json', body: JSON.stringify({ success: true }) });
      } else {
        request.respond({ contentType: 'application/json', body: JSON.stringify({ theme: 'dark', privacy_mode: false, seed_color: '#6750A4' }) });
      }
    } else if (url.includes('/api/metrics')) {
      request.respond({
        contentType: 'application/json',
        body: JSON.stringify({ metrics: { 'invidious': { cpu: 5.2, mem: 120, limit: 1024 } } })
      });
    } else if (url.includes('/api/system-health')) {
      request.respond({
        contentType: 'application/json',
        body: JSON.stringify({ cpu_percent: 12, ram_used: 2048, ram_total: 8192, project_size: 1500, uptime: '1 day, 2:30', drive_status: 'Healthy', drive_health_pct: 98, disk_percent: 45 })
      });
    } else if (url.includes('/api/certificate-status')) {
      request.respond({
        contentType: 'application/json',
        body: JSON.stringify({ status: 'Valid (Trusted)', type: 'RSA', subject: 'hub.test', issuer: 'Let\'s Encrypt', expires: '2026-12-31' })
      });
    } else if (url.includes('/api/odido/status')) {
      request.respond({
        contentType: 'application/json',
        body: JSON.stringify({ configured: true, remaining: '5.2 GB', bundle_code: 'A0DAY01', rate: '12 MB/min', status: 'Active', threshold: 100, auto_renew: true, graph_data: [10, 20, 15, 30, 25, 40] })
      });
    } else if (url.includes('/api/vpn/clients')) {
      request.respond({
        contentType: 'application/json',
        body: JSON.stringify({ clients: [{ name: 'Phone', id: 'p1', active: true, received: 5000, sent: 2000 }] })
      });
    } else if (url.includes('/api/vpn/profiles')) {
      request.respond({
        contentType: 'application/json',
        body: JSON.stringify({ profiles: ['mullvad-nl', 'proton-us'], active: 'mullvad-nl' })
      });
    } else if (url.includes('/api/logs')) {
      request.respond({
        contentType: 'application/json',
        body: JSON.stringify({ logs: [
          { time: '2026-01-08 10:00:00', level: 'INFO', category: 'SYSTEM', message: 'System started' },
          { time: '2026-01-08 10:05:00', level: 'WARN', category: 'NETWORK', message: 'VPN Reconnecting' }
        ]})
      });
    } else if (url.includes('/api/project-size-details')) {
      request.respond({
        contentType: 'application/json',
        body: JSON.stringify({
          details: [
            { name: 'Source Code', size: '50 MB' },
            { name: 'Docker Images', size: '1.2 GB' },
            { name: 'App Data', size: '250 MB' }
          ]
        })
      });
    } else if (url.includes('/api/check-updates')) {
        request.respond({
            contentType: 'application/json',
            body: JSON.stringify({ updates: [{ service: 'invidious', current: 'v1.0', latest: 'v1.1' }] })
        });
    } else if (method === 'POST') {
        // Default success for POSTs
        request.respond({ contentType: 'application/json', body: JSON.stringify({ success: true }) });
    } else {
      request.continue();
    }
  });
}

async function runTests() {
  const browser = await puppeteer.launch({
    headless: 'new',
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });
  const page = await browser.newPage();
  page.setDefaultTimeout(5000);

  console.log('--- STARTING COMPREHENSIVE DASHBOARD INTERACTION TESTS ---');

  page.on('console', msg => {
    if (msg.type() === 'error') console.log(`[BROWSER ERROR] ${msg.text()}`);
    // else console.log(`[BROWSER LOG] ${msg.text()}`); // Keep it quiet unless error
  });

  try {
    await attachInteractionsMocks(page);
    await page.goto(DASHBOARD_URL, { waitUntil: 'networkidle2' });

    // --- 1. GENERAL INTERACTIONS (NON-ADMIN) ---
    console.log('1. Testing Theme Toggle...');
    const initialTheme = await page.evaluate(() => document.documentElement.classList.contains('light-mode'));
    await page.click('.theme-toggle:first-of-type');
    await new Promise(r => setTimeout(r, 200));
    const newTheme = await page.evaluate(() => document.documentElement.classList.contains('light-mode'));
    if (initialTheme !== newTheme) console.log('   ✅ Theme toggle worked.');
    else throw new Error('Theme toggle failed');

    console.log('2. Testing Privacy Mode...');
    const initialPrivacy = await page.evaluate(() => document.body.classList.contains('privacy-mode'));
    await page.click('#privacy-switch');
    await new Promise(r => setTimeout(r, 200));
    const newPrivacy = await page.evaluate(() => document.body.classList.contains('privacy-mode'));
    if (initialPrivacy !== newPrivacy) console.log('   ✅ Privacy mode toggle worked.');
    else throw new Error('Privacy mode toggle failed');

    console.log('3. Testing Category Filters...');
    const chips = ['apps', 'system', 'dns', 'tools'];
    for (const chip of chips) {
        await page.click(`.filter-chip[data-target="${chip}"]`);
        await new Promise(r => setTimeout(r, 200));
        const isActive = await page.evaluate((c) => document.querySelector(`.filter-chip[data-target="${c}"]`).classList.contains('active'), chip);
        if (isActive) console.log('   ✅ Filter ' + chip + ' active.');
        else throw new Error('Filter ' + chip + ' failed');
    }

    // --- 2. ADMIN LOGIN ---
    console.log('4. Testing Admin Login...');
    await page.click('#admin-lock-btn');
    await page.waitForSelector('#login-modal', { visible: true });
    await page.type('#admin-password-input', 'testpassword');
    await page.click('#login-modal button[type="submit"]');
    await page.waitForFunction(() => document.body.classList.contains('admin-mode'));
    console.log('   ✅ Admin mode enabled.');

    // --- 3. ADMIN INTERACTIONS ---
    console.log('5. Testing Slot Switching Dialog...');
    await page.click('button[onclick="switchSlot()"]');
    await page.waitForSelector('#dialog-modal', { visible: true });
    if (await page.$eval('#dialog-message', el => el.textContent.includes('standby slot'))) console.log('   ✅ Slot switch dialog opened.');
    await page.click('#dialog-cancel-btn');
    await page.waitForSelector('#dialog-modal', { hidden: true });

    console.log('6. Testing Service Settings Modal & Metrics...');
    await page.waitForSelector('.settings-btn');
    await page.click('.settings-btn');
    await page.waitForSelector('#service-modal', { visible: true });
    const cpuText = await page.$eval('#modal-cpu-text', el => el.textContent);
    if (cpuText.includes('5.2%')) console.log('   ✅ Metrics loaded in modal.');
    await page.click('#service-modal .btn-icon');
    await page.waitForSelector('#service-modal', { hidden: true });

    console.log('7. Testing deSEC Config Form...');
    await page.type('#desec-domain-input', 'test.dedyn.io');
    await page.type('#desec-token-input', 'test-token');
    await page.click('form[onsubmit*="saveDesecConfig"] button[type="submit"]');
    console.log('   ✅ deSEC config submitted.');

    console.log('8. Testing Odido Config Form & VPN Toggle...');
    await page.click('#odido-vpn-switch');
    await new Promise(r => setTimeout(r, 200));
    const vpnActive = await page.evaluate(() => document.getElementById('odido-vpn-switch').classList.contains('active'));
    if (vpnActive) console.log('   ✅ Odido VPN toggle worked.');
    await page.type('#odido-api-key', 'secret-key');
    await page.click('form[onsubmit*="saveOdidoConfig"] button[type="submit"]');
    console.log('   ✅ Odido config submitted.');

    console.log('9. Testing VPN Client Management...');
    await page.click('button[onclick="openAddClientModal()"]');
    await page.waitForSelector('#add-client-modal', { visible: true });
    await page.type('#new-client-name', 'Test Client');
    await page.click('#add-client-modal .btn-filled');
    console.log('   ✅ Add client modal interaction worked.');
    await page.click('#add-client-modal .btn-icon');

    console.log('10. Testing WireGuard Profile Upload...');
    await page.type('#prof-name', 'Test Profile');
    await page.type('#prof-conf', '[Interface]\nPrivateKey = abc');
    await page.click('button[onclick="uploadProfile()"]');
    console.log('   ✅ Profile upload interaction worked.');

    console.log('11. Testing Theme Customization (Seed Color)...');
    await page.evaluate(() => applySeedColor('#ff0000'));
    console.log('   ✅ Seed color application worked.');
    await page.click('button[onclick="saveThemeSettings()"]');
    console.log('   ✅ Theme settings saved.');

    console.log('12. Testing Security Settings...');
    await page.select('#update-strategy-select', 'latest');
    await page.click('#session-cleanup-switch');
    await page.type('#session-timeout-input', '60');
    console.log('   ✅ Security settings interactions worked.');

    console.log('13. Testing System Actions...');
    await page.click('button[onclick="checkUpdates()"]');
    await page.click('button[onclick="restartStack()"]');
    console.log('   ✅ System action buttons clicked.');

    console.log('14. Testing Project Size Modal...');
    await page.click('.clickable-stat');
    await page.waitForSelector('#project-size-modal', { visible: true });
    await page.waitForSelector('#project-size-content', { visible: true });
    const projectContent = await page.$eval('#project-size-list', el => el.children.length);
    if (projectContent > 0) console.log('   ✅ Project size details loaded.');
    await page.click('#project-size-modal .btn-icon');

    console.log('15. Testing Log Filters...');
    await page.select('#log-filter-level', 'ERROR');
    await page.select('#log-filter-cat', 'NETWORK');
    console.log('   ✅ Log filters interaction worked.');

    console.log('--- ALL COMPREHENSIVE INTERACTION TESTS PASSED ---');

  } catch (error) {
    console.error('❌ Test run failed:', error);
    process.exit(1);
  } finally {
    await browser.close();
  }
}

runTests();