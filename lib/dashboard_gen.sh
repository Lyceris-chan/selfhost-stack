#!/usr/bin/env bash
generate_dashboard() {
    log_info "Generating Dashboard UI from template..."

    local template="$BASE_DIR/../../../templates/dashboard.html"
    local css_file="$BASE_DIR/../../../templates/assets/dashboard.css"
    local js_file="$BASE_DIR/../../../templates/assets/dashboard.js"

    if [ ! -f "$template" ]; then
        log_error "Dashboard template not found at $template"
        return 1
    fi

    # Initialize dashboard file from template
    cat "$template" > "$DASHBOARD_FILE"

    # Inject CSS (Replace placeholder with file content)
    # Using a temporary file to avoid sed issues with large inclusions
    sed -i "/{{DHI_CSS}}/{
        r $css_file
        d
    }" "$DASHBOARD_FILE"

    # Inject JS (Replace placeholder with file content)
    sed -i "/{{DHI_JS}}/{
        r $js_file
        d
    }" "$DASHBOARD_FILE"

    # Perform variable substitutions
    # Note: Using | as delimiter because some variables might contain /
    sed -i "s|\$LAN_IP|$LAN_IP|g" "$DASHBOARD_FILE"
    sed -i "s|\$DESEC_DOMAIN|$DESEC_DOMAIN|g" "$DASHBOARD_FILE"
    sed -i "s|\$PORT_PORTAINER|$PORT_PORTAINER|g" "$DASHBOARD_FILE"
    sed -i "s|\$BASE_DIR|$BASE_DIR|g" "$DASHBOARD_FILE"
    sed -i "s|\$PORT_DASHBOARD_WEB|$PORT_DASHBOARD_WEB|g" "$DASHBOARD_FILE"
    sed -i "s|\$APP_NAME|$APP_NAME|g" "$DASHBOARD_FILE"
    sed -i "s|\$ENABLE_XRAY|$ENABLE_XRAY|g" "$DASHBOARD_FILE"
    sed -i "s|\$XRAY_DOMAIN|$XRAY_DOMAIN|g" "$DASHBOARD_FILE"
    sed -i "s|\$XRAY_UUID|$XRAY_UUID|g" "$DASHBOARD_FILE"
    sed -i "s|\\\${CURRENT_SLOT}|$CURRENT_SLOT|g" "$DASHBOARD_FILE"
    sed -i "s|\$CURRENT_SLOT|$CURRENT_SLOT|g" "$DASHBOARD_FILE"

    log_info "Dashboard generated successfully at $DASHBOARD_FILE"
}