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

# 1. Core Logic (Utils, Init, Network, Auth) - Defines: log_info, log_warn, log_crit, ask_confirm, pull_with_retry, detect_dockerfile, allocate_subnet, safe_remove_network, detect_network, validate_wg_config, extract_wg_profile_name, authenticate_registries, setup_secrets, generate_protonpass_export
source "$SCRIPT_DIR/lib/core.sh"

# 2. Service Logic (Sources, Scripts, Configs, Compose, Dashboard) - Defines: sync_sources, generate_scripts, setup_static_assets, download_remote_assets, setup_configs, generate_libredirect_export, generate_compose, generate_dashboard
source "$SCRIPT_DIR/lib/services.sh"

# 3. Operations Logic (Cleanup, Backup, Deploy) - Defines: check_docker_rate_limit, check_cert_risk, clean_environment, cleanup_build_artifacts, perform_backup, swap_slots, finalize_swap, stop_inactive_slots, deploy_stack
source "$SCRIPT_DIR/lib/operations.sh"

# --- Error Handling ---
failure_handler() {
    local lineno=$1
    local msg=$2
    if command -v log_crit >/dev/null 2>&1; then
        log_crit "Deployment failed at line $lineno: $msg"
    else
        echo "[CRIT] Deployment failed at line $lineno: $msg"
    fi
}
trap 'failure_handler ${LINENO} "$BASH_COMMAND"' ERR

# --- Main Execution Flow ---

# 1. Cleanup & Reset
if [ "$CLEAN_ONLY" = true ]; then
    clean_environment # (from lib/operations.sh)
    log_info "Clean-only mode enabled. Deployment skipped." # (from lib/core.sh)
    exit 0
fi

# 2. Registry Authentication
authenticate_registries # (from lib/core.sh)

# 3. Clean Environment (if not clean-only, already handled above if clean-only)
clean_environment # (from lib/operations.sh)

# 4. Pre-pull Critical Images
log_info "Pre-pulling core infrastructure images in parallel..." # (from lib/core.sh)
$SUDO mkdir -p "$BASE_DIR"
DOTENV_FILE="$BASE_DIR/.env"
if [ ! -f "$DOTENV_FILE" ]; then $SUDO touch "$DOTENV_FILE"; fi
$SUDO chmod 666 "$DOTENV_FILE"

# AB_SERVICES and CRITICAL_IMAGES are defined in lib/constants.sh (sourced via lib/core.sh)

for srv in $AB_SERVICES; do
    SRV_UPPER=$(echo "${srv//-/_}" | tr '[:lower:]' '[:upper:]')
    VAR_NAME="${SRV_UPPER}_IMAGE_TAG"
    SLOT_VAR_NAME="${VAR_NAME}_${CURRENT_SLOT^^}"
    DEFAULT_VAR_NAME="${SRV_UPPER}_DEFAULT_TAG"
    
    # Determine the default value from constants.sh
    DEFAULT_VAL="${!DEFAULT_VAR_NAME:-latest}"

    # 1. Check if slot-specific tag exists in .env
    if grep -q "^$SLOT_VAR_NAME=" "$DOTENV_FILE"; then
        val=$(grep "^$SLOT_VAR_NAME=" "$DOTENV_FILE" | cut -d'=' -f2)
    # 2. Check if global tag exists in .env
    elif grep -q "^$VAR_NAME=" "$DOTENV_FILE"; then
        val=$(grep "^$VAR_NAME=" "$DOTENV_FILE" | cut -d'=' -f2)
    # 3. Use default from constants.sh
    else
        val="$DEFAULT_VAL"
        echo "$VAR_NAME=$val" | $SUDO tee -a "$DOTENV_FILE" >/dev/null
    fi
    
    export "$VAR_NAME=$val"
done

PIDS=""
for img in $CRITICAL_IMAGES; do
    pull_with_retry "$img" & # (from lib/core.sh)
    PIDS="$PIDS $!"
done

SUCCESS=true
for pid in $PIDS; do
    if ! wait "$pid"; then
        SUCCESS=false
    fi
done

if [ "$SUCCESS" = false ]; then
    log_crit "One or more critical images failed to pull. Aborting." # (from lib/core.sh)
    exit 1
fi
log_info "All critical images pulled successfully." # (from lib/core.sh)

# 5. Network & Directories
allocate_subnet # (from lib/core.sh)
detect_network # (from lib/core.sh)
setup_static_assets # (from lib/services.sh)

# 6. Auth & Secrets
setup_secrets # (from lib/core.sh)

setup_configs # (from lib/services.sh) Includes DNS/SSL config

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

if validate_wg_config; then # (from lib/core.sh)
    log_info "Existing WireGuard config found and validated. Skipping paste." # (from lib/core.sh)
else
    if [ -f "$ACTIVE_WG_CONF" ] && [ -s "$ACTIVE_WG_CONF" ]; then
        log_warn "Existing WireGuard config was invalid/empty. Removed." # (from lib/core.sh)
        rm "$ACTIVE_WG_CONF"
    fi

    if [ -n "${WG_CONF_B64:-}" ]; then
        log_info "WireGuard configuration provided in environment. Decoding..." # (from lib/core.sh)
        echo "$WG_CONF_B64" | base64 -d | $SUDO tee "$ACTIVE_WG_CONF" >/dev/null
    elif [ "$AUTO_CONFIRM" = true ]; then
        log_crit "Auto-confirm active but no WireGuard configuration provided via environment (WG_CONF_B64)."
        log_info "Please provide a base64-encoded WireGuard configuration in the WG_CONF_B64 environment variable."
        exit 1
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

    if ! validate_wg_config; then # (from lib/core.sh)
        log_crit "The pasted WireGuard configuration is invalid." # (from lib/core.sh)
        exit 1
    fi
fi

# 8. Extract Profile Name

INITIAL_PROFILE_NAME=$(extract_wg_profile_name "$ACTIVE_WG_CONF" || true) # (from lib/core.sh)
if [ -z "$INITIAL_PROFILE_NAME" ]; then INITIAL_PROFILE_NAME="Initial-Setup"; fi

INITIAL_PROFILE_NAME_SAFE=$(echo "$INITIAL_PROFILE_NAME" | tr -cd 'a-zA-Z0-9-_#')
if [ -z "$INITIAL_PROFILE_NAME_SAFE" ]; then INITIAL_PROFILE_NAME_SAFE="Initial-Setup"; fi

$SUDO mkdir -p "$WG_PROFILES_DIR"
$SUDO cp "$ACTIVE_WG_CONF" "$WG_PROFILES_DIR/${INITIAL_PROFILE_NAME_SAFE}.conf"
$SUDO chmod 644 "$GLUETUN_ENV_FILE" "$ACTIVE_WG_CONF" "$WG_PROFILES_DIR/${INITIAL_PROFILE_NAME_SAFE}.conf"
echo "$INITIAL_PROFILE_NAME_SAFE" | $SUDO tee "$ACTIVE_PROFILE_NAME_FILE" >/dev/null

# 9. Sync Sources (and patch)
sync_sources # (from lib/services.sh)

# 10. Generate Scripts & Dashboard
if [ "$SWAP_SLOTS" = true ]; then
    swap_slots # (from lib/operations.sh)
fi

generate_scripts # (from lib/services.sh)
generate_dashboard # (from lib/services.sh)

# 11. Generate Compose
generate_compose # (from lib/services.sh)

# 12. Setup Exports (Passwords & Redirections)
generate_protonpass_export # (from lib/core.sh)
generate_libredirect_export # (from lib/services.sh)

if [ "$GENERATE_ONLY" = true ]; then
    log_info "Generation complete. Skipping deployment (-G flag active)."
    exit 0
fi

# 13. Deploy
deploy_stack # (from lib/operations.sh)

# 14. Cleanup Inactive Slots (post-success)
if [ "$SWAP_SLOTS" = true ]; then
    if verify_health; then
        finalize_swap # (from lib/operations.sh)
        stop_inactive_slots # (from lib/operations.sh)
    else
        log_crit "Deployment health verification FAILED for the new slot. SWAP ABORTED."
        log_warn "The inactive slot has NOT been cleaned up to allow for investigation."
        log_warn "Active slot remains unchanged in state file."
        exit 1
    fi
fi
