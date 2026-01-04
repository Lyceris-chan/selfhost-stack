
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
        echo "│  Backup command: tar -czf privacy-hub-backup.tar.gz $DATA_DIR   │"
        echo "└─────────────────────────────────────────────────────────────────┘"
        echo ""
    fi

    TARGET_CONTAINERS="gluetun adguard dashboard portainer wg-easy hub-api odido-booster redlib wikiless wikiless_redis invidious invidious-db companion memos rimgo breezewiki anonymousoverflow scribe vert vertd"
    
    # If selected services are provided, only clean those
    if [ -n "$SELECTED_SERVICES" ]; then
        # Map selected service names to target container names (some might be different)
        # We'll use a simple approach: if it's in the selected list, we check it.
        # Note: wikiless_redis is a dependency of wikiless, etc.
        ACTUAL_TARGETS=""
        for srv in ${SELECTED_SERVICES//,/ }; do
            ACTUAL_TARGETS="$ACTUAL_TARGETS $srv"
            # Add known sub-services/dependencies
            if [ "$srv" = "wikiless" ]; then ACTUAL_TARGETS="$ACTUAL_TARGETS wikiless_redis"; fi
            if [ "$srv" = "invidious" ]; then ACTUAL_TARGETS="$ACTUAL_TARGETS invidious-db companion"; fi
            if [ "$srv" = "vert" ]; then ACTUAL_TARGETS="$ACTUAL_TARGETS vertd"; fi
            if [ "$srv" = "searxng" ]; then ACTUAL_TARGETS="$ACTUAL_TARGETS searxng-redis"; fi
            if [ "$srv" = "immich" ]; then ACTUAL_TARGETS="$ACTUAL_TARGETS immich-server immich-db immich-redis immich-machine-learning"; fi
        done
        CLEAN_LIST="$ACTUAL_TARGETS"
    else
        CLEAN_LIST="$TARGET_CONTAINERS"
    fi

    FOUND_CONTAINERS=""
    for c in $CLEAN_LIST; do
        # Check for both prefixed and non-prefixed versions
        if $DOCKER_CMD ps -a --format '{{.Names}}' | grep -qE "^(${CONTAINER_PREFIX}${c}|${c})$"; then
            NAME=$($DOCKER_CMD ps -a --format '{{.Names}}' | grep -E "^(${CONTAINER_PREFIX}${c}|${c})$" | head -n 1)
            FOUND_CONTAINERS="$FOUND_CONTAINERS $NAME"
        fi
    done

    if [ -n "$FOUND_CONTAINERS" ]; then
        if ask_confirm "Existing containers detected ($FOUND_CONTAINERS). Would you like to remove them to ensure a clean deployment?"; then
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
            if $DOCKER_CMD ps -a --format '{{.Names}}' 2>/dev/null | grep -qE "^(${CONTAINER_PREFIX}${c}|${c})$"; then
                NAME=$($DOCKER_CMD ps -a --format '{{.Names}}' | grep -E "^(${CONTAINER_PREFIX}${c}|${c})$" | head -n 1)
                log_info "  Removing: $NAME"
                $DOCKER_CMD rm -f "$NAME" 2>/dev/null || true
                REMOVED_CONTAINERS="${REMOVED_CONTAINERS}$NAME "
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

# --- SECTION 17: BACKUP & SLOT MANAGEMENT ---

perform_backup() {
    local tag="${1:-manual}"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="backup_${tag}_${timestamp}.tar.gz"
    
    mkdir -p "$BACKUP_DIR"
    log_info "Creating system backup: $backup_name..."
    
    # Backup secrets, config and dynamic state
    # We exclude large source directories and data volumes to keep it fast
    tar -czf "$BACKUP_DIR/$backup_name" \
        -C "$BASE_DIR" .secrets .active_slot config env \
        --exclude="sources" --exclude="data" 2>/dev/null
    
    log_info "Backup created successfully at $BACKUP_DIR/$backup_name"
    
    # Keep only last 5 backups
    ls -t "$BACKUP_DIR"/backup_* | tail -n +6 | xargs rm -f 2>/dev/null || true
}

swap_slots() {
    local old_slot="$CURRENT_SLOT"
    local new_slot="a"
    if [ "$old_slot" = "a" ]; then new_slot="b"; fi
    
    log_info "ORCHESTRATING SLOT SWAP: $old_slot -> $new_slot"
    
    # 1. Perform safety backup
    perform_backup "pre_swap"
    
    # 2. Update session state (file persistence happens in finalize_swap)
    export CURRENT_SLOT="$new_slot"
    export CONTAINER_PREFIX="dhi-${new_slot}-"
    
    log_info "Standby slot ($new_slot) initialized. Preparing deployment..."
}

finalize_swap() {
    log_info "Finalizing slot swap to $CURRENT_SLOT..."
    echo "$CURRENT_SLOT" | $SUDO tee "$ACTIVE_SLOT_FILE" >/dev/null
    log_info "Active slot persisted: $CURRENT_SLOT"
}

stop_inactive_slots() {
    local active_slot="$CURRENT_SLOT"
    local inactive_slot="a"
    if [ "$active_slot" = "a" ]; then inactive_slot="b"; fi
    
    local inactive_prefix="dhi-${inactive_slot}-"
    
    log_info "Cleaning up inactive slot ($inactive_slot) containers..."
    
    # Find all containers with the inactive prefix and stop/remove them
    local containers=$($DOCKER_CMD ps -a --format '{{.Names}}' | grep "^${inactive_prefix}" || true)
    if [ -n "$containers" ]; then
        $DOCKER_CMD rm -f $containers >/dev/null 2>&1 || true
        log_info "Inactive slot containers removed."
    fi
}

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
        # Explicitly launch core infrastructure services first if they are present
        CORE_SERVICES=""
        for srv in hub-api adguard unbound gluetun; do
            if grep -q "^  $srv:" "$COMPOSE_FILE"; then
                CORE_SERVICES="$CORE_SERVICES $srv"
            fi
        done

        if [ -n "$CORE_SERVICES" ]; then
            log_info "Launching core infrastructure services:$CORE_SERVICES..."
            $DOCKER_COMPOSE_FINAL_CMD -f "$COMPOSE_FILE" up -d --build $CORE_SERVICES
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
                    GLU_HEALTH=$($DOCKER_CMD inspect --format='{{.State.Status}}' ${CONTAINER_PREFIX}gluetun 2>/dev/null || echo "unknown")
                fi
                
                if [ "$HUB_HEALTH" = "healthy" ] && [ "$GLU_HEALTH" = "running" ]; then
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
        $DOCKER_COMPOSE_FINAL_CMD -f "$COMPOSE_FILE" up -d $ORPHAN_FLAG
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
                PORTAINER_JWT=$(echo "$AUTH_RESPONSE" | grep -oP '"jwt":"\K[^"\'']+')
                
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
                CHECK_USER=$(curl -s -H "Authorization: Bearer $PORTAINER_JWT" "http://$LAN_IP:$PORT_PORTAINER/api/users/$ADMIN_ID" | grep -oP '"Username":"\K[^"\'']+')
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

    # --- SECTION 16.2: ASSET LOCALIZATION ---
    # Download remote assets (fonts, utilities) via Gluetun proxy for privacy
    download_remote_assets

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
    echo "   📄 Importable CSV:      $BASE_DIR/protonpass_import.csv"
    echo "   📄 LibRedirect JSON:    $PROJECT_ROOT/libredirect_import.json"
    echo "=========================================================="
    
    if [ "$CLEAN_EXIT" = true ]; then
        exit 0
    fi

    # Cleanup build artifacts to save space after successful deployment
    cleanup_build_artifacts
}
