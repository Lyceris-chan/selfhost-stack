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

# Source libraries
source lib/utils.sh
source lib/init.sh
source lib/cleanup.sh
source lib/network.sh
source lib/auth.sh
source lib/config_gen.sh
source lib/dashboard_gen.sh
source lib/sources.sh
source lib/scripts.sh
source lib/compose_gen.sh
source lib/deploy.sh
source lib/xray.sh
source lib/backup.sh

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
mkdir -p "$BASE_DIR"
DOTENV_FILE="$BASE_DIR/.env"
if [ ! -f "$DOTENV_FILE" ]; then touch "$DOTENV_FILE"; fi

# Define all services that use the A/B scheme
AB_SERVICES="hub-api odido-booster memos gluetun portainer adguard unbound wg-easy redlib wikiless invidious rimgo breezewiki anonymousoverflow scribe vert vertd companion"

for srv in $AB_SERVICES; do
    VAR_NAME="${srv//-/_}_IMAGE_TAG"
    VAR_NAME=$(echo $VAR_NAME | tr '[:lower:]' '[:upper:]')
    if ! grep -q "^$VAR_NAME=" "$DOTENV_FILE"; then
        echo "$VAR_NAME=latest" >> "$DOTENV_FILE"
    fi
    val=$(grep "^$VAR_NAME=" "$DOTENV_FILE" | cut -d'=' -f2)
    export "$VAR_NAME=$val"
done

CRITICAL_IMAGES="dhi.io/nginx:1.28-alpine3.21 dhi.io/python:3.11-alpine3.22-dev dhi.io/node:20-alpine3.22-dev dhi.io/bun:1-alpine3.22-dev dhi.io/alpine-base:3.22 dhi.io/alpine-base:3.22-dev dhi.io/redis:7.2-debian dhi.io/postgres:14-alpine3.22 neilpang/acme.sh"

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
detECT_NETWORK
setup_assets
setup_configs # Includes DNS/SSL config

# 6. Auth & Secrets
setup_secrets

# 7. WireGuard Config
echo ""
echo "==========================================================="
echo " PROTON WIREGUARD CONFIGURATION"
echo "==========================================================="

validate_wg_config() {
    if [ ! -s "$ACTIVE_WG_CONF" ]; then return 1; fi
    if ! grep -q "PrivateKey" "$ACTIVE_WG_CONF"; then return 1; fi
    local PK_VAL
    PK_VAL=$(grep "PrivateKey" "$ACTIVE_WG_CONF" | cut -d'=' -f2 | tr -d '[:space:]')
    if [ -z "$PK_VAL" ]; then return 1; fi
    if [ "${#PK_VAL}" -lt 40 ]; then return 1; fi
    return 0
}

if validate_wg_config; then
    log_info "Existing WireGuard config found and validated. Skipping paste."
else
    if [ -f "$ACTIVE_WG_CONF" ] && [ -s "$ACTIVE_WG_CONF" ]; then
        log_warn "Existing WireGuard config was invalid/empty. Removed."
        rm "$ACTIVE_WG_CONF"
    fi

    if [ -n "${WG_CONF_B64:-}" ]; then
        log_info "WireGuard configuration provided in environment. Decoding..."
        echo "$WG_CONF_B64" | base64 -d > "$ACTIVE_WG_CONF"
    else
        echo "PASTE YOUR WIREGUARD .CONF CONTENT BELOW."
        echo "Make sure to include the [Interface] block with PrivateKey."
        echo "Press ENTER, then Ctrl+D (Linux/Mac) or Ctrl+Z (Windows) to save."
        echo "----------------------------------------------------------"
        cat > "$ACTIVE_WG_CONF"
        echo "" >> "$ACTIVE_WG_CONF" 
        echo "----------------------------------------------------------"
    fi
    
    $PYTHON_CMD lib/format_wg.py "$ACTIVE_WG_CONF"

    if ! validate_wg_config; then
        log_crit "The pasted WireGuard configuration is invalid."
        exit 1
    fi
fi

# 8. Extract Profile Name
extract_wg_profile_name() {
    local config_file="$1"
    local in_peer=0
    local profile_name=""
    while IFS= read -r line; do
        stripped=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if echo "$stripped" | grep -qi '^\[peer\]$'; then in_peer=1; continue; fi
        if [ "$in_peer" -eq 1 ] && echo "$stripped" | grep -q '^#'; then
            profile_name=$(echo "$stripped" | sed 's/^#[[:space:]]*//')
            if [ -n "$profile_name" ]; then echo "$profile_name"; return 0; fi
        fi
        if [ "$in_peer" -eq 1 ] && echo "$stripped" | grep -q '^\['; then break; fi
    done < "$config_file"
    while IFS= read -r line; do
        stripped=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if echo "$stripped" | grep -q '^#' && ! echo "$stripped" | grep -q '='; then
            profile_name=$(echo "$stripped" | sed 's/^#[[:space:]]*//')
            if [ -n "$profile_name" ]; then echo "$profile_name"; return 0; fi
        fi
    done < "$config_file"
    return 1
}

INITIAL_PROFILE_NAME=$(extract_wg_profile_name "$ACTIVE_WG_CONF" || true)
if [ -z "$INITIAL_PROFILE_NAME" ]; then INITIAL_PROFILE_NAME="Initial-Setup"; fi
INITIAL_PROFILE_NAME_SAFE=$(echo "$INITIAL_PROFILE_NAME" | tr -cd 'a-zA-Z0-9-_#')
if [ -z "$INITIAL_PROFILE_NAME_SAFE" ]; then INITIAL_PROFILE_NAME_SAFE="Initial-Setup"; fi

cp "$ACTIVE_WG_CONF" "$WG_PROFILES_DIR/${INITIAL_PROFILE_NAME_SAFE}.conf"
chmod 644 "$GLUETUN_ENV_FILE" "$ACTIVE_WG_CONF" "$WG_PROFILES_DIR/${INITIAL_PROFILE_NAME_SAFE}.conf"
echo "$INITIAL_PROFILE_NAME_SAFE" > "$ACTIVE_PROFILE_NAME_FILE"

# 9. Sync Sources (and patch)
sync_sources

# 10. Generate Scripts & Dashboard
if [ "$SWAP_SLOTS" = true ]; then
    swap_slots
fi

generate_scripts
generate_dashboard
setup_xray

# 11. Generate Compose
generate_compose
patch_compose_xray
generate_xray_readme

# 12. Setup Proton Pass Export
generate_protonpass_export

# 13. Deploy
deploy_stack

# 14. Cleanup Inactive Slots (post-success)
if [ "$SWAP_SLOTS" = true ]; then
    stop_inactive_slots
fi