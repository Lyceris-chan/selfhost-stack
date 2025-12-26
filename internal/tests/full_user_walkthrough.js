const puppeteer = require('puppeteer');
const path = require('path');

(async () => {
    console.log('🚀 Starting Comprehensive M3 UI & Interaction Test...');
    const browser = await puppeteer.launch({
        args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-web-security'],
        headless: true,
        protocolTimeout: 120000
    });
    const page = await browser.newPage();
    const DASHBOARD_URL = process.env.DASHBOARD_URL || 'http://localhost:8081';
    const reportPath = path.resolve(__dirname, 'WALKTHROUGH_REPORT.md');
    const screenshotPath = path.resolve(__dirname, 'final_full_walkthrough.png');

    const servicesList = [
        "invidious", "redlib", "wikiless", "rimgo", "breezewiki", 
        "anonymousoverflow", "scribe", "memos", "vert", 
        "adguard", "portainer", "wg-easy"
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
        adguard: 'http://127.0.0.1:8083',
        portainer: 'http://127.0.0.1:9000',
        "wg-easy": 'http://127.0.0.1:51821'
    };

    // 1. Setup Request Interception for Mocks (Ensuring "Online" status)
    await page.setRequestInterception(true);
    page.on('request', request => {
        const url = request.url();
        if (url.includes('/api/containers')) {
            const containers = {};
            servicesList.forEach(s => {
                containers[s] = { id: s + "-id", state: "running", hardened: true };
            });
            request.respond({
                contentType: 'application/json',
                body: JSON.stringify({ containers })
            });
        } else if (url.includes('/api/services')) {
            const services = {};
            servicesList.forEach((s, i) => {
                services[s] = {
                    name: s.charAt(0).toUpperCase() + s.slice(1),
                    category: (i < 8 ? "apps" : (i === 8 ? "tools" : "system")),
                    order: i * 10,
                    url: serviceUrls[s] || ""
                };
            });
            request.respond({
                contentType: 'application/json',
                body: JSON.stringify({ services })
            });
        } else if (url.includes('/api/status')) {
             const services = {};
             servicesList.forEach(s => { services[s] = "healthy"; });
             request.respond({
                 contentType: 'application/json',
                 body: JSON.stringify({
                    success: true,
                    gluetun: { status: "up", healthy: true },
                    services
                 })
             });        
        } else if (url.includes('/api/profiles')) {
            request.respond({
                contentType: 'application/json',
                body: JSON.stringify({ profiles: [] })
            });
        } else if (url.includes('/api/') || url.includes('/odido-api/')) {
            request.respond({
                contentType: 'application/json', 
                body: JSON.stringify({ success: true, status: "Healthy", containers: {}, updates: {}, services: {}, profiles: [] })
            });
        } else {
            request.continue();
        }
    });

    page.on('console', async msg => {
        if (msg.text().includes('EventSource')) return;
        const args = await Promise.all(msg.args().map(arg => arg.jsonValue().catch(() => arg.toString())));
        console.log('PAGE:', ...args);
    });

    const report = {
        timestamp: new Date().toISOString(),
        steps: [],
        overall: "FAIL"
    };

    const logStep = (step, status, details = "") => {
        console.log(`[${status}] ${step} ${details ? ': ' + details : ''}`);
        report.steps.push({ step, status, details });
    };

    try {
        await page.setViewport({ width: 1440, height: 900 });
        await page.goto(DASHBOARD_URL, { waitUntil: 'networkidle2' });

        // Initial load triggers renderDynamicGrid and fetchStatus automatically via DOMContentLoaded
        
        // Wait until at least one card is rendered
        await page.waitForSelector('.card[data-container]', { timeout: 15000 });

        // Manually trigger fetchStatus once more to be sure it hits our mocks immediately
        await page.evaluate(async () => {
            if (typeof fetchStatus === 'function') await fetchStatus();
        });

        const cardsCount = await page.$$eval('.card[data-container]', els => els.length);
        logStep("Initial Render", "PASS", `Found ${cardsCount} dynamic cards`);

        // Wait until at least one status text is in a valid state
        await page.waitForFunction(() => {
            const statusTexts = Array.from(document.querySelectorAll('.card[data-container] .status-text'));
            if (statusTexts.length === 0) return false;
            const validStates = ['Connected', 'Healthy', 'Running', 'Optimal'];
            return statusTexts.some(el => validStates.includes(el.textContent.trim()));
        }, { timeout: 20000 });

        const statusTexts = await page.$$eval('.card[data-container] .status-text', els => els.map(el => el.textContent.trim()));
        const validStates = ['Connected', 'Healthy', 'Running', 'Optimal'];
        const onlineCount = statusTexts.filter(text => validStates.includes(text)).length;
        logStep("Service Status", onlineCount > 0 ? "PASS" : "FAIL", `Online: ${onlineCount}/${statusTexts.length}`);

        // Verify Expansion (Auto-fit)
        const rowWidth = await page.$eval('#grid-all', el => el.offsetWidth);
        const cardWidth = await page.$eval('#grid-all .card', el => el.offsetWidth);
        if (cardWidth >= (rowWidth / 4) - 32) logStep("M3 Auto-fit", "PASS", `Card width ${cardWidth}px fills grid`);
        else logStep("M3 Auto-fit", "FAIL", `Card width ${cardWidth}px too small for grid ${rowWidth}px`);

        // Theme Toggle
        const themeBtn = await page.$('.theme-toggle');
        if (themeBtn) {
            const startTheme = await page.evaluate(() => document.documentElement.classList.contains('light-mode'));
            await page.evaluate(() => {
                const btn = document.querySelector('.theme-toggle');
                if (btn) btn.click();
            });
            const endTheme = await page.evaluate(() => document.documentElement.classList.contains('light-mode'));
            logStep("Theme Toggle", startTheme !== endTheme ? "PASS" : "FAIL", `Start: ${startTheme}, End: ${endTheme}`);
            await page.evaluate(() => {
                const btn = document.querySelector('.theme-toggle');
                if (btn) btn.click();
            });
        }

        // Privacy Mode Toggle
        const privacyBtn = await page.$('#privacy-switch');
        if (privacyBtn) {
            await page.evaluate(() => {
                const btn = document.querySelector('#privacy-switch');
                if (btn) btn.click();
            });
            const isPrivate = await page.evaluate(() => document.body.classList.contains('privacy-mode'));
            logStep("Privacy Mode", isPrivate ? "PASS" : "FAIL", "Sensitive info hidden");
            await page.evaluate(() => {
                const btn = document.querySelector('#privacy-switch');
                if (btn) btn.click();
            });
        }

        // Filter Chips Walkthrough
        const filters = ['apps', 'system', 'dns', 'tools', 'all'];
        for (const f of filters) {
            await page.evaluate((filter) => {
                const chip = document.querySelector(`.filter-chip[data-target="${filter}"]`);
                if (chip) chip.click();
            }, f);
            await new Promise(r => setTimeout(r, 300));
            const active = await page.$eval(`.filter-chip[data-target="${f}"]`, el => el.classList.contains('active'));
            logStep(`Filter Chip [${f}]`, active ? "PASS" : "FAIL");
        }

        // Enter Admin Mode (Mocked)
        await page.evaluate(() => {
            isAdmin = true;
            sessionStorage.setItem('is_admin', 'true');
            if (typeof updateAdminUI === 'function') updateAdminUI();
        });
        await new Promise(r => setTimeout(r, 1000));
        
        const logsFilter = await page.$('.filter-chip[data-target="logs"]');
        const logsVisible = await page.evaluate(el => window.getComputedStyle(el).display !== 'none', logsFilter);
        logStep("Admin Mode", logsVisible ? "PASS" : "FAIL", "Admin controls visible");

        // Open a Service Settings Modal
        const settingsBtn = await page.$('.settings-btn');
        if (settingsBtn) {
            await settingsBtn.evaluate(b => b.click());
            await page.waitForFunction(() => {
                const modal = document.getElementById('service-modal');
                return modal && window.getComputedStyle(modal).display !== 'none';
            }, { timeout: 5000 });
            logStep("Settings Modal", "PASS", "Modal opened via FAB");
            
            await page.evaluate(() => { if (typeof closeServiceModal === 'function') closeServiceModal(); });
            await new Promise(r => setTimeout(r, 500));
            const modalVisible = await page.evaluate(() => {
                const modal = document.getElementById('service-modal');
                return modal && window.getComputedStyle(modal).display !== 'none';
            });
            logStep("Modal Close", !modalVisible ? "PASS" : "FAIL");
        }

        // Final Layout Integrity
        await page.evaluate(() => {
            const chip = document.querySelector('.filter-chip[data-target="all"]');
            if (chip) chip.click();
        });
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

        if (overlaps.length === 0) logStep("Layout Integrity", "PASS", "No element overlaps");
        else logStep("Layout Integrity", "FAIL", `${overlaps.length} overlaps found`);

        report.overall = report.steps.every(s => s.status === "PASS") ? "PASS" : "FAIL";
        await page.screenshot({ path: screenshotPath, fullPage: true });
        console.log(`📸 Final screenshot saved to ${screenshotPath}`);

    } catch (e) {
        console.error('❌ CRITICAL ERROR:', e);
        report.overall = "ERROR";
        report.error = e.message;
    } finally {
        const fs = require('fs');
        const md = `# Walkthrough Verification Report
Generated: ${report.timestamp}
Overall Status: ${report.overall === "PASS" ? "✅ PASS" : "❌ " + report.overall}

## Test Steps
| Step | Status | Details |
| :--- | :--- | :--- |
${report.steps.map(s => `| ${s.step} | ${s.status === "PASS" ? "✅" : "❌"} | ${s.details} |`).join('\n')}
`;
        fs.writeFileSync(reportPath, md);
        console.log(`📝 Report saved to ${reportPath}`);
        await browser.close();
        if (report.overall !== "PASS") process.exit(1);
    }
})();
