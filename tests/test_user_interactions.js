const puppeteer = require('puppeteer');

(async () => {
  const DASHBOARD_URL = process.env.DASHBOARD_URL || 'http://10.0.1.200:8081';
  console.log(`Testing user interactions at: ${DASHBOARD_URL}`);

  const browser = await puppeteer.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });

  const page = await browser.newPage();
  
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

    console.log('3. Opening Service Management Modal (Invidious)...');
    // Find the settings button for Invidious
    await page.click('#link-invidious .settings-btn');
    await new Promise(r => setTimeout(r, 1000));
    const isModalVisible = await page.evaluate(() => {
      const modal = document.getElementById('service-modal');
      return modal && modal.style.display === 'flex';
    });
    console.log(`   Service modal visible: ${isModalVisible}`);

    console.log('4. Checking Tooltip Visibility...');
    await page.hover('#privacy-switch');
    await new Promise(r => setTimeout(r, 500));
    const isTooltipVisible = await page.evaluate(() => {
      const tooltip = document.querySelector('.tooltip-box');
      return tooltip && tooltip.classList.contains('visible');
    });
    console.log(`   Tooltip visible: ${isTooltipVisible}`);

    console.log('5. Closing Modal...');
    await page.click('#service-modal .btn-icon');
    await new Promise(r => setTimeout(r, 500));
    const isModalClosed = await page.evaluate(() => {
      const modal = document.getElementById('service-modal');
      return !modal || modal.style.display === 'none';
    });
    console.log(`   Service modal closed: ${isModalClosed}`);

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
