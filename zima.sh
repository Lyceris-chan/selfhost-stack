#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2001,SC2015,SC2016,SC2034,SC2024,SC2086
set -euo pipefail

# ==============================================================================
# 🛡️ ZIMAOS PRIVACY HUB: SECURE NETWORK STACK
# ==============================================================================
# This deployment provides a self-hosted network security environment.
# Digital independence requires ownership of the hardware and software that
# manages your data.
# ==============================================================================

# Source Consolidated Libraries
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_DIR

# Core Logic
source "${SCRIPT_DIR}/lib/core/core.sh"

# Service Logic
source "${SCRIPT_DIR}/lib/core/loader.sh"

# Operations Logic
source "${SCRIPT_DIR}/lib/core/operations.sh"

# --- Error Handling ---
failure_handler() {
  local lineno="$1"
  local msg="$2"
  if command -v log_crit >/dev/null 2>&1; then
    log_crit "Deployment failed at line ${lineno}: ${msg}"
  else
    echo "[CRIT] Deployment failed at line ${lineno}: ${msg}"
  fi

  if [[ -f "${HISTORY_LOG:-}" ]] && [[ -s "${HISTORY_LOG}" ]]; then
    echo "--- Last 5 Log Entries ---"
    tail -n 5 "${HISTORY_LOG}"
    echo "--------------------------"
  fi
  log_info "Check the full log at: ${HISTORY_LOG:-$BASE_DIR/deployment.log}"
}
trap 'failure_handler ${LINENO} "$BASH_COMMAND"' ERR

# --- Main Execution Flow ---

main() {
  # Cleanup & Reset (Immediate Exit)
  if [[ "${CLEAN_ONLY}" == "true" ]]; then
    clean_environment
    log_info "Clean-only mode enabled. Skipping deployment."
    exit 0
  fi

  # Backup & Restore (Immediate Exit)
  if [[ "${DO_BACKUP}" == "true" ]]; then
    perform_backup "manual"
    exit 0
  fi

  if [[ -n "${RESTORE_FILE}" ]]; then
    perform_restore "${RESTORE_FILE}"
    exit 0
  fi

  # Initialization & Network Detection
  # Required for subsequent prompts (e.g., deSEC needs PUBLIC_IP)
  clean_environment
  init_directories
  allocate_subnet
  detect_network

  # WireGuard Configuration Prompt (Requirement 1)
  echo ""
  echo "==========================================================="
  echo " PROTON WIREGUARD CONFIGURATION"
  echo "==========================================================="
  echo ""

  if validate_wg_config; then
    log_info "System found and validated existing WireGuard config."
  else
    if [[ -f "${ACTIVE_WG_CONF}" ]] && [[ -s "${ACTIVE_WG_CONF}" ]]; then
      log_warn "Existing WireGuard config was invalid/empty. Removed."
      rm "${ACTIVE_WG_CONF}"
    fi

    if [[ -n "${WG_CONF_B64:-}" ]]; then
      log_info "System detected WireGuard configuration in environment. Decoding..."
      echo "${WG_CONF_B64}" | base64 -d | ${SUDO} tee "${ACTIVE_WG_CONF}" >/dev/null

      if [[ ! -s "${ACTIVE_WG_CONF}" ]]; then
        log_crit "Failed to decode WireGuard config from environment variables. File is empty."
        exit 1
      fi

      if ! grep -q "Endpoint" "${ACTIVE_WG_CONF}" || ! grep -q "PublicKey" "${ACTIVE_WG_CONF}"; then
        log_crit "Decoded WireGuard config is missing required fields (Endpoint/PublicKey)."
        exit 1
      fi
    elif [[ "${AUTO_CONFIRM}" == "true" ]]; then
      log_crit "Auto-confirm active but no WireGuard configuration provided via environment."
      exit 1
    else
      echo "PASTE YOUR WIREGUARD .CONF CONTENT BELOW."
      echo "Press Enter, then Ctrl+D (or Cmd+D on some Mac terminals) to finish."
      echo "----------------------------------------------------------"
      cat | ${SUDO} tee "${ACTIVE_WG_CONF}" >/dev/null
      echo "" | ${SUDO} tee -a "${ACTIVE_WG_CONF}" >/dev/null
      echo "----------------------------------------------------------"
    fi

    ${SUDO} chmod 600 "${ACTIVE_WG_CONF}"
    "${PYTHON_CMD}" "${SCRIPT_DIR}/lib/utils/format_wg.py" "${ACTIVE_WG_CONF}"

    if [[ ! -s "${ACTIVE_WG_CONF}" ]]; then
      log_crit "WireGuard config is empty after formatting. Check format_wg.py."
      exit 1
    fi

    if ! validate_wg_config; then
      log_crit "The pasted WireGuard configuration is invalid."
      exit 1
    fi
  fi

  # Auth & Secrets Prompt (Requirements 2 & 3: deSEC and Passwords)
  setup_secrets

  # Background Operations (Now that user interaction is complete)
  log_info "Interactions complete. Starting background infrastructure preparation..."

  setup_static_assets

  log_info "Pre-pulling core infrastructure images sequentially..."
  resolve_service_tags
  pull_critical_images

  # Configuration Compilation
  setup_configs

  # Extract Profile Name
  local initial_profile_name
  initial_profile_name=$(extract_wg_profile_name "${ACTIVE_WG_CONF}" || echo "Initial-Setup")

  local initial_profile_name_safe
  initial_profile_name_safe=$(echo "${initial_profile_name}" | tr -cd 'a-zA-Z0-9-_#')
  [[ -z "${initial_profile_name_safe}" ]] && initial_profile_name_safe="Initial-Setup"

  ${SUDO} mkdir -p "${WG_PROFILES_DIR}"
  ${SUDO} cp "${ACTIVE_WG_CONF}" "${WG_PROFILES_DIR}/${initial_profile_name_safe}.conf"
  ${SUDO} chmod 600 "${ACTIVE_WG_CONF}" "${WG_PROFILES_DIR}/${initial_profile_name_safe}.conf"
  echo "${initial_profile_name_safe}" | ${SUDO} tee "${ACTIVE_PROFILE_NAME_FILE}" >/dev/null

  # Sync Sources
  sync_sources

  # Generate Scripts & Dashboard
  generate_scripts
  generate_dashboard

  # Generate Compose
  generate_compose

  # Setup Exports
  generate_protonpass_export
  generate_libredirect_export

  if [[ "${GENERATE_ONLY}" == "true" ]]; then
    log_info "Generation complete. Skipping deployment (-G flag active)."
    exit 0
  fi

  # Deploy
  deploy_stack
}

main "$@"
