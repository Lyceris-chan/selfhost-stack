# --- SECTION 16: STACK ORCHESTRATION & DEPLOYMENT ---
# Execute system deployment and verify global infrastructure integrity.

deploy_stack() {
    if command -v modprobe >/dev/null 2>&1; then
        $SUDO modprobe tun || true
    fi

    # Pre-flight Check: Port 53
    if is_service_enabled "adguard"; then
        log_info "Verifying port 53 availability..."
        if ! check_port_availability 53 "tcp" || ! check_port_availability 53 "udp"; then
            log_warn "Port 53 is already in use on this host."
            log_warn "This will likely cause AdGuard Home to fail."
            log_warn "Please disable systemd-resolved (systemctl disable --now systemd-resolved) or other DNS services."
            if ! ask_confirm "Attempt deployment anyway?"; then
                log_crit "Deployment aborted due to port conflict."
                exit 1
            fi
        fi
    fi

    # Retry wrapper for Docker Compose
    run_compose_up() {
        local args="$*"
        local max_retries=5
        local count=0
        local delay=3
        
        while [ $count -lt $max_retries ]; do
            if $DOCKER_COMPOSE_FINAL_CMD -f "$COMPOSE_FILE" up -d $args; then
                return 0
            fi
            
            exit_code=$?
            log_warn "Docker Compose failed (Exit Code: $exit_code). Retrying in ${delay}s ($((count+1))/$max_retries)..."
            
            # If iptables lock error, wait a bit longer
            sleep $delay
            count=$((count + 1))
            delay=$((delay * 2))
        done
        
        log_crit "Docker Compose failed after $max_retries attempts."
        return 1
    }

    if [ "$PARALLEL_DEPLOY" = true ]; then
        log_info "Parallel Mode Enabled: Launching full stack immediately..."
        run_compose_up --remove-orphans
    else
        # Explicitly launch core infrastructure services first if they are present
        CORE_SERVICES=""
        for srv in hub-api adguard unbound gluetun; do
            if grep -q "^  $srv:" "$COMPOSE_FILE"; then
                CORE_SERVICES="$CORE_SERVICES $srv"
            fi
        done

        if [ -n "$CORE_SERVICES" ]; then
            log_info "Launching core infrastructure services:$CORE_SERVICES..."
            run_compose_up $CORE_SERVICES
        fi

        # Wait for critical backends to be healthy before starting Nginx (dashboard) if they were launched
        if echo "$CORE_SERVICES" | grep -q "hub-api" || echo "$CORE_SERVICES" | grep -q "gluetun"; then
            log_info "Waiting for backend services to stabilize (this may take up to 60s)..."
            for i in $(seq 1 60); do
                HUB_HEALTH="healthy"
                GLU_HEALTH="running"
                
                if echo "$CORE_SERVICES" | grep -q "hub-api"; then
                    HUB_HEALTH=$($DOCKER_CMD inspect --format='{{.State.Health.Status}}' ${CONTAINER_PREFIX}hub-api 2>/dev/null || echo "unknown")
                fi
                if echo "$CORE_SERVICES" | grep -q "gluetun"; then
                    GLU_HEALTH=$($DOCKER_CMD inspect --format='{{.State.Health.Status}}' ${CONTAINER_PREFIX}gluetun 2>/dev/null || echo "unknown")
                fi
                
                if [ "$HUB_HEALTH" = "healthy" ] && [ "$GLU_HEALTH" = "healthy" ]; then
                    log_info "Backends are stable. Finalizing stack launch..."
                    break
                fi
                [ "$i" -eq 60 ] && log_warn "Backends taking longer than expected to stabilize. Proceeding anyway..."
                sleep 1
            done
        fi

        # Launch the rest of the stack
        # Use --remove-orphans only if we are doing a full deployment
        ORPHAN_FLAG="--remove-orphans"
        if [ -n "$SELECTED_SERVICES" ]; then
            ORPHAN_FLAG=""
        fi
        run_compose_up $ORPHAN_FLAG
    fi

    log_info "Verifying control plane connectivity..."
    sleep 5
    API_TEST=$(curl -s -o /dev/null -w "%{http_code}" "http://$LAN_IP:$PORT_DASHBOARD_WEB/api/status" || echo "FAILED")
    if [ "$API_TEST" = "200" ]; then
        log_info "Control plane is reachable."
    elif [ "$API_TEST" = "401" ]; then
        log_info "Control plane is reachable (Security handshake verified)."
    else
        log_warn "Control plane returned status $API_TEST. The dashboard may show 'Offline (API Error)' initially."
    fi

    # --- SECTION 16.1: PORTAINER AUTOMATION ---
    if [ "$AUTO_PASSWORD" = true ] && grep -q "portainer:" "$COMPOSE_FILE"; then
        log_info "Synchronizing Portainer administrative settings..."
        PORTAINER_READY=false
        for _ in {1..12}; do
            if curl -s --max-time 2 "http://$LAN_IP:$PORT_PORTAINER/api/system/status" > /dev/null; then
                PORTAINER_READY=true
                break
            fi
            sleep 5
        done

        if [ "$PORTAINER_READY" = true ]; then
            # Authenticate to get JWT (user was initialized via --admin-password CLI flag)
            # Try 'admin' first, then 'portainer' (in case it was already renamed in a previous run)
            AUTH_RESPONSE=$(curl -s --max-time 5 -X POST "http://$LAN_IP:$PORT_PORTAINER/api/auth" \
                -H "Content-Type: application/json" \
                -d "{\"Username\":\"admin\",\"Password\":\"$PORTAINER_PASS_RAW\"}" 2>&1 || echo "CURL_ERROR")
            
            if ! echo "$AUTH_RESPONSE" | grep -q "jwt"; then
                AUTH_RESPONSE=$(curl -s --max-time 5 -X POST "http://$LAN_IP:$PORT_PORTAINER/api/auth" \
                    -H "Content-Type: application/json" \
                    -d "{\"Username\":\"portainer\",\"Password\":\"$PORTAINER_PASS_RAW\"}" 2>&1 || echo "CURL_ERROR")
            fi
            
            if echo "$AUTH_RESPONSE" | grep -q "jwt"; then
                PORTAINER_JWT=$(echo "$AUTH_RESPONSE" | sed -n 's/.*"jwt":"\([^"\'']*\).*/\1/p')
                
                # 1. Disable Telemetry/Analytics
                log_info "Disabling Portainer anonymous telemetry..."
                curl -s --max-time 5 -X PUT "http://$LAN_IP:$PORT_PORTAINER/api/settings" \
                    -H "Authorization: Bearer $PORTAINER_JWT" \
                    -H "Content-Type: application/json" \
                    -d '{"EnableTelemetry":false}'>/dev/null 2>&1 || true

                # 2. Rename 'admin' user to 'portainer' (Security Best Practice)
                # First, get user ID of admin (usually 1)
                ADMIN_ID=$(curl -s -H "Authorization: Bearer $PORTAINER_JWT" "http://$LAN_IP:$PORT_PORTAINER/api/users/admin/check" 2>/dev/null | sed -n 's/.*"id":\([0-9]*\).*/\1/p' || echo "1")
                
                # Only rename if not already named 'portainer'
                CHECK_USER=$(curl -s -H "Authorization: Bearer $PORTAINER_JWT" "http://$LAN_IP:$PORT_PORTAINER/api/users/$ADMIN_ID" | sed -n 's/.*"Username":"\([^"\'']*\).*/\1/p')
                if [ "$CHECK_USER" != "portainer" ]; then
                    log_info "Renaming default 'admin' user to 'portainer'..."
                    curl -s --max-time 5 -X PUT "http://$LAN_IP:$PORT_PORTAINER/api/users/$ADMIN_ID" \
                        -H "Authorization: Bearer $PORTAINER_JWT" \
                        -H "Content-Type: application/json" \
                        -d '{"Username":"portainer"}'>/dev/null 2>&1 || true
                fi
            else
                log_warn "Failed to authenticate with Portainer API. Manual telemetry disable may be required."
            fi
        else
            log_warn "Portainer did not become ready in time. Skipping automated configuration."
        fi
    fi

    # --- SECTION 16.2: ASSET LOCALIZATION ---
    # Download remote assets (fonts, utilities) via Gluetun proxy for privacy
    download_remote_assets

    # Final Summary
    echo ""
    echo "=========================================================="
    echo "✅ DEPLOYMENT COMPLETE"
    echo "=========================================================="
    if [ -n "${DESEC_DOMAIN:-}" ] && [ -f "${AGH_CONF_DIR:-}/ssl.crt" ]; then
        echo "   • Dashboard:    https://${DESEC_DOMAIN}:8443"
        echo "                   (Local IP: http://$LAN_IP:$PORT_DASHBOARD_WEB)"
        echo "   • Secure DNS:   https://$DESEC_DOMAIN/dns-query"
        echo "   • Note:         VERT requires HTTPS to function correctly."
    else
        echo "   • Dashboard:    http://$LAN_IP:$PORT_DASHBOARD_WEB"
        if [ -n "${DESEC_DOMAIN:-}" ]; then
            echo "   • Secure DNS:   https://$DESEC_DOMAIN/dns-query"
        fi
    fi
    echo "   • Admin Pass:   $ADMIN_PASS_RAW"
    echo "   • Portainer:    http://$LAN_IP:$PORT_PORTAINER (User: portainer / Pass: $PORTAINER_PASS_RAW)"
    echo "   • WireGuard:    http://$LAN_IP:$PORT_WG_WEB (Pass: $VPN_PASS_RAW)"
    echo "   • AdGuard:      http://$LAN_IP:$PORT_ADGUARD_WEB (User: adguard / Pass: $AGH_PASS_RAW)"
    if [ -n "$ODIDO_TOKEN" ]; then
    echo "   • Odido Boost:  Active (Threshold: 100MB)"
    fi
    echo ""
    echo "   📁 Credentials saved to: $BASE_DIR/.secrets"
    echo "   📄 Importable CSV:      $BASE_DIR/protonpass_import.csv"
    echo "   📄 LibRedirect JSON:    $PROJECT_ROOT/libredirect_import.json"
    echo "=========================================================="
    
    if [ "$CLEAN_EXIT" = true ]; then
        exit 0
    fi

    # Cleanup build artifacts to save space after successful deployment
    cleanup_build_artifacts
}
