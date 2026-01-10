# --- SECTION 18: IMAGE MANAGEMENT ---

resolve_service_tags() {
    log_info "Resolving service image tags..."
    for srv in $STACK_SERVICES; do
        SRV_UPPER=$(echo "${srv//-/_}" | tr '[:lower:]' '[:upper:]')
        VAR_NAME="${SRV_UPPER}_IMAGE_TAG"
        DEFAULT_VAR_NAME="${SRV_UPPER}_DEFAULT_TAG"
        
        # Use specific default tag if defined, otherwise 'latest'
        val="${!DEFAULT_VAR_NAME:-latest}"

        if [ -f "$DOTENV_FILE" ] && $SUDO grep -q "^$VAR_NAME=" "$DOTENV_FILE"; then
            val=$($SUDO grep "^$VAR_NAME=" "$DOTENV_FILE" | cut -d'=' -f2)
        fi
        
        export "$VAR_NAME=$val"
    done
}

pull_critical_images() {
    log_info "Pre-pulling core infrastructure images in parallel..."
    local PIDS=""
    for img in $CRITICAL_IMAGES; do
        pull_with_retry "$img" &
        PIDS="$PIDS $!"
    done

    local SUCCESS=true
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
}
