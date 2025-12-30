#!/usr/bin/env bash

authenticate_registries() {
    # Export DOCKER_CONFIG globally
    export DOCKER_CONFIG="$DOCKER_AUTH_DIR"
    
    if [ "$AUTO_CONFIRM" = true ] || [ -n "$REG_TOKEN" ] || [ "$PERSONAL_MODE" = true ]; then
        if [ -n "$REG_TOKEN" ]; then
             log_info "Using provided credentials from environment."
        elif [ "$PERSONAL_MODE" = true ]; then
             log_info "Personal Mode: Using pre-configured registry credentials."
             REG_USER="laciachan"
             REG_TOKEN="${REG_TOKEN:-DOCKER_HUB_TOKEN_PLACEHOLDER}"
        else
             log_info "Auto-confirm enabled: Using default/placeholder credentials."
             REG_USER="laciachan"
             REG_TOKEN="DOCKER_HUB_TOKEN_PLACEHOLDER"
        fi
        
        # Docker Hub Login
        if [ "$REG_TOKEN" != "DOCKER_HUB_TOKEN_PLACEHOLDER" ] || [ "$AUTO_CONFIRM" = true ]; then
            if echo "$REG_TOKEN" | $DOCKER_CMD login -u "$REG_USER" --password-stdin >/dev/null 2>&1; then
                 log_info "Docker Hub: Authentication successful."
            else
                 log_warn "Docker Hub: Authentication failed."
            fi
            
            # DHI Registry Login
            if echo "$REG_TOKEN" | $DOCKER_CMD login dhi.io -u "$REG_USER" --password-stdin >/dev/null 2>&1; then
                 log_info "DHI Registry: Authentication successful."
            else
                 log_warn "DHI Registry: Authentication failed (using Docker Hub credentials)."
            fi
        fi
        return 0
    fi

    echo ""
    echo "--- REGISTRY AUTHENTICATION ---"
    echo "Please provide your credentials for Docker Hub."
    echo ""

    while true; do
        read -r -p "Username: " REG_USER
        read -rs -p "Token: " REG_TOKEN
        echo ""
        
        # Docker Hub Login
        if echo "$REG_TOKEN" | $DOCKER_CMD login -u "$REG_USER" --password-stdin >/dev/null 2>&1; then
             log_info "Docker Hub: Authentication successful."
             
             # DHI Registry Login
             if echo "$REG_TOKEN" | $DOCKER_CMD login dhi.io -u "$REG_USER" --password-stdin >/dev/null 2>&1; then
                 log_info "DHI Registry: Authentication successful."
             else
                 log_warn "DHI Registry: Authentication failed."
             fi
             
             return 0
        else
             log_warn "Docker Hub: Authentication failed."
        fi

        if ! ask_confirm "Authentication failed. Want to try again?"; then return 1; fi
    done
}

setup_secrets() {
    export PORTAINER_PASS_HASH="${PORTAINER_PASS_HASH:-}"
    export AGH_PASS_HASH="${AGH_PASS_HASH:-}"
    export WG_HASH_COMPOSE="${WG_HASH_COMPOSE:-}"
    export ADMIN_PASS_RAW="${ADMIN_PASS_RAW:-}"
    export VPN_PASS_RAW="${VPN_PASS_RAW:-}"
    export PORTAINER_PASS_RAW="${PORTAINER_PASS_RAW:-}"
    export AGH_PASS_RAW="${AGH_PASS_RAW:-}"
    if [ ! -f "$BASE_DIR/.secrets" ]; then
        echo "========================================"
        echo " CREDENTIAL CONFIGURATION"
        echo "========================================"
        
        if [ "$AUTO_PASSWORD" = true ]; then
            log_info "Automated password generation initialized."
            if [ "$FORCE_CLEAN" = false ] && [ -d "$DATA_DIR/portainer" ] && [ "$(ls -A "$DATA_DIR/portainer")" ]; then
                log_warn "Portainer data directory already exists. Portainer's security policy only allows setting the admin password on the FIRST deployment. The newly generated password displayed at the end will NOT work unless you manually reset it or delete the Portainer volume."
            fi
            VPN_PASS_RAW=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 24)
            AGH_PASS_RAW=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 24)
            ADMIN_PASS_RAW=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 24)
            PORTAINER_PASS_RAW=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 24)
            log_info "Credentials generated and will be displayed upon completion."
            echo ""
        else
            echo -n "1. Enter password for VPN Web UI: "
            read -rs VPN_PASS_RAW
            echo ""
            echo -n "2. Enter password for AdGuard Home: "
            read -rs AGH_PASS_RAW
            echo ""
            echo -n "3. Enter administrative password (for Dashboard): "
            read -rs ADMIN_PASS_RAW
            echo ""
            if [ "$FORCE_CLEAN" = false ] && [ -d "$DATA_DIR/portainer" ]; then
                 echo "   [!] NOTICE: Portainer already initialized. Entering a new password here will NOT update Portainer's internal admin credentials."
            fi
            echo -n "4. Enter password for Portainer: "
            read -rs PORTAINER_PASS_RAW
            echo ""
        fi
        
        if [ "$AUTO_CONFIRM" = true ]; then
            log_info "Auto-confirm enabled: Skipping interactive deSEC/GitHub/Odido setup (preserving environment variables)."
            if [ "$PERSONAL_MODE" = true ]; then
                log_info "Personal Mode: Applying user-specific defaults."
                REG_USER="laciachan"
                DESEC_DOMAIN="${DESEC_DOMAIN:-}" # Keep if set, otherwise maybe prompt once
            fi
            DESEC_DOMAIN="${DESEC_DOMAIN:-}"
            DESEC_TOKEN="${DESEC_TOKEN:-}"
            SCRIBE_GH_USER="${SCRIBE_GH_USER:-}"
            SCRIBE_GH_TOKEN="${SCRIBE_GH_TOKEN:-}"
            ODIDO_TOKEN="${ODIDO_TOKEN:-}"
            ODIDO_USER_ID="${ODIDO_USER_ID:-}"
        else
            echo "--- deSEC Domain & Certificate Setup ---"
            echo "   Steps:"
            echo "   1. Sign up at https://desec.io/"
            echo "   2. Create a domain (e.g., myhome.dedyn.io)"
            echo "   3. Create a NEW Token in Token Management (if you lost the old one)"
            echo ""
            echo -n "3. deSEC Domain (e.g., myhome.dedyn.io, or Enter to skip): "
            read -r DESEC_DOMAIN
            if [ -n "$DESEC_DOMAIN" ]; then
                echo -n "4. deSEC API Token: "
                read -rs DESEC_TOKEN
                echo ""
            else
                DESEC_TOKEN=""
                echo "   Skipping deSEC (will use self-signed certificates)"
            fi
            echo ""
            
            echo "--- Scribe (Medium Frontend) GitHub Integration ---"
            echo "   Scribe proxies GitHub gists and needs a token to avoid rate limits (60/hr vs 5000/hr)."
            echo "   1. Go to https://github.com/settings/tokens"
            echo "   2. Generate a new 'Classic' token"
            echo "   3. Scopes: Select 'gist' only"
            if [ -n "$DESEC_DOMAIN" ]; then
                echo -n "5. GitHub Username: "
                read -r SCRIBE_GH_USER
                echo -n "6. GitHub Personal Access Token: "
                read -rs SCRIBE_GH_TOKEN
                echo ""
            else
                echo -n "4. GitHub Username: "
                read -r SCRIBE_GH_USER
                echo -n "5. GitHub Personal Access Token: "
                read -rs SCRIBE_GH_TOKEN
                echo ""
            fi
            
            echo ""
            echo "--- Odido Bundle Booster (Optional) ---"
            echo "   Obtain the OAuth Token using https://github.com/GuusBackup/Odido.Authenticator"
            echo "   (works on any platform with .NET, no Apple device needed)"
            echo ""
            echo "   Steps:"
            echo "   1. Clone and run: git clone --recursive https://github.com/GuusBackup/Odido.Authenticator.git"
            echo "   2. Run: dotnet run --project Odido.Authenticator"
            echo "   3. Follow the login flow and get the OAuth Token"
            echo "   4. Enter the OAuth Token below - the script will fetch your User ID automatically"
            echo ""
            echo -n "Odido Access Token (OAuth Token from Authenticator, or Enter to skip): "
            read -rs ODIDO_TOKEN
            echo ""
            if [ -n "$ODIDO_TOKEN" ]; then
                log_info "Fetching Odido User ID automatically..."
                # Use curl with -L to follow redirects and capture the effective URL
                # Note: curl may fail on network issues, so we use || true to prevent script exit
                ODIDO_REDIRECT_URL=$(curl -sL --max-time 10 -o /dev/null -w '%{url_effective}' 
                    "https://www.odido.nl/my/bestelling-en-status/overzicht" || echo "FAILED")
                
                # Extract User ID from URL path - it's a 12-character hex string after capi.odido.nl/ 
                # Format: https://capi.odido.nl/{12-char-hex-userid}/account/...
                # Note: grep may not find a match, so we use || true to prevent pipeline failure with set -euo pipefail
                ODIDO_USER_ID=$(echo "$ODIDO_REDIRECT_URL" | grep -oiE 'capi\.odido\.nl/[0-9a-f]{12}' | sed 's|capi\.odido\.nl/||I' | head -1 || true)
                
                # Fallback: try to extract first path segment if hex pattern doesn't match
                if [ -z "$ODIDO_USER_ID" ]; then
                    ODIDO_USER_ID=$(echo "$ODIDO_REDIRECT_URL" | sed -n 's|https://capi.odido.nl/\([^/]*\)/.*|\1|p')
                fi
                
                if [ -n "$ODIDO_USER_ID" ] && [ "$ODIDO_USER_ID" != "account" ]; then
                    log_info "Successfully retrieved Odido User ID: $ODIDO_USER_ID"
                else
                    log_warn "Could not automatically retrieve User ID from Odido API"
                    log_warn "The API may be temporarily unavailable or the token may be invalid"
                    echo -n "   Enter Odido User ID manually (or Enter to skip): "
                    read -r ODIDO_USER_ID
                    if [ -z "$ODIDO_USER_ID" ]; then
                        log_warn "No User ID provided, skipping Odido integration"
                        ODIDO_TOKEN=""
                    fi
                fi
            else
                ODIDO_USER_ID=""
                echo "   Skipping Odido API integration (manual mode only)"
            fi
        fi
        
        log_info "Generating Secrets..."
        ODIDO_API_KEY=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32)
        HUB_API_KEY=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32)
        $DOCKER_CMD pull -q ghcr.io/wg-easy/wg-easy:latest > /dev/null || log_warn "Failed to pull wg-easy image, attempting to use local if available."
        
        # Safely generate WG hash
        HASH_OUTPUT=$($DOCKER_CMD run --rm ghcr.io/wg-easy/wg-easy wgpw "$VPN_PASS_RAW" 2>&1 || echo "FAILED")
        if [[ "$HASH_OUTPUT" == "FAILED" ]]; then
            log_crit "Failed to generate WireGuard password hash. Check Docker status."
            exit 1
        fi
        WG_HASH_CLEAN=$(echo "$HASH_OUTPUT" | grep -oP "(?<=PASSWORD_HASH=')[^']+")
        WG_HASH_ESCAPED="${WG_HASH_CLEAN//\\\$/\\\\\$\\$}"
        export WG_HASH_COMPOSE="$WG_HASH_ESCAPED"

        AGH_USER="adguard"
        # Safely generate AGH hash
        AGH_PASS_HASH=$($DOCKER_CMD run --rm alpine:3.21 sh -c 'apk add --no-cache apache2-utils >/dev/null 2>&1 && htpasswd -B -n -b "$1" "$2"' -- "$AGH_USER" "$AGH_PASS_RAW" 2>&1 | cut -d ":" -f 2 || echo "FAILED")
        if [[ "$AGH_PASS_HASH" == "FAILED" ]]; then
            log_crit "Failed to generate AdGuard password hash. Check Docker status."
            exit 1
        fi
        export AGH_USER AGH_PASS_HASH

        # Safely generate Portainer hash (bcrypt)
        PORTAINER_PASS_HASH=$($DOCKER_CMD run --rm alpine:3.21 sh -c 'apk add --no-cache apache2-utils >/dev/null 2>&1 && htpasswd -B -n -b "admin" "$1"' -- "$PORTAINER_PASS_RAW" 2>&1 | cut -d ":" -f 2 || echo "FAILED")
        if [[ "$PORTAINER_PASS_HASH" == "FAILED" ]]; then
            log_crit "Failed to generate Portainer password hash. Check Docker status."
            exit 1
        fi
        export PORTAINER_PASS_HASH
        export PORTAINER_HASH_COMPOSE="$PORTAINER_PASS_HASH"
        
        # Cryptographic Secrets
        SCRIBE_SECRET=$(head -c 64 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 64)
        ANONYMOUS_SECRET=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32)
        IV_HMAC=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 16)
        IV_COMPANION=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 16)

        cat > "$BASE_DIR/.secrets" <<EOF
VPN_PASS_RAW="$VPN_PASS_RAW"
AGH_PASS_RAW="$AGH_PASS_RAW"
ADMIN_PASS_RAW="$ADMIN_PASS_RAW"
PORTAINER_PASS_RAW="$PORTAINER_PASS_RAW"
DESEC_DOMAIN="$DESEC_DOMAIN"
DESEC_TOKEN="$DESEC_TOKEN"
SCRIBE_GH_USER="$SCRIBE_GH_USER"
SCRIBE_GH_TOKEN="$SCRIBE_GH_TOKEN"
ODIDO_TOKEN="$ODIDO_TOKEN"
ODIDO_USER_ID="$ODIDO_USER_ID"
HUB_API_KEY="$HUB_API_KEY"
UPDATE_STRATEGY="stable"
EOF
    else
        source "$BASE_DIR/.secrets"
        # Ensure all secrets are loaded/regenerated if missing
        if [ -z "${SCRIBE_SECRET:-}" ]; then SCRIBE_SECRET=$(head -c 64 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 64); echo "SCRIBE_SECRET=$SCRIBE_SECRET" >> "$BASE_DIR/.secrets"; fi
        if [ -z "${ANONYMOUS_SECRET:-}" ]; then ANONYMOUS_SECRET=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32); echo "ANONYMOUS_SECRET=$ANONYMOUS_SECRET" >> "$BASE_DIR/.secrets"; fi
        if [ -z "${IV_HMAC:-}" ]; then IV_HMAC=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 16); echo "IV_HMAC=$IV_HMAC" >> "$BASE_DIR/.secrets"; fi
        if [ -z "${IV_COMPANION:-}" ]; then IV_COMPANION=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 16); echo "IV_COMPANION=$IV_COMPANION" >> "$BASE_DIR/.secrets"; fi

        if [ -z "${ADMIN_PASS_RAW:-}" ]; then
            ADMIN_PASS_RAW=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 24)
            echo "ADMIN_PASS_RAW=$ADMIN_PASS_RAW" >> "$BASE_DIR/.secrets"
        fi
        if [ -z "${PORTAINER_PASS_RAW:-}" ]; then
            PORTAINER_PASS_RAW=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 24)
            echo "PORTAINER_PASS_RAW=$PORTAINER_PASS_RAW" >> "$BASE_DIR/.secrets"
        fi
        # Generate Portainer hash if missing from existing .secrets
        if [ -z "${PORTAINER_PASS_HASH:-}" ]; then
            log_info "Generating missing Portainer hash..."
            PORTAINER_PASS_HASH=$($DOCKER_CMD run --rm alpine:3.21 sh -c 'apk add --no-cache apache2-utils >/dev/null 2>&1 && htpasswd -B -n -b "admin" "$1"' -- "$PORTAINER_PASS_RAW" 2>&1 | cut -d ":" -f 2 || echo "FAILED")
            echo "PORTAINER_PASS_HASH='$PORTAINER_PASS_HASH'" >> "$BASE_DIR/.secrets"
        fi
        if [ -z "${ODIDO_API_KEY:-}" ]; then
            ODIDO_API_KEY=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32)
            echo "ODIDO_API_KEY=$ODIDO_API_KEY" >> "$BASE_DIR/.secrets"
        fi
        if [ -z "${UPDATE_STRATEGY:-}" ]; then
            UPDATE_STRATEGY="stable"
            echo "UPDATE_STRATEGY=stable" >> "$BASE_DIR/.secrets"
        fi
        export UPDATE_STRATEGY
        # If using an old .secrets file that has WG_HASH_ESCAPED but not WG_HASH_CLEAN
        export WG_HASH_COMPOSE="${WG_HASH_ESCAPED:-}"
        AGH_USER="adguard"
        export AGH_USER AGH_PASS_HASH PORTAINER_PASS_HASH PORTAINER_HASH_COMPOSE
    fi
}

generate_protonpass_export() {
    log_info "Generating Proton Pass import file (CSV)..."
    local export_file="$BASE_DIR/protonpass_import.csv"
    
    # Proton Pass CSV Import Format: Name,URL,Username,Password,Note
    # We use this generic format for maximum compatibility.
    cat > "$export_file" <<EOF
Name,URL,Username,Password,Note
Privacy Hub Admin,http://$LAN_IP:$PORT_DASHBOARD_WEB,admin,$ADMIN_PASS_RAW,Primary management portal for the privacy stack.
AdGuard Home,http://$LAN_IP:$PORT_ADGUARD_WEB,adguard,$AGH_PASS_RAW,Network-wide advertisement and tracker filtration.
WireGuard VPN UI,http://$LAN_IP:$PORT_WG_WEB,admin,$VPN_PASS_RAW,WireGuard remote access management interface.
Portainer UI,http://$LAN_IP:$PORT_PORTAINER,portainer,$PORTAINER_PASS_RAW,Docker container management interface.
Odido Booster API,http://$LAN_IP:8085,admin,$ODIDO_API_KEY,API key for dashboard and Odido automation.
Gluetun Control Server,http://$LAN_IP:8000,gluetun,$ADMIN_PASS_RAW,Internal VPN gateway control API.
deSEC DNS API,https://desec.io,$DESEC_DOMAIN,$DESEC_TOKEN,API token for deSEC dynamic DNS management.
GitHub Scribe Token,https://github.com/settings/tokens,$SCRIBE_GH_USER,$SCRIBE_GH_TOKEN,GitHub Personal Access Token (Gist Key) for Scribe Medium frontend.
EOF
    chmod 600 "$export_file"
    log_info "Credential export file created: $export_file"
}
