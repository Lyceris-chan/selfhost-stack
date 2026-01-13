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

# 1. Core Logic
source "${SCRIPT_DIR}/lib/core/core.sh"

# 2. Service Logic
source "${SCRIPT_DIR}/lib/core/loader.sh"

# 3. Operations Logic
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
  # 1. Cleanup & Reset
  if [[ "${CLEAN_ONLY}" == "true" ]]; then
    clean_environment
    log_info "Clean-only mode enabled. Deployment skipped."
    exit 0
  fi

  # 2. Clean Environment
  clean_environment
  init_directories

  # 4. Pre-pull Critical Images
  log_info "Pre-pulling core infrastructure images in parallel..."
  resolve_service_tags
  pull_critical_images

  # 5. Network & Directories
  allocate_subnet
  detect_network
  setup_static_assets

  # 7. WireGuard Config
  echo ""
  echo "==========================================================="
  echo " PROTON WIREGUARD CONFIGURATION"
  echo "==========================================================="
  echo ""

  if validate_wg_config; then
    log_info "Existing WireGuard config found and validated."
  else
    if [[ -f "${ACTIVE_WG_CONF}" ]] && [[ -s "${ACTIVE_WG_CONF}" ]]; then
      log_warn "Existing WireGuard config was invalid/empty. Removed."
      rm "${ACTIVE_WG_CONF}"
    fi

    if [[ -n "${WG_CONF_B64:-}" ]]; then
      log_info "WireGuard configuration provided in environment. Decoding..."
      echo "${WG_CONF_B64}" | base64 -d | ${SUDO} tee "${ACTIVE_WG_CONF}" >/dev/null
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

    if ! validate_wg_config; then
      log_crit "The pasted WireGuard configuration is invalid."
      exit 1
    fi
  fi

  # 6. Auth & Secrets
  setup_secrets
  setup_configs

  # 8. Extract Profile Name
  local initial_profile_name
  initial_profile_name=$(extract_wg_profile_name "${ACTIVE_WG_CONF}" || echo "Initial-Setup")

  local initial_profile_name_safe
  initial_profile_name_safe=$(echo "${initial_profile_name}" | tr -cd 'a-zA-Z0-9-_#')
  [[ -z "${initial_profile_name_safe}" ]] && initial_profile_name_safe="Initial-Setup"

  ${SUDO} mkdir -p "${WG_PROFILES_DIR}"
  ${SUDO} cp "${ACTIVE_WG_CONF}" "${WG_PROFILES_DIR}/${initial_profile_name_safe}.conf"
  ${SUDO} chmod 600 "${ACTIVE_WG_CONF}" "${WG_PROFILES_DIR}/${initial_profile_name_safe}.conf"
  echo "${initial_profile_name_safe}" | ${SUDO} tee "${ACTIVE_PROFILE_NAME_FILE}" >/dev/null

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

  if [[ "${GENERATE_ONLY}" == "true" ]]; then
    log_info "Generation complete. Skipping deployment (-G flag active)."
    exit 0
  fi

  # 13. Deploy
  deploy_stack
}

main "$@"


