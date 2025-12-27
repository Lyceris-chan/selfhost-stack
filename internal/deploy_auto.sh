#!/usr/bin/env bash
set -euo pipefail

# Credentials - Set these in your environment or enter when prompted
export REG_USER="${REG_USER:-}"
export REG_TOKEN="${REG_TOKEN:-}"

# Passwords
VPN_PASS="password"
AGH_PASS="password"
ADMIN_PASS="password"

# WireGuard Config
WG_CONF=""

if [ -z "$REG_USER" ] || [ -z "$REG_TOKEN" ] || [ -z "$WG_CONF" ]; then
    echo "Error: REG_USER, REG_TOKEN, and WG_CONF must be set in the script or environment."
    exit 1
fi

echo "Starting automated deployment..."

{
    # VPN Pass
    echo "$VPN_PASS"
    # AGH Pass
    echo "$AGH_PASS"
    # Admin Pass
    echo "$ADMIN_PASS"
    # deSEC Domain (skip)
    echo ""
    # GitHub User (skip)
    echo ""
    # GitHub Token (skip)
    echo ""
    # Odido Token (skip)
    echo ""
    # WireGuard Config
    echo "$WG_CONF"
} | sudo -E ./zima.sh -y -c

echo "Deployment finished."