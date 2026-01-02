#!/usr/bin/env bash

# --- SECTION 2: CLEANUP & ENVIRONMENT RESET ---
# Functions to clear out existing garbage for a clean start.

check_docker_rate_limit() {
    log_info "Checking if Docker Hub is going to throttle you..."
    # Export DOCKER_CONFIG globally
    export DOCKER_CONFIG="$DOCKER_AUTH_DIR"
    
    if ! output=$($DOCKER_CMD pull hello-world 2>&1); then
        if echo "$output" | grep -iaE "toomanyrequests|rate.*limit|pull.*limit|reached.*limit" >/dev/null; then
            log_crit "Docker Hub Rate Limit Reached! They want you to log in."
            # We already tried to auth at start, but maybe it failed or they skipped?
            # Or maybe they want to try a different account now.
            if ! authenticate_registries; then
                exit 1
            fi
        else
            log_warn "Docker pull check failed. We'll proceed, but don't be surprised if image pulls fail later."
        fi
    else
        log_info "Docker Hub connection is fine."
    fi
}

check_cert_risk() {
    CERT_PROTECT=false
    if [ -f "$BASE_DIR/config/adguard/ssl.crt" ]; then
        echo "----------------------------------------------------------"
        echo "   🔍 EXISTING SSL CERTIFICATE DETECTED"
        echo "----------------------------------------------------------"

        # Try to load existing domain configuration
        EXISTING_DOMAIN=""
        if [ -f "$BASE_DIR/.secrets" ]; then
            EXISTING_DOMAIN=$(grep "DESEC_DOMAIN=" "$BASE_DIR/.secrets" | cut -d'=' -f2 | tr -d '"' | tr -d "'")
        fi

        # Extract Certificate Details
        CERT_SUBJECT=$(openssl x509 -in "$BASE_DIR/config/adguard/ssl.crt" -noout -subject 2>/dev/null | sed 's/subject=//')
        CERT_ISSUER=$(openssl x509 -in "$BASE_DIR/config/adguard/ssl.crt" -noout -issuer 2>/dev/null | sed 's/issuer=//')
        CERT_DATES=$(openssl x509 -in "$BASE_DIR/config/adguard/ssl.crt" -noout -dates 2>/dev/null)
        CERT_NOT_AFTER=$(echo "$CERT_DATES" | grep "notAfter=" | cut -d= -f2)

        # Check validity (expiration)
        if openssl x509 -checkend 0 -noout -in "$BASE_DIR/config/adguard/ssl.crt" >/dev/null 2>&1; then
            CERT_VALIDITY="✅ Valid (Active)"
        else
            CERT_VALIDITY="❌ EXPIRED"
        fi

        echo "   • Subject:  $CERT_SUBJECT"
        echo "   • Issuer:   $CERT_ISSUER"
        echo "   • Expires:  $CERT_NOT_AFTER"
        echo "   • Status:   $CERT_VALIDITY"

        if [ -n "$EXISTING_DOMAIN" ]; then
            echo "   • Setup Domain: $EXISTING_DOMAIN"
            if echo "$CERT_SUBJECT" | grep -q "$EXISTING_DOMAIN"; then
                echo "   ✅ Certificate MATCHES the configured domain."
            else
                echo "   ⚠️  Certificate DOES NOT MATCH the configured domain ($EXISTING_DOMAIN)."
            fi
        fi

        if [ ! -f "$BASE_DIR/config/adguard/ssl.key" ]; then
            echo ""
            log_warn "⚠️  PRIVATE KEY MISSING: $BASE_DIR/config/adguard/ssl.key not found."
            echo "   This certificate cannot be used without its private key."
        fi

        echo ""

        # Check for standard ACME issuers (Let's Encrypt, ZeroSSL, etc)
        IS_ACME=false
        # Use the extracted issuer string for detection rather than grepping the raw file
        if echo "$CERT_ISSUER" | grep -qE "Let's Encrypt|R3|ISRG|ZeroSSL"; then
            IS_ACME=true
            log_warn "This appears to be a valid ACME-signed certificate."
            echo "   Deleting this file may trigger rate limits (e.g. Let's Encrypt 5/week)."
        else
            echo "   This appears to be a self-signed or custom certificate."
        fi

        echo "   Location: $BASE_DIR/config/adguard/ssl.crt"
        echo "----------------------------------------------------------"

        if [ "$AUTO_CONFIRM" = true ]; then
            if [ "$IS_ACME" = true ]; then
                log_warn "Auto-confirm is active. Preserving potentially valid certificate..."
                # Default action for valid certs with -y is PRESERVE (via N logic below)
                cert_response="n"
            else
                log_warn "Auto-confirm is active. Deleting self-signed certificate..."
                return 0
            fi
        else
            read -r -p "   Do you want to DELETE this certificate? (Default: No) [y/N]: " cert_response
        fi

        case "$cert_response" in
            [yY][eE][sS]|[yY]) return 0 ;;
            *)
                CERT_RESTORE=true
                CERT_PROTECT=true
                rm -rf "$CERT_BACKUP_DIR"
                mkdir -p "$CERT_BACKUP_DIR"
                for cert_file in "$BASE_DIR/config/adguard/ssl.crt" "$BASE_DIR/config/adguard/ssl.key"; do
                    if [ -f "$cert_file" ]; then
                        cp "$cert_file" "$CERT_BACKUP_DIR"/
                    fi
                done
                log_info "Certificate will be preserved and restored after cleanup."
                return 0 ;;
        esac
    fi
    return 0
}

clean_environment() {
    echo "=========================================================="
    echo "🛡️  ENVIRONMENT VALIDATION & CLEANUP"
    echo "=========================================================="
    
    if [ "$CLEAN_ONLY" = false ]; then
        check_docker_rate_limit
    fi

    if [ "$FORCE_CLEAN" = true ]; then
        log_warn "FORCE CLEAN ENABLED (-c): All existing data, configurations, and volumes will be permanently removed."
        echo ""
        echo "┌─────────────────────────────────────────────────────────────────┐"
        echo "│  ⚠️  CRITICAL DATA LOSS WARNING                                  │"
        echo "├─────────────────────────────────────────────────────────────────┤"
        echo "│  The following data will be PERMANENTLY DELETED:                │"
        echo "│                                                                 │"
        echo "│  • Memos notes and attachments                                  │"
        echo "│  • Invidious subscriptions and preferences                      │"
        echo "│  • AdGuard DNS query logs and custom rules                      │"
        echo "│  • WireGuard VPN profiles and client configurations             │"
        echo "│  • Immich photos and albums (if configured)                     │"
        echo "│  • All service databases and application state                  │"
        echo "│                                                                 │"
        echo "│  If you have stored ANYTHING of value in these services,        │"
        echo "│  STOP NOW and create a backup before proceeding!                │"
        echo "│                                                                 │"
        echo "│  Backup command: tar -czf privacy-hub-backup.tar.gz \\           │"
        echo "│                  /workspaces/selfhost-stack/data/AppData        │"
        echo "└─────────────────────────────────────────────────────────────────┘"
        echo ""
    fi

    TARGET_CONTAINERS="gluetun adguard dashboard portainer wg-easy hub-api odido-booster redlib wikiless wikiless_redis invidious invidious-db companion memos rimgo breezewiki anonymousoverflow scribe vert vertd"
    
    FOUND_CONTAINERS=""
    for c in $TARGET_CONTAINERS; do
        if $DOCKER_CMD ps -a --format '{{.Names}}' | grep -q "^${c}$"; then
            FOUND_CONTAINERS="$FOUND_CONTAINERS $c"
        fi
    done

    if [ -n "$FOUND_CONTAINERS" ]; then
        if ask_confirm "Existing containers detected. Would you like to remove them to ensure a clean deployment?"; then
            $DOCKER_CMD rm -f $FOUND_CONTAINERS 2>/dev/null || true
            log_info "Previous containers have been removed."
        fi
    fi

    CONFLICT_NETS=$($DOCKER_CMD network ls --format '{{.Name}}' | grep -E "(${APP_NAME}_dhi-frontnet|${APP_NAME//-/}_dhi-frontnet|${APP_NAME}_default|${APP_NAME//-/}_default)" || true)
    if [ -n "$CONFLICT_NETS" ]; then
        if ask_confirm "Conflicting networks detected. Should they be cleared?"; then
            for net in $CONFLICT_NETS; do
                log_info "  Removing network conflict: $net"
                safe_remove_network "$net"
            done
        fi
    fi

    if [ -d "$BASE_DIR" ] || $DOCKER_CMD volume ls -q | grep -q "portainer"; then
        echo ""
        echo "┌─────────────────────────────────────────────────────────────────┐"
        echo "│  ⚠️  DATA DELETION CONFIRMATION                                  │"
        echo "├─────────────────────────────────────────────────────────────────┤"
        echo "│  You are about to delete ALL Privacy Hub data including:        │"
        echo "│  notes, photos, VPN configs, DNS logs, and service databases.   │"
        echo "│                                                                 │"
        echo "│  This action CANNOT be undone. Have you backed up your data?    │"
        echo "└─────────────────────────────────────────────────────────────────┘"
        echo ""
        if ask_confirm "Wipe ALL application data? This action is irreversible."; then
            if ! check_cert_risk; then log_info "Data wipe aborted by user (Certificate Protection)."; return 1; fi
            log_info "Clearing BASE_DIR data..."
            if [ -d "$BASE_DIR" ]; then
                $SUDO rm -f "$BASE_DIR/.secrets" 2>/dev/null || true
                $SUDO rm -f "$BASE_DIR/.current_public_ip" 2>/dev/null || true
                $SUDO rm -f "$BASE_DIR/.active_profile_name" 2>/dev/null || true
                $SUDO rm -f "$BASE_DIR/.data_usage" 2>/dev/null || true
                $SUDO rm -f "$BASE_DIR/.wge_data_usage" 2>/dev/null || true
                $SUDO rm -rf "$BASE_DIR/config" 2>/dev/null || true
                $SUDO rm -rf "$BASE_DIR/env" 2>/dev/null || true
                $SUDO rm -rf "$BASE_DIR/sources" 2>/dev/null || true
                $SUDO rm -rf "$BASE_DIR/data" 2>/dev/null || true
                $SUDO rm -rf "$BASE_DIR/assets" 2>/dev/null || true
                $SUDO rm -rf "$BASE_DIR/wg-profiles" 2>/dev/null || true
                $SUDO rm -f "$BASE_DIR/active-wg.conf" 2>/dev/null || true
                $SUDO rm -f "$BASE_DIR/wg-ip-monitor.sh" 2>/dev/null || true
                $SUDO rm -f "$BASE_DIR/wg-control.sh" 2>/dev/null || true
                $SUDO rm -f "$BASE_DIR/wg-api.py" 2>/dev/null || true
                $SUDO rm -f "$BASE_DIR/cert-monitor.sh" 2>/dev/null || true
                $SUDO rm -f "$BASE_DIR/migrate.sh" 2>/dev/null || true
                $SUDO rm -f "$BASE_DIR/deployment.log" 2>/dev/null || true
                $SUDO rm -f "$BASE_DIR/docker-compose.yml" 2>/dev/null || true
                $SUDO rm -f "$BASE_DIR/dashboard.html" 2>/dev/null || true
                $SUDO rm -f "$BASE_DIR/gluetun.env" 2>/dev/null || true
                $SUDO rm -rf "$BASE_DIR" 2>/dev/null || true
            fi
            if [ -d "$MEMOS_HOST_DIR" ]; then
                $SUDO rm -rf "$MEMOS_HOST_DIR" 2>/dev/null || true
            fi
            # Remove volumes - try both unprefixed and prefixed names (sudo docker compose uses project prefix)
            for vol in portainer-data adguard-work redis-data postgresdata wg-config companioncache odido-data; do
                $DOCKER_CMD volume rm -f "$vol" 2>/dev/null || true
                $DOCKER_CMD volume rm -f "${APP_NAME}_${vol}" 2>/dev/null || true
            done
            log_info "Application data and volumes have been cleared."

            if [ "$CERT_RESTORE" = true ]; then
                log_info "Restoring preserved SSL certificate..."
                mkdir -p "$BASE_DIR/config/adguard"
                for cert_file in ssl.crt ssl.key; do
                    if [ -f "$CERT_BACKUP_DIR/$cert_file" ]; then
                        cp "$CERT_BACKUP_DIR/$cert_file" "$BASE_DIR/config/adguard/$cert_file"
                    fi
                done
                rm -rf "$CERT_BACKUP_DIR"
                CERT_RESTORE=false
                CERT_PROTECT=false
                log_info "SSL certificate restored."
            fi
        fi
    fi
    
    if [ "$FORCE_CLEAN" = true ]; then
        log_warn "REVERT: Rolling back deployment. This process will undo changes, restore system defaults, and clean up all created files..."
        echo ""
        
        # ============================================================
        # PHASE 1: Stop all containers to release locks
        # ============================================================
        log_info "Phase 1: Terminating running containers..."
        for c in $TARGET_CONTAINERS; do
            if $DOCKER_CMD ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${c}$"; then
                log_info "  Stopping: $c"
                $DOCKER_CMD stop "$c" 2>/dev/null || true
            fi
        done
        sleep 3
        
        # ============================================================
        # PHASE 2: Remove all containers
        # ============================================================
        log_info "Phase 2: Removing containers..."
        REMOVED_CONTAINERS=""
        for c in $TARGET_CONTAINERS; do
            if $DOCKER_CMD ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${c}$"; then
                log_info "  Removing: $c"
                $DOCKER_CMD rm -f "$c" 2>/dev/null || true
                REMOVED_CONTAINERS="${REMOVED_CONTAINERS}$c "
            fi
        done
        rm -rf "$DOCKER_AUTH_DIR" 2>/dev/null || true
        
        # ============================================================
        # PHASE 3: Remove ALL volumes (list everything, match patterns)
        # ============================================================
        log_info "Phase 3: Removing volumes..."
        REMOVED_VOLUMES=""
        ALL_VOLUMES=$($DOCKER_CMD volume ls -q 2>/dev/null || echo "")
        for vol in $ALL_VOLUMES; do
            case "$vol" in
                # Match exact names
                portainer-data|adguard-work|redis-data|postgresdata|wg-config|companioncache|odido-data)
                    log_info "  Removing volume: $vol"
                    $DOCKER_CMD volume rm -f "$vol" 2>/dev/null || true
                    REMOVED_VOLUMES="${REMOVED_VOLUMES}$vol "
                    ;;
                # Match prefixed names (sudo docker compose project prefix)
                ${APP_NAME}_*|${APP_NAME//-/}_*)
                    log_info "  Removing volume: $vol"
                    $DOCKER_CMD volume rm -f "$vol" 2>/dev/null || true
                    REMOVED_VOLUMES="${REMOVED_VOLUMES}$vol "
                    ;;
                # Match any volume containing our identifiers
                *portainer*|*adguard*|*redis*|*postgres*|*wg-config*|*companion*|*odido*)
                    log_info "  Removing volume: $vol"
                    $DOCKER_CMD volume rm -f "$vol" 2>/dev/null || true
                    REMOVED_VOLUMES="${REMOVED_VOLUMES}$vol "
                    ;;
            esac
        done
        
        # ============================================================
        # PHASE 4: Remove ALL networks created by this deployment
        # ============================================================
        log_info "Phase 4: Removing networks..."
        REMOVED_NETWORKS=""
        ALL_NETWORKS=$($DOCKER_CMD network ls --format '{{.Name}}' 2>/dev/null || echo "")
        for net in $ALL_NETWORKS; do
            case "$net" in
                # Skip default Docker networks
                bridge|host|none) continue ;;
                # Match our networks
                ${APP_NAME}_*|${APP_NAME//-/}_*|*dhi-frontnet*)
                    log_info "  Removing network: $net"
                    safe_remove_network "$net"
                    REMOVED_NETWORKS="${REMOVED_NETWORKS}$net "
                    ;;
            esac
        done
        
        # ============================================================
        # PHASE 5: Remove ALL images built/pulled by this deployment
        # ============================================================
        log_info "Phase 5: Removing images..."
        REMOVED_IMAGES=""
        # Remove images by known names
        KNOWN_IMAGES="qmcgaw/gluetun adguard/adguardhome nginx:1.27-alpine python:3.11-alpine3.21 node:20-alpine3.21 golang:1.23-alpine3.21 oven/bun:1-alpine ghcr.io/wg-easy/wg-easy redis:7.2-alpine quay.io/redlib/redlib:latest quay.io/invidious/invidious-companion postgres:14-alpine3.21 neosmemo/memos:stable codeberg.org/rimgo/rimgo ghcr.io/httpjamesm/anonymousoverflow:release klutchell/unbound ghcr.io/vert-sh/vertd 84codes/crystal:1.8.1-alpine 84codes/crystal:1.16.3-alpine neilpang/acme.sh"
        for img in $KNOWN_IMAGES; do
            if $DOCKER_CMD images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -q "$img"; then
                log_info "  Removing: $img"
                $DOCKER_CMD rmi -f "$img" 2>/dev/null || true
                REMOVED_IMAGES="${REMOVED_IMAGES}$img "
            fi
        done
        # Remove locally built images
        ALL_IMAGES=$($DOCKER_CMD images --format '{{.Repository}}:{{.Tag}} {{.ID}}' 2>/dev/null || echo "")
        echo "$ALL_IMAGES" | while read -r img_info; do
            img_name=$(echo "$img_info" | awk '{print $1}')
            img_id=$(echo "$img_info" | awk '{print $2}')
            case "$img_name" in
                *${APP_NAME}*|*${APP_NAME//-/}*|*odido*|*redlib*|*wikiless*|*scribe*|*vert*|*invidious*|*sources_*)
                    log_info "  Removing local image: $img_name"
                    $DOCKER_CMD rmi -f "$img_id" 2>/dev/null || true
                    # Note: We can't easily append to REMOVED_IMAGES inside a subshell/pipe loop
                    # but the main ones are captured above.
                    ;;
                "<none>:<none>")
                    # Remove dangling images
                    $DOCKER_CMD rmi -f "$img_id" 2>/dev/null || true
                    ;;
            esac
        done
        
        # ============================================================
        # PHASE 6: Remove ALL data directories and files
        # ============================================================
        log_info "Phase 6: Removing data directories..."

        # Main data directory
        if [ -d "$BASE_DIR" ]; then
            check_cert_risk
            
            log_info "  Removing: $BASE_DIR"
            $SUDO rm -rf "$BASE_DIR"

            if [ "$CERT_RESTORE" = true ]; then
                log_info "  Restoring preserved SSL certificate..."
                mkdir -p "$BASE_DIR/config/adguard"
                if [ -f "$CERT_BACKUP_DIR/ssl.crt" ]; then
                    cp "$CERT_BACKUP_DIR/ssl.crt" "$BASE_DIR/config/adguard/"
                fi
                if [ -f "$CERT_BACKUP_DIR/ssl.key" ]; then
                    cp "$CERT_BACKUP_DIR/ssl.key" "$BASE_DIR/config/adguard/"
                fi
                rm -rf "$CERT_BACKUP_DIR"
                CERT_RESTORE=false
                CERT_PROTECT=false
            fi
        fi
        
        if [ -d "$MEMOS_HOST_DIR" ]; then
            log_info "  Removing: $MEMOS_HOST_DIR"
            rm -rf "$MEMOS_HOST_DIR"
        fi
        
        if [ -d "$CERT_BACKUP_DIR" ]; then
            rm -rf "$CERT_BACKUP_DIR"
        fi
        
        # Alternative locations that might have been created
        if [ -d "$BASE_DIR" ]; then
            log_info "  Removing directory: $BASE_DIR"
            $SUDO rm -rf "$BASE_DIR"
        fi
        
        # ============================================================
        # PHASE 7: Remove cron jobs added by this script
        # ============================================================
        log_info "Phase 7: Clearing scheduled tasks..."
        EXISTING_CRON=$(crontab -l 2>/dev/null || true)
        REMOVED_CRONS=""
        if echo "$EXISTING_CRON" | grep -q "wg-ip-monitor"; then REMOVED_CRONS="${REMOVED_CRONS}wg-ip-monitor "; fi
        if echo "$EXISTING_CRON" | grep -q "cert-monitor"; then REMOVED_CRONS="${REMOVED_CRONS}cert-monitor "; fi
        
        if [ -n "$REMOVED_CRONS" ]; then
            log_info "  Clearing cron entries: $REMOVED_CRONS"
            echo "$EXISTING_CRON" | grep -v "wg-ip-monitor" | grep -v "cert-monitor" | grep -v "$APP_NAME" | crontab - 2>/dev/null || true
        fi
        
        # ============================================================
        # PHASE 8: Docker system cleanup
        # ============================================================
        log_info "Phase 8: Docker system cleanup..."
        # $DOCKER_CMD volume prune -f 2>/dev/null || true
        # $DOCKER_CMD network prune -f 2>/dev/null || true
        $DOCKER_CMD image prune -af 2>/dev/null || true
        $DOCKER_CMD builder prune -af 2>/dev/null || true
        $DOCKER_CMD system prune -f 2>/dev/null || true
        
       
        # ============================================================
        # PHASE 9: Reset stack-specific iptables rules
        # ============================================================
        log_info "Phase 9: Cleaning up specific networking rules (existing host rules will be preserved)..."
        # Only remove rules if they exist to avoid affecting other system configurations
        if $SUDO iptables -t nat -C POSTROUTING -s 10.8.0.0/24 -j MASQUERADE 2>/dev/null; then
            $SUDO iptables -t nat -D POSTROUTING -s 10.8.0.0/24 -j MASQUERADE 2>/dev/null || true
        fi
        if $SUDO iptables -C FORWARD -i wg0 -j ACCEPT 2>/dev/null; then
            $SUDO iptables -D FORWARD -i wg0 -j ACCEPT 2>/dev/null || true
        fi
        if $SUDO iptables -C FORWARD -o wg0 -j ACCEPT 2>/dev/null; then
            $SUDO iptables -D FORWARD -o wg0 -j ACCEPT 2>/dev/null || true
        fi
        
        echo ""
        log_info "============================================================"
        log_info "RESTORE COMPLETE: ENVIRONMENT HAS BEEN RESET"
        log_info "============================================================"
        log_info "The host system has been returned to its original state."
        log_info "============================================================"
    fi
}

cleanup_build_artifacts() {
    log_info "Cleaning up build artifacts to save space..."
    $DOCKER_CMD image prune -f >/dev/null 2>&1 || true
    $DOCKER_CMD builder prune -f >/dev/null 2>&1 || true
}
