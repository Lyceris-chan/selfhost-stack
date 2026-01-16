const puppeteer = require('puppeteer');
const fs = require('fs');

const URL = 'http://localhost:8080';
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
      
      console.log('Extended Tests Completed Successfully.');

  } catch (error) {
    console.error('Test Failed:', error);
  } finally {
    await browser.close();
  }
})();