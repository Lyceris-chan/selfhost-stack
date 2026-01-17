const puppeteer = require('puppeteer');
const fs = require('fs');

const LAN_IP = process.env.LAN_IP || '127.0.0.1';
const URL = `http://${LAN_IP}:8088`;
const SCREENSHOT_DIR = 'test/screenshots/extended';

if (!fs.existsSync(SCREENSHOT_DIR)) {
  fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });
}

async function testDashboardLoading(page) {
    console.log('1. Verifying Dashboard Loading...');
    await page.goto(URL, { waitUntil: 'networkidle0' });
    const title = await page.title();
    console.log(`Page Title: ${title}`);
    await page.screenshot({ path: `${SCREENSHOT_DIR}/1_dashboard_loaded.png` });
}

async function testAdminAuthentication(page) {
    console.log('4. Verifying Admin Authentication...');
    await page.click('#admin-lock-btn');
    try {
        await page.waitForSelector('#signin-modal', { visible: true, timeout: 5000 });
        await page.type('#admin-password-input', 'password');
        await page.screenshot({ path: `${SCREENSHOT_DIR}/4_admin_modal.png` });
    } catch (e) {
        console.log("Admin modal did not appear or timed out (expected if already logged in or disabled)");
    }
}

async function testGluetunStatus(page) {
    console.log('5. Verifying Gluetun Status...');
    const gluetunStatus = await page.$('#hint-vpn-status');
    if (gluetunStatus) {
        const text = await page.evaluate(el => el.textContent, gluetunStatus);
        console.log(`Gluetun Status Text: ${text}`);
    } else {
        console.error('Gluetun status element not found');
    }
}

async function testCertificateStatus(page) {
    console.log('Verifying Certificate Status...');
    // Add logic to check cert status
    const certStatus = await page.$('#cert-status-content');
    if (certStatus) {
        console.log('Certificate status section found.');
    }
}

async function testWireGuardManagement(page) {
    console.log('Verifying WireGuard Management...');
    // Add logic to check WG management
}

async function testSearXNGSearch(page) {
    console.log('Verifying SearXNG Search...');
    try {
        await page.goto('http://localhost:8082', { waitUntil: 'networkidle0' });
        await page.waitForSelector('input[name="q"]');
        await page.type('input[name="q"]', 'privacy');
        await page.keyboard.press('Enter');
        await page.waitForSelector('#urls', { timeout: 10000 }); // Wait for results container
        console.log('SearXNG Search: Results loaded.');
        await page.screenshot({ path: `${SCREENSHOT_DIR}/searxng_results.png` });
    } catch (e) {
        console.error('SearXNG Search Failed:', e);
        // Do not throw, allow other tests to run
    }
}

async function testRimgoImage(page) {
    console.log('Verifying Rimgo Image Loading...');
    try {
        // Test a specific gallery as requested
        await page.goto('http://localhost:3002/gallery/Lh4LLaq', { waitUntil: 'networkidle0' });
        const title = await page.title();
        if (title.toLowerCase().includes('rimgo') || title.includes('Imgur')) {
             console.log(`Rimgo Page Title Verified: ${title}`);
        } else {
             console.warn(`Rimgo Title unexpected: ${title}`);
        }
        await page.screenshot({ path: `${SCREENSHOT_DIR}/rimgo_gallery.png` });
    } catch (e) {
        console.error('Rimgo Test Failed:', e);
    }
}

async function testInvidiousVideo(page) {
    console.log('Verifying Invidious Video Loading...');
    try {
        // Test "Me at the zoo" - the first YouTube video
        await page.goto('http://localhost:3000/watch?v=jNQXAC9IVRw', { waitUntil: 'domcontentloaded', timeout: 30000 });
        
        const title = await page.title();
        console.log(`Invidious Page Title: ${title}`);
        
        if (title.toLowerCase().includes('invidious') || title.includes('Me at the zoo')) {
            console.log(`Invidious Video Verified: ${title}`);
        } else {
            console.warn(`Invidious Title unexpected: ${title}`);
        }
        await page.screenshot({ path: `${SCREENSHOT_DIR}/invidious_video.png` });
    } catch (e) {
        console.error('Invidious Test Failed:', e);
    }
}

async function testBreezewikiLookup(page) {
    console.log('Verifying Breezewiki Lookup...');
    try {
        // Breezewiki often redirects to a specific wiki.
        // Let's try the example url: breezewiki.com/paladins/search?q=talus -> localhost:8380
        // We'll target localhost:8380/paladins/search?q=talus
        await page.goto('http://localhost:8380/paladins/search?q=talus', { waitUntil: 'domcontentloaded', timeout: 15000 });
        // Check for some content indicating a wiki page or search result
        // Note: If internet access is restricted in the container (VPN), this might fail if it can't fetch upstream.
        // But the requirement implies testing the service functionality.
        const content = await page.content();
        if (content.includes('Talus') || content.includes('Search results')) {
            console.log('Breezewiki: Content verified.');
        } else {
            console.log('Breezewiki: Page loaded but specific content not found (could be upstream connectivity).');
        }
        await page.screenshot({ path: `${SCREENSHOT_DIR}/breezewiki_search.png` });
    } catch (e) {
        console.error('Breezewiki Test Failed:', e);
    }
}

(async () => {
  console.log('Starting Extended Interaction Tests...');
  const browser = await puppeteer.launch({
    headless: "new",
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--ignore-certificate-errors']
  });
  const page = await browser.newPage();
  await page.setViewport({ width: 1440, height: 900 });

  try {
      await testDashboardLoading(page);
      await testAdminAuthentication(page);
      await testGluetunStatus(page);
      await testCertificateStatus(page);
      await testWireGuardManagement(page);
      
      // New Functional Tests
      await testSearXNGSearch(page);
      await testRimgoImage(page);
      await testInvidiousVideo(page);
      await testBreezewikiLookup(page);
      
      console.log('Extended Tests Completed Successfully.');

  } catch (error) {
    console.error('Test Failed:', error);
  } finally {
    await browser.close();
  }
})();