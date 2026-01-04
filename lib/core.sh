
# Core logging functions that output to terminal and persist JSON formatted logs for the dashboard.
log_info() { 
    echo -e "\e[34m[INFO]\e[0m $1"
    if [ -d "$(dirname "$HISTORY_LOG")" ]; then
        printf '{"timestamp": "%s", "level": "INFO", "category": "SYSTEM", "message": "%s"}\n' "$(date +"%Y-%m-%d %H:%M:%S")" "$1" >> "$HISTORY_LOG" 2>/dev/null || true
    fi
}
log_warn() { 
    echo -e "\e[33m[WARN]\e[0m $1"
    if [ -d "$(dirname "$HISTORY_LOG")" ]; then
        printf '{"timestamp": "%s", "level": "WARN", "category": "SYSTEM", "message": "%s"}\n' "$(date +"%Y-%m-%d %H:%M:%S")" "$1" >> "$HISTORY_LOG" 2>/dev/null || true
    fi
}
log_crit() { 
    echo -e "\e[31m[CRIT]\e[0m $1"
    if [ -d "$(dirname "$HISTORY_LOG")" ]; then
        printf '{"timestamp": "%s", "level": "CRIT", "category": "SYSTEM", "message": "%s"}\n' "$(date +"%Y-%m-%d %H:%M:%S")" "$1" >> "$HISTORY_LOG" 2>/dev/null || true
    fi
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
    local max_retries=3
    local count=0
    while [ $count -lt $max_retries ]; do
        if $DOCKER_CMD pull "$img" >/dev/null 2>&1; then
            log_info "Successfully pulled $img"
            return 0
        fi
        count=$((count + 1))
        log_warn "Failed to pull $img. Retrying ($count/$max_retries)..."
        sleep 1
    done
    log_crit "Failed to pull critical image $img after $max_retries attempts."
    return 1
}

detect_dockerfile() {
    local repo_dir="$1"
    local preferred="${2:-}"
    local found=""
    if [ -n "$preferred" ] && [ -f "$repo_dir/$preferred" ]; then echo "$preferred"; return 0; fi
    if [ -f "$repo_dir/Dockerfile.dhi" ]; then echo "Dockerfile.dhi"; return 0; fi
    if [ -f "$repo_dir/Dockerfile" ]; then echo "Dockerfile"; return 0; fi
    if [ -f "$repo_dir/docker/Dockerfile" ]; then echo "docker/Dockerfile"; return 0; fi
    # Search deeper
    found=$(find "$repo_dir" -maxdepth 3 -type f -name 'Dockerfile*' -not -path '*/.*' 2>/dev/null | head -n 1 || true)
    if [ -n "$found" ]; then echo "${found#"$repo_dir/"}"; return 0; fi
    return 1
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
    echo "  -p          Auto-Passwords (generates random secure credentials)"
    echo "  -y          Auto-Confirm (non-interactive mode)"
    echo "  -P          Personal Mode (fast-track: combines -p, -y, and -j)"
    echo "  -j          Parallel Deploy (faster builds, high CPU usage)"
    echo "  -s <list>   Selective deployment (comma-separated list, e.g., -s invidious,memos)"
    echo "  -S          Swap Slots (A/B update toggle)"
    echo "  -c          Maintenance (recreates containers, preserves data)"
    echo "  -x          Factory Reset (⚠️ WIPES ALL CONTAINERS AND VOLUMES)"
    echo "  -a          Allow ProtonVPN (adds ProtonVPN domains to AdGuard allowlist)"
    echo "  -D          Dashboard Only (UI testing, skips service rebuild)"
    echo "  -E <file>   Load Environment Variables from file"
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
DASHBOARD_ONLY=false
PERSONAL_MODE=false
PARALLEL_DEPLOY=false
SWAP_SLOTS=false
ENV_FILE=""

while getopts "cxpyas:DPjShE:" opt; do
    case ${opt} in
        c) RESET_ENV=true; FORCE_CLEAN=true ;;
        x) CLEAN_EXIT=true; RESET_ENV=true; CLEAN_ONLY=true; FORCE_CLEAN=true ;;
        p) AUTO_PASSWORD=true ;;
        y) AUTO_CONFIRM=true; AUTO_PASSWORD=true ;;
        a) ALLOW_PROTON_VPN=true ;;
        s) SELECTED_SERVICES="${OPTARG}" ;;
        D) DASHBOARD_ONLY=true ;;
        P) PERSONAL_MODE=true; AUTO_PASSWORD=true; AUTO_CONFIRM=true; PARALLEL_DEPLOY=true ;;
        j) PARALLEL_DEPLOY=true ;;
        S) SWAP_SLOTS=true ;;
        E) ENV_FILE="${OPTARG}" ;;
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
REQUIRED_COMMANDS="docker curl git crontab iptables flock"
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

# Paths
SRC_DIR="$BASE_DIR/sources"
ENV_DIR="$BASE_DIR/env"
CONFIG_DIR="$BASE_DIR/config"
DATA_DIR="$BASE_DIR/data"
COMPOSE_FILE="$BASE_DIR/docker-compose.yml"
DASHBOARD_FILE="$BASE_DIR/dashboard.html"
GLUETUN_ENV_FILE="$BASE_DIR/gluetun.env"
SECRETS_FILE="$BASE_DIR/.secrets"
ACTIVE_SLOT_FILE="$BASE_DIR/.active_slot"
BACKUP_DIR="$BASE_DIR/backups"
ASSETS_DIR="$BASE_DIR/assets"
HISTORY_LOG="$BASE_DIR/deployment.log"
CERT_BACKUP_DIR="/tmp/${APP_NAME}-cert-backup"
CERT_RESTORE=false
CERT_PROTECT=false

# Memos storage
MEMOS_HOST_DIR="$PROJECT_ROOT/data/AppData/memos"

$SUDO mkdir -p "$BASE_DIR" "$SRC_DIR" "$ENV_DIR" "$CONFIG_DIR" "$DATA_DIR" "$BACKUP_DIR" "$ASSETS_DIR" "$MEMOS_HOST_DIR"
BASE_DIR="$(cd "$BASE_DIR" && pwd)"
WG_PROFILES_DIR="$BASE_DIR/wg-profiles"
ACTIVE_WG_CONF="$BASE_DIR/active-wg.conf"
ACTIVE_PROFILE_NAME_FILE="$BASE_DIR/.active_profile_name"
$SUDO mkdir -p "$WG_PROFILES_DIR"

# Slot Management (A/B)
if [ ! -f "$ACTIVE_SLOT_FILE" ]; then
    echo "a" | $SUDO tee "$ACTIVE_SLOT_FILE" >/dev/null
fi
CURRENT_SLOT=$(cat "$ACTIVE_SLOT_FILE" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
if [[ "$CURRENT_SLOT" != "a" && "$CURRENT_SLOT" != "b" ]]; then
    CURRENT_SLOT="a"
    echo "a" | $SUDO tee "$ACTIVE_SLOT_FILE" >/dev/null
fi

CONTAINER_PREFIX="dhi-${CURRENT_SLOT}-"
export CURRENT_SLOT
UPDATE_STRATEGY="stable"
export UPDATE_STRATEGY

# Docker Auth Config (stored in /tmp to survive -c cleanup)
DOCKER_AUTH_DIR="/tmp/$APP_NAME-docker-auth"
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
DESEC_DOMAIN=""
DESEC_TOKEN=""
DESEC_MONITOR_DOMAIN=""
DESEC_MONITOR_TOKEN=""
SCRIBE_GH_USER=""
SCRIBE_GH_TOKEN=""
ODIDO_USER_ID=""
ODIDO_TOKEN=""
ODIDO_API_KEY=""
ODIDO_USE_VPN="true"
VERTD_PUB_URL=""
VERT_PUB_HOSTNAME=""
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
WG_API_SCRIPT="$BASE_DIR/wg-api.py"
CERT_MONITOR_SCRIPT="$BASE_DIR/cert-monitor.sh"
MIGRATE_SCRIPT="$BASE_DIR/migrate.sh"

# Port Definitions
PORT_DASHBOARD_WEB=8081
PORT_ADGUARD_WEB=8083
PORT_PORTAINER=9000
PORT_WG_WEB=51821
PORT_INVIDIOUS=3000
PORT_REDLIB=8080
PORT_WIKILESS=8180
PORT_RIMGO=3002
PORT_BREEZEWIKI=8380
PORT_ANONYMOUS=8480
PORT_SCRIBE=8280
PORT_MEMOS=5230
PORT_VERT=5555
PORT_VERTD=24153
PORT_COMPANION=8282
PORT_COBALT=9001
PORT_SEARXNG=8082
PORT_IMMICH=2283

# Internal Ports
PORT_INT_REDLIB=8080
PORT_INT_WIKILESS=8180
PORT_INT_INVIDIOUS=3000
PORT_INT_RIMGO=3002
PORT_INT_BREEZEWIKI=10416
PORT_INT_ANONYMOUS=8480
PORT_INT_VERT=80
PORT_INT_VERTD=24153
PORT_INT_COMPANION=8282
PORT_INT_COBALT=9000
PORT_INT_SEARXNG=8080
PORT_INT_IMMICH=2283

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
    log_info "Assigned Virtual Subnet: $DOCKER_SUBNET"
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
        LAN_IP=$(hostname -I | awk '{print $1}')
        if [ -z "$LAN_IP" ]; then
            LAN_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7}')
        fi
        if [ -z "$LAN_IP" ]; then
            log_crit "Failed to detect LAN IP. Please use LAN_IP_OVERRIDE."
            exit 1
        fi
        log_info "Detected LAN IP: $LAN_IP"
    else
        log_info "Using existing LAN IP: $LAN_IP"
    fi

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
    PK_VAL=$(grep "PrivateKey" "$ACTIVE_WG_CONF" | cut -d'=' -f2 | tr -d '[:space:]')
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

authenticate_registries() {
    # Export DOCKER_CONFIG globally
    export DOCKER_CONFIG="$DOCKER_AUTH_DIR"
    
    if [ "$AUTO_CONFIRM" = true ] || [ -n "$REG_TOKEN" ] || [ "$PERSONAL_MODE" = true ]; then
        if [ -n "$REG_TOKEN" ]; then
             log_info "Using provided credentials from environment."
        elif [ "$PERSONAL_MODE" = true ]; then
             log_info "Personal Mode: Using pre-configured registry credentials."
             REG_USER="${REG_USER:-}"
             REG_TOKEN="${REG_TOKEN:-}"
        else
             log_info "Auto-confirm enabled: Skipping registry authentication."
             REG_USER="${REG_USER:-}"
             REG_TOKEN="${REG_TOKEN:-}"
        fi
        
        # Docker Hub Login
        if [ -n "$REG_TOKEN" ] && [ "$REG_TOKEN" != "DOCKER_HUB_TOKEN_PLACEHOLDER" ]; then
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
        else
            log_info "Registry authentication skipped (no token provided)."
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
            VPN_PASS_RAW=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 24)
            AGH_PASS_RAW=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 24)
            ADMIN_PASS_RAW=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 24)
            PORTAINER_PASS_RAW=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 24)
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
            if [ "$PERSONAL_MODE" = true ]; then
                log_info "Personal Mode: Applying user-specific defaults."
                REG_USER="${REG_USER:-}"
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
        
        # Safely generate WG hash (using generic alpine to avoid GHCR pull)
        # wg-easy uses standard bcrypt for its PASSWORD_HASH
        WG_HASH_CLEAN=$($DOCKER_CMD run --rm alpine:3.21 sh -c 'apk add --no-cache apache2-utils >/dev/null 2>&1 && htpasswd -B -n -b "admin" "$1"' -- "$VPN_PASS_RAW" 2>/dev/null | cut -d ":" -f 2 || echo "FAILED")
        if [[ "$WG_HASH_CLEAN" == "FAILED" ]]; then
            log_crit "Failed to generate WireGuard password hash. Check Docker status."
            exit 1
        fi
        WG_HASH_ESCAPED="${WG_HASH_CLEAN//\\\$/\\\\\$\\$}"
        export WG_HASH_COMPOSE="$WG_HASH_ESCAPED"

        AGH_USER="adguard"
        # Safely generate AGH hash
        AGH_PASS_HASH=$($DOCKER_CMD run --rm alpine:3.21 sh -c 'apk add --no-cache apache2-utils >/dev/null 2>&1 && htpasswd -B -n -b "$1" "$2"' -- "$AGH_USER" "$AGH_PASS_RAW" 2>/dev/null | cut -d ":" -f 2 || echo "FAILED")
        if [[ "$AGH_PASS_HASH" == "FAILED" ]]; then
            log_crit "Failed to generate AdGuard password hash. Check Docker status."
            exit 1
        fi
        export AGH_USER AGH_PASS_HASH

        # Safely generate Portainer hash (bcrypt)
        PORTAINER_PASS_HASH=$($DOCKER_CMD run --rm alpine:3.21 sh -c 'apk add --no-cache apache2-utils >/dev/null 2>&1 && htpasswd -B -n -b "admin" "$1"' -- "$PORTAINER_PASS_RAW" 2>/dev/null | cut -d ":" -f 2 || echo "FAILED")
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
        SEARXNG_SECRET=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32)
        IMMICH_DB_PASSWORD=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32)

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
SEARXNG_SECRET="$SEARXNG_SECRET"
IMMICH_DB_PASSWORD="$IMMICH_DB_PASSWORD"
EOF
    else
        source "$BASE_DIR/.secrets"
        # Ensure all secrets are loaded/regenerated if missing
        if [ -z "${SCRIBE_SECRET:-}" ]; then SCRIBE_SECRET=$(head -c 64 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 64); echo "SCRIBE_SECRET=$SCRIBE_SECRET" >> "$BASE_DIR/.secrets"; fi
        if [ -z "${ANONYMOUS_SECRET:-}" ]; then ANONYMOUS_SECRET=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32); echo "ANONYMOUS_SECRET=$ANONYMOUS_SECRET" >> "$BASE_DIR/.secrets"; fi
        if [ -z "${IV_HMAC:-}" ]; then IV_HMAC=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 16); echo "IV_HMAC=$IV_HMAC" >> "$BASE_DIR/.secrets"; fi
        if [ -z "${IV_COMPANION:-}" ]; then IV_COMPANION=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 16); echo "IV_COMPANION=$IV_COMPANION" >> "$BASE_DIR/.secrets"; fi
        if [ -z "${SEARXNG_SECRET:-}" ]; then SEARXNG_SECRET=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32); echo "SEARXNG_SECRET=$SEARXNG_SECRET" >> "$BASE_DIR/.secrets"; fi
        if [ -z "${IMMICH_DB_PASSWORD:-}" ]; then IMMICH_DB_PASSWORD=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32); echo "IMMICH_DB_PASSWORD=$IMMICH_DB_PASSWORD" >> "$BASE_DIR/.secrets"; fi

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
            PORTAINER_PASS_HASH=$($DOCKER_CMD run --rm alpine:3.21 sh -c 'apk add --no-cache apache2-utils >/dev/null 2>&1 && htpasswd -B -n -b "admin" "$1"' -- "$PORTAINER_PASS_RAW" 2>/dev/null | cut -d ":" -f 2 || echo "FAILED")
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
