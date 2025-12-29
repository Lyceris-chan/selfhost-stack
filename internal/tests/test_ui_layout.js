const puppeteer = require('puppeteer');
const fs = require('fs');
const path = require('path');

(async () => {
    console.log('Starting UI Layout Verification...');
    const browser = await puppeteer.launch({
        args: ['--no-sandbox', '--disable-setuid-sandbox']
    });
    const page = await browser.newPage();

    // Use the generated dashboard.html
    const dashboardPath = process.env.DASHBOARD_URL || ('file://' + path.resolve('/DATA/AppData/privacy-hub/dashboard.html'));
    
    const checkLayout = async (viewName, width, height) => {
        console.log(`Checking layout for ${viewName} (${width}x${height})...`);
        await page.setViewport({ width, height });
        await page.goto(dashboardPath, { waitUntil: 'networkidle0' });

        // Force update banner to be visible for testing
        await page.evaluate(() => {
            document.getElementById('update-banner').style.display = 'block';
            document.getElementById('update-list').textContent = 'Updates available for: invidious, wikiless, scribe, vert, hub-api, odido-booster';
        });

        // Check for overlaps using bounding boxes
        const overlaps = await page.evaluate(() => {
            const elements = Array.from(document.querySelectorAll('.card, .btn, #update-banner, h1, .section-label'));
            const results = [];
            for (let i = 0; i < elements.length; i++) {
                for (let j = i + 1; j < elements.length; j++) {
                    const rect1 = elements[i].getBoundingClientRect();
                    const rect2 = elements[j].getBoundingClientRect();
                    
                    // Simple overlap detection
                    const isOverlapping = !(rect1.right < rect2.left || 
                                            rect1.left > rect2.right || 
                                            rect1.bottom < rect2.top || 
                                            rect1.top > rect2.bottom);
                    
                    // Filter out parent-child relationships which are expected to "overlap"
                    if (isOverlapping && !elements[i].contains(elements[j]) && !elements[j].contains(elements[i])) {
                        // Also ignore elements with 0 size (hidden)
                        if (rect1.width > 0 && rect1.height > 0 && rect2.width > 0 && rect2.height > 0) {
                            results.push(`Overlap between ${elements[i].tagName}.${elements[i].className} and ${elements[j].tagName}.${elements[j].className}`);
                        }
                    }
                }
            }
            return results;
        });

        if (overlaps.length > 0) {
            console.error(`❌ FAIL: Detected ${overlaps.length} overlaps in ${viewName}:`);
            overlaps.forEach(o => console.error(`  - ${o}`));
        } else {
            console.log(`✅ PASS: No overlaps detected in ${viewName}.`);
        }
        
        await page.screenshot({ path: `screenshot_${viewName}.png` });
        return overlaps.length === 0;
    };

    const desktopOk = await checkLayout('desktop', 1280, 800);
    const mobileOk = await checkLayout('mobile', 375, 667);

    await browser.close();

    if (!desktopOk || !mobileOk) {
        process.exit(1);
    }
})();
