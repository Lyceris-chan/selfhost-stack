const puppeteer = require('puppeteer');
const fs = require('fs');
const path = require('path');

const LAN_IP = process.env.LAN_IP || '127.0.0.1';
const DASHBOARD_URL = `http://${LAN_IP}:8081`;
const SCREENSHOT_DIR = path.join(__dirname, 'screenshots');
const REPORT_FILE = path.join(__dirname, 'verification_report.md');

// Load admin password from .secrets if it exists
let ADMIN_PASS = 'admin123';
const secretsPath = path.join(__dirname, 'test_data/data/AppData/privacy-hub-test/.secrets');
if (fs.existsSync(secretsPath)) {
    const secrets = fs.readFileSync(secretsPath, 'utf8');
    const match = secrets.match(/ADMIN_PASS_RAW="([^"]+)"/);
    if (match) {
        ADMIN_PASS = match[1];
        console.log(`Loaded admin password from .secrets: ${ADMIN_PASS.substring(0, 3)}...`);
    }
}

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
    { name: 'Companion', url: `http://${LAN_IP}:8283/companion` },
    { name: 'OdidoBooster', url: `http://${LAN_IP}:8085/docs` },
];

const results = [];

function logResult(category, test, outcome, details = '') {
    const timestamp = new Date().toISOString();
    const result = { timestamp, category, test, outcome, details };
    results.push(result);
    console.log(`[${outcome}] ${category} > ${test}: ${details}`);
}

async function runTests() {
    if (!fs.existsSync(SCREENSHOT_DIR)) fs.mkdirSync(SCREENSHOT_DIR);

    const browser = await puppeteer.launch({
        headless: 'new',
        args: ['--no-sandbox', '--disable-setuid-sandbox']
    });

    const page = await browser.newPage();
    await page.setViewport({ width: 1440, height: 1200 });

    try {
        console.log('--- Phase 1: Service Connectivity & Deep Functionality ---');
        for (const service of SERVICES) {
            console.log(`Checking ${service.name}: ${service.url}`);
            try {
                await page.goto(service.url, { waitUntil: 'networkidle2', timeout: 60000 });
                await new Promise(r => setTimeout(r, 2000));
                
                await page.waitForSelector('body', { timeout: 20000 });
                logResult('Connectivity', service.name, 'PASS', `Reached ${service.url}`);

                if (service.name === 'Invidious') {
                    try {
                        console.log('  Testing Invidious Search & Playback...');
                        await page.waitForSelector('input[name="q"], input[type="text"]', { timeout: 30000 });
                        const searchBar = await page.$('input[name="q"]') || await page.$('input[type="text"]');
                        await searchBar.type('Big Buck Bunny 60fps');
                        await page.keyboard.press('Enter');
                        
                        await page.waitForSelector('a[href*="watch?v="]', { timeout: 30000 });
                        const videoLink = await page.$('a[href*="watch?v="]');
                        
                        if (videoLink) {
                            logResult('Invidious', 'Search', 'PASS', 'Search results found');
                            const videoUrl = await page.evaluate(el => el.href, videoLink);
                            console.log(`  Navigating to video: ${videoUrl}`);
                            
                            await page.goto(videoUrl, { waitUntil: 'networkidle2', timeout: 60000 });
                            await new Promise(r => setTimeout(r, 5000));
                            
                            const playerSelector = 'video, #player, .video-js, #player-container, iframe, .vjs-tech';
                            const videoPlayer = await page.waitForSelector(playerSelector, { timeout: 120000 });
                            
                            if (videoPlayer) {
                                logResult('Invidious', 'Player Loaded', 'PASS', 'Video player element detected');
                                
                                const playbackMetrics = await page.evaluate(async () => {
                                    const v = document.querySelector('video');
                                    if (!v) return { error: 'No video element' };
                                    const start = v.currentTime;
                                    await new Promise(r => setTimeout(r, 5000));
                                    return { start, end: v.currentTime, playing: v.currentTime > start, paused: v.paused };
                                });

                                if (playbackMetrics.playing) {
                                    logResult('Invidious', 'Playback Progress', 'PASS', `Video playing: ${playbackMetrics.start.toFixed(1)}s -> ${playbackMetrics.end.toFixed(1)}s`);
                                } else {
                                    logResult('Invidious', 'Playback Progress', 'WARN', playbackMetrics.error || 'Video element found but not progressing (might be paused or buffering)');
                                }
                            } else {
                                logResult('Invidious', 'Player Loaded', 'FAIL', 'Video player not found');
                            }
                        } else {
                            logResult('Invidious', 'Search', 'FAIL', 'No video results found');
                        }
                    } catch (e) {
                        logResult('Invidious', 'Functionality', 'FAIL', e.message);
                    }
                }

                await page.screenshot({ path: path.join(SCREENSHOT_DIR, `service_${service.name.toLowerCase()}.png`), fullPage: true });

            } catch (e) {
                logResult('Connectivity', service.name, 'FAIL', e.message);
            }
        }

        console.log('\n--- Phase 2: Dashboard Interaction ---');
        await page.goto(DASHBOARD_URL, { waitUntil: 'networkidle2' });
        await new Promise(r => setTimeout(r, 5000));

        // Test Guest mode filtering
        const infrastructureSelector = '.filter-chip[data-target="system"]';
        const infrastructureChip = await page.$(infrastructureSelector);
        
        if (infrastructureChip) {
            await infrastructureChip.click();
            await new Promise(r => setTimeout(r, 2000));
            const isActive = await page.evaluate(el => el.classList.contains('active'), infrastructureChip);
            logResult('Dashboard', 'Filter Toggle', isActive ? 'PASS' : 'FAIL', 'Infrastructure category activated');
        } else {
             logResult('Dashboard', 'Filter Toggle', 'FAIL', 'Infrastructure chip not found');
        }

        // Admin Login
        console.log('  Testing Admin Login...');
        await page.click('#admin-lock-btn');
        await page.waitForSelector('#admin-password-input', { visible: true });
        await page.type('#admin-password-input', ADMIN_PASS);
        await page.keyboard.press('Enter');
        
        // Wait for admin mode to activate (class on body)
        try {
            await page.waitForFunction(() => document.body.classList.contains('admin-mode'), { timeout: 10000 });
            logResult('Dashboard', 'Admin Login', 'PASS', 'Admin mode activated');
            await new Promise(r => setTimeout(r, 2000)); // Ensure UI re-render
        } catch (e) {
            const loginVisible = await page.evaluate(() => document.getElementById('login-modal').style.display !== 'none');
            logResult('Dashboard', 'Admin Login', 'FAIL', loginVisible ? 'Login modal still visible (Wrong password?)' : 'Body class not added');
            await page.screenshot({ path: path.join(SCREENSHOT_DIR, 'debug_login_fail.png') });
        }

        const isAdmin = await page.evaluate(() => document.body.classList.contains('admin-mode'));
        if (isAdmin) {
            // Test Update Check
            console.log('  Testing Update Check...');
            await page.waitForSelector('#update-all-btn', { visible: true, timeout: 10000 });
            await page.click('#update-all-btn');
            await page.waitForSelector('#update-selection-modal', { visible: true });
            logResult('Dashboard', 'Update Modal', 'PASS', 'Update selection modal opened');
            await page.click('#update-selection-modal .btn-icon'); // Close it

            // Test Invidious Settings Modal
            console.log('  Testing Invidious Settings...');
            const invidiousSettingsBtn = await page.$('[data-container="invidious"] .settings-btn');
            if (invidiousSettingsBtn) {
                await invidiousSettingsBtn.click();
                await page.waitForSelector('#service-modal', { visible: true });
                logResult('Dashboard', 'Settings Modal', 'PASS', 'Invidious management modal opened');
                
                // Test Update Individual Service
                const updateBtn = await page.evaluateHandle(() => {
                    return Array.from(document.querySelectorAll('#modal-actions button')).find(b => b.textContent.includes('Update Service'));
                });
                if (updateBtn && updateBtn.asElement()) {
                    await updateBtn.asElement().click();
                    logResult('Dashboard', 'Service Update', 'PASS', 'Update command sent for Invidious');
                    // Wait a bit for the snackbar/status change
                    await new Promise(r => setTimeout(r, 2000));
                }

                const migrateBtn = await page.evaluateHandle(() => {
                    return Array.from(document.querySelectorAll('#modal-actions button')).find(b => b.textContent.includes('Migrate Database'));
                });
                
                if (migrateBtn && migrateBtn.asElement()) {
                    await migrateBtn.asElement().click();
                    await page.waitForSelector('#dialog-modal', { visible: true });
                    logResult('Dashboard', 'Migrate Dialog', 'PASS', 'Confirmation dialog appeared');
                    await page.click('#dialog-cancel-btn');
                }
                await page.evaluate(() => document.querySelector('#service-modal .btn-icon').click());
            }

            // Test Session Cleanup Toggle
            const cleanupSwitch = await page.$('#session-cleanup-switch');
            if (cleanupSwitch) {
                const initialState = await page.evaluate(el => el.classList.contains('active'), cleanupSwitch);
                await page.evaluate(() => document.getElementById('session-cleanup-switch').click());
                await new Promise(r => setTimeout(r, 2000));
                const newState = await page.evaluate(el => el.classList.contains('active'), cleanupSwitch);
                logResult('Dashboard', 'Session Policy Toggle', newState !== initialState ? 'PASS' : 'FAIL', `Toggled cleanup: ${initialState} -> ${newState}`);
            }

            // Test Log Filtering
            console.log('  Testing Log Filtering...');
            const logsChip = await page.$('.filter-chip[data-target="logs"]');
            if (logsChip) {
                await logsChip.click();
                await new Promise(r => setTimeout(r, 2000));
                
                const logContainerVisible = await page.evaluate(() => {
                    const section = document.querySelector('section[data-category="logs"]');
                    return section && section.style.display !== 'none';
                });
                
                if (logContainerVisible) {
                    logResult('Dashboard', 'Log Visibility', 'PASS', 'Logs section visible');
                    
                    // Try to filter by level
                    await page.select('#log-filter-level', 'INFO');
                    await new Promise(r => setTimeout(r, 1000));
                    let logCount = await page.evaluate(() => document.querySelectorAll('#log-container .log-entry').length);
                    logResult('Dashboard', 'Log Level Filter', 'PASS', `Filtered INFO logs: ${logCount} entries found`);
                } else {
                    logResult('Dashboard', 'Log Visibility', 'FAIL', 'Logs section NOT visible after click');
                }
            } else {
                logResult('Dashboard', 'Log Interaction', 'FAIL', 'Logs filter chip not found');
            }
        }

        console.log('\n--- Phase 3: Portainer Integration ---');
        try {
            await page.goto(`http://${LAN_IP}:9000`, { waitUntil: 'networkidle2', timeout: 60000 });
            await page.waitForSelector('input[name="password"], #password', { timeout: 20000 });
            
            // Portainer might ask to set up admin password first if it's a fresh volume
            const setupHeader = await page.evaluate(() => document.body.innerText.includes('Create administrator user'));
            if (setupHeader) {
                console.log('  Setting up Portainer admin user...');
                await page.type('#password', 'portainer123');
                await page.type('#confirm_password', 'portainer123');
                await page.click('button[type="submit"]');
            } else {
                console.log('  Logging into Portainer...');
                await page.type('#username', 'admin');
                await page.type('#password', 'portainer123');
                await page.click('button[type="submit"]');
            }
            
            await page.waitForNavigation({ waitUntil: 'networkidle2' });
            const loggedIn = await page.evaluate(() => document.body.innerText.includes('Logout') || document.body.innerText.includes('Dashboard'));
            logResult('Portainer', 'Login', loggedIn ? 'PASS' : 'FAIL', loggedIn ? 'Logged into Portainer successfully' : 'Login failed');
            await page.screenshot({ path: path.join(SCREENSHOT_DIR, 'portainer_dashboard.png') });
        } catch (e) {
            logResult('Portainer', 'Integration', 'FAIL', e.message);
        }

    } catch (e) {
        console.error('Test Suite Error:', e);
        logResult('Global', 'Suite Execution', 'FAIL', e.message);
    } finally {
        await browser.close();
        await generateReport();
    }
}

async function generateReport() {
    console.log('\n--- Generating Comprehensive Report ---');
    const timestamp = new Date().toLocaleString();
    let report = `# Verification Report - ${timestamp}\n\n`;

    const summary = {
        total: results.length,
        pass: results.filter(r => r.outcome === 'PASS').length,
        fail: results.filter(r => r.outcome === 'FAIL').length,
        warn: results.filter(r => r.outcome === 'WARN').length
    };

    report += `## Summary\n`;
    report += `- **Total Tests:** ${summary.total}\n`;
    report += `- **Passed:** ✅ ${summary.pass}\n`;
    report += `- **Failed:** ❌ ${summary.fail}\n`;
    report += `- **Warnings:** ⚠️ ${summary.warn}\n\n`;

    const categories = [...new Set(results.map(r => r.category))];
    for (const cat of categories) {
        report += `### ${cat}\n`;
        report += `| Test | Outcome | Details |\n`;
        report += `|------|---------|---------|\n`;
        const catResults = results.filter(r => r.category === cat);
        for (const res of catResults) {
            const icon = res.outcome === 'PASS' ? '✅' : (res.outcome === 'FAIL' ? '❌' : '⚠️');
            report += `| ${res.test} | ${icon} ${res.outcome} | ${res.details} |\n`;
        }
        report += `\n`;
    }

    fs.writeFileSync(REPORT_FILE, report);
    console.log(`Report generated: ${REPORT_FILE}`);
}

runTests();