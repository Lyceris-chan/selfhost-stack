#!/usr/bin/env bash

# --- SECTION 0: ARGUMENT PARSING & INITIALIZATION ---
REG_USER="${REG_USER:-}"
REG_TOKEN="${REG_TOKEN:-}"
LAN_IP_OVERRIDE="${LAN_IP_OVERRIDE:-}"
WG_CONF_B64="${WG_CONF_B64:-}"

usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -c          Reset environment (recreates containers, preserves data)"
    echo "  -x          Factory Reset (⚠️ WIPES ALL CONTAINERS AND VOLUMES)"
    echo "  -p          Auto-Passwords (generates random secure credentials)"
    echo "  -y          Auto-Confirm (non-interactive mode)"
    echo "  -j          Parallel Deploy (faster builds, high CPU usage)"
    echo "  -S          Swap Slots (A/B update toggle)"
    echo "  -g <1-4>    Group Selection:"
    echo "                1: Essentials (Dashboard, DNS, VPN, Memos, Cobalt)"
    echo "                2: Search & Video (Essentials + Invidious, SearXNG)"
    echo "                3: Media & Heavy (Essentials + VERT, Immich)"
    echo "                4: Full Stack (Every service included in the repo)"
    echo "  -s <list>   Selective deployment (comma-separated list)"
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

while getopts "cxpyas:DPjShg:" opt; do
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
        g)
            case "${OPTARG}" in
                1) 
                    SELECTED_SERVICES="hub-api adguard unbound gluetun dashboard memos odido-booster cobalt" 
                    log_info "Selected Group 1: Essentials & Utilities"
                    ;;
                2) 
                    SELECTED_SERVICES="hub-api adguard unbound gluetun dashboard memos odido-booster cobalt invidious searxng" 
                    log_info "Selected Group 2: Essentials + Search & Video"
                    ;;
                3) 
                    SELECTED_SERVICES="hub-api adguard unbound gluetun dashboard memos odido-booster cobalt vert vertd immich" 
                    log_info "Selected Group 3: Essentials + Media & Conversion"
                    ;;
                4) 
                    SELECTED_SERVICES="hub-api adguard unbound gluetun dashboard scribe rimgo wikiless redlib breezewiki anonymousoverflow wg-easy portainer cobalt searxng immich invidious memos vert vertd odido-booster" 
                    log_info "Selected Group 4: Full Stack (Everything)"
                    ;;
                *) echo "Invalid group. Use 1, 2, 3, or 4."; exit 1 ;;
            esac
            ;;
        h) 
            usage
            exit 0
            ;;
        *) usage; exit 1 ;;
    esac
done
shift $((OPTIND -1))

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

APP_NAME="privacy-hub"
# Use absolute path for BASE_DIR to ensure it stays in the project root's data folder
PROJECT_ROOT="/workspaces/selfhost-stack"
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
