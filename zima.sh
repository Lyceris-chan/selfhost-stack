#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2001,SC2015,SC2016,SC2034,SC2024,SC2086
set -euo pipefail

# ==============================================================================
# 🛡️ ZIMAOS PRIVACY HUB: SECURE NETWORK STACK
# ==============================================================================
# This deployment provides a self-hosted network security environment.
# Digital independence requires ownership of the hardware and software that 
# manages your data.
#
# Core Components:
# - WireGuard: Secure remote access gateway for untrusted networks.
# - AdGuard Home + Unbound: Recursive, filtered DNS resolution for 
#   independent network visibility.
# - Privacy Frontends: Clean, telemetry-free interfaces for web services.
#
# ESTABLISH CONTROL. MAINTAIN PRIVACY.
# ==============================================================================

# Source Consolidated Libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_DIR

# 1. Core Logic (Utils, Init, Network, Auth)
source "$SCRIPT_DIR/lib/core.sh"

# 2. Service Logic (Sources, Scripts, Configs, Compose, Dashboard)
source "$SCRIPT_DIR/lib/services.sh"

# 3. Operations Logic (Cleanup, Backup, Deploy)
source "$SCRIPT_DIR/lib/operations.sh"

# --- Main Execution Flow ---

# 1. Cleanup & Reset
if [ "$CLEAN_ONLY" = true ]; then
    clean_environment
    log_info "Clean-only mode enabled. Deployment skipped."
    exit 0
fi

# 2. Registry Authentication
authenticate_registries

# 3. Clean Environment (if not clean-only, already handled above if clean-only)
clean_environment

# 4. Pre-pull Critical Images
log_info "Pre-pulling core infrastructure images in parallel..."
$SUDO mkdir -p "$BASE_DIR"
DOTENV_FILE="$BASE_DIR/.env"
if [ ! -f "$DOTENV_FILE" ]; then $SUDO touch "$DOTENV_FILE"; fi
$SUDO chmod 666 "$DOTENV_FILE"

# Define all services that use the A/B scheme
AB_SERVICES="hub-api odido-booster memos gluetun portainer adguard unbound wg-easy redlib wikiless invidious rimgo breezewiki anonymousoverflow scribe vert vertd companion"

for srv in $AB_SERVICES; do
    VAR_NAME="${srv//-/_}_IMAGE_TAG"
    VAR_NAME=$(echo $VAR_NAME | tr '[:lower:]' '[:upper:]')
    if ! grep -q "^$VAR_NAME=" "$DOTENV_FILE"; then
        echo "$VAR_NAME=latest" | $SUDO tee -a "$DOTENV_FILE" >/dev/null
    fi
    val=$(grep "^$VAR_NAME=" "$DOTENV_FILE" | cut -d'=' -f2)
    export "$VAR_NAME=$val"
done

CRITICAL_IMAGES="nginx:1.27.3-alpine python:3.11.11-alpine3.21 node:20.18.1-alpine3.21 oven/bun:1.1.34-alpine alpine:3.21.0 redis:7.2.6-alpine postgres:14.15-alpine3.21 neilpang/acme.sh:latest"

PIDS=""
for img in $CRITICAL_IMAGES; do
    pull_with_retry "$img" &
    PIDS="$PIDS $!"
done

SUCCESS=true
for pid in $PIDS; do
    if ! wait "$pid"; then
        SUCCESS=false
    fi
done

if [ "$SUCCESS" = false ]; then
    log_crit "One or more critical images failed to pull. Aborting."
    exit 1
fi
log_info "All critical images pulled successfully."

# 5. Network & Directories
allocate_subnet
detect_network
setup_static_assets

# 6. Auth & Secrets
setup_secrets

setup_configs # Includes DNS/SSL config

# 7. WireGuard Config
echo ""
echo "==========================================================="
echo " PROTON WIREGUARD CONFIGURATION"
echo "==========================================================="
echo ""
echo "⚠️  IMPORTANT: NAT-PMP (Port Forwarding) Configuration"
echo "-----------------------------------------------------------"
echo "When generating your WireGuard config in Proton VPN, ensure that"
echo "NAT-PMP (Port Forwarding) is DISABLED. Here's why:"
echo ""
echo "  • NAT-PMP opens a port on the VPN server that forwards to your device"
echo "  • This exposes your Privacy Hub services to the PUBLIC INTERNET"
echo "  • Anyone scanning Proton's IP ranges could find and attack your services"
echo "  • Your home IP remains hidden, but your services become publicly accessible"
echo ""
echo "The correct setting in Proton VPN WireGuard config generation:"
echo "  ✓ NAT-PMP (Port Forwarding) = OFF"
echo "  ✓ VPN Accelerator = ON (recommended for performance)"
echo "-----------------------------------------------------------"
echo ""

if validate_wg_config; then
    log_info "Existing WireGuard config found and validated. Skipping paste."
else
    if [ -f "$ACTIVE_WG_CONF" ] && [ -s "$ACTIVE_WG_CONF" ]; then
        log_warn "Existing WireGuard config was invalid/empty. Removed."
        rm "$ACTIVE_WG_CONF"
    fi

    if [ -n "${WG_CONF_B64:-}" ]; then
        log_info "WireGuard configuration provided in environment. Decoding..."
        echo "$WG_CONF_B64" | base64 -d | $SUDO tee "$ACTIVE_WG_CONF" >/dev/null
    elif [ "$AUTO_CONFIRM" = true ]; then
        log_warn "Auto-confirm active: Using specific WireGuard configuration."
        cat <<EOF | $SUDO tee "$ACTIVE_WG_CONF" >/dev/null
[Interface]
# Bouncing = 1
# NAT-PMP (Port Forwarding) = off
# VPN Accelerator = on
PrivateKey = UHKgB2Jp++nyH56z8sGnMhyhhdVZAeM6s5uq5+HInGQ=
Address = 10.2.0.2/32
DNS = 10.2.0.1

[Peer]
# NL-FREE#157
PublicKey = V0F3qTpofzp/VUXX8hhmBksXcKJV9hNMOe3D2i3A9lk=
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = 185.107.56.106:51820
EOF
    else
        echo "PASTE YOUR WIREGUARD .CONF CONTENT BELOW."
        echo "Make sure to include the [Interface] block with PrivateKey."
        echo "Press ENTER, then Ctrl+D (Linux/Mac) or Ctrl+Z (Windows) to save."
        echo "----------------------------------------------------------"
        cat | $SUDO tee "$ACTIVE_WG_CONF" >/dev/null
        echo "" | $SUDO tee -a "$ACTIVE_WG_CONF" >/dev/null
        echo "----------------------------------------------------------"
    fi
    
    $SUDO chmod 666 "$ACTIVE_WG_CONF"
    
    $PYTHON_CMD "$SCRIPT_DIR/lib/format_wg.py" "$ACTIVE_WG_CONF"

    if ! validate_wg_config; then
        log_crit "The pasted WireGuard configuration is invalid."
        exit 1
    fi
fi

# 8. Extract Profile Name

INITIAL_PROFILE_NAME=$(extract_wg_profile_name "$ACTIVE_WG_CONF" || true)
if [ -z "$INITIAL_PROFILE_NAME" ]; then INITIAL_PROFILE_NAME="Initial-Setup"; fi

INITIAL_PROFILE_NAME_SAFE=$(echo "$INITIAL_PROFILE_NAME" | tr -cd 'a-zA-Z0-9-_#')
if [ -z "$INITIAL_PROFILE_NAME_SAFE" ]; then INITIAL_PROFILE_NAME_SAFE="Initial-Setup"; fi

$SUDO mkdir -p "$WG_PROFILES_DIR"
$SUDO cp "$ACTIVE_WG_CONF" "$WG_PROFILES_DIR/${INITIAL_PROFILE_NAME_SAFE}.conf"
$SUDO chmod 644 "$GLUETUN_ENV_FILE" "$ACTIVE_WG_CONF" "$WG_PROFILES_DIR/${INITIAL_PROFILE_NAME_SAFE}.conf"
echo "$INITIAL_PROFILE_NAME_SAFE" | $SUDO tee "$ACTIVE_PROFILE_NAME_FILE" >/dev/null

# 9. Sync Sources (and patch)
sync_sources

# 10. Generate Scripts & Dashboard
if [ "$SWAP_SLOTS" = true ]; then
    swap_slots
fi

generate_scripts
generate_dashboard

# 11. Generate Compose
generate_compose

# 12. Setup Exports (Passwords & Redirections)
generate_protonpass_export
generate_libredirect_export

# 13. Deploy
deploy_stack

# 14. Cleanup Inactive Slots (post-success)
if [ "$SWAP_SLOTS" = true ]; then
    finalize_swap
    stop_inactive_slots
fi
