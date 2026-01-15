/**
 * @fileoverview Utility functions for Puppeteer-based UI testing.
 * Adheres to the Google JavaScript Style Guide.
 */

const fs = require('fs');
const path = require('path');
const puppeteer = require('puppeteer');

/** @const {string} Directory for saving test screenshots. */
const SCREENSHOT_DIR = path.join(__dirname, '../screenshots');

/** @const {string} Path to the markdown report file. */
const REPORT_FILE = path.join(__dirname, '../ui_report.md');

/** @type {Array<Object>} Stores test results for the final report. */
let results = [];

/** @type {Array<Object>} Stores console logs captured from the browser. */
let consoleLogs = [];

/**
 * Logs a test result and pushes it to the results collection.
 * 
 * @param {string} category Functional category of the test.
 * @param {string} test Name of the specific test case.
 * @param {string} outcome Result status (PASS, FAIL, WARN).
 * @param {string} details Descriptive information about the result.
 */
function logResult(category, test, outcome, details = '') {
  const timestamp = new Date().toISOString();
  results.push({timestamp, category, test, outcome, details});
  console.log(`[${outcome}] ${category} > ${test}: ${details}`);
}

/**
 * Initializes the Puppeteer browser and a new page.
 * 
 * @return {Promise<{browser: !puppeteer.Browser, page: !puppeteer.Page}>}
 */
async function initBrowser() {
  if (!fs.existsSync(SCREENSHOT_DIR)) {
    fs.mkdirSync(SCREENSHOT_DIR);
  }
  const browser = await puppeteer.launch({
    headless: 'new',
    args: ['--no-sandbox', '--disable-setuid-sandbox'],
  });
  const page = await browser.newPage();
  await page.setViewport({width: 1440, height: 1200});

  page.on('console', (msg) => {
    const type = msg.type();
    const text = msg.text();
    consoleLogs.push({type, text});
    if (type === 'error' || type === 'warn') {
      console.log(`[BROWSER ${type.toUpperCase()}] ${text}`);
    }
  });

  return {browser, page};
}

/**
 * Returns the collected browser console logs.
 * @return {Array<Object>}
 */
function getConsoleLogs() {
  return consoleLogs;
}

/**
 * Clears the stored console logs.
 */
function clearConsoleLogs() {
  consoleLogs = [];
}

/**
 * Attempts to retrieve the admin password from deployment artifacts.
 * 
 * @return {string} The detected password or a default dummy value.
 */
function getAdminPassword() {
  let adminPass = 'admin123';

  // Primary: Check test docker-compose.yml
  const composePath = path.join(
      __dirname, '../test_data/data/AppData/privacy-hub-test/docker-compose.yml');
  if (fs.existsSync(composePath)) {
    const compose = fs.readFileSync(composePath, 'utf8');
    const match = compose.match(/ADMIN_PASS_RAW=([^\n\s"]+)/);
    if (match) {
      adminPass = match[1];
      console.log(
          `Loaded admin password from test docker-compose.yml: ${adminPass}`);
      return adminPass;
    }
  }

  const paths = [
    path.join(
        __dirname, '../test_data/data/AppData/privacy-hub-test/.secrets'),
    path.join(__dirname, '../../data/AppData/privacy-hub/.secrets'),
  ];
  for (const p of paths) {
    if (fs.existsSync(p) && fs.lstatSync(p).isFile()) {
      const secrets = fs.readFileSync(p, 'utf8');
      const match = secrets.match(/ADMIN_PASS_RAW=["']?([^"'\n\s]+)["']?/);
      if (match) {
        adminPass = match[1];
        console.log(`Loaded admin password from ${p}`);
        return adminPass;
      }
    }
  }
  return adminPass;
}

/**
 * Generates a Markdown report from the collected test results.
 */
async function generateReport() {
  console.log('\n--- Generating UI Report ---');
  const timestamp = new Date().toLocaleString();
  let report = `# UI Verification Report - ${timestamp}\n\n`;
  const summary = {
    total: results.length,
    pass: results.filter((r) => r.outcome === 'PASS').length,
    fail: results.filter((r) => r.outcome === 'FAIL').length,
    warn: results.filter((r) => r.outcome === 'WARN').length,
  };
  report += `## Summary\n- **Total:** ${summary.total}\n` +
            `- **Passed:** ✅ ${summary.pass}\n` +
            `- **Failed:** ❌ ${summary.fail}\n` +
            `- **Warnings:** ⚠️ ${summary.warn}\n\n`;

  const categories = [...new Set(results.map((r) => r.category))];
  for (const cat of categories) {
    report += `### ${cat}\n| Test | Outcome | Details |\n|------|---------|---------|\n`;
    results.filter((r) => r.category === cat).forEach((res) => {
      const icon = res.outcome === 'PASS' ? '✅' :
          (res.outcome === 'FAIL' ? '❌' : '⚠️');
      report +=
          `| ${res.test} | ${icon} ${res.outcome} | ${res.details} |\n`;
    });
    report += `\n`;
  }
  fs.writeFileSync(REPORT_FILE, report);
  console.log(`Report generated: ${REPORT_FILE}`);
}

/**
 * Returns the collected test results.
 * @return {Array<Object>}
 */
function getResults() {
  return results;
}

module.exports = {
  initBrowser,
  logResult,
  getResults,
  getAdminPassword,
  generateReport,
  getConsoleLogs,
  clearConsoleLogs,
  SCREENSHOT_DIR,
};
