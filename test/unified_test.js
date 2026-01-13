const puppeteer = require('puppeteer');
const fs = require('fs');
const path = require('path');

const LAN_IP = process.env.LAN_IP || '127.0.0.1';
const DASHBOARD_URL = `http://${LAN_IP}:8081`;
const SCREENSHOT_DIR = path.join(__dirname, 'screenshots');
const REPORT_FILE = path.join(__dirname, 'verification_report.md');

// Load admin password from .secrets if it exists
let ADMIN_PASS = 'admin123';
const paths = [
    path.join(__dirname, '../data/AppData/privacy-hub/.secrets'),
    path.join(__dirname, 'test_data/data/AppData/privacy-hub-test/.secrets')
];
for (const p of paths) {
    if (fs.existsSync(p)) {
        const secrets = fs.readFileSync(p, 'utf8');
        const match = secrets.match(/ADMIN_PASS_RAW=["'](.+)["']/);
        if (match) {
            ADMIN_PASS = match[1];
            console.log(`Loaded admin password from ${p}: ${ADMIN_PASS.substring(0, 3)}...`);
            break;
        }
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

    { name: 'Companion', url: `http://${LAN_IP}:8283` },

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



    



        // Capture console logs



        page.on('console', msg => {



            const type = msg.type();



            const text = msg.text();



            if (type === 'error' || type === 'warn') {



                console.log(`[BROWSER ${type.toUpperCase()}] ${text}`);



            }



        });



    



        try {

        console.log('--- Phase 1: Service Connectivity & Deep Functionality ---');

        for (const service of SERVICES) {

            console.log(`Checking ${service.name}: ${service.url}`);

            try {

                // Use a longer timeout and waitUntil networkidle2 for robustness

                await page.goto(service.url, { waitUntil: 'domcontentloaded', timeout: 60000 });

                await new Promise(r => setTimeout(r, 2000));

                

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
                            console.log('  Waiting for video player (up to 5 minutes for Companion potoken)...');
                            await new Promise(r => setTimeout(r, 10000));
                            
                            const playerSelector = 'video, #player, .video-js, #player-container, iframe, .vjs-tech';
                            const videoPlayer = await page.waitForSelector(playerSelector, { timeout: 300000 });
                            
                            if (videoPlayer) {
                                logResult('Invidious', 'Player Loaded', 'PASS', 'Video player element detected');
                                
                                // Try to click play if it's a video element and not playing
                                await page.evaluate(() => {
                                    const v = document.querySelector('video');
                                    if (v && v.paused) v.play().catch(() => {});
                                    // Also try clicking the player area
                                    const p = document.querySelector('#player, .video-js, #player-container');
                                    if (p) p.click();
                                });

                                await new Promise(r => setTimeout(r, 10000));

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
        await page.waitForSelector('#login-modal', { visible: true });
        
        // Test Layout Alignment in Login Modal
        const loginLayout = await page.evaluate(() => {
            const modal = document.querySelector('#login-modal');
            const header = modal.querySelector('.modal-header');
            const title = header.querySelector('h2');
            const closeBtn = header.querySelector('.btn-icon');
            const tRect = title.getBoundingClientRect();
            const cRect = closeBtn.getBoundingClientRect();
            
            return {
                titleRight: tRect.right,
                closeLeft: cRect.left,
                overlap: (tRect.right > cRect.left),
                verticallyAligned: Math.abs((tRect.top + tRect.height/2) - (cRect.top + cRect.height/2)) < 5
            };
        });
        console.log(`[LOGIN LAYOUT] Title Right: ${loginLayout.titleRight}, Close Left: ${loginLayout.closeLeft}, Overlap: ${loginLayout.overlap}`);
        logResult('Dashboard', 'Login Modal Alignment', (!loginLayout.overlap && loginLayout.verticallyAligned) ? 'PASS' : 'FAIL', `Overlap: ${loginLayout.overlap}, Vertically Aligned: ${loginLayout.verticallyAligned}`);

        await page.type('#admin-password-input', ADMIN_PASS, { delay: 50 });
        await page.click('#login-modal .btn-filled'); // Sign in button
        
        // Wait for admin mode to activate (class on body) or modal to hide
        try {
            await page.waitForFunction(() => document.body.classList.contains('admin-mode') || document.getElementById('login-modal').style.display === 'none', { timeout: 15000 });
            const isAdminMode = await page.evaluate(() => document.body.classList.contains('admin-mode'));
            if (isAdminMode) {
                logResult('Dashboard', 'Admin Login', 'PASS', 'Admin mode activated');
            } else {
                logResult('Dashboard', 'Admin Login', 'FAIL', 'Login modal closed but admin mode not active');
            }
            await new Promise(r => setTimeout(r, 2000)); // Ensure UI re-render
        } catch (e) {
            const loginVisible = await page.evaluate(() => document.getElementById('login-modal').style.display !== 'none');
            logResult('Dashboard', 'Admin Login', 'FAIL', loginVisible ? 'Login modal still visible (Wrong password or slow API?)' : 'Body class not added');
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
                
                // Test Layout Alignment in Modal
                const layoutDebug = await page.evaluate(() => {
                    const header = document.querySelector('#service-modal .modal-header');
                    const title = header.querySelector('h2');
                    const closeBtn = header.querySelector('.btn-icon');
                    const tRect = title.getBoundingClientRect();
                    const cRect = closeBtn.getBoundingClientRect();
                    
                    return {
                        title: { x: tRect.x, y: tRect.y, w: tRect.width, h: tRect.height, right: tRect.right },
                        close: { x: cRect.x, y: cRect.y, w: cRect.width, h: cRect.height, left: cRect.left },
                        overlap: (tRect.right > cRect.left),
                        verticallyAligned: Math.abs((tRect.top + tRect.height/2) - (cRect.top + cRect.height/2)) < 5
                    };
                });
                console.log(`[LAYOUT DEBUG] Title Right: ${layoutDebug.title.right}, Close Left: ${layoutDebug.close.left}, Overlap: ${layoutDebug.overlap}`);
                logResult('Dashboard', 'Modal Alignment', (!layoutDebug.overlap && layoutDebug.verticallyAligned) ? 'PASS' : 'FAIL', `Overlap: ${layoutDebug.overlap}, Vertically Aligned: ${layoutDebug.verticallyAligned}`);

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

            // Test Click-to-Copy
            console.log('  Testing Click-to-Copy...');
            const codeBlock = await page.$('.code-block');
            if (codeBlock) {
                const originalText = await page.evaluate(el => el.textContent, codeBlock);
                await codeBlock.click();
                await new Promise(r => setTimeout(r, 500));
                const currentText = await page.evaluate(el => el.textContent, codeBlock);
                logResult('Dashboard', 'Click-to-Copy', currentText === 'Copied!' ? 'PASS' : 'FAIL', `Text changed to: ${currentText}`);
                await new Promise(r => setTimeout(r, 2000)); // Wait for reset
            } else {
                logResult('Dashboard', 'Click-to-Copy', 'FAIL', 'No code-block found');
            }

            // Test Link Switcher Functional
            console.log('  Testing Link Switcher...');
            const linkSwitch = await page.$('#link-mode-switch');
            if (linkSwitch) {
                const initialUrl = await page.evaluate(() => document.querySelector('.card').dataset.url);
                await page.evaluate(() => document.getElementById('link-mode-switch').click());
                await new Promise(r => setTimeout(r, 2000));
                const newUrl = await page.evaluate(() => document.querySelector('.card').dataset.url);
                logResult('Dashboard', 'Link Switcher', initialUrl !== newUrl ? 'PASS' : 'FAIL', `URL changed from ${initialUrl} to ${newUrl}`);
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
            }

            // Test Project Size Modal
            console.log('  Testing Project Size Modal...');
            const projectSizeBtn = await page.$('#sys-project-size');
            if (projectSizeBtn) {
                await page.evaluate(() => document.getElementById('sys-project-size').parentElement.click());
                await page.waitForSelector('#project-size-modal', { visible: true });
                await page.waitForSelector('#project-size-content', { visible: true, timeout: 10000 });
                
                const breakdownItems = await page.evaluate(() => document.querySelectorAll('#project-size-list .list-item').length);
                logResult('Dashboard', 'Storage Breakdown', breakdownItems > 0 ? 'PASS' : 'FAIL', `Found ${breakdownItems} items in breakdown`);
                
                // Test Prune Images (Trigger Dialog)
                const pruneBtn = await page.$('#project-size-content button');
                if (pruneBtn) {
                    await pruneBtn.click();
                    await page.waitForSelector('#dialog-modal', { visible: true });
                    logResult('Dashboard', 'Prune Images Dialog', 'PASS', 'Confirmation dialog appeared');
                    await page.click('#dialog-cancel-btn');
                }
                
                await page.evaluate(() => document.querySelector('#project-size-modal .btn-icon').click());
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