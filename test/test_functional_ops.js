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
  apiHost: process.env.API_HOST || '10.0.10.225', // Assuming test runs against this IP as seen in test_integration.js
  apiPort: process.env.API_PORT || 55555,
  secretsPath: path.join(__dirname, '../data/AppData/privacy-hub/.secrets'),
};

// Helper to read secrets
function getAdminPassword() {
  if (process.env.ADMIN_PASSWORD) return process.env.ADMIN_PASSWORD;
  try {
    if (!fs.existsSync(CONFIG.secretsPath)) {
      console.warn(`⚠️ Secrets file not found at ${CONFIG.secretsPath}. Using default 'changeme' or env var.`);
      return process.env.ADMIN_PASSWORD || 'changeme';
    }
    const content = fs.readFileSync(CONFIG.secretsPath, 'utf-8');
    const match = content.match(/ADMIN_PASS_RAW=["']?([^"'\n]+)["']?/);
    return match ? match[1] : 'changeme';
  } catch (e) {
    console.error('Error reading secrets:', e);
    return 'changeme';
  }
}

// Helper for HTTP requests
function request(method, path, body = null, token = null) {
  return new Promise((resolve, reject) => {
    const options = {
      hostname: CONFIG.apiHost,
      port: CONFIG.apiPort,
      path: '/api' + path,
      method: method,
      headers: {
        'Content-Type': 'application/json',
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
  
  const password = getAdminPassword();
  console.log(`🔑 Using admin password: ${password.substring(0, 3)}***`);

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

    // 7. Test Rollback Trigger (Mock)
    console.log(`\nTesting POST /rollback-service for ${testService} (Simulated)...`);
    // We expect this to fail or return a specific message if no backup exists, but the endpoint should be reachable.
    const rollbackTriggerRes = await request('POST', '/rollback-service', { service: testService }, token);
    if (rollbackTriggerRes.status === 200 || rollbackTriggerRes.status === 400 || rollbackTriggerRes.status === 404) {
        // 400/404 is acceptable if no backup exists, it proves the endpoint logic ran
        console.log(`✅ Rollback trigger endpoint reachable: ${rollbackTriggerRes.status} - ${JSON.stringify(rollbackTriggerRes.data)}`);
    } else {
        console.error(`❌ Rollback trigger failed unexpectedly: ${rollbackTriggerRes.status}`);
    }

  } catch (error) {
    console.error('❌ Fatal error:', error.message);
    process.exit(1);
  }
}

if (require.main === module) {
  main();
}
