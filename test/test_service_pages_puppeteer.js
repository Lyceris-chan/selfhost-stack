const puppeteer = require('puppeteer');

const DASHBOARD_URL = process.env.DASHBOARD_URL || 'http://localhost:8081/';
const BREEZEWIKI_PATH = process.env.BREEZEWIKI_PATH || '/paladins/wiki/Talus';
const INVIDIOUS_VIDEO_ID = process.env.INVIDIOUS_VIDEO_ID || 'dQw4w9WgXcQ';
const MOCK_SERVICE_PAGES = process.env.MOCK_SERVICE_PAGES === '1' || process.env.MOCK_API === '1';
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
  'cobalt',
  'searxng',
  'immich',
  'adguard',
  'portainer',
  'wg-easy',
  'hub-api',
  'odido-booster'
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
  cobalt: 'http://127.0.0.1:9001',
  searxng: 'http://127.0.0.1:8082',
  immich: 'http://127.0.0.1:2283',
  adguard: 'http://127.0.0.1:8083',
  portainer: 'http://127.0.0.1:9000',
  'wg-easy': 'http://127.0.0.1:51821',
  'hub-api': 'http://127.0.0.1:55555',
  'odido-booster': 'http://127.0.0.1:8085'
};

function normalizeBaseUrl(url) {
  return url.replace(/\/+$/, '');
}

function joinUrl(base, path) {
  const safeBase = normalizeBaseUrl(base);
  const safePath = path.startsWith('/') ? path : `/${path}`;
  return `${safeBase}${safePath}`;
}

async function attachApiMocks(page) {
  if (!MOCK_SERVICE_PAGES) return;
  await page.setRequestInterception(true);
  page.on('request', (request) => {
    const url = request.url();
    if (url.includes('/api/containers')) {
      const containers = {};
      servicesList.forEach((service) => {
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
      servicesList.forEach((service) => { services[service] = 'healthy'; });
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

function isValidUrl(url) {
  try {
    new URL(url);
    return true;
  } catch (error) {
    return false;
  }
}

async function checkBasicPage(page, name, url, mockServices) {
  if (mockServices) {
    const ok = !!url && isValidUrl(url);
    return {
      name,
      url,
      status: ok ? 200 : null,
      ok,
      title: 'Mocked',
      bodyLen: 0,
      finalUrl: url,
      mocked: true,
      error: ok ? undefined : 'Invalid URL'
    };
  }
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

async function testSpecialized(page, name, baseUrl, path, pattern, mockServices) {
  const url = joinUrl(baseUrl, path);
  if (mockServices) {
    const ok = isValidUrl(url);
    return { name, url, status: ok ? 200 : null, ok, mocked: true };
  }
  try {
    const response = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
    const status = response ? response.status() : null;
    const match = await page.evaluate((pat) => {
      const bodyText = document.body ? document.body.innerText : '';
      return new RegExp(pat, 'i').test(bodyText);
    }, pattern);
    const ok = !!response && status < 400 && match;
    return { name, url, status, ok };
  } catch (error) {
    return { name, url, status: null, ok: false, error: error.message };
  }
}

async function testBreezewiki(page, baseUrl, mockServices) {
  return testSpecialized(page, 'BreezeWiki /paladins/wiki/Talus', baseUrl, BREEZEWIKI_PATH, 'talus', mockServices);
}

async function testRimgoRandomImage(page, baseUrl, mockServices) {
  const base = normalizeBaseUrl(baseUrl);
  if (mockServices) {
    const ok = isValidUrl(base);
    return { name: 'Rimgo random image', url: base, status: ok ? 200 : null, ok, mocked: true };
  }
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

async function testInvidiousVideo(page, baseUrl, mockServices) {
  const url = joinUrl(baseUrl, `/watch?v=${INVIDIOUS_VIDEO_ID}`);
  if (mockServices) {
    const ok = isValidUrl(url);
    return { name: 'Invidious video playback page', url, status: ok ? 200 : null, ok, mocked: true };
  }
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
  
  const dashboardConsoleErrors = [];
  const services = await withPage(browser, async (page) => {
    // Capture console errors from the dashboard
    page.on('console', msg => {
      if (msg.type() === 'error') {
        const text = msg.text();
        // Ignore expected network errors during partial deployments
        if (text.includes('401 (Unauthorized)') || 
            text.includes('502 (Bad Gateway)') || 
            text.includes('404 (Not Found)') ||
            text.includes('net::ERR_ABORTED') ||
            text.includes('fontlay.com') ||
            text.includes('fetch error') ||
            text.includes('API Call failed')) {
          return;
        }
        dashboardConsoleErrors.push(text);
        console.log(`[DASHBOARD CONSOLE ERROR] ${text}`);
      }
    });

    await attachApiMocks(page);
    await page.goto(DASHBOARD_URL, { waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.waitForFunction(() => document.querySelectorAll('.card[data-url]').length > 0, { timeout: 30000 }).catch(() => null);
    return page.evaluate(() => {
      return Array.from(document.querySelectorAll('.card[data-url]')).map((card) => ({
        id: card.id || '',
        url: card.getAttribute('data-url'),
        container: card.getAttribute('data-container') || '',
      }));
    });
  });

  const results = [];
  // Add dashboard console check result
  results.push({
    name: 'Dashboard Console Logs',
    ok: dashboardConsoleErrors.length === 0,
    error: dashboardConsoleErrors.length > 0 ? `${dashboardConsoleErrors.length} errors found in console` : undefined
  });

  for (const service of services) {
    if (!service.url) continue;
    const name = service.container || service.id || service.url;
    const check = await withPage(browser, (page) => checkBasicPage(page, name, service.url, MOCK_SERVICE_PAGES));
    results.push(check);
  }

  const serviceMap = Object.fromEntries(
    services.map((s) => [s.container, s.url]).filter(([key, val]) => key && val),
  );

  if (serviceMap.breezewiki) results.push(await withPage(browser, (page) => testBreezewiki(page, serviceMap.breezewiki, MOCK_SERVICE_PAGES)));
  if (serviceMap.rimgo) results.push(await withPage(browser, (page) => testRimgoRandomImage(page, serviceMap.rimgo, MOCK_SERVICE_PAGES)));
  if (serviceMap.invidious) results.push(await withPage(browser, (page) => testInvidiousVideo(page, serviceMap.invidious, MOCK_SERVICE_PAGES)));
  
  // New specialized tests
  if (serviceMap.redlib) results.push(await withPage(browser, (page) => testSpecialized(page, 'Redlib Content', serviceMap.redlib, '/r/all', 'redlib', MOCK_SERVICE_PAGES)));
  if (serviceMap.wikiless) results.push(await withPage(browser, (page) => testSpecialized(page, 'Wikiless Content', serviceMap.wikiless, '/wiki/Main_Page', 'Wikipedia', MOCK_SERVICE_PAGES)));
  if (serviceMap.searxng) results.push(await withPage(browser, (page) => testSpecialized(page, 'SearXNG Content', serviceMap.searxng, '/', 'SearXNG', MOCK_SERVICE_PAGES)));
  if (serviceMap.immich) results.push(await withPage(browser, (page) => testSpecialized(page, 'Immich Login', serviceMap.immich, '/auth/login', 'Immich', MOCK_SERVICE_PAGES)));
  if (serviceMap.memos) results.push(await withPage(browser, (page) => testSpecialized(page, 'Memos Login', serviceMap.memos, '/auth/login', 'Memos', MOCK_SERVICE_PAGES)));
  if (serviceMap.vert) results.push(await withPage(browser, (page) => testSpecialized(page, 'VERT Interface', serviceMap.vert, '/', 'Conversion', MOCK_SERVICE_PAGES)));
  if (serviceMap.cobalt) results.push(await withPage(browser, (page) => testSpecialized(page, 'Cobalt Interface', serviceMap.cobalt, '/', 'cobalt', MOCK_SERVICE_PAGES)));
  if (serviceMap.scribe) results.push(await withPage(browser, (page) => testSpecialized(page, 'Scribe Interface', serviceMap.scribe, '/', 'scribe', MOCK_SERVICE_PAGES)));
  if (serviceMap.anonymousoverflow) results.push(await withPage(browser, (page) => testSpecialized(page, 'AnonOverflow Interface', serviceMap.anonymousoverflow, '/', 'overflow', MOCK_SERVICE_PAGES)));
  if (serviceMap.adguard) results.push(await withPage(browser, (page) => testSpecialized(page, 'AdGuard Login', serviceMap.adguard, '/', 'AdGuard', MOCK_SERVICE_PAGES)));
  if (serviceMap['wg-easy']) results.push(await withPage(browser, (page) => testSpecialized(page, 'WireGuard Login', serviceMap['wg-easy'], '/', 'WireGuard', MOCK_SERVICE_PAGES)));
  if (serviceMap['odido-booster']) results.push(await withPage(browser, (page) => testSpecialized(page, 'Odido Booster', serviceMap['odido-booster'], '/', 'Odido', MOCK_SERVICE_PAGES)));
  if (serviceMap['hub-api']) results.push(await withPage(browser, (page) => testSpecialized(page, 'Hub API Status', serviceMap['hub-api'], '/status', 'healthy', MOCK_SERVICE_PAGES)));

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
