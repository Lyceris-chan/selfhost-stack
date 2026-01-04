## Verification Suite

This directory contains the comprehensive verification suite for the Privacy Hub.

### Automated Testing Setup

The testing suite automatically loads configuration from the `details` file in the repository root.

1. Ensure the `details` file in the root contains your WireGuard configuration and Docker Hub credentials.
2. The verification suite will run `setup_test_config.py` to populate `test_config.env` automatically.

### Running the Full Suite

The `run_full_verification.sh` script is the primary entry point. It performs:
1. **Source Synchronization**: Clones all necessary service repositories.
2. **Batch Deployment**: Builds and verifies services in small batches to manage storage and CPU usage.
3. **UI/UX Testing**: Uses Puppeteer to verify dashboard interactions, theme toggling, admin mode, and log filtering.
4. **API Verification**: Tests the Hub API endpoints for health and status.
5. **Slot Swapping**: Verifies the A/B update system by swapping active slots.
6. **Log Integrity**: Ensures all system logs follow the required human-readable JSON format.

Usage:
```bash
bash run_full_verification.sh
```

### Manual Configuration (Optional)

If you need to override values, you can manually edit `test_config.env` after it has been generated, or copy the template:
```bash
cp test_config.template.env test_config.env
```

### Components

- `setup_test_config.py`: Extracts credentials from `details` file.
- `test_user_interactions.js`: Puppeteer-based UI interaction tests.
- `SERVICE_VERIFICATION_REPORT.md`: Generated report after service checks.
- `USER_INTERACTIONS_REPORT.md`: Generated report after UI checks.


