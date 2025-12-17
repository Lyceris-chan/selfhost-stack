#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2001,SC2015,SC2016,SC2034,SC2024,SC2086
set -euo pipefail

# ==============================================================================
# ZIMAOS PRIVACY HUB v3.9.2
# ==============================================================================
# Self-hosted privacy stack with WireGuard VPN, AdGuard Home DNS filtering,
# and privacy-respecting frontend services.
# ==============================================================================

# --- 0. ARGUMENT PARSING ---
FORCE_CLEAN=false
AUTO_PASSWORD=false
while getopts "cp" opt; do
  case ${opt} in
    c) FORCE_CLEAN=true ;;
    p) AUTO_PASSWORD=true ;;
    *) echo "Usage: $0 [-c (force cleanup/nuke)] [-p (auto-generate passwords)]"; exit 1 ;;
  esac
done

# --- 1. SETUP & VARIABLES ---
APP_NAME="privacy-hub"
BASE_DIR="/DATA/AppData/$APP_NAME"
# Ensure docker dir exists and has correct permissions
mkdir -p "$BASE_DIR/.docker"
sudo chown -R "$(whoami)" "$BASE_DIR/.docker"

# Paths
SRC_DIR="$BASE_DIR/sources"
ENV_DIR="$BASE_DIR/env"
CONFIG_DIR="$BASE_DIR/config"
COMPOSE_FILE="$BASE_DIR/docker-compose.yml"
DASHBOARD_FILE="$BASE_DIR/dashboard.html"
GLUETUN_ENV_FILE="$BASE_DIR/gluetun.env"
HISTORY_LOG="$BASE_DIR/deployment.log"

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

# Logging Functions
log_info() { echo -e "\e[34m[INFO]\e[0m $1"; }
log_warn() { echo -e "\e[33m[WARN]\e[0m $1"; }
log_crit() { echo -e "\e[31m[CRIT]\e[0m $1"; }

# --- 2. CLEANUP FUNCTION ---
ask_confirm() {
    if [ "$FORCE_CLEAN" = true ]; then return 0; fi
    read -r -p "$1 [y/N]: " response
    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

clean_environment() {
    echo "=========================================================="
    echo "🛡️  ENVIRONMENT CHECK & CLEANUP"
    echo "=========================================================="

    if [ "$FORCE_CLEAN" = true ]; then
        log_warn "FORCE CLEANUP ENABLED (-c): Wiping ALL data, configs, and volumes..."
    fi

    TARGET_CONTAINERS="gluetun adguard dashboard portainer watchtower wg-easy hub-api odido-booster redlib wikiless wikiless_redis invidious invidious-db companion libremdb rimgo breezewiki anonymousoverflow scribe vert vertd"
    
    FOUND_CONTAINERS=""
    for c in $TARGET_CONTAINERS; do
        if sudo docker ps -a --format '{{.Names}}' | grep -q "^${c}$"; then
            FOUND_CONTAINERS="$FOUND_CONTAINERS $c"
        fi
    done

    if [ -n "$FOUND_CONTAINERS" ]; then
        if ask_confirm "Remove existing containers?"; then
            sudo docker rm -f $FOUND_CONTAINERS 2>/dev/null || true
            log_info "Containers removed."
        fi
    fi

    CONFLICT_NETS=$(sudo docker network ls --format '{{.Name}}' | grep -E '(_frontnet|_default|privacy-hub|deployment)' || true)
    if [ -n "$CONFLICT_NETS" ]; then
        if ask_confirm "Prune networks?"; then
            sudo docker network prune -f > /dev/null
            log_info "Networks pruned."
        fi
    fi

    if [ -d "$BASE_DIR" ] || sudo docker volume ls -q | grep -q "portainer"; then
        if ask_confirm "Wipe ALL data (Resets Portainer/AdGuard Logins)?"; then
            log_info "Removing all deployment artifacts..."
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
                sudo rm -rf "$BASE_DIR/.docker" 2>/dev/null || true
                sudo rm -rf "$BASE_DIR" 2>/dev/null || true
            fi
            # Remove volumes - try both unprefixed and prefixed names (docker-compose uses project prefix)
            for vol in portainer-data adguard-work redis-data postgresdata wg-config companioncache odido-data; do
                sudo docker volume rm -f "$vol" 2>/dev/null || true
                sudo docker volume rm -f "${APP_NAME}_${vol}" 2>/dev/null || true
            done
            log_info "All deployment artifacts, configs, env files, and volumes wiped."
        fi
    fi
    
    if [ "$FORCE_CLEAN" = true ]; then
        log_warn "NUCLEAR CLEANUP MODE: Restoring system to pre-deployment state..."
        echo ""
        
        # ============================================================
        # PHASE 1: Stop all containers to release locks
        # ============================================================
        log_info "Phase 1: Stopping all deployment containers..."
        for c in $TARGET_CONTAINERS; do
            if sudo docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${c}$"; then
                log_info "  Stopping: $c"
                sudo docker stop "$c" 2>/dev/null || true
            fi
        done
        sleep 3
        
        # ============================================================
        # PHASE 2: Remove all containers
        # ============================================================
        log_info "Phase 2: Removing all deployment containers..."
        for c in $TARGET_CONTAINERS; do
            if sudo docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${c}$"; then
                log_info "  Removing container: $c"
                sudo docker rm -f "$c" 2>/dev/null || true
            fi
        done
        
        # ============================================================
        # PHASE 3: Remove ALL volumes (list everything, match patterns)
        # ============================================================
        log_info "Phase 3: Removing all deployment volumes..."
        ALL_VOLUMES=$(sudo docker volume ls -q 2>/dev/null || echo "")
        for vol in $ALL_VOLUMES; do
            case "$vol" in
                # Match exact names
                portainer-data|adguard-work|redis-data|postgresdata|wg-config|companioncache|odido-data)
                    log_info "  Removing volume: $vol"
                    sudo docker volume rm -f "$vol" 2>/dev/null || true
                    ;;
                # Match prefixed names (docker-compose project prefix)
                privacy-hub_*|privacyhub_*)
                    log_info "  Removing volume: $vol"
                    sudo docker volume rm -f "$vol" 2>/dev/null || true
                    ;;
                # Match any volume containing our identifiers
                *portainer*|*adguard*|*redis*|*postgres*|*wg-config*|*companion*|*odido*)
                    log_info "  Removing volume: $vol"
                    sudo docker volume rm -f "$vol" 2>/dev/null || true
                    ;;
            esac
        done
        
        # ============================================================
        # PHASE 4: Remove ALL networks created by this deployment
        # ============================================================
        log_info "Phase 4: Removing deployment networks..."
        ALL_NETWORKS=$(sudo docker network ls --format '{{.Name}}' 2>/dev/null || echo "")
        for net in $ALL_NETWORKS; do
            case "$net" in
                # Skip default Docker networks
                bridge|host|none) continue ;;
                # Match our networks
                privacy-hub_*|privacyhub_*|*frontnet*|*_default)
                    log_info "  Removing network: $net"
                    sudo docker network rm "$net" 2>/dev/null || true
                    ;;
            esac
        done
        
        # ============================================================
        # PHASE 5: Remove ALL images built/pulled by this deployment
        # ============================================================
        log_info "Phase 5: Removing deployment images..."
        # Remove images by known names
        KNOWN_IMAGES="qmcgaw/gluetun adguard/adguardhome nginx:alpine portainer/portainer-ce containrrr/watchtower python:3.11-alpine ghcr.io/wg-easy/wg-easy redis:8-alpine quay.io/invidious/invidious quay.io/invidious/invidious-companion docker.io/library/postgres:14 ghcr.io/zyachel/libremdb codeberg.org/rimgo/rimgo quay.io/pussthecatorg/breezewiki ghcr.io/httpjamesm/anonymousoverflow:release klutchell/unbound ghcr.io/vert-sh/vertd ghcr.io/vert-sh/vert httpd:alpine alpine:latest neilpang/acme.sh"
        for img in $KNOWN_IMAGES; do
            if sudo docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -q "$img"; then
                log_info "  Removing image: $img"
                sudo docker rmi -f "$img" 2>/dev/null || true
            fi
        done
        # Remove locally built images
        ALL_IMAGES=$(sudo docker images --format '{{.Repository}}:{{.Tag}} {{.ID}}' 2>/dev/null || echo "")
        echo "$ALL_IMAGES" | while read -r img_info; do
            img_name=$(echo "$img_info" | awk '{print $1}')
            img_id=$(echo "$img_info" | awk '{print $2}')
            case "$img_name" in
                *privacy-hub*|*privacyhub*|*odido*|*redlib*|*wikiless*|*scribe*|*vert*|*invidious*|*sources_*)
                    log_info "  Removing image: $img_name"
                    sudo docker rmi -f "$img_id" 2>/dev/null || true
                    ;;
                "<none>:<none>")
                    # Remove dangling images
                    sudo docker rmi -f "$img_id" 2>/dev/null || true
                    ;;
            esac
        done
        
        # ============================================================
        # PHASE 6: Remove ALL data directories and files
        # ============================================================
        log_info "Phase 6: Removing all data directories and files..."
        
        # Main data directory
        if [ -d "$BASE_DIR" ]; then
            log_info "  Removing: $BASE_DIR"
            sudo rm -rf "$BASE_DIR"
        fi
        
        # Alternative locations that might have been created
        if [ -d "/DATA/AppData/privacy-hub" ]; then
            log_info "  Removing: /DATA/AppData/privacy-hub"
            sudo rm -rf "/DATA/AppData/privacy-hub"
        fi
        
        # ============================================================
        # PHASE 7: Remove cron jobs added by this script
        # ============================================================
        log_info "Phase 7: Removing cron jobs..."
        EXISTING_CRON=$(crontab -l 2>/dev/null || true)
        if echo "$EXISTING_CRON" | grep -q "wg-ip-monitor"; then
            log_info "  Removing wg-ip-monitor cron job"
            echo "$EXISTING_CRON" | grep -v "wg-ip-monitor" | grep -v "privacy-hub" | crontab - 2>/dev/null || true
        fi
        
        # ============================================================
        # PHASE 8: Clean up Docker system
        # ============================================================
        log_info "Phase 8: Final Docker cleanup..."
        sudo docker volume prune -f 2>/dev/null || true
        sudo docker network prune -f 2>/dev/null || true
        sudo docker image prune -af 2>/dev/null || true
        sudo docker builder prune -af 2>/dev/null || true
        sudo docker system prune -f 2>/dev/null || true
        
        echo ""
        log_info "============================================================"
        log_info "NUCLEAR CLEANUP COMPLETE"
        log_info "============================================================"
        log_info "The following have been removed:"
        log_info "  ✓ All deployment containers ($TARGET_CONTAINERS)"
        log_info "  ✓ All deployment volumes (portainer-data, adguard-work, etc.)"
        log_info "  ✓ All deployment networks (frontnet, etc.)"
        log_info "  ✓ All deployment images"
        log_info "  ✓ All configuration files and secrets"
        log_info "  ✓ All data directories ($BASE_DIR)"
        log_info "  ✓ All cron jobs (wg-ip-monitor)"
        log_info ""
        log_info "System restored to pre-deployment state."
        log_info "============================================================"
    fi
}

# Run cleanup
clean_environment

mkdir -p "$BASE_DIR" "$SRC_DIR" "$ENV_DIR" "$CONFIG_DIR/unbound" "$AGH_CONF_DIR" "$NGINX_CONF_DIR" "$WG_PROFILES_DIR"

# Initialize log files and data files
touch "$HISTORY_LOG" "$ACTIVE_WG_CONF" "$BASE_DIR/.data_usage" "$BASE_DIR/.wge_data_usage"
if [ ! -f "$ACTIVE_PROFILE_NAME_FILE" ]; then echo "Initial-Setup" > "$ACTIVE_PROFILE_NAME_FILE"; fi
chmod 666 "$ACTIVE_PROFILE_NAME_FILE" "$HISTORY_LOG" "$BASE_DIR/.data_usage" "$BASE_DIR/.wge_data_usage"

# --- 3. DYNAMIC SUBNET ALLOCATION ---
log_info "Allocating Private Network Subnet..."

FOUND_SUBNET=""
FOUND_OCTET=""

for i in {20..30}; do
    TEST_SUBNET="172.$i.0.0/16"
    TEST_NET_NAME="probe_net_$i"
    if sudo docker network create --subnet="$TEST_SUBNET" "$TEST_NET_NAME" >/dev/null 2>&1; then
        sudo docker network rm "$TEST_NET_NAME" >/dev/null 2>&1
        FOUND_SUBNET="$TEST_SUBNET"
        FOUND_OCTET="$i"
        break
    fi
done

if [ -z "$FOUND_SUBNET" ]; then
    log_crit "No free subnets found. Please run 'docker network prune' manually."
    exit 1
fi

DOCKER_SUBNET="$FOUND_SUBNET"
log_info "Assigned Subnet: $DOCKER_SUBNET"

# --- 4. NETWORK INTELLIGENCE ---
log_info "Analyzing Network..."
LAN_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+\.\d+\.\d+\.\d+' | grep -v '^127\.' | head -n1 || echo "192.168.0.100")
PUBLIC_IP=$(curl -s --max-time 5 https://api.ipify.org || curl -s --max-time 5 https://ifconfig.me || echo "$LAN_IP")
echo "$PUBLIC_IP" > "$CURRENT_IP_FILE"

# --- 5. AUTHENTICATION & SECRETS ---
if [ ! -f "$BASE_DIR/.secrets" ]; then
    echo "========================================"
    echo " CREDENTIAL SETUP"
    echo "========================================"
    
    if [ "$AUTO_PASSWORD" = true ]; then
        log_info "Auto-generating VPN and AdGuard passwords..."
        VPN_PASS_RAW=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 24)
        AGH_PASS_RAW=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 24)
        log_info "Passwords generated (will be displayed at the end)"
        echo ""
    else
        echo -n "1. Enter password for VPN Web UI: "
        read -rs VPN_PASS_RAW
        echo ""
        echo -n "2. Enter password for AdGuard Home: "
        read -rs AGH_PASS_RAW
        echo ""
    fi
    
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
        # Use curl with -L to follow redirects and capture the final URL
        # Note: curl may fail on network issues, so we use || true to prevent script exit
        ODIDO_REDIRECT_URL=$(curl -sL -o /dev/null -w '%{url_effective}' \
            -H "Authorization: Bearer $ODIDO_TOKEN" \
            -H "User-Agent: T-Mobile 5.3.28 (Android 10; 10)" \
            "https://capi.odido.nl/account/current" 2>/dev/null || true)
        
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
    
    log_info "Generating Secrets..."
    ODIDO_API_KEY=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32)
    sudo docker pull -q ghcr.io/wg-easy/wg-easy:latest > /dev/null
    HASH_OUTPUT=$(sudo docker run --rm ghcr.io/wg-easy/wg-easy wgpw "$VPN_PASS_RAW")
    WG_HASH_CLEAN=$(echo "$HASH_OUTPUT" | grep -oP "(?<=PASSWORD_HASH=')[^']+")
    WG_HASH_ESCAPED="${WG_HASH_CLEAN//\$/\$\$}"

    AGH_USER="adguard"
    AGH_PASS_HASH=$(sudo docker run --rm httpd:alpine htpasswd -B -n -b "$AGH_USER" "$AGH_PASS_RAW" | cut -d ":" -f 2)
    
    cat > "$BASE_DIR/.secrets" <<EOF
VPN_PASS_RAW=$VPN_PASS_RAW
AGH_PASS_RAW=$AGH_PASS_RAW
WG_HASH_ESCAPED=$WG_HASH_ESCAPED
AGH_PASS_HASH=$AGH_PASS_HASH
DESEC_DOMAIN=$DESEC_DOMAIN
DESEC_TOKEN=$DESEC_TOKEN
SCRIBE_GH_USER=$SCRIBE_GH_USER
SCRIBE_GH_TOKEN=$SCRIBE_GH_TOKEN
ODIDO_USER_ID=$ODIDO_USER_ID
ODIDO_TOKEN=$ODIDO_TOKEN
ODIDO_API_KEY=$ODIDO_API_KEY
EOF
else
    source "$BASE_DIR/.secrets"
    if [ -z "${ODIDO_API_KEY:-}" ]; then
        ODIDO_API_KEY=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32)
        echo "ODIDO_API_KEY=$ODIDO_API_KEY" >> "$BASE_DIR/.secrets"
    fi
    AGH_USER="adguard"
fi

echo ""
echo "=========================================================="
echo " PROTON WIREGUARD CONFIGURATION"
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

# --- 6. GLUETUN VPN CONFIGURATION ---
log_info "Configuring Gluetun..."
sudo docker pull -q qmcgaw/gluetun:latest > /dev/null

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

# --- 7. SECRET GENERATION ---
SCRIBE_SECRET=$(head -c 64 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 64)
ANONYMOUS_SECRET=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32)
IV_HMAC=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 16)
IV_COMPANION=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 16)

# --- 8. PORT CONFIGURATION ---
PORT_INT_REDLIB=8080; PORT_INT_WIKILESS=8180; PORT_INT_INVIDIOUS=3000
PORT_INT_LIBREMDB=3001; PORT_INT_RIMGO=3002; PORT_INT_BREEZEWIKI=10416
PORT_INT_ANONYMOUS=8480; PORT_INT_VERT=80; PORT_INT_VERTD=24153
PORT_ADGUARD_WEB=8083; PORT_DASHBOARD_WEB=8081
PORT_PORTAINER=9000; PORT_WG_WEB=51821; PORT_WG_UDP=51820
PORT_REDLIB=8080; PORT_WIKILESS=8180; PORT_INVIDIOUS=3000; PORT_LIBREMDB=3001
PORT_RIMGO=3002; PORT_SCRIBE=8280; PORT_BREEZEWIKI=8380; PORT_ANONYMOUS=8480
PORT_VERT=5555; PORT_VERTD=24153

# --- 9. SERVICE CONFIGURATION ---
log_info "Generating Service Configs..."

# DNS & Certificate Setup
log_info "Setting up DNS and certificates..."

if [ -n "$DESEC_DOMAIN" ] && [ -n "$DESEC_TOKEN" ]; then
    log_info "deSEC domain provided: $DESEC_DOMAIN"
    log_info "Configuring Let's Encrypt with DNS-01 challenge..."
    
    log_info "Updating deSEC DNS record to point to $PUBLIC_IP..."
    DESEC_RESPONSE=$(curl -s -X PATCH "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/" \
        -H "Authorization: Token $DESEC_TOKEN" \
        -H "Content-Type: application/json" \
        -d "[{\"subname\": \"\", \"ttl\": 3600, \"type\": \"A\", \"records\": [\"$PUBLIC_IP\"]}]" 2>&1)
    
    PUBLIC_IP_ESCAPED="${PUBLIC_IP//./\\.}"
    if [ -z "$DESEC_RESPONSE" ] || echo "$DESEC_RESPONSE" | grep -qE "(${PUBLIC_IP_ESCAPED}|\[\]|\"records\")" ; then
        log_info "DNS record updated successfully"
    else
        log_warn "DNS update response: $DESEC_RESPONSE"
    fi
    
    log_info "Setting up SSL certificates..."
    mkdir -p "$AGH_CONF_DIR/certbot"
    
    log_info "Attempting Let's Encrypt certificate..."
    CERT_SUCCESS=false
    CERT_LOG_FILE="$AGH_CONF_DIR/certbot/last_run.log"

    # Request Let's Encrypt certificate via DNS-01 challenge
    CERT_OUTPUT=$(sudo docker run --rm \
        -v "$AGH_CONF_DIR:/acme" \
        -e "DESEC_Token=$DESEC_TOKEN" \
        -e "DEDYN_TOKEN=$DESEC_TOKEN" \
        -e "DESEC_DOMAIN=$DESEC_DOMAIN" \
        neilpang/acme.sh:latest \
        --issue \
        --dns dns_desec \
        --dnssleep 120 \
        --debug 2 \
        -d "$DESEC_DOMAIN" \
        -d "*.$DESEC_DOMAIN" \
        --keylength ec-256 \
        --server letsencrypt \
        --home /acme \
        --config-home /acme \
        --cert-home /acme/certs 2>&1) && CERT_SUCCESS=true || CERT_SUCCESS=false
    echo "$CERT_OUTPUT" > "$CERT_LOG_FILE"

    if [ "$CERT_SUCCESS" = true ] && [ -f "$AGH_CONF_DIR/certs/${DESEC_DOMAIN}_ecc/fullchain.cer" ]; then
        cp "$AGH_CONF_DIR/certs/${DESEC_DOMAIN}_ecc/fullchain.cer" "$AGH_CONF_DIR/ssl.crt"
        cp "$AGH_CONF_DIR/certs/${DESEC_DOMAIN}_ecc/${DESEC_DOMAIN}.key" "$AGH_CONF_DIR/ssl.key"
        log_info "Let's Encrypt certificate installed successfully!"
        log_info "Certificate log saved to $CERT_LOG_FILE"
    elif [ "$CERT_SUCCESS" = true ] && [ -f "$AGH_CONF_DIR/certs/${DESEC_DOMAIN}/fullchain.cer" ]; then
        cp "$AGH_CONF_DIR/certs/${DESEC_DOMAIN}/fullchain.cer" "$AGH_CONF_DIR/ssl.crt"
        cp "$AGH_CONF_DIR/certs/${DESEC_DOMAIN}/${DESEC_DOMAIN}.key" "$AGH_CONF_DIR/ssl.key"
        log_info "Let's Encrypt certificate installed successfully!"
        log_info "Certificate log saved to $CERT_LOG_FILE"
    else
        RETRY_TIME=$(echo "$CERT_OUTPUT" | grep -oiE 'retry after [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]+ UTC' | head -1 | sed 's/retry after //I')
        if [ -n "$RETRY_TIME" ]; then
            RETRY_EPOCH=$(date -u -d "$RETRY_TIME" +%s 2>/dev/null || echo "")
            NOW_EPOCH=$(date -u +%s)
            if [ -n "$RETRY_EPOCH" ] && [ "$RETRY_EPOCH" -gt "$NOW_EPOCH" ] 2>/dev/null; then
                SECS_LEFT=$((RETRY_EPOCH - NOW_EPOCH))
                HRS_LEFT=$((SECS_LEFT / 3600))
                MINS_LEFT=$(((SECS_LEFT % 3600) / 60))
                log_warn "Let's Encrypt rate limited. Retry after $RETRY_TIME (~${HRS_LEFT}h ${MINS_LEFT}m)."
            else
                log_warn "Let's Encrypt rate limited. Retry after $RETRY_TIME."
            fi
        else
            log_warn "Let's Encrypt failed (see $CERT_LOG_FILE)."
        fi
        log_warn "Let's Encrypt failed, generating self-signed certificate..."
        sudo docker run --rm \
            -v "$AGH_CONF_DIR:/certs" \
            alpine:latest /bin/sh -c "
            apk add --no-cache openssl > /dev/null 2>&1
            openssl req -x509 -newkey rsa:4096 -sha256 \
                -days 365 -nodes \
                -keyout /certs/ssl.key -out /certs/ssl.crt \
                -subj '/CN=$DESEC_DOMAIN' \
                -addext 'subjectAltName=DNS:$DESEC_DOMAIN,DNS:*.$DESEC_DOMAIN,IP:$PUBLIC_IP'
            "
        log_info "Generated self-signed certificate for $DESEC_DOMAIN"
    fi
    
    DNS_SERVER_NAME="$DESEC_DOMAIN"
    
    if [ -f "$AGH_CONF_DIR/ssl.crt" ] && [ -f "$AGH_CONF_DIR/ssl.key" ]; then
        log_info "SSL certificate ready for $DESEC_DOMAIN"
    else
        log_warn "SSL certificate files not found - AdGuard may not start with TLS"
    fi
    
else
    log_info "No deSEC domain provided, generating self-signed certificate..."
    sudo docker run --rm -v "$AGH_CONF_DIR:/certs" alpine:latest /bin/sh -c \
        "apk add --no-cache openssl && \
         openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
         -keyout /certs/ssl.key -out /certs/ssl.crt \
         -subj '/CN=$LAN_IP' \
         -addext 'subjectAltName=IP:$LAN_IP,IP:$PUBLIC_IP'"
    
    log_info "Self-signed certificate generated"
    DNS_SERVER_NAME="$LAN_IP"
fi

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
filters:
  - enabled: true
    url: https://raw.githubusercontent.com/Lyceris-chan/dns-blocklist-generator/refs/heads/main/blocklist.txt
    name: "Lyceris-chan Blocklist"
    id: 1
filters_update_interval: 1
EOF

cat > "$NGINX_CONF" <<EOF
server {
    listen $PORT_DASHBOARD_WEB default_server;
    root /usr/share/nginx/html;
    index index.html;
    location /api/ {
        proxy_pass http://hub-api:55555/;
        proxy_set_header Host \$host;
        proxy_buffering off;
        proxy_cache off;
    }
}
EOF

# --- 10. ENVIRONMENT FILES ---
cat > "$ENV_DIR/libremdb.env" <<EOF
NEXT_PUBLIC_URL=http://$LAN_IP:$PORT_LIBREMDB
AXIOS_USERAGENT=Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0
NEXT_TELEMETRY_DISABLED=1
EOF
cat > "$ENV_DIR/anonymousoverflow.env" <<EOF
APP_URL=http://$LAN_IP:$PORT_ANONYMOUS
JWT_SIGNING_SECRET=$ANONYMOUS_SECRET
EOF
cat > "$ENV_DIR/scribe.env" <<EOF
SCRIBE_HOST=0.0.0.0
PORT=$PORT_SCRIBE
SECRET_KEY_BASE=$SCRIBE_SECRET
LUCKY_ENV=production
APP_DOMAIN=$LAN_IP:$PORT_SCRIBE
GITHUB_USERNAME="$SCRIBE_GH_USER"
GITHUB_PERSONAL_ACCESS_TOKEN="$SCRIBE_GH_TOKEN"
EOF

# --- 11. REPOSITORY SETUP ---
log_info "Cloning Repositories..."
clone_repo() { 
    if [ ! -d "$2/.git" ]; then 
        git clone --depth 1 "$1" "$2"
    else 
        (cd "$2" && git fetch --all && git reset --hard "origin/$(git rev-parse --abbrev-ref HEAD)" && git pull)
    fi
}
clone_repo "https://github.com/Metastem/Wikiless" "$SRC_DIR/wikiless"
cat > "$SRC_DIR/wikiless/wikiless.config" <<'EOF'
const config = {
  /**
  * Set these configs below to suite your environment.
  */
  domain: process.env.DOMAIN || '', // Set to your own domain
  default_lang: process.env.DEFAULT_LANG || 'en', // Set your own language by default
  theme: process.env.THEME || 'dark', // Set to 'white' or 'dark' by default
  http_addr: process.env.HTTP_ADDR || '0.0.0.0', // don't touch, unless you know what your doing
  nonssl_port: process.env.NONSSL_PORT || 8080, // don't touch, unless you know what your doing
  
  /**
  * You can configure redis below if needed.
  * By default Wikiless uses 'redis://127.0.0.1:6379' as the Redis URL.
  * Versions before 0.1.1 Wikiless used redis_host and redis_port properties,
  * but they are not supported anymore.
  * process.env.REDIS_HOST is still here for backwards compatibility.
  */
  redis_url: process.env.REDIS_URL || process.env.REDIS_HOST || 'redis://127.0.0.1:6379',
  redis_password: process.env.REDIS_PASSWORD,
  
  /**
  * You might need to change these configs below if you host through a reverse
  * proxy like nginx.
  */
  trust_proxy: process.env.TRUST_PROXY === 'true' || true,
  trust_proxy_address: process.env.TRUST_PROXY_ADDRESS || '127.0.0.1',

  /**
  * Redis cache expiration values (in seconds).
  * When the cache expires, new content is fetched from Wikipedia (when the
  * given URL is revisited).
  */
  setexs: {
    wikipage: process.env.WIKIPAGE_CACHE_EXPIRATION || (60 * 60 * 1), // 1 hour
  },

  /**
  * Wikimedia requires a HTTP User-agent header for all Wikimedia related
  * requests. It's a good idea to change this to something unique.
  * Read more: https://useragents.me/
  */
  wikimedia_useragent: process.env.wikimedia_useragent || 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36',

  /**
  * Cache control. Wikiless can automatically remove the cached media files from
  * the server. Cache control is on by default.
  * 'cache_control_interval' sets the interval for often the cache directory
  * is emptied (in hours). Default is every 24 hours.
  */
  cache_control: process.env.CACHE_CONTROL !== 'true' || true,
  cache_control_interval: process.env.CACHE_CONTROL_INTERVAL || 24,
}

module.exports = config
EOF
clone_repo "https://git.sr.ht/~edwardloveall/scribe" "$SRC_DIR/scribe"
clone_repo "https://github.com/iv-org/invidious.git" "$SRC_DIR/invidious"
clone_repo "https://github.com/Lyceris-chan/odido-bundle-booster.git" "$SRC_DIR/odido-bundle-booster"

mkdir -p "$SRC_DIR/redlib"
cat > "$SRC_DIR/redlib/Dockerfile" <<EOF
FROM alpine:3.19
RUN apk add --no-cache curl ca-certificates
RUN curl -L -o /usr/local/bin/redlib "https://github.com/mycodedoesnotcompile2/redlib_fork/releases/latest/download/redlib-0.36.0-wproxy-x86_64-unknown-linux-musl"
RUN chmod +x /usr/local/bin/redlib
RUN adduser --home /nonexistent --no-create-home --disabled-password redlib
USER redlib
EXPOSE 8080
HEALTHCHECK --interval=1m --timeout=3s CMD wget --spider -q http://localhost:8080/settings || exit 1
CMD ["redlib"]
EOF
clone_repo "https://github.com/VERT-sh/VERT.git" "$SRC_DIR/vert"
# Patch VERT Dockerfile to add missing build args
if ! grep -q "ARG PUB_DISABLE_FAILURE_BLOCKS" "$SRC_DIR/vert/Dockerfile"; then
    if grep -q "^ARG PUB_STRIPE_KEY$" "$SRC_DIR/vert/Dockerfile" && grep -q "^ENV PUB_STRIPE_KEY=" "$SRC_DIR/vert/Dockerfile"; then
        sed -i '/^ARG PUB_STRIPE_KEY$/a ARG PUB_DISABLE_FAILURE_BLOCKS\nARG PUB_DISABLE_DONATIONS' "$SRC_DIR/vert/Dockerfile"
        sed -i '/^ENV PUB_STRIPE_KEY=\${PUB_STRIPE_KEY}$/a ENV PUB_DISABLE_FAILURE_BLOCKS=${PUB_DISABLE_FAILURE_BLOCKS}\nENV PUB_DISABLE_DONATIONS=${PUB_DISABLE_DONATIONS}' "$SRC_DIR/vert/Dockerfile"
        log_info "Patched VERT Dockerfile to add missing PUB_DISABLE_FAILURE_BLOCKS and PUB_DISABLE_DONATIONS ARG/ENV"
    else
        log_warn "VERT Dockerfile structure changed - could not apply patches. Build may fail."
    fi
fi

chmod -R 777 "$SRC_DIR/invidious" "$SRC_DIR/vert" "$ENV_DIR" "$CONFIG_DIR" "$WG_PROFILES_DIR"

# --- 12. CONTROL SCRIPTS ---
cat > "$WG_CONTROL_SCRIPT" <<'EOF'
#!/bin/sh
ACTION=$1
PROFILE_NAME=$2
PROFILES_DIR="/profiles"
ACTIVE_CONF="/active-wg.conf"
NAME_FILE="/app/.active_profile_name"
LOG_FILE="/app/deployment.log"

sanitize_json_string() {
    printf '%s' "$1" | tr -d '\000-\037' | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

if [ "$ACTION" = "activate" ]; then
    if [ -f "$PROFILES_DIR/$PROFILE_NAME.conf" ]; then
        ln -sf "$PROFILES_DIR/$PROFILE_NAME.conf" "$ACTIVE_CONF"
        echo "$PROFILE_NAME" > "$NAME_FILE"
        DEPENDENTS="redlib wikiless wikiless_redis invidious invidious-db companion libremdb rimgo breezewiki anonymousoverflow scribe"
        docker stop $DEPENDENTS 2>/dev/null || true
        docker-compose -f /app/docker-compose.yml up -d --force-recreate gluetun 2>/dev/null || true
        sleep 5
        docker start $DEPENDENTS 2>/dev/null || true
    else
        echo "Error: Profile not found"
        exit 1
    fi
elif [ "$ACTION" = "delete" ]; then
    if [ -f "$PROFILES_DIR/$PROFILE_NAME.conf" ]; then
        rm "$PROFILES_DIR/$PROFILE_NAME.conf"
    fi
elif [ "$ACTION" = "status" ]; then
    GLUETUN_STATUS="down"
    GLUETUN_HEALTHY="false"
    HANDSHAKE_AGO="N/A"
    ENDPOINT="--"
    PUBLIC_IP="--"
    DATA_FILE="/app/.data_usage"
    
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^gluetun$"; then
        # Check container health status
        HEALTH=$(docker inspect --format='{{.State.Health.Status}}' gluetun 2>/dev/null || echo "unknown")
        if [ "$HEALTH" = "healthy" ]; then
            GLUETUN_HEALTHY="true"
        fi
        
        # Use gluetun's HTTP control server API (port 8000) for status
        # API docs: https://github.com/qdm12/gluetun-wiki/blob/main/setup/advanced/control-server.md
        
        # Get VPN status from control server
        VPN_STATUS_RESPONSE=$(docker exec gluetun wget -qO- --timeout=3 http://127.0.0.1:8000/v1/vpn/status 2>/dev/null || echo "")
        if [ -n "$VPN_STATUS_RESPONSE" ]; then
            # Extract status from {"status":"running"} or {"status":"stopped"}
            VPN_RUNNING=$(echo "$VPN_STATUS_RESPONSE" | grep -o '"status":"running"' || echo "")
            if [ -n "$VPN_RUNNING" ]; then
                GLUETUN_STATUS="up"
                HANDSHAKE_AGO="Connected"
            else
                GLUETUN_STATUS="down"
                HANDSHAKE_AGO="Disconnected"
            fi
        elif [ "$GLUETUN_HEALTHY" = "true" ]; then
            # Fallback: if container is healthy, assume VPN is up
            GLUETUN_STATUS="up"
            HANDSHAKE_AGO="Connected (API unavailable)"
        fi
        
        # Get public IP from control server
        PUBLIC_IP_RESPONSE=$(docker exec gluetun wget -qO- --timeout=3 http://127.0.0.1:8000/v1/publicip/ip 2>/dev/null || echo "")
        if [ -n "$PUBLIC_IP_RESPONSE" ]; then
            # Extract IP from {"public_ip":"x.x.x.x"}
            EXTRACTED_IP=$(echo "$PUBLIC_IP_RESPONSE" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "")
            if [ -n "$EXTRACTED_IP" ]; then
                PUBLIC_IP="$EXTRACTED_IP"
            fi
        fi
        
        # Fallback to external IP check if control server didn't return an IP
        if [ -z "$PUBLIC_IP" ] || [ "$PUBLIC_IP" = "--" ]; then
            PUBLIC_IP=$(docker exec gluetun wget -qO- --timeout=5 https://api.ipify.org 2>/dev/null || echo "--")
        fi
        
        # Try to get endpoint from WireGuard config if available
        WG_CONF_ENDPOINT=$(docker exec gluetun cat /gluetun/wireguard/wg0.conf 2>/dev/null | grep -i "^Endpoint" | cut -d'=' -f2 | tr -d ' ' | head -1 || echo "")
        if [ -n "$WG_CONF_ENDPOINT" ]; then
            ENDPOINT="$WG_CONF_ENDPOINT"
        fi
        
        # Get current RX/TX from /proc/net/dev (works for tun0 or wg0 interface)
        # Format: iface: rx_bytes rx_packets ... tx_bytes tx_packets ...
        NET_DEV=$(docker exec gluetun cat /proc/net/dev 2>/dev/null || echo "")
        CURRENT_RX="0"
        CURRENT_TX="0"
        if [ -n "$NET_DEV" ]; then
            # Try tun0 first (OpenVPN), then wg0 (WireGuard)
            VPN_LINE=$(echo "$NET_DEV" | grep -E "^\s*(tun0|wg0):" | head -1 || echo "")
            if [ -n "$VPN_LINE" ]; then
                # Extract RX bytes (field 2) and TX bytes (field 10)
                CURRENT_RX=$(echo "$VPN_LINE" | awk '{print $2}' 2>/dev/null || echo "0")
                CURRENT_TX=$(echo "$VPN_LINE" | awk '{print $10}' 2>/dev/null || echo "0")
                case "$CURRENT_RX" in ''|*[!0-9]*) CURRENT_RX="0" ;; esac
                case "$CURRENT_TX" in ''|*[!0-9]*) CURRENT_TX="0" ;; esac
            fi
        fi
        
        # Load previous values and calculate cumulative total
        PREV_RX="0"
        PREV_TX="0"
        TOTAL_RX="0"
        TOTAL_TX="0"
        LAST_RX="0"
        LAST_TX="0"
        if [ -f "$DATA_FILE" ]; then
            . "$DATA_FILE" 2>/dev/null || true
        fi
        
        # Detect counter reset (container restart) - current < last means reset
        if { [ "$CURRENT_RX" -lt "$LAST_RX" ] || [ "$CURRENT_TX" -lt "$LAST_TX" ]; } 2>/dev/null; then
            # Counter reset detected - add last values to total before reset
            TOTAL_RX=$((TOTAL_RX + LAST_RX))
            TOTAL_TX=$((TOTAL_TX + LAST_TX))
        fi
        
        # Calculate session values (current readings)
        SESSION_RX="$CURRENT_RX"
        SESSION_TX="$CURRENT_TX"
        
        # Calculate all-time totals
        ALLTIME_RX=$((TOTAL_RX + CURRENT_RX))
        ALLTIME_TX=$((TOTAL_TX + CURRENT_TX))
        
        # Save state
        cat > "$DATA_FILE" <<DATAEOF
LAST_RX=$CURRENT_RX
LAST_TX=$CURRENT_TX
TOTAL_RX=$TOTAL_RX
TOTAL_TX=$TOTAL_TX
DATAEOF
    else
        # Container not running - load saved totals
        ALLTIME_RX="0"
        ALLTIME_TX="0"
        SESSION_RX="0"
        SESSION_TX="0"
        if [ -f "$DATA_FILE" ]; then
            . "$DATA_FILE" 2>/dev/null || true
            ALLTIME_RX=$((TOTAL_RX + LAST_RX))
            ALLTIME_TX=$((TOTAL_TX + LAST_TX))
        fi
    fi
    
    ACTIVE_NAME=$(cat "$NAME_FILE" 2>/dev/null | tr -d '\n\r' || echo "Unknown")
    if [ -z "$ACTIVE_NAME" ]; then ACTIVE_NAME="Unknown"; fi
    
    WGE_STATUS="down"
    WGE_HOST="Unknown"
    WGE_CLIENTS="0"
    WGE_CONNECTED="0"
    
    WGE_SESSION_RX="0"
    WGE_SESSION_TX="0"
    WGE_TOTAL_RX="0"
    WGE_TOTAL_TX="0"
    WGE_DATA_FILE="/app/.wge_data_usage"
    
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^wg-easy$"; then
        WGE_STATUS="up"
        WGE_HOST=$(docker exec wg-easy printenv WG_HOST 2>/dev/null | tr -d '\n\r' || echo "Unknown")
        if [ -z "$WGE_HOST" ]; then WGE_HOST="Unknown"; fi
        WG_PEER_DATA=$(docker exec wg-easy wg show wg0 2>/dev/null || echo "")
        if [ -n "$WG_PEER_DATA" ]; then
            WGE_CLIENTS=$(echo "$WG_PEER_DATA" | grep -c "^peer:" 2>/dev/null || echo "0")
            CONNECTED_COUNT=0
            
            # Calculate total RX/TX from all peers
            WGE_CURRENT_RX=0
            WGE_CURRENT_TX=0
            for rx in $(echo "$WG_PEER_DATA" | grep "transfer:" | awk '{print $2}' | sed 's/[^0-9]//g' 2>/dev/null || echo ""); do
                case "$rx" in ''|*[!0-9]*) ;; *) WGE_CURRENT_RX=$((WGE_CURRENT_RX + rx)) ;; esac
            done
            for tx in $(echo "$WG_PEER_DATA" | grep "transfer:" | awk '{print $4}' | sed 's/[^0-9]//g' 2>/dev/null || echo ""); do
                case "$tx" in ''|*[!0-9]*) ;; *) WGE_CURRENT_TX=$((WGE_CURRENT_TX + tx)) ;; esac
            done
            
            # Load previous values for WG-Easy
            WGE_LAST_RX="0"
            WGE_LAST_TX="0"
            WGE_SAVED_TOTAL_RX="0"
            WGE_SAVED_TOTAL_TX="0"
            if [ -f "$WGE_DATA_FILE" ]; then
                . "$WGE_DATA_FILE" 2>/dev/null || true
            fi
            
            # Detect counter reset
            if { [ "$WGE_CURRENT_RX" -lt "$WGE_LAST_RX" ] || [ "$WGE_CURRENT_TX" -lt "$WGE_LAST_TX" ]; } 2>/dev/null; then
                WGE_SAVED_TOTAL_RX=$((WGE_SAVED_TOTAL_RX + WGE_LAST_RX))
                WGE_SAVED_TOTAL_TX=$((WGE_SAVED_TOTAL_TX + WGE_LAST_TX))
            fi
            
            WGE_SESSION_RX="$WGE_CURRENT_RX"
            WGE_SESSION_TX="$WGE_CURRENT_TX"
            WGE_TOTAL_RX=$((WGE_SAVED_TOTAL_RX + WGE_CURRENT_RX))
            WGE_TOTAL_TX=$((WGE_SAVED_TOTAL_TX + WGE_CURRENT_TX))
            
            # Save state
            cat > "$WGE_DATA_FILE" <<WGEDATAEOF
WGE_LAST_RX=$WGE_CURRENT_RX
WGE_LAST_TX=$WGE_CURRENT_TX
WGE_SAVED_TOTAL_RX=$WGE_SAVED_TOTAL_RX
WGE_SAVED_TOTAL_TX=$WGE_SAVED_TOTAL_TX
WGEDATAEOF
            
            for hs in $(echo "$WG_PEER_DATA" | grep "latest handshake:" | sed 's/.*latest handshake: //' | sed 's/ seconds.*//' | grep -E '^[0-9]+' 2>/dev/null || echo ""); do
                if [ -n "$hs" ] && [ "$hs" -lt 180 ] 2>/dev/null; then
                    CONNECTED_COUNT=$((CONNECTED_COUNT + 1))
                fi
            done
            WGE_CONNECTED="$CONNECTED_COUNT"
        fi
    fi
    
    ACTIVE_NAME=$(sanitize_json_string "$ACTIVE_NAME")
    ENDPOINT=$(sanitize_json_string "$ENDPOINT")
    PUBLIC_IP=$(sanitize_json_string "$PUBLIC_IP")
    HANDSHAKE_AGO=$(sanitize_json_string "$HANDSHAKE_AGO")
    WGE_HOST=$(sanitize_json_string "$WGE_HOST")
    
    printf '{"gluetun":{"status":"%s","healthy":%s,"active_profile":"%s","endpoint":"%s","public_ip":"%s","handshake_ago":"%s","session_rx":"%s","session_tx":"%s","total_rx":"%s","total_tx":"%s"},"wgeasy":{"status":"%s","host":"%s","clients":"%s","connected":"%s","session_rx":"%s","session_tx":"%s","total_rx":"%s","total_tx":"%s"}}' \
        "$GLUETUN_STATUS" "$GLUETUN_HEALTHY" "$ACTIVE_NAME" "$ENDPOINT" "$PUBLIC_IP" "$HANDSHAKE_AGO" "$SESSION_RX" "$SESSION_TX" "$ALLTIME_RX" "$ALLTIME_TX" \
        "$WGE_STATUS" "$WGE_HOST" "$WGE_CLIENTS" "$WGE_CONNECTED" "$WGE_SESSION_RX" "$WGE_SESSION_TX" "$WGE_TOTAL_RX" "$WGE_TOTAL_TX"
fi
EOF
chmod +x "$WG_CONTROL_SCRIPT"

cat > "$WG_API_SCRIPT" <<'APIEOF'
#!/usr/bin/env python3
import http.server
import socketserver
import json
import os
import re
import subprocess
import time

PORT = 55555
PROFILES_DIR = "/profiles"
CONTROL_SCRIPT = "/usr/local/bin/wg-control.sh"
LOG_FILE = "/app/deployment.log"


def extract_profile_name(config):
    """Extract profile name from WireGuard config."""
    lines = config.split('\n')
    in_peer = False
    for line in lines:
        stripped = line.strip()
        if stripped.lower() == '[peer]':
            in_peer = True
            continue
        if in_peer and stripped.startswith('#'):
            name = stripped.lstrip('#').strip()
            if name:
                return name
        if in_peer and stripped.startswith('['):
            break
    for line in lines:
        stripped = line.strip()
        if stripped.startswith('#'):
            name = stripped.lstrip('#').strip()
            if name and '=' not in name:
                return name
    return None

class ThreadingHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True

class APIHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass  # Suppress default logging
    
    def _send_json(self, data, code=200):
        self.send_response(code)
        self.send_header('Content-type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode('utf-8'))

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

    def do_GET(self):
        if self.path == '/status':
            try:
                result = subprocess.run([CONTROL_SCRIPT, "status"], capture_output=True, text=True, timeout=30)
                output = result.stdout.strip()
                output = re.sub(r'[\x00-\x1f\x7f-\x9f]', '', output)
                json_start = output.find('{')
                json_end = output.rfind('}')
                if json_start != -1 and json_end != -1:
                    output = output[json_start:json_end+1]
                self._send_json(json.loads(output))
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path == '/containers':
            try:
                # Get container IDs for Portainer links
                result = subprocess.run(
                    ['docker', 'ps', '-a', '--format', '{{.Names}}\t{{.ID}}'],
                    capture_output=True, text=True, timeout=10
                )
                containers = {}
                for line in result.stdout.strip().split('\n'):
                    if '\t' in line:
                        name, cid = line.split('\t', 1)
                        containers[name] = cid
                self._send_json({"containers": containers})
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path == '/profiles':
            try:
                files = [f.replace('.conf', '') for f in os.listdir(PROFILES_DIR) if f.endswith('.conf')]
                self._send_json({"profiles": files})
            except:
                self._send_json({"error": "Failed to list profiles"}, 500)
        elif self.path == '/events':
            self.send_response(200)
            self.send_header('Content-type', 'text/event-stream')
            self.send_header('Cache-Control', 'no-cache')
            self.send_header('Connection', 'keep-alive')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.send_header('X-Accel-Buffering', 'no')
            self.end_headers()
            try:
                for _ in range(10):
                    if os.path.exists(LOG_FILE):
                        break
                    time.sleep(1)
                if not os.path.exists(LOG_FILE):
                    self.wfile.write(b"data: Log file initializing...\n\n")
                    self.wfile.flush()
                f = open(LOG_FILE, 'r')
                f.seek(0, 2)
                # Send initial keepalive
                self.wfile.write(b": keepalive\n\n")
                self.wfile.flush()
                keepalive_counter = 0
                while True:
                    line = f.readline()
                    if line:
                        self.wfile.write(f"data: {line.strip()}\n\n".encode('utf-8'))
                        self.wfile.flush()
                        keepalive_counter = 0
                    else:
                        time.sleep(1)
                        keepalive_counter += 1
                        # Send keepalive comment every 15 seconds to prevent timeout
                        if keepalive_counter >= 15:
                            self.wfile.write(b": keepalive\n\n")
                            self.wfile.flush()
                            keepalive_counter = 0
            except (BrokenPipeError, ConnectionResetError):
                pass
            except Exception:
                pass

    def do_POST(self):
        if self.path == '/upload':
            try:
                l = int(self.headers['Content-Length'])
                data = json.loads(self.rfile.read(l).decode('utf-8'))
                raw_name = data.get('name', '').strip()
                config = data.get('config')
                if not raw_name:
                    extracted = extract_profile_name(config)
                    raw_name = extracted if extracted else f"Imported_{int(time.time())}"
                safe = "".join([c for c in raw_name if c.isalnum() or c in ('-', '_', '#')])
                with open(os.path.join(PROFILES_DIR, f"{safe}.conf"), "w") as f:
                    f.write(config.replace('\r', ''))
                self._send_json({"success": True, "name": safe})
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path == '/activate':
            try:
                l = int(self.headers['Content-Length'])
                name = json.loads(self.rfile.read(l).decode('utf-8')).get('name')
                safe = "".join([c for c in name if c.isalnum() or c in ('-', '_', '#')])
                subprocess.run([CONTROL_SCRIPT, "activate", safe], check=True, timeout=60)
                self._send_json({"success": True})
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path == '/delete':
            try:
                l = int(self.headers['Content-Length'])
                name = json.loads(self.rfile.read(l).decode('utf-8')).get('name')
                safe = "".join([c for c in name if c.isalnum() or c in ('-', '_', '#')])
                subprocess.run([CONTROL_SCRIPT, "delete", safe], check=True, timeout=30)
                self._send_json({"success": True})
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path == '/odido-userid':
            try:
                l = int(self.headers['Content-Length'])
                data = json.loads(self.rfile.read(l).decode('utf-8'))
                oauth_token = data.get('oauth_token', '').strip()
                if not oauth_token:
                    self._send_json({"error": "oauth_token is required"}, 400)
                    return
                # Use curl to fetch the User ID from Odido API
                result = subprocess.run([
                    'curl', '-sL', '-o', '/dev/null', '-w', '%{url_effective}',
                    '-H', f'Authorization: Bearer {oauth_token}',
                    '-H', 'User-Agent: T-Mobile 5.3.28 (Android 10; 10)',
                    'https://capi.odido.nl/account/current'
                ], capture_output=True, text=True, timeout=30)
                redirect_url = result.stdout.strip()
                # Extract 12-character hex User ID from URL (case-insensitive)
                match = re.search(r'capi\.odido\.nl/([0-9a-fA-F]{12})', redirect_url, re.IGNORECASE)
                if match:
                    user_id = match.group(1)
                    self._send_json({"success": True, "user_id": user_id})
                else:
                    # Fallback: extract first path segment after capi.odido.nl/
                    match = re.search(r'capi\.odido\.nl/([^/]+)/', redirect_url, re.IGNORECASE)
                    if match and match.group(1).lower() != 'account':
                        user_id = match.group(1)
                        self._send_json({"success": True, "user_id": user_id})
                    else:
                        self._send_json({"error": "Could not extract User ID from Odido API response", "url": redirect_url}, 400)
            except Exception as e:
                self._send_json({"error": str(e)}, 500)

if __name__ == "__main__":
    print(f"Starting API server on port {PORT}...")
    if not os.path.exists(LOG_FILE):
        os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
        open(LOG_FILE, 'a').close()
    with ThreadingHTTPServer(("", PORT), APIHandler) as httpd:
        print(f"API server running on port {PORT}")
        httpd.serve_forever()
APIEOF
chmod +x "$WG_API_SCRIPT"

# --- 13. DOCKER COMPOSE CONFIGURATION ---
log_info "Writing docker-compose.yml..."
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
    image: python:3.11-alpine
    container_name: hub-api
    networks: [frontnet]
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock"
      - "$WG_PROFILES_DIR:/profiles"
      - "$ACTIVE_WG_CONF:/active-wg.conf"
      - "$ACTIVE_PROFILE_NAME_FILE:/app/.active_profile_name"
      - "$WG_CONTROL_SCRIPT:/usr/local/bin/wg-control.sh"
      - "$WG_API_SCRIPT:/app/server.py"
      - "$GLUETUN_ENV_FILE:/app/gluetun.env"
      - "$COMPOSE_FILE:/app/docker-compose.yml"
      - "$HISTORY_LOG:/app/deployment.log"
      - "$BASE_DIR/.data_usage:/app/.data_usage"
      - "$BASE_DIR/.wge_data_usage:/app/.wge_data_usage"
    entrypoint: ["/bin/sh", "-c", "apk add --no-cache docker-cli docker-compose && touch /app/.data_usage /app/.wge_data_usage && python /app/server.py"]
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '0.2', memory: 128M}

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
    networks: [frontnet]
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    command: >
      --schedule "0 0 3 * * *"
      --cleanup
      --disable-containers watchtower
      --notification-url "generic://hub-api:55555/watchtower?template=json&disabletls=yes"
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '0.2', memory: 128M}

  gluetun:
    image: qmcgaw/gluetun
    container_name: gluetun
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
    image: nginx:alpine
    container_name: dashboard
    networks: [frontnet]
    ports: ["$LAN_IP:$PORT_DASHBOARD_WEB:$PORT_DASHBOARD_WEB"]
    volumes:
      - "$DASHBOARD_FILE:/usr/share/nginx/html/index.html:ro"
      - "$NGINX_CONF:/etc/nginx/conf.d/default.conf:ro"
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
    environment:
      - WG_HOST=$PUBLIC_IP
      - PASSWORD_HASH=$WG_HASH_ESCAPED
      - WG_DEFAULT_DNS=$LAN_IP
      - WG_ALLOWED_IPS=10.0.0.0/8,172.16.0.0/12,192.168.0.0/16
      - WG_PERSISTENT_KEEPALIVE=0
      - WG_PORT=51820
      - WG_DEVICE=eth0
      - WG_POST_UP=iptables -t nat -I POSTROUTING 1 -s 10.8.0.0/24 -j MASQUERADE; iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT
      - WG_POST_DOWN=iptables -t nat -D POSTROUTING -s 10.8.0.0/24 -j MASQUERADE; iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT
    volumes: ["wg-config:/etc/wireguard"]
    cap_add: [NET_ADMIN, SYS_MODULE]
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '1.0', memory: 256M}

  redlib:
    build: {context: "$SRC_DIR/redlib"}
    container_name: redlib
    network_mode: "service:gluetun"
    environment: {REDLIB_DEFAULT_WIDE: "on", REDLIB_DEFAULT_USE_HLS: "on", REDLIB_DEFAULT_SHOW_NSFW: "on"}
    restart: unless-stopped
    depends_on: {gluetun: {condition: service_healthy}}
    deploy:
      resources:
        limits: {cpus: '0.5', memory: 256M}

  wikiless:
    build: {context: "$SRC_DIR/wikiless"}
    container_name: wikiless
    network_mode: "service:gluetun"
    environment: {DOMAIN: "$LAN_IP:$PORT_WIKILESS", NONSSL_PORT: "$PORT_INT_WIKILESS"}
    depends_on: {wikiless_redis: {condition: service_healthy}, gluetun: {condition: service_healthy}}
    restart: always
    deploy:
      resources:
        limits: {cpus: '0.5', memory: 256M}

  wikiless_redis:
    image: redis:8-alpine
    container_name: wikiless_redis
    network_mode: "service:gluetun"
    volumes: ["redis-data:/data"]
    healthcheck: {test: ["CMD", "redis-cli", "ping"], interval: 5s, timeout: 3s, retries: 5}
    restart: always
    deploy:
      resources:
        limits: {cpus: '0.3', memory: 128M}

  invidious:
    image: quay.io/invidious/invidious:latest
    container_name: invidious
    network_mode: "service:gluetun"
    environment:
      INVIDIOUS_CONFIG: |
        db:
          dbname: invidious
          user: kemal
          password: kemal
          host: 127.0.0.1
          port: 5432
        check_tables: true
        invidious_companion:
          - private_url: "http://127.0.0.1:8282/companion"
        invidious_companion_key: "$IV_COMPANION"
        hmac_key: "$IV_HMAC"
    healthcheck: {test: "wget -nv --tries=1 --spider http://127.0.0.1:3000/api/v1/stats || exit 1", interval: 30s, timeout: 5s, retries: 2}
    logging:
      options:
        max-size: "1G"
        max-file: "4"
    depends_on:
      invidious-db: {condition: service_healthy}
      gluetun: {condition: service_healthy}
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '1.5', memory: 1024M}

  invidious-db:
    image: docker.io/library/postgres:14
    container_name: invidious-db
    network_mode: "service:gluetun"
    environment: {POSTGRES_DB: invidious, POSTGRES_USER: kemal, POSTGRES_PASSWORD: kemal}
    volumes:
      - postgresdata:/var/lib/postgresql/data
      - $SRC_DIR/invidious/config/sql:/config/sql
      - $SRC_DIR/invidious/docker/init-invidious-db.sh:/docker-entrypoint-initdb.d/init-invidious-db.sh
    healthcheck: {test: ["CMD-SHELL", "pg_isready -U kemal -d invidious"], interval: 10s, timeout: 5s, retries: 5}
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '1.0', memory: 512M}

  companion:
    image: quay.io/invidious/invidious-companion:latest
    container_name: companion
    network_mode: "service:gluetun"
    environment:
      - SERVER_SECRET_KEY=$IV_COMPANION
    restart: unless-stopped
    logging:
      options:
        max-size: "1G"
        max-file: "4"
    cap_drop:
      - ALL
    read_only: true
    volumes:
      - companioncache:/var/tmp/youtubei.js:rw
    security_opt:
      - no-new-privileges:true
    depends_on: {gluetun: {condition: service_healthy}}

  libremdb:
    image: ghcr.io/zyachel/libremdb:latest
    container_name: libremdb
    network_mode: "service:gluetun"
    env_file: ["$ENV_DIR/libremdb.env"]
    environment: {PORT: "$PORT_INT_LIBREMDB"}
    depends_on: {gluetun: {condition: service_healthy}}
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '0.5', memory: 256M}

  rimgo:
    image: codeberg.org/rimgo/rimgo:latest
    pull_policy: if_not_present
    container_name: rimgo
    network_mode: "service:gluetun"
    environment: {IMGUR_CLIENT_ID: "546c25a59c58ad7", ADDRESS: "0.0.0.0", PORT: "$PORT_INT_RIMGO"}
    depends_on: {gluetun: {condition: service_healthy}}
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '0.5', memory: 256M}

  breezewiki:
    image: quay.io/pussthecatorg/breezewiki:latest
    container_name: breezewiki
    network_mode: "service:gluetun"
    environment:
      - bw_bind_host=0.0.0.0
      - bw_port=$PORT_INT_BREEZEWIKI
      - bw_canonical_origin=http://$LAN_IP:$PORT_BREEZEWIKI
      - bw_debug=false
      - bw_feature_search_suggestions=true
      - bw_strict_proxy=true
    depends_on: {gluetun: {condition: service_healthy}}
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '0.5', memory: 256M}

  anonymousoverflow:
    image: ghcr.io/httpjamesm/anonymousoverflow:release
    container_name: anonymousoverflow
    network_mode: "service:gluetun"
    env_file: ["$ENV_DIR/anonymousoverflow.env"]
    environment: {PORT: "$PORT_INT_ANONYMOUS"}
    depends_on: {gluetun: {condition: service_healthy}}
    restart: always
    deploy:
      resources:
        limits: {cpus: '0.5', memory: 256M}

  scribe:
    build: {context: "$SRC_DIR/scribe"}
    container_name: scribe
    network_mode: "service:gluetun"
    env_file: ["$ENV_DIR/scribe.env"]
    depends_on: {gluetun: {condition: service_healthy}}
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '0.5', memory: 256M}

  # VERT: Local file conversion service
  vertd:
    container_name: vertd
    image: ghcr.io/vert-sh/vertd:latest
    networks: [frontnet]
    ports: ["$LAN_IP:$PORT_VERTD:$PORT_INT_VERTD"]
    labels:
      - "casaos.skip=true"
    # Intel GPU support
    devices:
      - /dev/dri
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '2.0', memory: 1024M}

  vert:
    container_name: vert
    image: ghcr.io/vert-sh/vert:latest
    build:
      context: $SRC_DIR/vert
      args:
        PUB_HOSTNAME: $LAN_IP:$PORT_VERT
        PUB_PLAUSIBLE_URL: ""
        PUB_ENV: production
        PUB_DISABLE_ALL_EXTERNAL_REQUESTS: "true"
        PUB_DISABLE_FAILURE_BLOCKS: "true"
        PUB_VERTD_URL: http://vertd:$PORT_INT_VERTD
        PUB_DONATION_URL: ""
        PUB_STRIPE_KEY: ""
        PUB_DISABLE_DONATIONS: "true"
    environment:
      - PUB_HOSTNAME=$LAN_IP:$PORT_VERT
      - PUB_PLAUSIBLE_URL=
      - PUB_ENV=production
      - PUB_DISABLE_ALL_EXTERNAL_REQUESTS=true
      - PUB_DISABLE_FAILURE_BLOCKS=true
      - PUB_VERTD_URL=http://vertd:$PORT_INT_VERTD
      - PUB_DONATION_URL=
      - PUB_STRIPE_KEY=
      - PUB_DISABLE_DONATIONS=true
    networks: [frontnet]
    ports: ["$LAN_IP:$PORT_VERT:$PORT_INT_VERT"]
    labels:
      - "casaos.skip=true"
    depends_on:
      vertd: {condition: service_started}
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '0.5', memory: 256M}

x-casaos:
  architectures:
    - amd64
  main: dashboard
  author: Lyceris-chan
  category: Network
  scheme: http
  hostname: $LAN_IP
  index: /
  port_map: "8081"
  title:
    en_us: Privacy Hub
  tagline:
    en_us: Self-hosted privacy stack with VPN, DNS filtering, and privacy frontends
  description:
    en_us: |
      A comprehensive self-hosted privacy stack with WireGuard VPN access, 
      AdGuard Home DNS filtering, and various privacy-respecting frontend services
      including Invidious, Redlib, Wikiless, and more.
  icon: https://raw.githubusercontent.com/AdrienPoupa/docker-compose-nas/master/images/adguard.png
EOF

# --- 14. DASHBOARD GENERATION ---
echo "[+] Generating Dashboard..."
cat > "$DASHBOARD_FILE" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ZimaOS Privacy Hub</title>
    <!-- Google Sans Flex from cdn.fontlay.com, Cascadia Code from Google Fonts -->
    <link href="https://cdn.fontlay.com/google-sans-flex/css/google-sans-flex.css" rel="stylesheet">
    <link href="https://fonts.googleapis.com/css2?family=Cascadia+Code:wght@400;500;600&display=swap" rel="stylesheet">
    <link href="https://fonts.googleapis.com/icon?family=Material+Symbols+Rounded" rel="stylesheet">
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
            --md-sys-color-surface-container: #1D1B20;
            --md-sys-color-surface-container-high: #2B2930;
            --md-sys-color-surface-container-highest: #36343B;
            --md-sys-color-surface-bright: #3B383E;
            /* Outline */
            --md-sys-color-outline: #938F99;
            --md-sys-color-outline-variant: #49454F;
            /* Custom success */
            --md-sys-color-success: #A8DAB5;
            --md-sys-color-on-success: #003912;
            --md-sys-color-success-container: #00522B;
            /* Custom warning */
            --md-sys-color-warning: #FFCC80;
            --md-sys-color-on-warning: #4A2800;
            /* Expressive shape */
            --md-sys-shape-corner-extra-large: 28px;
            --md-sys-shape-corner-large: 16px;
            --md-sys-shape-corner-medium: 12px;
            --md-sys-shape-corner-small: 8px;
            --md-sys-shape-corner-full: 100px;
            /* State layers */
            --md-sys-state-hover-opacity: 0.08;
            --md-sys-state-focus-opacity: 0.12;
            --md-sys-state-pressed-opacity: 0.12;
            /* Elevation */
            --md-sys-elevation-1: 0 1px 2px rgba(0,0,0,0.3), 0 1px 3px 1px rgba(0,0,0,0.15);
            --md-sys-elevation-2: 0 1px 2px rgba(0,0,0,0.3), 0 2px 6px 2px rgba(0,0,0,0.15);
            --md-sys-elevation-3: 0 4px 8px 3px rgba(0,0,0,0.15), 0 1px 3px rgba(0,0,0,0.3);
            /* Motion */
            --md-sys-motion-easing-emphasized: cubic-bezier(0.2, 0.0, 0, 1.0);
            --md-sys-motion-duration-medium: 300ms;
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
        
        .container { max-width: 1280px; width: 100%; }
        
        /* MD3 Typography Scale */
        .display-large { font-size: 57px; line-height: 64px; font-weight: 400; letter-spacing: -0.25px; }
        .display-medium { font-size: 45px; line-height: 52px; font-weight: 400; letter-spacing: 0; }
        .headline-large { font-size: 32px; line-height: 40px; font-weight: 400; letter-spacing: 0; }
        .headline-medium { font-size: 28px; line-height: 36px; font-weight: 400; letter-spacing: 0; }
        .title-large { font-size: 22px; line-height: 28px; font-weight: 400; letter-spacing: 0; }
        .title-medium { font-size: 16px; line-height: 24px; font-weight: 500; letter-spacing: 0.15px; }
        .title-small { font-size: 14px; line-height: 20px; font-weight: 500; letter-spacing: 0.1px; }
        .body-large { font-size: 16px; line-height: 24px; font-weight: 400; letter-spacing: 0.5px; }
        .body-medium { font-size: 14px; line-height: 20px; font-weight: 400; letter-spacing: 0.25px; }
        .body-small { font-size: 12px; line-height: 16px; font-weight: 400; letter-spacing: 0.4px; }
        .label-large { font-size: 14px; line-height: 20px; font-weight: 500; letter-spacing: 0.1px; }
        .label-medium { font-size: 12px; line-height: 16px; font-weight: 500; letter-spacing: 0.5px; }
        .label-small { font-size: 11px; line-height: 16px; font-weight: 500; letter-spacing: 0.5px; }
        
        /* Header */
        header {
            margin-bottom: 32px;
            padding: 16px 0;
        }
        
        h1 {
            font-family: 'Google Sans Flex', 'Google Sans', sans-serif;
            font-weight: 400;
            font-size: 45px;
            line-height: 52px;
            margin: 0;
            color: var(--md-sys-color-primary);
            letter-spacing: 0;
        }
        
        .subtitle {
            font-size: 16px;
            color: var(--md-sys-color-on-surface-variant);
            margin-top: 8px;
            font-weight: 400;
            letter-spacing: 0.5px;
        }
        
        /* Section Labels - MD3 Overline style */
        .section-label {
            color: var(--md-sys-color-primary);
            font-size: 11px;
            font-weight: 500;
            letter-spacing: 1px;
            text-transform: uppercase;
            margin: 48px 0 16px 4px;
        }
        
        .section-label:first-of-type {
            margin-top: 24px;
        }
        
        .section-hint {
            font-size: 12px;
            color: var(--md-sys-color-on-surface-variant);
            margin: -8px 0 16px 4px;
            letter-spacing: 0.4px;
        }
        
        /* Grid Layouts - MD3 spacing (16dp gap) */
        .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 16px; margin-bottom: 24px; }
        .grid-2 { display: grid; grid-template-columns: repeat(2, 1fr); gap: 16px; margin-bottom: 24px; }
        .grid-3 { display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px; margin-bottom: 24px; }
        @media (max-width: 1100px) { .grid-3 { grid-template-columns: repeat(2, 1fr); } }
        @media (max-width: 900px) { .grid-2, .grid-3 { grid-template-columns: 1fr; } }
        @media (max-width: 600px) { body { padding: 16px; } }
        
        /* MD3 Cards with tonal elevation */
        .card {
            background: var(--md-sys-color-surface-container);
            border-radius: var(--md-sys-shape-corner-extra-large);
            padding: 24px;
            text-decoration: none;
            color: inherit;
            transition: all var(--md-sys-motion-duration-medium) var(--md-sys-motion-easing-emphasized);
            position: relative;
            display: flex;
            flex-direction: column;
            min-height: 140px;
            border: none;
            overflow: hidden;
            box-sizing: border-box;
        }
        
        .card::before {
            content: '';
            position: absolute;
            inset: 0;
            background: var(--md-sys-color-on-surface);
            opacity: 0;
            transition: opacity var(--md-sys-motion-duration-medium) var(--md-sys-motion-easing-emphasized);
            pointer-events: none;
        }
        
        .card:hover::before { opacity: var(--md-sys-state-hover-opacity); }
        .card:hover { 
            background: var(--md-sys-color-surface-container-high);
            box-shadow: var(--md-sys-elevation-2);
        }
        
        .card:active::before { opacity: var(--md-sys-state-pressed-opacity); }
        .card.full-width { grid-column: 1 / -1; }
        
        .card h2 {
            margin: 0 0 8px 0;
            font-size: 22px;
            font-weight: 500;
            color: var(--md-sys-color-on-surface);
            line-height: 28px;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }
        
        .card h3 {
            margin: 0 0 16px 0;
            font-size: 16px;
            font-weight: 500;
            color: var(--md-sys-color-on-surface);
            line-height: 24px;
            letter-spacing: 0.15px;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }
        
        /* MD3 Assist Chips */
        .chip-box { display: flex; gap: 8px; flex-wrap: wrap; margin-top: auto; padding-top: 12px; }
        
        .chip {
            display: inline-flex;
            align-items: center;
            gap: 6px;
            font-size: 12px;
            padding: 6px 16px;
            border-radius: var(--md-sys-shape-corner-small);
            font-weight: 500;
            letter-spacing: 0.5px;
            text-decoration: none;
            transition: all var(--md-sys-motion-duration-medium) var(--md-sys-motion-easing-emphasized);
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
            transition: opacity var(--md-sys-motion-duration-medium);
        }
        
        .chip:hover::before { opacity: var(--md-sys-state-hover-opacity); }
        
        .chip.vpn {
            background: var(--md-sys-color-primary-container);
            color: var(--md-sys-color-on-primary-container);
            border: none;
        }
        
        .chip.admin {
            background: var(--md-sys-color-secondary-container);
            color: var(--md-sys-color-on-secondary-container);
            border: none;
        }
        
        .chip.tertiary {
            background: var(--md-sys-color-tertiary-container);
            color: var(--md-sys-color-on-tertiary-container);
            border: none;
        }
        
        a.chip { cursor: pointer; }
        
        /* Status Indicator */
        .status-indicator {
            display: inline-flex;
            align-items: center;
            gap: 8px;
            background: var(--md-sys-color-surface-container-highest);
            padding: 8px 16px;
            border-radius: var(--md-sys-shape-corner-full);
            font-size: 13px;
            color: var(--md-sys-color-on-surface-variant);
            margin-top: 16px;
            width: fit-content;
        }
        
        .status-dot {
            width: 8px;
            height: 8px;
            border-radius: 50%;
            background: var(--md-sys-color-outline);
            transition: all var(--md-sys-motion-duration-medium) var(--md-sys-motion-easing-emphasized);
        }
        
        .status-dot.up {
            background: var(--md-sys-color-success);
            box-shadow: 0 0 12px var(--md-sys-color-success);
        }
        
        .status-dot.down {
            background: var(--md-sys-color-error);
            box-shadow: 0 0 12px var(--md-sys-color-error);
        }
        
        /* MD3 Text Fields */
        .text-field {
            width: 100%;
            background: transparent;
            border: 1px solid var(--md-sys-color-outline);
            color: var(--md-sys-color-on-surface);
            padding: 16px;
            border-radius: var(--md-sys-shape-corner-small);
            font-family: 'Cascadia Code', 'Consolas', monospace;
            font-size: 14px;
            box-sizing: border-box;
            outline: none;
            transition: all var(--md-sys-motion-duration-medium) var(--md-sys-motion-easing-emphasized);
        }
        
        .text-field:hover { border-color: var(--md-sys-color-on-surface); }
        .text-field:focus {
            border-color: var(--md-sys-color-primary);
            border-width: 2px;
            padding: 15px;
        }
        
        textarea.text-field { min-height: 120px; resize: vertical; }
        
        /* MD3 Expressive Buttons */
        .btn {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            gap: 8px;
            padding: 0 24px;
            height: 40px;
            min-width: 64px;
            border-radius: 20px;
            font-size: 14px;
            font-weight: 500;
            letter-spacing: 0.1px;
            line-height: 20px;
            cursor: pointer;
            transition: all 200ms cubic-bezier(0.2, 0, 0, 1);
            border: none;
            position: relative;
            overflow: hidden;
            text-decoration: none;
            font-family: inherit;
            white-space: nowrap;
        }
        
        .btn::before {
            content: '';
            position: absolute;
            inset: 0;
            background: currentColor;
            opacity: 0;
            transition: opacity 150ms ease;
            pointer-events: none;
        }
        
        .btn:hover::before { opacity: 0.08; }
        .btn:focus-visible::before { opacity: 0.12; }
        .btn:active::before { opacity: 0.12; }
        
        .btn-filled {
            background: var(--md-sys-color-primary);
            color: var(--md-sys-color-on-primary);
            box-shadow: var(--md-sys-elevation-1);
        }
        
        .btn-filled:hover { 
            box-shadow: var(--md-sys-elevation-2);
        }
        
        .btn-filled:active {
            box-shadow: var(--md-sys-elevation-1);
        }
        
        .btn-tonal {
            background: var(--md-sys-color-secondary-container);
            color: var(--md-sys-color-on-secondary-container);
        }
        
        .btn-tonal:hover {
            box-shadow: var(--md-sys-elevation-1);
        }
        
        .btn-outlined {
            background: transparent;
            color: var(--md-sys-color-primary);
            border: 1px solid var(--md-sys-color-outline);
        }
        
        .btn-outlined:hover {
            background: rgba(208, 188, 255, 0.08);
        }
        
        .btn-text {
            background: transparent;
            color: var(--md-sys-color-primary);
            padding: 0 12px;
            min-width: 48px;
        }
        
        .btn-text:hover {
            background: rgba(208, 188, 255, 0.08);
        }
        
        .btn-tertiary {
            background: var(--md-sys-color-tertiary-container);
            color: var(--md-sys-color-on-tertiary-container);
        }
        
        .btn-tertiary:hover {
            box-shadow: var(--md-sys-elevation-1);
        }
        
        .btn:disabled {
            background: rgba(230, 225, 229, 0.12);
            color: rgba(230, 225, 229, 0.38);
            box-shadow: none;
            cursor: not-allowed;
            pointer-events: none;
        }
        
        .btn:disabled::before { display: none; }
        
        .btn-icon {
            background: transparent;
            border: 1px solid var(--md-sys-color-outline-variant);
            padding: 0;
            width: 40px;
            height: 40px;
            min-width: 40px;
            border-radius: 20px;
            color: var(--md-sys-color-on-surface-variant);
        }
        
        .btn-icon:hover { 
            background: rgba(202, 196, 208, 0.08);
            border-color: var(--md-sys-color-outline);
        }
        
        .btn-icon svg { width: 24px; height: 24px; fill: currentColor; }
        
        /* Profile List Items */
        .list-item {
            display: flex;
            justify-content: space-between;
            align-items: center;
            background: var(--md-sys-color-surface-container-high);
            padding: 16px 20px;
            border-radius: var(--md-sys-shape-corner-large);
            margin-bottom: 8px;
            transition: all var(--md-sys-motion-duration-medium) var(--md-sys-motion-easing-emphasized);
            position: relative;
            overflow: hidden;
        }
        
        .list-item::before {
            content: '';
            position: absolute;
            inset: 0;
            background: var(--md-sys-color-on-surface);
            opacity: 0;
            transition: opacity var(--md-sys-motion-duration-medium);
        }
        
        .list-item:hover::before { opacity: var(--md-sys-state-hover-opacity); }
        
        .list-item-text {
            font-weight: 500;
            color: var(--md-sys-color-on-surface);
            cursor: pointer;
            flex-grow: 1;
            position: relative;
            z-index: 1;
        }
        
        .list-item-text:hover { color: var(--md-sys-color-primary); }
        
        /* Stats Display */
        .stat-row {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 12px 0;
            border-bottom: 1px solid var(--md-sys-color-outline-variant);
            font-size: 14px;
        }
        
        .stat-row:last-child { border: none; }
        
        .stat-label { color: var(--md-sys-color-on-surface-variant); }
        
        .stat-value {
            font-family: 'Cascadia Code', 'Consolas', monospace;
            color: var(--md-sys-color-primary);
            font-weight: 500;
        }
        
        .stat-value.success { color: var(--md-sys-color-success); }
        .stat-value.error { color: var(--md-sys-color-error); }
        .stat-value.warning { color: var(--md-sys-color-warning); }
        
        /* Log Container */
        .log-container {
            background: #0D0D0D;
            border: 1px solid var(--md-sys-color-outline-variant);
            border-radius: var(--md-sys-shape-corner-large);
            padding: 16px;
            height: 320px;
            overflow-y: auto;
            font-family: 'Cascadia Code', 'Consolas', monospace;
            font-size: 13px;
            color: var(--md-sys-color-on-surface-variant);
        }
        
        .log-entry {
            padding: 4px 0;
            border-bottom: 1px solid rgba(255,255,255,0.05);
        }
        
        /* Code Display */
        .code-label {
            font-size: 11px;
            color: var(--md-sys-color-on-surface-variant);
            text-transform: uppercase;
            letter-spacing: 0.5px;
            margin-bottom: 4px;
            font-weight: 500;
        }
        
        .code-block {
            background: #0D0D0D;
            border: 1px solid var(--md-sys-color-outline-variant);
            border-radius: var(--md-sys-shape-corner-small);
            padding: 14px 16px;
            font-family: 'Cascadia Code', 'Consolas', monospace;
            font-size: 13px;
            color: var(--md-sys-color-primary);
            margin: 8px 0;
            overflow-x: auto;
            white-space: nowrap;
        }
        
        /* Progress Bar */
        .progress-track {
            background: var(--md-sys-color-surface-container-highest);
            border-radius: var(--md-sys-shape-corner-full);
            height: 8px;
            margin: 16px 0;
            overflow: hidden;
        }
        
        .progress-indicator {
            background: linear-gradient(90deg, var(--md-sys-color-success), #4CAF50);
            height: 100%;
            border-radius: var(--md-sys-shape-corner-full);
            transition: width var(--md-sys-motion-duration-medium) var(--md-sys-motion-easing-emphasized);
        }
        
        .progress-indicator.low {
            background: linear-gradient(90deg, var(--md-sys-color-warning), #FF9800);
        }
        
        .progress-indicator.critical {
            background: linear-gradient(90deg, var(--md-sys-color-error), #F44336);
        }
        
        /* Privacy Toggle - MD3 Switch (strict implementation) */
        .switch-container {
            display: flex;
            align-items: center;
            gap: 12px;
            background: transparent;
            padding: 8px 0;
            margin-left: auto;
        }

        .switch-label {
            font-size: 14px;
            font-weight: 600;
            letter-spacing: 0.1px;
            color: var(--md-sys-color-on-surface);
            cursor: pointer;
            user-select: none;
        }

        .switch-track {
            position: relative;
            width: 52px;
            height: 32px;
            background: color-mix(in srgb, var(--md-sys-color-on-surface) 12%, transparent);
            border: 2px solid var(--md-sys-color-outline);
            border-radius: 999px;
            cursor: pointer;
            transition: background var(--md-sys-motion-duration-medium) var(--md-sys-motion-easing-emphasized),
                        border-color var(--md-sys-motion-duration-medium) var(--md-sys-motion-easing-emphasized);
        }

        .switch-track::after {
            content: '';
            position: absolute;
            top: 50%;
            left: 6px;
            transform: translateY(-50%);
            width: 18px;
            height: 18px;
            background: var(--md-sys-color-surface);
            border-radius: 50%;
            transition: all var(--md-sys-motion-duration-medium) var(--md-sys-motion-easing-emphasized);
            box-shadow: 0 1px 3px rgba(0,0,0,0.3);
        }

        .switch-track:hover {
            border-color: var(--md-sys-color-on-surface);
        }

        .switch-track:hover::after {
            background: var(--md-sys-color-surface-container-highest);
        }

        .switch-track.active {
            background: var(--md-sys-color-primary);
            border-color: var(--md-sys-color-primary);
        }

        .switch-track.active::after {
            left: calc(100% - 26px);
            width: 22px;
            height: 22px;
            background: var(--md-sys-color-on-primary);
            box-shadow: 0 2px 6px rgba(0,0,0,0.35);
        }
        
        .sensitive { transition: filter var(--md-sys-motion-duration-medium), opacity var(--md-sys-motion-duration-medium); }
        .privacy-mode .sensitive { filter: blur(10px); opacity: 0.5; user-select: none; }
        
        .header-row { display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 16px; }
        
        /* Button Group with proper spacing */
        .btn-group { display: flex; gap: 12px; margin-top: 20px; flex-wrap: wrap; }
        
        /* Card content spacing */
        .card > .btn, .card > div > .btn { margin-top: 16px; }
        .card > .text-field:last-of-type { margin-bottom: 16px; }
        .card > div[style*="text-align:right"] { margin-top: 16px; }
        
        /* Status feedback */
        .feedback { margin-top: 12px; font-size: 13px; text-align: center; }
        .feedback.success { color: var(--md-sys-color-success); }
        .feedback.error { color: var(--md-sys-color-error); }
        .feedback.info { color: var(--md-sys-color-primary); }

        .profile-card { display: flex; flex-direction: column; gap: 12px; }
        .profile-card #profile-list { flex: 1; }
        .profile-hint { color: var(--md-sys-color-on-surface-variant); margin-top: auto; }
        
        /* Material Icons */
        .material-symbols-rounded { font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24; vertical-align: middle; }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <div class="header-row">
                <div>
                    <h1>Privacy Hub</h1>
                    <div class="subtitle">Secure Self-Hosted Gateway</div>
                </div>
                <div class="switch-container">
                    <span class="switch-label" onclick="togglePrivacy()">Hide Sensitive</span>
                    <div class="switch-track" id="privacy-switch" onclick="togglePrivacy()" title="Blur sensitive information"></div>
                </div>
            </div>
        </header>

        <div class="section-label">Privacy Services</div>
        <div class="section-hint">🔒 VPN Routed &nbsp;•&nbsp; 📍 Direct &nbsp;•&nbsp; Click chip to manage in Portainer</div>
        <div class="grid-3">
            <a href="http://$LAN_IP:$PORT_INVIDIOUS" class="card" data-check="true" data-container="invidious"><h2>Invidious</h2><div class="chip-box"><span class="chip vpn portainer-link" data-container="invidious">🔒 VPN</span></div><div class="status-indicator"><span class="status-dot"></span><span class="status-text">Checking...</span></div></a>
            <a href="http://$LAN_IP:$PORT_REDLIB" class="card" data-check="true" data-container="redlib"><h2>Redlib</h2><div class="chip-box"><span class="chip vpn portainer-link" data-container="redlib">🔒 VPN</span></div><div class="status-indicator"><span class="status-dot"></span><span class="status-text">Checking...</span></div></a>
            <a href="http://$LAN_IP:$PORT_WIKILESS" class="card" data-check="true" data-container="wikiless"><h2>Wikiless</h2><div class="chip-box"><span class="chip vpn portainer-link" data-container="wikiless">🔒 VPN</span></div><div class="status-indicator"><span class="status-dot"></span><span class="status-text">Checking...</span></div></a>
            <a href="http://$LAN_IP:$PORT_LIBREMDB" class="card" data-check="true" data-container="libremdb"><h2>LibremDB</h2><div class="chip-box"><span class="chip vpn portainer-link" data-container="libremdb">🔒 VPN</span></div><div class="status-indicator"><span class="status-dot"></span><span class="status-text">Checking...</span></div></a>
            <a href="http://$LAN_IP:$PORT_RIMGO" class="card" data-check="true" data-container="rimgo"><h2>Rimgo</h2><div class="chip-box"><span class="chip vpn portainer-link" data-container="rimgo">🔒 VPN</span></div><div class="status-indicator"><span class="status-dot"></span><span class="status-text">Checking...</span></div></a>
            <a href="http://$LAN_IP:$PORT_SCRIBE" class="card" data-check="true" data-container="scribe"><h2>Scribe</h2><div class="chip-box"><span class="chip vpn portainer-link" data-container="scribe">🔒 VPN</span></div><div class="status-indicator"><span class="status-dot"></span><span class="status-text">Checking...</span></div></a>
            <a href="http://$LAN_IP:$PORT_BREEZEWIKI" class="card" data-check="true" data-container="breezewiki"><h2>BreezeWiki</h2><div class="chip-box"><span class="chip vpn portainer-link" data-container="breezewiki">🔒 VPN</span></div><div class="status-indicator"><span class="status-dot"></span><span class="status-text">Checking...</span></div></a>
            <a href="http://$LAN_IP:$PORT_ANONYMOUS" class="card" data-check="true" data-container="anonymousoverflow"><h2>AnonOverflow</h2><div class="chip-box"><span class="chip vpn portainer-link" data-container="anonymousoverflow">🔒 VPN</span></div><div class="status-indicator"><span class="status-dot"></span><span class="status-text">Checking...</span></div></a>
            <a href="http://$LAN_IP:$PORT_VERT" class="card" data-check="true" data-container="vert"><h2>VERT</h2><div class="chip-box"><span class="chip admin portainer-link" data-container="vert">📍 Direct</span></div><div class="status-indicator"><span class="status-dot"></span><span class="status-text">Checking...</span></div></a>
        </div>

        <div class="section-label">Administration</div>
        <div class="section-hint">Accessible via LAN or WG-Easy remote connection</div>
        <div class="grid-3">
            <a href="http://$LAN_IP:$PORT_ADGUARD_WEB" class="card" data-container="adguard"><h2>AdGuard Home</h2><div class="chip-box"><span class="chip admin portainer-link" data-container="adguard">📍 Direct</span></div></a>
            <a href="http://$LAN_IP:$PORT_PORTAINER" class="card" data-container="portainer"><h2>Portainer</h2><div class="chip-box"><span class="chip admin portainer-link" data-container="portainer">📍 Direct</span></div></a>
            <a href="http://$LAN_IP:$PORT_WG_WEB" class="card" data-container="wg-easy"><h2>WireGuard</h2><div class="chip-box"><span class="chip admin portainer-link" data-container="wg-easy">📍 Direct</span></div></a>
        </div>

        <div class="section-label">DNS Configuration</div>
        <div class="grid-2">
            <div class="card">
                <h3>Device DNS Settings</h3>
                <p class="body-medium" style="color:var(--md-sys-color-on-surface-variant); margin-bottom:16px;">Configure your devices to use this DNS server:</p>
                <div class="code-label">Plain DNS</div>
                <div class="code-block sensitive">$LAN_IP:53</div>
EOF
if [ -n "$DESEC_DOMAIN" ]; then
    cat >> "$DASHBOARD_FILE" <<EOF
                <div class="code-label">Domain</div>
                <div class="code-block sensitive">$DESEC_DOMAIN</div>
                <div class="code-label">DNS-over-HTTPS</div>
                <div class="code-block sensitive">https://$DESEC_DOMAIN/dns-query</div>
                <div class="code-label">DNS-over-TLS</div>
                <div class="code-block sensitive">$DESEC_DOMAIN:853</div>
                <div class="code-label">DNS-over-QUIC</div>
                <div class="code-block sensitive">quic://$DESEC_DOMAIN</div>
            </div>
            <div class="card">
                <h3>Mobile Device Setup</h3>
                <p class="body-medium" style="color:var(--md-sys-color-on-surface-variant); margin-bottom:12px;">To use encrypted DNS on your devices:</p>
                <ol style="margin:0; padding-left:20px; font-size:14px; color:var(--md-sys-color-on-surface); line-height:1.8;">
                    <li>Connect to WireGuard VPN first</li>
                    <li>Set Private DNS to:</li>
                </ol>
                <div class="code-block sensitive" style="margin-left:20px;">$DESEC_DOMAIN</div>
                <p class="body-small" style="color:var(--md-sys-color-success); margin-top:12px;">✓ Valid Let's Encrypt certificate (no warnings)</p>
            </div>
EOF
else
    cat >> "$DASHBOARD_FILE" <<EOF
                <div class="code-label">DNS-over-HTTPS</div>
                <div class="code-block sensitive">https://$LAN_IP/dns-query</div>
                <div class="code-label">DNS-over-TLS</div>
                <div class="code-block sensitive">$LAN_IP:853</div>
            </div>
            <div class="card">
                <h3>Mobile Device Setup</h3>
                <p style="font-size:0.85rem; color:var(--s); margin-bottom:12px;">To use DNS on your devices:</p>
                <ol style="margin:0; padding-left:20px; font-size:0.9rem; color:var(--on-surf); line-height:1.8;">
                    <li>Connect to WireGuard VPN first</li>
                    <li>Set DNS server to:</li>
                </ol>
                <div class="code-block sensitive" style="margin-left:20px;">$LAN_IP</div>
                <p style="font-size:0.8rem; color:var(--err); margin-top:12px;">⚠ Self-signed certificate (expect browser warnings)</p>
                <p style="font-size:0.75rem; color:#888; margin-top:8px;">Tip: Set up deSEC for a free domain with valid SSL</p>
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
                    <div id="odido-configured" style="display:none;">
                        <div class="stat-row"><span class="stat-label">Data Remaining</span><span class="stat-value" id="odido-remaining">--</span></div>
                        <div class="stat-row"><span class="stat-label">Bundle Code</span><span class="stat-value" id="odido-bundle-code">--</span></div>
                        <div class="stat-row"><span class="stat-label">Auto-Renew</span><span class="stat-value" id="odido-auto-renew">--</span></div>
                        <div class="stat-row"><span class="stat-label">Threshold</span><span class="stat-value" id="odido-threshold">--</span></div>
                        <div class="stat-row"><span class="stat-label">Consumption Rate</span><span class="stat-value" id="odido-rate">--</span></div>
                        <div class="stat-row"><span class="stat-label">API Connected</span><span class="stat-value" id="odido-api-status">--</span></div>
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
        const ODIDO_API = "http://$LAN_IP:8085/api";
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
                const res = await fetch(\`\${API}/containers\`);
                const data = await res.json();
                containerIds = data.containers || {};
                // Update all portainer links
                document.querySelectorAll('.portainer-link').forEach(el => {
                    const containerName = el.dataset.container;
                    if (containerIds[containerName]) {
                        el.onclick = (e) => {
                            e.preventDefault();
                            e.stopPropagation();
                            window.open(\`\${PORTAINER_URL}/#!/1/docker/containers/\${containerIds[containerName]}\`, '_blank');
                        };
                        el.style.cursor = 'pointer';
                        el.title = \`Manage \${containerName} in Portainer\`;
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
            try {
                const res = await fetch(\`\${API}/status\`);
                const data = await res.json();
                const g = data.gluetun;
                const vpnStatus = document.getElementById('vpn-status');
                if (g.status === "up" && g.healthy) {
                    vpnStatus.textContent = "Connected (Healthy)";
                    vpnStatus.className = "stat-value success";
                } else if (g.status === "up") {
                    vpnStatus.textContent = "Connected";
                    vpnStatus.className = "stat-value success";
                } else {
                    vpnStatus.textContent = "Disconnected";
                    vpnStatus.className = "stat-value error";
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
                    wgeStat.className = "stat-value success";
                } else {
                    wgeStat.textContent = "Stopped";
                    wgeStat.className = "stat-value error";
                }
                document.getElementById('wge-host').textContent = w.host || "--";
                document.getElementById('wge-clients').textContent = w.clients || "0";
                const wgeConnected = document.getElementById('wge-connected');
                const connectedCount = parseInt(w.connected) || 0;
                wgeConnected.textContent = connectedCount > 0 ? \`\${connectedCount} active\` : "None";
                wgeConnected.style.color = connectedCount > 0 ? "var(--md-sys-color-success)" : "var(--md-sys-color-on-surface-variant)";
                document.getElementById('wge-session-rx').textContent = formatBytes(w.session_rx || 0);
                document.getElementById('wge-session-tx').textContent = formatBytes(w.session_tx || 0);
                document.getElementById('wge-total-rx').textContent = formatBytes(w.total_rx || 0);
                document.getElementById('wge-total-tx').textContent = formatBytes(w.total_tx || 0);
            } catch(e) { console.error('Status fetch error:', e); }
        }
        
        async function fetchOdidoStatus() {
            try {
                const headers = odidoApiKey ? { 'X-API-Key': odidoApiKey } : {};
                const res = await fetch(\`\${ODIDO_API}/status\`, { headers });
                if (!res.ok) {
                    // Show configured panel but indicate API error
                    document.getElementById('odido-loading').style.display = 'none';
                    document.getElementById('odido-not-configured').style.display = 'none';
                    document.getElementById('odido-configured').style.display = 'block';
                    document.getElementById('odido-remaining').textContent = '--';
                    document.getElementById('odido-bundle-code').textContent = '--';
                    document.getElementById('odido-threshold').textContent = '--';
                    document.getElementById('odido-auto-renew').textContent = '--';
                    document.getElementById('odido-rate').textContent = '--';
                    const apiStatus = document.getElementById('odido-api-status');
                    apiStatus.textContent = \`Error: \${res.status}\`;
                    apiStatus.style.color = 'var(--err)';
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
                document.getElementById('odido-remaining').textContent = \`\${Math.round(remaining)} MB\`;
                document.getElementById('odido-bundle-code').textContent = bundleCode;
                document.getElementById('odido-threshold').textContent = \`\${threshold} MB\`;
                document.getElementById('odido-auto-renew').textContent = config.auto_renew_enabled ? 'Enabled' : 'Disabled';
                document.getElementById('odido-rate').textContent = \`\${rate.toFixed(3)} MB/min\`;
                const apiStatus = document.getElementById('odido-api-status');
                apiStatus.textContent = isConfigured ? 'Connected' : 'Not configured';
                apiStatus.style.color = isConfigured ? 'var(--md-sys-color-success)' : 'var(--md-sys-color-warning)';
                const maxData = config.bundle_size_mb || 1024;
                const percent = Math.min(100, (remaining / maxData) * 100);
                const bar = document.getElementById('odido-bar');
                bar.style.width = \`\${percent}%\`;
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
                    const res = await fetch(\`\${API}/odido-userid\`, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ oauth_token: oauthToken })
                    });
                    const result = await res.json();
                    if (result.error) throw new Error(result.error);
                    if (result.user_id) {
                        data.odido_user_id = result.user_id;
                        data.odido_token = oauthToken;
                        st.textContent = \`User ID fetched: \${result.user_id}\`;
                        st.style.color = 'var(--ok)';
                    } else {
                        throw new Error('Could not extract User ID from Odido API response');
                    }
                } catch(e) {
                    st.textContent = \`Failed to fetch User ID: \${e.message}\`;
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
                const res = await fetch(\`\${ODIDO_API}/config\`, {
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
                const res = await fetch(\`\${ODIDO_API}/odido/buy-bundle\`, {
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
                const res = await fetch(\`\${ODIDO_API}/odido/remaining\`, { headers });
                const result = await res.json();
                if (result.detail) throw new Error(result.detail);
                st.textContent = \`Live data: \${Math.round(result.remaining_mb || 0)} MB remaining\`;
                st.style.color = 'var(--ok)';
                setTimeout(fetchOdidoStatus, 1000);
            } catch(e) {
                st.textContent = e.message;
                st.style.color = 'var(--err)';
            }
        }
        
        async function fetchProfiles() {
            try {
                const res = await fetch(\`\${API}/profiles\`);
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
                    name.onclick = () => activateProfile(p);

                    const delBtn = document.createElement('button');
                    delBtn.className = 'btn btn-icon';
                    delBtn.title = 'Delete';
                    delBtn.innerHTML = '<svg viewBox="0 0 24 24"><path d="M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z"/></svg>';
                    delBtn.onclick = () => deleteProfile(p);

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
                const upRes = await fetch(\`\${API}/upload\`, { method:'POST', body:JSON.stringify({name: nameInput, config}) });
                const upData = await upRes.json();
                if(upData.error) throw new Error(upData.error);
                const finalName = upData.name;
                st.textContent = \`Activating \${finalName}...\`;
                await fetch(\`\${API}/activate\`, { method:'POST', body:JSON.stringify({name: finalName}) });
                st.textContent = "Success! VPN restarting.";
                fetchProfiles(); document.getElementById('prof-name').value=""; document.getElementById('prof-conf').value="";
            } catch(e) { st.textContent = e.message; }
        }
        
        async function activateProfile(name) {
            if(!confirm(\`Switch to \${name}?\`)) return;
            try { await fetch(\`\${API}/activate\`, { method:'POST', body:JSON.stringify({name}) }); alert("Profile switched. VPN restarting."); } catch(e) { alert("Error"); }
        }
        
        async function deleteProfile(name) {
            if(!confirm(\`Delete \${name}?\`)) return;
            try { await fetch(\`\${API}/delete\`, { method:'POST', body:JSON.stringify({name}) }); fetchProfiles(); } catch(e) { alert("Error"); }
        }
        
        function startLogStream() {
            const el = document.getElementById('log-container');
            const status = document.getElementById('log-status');
            const evtSource = new EventSource(\`\${API}/events\`);
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
        
        function formatBytes(a,b=2){if(!+a)return"0 B";const c=0>b?0:b,d=Math.floor(Math.log(a)/Math.log(1024));return\`\${parseFloat((a/Math.pow(1024,d)).toFixed(c))} \${["B","KiB","MiB","GiB","TiB"][d]}\`}
        
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
                document.getElementById('privacy-switch').classList.add('active');
                document.body.classList.add('privacy-mode');
            }
            updateProfileDisplay();
        }
        
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
            fetchStatus(); fetchProfiles(); fetchOdidoStatus(); startLogStream();
            setInterval(fetchStatus, 5000);
            setInterval(fetchOdidoStatus, 60000);  // Reduced polling frequency to respect Odido API
            setInterval(fetchContainerIds, 60000);
            document.querySelectorAll('.card[data-check="true"]').forEach(c => {
                const url = c.href; const dot = c.querySelector('.status-dot'); const txt = c.querySelector('.status-text');
                fetch(url, { mode: 'no-cors', cache: 'no-store' })
                    .then(() => { dot.classList.add('up'); dot.classList.remove('down'); txt.textContent = "Online"; })
                    .catch(() => { dot.classList.add('down'); dot.classList.remove('up'); txt.textContent = "Offline"; });
            });
        });
    </script>
</body>
</html>
EOF

# --- 15. IP MONITORING ---
echo "[+] Generating IP Monitor Script..."

if [ -n "$DESEC_DOMAIN" ] && [ -n "$DESEC_TOKEN" ]; then
    DESEC_MONITOR_DOMAIN="$DESEC_DOMAIN"
    DESEC_MONITOR_TOKEN="$DESEC_TOKEN"
else
    DESEC_MONITOR_DOMAIN=""
    DESEC_MONITOR_TOKEN=""
fi

cat > "$MONITOR_SCRIPT" <<EOF
#!/usr/bin/env bash
COMPOSE_FILE="$COMPOSE_FILE"
CURRENT_IP_FILE="$CURRENT_IP_FILE"
LOG_FILE="$IP_LOG_FILE"
DESEC_DOMAIN="$DESEC_MONITOR_DOMAIN"
DESEC_TOKEN="$DESEC_MONITOR_TOKEN"

NEW_IP=\$(curl -s --max-time 5 https://api.ipify.org || curl -s --max-time 5 https://ifconfig.me)

if [[ ! "\$NEW_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\$ ]]; then
    echo "\$(date) [ERROR] Failed to get valid public IP" >> "\$LOG_FILE"
    exit 1
fi

OLD_IP=\$(cat "\$CURRENT_IP_FILE" 2>/dev/null || echo "")

if [ "\$NEW_IP" != "\$OLD_IP" ]; then
    echo "\$(date) [INFO] IP Change detected: \$OLD_IP -> \$NEW_IP" >> "\$LOG_FILE"
    echo "\$NEW_IP" > "\$CURRENT_IP_FILE"
    
    if [ -n "\$DESEC_DOMAIN" ] && [ -n "\$DESEC_TOKEN" ]; then
        echo "\$(date) [INFO] Updating deSEC DNS record for \$DESEC_DOMAIN..." >> "\$LOG_FILE"
        DESEC_RESPONSE=\$(curl -s -X PATCH "https://desec.io/api/v1/domains/\$DESEC_DOMAIN/rrsets/" \\
            -H "Authorization: Token \$DESEC_TOKEN" \\
            -H "Content-Type: application/json" \\
            -d "[{\"subname\": \"\", \"ttl\": 3600, \"type\": \"A\", \"records\": [\"\$NEW_IP\"]}]" 2>&1)
        
        NEW_IP_ESCAPED=\$(echo "\$NEW_IP" | sed 's/\\./\\\\./g')
        if [ -z "\$DESEC_RESPONSE" ] || echo "\$DESEC_RESPONSE" | grep -qE "(\${NEW_IP_ESCAPED}|\\[\\]|\"records\")" ; then
            echo "\$(date) [INFO] deSEC DNS updated successfully to \$NEW_IP" >> "\$LOG_FILE"
        else
            echo "\$(date) [WARN] deSEC DNS update may have failed: \$DESEC_RESPONSE" >> "\$LOG_FILE"
        fi
    fi
    
    sed -i "s|WG_HOST=.*|WG_HOST=\$NEW_IP|g" "\$COMPOSE_FILE"
    docker compose -f "\$COMPOSE_FILE" up -d --no-deps --force-recreate wg-easy
    echo "\$(date) [INFO] WireGuard container restarted with new IP" >> "\$LOG_FILE"
fi
EOF
chmod +x "$MONITOR_SCRIPT"
CRON_CMD="*/5 * * * * $MONITOR_SCRIPT"
EXISTING_CRON=$(crontab -l 2>/dev/null || true)
echo "$EXISTING_CRON" | grep -v "$MONITOR_SCRIPT" | { cat; echo "$CRON_CMD"; } | crontab -

# --- 16. DEPLOYMENT ---
echo "=========================================================="
echo "RUNNING FINAL DEPLOYMENT"
echo "=========================================================="
sudo modprobe tun || true

sudo env DOCKER_CONFIG="$BASE_DIR/.docker" docker compose -f "$COMPOSE_FILE" up -d --build --remove-orphans

echo "[+] Waiting for AdGuard to start..."
sleep 10

if sudo docker ps | grep -q adguard; then
    log_info "AdGuard container is running"
    sleep 5
    if curl -s --max-time 5 "http://$LAN_IP:$PORT_ADGUARD_WEB" > /dev/null; then
        log_info "AdGuard web interface is accessible"
    else
        log_warn "AdGuard web interface not yet accessible (may still be initializing)"
    fi
    if sudo docker exec adguard test -f /opt/adguardhome/conf/AdGuardHome.yaml; then
        log_info "AdGuard configuration file is present"
    else
        log_warn "AdGuard configuration file not found in container"
    fi
else
    log_warn "AdGuard container not running - please check logs"
fi

echo "[+] Cleaning up unused images..."
sudo docker image prune -af

echo "=========================================================="
echo "DEPLOYMENT COMPLETE V3.9.2"
echo "=========================================================="
echo "ACCESS DASHBOARD:"
echo "http://$LAN_IP:$PORT_DASHBOARD_WEB"
echo ""
echo "ADGUARD HOME (DNS + Web UI):"
echo "http://$LAN_IP:$PORT_ADGUARD_WEB"
echo ""
echo "WIREGUARD VPN (Remote Access):"
echo "http://$LAN_IP:$PORT_WG_WEB"
echo ""
echo "DNS SERVER (via WireGuard VPN):"
echo "  Regular DNS: $LAN_IP:53"
if [ -n "$DESEC_DOMAIN" ]; then
    echo "  DoH: https://$DESEC_DOMAIN/dns-query"
    echo "  DoT: tls://$DESEC_DOMAIN"
    echo "  DoQ: quic://$DESEC_DOMAIN"
    echo ""
    echo "ENCRYPTED DNS SETUP:"
    echo "  1. Connect to WireGuard VPN first"
    echo "  2. Configure your device with:"
    echo "     - DoH URL: https://$DESEC_DOMAIN/dns-query"
    echo "     - DoT Server: $DESEC_DOMAIN:853"
    echo "  3. No certificate warnings (Let's Encrypt cert)"
else
    echo "  DoH: https://$LAN_IP/dns-query (via VPN)"
    echo "  DoT: tls://$LAN_IP (via VPN)"
    echo ""
    echo "ENCRYPTED DNS SETUP:"
    echo "  1. Connect to WireGuard VPN first"
    echo "  2. Configure with $LAN_IP"
    echo "  3. You'll see cert warnings (self-signed)"
fi
echo ""
echo "SECURITY MODEL:"
echo "  ✓ ONLY WireGuard (51820/udp) exposed to internet"
echo "  ✓ All services bound to LAN IP (not 0.0.0.0)"
echo "  ✓ WireGuard controls access - valid config required"
echo "  ✓ No direct DNS exposure - requires VPN authentication"
echo "  ✓ Fully recursive DNS (no third-party upstream)"
echo ""
echo "SPLIT TUNNELING (bandwidth optimized):"
echo "  ✓ Only private IPs routed through VPN (LAN + Docker networks)"
echo "  ✓ Internet traffic goes direct (not through tunnel)"
echo "  ✓ DNS routed to AdGuard for ad-blocking on mobile"
echo "  ✓ All services (including VERT) accessible via VPN tunnel"
echo ""
if [ "$AUTO_PASSWORD" = true ]; then
    echo "=========================================================="
    echo "AUTO-GENERATED CREDENTIALS"
    echo "=========================================================="
    echo "VPN Web UI Password: $VPN_PASS_RAW"
    echo "AdGuard Home Password: $AGH_PASS_RAW"
    echo "AdGuard Home Username: adguard"
    echo "Odido Booster API Key: $ODIDO_API_KEY"
    echo ""
    echo "IMPORTANT: Save these credentials securely!"
    echo "They are also stored in: $BASE_DIR/.secrets"
fi
echo "=========================================================="
