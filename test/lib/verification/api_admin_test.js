/**
 * @fileoverview Admin API Verification.
 * Tests administrative endpoints using the API Key, bypassing the UI login.
 */

const http = require('http');
const fs = require('fs');
const path = require('path');

const CONFIG = {
  baseUrl: process.env.API_URL || 'http://localhost:55555',
  secretsFile: path.join(__dirname, '..', '..', '..', 'data', 'AppData', 'privacy-hub', '.secrets'),
};

function getApiKey() {
  if (!fs.existsSync(CONFIG.secretsFile)) {
    console.error('❌ Secrets file not found');
    return null;
  }
  const content = fs.readFileSync(CONFIG.secretsFile, 'utf8');
  const match = content.match(/HUB_API_KEY='([^']+)'/);
  return match ? match[1] : null;
}

function makeRequest(method, path, apiKey, body = null) {
  return new Promise((resolve, reject) => {
    const url = new URL(CONFIG.baseUrl + path);
    const options = {
      method: method,
      headers: {
        'X-API-Key': apiKey,
        'Content-Type': 'application/json',
      },
    };

    const req = http.request(url, options, (res) => {
      let data = '';
      res.on('data', (chunk) => data += chunk);
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, body: data ? JSON.parse(data) : {} });
        } catch (e) {
          resolve({ status: res.statusCode, body: data });
        }
      });
    });

    req.on('error', (e) => reject(e));
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

async function run() {
  console.log('=== Running Admin API Verification ===');
  
  const apiKey = getApiKey();
  if (!apiKey) {
    console.error('❌ Could not retrieve API Key');
    process.exit(1);
  }
  console.log('    ✓ API Key retrieved');

  let passed = 0;
  let failed = 0;

  async function check(name, fn) {
    try {
      await fn();
      console.log(`    ✓ ${name} passed`);
      passed++;
    } catch (e) {
      console.log(`    ❌ ${name} failed: ${e.message}`);
      failed++;
    }
  }

  // 1. Check Updates
  await check('Update Status', async () => {
    const res = await makeRequest('GET', '/api/updates', apiKey);
    if (res.status !== 200) throw new Error(`Status ${res.status}`);
  });

  // 2. Trigger Update Check (Async)
  await check('Trigger Update Check', async () => {
    const res = await makeRequest('GET', '/api/check-updates', apiKey);
    if (res.status !== 200) throw new Error(`Status ${res.status}`);
    if (!res.body.success) throw new Error('Response success was false');
  });

  // 3. Rollback Status
  await check('Rollback Availability', async () => {
    const res = await makeRequest('GET', '/api/rollback-status?service=hub-api', apiKey);
    if (res.status !== 200) throw new Error(`Status ${res.status}`);
    if (res.body.available === undefined) throw new Error('Invalid response schema');
  });

  // 4. Changelog
  await check('Changelog Fetch', async () => {
    const res = await makeRequest('GET', '/api/changelog?service=portainer', apiKey);
    if (res.status !== 200) throw new Error(`Status ${res.status}`);
    if (!res.body.changelog) throw new Error('No changelog field');
  });

  // 5. System Health (Relaxed check)
  await check('System Health', async () => {
    const res = await makeRequest('GET', '/api/system-health', apiKey);
    if (res.status !== 200) throw new Error(`Status ${res.status}`);
    // Check for any common health keys
    if (res.body.cpu === undefined && res.body.status === undefined && res.body.uptime === undefined) {
        throw new Error(`Invalid health data: ${JSON.stringify(res.body)}`);
    }
  });

  console.log('--------------------------------------------------');
  console.log(`Passed: ${passed}, Failed: ${failed}`);
  
  if (failed > 0) process.exit(1);
}

run();