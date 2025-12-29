#!/usr/bin/env bash

# --- SECTION 0: ARGUMENT PARSING & INITIALIZATION ---
REG_USER="${REG_USER:-}"
REG_TOKEN="${REG_TOKEN:-}"
LAN_IP_OVERRIDE="${LAN_IP_OVERRIDE:-}"
WG_CONF_B64="${WG_CONF_B64:-}"

usage() {
    echo "Usage: $0 [-c (reset environment)] [-x (cleanup and exit)] [-p (auto-passwords)] [-y (auto-confirm)] [-a (allow Proton VPN)] [-s services)] [-D (dashboard only)] [-P (personal mode)] [-j (parallel deploy)] [-X (enable xray)] [-S (swap slots/update)] [-h]"
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
ENABLE_XRAY="false"
SWAP_SLOTS=false

while getopts "cxpyas:DPjXSh" opt; do
    case ${opt} in
        c) RESET_ENV=true; FORCE_CLEAN=true ;;
        x) CLEAN_EXIT=true; RESET_ENV=true; CLEAN_ONLY=true; FORCE_CLEAN=true ;;
        p) AUTO_PASSWORD=true ;;
        y) AUTO_CONFIRM=true ;;
        a) ALLOW_PROTON_VPN=true ;;
        s) SELECTED_SERVICES="${OPTARG}" ;;
        D) DASHBOARD_ONLY=true ;;
        P) PERSONAL_MODE=true; AUTO_PASSWORD=true; AUTO_CONFIRM=true; PARALLEL_DEPLOY=true ;;
        j) PARALLEL_DEPLOY=true ;;
        X) ENABLE_XRAY="true" ;;
        S) SWAP_SLOTS=true ;;
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
# Slot Management (A/B)
if [ ! -f "$ACTIVE_SLOT_FILE" ]; then
    echo "a" > "$ACTIVE_SLOT_FILE"
fi
CURRENT_SLOT=$(cat "$ACTIVE_SLOT_FILE" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
if [[ "$CURRENT_SLOT" != "a" && "$CURRENT_SLOT" != "b" ]]; then
    CURRENT_SLOT="a"
    echo "a" > "$ACTIVE_SLOT_FILE"
fi

CONTAINER_PREFIX="dhi-${CURRENT_SLOT}-"
export CURRENT_SLOT
BASE_DIR="./DATA/AppData/$APP_NAME"
UPDATE_STRATEGY="stable"
export UPDATE_STRATEGY
mkdir -p "$BASE_DIR"
BASE_DIR="$(cd "$BASE_DIR" && pwd)"

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
ENABLE_XRAY="false"
XRAY_DOMAIN=""
XRAY_UUID=""
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
WG_API_SCRIPT="$BASE_DIR/wg-api.py"
CERT_MONITOR_SCRIPT="$BASE_DIR/cert-monitor.sh"
MIGRATE_SCRIPT="$BASE_DIR/migrate.sh"

# Memos storage
MEMOS_HOST_DIR="./DATA/AppData/memos"
mkdir -p "$MEMOS_HOST_DIR"
MEMOS_HOST_DIR="$(cd "$MEMOS_HOST_DIR" && pwd)"
