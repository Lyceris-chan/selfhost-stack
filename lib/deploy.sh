#!/usr/bin/env bash

# --- SECTION 16: STACK ORCHESTRATION & DEPLOYMENT ---
# Execute system deployment and verify global infrastructure integrity.

deploy_stack() {
    if command -v modprobe >/dev/null 2>&1; then
        $SUDO modprobe tun || true
    fi

    if [ "$PARALLEL_DEPLOY" = true ]; then
        log_info "Parallel Mode Enabled: Launching full stack immediately..."
        $DOCKER_COMPOSE_FINAL_CMD -f "$COMPOSE_FILE" up -d --build --remove-orphans
    else
        # Explicitly launch core infrastructure services first
        log_info "Launching core infrastructure services..."
        $DOCKER_COMPOSE_FINAL_CMD -f "$COMPOSE_FILE" up -d --build hub-api adguard unbound gluetun

        # Wait for critical backends to be healthy before starting Nginx (dashboard)
        log_info "Waiting for backend services to stabilize (this may take up to 60s)..."
        for i in $(seq 1 60); do
            HUB_HEALTH=$($DOCKER_CMD inspect --format='{{.State.Health.Status}}' ${CONTAINER_PREFIX}hub-api 2>/dev/null || echo "unknown")
            GLU_HEALTH=$($DOCKER_CMD inspect --format='{{.State.Status}}' ${CONTAINER_PREFIX}gluetun 2>/dev/null || echo "unknown")
            
            if [ "$HUB_HEALTH" = "healthy" ] && [ "$GLU_HEALTH" = "running" ]; then
                log_info "Backends are stable. Finalizing stack launch..."
                break
            fi
            [ "$i" -eq 60 ] && log_warn "Backends taking longer than expected to stabilize. Proceeding anyway..."
            sleep 1
        done

        # Launch the rest of the stack
        $DOCKER_COMPOSE_FINAL_CMD -f "$COMPOSE_FILE" up -d --remove-orphans
    fi

    log_info "Verifying control plane connectivity..."
    sleep 5
    API_TEST=$(curl -s -o /dev/null -w "% {http_code}" "http://$LAN_IP:$PORT_DASHBOARD_WEB/api/status" || echo "FAILED")
    if [ "$API_TEST" = "200" ]; then
        log_info "Control plane is reachable."
    elif [ "$API_TEST" = "401" ]; then
        log_info "Control plane is reachable (Security handshake verified)."
    else
        log_warn "Control plane returned status $API_TEST. The dashboard may show 'Offline (API Error)' initially."
    fi

    # --- SECTION 16.1: PORTAINER AUTOMATION ---
    if [ "$AUTO_PASSWORD" = true ]; then
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
                PORTAINER_JWT=$(echo "$AUTH_RESPONSE" | grep -oP '"jwt":"\K[^"']+')
                
                # 1. Disable Telemetry/Analytics
                log_info "Disabling Portainer anonymous telemetry..."
                curl -s --max-time 5 -X PUT "http://$LAN_IP:$PORT_PORTAINER/api/settings" \
                    -H "Authorization: Bearer $PORTAINER_JWT" \
                    -H "Content-Type: application/json" \
                    -d '{"EnableTelemetry":false}' >/dev/null 2>&1 || true

                # 2. Rename 'admin' user to 'portainer' (Security Best Practice)
                # First, get user ID of admin (usually 1)
                ADMIN_ID=$(curl -s -H "Authorization: Bearer $PORTAINER_JWT" "http://$LAN_IP:$PORT_PORTAINER/api/users/admin/check" 2>/dev/null | grep -oP 'id":\K\d+' || echo "1")
                
                # Only rename if not already named 'portainer'
                CHECK_USER=$(curl -s -H "Authorization: Bearer $PORTAINER_JWT" "http://$LAN_IP:$PORT_PORTAINER/api/users/$ADMIN_ID" | grep -oP '"Username":"\K[^"']+')
                if [ "$CHECK_USER" != "portainer" ]; then
                    log_info "Renaming default 'admin' user to 'portainer'..."
                    curl -s --max-time 5 -X PUT "http://$LAN_IP:$PORT_PORTAINER/api/users/$ADMIN_ID" \
                        -H "Authorization: Bearer $PORTAINER_JWT" \
                        -H "Content-Type: application/json" \
                        -d '{"Username":"portainer"}' >/dev/null 2>&1 || true
                fi
            else
                log_warn "Failed to authenticate with Portainer API. Manual telemetry disable may be required."
            fi
        else
            log_warn "Portainer did not become ready in time. Skipping automated configuration."
        fi
    fi

    # Final Summary
    echo ""
    echo "=========================================================="
    echo "✅ DEPLOYMENT COMPLETE"
    echo "=========================================================="
    echo "   • Dashboard:    http://$LAN_IP:$PORT_DASHBOARD_WEB"
    if [ -n "$DESEC_DOMAIN" ]; then
    echo "   • Secure DNS:   https://$DESEC_DOMAIN/dns-query"
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
    echo "   📄 Importable CSV: $BASE_DIR/protonpass_import.csv"
    echo "=========================================================="
    
    if [ "$CLEAN_EXIT" = true ]; then
        exit 0
    fi
}
