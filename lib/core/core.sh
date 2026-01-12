
# Source Consolidated Constants
# SCRIPT_DIR is exported from zima.sh
source "${SCRIPT_DIR}/lib/core/constants.sh"

detect_dockerfile() {
    local repo_dir="$1"
    local preferred="${2:-}"
    local found=""
    if [ -n "$preferred" ] && [ -f "$repo_dir/$preferred" ]; then echo "$preferred"; return 0; fi
    if [ -f "$repo_dir/Dockerfile.alpine" ]; then echo "Dockerfile.alpine"; return 0; fi
    if [ -f "$repo_dir/Dockerfile" ]; then echo "Dockerfile"; return 0; fi
    if [ -f "$repo_dir/docker/Dockerfile" ]; then echo "docker/Dockerfile"; return 0; fi
    # Search deeper
    found=$(find "$repo_dir" -maxdepth 3 -type f -name 'Dockerfile*' -not -path '*/.*' 2>/dev/null | head -n 1 || true)
    if [ -n "$found" ]; then echo "${found#"$repo_dir/"}"; return 0; fi
    return 1
}

# Core logging functions that output to terminal and persist JSON formatted logs for the dashboard.
# Uses Python for secure JSON escaping to prevent injection.
log_to_file() {
    local level=$1
    local msg=$2
    if [ -d "$(dirname "$HISTORY_LOG")" ]; then
        $PYTHON_CMD -c "import json, datetime, sys; print(json.dumps({'timestamp': datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S'), 'level': sys.argv[1], 'category': 'SYSTEM', 'source': 'orchestrator', 'message': sys.argv[2]}))" "$level" "$msg" >> "$HISTORY_LOG" 2>/dev/null || true
    fi
}

log_info() { 
    echo -e "\e[34m  ➜ [INFO]\e[0m $1"
    log_to_file "INFO" "$1"
}
log_warn() { 
    echo -e "\e[33m  ⚠️ [WARN]\e[0m $1"
    log_to_file "WARN" "$1"
}
log_crit() { 
    echo -e "\e[31m  ✖ [CRIT]\e[0m $1"
    log_to_file "CRIT" "$1"
}

ask_confirm() {
    if [ "$AUTO_CONFIRM" = true ]; then return 0; fi
    read -r -p "$1 [y/N]: " response
    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

pull_with_retry() {
    local img=$1
    if $DOCKER_CMD pull "$img" >/dev/null 2>&1; then
        log_info "Successfully pulled $img"
        return 0
    fi
    log_crit "Failed to pull critical image $img."
    return 1
}

authenticate_registries() {
    if [ -n "${REG_USER:-}" ] && [ -n "${REG_TOKEN:-}" ]; then
        log_info "Authenticating with Docker Registry..."
        # Use printf to avoid issues with special characters in token
        if printf "%s" "$REG_TOKEN" | $DOCKER_CMD login -u "$REG_USER" --password-stdin >/dev/null 2>&1; then
            log_info "Registry authentication successful."
            return 0
        else
            log_warn "Registry authentication failed. Continuing as anonymous."
            return 1
        fi
    fi
    return 0
}

safe_replace() {
    local template_file="$1"
    local output_file="$2"
    shift 2
    if [ ! -f "$template_file" ]; then
        log_warn "Template file not found: $template_file"
        return 1
    fi
    local content
    content=$(cat "$template_file")
    while [ $# -gt 0 ]; do
        local placeholder="$1"
        local value="$2"
        # Use bash parameter expansion for global replacement
        content="${content//$placeholder/$value}"
        shift 2
    done
    printf "%s" "$content" > "$output_file"
}

generate_secret() {
    local length=${1:-32}
    head -c 64 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c "$length"
}

generate_hash() {
    local user=$1
    local pass=$2
    $DOCKER_CMD run --rm alpine:3.21 sh -c 'apk add --no-cache apache2-utils >/dev/null 2>&1 && htpasswd -B -n -b "$1" "$2"' -- "$user" "$pass" 2>/dev/null | cut -d: -f2 || echo "FAILED"
}

# --- SECTION 0: ARGUMENT PARSING & INITIALIZATION ---
REG_USER="${REG_USER:-}"
REG_TOKEN="${REG_TOKEN:-}"
LAN_IP_OVERRIDE="${LAN_IP_OVERRIDE:-}"
WG_CONF_B64="${WG_CONF_B64:-}"

usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -y          Auto-Confirm (non-interactive mode)"
    echo "  -j          Parallel Deploy (faster builds, high CPU usage)"
    echo "  -s <list>   Selective deployment (comma-separated list, e.g., -s invidious,memos)"
    echo "  -c          Maintenance (recreates containers, preserves data)"
    echo "  -E <file>   Load Environment Variables from file"
    echo "  -G          Generate Only (stops before deployment)"
    echo "  -h          Show this help message"
}

FORCE_CLEAN=false
CLEAN_ONLY=false
AUTO_PASSWORD=false
CLEAN_EXIT=false
RESET_ENV=false
AUTO_CONFIRM=false
ALLOW_PROTON_VPN=false
SELECTED_SERVICES=""
PARALLEL_DEPLOY=false
GENERATE_ONLY=false
ENV_FILE=""
PERSONAL_MODE=false
REG_TOKEN=""
REG_USER=""

while getopts "cxpyas:j hE:G" opt; do
    case ${opt} in
        c) RESET_ENV=true; FORCE_CLEAN=true ;;
        x) CLEAN_EXIT=true; RESET_ENV=true; CLEAN_ONLY=true; FORCE_CLEAN=true ;;
        p) AUTO_PASSWORD=true ;;
        y) AUTO_CONFIRM=true; AUTO_PASSWORD=true ;;
        a) ALLOW_PROTON_VPN=true ;;
        s) SELECTED_SERVICES="${OPTARG}" ;;
        j) PARALLEL_DEPLOY=true ;;
        E) ENV_FILE="${OPTARG}" ;;
        G) GENERATE_ONLY=true ;;
        h) 
            usage
            exit 0
            ;;
        *) usage; exit 1 ;;
    esac
done
shift $((OPTIND -1))

# --- LOAD EXTERNAL ENV FILE ---
if [ -n "$ENV_FILE" ]; then
    if [ -f "$ENV_FILE" ]; then
        # shellcheck disable=SC1090
        source "$ENV_FILE"
    else
        echo "[CRIT] Environment file not found: $ENV_FILE"
        exit 1
    fi
fi

# --- SECTION 1: ENVIRONMENT VALIDATION & DIRECTORY SETUP ---
# Suppress git advice/warnings for cleaner logs during automated clones
export GIT_CONFIG_PARAMETERS="'advice.detachedHead=false'"

# Verify core dependencies before proceeding.
REQUIRED_COMMANDS="docker curl git crontab iptables flock jq awk sed grep find tar ip"
if [ "$(id -u)" -ne 0 ] && ! command -v sudo >/dev/null 2>&1; then
    echo "[CRIT] sudo is required for non-root users. Please install it."
    exit 1
fi
for cmd in $REQUIRED_COMMANDS; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "[CRIT] '$cmd' is required but not installed. Please install it."
        exit 1
    fi
done

# Detect if sudo is available
if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo -E"
else
    SUDO=""
fi

# Docker Compose Check (Plugin or Standalone)
if $SUDO docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    if $SUDO docker-compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE_CMD="docker-compose"
    else
        echo "[CRIT] Docker Compose is installed but not executable."
        exit 1
    fi
else
    echo "[CRIT] Docker Compose v2 is required. Please update your environment."
    exit 1
fi

APP_NAME="${APP_NAME:-privacy-hub}"
# Sanitize APP_NAME to prevent directory traversal or problematic characters
APP_NAME=$(echo "$APP_NAME" | tr -cd 'a-zA-Z0-9-_')
if [ -z "$APP_NAME" ]; then APP_NAME="privacy-hub"; fi
# Use absolute path for BASE_DIR to ensure it stays in the project root's data folder
# Detect PROJECT_ROOT dynamically if not already set
if [ -z "${PROJECT_ROOT:-}" ]; then
    # SCRIPT_DIR is exported from zima.sh
    if [ -n "${SCRIPT_DIR:-}" ]; then
        PROJECT_ROOT="$SCRIPT_DIR"
    else
        PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    fi
fi
BASE_DIR="$PROJECT_ROOT/data/AppData/$APP_NAME"
$SUDO mkdir -p "$BASE_DIR"
$SUDO chown "$(whoami)" "$BASE_DIR"
BASE_DIR="$(cd "$BASE_DIR" && pwd)"

# Paths
SRC_DIR="$BASE_DIR/sources"
ENV_DIR="$BASE_DIR/env"
CONFIG_DIR="$BASE_DIR/config"
DATA_DIR="$BASE_DIR/data"
COMPOSE_FILE="$BASE_DIR/docker-compose.yml"
DASHBOARD_FILE="$BASE_DIR/dashboard.html"
SECRETS_FILE="$BASE_DIR/.secrets"
BACKUP_DIR="$BASE_DIR/backups"
ASSETS_DIR="$BASE_DIR/assets"
HISTORY_LOG="$BASE_DIR/deployment.log"
CERT_BACKUP_DIR="$PROJECT_ROOT/data/AppData/.cert-backups/$APP_NAME"
CERT_RESTORE=false
CERT_PROTECT=false

# Memos storage
MEMOS_HOST_DIR="$PROJECT_ROOT/data/AppData/memos"

# WireGuard & Profiles
WG_PROFILES_DIR="$BASE_DIR/wg-profiles"
ACTIVE_WG_CONF="$BASE_DIR/active-wg.conf"
ACTIVE_PROFILE_NAME_FILE="$BASE_DIR/.active_profile_name"
DOTENV_FILE="$BASE_DIR/.env"

init_directories() {
    log_info "Initializing project directories..."
    $SUDO mkdir -p "$SRC_DIR" "$ENV_DIR" "$CONFIG_DIR" "$DATA_DIR" "$BACKUP_DIR" "$ASSETS_DIR" "$MEMOS_HOST_DIR" "$DATA_DIR/hub-api" "$WG_PROFILES_DIR"
    $SUDO chown "$(whoami)" "$BASE_DIR" "$SRC_DIR" "$ENV_DIR" "$CONFIG_DIR" "$BACKUP_DIR" "$ASSETS_DIR" "$WG_PROFILES_DIR"
    
    # Initialize metadata files with correct ownership
    [ ! -f "$DOTENV_FILE" ] && $SUDO touch "$DOTENV_FILE"
    [ ! -f "$ACTIVE_WG_CONF" ] && $SUDO touch "$ACTIVE_WG_CONF"
    
    $SUDO chown "$(whoami)" "$DOTENV_FILE" "$ACTIVE_WG_CONF"
    $SUDO chmod 600 "$DOTENV_FILE" "$ACTIVE_WG_CONF"

    $SUDO chown -R 1000:1000 "$DATA_DIR" "$MEMOS_HOST_DIR" "$DATA_DIR/hub-api"
}

# Container naming and persistence
CONTAINER_PREFIX="hub-"
export CONTAINER_PREFIX

UPDATE_STRATEGY="stable"
export UPDATE_STRATEGY

# Docker Auth Config
DOCKER_AUTH_DIR="$BASE_DIR/.docker"
# Ensure clean state for auth only if it doesn't already have a config
if [ ! -f "$DOCKER_AUTH_DIR/config.json" ]; then
    $SUDO mkdir -p "$DOCKER_AUTH_DIR"
    $SUDO chown -R "$(whoami)" "$DOCKER_AUTH_DIR"
fi

# Detect Python interpreter
if command -v python3 >/dev/null 2>&1; then
    PYTHON_CMD="python3"
elif command -v python >/dev/null 2>&1; then
    PYTHON_CMD="python"
else
    echo "[CRIT] Python is required but not installed. Please install python3."
    exit 1
fi

# Define consistent docker command using custom config for auth
DOCKER_CMD="$SUDO env DOCKER_CONFIG=\"$DOCKER_AUTH_DIR\" GOTOOLCHAIN=auto docker"
DOCKER_COMPOSE_FINAL_CMD="$SUDO env DOCKER_CONFIG=\"$DOCKER_AUTH_DIR\" GOTOOLCHAIN=auto $DOCKER_COMPOSE_CMD"

# Initialize deSEC variables to prevent unbound variable errors
DESEC_DOMAIN="${DESEC_DOMAIN:-}"
DESEC_TOKEN="${DESEC_TOKEN:-}"
DESEC_MONITOR_DOMAIN="${DESEC_MONITOR_DOMAIN:-}"
DESEC_MONITOR_TOKEN="${DESEC_MONITOR_TOKEN:-}"
SCRIBE_GH_USER="${SCRIBE_GH_USER:-}"
SCRIBE_GH_TOKEN="${SCRIBE_GH_TOKEN:-}"
ODIDO_USER_ID="${ODIDO_USER_ID:-}"
ODIDO_TOKEN="${ODIDO_TOKEN:-}"
ODIDO_API_KEY="${ODIDO_API_KEY:-}"
ODIDO_USE_VPN="true"
VERTD_PUB_URL="${VERTD_PUB_URL:-}"
VERT_PUB_HOSTNAME="${VERT_PUB_HOSTNAME:-}"
WG_HASH_CLEAN=""
FOUND_OCTET=""
AGH_USER="adguard"
AGH_PASS_HASH=""
PORTAINER_PASS_HASH=""
PORTAINER_HASH_COMPOSE=""
WG_HASH_COMPOSE=""
ADMIN_PASS_RAW=""
VPN_PASS_RAW=""
PORTAINER_PASS_RAW=""
AGH_PASS_RAW=""
ANONYMOUS_SECRET=""
SCRIBE_SECRET=""
SEARXNG_SECRET=""
IMMICH_DB_PASSWORD=""
IMMICH_ADMIN_PASS_RAW=""

# Service Configurations
NGINX_CONF_DIR="$CONFIG_DIR/nginx"
NGINX_CONF="$NGINX_CONF_DIR/default.conf"
UNBOUND_CONF="$CONFIG_DIR/unbound/unbound.conf"
BREEZEWIKI_CONF="$CONFIG_DIR/breezewiki/breezewiki.ini"
AGH_CONF_DIR="$CONFIG_DIR/adguard"
AGH_YAML="$AGH_CONF_DIR/AdGuardHome.yaml"

# Scripts
MONITOR_SCRIPT="$BASE_DIR/wg-ip-monitor.sh"
IP_LOG_FILE="$BASE_DIR/wg-ip-monitor.log"
CURRENT_IP_FILE="$BASE_DIR/.current_public_ip"
WG_CONTROL_SCRIPT="$BASE_DIR/wg-control.sh"
WG_API_SCRIPT="$BASE_DIR/wg-api.py"
CERT_MONITOR_SCRIPT="$BASE_DIR/cert-monitor.sh"
MIGRATE_SCRIPT="$BASE_DIR/migrate.sh"
PATCHES_SCRIPT="$BASE_DIR/patches.sh"

# Ensure root-level data files are writable by the container user (UID 1000)
$SUDO touch "$HISTORY_LOG" "$ACTIVE_WG_CONF" "$BASE_DIR/.data_usage" "$BASE_DIR/.wge_data_usage"
$SUDO chown 1000:1000 "$HISTORY_LOG" "$ACTIVE_WG_CONF" "$BASE_DIR/.data_usage" "$BASE_DIR/.wge_data_usage" "$ACTIVE_PROFILE_NAME_FILE" 2>/dev/null || true
$SUDO chown -R 1000:1000 "$DATA_DIR" "$MEMOS_HOST_DIR" "$ASSETS_DIR" 2>/dev/null || true

# --- SECTION 3: DYNAMIC SUBNET ALLOCATION ---
allocate_subnet() {
    log_info "Allocating private virtual subnet for container isolation."

    FOUND_SUBNET=""
    FOUND_OCTET=""

    for i in {20..30}; do
        TEST_SUBNET="172.$i.0.0/16"
        TEST_NET_NAME="probe_net_$i"
        if $DOCKER_CMD network create --subnet="$TEST_SUBNET" "$TEST_NET_NAME" >/dev/null 2>&1; then
            $DOCKER_CMD network rm "$TEST_NET_NAME" >/dev/null 2>&1
            FOUND_SUBNET="$TEST_SUBNET"
            FOUND_OCTET="$i"
            break
        fi
    done

    if [ -z "$FOUND_SUBNET" ]; then
        log_crit "Fatal: No available subnets identified. Please verify host network configuration."
        exit 1
    fi

    DOCKER_SUBNET="$FOUND_SUBNET"
    export DOCKER_SUBNET
    export FOUND_OCTET
    log_info "Assigned Virtual Subnet: $DOCKER_SUBNET"
}

check_port_availability() {
    local port=$1
    local proto=${2:-tcp}
    
    if command -v ss >/dev/null 2>&1; then
        if $SUDO ss -Hl"${proto:0:1}"n sport = :"$port" | grep -q "$port"; then
            return 1
        fi
    elif command -v netstat >/dev/null 2>&1; then
        if $SUDO netstat -l"${proto:0:1}"n | grep -q ":$port "; then
            return 1
        fi
    elif command -v lsof >/dev/null 2>&1; then
        if $SUDO lsof -i "${proto}:${port}" -s "${proto}:LISTEN" >/dev/null 2>&1; then
            return 1
        fi
    fi
    return 0
}

is_service_enabled() {
    local srv="$1"
    if [ -z "${SELECTED_SERVICES:-}" ]; then return 0; fi
    if echo "$SELECTED_SERVICES" | grep -qE "(^|,)$srv(,|$)"; then return 0; fi
    return 1
}

safe_remove_network() {
    local net_name="$1"
    if $DOCKER_CMD network inspect "$net_name" >/dev/null 2>&1; then
        # Check if any containers are using it
        local containers=$($DOCKER_CMD network inspect "$net_name" --format '{{range .Containers}}{{.Name}} {{end}}')
        if [ -n "$containers" ]; then
            for c in $containers; do
                log_info "  Disconnecting container $c from network $net_name..."
                $DOCKER_CMD network disconnect -f "$net_name" "$c" 2>/dev/null || true
            done
        fi
        $DOCKER_CMD network rm "$net_name" 2>/dev/null || true
    fi
}

detect_network() {
    log_info "Identifying network environment..."

    # 1. LAN IP Detection
    if [ -n "$LAN_IP_OVERRIDE" ]; then
        LAN_IP="$LAN_IP_OVERRIDE"
        log_info "Using LAN IP Override: $LAN_IP"
    elif [ -z "${LAN_IP:-}" ]; then
        # Try to find primary interface IP
        # 1. Try ip route with a neutral destination (routing table lookup only)
        # Using 10.255.255.255 as a destination to see which interface/source IP would be used
        LAN_IP=$(ip route get 10.255.255.255 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -n1)
        
        # 2. Fallback: Try to find interface with default route
        if [ -z "$LAN_IP" ]; then
            local default_iface=$(ip route show default 2>/dev/null | awk '/default/ {print $5}' | head -n1)
            if [ -n "$default_iface" ]; then
                LAN_IP=$(ip -4 addr show "$default_iface" scope global | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -n1)
            fi
        fi

        # 3. Fallback: hostname -I (if available)
        if [ -z "$LAN_IP" ]; then
            LAN_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
        fi

        # 4. Last resort: Any global IPv4 address
        if [ -z "$LAN_IP" ]; then
            LAN_IP=$(ip -4 addr show scope global | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -n1)
        fi

        if [ -z "$LAN_IP" ]; then
            log_crit "Failed to detect LAN IP. Please use LAN_IP_OVERRIDE."
            exit 1
        fi
        log_info "Detected LAN IP: $LAN_IP"
    else
        log_info "Using existing LAN IP: $LAN_IP"
    fi
    export LAN_IP

    # 2. Public IP Detection
    if [ -n "${PUBLIC_IP:-}" ] && [ "$PUBLIC_IP" != "FAILED" ]; then
        log_info "Using existing Public IP: $PUBLIC_IP"
    else
        log_info "Detecting public IP address (for VPN endpoint)..."
        # Use a privacy-conscious IP check service as requested, via proxy if possible
        local proxy="http://172.${FOUND_OCTET}.0.254:8888"
        PUBLIC_IP=$(curl --proxy "$proxy" -s --max-time 10 https://api.ipify.org || curl -s --max-time 10 https://api.ipify.org || curl -s --max-time 10 http://ip-api.com/line?fields=query || echo "FAILED")
        if [ "$PUBLIC_IP" = "FAILED" ]; then
            log_warn "Failed to detect public IP. VPN may not be reachable from external networks."
            PUBLIC_IP="$LAN_IP"
        fi
        log_info "Public IP: $PUBLIC_IP"
    fi
}

validate_wg_config() {
    if [ ! -s "$ACTIVE_WG_CONF" ]; then return 1; fi
    if ! grep -q "PrivateKey" "$ACTIVE_WG_CONF"; then return 1; fi
    local PK_VAL
    PK_VAL=$(grep "PrivateKey" "$ACTIVE_WG_CONF" | cut -d'=' -f2- | tr -d '[:space:]')
    if [ -z "$PK_VAL" ]; then return 1; fi
    if [ "${#PK_VAL}" -lt 40 ]; then return 1; fi
    return 0
}

extract_wg_profile_name() {
    local config_file="$1"
    local in_peer=0
    local profile_name=""
    while IFS= read -r line; do
        stripped=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if echo "$stripped" | grep -qi '^\[peer\]$'; then in_peer=1; continue; fi
        if [ "$in_peer" -eq 1 ] && echo "$stripped" | grep -q '^#'; then
            profile_name=$(echo "$stripped" | sed 's/^#[[:space:]]*//')
            if [ -n "$profile_name" ]; then echo "$profile_name"; return 0; fi
        fi
        if [ "$in_peer" -eq 1 ] && echo "$stripped" | grep -q '^\['; then break; fi
    done < "$config_file"
    while IFS= read -r line; do
        stripped=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if echo "$stripped" | grep -q '^#' && ! echo "$stripped" | grep -q '='; then
            profile_name=$(echo "$stripped" | sed 's/^#[[:space:]]*//')
            if [ -n "$profile_name" ]; then echo "$profile_name"; return 0; fi
        fi
    done < "$config_file"
    return 1
}

setup_secrets() {
    export PORTAINER_PASS_HASH="${PORTAINER_PASS_HASH:-}"
    export AGH_PASS_HASH="${AGH_PASS_HASH:-}"
    export WG_HASH_COMPOSE="${WG_HASH_COMPOSE:-}"
    export ADMIN_PASS_RAW="${ADMIN_PASS_RAW:-}"
    export VPN_PASS_RAW="${VPN_PASS_RAW:-}"
    export PORTAINER_PASS_RAW="${PORTAINER_PASS_RAW:-}"
    export AGH_PASS_RAW="${AGH_PASS_RAW:-}"
    export SEARXNG_SECRET="${SEARXNG_SECRET:-}"
    export IMMICH_DB_PASSWORD="${IMMICH_DB_PASSWORD:-}"
    if [ ! -f "$BASE_DIR/.secrets" ]; then
        echo "========================================"
        echo " CREDENTIAL CONFIGURATION"
        echo "========================================"
        
        if [ "$AUTO_PASSWORD" = true ]; then
            log_info "Automated password generation initialized."
            if [ "$FORCE_CLEAN" = false ] && [ -d "$DATA_DIR/portainer" ] && [ "$(ls -A "$DATA_DIR/portainer")" ]; then
                log_warn "Portainer data directory already exists. Portainer's security policy only allows setting the admin password on the FIRST deployment. The newly generated password displayed at the end will NOT work unless you manually reset it or delete the Portainer volume."
            fi
            if [ -z "$VPN_PASS_RAW" ]; then VPN_PASS_RAW=$(generate_secret 24); fi
            if [ -z "$AGH_PASS_RAW" ]; then AGH_PASS_RAW=$(generate_secret 24); fi
            if [ -z "$ADMIN_PASS_RAW" ]; then ADMIN_PASS_RAW=$(generate_secret 24); fi
            if [ -z "$PORTAINER_PASS_RAW" ]; then PORTAINER_PASS_RAW=$(generate_secret 24); fi
            log_info "Credentials generated and will be displayed upon completion."
            echo ""
        else
            echo "--- MANUAL CREDENTIAL PROVISIONING ---"
            echo "Security Note: Please use strong, unique passwords for each service."
            echo ""
            echo -n "1. VPN Web UI Password (Protecting peer management): "
            read -rs VPN_PASS_RAW
            echo ""
            echo -n "2. AdGuard Home Password (Protecting DNS filters): "
            read -rs AGH_PASS_RAW
            echo ""
            echo -n "3. Management Dashboard Password (Primary control plane): "
            read -rs ADMIN_PASS_RAW
            echo ""
            if [ "$FORCE_CLEAN" = false ] && [ -d "$DATA_DIR/portainer" ]; then
                 echo "   [!] NOTICE: Portainer already initialized. New passwords will not affect existing Portainer admin account."
            fi
            echo -n "4. Portainer Password (Infrastructure orchestration): "
            read -rs PORTAINER_PASS_RAW
            echo ""
        fi
        
        if [ "$AUTO_CONFIRM" = true ]; then
            log_info "Auto-confirm enabled: Skipping interactive deSEC/GitHub/Odido setup (preserving environment variables)."
            if [ "${PERSONAL_MODE:-false}" = true ]; then
                log_info "Personal Mode: Applying user-specific defaults."
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
            
            while [ -z "$DESEC_DOMAIN" ]; do
                echo -n "3. deSEC Domain (e.g., myhome.dedyn.io${DESEC_DOMAIN:+; current: $DESEC_DOMAIN}): "
                read -r input_domain
                DESEC_DOMAIN="${input_domain:-$DESEC_DOMAIN}"
                if [ -z "$DESEC_DOMAIN" ]; then
                     echo "   ⚠️  A deSEC domain is REQUIRED for external access and VERTd HTTPS support."
                fi
            done
            
            echo -n "4. deSEC API Token${DESEC_TOKEN:+ (current: [HIDDEN])}: "
            read -rs input_token
            echo ""
            DESEC_TOKEN="${input_token:-$DESEC_TOKEN}"
            echo ""
            
            echo "--- Scribe (Medium Frontend) GitHub Integration ---"
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
                # We pass the Authorization header and a mobile User-Agent to mimic the app
                ODIDO_REDIRECT_URL=$(curl -sL --max-time 10 -o /dev/null -w '%{url_effective}' \
                    -H "Authorization: Bearer $ODIDO_TOKEN" \
                    -H "User-Agent: T-Mobile 5.3.28 (Android 10; 10)" \
                    "https://capi.odido.nl/account/current" || echo "FAILED")
                
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
        
        log_info "Generating Secrets (Batch Processing)..."
        HUB_API_KEY=$(generate_secret 32)
        ODIDO_API_KEY="$HUB_API_KEY"
        
        # Optimized: Generate all hashes in a single container run to save time
        # We use alpine:3.21 and py3-bcrypt for standard $2b$ hashes (better compatibility than htpasswd $2y$)
        HASH_OUTPUT=$($DOCKER_CMD run --rm alpine:3.21 sh -c '
            apk add --no-cache python3 py3-bcrypt apache2-utils >/dev/null 2>&1
            if [ $? -ne 0 ]; then echo "FAILED"; exit 1; fi

            # Helper python script for bcrypt
            cat > gen_hash.py <<PYEOF
import bcrypt, sys
try:
    user = sys.argv[1].encode()
    pwd = sys.argv[2].encode()
    # Generate bcrypt hash (cost 10 default, prefix 2b)
    h = bcrypt.hashpw(pwd, bcrypt.gensalt())
    print(h.decode("utf-8"))
except Exception:
    sys.exit(1)
PYEOF

            echo "WG_HASH:$(python3 gen_hash.py "admin" "$1")"
            echo "AGH_HASH:$(htpasswd -B -n -b "$2" "$3" | cut -d: -f2)"
            echo "PORT_HASH:$(python3 gen_hash.py "admin" "$4")"
        ' -- "$VPN_PASS_RAW" "$AGH_USER" "$AGH_PASS_RAW" "$PORTAINER_PASS_RAW" 2>/dev/null || echo "FAILED")

        if echo "$HASH_OUTPUT" | grep -q "FAILED"; then
             log_crit "Failed to generate password hashes. Check Docker status."
             exit 1
        fi

        WG_HASH_CLEAN=$(echo "$HASH_OUTPUT" | grep "^WG_HASH:" | cut -d: -f2)
        AGH_PASS_HASH=$(echo "$HASH_OUTPUT" | grep "^AGH_HASH:" | cut -d: -f2)
        PORTAINER_PASS_HASH=$(echo "$HASH_OUTPUT" | grep "^PORT_HASH:" | cut -d: -f2)

        if [ -z "$WG_HASH_CLEAN" ] || [ -z "$AGH_PASS_HASH" ] || [ -z "$PORTAINER_PASS_HASH" ]; then
             log_crit "Failed to parse generated hashes."
             exit 1
        fi
        
        # Cryptographic Secrets
        SCRIBE_SECRET=$(generate_secret 64)
        ANONYMOUS_SECRET=$(generate_secret 32)
        IV_HMAC=$(generate_secret 16)
        IV_COMPANION=$(generate_secret 16)
        SEARXNG_SECRET=$(generate_secret 32)
        IMMICH_DB_PASSWORD=$(generate_secret 32)
        IMMICH_ADMIN_PASS_RAW=$(generate_secret 24)
        INVIDIOUS_DB_PASSWORD=$(generate_secret 32)

        cat > "$BASE_DIR/.secrets" <<EOF
VPN_PASS_RAW="$VPN_PASS_RAW"
AGH_PASS_RAW="$AGH_PASS_RAW"
ADMIN_PASS_RAW="$ADMIN_PASS_RAW"
PORTAINER_PASS_RAW="$PORTAINER_PASS_RAW"
IMMICH_ADMIN_PASS_RAW="$IMMICH_ADMIN_PASS_RAW"
DESEC_DOMAIN="$DESEC_DOMAIN"
DESEC_TOKEN="$DESEC_TOKEN"
SCRIBE_GH_USER="$SCRIBE_GH_USER"
SCRIBE_GH_TOKEN="$SCRIBE_GH_TOKEN"
ODIDO_TOKEN="$ODIDO_TOKEN"
ODIDO_USER_ID="$ODIDO_USER_ID"
ODIDO_API_KEY="$ODIDO_API_KEY"
HUB_API_KEY="$HUB_API_KEY"
UPDATE_STRATEGY="stable"
SEARXNG_SECRET="$SEARXNG_SECRET"
IMMICH_DB_PASSWORD="$IMMICH_DB_PASSWORD"
INVIDIOUS_DB_PASSWORD="$INVIDIOUS_DB_PASSWORD"
WG_HASH_CLEAN="$WG_HASH_CLEAN"
AGH_PASS_HASH="$AGH_PASS_HASH"
PORTAINER_PASS_HASH="$PORTAINER_PASS_HASH"
SCRIBE_SECRET="$SCRIBE_SECRET"
ANONYMOUS_SECRET="$ANONYMOUS_SECRET"
IV_HMAC="$IV_HMAC"
IV_COMPANION="$IV_COMPANION"
EOF
        $SUDO chmod 600 "$BASE_DIR/.secrets"
    else
        source "$BASE_DIR/.secrets"
        # Ensure all secrets are loaded/regenerated if missing
        local updated_secrets=false
        if [ -z "${SCRIBE_SECRET:-}" ]; then SCRIBE_SECRET=$(head -c 64 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 64); echo "SCRIBE_SECRET='$SCRIBE_SECRET'" >> "$BASE_DIR/.secrets"; updated_secrets=true; fi
        if [ -z "${ANONYMOUS_SECRET:-}" ]; then ANONYMOUS_SECRET=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32); echo "ANONYMOUS_SECRET=$ANONYMOUS_SECRET" >> "$BASE_DIR/.secrets"; updated_secrets=true; fi
        if [ -z "${IV_HMAC:-}" ]; then IV_HMAC=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 16); echo "IV_HMAC=$IV_HMAC" >> "$BASE_DIR/.secrets"; updated_secrets=true; fi
        if [ -z "${IV_COMPANION:-}" ]; then IV_COMPANION=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 16); echo "IV_COMPANION=$IV_COMPANION" >> "$BASE_DIR/.secrets"; updated_secrets=true; fi
        if [ -z "${SEARXNG_SECRET:-}" ]; then SEARXNG_SECRET=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32); echo "SEARXNG_SECRET=$SEARXNG_SECRET" >> "$BASE_DIR/.secrets"; updated_secrets=true; fi
        if [ -z "${IMMICH_DB_PASSWORD:-}" ]; then IMMICH_DB_PASSWORD=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32); echo "IMMICH_DB_PASSWORD=$IMMICH_DB_PASSWORD" >> "$BASE_DIR/.secrets"; updated_secrets=true; fi

        if [ -z "${ADMIN_PASS_RAW:-}" ]; then
            ADMIN_PASS_RAW=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 24)
            echo "ADMIN_PASS_RAW=$ADMIN_PASS_RAW" >> "$BASE_DIR/.secrets"; updated_secrets=true
        fi
        if [ -z "${PORTAINER_PASS_RAW:-}" ]; then
            PORTAINER_PASS_RAW=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 24)
            echo "PORTAINER_PASS_RAW=$PORTAINER_PASS_RAW" >> "$BASE_DIR/.secrets"; updated_secrets=true
        fi

        # Generate hashes if missing
        if [ -z "${WG_HASH_CLEAN:-}" ]; then
            log_info "Generating missing WireGuard hash..."
            WG_HASH_CLEAN=$(generate_hash "admin" "$VPN_PASS_RAW")
            echo "WG_HASH_CLEAN='$WG_HASH_CLEAN'" >> "$BASE_DIR/.secrets"; updated_secrets=true
        fi
        if [ -z "${AG_PASS_HASH:-}" ]; then
            log_info "Generating missing AdGuard hash..."
            AGH_USER="adguard"
            AGH_PASS_HASH=$(generate_hash "$AGH_USER" "$AGH_PASS_RAW")
            echo "AGH_PASS_HASH='$AGH_PASS_HASH'" >> "$BASE_DIR/.secrets"; updated_secrets=true
        fi
        if [ -z "${PORTAINER_PASS_HASH:-}" ]; then
            log_info "Generating missing Portainer hash..."
            PORTAINER_PASS_HASH=$(generate_hash "admin" "$PORTAINER_PASS_RAW")
            echo "PORTAINER_PASS_HASH='$PORTAINER_PASS_HASH'" >> "$BASE_DIR/.secrets"; updated_secrets=true
        fi

        # Ensure API keys are consistent and present
        if [ -z "${HUB_API_KEY:-}" ] && [ -n "${ODIDO_API_KEY:-}" ]; then
            HUB_API_KEY="$ODIDO_API_KEY"
            echo "HUB_API_KEY=$HUB_API_KEY" >> "$BASE_DIR/.secrets"; updated_secrets=true
        elif [ -n "${HUB_API_KEY:-}" ] && [ -z "${ODIDO_API_KEY:-}" ]; then
            ODIDO_API_KEY="$HUB_API_KEY"
            echo "ODIDO_API_KEY=$ODIDO_API_KEY" >> "$BASE_DIR/.secrets"; updated_secrets=true
        elif [ -z "${HUB_API_KEY:-}" ] && [ -z "${ODIDO_API_KEY:-}" ]; then
            HUB_API_KEY=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32)
            ODIDO_API_KEY="$HUB_API_KEY"
            echo "HUB_API_KEY=$HUB_API_KEY" >> "$BASE_DIR/.secrets"; updated_secrets=true
            echo "ODIDO_API_KEY=$ODIDO_API_KEY" >> "$BASE_DIR/.secrets"; updated_secrets=true
        fi

        if [ -z "${UPDATE_STRATEGY:-}" ]; then
            UPDATE_STRATEGY="stable"
            echo "UPDATE_STRATEGY=stable" >> "$BASE_DIR/.secrets"; updated_secrets=true
        fi
        export UPDATE_STRATEGY
        if [ "$updated_secrets" = true ]; then
            $SUDO chmod 600 "$BASE_DIR/.secrets"
        fi
        AGH_USER="adguard"
    fi
    
    # Final export of all variables for use in other scripts
    export VPN_PASS_RAW AGH_PASS_RAW ADMIN_PASS_RAW PORTAINER_PASS_RAW ALLOW_PROTON_VPN
    
    # Persist LAN_IP to .env for Docker Compose
    if ! grep -q "LAN_IP=" "$DOTENV_FILE" 2>/dev/null; then
        echo "LAN_IP=$LAN_IP" >> "$DOTENV_FILE"
    else
        sed -i "s|^LAN_IP=.*|LAN_IP=$LAN_IP|" "$DOTENV_FILE"
    fi
    export DESEC_DOMAIN DESEC_TOKEN SCRIBE_GH_USER SCRIBE_GH_TOKEN
    export ODIDO_TOKEN ODIDO_USER_ID ODIDO_API_KEY HUB_API_KEY
    export WG_HASH_CLEAN AGH_PASS_HASH PORTAINER_PASS_HASH
    export SCRIBE_SECRET ANONYMOUS_SECRET IV_HMAC IV_COMPANION
    export SEARXNG_SECRET IMMICH_DB_PASSWORD INVIDIOUS_DB_PASSWORD
    export AGH_USER
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
Portainer UI,http://$LAN_IP:$PORT_PORTAINER,admin,$PORTAINER_PASS_RAW,Docker container management interface.
Odido Booster API,http://$LAN_IP:8085,admin,$ODIDO_API_KEY,API key for dashboard and Odido automation.
Gluetun Control Server,http://$LAN_IP:8000,gluetun,$ADMIN_PASS_RAW,Internal VPN gateway control API.
deSEC DNS API,https://desec.io,$DESEC_DOMAIN,$DESEC_TOKEN,API token for deSEC dynamic DNS management.
GitHub Scribe Token,https://github.com/settings/tokens,$SCRIBE_GH_USER,$SCRIBE_GH_TOKEN,GitHub Personal Access Token (Gist Key) for Scribe Medium frontend.
EOF
    chmod 600 "$export_file"
    log_info "Credential export file created: $export_file"
}
