#!/usr/bin/env bash
BASE_DIR="/DATA/AppData/privacy-hub"
DASHBOARD_FILE="$BASE_DIR/dashboard.html"
LAN_IP="10.0.1.183"
PUBLIC_IP="1.2.3.4"
ODIDO_API_KEY="mock_key"
FOUND_OCTET="1" # Dummy value for shell variable, not used in dashboard JS directly

mkdir -p "$BASE_DIR"

# Temporarily redirect stdout of zima.sh to a file to capture the dashboard generation block
# and then execute that block in a subshell.

# Extract dashboard HTML generation from zima.sh
# Lines 4342 to 8261 contain all the cat commands for DASHBOARD_FILE
sed -n '4342,8261p' zima.sh > /tmp/dashboard_gen_block.sh

# Now, execute this block with the necessary environment variables set
# The 'eval' is crucial here because the extracted block uses HEREDOCs with unquoted EOF,
# meaning shell variables will be expanded at eval time.
(
    export BASE_DIR
    export DASHBOARD_FILE
    export LAN_IP
    export PUBLIC_IP
    export ODIDO_API_KEY
    export FOUND_OCTET # Used in zima.sh but not directly for dashboard HTML itself.
    
    # Run the extracted script
    bash /tmp/dashboard_gen_block.sh
)

rm /tmp/dashboard_gen_block.sh
echo "Dashboard regenerated at $DASHBOARD_FILE"