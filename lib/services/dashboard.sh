#!/usr/bin/env bash
set -euo pipefail

generate_dashboard() {
  log_info "Generating Dashboard UI from template..."

  local template="${SCRIPT_DIR}/lib/templates/dashboard.html"
  local css_file="${SCRIPT_DIR}/lib/templates/assets/dashboard.css"
  local js_file="${SCRIPT_DIR}/lib/templates/assets/dashboard.js"

  if [[ ! -f "${template}" ]]; then
    log_crit "Dashboard template not found at ${template}"
    return 1
  fi

  # Initialize dashboard file from template
  cat "${template}" > "${DASHBOARD_FILE}"

  # Inject CSS (Replace placeholder with file content)
  sed -i "/{{HUB_CSS}}/{
    r ${css_file}
    d
  }" "${DASHBOARD_FILE}"

  # Inject JS (Replace placeholder with file content)
  sed -i "/{{HUB_JS}}/{
    r ${js_file}
    d
  }" "${DASHBOARD_FILE}"

  # Perform variable substitutions
  sed -i "s|\$LAN_IP|${LAN_IP}|g" "${DASHBOARD_FILE}"
  sed -i "s|\$DESEC_DOMAIN|${DESEC_DOMAIN}|g" "${DASHBOARD_FILE}"
  sed -i "s|\$PORT_PORTAINER|${PORT_PORTAINER}|g" "${DASHBOARD_FILE}"
  sed -i "s|\$BASE_DIR|${BASE_DIR}|g" "${DASHBOARD_FILE}"
  sed -i "s|\$PORT_DASHBOARD_WEB|${PORT_DASHBOARD_WEB}|g" "${DASHBOARD_FILE}"
  sed -i "s|\$APP_NAME|${APP_NAME}|g" "${DASHBOARD_FILE}"

  log_info "Dashboard generated successfully at ${DASHBOARD_FILE}"
}