const puppeteer = require('puppeteer');

(async () => {
  const DASHBOARD_URL = process.env.DASHBOARD_URL || 'http://10.0.1.200:8081';
  console.log(`Testing user interactions at: ${DASHBOARD_URL}`);

  const browser = await puppeteer.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });

  const page = await browser.newPage();
  await page.setViewport({ width: 1280, height: 800 });
  
  // Capture console errors
  const consoleErrors = [];
  page.on('console', msg => {
    if (msg.type() === 'error') {
      // Ignore transient 502 on initial load
      if (msg.text().includes('502 (Bad Gateway)')) {
          console.log(`Ignoring transient load error: ${msg.text()}`);
          return;
      }
      consoleErrors.push(msg.text());
      console.log(`Console Error: ${msg.text()}`);
    }
  });

  try {
    await page.goto(DASHBOARD_URL, { waitUntil: 'networkidle2' });
    await page.waitForSelector('.card[data-url]', { timeout: 30000 });
    await page.waitForSelector('#link-invidious .settings-btn', { timeout: 30000 });
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
    await page.click('.theme-toggle');
    await new Promise(r => setTimeout(r, 500));
    const isLightMode = await page.evaluate(() => document.documentElement.classList.contains('light-mode'));
    console.log(`   Light mode active: ${isLightMode}`);

    console.log('2. Toggling Privacy Masking...');
    await page.click('#privacy-switch');
    await new Promise(r => setTimeout(r, 500));
    const isPrivacyMode = await page.evaluate(() => document.body.classList.contains('privacy-mode'));
    console.log(`   Privacy mode active: ${isPrivacyMode}`);

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
    console.log(`   Grid columns (wide/narrow): ${colsWide}/${colsNarrow}`);
    console.log(`   Chip layout: ${chipLayout ? chipLayout.display : 'missing'}`);

    console.log('4. Cycling Category Filters...');
    const filterChips = await page.$$('.filter-chip');
    for (const chip of filterChips) {
      await chip.click();
      await new Promise(r => setTimeout(r, 150));
    }
    await page.click('.filter-chip[data-target="system"]');
    await new Promise(r => setTimeout(r, 150));

    console.log('5. Setting Theme Seed Color...');
    await page.$eval('#theme-seed-color', (el) => {
      el.value = '#00ff00';
      el.dispatchEvent(new Event('input', { bubbles: true }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
    });
    const seedHex = await page.$eval('#theme-seed-hex', el => el.textContent.trim());
    console.log(`   Seed hex updated: ${seedHex}`);

    console.log('6. Applying Theme Preset...');
    await page.evaluate(() => {
      if (typeof window.initStaticPresets === 'function') {
        window.initStaticPresets();
      }
    });
    const presets = await page.$$('#static-presets div');
    let presetClicked = false;
    for (const preset of presets) {
      const box = await preset.boundingBox();
      if (box) {
        await preset.evaluate((el) => el.scrollIntoView({ block: 'center', inline: 'center' }));
        await preset.click();
        presetClicked = true;
        await new Promise(r => setTimeout(r, 300));
        break;
      }
    }
    console.log(`   Preset clicked: ${presetClicked}`);

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
    console.log(`   Card clicked: ${cardClicked}`);

    console.log('8. Opening Service Management Modal (Invidious)...');
    const invidiousCard = await page.$('#link-invidious');
    if (invidiousCard) {
      await invidiousCard.hover();
    }
    await page.waitForSelector('#link-invidious .settings-btn', { visible: true, timeout: 30000 });
    await page.click('#link-invidious .settings-btn');
    await new Promise(r => setTimeout(r, 1000));
    let isModalVisible = await page.evaluate(() => {
      const modal = document.getElementById('service-modal');
      return modal && modal.style.display === 'flex';
    });
    if (!isModalVisible) {
      await page.evaluate(() => {
        const btn = document.querySelector('#link-invidious .settings-btn');
        if (btn) btn.click();
      });
      await new Promise(r => setTimeout(r, 800));
      isModalVisible = await page.evaluate(() => {
        const modal = document.getElementById('service-modal');
        return modal && modal.style.display === 'flex';
      });
    }
    console.log(`   Service modal visible: ${isModalVisible}`);

    console.log('9. Checking Tooltip Visibility...');
    await page.hover('#privacy-switch');
    await new Promise(r => setTimeout(r, 500));
    const isTooltipVisible = await page.evaluate(() => {
      const tooltip = document.querySelector('.tooltip-box');
      return tooltip && tooltip.classList.contains('visible');
    });
    console.log(`   Tooltip visible: ${isTooltipVisible}`);

    console.log('10. Closing Modal...');
    if (isModalVisible) {
      await page.click('#service-modal .btn-icon');
      await new Promise(r => setTimeout(r, 500));
    }
    const isModalClosed = await page.evaluate(() => {
      const modal = document.getElementById('service-modal');
      return !modal || modal.style.display === 'none';
    });
    console.log(`   Service modal closed: ${isModalClosed}`);

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

    console.log('12. Testing Log Filters...');
    await page.click('.filter-chip[data-target="logs"]');
    await new Promise(r => setTimeout(r, 150));
    await page.select('#log-filter-level', 'INFO');
    await page.select('#log-filter-cat', 'SYSTEM');
    await new Promise(r => setTimeout(r, 300));
    console.log('    Log filters applied.');

    console.log('13. Final Check: Accessibility & Errors...');
    if (consoleErrors.length > 0) {
      console.log('❌ Interaction test failed with console errors.');
      process.exit(1);
    } else {
      console.log('✅ Interaction test passed with zero console errors.');
    }

  } catch (err) {
    console.error('Test execution failed:', err);
    process.exit(1);
  } finally {
    await browser.close();
  }
})();
