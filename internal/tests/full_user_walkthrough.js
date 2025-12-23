const puppeteer = require('puppeteer');
const path = require('path');

(async () => {
    console.log('🚀 Starting Comprehensive M3 UI & Interaction Test...');
    const browser = await puppeteer.launch({
        args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-web-security'],
        headless: true
    });
    const page = await browser.newPage();
    const DASHBOARD_URL = 'file://' + path.resolve('/DATA/AppData/privacy-hub/dashboard.html');

    // 1. Setup Request Interception for Mocks (Ensuring "Online" status)
    await page.setRequestInterception(true);
    page.on('request', request => {
        const url = request.url();
        if (url.includes('/api/containers')) {
            request.respond({
                content: 'application/json',
                body: JSON.stringify({
                    containers: {
                        "invidious": { id: "inv-id", state: "running", hardened: true },
                        "adguard": { id: "adg-id", state: "running" },
                        "gluetun": { id: "glu-id", state: "running" },
                        "portainer": { id: "por-id", state: "running" },
                        "watchtower": { id: "wat-id", state: "running" },
                        "memos": { id: "mem-id", state: "running" },
                        "rimgo": { id: "rim-id", state: "running" },
                        "breezewiki": { id: "bre-id", state: "running" },
                        "unbound": { id: "unb-id", state: "running" }
                    }
                })
            });
        } else if (url.includes('/api/services')) {
            request.respond({
                content: 'application/json',
                body: JSON.stringify({
                    services: {
                        "invidious": { name: "Invidious", category: "apps", order: 1 },
                        "adguard": { name: "AdGuard Home", category: "dns", order: 2 },
                        "gluetun": { name: "VPN Gateway", category: "system", order: 3 },
                        "portainer": { name: "Infrastructure", category: "system", order: 4 },
                        "watchtower": { name: "Auto-Updates", category: "system", order: 5 },
                        "memos": { name: "Memos", category: "apps", order: 6 },
                        "rimgo": { name: "Rimgo", category: "apps", order: 7 },
                        "breezewiki": { name: "BreezeWiki", category: "apps", order: 8 },
                        "unbound": { name: "Unbound", category: "dns", order: 9 }
                    }
                })
            });
        } else if (url.includes('/api/status')) {
             request.respond({
                 content: 'application/json',
                 body: JSON.stringify({ 
                    success: true,
                    status: "Healthy",
                    services: {
                        "invidious": "healthy",
                        "adguard": "healthy",
                        "gluetun": "healthy",
                        "portainer": "healthy",
                        "watchtower": "healthy",
                        "memos": "healthy",
                        "rimgo": "healthy",
                        "breezewiki": "healthy",
                        "unbound": "healthy"
                    }
                 })
             });
        } else if (url.includes('/api/profiles')) {
            request.respond({
                content: 'application/json',
                body: JSON.stringify({ profiles: [] })
            });
        } else if (url.includes('/api/') || url.includes('/odido-api/')) {
            request.respond({ 
                content: 'application/json', 
                body: JSON.stringify({ success: true, status: "Healthy", containers: {}, updates: {}, services: {}, profiles: [] }) 
            });
        } else {
            request.continue();
        }
    });

    page.on('console', msg => {
        if (!msg.text().includes('EventSource')) console.log('PAGE:', msg.text());
    });

    try {
        await page.setViewport({ width: 1440, height: 900 });
        await page.goto(DASHBOARD_URL, { waitUntil: 'load' });

        // Manually trigger updates to ensure our mocks are applied immediately
        await page.evaluate(async () => {
            if (typeof renderDynamicGrid === 'function') await renderDynamicGrid();
            if (typeof fetchStatus === 'function') await fetchStatus();
            if (typeof fetchContainerIds === 'function') await fetchContainerIds();
        });

        console.log('--- Phase 1: Initial Render & M3 Compliance ---');
        await page.waitForSelector('.card', { timeout: 10000 });
        
        const cardCount = await page.$$eval('.card', els => els.length);
        console.log(`✅ Found ${cardCount} cards on page.`);

        // Verify M3 Card Styling
        const cardStyle = await page.$eval('.card', el => {
            const style = window.getComputedStyle(el);
            return {
                radius: style.borderRadius,
                shadow: style.boxShadow,
                bg: style.backgroundColor
            };
        });
        console.log(`   Card Radius: ${cardStyle.radius} (Expected: ~28px for Extra Large)`);
        console.log(`   Card Shadow: ${cardStyle.shadow.includes('none') ? 'MISSING' : 'PRESENT'}`);

        // Verify Expansion (Auto-fit)
        const rowWidth = await page.$eval('#grid-all', el => el.offsetWidth);
        const cardWidth = await page.$eval('#grid-all .card', el => el.offsetWidth);
        console.log(`   Grid Width: ${rowWidth}px, Card Width: ${cardWidth}px`);
        if (cardWidth > rowWidth / 4) console.log('✅ PASS: Cards are expanding to fill row (M3 auto-fit).');

        console.log('--- Phase 2: Service Status (All Online) ---');
        // Wait for polling (fetchStatus is called on load, but we wait to be sure)
        await new Promise(r => setTimeout(r, 5000));
        const statuses = await page.$$eval('.status-text', els => els.map(e => e.textContent));
        const allOnline = statuses.every(s => s === 'Connected' || s === 'Healthy' || s === 'Running');
        if (allOnline) console.log('✅ PASS: All services showing as online.');
        else console.warn(`⚠️ Some services offline: ${statuses.filter(s => s !== 'Connected').join(', ')}`);

        console.log('--- Phase 3: Toggling Settings & Modes ---');
        
        // Theme Toggle
        const themeBtn = await page.$('.theme-toggle');
        if (themeBtn) {
            await themeBtn.click();
            const isLight = await page.evaluate(() => document.documentElement.classList.contains('light-mode'));
            console.log(`✅ Theme toggled. Light mode: ${isLight}`);
            await themeBtn.click(); // Toggle back
        }

        // Privacy Mode Toggle
        const privacyBtn = await page.$('#privacy-switch');
        if (privacyBtn) {
            await privacyBtn.click();
            const isPrivate = await page.evaluate(() => document.body.classList.contains('privacy-mode'));
            console.log(`✅ Privacy Mode toggled: ${isPrivate}`);
            await privacyBtn.click(); // Toggle back
        }

        // Filter Chips Walkthrough
        const filters = ['apps', 'system', 'dns', 'tools', 'all'];
        for (const f of filters) {
            await page.click(`.filter-chip[data-target="${f}"]`);
            await new Promise(r => setTimeout(r, 300));
            const active = await page.$eval(`.filter-chip[data-target="${f}"]`, el => el.classList.contains('active'));
            console.log(`✅ Filter '${f}' active: ${active}`);
        }

        console.log('--- Phase 4: Admin Mode Interactions ---');
        // Enter Admin Mode (Mocked)
        await page.evaluate(() => {
            isAdmin = true;
            sessionStorage.setItem('is_admin', 'true');
            if (typeof updateAdminUI === 'function') updateAdminUI();
        });
        await new Promise(r => setTimeout(r, 1000)); // Wait for DOM update
        console.log('   Entered Admin Mode.');

        // Verify Admin-only elements
        const logsFilter = await page.$('.filter-chip[data-target="logs"]');
        const logsVisible = await page.evaluate(el => window.getComputedStyle(el).display !== 'none', logsFilter);
        console.log(`✅ Admin Filter 'Logs' visible: ${logsVisible}`);

        // Wait for settings button to be visible
        await page.waitForFunction(() => {
            const btn = document.querySelector('.settings-btn');
            return btn && window.getComputedStyle(btn).display !== 'none';
        }, { timeout: 5000 });

        // Open a Service Settings Modal
        const settingsBtn = await page.$('.settings-btn');
        if (settingsBtn) {
            await settingsBtn.evaluate(b => b.click());
            await page.waitForFunction(() => {
                const modal = document.getElementById('service-modal');
                return modal && window.getComputedStyle(modal).display !== 'none';
            }, { timeout: 5000 });
            console.log('✅ Service Settings Modal opened.');
            
            // Close modal
            await page.evaluate(() => {
                if (typeof closeServiceModal === 'function') closeServiceModal();
            });
            await new Promise(r => setTimeout(r, 500));
            const modalVisible = await page.evaluate(() => {
                const modal = document.getElementById('service-modal');
                return modal && window.getComputedStyle(modal).display !== 'none';
            });
            console.log(`✅ Modal closed: ${!modalVisible}`);
        }

        console.log('--- Phase 5: Final Layout Integrity ---');
        await page.click('.filter-chip[data-target="all"]');
        const overlaps = await page.evaluate(() => {
            const elements = Array.from(document.querySelectorAll('.card, .filter-chip, .btn, h1, .section-label'));
            const results = [];
            for (let i = 0; i < elements.length; i++) {
                for (let j = i + 1; j < elements.length; j++) {
                    const r1 = elements[i].getBoundingClientRect();
                    const r2 = elements[j].getBoundingClientRect();
                    const overlap = !(r1.right < r2.left || r1.left > r2.right || r1.bottom < r2.top || r1.top > r2.bottom);
                    if (overlap && !elements[i].contains(elements[j]) && !elements[j].contains(elements[i])) {
                        if (r1.width > 0 && r1.height > 0 && r2.width > 0 && r2.height > 0) {
                            results.push(`${elements[i].className} overlaps with ${elements[j].className}`);
                        }
                    }
                }
            }
            return results;
        });

        if (overlaps.length === 0) console.log('✅ PASS: No UI overlaps detected.');
        else console.error(`❌ FAIL: Detected ${overlaps.length} overlaps.`);

        await page.screenshot({ path: 'internal/tests/final_full_walkthrough.png', fullPage: true });
        console.log('📸 Final screenshot saved to internal/tests/final_full_walkthrough.png');

    } catch (e) {
        console.error('❌ CRITICAL ERROR:', e);
        process.exit(1);
    } finally {
        await browser.close();
    }
})();
