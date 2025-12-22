const puppeteer = require('puppeteer');

const DASHBOARD_URL = process.env.DASHBOARD_URL || 'http://10.0.10.248:8081/';
const BREEZEWIKI_PATH = process.env.BREEZEWIKI_PATH || '/paladins/wiki/Talus';
const INVIDIOUS_VIDEO_ID = process.env.INVIDIOUS_VIDEO_ID || 'dQw4w9WgXcQ';

function normalizeBaseUrl(url) {
  return url.replace(/\/+$/, '');
}

function joinUrl(base, path) {
  const safeBase = normalizeBaseUrl(base);
  const safePath = path.startsWith('/') ? path : `/${path}`;
  return `${safeBase}${safePath}`;
}

async function checkBasicPage(page, name, url) {
  try {
    const response = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
    const status = response ? response.status() : null;
    const title = await page.title();
    const bodyText = await page.evaluate(() => (document.body ? document.body.innerText.trim() : ''));
    const ok = !!response && status < 400;
    return { name, url, status, ok, title, bodyLen: bodyText.length, finalUrl: page.url() };
  } catch (error) {
    return { name, url, status: null, ok: false, error: error.message };
  }
}

async function testBreezewiki(page, baseUrl) {
  const url = joinUrl(baseUrl, BREEZEWIKI_PATH);
  try {
    const response = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
    const status = response ? response.status() : null;
    const hasTalus = await page.evaluate(() => {
      const bodyText = document.body ? document.body.innerText : '';
      return /talus/i.test(bodyText);
    });
    const ok = !!response && status < 400 && hasTalus;
    return { name: 'BreezeWiki /paladins/wiki/Talus', url, status, ok };
  } catch (error) {
    return { name: 'BreezeWiki /paladins/wiki/Talus', url, status: null, ok: false, error: error.message };
  }
}

async function testRimgoRandomImage(page, baseUrl) {
  const base = normalizeBaseUrl(baseUrl);
  let response = null;
  try {
    await page.goto(`${base}/trending`, { waitUntil: 'domcontentloaded', timeout: 60000 });
    let links = await page.evaluate(() => {
      const anchors = Array.from(document.querySelectorAll('a[href*="/gallery/"], a[href*="/i/"]'));
      return anchors.map((a) => a.href).filter(Boolean);
    });
    if (links.length === 0) {
      await page.goto(base, { waitUntil: 'domcontentloaded', timeout: 60000 });
      links = await page.evaluate(() => {
        const anchors = Array.from(document.querySelectorAll('a[href*="/gallery/"], a[href*="/i/"]'));
        return anchors.map((a) => a.href).filter(Boolean);
      });
    }
    if (links.length === 0) {
      return { name: 'Rimgo random image', url: base, status: null, ok: false, error: 'No image links found' };
    }
    const randomLink = links[Math.floor(Math.random() * links.length)];
    response = await page.goto(randomLink, { waitUntil: 'domcontentloaded', timeout: 60000 });
    const status = response ? response.status() : null;
    const hasImage = await page.evaluate(() => {
      const img = document.querySelector('img');
      return img && (img.getAttribute('src') || '').length > 0;
    });
    const ok = !!response && status < 400 && hasImage;
    return { name: 'Rimgo random image', url: page.url(), status, ok };
  } catch (error) {
    return { name: 'Rimgo random image', url: base, status: null, ok: false, error: error.message };
  }
}

async function testInvidiousVideo(page, baseUrl) {
  const url = joinUrl(baseUrl, `/watch?v=${INVIDIOUS_VIDEO_ID}`);
  try {
    const response = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
    const status = response ? response.status() : null;
    const hasVideo = await page.evaluate(() => !!document.querySelector('video'));
    const hasError = await page.evaluate(() => /unavailable|error|not found/i.test(document.body ? document.body.innerText : ''));
    const ok = !!response && status < 400 && hasVideo && !hasError;
    return { name: 'Invidious video playback page', url, status, ok };
  } catch (error) {
    return { name: 'Invidious video playback page', url, status: null, ok: false, error: error.message };
  }
}

async function withPage(browser, fn) {
  const page = await browser.newPage();
  page.setDefaultTimeout(60000);
  try {
    return await fn(page);
  } finally {
    await page.close();
  }
}

async function run() {
  const browser = await puppeteer.launch({
    headless: 'new',
    args: ['--no-sandbox', '--disable-setuid-sandbox'],
  });

  console.log('Starting Service Page Verification...');
  console.log(`Dashboard URL: ${DASHBOARD_URL}`);
  const services = await withPage(browser, async (page) => {
    await page.goto(DASHBOARD_URL, { waitUntil: 'domcontentloaded', timeout: 60000 });
    return page.evaluate(() => {
      return Array.from(document.querySelectorAll('.card[data-url]')).map((card) => ({
        id: card.id || '',
        url: card.getAttribute('data-url'),
        container: card.getAttribute('data-container') || '',
      }));
    });
  });

  const results = [];
  for (const service of services) {
    if (!service.url) continue;
    const name = service.container || service.id || service.url;
    const check = await withPage(browser, (page) => checkBasicPage(page, name, service.url));
    results.push(check);
  }

  const serviceMap = Object.fromEntries(
    services.map((s) => [s.container, s.url]).filter(([key, val]) => key && val),
  );

  if (serviceMap.breezewiki) {
    results.push(await withPage(browser, (page) => testBreezewiki(page, serviceMap.breezewiki)));
  } else {
    results.push({ name: 'BreezeWiki /paladins/wiki/Talus', url: 'N/A', ok: false, error: 'BreezeWiki base URL not found' });
  }

  if (serviceMap.rimgo) {
    results.push(await withPage(browser, (page) => testRimgoRandomImage(page, serviceMap.rimgo)));
  } else {
    results.push({ name: 'Rimgo random image', url: 'N/A', ok: false, error: 'Rimgo base URL not found' });
  }

  if (serviceMap.invidious) {
    results.push(await withPage(browser, (page) => testInvidiousVideo(page, serviceMap.invidious)));
  } else {
    results.push({ name: 'Invidious video playback page', url: 'N/A', ok: false, error: 'Invidious base URL not found' });
  }

  await browser.close();

  console.log('\n--- SERVICE PAGE RESULTS ---');
  for (const result of results) {
    const status = result.ok ? 'PASS' : 'FAIL';
    const details = result.status ? `status=${result.status}` : (result.error ? `error=${result.error}` : 'status=unknown');
    console.log(`${status === 'PASS' ? '✅' : '❌'} ${result.name}: ${status} (${details}) ${result.url ? result.url : ''}`);
  }

  const failures = results.filter((r) => !r.ok);
  if (failures.length > 0) {
    process.exitCode = 1;
  }
}

run().catch((error) => {
  console.error('Service page verification failed:', error);
  process.exit(1);
});
