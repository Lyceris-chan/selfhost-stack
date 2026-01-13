#!/usr/bin/env bash
set -euo pipefail

# Service Logic Modules
# Broken down for maintainability

source "$SCRIPT_DIR/lib/services/sync.sh"
source "$SCRIPT_DIR/lib/services/images.sh"
source "$SCRIPT_DIR/lib/services/config.sh"
source "$SCRIPT_DIR/lib/services/compose.sh"
source "$SCRIPT_DIR/lib/services/dashboard.sh"
source "$SCRIPT_DIR/lib/services/deploy.sh"
