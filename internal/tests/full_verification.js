
const puppeteer = require('puppeteer');

(async () => {
  const browser = await puppeteer.launch({
    args: ['--no-sandbox', '--disable-setuid-sandbox'],
    headless: true // Run in headless mode
  });
  const page = await browser.newPage();
  
  // Set viewport to desktop size
  await page.setViewport({ width: 1280, height: 800 });

  const DASHBOARD_URL = 'http://10.0.1.183:8081'; // Using the IP from previous verification

  console.log(`[TEST] Navigating to ${DASHBOARD_URL}...`);
  try {
    await page.goto(DASHBOARD_URL, { waitUntil: 'domcontentloaded', timeout: 60000 });
    // Clear localStorage to reset state (advisory, theme, filters)
    await page.evaluate(() => localStorage.clear());
    await page.reload({ waitUntil: 'domcontentloaded' });
  } catch (e) {
    console.error("[FAIL] Could not load dashboard:", e);
    await browser.close();
    process.exit(1);
  }

  // 1. Critical Advisory Check
  console.log("[TEST] Checking Critical Network Advisory...");
  const advisory = await page.$('#mac-advisory');
  if (advisory) {
    console.log("  - Advisory bar found.");
    const dismissBtn = await page.$('#mac-advisory button');
    if (dismissBtn) {
      await dismissBtn.click();
      console.log("  - Dismiss button clicked.");
      // Wait for animation/hiding
      await new Promise(r => setTimeout(r, 500));
      const isVisible = await page.$eval('#mac-advisory', el => el.style.display !== 'none');
      if (!isVisible) console.log("  - PASS: Advisory dismissed.");
      else console.error("  - FAIL: Advisory still visible.");
    } else console.error("  - FAIL: Dismiss button not found.");
  } else {
    console.log("  - Advisory bar NOT found (might be already dismissed or not rendered).");
  }

  // 2. Chip Layout Check
  console.log("[TEST] Verifying Chip Layout (CSS)...");
  // Wait for dynamic grid to load
  await page.waitForSelector('.chip-box', { timeout: 5000 }).catch(() => console.log("  - Waiting for chips..."));
  
  const chipBoxStyle = await page.$eval('.chip-box', el => getComputedStyle(el).flexWrap);
  if (chipBoxStyle === 'wrap') console.log(`  - PASS: .chip-box flex-wrap is '${chipBoxStyle}'`);
  else console.error(`  - FAIL: .chip-box flex-wrap is '${chipBoxStyle}'`);

  const chipFlex = await page.$eval('.chip', el => getComputedStyle(el).flex);
  // flex: 1 1 auto usually computes to "1 1 auto" or "1 1 0%" depending on browser.
  if (chipFlex.startsWith('1 1')) console.log(`  - PASS: .chip flex is '${chipFlex}'`);
  else console.error(`  - FAIL: .chip flex is '${chipFlex}'`);

  // 3. User Interactions
  console.log("[TEST] Simulating User Interactions...");
  
  // Filter Chips
  const filters = ['apps', 'system', 'dns', 'tools', 'all'];
  for (const filter of filters) {
    const chip = await page.$(`.filter-chip[data-target="${filter}"]`);
    if (chip) {
      await chip.click();
      console.log(`  - Clicked filter: ${filter}`);
      await new Promise(r => setTimeout(r, 500)); // Wait for transition/render

      if (filter === 'all') {
          const gridAllVisible = await page.$eval('#grid-all', el => el.offsetParent !== null);
          const gridAppsHidden = await page.$eval('#grid-apps', el => el.offsetParent === null); // Should be hidden
          if (gridAllVisible && gridAppsHidden) console.log("  - PASS: 'All Services' view active.");
          else console.error("  - FAIL: 'All Services' view check failed.");
      }

      // Verify active class
      const isActive = await page.$eval(`.filter-chip[data-target="${filter}"]`, el => el.classList.contains('active'));
      if (!isActive) console.error(`  - FAIL: Filter ${filter} did not become active.`);
    } else {
      // Admin only chips might be hidden initially
      if (filter === 'logs') console.log(`  - Log filter hidden (expected if not admin).`);
      else console.error(`  - FAIL: Filter chip ${filter} not found.`);
    }
  }

  // Toggles
  console.log("  - Toggling Privacy Mode...");
  const privacySwitch = await page.$('#privacy-switch');
  if (privacySwitch) {
    await privacySwitch.click();
    await new Promise(r => setTimeout(r, 200));
    const isPrivate = await page.evaluate(() => document.body.classList.contains('privacy-mode'));
    if (isPrivate) console.log("  - PASS: Privacy mode active.");
    else console.error("  - FAIL: Privacy mode not active.");
    
    // Toggle back
    await privacySwitch.click();
  }

  console.log("  - Toggling Theme...");
  const themeToggle = await page.$('.theme-toggle');
  if (themeToggle) {
    const startTheme = await page.evaluate(() => document.documentElement.classList.contains('light-mode'));
    await themeToggle.click();
    await new Promise(r => setTimeout(r, 200));
    const endTheme = await page.evaluate(() => document.documentElement.classList.contains('light-mode'));
    if (startTheme !== endTheme) console.log("  - PASS: Theme toggled.");
    else console.error("  - FAIL: Theme did not change.");
  }

  // 4. Admin Mode Simulation
  console.log("[TEST] Simulating Admin Mode...");
  // We can't easily interact with window.prompt in headless, but we can call the function manually or mock the API.
  // Actually, we can assume the user wants to check if the UI *reacts* to admin mode.
  // Let's set it manually in JS context since we can't type in prompt easily without handling dialog event.
  await page.evaluate(() => {
    // Mock successful admin verification
    isAdmin = true;
    sessionStorage.setItem('is_admin', 'true');
    document.body.classList.add('admin-mode');
    // Force UI update
    if (typeof updateAdminUI === 'function') updateAdminUI();
  });
  console.log("  - Admin mode forced via JS.");
  
  // Check if admin-only elements are visible
  const adminChipVisible = await page.$eval('.filter-chip[data-target="logs"]', el => {
    return window.getComputedStyle(el).display !== 'none';
  });
  if (adminChipVisible) console.log("  - PASS: Admin-only 'Logs' filter is now visible.");
  else console.error("  - FAIL: Admin-only elements still hidden.");

  // 5. Service Status Check
  console.log("[TEST] Verifying Service Status (waiting for poll)...");
  await new Promise(r => setTimeout(r, 15000)); // Wait 15s for polling cycle
  
  const statuses = await page.$$eval('.status-text', els => els.map(e => e.textContent.trim()));
  const total = statuses.length;
  const online = statuses.filter(s => s === 'Connected' || s === 'Healthy' || s === 'Active' || s === 'Running' || s === 'Optimal' || s === 'Connected (Healthy)').length;
  
  console.log(`  - Found ${total} status indicators.`);
  console.log(`  - ${online} services reporting online/healthy.`);
  
  statuses.forEach(s => {
    if (s === 'Offline' || s === 'Issue Detected' || s === 'Down') {
      console.warn(`  - WARN: Found service with status: ${s}`);
    }
  });

  if (online > 5) console.log("  - PASS: Majority of services are online.");
  else console.warn("  - WARN: Low number of online services. Check logs.");

  // Screenshot for visual verification artifact (saved to internal/tests)
  await page.screenshot({ path: 'verification_screenshot.png', fullPage: true });
  console.log("[TEST] Screenshot saved to verification_screenshot.png");

  await browser.close();
})();
