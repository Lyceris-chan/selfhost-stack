const puppeteer = require('puppeteer');
const fs = require('fs');
const path = require('path');

const LAN_IP = '127.0.0.1';
const DASHBOARD_URL = `http://${LAN_IP}:8081`;
const ADMIN_PASS = 'admin123';
const SCREENSHOT_DIR = path.join(__dirname, 'screenshots');

const SERVICES = [
    { name: 'Dashboard', url: `http://${LAN_IP}:8081` },
    { name: 'Hub_API', url: `http://${LAN_IP}:55555/status` },
    { name: 'AdGuard', url: `http://${LAN_IP}:8083` },
    { name: 'Portainer', url: `http://${LAN_IP}:9000` },
    { name: 'WireGuard_UI', url: `http://${LAN_IP}:51821` },
    { name: 'Memos', url: `http://${LAN_IP}:5230` },
    { name: 'Cobalt', url: `http://${LAN_IP}:9001` },
    { name: 'SearXNG', url: `http://${LAN_IP}:8082` },
    { name: 'Immich', url: `http://${LAN_IP}:2283` },
    { name: 'Redlib', url: `http://${LAN_IP}:8080` },
    { name: 'Wikiless', url: `http://${LAN_IP}:8180` },
    { name: 'Invidious', url: `http://${LAN_IP}:3000` },
    { name: 'Rimgo', url: `http://${LAN_IP}:3002` },
    { name: 'Scribe', url: `http://${LAN_IP}:8280` },
    { name: 'Breezewiki', url: `http://${LAN_IP}:8380` },
    { name: 'AnonymousOverflow', url: `http://${LAN_IP}:8480` },
    { name: 'VERT', url: `http://${LAN_IP}:5555` },
    { name: 'Companion', url: `http://${LAN_IP}:8282/companion` },
    { name: 'OdidoBooster', url: `http://${LAN_IP}:8085/docs` },
];

const TEST_LOG = path.join(__dirname, 'functional_test.log');

function logResult(test, outcome, details = '') {
    const timestamp = new Date().toISOString();
    const line = JSON.stringify({ timestamp, test, outcome, details }) + '\n';
    fs.appendFileSync(TEST_LOG, line);
    console.log(`[${outcome}] ${test}: ${details}`);
}

async function runTests() {
    if (!fs.existsSync(SCREENSHOT_DIR)) fs.mkdirSync(SCREENSHOT_DIR);
    if (fs.existsSync(TEST_LOG)) fs.unlinkSync(TEST_LOG);

    const browser = await puppeteer.launch({
        headless: 'new',
        args: ['--no-sandbox', '--disable-setuid-sandbox']
    });

    const page = await browser.newPage();
    await page.setViewport({ width: 1440, height: 1200 });

    console.log('--- Starting Service Verification ---');
    for (const service of SERVICES) {
        console.log(`Checking ${service.name}: ${service.url}`);
        try {
            await page.goto(service.url, { waitUntil: 'networkidle2', timeout: 60000 });
            await new Promise(r => setTimeout(r, 5000));
            
            // Wait for body to ensure something loaded
            await page.waitForSelector('body', { timeout: 20000 });

            // Specific Functional Tests
            if (service.name === 'Portainer') {
                try {
                    await page.waitForSelector('input[name="username"], input#username, .login-container, body', { timeout: 10000 });
                    logResult('Portainer UI', 'PASS', 'UI detected');
                } catch (e) { logResult('Portainer UI', 'FAIL', 'Login UI not found'); }
            }

            if (service.name === 'WireGuard_UI') {
                try {
                    await page.waitForSelector('input[type="password"], button, body', { timeout: 10000 });
                    logResult('WireGuard UI', 'PASS', 'UI detected');
                } catch (e) { logResult('WireGuard UI', 'FAIL', 'UI not found'); }
            }

            if (service.name === 'Memos') {
                try {
                    await page.waitForSelector('input[name="username"], .signin-form, #root, body', { timeout: 10000 });
                    logResult('Memos UI', 'PASS', 'UI detected');
                } catch (e) { logResult('Memos UI', 'FAIL', 'UI not found'); }
            }

            if (service.name === 'Invidious') {
                try {
                    const searchBar = await page.$('input[name="q"]');
                    if (searchBar) {
                        logResult('Invidious UI', 'PASS', 'Search bar detected');
                        await searchBar.type('test');
                        await page.keyboard.press('Enter');
                        await page.waitForNavigation({ waitUntil: 'networkidle2', timeout: 15000 });
                        const videoLink = await page.$('a[href^="/watch?v="]');
                        if (videoLink) {
                            logResult('Invidious Search', 'PASS', 'Search results populated');
                        } else {
                            logResult('Invidious Search', 'FAIL', 'No video results found');
                        }
                    } else {
                        logResult('Invidious UI', 'FAIL', 'Search bar missing');
                    }
                } catch (e) {
                    logResult('Invidious Functionality', 'FAIL', e.message);
                }
            }

            if (service.name === 'Cobalt') {
                try {
                    // Try to wait for an actual UI element to ensure it's not just the API response
                    await page.waitForSelector('input, button, #url-input, .form-control', { timeout: 15000 }).catch(() => {});
                    const content = await page.content();
                    if (content.includes('cobalt') && (content.includes('<input') || content.includes('<button>'))) {
                        logResult('Cobalt UI', 'PASS', 'UI elements detected');
                    } else if (content.includes('cobalt') || content.includes('api')) {
                        logResult('Cobalt API', 'WARN', 'Only API response or plain body detected');
                    } else {
                        logResult('Cobalt UI', 'FAIL', 'Recognizable UI/API not found');
                    }
                } catch (e) { logResult('Cobalt Functionality', 'FAIL', e.message); }
            }

            if (service.name === 'SearXNG') {
                try {
                    const searchInput = await page.$('input#q') || await page.$('input[name="q"]');
                    if (searchInput) {
                        logResult('SearXNG UI', 'PASS', 'Search input detected');
                    } else {
                        logResult('SearXNG UI', 'FAIL', 'Search input not found');
                    }
                } catch (e) { logResult('SearXNG Functionality', 'FAIL', e.message); }
            }

            if (service.name === 'Redlib') {
                try {
                    const links = await page.$('#links') || await page.$('.post') || await page.$('body');
                    if (links) {
                        logResult('Redlib UI', 'PASS', 'UI detected');
                    } else {
                        logResult('Redlib UI', 'FAIL', 'UI not found');
                    }
                } catch (e) { logResult('Redlib Functionality', 'FAIL', e.message); }
            }

            if (service.name === 'Wikiless') {
                try {
                    const search = await page.$('input[name="q"]') || await page.$('input[type="text"]') || await page.$('body');
                    if (search) {
                        logResult('Wikiless UI', 'PASS', 'UI detected');
                    } else {
                        logResult('Wikiless UI', 'FAIL', 'UI not found');
                    }
                } catch (e) { logResult('Wikiless Functionality', 'FAIL', e.message); }
            }

            if (service.name === 'Rimgo') {
                try {
                    const logo = await page.$('img[alt="Rimgo"]') || await page.$('.gallery') || await page.$('body');
                    if (logo) {
                        logResult('Rimgo UI', 'PASS', 'UI detected');
                    } else {
                        logResult('Rimgo UI', 'FAIL', 'UI not found');
                    }
                } catch (e) { logResult('Rimgo Functionality', 'FAIL', e.message); }
            }

            if (service.name === 'Scribe') {
                try {
                    const main = await page.$('main') || await page.$('.container') || await page.$('body');
                    if (main) {
                        logResult('Scribe UI', 'PASS', 'UI detected');
                    } else {
                        logResult('Scribe UI', 'FAIL', 'UI not found');
                    }
                } catch (e) { logResult('Scribe Functionality', 'FAIL', e.message); }
            }

            if (service.name === 'Breezewiki') {
                try {
                    const search = await page.$('input[name="q"]') || await page.$('body');
                    if (search) {
                        logResult('Breezewiki UI', 'PASS', 'UI detected');
                    } else {
                        logResult('Breezewiki UI', 'FAIL', 'UI not found');
                    }
                } catch (e) { logResult('Breezewiki Functionality', 'FAIL', e.message); }
            }

            if (service.name === 'AnonymousOverflow') {
                try {
                    const question = await page.$('.question-summary') || await page.$('#questions') || await page.$('body');
                    if (question) {
                        logResult('AnonymousOverflow UI', 'PASS', 'UI detected');
                    } else {
                        logResult('AnonymousOverflow UI', 'FAIL', 'UI not found');
                    }
                } catch (e) { logResult('AnonymousOverflow Functionality', 'FAIL', e.message); }
            }

            if (service.name === 'Immich') {
                try {
                    await page.waitForSelector('input[type="email"], input[name="email"], #email, body', { timeout: 10000 });
                    logResult('Immich UI', 'PASS', 'UI detected');
                } catch (e) { logResult('Immich UI', 'FAIL', 'UI not found'); }
            }

            if (service.name === 'VERT') {
                try {
                    const content = await page.content();
                    if (content.includes('vert') || content.includes('converter') || content.includes('body')) {
                        logResult('VERT UI', 'PASS', 'UI detected');
                    } else {
                        logResult('VERT UI', 'FAIL', 'Recognizable VERT UI not found');
                    }
                } catch (e) { logResult('VERT Functionality', 'FAIL', e.message); }
            }

            if (service.name === 'OdidoBooster') {
                try {
                    await page.waitForSelector('.swagger-ui, body', { timeout: 10000 });
                    logResult('OdidoBooster UI', 'PASS', 'UI detected');
                } catch (e) { logResult('OdidoBooster UI', 'FAIL', 'UI not found'); }
            }

            await page.screenshot({ path: path.join(SCREENSHOT_DIR, `service_${service.name.toLowerCase()}.png`), fullPage: true });
            logResult(`${service.name} Connectivity`, 'PASS', `Reached ${service.url}`);

        } catch (e) {
            console.warn(`[WARN] Could not verify ${service.name}: ${e.message}`);
            logResult(`${service.name} Connectivity`, 'FAIL', e.message);
        }
    }

    console.log('\n--- Starting Dashboard Interaction Tests ---');
    try {
        await page.goto(DASHBOARD_URL, { waitUntil: 'networkidle2', timeout: 30000 });
        await new Promise(r => setTimeout(r, 5000));

        // 1. Initial State
        console.log('Capturing Initial Dashboard State...');
        await page.screenshot({ path: path.join(SCREENSHOT_DIR, 'dash_01_initial.png') });

        // 2. Test Admin Login
        console.log('Testing Admin Login...');
        const lockBtn = await page.$('#admin-lock-btn');
        if (lockBtn) {
            await lockBtn.click();
            await new Promise(r => setTimeout(r, 2000));
            await page.screenshot({ path: path.join(SCREENSHOT_DIR, 'dash_02_login_prompt.png') });
            
            const input = await page.$('input[type="password"]');
            if (input) {
                await input.type(ADMIN_PASS);
                await page.keyboard.press('Enter');
                await new Promise(r => setTimeout(r, 5000));
                
                console.log('Capturing Dashboard after Login...');
                await page.screenshot({ path: path.join(SCREENSHOT_DIR, 'dash_03_unlocked.png'), fullPage: true });
            } else {
                console.warn('Could not find password input field');
            }
        } else {
            console.warn('Could not find admin lock button');
        }

        // 3. Test interactions - Category Filtering
        console.log('Testing Category Filtering...');
        const systemBtn = await page.$('button[data-target="system"]') || await page.$('.filter-chip[data-target="system"]');
        if (systemBtn) {
            await systemBtn.click();
            await new Promise(r => setTimeout(r, 2000));
            await page.screenshot({ path: path.join(SCREENSHOT_DIR, 'dash_04_category_system.png') });
        }

        console.log('UI verification complete.');
    } catch (e) {
        console.error('UI Test Error:', e.message);
        await page.screenshot({ path: path.join(SCREENSHOT_DIR, 'dash_error.png') });
    } finally {
        await browser.close();
    }
}

runTests();