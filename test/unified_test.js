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
            await page.goto(service.url, { waitUntil: 'networkidle2', timeout: 20000 });
            await new Promise(r => setTimeout(r, 2000));
            await page.screenshot({ path: path.join(SCREENSHOT_DIR, `service_${service.name.toLowerCase()}.png`) });
            logResult(`${service.name} Connectivity`, 'PASS', `Reached ${service.url}`);

            // Specific Functional Tests
            if (service.name === 'Invidious') {
                try {
                    // Check if search bar exists
                    const searchBar = await page.$('input[name="q"]');
                    if (searchBar) {
                        logResult('Invidious UI', 'PASS', 'Search bar detected');
                        // Optional: Perform a search to check "playback" capability (search results)
                        await searchBar.type('test');
                        await page.keyboard.press('Enter');
                        await page.waitForNavigation({ waitUntil: 'networkidle2', timeout: 10000 });
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
                    // Cobalt usually has an input for URL
                    const urlInput = await page.$('input[type="url"]') || await page.$('input[placeholder*="URL"]');
                    if (urlInput) {
                        logResult('Cobalt UI', 'PASS', 'URL input detected');
                    } else {
                        // Check if it's just the API
                        const content = await page.content();
                        if (content.includes('cobalt') || content.includes('api')) {
                            logResult('Cobalt API', 'PASS', 'Cobalt reachable');
                        } else {
                            logResult('Cobalt UI', 'FAIL', 'Recognizable UI/API not found');
                        }
                    }
                } catch (e) {
                    logResult('Cobalt Functionality', 'FAIL', e.message);
                }
            }

            if (service.name === 'SearXNG') {
                try {
                    const searchInput = await page.$('input#q');
                    if (searchInput) {
                        logResult('SearXNG UI', 'PASS', 'Search input detected');
                    } else {
                        logResult('SearXNG UI', 'FAIL', 'Search input not found');
                    }
                } catch (e) { logResult('SearXNG Functionality', 'FAIL', e.message); }
            }

            if (service.name === 'Redlib') {
                try {
                    const links = await page.$('#links'); // Common id for post list or similar
                    const posts = await page.$('.post'); 
                    if (links || posts) {
                        logResult('Redlib UI', 'PASS', 'Post list detected');
                    } else {
                        logResult('Redlib UI', 'FAIL', 'No post list found');
                    }
                } catch (e) { logResult('Redlib Functionality', 'FAIL', e.message); }
            }

            if (service.name === 'Wikiless') {
                try {
                    const search = await page.$('input[name="q"]');
                    if (search) {
                        logResult('Wikiless UI', 'PASS', 'Search input detected');
                    } else {
                        logResult('Wikiless UI', 'FAIL', 'Search input not found');
                    }
                } catch (e) { logResult('Wikiless Functionality', 'FAIL', e.message); }
            }

            if (service.name === 'Rimgo') {
                try {
                    // Check for gallery or logo
                    const logo = await page.$('img[alt="Rimgo"]') || await page.$('.gallery');
                    if (logo) {
                        logResult('Rimgo UI', 'PASS', 'UI element detected');
                    } else {
                        logResult('Rimgo UI', 'FAIL', 'UI element not found');
                    }
                } catch (e) { logResult('Rimgo Functionality', 'FAIL', e.message); }
            }

            if (service.name === 'Scribe') {
                try {
                    // Check for article list or main container
                    const main = await page.$('main') || await page.$('.container');
                    if (main) {
                        logResult('Scribe UI', 'PASS', 'Main container detected');
                    } else {
                        logResult('Scribe UI', 'FAIL', 'Main container not found');
                    }
                } catch (e) { logResult('Scribe Functionality', 'FAIL', e.message); }
            }

            if (service.name === 'Breezewiki') {
                try {
                    const search = await page.$('input[name="q"]');
                    if (search) {
                        logResult('Breezewiki UI', 'PASS', 'Search input detected');
                    } else {
                        logResult('Breezewiki UI', 'FAIL', 'Search input not found');
                    }
                } catch (e) { logResult('Breezewiki Functionality', 'FAIL', e.message); }
            }

            if (service.name === 'AnonymousOverflow') {
                try {
                    const question = await page.$('.question-summary') || await page.$('#questions');
                    if (question) {
                        logResult('AnonymousOverflow UI', 'PASS', 'Question list detected');
                    } else {
                        logResult('AnonymousOverflow UI', 'FAIL', 'Question list not found');
                    }
                } catch (e) { logResult('AnonymousOverflow Functionality', 'FAIL', e.message); }
            }

            if (service.name === 'Memos') {
                try {
                    const login = await page.$('input[name="username"]') || await page.$('.signin-form');
                    if (login) {
                        logResult('Memos UI', 'PASS', 'Login form detected');
                    } else {
                        logResult('Memos UI', 'FAIL', 'Login form not found');
                    }
                } catch (e) { logResult('Memos Functionality', 'FAIL', e.message); }
            }

            if (service.name === 'Immich') {
                try {
                    const email = await page.$('input[type="email"]');
                    if (email) {
                        logResult('Immich UI', 'PASS', 'Login email input detected');
                    } else {
                        logResult('Immich UI', 'FAIL', 'Login input not found');
                    }
                } catch (e) { logResult('Immich Functionality', 'FAIL', e.message); }
            }

            if (service.name === 'Portainer') {
                try {
                    const user = await page.$('input[name="username"]') || await page.$('input#username');
                    if (user) {
                        logResult('Portainer UI', 'PASS', 'Login username input detected');
                    } else {
                        logResult('Portainer UI', 'FAIL', 'Login input not found');
                    }
                } catch (e) { logResult('Portainer Functionality', 'FAIL', e.message); }
            }

            if (service.name === 'AdGuard') {
                try {
                    const user = await page.$('input[name="username"]') || await page.$('input[type="text"]');
                    if (user) {
                        logResult('AdGuard UI', 'PASS', 'Login input detected');
                    } else {
                        logResult('AdGuard UI', 'FAIL', 'Login input not found');
                    }
                } catch (e) { logResult('AdGuard Functionality', 'FAIL', e.message); }
            }

            if (service.name === 'WireGuard_UI') {
                try {
                    const pass = await page.$('input[type="password"]');
                    if (pass) {
                        logResult('WireGuard UI', 'PASS', 'Password input detected');
                    } else {
                        logResult('WireGuard UI', 'FAIL', 'Password input not found');
                    }
                } catch (e) { logResult('WireGuard UI Functionality', 'FAIL', e.message); }
            }

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
            await new Promise(r => setTimeout(r, 1000));
            
            // Check if password prompt appeared
            await page.screenshot({ path: path.join(SCREENSHOT_DIR, 'dash_02_login_prompt.png') });
            
            // Type password - Assuming there's a password input, usually in a Swal or custom modal
            // We'll try to find any input and type into it
            const input = await page.$('input[type="password"]');
            if (input) {
                await input.type(ADMIN_PASS);
                await page.keyboard.press('Enter');
                await new Promise(r => setTimeout(r, 3000));
                
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
        const systemBtn = await page.$('button[data-category="system"]');
        if (systemBtn) {
            await systemBtn.click();
            await new Promise(r => setTimeout(r, 1000));
            await page.screenshot({ path: path.join(SCREENSHOT_DIR, 'dash_04_category_system.png') });
        }

        // 4. Test interactions - Manage Button
        console.log('Testing Manage/Portainer Button...');
        const manageBtn = await page.$('a[href*="9000"]');
        if (manageBtn) {
            console.log('Found Portainer link');
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