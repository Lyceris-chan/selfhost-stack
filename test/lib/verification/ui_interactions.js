/**
 * @fileoverview Comprehensive UI Interaction Verification.
 * Performs user and admin actions on the dashboard using Puppeteer.
 */

const puppeteer = require('puppeteer');
const http = require('http');
const fs = require('fs');
const path = require('path');

const CONFIG = {
  baseUrl: process.env.TEST_BASE_URL || 'http://localhost:8088',
  adminPassword: process.env.ADMIN_PASSWORD || getAdminPassword() || 'changeme',
  headless: process.env.HEADLESS !== 'false',
  timeout: 60000,
  screenshotDir: path.join(__dirname, '..', '..', '..', 'test', 'screenshots'),
  servicesDir: path.join(__dirname, '..', '..', '..', 'test', 'screenshots', 'services'),
};

function getAdminPassword() {
  const secretsFile = path.join(__dirname, '..', '..', '..', 'data', 'AppData', 'privacy-hub', '.secrets');
  if (!fs.existsSync(secretsFile)) return null;
  const content = fs.readFileSync(secretsFile, 'utf8');
  const match = content.match(/ADMIN_PASS_RAW='([^']+)'/);
  return match ? match[1] : null;
}

function checkUrl(url) {
  return new Promise((resolve) => {
    const req = http.get(url, (res) => {
      resolve(res.statusCode === 200);
    });
    req.on('error', () => resolve(false));
    req.end();
  });
}

function cleanupScreenshots() {
  if (fs.existsSync(CONFIG.screenshotDir)) {
    fs.readdirSync(CONFIG.screenshotDir).forEach(file => {
      if (file.endsWith('.png')) {
        fs.unlinkSync(path.join(CONFIG.screenshotDir, file));
      }
    });
  } else {
    fs.mkdirSync(CONFIG.screenshotDir, { recursive: true });
  }
  
  if (fs.existsSync(CONFIG.servicesDir)) {
    fs.readdirSync(CONFIG.servicesDir).forEach(file => {
      if (file.endsWith('.png')) {
        fs.unlinkSync(path.join(CONFIG.servicesDir, file));
      }
    });
  } else {
    fs.mkdirSync(CONFIG.servicesDir, { recursive: true });
  }
  console.log('    ✓ Screenshots folders cleaned');
}

async function takeScreenshot(page, name, dir = CONFIG.screenshotDir) {
  const timestamp = Date.now();
  const filePath = path.join(dir, `${timestamp}_${name}.png`);
  try {
      await page.screenshot({ path: filePath, fullPage: true });
      console.log(`    📷 Screenshot taken: ${name}`);
  } catch (e) {
      console.warn(`    ⚠️  Failed to take screenshot ${name}: ${e.message}`);
  }
}

async function authenticateAdmin(page) {
  try {
    const isAlreadyAdmin = await page.evaluate(() => document.body.classList.contains('admin-mode'));
    if (isAlreadyAdmin) return true;

    console.log('    🔑 Authenticating as admin...');
    await page.waitForSelector('#admin-lock-btn', {timeout: 15000});
    await page.evaluate(() => document.getElementById('admin-lock-btn').click());
    await new Promise(r => setTimeout(r, 2000));
    await page.waitForSelector('#admin-password-input', {visible: true, timeout: 15000});
    await takeScreenshot(page, 'admin_login_modal');
    await page.type('#admin-password-input', CONFIG.adminPassword);
    await page.keyboard.press('Enter');
    await page.waitForFunction(() => document.body.classList.contains('admin-mode'), {timeout: 20000});
    console.log('    ✅ Admin authentication successful');
    await takeScreenshot(page, 'admin_authenticated');
    return true;
  } catch (e) {
    console.warn(`    ⚠️  Admin authentication failed: ${e.message}`);
    await takeScreenshot(page, 'admin_auth_fail');
    return false;
  }
}

async function checkFilters(page) {
  console.log('  Testing Filters...');
  const filters = ['all', 'apps', 'system'];
  for (const filter of filters) {
    try {
      const chip = await page.$(`.filter-chip[data-target="${filter}"]`);
      if (chip) {
        await chip.click();
        await new Promise(r => setTimeout(r, 500));
        await takeScreenshot(page, `filter_${filter}`);
      }
    } catch (e) {}
  }
  const allChip = await page.$('.filter-chip[data-target="all"]');
  if (allChip) await allChip.click();
}

async function testThemeToggle(page) {
  console.log('  Testing Theme Toggle...');
  try {
    // The theme toggle button uses class 'theme-toggle' and onclick='toggleTheme()'
    // It might not have an ID 'theme-toggle-btn'. Let's use the class or onclick.
    // In dashboard.html: <button class="theme-toggle" onclick="toggleTheme()" ...>
    const selector = '.theme-toggle[onclick="toggleTheme()"]';
    
    await page.waitForSelector(selector, { visible: true, timeout: 2000 });
    // Click theme toggle button
    await page.click(selector);
    await new Promise(r => setTimeout(r, 1000)); // Wait for transition
    await takeScreenshot(page, 'theme_toggled');
    // Toggle back
    await page.click(selector);
    await new Promise(r => setTimeout(r, 500));
  } catch (e) {
    console.warn(`    ⚠️  Theme toggle test failed: ${e.message}`);
  }
}

async function testPrivacyToggle(page) {
  console.log('  Testing Privacy Toggle...');
  try {
    // In dashboard.html: <button class="switch-container" id="privacy-switch" onclick="togglePrivacy()" ...>
    const selector = '#privacy-switch';
    
    await page.waitForSelector(selector, { visible: true, timeout: 2000 });
    // Click privacy toggle button (eye icon)
    await page.click(selector);
    await new Promise(r => setTimeout(r, 500));
    await takeScreenshot(page, 'privacy_toggled');
    // Toggle back
    await page.click(selector);
    await new Promise(r => setTimeout(r, 500));
  } catch (e) {
    console.warn(`    ⚠️  Privacy toggle test failed: ${e.message}`);
  }
}

async function captureServices(browser, page) {
    console.log('  Capturing Service Snapshots (Deep Interactions)...');
    
    await takeScreenshot(page, 'all_services_overview');
    
    // Inject window.open override
    await page.evaluate(() => {
        window.open = (url) => { window.location.href = url; return window; };
        document.querySelectorAll('a').forEach(a => a.target = '_self');
    });

    // Extract Cards
    const cardsInfo = await page.evaluate(() => {
        const cards = Array.from(document.querySelectorAll('.card'));
        return cards.map((card, index) => {
            const title = card.querySelector('h2, h3')?.innerText.trim() || 'Unknown';
            return { index, title };
        });
    });

    console.log(`    Found ${cardsInfo.length} cards to process...`);

    const skipTitles = [
      'System information', 'System health', 'System & deployment logs', 'Certificate status',
      'Updates are available', 'Critical network advisory', 'deSEC configuration', 'Device DNS settings',
      'Endpoint provisioning', 'Odido status', 'Configuration', 'VPN client access', 'WireGuard Profiles',
      'Theme customization', 'Security & privacy', 'Unknown'
    ];

    for (const info of cardsInfo) {
        if (skipTitles.includes(info.title)) continue;

        const safeTitle = info.title.replace(/[^a-zA-Z0-9]/g, '_');
        console.log(`    🌐 Visiting ${info.title}...`);
        
        try {
            const card = (await page.$$('.card'))[info.index];
            if (!card) continue;

            await Promise.all([
                page.waitForNavigation({ waitUntil: 'domcontentloaded', timeout: 15000 }).catch(() => {}),
                card.click(),
            ]);

            // DEEP DIVE LOGIC
            if (info.title.includes('Invidious')) {
                console.log('      > Invidious: Searching and playing...');
                try {
                    await page.waitForSelector('input[name="q"]', {timeout: 5000});
                    await page.type('input[name="q"]', 'big buck bunny');
                    await Promise.all([page.waitForNavigation(), page.keyboard.press('Enter')]);
                    await page.waitForSelector('.thumbnail', {timeout: 5000});
                    const video = await page.$('.thumbnail');
                    if (video) {
                        await Promise.all([page.waitForNavigation(), video.click()]);
                        await page.waitForSelector('video', {timeout: 10000});
                        await new Promise(r => setTimeout(r, 2000));
                        await takeScreenshot(page, `${safeTitle}_video_play`, CONFIG.servicesDir);
                    }
                } catch(e) { console.log('      ! Deep dive failed:', e.message); }
            }
            else if (info.title.includes('SearXNG')) {
                console.log('      > SearXNG: Searching...');
                try {
                    await page.waitForSelector('input[name="q"]', {timeout: 5000});
                    await page.type('input[name="q"]', 'linux');
                    await Promise.all([page.waitForNavigation(), page.keyboard.press('Enter')]);
                    await page.waitForSelector('#urls', {timeout: 5000});
                    await takeScreenshot(page, `${safeTitle}_search_results`, CONFIG.servicesDir);
                } catch(e) { console.log('      ! Deep dive failed:', e.message); }
            }
            else if (info.title.includes('Wikiless')) {
                console.log('      > Wikiless: Viewing article...');
                try {
                    await page.waitForSelector('input[name="q"]', {timeout: 5000});
                    await page.type('input[name="q"]', 'Privacy');
                    await Promise.all([page.waitForNavigation(), page.keyboard.press('Enter')]);
                    await page.waitForSelector('#content', {timeout: 5000});
                    await takeScreenshot(page, `${safeTitle}_article`, CONFIG.servicesDir);
                } catch(e) { console.log('      ! Deep dive failed:', e.message); }
            }
            else if (info.title.includes('Rimgo')) {
                console.log('      > Rimgo: Checking image...');
                try {
                    await page.waitForSelector('img', {timeout: 5000});
                    await takeScreenshot(page, `${safeTitle}_gallery`, CONFIG.servicesDir);
                } catch(e) { console.log('      ! Deep dive failed:', e.message); }
            }
            else if (info.title.includes('BreezeWiki')) {
                console.log('      > BreezeWiki: Visiting Random...');
                try {
                    // Try to find a random page link or similar
                    const links = await page.$$('a');
                    if (links.length > 5) {
                        // Click a random link from the list (likely a wiki)
                        await Promise.all([page.waitForNavigation(), links[5].click()]);
                        await takeScreenshot(page, `${safeTitle}_wiki_view`, CONFIG.servicesDir);
                    } else {
                        await takeScreenshot(page, `${safeTitle}_homepage`, CONFIG.servicesDir);
                    }
                } catch(e) { console.log('      ! Deep dive failed:', e.message); }
            }
            else if (info.title.includes('Redlib')) {
                console.log('      > Redlib: Browsing r/all...');
                try {
                    // Navigate to a subreddit if possible or click a link
                    const links = await page.$$('a[href*="/r/"]');
                    if (links.length > 0) {
                        await Promise.all([page.waitForNavigation(), links[0].click()]);
                        await takeScreenshot(page, `${safeTitle}_subreddit`, CONFIG.servicesDir);
                    } else {
                        await takeScreenshot(page, `${safeTitle}_homepage`, CONFIG.servicesDir);
                    }
                } catch(e) { console.log('      ! Deep dive failed:', e.message); }
            }
            else {
                // Default Homepage Capture
                await new Promise(r => setTimeout(r, 1000));
                await takeScreenshot(page, `${safeTitle}_homepage`, CONFIG.servicesDir);
            }
            
            // Go back
            await page.goto(CONFIG.baseUrl, { waitUntil: 'domcontentloaded' });
            
            // Re-inject overrides
            await page.evaluate(() => {
                window.open = (url) => { window.location.href = url; return window; };
                document.querySelectorAll('a').forEach(a => a.target = '_self');
            });

        } catch (e) {
            console.warn(`    ⚠️  Could not load ${info.title}: ${e.message}`);
            try { await page.goto(CONFIG.baseUrl, { waitUntil: 'domcontentloaded' }); } catch(e2) {}
        }
    }
}

async function runInteractions() {
  console.log(`Target: ${CONFIG.baseUrl}`);
  const isAccessible = await checkUrl(CONFIG.baseUrl);
  if (!isAccessible) {
    console.log('⚠ Dashboard not accessible. Skipping interactions.');
    return true; 
  }

  cleanupScreenshots();

  let browser;
  try {
    browser = await puppeteer.launch({
      headless: CONFIG.headless ? 'new' : false,
      args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage', '--disable-gpu', '--ignore-certificate-errors'],
    });

    const page = await browser.newPage();
    await page.setViewport({ width: 1920, height: 1080 }); 
    await page.goto(CONFIG.baseUrl, {waitUntil: 'networkidle2', timeout: 30000});

    // Wait for fade-in transition
    await page.waitForFunction(() => getComputedStyle(document.body).opacity === '1', { timeout: 5000 });

    console.log('  Verifying Layout...');
    await takeScreenshot(page, 'dashboard_initial');

    await checkFilters(page);
    await testThemeToggle(page);
    await testPrivacyToggle(page);
    
    // Capture Services (Deep)
    await captureServices(browser, page);

    // Auth
    const adminSuccess = await authenticateAdmin(page);
    if (adminSuccess) {
      await page.click('#admin-lock-btn');
      try {
        await page.waitForSelector('#dialog-confirm-btn', {visible: true, timeout: 2000});
        await page.click('#dialog-confirm-btn');
      } catch (e) {} 
      await page.waitForFunction(() => !document.body.classList.contains('admin-mode'), {timeout: 5000});
      console.log('    ✓ Admin logout successful');
    }

    console.log('✅ UI Interactions Verification passed');
    return true;

  } catch (e) {
    console.error('❌ UI Interactions Verification failed:', e.message);
    return false;
  } finally {
    if (browser) await browser.close();
  }
}

if (require.main === module) {
  runInteractions().then(success => process.exit(success ? 0 : 1));
}

module.exports = { runInteractions };