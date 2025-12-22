#!/usr/bin/env bash
set -euo pipefail

# Credentials
export REG_USER="laciachan"
export REG_TOKEN="<REDACTED_TOKEN>"

# Passwords
VPN_PASS="testpassword123"
AGH_PASS="testpassword123"
ADMIN_PASS="testpassword123"

# WireGuard Config
WG_CONF="[Interface]
# Bouncing = 2
# NAT-PMP (Port Forwarding) = on
# VPN Accelerator = on
PrivateKey = eFLt1FVdbzdAqTBJPvT6roE+aRmKKR87qraOFqdZ+10=
Address = 10.2.0.2/32
DNS = 10.2.0.1

[Peer]
# NL-FREE#142
PublicKey = uZp/DOcYSAVEHjK8Ht9jG0K9pa2+Oe5rVXVglFHq6R8=
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = 169.150.218.26:51820"

# Run zima.sh with automated inputs
# -y: auto-confirm
# -p: auto-passwords (we might want to provide them instead)
# Actually, I'll provide them manually via stdin to test the flow

echo "Starting automated deployment..."

# Note: zima.sh -y -c will wipe and skip some prompts
# But it still asks for passwords if .secrets is missing

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
    # End of WG Config (Ctrl+D equivalent)
} | sudo -E ./zima.sh -y -c

echo "Deployment finished."
