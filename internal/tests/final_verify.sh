#!/usr/bin/env bash
set -euo pipefail

# Credentials
export REG_USER="laciachan"
export REG_TOKEN="${REG_TOKEN:-}" # DO NOT HARDCODE SECRETS
export AUTO_CONFIRM=true


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

echo "🚀 Starting Full System Deployment & Verification..."

{
    # VPN Pass
    echo "verification-pass-123"
    # AGH Pass
    echo "verification-pass-123"
    # Admin Pass
    echo "verification-pass-123"
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

echo "✅ Stack Deployed. Waiting for services to reach healthy state..."
sleep 30

# Verify health
sudo docker ps --format '{{.Names}}: {{.Status}}'
