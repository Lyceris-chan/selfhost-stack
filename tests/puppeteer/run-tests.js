#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");
const puppeteer = require("puppeteer");
const puppeteerPackage = require("puppeteer/package.json");

const DEFAULT_TIMEOUT_MS = parseInt(process.env.TEST_TIMEOUT_MS || "60000", 10);
const NAVIGATION_TIMEOUT_MS = parseInt(
  process.env.TEST_NAVIGATION_TIMEOUT_MS || "60000",
  10
);
const HEADLESS = (process.env.PUPPETEER_HEADLESS || "true").toLowerCase() !== "false";
const REPORT_DIR = process.env.TEST_REPORT_DIR || path.join(__dirname, "reports");
const CAPTURE_FAILURE_SCREENSHOTS =
  (process.env.TEST_CAPTURE_FAILURE_SCREENSHOTS || "false").toLowerCase() === "true";

const BASE_HOST = normalizeBaseHost(process.env.TEST_HOST || "http://127.0.0.1");

const SERVICE_DEFAULTS = {
  wikiless: {
    baseUrl: envOrDefault("WIKILESS_URL", buildBaseUrl(BASE_HOST, envOrDefault("WIKILESS_PORT", "8180"))),
    testPath: envOrDefault("WIKILESS_TEST_PATH", "/wiki/OpenAI"),
    expectedText: envOrDefault("WIKILESS_EXPECTED_TEXT", "OpenAI")
  },
  breezewiki: {
    baseUrl: envOrDefault("BREEZEWIKI_URL", buildBaseUrl(BASE_HOST, envOrDefault("BREEZEWIKI_PORT", "10416"))),
    testPath: envOrDefault("BREEZEWIKI_TEST_PATH", "/wiki/Talus?wiki=paladins"),
    expectedText: envOrDefault("BREEZEWIKI_EXPECTED_TEXT", "Talus")
  },
  redlib: {
    baseUrl: envOrDefault("REDLIB_URL", buildBaseUrl(BASE_HOST, envOrDefault("REDLIB_PORT", "8080"))),
    testPath: envOrDefault("REDLIB_TEST_PATH", "/settings")
  },
  rimgo: {
    baseUrl: envOrDefault("RIMGO_URL", buildBaseUrl(BASE_HOST, envOrDefault("RIMGO_PORT", "3002"))),
    testPath: envOrDefault("RIMGO_TEST_PATH", "/dhc04iu")
  },
  invidious: {
    baseUrl: envOrDefault("INVIDIOUS_URL", buildBaseUrl(BASE_HOST, envOrDefault("INVIDIOUS_PORT", "3000"))),
    testPath: envOrDefault("INVIDIOUS_TEST_PATH", "/watch?v=dQw4w9WgXcQ")
  },
  memos: {
    baseUrl: envOrDefault("MEMOS_URL", buildBaseUrl(BASE_HOST, envOrDefault("MEMOS_PORT", "5230"))),
    testPath: "/"
  },
  anonymousoverflow: {
    baseUrl: envOrDefault("ANONYMOUS_URL", buildBaseUrl(BASE_HOST, envOrDefault("ANONYMOUS_PORT", "8480"))),
    testPath: "/"
  },
  scribe: {
    baseUrl: envOrDefault("SCRIBE_URL", buildBaseUrl(BASE_HOST, envOrDefault("SCRIBE_PORT", "8280"))),
    testPath: "/"
  }
};

const TESTS = [
  {
    id: "wikiless",
    name: "Wikiless page load",
    url: resolveTestUrl(SERVICE_DEFAULTS.wikiless.baseUrl, SERVICE_DEFAULTS.wikiless.testPath),
    expectedText: SERVICE_DEFAULTS.wikiless.expectedText,
    run: async (page, expectedText) => {
      await page.waitForSelector("h1", { timeout: DEFAULT_TIMEOUT_MS });
      const heading = await page.$eval("h1", (el) => (el.textContent || "").trim());
      if (expectedText && !heading.includes(expectedText)) {
        throw new Error(`Expected heading to include "${expectedText}", got "${heading}"`);
      }
    }
  },
  {
    id: "breezewiki",
    name: "BreezeWiki search result",
    url: resolveTestUrl(SERVICE_DEFAULTS.breezewiki.baseUrl, SERVICE_DEFAULTS.breezewiki.testPath),
    expectedText: SERVICE_DEFAULTS.breezewiki.expectedText,
    run: async (page, expectedText) => {
      await page.waitForSelector("h1, .search-results", { timeout: DEFAULT_TIMEOUT_MS });
      const body = await page.$eval("body", (el) => el.textContent);
      if (expectedText && !body.includes(expectedText)) {
        throw new Error(`Expected body to include "${expectedText}"`);
      }
    }
  },
  {
    id: "redlib",
    name: "Redlib settings page",
    url: resolveTestUrl(SERVICE_DEFAULTS.redlib.baseUrl, SERVICE_DEFAULTS.redlib.testPath),
    run: async (page) => {
      await page.waitForSelector("form", { timeout: DEFAULT_TIMEOUT_MS });
    }
  },
  {
    id: "rimgo",
    name: "Rimgo image load (dhc04iu)",
    url: resolveTestUrl(SERVICE_DEFAULTS.rimgo.baseUrl, SERVICE_DEFAULTS.rimgo.testPath),
    run: async (page) => {
      await page.waitForFunction(() => {
        const img = document.querySelector("img");
        return img && img.complete && img.naturalWidth > 0;
      }, { timeout: DEFAULT_TIMEOUT_MS });
    }
  },
  {
    id: "memos",
    name: "Memos dashboard load",
    url: resolveTestUrl(SERVICE_DEFAULTS.memos.baseUrl, SERVICE_DEFAULTS.memos.testPath),
    run: async (page) => {
      await page.waitForSelector("body", { timeout: DEFAULT_TIMEOUT_MS });
    }
  },
  {
    id: "anonymousoverflow",
    name: "AnonymousOverflow load",
    url: resolveTestUrl(SERVICE_DEFAULTS.anonymousoverflow.baseUrl, SERVICE_DEFAULTS.anonymousoverflow.testPath),
    run: async (page) => {
      await page.waitForSelector("body", { timeout: DEFAULT_TIMEOUT_MS });
    }
  },
  {
    id: "scribe",
    name: "Scribe load",
    url: resolveTestUrl(SERVICE_DEFAULTS.scribe.baseUrl, SERVICE_DEFAULTS.scribe.testPath),
    run: async (page) => {
      await page.waitForSelector("body", { timeout: DEFAULT_TIMEOUT_MS });
    }
  }
];

async function main() {
  const runStartedAt = new Date();
  fs.mkdirSync(REPORT_DIR, { recursive: true });
  const timestamp = formatTimestamp(runStartedAt);

  const launchOptions = {
    headless: HEADLESS,
    args: ["--no-sandbox", "--disable-setuid-sandbox"],
    defaultViewport: { width: 1280, height: 720 }
  };

  const browser = await puppeteer.launch(launchOptions);
  const results = [];

  try {
    for (const test of TESTS) {
      const page = await browser.newPage();
      page.setDefaultTimeout(DEFAULT_TIMEOUT_MS);
      page.setDefaultNavigationTimeout(NAVIGATION_TIMEOUT_MS);

      const testStart = Date.now();
      let status = "pass";
      let errorMessage = "";

      try {
        console.log(`[RUN] ${test.name} - ${test.url}`);
        await page.goto(test.url, { waitUntil: "networkidle2", timeout: NAVIGATION_TIMEOUT_MS });
        await test.run(page, test.expectedText);
      } catch (error) {
        status = "fail";
        errorMessage = error && error.message ? error.message : String(error);
      } finally {
        await page.close();
      }

      const durationMs = Date.now() - testStart;
      results.push({ id: test.id, name: test.name, url: test.url, status, durationMs, error: errorMessage });

      const indicator = status === "pass" ? "PASS" : "FAIL";
      console.log(`[${indicator}] ${test.name}`);
      if (errorMessage) {
        console.log(`  Error: ${errorMessage}`);
      }
    }
  } finally {
    await browser.close();
  }

  const summary = buildSummary(results);
  const reportMdPath = path.join(REPORT_DIR, `report-${timestamp}.md`);
  fs.writeFileSync(reportMdPath, buildMarkdownReport(results, summary, runStartedAt), "utf8");

  console.log(`\nFinal Summary: ${summary.passed}/${summary.total} passed`);
  console.log(`Report: ${reportMdPath}`);

  if (summary.failed > 0) process.exitCode = 1;
}

function envOrDefault(key, fallback) {
  return process.env[key] && process.env[key].trim() ? process.env[key].trim() : fallback;
}

function normalizeBaseHost(value) {
  let host = (value || "").trim();
  if (!/^https?:\/\//i.test(host)) host = `http://${host}`;
  return host.replace(/\/+$/, "");
}

function buildBaseUrl(host, port) {
  try {
    const parsed = new URL(host);
    if (parsed.port) return host;
  } catch (e) {}
  return `${host}:${port}`;
}

function resolveTestUrl(baseUrl, testPath) {
  const base = baseUrl.endsWith("/") ? baseUrl : `${baseUrl}/`;
  const p = testPath.startsWith("/") ? testPath.substring(1) : testPath;
  return new URL(p, base).toString();
}

function formatTimestamp(date) {
  const pad = (v) => String(v).padStart(2, "0");
  return `${date.getFullYear()}${pad(date.getMonth() + 1)}${pad(date.getDate())}-${pad(date.getHours())}${pad(date.getMinutes())}${pad(date.getSeconds())}`;
}

function buildSummary(results) {
  return results.reduce((acc, r) => {
    acc.total++;
    if (r.status === "pass") acc.passed++; else acc.failed++;
    return acc;
  }, { total: 0, passed: 0, failed: 0 });
}

function buildMarkdownReport(results, summary, startedAt) {
  let md = `# Puppeteer Test Report\n\nStarted: ${startedAt.toISOString()}\n\n## Summary\n- Total: ${summary.total}\n- Passed: ${summary.passed}\n- Failed: ${summary.failed}\n\n## Results\n`;
  for (const r of results) {
    md += `### ${r.name}\n- Status: ${r.status.toUpperCase()}\n- URL: ${r.url}\n- Duration: ${r.durationMs}ms\n`;
    if (r.error) md += `- Error: ${r.error}\n`;
    md += "\n";
  }
  return md;
}

main().catch(console.error);