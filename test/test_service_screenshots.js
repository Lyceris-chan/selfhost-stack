/**
 * @fileoverview Service Screenshot Capture Suite
 *
 * Navigates to each service deployed in the Privacy Hub stack and captures
 * a full-page screenshot to verify visual integrity and accessibility.
 */

const puppeteer = require('puppeteer');
const fs = require('fs').promises;
const path = require('path');

const CONFIG = {
  lanIp: process.env.TEST_LAN_IP || 'localhost',
  timeout: 30000,
  screenshotDir: path.join(__dirname, 'screenshots', 'services'),
};

const SERVICES = [
  { name: 'Dashboard', port: 8088, path: '/' },
  { name: 'AdGuard_Home', port: 8083, path: '/' },
  { name: 'WireGuard_UI', port: 51821, path: '/' }, // Login page
  { name: 'Portainer', port: 9000, path: '/' },     // Login page
  { name: 'Redlib', port: 8080, path: '/' },
  { name: 'Wikiless', port: 8180, path: '/' },
  { name: 'Invidious', port: 3000, path: '/' },
  { name: 'Rimgo', port: 3002, path: '/' },
  { name: 'Breezewiki', port: 8380, path: '/' },
  { name: 'AnonymousOverflow', port: 8480, path: '/' },
  { name: 'SearXNG', port: 8082, path: '/' },
  { name: 'Immich', port: 2283, path: '/' },
  { name: 'Memos', port: 5230, path: '/' },
  { name: 'Cobalt', port: 9001, path: '/' },        // Often 9001 internal, mapped? Check compose if failing
  { name: 'Scribe', port: 8280, path: '/' },
  { name: 'VERT', port: 5555, path: '/' },
];

async function captureScreenshots() {
  console.log('📸 Starting Service Screenshot Capture...');
  console.log(`Target Host: ${CONFIG.lanIp}`);
  
  await fs.mkdir(CONFIG.screenshotDir, { recursive: true });

  const browser = await puppeteer.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--ignore-certificate-errors'],
  });

  const page = await browser.newPage();
  await page.setViewport({ width: 1280, height: 800 });

  let successCount = 0;

  for (const service of SERVICES) {
    const url = `http://${CONFIG.lanIp}:${service.port}${service.path}`;
    const screenshotPath = path.join(CONFIG.screenshotDir, `${service.name}.png`);
    
    try {
      console.log(`  Visiting ${service.name} (${url})...`);
      
      const response = await page.goto(url, {
        waitUntil: 'networkidle2',
        timeout: CONFIG.timeout
      });

      if (!response) {
        throw new Error('No response received');
      }

      // Special handling for loading screens or redirects
      await new Promise(r => setTimeout(r, 2000));

      await page.screenshot({ path: screenshotPath, fullPage: true });
      console.log(`  ✅ Captured: ${service.name}`);
      successCount++;

    } catch (e) {
      console.log(`  ❌ Failed ${service.name}: ${e.message}`);
      // Take an error screenshot if possible
      try {
        await page.screenshot({ path: path.join(CONFIG.screenshotDir, `${service.name}_ERROR.png`) });
      } catch (err) { /* ignore */ }
    }
  }

  await browser.close();
  console.log(`
🎉 Screenshot run complete. ${successCount}/${SERVICES.length} services captured.`);
  console.log(`📂 Gallery: ${CONFIG.screenshotDir}`);
  
  return successCount > 0 ? 0 : 1;
}

if (require.main === module) {
  captureScreenshots().catch(err => {
    console.error('Fatal Error:', err);
    process.exit(1);
  });
}
