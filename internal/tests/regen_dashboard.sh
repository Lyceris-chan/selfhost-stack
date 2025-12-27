#!/usr/bin/env bash
# Define base path - override for testing if needed
if [ -z "$BASE_DIR" ]; then
    # Use a temp dir if /DATA is not available/writable
    if [ ! -w "/DATA" ]; then
        BASE_DIR="/tmp/privacy-hub-test"
    else
        BASE_DIR="/DATA/AppData/privacy-hub"
    fi
fi

DASHBOARD_FILE="$BASE_DIR/dashboard.html"
LAN_IP="10.0.1.183"
PUBLIC_IP="1.2.3.4"
ODIDO_API_KEY="mock_key"
FOUND_OCTET="1"
DESEC_DOMAIN="example.dedyn.io"
PORT_PORTAINER="9000"

mkdir -p "$BASE_DIR"

# Extract dashboard HTML generation from zima.sh dynamically
# Find function definition and extract body
sed -n '/^generate_dashboard() {/,/^}/p' ../../zima.sh > /tmp/dashboard_gen_func.sh
# Remove first line (func decl) and last line (closing brace)
sed '1d;$d' /tmp/dashboard_gen_func.sh > /tmp/dashboard_gen_block.sh

(
    export BASE_DIR
    export DASHBOARD_FILE
    export LAN_IP
    export PUBLIC_IP
    export ODIDO_API_KEY
    export FOUND_OCTET
    export DESEC_DOMAIN
    export PORT_PORTAINER
    
    # Mock logging
    log_info() { echo "[INFO] $1"; }
    export -f log_info
    
    # Run the extracted script
    bash /tmp/dashboard_gen_block.sh
)

rm /tmp/dashboard_gen_func.sh /tmp/dashboard_gen_block.sh
echo "Dashboard regenerated at $DASHBOARD_FILE"