/**
 * @fileoverview Functional Verification Tests.
 * Performs deep functional checks on services (Search, Video, etc.) and VPN management.
 */

const puppeteer = require('puppeteer');
const fs = require('fs');
const path = require('path');

const CONFIG = {
  baseUrl: process.env.TEST_BASE_URL || 'http://localhost:8088',
  adminPassword: process.env.ADMIN_PASSWORD || 'changeme',
  headless: process.env.HEADLESS !== 'false',
  timeout: 60000,
  screenshotDir: path.join(__dirname, '..', '..', '..', 'test', 'screenshots', 'functional'),
};

if (!fs.existsSync(CONFIG.screenshotDir)) {
  fs.mkdirSync(CONFIG.screenshotDir, { recursive: true });
}

async function takeScreenshot(page, name) {
  const filePath = path.join(CONFIG.screenshotDir, `${name}.png`);
  try {
    await page.screenshot({ path: filePath, fullPage: true });
    console.log(`    📷 Saved: ${name}`);
  } catch (e) {
    console.warn(`    ⚠️ Failed screenshot: ${e.message}`);
  }
}

async function getServiceLink(page, titlePattern) {
  // Extract link from dashboard card (using flexible selector strategy)
  const href = await page.evaluate((pattern) => {
    const cards = Array.from(document.querySelectorAll('.card'));
    for (const card of cards) {
      const title = card.querySelector('h2, h3')?.innerText || '';
      if (title.toLowerCase().includes(pattern.toLowerCase())) {
        const link = card.tagName === 'A' ? card : card.querySelector('a');
        return link ? link.href : null;
      }
    }
    return null;
  }, titlePattern);
  return href;
}

async function testSearXNG(browser, dashboardPage) {
  console.log('  🔍 Testing SearXNG...');
  const url = await getServiceLink(dashboardPage, 'SearXNG');
  if (!url) { console.log('    ⚠️ SearXNG link not found'); return; }

  const page = await browser.newPage();
  try {
    await page.goto(url, { waitUntil: 'domcontentloaded' });
    // Input query
    await page.waitForSelector('input[name="q"]', { timeout: 5000 });
    await page.type('input[name="q"]', 'test query');
    await page.keyboard.press('Enter');
    await page.waitForSelector('#urls', { timeout: 10000 }); // Results container
    console.log('    ✓ SearXNG search successful');
    await takeScreenshot(page, 'searxng_results');
  } catch (e) {
    console.log(`    ❌ SearXNG failed: ${e.message}`);
    await takeScreenshot(page, 'searxng_fail');
  } finally { await page.close(); }
}

async function testInvidious(browser, dashboardPage) {
  console.log('  📺 Testing Invidious...');
  const url = await getServiceLink(dashboardPage, 'Invidious');
  if (!url) { console.log('    ⚠️ Invidious link not found'); return; }

  const page = await browser.newPage();
  try {
    // Navigate directly to Big Buck Bunny or a known test video if possible, 
    // or search for it.
    await page.goto(url, { waitUntil: 'domcontentloaded' });
    await page.waitForSelector('input[name="q"]', { timeout: 5000 });
    await page.type('input[name="q"]', 'big buck bunny');
    await page.keyboard.press('Enter');
    
    // Wait for results
    await page.waitForSelector('.thumbnail', { timeout: 10000 });
    const video = await page.$('.thumbnail');
    if (video) {
        await Promise.all([
            page.waitForNavigation({ waitUntil: 'domcontentloaded' }),
            video.click()
        ]);
        await page.waitForSelector('video', { timeout: 10000 });
        console.log('    ✓ Invidious video player loaded');
        await takeScreenshot(page, 'invidious_player');
    }
  } catch (e) {
    console.log(`    ❌ Invidious failed: ${e.message}`);
    await takeScreenshot(page, 'invidious_fail');
  } finally { await page.close(); }
}

async function testRedlib(browser, dashboardPage) {
  console.log('  🔴 Testing Redlib...');
  const url = await getServiceLink(dashboardPage, 'Redlib');
  if (!url) { console.log('    ⚠️ Redlib link not found'); return; }

  const page = await browser.newPage();
  try {
    await page.goto(url, { waitUntil: 'domcontentloaded' });
    // Go to a specific subreddit, e.g. /r/test
    const subredditUrl = url.replace(/\/$/, '') + '/r/test';
    await page.goto(subredditUrl, { waitUntil: 'domcontentloaded' });
    await page.waitForSelector('.post', { timeout: 5000 });
    console.log('    ✓ Redlib subreddit feed loaded');
    await takeScreenshot(page, 'redlib_feed');
  } catch (e) {
    console.log(`    ❌ Redlib failed: ${e.message}`);
    await takeScreenshot(page, 'redlib_fail');
  } finally { await page.close(); }
}

async function testBreezeWiki(browser, dashboardPage) {
  console.log('  📖 Testing BreezeWiki...');
  const url = await getServiceLink(dashboardPage, 'BreezeWiki');
  if (!url) { console.log('    ⚠️ BreezeWiki link not found'); return; }

  const page = await browser.newPage();
  try {
    // Construct the specific search URL requested
    // http://192.168.69.206:8380/paladins/search?q=talus
    // We replace the base IP with our BreezeWiki URL
    const baseUrl = url.replace(/\/$/, ''); 
    const searchUrl = `${baseUrl}/paladins/search?q=talus`;
    
    await page.goto(searchUrl, { waitUntil: 'domcontentloaded' });
    // Verify results loaded
    await page.waitForSelector('h1', { timeout: 5000 });
    console.log('    ✓ BreezeWiki search loaded');
    await takeScreenshot(page, 'breezewiki_search');
  } catch (e) {
    console.log(`    ❌ BreezeWiki failed: ${e.message}`);
    await takeScreenshot(page, 'breezewiki_fail');
  } finally { await page.close(); }
}

async function testRimgo(browser, dashboardPage) {
  console.log('  🖼️ Testing Rimgo...');
  const url = await getServiceLink(dashboardPage, 'Rimgo');
  if (!url) { console.log('    ⚠️ Rimgo link not found'); return; }

  const page = await browser.newPage();
  try {
    await page.goto(url, { waitUntil: 'domcontentloaded' });
    // Try to navigate to a random imgur gallery or just check homepage load
    // Rimgo is a frontend for Imgur. 
    await page.waitForSelector('img', { timeout: 5000 });
    console.log('    ✓ Rimgo loaded');
    await takeScreenshot(page, 'rimgo_view');
  } catch (e) {
    console.log(`    ❌ Rimgo failed: ${e.message}`);
    await takeScreenshot(page, 'rimgo_fail');
  } finally { await page.close(); }
}

async function testWikiless(browser, dashboardPage) {
  console.log('  📖 Testing Wikiless...');
  const url = await getServiceLink(dashboardPage, 'Wikiless');
  if (!url) { console.log('    ⚠️ Wikiless link not found'); return; }

  const page = await browser.newPage();
  try {
    await page.goto(url, { waitUntil: 'domcontentloaded' });
    // Search/View random
    await page.waitForSelector('input[name="q"]', { timeout: 5000 });
    await page.type('input[name="q"]', 'Special:Random'); 
    await page.keyboard.press('Enter');
    await page.waitForSelector('#content', { timeout: 10000 });
    console.log('    ✓ Wikiless random article loaded');
    await takeScreenshot(page, 'wikiless_article');
  } catch (e) {
    console.log(`    ❌ Wikiless failed: ${e.message}`);
    await takeScreenshot(page, 'wikiless_fail');
  } finally { await page.close(); }
}

async function testWireGuardClient(page) {
  console.log('  🔒 Testing WireGuard Client Creation...');
  try {
    // 1. Authenticate (if not already)
    const isAlreadyAdmin = await page.evaluate(() => document.body.classList.contains('admin-mode'));
    if (!isAlreadyAdmin) {
        await page.waitForSelector('#admin-lock-btn', { timeout: 5000 });
        await page.evaluate(() => document.getElementById('admin-lock-btn').click());
        await new Promise(r => setTimeout(r, 1000));
        await page.waitForSelector('#admin-password-input', { visible: true });
        await page.type('#admin-password-input', CONFIG.adminPassword);
        await page.keyboard.press('Enter');
        await page.waitForFunction(() => document.body.classList.contains('admin-mode'), { timeout: 10000 });
    }

    // 2. Open Modal
    await page.evaluate(() => window.openAddClientModal());
    await page.waitForSelector('#add-client-modal', { visible: true });
    await takeScreenshot(page, 'wg_modal_open');

    // 3. Fill and Create
    const clientName = `TestClient_${Date.now()}`;
    await page.type('#new-client-name', clientName);
    
    // Click Create
    await page.evaluate(() => {
        const btns = Array.from(document.querySelectorAll('#add-client-modal button'));
        const createBtn = btns.find(b => b.textContent.includes('Create'));
        if (createBtn) createBtn.click();
    });

    // 4. Wait for QR Modal (Success)
    await page.waitForSelector('#client-qr-modal', { visible: true, timeout: 10000 });
    await page.waitForSelector('#qrcode-container img, #qrcode-container canvas', { timeout: 5000 });
    console.log('    ✓ WireGuard client created and QR code generated');
    await takeScreenshot(page, 'wg_client_created');

    // Cleanup
    await page.evaluate(() => document.getElementById('client-qr-modal').style.display='none');

  } catch (e) {
    console.log(`    ❌ WireGuard test failed: ${e.message}`);
    await takeScreenshot(page, 'wg_fail');
  }
}

async function run() {
  console.log('=== Running Functional Verification ===');
  const browser = await puppeteer.launch({
    headless: CONFIG.headless ? 'new' : false,
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--ignore-certificate-errors'],
  });
  
  const page = await browser.newPage();
  await page.setViewport({ width: 1920, height: 1080 });
  
  try {
    await page.goto(CONFIG.baseUrl, { waitUntil: 'networkidle2' });
    
    // Run tests
    await testSearXNG(browser, page);
    await testInvidious(browser, page);
    await testRedlib(browser, page);
    await testBreezeWiki(browser, page);
    await testWikiless(browser, page);
    await testRimgo(browser, page);
    await testWireGuardClient(page); // Uses the dashboard page directly

  } catch (e) {
    console.error('Test suite error:', e);
  } finally {
    await browser.close();
  }
}

run();
