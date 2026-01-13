# --- SECTION 18: IMAGE MANAGEMENT ---

resolve_service_tags() {
  log_info "Resolving service image tags..."
  local srv_upper
  local var_name
  local default_var_name
  local val

  for srv in ${STACK_SERVICES}; do
    srv_upper=$(echo "${srv//-/_}" | tr '[:lower:]' '[:upper:]')
    var_name="${srv_upper}_IMAGE_TAG"
    default_var_name="${srv_upper}_DEFAULT_TAG"

    # Use specific default tag if defined, otherwise 'latest'
    val="${!default_var_name:-latest}"

    if [[ -f "${DOTENV_FILE}" ]] && "${SUDO}" grep -q "^${var_name}=" "${DOTENV_FILE}"; then
      val=$("${SUDO}" grep "^${var_name}=" "${DOTENV_FILE}" | cut -d'=' -f2)
    fi

    export "${var_name}=${val}"
  done
}

pull_critical_images() {
  log_info "Pre-pulling core infrastructure images in parallel..."
  local pids=()
  for img in ${CRITICAL_IMAGES}; do
    pull_with_retry "${img}" &
    pids+=($!)
  done

  local success=true
  for pid in "${pids[@]}"; do
    if ! wait "${pid}"; then
      success=false
    fi
  done

  if [[ "${success}" == "false" ]]; then
    log_crit "One or more critical images failed to pull. Aborting."
    exit 1
  fi
  log_info "All critical images pulled successfully."
}
