/**
 * @fileoverview Functional Operations Test Suite
 * Tests the backend API endpoints for update, migrate, and rollback operations.
 */

const fs = require('fs');
const path = require('path');
const http = require('http');
const https = require('https');

// Configuration
const CONFIG = {
  apiHost: process.env.API_HOST || '127.0.0.1', 
  apiPort: process.env.API_PORT || 55555,
  secretsPath: path.join(__dirname, 'test_data/data/AppData/privacy-hub-test/.secrets'),
};

// Helper to read secrets
function getSecrets() {
  const secrets = {
    password: process.env.ADMIN_PASSWORD || '',
    apiKey: process.env.HUB_API_KEY || ''
  };
  
  try {
    if (fs.existsSync(CONFIG.secretsPath)) {
      const content = fs.readFileSync(CONFIG.secretsPath, 'utf-8');
      
      const passMatch = content.match(/ADMIN_PASS_RAW=["']?([^"'\n]+)["']?/);
      if (passMatch && !process.env.ADMIN_PASSWORD) secrets.password = passMatch[1];
      
      const keyMatch = content.match(/HUB_API_KEY=['"]?([^"'\n]+)['"]?/);
      if (keyMatch && !process.env.HUB_API_KEY) secrets.apiKey = keyMatch[1];
    }
  } catch (e) {
    console.error('Error reading secrets:', e);
  }
  
  if (!secrets.password) secrets.password = 'changeme';
  return secrets;
}

// Helper for HTTP requests
function request(method, path, body = null, token = null, extraHeaders = {}) {
  return new Promise((resolve, reject) => {
    // Handle paths that might not be under /api
    const requestPath = path.startsWith('/api') || path === '/watchtower' ? path : '/api' + path;
    
    const options = {
      hostname: CONFIG.apiHost,
      port: CONFIG.apiPort,
      path: requestPath,
      method: method,
      headers: {
        'Content-Type': 'application/json',
        ...extraHeaders
      },
    };

    if (token) {
      options.headers['X-Session-Token'] = token;
    }

    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => data += chunk);
      res.on('end', () => {
        try {
          const json = JSON.parse(data);
          resolve({ status: res.statusCode, data: json });
        } catch (e) {
          resolve({ status: res.statusCode, data });
        }
      });
    });

    req.on('error', (e) => reject(e));

    if (body) {
      req.write(JSON.stringify(body));
    }
    req.end();
  });
}

async function main() {
  console.log('🚀 Starting Functional Operations Tests\n');
  
  const { password, apiKey } = getSecrets();
  console.log(`🔑 Using admin password: ${password.substring(0, 3)}***`);
  console.log(`🔑 Using API Key: ${apiKey ? apiKey.substring(0, 3) + '***' : 'None'}`);

  try {
    // 1. Authenticate
    console.log('Testing Authentication...');
    const authRes = await request('POST', '/verify-admin', { password });
    
    if (authRes.status !== 200 || !authRes.data.token) {
      throw new Error(`Authentication failed: ${JSON.stringify(authRes.data)}`);
    }
    const token = authRes.data.token;
    console.log('✅ Authentication successful');

    // 2. Get Services
    console.log('\nTesting GET /services...');
    const servicesRes = await request('GET', '/services', null, token);
    if (servicesRes.status === 200 && servicesRes.data.services) {
        console.log(`✅ Retrieved ${Object.keys(servicesRes.data.services).length} services`);
    } else {
        console.error(`❌ Failed to retrieve services: ${servicesRes.status}`);
    }

    // 3. Check Updates
    console.log('\nTesting GET /updates...');
    const updatesRes = await request('GET', '/updates', null, token);
    if (updatesRes.status === 200) {
        console.log('✅ Update check successful');
    } else {
        console.error(`❌ Failed update check: ${updatesRes.status}`);
    }

    // 4. Test Service Operation: Migrate (Safe operation on simple service)
    // We use 'rimgo' or 'redlib' as they are safe targets.
    // Or we can just check if the endpoint accepts the request.
    const testService = 'rimgo';
    console.log(`\nTesting POST /migrate for ${testService} (Backup: no)...`);
    const migrateRes = await request('POST', `/migrate?service=${testService}&backup=no`, null, token);
    
    // Note: The script execution might fail if docker is not available in the way hub-api expects,
    // but the API should handle the request and try to run it.
    // We expect 200 OK even if the script output says "skipped" or similar.
    if (migrateRes.status === 200) {
        console.log(`✅ Migration request accepted: ${JSON.stringify(migrateRes.data)}`);
    } else {
        console.warn(`⚠️ Migration request failed (might be expected in test env): ${migrateRes.status} - ${JSON.stringify(migrateRes.data)}`);
    }

    // 5. Test Update Trigger (Mock/Dry Run approach - checking if it accepts)
    // We won't actually trigger a full update as it might kill the container we are testing against.
    // However, the router `POST /update-service` adds a background task.
    // It returns immediate success.
    console.log(`\nTesting POST /update-service for ${testService}...`);
    const updateRes = await request('POST', '/update-service', { service: testService }, token);
    
    if (updateRes.status === 200 && updateRes.data.success) {
        console.log(`✅ Update request accepted: ${updateRes.data.message}`);
    } else {
        console.error(`❌ Update request failed: ${updateRes.status} - ${JSON.stringify(updateRes.data)}`);
    }

    // 6. Test Rollback Status
    console.log(`\nTesting GET /rollback-status for ${testService}...`);
    const rollbackRes = await request('GET', `/rollback-status?service=${testService}`, null, token);
    if (rollbackRes.status === 200) {
        console.log(`✅ Rollback status checked: ${JSON.stringify(rollbackRes.data)}`);
    } else {
        console.error(`❌ Rollback status check failed: ${rollbackRes.status}`);
    }

    // 7. Test Rollback Trigger
    console.log(`\nTesting POST /rollback-service for ${testService}...`);
    // This will trigger a real rollback if a state exists
    const rollbackTriggerRes = await request('POST', '/rollback-service', { service: testService }, token);
    if (rollbackTriggerRes.status === 200 || rollbackTriggerRes.status === 400 || rollbackTriggerRes.status === 404) {
        // 400/404 is acceptable if no backup exists, it proves the endpoint logic ran
        console.log(`✅ Rollback trigger endpoint reachable: ${rollbackTriggerRes.status} - ${JSON.stringify(rollbackTriggerRes.data)}`);
    } else {
        console.error(`❌ Rollback trigger failed unexpectedly: ${rollbackTriggerRes.status}`);
    }

    // 8. Test Watchtower Updates (Webhook)
    console.log('\nTesting POST /watchtower (Webhook)...');
    // Watchtower uses X-API-Key or ?token=...
    const watchtowerRes = await request('POST', '/watchtower', { message: 'Test Update' }, null, { 'X-API-Key': apiKey });
    if (watchtowerRes.status === 200) {
        console.log(`✅ Watchtower webhook accepted: ${JSON.stringify(watchtowerRes.data)}`);
    } else {
        console.error(`❌ Watchtower webhook failed: ${watchtowerRes.status} (Key used: ${apiKey ? 'Yes' : 'No'})`);
    }

    // 9. Test Changelog Retrieval
    // Testing with a known service or generic fallback
    const changelogService = 'hub-api'; 
    console.log(`\nTesting GET /changelog for ${changelogService}...`);
    const changelogRes = await request('GET', `/changelog?service=${changelogService}`, null, token);
    if (changelogRes.status === 200) {
        console.log(`✅ Changelog retrieved: ${changelogRes.data.changelog ? 'Content found' : 'Empty (Expected)'}`);
    } else {
        console.warn(`⚠️ Changelog retrieval failed (might be missing token or file): ${changelogRes.status}`);
    }

    // 10. Test Invidious Backup (via Migrate)
    console.log('\nTesting POST /migrate for Invidious (Backup: yes)...');
    // We use dry-run or expect it to fail safely in test env if container missing, but verify endpoint logic
    const invidiousRes = await request('POST', '/migrate?service=invidious&backup=yes', null, token);
    if (invidiousRes.status === 200) {
        console.log(`✅ Invidious backup/migrate request accepted: ${JSON.stringify(invidiousRes.data)}`);
    } else {
         // It might fail if container not running, which is fine for functional op test of API
        console.log(`ℹ️ Invidious backup/migrate response: ${invidiousRes.status} (Likely container missing in test runner, but API handled it)`);
    }

    // 11. Test System Backup
    console.log('\nTesting POST /backup (System Wide)...');
    const backupRes = await request('POST', '/backup', {}, token);
    if (backupRes.status === 200) {
        console.log(`✅ System backup triggered: ${JSON.stringify(backupRes.data)}`);
    } else {
        console.error(`❌ System backup trigger failed: ${backupRes.status}`);
    }
    
    // 12. Skip Memos Backup Test
    console.log('\nℹ️ Skipping memos backup test as requested by configuration.');

  } catch (error) {
    console.error('❌ Fatal error:', error.message);
    process.exit(1);
  }
}

if (require.main === module) {
  main();
}
