#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2024,SC2086
set -euo pipefail

# ==============================================================================
# ZIMAOS PRIVACY HUB V3.9.2: HOTFIX
# ==============================================================================
# Changes:
# - FIX: Normalizes "Key = Value" to "Key=Value" to fix Gluetun parser errors
# - FIX: Enhanced sanitization (strips \r, trailing spaces, blank lines)
# - FIX: Added validation for WireGuard Private Key
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

# PATHS
SRC_DIR="$BASE_DIR/sources"
ENV_DIR="$BASE_DIR/env"
CONFIG_DIR="$BASE_DIR/config"
COMPOSE_FILE="$BASE_DIR/docker-compose.yml"
DASHBOARD_FILE="$BASE_DIR/dashboard.html"
GLUETUN_ENV_FILE="$BASE_DIR/gluetun.env"
HISTORY_LOG="$BASE_DIR/deployment.log"

# WIREGUARD
WG_PROFILES_DIR="$BASE_DIR/wg-profiles"
ACTIVE_WG_CONF="$BASE_DIR/active-wg.conf"
ACTIVE_PROFILE_NAME_FILE="$BASE_DIR/.active_profile_name"
mkdir -p "$WG_PROFILES_DIR"

# SUB-CONFIGS
NGINX_CONF_DIR="$CONFIG_DIR/nginx"
NGINX_CONF="$NGINX_CONF_DIR/default.conf"
UNBOUND_CONF="$CONFIG_DIR/unbound/unbound.conf"
AGH_CONF_DIR="$CONFIG_DIR/adguard"
AGH_YAML="$AGH_CONF_DIR/AdGuardHome.yaml"

# SCRIPTS
MONITOR_SCRIPT="$BASE_DIR/wg-ip-monitor.sh"
IP_LOG_FILE="$BASE_DIR/wg-ip-monitor.log"
CURRENT_IP_FILE="$BASE_DIR/.current_public_ip"
WG_CONTROL_SCRIPT="$BASE_DIR/wg-control.sh"
WG_API_SCRIPT="$BASE_DIR/wg-api.sh"

# LOGGING
log_info() { echo -e "\e[34m[INFO]\e[0m $1"; }
log_warn() { echo -e "\e[33m[WARN]\e[0m $1"; }
log_crit() { echo -e "\e[31m[CRIT]\e[0m $1"; }

# --- 2. CLEANUP FUNCTION (Force Support) ---
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

    TARGET_CONTAINERS="gluetun adguard dashboard portainer watchtower wg-easy wg-controller redlib wikiless wikiless_redis invidious invidious-db companion libremdb rimgo breezewiki anonymousoverflow scribe dumb"
    
    FOUND_CONTAINERS=""
    for c in $TARGET_CONTAINERS; do
        if sudo docker ps -a --format '{{.Names}}' | grep -q "^\\${c}$"; then
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
            # Force remove volumes by stopping any containers that might be using them first
            for vol in portainer-data adguard-work redis-data postgresdata wg-config companioncache; do
                sudo docker volume rm -f "$vol" 2>/dev/null || true
            done
            log_info "All deployment artifacts, configs, env files, and volumes wiped."
        fi
    fi
    
    if [ "$FORCE_CLEAN" = true ]; then
        log_warn "NUCLEAR CLEANUP MODE: Removing everything..."
        if [ -d "$BASE_DIR" ]; then
            sudo rm -rf "$BASE_DIR" 2>/dev/null || true
        fi
        # Explicitly remove named volumes used by the stack (force flag)
        for vol in portainer-data adguard-work redis-data postgresdata wg-config companioncache; do
            sudo docker volume rm -f "$vol" 2>/dev/null || true
        done
        sudo docker volume prune -f 2>/dev/null || true
        sudo docker image prune -af 2>/dev/null || true
        sudo docker builder prune -af 2>/dev/null || true
        log_info "Nuclear cleanup complete."
    fi
}

# RUN CLEANUP
clean_environment

mkdir -p "$BASE_DIR" "$SRC_DIR" "$ENV_DIR" "$CONFIG_DIR/unbound" "$AGH_CONF_DIR" "$NGINX_CONF_DIR" "$WG_PROFILES_DIR"

# Init Logs
touch "$HISTORY_LOG" "$ACTIVE_WG_CONF"
if [ ! -f "$ACTIVE_PROFILE_NAME_FILE" ]; then echo "Initial-Setup" > "$ACTIVE_PROFILE_NAME_FILE"; fi
chmod 666 "$ACTIVE_PROFILE_NAME_FILE" "$HISTORY_LOG"

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
    echo "   Automatically top-up your Odido mobile data when running low."
    echo "   Requires credentials from the Odido app."
    echo ""
    echo -n "Odido User ID (or Enter to skip): "
    read -r ODIDO_USER_ID
    if [ -n "$ODIDO_USER_ID" ]; then
        echo -n "Odido Access Token: "
        read -rs ODIDO_TOKEN
        echo ""
        echo -n "Odido Bundle Code (default: A0DAY01 for 2GB): "
        read -r ODIDO_BUNDLE_CODE
        if [ -z "$ODIDO_BUNDLE_CODE" ]; then
            ODIDO_BUNDLE_CODE="A0DAY01"
        fi
        echo -n "Odido Threshold MB (default: 350): "
        read -r ODIDO_THRESHOLD
        if [ -z "$ODIDO_THRESHOLD" ]; then
            ODIDO_THRESHOLD="350"
        fi
    else
        ODIDO_TOKEN=""
        ODIDO_BUNDLE_CODE=""
        ODIDO_THRESHOLD=""
    fi
    
    log_info "Generating Secrets..."
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
ODIDO_BUNDLE_CODE=$ODIDO_BUNDLE_CODE
ODIDO_THRESHOLD=$ODIDO_THRESHOLD
EOF
else
    source "$BASE_DIR/.secrets"
    AGH_USER="adguard"
fi

echo ""
echo "=========================================================="
echo " PROTON WIREGUARD CONFIGURATION"
echo "=========================================================="

# NEW: Validation Logic
validate_wg_config() {
    if [ ! -s "$ACTIVE_WG_CONF" ]; then return 1; fi
    # Check if PrivateKey exists
    if ! grep -q "PrivateKey" "$ACTIVE_WG_CONF"; then
        return 1
    fi
    # Check if PrivateKey is just whitespace or empty value
    local PK_VAL
    PK_VAL=$(grep "PrivateKey" "$ACTIVE_WG_CONF" | cut -d'=' -f2 | tr -d '[:space:]')
    if [ -z "$PK_VAL" ]; then
        return 1
    fi
    # If the key is shorter than typical WireGuard keys (approx 44 chars), it's suspicious
    if [ "${#PK_VAL}" -lt 40 ]; then
        return 1
    fi
    return 0
}

# Check existing file
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
    
    # Sanitization:
    # 1. Remove Windows Carriage Returns \r (Critical for base64 errors)
    sed -i 's/\r//g' "$ACTIVE_WG_CONF"
    # 2. Remove trailing spaces/tabs
    sed -i 's/[ \t]*$//' "$ACTIVE_WG_CONF"
    # 3. Remove leading blank lines
    sed -i '/./,$!d' "$ACTIVE_WG_CONF"
    # 4. Normalize "Key = Value" to "Key=Value" to prevent parser issues with leading spaces
    sed -i 's/ *= */=/g' "$ACTIVE_WG_CONF"

    if ! validate_wg_config; then
        log_crit "The pasted WireGuard configuration is invalid (missing PrivateKey or malformed)."
        log_crit "Please ensure you are pasting the full contents of the .conf file."
        log_crit "Aborting to prevent container errors."
        exit 1
    fi
fi

# --- 6. SETUP GLUETUN ENV ---
log_info "Configuring Gluetun..."
sudo docker pull -q qmcgaw/gluetun:latest > /dev/null

cat > "$GLUETUN_ENV_FILE" <<EOF
VPN_SERVICE_PROVIDER=custom
VPN_TYPE=wireguard
FIREWALL_VPN_INPUT_PORTS=8080,8180,3000,3001,3002,8280,10416,8480,5555
FIREWALL_OUTBOUND_SUBNETS=10.0.0.0/8,172.16.0.0/12,192.168.0.0/16
EOF

# Extract profile name from WireGuard config (look for comment in [Peer] section like "# NL-FREE#231")
extract_wg_profile_name() {
    local config_file="$1"
    local in_peer=0
    local profile_name=""
    while IFS= read -r line; do
        stripped=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        # Check for [Peer] section start
        if echo "$stripped" | grep -qi '^\[peer\]$'; then
            in_peer=1
            continue
        fi
        # If in [Peer] section and found a comment, extract it as profile name
        if [ "$in_peer" -eq 1 ] && echo "$stripped" | grep -q '^#'; then
            profile_name=$(echo "$stripped" | sed 's/^#[[:space:]]*//')
            if [ -n "$profile_name" ]; then
                echo "$profile_name"
                return 0
            fi
        fi
        # If hit another section, stop looking
        if [ "$in_peer" -eq 1 ] && echo "$stripped" | grep -q '^\['; then
            break
        fi
    done < "$config_file"
    # Fallback: look for any comment that doesn't look like "Key = Value"
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

# Get initial profile name from WireGuard config
INITIAL_PROFILE_NAME=$(extract_wg_profile_name "$ACTIVE_WG_CONF")
if [ -z "$INITIAL_PROFILE_NAME" ]; then
    INITIAL_PROFILE_NAME="Initial-Setup"
fi
# Sanitize the profile name (keep only alphanumeric, dash, underscore, hash)
INITIAL_PROFILE_NAME_SAFE=$(echo "$INITIAL_PROFILE_NAME" | tr -cd 'a-zA-Z0-9-_#')
if [ -z "$INITIAL_PROFILE_NAME_SAFE" ]; then
    INITIAL_PROFILE_NAME_SAFE="Initial-Setup"
fi

cp "$ACTIVE_WG_CONF" "$WG_PROFILES_DIR/${INITIAL_PROFILE_NAME_SAFE}.conf"
chmod 644 "$GLUETUN_ENV_FILE" "$ACTIVE_WG_CONF" "$WG_PROFILES_DIR/${INITIAL_PROFILE_NAME_SAFE}.conf"

# Update the active profile name file with the extracted name
echo "$INITIAL_PROFILE_NAME_SAFE" > "$ACTIVE_PROFILE_NAME_FILE"

# Secrets Gen
SCRIBE_SECRET=$(head -c 64 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 64)
ANONYMOUS_SECRET=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32)
IV_HMAC=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 16)
IV_COMPANION=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 16)

# --- 8. PORT VARS ---
PORT_INT_REDLIB=8080; PORT_INT_WIKILESS=8180; PORT_INT_INVIDIOUS=3000
PORT_INT_LIBREMDB=3001; PORT_INT_RIMGO=3002; PORT_INT_BREEZEWIKI=10416
PORT_INT_ANONYMOUS=8480; PORT_ADGUARD_WEB=8083; PORT_DASHBOARD_WEB=8081
PORT_PORTAINER=9000; PORT_WG_WEB=51821; PORT_WG_UDP=51820
PORT_REDLIB=8080; PORT_WIKILESS=8180; PORT_INVIDIOUS=3000; PORT_LIBREMDB=3001
PORT_RIMGO=3002; PORT_SCRIBE=8280; PORT_BREEZEWIKI=8380; PORT_ANONYMOUS=8480
PORT_DUMB=5555

# --- 9. CONFIG GENERATION ---
log_info "Generating Service Configs..."

# --- 9a. DNS & CERTIFICATE SETUP ---
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
    
    # FIX: Added --dnssleep 30 to disable broken self-checks and wait for propagation
    sudo docker run --rm \
        -v "$AGH_CONF_DIR:/acme" \
        -e "DESEC_Token=$DESEC_TOKEN" \
        -e "DEDYN_TOKEN=$DESEC_TOKEN" \
        -e "DESEC_DOMAIN=$DESEC_DOMAIN" \
        neilpang/acme.sh:latest \
        --issue \
        --dns dns_desec \
        --dnssleep 30 \
        -d "$DESEC_DOMAIN" \
        -d "*.$DESEC_DOMAIN" \
        --keylength 4096 \
        --server letsencrypt \
        --home /acme \
        --config-home /acme \
        --cert-home /acme/certs 2>&1 && CERT_SUCCESS=true || true
    
    if [ "$CERT_SUCCESS" = true ] && [ -f "$AGH_CONF_DIR/certs/${DESEC_DOMAIN}_ecc/fullchain.cer" ]; then
        cp "$AGH_CONF_DIR/certs/${DESEC_DOMAIN}_ecc/fullchain.cer" "$AGH_CONF_DIR/ssl.crt"
        cp "$AGH_CONF_DIR/certs/${DESEC_DOMAIN}_ecc/${DESEC_DOMAIN}.key" "$AGH_CONF_DIR/ssl.key"
        log_info "Let's Encrypt certificate installed successfully!"
    elif [ "$CERT_SUCCESS" = true ] && [ -f "$AGH_CONF_DIR/certs/${DESEC_DOMAIN}/fullchain.cer" ]; then
        cp "$AGH_CONF_DIR/certs/${DESEC_DOMAIN}/fullchain.cer" "$AGH_CONF_DIR/ssl.crt"
        cp "$AGH_CONF_DIR/certs/${DESEC_DOMAIN}/${DESEC_DOMAIN}.key" "$AGH_CONF_DIR/ssl.key"
        log_info "Let's Encrypt certificate installed successfully!"
    else
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

# Generate Unbound configuration - FULLY RECURSIVE
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
# OPTIMIZATION: Check for updates every 1 hour (negligible resource usage, better sync)
filters_update_interval: 1
EOF

cat > "$NGINX_CONF" <<EOF
server {
    listen $PORT_DASHBOARD_WEB default_server;
    root /usr/share/nginx/html;
    index index.html;
    location /api/ {
        proxy_pass http://wg-controller:55555/;
        proxy_set_header Host \$host;
        proxy_buffering off;
        proxy_cache off;
    }
}
EOF

# --- 10. ENV FILES ---
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

# --- 11. REPOS ---
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
chmod -R 777 "$SRC_DIR/invidious" "$ENV_DIR" "$CONFIG_DIR" "$WG_PROFILES_DIR"

# --- 12. BACKEND CONTROL SCRIPTS ---
cat > "$WG_CONTROL_SCRIPT" <<'EOF'
#!/bin/sh
ACTION=$1
PROFILE_NAME=$2
PROFILES_DIR="/profiles"
ACTIVE_CONF="/active-wg.conf"
NAME_FILE="/app/.active_profile_name"
LOG_FILE="/app/deployment.log"

# Helper function to sanitize strings for JSON (remove control chars, escape quotes)
sanitize_json_string() {
    printf '%s' "$1" | tr -d '\000-\037' | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

if [ "$ACTION" = "activate" ]; then
    if [ -f "$PROFILES_DIR/$PROFILE_NAME.conf" ]; then
        ln -sf "$PROFILES_DIR/$PROFILE_NAME.conf" "$ACTIVE_CONF"
        echo "$PROFILE_NAME" > "$NAME_FILE"
        DEPENDENTS="redlib wikiless wikiless_redis invidious invidious-db companion libremdb rimgo breezewiki anonymousoverflow scribe dumb"
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
    HANDSHAKE="0"
    HANDSHAKE_AGO="Never"
    RX="0"
    TX="0"
    ENDPOINT="--"
    PUBLIC_IP="--"
    
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^gluetun$"; then
        # Check container health
        HEALTH=$(docker inspect --format='{{.State.Health.Status}}' gluetun 2>/dev/null || echo "unknown")
        if [ "$HEALTH" = "healthy" ]; then
            GLUETUN_HEALTHY="true"
        fi
        WG_OUT=$(docker exec gluetun wg show wg0 dump 2>/dev/null | head -n 2 | tail -n 1 || echo "")
        if [ -n "$WG_OUT" ]; then
            GLUETUN_STATUS="up"
            HANDSHAKE=$(echo "$WG_OUT" | awk '{print $5}' 2>/dev/null || echo "0")
            RX=$(echo "$WG_OUT" | awk '{print $6}' 2>/dev/null || echo "0")
            TX=$(echo "$WG_OUT" | awk '{print $7}' 2>/dev/null || echo "0")
            ENDPOINT=$(docker exec gluetun wg show wg0 endpoints 2>/dev/null | awk '{print $2}' 2>/dev/null || echo "--")
            # Ensure numeric values
            case "$HANDSHAKE" in ''|*[!0-9]*) HANDSHAKE="0" ;; esac
            case "$RX" in ''|*[!0-9]*) RX="0" ;; esac
            case "$TX" in ''|*[!0-9]*) TX="0" ;; esac
            # Calculate time since last handshake
            if [ "$HANDSHAKE" != "0" ] && [ "$HANDSHAKE" -gt 0 ] 2>/dev/null; then
                NOW=$(date +%s)
                DIFF=$((NOW - HANDSHAKE))
                if [ "$DIFF" -lt 60 ]; then
                    HANDSHAKE_AGO="${DIFF}s ago"
                elif [ "$DIFF" -lt 3600 ]; then
                    HANDSHAKE_AGO="$((DIFF / 60))m ago"
                else
                    HANDSHAKE_AGO="$((DIFF / 3600))h ago"
                fi
            fi
        fi
        # Get public IP from gluetun
        PUBLIC_IP=$(docker exec gluetun wget -qO- --timeout=5 https://api.ipify.org 2>/dev/null || echo "--")
    fi
    
    ACTIVE_NAME=$(cat "$NAME_FILE" 2>/dev/null | tr -d '\n\r' || echo "Unknown")
    if [ -z "$ACTIVE_NAME" ]; then ACTIVE_NAME="Unknown"; fi
    
    WGE_STATUS="down"
    WGE_HOST="Unknown"
    WGE_CLIENTS="0"
    WGE_CONNECTED="0"
    
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^wg-easy$"; then
        WGE_STATUS="up"
        WGE_HOST=$(docker exec wg-easy printenv WG_HOST 2>/dev/null | tr -d '\n\r' || echo "Unknown")
        if [ -z "$WGE_HOST" ]; then WGE_HOST="Unknown"; fi
        # Try to get client count from wg-easy (via wg show)
        WG_PEER_DATA=$(docker exec wg-easy wg show wg0 2>/dev/null || echo "")
        if [ -n "$WG_PEER_DATA" ]; then
            # Count total peers
            WGE_CLIENTS=$(echo "$WG_PEER_DATA" | grep -c "^peer:" 2>/dev/null || echo "0")
            # Count peers with recent handshake (within last 3 minutes = 180 seconds)
            CONNECTED_COUNT=0
            for hs in $(echo "$WG_PEER_DATA" | grep "latest handshake:" | sed 's/.*latest handshake: //' | sed 's/ seconds.*//' | grep -E '^[0-9]+' 2>/dev/null || echo ""); do
                if [ -n "$hs" ] && [ "$hs" -lt 180 ] 2>/dev/null; then
                    CONNECTED_COUNT=$((CONNECTED_COUNT + 1))
                fi
            done
            WGE_CONNECTED="$CONNECTED_COUNT"
        fi
    fi
    
    # Sanitize all string values
    ACTIVE_NAME=$(sanitize_json_string "$ACTIVE_NAME")
    ENDPOINT=$(sanitize_json_string "$ENDPOINT")
    PUBLIC_IP=$(sanitize_json_string "$PUBLIC_IP")
    HANDSHAKE_AGO=$(sanitize_json_string "$HANDSHAKE_AGO")
    WGE_HOST=$(sanitize_json_string "$WGE_HOST")
    
    # Output clean JSON
    printf '{"gluetun":{"status":"%s","healthy":%s,"active_profile":"%s","endpoint":"%s","public_ip":"%s","handshake":"%s","handshake_ago":"%s","rx":"%s","tx":"%s"},"wgeasy":{"status":"%s","host":"%s","clients":"%s","connected":"%s"}}' \
        "$GLUETUN_STATUS" "$GLUETUN_HEALTHY" "$ACTIVE_NAME" "$ENDPOINT" "$PUBLIC_IP" "$HANDSHAKE" "$HANDSHAKE_AGO" "$RX" "$TX" \
        "$WGE_STATUS" "$WGE_HOST" "$WGE_CLIENTS" "$WGE_CONNECTED"
fi
EOF
chmod +x "$WG_CONTROL_SCRIPT"

cat > "$WG_API_SCRIPT" <<'APIEOF'
#!/usr/bin/env python3
import http.server
import socketserver
import json
import os
import subprocess
import time
import urllib.request
import urllib.error

PORT = 55555
PROFILES_DIR = "/profiles"
CONTROL_SCRIPT = "/usr/local/bin/wg-control.sh"
LOG_FILE = "/app/deployment.log"
ODIDO_CONFIG_FILE = "/app/odido.json"

# Odido API class for interacting with the Odido carrier API
class OdidoAPI:
    BASE_URL = "https://capi.odido.nl"
    
    def __init__(self, user_id, access_token):
        self.user_id = user_id
        self.access_token = access_token
        self.headers = {
            "Authorization": f"Bearer {access_token}",
            "User-Agent": "T-Mobile 5.3.28 (Android 10; 10)",
            "Accept": "application/json",
            "Content-Type": "application/json"
        }
    
    def _request(self, url, method="GET", data=None):
        req = urllib.request.Request(url, headers=self.headers, method=method)
        if data:
            req.data = json.dumps(data).encode('utf-8')
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                return json.loads(resp.read().decode('utf-8'))
        except urllib.error.HTTPError as e:
            return {"error": f"HTTP {e.code}: {e.reason}"}
        except Exception as e:
            return {"error": str(e)}
    
    def get_subscriptions(self):
        """Fetch linked subscriptions"""
        return self._request(f"{self.BASE_URL}/{self.user_id}/linkedsubscriptions")
    
    def get_roaming_bundles(self, subscription_url):
        """Fetch roaming bundles for a subscription"""
        return self._request(f"{subscription_url}/roamingbundles")
    
    def buy_bundle(self, subscription_url, buying_code):
        """Purchase a data bundle"""
        data = {"Bundles": [{"BuyingCode": buying_code}]}
        return self._request(f"{subscription_url}/roamingbundles", method="POST", data=data)
    
    def get_data_remaining(self):
        """Get remaining data in MB"""
        try:
            subs = self.get_subscriptions()
            if "error" in subs:
                return subs
            subscription_url = subs["subscriptions"][0]["SubscriptionURL"]
            bundles = self.get_roaming_bundles(subscription_url)
            if "error" in bundles:
                return bundles
            total_remaining = 0
            for bundle in bundles.get("Bundles", []):
                if bundle.get("ZoneColor") == "NL":
                    remaining = bundle.get("Remaining", {})
                    total_remaining += remaining.get("Value", 0)
            return {
                "remaining_mb": round(total_remaining / 1024, 0),
                "remaining_bytes": total_remaining,
                "subscription_url": subscription_url
            }
        except Exception as e:
            return {"error": str(e)}

def load_odido_config():
    """Load Odido configuration from file"""
    try:
        if os.path.exists(ODIDO_CONFIG_FILE):
            with open(ODIDO_CONFIG_FILE, 'r') as f:
                return json.load(f)
    except:
        pass
    # Load from environment variables as fallback
    user_id = os.environ.get("ODIDO_USER_ID", "")
    token = os.environ.get("ODIDO_TOKEN", "")
    bundle_code = os.environ.get("ODIDO_BUNDLE_CODE", "A0DAY01")
    threshold = int(os.environ.get("ODIDO_THRESHOLD", "350"))
    return {
        "user_id": user_id,
        "token": token,
        "bundle_code": bundle_code,
        "threshold": threshold,
        "enabled": bool(user_id and token)
    }

def save_odido_config(config):
    """Save Odido configuration to file"""
    with open(ODIDO_CONFIG_FILE, 'w') as f:
        json.dump(config, f)

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
                json_start = output.find('{')
                if json_start != -1:
                    output = output[json_start:]
                self._send_json(json.loads(output))
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path == '/profiles':
            try:
                files = [f.replace('.conf', '') for f in os.listdir(PROFILES_DIR) if f.endswith('.conf')]
                self._send_json({"profiles": files})
            except:
                self._send_json({"error": "Failed to list profiles"}, 500)
        elif self.path == '/odido/status':
            try:
                config = load_odido_config()
                if not config.get("enabled"):
                    self._send_json({"enabled": False, "configured": False})
                    return
                api = OdidoAPI(config["user_id"], config["token"])
                data = api.get_data_remaining()
                data["enabled"] = True
                data["configured"] = True
                data["bundle_code"] = config.get("bundle_code", "A0DAY01")
                data["threshold"] = config.get("threshold", 350)
                self._send_json(data)
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path == '/odido/config':
            try:
                config = load_odido_config()
                # Mask the token for security
                if config.get("token"):
                    config["token_masked"] = config["token"][:8] + "..." if len(config["token"]) > 8 else "***"
                    del config["token"]
                self._send_json(config)
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path == '/events':
            self.send_response(200)
            self.send_header('Content-type', 'text/event-stream')
            self.send_header('Cache-Control', 'no-cache')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            try:
                # Wait for log file to exist
                for _ in range(10):
                    if os.path.exists(LOG_FILE):
                        break
                    time.sleep(1)
                if not os.path.exists(LOG_FILE):
                    self.wfile.write(b"data: Log file initializing...\n\n")
                    self.wfile.flush()
                f = open(LOG_FILE, 'r')
                f.seek(0, 2)
                while True:
                    line = f.readline()
                    if line:
                        self.wfile.write(f"data: {line.strip()}\n\n".encode('utf-8'))
                        self.wfile.flush()
                    else:
                        time.sleep(1)
            except:
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
        elif self.path == '/odido/config':
            try:
                l = int(self.headers['Content-Length'])
                data = json.loads(self.rfile.read(l).decode('utf-8'))
                config = load_odido_config()
                if "user_id" in data:
                    config["user_id"] = data["user_id"]
                if "token" in data:
                    config["token"] = data["token"]
                if "bundle_code" in data:
                    config["bundle_code"] = data["bundle_code"]
                if "threshold" in data:
                    config["threshold"] = int(data["threshold"])
                config["enabled"] = bool(config.get("user_id") and config.get("token"))
                save_odido_config(config)
                self._send_json({"success": True, "enabled": config["enabled"]})
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path == '/odido/buy':
            try:
                config = load_odido_config()
                if not config.get("enabled"):
                    self._send_json({"error": "Odido not configured"}, 400)
                    return
                l = int(self.headers['Content-Length']) if self.headers.get('Content-Length') else 0
                data = json.loads(self.rfile.read(l).decode('utf-8')) if l > 0 else {}
                bundle_code = data.get("bundle_code", config.get("bundle_code", "A0DAY01"))
                api = OdidoAPI(config["user_id"], config["token"])
                status = api.get_data_remaining()
                if "error" in status:
                    self._send_json(status, 500)
                    return
                result = api.buy_bundle(status["subscription_url"], bundle_code)
                self._send_json(result)
            except Exception as e:
                self._send_json({"error": str(e)}, 500)

if __name__ == "__main__":
    print(f"Starting API server on port {PORT}...")
    # Ensure log file exists
    if not os.path.exists(LOG_FILE):
        os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
        open(LOG_FILE, 'a').close()
    with ThreadingHTTPServer(("", PORT), APIHandler) as httpd:
        print(f"API server running on port {PORT}")
        httpd.serve_forever()
APIEOF
chmod +x "$WG_API_SCRIPT"

# --- 13. DOCKER COMPOSE WITH RESOURCE TUNING ---
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

services:
  wg-controller:
    image: python:3.11-alpine
    container_name: wg-controller
    networks: [frontnet]
    environment:
      - ODIDO_USER_ID=${ODIDO_USER_ID:-}
      - ODIDO_TOKEN=${ODIDO_TOKEN:-}
      - ODIDO_BUNDLE_CODE=${ODIDO_BUNDLE_CODE:-A0DAY01}
      - ODIDO_THRESHOLD=${ODIDO_THRESHOLD:-350}
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
      - "$BASE_DIR/odido.json:/app/odido.json"
    entrypoint: ["/bin/sh", "-c", "touch /app/odido.json && apk add --no-cache docker-cli docker-compose && python /app/server.py"]
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '0.2', memory: 128M}

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
      --notification-url "generic://wg-controller:55555/watchtower?template=json&disabletls=yes"
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
      - "$LAN_IP:$PORT_DUMB:5555/tcp"
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
    x-casaos:
      author: "self"
      category: "Network"
      icon: "https://raw.githubusercontent.com/IceWhaleTech/CasaOS-AppStore/main/Apps/NginxProxyManager/icon.png"
      index: "/"
      main: "dashboard"
      port_map: "$PORT_DASHBOARD_WEB"
      title:
        en_US: "Privacy Hub"
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
    depends_on: {invidious-db: {condition: service_healthy}, gluetun: {condition: service_healthy}}
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
    environment: {SERVER_SECRET_KEY: "$IV_COMPANION", SERVER_PORT: "8282"}
    volumes: ["companioncache:/var/tmp/youtubei.js:rw"]
    restart: unless-stopped
    read_only: true
    security_opt: ["no-new-privileges:true"]
    deploy:
      resources:
        limits: {cpus: '0.3', memory: 128M}

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

  dumb:
    image: ghcr.io/rramiachraf/dumb:latest
    container_name: dumb
    network_mode: "service:gluetun"
    depends_on: {gluetun: {condition: service_healthy}}
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '0.5', memory: 256M}
EOF

# --- 14. DASHBOARD HTML ---
echo "[+] Generating Dashboard..."
cat > "$DASHBOARD_FILE" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ZimaOS Privacy Hub</title>
    <link href="https://fontlay.com/css?family=Google+Sans+Flex" rel="stylesheet">
    <link href="https://fontlay.com/css?family=Cascadia+Code" rel="stylesheet">
    <style>
        :root {
            --bg: #141218; --surf: #1d1b20; --surf-high: #2b2930;
            --on-surf: #e6e1e5; --outline: #938f99;
            --p: #d0bcff; --on-p: #381e72; --pc: #4f378b; --on-pc: #eaddff;
            --s: #ccc2dc; --on-s: #332d41; --sc: #4a4458; --on-sc: #e8def8;
            --err: #f2b8b5; --on-err: #601410;
            --ok: #bceabb; --on-ok: #003912;
            --warn: #ffb74d;
            --radius: 20px;
        }
        body { background: var(--bg); color: var(--on-surf); font-family: 'Google Sans Flex', sans-serif; margin: 0; padding: 40px; display: flex; flex-direction: column; align-items: center; min-height: 100vh; }
        .container { max-width: 1200px; width: 100%; }
        header { margin-bottom: 48px; }
        h1 { font-weight: 400; font-size: 3rem; margin: 0; color: var(--p); line-height: 1.1; }
        .sub { font-size: 1.1rem; color: var(--s); margin-top: 8px; font-weight: 500; }
        .section-label {
            color: var(--p); font-size: 0.9rem; font-weight: 600; letter-spacing: 1.5px; text-transform: uppercase;
            margin: 48px 0 16px 8px;
        }
        .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 16px; }
        .grid-2 { display: grid; grid-template-columns: repeat(2, 1fr); gap: 16px; }
        .grid-3 { display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px; }
        @media (max-width: 900px) { .grid-2, .grid-3 { grid-template-columns: 1fr; } }
        .card {
            background: var(--surf); border-radius: var(--radius); padding: 24px;
            text-decoration: none; color: inherit; transition: 0.2s; position: relative;
            display: flex; flex-direction: column; justify-content: space-between; min-height: 130px; border: 1px solid transparent;
        }
        .card:hover { background: var(--surf-high); transform: translateY(-2px); box-shadow: 0 4px 12px rgba(0,0,0,0.3); }
        .card.full-width { grid-column: 1 / -1; }
        .card h2 { margin: 0 0 8px 0; font-size: 1.4rem; font-weight: 400; color: var(--on-surf); }
        .card h3 { margin: 0 0 16px 0; font-size: 1.1rem; font-weight: 500; color: var(--on-surf); }
        .chip-box { display: flex; gap: 8px; flex-wrap: wrap; margin-bottom: auto; }
        .badge { font-size: 0.75rem; padding: 6px 12px; border-radius: 8px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px; }
        .badge.vpn { background: var(--pc); color: var(--on-pc); }
        .badge.admin { background: var(--sc); color: var(--on-sc); }
        .badge.odido { background: #ff6b35; color: #fff; }
        .status-pill {
            display: inline-flex; align-items: center; gap: 8px; background: rgba(255,255,255,0.06);
            padding: 6px 14px; border-radius: 50px; font-size: 0.85rem; color: var(--s); margin-top: 16px; width: fit-content;
        }
        .dot { width: 8px; height: 8px; border-radius: 50%; background: #666; transition: 0.3s; }
        .dot.up { background: var(--ok); box-shadow: 0 0 10px var(--ok); }
        .dot.down { background: var(--err); box-shadow: 0 0 10px var(--err); }
        .input-field {
            width: 100%; background: #141218; border: 1px solid #49454f; color: #fff;
            padding: 14px; border-radius: 12px; font-family: 'Cascadia Code', monospace; font-size: 0.9rem; box-sizing: border-box; outline: none; transition: 0.2s;
        }
        .input-field:focus { border-color: var(--p); background: #1d1b20; }
        textarea.input-field { min-height: 120px; resize: vertical; }
        .btn {
            background: var(--p); color: var(--on-p); border: none; padding: 12px 24px; border-radius: 50px;
            font-weight: 600; cursor: pointer; text-transform: uppercase; letter-spacing: 0.5px; transition: 0.2s; margin-top: 16px; display: inline-block;
        }
        .btn:hover { opacity: 0.9; box-shadow: 0 2px 8px rgba(208, 188, 255, 0.3); }
        .btn:disabled { opacity: 0.5; cursor: not-allowed; }
        .btn.secondary { background: var(--sc); color: var(--on-sc); }
        .btn.odido-buy { background: #ff6b35; color: #fff; }
        .btn.del { 
            background: transparent; border: 1px solid #444; 
            padding: 8px; width: 32px; height: 32px; border-radius: 8px; 
            display: flex; align-items: center; justify-content: center; margin: 0; transition: 0.2s;
        }
        .btn.del:hover { background: rgba(242, 184, 181, 0.1); border-color: var(--err); }
        .btn.del svg { width: 16px; height: 16px; fill: var(--err); }
        .profile-row {
            display: flex; justify-content: space-between; align-items: center;
            background: #2b2930; padding: 12px 16px; border-radius: 12px; margin-bottom: 8px; border: 1px solid #444;
        }
        .profile-name { font-weight: 500; color: var(--on-surf); cursor: pointer; flex-grow: 1; }
        .profile-name:hover { color: var(--p); }
        .stat-row { display: flex; justify-content: space-between; margin-bottom: 10px; font-size: 0.95rem; border-bottom: 1px solid #333; padding-bottom: 8px; }
        .stat-row:last-child { border: none; padding: 0; margin: 0; }
        .stat-val { font-family: 'Cascadia Code', monospace; color: var(--p); }
        .active-prof { color: var(--ok); font-weight: bold; }
        .log-box {
            background: #000; border: 1px solid #333; padding: 16px; border-radius: 12px;
            height: 300px; overflow-y: auto; font-family: 'Cascadia Code', monospace; font-size: 0.85rem; color: #ccc;
        }
        .log-line { margin: 2px 0; border-bottom: 1px solid #111; padding-bottom: 2px; }
        .code-block {
            background: #0d0d0d; border: 1px solid #333; border-radius: 8px; padding: 12px 16px;
            font-family: 'Cascadia Code', monospace; font-size: 0.85rem; color: var(--p);
            margin: 8px 0; overflow-x: auto; white-space: nowrap;
        }
        .code-label { font-size: 0.75rem; color: var(--s); margin-bottom: 4px; text-transform: uppercase; letter-spacing: 0.5px; }
        .data-bar { background: #333; border-radius: 8px; height: 12px; margin: 12px 0; overflow: hidden; }
        .data-bar-fill { background: linear-gradient(90deg, var(--ok), #4caf50); height: 100%; border-radius: 8px; transition: width 0.3s; }
        .data-bar-fill.low { background: linear-gradient(90deg, var(--warn), #ff9800); }
        .data-bar-fill.critical { background: linear-gradient(90deg, var(--err), #f44336); }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>Privacy Hub</h1>
            <div class="sub">Secure Self-Hosted Gateway</div>
        </header>

        <div class="section-label">Privacy Services</div>
        <div class="grid">
            <a href="http://$LAN_IP:$PORT_INVIDIOUS" class="card" data-check="true"><h2>Invidious</h2><div class="chip-box"><span class="badge vpn">VPN</span></div><div class="status-pill"><span class="dot"></span><span class="status-text">Checking...</span></div></a>
            <a href="http://$LAN_IP:$PORT_REDLIB" class="card" data-check="true"><h2>Redlib</h2><div class="chip-box"><span class="badge vpn">VPN</span></div><div class="status-pill"><span class="dot"></span><span class="status-text">Checking...</span></div></a>
            <a href="http://$LAN_IP:$PORT_WIKILESS" class="card" data-check="true"><h2>Wikiless</h2><div class="chip-box"><span class="badge vpn">VPN</span></div><div class="status-pill"><span class="dot"></span><span class="status-text">Checking...</span></div></a>
            <a href="http://$LAN_IP:$PORT_LIBREMDB" class="card" data-check="true"><h2>LibremDB</h2><div class="chip-box"><span class="badge vpn">VPN</span></div><div class="status-pill"><span class="dot"></span><span class="status-text">Checking...</span></div></a>
            <a href="http://$LAN_IP:$PORT_RIMGO" class="card" data-check="true"><h2>Rimgo</h2><div class="chip-box"><span class="badge vpn">VPN</span></div><div class="status-pill"><span class="dot"></span><span class="status-text">Checking...</span></div></a>
            <a href="http://$LAN_IP:$PORT_SCRIBE" class="card" data-check="true"><h2>Scribe</h2><div class="chip-box"><span class="badge vpn">VPN</span></div><div class="status-pill"><span class="dot"></span><span class="status-text">Checking...</span></div></a>
            <a href="http://$LAN_IP:$PORT_BREEZEWIKI" class="card" data-check="true"><h2>BreezeWiki</h2><div class="chip-box"><span class="badge vpn">VPN</span></div><div class="status-pill"><span class="dot"></span><span class="status-text">Checking...</span></div></a>
            <a href="http://$LAN_IP:$PORT_ANONYMOUS" class="card" data-check="true"><h2>AnonOverflow</h2><div class="chip-box"><span class="badge vpn">VPN</span></div><div class="status-pill"><span class="dot"></span><span class="status-text">Checking...</span></div></a>
            <a href="http://$LAN_IP:$PORT_DUMB" class="card" data-check="true"><h2>Dumb</h2><div class="chip-box"><span class="badge vpn">VPN</span></div><div class="status-pill"><span class="dot"></span><span class="status-text">Checking...</span></div></a>
        </div>

        <div class="section-label">Administration</div>
        <div class="grid-3">
            <a href="http://$LAN_IP:$PORT_ADGUARD_WEB" class="card"><h2>AdGuard Home</h2><div class="chip-box"><span class="badge admin">Network</span></div></a>
            <a href="http://$LAN_IP:$PORT_PORTAINER" class="card"><h2>Portainer</h2><div class="chip-box"><span class="badge admin">System</span></div></a>
            <a href="http://$LAN_IP:$PORT_WG_WEB" class="card"><h2>WireGuard</h2><div class="chip-box"><span class="badge admin">Remote Access</span></div></a>
        </div>

        <div class="section-label">DNS Configuration</div>
        <div class="grid-2">
            <div class="card">
                <h3>Device DNS Settings</h3>
                <p style="font-size:0.85rem; color:var(--s); margin-bottom:16px;">Configure your devices to use this DNS server:</p>
                <div class="code-label">Plain DNS</div>
                <div class="code-block">$LAN_IP:53</div>
EOF
if [ -n "$DESEC_DOMAIN" ]; then
    cat >> "$DASHBOARD_FILE" <<EOF
                <div class="code-label">Domain</div>
                <div class="code-block">$DESEC_DOMAIN</div>
                <div class="code-label">DNS-over-HTTPS</div>
                <div class="code-block">https://$DESEC_DOMAIN/dns-query</div>
                <div class="code-label">DNS-over-TLS</div>
                <div class="code-block">$DESEC_DOMAIN:853</div>
                <div class="code-label">DNS-over-QUIC</div>
                <div class="code-block">quic://$DESEC_DOMAIN</div>
            </div>
            <div class="card">
                <h3>Mobile Device Setup</h3>
                <p style="font-size:0.85rem; color:var(--s); margin-bottom:12px;">To use encrypted DNS on your devices:</p>
                <ol style="margin:0; padding-left:20px; font-size:0.9rem; color:var(--on-surf); line-height:1.8;">
                    <li>Connect to WireGuard VPN first</li>
                    <li>Set Private DNS to:</li>
                </ol>
                <div class="code-block" style="margin-left:20px;">$DESEC_DOMAIN</div>
                <p style="font-size:0.8rem; color:var(--ok); margin-top:12px;">✓ Valid Let's Encrypt certificate (no warnings)</p>
            </div>
EOF
else
    cat >> "$DASHBOARD_FILE" <<EOF
                <div class="code-label">DNS-over-HTTPS</div>
                <div class="code-block">https://$LAN_IP/dns-query</div>
                <div class="code-label">DNS-over-TLS</div>
                <div class="code-block">$LAN_IP:853</div>
            </div>
            <div class="card">
                <h3>Mobile Device Setup</h3>
                <p style="font-size:0.85rem; color:var(--s); margin-bottom:12px;">To use DNS on your devices:</p>
                <ol style="margin:0; padding-left:20px; font-size:0.9rem; color:var(--on-surf); line-height:1.8;">
                    <li>Connect to WireGuard VPN first</li>
                    <li>Set DNS server to:</li>
                </ol>
                <div class="code-block" style="margin-left:20px;">$LAN_IP</div>
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
                        <p style="color:var(--s); font-size:0.9rem;">Odido integration not configured. Add your credentials to enable automatic data top-ups.</p>
                    </div>
                    <div id="odido-configured" style="display:none;">
                        <div class="stat-row"><span>Data Remaining</span><span class="stat-val" id="odido-remaining">--</span></div>
                        <div class="stat-row"><span>Threshold</span><span class="stat-val" id="odido-threshold">--</span></div>
                        <div class="stat-row"><span>Bundle Code</span><span class="stat-val" id="odido-bundle-code">--</span></div>
                        <div class="data-bar"><div class="data-bar-fill" id="odido-bar" style="width:0%"></div></div>
                        <div style="text-align:center; margin-top:16px;">
                            <button onclick="buyOdidoBundle()" class="btn odido-buy" id="odido-buy-btn">Buy Bundle Now</button>
                        </div>
                        <div id="odido-buy-status" style="margin-top:10px; font-size:0.85rem; text-align:center;"></div>
                    </div>
                    <div id="odido-loading" style="color:var(--s);">Loading...</div>
                </div>
            </div>
            <div class="card">
                <h3>Configuration</h3>
                <input type="text" id="odido-user-id" class="input-field" placeholder="User ID" style="margin-bottom:12px;">
                <input type="password" id="odido-token" class="input-field" placeholder="Access Token" style="margin-bottom:12px;">
                <input type="text" id="odido-bundle-code-input" class="input-field" placeholder="Bundle Code (e.g., A0DAY01)" style="margin-bottom:12px;">
                <input type="number" id="odido-threshold-input" class="input-field" placeholder="Threshold MB (default: 350)" style="margin-bottom:12px;">
                <div style="text-align:right;">
                    <button onclick="saveOdidoConfig()" class="btn secondary">Save Configuration</button>
                </div>
                <div id="odido-config-status" style="margin-top:10px; font-size:0.85rem; color:var(--p);"></div>
            </div>
        </div>

        <div class="section-label">WireGuard Profiles</div>
        <div class="grid-2">
            <div class="card">
                <h3>Upload Profile</h3>
                <input type="text" id="prof-name" class="input-field" placeholder="Optional: Custom Name" style="margin-bottom:12px;">
                <textarea id="prof-conf" class="input-field" placeholder="Paste .conf content here..."></textarea>
                <div style="text-align:right;"><button onclick="uploadProfile()" class="btn">Upload & Activate</button></div>
                <div id="upload-status" style="margin-top:10px; font-size:0.85rem; color:var(--p);"></div>
            </div>
            <div class="card">
                <h3>Manage Profiles</h3>
                <div id="profile-list">Loading...</div>
                <p style="font-size:0.8rem; color:#888; margin-top:16px;">Click name to activate.</p>
            </div>
        </div>

        <div class="section-label">System Status & Logs</div>
        <div class="grid-2">
            <div class="card">
                <h3>Gluetun (Frontend Proxy)</h3>
                <div class="stat-row"><span>Status</span><span class="stat-val" id="vpn-status">--</span></div>
                <div class="stat-row"><span>Active Profile</span><span class="stat-val active-prof" id="vpn-active">--</span></div>
                <div class="stat-row"><span>VPN Endpoint</span><span class="stat-val" id="vpn-endpoint">--</span></div>
                <div class="stat-row"><span>Public IP</span><span class="stat-val" id="vpn-public-ip">--</span></div>
                <div class="stat-row"><span>Last Handshake</span><span class="stat-val" id="vpn-handshake">--</span></div>
                <div class="stat-row"><span>Data (RX / TX)</span><span class="stat-val"><span id="vpn-rx">0</span> / <span id="vpn-tx">0</span></span></div>
            </div>
            <div class="card">
                <h3>WG-Easy (External Access)</h3>
                <div class="stat-row"><span>Service Status</span><span class="stat-val" id="wge-status">--</span></div>
                <div class="stat-row"><span>External IP</span><span class="stat-val" id="wge-host">--</span></div>
                <div class="stat-row"><span>UDP Port</span><span class="stat-val">51820</span></div>
                <div class="stat-row"><span>Total Clients</span><span class="stat-val" id="wge-clients">--</span></div>
                <div class="stat-row"><span>Connected Now</span><span class="stat-val" id="wge-connected">--</span></div>
            </div>
        </div>
        <div class="grid">
            <div class="card full-width">
                <h3>Deployment History</h3>
                <div id="log-container" class="log-box"></div>
                <div id="log-status" style="font-size:0.8rem; color:var(--s); text-align:right; margin-top:5px;">Connecting...</div>
            </div>
        </div>
    </div>

    <script>
        const API = "/api";
        
        async function fetchStatus() {
            try {
                const res = await fetch(\`\\${API}/status\`);
                const data = await res.json();
                const g = data.gluetun;
                const vpnStatus = document.getElementById('vpn-status');
                if (g.status === "up" && g.healthy) {
                    vpnStatus.textContent = "Connected (Healthy)";
                    vpnStatus.style.color = "var(--ok)";
                } else if (g.status === "up") {
                    vpnStatus.textContent = "Connected";
                    vpnStatus.style.color = "var(--ok)";
                } else {
                    vpnStatus.textContent = "Disconnected";
                    vpnStatus.style.color = "var(--err)";
                }
                document.getElementById('vpn-active').textContent = g.active_profile || "Unknown";
                document.getElementById('vpn-endpoint').textContent = g.endpoint || "--";
                document.getElementById('vpn-public-ip').textContent = g.public_ip || "--";
                document.getElementById('vpn-handshake').textContent = g.handshake_ago || "Never";
                document.getElementById('vpn-rx').textContent = formatBytes(g.rx);
                document.getElementById('vpn-tx').textContent = formatBytes(g.tx);
                const w = data.wgeasy;
                const wgeStat = document.getElementById('wge-status');
                wgeStat.textContent = (w.status === "up") ? "Running" : "Stopped";
                wgeStat.style.color = (w.status === "up") ? "var(--ok)" : "var(--err)";
                document.getElementById('wge-host').textContent = w.host || "--";
                document.getElementById('wge-clients').textContent = w.clients || "0";
                const wgeConnected = document.getElementById('wge-connected');
                const connectedCount = parseInt(w.connected) || 0;
                wgeConnected.textContent = connectedCount > 0 ? \`\\\${connectedCount} active\` : "None";
                wgeConnected.style.color = connectedCount > 0 ? "var(--ok)" : "var(--s)";
            } catch(e) { console.error('Status fetch error:', e); }
        }
        
        async function fetchOdidoStatus() {
            try {
                const res = await fetch(\`\\${API}/odido/status\`);
                const data = await res.json();
                document.getElementById('odido-loading').style.display = 'none';
                if (!data.enabled || !data.configured) {
                    document.getElementById('odido-not-configured').style.display = 'block';
                    document.getElementById('odido-configured').style.display = 'none';
                } else {
                    document.getElementById('odido-not-configured').style.display = 'none';
                    document.getElementById('odido-configured').style.display = 'block';
                    const remaining = data.remaining_mb || 0;
                    const threshold = data.threshold || 350;
                    document.getElementById('odido-remaining').textContent = \`\\${remaining} MB\`;
                    document.getElementById('odido-threshold').textContent = \`\\${threshold} MB\`;
                    document.getElementById('odido-bundle-code').textContent = data.bundle_code || 'A0DAY01';
                    const maxData = 2048;
                    const percent = Math.min(100, (remaining / maxData) * 100);
                    const bar = document.getElementById('odido-bar');
                    bar.style.width = \`\\\${percent}%\`;
                    bar.className = 'data-bar-fill';
                    if (remaining < threshold) bar.classList.add('critical');
                    else if (remaining < threshold * 2) bar.classList.add('low');
                }
            } catch(e) {
                document.getElementById('odido-loading').textContent = 'Error loading status';
            }
        }
        
        async function saveOdidoConfig() {
            const st = document.getElementById('odido-config-status');
            const data = {};
            const userId = document.getElementById('odido-user-id').value.trim();
            const token = document.getElementById('odido-token').value.trim();
            const bundleCode = document.getElementById('odido-bundle-code-input').value.trim();
            const threshold = document.getElementById('odido-threshold-input').value.trim();
            if (userId) data.user_id = userId;
            if (token) data.token = token;
            if (bundleCode) data.bundle_code = bundleCode;
            if (threshold) data.threshold = parseInt(threshold);
            if (Object.keys(data).length === 0) {
                st.textContent = 'Please fill in at least one field';
                st.style.color = 'var(--err)';
                return;
            }
            st.textContent = 'Saving...';
            st.style.color = 'var(--p)';
            try {
                const res = await fetch(\`\\${API}/odido/config\`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(data)
                });
                const result = await res.json();
                if (result.error) throw new Error(result.error);
                st.textContent = 'Configuration saved!';
                st.style.color = 'var(--ok)';
                document.getElementById('odido-user-id').value = '';
                document.getElementById('odido-token').value = '';
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
            st.textContent = 'Purchasing bundle...';
            st.style.color = 'var(--p)';
            try {
                const res = await fetch(\`\\${API}/odido/buy\`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({})
                });
                const result = await res.json();
                if (result.error) throw new Error(result.error);
                st.textContent = 'Bundle purchased successfully!';
                st.style.color = 'var(--ok)';
                setTimeout(fetchOdidoStatus, 2000);
            } catch(e) {
                st.textContent = e.message;
                st.style.color = 'var(--err)';
            }
            btn.disabled = false;
        }
        
        async function fetchProfiles() {
            try {
                const res = await fetch(\`\\${API}/profiles\`);
                const data = await res.json();
                const el = document.getElementById('profile-list');
                el.innerHTML = '';
                data.profiles.forEach(p => {
                    const row = document.createElement('div');
                    row.className = 'profile-row';
                    row.innerHTML = \`
                        <span class="profile-name" onclick="activateProfile('\\${p}')">\\${p}</span>
                        <button class="btn del" onclick="deleteProfile('\\${p}')" title="Delete">
                           <svg viewBox="0 0 24 24"><path d="M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z"/></svg>
                        </button>\`;
                    el.appendChild(row);
                });
            } catch(e) {}
        }
        
        async function uploadProfile() {
            const nameInput = document.getElementById('prof-name').value;
            const config = document.getElementById('prof-conf').value;
            const st = document.getElementById('upload-status');
            if(!config) { st.textContent="Error: Config content missing"; return; }
            st.textContent = "Uploading...";
            try {
                const upRes = await fetch(\`\\${API}/upload\`, { method:'POST', body:JSON.stringify({name: nameInput, config}) });
                const upData = await upRes.json();
                if(upData.error) throw new Error(upData.error);
                const finalName = upData.name;
                st.textContent = \`Activating \\${finalName}...\`;
                await fetch(\`\\${API}/activate\`, { method:'POST', body:JSON.stringify({name: finalName}) });
                st.textContent = "Success! VPN restarting.";
                fetchProfiles(); document.getElementById('prof-name').value=""; document.getElementById('prof-conf').value="";
            } catch(e) { st.textContent = e.message; }
        }
        
        async function activateProfile(name) {
            if(!confirm(\`Switch to \\${name}?\`)) return;
            try { await fetch(\`\\${API}/activate\`, { method:'POST', body:JSON.stringify({name}) }); alert("Profile switched. VPN restarting."); } catch(e) { alert("Error"); }
        }
        
        async function deleteProfile(name) {
            if(!confirm(\`Delete \\${name}?\`)) return;
            try { await fetch(\`\\${API}/delete\`, { method:'POST', body:JSON.stringify({name}) }); fetchProfiles(); } catch(e) { alert("Error"); }
        }
        
        function startLogStream() {
            const el = document.getElementById('log-container');
            const status = document.getElementById('log-status');
            const evtSource = new EventSource(\`\\${API}/events\`);
            evtSource.onmessage = function(e) {
                const div = document.createElement('div');
                div.className = 'log-line';
                div.textContent = e.data;
                el.appendChild(div);
                el.scrollTop = el.scrollHeight;
            };
            evtSource.onopen = function() { status.textContent = "Live"; status.style.color = "var(--ok)"; };
            evtSource.onerror = function() { status.textContent = "Reconnecting..."; status.style.color = "var(--err)"; evtSource.close(); setTimeout(startLogStream, 3000); };
        }
        
        function formatBytes(a,b=2){if(!+a)return"0 B";const c=0>b?0:b,d=Math.floor(Math.log(a)/Math.log(1024));return\`\\${parseFloat((a/Math.pow(1024,d)).toFixed(c))} \${["B","KiB","MiB","GiB","TiB"][d]}\`}
        
        document.addEventListener('DOMContentLoaded', () => {
            fetchStatus(); fetchProfiles(); fetchOdidoStatus(); startLogStream();
            setInterval(fetchStatus, 5000);
            setInterval(fetchOdidoStatus, 30000);
            document.querySelectorAll('.card[data-check="true"]').forEach(c => {
                const url = c.href; const dot = c.querySelector('.dot'); const txt = c.querySelector('.status-text');
                fetch(url, { mode: 'no-cors', cache: 'no-store' })
                    .then(() => { dot.classList.add('up'); dot.classList.remove('down'); txt.textContent = "Online"; })
                    .catch(() => { dot.classList.add('down'); dot.classList.remove('up'); txt.textContent = "Offline"; });
            });
        });
    </script>
</body>
</html>
EOF

# --- 15. IP MONITOR ---
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

# --- 16. START ---
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
echo "DEPLOYMENT COMPLETE V3.9"
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
echo "  ✓ All DNS services accessible via local network or VPN"
echo "  ✓ No direct DNS exposure - requires VPN authentication"
echo "  ✓ Fully recursive DNS (no third-party upstream)"
echo "  ✓ Filter updates every 6 hours"
echo ""
if [ "$AUTO_PASSWORD" = true ]; then
    echo "=========================================================="
    echo "AUTO-GENERATED CREDENTIALS"
    echo "=========================================================="
    echo "VPN Web UI Password: $VPN_PASS_RAW"
    echo "AdGuard Home Password: $AGH_PASS_RAW"
    echo "AdGuard Home Username: adguard"
    echo ""
    echo "IMPORTANT: Save these credentials securely!"
    echo "They are also stored in: $BASE_DIR/.secrets"
    echo ""
fi
echo "=========================================================="
