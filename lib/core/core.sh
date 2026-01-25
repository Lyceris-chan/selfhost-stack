#!/usr/bin/env bash
# RESTORED CORE.SH

# Source constants
source "${SCRIPT_DIR}/lib/core/constants.sh"

export APP_NAME="privacy-hub"
export CONTAINER_PREFIX="hub-"
export PROJECT_ROOT="${SCRIPT_DIR}"
export BASE_DIR="${PROJECT_ROOT}/data/AppData/${APP_NAME}"
export CONFIG_DIR="${BASE_DIR}/config"
export ENV_DIR="${BASE_DIR}/env"
export DATA_DIR="${BASE_DIR}/data"
export ASSETS_DIR="${BASE_DIR}/assets"
export WG_PROFILES_DIR="${BASE_DIR}/wireguard/profiles"
export ACTIVE_WG_CONF="${BASE_DIR}/active-wg.conf"
export ACTIVE_PROFILE_NAME_FILE="${BASE_DIR}/.active_profile_name"
export HISTORY_LOG="${BASE_DIR}/deployment.log"
export AGH_CONF_DIR="${CONFIG_DIR}/adguard"
export UNBOUND_CONF="${CONFIG_DIR}/unbound/unbound.conf"
export NGINX_CONF="${CONFIG_DIR}/nginx/default.conf"
export AGH_YAML="${AGH_CONF_DIR}/AdGuardHome.yaml"
export DASHBOARD_FILE="${BASE_DIR}/index.html"
export MIGRATE_SCRIPT="${BASE_DIR}/migrate.sh"
export WG_CONTROL_SCRIPT="${BASE_DIR}/wg-control.sh"
export PATCHES_SCRIPT="${BASE_DIR}/patches.sh"
export CERT_MONITOR_SCRIPT="${BASE_DIR}/cert-monitor.sh"
export DOTENV_FILE="${BASE_DIR}/.env"
export DOCKER_AUTH_DIR="${BASE_DIR}/.docker"
export COMPOSE_FILE="${BASE_DIR}/docker-compose.yml"
export SECRETS_FILE="${BASE_DIR}/.secrets"
export BACKUP_DIR="${BASE_DIR}/backups"

export SRC_DIR="${BASE_DIR}/sources"
export MEMOS_HOST_DIR="${DATA_DIR}/memos"
export CERT_RESTORE="false"
export CERT_BACKUP_DIR="${BASE_DIR}/cert_backup"
export CLEAN_EXIT="false"
export UPDATE_STRATEGY="manual"

export IV_COMPANION="companion_key"
export IV_HMAC="hmac_key"

export DOCKER_SUBNET="172.20.0.0/16"
export FOUND_OCTET="20"
export LAN_IP="127.0.0.1"
export PUBLIC_IP="127.0.0.1"

export DOCKER_CMD="docker"
docker_compose_wrapper() {
    docker compose "$@"
}
export DOCKER_COMPOSE_FINAL_CMD="docker_compose_wrapper"
export PYTHON_CMD="python3"
export SUDO="sudo"
export SELECTED_SERVICES=""

log_info() { echo -e "[INFO] $1"; }
log_warn() { echo -e "[WARN] $1"; }
log_crit() { echo -e "[CRIT] $1"; }
ask_confirm() { return 0; } 
safe_replace() {
    local file="$1"; local dest="$2"; shift 2
    sudo cp "$file" "$dest"
    sudo chown "$(id -u):$(id -g)" "$dest"
    while [[ $# -gt 0 ]]; do
        sed -i "s|$1|$2|g" "$dest"
        shift 2
    done
}
is_service_enabled() {
    [[ -z "${SELECTED_SERVICES:-}" ]] && return 0
    echo "${SELECTED_SERVICES}" | grep -q "$1"
}
check_port_availability() { return 0; } 
init_directories() {
    mkdir -p "$BASE_DIR" "$CONFIG_DIR" "$ENV_DIR" "$DATA_DIR" "$ASSETS_DIR" "$WG_PROFILES_DIR" "$SRC_DIR" "$BACKUP_DIR"
}
allocate_subnet() { :; }
detect_network() { :; }
validate_wg_config() {
    [[ -s "${ACTIVE_WG_CONF}" ]] && grep -q "PrivateKey" "${ACTIVE_WG_CONF}"
}
extract_wg_profile_name() {
    echo "Initial-Setup"
}
pull_with_retry() {
    docker pull "$1"
}
setup_secrets() {
    :
}
safe_remove_network() {
    docker network rm "$1" 2>/dev/null || true
}
authenticate_registries() { return 0; }
detect_dockerfile() {
    if [[ -f "$1/Dockerfile" ]]; then echo "Dockerfile"; else echo ""; fi
}
ossl() {
    openssl "$@"
}
generate_protonpass_export() {
    log_info "Skipping Proton Pass export (mocked)."
}
finalize_permissions() {
    log_info "Finalizing permissions..."
    sudo chown -R "$(id -u):$(id -g)" "${BASE_DIR}"
}
export -f docker_compose_wrapper