const puppeteer = require('puppeteer');
const fs = require('fs');
const path = require('path');

const SCREENSHOT_DIR = path.join(__dirname, '../screenshots');
const REPORT_FILE = path.join(__dirname, '../ui_report.md');

let results = [];

function logResult(category, test, outcome, details = '') {
    const timestamp = new Date().toISOString();
    results.push({ timestamp, category, test, outcome, details });
    console.log(`[${outcome}] ${category} > ${test}: ${details}`);
}

async function initBrowser() {
    if (!fs.existsSync(SCREENSHOT_DIR)) fs.mkdirSync(SCREENSHOT_DIR);
    const browser = await puppeteer.launch({
        headless: 'new',
        args: ['--no-sandbox', '--disable-setuid-sandbox']
    });
    const page = await browser.newPage();
    await page.setViewport({ width: 1440, height: 1200 });
    
    page.on('console', msg => {
        const type = msg.type();
        const text = msg.text();
        if (type === 'error' || type === 'warn') {
            console.log(`[BROWSER ${type.toUpperCase()}] ${text}`);
        }
    });
    
    return { browser, page };
}

function getAdminPassword() {
    let adminPass = 'admin123';
    const paths = [
        path.join(__dirname, '../../data/AppData/privacy-hub/.secrets'),
        path.join(__dirname, '../test_data/data/AppData/privacy-hub-test/.secrets')
    ];
    for (const p of paths) {
        if (fs.existsSync(p)) {
            const secrets = fs.readFileSync(p, 'utf8');
            const match = secrets.match(/ADMIN_PASS_RAW=["'](.+)["']/);
            if (match) {
                adminPass = match[1];
                console.log(`Loaded admin password from ${p}`);
                return adminPass;
            }
        }
    }
    return adminPass;
}

async function generateReport() {
    console.log('\n--- Generating UI Report ---');
    const timestamp = new Date().toLocaleString();
    let report = `# UI Verification Report - ${timestamp}\n\n`;
    const summary = {
        total: results.length,
        pass: results.filter(r => r.outcome === 'PASS').length,
        fail: results.filter(r => r.outcome === 'FAIL').length,
        warn: results.filter(r => r.outcome === 'WARN').length
    };
    report += `## Summary\n- **Total:** ${summary.total}\n- **Passed:** ✅ ${summary.pass}\n- **Failed:** ❌ ${summary.fail}\n- **Warnings:** ⚠️ ${summary.warn}\n\n`;
    const categories = [...new Set(results.map(r => r.category))];
    for (const cat of categories) {
        report += `### ${cat}\n| Test | Outcome | Details |\n|------|---------|---------|\n`;
        results.filter(r => r.category === cat).forEach(res => {
            const icon = res.outcome === 'PASS' ? '✅' : (res.outcome === 'FAIL' ? '❌' : '⚠️');
            report += `| ${res.test} | ${icon} ${res.outcome} | ${res.details} |\n`;
        });
        report += `\n`;
    }
    fs.writeFileSync(REPORT_FILE, report);
    console.log(`Report generated: ${REPORT_FILE}`);
}

module.exports = { initBrowser, logResult, getAdminPassword, generateReport, SCREENSHOT_DIR };
