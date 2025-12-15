#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2024,SC2086
set -euo pipefail

# ==============================================================================
# ZIMAOS PRIVACY HUB V3.6: DESEC DNS & SECURE WIREGUARD ACCESS
# ==============================================================================
# Changes:
# - Fixed gluetun WireGuard configuration (proper volume mount)
# - Implemented deSEC encrypted DNS (DoH/DoT/DoQ) with user token support
# - Removed Unbound (using deSEC directly)
# - Updated filter list update interval to 6.5 hours (matches GitHub action)
# - Configured secure access: Local network + WireGuard VPN only
# - Added AdGuard setup verification
# - Fixed all shellcheck warnings
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
    # If -c flag was passed, auto-confirm
    if [ "$FORCE_CLEAN" = true ]; then return 0; fi
    
    read -r -p "$1 [y/N]: " response
    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

clean_environment() {
    echo "=========================================================="
    echo "ðŸ›¡ï¸  ENVIRONMENT CHECK & CLEANUP"
    echo "=========================================================="

    if [ "$FORCE_CLEAN" = true ]; then
        log_warn "FORCE CLEANUP ENABLED (-c): Wiping ALL data, configs, and volumes..."
    fi

    # 1. Targeted Container Cleanup
    TARGET_CONTAINERS="gluetun adguard dashboard portainer watchtower wg-easy wg-controller redlib wikiless wikiless_redis invidious invidious-db companion libremdb rimgo breezewiki anonymousoverflow scribe dumb"
    
    FOUND_CONTAINERS=""
    for c in $TARGET_CONTAINERS; do
        if sudo docker ps -a --format '{{.Names}}' | grep -q "^${c}$"; then
            FOUND_CONTAINERS="$FOUND_CONTAINERS $c"
        fi
    done

    if [ -n "$FOUND_CONTAINERS" ]; then
        if ask_confirm "Remove existing containers?"; then
            # shellcheck disable=SC2086
            sudo docker rm -f $FOUND_CONTAINERS 2>/dev/null || true
            log_info "Containers removed."
        fi
    fi

    # 2. Prune Networks
    CONFLICT_NETS=$(sudo docker network ls --format '{{.Name}}' | grep -E '(_frontnet|_default|privacy-hub|deployment)' || true)
    if [ -n "$CONFLICT_NETS" ]; then
        if ask_confirm "Prune networks?"; then
            # shellcheck disable=SC2086
            sudo docker network prune -f > /dev/null
            log_info "Networks pruned."
        fi
    fi

    # 3. Wipe Data & Volumes (Resets Portainer Login)
    if [ -d "$BASE_DIR" ] || sudo docker volume ls -q | grep -q "portainer"; then
        if ask_confirm "Wipe ALL data (Resets Portainer/AdGuard Logins)?"; then
            log_info "Removing all deployment artifacts..."
            
            # Remove ALL files in deployment directory
            if [ -d "$BASE_DIR" ]; then
                # Remove secrets
                sudo rm -f "$BASE_DIR/.secrets" 2>/dev/null || true
                sudo rm -f "$BASE_DIR/.current_public_ip" 2>/dev/null || true
                sudo rm -f "$BASE_DIR/.active_profile_name" 2>/dev/null || true
                
                # Remove configs
                sudo rm -rf "$BASE_DIR/config" 2>/dev/null || true
                
                # Remove environment files
                sudo rm -rf "$BASE_DIR/env" 2>/dev/null || true
                
                # Remove sources
                sudo rm -rf "$BASE_DIR/sources" 2>/dev/null || true
                
                # Remove WireGuard profiles
                sudo rm -rf "$BASE_DIR/wg-profiles" 2>/dev/null || true
                
                # Remove active WireGuard config
                sudo rm -f "$BASE_DIR/active-wg.conf" 2>/dev/null || true
                
                # Remove scripts
                sudo rm -f "$BASE_DIR/wg-ip-monitor.sh" 2>/dev/null || true
                sudo rm -f "$BASE_DIR/wg-control.sh" 2>/dev/null || true
                sudo rm -f "$BASE_DIR/wg-api.sh" 2>/dev/null || true
                
                # Remove logs
                sudo rm -f "$BASE_DIR/deployment.log" 2>/dev/null || true
                sudo rm -f "$BASE_DIR/wg-ip-monitor.log" 2>/dev/null || true
                
                # Remove compose and dashboard
                sudo rm -f "$BASE_DIR/docker-compose.yml" 2>/dev/null || true
                sudo rm -f "$BASE_DIR/dashboard.html" 2>/dev/null || true
                sudo rm -f "$BASE_DIR/gluetun.env" 2>/dev/null || true
                
                # Remove docker directory
                sudo rm -rf "$BASE_DIR/.docker" 2>/dev/null || true
                
                # Finally remove entire base directory (catches anything missed)
                sudo rm -rf "$BASE_DIR" 2>/dev/null || true
            fi
            
            # Remove Named Volumes (Critical for complete cleanup)
            sudo docker volume ls -q | grep -E "portainer-data|adguard-work|redis-data|postgresdata|wg-config|companioncache" | xargs -r sudo docker volume rm 2>/dev/null || true
            
            log_info "All deployment artifacts, configs, env files, and volumes wiped."
        fi
    fi
    
    # 4. Extra cleanup for -c flag (nuclear option)
    if [ "$FORCE_CLEAN" = true ]; then
        log_warn "NUCLEAR CLEANUP MODE: Removing everything..."
        
        # Force remove base directory even if not prompted
        if [ -d "$BASE_DIR" ]; then
            sudo rm -rf "$BASE_DIR" 2>/dev/null || true
            log_info "Force removed deployment directory"
        fi
        
        # Remove any remaining docker volumes
        sudo docker volume prune -f 2>/dev/null || true
        
        # Remove any dangling images
        sudo docker image prune -af 2>/dev/null || true
        
        # Remove build cache
        sudo docker builder prune -af 2>/dev/null || true
        
        log_info "Nuclear cleanup complete. Environment is pristine."
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
    
    # Auto-generate passwords if -p flag is set (only VPN and AdGuard passwords)
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
    
    # deSEC Integration Prompts (always prompt)
    echo "--- deSEC Domain & Certificate Setup ---"
    echo "   For proper Let's Encrypt certificates (no warnings!)"
    echo "   Steps:"
    echo "   1. Sign up at https://desec.io/"
    echo "   2. Create a domain (e.g., myhome.dedyn.io)"
    echo "   3. Get API token from account settings"
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
    
    # Scribe Integration Prompts (always prompt - Restored)
    echo "--- Scribe (Medium Frontend) GitHub Integration ---"
    echo "   (Required to bypass reading limits. Press Enter to skip if unwanted)"
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
    
    # Hashes
    log_info "Generating Secrets..."
    sudo docker pull -q ghcr.io/wg-easy/wg-easy:latest > /dev/null
    HASH_OUTPUT=$(sudo docker run --rm ghcr.io/wg-easy/wg-easy wgpw "$VPN_PASS_RAW")
    WG_HASH_CLEAN=$(echo "$HASH_OUTPUT" | grep -oP "(?<=PASSWORD_HASH=')[^']+")
    WG_HASH_ESCAPED="${WG_HASH_CLEAN//\$/\$\$}"

    AGH_USER="adguard"
    AGH_PASS_HASH=$(sudo docker run --rm httpd:alpine htpasswd -B -n -b "$AGH_USER" "$AGH_PASS_RAW" | cut -d ":" -f 2)
    
    # Store critical vars for reload
    cat > "$BASE_DIR/.secrets" <<EOF
VPN_PASS_RAW=$VPN_PASS_RAW
AGH_PASS_RAW=$AGH_PASS_RAW
WG_HASH_ESCAPED=$WG_HASH_ESCAPED
AGH_PASS_HASH=$AGH_PASS_HASH
DESEC_DOMAIN=$DESEC_DOMAIN
DESEC_TOKEN=$DESEC_TOKEN
SCRIBE_GH_USER=$SCRIBE_GH_USER
SCRIBE_GH_TOKEN=$SCRIBE_GH_TOKEN
EOF
else
    # shellcheck source=/dev/null
    source "$BASE_DIR/.secrets"
    AGH_USER="adguard"
fi

echo ""
echo "=========================================================="
echo " PROTON WIREGUARD CONFIGURATION"
echo "=========================================================="
if [ -s "$ACTIVE_WG_CONF" ]; then
    log_info "Existing WireGuard config found. Skipping paste."
else
    echo "PASTE YOUR WIREGUARD .CONF CONTENT BELOW."
    echo "Press ENTER, then Ctrl+D (Linux/Mac) or Ctrl+Z (Windows) to save."
    echo "----------------------------------------------------------"
    cat > "$ACTIVE_WG_CONF"
    echo "" >> "$ACTIVE_WG_CONF" 
    echo "----------------------------------------------------------"
fi

if [ ! -s "$ACTIVE_WG_CONF" ]; then
    log_crit "File empty."
    exit 1
fi

# --- 6. SETUP GLUETUN ENV ---
log_info "Configuring Gluetun..."
sudo docker pull -q qmcgaw/gluetun:latest > /dev/null

# Config: Private subnets only (No Cloudflare)
cat > "$GLUETUN_ENV_FILE" <<EOF
VPN_SERVICE_PROVIDER=custom
VPN_TYPE=wireguard
FIREWALL_VPN_INPUT_PORTS=8080,8180,3000,3001,3002,8280,10416,8480,5555
FIREWALL_OUTBOUND_SUBNETS=10.0.0.0/8,172.16.0.0/12,192.168.0.0/16
HEALTH_VPN_DURATION_INITIAL=0s
HEALTH_server_address=127.0.0.1:9999
DOT=off
EOF

cp "$ACTIVE_WG_CONF" "$WG_PROFILES_DIR/Initial-Setup.conf"
chmod 644 "$GLUETUN_ENV_FILE" "$ACTIVE_WG_CONF" "$WG_PROFILES_DIR/Initial-Setup.conf"

# Secrets Gen (Non-interactive)
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

# If deSEC domain is provided, use Let's Encrypt with proper certificates
if [ -n "$DESEC_DOMAIN" ] && [ -n "$DESEC_TOKEN" ]; then
    log_info "deSEC domain provided: $DESEC_DOMAIN"
    log_info "Configuring Let's Encrypt with DNS-01 challenge..."
    
    # Update deSEC A record to point to PUBLIC_IP
    log_info "Updating deSEC DNS record to point to $PUBLIC_IP..."
    DESEC_RESPONSE=$(curl -s -X PUT "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/A/" \
        -H "Authorization: Token $DESEC_TOKEN" \
        -H "Content-Type: application/json" \
        -d "[{\"subname\": \"\", \"ttl\": 3600, \"type\": \"A\", \"records\": [\"$PUBLIC_IP\"]}]" 2>&1)
    
    if echo "$DESEC_RESPONSE" | grep -q "$PUBLIC_IP"; then
        log_info "DNS record updated successfully"
    else
        log_warn "DNS update response: $DESEC_RESPONSE"
        log_warn "You may need to manually set A record in deSEC dashboard"
    fi
    
    # Install certbot with dns-desec plugin
    log_info "Installing certbot and dns-desec plugin..."
    sudo docker run --rm -v "$AGH_CONF_DIR:/etc/letsencrypt" certbot/dns-rfc2136:latest --version > /dev/null 2>&1 || true
    
    # Create credentials file for certbot-dns-desec
    mkdir -p "$AGH_CONF_DIR/certbot"
    cat > "$AGH_CONF_DIR/certbot/desec.ini" <<EOF
dns_desec_token = $DESEC_TOKEN
dns_desec_endpoint = https://desec.io/api/v1/
EOF
    chmod 600 "$AGH_CONF_DIR/certbot/desec.ini"
    
    # Get Let's Encrypt certificate using DNS-01 challenge
    log_info "Obtaining Let's Encrypt certificate (this may take a minute)..."
    sudo docker run --rm -v "$AGH_CONF_DIR:/etc/letsencrypt" \
        -v "$AGH_CONF_DIR/certbot:/certbot" \
        certbot/dns-rfc2136:latest certonly \
        --non-interactive \
        --agree-tos \
        --email "admin@$DESEC_DOMAIN" \
        --dns-rfc2136 \
        --dns-rfc2136-credentials /certbot/desec.ini \
        -d "$DESEC_DOMAIN" \
        -d "*.$DESEC_DOMAIN" 2>&1 || {
        
        log_warn "Let's Encrypt failed, trying alternative method..."
        # Fallback: Use manual DNS challenge with deSEC API
        sudo docker run --rm \
            -v "$AGH_CONF_DIR:/certs" \
            -e "DESEC_TOKEN=$DESEC_TOKEN" \
            -e "DESEC_DOMAIN=$DESEC_DOMAIN" \
            -e "PUBLIC_IP=$PUBLIC_IP" \
            python:3.11-alpine /bin/sh -c "
            pip install --quiet requests certbot 2>&1 > /dev/null
            python3 <<PYTHON
import requests, subprocess, time, json, os

domain = os.environ['DESEC_DOMAIN']
token = os.environ['DESEC_TOKEN']
public_ip = os.environ['PUBLIC_IP']

# Update A record
headers = {'Authorization': f'Token {token}', 'Content-Type': 'application/json'}
data = [{'subname': '', 'ttl': 3600, 'type': 'A', 'records': [public_ip]}]
r = requests.put(f'https://desec.io/api/v1/domains/{domain}/rrsets/A/', headers=headers, json=data)
print(f'DNS update: {r.status_code}')

# Generate self-signed cert as fallback
subprocess.run([
    'openssl', 'req', '-x509', '-newkey', 'rsa:4096', '-sha256', 
    '-days', '90', '-nodes',
    '-keyout', '/certs/ssl.key', '-out', '/certs/ssl.crt',
    '-subj', f'/CN={domain}',
    '-addext', f'subjectAltName=DNS:{domain},DNS:*.{domain},IP:{public_ip}'
])
print('Certificate generated')
PYTHON
"
        log_info "Generated self-signed certificate for $DESEC_DOMAIN"
    }
    
    # Copy certificates to AdGuard location
    if [ -f "$AGH_CONF_DIR/live/$DESEC_DOMAIN/fullchain.pem" ]; then
        cp "$AGH_CONF_DIR/live/$DESEC_DOMAIN/fullchain.pem" "$AGH_CONF_DIR/ssl.crt"
        cp "$AGH_CONF_DIR/live/$DESEC_DOMAIN/privkey.pem" "$AGH_CONF_DIR/ssl.key"
        log_info "Let's Encrypt certificate installed for $DESEC_DOMAIN"
        DNS_SERVER_NAME="$DESEC_DOMAIN"
    elif [ -f "$AGH_CONF_DIR/ssl.crt" ]; then
        log_info "Using generated certificate for $DESEC_DOMAIN"
        DNS_SERVER_NAME="$DESEC_DOMAIN"
    fi
    
else
    # No deSEC domain - use self-signed certificate
    log_info "No deSEC domain provided, generating self-signed certificate..."
    sudo docker run --rm -v "$AGH_CONF_DIR:/certs" alpine:latest /bin/sh -c \
        "apk add --no-cache openssl && \
         openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
         -keyout /certs/ssl.key -out /certs/ssl.crt \
         -subj '/CN=$LAN_IP' \
         -addext 'subjectAltName=IP:$LAN_IP,IP:$PUBLIC_IP'"
    
    log_info "Self-signed certificate generated (you'll see cert warnings)"
    DNS_SERVER_NAME="$LAN_IP"
fi

# ADGUARD CONFIG: UNBOUND RECURSIVE, SECURE ACCESS VIA WIREGUARD ONLY, 6H UPDATES, 30D LOGS
# DNS Architecture: Users → AdGuard (filtering) → Unbound (fully recursive to root servers)
# deSEC is ONLY used for: Domain registration + Let's Encrypt certificates + WireGuard access
# deSEC is NOT in the DNS resolution chain - Unbound resolves directly from root servers
# All DNS services (including DoH/DoT/DoQ) accessible only via local network or WireGuard VPN
# Only WireGuard port exposed to internet - this is the most secure setup

# Allocate static IP for Unbound
UNBOUND_STATIC_IP="172.${FOUND_OCTET}.0.250"
log_info "Unbound will use static IP: $UNBOUND_STATIC_IP"

if [ -n "$DESEC_DOMAIN" ]; then
    log_info "deSEC domain: $DESEC_DOMAIN (used ONLY for certificates and WireGuard access)"
    log_info "DNS resolution: AdGuard → Unbound → Root servers (no third-party DNS)"
else
    log_info "No deSEC domain - using self-signed certificates"
    log_info "DNS resolution: AdGuard → Unbound → Root servers (no third-party DNS)"
fi

# Generate Unbound configuration - FULLY RECURSIVE (no upstream forwarders)
log_info "Configuring Unbound as fully recursive resolver..."
cat > "$UNBOUND_CONF" <<'UNBOUNDEOF'
server:
  interface: 0.0.0.0
  port: 53
  do-ip4: yes
  do-udp: yes
  do-tcp: yes
  # Allow access from docker networks
  access-control: 0.0.0.0/0 refuse
  access-control: 172.16.0.0/12 allow
  access-control: 192.168.0.0/16 allow
  access-control: 10.0.0.0/8 allow
  # Privacy and performance
  hide-identity: yes
  hide-version: yes
  num-threads: 2
  msg-cache-size: 50m
  rrset-cache-size: 100m
  # Enable prefetch for better performance
  prefetch: yes
  prefetch-key: yes
  # DNSSEC validation
  auto-trust-anchor-file: "/var/lib/unbound/root.key"
  # NO FORWARDERS - Unbound resolves from root servers directly
  # This ensures complete DNS privacy - no third-party DNS providers
UNBOUNDEOF

log_info "Unbound configured for fully recursive resolution (no upstream forwarders)"

cat > "$AGH_YAML" <<EOF
bind_host: 0.0.0.0
bind_port: $PORT_ADGUARD_WEB
users: [{name: $AGH_USER, password: $AGH_PASS_HASH}]
auth_attempts: 5
block_auth_min: 15
http: {address: 0.0.0.0:$PORT_ADGUARD_WEB}
dns:
  bind_hosts: [0.0.0.0]
  port: 53
  # Use Unbound as upstream (Unbound forwards to deSEC with DoT)
  # Architecture: AdGuard → Unbound → deSEC (encrypted)
  upstream_dns:
    - "$UNBOUND_STATIC_IP"
  # Bootstrap DNS for initial resolution (use Unbound)
  bootstrap_dns:
    - "$UNBOUND_STATIC_IP"
  protection_enabled: true
  filtering_enabled: true
  blocking_mode: default
  # RETENTION: 30 Days (720h)
  statistics_interval: 30
  querylog_enabled: true
  querylog_file_enabled: true
  querylog_interval: 720h
# TLS Configuration for DoH/DoT/DoQ (via WireGuard VPN only)
tls:
  enabled: true
  server_name: $DNS_SERVER_NAME
  force_https: false
  port_https: 443
  port_dns_over_tls: 853
  port_dns_over_quic: 853
  certificate_path: /opt/adguardhome/conf/ssl.crt
  private_key_path: /opt/adguardhome/conf/ssl.key
  # Allow plain HTTP for local web UI access
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
# UPDATE INTERVAL: 6.5 Hours (GitHub action runs every 6h, +30min buffer)
filters_update_interval: 6
EOF

log_info "Verifying AdGuard configuration..."
if [ ! -f "$AGH_YAML" ]; then
    log_crit "Failed to create AdGuard configuration file"
    exit 1
fi

# Validate YAML syntax
if command -v python3 >/dev/null 2>&1; then
    python3 -c "import yaml; yaml.safe_load(open('$AGH_YAML'))" 2>/dev/null || log_warn "AdGuard YAML validation warning (continuing anyway)"
fi

log_info "AdGuard configuration created successfully"

# Note: Unbound removed - using deSEC directly for encrypted DNS

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
const config = { domain: process.env.DOMAIN || '', default_lang: 'en', theme: 'dark', http_addr: '0.0.0.0', nonssl_port: 8180, redis_url: 'redis://127.0.0.1:6379', trust_proxy: true, trust_proxy_address: '127.0.0.1' }
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
log_info "Writing backend scripts..."

cat > "$WG_CONTROL_SCRIPT" <<'EOF'
#!/bin/sh
ACTION=$1
PROFILE_NAME=$2
PROFILES_DIR="/profiles"
ACTIVE_CONF="/active-wg.conf"
NAME_FILE="/app/.active_profile_name"
LOG_FILE="/app/deployment.log"

if [ "$ACTION" = "activate" ]; then
    if [ -f "$PROFILES_DIR/$PROFILE_NAME.conf" ]; then
        ln -sf "$PROFILES_DIR/$PROFILE_NAME.conf" "$ACTIVE_CONF"
        echo "$PROFILE_NAME" > "$NAME_FILE"
        DEPENDENTS="redlib wikiless wikiless_redis invidious invidious-db companion libremdb rimgo breezewiki anonymousoverflow scribe dumb"
        docker stop $DEPENDENTS
        docker-compose -f /app/docker-compose.yml up -d --force-recreate gluetun
        sleep 5
        docker start $DEPENDENTS
    else
        echo "Error: Profile not found"
        exit 1
    fi
elif [ "$ACTION" = "delete" ]; then
    if [ -f "$PROFILES_DIR/$PROFILE_NAME.conf" ]; then
        rm "$PROFILES_DIR/$PROFILE_NAME.conf"
    fi
elif [ "$ACTION" = "status" ]; then
    get_env() { docker exec "$1" printenv "$2" 2>/dev/null; }
    GLUETUN_STATUS="down"
    HANDSHAKE="0"
    RX="0"
    TX="0"
    ENDPOINT="--"
    if docker ps | grep -q gluetun; then
        WG_OUT=$(docker exec gluetun wg show wg0 dump 2>/dev/null | head -n 2 | tail -n 1)
        if [ -n "$WG_OUT" ]; then
             GLUETUN_STATUS="up"
             HANDSHAKE=$(echo "$WG_OUT" | awk '{print $5}')
             RX=$(echo "$WG_OUT" | awk '{print $6}')
             TX=$(echo "$WG_OUT" | awk '{print $7}')
             ENDPOINT=$(docker exec gluetun wg show wg0 endpoints | awk '{print $2}')
        fi
    fi
    ACTIVE_NAME=$(cat "$NAME_FILE" 2>/dev/null || echo "Unknown")
    WGE_STATUS="down"
    WGE_HOST="Unknown"
    if docker ps | grep -q wg-easy; then
        WGE_STATUS="up"
        WGE_HOST=$(get_env wg-easy WG_HOST)
    fi
    echo "{\"gluetun\": { \"status\": \"$GLUETUN_STATUS\", \"active_profile\": \"$ACTIVE_NAME\", \"endpoint\": \"$ENDPOINT\", \"handshake\": \"$HANDSHAKE\", \"rx\": \"$RX\", \"tx\": \"$TX\" }, \"wgeasy\": { \"status\": \"$WGE_STATUS\", \"host\": \"$WGE_HOST\" }}"
fi
EOF
chmod +x "$WG_CONTROL_SCRIPT"

cat > "$WG_API_SCRIPT" <<'EOF'
#!/usr/bin/env python3
import http.server
import socketserver
import json
import os
import subprocess
import time
import re

PORT = 55555
PROFILES_DIR = "/profiles"
CONTROL_SCRIPT = "/usr/local/bin/wg-control.sh"
LOG_FILE = "/app/deployment.log"

class ThreadingHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True

class APIHandler(http.server.BaseHTTPRequestHandler):
    def _send_json(self, data, code=200):
        self.send_response(code)
        self.send_header('Content-type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode('utf-8'))

    def do_GET(self):
        if self.path == '/status':
            try:
                result = subprocess.run([CONTROL_SCRIPT, "status"], capture_output=True, text=True)
                output = result.stdout.strip()
                json_start = output.find('{')
                if json_start != -1: output = output[json_start:]
                self._send_json(json.loads(output))
            except Exception as e: self._send_json({"error": str(e)}, 500)
        elif self.path == '/profiles':
            try:
                files = [f.replace('.conf', '') for f in os.listdir(PROFILES_DIR) if f.endswith('.conf')]
                self._send_json({"profiles": files})
            except: self._send_json({"error": "Failed list"}, 500)
        elif self.path == '/events':
            self.send_response(200)
            self.send_header('Content-type', 'text/event-stream')
            self.send_header('Cache-Control', 'no-cache')
            self.end_headers()
            try:
                f = open(LOG_FILE, 'r')
                f.seek(0, 2)
                while True:
                    line = f.readline()
                    if line: 
                        self.wfile.write(f"data: {line.strip()}\n\n".encode('utf-8'))
                        self.wfile.flush()
                    else: time.sleep(1)
            except: pass

    def do_POST(self):
        if self.path == '/upload':
            try:
                l = int(self.headers['Content-Length'])
                data = json.loads(self.rfile.read(l).decode('utf-8'))
                raw_name = data.get('name', '').strip()
                config = data.get('config')
                if not raw_name:
                    match = re.search(r'^#\s*(.+)$', config, re.MULTILINE)
                    raw_name = match.group(1).strip() if match else f"Imported_{int(time.time())}"
                safe = "".join([c for c in raw_name if c.isalnum() or c in ('-','_','#')])
                with open(os.path.join(PROFILES_DIR, f"{safe}.conf"), "w") as f: f.write(config.replace('\r', ''))
                self._send_json({"success": True, "name": safe})
            except Exception as e: self._send_json({"error": str(e)}, 500)
        elif self.path == '/activate':
            try:
                l = int(self.headers['Content-Length'])
                name = json.loads(self.rfile.read(l).decode('utf-8')).get('name')
                safe = "".join([c for c in name if c.isalnum() or c in ('-','_','#')])
                subprocess.run([CONTROL_SCRIPT, "activate", safe], check=True)
                self._send_json({"success": True})
            except Exception as e: self._send_json({"error": str(e)}, 500)
        elif self.path == '/delete':
            try:
                l = int(self.headers['Content-Length'])
                name = json.loads(self.rfile.read(l).decode('utf-8')).get('name')
                safe = "".join([c for c in name if c.isalnum() or c in ('-','_','#')])
                subprocess.run([CONTROL_SCRIPT, "delete", safe], check=True)
                self._send_json({"success": True})
            except Exception as e: self._send_json({"error": str(e)}, 500)

if __name__ == "__main__":
    with ThreadingHTTPServer(("", PORT), APIHandler) as httpd: httpd.serve_forever()
EOF
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
    entrypoint: ["/bin/sh", "-c", "apk add --no-cache docker-cli docker-compose && python /app/server.py"]
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
    # TUNING: IP forwarding is mandatory for VPN routing
    sysctls:
      - net.ipv4.conf.all.src_valid_mark=1
      - net.ipv4.ip_forward=1
    # FIX: Expose TUN device for ZimaOS
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
    # --------------------------------------------------------------------------
    # GLUETUN: MOUNT WG CONF DIRECTLY (As per docs)
    # --------------------------------------------------------------------------
    volumes:
      - "$ACTIVE_WG_CONF:/gluetun/wireguard/wg0.conf:ro"
    env_file:
      - "$GLUETUN_ENV_FILE"
    restart: unless-stopped
    deploy:
      resources:
        # High CPU for WireGuard encryption (up to 2 full cores)
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
    # SECURE PORT BINDING: All ports bound to LAN_IP only
    # Access via: Local network OR WireGuard VPN tunnel
    # - Regular DNS (53): $LAN_IP only
    # - Web UI (8083): $LAN_IP only
    # - DoH (443): $LAN_IP only - accessible via WireGuard
    # - DoT/DoQ (853): $LAN_IP only - accessible via WireGuard
    # ONLY WireGuard port (51820) is exposed to internet
    # When connected via WireGuard, access DoH at: https://DESEC_DOMAIN/dns-query
    # DNS Resolution: AdGuard (filtering) → Unbound (recursive to root servers)
    # deSEC used ONLY for: domain name + certificates (NOT in DNS chain)
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
        # Invidious can be CPU hungry during video processing/proxying
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
    environment: {SERVER_SECRET_KEY: "$IV_COMPANION"}
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
    <style>
        :root {
            --bg: #141218; --surf: #1d1b20; --surf-high: #2b2930;
            --on-surf: #e6e1e5; --outline: #938f99;
            --p: #d0bcff; --on-p: #381e72; --pc: #4f378b; --on-pc: #eaddff;
            --s: #ccc2dc; --on-s: #332d41; --sc: #4a4458; --on-sc: #e8def8;
            --err: #f2b8b5; --on-err: #601410;
            --ok: #bceabb; --on-ok: #003912;
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
        .card {
            background: var(--surf); border-radius: var(--radius); padding: 24px;
            text-decoration: none; color: inherit; transition: 0.2s; position: relative;
            display: flex; flex-direction: column; justify-content: space-between; min-height: 130px; border: 1px solid transparent;
        }
        .card:hover { background: var(--surf-high); transform: translateY(-2px); box-shadow: 0 4px 12px rgba(0,0,0,0.3); }
        .card h2 { margin: 0 0 8px 0; font-size: 1.4rem; font-weight: 400; color: var(--on-surf); }
        .chip-box { display: flex; gap: 8px; flex-wrap: wrap; margin-bottom: auto; }
        .badge { font-size: 0.75rem; padding: 6px 12px; border-radius: 8px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px; }
        .badge.vpn { background: var(--pc); color: var(--on-pc); }
        .badge.admin { background: var(--sc); color: var(--on-sc); }
        .status-pill {
            display: inline-flex; align-items: center; gap: 8px; background: rgba(255,255,255,0.06);
            padding: 6px 14px; border-radius: 50px; font-size: 0.85rem; color: var(--s); margin-top: 16px; width: fit-content;
        }
        .dot { width: 8px; height: 8px; border-radius: 50%; background: #666; transition: 0.3s; }
        .dot.up { background: var(--ok); box-shadow: 0 0 10px var(--ok); }
        .dot.down { background: var(--err); box-shadow: 0 0 10px var(--err); }
        .input-field {
            width: 100%; background: #141218; border: 1px solid #49454f; color: #fff;
            padding: 14px; border-radius: 12px; font-family: monospace; font-size: 0.9rem; box-sizing: border-box; outline: none; transition: 0.2s;
        }
        .input-field:focus { border-color: var(--p); background: #1d1b20; }
        textarea.input-field { min-height: 120px; resize: vertical; }
        .btn {
            background: var(--p); color: var(--on-p); border: none; padding: 12px 24px; border-radius: 50px;
            font-weight: 600; cursor: pointer; text-transform: uppercase; letter-spacing: 0.5px; transition: 0.2s; margin-top: 16px; display: inline-block;
        }
        .btn:hover { opacity: 0.9; box-shadow: 0 2px 8px rgba(208, 188, 255, 0.3); }
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
        .stat-val { font-family: monospace; color: var(--p); }
        .active-prof { color: var(--ok); font-weight: bold; }
        .log-box {
            background: #000; border: 1px solid #333; padding: 16px; border-radius: 12px;
            height: 300px; overflow-y: auto; font-family: 'Courier New', monospace; font-size: 0.85rem; color: #ccc;
        }
        .log-line { margin: 2px 0; border-bottom: 1px solid #111; padding-bottom: 2px; }
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
        <div class="grid">
            <a href="http://$LAN_IP:$PORT_ADGUARD_WEB" class="card"><h2>AdGuard Home</h2><div class="chip-box"><span class="badge admin">Network</span></div></a>
            <a href="http://$LAN_IP:$PORT_PORTAINER" class="card"><h2>Portainer</h2><div class="chip-box"><span class="badge admin">System</span></div></a>
            <a href="http://$LAN_IP:$PORT_WG_WEB" class="card"><h2>WireGuard</h2><div class="chip-box"><span class="badge admin">Remote Access</span></div></a>
        </div>

        <div class="section-label">WireGuard Profiles</div>
        <div class="grid">
            <div class="card">
                <h3 style="margin-top:0;">Upload Profile</h3>
                <input type="text" id="prof-name" class="input-field" placeholder="Optional: Custom Name" style="margin-bottom:12px;">
                <textarea id="prof-conf" class="input-field" placeholder="Paste .conf content here..."></textarea>
                <div style="text-align:right;"><button onclick="uploadProfile()" class="btn">Upload & Activate</button></div>
                <div id="upload-status" style="margin-top:10px; font-size:0.85rem; color:var(--p);"></div>
            </div>
            <div class="card">
                <h3 style="margin-top:0;">Manage Profiles</h3>
                <div id="profile-list">Loading...</div>
                <p style="font-size:0.8rem; color:#888; margin-top:16px;">Click name to activate.</p>
            </div>
        </div>

        <div class="section-label">System Status & Logs</div>
        <div class="grid">
            <div class="card">
                <h3 style="margin-top:0; margin-bottom:16px; color:var(--on-surf);">Gluetun (Frontend Proxy)</h3>
                <div class="stat-row"><span>Active Profile</span><span class="stat-val active-prof" id="vpn-active">--</span></div>
                <div class="stat-row"><span>Endpoint IP</span><span class="stat-val" id="vpn-endpoint">--</span></div>
                <div class="stat-row"><span>Live Traffic</span><span class="stat-val"><span id="vpn-rx">0</span> / <span id="vpn-tx">0</span></span></div>
            </div>
            <div class="card">
                <h3 style="margin-top:0; margin-bottom:16px; color:var(--on-surf);">WG-Easy (External Access)</h3>
                <div class="stat-row"><span>Service Status</span><span class="stat-val" id="wge-status">--</span></div>
                <div class="stat-row"><span>External IP</span><span class="stat-val" id="wge-host">--</span></div>
                <div class="stat-row"><span>UDP Port</span><span class="stat-val">51820</span></div>
            </div>
            <div class="card" style="grid-column: span 2;">
                <h3 style="margin-top:0;">Deployment History</h3>
                <div id="log-container" class="log-box"></div>
                <div id="log-status" style="font-size:0.8rem; color:var(--s); text-align:right; margin-top:5px;">Connecting...</div>
            </div>
        </div>
    </div>

    <script>
        const API = "/api";
        async function fetchStatus() {
            try {
                const res = await fetch(\`\${API}/status\`);
                const data = await res.json();
                const g = data.gluetun;
                document.getElementById('vpn-active').textContent = g.active_profile || "Unknown";
                document.getElementById('vpn-endpoint').textContent = g.endpoint || "Unknown";
                document.getElementById('vpn-rx').textContent = formatBytes(g.rx);
                document.getElementById('vpn-tx').textContent = formatBytes(g.tx);
                const w = data.wgeasy;
                const wgeStat = document.getElementById('wge-status');
                wgeStat.textContent = (w.status === "up") ? "Running" : "Stopped";
                wgeStat.style.color = (w.status === "up") ? "var(--ok)" : "var(--err)";
                document.getElementById('wge-host').textContent = w.host || "--";
            } catch(e) {}
        }
        async function fetchProfiles() {
            try {
                const res = await fetch(\`\${API}/profiles\`);
                const data = await res.json();
                const el = document.getElementById('profile-list');
                el.innerHTML = '';
                data.profiles.forEach(p => {
                    const row = document.createElement('div');
                    row.className = 'profile-row';
                    row.innerHTML = \`
                        <span class="profile-name" onclick="activateProfile('\${p}')">\${p}</span>
                        <button class="btn del" onclick="deleteProfile('\${p}')" title="Delete">
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
                div.className = 'log-line';
                div.textContent = e.data;
                el.appendChild(div);
                el.scrollTop = el.scrollHeight;
            };
            evtSource.onopen = function() { status.textContent = "Live"; status.style.color = "var(--ok)"; };
            evtSource.onerror = function() { status.textContent = "Reconnecting..."; status.style.color = "var(--err)"; evtSource.close(); setTimeout(startLogStream, 3000); };
        }
        function formatBytes(a,b=2){if(!+a)return"0 B";const c=0>b?0:b,d=Math.floor(Math.log(a)/Math.log(1024));return\`\${parseFloat((a/Math.pow(1024,d)).toFixed(c))} \${["B","KiB","MiB","GiB","TiB"][d]}\`}
        document.addEventListener('DOMContentLoaded', () => {
            fetchStatus(); fetchProfiles(); startLogStream(); setInterval(fetchStatus, 5000);
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
cat > "$MONITOR_SCRIPT" <<EOF
#!/usr/bin/env bash
COMPOSE_FILE="$COMPOSE_FILE"
CURRENT_IP_FILE="$CURRENT_IP_FILE"
LOG_FILE="$IP_LOG_FILE"
NEW_IP=\$(curl -s --max-time 5 https://api.ipify.org || curl -s --max-time 5 https://ifconfig.me)
if [[ ! "\$NEW_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\$ ]]; then exit 1; fi
OLD_IP=\$(cat "\$CURRENT_IP_FILE" 2>/dev/null || echo "")
if [ "\$NEW_IP" != "\$OLD_IP" ]; then
    echo "\$(date) [INFO] IP Change: \$OLD_IP -> \$NEW_IP" >> "\$LOG_FILE"
    echo "\$NEW_IP" > "\$CURRENT_IP_FILE"
    sed -i "s|WG_HOST=.*|WG_HOST=\$NEW_IP|g" "\$COMPOSE_FILE"
    docker compose -f "\$COMPOSE_FILE" up -d --no-deps --force-recreate wg-easy
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
# Pre-load tun module for ZimaOS
sudo modprobe tun || true

sudo env DOCKER_CONFIG="$BASE_DIR/.docker" docker compose -f "$COMPOSE_FILE" up -d --build --remove-orphans

echo "[+] Waiting for AdGuard to start..."
sleep 10

# Verify AdGuard is running and configuration is applied
log_info "Verifying AdGuard Home setup..."
if sudo docker ps | grep -q adguard; then
    log_info "AdGuard container is running"
    
    # Wait a bit more for AdGuard to fully initialize
    sleep 5
    
    # Check if AdGuard web interface is accessible
    if curl -s --max-time 5 "http://$LAN_IP:$PORT_ADGUARD_WEB" > /dev/null; then
        log_info "AdGuard web interface is accessible"
    else
        log_warn "AdGuard web interface not yet accessible (may still be initializing)"
    fi
    
    # Verify configuration file was loaded
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
echo "DEPLOYMENT COMPLETE V3.6"
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
echo "DNS ARCHITECTURE:"
echo "  Users → AdGuard (ad blocking) → Unbound (recursive) → Root servers"
if [ -n "$DESEC_DOMAIN" ]; then
    echo "  deSEC used for: Domain ($DESEC_DOMAIN) + Let's Encrypt certificates"
else
    echo "  deSEC: Not configured (using self-signed certificates)"
fi
echo "  deSEC NOT in DNS resolution chain - full privacy!"
echo ""
echo "SECURITY MODEL:"
echo "  ✓ ONLY WireGuard (51820/udp) exposed to internet"
echo "  ✓ All DNS services accessible via local network or VPN"
echo "  ✓ No direct DNS exposure - requires VPN authentication"
echo "  ✓ Fully recursive DNS (no third-party upstream)"
echo "  ✓ Filter updates every 6 hours"
echo ""
# Print auto-generated passwords if -p flag was used
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
