/**
 * @fileoverview Targeted Functional Tests.
 * Performs specific user interactions requested: SearXNG search, Invidious play, Redlib browse, BreezeWiki search.
 */

const puppeteer = require('puppeteer');
const fs = require('fs');
const path = require('path');

const CONFIG = {
  baseUrl: process.env.TEST_BASE_URL || 'http://localhost:8088',
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

async function getServiceUrl(page, titleText) {
  return await page.evaluate((text) => {
    const cards = Array.from(document.querySelectorAll('.card'));
    for (const card of cards) {
      const title = card.querySelector('h2, h3')?.innerText || '';
      if (title.toLowerCase().includes(text.toLowerCase())) {
        const link = card.tagName === 'A' ? card : card.querySelector('a');
        return link ? link.href : null;
      }
    }
    return null;
  }, titleText);
}

async function run() {
  console.log('=== Running Targeted Functional Tests ===');
  const browser = await puppeteer.launch({
    headless: CONFIG.headless ? 'new' : false,
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--ignore-certificate-errors', '--disable-dev-shm-usage'],
  });
  
  const page = await browser.newPage();
  await page.setViewport({ width: 1920, height: 1080 });
  
  // 1. Get Dashboard Links
  console.log('  Using Dashboard to resolve service URLs...');
  await page.goto(CONFIG.baseUrl, { waitUntil: 'networkidle2' });
  
  const services = {
    searxng: await getServiceUrl(page, 'SearXNG'),
    invidious: await getServiceUrl(page, 'Invidious'),
    redlib: await getServiceUrl(page, 'Redlib'),
    breezewiki: await getServiceUrl(page, 'BreezeWiki'),
    wikiless: await getServiceUrl(page, 'Wikiless'),
    rimgo: await getServiceUrl(page, 'Rimgo'),
  };

  console.log('  Service URLs resolved:', services);

  // 2. SearXNG Search
  if (services.searxng) {
    console.log('  🔍 Testing SearXNG...');
    try {
      await page.goto(services.searxng, { waitUntil: 'domcontentloaded' });
      await page.waitForSelector('input[name="q"]', { timeout: 5000 });
      await page.type('input[name="q"]', 'test query');
      await page.keyboard.press('Enter');
      await page.waitForSelector('#urls', { timeout: 10000 });
      console.log('    ✓ SearXNG search successful');
      await takeScreenshot(page, 'searxng_search_results');
    } catch (e) {
      console.log(`    ❌ SearXNG failed: ${e.message}`);
      await takeScreenshot(page, 'searxng_fail');
    }
  }

  // 3. Invidious Play (Big Buck Bunny)
  if (services.invidious) {
    console.log('  📺 Testing Invidious...');
    try {
      await page.goto(services.invidious, { waitUntil: 'domcontentloaded' });
      await page.waitForSelector('input[name="q"]', { timeout: 5000 });
      await page.type('input[name="q"]', 'big buck bunny');
      await page.keyboard.press('Enter');
      await page.waitForSelector('.thumbnail', { timeout: 10000 });
      
      const video = await page.$('.thumbnail');
      await Promise.all([
        page.waitForNavigation({ waitUntil: 'domcontentloaded' }),
        video.click()
      ]);
      await page.waitForSelector('video', { timeout: 15000 });
      console.log('    ✓ Invidious video page loaded');
      await takeScreenshot(page, 'invidious_video_page');
    } catch (e) {
      console.log(`    ❌ Invidious failed: ${e.message}`);
      await takeScreenshot(page, 'invidious_fail');
    }
  }

  // 4. BreezeWiki Specific Search
  if (services.breezewiki) {
    console.log('  📖 Testing BreezeWiki (Custom URL)...');
    try {
      // "copy this format http://.../paladins/search?q=talus"
      // We replace the dashboard's IP base with the discovered one if needed, or just append path
      const baseUrl = services.breezewiki.replace(/\/$/, '');
      const targetUrl = `${baseUrl}/paladins/search?q=talus`;
      
      await page.goto(targetUrl, { waitUntil: 'domcontentloaded' });
      await page.waitForSelector('h1', { timeout: 10000 }); // "Search results"
      console.log('    ✓ BreezeWiki specific search loaded');
      await takeScreenshot(page, 'breezewiki_talus_search');
    } catch (e) {
      console.log(`    ❌ BreezeWiki failed: ${e.message}`);
      await takeScreenshot(page, 'breezewiki_fail');
    }
  }

  // 5. Redlib Subreddit
  if (services.redlib) {
    console.log('  🔴 Testing Redlib...');
    try {
      const baseUrl = services.redlib.replace(/\/$/, '');
      await page.goto(`${baseUrl}/r/test`, { waitUntil: 'domcontentloaded' });
      await page.waitForSelector('.post', { timeout: 10000 });
      console.log('    ✓ Redlib /r/test loaded');
      await takeScreenshot(page, 'redlib_subreddit');
    } catch (e) {
      console.log(`    ❌ Redlib failed: ${e.message}`);
      await takeScreenshot(page, 'redlib_fail');
    }
  }

  // 6. Rimgo Random Image
  if (services.rimgo) {
    console.log('  🖼️ Testing Rimgo...');
    try {
      // Rimgo homepage usually shows popular/random. Just verify image load.
      await page.goto(services.rimgo, { waitUntil: 'domcontentloaded' });
      await page.waitForSelector('img', { timeout: 10000 });
      console.log('    ✓ Rimgo loaded');
      await takeScreenshot(page, 'rimgo_view');
    } catch (e) {
      console.log(`    ❌ Rimgo failed: ${e.message}`);
      await takeScreenshot(page, 'rimgo_fail');
    }
  }

  // 7. Wikiless Random
  if (services.wikiless) {
    console.log('  📚 Testing Wikiless...');
    try {
        await page.goto(services.wikiless, { waitUntil: 'domcontentloaded' });
        await page.type('input[name="q"]', 'Privacy');
        await page.keyboard.press('Enter');
        await page.waitForSelector('#content', { timeout: 10000 });
        console.log('    ✓ Wikiless article loaded');
        await takeScreenshot(page, 'wikiless_article');
    } catch (e) {
        console.log(`    ❌ Wikiless failed: ${e.message}`);
        await takeScreenshot(page, 'wikiless_fail');
    }
  }

  await browser.close();
}

run();
