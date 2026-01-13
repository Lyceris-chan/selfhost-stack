const { initBrowser, logResult, getAdminPassword, generateReport, SCREENSHOT_DIR } = require('./lib/browser_utils');
const path = require('path');

const LAN_IP = process.env.LAN_IP || '127.0.0.1';
const DASHBOARD_URL = `http://${LAN_IP}:8081`;

async function runAudit() {
    const { browser, page } = await initBrowser();
    const ADMIN_PASS = getAdminPassword();

    try {
        console.log('--- Phase 1: Dashboard UI Audit ---');
        await page.goto(DASHBOARD_URL, { waitUntil: 'networkidle2', timeout: 30000 });
        
        // 1. Theme Extraction & Application
        logResult('Dashboard', 'Load', 'PASS', 'Dashboard reachable');
        
        // 2. Admin Login
        console.log('  Testing Admin Login...');
        await page.click('#admin-lock-btn');
        await page.waitForSelector('#login-modal', { visible: true });
        
        // Layout check
        const loginLayout = await page.evaluate(() => {
            const modal = document.querySelector('#login-modal');
            const header = modal.querySelector('.modal-header');
            const title = header.querySelector('h2');
            const closeBtn = header.querySelector('.btn-icon');
            const tRect = title.getBoundingClientRect();
            const cRect = closeBtn.getBoundingClientRect();
            return {
                overlap: (tRect.right > cRect.left),
                verticallyAligned: Math.abs((tRect.top + tRect.height/2) - (cRect.top + cRect.height/2)) < 5
            };
        });
        logResult('Dashboard', 'Login Modal Layout', (!loginLayout.overlap && loginLayout.verticallyAligned) ? 'PASS' : 'FAIL', `Overlap: ${loginLayout.overlap}`);

        await page.type('#admin-password-input', ADMIN_PASS);
        await page.click('#login-modal .btn-filled');
        await page.waitForFunction(() => document.body.classList.contains('admin-mode'), { timeout: 10000 });
        logResult('Dashboard', 'Admin Login', 'PASS', 'Authenticated successfully');

        // 3. Click-to-Copy Verification
        console.log('  Testing Click-to-Copy...');
        const codeBlock = await page.$('.code-block');
        if (codeBlock) {
            await codeBlock.click();
            await new Promise(r => setTimeout(r, 500));
            const text = await page.evaluate(el => el.textContent, codeBlock);
            logResult('Dashboard', 'Click-to-Copy', text === 'Copied!' ? 'PASS' : 'FAIL', 'Visual feedback verified');
        }

        // 4. Invidious Deep Link & Playback (Spot Check)
        console.log('--- Phase 2: Functional Spot Check (Invidious) ---');
        await page.goto(`http://${LAN_IP}:3000`, { waitUntil: 'domcontentloaded' });
        await page.waitForSelector('input[name="q"]', { timeout: 10000 });
        await page.type('input[name="q"]', 'Big Buck Bunny');
        await page.keyboard.press('Enter');
        await page.waitForSelector('a[href*="watch?v="]', { timeout: 10000 });
        logResult('Invidious', 'Search', 'PASS', 'Results returned');

    } catch (e) {
        console.error('Audit Error:', e);
        logResult('Global', 'Audit Execution', 'FAIL', e.message);
    } finally {
        await browser.close();
        await generateReport();
    }
}

runAudit();
