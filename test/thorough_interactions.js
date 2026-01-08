const puppeteer = require('puppeteer');
const fs = require('fs');
const path = require('path');

const DASHBOARD_URL = process.env.DASHBOARD_URL || 'http://localhost:8081/dashboard.html';

async function attachThoroughMocks(page) {
  await page.setRequestInterception(true);
  page.on('request', (request) => {
    const url = request.url();
    const method = request.method();

    // 1. Core Services & Containers
    if (url.includes('/api/containers')) {
      request.respond({
        contentType: 'application/json',
        body: JSON.stringify({
          containers: {
            'invidious': { id: 'inv-id', hardened: true },
            'adguard': { id: 'ag-id', hardened: true },
            'hub-api': { id: 'hub-id', hardened: true },
            'gluetun': { id: 'gt-id', hardened: false },
            'portainer': { id: 'pt-id', hardened: false },
            'wg-easy': { id: 'wg-id', hardened: false }
          }
        })
      });
    } else if (url.includes('/api/services')) {
      request.respond({
        contentType: 'application/json',
        body: JSON.stringify({
          services: {
            'invidious': { name: 'Invidious', category: 'apps', url: 'http://inv', description: 'Privacy-friendly YouTube front-end.' },
            'adguard': { name: 'AdGuard', category: 'system', url: 'http://ag', description: 'Network-wide ad and tracker blocking.' },
            'gluetun': { name: 'Gluetun', category: 'system', description: 'VPN Gateway' },
            'portainer': { name: 'Portainer', category: 'tools', url: 'http://pt', description: 'Docker Management' }
          }
        })
      });
    } else if (url.includes('/api/status')) {
      request.respond({
        contentType: 'application/json',
        body: JSON.stringify({
          gluetun: { status: 'up', healthy: true, public_ip: '1.2.3.4', active_profile: 'Mullvad_US', session_rx: 1024*1024, session_tx: 512*1024, total_rx: 10*1024*1024, total_tx: 5*1024*1024 },
          wgeasy: { status: 'up', connected: 2, clients: 5, session_rx: 2048, session_tx: 1024, total_rx: 100000, total_tx: 50000 },
          services: { 'invidious': 'healthy', 'adguard': 'healthy', 'gluetun': 'healthy', 'portainer': 'healthy' }
        })
      });
    } 
    
    // 2. Auth
    else if (url.includes('/api/verify-admin')) {
      request.respond({
        contentType: 'application/json',
        body: JSON.stringify({ success: true, token: 'mock-session-token', cleanup: true })
      });
    } else if (url.includes('/api/toggle-session-cleanup')) {
      request.respond({
        contentType: 'application/json',
        body: JSON.stringify({ success: true, enabled: true })
      });
    }

    // 3. Theme & Settings
    else if (url.includes('/api/theme')) {
      if (method === 'POST') {
        request.respond({ contentType: 'application/json', body: JSON.stringify({ success: true }) });
      } else {
        request.respond({
          contentType: 'application/json', 
          body: JSON.stringify({
            theme: 'dark', 
            privacy_mode: false, 
            seed: '#D0BCFF',
            dashboard_filter: 'apps,system,tools',
            is_admin: false,
            session_timeout: 30,
            odido_use_vpn: true
          }) 
        });
      }
    }

    // 4. Metrics & Health
    else if (url.includes('/api/metrics')) {
      request.respond({
        contentType: 'application/json',
        body: JSON.stringify({
          metrics: {
            'invidious': { cpu: 5.2, mem: 120, limit: 1024 },
            'adguard': { cpu: 1.5, mem: 45, limit: 512 }
          } 
        })
      });
    } else if (url.includes('/api/system-health')) {
      request.respond({
        contentType: 'application/json',
        body: JSON.stringify({ cpu_percent: 12, ram_used: 2048, ram_total: 8192, project_size: 1500, uptime: 3600, drive_status: 'Healthy', drive_health_pct: 98, disk_percent: 45 })
      });
    } else if (url.includes('/api/project-details')) {
      request.respond({
        contentType: 'application/json',
        body: JSON.stringify({ source_size: 100, data_size: 500, images_size: 800, volumes_size: 200, containers_size: 50, dangling_size: 10 })
      });
    }

    // 5. SSL & DNS
    else if (url.includes('/api/certificate-status')) {
      request.respond({
        contentType: 'application/json',
        body: JSON.stringify({
            status: 'Issuance Failed', 
            type: 'RSA', 
            subject: 'hub.test', 
            issuer: 'Let\'s Encrypt', 
            expires: '2026-12-31',
            error: 'deSEC verification failed' 
        })
      });
    } else if (url.includes('/api/config-desec') || url.includes('/api/request-ssl-check')) {
      request.respond({ contentType: 'application/json', body: JSON.stringify({ success: true }) });
    }

    // 6. VPN Clients & Profiles
    else if (url.includes('/api/wg/clients')) {
      if (url.endsWith('/configuration')) {
          request.respond({
              contentType: 'text/plain',
              body: 'WIRE_GUARD_CONFIG_TEXT'
          });
      } else if (method === 'GET') {
        request.respond({
          contentType: 'application/json',
          body: JSON.stringify([
            { id: 'c1', name: 'Phone', address: '10.8.0.2', enabled: true, transferRx: 5000, transferTx: 2000, handshakeAt: new Date().toISOString() }
          ])
        });
      } else if (method === 'POST') {
        request.respond({ contentType: 'application/json', body: JSON.stringify({ success: true }) });
      } else if (method === 'DELETE') {
        request.respond({ contentType: 'application/json', body: JSON.stringify({ success: true }) });
      }
    } else if (url.includes('/api/profiles')) {
      request.respond({
        contentType: 'application/json',
        body: JSON.stringify({ profiles: ['Mullvad_US', 'Proton_CH'] })
      });
    } else if (url.includes('/api/activate') || url.includes('/api/upload') || url.includes('/api/delete')) {
      request.respond({ contentType: 'application/json', body: JSON.stringify({ success: true, name: 'Imported_Profile' }) });
    }

    // 7. Odido
    else if (url.includes('/odido-api/api/status')) {
      request.respond({
        contentType: 'application/json',
        body: JSON.stringify({
          state: { remaining_mb: 500, last_updated_ts: Date.now() },
          config: { absolute_min_threshold_mb: 100, bundle_code: 'A0DAY01', auto_renew_enabled: true, bundle_size_mb: 1024 },
          consumption_rate_mb_per_min: 0.5
        })
      });
    } else if (url.includes('/odido-api/api/config') || url.includes('/odido-api/api/odido/buy-bundle') || url.includes('/odido-api/api/odido/remaining') || url.includes('/api/odido-userid')) {
      request.respond({ contentType: 'application/json', body: JSON.stringify({ success: true, user_id: '1234567890ab' }) });
    }

    // 8. Updates & Logs
    else if (url.includes('/api/updates')) {
      request.respond({
        contentType: 'application/json',
        body: JSON.stringify({ updates: { 'invidious': 'Update Available', 'adguard': 'Update Available' } })
      });
    } else if (url.includes('/api/logs')) {
      request.respond({
        contentType: 'application/json',
        body: JSON.stringify({ logs: [{ timestamp: '2026-01-08 12:00:00', level: 'INFO', category: 'SYSTEM', message: 'Test log message' }] })
      });
    } else if (url.includes('/api/update-service') || url.includes('/api/batch-update') || url.includes('/api/restart-stack') || url.includes('/api/switch-slot') || url.includes('/api/purge-images') || url.includes('/api/uninstall') || url.includes('/api/check-updates')) {
      request.respond({ contentType: 'application/json', body: JSON.stringify({ success: true }) });
    }

    else {
      request.continue();
    }
  });
}

async function runThoroughTests() {
  const browser = await puppeteer.launch({
    headless: 'new',
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });
  const page = await browser.newPage();
  page.setDefaultTimeout(10000);

  console.log('--- STARTING THOROUGH DASHBOARD INTERACTION TESTS ---');

  page.on('console', msg => {
    if (msg.type() === 'error') console.log(`[BROWSER ERROR] ${msg.text()}`);
    else console.log(`[BROWSER LOG] ${msg.text()}`);
  });

  const doLogin = async () => {
    console.log('  Performing Admin Login...');
    await page.evaluate(() => document.getElementById('admin-lock-btn').click());
    await page.waitForSelector('#login-modal', { visible: true });
    await page.type('#admin-password-input', 'testpassword');
    await page.evaluate(() => document.querySelector('#login-modal button[type="submit"]').click());
    await page.waitForFunction(() => document.body.classList.contains('admin-mode'));
    console.log('  ✅ Admin mode active.');
  };

  try {
    await attachThoroughMocks(page);
    await page.goto(DASHBOARD_URL, { waitUntil: 'networkidle0' });

    // Helper: Wait for half a second
    const wait = (ms = 500) => new Promise(r => setTimeout(r, ms));

    // Suite 1: Public User Interactions
    console.log('SUITE 1: Public User Interactions');
    
    console.log('  Testing Theme Toggle...');
    await page.waitForSelector('.theme-toggle');
    await page.evaluate(() => document.querySelector('.theme-toggle').click());
    await wait();
    
    console.log('  Testing Privacy Mode...');
    await page.evaluate(() => document.getElementById('privacy-switch').click());
    await wait();

    console.log('  Testing Category Filtering...');
    await page.evaluate(() => document.querySelector('.filter-chip[data-target="apps"]').click());
    await wait();
    await page.evaluate(() => document.querySelector('.filter-chip[data-target="all"]').click());
    await wait();

    console.log('  Testing Advisory Dismissal...');
    await page.evaluate(() => document.querySelector('#mac-advisory .btn-icon').click());
    await wait();

    // Suite 2: Admin Login
    console.log('\nSUITE 2: Admin Authentication');
    await doLogin();

    // Suite 3: Admin Managed Service Interactions
    console.log('\nSUITE 3: Admin Service Management');
    
    console.log('  Testing Update Banner & Batch Update Modal...');
    await page.waitForSelector('#update-banner', { visible: true });
    await page.evaluate(() => document.querySelector('#update-banner .btn-filled').click()); // Update All
    await page.waitForSelector('#update-selection-modal', { visible: true });
    await wait(2000); // Wait for mock polling
    await page.waitForSelector('.update-checkbox', { visible: true });
    console.log('    Triggering Batch Update...');
    await page.evaluate(() => document.getElementById('start-update-btn').click());
    await page.waitForSelector('#dialog-confirm-btn', { visible: true });
    await page.evaluate(() => document.getElementById('dialog-confirm-btn').click());
    await wait();
    
    console.log('  Testing Service Settings Modal & Actions...');
    await page.waitForSelector('.settings-btn', { visible: true });
    await page.evaluate(() => document.querySelector('.settings-btn').click());
    await page.waitForSelector('#service-modal', { visible: true });
    
    console.log('    Triggering Update Service...');
    await page.evaluate(() => document.querySelector('#modal-actions button').click()); 
    await wait();
    
    console.log('    Closing Modal...');
    await page.evaluate(() => document.querySelector('#service-modal .btn-icon').click());
    await wait();

    // Suite 4: Infrastructure & DNS Settings
    console.log('\nSUITE 4: Infrastructure & DNS');
    
    console.log('  Testing deSEC Form...');
    await page.type('#desec-domain-input', 'test.dedyn.io');
    await page.type('#desec-token-input', 'test-token');
    await page.evaluate(() => document.querySelector('form[onsubmit*="saveDesecConfig"] button').click());
    await wait();

    console.log('  Testing SSL Retry...');
    await page.waitForSelector('#ssl-retry-btn', { visible: true });
    await page.evaluate(() => document.getElementById('ssl-retry-btn').click());
    await wait();
    try {
        await page.waitForSelector('#dialog-modal', { visible: true, timeout: 3000 });
        await page.evaluate(() => document.getElementById('dialog-confirm-btn').click());
        await wait();
    } catch (e) { console.log('    (Retry dialog skip)'); }

    // Suite 5: Odido Booster
    console.log('\nSUITE 5: Odido Booster');
    
    console.log('  Testing Refresh Status...');
    await page.evaluate(() => document.querySelector('button[onclick="refreshOdidoRemaining()"]' ).click());
    await wait();

    console.log('  Testing Buy Bundle...');
    await page.evaluate(() => document.getElementById('odido-buy-btn').click());
    await wait();

    console.log('  Testing Odido Config...');
    await page.type('#odido-api-key', 'test-api-key');
    await page.evaluate(() => document.querySelector('form[onsubmit*="saveOdidoConfig"] button').click());
    await wait();

    console.log('  Testing VPN Routing Toggle...');
    await page.evaluate(() => document.getElementById('odido-vpn-switch').click());
    await wait();

    // Suite 6: VPN Management
    console.log('\nSUITE 6: VPN Management');
    
    console.log('  Testing Add Client Modal...');
    await page.evaluate(() => document.querySelector('button[onclick="openAddClientModal()"]' ).click());
    await page.waitForSelector('#add-client-modal', { visible: true });
    await page.type('#new-client-name', 'New Test Client');
    await page.evaluate(() => document.querySelector('#add-client-modal .btn-filled').click());
    await wait();

    console.log('  Testing Client List Actions...');
    await page.waitForSelector('#wg-client-list .btn-icon', { visible: true });
    await page.evaluate(() => document.querySelector('#wg-client-list .btn-icon').click()); // Open QR
    await wait();
    try {
        await page.waitForSelector('#client-qr-modal', { visible: true, timeout: 3000 });
        await page.evaluate(() => document.querySelector('#client-qr-modal .btn-icon').click()); // Close
        await wait();
    } catch (e) { console.log('    (QR Modal skip)'); }

    console.log('  Testing Profile Upload...');
    await page.type('#prof-name', 'Test Profile');
    await page.type('#prof-conf', '[Interface]\nPrivateKey = ABC\n[Peer]\nPublicKey = DEF');
    await page.evaluate(() => document.querySelector('button[onclick="uploadProfile()"]' ).click());
    await wait();
    try {
        await page.waitForSelector('#dialog-confirm-btn', { visible: true, timeout: 3000 });
        await page.evaluate(() => document.getElementById('dialog-confirm-btn').click());
        await wait();
    } catch (e) {}

    // Suite 7: Customization & System Info
    console.log('\nSUITE 7: Customization & System Info');
    
    console.log('  Enabling System Logs Category...');
    await page.evaluate(() => filterCategory('logs'));
    await wait();

    console.log('  Testing Theme Seed Color...');
    await page.evaluate(() => {
        const picker = document.getElementById('theme-seed-color');
        if (picker) {
            picker.value = '#FF0000';
            picker.dispatchEvent(new Event('change'));
        }
    });
    await wait();

    console.log('  Testing Manual Hex Color...');
    await page.type('#manual-color-input', '#00FF00');
    await page.evaluate(() => document.querySelector('button[onclick="addManualColor()"]' ).click());
    await wait();

    console.log('  Testing Update Strategy Change...');
    await page.select('#update-strategy-select', 'latest');
    await wait();

    console.log('  Testing Session Cleanup Toggle...');
    await page.evaluate(() => document.getElementById('session-cleanup-switch').click());
    await wait();

    console.log('  Testing Project Size Modal...');
    await page.waitForSelector('.clickable-stat', { visible: true });
    await page.evaluate(() => document.querySelector('.clickable-stat').click());
    await page.waitForSelector('#project-size-modal', { visible: true });
    await page.waitForSelector('#project-size-content', { visible: true });
    await wait();
    console.log('    Triggering Purge Images...');
    await page.evaluate(() => document.querySelector('#project-size-content .btn-filled').click());
    await wait();
    try {
        await page.waitForSelector('#dialog-confirm-btn', { visible: true, timeout: 3000 });
        await page.evaluate(() => document.getElementById('dialog-confirm-btn').click());
        await wait();
    } catch (e) {}
    await page.evaluate(() => document.querySelector('#project-size-modal .btn-icon').click());
    await wait();

    // Suite 8: System Logs
    console.log('\nSUITE 8: System Logs');
    console.log('  Testing Log Filters...');
    await page.waitForSelector('#log-filter-level', { visible: true });
    await page.select('#log-filter-level', 'ERROR');
    await wait();
    await page.select('#log-filter-cat', 'NETWORK');
    await wait();

    // Suite 9: Dangerous Actions
    console.log('\nSUITE 9: Dangerous Actions');
    
    console.log('  Testing Slot Switching...');
    await page.evaluate(() => document.querySelector('button[data-tooltip*="standby slot"]').click());
    await page.waitForSelector('#dialog-modal', { visible: true });
    await page.evaluate(() => document.getElementById('dialog-confirm-btn').click());
    await wait();
    console.log('  ✅ Slot switch triggered.');

    // We must re-login after each "destructive" (body wiping) action if we continue
    await page.goto(DASHBOARD_URL, { waitUntil: 'networkidle0' });
    await doLogin();

    console.log('  Testing Stack Restart...');
    await page.evaluate(() => document.querySelector('button[onclick="restartStack()"]' ).click());
    await page.waitForSelector('#dialog-modal', { visible: true });
    await page.evaluate(() => document.getElementById('dialog-confirm-btn').click());
    await wait();
    console.log('  ✅ Stack restart triggered.');

    await page.goto(DASHBOARD_URL, { waitUntil: 'networkidle0' });
    await doLogin();

    console.log('  Testing Uninstall System...');
    await page.evaluate(() => document.querySelector('button[onclick="uninstallStack()"]' ).click());
    await page.waitForSelector('#dialog-modal', { visible: true });
    await page.evaluate(() => document.getElementById('dialog-confirm-btn').click()); // First confirm
    await wait();
    await page.waitForSelector('#dialog-modal', { visible: true });
    await page.evaluate(() => document.getElementById('dialog-confirm-btn').click()); // Second confirm
    await wait();
    console.log('  ✅ Uninstall triggered.');

    console.log('\n--- ALL THOROUGH INTERACTION TESTS COMPLETED ---');

  } catch (error) {
    console.error('Test run failed:', error);
    process.exit(1);
  } finally {
    await browser.close();
  }
}

runThoroughTests();
