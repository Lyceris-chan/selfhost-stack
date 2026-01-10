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

# 1. Core Logic (Utils, Init, Network, Auth) - Defines: log_info, log_warn, log_crit, ask_confirm, pull_with_retry, detect_dockerfile, allocate_subnet, safe_remove_network, detect_network, validate_wg_config, extract_wg_profile_name, setup_secrets, generate_protonpass_export
source "$SCRIPT_DIR/lib/core.sh"

# 2. Service Logic (Sources, Scripts, Configs, Compose, Dashboard) - Defines: sync_sources, generate_scripts, setup_static_assets, download_remote_assets, setup_configs, generate_libredirect_export, generate_compose, generate_dashboard
source "$SCRIPT_DIR/lib/services.sh"

# 3. Operations Logic (Cleanup, Backup, Deploy) - Defines: check_docker_rate_limit, check_cert_risk, clean_environment, cleanup_build_artifacts, perform_backup, deploy_stack
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
    
    if [ -f "${HISTORY_LOG:-}" ] && [ -s "$HISTORY_LOG" ]; then
        echo "--- Last 5 Log Entries ---"
        tail -n 5 "$HISTORY_LOG"
        echo "--------------------------"
    fi
    log_info "Check the full log at: ${HISTORY_LOG:-$BASE_DIR/deployment.log}"
}
trap 'failure_handler ${LINENO} "$BASH_COMMAND"' ERR

# --- Main Execution Flow ---

# 1. Cleanup & Reset
if [ "$CLEAN_ONLY" = true ]; then
    clean_environment
    log_info "Clean-only mode enabled. Deployment skipped."
    exit 0
fi

# 2. Clean Environment (if not clean-only, already handled above if clean-only)
clean_environment
init_directories

# 4. Pre-pull Critical Images
log_info "Pre-pulling core infrastructure images in parallel..."

# STACK_SERVICES and CRITICAL_IMAGES are defined in lib/constants.sh

# 4. Image Tag Resolution & Pre-pull
resolve_service_tags
pull_critical_images


# 5. Network & Directories
allocate_subnet
detect_network
setup_static_assets

# 6. Auth & Secrets
setup_secrets

setup_configs

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
        log_crit "Auto-confirm active but no WireGuard configuration provided via environment (WG_CONF_B64)."
        exit 1
    else
        echo "PASTE YOUR WIREGUARD .CONF CONTENT BELOW."
        echo "----------------------------------------------------------"
        cat | $SUDO tee "$ACTIVE_WG_CONF" >/dev/null
        echo "" | $SUDO tee -a "$ACTIVE_WG_CONF" >/dev/null
        echo "----------------------------------------------------------"
    fi
    
    $SUDO chmod 600 "$ACTIVE_WG_CONF"
    $PYTHON_CMD "$SCRIPT_DIR/lib/scripts/format_wg.py" "$ACTIVE_WG_CONF"

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

# 9. Sync Sources
sync_sources

# 10. Generate Scripts & Dashboard
generate_scripts
generate_dashboard

# 11. Generate Compose
generate_compose

# 12. Setup Exports
generate_protonpass_export
generate_libredirect_export

if [ "$GENERATE_ONLY" = true ]; then
    log_info "Generation complete. Skipping deployment (-G flag active)."
    exit 0
fi

# 13. Deploy
deploy_stack

