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
