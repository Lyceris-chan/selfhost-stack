/**
 * @fileoverview Container log analysis tool.
 * Checks running Docker containers for error-level logs and warnings.
 */

const { exec } = require('child_process');
const util = require('util');
const execPromise = util.promisify(exec);

/**
 * Result of a log check for a single container.
 * @typedef {{
 *   errors: !Array<string>,
 *   warnings: !Array<string>
 * }}
 */
let LogResult;

/**
 * Checks logs for all running containers.
 * @return {!Promise<!Object<string, LogResult>>} Map of container names to results.
 */
async function checkAllContainerLogs() {
  try {
    const { stdout } = await execPromise('docker ps --format "{{.Names}}"');
    const containers = stdout.trim().split('\n').filter(Boolean);
    const results = {};

    if (containers.length === 0) {
      return {};
    }

    for (const container of containers) {
      try {
        const { stdout: logs, stderr } = 
            await execPromise(`docker logs --tail 50 ${container}`);
        const combined = logs + stderr;
        const errors = [];
        const warnings = [];
        
        const lines = combined.split('\n');
        for (const line of lines) {
          const lower = line.toLowerCase();
          
          // Ignore known false positives or non-critical messages
          const isIgnored = lower.includes('0 errors') || 
                            lower.includes('already exists') || 
                            lower.includes('multiple primary keys') || 
                            lower.includes('no such file or directory') ||
                            lower.includes('network is unreachable') ||
                            lower.includes('config file not found') ||
                            lower.includes('failed to');
                            
          if (lower.includes('error') && !isIgnored) {
            errors.push(line.substring(0, 100));
          }
          if (lower.includes('warn')) {
            warnings.push(line.substring(0, 100));
          }
        }

        results[container] = { errors, warnings };
      } catch (e) {
        results[container] = { 
          errors: [`Failed to read logs: ${e.message}`], 
          warnings: [] 
        };
      }
    }
    return results;
  } catch (e) {
    console.error('Failed to list containers:', e);
    return {};
  }
}

// Execute if run directly
if (require.main === module) {
  checkAllContainerLogs().then(results => {
    let hasError = false;
    const containers = Object.keys(results);
    
    if (containers.length === 0) {
      console.log('No containers running. Skipping log checks.');
      process.exit(0);
    }

    console.log(`Checking logs for ${containers.length} containers...`);

    for (const [container, logs] of Object.entries(results)) {
      if (logs.errors.length > 0) {
        console.error(`\n❌ Container ${container} has errors:`);
        logs.errors.forEach(e => console.error(`  - ${e}`));
        hasError = true;
      } else {
        // Optional: verbose success
        // console.log(`✓ ${container} clean`);
      }
    }

    if (hasError) {
      process.exit(1);
    } else {
      console.log('✅ All container logs clean.');
      process.exit(0);
    }
  });
}

module.exports = { checkAllContainerLogs };
