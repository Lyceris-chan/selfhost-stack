#!/bin/bash
#
# Orchestrates the loading of service logic modules.
#
# This script sources all necessary service-specific scripts to ensure
# their functions and variables are available to the main orchestrator.

source "$SCRIPT_DIR/lib/services/sync.sh"
source "$SCRIPT_DIR/lib/services/images.sh"
source "$SCRIPT_DIR/lib/services/config.sh"
source "$SCRIPT_DIR/lib/services/compose.sh"
source "$SCRIPT_DIR/lib/services/dashboard.sh"
source "$SCRIPT_DIR/lib/services/deploy.sh"
