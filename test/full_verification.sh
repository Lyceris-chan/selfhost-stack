#!/bin/bash
# Clear all relevant environment variables to ensure no secrets or test configs leak into the process
echo "Clearing environment variables..."
unset LAN_IP PUBLIC_IP ADMIN_PASS_RAW VPN_PASS_RAW RIMGO_IMGUR_CLIENT_ID ODIDO_API_KEY ODIDO_USER_ID ODIDO_TOKEN WG_CONF_B64 DESEC_DOMAIN DESEC_TOKEN REG_USER REG_TOKEN TEST_MODE

# Ensure we are in the project root
cd "$(dirname "$0")/.."

# Run manual verification using mock values with a completely clean environment
echo "Starting manual verification with mock values (Clean Env)..."
env -i HOME="$HOME" PATH="$PATH" USER="$(whoami)" SHELL="$SHELL" TERM="$TERM" ./test/manual_verification.sh
