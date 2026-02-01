# RESTORED CORE.SH

# Source constants
source "${SCRIPT_DIR}/lib/core/constants.sh"

export APP_NAME="${APP_NAME:-privacy-hub}"
export CONTAINER_PREFIX="hub-"
export PROJECT_ROOT="${PROJECT_ROOT:-${SCRIPT_DIR}}"
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
export MONITOR_SCRIPT="${BASE_DIR}/wg-ip-monitor.sh"
export IP_LOG_FILE="${BASE_DIR}/ip-monitor.log"
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
export PYTHON_CMD="${PYTHON_CMD:-python3}"
export SUDO="${SUDO:-sudo}"
export CURL_CMD="${CURL_CMD:-curl}"
export SELECTED_SERVICES=""

log_info() { echo -e "[INFO] $1"; }
log_warn() { echo -e "[WARN] $1"; }
log_crit() { echo -e "[CRIT] $1"; }
ask_confirm() {
    local prompt="$1"
    if [[ "${AUTO_CONFIRM:-false}" == "true" ]]; then
        return 0
    fi
    local response
    read -r -p "${prompt} [y/N]: " response
    case "${response}" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
} 
safe_replace() {
    local file="$1"; local dest="$2"; shift 2
    sudo cp "$file" "$dest"
    sudo chown "$(id -u):$(id -g)" "$dest"
    
    # Use Python for safe literal string replacement to avoid sed delimiter collision
    while [[ $# -gt 0 ]]; do
        local target="$1"
        local replacement="$2"
        # We read, replace, and write back to the destination file
        # Using python3 -c to handle the file I/O and replacement safely
        "${PYTHON_CMD}" -c "
import sys
try:
    file_path = sys.argv[1]
    target = sys.argv[2]
    replacement = sys.argv[3]
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    new_content = content.replace(target, replacement)
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(new_content)
except Exception as e:
    sys.stderr.write(f'Error in safe_replace: {e}\\n')
    sys.exit(1)
" "$dest" "$target" "$replacement"
        shift 2
    done
}
is_service_enabled() {
    [[ -z "${SELECTED_SERVICES:-}" ]] && return 0
    echo "${SELECTED_SERVICES}" | grep -q "$1"
}
check_port_availability() {
    local port="$1"
    local proto="${2:-tcp}"
    
    "${PYTHON_CMD}" -c "
import socket, sys
try:
    sock_type = socket.SOCK_STREAM if '${proto}' == 'tcp' else socket.SOCK_DGRAM
    s = socket.socket(socket.AF_INET, sock_type)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('0.0.0.0', int('${port}')))
    s.close()
    sys.exit(0)
except Exception:
    sys.exit(1)
"
} 
init_directories() {
    mkdir -p "$BASE_DIR" "$CONFIG_DIR" "$ENV_DIR" "$DATA_DIR" "$ASSETS_DIR" "$WG_PROFILES_DIR" "$SRC_DIR" "$BACKUP_DIR"
}

detect_network() {
    log_info "Detecting network configuration..."
    
    # Public IP
    if [[ -z "${PUBLIC_IP:-}" ]] || [[ "${PUBLIC_IP}" == "127.0.0.1" ]]; then
        PUBLIC_IP=$(curl -s --max-time 5 https://api.ipify.org || echo "127.0.0.1")
    fi
    
    # LAN IP
    if [[ -n "${LAN_IP_OVERRIDE:-}" ]]; then
        LAN_IP="${LAN_IP_OVERRIDE}"
    elif [[ -z "${LAN_IP:-}" ]] || [[ "${LAN_IP}" == "127.0.0.1" ]]; then
        # Python one-liner to get LAN IP
        LAN_IP=$("${PYTHON_CMD}" -c "import socket; s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.connect(('9.9.9.9', 80)); print(s.getsockname()[0]); s.close()" 2>/dev/null || echo "127.0.0.1")
    fi
    
    export PUBLIC_IP
    export LAN_IP
    log_info "Network: Public=${PUBLIC_IP}, LAN=${LAN_IP}"
}

validate_wg_config() {
    # Check for Environment Variable (CI/Test Mode)
    if [[ -n "${WG_CONF_B64:-}" ]]; then
        # Decode and validate
        local decoded
        decoded=$(echo "${WG_CONF_B64}" | base64 -d 2>/dev/null)
        if echo "${decoded}" | grep -q "\[Interface\]"; then
             # Write to file if not exists or override
             mkdir -p "$(dirname "${ACTIVE_WG_CONF}")"
             echo "${decoded}" > "${ACTIVE_WG_CONF}"
             chmod 600 "${ACTIVE_WG_CONF}"
             return 0
        fi
    fi

    # Check for Existing File
    if [[ -f "${ACTIVE_WG_CONF}" ]] && grep -q "\[Interface\]" "${ACTIVE_WG_CONF}"; then
        return 0
    fi

    return 1
}

# Certificate verification helper using containerized Python
# We use python:3.11-alpine to ensure a consistent environment and avoid host dependencies.
verify_cert() {
    local cert_path="$1"
    local domain="$2"
    
    if [[ ! -f "${cert_path}" ]]; then
        return 1
    fi

    # Run verification inside a container to guarantee Python 3.11 availability
    # and consistency of the internal ssl API we are using.
    docker run --rm -v "${cert_path}:/cert.pem" python:3.11-alpine python3 -c "
import ssl, sys, datetime
try:
    # _test_decode_cert is an internal API but stable in 3.11 (pinned image)
    cert = ssl._ssl._test_decode_cert('/cert.pem')
    
    # Check expiry (within 24h)
    not_after = datetime.datetime.strptime(cert['notAfter'], '%b %d %H:%M:%S %Y %Z')
    if not_after < datetime.datetime.utcnow() + datetime.timedelta(days=1):
        sys.exit(2) # Expired or expiring soon
    
    # Check Subject/CN
    subject = dict(x[0] for x in cert['subject'])
    cn = subject.get('commonName', '')
    if cn != '${domain}':
        sys.exit(3) # Domain mismatch
        
    # Check Issuer (Self-signed check)
    issuer = dict(x[0] for x in cert['issuer'])
    if issuer == subject:
        sys.exit(4) # Self-signed
        
    sys.exit(0)
except Exception as e:
    sys.exit(1)
"
}

allocate_subnet() {
    log_info "Allocating conflict-free Docker subnet..."
    local octet=20
    while true; do
        if [[ $octet -gt 31 ]]; then
            log_crit "No available 172.x.0.0/16 subnets found (checked 20-31)."
            exit 1
        fi
        local candidate="172.${octet}.0.0/16"
        
        # Check Docker networks (handle empty list)
        local net_ids
        net_ids=$(docker network ls -q 2>/dev/null || true)
        if [[ -n "${net_ids}" ]]; then
             if docker network inspect ${net_ids} 2>/dev/null | grep -q "${candidate}"; then
                log_warn "Subnet ${candidate} is in use by Docker. Trying next..."
                ((octet++))
                continue
             fi
        fi

        # Check Host Routes
        if ip route | grep -q "172.${octet}."; then
            log_warn "Subnet ${candidate} overlaps with host routes. Trying next..."
            ((octet++))
            continue
        fi
        
        export FOUND_OCTET="${octet}"
        export DOCKER_SUBNET="${candidate}"
        log_info "Selected subnet: ${DOCKER_SUBNET}"
        break
    done
}
generate_protonpass_export() {
    log_info "Skipping Proton Pass export (mocked)."
}
finalize_permissions() {
    log_info "Finalizing permissions..."
    sudo chown -R "$(id -u):$(id -g)" "${BASE_DIR}"
}
export -f docker_compose_wrapper