#!/usr/bin/env bash
################################################################################
# PRIVACY HUB - CORE LIBRARY
################################################################################
#
# Core utility functions for Privacy Hub deployment and management.
# Provides foundational functionality including logging, Docker operations,
# service detection, and error handling.
#
# Architecture:
#   - Utility functions for common operations
#   - Docker and Docker Compose wrappers
#   - Service lifecycle management
#   - Logging system with severity levels
#   - Error handling and validation
#
# Key Components:
#   - Dockerfile detection and validation
#   - Service dependency resolution
#   - Port availability checking
#   - Version comparison utilities
#   - Tag resolution for container images
#
# Dependencies:
#   - bash 4.0+
#   - docker / docker-compose
#   - constants.sh (port and service definitions)
#
# Usage:
#   Source this file from main orchestration script (zima.sh)
#   Functions are called by service-specific modules
#
# Style Guide:
#   Adheres to Google Shell Style Guide
#   - Function documentation using header blocks
#   - Error handling with set -euo pipefail
#   - Readonly variables for constants
#   - Local variables in functions
#
# References:
#   - Google Shell Style Guide
#   - Docker Compose specification
#   - Bash best practices
#
# Author: ZimaOS Privacy Hub Team
# Version: 2.0.0
################################################################################

set -euo pipefail

# Source Consolidated Constants
# SCRIPT_DIR is exported from zima.sh
source "${SCRIPT_DIR}/lib/core/constants.sh"

################################################################################
# detect_dockerfile - Locate the appropriate Dockerfile in a repository
# Arguments:
#   $1 - Repository directory path
#   $2 - Preferred Dockerfile name (optional)
# Returns:
#   0 if a Dockerfile is found, 1 otherwise
# Outputs:
#   Prints the relative path to the found Dockerfile to stdout
################################################################################
detect_dockerfile() {
	local repo_dir="$1"
	local preferred="${2:-}"
	local found=""

	if [[ -n "${preferred}" ]] && [[ -f "${repo_dir}/${preferred}" ]]; then
		echo "${preferred}"
		return 0
	fi

	if [[ -f "${repo_dir}/Dockerfile.alpine" ]]; then
		echo "Dockerfile.alpine"
		return 0
	fi

	if [[ -f "${repo_dir}/Dockerfile" ]]; then
		echo "Dockerfile"
		return 0
	fi

	if [[ -f "${repo_dir}/docker/Dockerfile" ]]; then
		echo "docker/Dockerfile"
		return 0
	fi

	# Search deeper
	found=$(find "${repo_dir}" -maxdepth 3 -type f -name 'Dockerfile*' -not -path '*/.*' 2>/dev/null | head -n 1 || true)
	if [[ -n "${found}" ]]; then
		echo "${found#"$repo_dir/"}"
		return 0
	fi

	return 1
}

################################################################################
# Logging Functions
#
# Core logging functions that output to terminal and persist JSON formatted
# logs for dashboard consumption. Uses Python for secure JSON escaping to
# prevent injection attacks.
################################################################################

################################################################################
# log_to_file - Internal JSON log writer
#
# Writes structured JSON log entries to the deployment history log file.
# This function is used internally by log_info, log_warn, and log_crit.
#
# Globals:
#   HISTORY_LOG
#   PYTHON_CMD
# Arguments:
#   $1 - Log level (INFO, WARN, CRIT)
#   $2 - Log message
# Outputs:
#   Appends a JSON line to the history log file
################################################################################
log_to_file() {
	local level="$1"
	local msg="$2"
	local log_dir
	log_dir=$(dirname "${HISTORY_LOG}")

	if [[ -d "${log_dir}" ]]; then
		"${PYTHON_CMD}" -c "import json, datetime, sys; print(json.dumps({'timestamp': datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S'), 'level': sys.argv[1], 'category': 'SYSTEM', 'source': 'orchestrator', 'message': sys.argv[2]}))" "${level}" "${msg}" >>"${HISTORY_LOG}" 2>/dev/null || true
	fi
}

################################################################################
# log_info - Print and log an informational message
# Arguments:
#   $1 - Message to log
# Outputs:
#   Writes to stdout and the history log
################################################################################
log_info() {
	local msg="$1"
	echo -e "\e[34m  ➜ [INFO]\e[0m ${msg}"
	log_to_file "INFO" "${msg}"
}

################################################################################
# log_warn - Print and log a warning message
# Arguments:
#   $1 - Message to log
# Outputs:
#   Writes to stdout and the history log
################################################################################
log_warn() {
	local msg="$1"
	echo -e "\e[33m  ⚠️ [WARN]\e[0m ${msg}"
	log_to_file "WARN" "${msg}"
}

################################################################################
# log_crit - Print and log a critical error message
# Arguments:
#   $1 - Message to log
# Outputs:
#   Writes to stderr and the history log
################################################################################
log_crit() {
	local msg="$1"
	echo -e "\e[31m  ✖ [CRIT]\e[0m ${msg}"
	log_to_file "CRIT" "${msg}"
}

################################################################################
# ask_confirm - Prompt the user for confirmation
# Globals:
#   AUTO_CONFIRM
# Arguments:
#   $1 - Prompt message
# Returns:
#   0 if confirmed, 1 otherwise
################################################################################
ask_confirm() {
	local prompt="$1"
	local response

	if [[ "${AUTO_CONFIRM}" == "true" ]]; then
		return 0
	fi

	read -r -p "${prompt} [y/N]: " response
	case "${response}" in
	[yY][eE][sS] | [yY]) return 0 ;;
	*) return 1 ;;
	esac
}

################################################################################
# pull_with_retry - Attempt to pull a docker image
# Globals:
#   DOCKER_CMD
# Arguments:
#   $1 - Image name
# Returns:
#   0 if successful, 1 otherwise
################################################################################
pull_with_retry() {
	local img="$1"
	# Always attempt to pull if tag is :latest or FORCE_UPDATE is enabled
	if [[ "${img}" == *":latest" ]] || [[ "${FORCE_UPDATE:-false}" == "true" ]]; then
		log_info "Attempting to pull newest version of ${img}..."
		if "${DOCKER_CMD}" pull "${img}"; then
			return 0
		fi
		# Fallback to local if pull fails (e.g. offline)
		if "${DOCKER_CMD}" image inspect "${img}" >/dev/null 2>&1; then
			log_warn "Pull failed for ${img}. Using existing local version."
			return 0
		fi
	else
		if "${DOCKER_CMD}" image inspect "${img}" >/dev/null 2>&1; then
			log_info "Image ${img} exists locally. Skipping pull."
			return 0
		fi
	fi

	if "${DOCKER_CMD}" pull "${img}"; then
		log_info "Successfully pulled ${img}"
		return 0
	fi
	log_crit "Failed to pull critical image ${img}."
	return 1
}

################################################################################
# authenticate_registries - Log in to Docker registries if credentials provided
# Globals:
#   REG_USER
#   REG_TOKEN
#   DOCKER_CMD
# Returns:
#   0 if successful or no credentials, 1 on failure
################################################################################
authenticate_registries() {
	if [[ -n "${REG_USER:-}" ]] && [[ -n "${REG_TOKEN:-}" ]]; then
		log_info "Authenticating with Docker Registry..."
		# Use printf to avoid issues with special characters in token
		if printf "%s" "${REG_TOKEN}" | ${DOCKER_CMD} login -u "${REG_USER}" --password-stdin >/dev/null 2>&1; then
			log_info "Registry authentication successful."
			return 0
		else
			log_warn "Registry authentication failed. Continuing as anonymous."
			return 1
		fi
	fi
	return 0
}

################################################################################
# safe_replace - Perform a string replacement in a template file
# Arguments:
#   $1 - Template file path
#   $2 - Output file path
#   $@ - Pairs of placeholder and replacement value
# Returns:
#   0 if successful, 1 otherwise
################################################################################
safe_replace() {
	local template_file="$1"
	local output_file="$2"
	shift 2

	if [[ ! -f "${template_file}" ]]; then
		log_warn "Template file not found: ${template_file}"
		return 1
	fi

	local content
	content=$(cat "${template_file}")
	while [[ $# -gt 0 ]]; do
		local placeholder="$1"
		local value="$2"
		# Use bash parameter expansion for global replacement
		content="${content//"$placeholder"/"$value"}"
		shift 2
	done
	printf "%s" "${content}" >"${output_file}"
}

################################################################################
# generate_secret - Generate a random alphanumeric string
# Arguments:
#   $1 - Desired length (default: 32)
# Outputs:
#   Prints the generated secret to stdout
################################################################################
generate_secret() {
	local length="${1:-32}"
	head -c 64 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c "${length}"
}

################################################################################
# generate_hash - Generate a bcrypt hash for a password
# Arguments:
#   $1 - Username
#   $2 - Password
# Returns:
#   0 if successful, 1 on failure
# Outputs:
#   Prints the generated hash to stdout
################################################################################
generate_hash() {
	local user="$1"
	local pass="$2"
	local hash=""

	# Method 1: Try host Python (if crypt/bcrypt supported)
	if command -v "${PYTHON_CMD}" >/dev/null 2>&1; then
		# Try to use crypt module with bcrypt salt
		hash=$("${PYTHON_CMD}" -c "import crypt, random, string, sys; salt = '\$2b\$12\$' + ''.join(random.choices(string.ascii_letters + string.digits, k=22)); print(crypt.crypt(sys.argv[1], salt))" "${pass}" 2>/dev/null || true)
	fi

	# Method 2: Try host htpasswd
	if [[ -z "${hash}" ]] && command -v htpasswd >/dev/null 2>&1; then
		hash=$(htpasswd -B -n -b "${user}" "${pass}" | cut -d: -f2 || true)
	fi

	# Method 3: Docker Fallback (Alpine)
	if [[ -z "${hash}" ]]; then
		hash=$("${DOCKER_CMD}" run --rm alpine:3.21 sh -c 'apk add --no-cache apache2-utils >/dev/null 2>&1 && htpasswd -B -n -b "$1" "$2"' -- "${user}" "${pass}" 2>/dev/null | cut -d: -f2 || echo "FAILED")
	fi

	if [[ -n "${hash}" ]] && [[ "${hash}" != "FAILED" ]]; then
		# Portainer compatibility: Normalize $2y$ (Apache variant) to $2b$ (standard)
		echo "${hash//\$2y\$/\$2b\$}"
		return 0
	fi

	echo "FAILED"
	return 1
}

# Initialize globals
FORCE_CLEAN=false
CLEAN_ONLY=false
AUTO_PASSWORD=false
CLEAN_EXIT=false
RESET_ENV=false
AUTO_CONFIRM="${AUTO_CONFIRM:-false}"
ALLOW_PROTON_VPN=false
SELECTED_SERVICES=""
PARALLEL_DEPLOY=false
GENERATE_ONLY=false
DO_BACKUP=false
RESTORE_FILE=""
ENV_FILE=""
PERSONAL_MODE=false
REG_TOKEN="${REG_TOKEN:-}"
REG_USER="${REG_USER:-}"
LAN_IP_OVERRIDE=""
WG_CONF_B64="${WG_CONF_B64:-}"

################################################################################
# usage - Display script usage information
# Arguments:
#   None
# Outputs:
#   Writes usage help to stdout
################################################################################
usage() {
	echo "Usage: $0 [options]"
	echo ""
	echo "Options:"
	echo "  -x          Factory Reset (wipes all data)"
	echo "  -a          Allow ProtonVPN domains (whitelist for browser extensions)"
	echo "  -p          Auto-Generate Passwords (skip prompts)"
	echo "  -y          Auto-Confirm (Reserved for automated testing)"
	echo "  -j          Parallel Deploy (faster builds, high CPU usage)"
	echo "  -s <list>   Selective deployment (comma-separated list, e.g., -s invidious,memos)"
	echo "  -o          Skip Odido Bundle Booster deployment"
	echo "  -c          Maintenance (recreates containers, preserves data)"
	echo "  -b          Create a system backup"
	echo "  -r <file>   Restore from a system backup file"
	echo "  -E <file>   Load Environment Variables from file"
	echo "  -G          Generate Only (stops before deployment)"
	echo "  -h          Show this help message"
}

################################################################################
# parse_args - Parse command line arguments
# Arguments:
#   $@ - Command line arguments
# Returns:
#   None
################################################################################
parse_args() {
	local opt
	while getopts "cxpyas:j hE:Gobr:" opt; do
		case ${opt} in
		c)
			RESET_ENV=true
			FORCE_CLEAN=true
			;;
		x)
			CLEAN_EXIT=true
			RESET_ENV=true
			CLEAN_ONLY=true
			FORCE_CLEAN=true
			;;
		p) AUTO_PASSWORD=true ;;
		y)
			AUTO_CONFIRM=true
			AUTO_PASSWORD=true
			;;
		a) ALLOW_PROTON_VPN=true ;;
		s) SELECTED_SERVICES="${OPTARG}" ;;
		o) SKIP_ODIDO=true ;;
		j) PARALLEL_DEPLOY=true ;;
		E) ENV_FILE="${OPTARG}" ;;
		G) GENERATE_ONLY=true ;;
		b) DO_BACKUP=true ;;
		r) RESTORE_FILE="${OPTARG}" ;;
		h)
			usage
			exit 0
			;;
		*)
			usage
			exit 1
			;;
		esac
	done
	shift $((OPTIND - 1))
}

parse_args "$@"

SKIP_ODIDO="${SKIP_ODIDO:-false}"

# Handle odido-booster exclusion logic
if [ "$SKIP_ODIDO" = true ]; then
	if [ -z "$SELECTED_SERVICES" ]; then
		# Dynamically remove odido-booster from the full stack list
		SELECTED_SERVICES=$(echo "$STACK_SERVICES" | sed 's/\bodido-booster\b//g' | sed 's/  */ /g' | sed 's/^ //;s/ $//' | tr ' ' ',')
	else
		# Remove odido-booster from the list if it's there
		SELECTED_SERVICES=$(echo "$SELECTED_SERVICES" | sed 's/\bodido-booster\b//g' | sed 's/,,/,/g' | sed 's/^,//' | sed 's/,$//')
	fi
fi

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

# Suppress git advice/warnings for cleaner logs during automated clones
export GIT_CONFIG_PARAMETERS="'advice.detachedHead=false'"

# Verify core dependencies before proceeding.
REQUIRED_COMMANDS="docker curl git crontab iptables flock jq awk sed grep find tar ip"
if [ "$(id -u)" -ne 0 ] && ! command -v sudo >/dev/null 2>&1; then
	if [[ "${SKIP_SUDO_CHECK:-false}" != "true" ]]; then
		echo "[CRIT] sudo is required for non-root users. Please install it."
		exit 1
	fi
fi
for cmd in $REQUIRED_COMMANDS; do
	if ! command -v "$cmd" >/dev/null 2>&1; then
		echo "[CRIT] '$cmd' is required but not installed. Please install it."
		exit 1
	fi
done

# Detect if sudo is available
if command -v sudo >/dev/null 2>&1; then
	SUDO="sudo"
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
readonly SRC_DIR="$BASE_DIR/sources"
readonly ENV_DIR="$BASE_DIR/env"
readonly CONFIG_DIR="$BASE_DIR/config"
readonly DATA_DIR="$BASE_DIR/data"
export DATA_DIR
readonly COMPOSE_FILE="$BASE_DIR/docker-compose.yml"
readonly DASHBOARD_FILE="$BASE_DIR/dashboard.html"
readonly SECRETS_FILE="$BASE_DIR/.secrets"
BACKUP_DIR="${BACKUP_DIR:-$BASE_DIR/backups}"
export BACKUP_DIR
readonly ASSETS_DIR="$BASE_DIR/assets"
readonly HISTORY_LOG="$BASE_DIR/deployment.log"
readonly CERT_BACKUP_DIR="$PROJECT_ROOT/data/AppData/.cert-backups/$APP_NAME"
CERT_RESTORE=false
CERT_PROTECT=false

# Memos storage
readonly MEMOS_HOST_DIR="$PROJECT_ROOT/data/AppData/memos"

# WireGuard & Profiles
readonly WG_PROFILES_DIR="$BASE_DIR/wg-profiles"
readonly ACTIVE_WG_CONF="$BASE_DIR/active-wg.conf"
readonly ACTIVE_PROFILE_NAME_FILE="$BASE_DIR/.active_profile_name"
readonly DOTENV_FILE="$BASE_DIR/.env"

################################################################################
# init_directories - Create and set permissions for necessary directories
# Globals:
#   SRC_DIR, ENV_DIR, CONFIG_DIR, DATA_DIR, BACKUP_DIR, ASSETS_DIR,
#   MEMOS_HOST_DIR, WG_PROFILES_DIR, DOTENV_FILE, ACTIVE_WG_CONF,
#   HISTORY_LOG, ACTIVE_PROFILE_NAME_FILE, BASE_DIR
# Returns:
#   None
################################################################################
init_directories() {
	log_info "Initializing project directories..."
	$SUDO mkdir -p "$SRC_DIR" "$ENV_DIR" "$CONFIG_DIR" "$DATA_DIR" "$BACKUP_DIR" "$ASSETS_DIR" "$MEMOS_HOST_DIR" "$DATA_DIR/hub-api" "$WG_PROFILES_DIR"
	$SUDO chown "$(whoami)" "$BASE_DIR" "$SRC_DIR" "$ENV_DIR" "$CONFIG_DIR" "$BACKUP_DIR" "$ASSETS_DIR" "$WG_PROFILES_DIR"
	$SUDO chown -R 1000:1000 "$BASE_DIR"
}

################################################################################
# finalize_permissions - Ensure consistent ownership of all project files
# Globals:
#   SUDO, BASE_DIR
################################################################################
finalize_permissions() {
	log_info "Finalizing file permissions..."
	$SUDO chown -R 1000:1000 "$BASE_DIR"
}

# Container naming and persistence
CONTAINER_PREFIX="hub-"
export CONTAINER_PREFIX

UPDATE_STRATEGY="stable"
export UPDATE_STRATEGY

# Docker Auth Config
DOCKER_AUTH_DIR="${PH_DOCKER_AUTH_DIR:-$BASE_DIR/.docker}"
# Ensure clean state for auth only if it doesn't already have a config
if [[ ! -d "${DOCKER_AUTH_DIR}" ]]; then
	${SUDO} mkdir -p "${DOCKER_AUTH_DIR}"
fi
# Always ensure ownership of the auth directory and its contents
${SUDO} chown -R "$(whoami)" "${DOCKER_AUTH_DIR}"

# Detect Python interpreter
if command -v python3 >/dev/null 2>&1; then
	PYTHON_CMD="python3"
elif command -v python >/dev/null 2>&1; then
	PYTHON_CMD="python"
else
	echo "[CRIT] Python is required but not installed. Please install python3."
	exit 1
fi

################################################################################
# docker_cmd - Execute a docker command with proper SUDO and config
# Globals:
#   SUDO, DOCKER_AUTH_DIR
# Arguments:
#   $@ - Docker arguments
# Returns:
#   Exit status of the docker command
################################################################################
docker_cmd() {
	if [[ -n "${SUDO:-}" ]]; then
		${SUDO} env DOCKER_CONFIG="${DOCKER_AUTH_DIR}" GOTOOLCHAIN=auto docker "$@"
	else
		env DOCKER_CONFIG="${DOCKER_AUTH_DIR}" GOTOOLCHAIN=auto docker "$@"
	fi
}

################################################################################
# docker_compose_cmd - Execute a docker compose command with proper SUDO and config
# Globals:
#   SUDO, DOCKER_AUTH_DIR, DOCKER_COMPOSE_CMD
# Arguments:
#   $@ - Docker compose arguments
# Returns:
#   Exit status of the docker compose command
################################################################################
docker_compose_cmd() {
	if [[ -n "${SUDO:-}" ]]; then
		${SUDO} env DOCKER_CONFIG="${DOCKER_AUTH_DIR}" GOTOOLCHAIN=auto ${DOCKER_COMPOSE_CMD} "$@"
	else
		env DOCKER_CONFIG="${DOCKER_AUTH_DIR}" GOTOOLCHAIN=auto ${DOCKER_COMPOSE_CMD} "$@"
	fi
}

# Replace variables with function calls in existing code (conceptually, but here we just redefine the variables to call the functions if needed, or better, update the scripts to call the functions)
# For compatibility with existing scripts using $DOCKER_CMD:
DOCKER_CMD="docker_cmd"
DOCKER_COMPOSE_FINAL_CMD="docker_compose_cmd"

################################################################################
# ossl - Execute an openssl command with docker fallback if necessary
# Globals:
#   BASE_DIR
# Arguments:
#   $@ - OpenSSL arguments
# Returns:
#   Exit status of the openssl command
################################################################################
ossl() {
	if command -v openssl >/dev/null 2>&1; then
		openssl "$@"
	else
		# Fallback to docker using acme.sh image which contains openssl
		# We use -v to mount the current directory so relative paths might work if they are under BASE_DIR
		# But for more reliability, callers should use absolute paths if possible or we can mount BASE_DIR
		"${DOCKER_CMD}" run --rm --entrypoint openssl -v "${BASE_DIR}:${BASE_DIR}:ro" -w "$(pwd)" neilpang/acme.sh:latest "$@"
	fi
}

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
INVIDIOUS_DB_PASSWORD=""
IMMICH_ADMIN_PASS_RAW=""
IV_HMAC=""
IV_COMPANION=""

# Service Configurations
readonly NGINX_CONF_DIR="$CONFIG_DIR/nginx"
readonly NGINX_CONF="$NGINX_CONF_DIR/default.conf"
readonly UNBOUND_CONF="$CONFIG_DIR/unbound/unbound.conf"
readonly BREEZEWIKI_CONF="$CONFIG_DIR/breezewiki/breezewiki.ini"
readonly AGH_CONF_DIR="$CONFIG_DIR/adguard"
readonly AGH_YAML="$AGH_CONF_DIR/AdGuardHome.yaml"

# Scripts
readonly MONITOR_SCRIPT="$BASE_DIR/wg-ip-monitor.sh"
readonly IP_LOG_FILE="$BASE_DIR/wg-ip-monitor.log"
readonly CURRENT_IP_FILE="$BASE_DIR/.current_public_ip"
readonly WG_CONTROL_SCRIPT="$BASE_DIR/wg-control.sh"
readonly WG_API_SCRIPT="$BASE_DIR/wg-api.py"
readonly CERT_MONITOR_SCRIPT="$BASE_DIR/cert-monitor.sh"
readonly MIGRATE_SCRIPT="$BASE_DIR/migrate.sh"
readonly PATCHES_SCRIPT="$BASE_DIR/patches.sh"

# Ensure root-level data files are writable by the container user (UID 1000)
$SUDO touch "$HISTORY_LOG" "$ACTIVE_WG_CONF" "$BASE_DIR/.data_usage" "$BASE_DIR/.wge_data_usage"
if [ ! -f "$ACTIVE_PROFILE_NAME_FILE" ]; then echo "Initial-Setup" | $SUDO tee "$ACTIVE_PROFILE_NAME_FILE" >/dev/null; fi
$SUDO chmod 666 "$HISTORY_LOG" 2>/dev/null || true
$SUDO chmod 644 "$ACTIVE_PROFILE_NAME_FILE" "$BASE_DIR/.data_usage" "$BASE_DIR/.wge_data_usage"
$SUDO chown 1000:1000 "$HISTORY_LOG" "$ACTIVE_WG_CONF" "$BASE_DIR/.data_usage" "$BASE_DIR/.wge_data_usage" "$ACTIVE_PROFILE_NAME_FILE" 2>/dev/null || true
$SUDO chown -R 1000:1000 "$DATA_DIR" "$MEMOS_HOST_DIR" "$ASSETS_DIR" 2>/dev/null || true

################################################################################
# allocate_subnet - Find an available 172.x.0.0/16 subnet for Docker isolation
# Globals:
#   DOCKER_CMD
#   FOUND_OCTET
#   DOCKER_SUBNET
# Outputs:
#   Sets DOCKER_SUBNET and FOUND_OCTET
################################################################################
allocate_subnet() {
	log_info "Allocating private virtual subnet for container isolation."

	# Try to reuse existing subnet to prevent bridge conflicts
	# The default project name is APP_NAME (privacy-hub), so network is privacy-hub_frontend
	# Docker Compose v2 might use hyphens or underscores depending on version/config
	local existing_subnet=""
	local net_name
	for net_name in "${APP_NAME}_frontend" "${APP_NAME}-frontend" "privacy-hub_frontend"; do
		existing_subnet=$("${DOCKER_CMD}" network inspect "${net_name}" --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null || true)
		if [[ -n "${existing_subnet}" ]]; then
			log_info "Reusing existing network subnet: ${existing_subnet}"
			DOCKER_SUBNET="${existing_subnet}"
			# Extract octet (e.g., 172.20.0.0/16 -> 20)
			FOUND_OCTET=$(echo "${existing_subnet}" | cut -d. -f2)
			export DOCKER_SUBNET FOUND_OCTET
			return 0
		fi
	done

	local found_subnet=""
	local found_octet=""
	local test_subnet
	local test_net_name
	local i

	for i in {20..30}; do
		test_subnet="172.${i}.0.0/16"
		test_net_name="probe_net_${i}"
		if "${DOCKER_CMD}" network create --subnet="${test_subnet}" "${test_net_name}" >/dev/null 2>&1; then
			"${DOCKER_CMD}" network rm "${test_net_name}" >/dev/null 2>&1
			found_subnet="${test_subnet}"
			found_octet="${i}"
			break
		fi
	done

	if [[ -z "${found_subnet}" ]]; then
		log_crit "Fatal: No available subnets identified. Please verify host network configuration."
		exit 1
	fi

	DOCKER_SUBNET="${found_subnet}"
	export DOCKER_SUBNET
	FOUND_OCTET="${found_octet}"
	export FOUND_OCTET
	log_info "Assigned Virtual Subnet: ${DOCKER_SUBNET}"
}

################################################################################
# check_port_availability - Check if a port is currently in use on the host
# Arguments:
#   $1 - Port number
#   $2 - Protocol (tcp or udp, default: tcp)
# Returns:
#   0 if available, 1 if in use
################################################################################
check_port_availability() {
	local port="$1"
	local proto="${2:-tcp}"

	if command -v ss >/dev/null 2>&1; then
		if "${SUDO}" ss -Hl"${proto:0:1}"n sport = :"${port}" | grep -q "${port}"; then
			return 1
		fi
	elif command -v netstat >/dev/null 2>&1; then
		if "${SUDO}" netstat -l"${proto:0:1}"n | grep -q ":${port} "; then
			return 1
		fi
	elif command -v lsof >/dev/null 2>&1; then
		if "${SUDO}" lsof -i "${proto}:${port}" -s "${proto}:LISTEN" >/dev/null 2>&1; then
			return 1
		fi
	fi
	return 0
}

################################################################################
# is_service_enabled - Check if a service is in the selection list
# Globals:
#   SELECTED_SERVICES
# Arguments:
#   $1 - Service identifier
# Returns:
#   0 if enabled or no selection active, 1 otherwise
################################################################################
is_service_enabled() {
	local srv="$1"
	if [[ -z "${SELECTED_SERVICES:-}" ]]; then
		return 0
	fi
	if echo "${SELECTED_SERVICES}" | grep -qE "(^|,)$srv(,|$)"; then
		return 0
	fi
	return 1
}

################################################################################
# safe_remove_network - Remove a docker network and disconnect containers
# Globals:
#   DOCKER_CMD
# Arguments:
#   $1 - Network name
################################################################################
safe_remove_network() {
	local net_name="$1"
	local containers
	if "${DOCKER_CMD}" network inspect "${net_name}" >/dev/null 2>&1; then
		# Check if any containers are using it
		containers=$("${DOCKER_CMD}" network inspect "${net_name}" --format '{{range .Containers}}{{.Name}} {{end}}')
		if [[ -n "${containers}" ]]; then
			for c in ${containers}; do
				log_info "  Disconnecting container ${c} from network ${net_name}..."
				"${DOCKER_CMD}" network disconnect -f "${net_name}" "${c}" 2>/dev/null || true
			done
		fi
		"${DOCKER_CMD}" network rm "${net_name}" 2>/dev/null || true
	fi
}

################################################################################
# detect_network - Detect LAN and Public IP addresses
# Globals:
#   LAN_IP_OVERRIDE
#   FOUND_OCTET
#   PUBLIC_IP
# Outputs:
#   Sets LAN_IP and PUBLIC_IP
################################################################################
detect_network() {
	log_info "Identifying network environment..."

	# 1. LAN IP Detection
	if [[ -n "${LAN_IP_OVERRIDE}" ]]; then
		LAN_IP="${LAN_IP_OVERRIDE}"
		log_info "Using LAN IP Override: ${LAN_IP}"
	elif [[ -z "${LAN_IP:-}" ]]; then
		# Try to find primary interface IP
		# 1. Try ip route with a neutral destination (routing table lookup only)
		# Using 10.255.255.255 as a destination to see which interface/source IP would be used
		LAN_IP=$(ip route get 10.255.255.255 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -n1)

		# 2. Fallback: Try to find interface with default route
		if [[ -z "${LAN_IP}" ]]; then
			local default_iface
			default_iface=$(ip route show default 2>/dev/null | awk '/default/ {print $5}' | head -n1)
			if [[ -n "${default_iface}" ]]; then
				LAN_IP=$(ip -4 addr show "${default_iface}" scope global | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -n1)
			fi
		fi

		# 3. Fallback: hostname -I (if available)
		if [[ -z "${LAN_IP}" ]]; then
			LAN_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
		fi

		# 4. Last resort: Any global IPv4 address
		if [[ -z "${LAN_IP}" ]]; then
			LAN_IP=$(ip -4 addr show scope global | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -n1)
		fi

		if [[ -z "${LAN_IP}" ]]; then
			log_crit "Failed to detect LAN IP. Please use LAN_IP_OVERRIDE."
			exit 1
		fi
		log_info "Detected LAN IP: ${LAN_IP}"
	else
		log_info "Using existing LAN IP: ${LAN_IP}"
	fi
	export LAN_IP

	# 2. Public IP Detection
	if [[ -n "${PUBLIC_IP:-}" ]] && [[ "${PUBLIC_IP}" != "FAILED" ]]; then
		log_info "Using existing Public IP: ${PUBLIC_IP}"
	else
		log_info "Detecting public IP address (for VPN endpoint)..."
		# Use a privacy-conscious IP check service as requested, via proxy if possible
		local proxy="http://172.${FOUND_OCTET}.0.254:8888"
		PUBLIC_IP=$(curl --proxy "${proxy}" -s --max-time 10 https://api.ipify.org || curl -s --max-time 10 https://api.ipify.org || curl -s --max-time 10 http://ip-api.com/line?fields=query || echo "FAILED")
		if [[ "${PUBLIC_IP}" == "FAILED" ]]; then
			log_warn "Failed to detect public IP. VPN may not be reachable from external networks."
			PUBLIC_IP="${LAN_IP}"
		fi
		log_info "Public IP: ${PUBLIC_IP}"
	fi
}

################################################################################
# validate_wg_config - Validate the active WireGuard configuration file
# Globals:
#   ACTIVE_WG_CONF
# Returns:
#   0 if valid, 1 otherwise
################################################################################
validate_wg_config() {
	if [[ ! -s "${ACTIVE_WG_CONF}" ]]; then return 1; fi
	if ! grep -q "PrivateKey" "${ACTIVE_WG_CONF}"; then return 1; fi
	local pk_val
	pk_val=$(grep "PrivateKey" "${ACTIVE_WG_CONF}" | cut -d'=' -f2- | tr -d '[:space:]')
	if [[ -z "${pk_val}" ]]; then return 1; fi
	if [[ "${#pk_val}" -lt 40 ]]; then return 1; fi
	return 0
}

################################################################################
# extract_wg_profile_name - Extract profile name from WG config comments
# Arguments:
#   $1 - Path to WG config file
# Returns:
#   0 if found, 1 otherwise
# Outputs:
#   Prints the extracted name to stdout
################################################################################
extract_wg_profile_name() {
	local config_file="$1"
	local in_peer=0
	local profile_name=""
	local stripped
	while IFS= read -r line; do
		stripped=$(echo "${line}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
		if echo "${stripped}" | grep -qi '^\[peer\]$'; then
			in_peer=1
			continue
		fi
		if [[ "${in_peer}" -eq 1 ]] && echo "${stripped}" | grep -q '^#'; then
			profile_name=$(echo "${stripped}" | sed 's/^#[[:space:]]*//')
			if [[ -n "${profile_name}" ]]; then
				echo "${profile_name}"
				return 0
			fi
		fi
		if [[ "${in_peer}" -eq 1 ]] && echo "${stripped}" | grep -q '^\['; then break; fi
	done <"${config_file}"
	while IFS= read -r line; do
		stripped=$(echo "${line}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
		if echo "${stripped}" | grep -q '^#' && ! echo "${stripped}" | grep -q '='; then
			profile_name=$(echo "${stripped}" | sed 's/^#[[:space:]]*//')
			if [[ -n "${profile_name}" ]]; then
				echo "${profile_name}"
				return 0
			fi
		fi
	done <"${config_file}"
	return 1
}

################################################################################
# setup_secrets - Prompt for or load system secrets and credentials
# Globals:
#   PORTAINER_PASS_HASH, AGH_PASS_HASH, WG_HASH_COMPOSE, ADMIN_PASS_RAW,
#   VPN_PASS_RAW, PORTAINER_PASS_RAW, AGH_PASS_RAW, SEARXNG_SECRET,
#   IMMICH_DB_PASSWORD, BASE_DIR, AUTO_CONFIRM, PERSONAL_MODE, AUTO_PASSWORD,
#   DESEC_DOMAIN, DESEC_TOKEN, SCRIBE_GH_USER, SCRIBE_GH_TOKEN, HUB_API_KEY,
#   ODIDO_API_KEY, WG_HASH_CLEAN, DATA_DIR, AGH_USER
# Returns:
#   None
################################################################################
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

	if [[ ! -f "${BASE_DIR}/.secrets" ]]; then
		echo "========================================"
		echo " CREDENTIAL CONFIGURATION"
		echo "========================================"

		if [[ "${AUTO_CONFIRM}" == "true" ]]; then
			log_info "Auto-confirm enabled: Skipping interactive deSEC/GitHub/Odido setup."
			if [[ "${PERSONAL_MODE:-false}" == "true" ]]; then
				log_info "Personal Mode: Applying user-specific defaults."
			fi

			VPN_PASS_RAW="${VPN_PASS_RAW:-$(generate_secret 24)}"
			AGH_PASS_RAW="${AGH_PASS_RAW:-$(generate_secret 24)}"
			ADMIN_PASS_RAW="${ADMIN_PASS_RAW:-$(generate_secret 24)}"
			PORTAINER_PASS_RAW="${PORTAINER_PASS_RAW:-$(generate_secret 24)}"
		else
			local step_num=1

			# 1. deSEC Domain & Certificate Setup
			echo "--- deSEC Domain & Certificate Setup ---"
			local input_domain=""
			while [[ -z "${DESEC_DOMAIN}" ]]; do
				echo -n "${step_num}. deSEC Domain (e.g., myhome.dedyn.io): "
				read -r input_domain
				DESEC_DOMAIN="${input_domain:-$DESEC_DOMAIN}"
				if [[ -z "${DESEC_DOMAIN}" ]]; then
					echo "   ⚠️  A deSEC domain is REQUIRED for external access and VERTd HTTPS support."
				fi
			done
			((step_num++))

			local input_token=""
			echo -n "${step_num}. deSEC API Token: "
			read -rs input_token
			echo ""
			DESEC_TOKEN="${input_token:-$DESEC_TOKEN}"
			echo ""
			((step_num++))

			# 2. Password Preferences
			echo "--- MANUAL CREDENTIAL PROVISIONING ---"
			echo "Security Note: Please use strong, unique passwords for each service."
			echo ""

			if [[ "${AUTO_PASSWORD}" == "true" ]]; then
				log_info "Automated password generation initialized."
				VPN_PASS_RAW="${VPN_PASS_RAW:-$(generate_secret 24)}"
				AGH_PASS_RAW="${AGH_PASS_RAW:-$(generate_secret 24)}"
				ADMIN_PASS_RAW="${ADMIN_PASS_RAW:-$(generate_secret 24)}"
				PORTAINER_PASS_RAW="${PORTAINER_PASS_RAW:-$(generate_secret 24)}"
				log_info "Credentials generated and will be displayed upon completion."
			else
				echo -n "${step_num}. VPN Web UI Password (Protecting peer management): "
				read -rs VPN_PASS_RAW
				echo ""
				((step_num++))
				echo -n "${step_num}. AdGuard Home Password (Protecting DNS filters): "
				read -rs AGH_PASS_RAW
				echo ""
				((step_num++))
				echo -n "${step_num}. Management Dashboard Password (Primary control plane): "
				read -rs ADMIN_PASS_RAW
				echo ""
				((step_num++))
				if [[ "${FORCE_CLEAN}" == "false" ]] && [[ -d "${DATA_DIR}/portainer" ]]; then
					echo "   [!] NOTICE: Portainer already initialized. New passwords will not affect existing Portainer admin account."
				fi
				echo -n "${step_num}. Portainer Password (Infrastructure orchestration): "
				read -rs PORTAINER_PASS_RAW
				echo ""
				((step_num++))
			fi

			echo ""
			echo "--- Scribe (Medium Frontend) GitHub Integration (Optional) ---"
			echo "Note: GitHub credentials are optional but enable gist proxying."
			echo -n "${step_num}. GitHub Username (or press Enter to skip): "
			read -r SCRIBE_GH_USER
			((step_num++))
			if [[ -n "${SCRIBE_GH_USER}" ]]; then
				echo -n "${step_num}. GitHub Personal Access Token: "
				read -rs SCRIBE_GH_TOKEN
				echo ""
				((step_num++))
			else
				SCRIBE_GH_TOKEN=""
			fi

			echo ""
			echo "--- Odido Bundle Booster (Optional) ---"
			echo "Note: OAuth token must be obtained from the dashboard after deployment."
			echo "      The dashboard provides a sign-in URL generator for secure authentication."
			if ask_confirm "Do you want to enable Odido Bundle Booster?"; then
				log_info "Odido Bundle Booster will be deployed. Configure credentials via dashboard after setup."
				ODIDO_USER_ID=""
			else
				ODIDO_USER_ID=""
				SKIP_ODIDO=true
			fi

			# OAuth token will be obtained via dashboard after deployment
			ODIDO_TOKEN=""
		fi

		log_info "Generating Secrets (Batch Processing)..."
		HUB_API_KEY=$(generate_secret 32)
		ODIDO_API_KEY="${HUB_API_KEY}"

		if [[ -n "${WG_HASH_CLEAN:-}" ]] && [[ -n "${AGH_PASS_HASH:-}" ]] && [[ -n "${PORTAINER_PASS_HASH:-}" ]]; then
			log_info "Using provided password hashes."
		else
			WG_HASH_CLEAN=$(generate_hash "admin" "${VPN_PASS_RAW}")
			AGH_PASS_HASH=$(generate_hash "${AGH_USER}" "${AGH_PASS_RAW}")
			PORTAINER_PASS_HASH=$(generate_hash "admin" "${PORTAINER_PASS_RAW}")

			if [[ -z "${WG_HASH_CLEAN}" ]] || [[ -z "${AGH_PASS_HASH}" ]] || [[ -z "${PORTAINER_PASS_HASH}" ]] || [[ "${WG_HASH_CLEAN}" == "FAILED" ]] || [[ "${AGH_PASS_HASH}" == "FAILED" ]] || [[ "${PORTAINER_PASS_HASH}" == "FAILED" ]]; then
				log_crit "Failed to generate password hashes. Check Docker/Python status."
				exit 1
			fi
		fi

		SCRIBE_SECRET=$(generate_secret 64)
		ANONYMOUS_SECRET=$(generate_secret 32)
		IV_HMAC=$(generate_secret 16)
		IV_COMPANION=$(generate_secret 16)
		SEARXNG_SECRET=$(generate_secret 32)
		IMMICH_DB_PASSWORD=$(generate_secret 32)
		IMMICH_ADMIN_PASS_RAW=$(generate_secret 24)
		INVIDIOUS_DB_PASSWORD=$(generate_secret 32)

		# Robustness: Remove .secrets if it accidentally became a directory (Docker auto-mount issue)
		if [[ -d "${BASE_DIR}/.secrets" ]]; then
			log_warn ".secrets found as a directory. Removing..."
			${SUDO} rm -rf "${BASE_DIR}/.secrets"
		fi

		cat >"${BASE_DIR}/.secrets" <<EOF
VPN_PASS_RAW="${VPN_PASS_RAW}"
AGH_PASS_RAW="${AGH_PASS_RAW}"
ADMIN_PASS_RAW="${ADMIN_PASS_RAW}"
PORTAINER_PASS_RAW="${PORTAINER_PASS_RAW}"
IMMICH_ADMIN_PASS_RAW="${IMMICH_ADMIN_PASS_RAW}"
DESEC_DOMAIN="${DESEC_DOMAIN}"
DESEC_TOKEN="${DESEC_TOKEN}"
SCRIBE_GH_USER="${SCRIBE_GH_USER}"
SCRIBE_GH_TOKEN="${SCRIBE_GH_TOKEN}"
ODIDO_TOKEN="${ODIDO_TOKEN}"
ODIDO_USER_ID="${ODIDO_USER_ID}"
ODIDO_API_KEY='${ODIDO_API_KEY}'
HUB_API_KEY='${HUB_API_KEY}'
UPDATE_STRATEGY="stable"
ROLLBACK_BACKUP_ENABLED='true'
SEARXNG_SECRET='${SEARXNG_SECRET}'
IMMICH_DB_PASSWORD='${IMMICH_DB_PASSWORD}'
INVIDIOUS_DB_PASSWORD='${INVIDIOUS_DB_PASSWORD}'
WG_HASH_CLEAN='${WG_HASH_CLEAN}'
AGH_PASS_HASH='${AGH_PASS_HASH}'
PORTAINER_PASS_HASH='${PORTAINER_PASS_HASH}'
SCRIBE_SECRET='${SCRIBE_SECRET}'
ANONYMOUS_SECRET='${ANONYMOUS_SECRET}'
IV_HMAC='${IV_HMAC}'
IV_COMPANION='${IV_COMPANION}'
EOF
		"${SUDO}" chown 1000:1000 "${BASE_DIR}/.secrets"
		"${SUDO}" chmod 600 "${BASE_DIR}/.secrets"
	else
		source "${BASE_DIR}/.secrets"
		local updated_secrets=false
		# Logic to ensure all secrets are present
		if [[ -z "${HUB_API_KEY:-}" ]]; then
			HUB_API_KEY=$(generate_secret 32)
			echo "HUB_API_KEY='${HUB_API_KEY}'" >>"${BASE_DIR}/.secrets"
			updated_secrets=true
		fi
		if [[ "${updated_secrets}" == "true" ]]; then
			"${SUDO}" chmod 600 "${BASE_DIR}/.secrets"
		fi
	fi

	export VPN_PASS_RAW AGH_PASS_RAW ADMIN_PASS_RAW PORTAINER_PASS_RAW ALLOW_PROTON_VPN
	export DESEC_DOMAIN DESEC_TOKEN SCRIBE_GH_USER SCRIBE_GH_TOKEN
	export ODIDO_TOKEN ODIDO_USER_ID ODIDO_API_KEY HUB_API_KEY
	export WG_HASH_CLEAN AGH_PASS_HASH PORTAINER_PASS_HASH
	export SCRIBE_SECRET ANONYMOUS_SECRET IV_HMAC IV_COMPANION
	export SEARXNG_SECRET IMMICH_DB_PASSWORD INVIDIOUS_DB_PASSWORD
	export AGH_USER
}

################################################################################
# generate_protonpass_export - Create a CSV for password manager import
# Globals:
#   BASE_DIR
#   LAN_IP
#   PORT_DASHBOARD_WEB
#   ADMIN_PASS_RAW
#   PORT_ADGUARD_WEB
#   AGH_PASS_RAW
#   PORT_WG_WEB
#   VPN_PASS_RAW
#   PORT_PORTAINER
#   PORTAINER_PASS_RAW
################################################################################
generate_protonpass_export() {
	log_info "Generating Proton Pass import file (CSV)..."
	local export_file="${BASE_DIR}/protonpass_import.csv"

	cat >"${export_file}" <<EOF
Name,URL,Username,Password,Note
Privacy Hub Admin,http://${LAN_IP}:${PORT_DASHBOARD_WEB},admin,${ADMIN_PASS_RAW},Primary management portal.
AdGuard Home,http://${LAN_IP}:${PORT_ADGUARD_WEB},adguard,${AGH_PASS_RAW},DNS filtration.
WireGuard VPN UI,http://${LAN_IP}:${PORT_WG_WEB},admin,${VPN_PASS_RAW},WireGuard management.
Portainer UI,http://${LAN_IP}:${PORT_PORTAINER},admin,${PORTAINER_PASS_RAW},Container management.
EOF
	chmod 600 "${export_file}"
	log_info "Credential export file created: ${export_file}"
}
