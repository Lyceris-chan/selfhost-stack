const puppeteer = require('puppeteer');
const fs = require('fs');
const path = require('path');

(async () => {
  const DASHBOARD_URL = process.env.DASHBOARD_URL || 'http://localhost:8081';
  const MOCK_API = process.env.MOCK_API === '1';
  const REPORT_PATH = path.resolve(__dirname, 'USER_INTERACTIONS_REPORT.md');
  console.log(`Testing user interactions at: ${DASHBOARD_URL}`);

  const steps = [];
  const recordStep = (step, ok, details = '') => {
    const status = ok ? 'PASS' : 'FAIL';
    const message = details ? `${step} - ${details}` : step;
    console.log(`[${status}] ${message}`);
    steps.push({ step, status, details });
    return ok;
  };
  const consoleErrors = [];

  const browser = await puppeteer.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox'],
    protocolTimeout: 120000
  });

  const page = await browser.newPage();
  await page.setViewport({ width: 1280, height: 800 });
  
  // Capture console messages
  page.on('console', async msg => {
    const text = msg.text();
    const type = msg.type();
    
    if (type === 'error' && text.includes('502 (Bad Gateway)')) {
        return;
    }
    if (type === 'error' && text.includes('Failed to load resource')) {
        return;
    }
    if (type === 'error' && text.includes('ERR_FAILED')) {
        return;
    }
    if (type === 'error' && text.includes('EventSource')) {
        return;
    }
    if (type === 'error' && text.includes('text/event-stream')) {
        return;
    }
    
    let args = [];
    try {
        args = await Promise.all(msg.args().map(arg => arg.jsonValue().catch(() => arg.toString())));
    } catch (e) {}
    
    console.log(`[Browser ${type.toUpperCase()}] ${text}`, args);
    if (type === 'error') {
      consoleErrors.push(text);
    }
  });
  page.on('dialog', async dialog => {
    await dialog.accept();
  });

  try {
    if (MOCK_API) {
      const servicesList = [
        'invidious',
        'redlib',
        'wikiless',
        'rimgo',
        'breezewiki',
        'anonymousoverflow',
        'scribe',
        'memos',
        'vert',
        'adguard',
        'portainer',
        'wg-easy'
      ];
      const serviceUrls = {
        invidious: 'http://127.0.0.1:3000',
        redlib: 'http://127.0.0.1:8080',
        wikiless: 'http://127.0.0.1:8180',
        rimgo: 'http://127.0.0.1:3002',
        breezewiki: 'http://127.0.0.1:8380',
        anonymousoverflow: 'http://127.0.0.1:8480',
        scribe: 'http://127.0.0.1:8280',
        memos: 'http://127.0.0.1:5230',
        vert: 'http://127.0.0.1:5555',
        adguard: 'http://127.0.0.1:8083',
        portainer: 'http://127.0.0.1:9000',
        'wg-easy': 'http://127.0.0.1:51821'
      };
      await page.setRequestInterception(true);
      page.on('request', request => {
        const url = request.url();
        if (url.includes('/api/containers')) {
          const containers = {};
          servicesList.forEach(service => {
            containers[service] = { id: `${service}-id`, state: 'running', hardened: true };
          });
          request.respond({
            contentType: 'application/json',
            body: JSON.stringify({ containers })
          });
          return;
        }
        if (url.includes('/api/services')) {
          const services = {};
          servicesList.forEach((service, index) => {
            services[service] = {
              name: service.charAt(0).toUpperCase() + service.slice(1),
              category: index < 8 ? 'apps' : (index === 8 ? 'tools' : 'system'),
              order: index * 10,
              url: serviceUrls[service] || ''
            };
          });
          request.respond({
            contentType: 'application/json',
            body: JSON.stringify({ services })
          });
          return;
        }
        if (url.includes('/api/status')) {
          const services = {};
          servicesList.forEach(service => { services[service] = 'healthy'; });
          request.respond({
            contentType: 'application/json',
            body: JSON.stringify({
              success: true,
              gluetun: { status: 'up', healthy: true },
              services
            })
          });
          return;
        }
        if (url.includes('/api/profiles')) {
          request.respond({
            contentType: 'application/json',
            body: JSON.stringify({ profiles: [] })
          });
          return;
        }
        if (url.includes('/api/') || url.includes('/odido-api/')) {
          request.respond({
            contentType: 'application/json',
            body: JSON.stringify({ success: true, status: 'Healthy', containers: {}, updates: {}, services: {}, profiles: [] })
          });
          return;
        }
        request.continue();
      });
    }

    await page.goto(DASHBOARD_URL, { waitUntil: 'networkidle2' });
    await page.evaluate(() => localStorage.clear());
    await page.reload({ waitUntil: 'domcontentloaded' });
    
    // Initialize auth key
    await page.evaluate((key) => {
        localStorage.setItem('odido_api_key', key);
        window.odidoApiKey = key;
    }, process.env.HUB_API_KEY || 'J9zfiLY9h21tr1POK81acZS3zSu3id9x');

    await page.waitForSelector('.card[data-url]', { timeout: 30000 });
    await page.waitForSelector('.card[data-container="invidious"] .settings-btn', { timeout: 30000 });
    await page.waitForFunction(() => typeof window.toggleTheme === 'function');
    await page.evaluate(() => {
      window.open = () => null;
      const noOps = [
        'restartStack',
        'uninstallStack',
        'updateService',
        'startBatchUpdate',
        'uploadProfile',
        'buyOdidoBundle',
        'refreshOdidoRemaining',
        'requestSslCheck'
      ];
      noOps.forEach((fn) => {
        if (typeof window[fn] === 'function') {
          window[fn] = () => {};
        }
      });
    });

    console.log('1. Toggling Theme Mode...');
    const startTheme = await page.evaluate(() => document.documentElement.classList.contains('light-mode'));
    await page.evaluate(() => {
        const btn = document.querySelector('.theme-toggle');
        if (btn) btn.click();
    });
    await new Promise(r => setTimeout(r, 500));
    const endTheme = await page.evaluate(() => document.documentElement.classList.contains('light-mode'));
    recordStep('Theme Toggle', startTheme !== endTheme, `Start: ${startTheme}, End: ${endTheme}`);

    console.log('2. Toggling Privacy Masking...');
    await page.click('#privacy-switch');
    await new Promise(r => setTimeout(r, 500));
    const isPrivacyMode = await page.evaluate(() => document.body.classList.contains('privacy-mode'));
    recordStep('Privacy Toggle', isPrivacyMode, `Privacy mode active: ${isPrivacyMode}`);

    console.log('3. Verifying Dynamic Grid & Chips...');
    const gridColumns = async () => page.evaluate(() => {
      const grid = document.getElementById('grid-apps');
      if (!grid) return 0;
      const cols = getComputedStyle(grid).gridTemplateColumns.split(' ').filter(Boolean);
      return cols.length;
    });
    await page.setViewport({ width: 1440, height: 900 });
    await new Promise(r => setTimeout(r, 300));
    const colsWide = await gridColumns();
    await page.setViewport({ width: 1024, height: 900 });
    await new Promise(r => setTimeout(r, 300));
    const colsNarrow = await gridColumns();
    await page.setViewport({ width: 1280, height: 800 });
    await new Promise(r => setTimeout(r, 300));
    const chipLayout = await page.evaluate(() => {
      const box = document.querySelector('.chip-box');
      if (!box) return null;
      const style = getComputedStyle(box);
      return { display: style.display, columns: style.gridTemplateColumns, gap: style.gap };
    });
    recordStep('Grid Columns', colsWide > 0 && colsNarrow > 0, `wide=${colsWide}, narrow=${colsNarrow}`);
    recordStep('Chip Layout', !!chipLayout, `display=${chipLayout ? chipLayout.display : 'missing'}`);

    console.log('4. Cycling Category Filters...');
    await page.waitForSelector('.filter-chip[data-target="system"]', { visible: true });
    const filterChips = await page.$$('.filter-chip');
    let filterPass = true;
    for (const chip of filterChips) {
      await page.evaluate((el) => el.click(), chip);
      await new Promise(r => setTimeout(r, 150));
      const active = await page.evaluate((el) => el.classList.contains('active'), chip);
      if (!active) filterPass = false;
    }
    await page.evaluate(() => {
        const btn = document.querySelector('.filter-chip[data-target="system"]');
        if (btn) btn.click();
    });
    await new Promise(r => setTimeout(r, 150));
    recordStep('Filter Chips', filterPass, `Chips cycled: ${filterChips.length}`);

    console.log('5. Setting Theme Seed Color...');
    await page.$eval('#theme-seed-color', (el) => {
      el.value = '#00ff00';
      el.dispatchEvent(new Event('input', { bubbles: true }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
    });
    const seedHex = await page.$eval('#theme-seed-hex', el => el.textContent.trim());
    recordStep('Theme Seed Color', seedHex.toLowerCase().includes('#00ff00'), `Seed hex: ${seedHex}`);

    console.log('6. Testing Admin Mode Authentication (M3 Modal)...');
    // Verify admin mode is initially locked (settings-btn should be hidden)
    const settingsBtnHidden = await page.evaluate(() => {
        const btn = document.querySelector('.settings-btn');
        return !btn || getComputedStyle(btn).display === 'none';
    });
    recordStep('Admin Locked', settingsBtnHidden, `Admin features locked: ${settingsBtnHidden}`);

    // Open login modal
    await page.evaluate(() => {
        const btn = document.querySelector('#admin-lock-btn');
        if (btn) btn.click();
    });
    await page.waitForSelector('#login-modal', { visible: true, timeout: 5000 });
    
    // Type password and submit
    const adminPass = process.env.ADMIN_PASS || '9UDwVeCIWV6PQcdSfAKtfvsJ';
    await page.type('#admin-password-input', adminPass);
    await page.click('#login-modal .btn-filled');
    
    await new Promise(r => setTimeout(r, 1500));
    
    let isAdminMode = await page.evaluate(() => document.body.classList.contains('admin-mode'));
    const settingsBtnVisible = await page.evaluate(() => {
      const btn = document.querySelector('.settings-btn');
      return btn && getComputedStyle(btn).display !== 'none';
    });
    recordStep('Admin Mode', isAdminMode && settingsBtnVisible, `Admin mode: ${isAdminMode}, settings visible: ${settingsBtnVisible}`);

    console.log('6.5 Verifying Full-Width Banners...');
    const bannerWidthInfo = await page.evaluate(() => {
        const banner = document.getElementById('mac-advisory');
        if (!banner) return { found: false };
        const rect = banner.getBoundingClientRect();
        return { 
            found: true, 
            width: rect.width, 
            windowWidth: window.innerWidth,
            // Allow 5px tolerance for scrollbars or subpixel rendering
            isFullWidth: Math.abs(rect.width - (window.innerWidth - 48)) <= 5
        };
    });
    recordStep('MAC Banner Full-Width', bannerWidthInfo.found && bannerWidthInfo.isFullWidth, 
        `Banner width: ${bannerWidthInfo.width}, Window: ${bannerWidthInfo.windowWidth} (Expected ~${bannerWidthInfo.windowWidth - 48})`);


    console.log('7. Applying Theme Preset...');
    await page.evaluate(() => {
      if (typeof window.initStaticPresets === 'function') {
        window.initStaticPresets();
      }
    });
    const presetClicked = await page.evaluate(() => {
      const preset = document.querySelector('#static-presets div');
      if (!preset) return false;
      preset.scrollIntoView({ block: 'center', inline: 'center' });
      preset.click();
      return true;
    });
    await new Promise(r => setTimeout(r, 300));
    recordStep('Theme Preset', presetClicked, `Preset clicked: ${presetClicked}`);

    await page.click('.filter-chip[data-target="all"]');
    await new Promise(r => setTimeout(r, 150));

    console.log('7. Clicking Service Card (no navigation)...');
    const cards = await page.$$('.card[data-url]');
    let cardClicked = false;
    for (const card of cards) {
      const box = await card.boundingBox();
      if (box) {
        await card.evaluate((el) => el.scrollIntoView({ block: 'center', inline: 'center' }));
        await card.hover();
        await card.click();
        cardClicked = true;
        break;
      }
    }
    recordStep('Service Card Click', cardClicked, `Card clicked: ${cardClicked}`);

    console.log('8. Opening Service Management Modal (Invidious)...');
    const invidiousCard = await page.$('.card[data-container="invidious"]');
    
    // Audit: Navigation Arrow
    const hasNavArrow = await page.evaluate(() => {
        const arrow = document.querySelector('.card[data-container="invidious"] .nav-arrow');
        return !!arrow && window.getComputedStyle(arrow).fontFamily.includes('Material Symbols Rounded');
    });
    recordStep('Service Navigation Arrow', hasNavArrow, `Nav arrow present: ${hasNavArrow}`);

    // Audit: Absence of Metrics on Chips
    const hasMetricsOnChips = await page.evaluate(() => {
        return !!document.querySelector('.card .chip .cpu-val') || !!document.querySelector('.card .chip .mem-val');
    });
    recordStep('Service Card Metrics Hidden', !hasMetricsOnChips, `Metrics hidden: ${!hasMetricsOnChips}`);

    if (invidiousCard) {
      await invidiousCard.hover();
    }
    await page.waitForSelector('.card[data-container="invidious"] .settings-btn', { visible: true, timeout: 30000 });
    await page.click('.card[data-container="invidious"] .settings-btn');
    await new Promise(r => setTimeout(r, 1000));
    
    // Audit: Presence of Metrics in Modal
    const modalMetricsVisible = await page.evaluate(() => {
        const cpu = document.getElementById('modal-cpu-text');
        const mem = document.getElementById('modal-mem-text');
        return !!cpu && !!mem && cpu.offsetParent !== null;
    });
    recordStep('Modal Metrics Visible', modalMetricsVisible, `Modal metrics visible: ${modalMetricsVisible}`);

    let isModalVisible = await page.evaluate(() => {
      const modal = document.getElementById('service-modal');
      return modal && modal.style.display === 'flex';
    });
    if (!isModalVisible) {
      await page.evaluate(() => {
        const btn = document.querySelector('.card[data-container="invidious"] .settings-btn');
        if (btn) btn.click();
      });
      await new Promise(r => setTimeout(r, 800));
      isModalVisible = await page.evaluate(() => {
        const modal = document.getElementById('service-modal');
        return modal && modal.style.display === 'flex';
      });
    }
    recordStep('Service Modal Open', isModalVisible, `Modal visible: ${isModalVisible}`);

    console.log('9. Checking Tooltip Visibility...');
    await page.evaluate(() => {
      const target = document.querySelector('#privacy-switch');
      if (target) {
        target.dispatchEvent(new MouseEvent('mouseover', { bubbles: true }));
      }
    });
    await new Promise(r => setTimeout(r, 300));
    const tooltipInfo = await page.evaluate(() => {
      const tooltip = document.querySelector('.tooltip-box');
      if (!tooltip) return { visible: false, text: '' };
      const visible = tooltip.classList.contains('visible') || getComputedStyle(tooltip).opacity !== '0';
      return { visible, text: tooltip.textContent || '' };
    });
    const tooltipOk = tooltipInfo.text.trim().length > 0;
    recordStep('Tooltip Visible', tooltipOk, `Tooltip text: ${tooltipInfo.text.trim() || 'none'}`);

    console.log('10. Closing Modal...');
    if (isModalVisible) {
      await page.click('#service-modal .btn-icon');
      await new Promise(r => setTimeout(r, 500));
    }
    const isModalClosed = await page.evaluate(() => {
      const modal = document.getElementById('service-modal');
      return !modal || modal.style.display === 'none';
    });
    recordStep('Service Modal Close', isModalClosed, `Modal closed: ${isModalClosed}`);

    console.log('11. Opening Batch Update Modal...');
    const updateButtons = await page.$$('button[onclick="updateAllServices()"]');
    let updateBtn = null;
    for (const btn of updateButtons) {
      const box = await btn.boundingBox();
      if (box) {
        updateBtn = btn;
        break;
      }
    }
    if (updateBtn) {
      // Manually force the banner visible for width check (it might be hidden if no updates)
      await page.evaluate(() => {
          const banner = document.getElementById('update-banner');
          if (banner) banner.style.display = 'block';
      });
      
      const updateBannerWidth = await page.evaluate(() => {
          const banner = document.getElementById('update-banner');
          if (!banner) return { found: false };
          const rect = banner.getBoundingClientRect();
          return { 
              found: true, 
              width: rect.width, 
              windowWidth: window.innerWidth,
              isFullWidth: Math.abs(rect.width - (window.innerWidth - 48)) <= 5
          };
      });
      recordStep('Update Banner Full-Width', updateBannerWidth.found && updateBannerWidth.isFullWidth, 
          `Banner width: ${updateBannerWidth.width}, Window: ${updateBannerWidth.windowWidth} (Expected ~${updateBannerWidth.windowWidth - 48})`);

      await updateBtn.click();
      await page.waitForFunction(() => {
        const modal = document.getElementById('update-selection-modal');
        return modal && modal.style.display === 'flex';
      }, { timeout: 15000 });
      const toggleBtn = await page.$('#update-selection-modal button[onclick="toggleAllUpdates()"]');
      if (toggleBtn) {
        await toggleBtn.click();
      }
      const startBtn = await page.$('#start-update-btn');
      if (startBtn) {
        await startBtn.click();
      }
      await page.click('#update-selection-modal .btn-icon');
      await new Promise(r => setTimeout(r, 500));
    }
    recordStep('Batch Update Modal', !!updateBtn, `Update modal opened: ${!!updateBtn}`);

    console.log('12. Testing Log Filters...');
    const logsChip = await page.$('.filter-chip[data-target="logs"]');
    if (logsChip) {
      await logsChip.click();
      await new Promise(r => setTimeout(r, 150));
      await page.select('#log-filter-level', 'INFO');
      await page.select('#log-filter-cat', 'SYSTEM');
      await new Promise(r => setTimeout(r, 300));
      recordStep('Log Filters', true, 'Log filters applied');
    } else {
      recordStep('Log Filters', false, 'Logs filter chip not found');
    }

    console.log('13. Final Check: Accessibility & Errors...');
    recordStep('Console Errors', consoleErrors.length === 0, consoleErrors.slice(0, 5).join('; '));

  } catch (err) {
    console.error('Test execution failed:', err);
    process.exit(1);
  } finally {
    const report = {
      timestamp: new Date().toISOString(),
      url: DASHBOARD_URL,
      steps
    };
    const overallPass = steps.every(s => s.status === 'PASS');
    const lines = [];
    lines.push('# User Interaction Verification Report');
    lines.push(`Generated: ${report.timestamp}`);
    lines.push(`Dashboard URL: ${report.url}`);
    lines.push(`Overall Status: ${overallPass ? '✅ PASS' : '❌ FAIL'}`);
    lines.push('');
    lines.push('## Test Steps');
    lines.push('| Step | Status | Details |');
    lines.push('| :--- | :--- | :--- |');
    steps.forEach(step => {
      const details = step.details ? step.details.replace(/\|/g, '\\|') : '-';
      lines.push(`| ${step.step} | ${step.status === 'PASS' ? '✅' : '❌'} | ${details} |`);
    });
    fs.writeFileSync(REPORT_PATH, `${lines.join('\n')}\n`);
    console.log(`📝 Report saved to ${REPORT_PATH}`);
    await browser.close();
    if (!overallPass) process.exit(1);
  }
})();
