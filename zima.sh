#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2001,SC2015,SC2016,SC2034,SC2024,SC2086
set -euo pipefail

# ==============================================================================
# ZIMAOS PRIVACY HUB
# ==============================================================================
# A production-grade, self-hosted privacy stack featuring:
# - WireGuard VPN for secure, authenticated remote access.
# - AdGuard Home + Unbound for recursive, filtered DNS resolution.
# - Privacy frontends routed via Gluetun VPN for complete anonymity.
# - Automated SSL lifecycle management with deSEC & Let's Encrypt.
# - Real-time system monitoring and dynamic DNS automation.
# ==============================================================================

# --- SECTION 0: ARGUMENT PARSING & INITIALIZATION ---
FORCE_CLEAN=false
AUTO_PASSWORD=false
while getopts "cp" opt; do
  case ${opt} in
    c) FORCE_CLEAN=true ;;
    p) AUTO_PASSWORD=true ;;
    *) echo "Usage: $0 [-c (force cleanup/nuke)] [-p (auto-generate passwords)]"; exit 1 ;;
  esac
done

# --- SECTION 1: ENVIRONMENT VALIDATION & DIRECTORY SETUP ---
# Verify core dependencies before proceeding with deployment.
if ! command -v docker >/dev/null 2>&1; then
    echo "[CRIT] Docker is not installed. System cannot proceed."
    exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
    echo "[CRIT] Docker Compose v2 is not installed. Please install it first (usually 'docker-compose-plugin')."
    exit 1
fi

APP_NAME="privacy-hub"
BASE_DIR="/DATA/AppData/$APP_NAME"

# Docker Auth Config (stored in /tmp to survive -c cleanup)
DOCKER_AUTH_DIR="/tmp/$APP_NAME-docker-auth"
mkdir -p "$DOCKER_AUTH_DIR"
sudo chown -R "$(whoami)" "$DOCKER_AUTH_DIR"

# Define consistent docker command using custom config for auth
DOCKER_CMD="sudo env DOCKER_CONFIG=$DOCKER_AUTH_DIR docker"

# Paths
SRC_DIR="$BASE_DIR/sources"
ENV_DIR="$BASE_DIR/env"
CONFIG_DIR="$BASE_DIR/config"
COMPOSE_FILE="$BASE_DIR/docker-compose.yml"
DASHBOARD_FILE="$BASE_DIR/dashboard.html"
GLUETUN_ENV_FILE="$BASE_DIR/gluetun.env"
FONTS_DIR="$BASE_DIR/fonts"
HISTORY_LOG="$BASE_DIR/deployment.log"

# Initialize deSEC variables to prevent unbound variable errors
DESEC_DOMAIN=""
DESEC_TOKEN=""
DESEC_MONITOR_DOMAIN=""
DESEC_MONITOR_TOKEN=""
SCRIBE_GH_USER=""
SCRIBE_GH_TOKEN=""
ODIDO_USER_ID=""
ODIDO_TOKEN=""
ODIDO_API_KEY=""
WG_HASH_CLEAN=""
FOUND_OCTET=""

# WireGuard Profiles
WG_PROFILES_DIR="$BASE_DIR/wg-profiles"
ACTIVE_WG_CONF="$BASE_DIR/active-wg.conf"
ACTIVE_PROFILE_NAME_FILE="$BASE_DIR/.active_profile_name"
mkdir -p "$WG_PROFILES_DIR"

# Service Configurations
NGINX_CONF_DIR="$CONFIG_DIR/nginx"
NGINX_CONF="$NGINX_CONF_DIR/default.conf"
UNBOUND_CONF="$CONFIG_DIR/unbound/unbound.conf"
AGH_CONF_DIR="$CONFIG_DIR/adguard"
AGH_YAML="$AGH_CONF_DIR/AdGuardHome.yaml"

# Scripts
MONITOR_SCRIPT="$BASE_DIR/wg-ip-monitor.sh"
IP_LOG_FILE="$BASE_DIR/wg-ip-monitor.log"
CURRENT_IP_FILE="$BASE_DIR/.current_public_ip"
WG_CONTROL_SCRIPT="$BASE_DIR/wg-control.sh"
WG_API_SCRIPT="$BASE_DIR/wg-api.sh"
CERT_MONITOR_SCRIPT="$BASE_DIR/cert-monitor.sh"

# Logging Functions
log_info() { 
    echo -e "\e[34m[INFO]\e[0m $1"
    if [ -d "$(dirname "$HISTORY_LOG")" ]; then
        echo "$(date) [INFO] $1" >> "$HISTORY_LOG" 2>/dev/null || true
    fi
}
log_warn() { 
    echo -e "\e[33m[WARN]\e[0m $1"
    if [ -d "$(dirname "$HISTORY_LOG")" ]; then
        echo "$(date) [WARN] $1" >> "$HISTORY_LOG" 2>/dev/null || true
    fi
}
log_crit() { 
    echo -e "\e[31m[CRIT]\e[0m $1"
    if [ -d "$(dirname "$HISTORY_LOG")" ]; then
        echo "$(date) [CRIT] $1" >> "$HISTORY_LOG" 2>/dev/null || true
    fi
}

# --- SECTION 2: CLEANUP & ENVIRONMENT RESET ---
# Functions to clear out existing garbage for a clean start.
ask_confirm() {
    if [ "$FORCE_CLEAN" = true ]; then return 0; fi
    read -r -p "$1 [y/N]: " response
    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

authenticate_registries() {
    # Export DOCKER_CONFIG globally
    export DOCKER_CONFIG="$DOCKER_AUTH_DIR"
    
    echo ""
    echo "--- REGISTRY AUTHENTICATION ---"
    echo "Enter your credentials for dhi.io and Docker Hub."
    echo "We use the same token for both because you shouldn't have to manage five different passwords for one task."
    echo ""

    while true; do
        read -r -p "Username: " REG_USER
        read -rs -p "Access Token (PAT): " REG_TOKEN
        echo ""
        
        # DHI Login
        DHI_LOGIN_OK=false
        if echo "$REG_TOKEN" | sudo env DOCKER_CONFIG="$DOCKER_CONFIG" docker login dhi.io -u "$REG_USER" --password-stdin; then
            log_info "dhi.io: Authenticated. You're now pulling hardened images."
            DHI_LOGIN_OK=true
        else
            log_crit "dhi.io: Login failed. Check your token."
        fi

        # Docker Hub Login
        HUB_LOGIN_OK=false
        if echo "$REG_TOKEN" | sudo env DOCKER_CONFIG="$DOCKER_CONFIG" docker login -u "$REG_USER" --password-stdin >/dev/null 2>&1; then
             log_info "Docker Hub: Authenticated. Pull limits increased."
             HUB_LOGIN_OK=true
        else
             log_warn "Docker Hub: Login failed. You might hit pull limits if this is an anonymous pull."
        fi

        if [ "$DHI_LOGIN_OK" = true ]; then
            if [ "$HUB_LOGIN_OK" = false ]; then
                log_warn "Proceeding with DHI only. Docker Hub might throttle you."
            fi
            return 0
        fi

        if ! ask_confirm "Authentication failed. Want to try again?"; then return 1; fi
    done
}

setup_fonts() {
    log_info "Setting up local fonts so Google doesn't track your dashboard visits..."
    mkdir -p "$FONTS_DIR"
    
    # Check if fonts are already set up
    if [ -f "$FONTS_DIR/gs.css" ] && [ -f "$FONTS_DIR/cc.css" ] && [ -f "$FONTS_DIR/ms.css" ]; then
        log_info "Local fonts are already here."
        return 0
    fi

    # URLs
    URL_GS="https://api.fonts.coollabs.io/css2?family=Google+Sans+Flex:wght@400;500;600;700&display=swap"
    URL_CC="https://api.fonts.coollabs.io/css2?family=Cascadia+Code:ital,wght@0,200..700;1,200..700&display=swap"
    URL_MS="https://api.fonts.coollabs.io/css2?family=Material+Symbols+Rounded:opsz,wght,FILL,GRAD@20..48,100..700,0..1,-50..200&display=swap"

    # Download CSS
    curl -s "$URL_GS" > "$FONTS_DIR/gs.css"
    curl -s "$URL_CC" > "$FONTS_DIR/cc.css"
    curl -s "$URL_MS" > "$FONTS_DIR/ms.css"

    # Parse and download woff2 files for each CSS file
    cd "$FONTS_DIR"
    for css_file in gs.css cc.css ms.css; do
        # Extract URLs from url(...) - handle optional quotes
        grep -o "url([^)]*)" "$css_file" | sed 's/url(//;s/)//' | tr -d "'\"" | sort | uniq | while read -r url; do
            if [ -z "$url" ]; then continue; fi
            filename=$(basename "$url")
            # Strip everything after ?
            clean_name="${filename%%\?*}"
            
            if [ ! -f "$clean_name" ]; then
                # log_info "Downloading font: $clean_name"
                curl -sL "$url" -o "$clean_name"
            fi
            
            # Escape URL for sed: escape / and &
            escaped_url=$(echo "$url" | sed 's/[\/&]/\\&/g')
            # Replace the URL in the CSS file
            sed -i "s|url(['\"]\{0,1\}$escaped_url['\"]\{0,1\})|url($clean_name)|g" "$css_file"
        done
    done
    cd - >/dev/null
    
    log_info "Fonts setup complete (Separate files retained for reliability)."
}

check_docker_rate_limit() {
    log_info "Checking if Docker Hub is going to throttle you..."
    # Export DOCKER_CONFIG globally
    export DOCKER_CONFIG="$DOCKER_AUTH_DIR"
    
    if ! output=$(sudo env DOCKER_CONFIG="$DOCKER_CONFIG" docker pull hello-world 2>&1); then
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

clean_environment() {
    echo "=========================================================="
    echo "🛡️  ENVIRONMENT CHECK & CLEANUP"
    echo "=========================================================="
    
    check_docker_rate_limit

    if [ "$FORCE_CLEAN" = true ]; then
        log_warn "NUCLEAR CLEANUP ENABLED (-c): We're wiping EVERYTHING. Hope you have backups."
    fi

    TARGET_CONTAINERS="gluetun adguard dashboard portainer watchtower wg-easy hub-api odido-booster redlib wikiless wikiless_redis invidious invidious-db companion libremdb rimgo breezewiki anonymousoverflow scribe vert vertd"
    
    FOUND_CONTAINERS=""
    for c in $TARGET_CONTAINERS; do
        if $DOCKER_CMD ps -a --format '{{.Names}}' | grep -q "^${c}$"; then
            FOUND_CONTAINERS="$FOUND_CONTAINERS $c"
        fi
    done

    if [ -n "$FOUND_CONTAINERS" ]; then
        if ask_confirm "Want to remove existing containers?"; then
            $DOCKER_CMD rm -f $FOUND_CONTAINERS 2>/dev/null || true
            log_info "Old containers removed."
        fi
    fi

    CONFLICT_NETS=$($DOCKER_CMD network ls --format '{{.Name}}' | grep -E '(privacy-hub_frontnet|privacyhub_frontnet|privacy-hub_default|privacyhub_default)' || true)
    if [ -n "$CONFLICT_NETS" ]; then
        if ask_confirm "Remove network conflicts?"; then
            for net in $CONFLICT_NETS; do
                log_info "  Removing junk network: $net"
                $DOCKER_CMD network rm "$net" 2>/dev/null || true
            done
        fi
    fi

    if [ -d "$BASE_DIR" ] || $DOCKER_CMD volume ls -q | grep -q "portainer"; then
        if ask_confirm "Wipe ALL data? (This resets your logins and configs. This is your last warning.)"; then
            log_info "Clearing out the BASE_DIR..."
            if [ -d "$BASE_DIR" ]; then
                sudo rm -f "$BASE_DIR/.secrets" 2>/dev/null || true
                sudo rm -f "$BASE_DIR/.current_public_ip" 2>/dev/null || true
                sudo rm -f "$BASE_DIR/.active_profile_name" 2>/dev/null || true
                sudo rm -rf "$BASE_DIR/config" 2>/dev/null || true
                sudo rm -rf "$BASE_DIR/env" 2>/dev/null || true
                sudo rm -rf "$BASE_DIR/sources" 2>/dev/null || true
                sudo rm -rf "$BASE_DIR/wg-profiles" 2>/dev/null || true
                sudo rm -f "$BASE_DIR/active-wg.conf" 2>/dev/null || true
                sudo rm -f "$BASE_DIR/wg-ip-monitor.sh" 2>/dev/null || true
                sudo rm -f "$BASE_DIR/wg-control.sh" 2>/dev/null || true
                sudo rm -f "$BASE_DIR/wg-api.sh" 2>/dev/null || true
                sudo rm -f "$BASE_DIR/deployment.log" 2>/dev/null || true
                sudo rm -f "$BASE_DIR/wg-ip-monitor.log" 2>/dev/null || true
                sudo rm -f "$BASE_DIR/docker-compose.yml" 2>/dev/null || true
                sudo rm -f "$BASE_DIR/dashboard.html" 2>/dev/null || true
                sudo rm -f "$BASE_DIR/gluetun.env" 2>/dev/null || true
                sudo rm -rf "$BASE_DIR" 2>/dev/null || true
            fi
            # Remove volumes - try both unprefixed and prefixed names (docker compose uses project prefix)
            for vol in portainer-data adguard-work redis-data postgresdata wg-config companioncache odido-data; do
                $DOCKER_CMD volume rm -f "$vol" 2>/dev/null || true
                $DOCKER_CMD volume rm -f "${APP_NAME}_${vol}" 2>/dev/null || true
            done
            log_info "Data and volumes wiped."
        fi
    fi
    
    if [ "$FORCE_CLEAN" = true ]; then
        log_warn "RESTORE SYSTEM: Returning your machine to its original state..."
        echo ""
        
        # ============================================================
        # PHASE 1: Stop all containers to release locks
        # ============================================================
        log_info "Phase 1: Killing containers..."
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
                # Match prefixed names (docker compose project prefix)
                privacy-hub_*|privacyhub_*)
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
                privacy-hub_*|privacyhub_*|*frontnet*)
                    log_info "  Removing network: $net"
                    $DOCKER_CMD network rm "$net" 2>/dev/null || true
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
        KNOWN_IMAGES="qmcgaw/gluetun adguard/adguardhome nginx:alpine dhi.io/nginx:alpine portainer/portainer-ce containrrr/watchtower python:3.11-alpine dhi.io/python:3.11-alpine ghcr.io/wg-easy/wg-easy redis:8-alpine dhi.io/redis:8-alpine quay.io/invidious/invidious quay.io/invidious/invidious-companion docker.io/library/postgres:14 dhi.io/postgres:14 ghcr.io/zyachel/libremdb codeberg.org/rimgo/rimgo quay.io/pussthecatorg/breezewiki ghcr.io/httpjamesm/anonymousoverflow:release klutchell/unbound ghcr.io/vert-sh/vertd ghcr.io/vert-sh/vert httpd:alpine dhi.io/httpd:alpine alpine:latest dhi.io/alpine:latest neilpang/acme.sh"
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
                *privacy-hub*|*privacyhub*|*odido*|*redlib*|*wikiless*|*scribe*|*vert*|*invidious*|*sources_*)
                    log_info "  Removing local build: $img_name"
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
            log_info "  Removing: $BASE_DIR"
            sudo rm -rf "$BASE_DIR"
        fi
        
        # Alternative locations that might have been created
        if [ -d "/DATA/AppData/privacy-hub" ]; then
            log_info "  Removing alternative path: /DATA/AppData/privacy-hub"
            sudo rm -rf "/DATA/AppData/privacy-hub"
        fi
        
        # ============================================================
        # PHASE 7: Remove cron jobs added by this script
        # ============================================================
        log_info "Phase 7: Removing cron jobs..."
        EXISTING_CRON=$(crontab -l 2>/dev/null || true)
        REMOVED_CRONS=""
        if echo "$EXISTING_CRON" | grep -q "wg-ip-monitor"; then REMOVED_CRONS="${REMOVED_CRONS}wg-ip-monitor "; fi
        if echo "$EXISTING_CRON" | grep -q "cert-monitor"; then REMOVED_CRONS="${REMOVED_CRONS}cert-monitor "; fi
        
        if [ -n "$REMOVED_CRONS" ]; then
            log_info "  Clearing cron: $REMOVED_CRONS"
            echo "$EXISTING_CRON" | grep -v "wg-ip-monitor" | grep -v "cert-monitor" | grep -v "privacy-hub" | crontab - 2>/dev/null || true
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
        # PHASE 9: Reset iptables rules
        # ============================================================
        log_info "Phase 9: Resetting iptables..."
        sudo iptables -t nat -D POSTROUTING -s 10.8.0.0/24 -j MASQUERADE 2>/dev/null || true
        sudo iptables -D FORWARD -i wg0 -j ACCEPT 2>/dev/null || true
        sudo iptables -D FORWARD -o wg0 -j ACCEPT 2>/dev/null || true
        
        echo ""
        log_info "============================================================"
        log_info "RESTORE COMPLETE"
        log_info "============================================================"
        log_info "The following garbage has been taken out:"
        log_info "  ✓ Containers: ${REMOVED_CONTAINERS:-none}"
        log_info "  ✓ Volumes: ${REMOVED_VOLUMES:-none}"
        log_info "  ✓ Networks: ${REMOVED_NETWORKS:-none}"
        log_info "  ✓ Images: ${REMOVED_IMAGES:-none}"
        log_info "  ✓ Configs and secrets"
        log_info "  ✓ Data directories ($BASE_DIR)"
        log_info "  ✓ Cron jobs: ${REMOVED_CRONS:-none}"
        log_info "  ✓ Iptables rules"
        log_info ""
        log_info "Your system is back to normal."
        log_info "============================================================"
    fi
}

# Authenticate to registries (DHI & Docker Hub)
authenticate_registries

# Run cleanup
clean_environment

# Ensure authentication works by pulling critical utility images now
log_info "Pre-pulling ALL deployment images to avoid rate limits..."
# Explicitly pull images used by 'docker run' commands later in the script
# These images are small but critical for password generation and setup
CRITICAL_IMAGES="qmcgaw/gluetun adguard/adguardhome dhi.io/nginx:alpine portainer/portainer-ce containrrr/watchtower dhi.io/python:3.11-alpine ghcr.io/wg-easy/wg-easy dhi.io/redis:8-alpine quay.io/invidious/invidious quay.io/invidious/invidious-companion dhi.io/postgres:14 ghcr.io/zyachel/libremdb codeberg.org/rimgo/rimgo quay.io/pussthecatorg/breezewiki ghcr.io/httpjamesm/anonymousoverflow:release klutchell/unbound ghcr.io/vert-sh/vertd ghcr.io/vert-sh/vert dhi.io/httpd:alpine dhi.io/alpine:latest dhi.io/alpine:3.19 dhi.io/node:16-alpine 84codes/crystal:1.8.1-alpine node:25.2-alpine3.21 dhi.io/nginx:stable-alpine oven/bun:latest neilpang/acme.sh"

for img in $CRITICAL_IMAGES; do
    if ! $DOCKER_CMD pull "$img"; then
        log_warn "Failed to pull $img. You might be hitting rate limits."
        if authenticate_docker_hub; then
             # Retry once
             if ! $DOCKER_CMD pull "$img"; then
                 log_crit "Failed to pull $img even after login. Exiting."
                 exit 1
             fi
        else
             log_crit "Authentication failed or cancelled. Exiting."
             exit 1
        fi
    fi
done

mkdir -p "$BASE_DIR" "$SRC_DIR" "$ENV_DIR" "$CONFIG_DIR/unbound" "$AGH_CONF_DIR" "$NGINX_CONF_DIR" "$WG_PROFILES_DIR"

setup_fonts

# Initialize log files and data files
touch "$HISTORY_LOG" "$ACTIVE_WG_CONF" "$BASE_DIR/.data_usage" "$BASE_DIR/.wge_data_usage"
if [ ! -f "$ACTIVE_PROFILE_NAME_FILE" ]; then echo "Initial-Setup" > "$ACTIVE_PROFILE_NAME_FILE"; fi
chmod 666 "$ACTIVE_PROFILE_NAME_FILE" "$HISTORY_LOG" "$BASE_DIR/.data_usage" "$BASE_DIR/.wge_data_usage"

# --- SECTION 3: DYNAMIC SUBNET ALLOCATION ---
# Automatically identify and assign a free bridge subnet to prevent network conflicts.
log_info "Allocating Private Network Subnet..."

FOUND_SUBNET=""
FOUND_OCTET=""

for i in {20..30}; do
    TEST_SUBNET="172.$i.0.0/16"
    TEST_NET_NAME="probe_net_$i"
    if $DOCKER_CMD network create --subnet="$TEST_SUBNET" "$TEST_NET_NAME" >/dev/null 2>&1; then
echo "=========================================================="

# WireGuard Configuration Validation
validate_wg_config() {
    if [ ! -s "$ACTIVE_WG_CONF" ]; then return 1; fi
    if ! grep -q "PrivateKey" "$ACTIVE_WG_CONF"; then
        return 1
    fi
    local PK_VAL
    PK_VAL=$(grep "PrivateKey" "$ACTIVE_WG_CONF" | cut -d'=' -f2 | tr -d '[:space:]')
    if [ -z "$PK_VAL" ]; then
        return 1
    fi
    # WireGuard private keys are exactly 44 base64 characters
    if [ "${#PK_VAL}" -lt 40 ]; then
        return 1
    fi
    return 0
}

# Check existing WireGuard configuration
if validate_wg_config; then
    log_info "Existing WireGuard config found and validated. Skipping paste."
else
    if [ -f "$ACTIVE_WG_CONF" ] && [ -s "$ACTIVE_WG_CONF" ]; then
        log_warn "Existing WireGuard config was invalid/empty. Removed."
        rm "$ACTIVE_WG_CONF"
    fi

    echo "PASTE YOUR WIREGUARD .CONF CONTENT BELOW."
    echo "Make sure to include the [Interface] block with PrivateKey."
    echo "Press ENTER, then Ctrl+D (Linux/Mac) or Ctrl+Z (Windows) to save."
    echo "----------------------------------------------------------"
    cat > "$ACTIVE_WG_CONF"
    echo "" >> "$ACTIVE_WG_CONF" 
    echo "----------------------------------------------------------"
    
    # Sanitize the configuration file
    sed -i 's/\r//g' "$ACTIVE_WG_CONF"
    sed -i 's/[ \t]*$//' "$ACTIVE_WG_CONF"
    sed -i '/./,$!d' "$ACTIVE_WG_CONF"
    sed -i 's/ *= */=/g' "$ACTIVE_WG_CONF"

    if ! validate_wg_config; then
        log_crit "The pasted WireGuard configuration is invalid (missing PrivateKey or malformed)."
        log_crit "Please ensure you are pasting the full contents of the .conf file."
        log_crit "Aborting to prevent container errors."
        exit 1
    fi
fi

# --- SECTION 6: VPN PROXY CONFIGURATION (GLUETUN) ---
# Configure the anonymizing VPN gateway for privacy frontends.
log_info "Configuring Gluetun VPN Client..."
$DOCKER_CMD pull -q qmcgaw/gluetun:latest > /dev/null

cat > "$GLUETUN_ENV_FILE" <<EOF
VPN_SERVICE_PROVIDER=custom
VPN_TYPE=wireguard
FIREWALL_VPN_INPUT_PORTS=8080,8180,3000,3001,3002,8280,10416,8480
FIREWALL_OUTBOUND_SUBNETS=10.0.0.0/8,172.16.0.0/12,192.168.0.0/16
EOF

# Extract profile name from WireGuard config
extract_wg_profile_name() {
    local config_file="$1"
    local in_peer=0
    local profile_name=""
    while IFS= read -r line; do
        stripped=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if echo "$stripped" | grep -qi '^\[peer\]$'; then
            in_peer=1
            continue
        fi
        if [ "$in_peer" -eq 1 ] && echo "$stripped" | grep -q '^#'; then
            profile_name=$(echo "$stripped" | sed 's/^#[[:space:]]*//')
            if [ -n "$profile_name" ]; then
                echo "$profile_name"
                return 0
            fi
        fi
        if [ "$in_peer" -eq 1 ] && echo "$stripped" | grep -q '^\['; then
            break
        fi
    done < "$config_file"
    # Fallback: look for any comment
    while IFS= read -r line; do
        stripped=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if echo "$stripped" | grep -q '^#' && ! echo "$stripped" | grep -q '='; then
            profile_name=$(echo "$stripped" | sed 's/^#[[:space:]]*//')
            if [ -n "$profile_name" ]; then
                echo "$profile_name"
                return 0
            fi
        fi
    done < "$config_file"
    echo ""
    return 1
}

# Initialize profile
INITIAL_PROFILE_NAME=$(extract_wg_profile_name "$ACTIVE_WG_CONF")
if [ -z "$INITIAL_PROFILE_NAME" ]; then
    INITIAL_PROFILE_NAME="Initial-Setup"
fi
INITIAL_PROFILE_NAME_SAFE=$(echo "$INITIAL_PROFILE_NAME" | tr -cd 'a-zA-Z0-9-_#')
if [ -z "$INITIAL_PROFILE_NAME_SAFE" ]; then
    INITIAL_PROFILE_NAME_SAFE="Initial-Setup"
fi

cp "$ACTIVE_WG_CONF" "$WG_PROFILES_DIR/${INITIAL_PROFILE_NAME_SAFE}.conf"
chmod 644 "$GLUETUN_ENV_FILE" "$ACTIVE_WG_CONF" "$WG_PROFILES_DIR/${INITIAL_PROFILE_NAME_SAFE}.conf"
echo "$INITIAL_PROFILE_NAME_SAFE" > "$ACTIVE_PROFILE_NAME_FILE"

# --- SECTION 7: CRYPTOGRAPHIC SECRET GENERATION ---
# Generate high-entropy unique keys for various service-level authentication mechanisms.
SCRIBE_SECRET=$(head -c 64 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 64)
ANONYMOUS_SECRET=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32)
IV_HMAC=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 16)
IV_COMPANION=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 16)

# --- SECTION 8: PORT MAPPING CONFIGURATION ---
# Define internal and external port mappings for all infrastructure components.
PORT_INT_REDLIB=8080; PORT_INT_WIKILESS=8180; PORT_INT_INVIDIOUS=3000
PORT_INT_LIBREMDB=3001; PORT_INT_RIMGO=3002; PORT_INT_BREEZEWIKI=10416
PORT_INT_ANONYMOUS=8480; PORT_INT_VERT=80; PORT_INT_VERTD=24153
PORT_ADGUARD_WEB=8083; PORT_DASHBOARD_WEB=8081
PORT_PORTAINER=9000; PORT_WG_WEB=51821
PORT_REDLIB=8080; PORT_WIKILESS=8180; PORT_INVIDIOUS=3000; PORT_LIBREMDB=3001
PORT_RIMGO=3002; PORT_SCRIBE=8280; PORT_BREEZEWIKI=8380; PORT_ANONYMOUS=8480
PORT_VERT=5555; PORT_VERTD=24153
UNBOUND_STATIC_IP="172.${FOUND_OCTET}.0.250"
log_info "Unbound will use static IP: $UNBOUND_STATIC_IP"

# Unbound recursive DNS configuration
cat > "$UNBOUND_CONF" <<'UNBOUNDEOF'
server:
  interface: 0.0.0.0
  port: 53
  do-ip4: yes
  do-udp: yes
  do-tcp: yes
  access-control: 0.0.0.0/0 refuse
  access-control: 172.16.0.0/12 allow
  access-control: 192.168.0.0/16 allow
  access-control: 10.0.0.0/8 allow
  hide-identity: yes
  hide-version: yes
  num-threads: 2
  msg-cache-size: 50m
  rrset-cache-size: 100m
  prefetch: yes
  prefetch-key: yes
  auto-trust-anchor-file: "/var/lib/unbound/root.key"
UNBOUNDEOF

cat > "$AGH_YAML" <<EOF
schema_version: 29
bind_host: 0.0.0.0
bind_port: $PORT_ADGUARD_WEB
users: [{name: $AGH_USER, password: $AGH_PASS_HASH}]
auth_attempts: 5
block_auth_min: 15
http: {address: 0.0.0.0:$PORT_ADGUARD_WEB}
dns:
  bind_hosts: [0.0.0.0]
  port: 53
  upstream_dns:
    - "$UNBOUND_STATIC_IP"
  bootstrap_dns:
    - "$UNBOUND_STATIC_IP"
  protection_enabled: true
  filtering_enabled: true
  blocking_mode: default
querylog:
  enabled: true
  file_enabled: true
  interval: 720h
  size_memory: 1000
  ignored: []
statistics:
  enabled: true
  interval: 720h
  ignored: []
tls:
  enabled: true
  server_name: $DNS_SERVER_NAME
  force_https: false
  port_https: 443
  port_dns_over_tls: 853
  port_dns_over_quic: 853
  certificate_path: /opt/adguardhome/conf/ssl.crt
  private_key_path: /opt/adguardhome/conf/ssl.key
  allow_unencrypted_doh: false
user_rules:
  - "@@||getproton.me^"
  - "@@||vpn-api.proton.me^"
  - "@@||protonstatus.com^"
  - "@@||protonvpn.ch^"
  - "@@||protonvpn.com^"
  - "@@||protonvpn.net^"
  - "@@||dns.desec.io^"
  - "@@||desec.io^"
  # Default DNS blocklist powered by Lyceris-chan/dns-blocklist-generator
filters:
  - enabled: true
    url: https://raw.githubusercontent.com/Lyceris-chan/dns-blocklist-generator/refs/heads/main/blocklist.txt
    name: "Lyceris-chan Blocklist"
    id: 1
filters_update_interval: 1
EOF

if [ -n "$DESEC_DOMAIN" ]; then
    cat >> "$AGH_YAML" <<EOF
rewrites:
  - domain: $DESEC_DOMAIN
    answer: $LAN_IP
  - domain: "*.$DESEC_DOMAIN"
    answer: $LAN_IP
EOF
fi

cat > "$COMPOSE_FILE" <<EOF
networks:
  frontnet:
    driver: bridge
    ipam:
      config:
        - subnet: $DOCKER_SUBNET

volumes:
  postgresdata:
  companioncache:
  redis-data:
  wg-config:
  adguard-work:
  portainer-data:
  odido-data:

services:
  hub-api:
    build:
      context: $SRC_DIR/hub-api
    container_name: hub-api
    labels:
      - "casaos.skip=true"
    networks: [frontnet]
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock"
      - "$WG_PROFILES_DIR:/profiles"
      - "$ACTIVE_WG_CONF:/active-wg.conf"
      - "$ACTIVE_PROFILE_NAME_FILE:/app/.active_profile_name"
      - "$WG_CONTROL_SCRIPT:/usr/local/bin/wg-control.sh"
      - "$CERT_MONITOR_SCRIPT:/usr/local/bin/cert-monitor.sh"
      - "$WG_API_SCRIPT:/app/server.py"
      - "$GLUETUN_ENV_FILE:/app/gluetun.env"
      - "$COMPOSE_FILE:/app/docker-compose.yml"
      - "$HISTORY_LOG:/app/deployment.log"
      - "$BASE_DIR/.data_usage:/app/.data_usage"
      - "$BASE_DIR/.wge_data_usage:/app/.wge_data_usage"
      - "$AGH_CONF_DIR:/etc/adguard/conf"
      - "$DOCKER_AUTH_DIR:/root/.docker:ro"
    environment:
      - HUB_API_KEY=$ODIDO_API_KEY
      - DOCKER_CONFIG=/root/.docker
    entrypoint: ["/bin/sh", "-c", "touch /app/.data_usage /app/.wge_data_usage && python -u /app/server.py"]
    healthcheck:
      test: ["CMD", "nc", "-z", "127.0.0.1", "55555"]
      interval: 20s
      timeout: 10s
      retries: 5
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '0.5', memory: 256M}

  odido-booster:
    build:
      context: $SRC_DIR/odido-bundle-booster
    container_name: odido-booster
    networks: [frontnet]
    ports: ["$LAN_IP:8085:80"]
    environment:
      - API_KEY=$ODIDO_API_KEY
      - ODIDO_USER_ID=$ODIDO_USER_ID
      - ODIDO_TOKEN=$ODIDO_TOKEN
      - PORT=80
    volumes:
      - odido-data:/data
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '0.3', memory: 128M}

  watchtower:
    image: containrrr/watchtower
    container_name: watchtower
    labels:
      - "casaos.skip=true"
    networks: [frontnet]
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    command: >
      --schedule "0 0 3 * * *"
      --cleanup
      --include-stopped
      --disable-containers watchtower
      --notification-url "generic://hub-api:55555/watchtower?template=json&disabletls=yes"
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '0.2', memory: 128M}

  gluetun:
    image: qmcgaw/gluetun
    container_name: gluetun
    labels:
      - "casaos.skip=true"
    cap_add: [NET_ADMIN]
    sysctls:
      - net.ipv4.conf.all.src_valid_mark=1
      - net.ipv4.ip_forward=1
    devices:
      - /dev/net/tun:/dev/net/tun
    networks: [frontnet]
    ports:
      - "$LAN_IP:$PORT_REDLIB:$PORT_INT_REDLIB/tcp"
      - "$LAN_IP:$PORT_WIKILESS:$PORT_INT_WIKILESS/tcp"
      - "$LAN_IP:$PORT_INVIDIOUS:$PORT_INT_INVIDIOUS/tcp"
      - "$LAN_IP:$PORT_LIBREMDB:$PORT_INT_LIBREMDB/tcp"
      - "$LAN_IP:$PORT_RIMGO:$PORT_INT_RIMGO/tcp"
      - "$LAN_IP:$PORT_SCRIBE:$PORT_SCRIBE/tcp"
      - "$LAN_IP:$PORT_BREEZEWIKI:$PORT_INT_BREEZEWIKI/tcp"
      - "$LAN_IP:$PORT_ANONYMOUS:$PORT_INT_ANONYMOUS/tcp"
    volumes:
      - "$ACTIVE_WG_CONF:/gluetun/wireguard/wg0.conf:ro"
    env_file:
      - "$GLUETUN_ENV_FILE"
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '2.0', memory: 512M}

  dashboard:
    image: dhi.io/nginx:alpine-slim
    container_name: dashboard
    networks: [frontnet]
    ports:
      - "$LAN_IP:$PORT_DASHBOARD_WEB:$PORT_DASHBOARD_WEB"
      - "$LAN_IP:8443:8443"
    volumes:
      - "$FONTS_DIR:/usr/share/nginx/html/fonts:ro"
      - "$DASHBOARD_FILE:/usr/share/nginx/html/index.html:ro"
      - "$NGINX_CONF:/etc/nginx/conf.d/default.conf:ro"
      - "$AGH_CONF_DIR:/etc/adguard/conf:ro"
    labels:
      - "dev.casaos.app.ui.protocol=http"
      - "dev.casaos.app.ui.port=$PORT_DASHBOARD_WEB"
      - "dev.casaos.app.ui.hostname=$LAN_IP"
    depends_on:
      hub-api: {condition: service_healthy}
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://127.0.0.1:8081/"]
      interval: 30s
      timeout: 5s
      retries: 3
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '0.3', memory: 128M}

  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    command: -H unix:///var/run/docker.sock
    networks: [frontnet]
    ports: ["$LAN_IP:$PORT_PORTAINER:9000"]
    volumes: ["/var/run/docker.sock:/var/run/docker.sock", "portainer-data:/data"]
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '0.5', memory: 512M}

  adguard:
    image: adguard/adguardhome:latest
    container_name: adguard
    networks: [frontnet]
    ports:
      - "$LAN_IP:53:53/udp"
      - "$LAN_IP:53:53/tcp"
      - "$LAN_IP:$PORT_ADGUARD_WEB:$PORT_ADGUARD_WEB/tcp"
      - "$LAN_IP:443:443/tcp"
      - "$LAN_IP:443:443/udp"
      - "$LAN_IP:853:853/tcp"
      - "$LAN_IP:853:853/udp"
    volumes: ["adguard-work:/opt/adguardhome/work", "$AGH_CONF_DIR:/opt/adguardhome/conf"]
    depends_on:
      - unbound
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '0.5', memory: 256M}

  unbound:
    image: klutchell/unbound:latest
    container_name: unbound
    labels:
      - "casaos.skip=true"
    networks:
      frontnet:
        ipv4_address: $UNBOUND_STATIC_IP
    volumes:
      - "$UNBOUND_CONF:/opt/unbound/etc/unbound/unbound.conf:ro"
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '0.5', memory: 256M}

  # WG-Easy: Remote access VPN server (only 51820/UDP exposed to internet)
  wg-easy:
    image: ghcr.io/wg-easy/wg-easy:latest
    container_name: wg-easy
    network_mode: "host"

# --- SECTION 14: DASHBOARD & UI GENERATION ---
# Generate the Material Design 3 management dashboard.
log_info "Compiling Management Dashboard UI..."
cat > "$DASHBOARD_FILE" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ZimaOS Privacy Hub</title>
    <!-- Local privacy friendly fonts (Hosted Locally) -->
    <link href="fonts/gs.css" rel="stylesheet">
    <link href="fonts/cc.css" rel="stylesheet">
    <link href="fonts/ms.css" rel="stylesheet">
    <style>
        /* ============================================
           Material 3 Dark Theme - Strict Implementation
           Reference: https://m3.material.io/
           ============================================ */
        
        :root {
            /* M3 Dark Theme Color Tokens */
            --md-sys-color-primary: #D0BCFF;
            --md-sys-color-on-primary: #381E72;
            --md-sys-color-primary-container: #4F378B;
            --md-sys-color-on-primary-container: #EADDFF;
            /* Secondary */
            --md-sys-color-secondary: #CCC2DC;
            --md-sys-color-on-secondary: #332D41;
            --md-sys-color-secondary-container: #4A4458;
            --md-sys-color-on-secondary-container: #E8DEF8;
            /* Tertiary */
            --md-sys-color-tertiary: #EFB8C8;
            --md-sys-color-on-tertiary: #492532;
            --md-sys-color-tertiary-container: #633B48;
            --md-sys-color-on-tertiary-container: #FFD8E4;
            /* Error */
            --md-sys-color-error: #F2B8B5;
            --md-sys-color-on-error: #601410;
            --md-sys-color-error-container: #8C1D18;
            --md-sys-color-on-error-container: #F9DEDC;
            /* Surface */
            --md-sys-color-surface: #141218;
            --md-sys-color-on-surface: #E6E1E5;
            --md-sys-color-surface-variant: #49454F;
            --md-sys-color-on-surface-variant: #CAC4D0;
            --md-sys-color-surface-container-low: #1D1B20;
            --md-sys-color-surface-container: #211F26;
            --md-sys-color-surface-container-high: #2B2930;
            --md-sys-color-surface-container-highest: #36343B;
            --md-sys-color-surface-bright: #3B383E;
            /* Outline */
            --md-sys-color-outline: #938F99;
            --md-sys-color-outline-variant: #49454F;
            /* Inverse */
            --md-sys-color-inverse-surface: #E6E1E5;
            --md-sys-color-inverse-on-surface: #313033;
            /* Custom success */
            --md-sys-color-success: #A8DAB5;
            --md-sys-color-on-success: #003912;
            --md-sys-color-success-container: #00522B;
            /* Custom warning */
            --md-sys-color-warning: #FFCC80;
            --md-sys-color-on-warning: #4A2800;

            /* MD3 Expressive Motion */
            --md-sys-motion-easing-emphasized: cubic-bezier(0.2, 0.0, 0, 1.0);
            --md-sys-motion-duration-short: 150ms;
            --md-sys-motion-duration-medium: 300ms;
            
            /* MD3 Expressive Shapes */
            --md-sys-shape-corner-extra-large: 28px;
            --md-sys-shape-corner-large: 16px;
            --md-sys-shape-corner-medium: 12px;
            --md-sys-shape-corner-small: 8px;
            --md-sys-shape-corner-full: 100px;

            /* Elevation */
            --md-sys-elevation-1: 0 1px 3px 1px rgba(0,0,0,0.15), 0 1px 2px rgba(0,0,0,0.3);
            --md-sys-elevation-2: 0 2px 6px 2px rgba(0,0,0,0.15), 0 1px 2px rgba(0,0,0,0.3);
            
            /* State Opacities */
            --md-sys-state-hover-opacity: 0.08;
            --md-sys-state-focus-opacity: 0.12;
            --md-sys-state-pressed-opacity: 0.12;
        }
        
        * { box-sizing: border-box; margin: 0; padding: 0; }
        
        body {
            background: var(--md-sys-color-surface);
            color: var(--md-sys-color-on-surface);
            font-family: 'Google Sans Flex', 'Google Sans', system-ui, -apple-system, sans-serif;
            margin: 0;
            padding: 24px;
            display: flex;
            flex-direction: column;
            align-items: center;
            min-height: 100vh;
            line-height: 1.5;
            -webkit-font-smoothing: antialiased;
        }

        .code-block, .log-container, .text-field, .stat-value, .monospace {
            font-family: 'Cascadia Code', 'Consolas', monospace;
        }
        
        .material-symbols-rounded {
            font-family: 'Material Symbols Rounded';
            font-weight: normal;
            font-style: normal;
            font-size: 24px;
            line-height: 1;
            letter-spacing: normal;
            text-transform: none;
            display: inline-block;
            white-space: nowrap;
            word-wrap: normal;
            direction: ltr;
            -webkit-font-smoothing: antialiased;
        }

        .container { max-width: 1280px; width: 100%; margin: 0 auto; position: relative; }
        
        /* Header */
        header {
            margin-bottom: 56px;
            padding: 16px 0;
        }

        .header-row {
            display: flex;
            justify-content: space-between;
            align-items: flex-end;
            gap: 24px;
        }
        
        h1 {
            font-family: 'Google Sans Flex', 'Google Sans', sans-serif;
            font-weight: 400;
            font-size: 45px; /* Display Medium */
            line-height: 52px;
            margin: 0;
            color: var(--md-sys-color-primary);
            letter-spacing: 0;
        }
        
        .subtitle {
            font-size: 22px; /* Title Large */
            color: var(--md-sys-color-on-surface-variant);
            margin-top: 12px;
            font-weight: 400;
            letter-spacing: 0;
        }
        
        /* Section Labels */
        .section-label {
            color: var(--md-sys-color-primary);
            font-size: 14px; /* Title Small */
            font-weight: 500;
            letter-spacing: 0.1px;
            margin: 48px 0 12px 4px;
            text-transform: none;
        }
        
        .section-label:first-of-type {
            margin-top: 24px;
        }
        
        .section-hint {
            font-size: 14px; /* Body Medium */
            color: var(--md-sys-color-on-surface-variant);
            margin: 0 0 24px 4px;
            letter-spacing: 0.25px;
        }
        
        /* Grid Layouts */
        .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 16px; margin-bottom: 24px; }
        .grid-2 { display: grid; grid-template-columns: repeat(2, 1fr); gap: 16px; margin-bottom: 24px; }
        .grid-3 { display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px; margin-bottom: 24px; }
        @media (max-width: 1100px) { .grid-3 { grid-template-columns: repeat(2, 1fr); } }
        @media (max-width: 900px) { .grid-2, .grid-3 { grid-template-columns: 1fr; } }
        
        /* MD3 Component Refinements - Elevated Cards */
        .card {
            background: var(--md-sys-color-surface-container-low);
            border-radius: var(--md-sys-shape-corner-extra-large);
            padding: 24px;
            text-decoration: none;
            color: inherit;
            transition: all var(--md-sys-motion-duration-medium) var(--md-sys-motion-easing-emphasized);
            position: relative;
            display: flex;
            flex-direction: column;
            min-height: 180px;
            border: none;
            overflow: visible; 
            box-sizing: border-box;
            box-shadow: var(--md-sys-elevation-1);
        }
        
        .card::before {
            content: '';
            position: absolute;
            inset: 0;
            border-radius: inherit;
            background: var(--md-sys-color-on-surface);
            opacity: 0;
            transition: opacity var(--md-sys-motion-duration-short) linear;
            pointer-events: none;
            z-index: 1;
        }
        
        .card:hover::before { opacity: var(--md-sys-state-hover-opacity); }
        .card:hover { 
            background: var(--md-sys-color-surface-container);
            box-shadow: var(--md-sys-elevation-2);
            transform: translateY(-2px);
        }
        
        .card:active::before { opacity: var(--md-sys-state-pressed-opacity); }
        .card.full-width { grid-column: 1 / -1; }
        
        .card-header {
            display: flex;
            justify-content: space-between;
            align-items: flex-start;
            margin-bottom: 12px;
        }

        .card h2 {
            margin: 0;
            font-size: 22px; /* Title Large */
            font-weight: 400;
            color: var(--md-sys-color-on-surface);
            line-height: 28px;
            flex: 1;
        }

        .card .description {
            font-size: 14px; /* Body Medium */
            color: var(--md-sys-color-on-surface-variant);
            margin-bottom: 16px;
            line-height: 20px;
            flex-grow: 1;
        }
        
        .card h3 {
            margin: 0 0 16px 0;
            font-size: 16px; /* Title Medium */
            font-weight: 500;
            color: var(--md-sys-color-on-surface);
            line-height: 24px;
            letter-spacing: 0.15px;
        }
        
        /* MD3 Assist Chips */
        .chip-box { 
            display: flex; 
            gap: 8px; 
            flex-wrap: wrap; 
            padding-top: 12px;
            position: relative;
            z-index: 2;
        }
        
        .chip {
            display: inline-flex;
            align-items: center;
            gap: 8px;
            height: 32px;
            padding: 0 16px;
            border-radius: 8px;
            font-size: 14px; /* Label Large */
            font-weight: 500;
            letter-spacing: 0.1px;
            text-decoration: none;
            transition: all var(--md-sys-motion-duration-short) linear;
            border: 1px solid var(--md-sys-color-outline);
            background: transparent;
            color: var(--md-sys-color-on-surface);
            position: relative;
            overflow: hidden;
        }
        
        .chip::before {
            content: '';
            position: absolute;
            inset: 0;
            background: currentColor;
            opacity: 0;
            transition: opacity var(--md-sys-motion-duration-short) linear;
        }
        
        .chip:hover::before { opacity: var(--md-sys-state-hover-opacity); }
        
        .chip.vpn { background: var(--md-sys-color-primary-container); color: var(--md-sys-color-on-primary-container); border: none; }
        .chip.admin { background: var(--md-sys-color-secondary-container); color: var(--md-sys-color-on-secondary-container); border: none; }
        .chip.tertiary { background: var(--md-sys-color-tertiary-container); color: var(--md-sys-color-on-tertiary-container); border: none; }
        
        /* Status Indicator */
        .status-indicator {
            display: inline-flex;
            align-items: center;
            gap: 8px;
            background: var(--md-sys-color-surface-container-highest);
            padding: 6px 12px;
            border-radius: var(--md-sys-shape-corner-full);
            font-size: 12px;
            color: var(--md-sys-color-on-surface-variant);
            width: fit-content;
        }
        
        .status-dot {
            width: 8px;
            height: 8px;
            border-radius: 50%;
            background: var(--md-sys-color-outline);
        }
        
        .status-dot.up { background: var(--md-sys-color-success); box-shadow: 0 0 8px var(--md-sys-color-success); }
        .status-dot.down { background: var(--md-sys-color-error); box-shadow: 0 0 8px var(--md-sys-color-error); }
        
        /* MD3 Text Fields */
        .text-field {
            width: 100%;
            background: var(--md-sys-color-surface-container-highest);
            border: none;
            border-bottom: 1px solid var(--md-sys-color-on-surface-variant);
            color: var(--md-sys-color-on-surface);
            padding: 16px;
            border-radius: 4px 4px 0 0;
            font-size: 16px;
            box-sizing: border-box;
            outline: none;
            transition: all var(--md-sys-motion-duration-short) linear;
        }
        
        .text-field:focus {
            border-bottom: 2px solid var(--md-sys-color-primary);
            background: var(--md-sys-color-surface-container-highest);
        }
        
        textarea.text-field { min-height: 120px; resize: vertical; }
        
        /* MD3 Buttons */
        .btn {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            gap: 8px;
            padding: 0 24px;
            height: 40px;
            border-radius: 20px;
            font-size: 14px;
            font-weight: 500;
            letter-spacing: 0.1px;
            cursor: pointer;
            transition: all var(--md-sys-motion-duration-short) linear;
            border: none;
            position: relative;
            overflow: hidden;
            text-decoration: none;
            font-family: inherit;
        }
        
        .btn::before {
            content: '';
            position: absolute;
            inset: 0;
            background: currentColor;
            opacity: 0;
            transition: opacity var(--md-sys-motion-duration-short) linear;
        }
        
        .btn:hover::before { opacity: 0.08; }
        
        .btn-filled { background: var(--md-sys-color-primary); color: var(--md-sys-color-on-primary); box-shadow: var(--md-sys-elevation-1); }
        .btn-tonal { background: var(--md-sys-color-secondary-container); color: var(--md-sys-color-on-secondary-container); }
        .btn-outlined { background: transparent; color: var(--md-sys-color-primary); border: 1px solid var(--md-sys-color-outline); }
        .btn-tertiary { background: var(--md-sys-color-tertiary-container); color: var(--md-sys-color-on-tertiary-container); }
        
        .btn-icon:hover {
            background: rgba(202, 196, 208, 0.08);
            border-color: var(--md-sys-color-outline);
        }
        
        .portainer-link {
            text-decoration: none;
            cursor: pointer;
            transition: all var(--md-sys-motion-duration-short) linear;
            position: relative;
            padding-right: 28px; /* Space for the icon */
        }
        .portainer-link:hover {
            background: var(--md-sys-color-secondary-container);
            color: var(--md-sys-color-on-secondary-container);
            border-color: transparent;
        }
        /* External link icon for Portainer chips */
        .portainer-link::after {
            content: '\e895'; /* Material Symbol 'open_in_new' */
            font-family: 'Material Symbols Rounded';
            position: absolute;
            right: 8px;
            font-size: 14px;
            top: 50%;
            transform: translateY(-50%);
        }
        
        .btn-action {
            background: var(--md-sys-color-secondary-container);
            color: var(--md-sys-color-on-secondary-container);
            border-radius: var(--md-sys-shape-corner-medium);
            box-shadow: var(--md-sys-elevation-1);
        }
        
        .btn-icon { width: 40px; height: 40px; padding: 0; border-radius: 20px; }
        .btn-icon svg { width: 24px; height: 24px; fill: currentColor; }
        
        /* MD3 Switch */
        .switch-container {
            display: inline-flex;
            align-items: center;
            gap: 16px;
            cursor: pointer;
            padding: 8px 0;
        }

        .switch-track {
            width: 52px;
            height: 32px;
            background: var(--md-sys-color-surface-container-highest);
            border: 2px solid var(--md-sys-color-outline);
            border-radius: 16px;
            position: relative;
            transition: all var(--md-sys-motion-duration-short) linear;
        }

        .switch-thumb {
            width: 16px;
            height: 16px;
            background: var(--md-sys-color-outline);
            border-radius: 50%;
            position: absolute;
            top: 50%;
            left: 6px;
            transform: translateY(-50%);
            transition: all var(--md-sys-motion-duration-short) var(--md-sys-motion-easing-emphasized);
            display: flex;
            align-items: center;
            justify-content: center;
        }

        .switch-container.active .switch-track { background: var(--md-sys-color-primary); border-color: var(--md-sys-color-primary); }
        .switch-container.active .switch-thumb { width: 24px; height: 24px; left: 24px; background: var(--md-sys-color-on-primary); }

        /* Tooltips */
        [data-tooltip] { 
            position: relative; 
        }
        [data-tooltip]::after {
            content: attr(data-tooltip);
            position: absolute;
            bottom: 100%;
            left: 50%;
            transform: translateX(-50%) translateY(-8px);
            background: var(--md-sys-color-inverse-surface);
            color: var(--md-sys-color-inverse-on-surface);
            padding: 6px 10px;
            border-radius: 6px;
            font-size: 12px;
            white-space: pre;
            opacity: 0;
            pointer-events: none;
            transition: all var(--md-sys-motion-duration-short) ease;
            z-index: 9999;
            box-shadow: var(--md-sys-elevation-2);
        }
        [data-tooltip]:hover::after { 
            opacity: 1; 
            transform: translateX(-50%) translateY(-12px);
        }

        /* Ensure parent elements don't clip tooltips */
        .card, .chip, .status-indicator, li, span, div {
            /* Tooltip container safety */
        }
        
        .card {
            /* ... existing ... */
            overflow: visible; /* Changed from hidden to allow tooltips to escape */
        }
        
        /* Prevent card content overlapping */
        .card > * {
            position: relative;
            z-index: 2;
        }
        
        .card::before {
            /* ... existing ... */
            z-index: 1;
        }

        .portainer-link {
            text-decoration: none;
            cursor: pointer;
            transition: all var(--md-sys-motion-duration-short) linear;
            position: relative;
            padding-right: 28px; /* Space for the icon */
        }
        .portainer-link:hover {
            background: var(--md-sys-color-secondary-container);
            color: var(--md-sys-color-on-secondary-container);
            border-color: transparent;
        }
        /* External link icon for Portainer chips */
        .portainer-link::after {
            content: '\e895'; /* Material Symbol 'open_in_new' */
            font-family: 'Material Symbols Rounded';
            position: absolute;
            right: 8px;
            font-size: 14px;
            top: 50%;
            transform: translateY(-50%);
        }

        .portainer-link {
            text-decoration: none;
            cursor: pointer;
            transition: all var(--md-sys-motion-duration-short) linear;
            position: relative;
            padding-right: 28px; /* Space for the icon */
        }
        .portainer-link:hover {
            background: var(--md-sys-color-secondary-container);
            color: var(--md-sys-color-on-secondary-container);
            border-color: transparent;
        }
        /* External link icon for Portainer chips */
        .portainer-link::after {
            content: '\e895'; /* Material Symbol 'open_in_new' */
            font-family: 'Material Symbols Rounded';
            position: absolute;
            right: 8px;
            font-size: 14px;
            top: 50%;
            transform: translateY(-50%);
        }

        .log-container {
            background: #0D0D0D;
            border-radius: var(--md-sys-shape-corner-large);
            padding: 16px;
            height: 320px;
            overflow-y: auto;
            font-size: 13px;
            color: var(--md-sys-color-on-surface-variant);
        }
        
        .code-block {
            background: #0D0D0D;
            border-radius: var(--md-sys-shape-corner-small);
            padding: 14px 16px;
            font-size: 13px;
            color: var(--md-sys-color-primary);
            margin: 8px 0;
            overflow-x: auto;
        }
        
        .sensitive { transition: filter 400ms var(--md-sys-motion-easing-emphasized); }
        .privacy-mode .sensitive { filter: blur(6px); opacity: 0.4; }
        
        .text-success { color: var(--md-sys-color-success); }
        .stat-row { 
            display: flex; 
            justify-content: space-between; 
            align-items: center;
            margin-bottom: 12px; 
            font-size: 14px; 
            gap: 12px;
        }
        .stat-label { 
            color: var(--md-sys-color-on-surface-variant); 
            flex-shrink: 0;
        }
        .stat-value {
            text-align: right;
            word-break: break-all;
        }
        
        .progress-track { background: var(--md-sys-color-surface-container-highest); border-radius: 4px; height: 8px; margin: 16px 0; overflow: hidden; }
        .progress-indicator { background: var(--md-sys-color-primary); height: 100%; transition: width var(--md-sys-motion-duration-medium) linear; }
        
        .btn-group { display: flex; gap: 8px; margin-top: 16px; flex-wrap: wrap; }
        .list-item { display: flex; justify-content: space-between; align-items: center; padding: 12px 0; border-bottom: 1px solid var(--md-sys-color-outline-variant); gap: 12px; }
        .list-item-text { cursor: pointer; flex: 1; font-weight: 500; word-break: break-all; }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <div class="header-row">
                <div>
                    <h1>Privacy Hub</h1>
                    <div class="subtitle">Gateway Systems Governance</div>
                </div>
                <div class="switch-container" id="privacy-switch" onclick="togglePrivacy()" data-tooltip="Redact identifying metrics">
                    <span class="label-large">Redaction Mode</span>
                    <div class="switch-track">
                        <div class="switch-thumb"></div>
                    </div>
                </div>
            </div>
        </header>

        <div class="section-label">Applications</div>
        <div class="section-hint" style="display: flex; gap: 8px; flex-wrap: wrap;">
            <span class="chip" data-tooltip="Services isolated within a secure VPN tunnel for complete anonymity">🔒 VPN Protected</span>
            <span class="chip" data-tooltip="Local services accessed directly through the internal network interface">📍 Direct Access</span>
            <span class="chip tertiary" data-tooltip="Advanced infrastructure control and container telemetry via Portainer">🛠️ Infrastructure</span>
        </div>
        <div class="grid-3">
            <a id="link-invidious" href="http://$LAN_IP:$PORT_INVIDIOUS" class="card" data-check="true" data-container="invidious">
                <div class="card-header"><h2>Invidious</h2><div class="status-indicator"><span class="status-dot"></span><span class="status-text">Detecting...</span></div></div>
                <p class="description">Private YouTube Interface</p>
                <div class="chip-box"><span class="chip vpn portainer-link" data-container="invidious" data-tooltip="Manage Invidious Container">Private Instance</span></div>
            </a>
            <a id="link-redlib" href="http://$LAN_IP:$PORT_REDLIB" class="card" data-check="true" data-container="redlib">
                <div class="card-header"><h2>Redlib</h2><div class="status-indicator"><span class="status-dot"></span><span class="status-text">Detecting...</span></div></div>
                <p class="description">Private Reddit Interface</p>
                <div class="chip-box"><span class="chip vpn portainer-link" data-container="redlib" data-tooltip="Manage Redlib Container">Private Instance</span></div>
            </a>
            <a id="link-wikiless" href="http://$LAN_IP:$PORT_WIKILESS" class="card" data-check="true" data-container="wikiless">
                <div class="card-header"><h2>Wikiless</h2><div class="status-indicator"><span class="status-dot"></span><span class="status-text">Detecting...</span></div></div>
                <p class="description">Private Wikipedia Interface</p>
                <div class="chip-box"><span class="chip vpn portainer-link" data-container="wikiless" data-tooltip="Manage Wikiless Container">Private Instance</span></div>
            </a>
            <a id="link-libremdb" href="http://$LAN_IP:$PORT_LIBREMDB" class="card" data-check="true" data-container="libremdb">
                <div class="card-header"><h2>LibremDB</h2><div class="status-indicator"><span class="status-dot"></span><span class="status-text">Detecting...</span></div></div>
                <p class="description">Private Movie Database</p>
                <div class="chip-box"><span class="chip vpn portainer-link" data-container="libremdb" data-tooltip="Manage LibremDB Container">Private Instance</span></div>
            </a>
            <a id="link-rimgo" href="http://$LAN_IP:$PORT_RIMGO" class="card" data-check="true" data-container="rimgo">
                <div class="card-header"><h2>Rimgo</h2><div class="status-indicator"><span class="status-dot"></span><span class="status-text">Detecting...</span></div></div>
                <p class="description">Private Imgur Interface</p>
                <div class="chip-box"><span class="chip vpn portainer-link" data-container="rimgo" data-tooltip="Manage Rimgo Container">Private Instance</span></div>
            </a>
            <a id="link-scribe" href="http://$LAN_IP:$PORT_SCRIBE" class="card" data-check="true" data-container="scribe">
                <div class="card-header"><h2>Scribe</h2><div class="status-indicator"><span class="status-dot"></span><span class="status-text">Detecting...</span></div></div>
                <p class="description">Private Medium Interface</p>
                <div class="chip-box"><span class="chip vpn portainer-link" data-container="scribe" data-tooltip="Manage Scribe Container">Private Instance</span></div>
            </a>
            <a id="link-breezewiki" href="http://$LAN_IP:$PORT_BREEZEWIKI/" class="card" data-check="true" data-container="breezewiki">
                <div class="card-header"><h2>BreezeWiki</h2><div class="status-indicator"><span class="status-dot"></span><span class="status-text">Detecting...</span></div></div>
                <p class="description">Private Fandom Interface</p>
                <div class="chip-box"><span class="chip vpn portainer-link" data-container="breezewiki" data-tooltip="Manage BreezeWiki Container">Private Instance</span></div>
            </a>
            <a id="link-anonymousoverflow" href="http://$LAN_IP:$PORT_ANONYMOUS" class="card" data-check="true" data-container="anonymousoverflow">
                <div class="card-header"><h2>AnonOverflow</h2><div class="status-indicator"><span class="status-dot"></span><span class="status-text">Detecting...</span></div></div>
                <p class="description">Private StackOverflow Interface</p>
                <div class="chip-box"><span class="chip vpn portainer-link" data-container="anonymousoverflow" data-tooltip="Manage AnonOverflow Container">Private Instance</span></div>
            </a>
            <a id="link-vert" href="http://$LAN_IP:$PORT_VERT" class="card" data-check="true" data-container="vert">
                <div class="card-header"><h2>VERT</h2><div class="status-indicator"><span class="status-dot"></span><span class="status-text">Detecting...</span></div></div>
                <p class="description">Local File Converter</p>
                <div class="chip-box"><span class="chip admin portainer-link" data-container="vert" data-tooltip="Manage VERT Container">Utility</span><span class="chip tertiary" data-tooltip="Utilizes local GPU (/dev/dri) for high-performance conversion">GPU Accelerated</span></div>
            </a>
        </div>

        <div class="section-label">System Management</div>
        <div class="section-hint" style="display: flex; gap: 8px;">
            <span class="chip" data-tooltip="Core infrastructure management and gateway orchestration">⚙️ Core Services</span>
        </div>
        <div class="grid-3">
            <a id="link-adguard" href="http://$LAN_IP:$PORT_ADGUARD_WEB" class="card" data-check="true" data-container="adguard">
                <div class="card-header"><h2>AdGuard Home</h2><div class="status-indicator"><span class="status-dot"></span><span class="status-text">Detecting...</span></div></div>
                <p class="description">DNS Ad-Blocker</p>
                <div class="chip-box"><span class="chip admin portainer-link" data-container="adguard" data-tooltip="Manage AdGuard Container">Local Access</span><span class="chip tertiary" data-tooltip="DNS-over-HTTPS/TLS/QUIC support enabled">Encrypted DNS</span></div>
            </a>
            <a id="link-portainer" href="http://$LAN_IP:$PORT_PORTAINER" class="card" data-check="true" data-container="portainer">
                <div class="card-header"><h2>Portainer</h2><div class="status-indicator"><span class="status-dot"></span><span class="status-text">Detecting...</span></div></div>
                <p class="description">Docker Manager</p>
                <div class="chip-box"><span class="chip admin portainer-link" data-container="portainer" data-tooltip="Manage Portainer Container">Local Access</span></div>
            </a>
            <a id="link-wg-easy" href="http://$LAN_IP:$PORT_WG_WEB" class="card" data-check="true" data-container="wg-easy">
                <div class="card-header"><h2>WireGuard</h2><div class="status-indicator"><span class="status-dot"></span><span class="status-text">Detecting...</span></div></div>
                <p class="description">VPN Server</p>
                <div class="chip-box"><span class="chip admin portainer-link" data-container="wg-easy" data-tooltip="Manage WireGuard Container">Local Access</span></div>
            </a>
        </div>

        <div class="section-label">DNS Configuration</div>
        <div class="grid-3">
            <div class="card">
                <h3>Certificate Status</h3>
                <div id="cert-status-content" style="padding-top: 12px;">
                    <div class="stat-row" data-tooltip="Type of SSL certificate currently installed"><span class="stat-label">Type</span><span class="stat-value" id="cert-type">Loading...</span></div>
                    <div class="stat-row" data-tooltip="The domain name this certificate protects"><span class="stat-label">Domain</span><span class="stat-value sensitive" id="cert-subject">Loading...</span></div>
                    <div class="stat-row" data-tooltip="The authority that issued this certificate"><span class="stat-label">Issuer</span><span class="stat-value sensitive" id="cert-issuer">Loading...</span></div>
                    <div class="stat-row" data-tooltip="Date when this certificate will expire"><span class="stat-label">Expires</span><span class="stat-value sensitive" id="cert-to">Loading...</span></div>
                    <div id="ssl-failure-info" style="display:none; margin-top: 12px; padding: 12px; border-radius: 8px; background: var(--md-sys-color-error-container); color: var(--md-sys-color-on-error-container);">
                        <div class="body-small" style="font-weight:bold; margin-bottom:4px;">Issuance Failure</div>
                        <div class="body-small" id="ssl-failure-reason">--</div>
                        <div class="body-small" id="ssl-retry-time" style="margin-top:4px; opacity:0.8;">--</div>
                    </div>
                </div>
                <div id="cert-status-badge" class="chip" style="margin-top: auto; width: fit-content;">...</div>
                <button id="ssl-retry-btn" class="btn btn-icon btn-action" style="display:none;" data-tooltip="Force Let's Encrypt re-attempt" onclick="requestSslCheck()">
                    <svg viewBox="0 0 24 24"><path d="M17.65 6.35C16.2 4.9 14.21 4 12 4c-4.42 0-7.99 3.58-7.99 8s3.57 8 7.99 8c3.73 0 6.84-2.55 7.73-6h-2.08c-.82 2.33-3.07 4-5.65 4-3.31 0-6-2.69-6-6s2.69-6 6-6c1.66 0 3.14.69 4.22 1.78L13 11h7V4l-2.35 2.35z" fill="currentColor"/></svg>
                </button>
            </div>
            <div class="card">
                <h3>Device DNS Settings</h3>
                <p class="body-medium description">Configure hardware endpoints to utilize this filtering gateway:</p>
                <div class="code-label" data-tooltip="Standard DNS over port 53">Standard IPv4</div>
                <div class="code-block sensitive">$LAN_IP:53</div>
EOF
if [ -n "$DESEC_DOMAIN" ]; then
    cat >> "$DASHBOARD_FILE" <<EOF
                <div class="code-label" data-tooltip="Secured DNS via HTTPS (port 443)">DNS-over-HTTPS (DoH)</div>
                <div class="code-block sensitive">https://$DESEC_DOMAIN/dns-query</div>
                <div class="code-label" data-tooltip="Secured DNS via TLS (port 853)">DNS-over-TLS (DoT)</div>
                <div class="code-block sensitive">$DESEC_DOMAIN:853</div>
                <div class="code-label" data-tooltip="Secured DNS via QUIC (port 853)">DNS-over-QUIC (DoQ)</div>
                <div class="code-block sensitive">quic://$DESEC_DOMAIN</div>
            </div>
            <div class="card">
                <h3>Endpoint Provisioning</h3>
                <div id="dns-setup-trusted" style="display:none;">
                    <p class="body-medium description">Universal trusted SSL active. Implementation:</p>
                    <ol style="margin:0; padding-left:20px; font-size:14px; color:var(--md-sys-color-on-surface); line-height:1.8;">
                        <li data-tooltip="Optimized for local low-latency resolution"><b>Intranet:</b> Direct standard binding.</li>
                        <li data-tooltip="Authenticated remote access tunnel required"><b>Remote:</b> Secure WireGuard link.</li>
                    </ol>
                    <div class="code-label" style="margin-top:12px;">Mobile Private DNS Hostname</div>
                    <div class="code-block sensitive" style="margin-top:4px;">$DESEC_DOMAIN</div>
                    <p class="body-small" style="color:var(--md-sys-color-success); margin-top:12px;">✓ Verified Certificate Authority</p>
                </div>
                <div id="dns-setup-untrusted" style="display:none;">
                    <p class="body-medium description" style="color:var(--md-sys-color-error);">⚠ Limited Encrypted DNS Coverage</p>
                    <p class="body-small description">Android 'Private DNS' requires a FQDN. Falling back to IPv4 binding.</p>
                    <div class="code-label">Primary Gateway</div>
                    <div class="code-block sensitive">$LAN_IP</div>
                </div>
            </div>
EOF
else
    cat >> "$DASHBOARD_FILE" <<EOF
                <div class="code-label" data-tooltip="Secured DNS via HTTPS">DNS-over-HTTPS</div>
                <div class="code-block sensitive">https://$LAN_IP/dns-query</div>
                <div class="code-label" data-tooltip="Secured DNS via TLS">DNS-over-TLS</div>
                <div class="code-block sensitive">$LAN_IP:853</div>
            </div>
            <div class="card">
                <h3>Endpoint Provisioning</h3>
                <p class="body-medium description">Infrastructure access model:</p>
                <ol style="margin:0; padding-left:20px; font-size:14px; color:var(--md-sys-color-on-surface); line-height:1.8;">
                    <li>Configure router WAN/LAN DNS: <b class="sensitive">$LAN_IP</b></li>
                    <li>Remote Access: Utilize WireGuard VPN interface</li>
                </ol>
                <div class="code-block sensitive" style="margin-top:12px;">$LAN_IP</div>
                <p class="body-small" style="color:var(--md-sys-color-error); margin-top:12px;">⚠ Self-Signed (Browser Interstitials Expected)</p>
            </div>
EOF
fi
cat >> "$DASHBOARD_FILE" <<EOF
        </div>

        <div class="section-label">Odido Bundle Booster</div>
        <div class="grid-2">
            <div class="card">
                <h3>Data Status</h3>
                <div id="odido-status-container">
                    <div id="odido-not-configured" style="display:none;">
                        <p class="body-medium" style="color:var(--md-sys-color-on-surface-variant);">Odido Bundle Booster service available. Configure credentials via API or link below.</p>
                        <a href="http://$LAN_IP:8085/docs" target="_blank" class="btn btn-tonal" style="margin-top:12px;">Open API Docs</a>
                    </div>
                    <div id="odido-configured" style="display:none; padding-top: 8px;">
                        <div class="stat-row"><span class="stat-label">Data Remaining</span><span class="stat-value" id="odido-remaining">--</span></div>
                        <div class="stat-row"><span class="stat-label">Bundle Code</span><span class="stat-value" id="odido-bundle-code">--</span></div>
                        <div class="stat-row"><span class="stat-label">Auto-Renew</span><span class="stat-value" id="odido-auto-renew">--</span></div>
                        <div class="stat-row"><span class="stat-label">Threshold</span><span class="stat-value" id="odido-threshold">--</span></div>
                        <div class="stat-row"><span class="stat-label">Consumption Rate</span><span class="stat-value" id="odido-rate">--</span></div>
                        <div class="stat-row"><span class="stat-label">API Status</span><span class="stat-value" id="odido-api-status">--</span></div>
                        <div class="progress-track"><div class="progress-indicator" id="odido-bar" style="width:0%"></div></div>
                        <div class="btn-group" style="justify-content:center;">
                            <button onclick="buyOdidoBundle()" class="btn btn-tertiary" id="odido-buy-btn">Buy Bundle</button>
                            <button onclick="refreshOdidoRemaining()" class="btn btn-tonal">Refresh</button>
                            <a href="http://$LAN_IP:8085/docs" target="_blank" class="btn btn-outlined">API</a>
                        </div>
                        <div id="odido-buy-status" class="feedback"></div>
                    </div>
                    <div id="odido-loading" style="color:var(--md-sys-color-on-surface-variant);">Loading...</div>
                </div>
            </div>
            <div class="card">
                <h3>Configuration</h3>
                <input type="text" id="odido-api-key" class="text-field sensitive" placeholder="Dashboard API Key" style="margin-bottom:12px;">
                <input type="password" id="odido-oauth-token" class="text-field sensitive" placeholder="Odido OAuth Token (auto-fetches User ID)" style="margin-bottom:12px;">
                <input type="text" id="odido-bundle-code-input" class="text-field" placeholder="Bundle Code (default: A0DAY01)" style="margin-bottom:12px;">
                <input type="number" id="odido-threshold-input" class="text-field" placeholder="Min Threshold MB (default: 100)" style="margin-bottom:12px;">
                <input type="number" id="odido-lead-time-input" class="text-field" placeholder="Lead Time Minutes (default: 30)" style="margin-bottom:12px;">
                <div style="text-align:right;">
                    <button onclick="saveOdidoConfig()" class="btn btn-tonal">Save Configuration</button>
                </div>
                <div id="odido-config-status" class="feedback info"></div>
            </div>
        </div>

        <div class="section-label">WireGuard Profiles</div>
        <div class="grid-2">
            <div class="card">
                <h3>Upload Profile</h3>
                <input type="text" id="prof-name" class="text-field" placeholder="Optional: Custom Name" style="margin-bottom:12px;">
                <textarea id="prof-conf" class="text-field sensitive" placeholder="Paste .conf content here..."></textarea>
                <div style="text-align:right;"><button onclick="uploadProfile()" class="btn btn-filled">Upload & Activate</button></div>
                <div id="upload-status" class="feedback info"></div>
            </div>
            <div class="card profile-card">
                <h3>Manage Profiles</h3>
                <div id="profile-list">Loading...</div>
                <p class="body-small profile-hint">Click name to activate.</p>
            </div>
        </div>

        <div class="section-label">System Status & Logs</div>
        <div class="grid-2">
            <div class="card">
                <h3>Gluetun (Frontend Proxy)</h3>
                <div class="stat-row"><span class="stat-label">Status</span><span class="stat-value" id="vpn-status">--</span></div>
                <div class="stat-row"><span class="stat-label">Active Profile</span><span class="stat-value success" id="vpn-active">--</span></div>
                <div class="stat-row"><span class="stat-label">VPN Endpoint</span><span class="stat-value sensitive" id="vpn-endpoint">--</span></div>
                <div class="stat-row"><span class="stat-label">Public IP</span><span class="stat-value sensitive" id="vpn-public-ip">--</span></div>
                <div class="stat-row"><span class="stat-label">Connection</span><span class="stat-value" id="vpn-connection">--</span></div>
                <div class="stat-row"><span class="stat-label">This Session</span><span class="stat-value"><span id="vpn-session-rx">0 B</span> ↓ / <span id="vpn-session-tx">0 B</span> ↑</span></div>
                <div class="stat-row"><span class="stat-label">All Time</span><span class="stat-value"><span id="vpn-total-rx">0 B</span> ↓ / <span id="vpn-total-tx">0 B</span> ↑</span></div>
            </div>
            <div class="card">
                <h3>WG-Easy (External Access)</h3>
                <div class="stat-row"><span class="stat-label">Service Status</span><span class="stat-value" id="wge-status">--</span></div>
                <div class="stat-row"><span class="stat-label">External IP</span><span class="stat-value sensitive" id="wge-host">--</span></div>
                <div class="stat-row"><span class="stat-label">UDP Port</span><span class="stat-value">51820</span></div>
                <div class="stat-row"><span class="stat-label">Total Clients</span><span class="stat-value" id="wge-clients">--</span></div>
                <div class="stat-row"><span class="stat-label">Connected Now</span><span class="stat-value" id="wge-connected">--</span></div>
                <div class="stat-row"><span class="stat-label">This Session</span><span class="stat-value"><span id="wge-session-rx">0 B</span> ↓ / <span id="wge-session-tx">0 B</span> ↑</span></div>
                <div class="stat-row"><span class="stat-label">All Time</span><span class="stat-value"><span id="wge-total-rx">0 B</span> ↓ / <span id="wge-total-tx">0 B</span> ↑</span></div>
            </div>
        </div>
        <div class="grid">
            <div class="card full-width">
                <h3>Deployment History</h3>
                <div id="log-container" class="log-container sensitive"></div>
                <div id="log-status" class="body-small" style="color:var(--md-sys-color-on-surface-variant); text-align:right; margin-top:8px;">Connecting...</div>
            </div>
        </div>
    </div>

    <script>
        const API = "/api";
        const ODIDO_API = "/odido-api/api";
        const PORTAINER_URL = "http://$LAN_IP:$PORT_PORTAINER";
        const DEFAULT_ODIDO_API_KEY = "$ODIDO_API_KEY";
        let storedOdidoKey = localStorage.getItem('odido_api_key');
        // Ensure the dashboard always uses the latest deployment key
        if (DEFAULT_ODIDO_API_KEY && storedOdidoKey && storedOdidoKey !== DEFAULT_ODIDO_API_KEY) {
            localStorage.setItem('odido_api_key', DEFAULT_ODIDO_API_KEY);
            storedOdidoKey = DEFAULT_ODIDO_API_KEY;
        }
        let odidoApiKey = storedOdidoKey || DEFAULT_ODIDO_API_KEY;
        let containerIds = {};
        
        async function fetchContainerIds() {
            try {
                const res = await fetch(API + "/containers");
                const data = await res.json();
                containerIds = data.containers || {};
                // Update all portainer links
                document.querySelectorAll('.portainer-link').forEach(el => {
                    const containerName = el.dataset.container;
                    if (containerIds[containerName]) {
                        el.onclick = function(e) {
                            e.preventDefault();
                            e.stopPropagation();
                            window.open(PORTAINER_URL + "/#!/1/docker/containers/" + containerIds[containerName], '_blank');
                        };
                        el.style.cursor = 'pointer';
                        el.dataset.tooltip = "Manage " + containerName + " in Portainer";
                    }
                });
            } catch(e) { console.error('Container fetch error:', e); }
        }
        
        // Store real profile name for privacy mode masking
        let realProfileName = '';
        let maskedProfileId = '';
        const profileMaskMap = {};
        
        function generateRandomId() {
            const chars = 'abcdef0123456789';
            let id = '';
            for (let i = 0; i < 8; i++) id += chars.charAt(Math.floor(Math.random() * chars.length));
            return 'profile-' + id;
        }
        
        function updateProfileDisplay() {
            const vpnActive = document.getElementById('vpn-active');
            const isPrivate = document.body.classList.contains('privacy-mode');
            if (isPrivate && realProfileName) {
                if (!maskedProfileId) maskedProfileId = generateRandomId();
                vpnActive.textContent = maskedProfileId;
                vpnActive.classList.add('sensitive-masked');
            } else if (realProfileName) {
                vpnActive.textContent = realProfileName;
                vpnActive.classList.remove('sensitive-masked');
            }
            updateProfileListDisplay();
        }

        function getProfileLabel(name) {
            const isPrivate = document.body.classList.contains('privacy-mode');
            if (!isPrivate) return name;
            if (!profileMaskMap[name]) profileMaskMap[name] = generateRandomId();
            return profileMaskMap[name];
        }

        function updateProfileListDisplay() {
            const items = document.querySelectorAll('#profile-list .list-item-text');
            items.forEach((item) => {
                const realName = item.dataset.realName;
                if (realName) item.textContent = getProfileLabel(realName);
            });
        }
        
        async function fetchStatus() {
            const controller = new AbortController();
            const timeoutId = setTimeout(() => controller.abort(), 5000);
            try {
                const res = await fetch(API + "/status", { signal: controller.signal });
                clearTimeout(timeoutId);
                const data = await res.json();
                const g = data.gluetun;
                const vpnStatus = document.getElementById('vpn-status');
                if (g.status === "up" && g.healthy) {
                    vpnStatus.textContent = "Connected (Healthy)";
                    vpnStatus.className = "stat-value text-success";
                    vpnStatus.title = "VPN tunnel is active and passing health checks";
                } else if (g.status === "up") {
                    vpnStatus.textContent = "Connected";
                    vpnStatus.className = "stat-value text-success";
                    vpnStatus.title = "VPN tunnel is active";
                } else {
                    vpnStatus.textContent = "Disconnected";
                    vpnStatus.className = "stat-value error";
                    vpnStatus.title = "VPN tunnel is not established";
                }
                realProfileName = g.active_profile || "Unknown";
                updateProfileDisplay();
                document.getElementById('vpn-endpoint').textContent = g.endpoint || "--";
                document.getElementById('vpn-public-ip').textContent = g.public_ip || "--";
                document.getElementById('vpn-connection').textContent = g.handshake_ago || "Never";
                document.getElementById('vpn-session-rx').textContent = formatBytes(g.session_rx || 0);
                document.getElementById('vpn-session-tx').textContent = formatBytes(g.session_tx || 0);
                document.getElementById('vpn-total-rx').textContent = formatBytes(g.total_rx || 0);
                document.getElementById('vpn-total-tx').textContent = formatBytes(g.total_tx || 0);
                const w = data.wgeasy;
                const wgeStat = document.getElementById('wge-status');
                if (w.status === "up") {
                    wgeStat.textContent = "Running";
                    wgeStat.className = "stat-value text-success";
                    wgeStat.title = "WireGuard management service is operational";
                } else {
                    wgeStat.textContent = "Stopped";
                    wgeStat.className = "stat-value error";
                    wgeStat.title = "WireGuard management service is not running";
                }
                document.getElementById('wge-host').textContent = w.host || "--";
                document.getElementById('wge-clients').textContent = w.clients || "0";
                const wgeConnected = document.getElementById('wge-connected');
                const connectedCount = parseInt(w.connected) || 0;
                wgeConnected.textContent = connectedCount > 0 ? connectedCount + " active" : "None";
                wgeConnected.className = connectedCount > 0 ? "stat-value text-success" : "stat-value";
                document.getElementById('wge-session-rx').textContent = formatBytes(w.session_rx || 0);
                document.getElementById('wge-session-tx').textContent = formatBytes(w.session_tx || 0);
                document.getElementById('wge-total-rx').textContent = formatBytes(w.total_rx || 0);
                document.getElementById('wge-total-tx').textContent = formatBytes(w.total_tx || 0);

                // Update service statuses from server-side checks
                if (data.services) {
                    const statusLabels = {
                        'healthy': { text: 'Healthy', tip: 'Service is operational and passing health checks' },
                        'up': { text: 'Online', tip: 'Service is running but lacks specific health checks' },
                        'starting': { text: 'Starting', tip: 'Service is currently initializing' },
                        'unhealthy': { text: 'Unhealthy', tip: 'Service is running but failing health checks' },
                        'down': { text: 'Offline', tip: 'Service is stopped or unreachable' }
                    };

                    for (const [name, status] of Object.entries(data.services)) {
                        const card = document.getElementById("link-" + name);
                        if (card) {
                            const indicator = card.querySelector('.status-indicator');
                            const dot = card.querySelector('.status-dot');
                            const txt = card.querySelector('.status-text');
                            if (dot && txt && indicator) {
                                const info = statusLabels[status] || statusLabels['down'];
                                dot.className = "status-dot " + status;
                                txt.textContent = info.text;
                                indicator.dataset.tooltip = info.tip;
                                // Apply text-success class if healthy or up
                                if (status === 'healthy' || status === 'up') {
                                    txt.classList.add('text-success');
                                } else {
                                    txt.classList.remove('text-success');
                                }
                            }
                        }
                    }
                }
            } catch(e) { 
                console.error('Status fetch error:', e);
                // On error, mark all services as offline
                document.querySelectorAll('.card[data-check="true"]').forEach(c => {
                    const dot = c.querySelector('.status-dot');
                    const txt = c.querySelector('.status-text');
                    if (dot && txt) {
                        dot.className = "status-dot down";
                        txt.textContent = "Offline (API Error)";
                        txt.classList.remove('text-success');
                    }
                });
            }
        }
        
        async function fetchOdidoStatus() {
            try {
                const headers = odidoApiKey ? { 'X-API-Key': odidoApiKey } : {};
                const res = await fetch(ODIDO_API + "/status", { headers });
                if (!res.ok) {
                    const data = await res.json().catch(() => ({}));
                    document.getElementById('odido-loading').style.display = 'none';
                    document.getElementById('odido-not-configured').style.display = 'none';
                    document.getElementById('odido-configured').style.display = 'block';
                    document.getElementById('odido-remaining').textContent = '--';
                    document.getElementById('odido-bundle-code').textContent = '--';
                    document.getElementById('odido-threshold').textContent = '--';
                    const apiStatus = document.getElementById('odido-api-status');
                    
                    if (res.status === 401) {
                        apiStatus.textContent = 'Dashboard API Key Invalid';
                        apiStatus.style.color = 'var(--md-sys-color-error)';
                    } else if (res.status === 400 || (data.detail && data.detail.includes('credentials'))) {
                        apiStatus.textContent = 'Odido Account Not Linked';
                        apiStatus.style.color = 'var(--md-sys-color-warning)';
                    } else {
                        apiStatus.textContent = "Service Error: " + res.status;
                        apiStatus.style.color = 'var(--md-sys-color-error)';
                    }
                    return;
                }
                const data = await res.json();
                document.getElementById('odido-loading').style.display = 'none';
                document.getElementById('odido-not-configured').style.display = 'none';
                document.getElementById('odido-configured').style.display = 'block';
                const state = data.state || {};
                const config = data.config || {};
                const remaining = state.remaining_mb || 0;
                const threshold = config.absolute_min_threshold_mb || 100;
                const rate = data.consumption_rate_mb_per_min || 0;
                const bundleCode = config.bundle_code || 'A0DAY01';
                const hasOdidoCreds = config.odido_user_id && config.odido_token;
                // Also consider as "connected" if we have real data from the API
                const hasRealData = remaining > 0 || state.last_updated_ts;
                const isConfigured = hasOdidoCreds || hasRealData;
                document.getElementById('odido-remaining').textContent = Math.round(remaining) + " MB";
                document.getElementById('odido-bundle-code').textContent = bundleCode;
                document.getElementById('odido-threshold').textContent = threshold + " MB";
                document.getElementById('odido-auto-renew').textContent = config.auto_renew_enabled ? 'Enabled' : 'Disabled';
                document.getElementById('odido-rate').textContent = rate.toFixed(3) + " MB/min";
                const apiStatus = document.getElementById('odido-api-status');
                apiStatus.textContent = isConfigured ? 'Connected' : 'Not configured';
                apiStatus.style.color = isConfigured ? 'var(--md-sys-color-success)' : 'var(--md-sys-color-warning)';
                const maxData = config.bundle_size_mb || 1024;
                const percent = Math.min(100, (remaining / maxData) * 100);
                const bar = document.getElementById('odido-bar');
                bar.style.width = percent + "%";
                bar.className = 'progress-indicator';
                if (remaining < threshold) bar.classList.add('critical');
                else if (remaining < threshold * 2) bar.classList.add('low');
            } catch(e) {
                // Network error or service unavailable - show not-configured with error info
                document.getElementById('odido-loading').style.display = 'none';
                document.getElementById('odido-not-configured').style.display = 'block';
                document.getElementById('odido-configured').style.display = 'none';
                console.error('Odido status error:', e);
            }
        }
        
        async function saveOdidoConfig() {
            const st = document.getElementById('odido-config-status');
            const data = {};
            const apiKey = document.getElementById('odido-api-key').value.trim();
            const oauthToken = document.getElementById('odido-oauth-token').value.trim();
            const bundleCode = document.getElementById('odido-bundle-code-input').value.trim();
            const threshold = document.getElementById('odido-threshold-input').value.trim();
            const leadTime = document.getElementById('odido-lead-time-input').value.trim();
            
            if (apiKey) {
                odidoApiKey = apiKey;
                localStorage.setItem('odido_api_key', apiKey);
                data.api_key = apiKey;
            }
            
            // If OAuth token provided, fetch User ID automatically via hub-api API (uses curl)
            if (oauthToken) {
                st.textContent = 'Fetching User ID from Odido API...';
                st.style.color = 'var(--p)';
                try {
                    const res = await fetch(API + "/odido-userid", {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ oauth_token: oauthToken })
                    });
                    const result = await res.json();
                    if (result.error) throw new Error(result.error);
                    if (result.user_id) {
                        data.odido_user_id = result.user_id;
                        data.odido_token = oauthToken;
                        st.textContent = "User ID fetched: " + result.user_id;
                        st.style.color = 'var(--ok)';
                    } else {
                        throw new Error('Could not extract User ID from Odido API response');
                    }
                } catch(e) {
                    st.textContent = "Failed to fetch User ID: " + e.message;
                    st.style.color = 'var(--err)';
                    return;
                }
            }
            
            if (bundleCode) data.bundle_code = bundleCode;
            if (threshold) data.absolute_min_threshold_mb = parseInt(threshold);
            if (leadTime) data.lead_time_minutes = parseInt(leadTime);
            
            if (Object.keys(data).length === 0) {
                st.textContent = 'Please fill in at least one field';
                st.style.color = 'var(--err)';
                return;
            }
            st.textContent = 'Saving configuration...';
            st.style.color = 'var(--p)';
            try {
                const headers = { 'Content-Type': 'application/json' };
                if (odidoApiKey) headers['X-API-Key'] = odidoApiKey;
                const res = await fetch(ODIDO_API + "/config", {
                    method: 'POST',
                    headers,
                    body: JSON.stringify(data)
                });
                const result = await res.json();
                if (result.detail) throw new Error(result.detail);
                st.textContent = 'Configuration saved!';
                st.style.color = 'var(--ok)';
                document.getElementById('odido-api-key').value = '';
                document.getElementById('odido-oauth-token').value = '';
                document.getElementById('odido-bundle-code-input').value = '';
                document.getElementById('odido-threshold-input').value = '';
                document.getElementById('odido-lead-time-input').value = '';
                fetchOdidoStatus();
            } catch(e) {
                st.textContent = e.message;
                st.style.color = 'var(--err)';
            }
        }
        
        async function buyOdidoBundle() {
            const st = document.getElementById('odido-buy-status');
            const btn = document.getElementById('odido-buy-btn');
            btn.disabled = true;
            st.textContent = 'Purchasing bundle from Odido...';
            st.style.color = 'var(--p)';
            try {
                const headers = { 'Content-Type': 'application/json' };
                if (odidoApiKey) headers['X-API-Key'] = odidoApiKey;
                const res = await fetch(ODIDO_API + "/odido/buy-bundle", {
                    method: 'POST',
                    headers,
                    body: JSON.stringify({})
                });
                const result = await res.json();
                if (result.detail) throw new Error(result.detail);
                st.textContent = 'Bundle purchased successfully!';
                st.style.color = 'var(--ok)';
                setTimeout(fetchOdidoStatus, 2000);
            } catch(e) {
                st.textContent = e.message;
                st.style.color = 'var(--err)';
            }
            btn.disabled = false;
        }
        
        async function refreshOdidoRemaining() {
            const st = document.getElementById('odido-buy-status');
            st.textContent = 'Fetching from Odido API...';
            st.style.color = 'var(--p)';
            try {
                const headers = {};
                if (odidoApiKey) headers['X-API-Key'] = odidoApiKey;
                const res = await fetch(ODIDO_API + "/odido/remaining", { headers });
                const result = await res.json();
                if (result.detail) throw new Error(result.detail);
                st.textContent = "Live data: " + Math.round(result.remaining_mb || 0) + " MB remaining";
                st.style.color = 'var(--ok)';
                setTimeout(fetchOdidoStatus, 1000);
            } catch(e) {
                st.textContent = e.message;
                st.style.color = 'var(--err)';
            }
        }
        
        async function fetchProfiles() {
            try {
                const res = await fetch(API + "/profiles");
                const data = await res.json();
                const el = document.getElementById('profile-list');
                el.innerHTML = '';
                data.profiles.forEach(p => {
                    const row = document.createElement('div');
                    row.className = 'list-item';

                    const name = document.createElement('span');
                    name.className = 'list-item-text';
                    name.dataset.realName = p;
                    name.textContent = getProfileLabel(p);
                    name.onclick = function() { activateProfile(p); };

                    const delBtn = document.createElement('button');
                    delBtn.className = 'btn btn-icon btn-action';
                    delBtn.title = 'Delete';
                    delBtn.innerHTML = '<svg viewBox="0 0 24 24"><path d="M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z"/></svg>';
                    delBtn.onclick = function() { deleteProfile(p); };

                    row.appendChild(name);
                    row.appendChild(delBtn);
                    el.appendChild(row);
                });
                updateProfileListDisplay();
            } catch(e) {}
        }
        async function uploadProfile() {
            const nameInput = document.getElementById('prof-name').value;
            const config = document.getElementById('prof-conf').value;
            const st = document.getElementById('upload-status');
            if(!config) { st.textContent="Error: Config content missing"; return; }
            st.textContent = "Uploading...";
            try {
                const headers = { 'Content-Type': 'application/json' };
                if (odidoApiKey) headers['X-API-Key'] = odidoApiKey;
                const upRes = await fetch(API + "/upload", { 
                    method:'POST', 
                    headers: headers,
                    body:JSON.stringify({name: nameInput, config: config}) 
                });
                const upData = await upRes.json();
                if(upData.error) throw new Error(upData.error);
                const activeName = upData.name;
                st.textContent = "Activating " + activeName + "...";
                await fetch(API + "/activate", { 
                    method:'POST', 
                    headers: headers,
                    body:JSON.stringify({name: activeName}) 
                });
                st.textContent = "Success! VPN restarting.";
                fetchProfiles(); document.getElementById('prof-name').value=""; document.getElementById('prof-conf').value="";
            } catch(e) { st.textContent = e.message; }
        }
        
        async function activateProfile(name) {
            if(!confirm("Switch to " + name + "?")) return;
            try { 
                const headers = { 'Content-Type': 'application/json' };
                if (odidoApiKey) headers['X-API-Key'] = odidoApiKey;
                await fetch(API + "/activate", { 
                    method:'POST', 
                    headers: headers,
                    body:JSON.stringify({name: name}) 
                }); 
                alert("Profile switched. VPN restarting."); 
            } catch(e) { alert("Error"); }
        }
        
        async function deleteProfile(name) {
            if(!confirm("Delete " + name + "?")) return;
            try { 
                const headers = { 'Content-Type': 'application/json' };
                if (odidoApiKey) headers['X-API-Key'] = odidoApiKey;
                await fetch(API + "/delete", { 
                    method:'POST', 
                    headers: headers,
                    body:JSON.stringify({name: name}) 
                }); 
                fetchProfiles(); 
            } catch(e) { alert("Error"); }
        }
        
        function startLogStream() {
            const el = document.getElementById('log-container');
            const status = document.getElementById('log-status');
            const evtSource = new EventSource(API + "/events");
            evtSource.onmessage = function(e) {
                const div = document.createElement('div');
                div.className = 'log-entry';
                div.textContent = e.data;
                el.appendChild(div);
                el.scrollTop = el.scrollHeight;
            };
            evtSource.onopen = function() { status.textContent = "Live"; status.style.color = "var(--md-sys-color-success)"; };
            evtSource.onerror = function() { status.textContent = "Reconnecting..."; status.style.color = "var(--md-sys-color-error)"; evtSource.close(); setTimeout(startLogStream, 3000); };
        }
        
        function formatBytes(a,b=2){if(!+a)return"0 B";const c=0>b?0:b,d=Math.floor(Math.log(a)/Math.log(1024));return parseFloat((a/Math.pow(1024,d)).toFixed(c)) + " " + ["B","KiB","MiB","GiB","TiB"][d]}
        
        // Privacy toggle functionality
        function togglePrivacy() {
            const toggle = document.getElementById('privacy-switch');
            const body = document.body;
            const isPrivate = toggle.classList.toggle('active');
            if (isPrivate) {
                body.classList.add('privacy-mode');
                localStorage.setItem('privacy_mode', 'true');
            } else {
                body.classList.remove('privacy-mode');
                localStorage.setItem('privacy_mode', 'false');
            }
            updateProfileDisplay();
        }
        
        function initPrivacyMode() {
            const savedMode = localStorage.getItem('privacy_mode');
            if (savedMode === 'true') {
                const toggle = document.getElementById('privacy-switch');
                if (toggle) toggle.classList.add('active');
                document.body.classList.add('privacy-mode');
            }
            updateProfileDisplay();
        }
        
        async function fetchCertStatus() {
            try {
                const controller = new AbortController();
                const timeoutId = setTimeout(() => controller.abort(), 5000);
                const res = await fetch(API + "/certificate-status", { signal: controller.signal });
                clearTimeout(timeoutId);
                const data = await res.json();

                const certType = document.getElementById('cert-type');
                const subject = document.getElementById('cert-subject');
                const issuer = document.getElementById('cert-issuer');
                const validTo = document.getElementById('cert-to');
                const badge = document.getElementById('cert-status-badge');

                if (data.error) {
                    certType.textContent = "Error";
                    subject.textContent = data.error;
                    issuer.textContent = "--";
                    validTo.textContent = "--";
                    badge.textContent = "Unknown";
                    badge.className = "chip";
                    return;
                }
                
                certType.textContent = data.type;
                subject.textContent = data.subject;
                issuer.textContent = data.issuer;
                validTo.textContent = data.valid_to;

                const isTrusted = data.type === "Let's Encrypt";
                const domain = isTrusted ? data.subject : "";
                
                const failInfo = document.getElementById('ssl-failure-info');
                if (!isTrusted && data.failure_reason) {
                    failInfo.style.display = 'block';
                    document.getElementById('ssl-failure-reason').textContent = data.failure_reason;
                    if (data.retry_after) {
                        document.getElementById('ssl-retry-time').textContent = "Retry after: " + data.retry_after;
                    } else {
                        document.getElementById('ssl-retry-time').textContent = "Retrying periodically...";
                    }
                } else {
                    failInfo.style.display = 'none';
                }

                if (isTrusted) {
                    badge.textContent = "✓ Globally Trusted";
                    badge.title = "This certificate is automatically trusted by all devices without installing root CAs.";
                    badge.className = "chip vpn"; // Success style
                    document.getElementById('dns-setup-trusted').style.display = 'block';
                    document.getElementById('dns-setup-untrusted').style.display = 'none';
                    document.getElementById('ssl-retry-btn').style.display = 'none';
                } else {
                    badge.textContent = "⚠ Self-Signed / Untrusted";
                    badge.title = "DoH/DoT/DoQ will likely fail on mobile devices. deSEC recommended for trusted SSL.";
                    badge.className = "chip admin"; // Warning style
                    document.getElementById('dns-setup-trusted').style.display = 'none';
                    document.getElementById('dns-setup-untrusted').style.display = 'block';
                    document.getElementById('ssl-retry-btn').style.display = 'inline-flex';
                }

                // Automated Link Switching Logic
                const services = {
                    'invidious': { port: '$PORT_INVIDIOUS', sub: 'invidious' },
                    'redlib': { port: '$PORT_REDLIB', sub: 'redlib' },
                    'wikiless': { port: '$PORT_WIKILESS', sub: 'wikiless' },
                    'libremdb': { port: '$PORT_LIBREMDB', sub: 'libremdb' },
                    'rimgo': { port: '$PORT_RIMGO', sub: 'rimgo' },
                    'scribe': { port: '$PORT_SCRIBE', sub: 'scribe' },
                    'breezewiki': { port: '$PORT_BREEZEWIKI', sub: 'breezewiki' },
                    'anonymousoverflow': { port: '$PORT_ANONYMOUS', sub: 'anonymousoverflow' },
                    'vert': { port: '$PORT_VERT', sub: 'vert' },
                    'adguard': { port: '$PORT_ADGUARD_WEB', sub: 'adguard' },
                    'portainer': { port: '$PORT_PORTAINER', sub: 'portainer' },
                    'wg-easy': { port: '$PORT_WG_WEB', sub: 'wireguard' }
                };

                for (const [id, info] of Object.entries(services)) {
                    const el = document.getElementById('link-' + id);
                    if (!el) continue;
                    if (isTrusted && domain) {
                        el.href = "https://" + info.sub + "." + domain + ":8443/";
                    } else {
        document.addEventListener('DOMContentLoaded', () => {
            // Pre-populate Odido API key from deployment
            if (DEFAULT_ODIDO_API_KEY && !localStorage.getItem('odido_api_key')) {
                localStorage.setItem('odido_api_key', DEFAULT_ODIDO_API_KEY);
                odidoApiKey = DEFAULT_ODIDO_API_KEY;
            }
            // Pre-populate the API key input field so users can see their dashboard API key
            const apiKeyInput = document.getElementById('odido-api-key');
            if (apiKeyInput && odidoApiKey) {
                apiKeyInput.value = odidoApiKey;
            }
            
            initPrivacyMode();
            fetchContainerIds();
            fetchStatus(); fetchProfiles(); fetchOdidoStatus(); fetchCertStatus(); startLogStream();
            setInterval(fetchStatus, 5000);
            setInterval(fetchOdidoStatus, 60000);  // Reduced polling frequency to respect Odido API
            setInterval(fetchContainerIds, 60000);
        });
    </script>
</body>
</html>
EOF

# --- SECTION 15: BACKGROUND DAEMONS & PROACTIVE MONITORING ---
# Initialize automated background tasks for SSL renewal and Dynamic DNS updates.
if [ -n "$DESEC_DOMAIN" ] && [ -n "$DESEC_TOKEN" ]; then
    DESEC_MONITOR_DOMAIN="$DESEC_DOMAIN"
    DESEC_MONITOR_TOKEN="$DESEC_TOKEN"
else
    DESEC_MONITOR_DOMAIN=""
    DESEC_MONITOR_TOKEN=""
fi

cat > "$CERT_MONITOR_SCRIPT" <<EOF
#!/usr/bin/env bash
AGH_CONF_DIR="$AGH_CONF_DIR"
DESEC_TOKEN="$DESEC_MONITOR_TOKEN"
DESEC_DOMAIN="$DESEC_DOMAIN"
COMPOSE_FILE="$COMPOSE_FILE"
LAN_IP="$LAN_IP"
PORT_DASHBOARD_WEB="$PORT_DASHBOARD_WEB"
DOCKER_AUTH_DIR="$DOCKER_AUTH_DIR"
DOCKER_CMD="sudo env DOCKER_CONFIG=\$DOCKER_AUTH_DIR docker"
LOG_FILE="\$AGH_CONF_DIR/certbot/monitor.log"
LOCK_FILE="\$AGH_CONF_DIR/certbot/monitor.lock"
EOF

cat >> "$CERT_MONITOR_SCRIPT" <<'EOF'
# Use flock to prevent concurrent runs
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    exit 0
fi

if [ -z "$DESEC_DOMAIN" ]; then exit 0; fi

# Auto-detect if action is needed:
# - Certificate file is missing
# - Certificate is self-signed (not Let's Encrypt)
# - Certificate expires in less than 30 days
NEEDS_ACTION=false
if [ ! -f "$AGH_CONF_DIR/ssl.crt" ]; then
    NEEDS_ACTION=true
elif ! grep -qE "Let's Encrypt|R3|ISRG" "$AGH_CONF_DIR/ssl.crt"; then
    NEEDS_ACTION=true
elif ! openssl x509 -checkend 2592000 -noout -in "$AGH_CONF_DIR/ssl.crt" >/dev/null 2>&1; then
    NEEDS_ACTION=true
fi

if [ "$NEEDS_ACTION" = false ]; then
    exit 0
fi

# Check if we should wait due to previous rate limit failure
CERT_LOG_FILE="$AGH_CONF_DIR/certbot/last_run.log"
if [ -f "$CERT_LOG_FILE" ]; then
    RETRY_TIME=$(grep -oiE 'retry after [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]+ UTC' "$CERT_LOG_FILE" | head -1 | sed 's/retry after //I')
    if [ -n "$RETRY_TIME" ]; then
        RETRY_EPOCH=$(date -u -d "$RETRY_TIME" +%s 2>/dev/null || echo "")
        NOW_EPOCH=$(date -u +%s)
        if [ -n "$RETRY_EPOCH" ] && [ "$NOW_EPOCH" -lt "$RETRY_EPOCH" ]; then
            # Still in rate limit window
            exit 0
        fi
    fi
fi

echo "$(date) [INFO] Auto-detected that certificate requires attention (recovery/renewal)." >> "$LOG_FILE"

# Attempt Let's Encrypt
CERT_TMP_OUT=$(mktemp)
if $DOCKER_CMD run --rm \
    -v "$AGH_CONF_DIR:/acme" \
    -e "DESEC_Token=$DESEC_TOKEN" \
    -e "DEDYN_TOKEN=$DESEC_TOKEN" \
    -e "DESEC_DOMAIN=$DESEC_DOMAIN" \
    neilpang/acme.sh:latest \
    --issue \
    --dns dns_desec \
    --dnssleep 120 \
    -d "$DESEC_DOMAIN" \
    -d "*.$DESEC_DOMAIN" \
    --keylength ec-256 \
    --server letsencrypt \
    --home /acme \
    --config-home /acme \
    --cert-home /acme/certs \
    --force > "$CERT_TMP_OUT" 2>&1; then
    
    if [ -f "$AGH_CONF_DIR/certs/${DESEC_DOMAIN}_ecc/fullchain.cer" ]; then
        cp "$AGH_CONF_DIR/certs/${DESEC_DOMAIN}_ecc/fullchain.cer" "$AGH_CONF_DIR/ssl.crt"
        cp "$AGH_CONF_DIR/certs/${DESEC_DOMAIN}_ecc/${DESEC_DOMAIN}.key" "$AGH_CONF_DIR/ssl.key"
        
        # Update docker-compose metadata for CasaOS dashboard transition to HTTPS/Domain
        if [ -f "$COMPOSE_FILE" ]; then
            sed -i "s|dev.casaos.app.ui.protocol=http|dev.casaos.app.ui.protocol=https|g" "$COMPOSE_FILE"
            sed -i "s|dev.casaos.app.ui.port=$PORT_DASHBOARD_WEB|dev.casaos.app.ui.port=8443|g" "$COMPOSE_FILE"
            sed -i "s|dev.casaos.app.ui.hostname=$LAN_IP|dev.casaos.app.ui.hostname=$DESEC_DOMAIN|g" "$COMPOSE_FILE"
            sed -i "s|scheme: http|scheme: https|g" "$COMPOSE_FILE"
            $DOCKER_CMD compose -f "$COMPOSE_FILE" up -d --no-deps dashboard
        fi

        $DOCKER_CMD restart adguard
        $DOCKER_CMD restart dashboard
        echo "$(date) [INFO] Successfully updated Let's Encrypt certificate and synchronized dashboard config." >> "$LOG_FILE"
    elif [ -f "$AGH_CONF_DIR/certs/${DESEC_DOMAIN}/fullchain.cer" ]; then
        cp "$AGH_CONF_DIR/certs/${DESEC_DOMAIN}/fullchain.cer" "$AGH_CONF_DIR/ssl.crt"
        cp "$AGH_CONF_DIR/certs/${DESEC_DOMAIN}/${DESEC_DOMAIN}.key" "$AGH_CONF_DIR/ssl.key"

        # Update docker-compose metadata for CasaOS dashboard transition to HTTPS/Domain
        if [ -f "$COMPOSE_FILE" ]; then
            sed -i "s|dev.casaos.app.ui.protocol=http|dev.casaos.app.ui.protocol=https|g" "$COMPOSE_FILE"
            sed -i "s|dev.casaos.app.ui.port=$PORT_DASHBOARD_WEB|dev.casaos.app.ui.port=8443|g" "$COMPOSE_FILE"
            sed -i "s|dev.casaos.app.ui.hostname=$LAN_IP|dev.casaos.app.ui.hostname=$DESEC_DOMAIN|g" "$COMPOSE_FILE"
            sed -i "s|scheme: http|scheme: https|g" "$COMPOSE_FILE"
            $DOCKER_CMD compose -f "$COMPOSE_FILE" up -d --no-deps dashboard
        fi

        $DOCKER_CMD restart adguard
        $DOCKER_CMD restart dashboard
        echo "$(date) [INFO] Successfully updated Let's Encrypt certificate and synchronized dashboard config." >> "$LOG_FILE"
    fi
else
    cat "$CERT_TMP_OUT" > "$CERT_LOG_FILE"
    echo "$(date) [WARN] Let's Encrypt attempt failed. Will retry later." >> "$LOG_FILE"
fi
rm -f "$CERT_TMP_OUT"
EOF
chmod +x "$CERT_MONITOR_SCRIPT"
EXISTING_CRON=$(crontab -l 2>/dev/null || true)
echo "$EXISTING_CRON" | grep -v "$CERT_MONITOR_SCRIPT" | { cat; echo "*/5 * * * * $CERT_MONITOR_SCRIPT"; } | crontab -

# --- SECTION 15.1: DYNAMIC IP AUTOMATION ---
# Detect public IP changes and synchronize DNS records and VPN endpoints.
cat > "$MONITOR_SCRIPT" <<EOF
#!/usr/bin/env bash
COMPOSE_FILE="$COMPOSE_FILE"
CURRENT_IP_FILE="$CURRENT_IP_FILE"
LOG_FILE="$IP_LOG_FILE"
LOCK_FILE="$BASE_DIR/.ip-monitor.lock"
DESEC_DOMAIN="$DESEC_MONITOR_DOMAIN"
DESEC_TOKEN="$DESEC_MONITOR_TOKEN"
DOCKER_CONFIG="$DOCKER_AUTH_DIR"
export DOCKER_CONFIG
EOF

cat >> "$MONITOR_SCRIPT" <<'EOF'
# Use flock to prevent concurrent runs
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    exit 0
fi

NEW_IP=$(curl -s --max-time 5 https://api.ipify.org || curl -s --max-time 5 https://ifconfig.me || echo "FAILED")

if [[ ! "$NEW_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "$(date) [ERROR] Failed to get valid public IP (Response: $NEW_IP)" >> "$LOG_FILE"
    exit 1
fi

OLD_IP=$(cat "$CURRENT_IP_FILE" 2>/dev/null || echo "")

if [ "$NEW_IP" != "$OLD_IP" ]; then
    echo "$(date) [INFO] IP Change detected: $OLD_IP -> $NEW_IP" >> "$LOG_FILE"
    echo "$NEW_IP" > "$CURRENT_IP_FILE"
    
    if [ -n "$DESEC_DOMAIN" ] && [ -n "$DESEC_TOKEN" ]; then
        echo "$(date) [INFO] Updating deSEC DNS record for $DESEC_DOMAIN..." >> "$LOG_FILE"
        DESEC_RESPONSE=$(curl -s -X PATCH "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/" \
            -H "Authorization: Token $DESEC_TOKEN" \
            -H "Content-Type: application/json" \
            -d "[{\"subname\": \"\", \"ttl\": 3600, \"type\": \"A\", \"records\": [\"$NEW_IP\"]}]" 2>&1 || echo "CURL_ERROR")
        
        NEW_IP_ESCAPED=$(echo "$NEW_IP" | sed 's/\./\\./g')
        if [[ "$DESEC_RESPONSE" == "CURL_ERROR" ]]; then
            echo "$(date) [ERROR] Failed to communicate with deSEC API" >> "$LOG_FILE"
        elif [ -z "$DESEC_RESPONSE" ] || echo "$DESEC_RESPONSE" | grep -qE "(${NEW_IP_ESCAPED}|\[\]|\"records\")" ; then
            echo "$(date) [INFO] deSEC DNS updated successfully to $NEW_IP" >> "$LOG_FILE"
        else
            echo "$(date) [WARN] deSEC DNS update may have failed: $DESEC_RESPONSE" >> "$LOG_FILE"
        fi
    fi
    
    sed -i "s|WG_HOST=.*|WG_HOST=$NEW_IP|g" "$COMPOSE_FILE"
    docker compose -f "$COMPOSE_FILE" up -d --no-deps --force-recreate wg-easy
    echo "$(date) [INFO] WireGuard container restarted with new IP" >> "$LOG_FILE"
fi
EOF
chmod +x "$MONITOR_SCRIPT"
CRON_CMD="*/5 * * * * $MONITOR_SCRIPT"
EXISTING_CRON=$(crontab -l 2>/dev/null || true)
echo "$EXISTING_CRON" | grep -v "$MONITOR_SCRIPT" | { cat; echo "$CRON_CMD"; } | crontab -

# --- SECTION 16: STACK ORCHESTRATION & DEPLOYMENT ---
# Execute system deployment and verify global infrastructure integrity.
check_iptables() {
    log_info "Verifying iptables rules..."
    if sudo iptables -t nat -C POSTROUTING -s 10.8.0.0/24 -j MASQUERADE 2>/dev/null && \
       sudo iptables -C FORWARD -i wg0 -j ACCEPT 2>/dev/null && \
       sudo iptables -C FORWARD -o wg0 -j ACCEPT 2>/dev/null; then
        log_info "iptables rules for wg-easy are correctly set up."
    else
        log_warn "iptables rules for wg-easy may not be correctly set up."
        log_warn "Please check your firewall settings if you experience connectivity issues."
    fi
}

echo "=========================================================="
echo "RUNNING SYSTEM DEPLOYMENT"
echo "=========================================================="
sudo modprobe tun || true

sudo env DOCKER_CONFIG="$DOCKER_AUTH_DIR" docker compose -f "$COMPOSE_FILE" up -d --build --remove-orphans

if $DOCKER_CMD ps | grep -q adguard; then
    log_info "AdGuard container is running"
    sleep 5
    if curl -s --max-time 5 "http://$LAN_IP:$PORT_ADGUARD_WEB" > /dev/null; then
        log_info "AdGuard web interface is accessible"
    else
