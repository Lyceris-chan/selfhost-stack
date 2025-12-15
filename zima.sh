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

