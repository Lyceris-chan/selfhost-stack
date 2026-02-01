set -euo pipefail

# Functions to clear out existing garbage for a clean start.

################################################################################
# check_docker_rate_limit - Verify if Docker Hub is throttling requests
# Globals:
#   DOCKER_AUTH_DIR, DOCKER_CMD
# Returns:
#   None
# Outputs:
#   Logs status to stdout/stderr
################################################################################
check_docker_rate_limit() {
	log_info "Checking if Docker Hub is going to throttle you..."
	# Export DOCKER_CONFIG globally
	export DOCKER_CONFIG="${DOCKER_AUTH_DIR}"

	local output
	if ! output=$("${DOCKER_CMD}" pull hello-world 2>&1); then
		if echo "${output}" | grep -iaE "toomanyrequests|rate.*limit|pull.*limit|reached.*limit" >/dev/null; then
			log_warn "Docker Hub Rate Limit Detected. Proceeding with caution (cached images will be used if available)."
		else
			log_warn "Docker pull check failed. We'll proceed, but don't be surprised if image pulls fail later."
		fi
	else
		log_info "Docker Hub connection is fine."
	fi
}

################################################################################
# check_cert_risk - Identify existing SSL certificates and offer preservation
# Globals:
#   BASE_DIR, CERT_PROTECT, CERT_RESTORE, CERT_BACKUP_DIR, AUTO_CONFIRM
# Returns:
#   0
# Outputs:
#   Writes certificate information to stdout
################################################################################
check_cert_risk() {
	CERT_PROTECT=false
	local ssl_crt="${BASE_DIR}/config/adguard/ssl.crt"
	local ssl_key="${BASE_DIR}/config/adguard/ssl.key"

	if [[ -s "${ssl_crt}" ]]; then
		echo "----------------------------------------------------------"
		echo "   🔍 EXISTING SSL CERTIFICATE DETECTED"
		echo "----------------------------------------------------------"

		# Try to load existing domain configuration
		local existing_domain=""
		if [[ -f "${BASE_DIR}/.secrets" ]]; then
			existing_domain=$(grep "DESEC_DOMAIN=" "${BASE_DIR}/.secrets" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'" || true)
		fi

		# Extract Certificate Details using Containerized Python
		# We use python:3.11-alpine to ensure consistent API behavior for _test_decode_cert
		local cert_info
		cert_info=$(docker run --rm -v "${ssl_crt}:/cert.pem" python:3.11-alpine python3 -c "
import ssl, sys
try:
    cert = ssl._ssl._test_decode_cert('/cert.pem')
    subject = dict(x[0] for x in cert['subject'])
    issuer = dict(x[0] for x in cert['issuer'])
    print(f\"CN:{subject.get('commonName', '')}\")
    print(f\"ISSUER:{issuer.get('commonName', '')}\")
    print(f\"EXPIRY:{cert['notAfter']}\")
except Exception:
    print(\"CN:\")
    print(\"ISSUER:\")
    print(\"EXPIRY:\")
")
		
		# Safe parsing of certificate info (No eval)
		local CERT_CN=""
		local CERT_ISSUER=""
		local CERT_EXPIRY=""
		while IFS=':' read -r key value; do
			# Trim whitespace
			value=$(echo "$value" | sed 's/^[ \t]*//;s/[ \t]*$//') 
			case "$key" in
				CN) CERT_CN="$value" ;;
				ISSUER) CERT_ISSUER="$value" ;;
				EXPIRY) CERT_EXPIRY="$value" ;;
			esac
		done <<< "${cert_info}"

		local cert_validity="❌ EXPIRED / INVALID"
		# Check validity (not expired) using containerized python
		if docker run --rm -v "${ssl_crt}:/cert.pem" python:3.11-alpine python3 -c "
import ssl, datetime, sys
try:
    cert = ssl._ssl._test_decode_cert('/cert.pem')
    not_after = datetime.datetime.strptime(cert['notAfter'], '%b %d %H:%M:%S %Y %Z')
    if not_after > datetime.datetime.utcnow():
        sys.exit(0)
    sys.exit(1)
except:
    sys.exit(1)
"; then
			cert_validity="✅ Valid (Active)"
		fi

		echo "   • Common Name: ${CERT_CN:-Unknown/Invalid}"
		echo "   • Issuer:      ${CERT_ISSUER:-Unknown/Invalid}"
		echo "   • Expires:     ${CERT_EXPIRY:-Unknown}"
		echo "   • Status:      ${cert_validity}"

		if [[ -n "${existing_domain}" ]]; then
			echo "   • Setup Domain: ${existing_domain}"
			if [[ -n "${CERT_CN}" ]] && echo "${CERT_CN}" | grep -q "${existing_domain}"; then
				echo "   ✅ Certificate MATCHES the configured domain."
			else
				echo "   ⚠️  Certificate DOES NOT MATCH the configured domain (${existing_domain})."
			fi
		fi

		local is_acme=false
		if echo "${CERT_ISSUER}" | grep -qE "Let's Encrypt|R3|ISRG|ZeroSSL"; then
			is_acme=true
			log_warn "This appears to be a valid ACME-signed certificate."
		fi

		# If certificate is unreadable/invalid, preservation is pointless.
		# Skip prompt and allow deletion if we are already in a wipe flow.
		if [[ -z "${CERT_CN}" ]] && [[ -z "${CERT_ISSUER}" ]]; then
			log_warn "Certificate is invalid or unreadable. Skipping preservation."
			return 0
		fi

		local cert_response="n"
		if [[ "${AUTO_CONFIRM}" == "true" ]]; then
			if [[ "${is_acme}" == "true" ]]; then
				cert_response="n"
			else
				return 0
			fi
		else
			read -r -p "   Do you want to DELETE this certificate? (Default: No) [y/N]: " cert_response
		fi

		case "${cert_response}" in
		[yY][eE][sS] | [yY]) return 0 ;;
		*)
			CERT_RESTORE=true
			CERT_PROTECT=true
			mkdir -p "${CERT_BACKUP_DIR}"
			[[ -f "${ssl_crt}" ]] && cp "${ssl_crt}" "${CERT_BACKUP_DIR}/"
			[[ -f "${ssl_key}" ]] && cp "${ssl_key}" "${CERT_BACKUP_DIR}/"
			log_info "Certificate will be preserved and restored after cleanup."
			return 0
			;;
		esac
	fi
	return 0
}

################################################################################
# clean_environment - Perform environmental cleanup and remove old containers
# Globals:
#   BASE_DIR, CLEAN_ONLY, SELECTED_SERVICES, ALL_CONTAINERS, DOCKER_CMD,
#   CONTAINER_PREFIX, MEMOS_HOST_DIR, CERT_RESTORE, CERT_BACKUP_DIR
# Returns:
#   None
# Outputs:
#   Logs actions to stdout
################################################################################
clean_environment() {
	echo "=========================================================="
	echo "🛡️  ENVIRONMENT VALIDATION & CLEANUP"
	echo "=========================================================="

	if [[ -z "${BASE_DIR}" ]] || [[ "${BASE_DIR}" == "/" ]]; then
		log_crit "Critical Error: BASE_DIR is set to a protected path or empty. Aborting."
		exit 1
	fi

	if [[ "${CLEAN_ONLY}" == "false" ]]; then
		check_docker_rate_limit
	fi

	local clean_list
	if [[ -n "${SELECTED_SERVICES}" ]]; then
		local actual_targets=""
		local srv
		for srv in ${SELECTED_SERVICES//,/ }; do
			actual_targets="${actual_targets} ${srv}"
			[[ "${srv}" == "wikiless" ]] && actual_targets="${actual_targets} wikiless_redis"
			[[ "${srv}" == "invidious" ]] && actual_targets="${actual_targets} invidious-db companion"
		done
		clean_list="${actual_targets}"
	else
		clean_list="${ALL_CONTAINERS}"
	fi

	local found_containers=""
	local c
	for c in ${clean_list}; do
		if "${DOCKER_CMD}" ps -a --format '{{.Names}}' | grep -qE "^(${CONTAINER_PREFIX}${c}|${c})$"; then
			local name
			name=$("${DOCKER_CMD}" ps -a --format '{{.Names}}' | grep -E "^(${CONTAINER_PREFIX}${c}|${c})$" | head -n 1)
			found_containers="${found_containers} ${name}"
		fi
	done

	if [[ -n "${found_containers}" ]]; then
		if ask_confirm "Existing containers detected (${found_containers}). Remove them?"; then
			"${DOCKER_CMD}" rm -f ${found_containers} 2>/dev/null || true
			log_info "Previous containers removed."
		fi
	fi

	# Cleanup networks
	if "${DOCKER_CMD}" network ls --format '{{.Name}}' | grep -q "${APP_NAME}_frontend"; then
		log_info "Removing existing project network..."
		safe_remove_network "${APP_NAME}_frontend"
		safe_remove_network "${APP_NAME}-frontend"
		safe_remove_network "privacy-hub_frontend"
	fi

	if [[ -d "${BASE_DIR}" ]]; then
		if ask_confirm "Wipe ALL application data? This action is irreversible."; then
			check_cert_risk
			log_info "Clearing data..."
			"${SUDO}" rm -rf "${BASE_DIR}" 2>/dev/null || true
			[[ -d "${MEMOS_HOST_DIR}" ]] && "${SUDO}" rm -rf "${MEMOS_HOST_DIR}" 2>/dev/null || true
			log_info "Data cleared."

			if [[ "${CERT_RESTORE}" == "true" ]]; then
				log_info "Restoring preserved SSL certificate..."
				mkdir -p "${BASE_DIR}/config/adguard"
				[[ -f "${CERT_BACKUP_DIR}/ssl.crt" ]] && cp "${CERT_BACKUP_DIR}/ssl.crt" "${BASE_DIR}/config/adguard/"
				[[ -f "${CERT_BACKUP_DIR}/ssl.key" ]] && cp "${CERT_BACKUP_DIR}/ssl.key" "${BASE_DIR}/config/adguard/"
				rm -rf "${CERT_BACKUP_DIR}"
				CERT_RESTORE=false
				log_info "SSL certificate restored."
			fi
		fi
	fi
}

################################################################################
# cleanup_build_artifacts - Remove unused Docker images and build cache
# Globals:
#   DOCKER_CMD
# Returns:
#   None
################################################################################
cleanup_build_artifacts() {
	log_info "Cleaning up build artifacts to save space..."
	"${DOCKER_CMD}" image prune -f >/dev/null 2>&1 || true
	"${DOCKER_CMD}" builder prune -f >/dev/null 2>&1 || true
}

################################################################################
# perform_backup - Create a compressed archive of system configurations
# Arguments:
#   $1 - Backup tag (default: manual)
# Globals:
#   BACKUP_DIR, BASE_DIR
# Returns:
#   None
# Outputs:
#   Creates a .tar.gz file in BACKUP_DIR
################################################################################
perform_backup() {
	local tag="${1:-manual}"
	local timestamp
	timestamp=$(date +%Y%m%d_%H%M%S)
	local backup_name="backup_${tag}_${timestamp}.tar.gz"

	mkdir -p "${BACKUP_DIR}"
	log_info "Creating system backup: ${backup_name}..."

	local targets=""
	local t
	for t in .secrets config env; do
		[[ -e "${BASE_DIR}/${t}" ]] && targets="${targets} ${t}"
	done

	if [[ -n "${targets}" ]]; then
		log_info "Targets for backup: ${targets}"
		if tar -czf "${BACKUP_DIR}/${backup_name}" -C "${BASE_DIR}" ${targets} > "${BACKUP_DIR}/tar.log" 2>&1; then
			log_info "Backup created at ${BACKUP_DIR}/${backup_name}"
		else
			log_warn "Backup partially failed."
		fi
	fi
}

################################################################################
# perform_restore - Extract a system backup to the base directory
# Arguments:
#   $1 - Path to backup file
# Globals:
#   BASE_DIR, SUDO
# Returns:
#   None
################################################################################
perform_restore() {
	local backup_file="$1"
	if [[ ! -f "${backup_file}" ]]; then
		log_crit "Backup file not found: ${backup_file}"
		exit 1
	fi

	log_info "Restoring system from backup: ${backup_file}..."

	# Ensure we are in a safe state (stop containers if any)
	# But for simplicity, we just extract.

	if "${SUDO}" tar -xzf "${backup_file}" -C "${BASE_DIR}"; then
		log_info "Restore successful. All configurations and secrets have been replaced."
		"${SUDO}" chown -R "$(whoami)" "${BASE_DIR}"
		# Ensure secrets have restricted permissions
		[[ -f "${BASE_DIR}/.secrets" ]] && "${SUDO}" chmod 600 "${BASE_DIR}/.secrets"
	else
		log_crit "Restore failed."
		exit 1
	fi
}

################################################################################
# setup_cron - Configure system cron jobs for maintenance tasks
# Globals:
#   MONITOR_SCRIPT, IP_LOG_FILE, CERT_MONITOR_SCRIPT, BASE_DIR, APP_NAME
# Returns:
#   None
################################################################################
setup_cron() {
	log_info "Configuring scheduled tasks..."
	local cron_jobs=""
	[[ -f "${MONITOR_SCRIPT}" ]] && cron_jobs="${cron_jobs}*/5 * * * * ${MONITOR_SCRIPT} >> ${IP_LOG_FILE} 2>&1
"
	[[ -f "${CERT_MONITOR_SCRIPT}" ]] && cron_jobs="${cron_jobs}0 3 * * * ${CERT_MONITOR_SCRIPT} >> ${BASE_DIR}/cert-monitor.log 2>&1
"
	
	if [[ -z "${cron_jobs}" ]]; then
		log_info "No maintenance scripts found. Skipping cron configuration."
		return 0
	fi
	(
		crontab -l 2>/dev/null | grep -vE "wg-ip-monitor|cert-monitor|${APP_NAME}" || true
		echo "${cron_jobs}"
	) | crontab -
}

################################################################################
# pull_with_retry - Pull a Docker image with retries
# Arguments:
#   $1 - Image name/tag
# Globals:
#   DOCKER_CMD
# Returns:
#   0 on success, 1 on failure
################################################################################
pull_with_retry() {
    local img="$1"
    local max_retries=3
    local delay=2
    local attempt=1

    while [[ $attempt -le $max_retries ]]; do
        log_info "Pulling image: ${img} (Attempt $attempt/$max_retries)"
        if "${DOCKER_CMD}" pull "${img}"; then
            return 0
        fi

        # Check if we already have it (useful if rate limited but image is cached)
        if "${DOCKER_CMD}" image inspect "${img}" >/dev/null 2>&1; then
            log_warn "Pull failed for ${img}, but image exists locally. Continuing..."
            return 0
        fi

        log_warn "Pull failed for ${img}. Retrying in ${delay}s..."
        ((attempt++))
        sleep $delay
    done
    return 1
}

################################################################################
# safe_remove_network - Remove a Docker network if it exists
# Arguments:
#   $1 - Network name
# Globals:
#   DOCKER_CMD
# Returns:
#   None
################################################################################
safe_remove_network() {
    local net="$1"
    if "${DOCKER_CMD}" network inspect "${net}" >/dev/null 2>&1; then
        "${DOCKER_CMD}" network rm "${net}" >/dev/null 2>&1 || true
    fi
}

################################################################################
# extract_wg_profile_name - Extract profile name from WG config
# Arguments:
#   $1 - Config file path
# Returns:
#   0 on success (prints name), 1 on failure
################################################################################
extract_wg_profile_name() {
    local conf="$1"
    if [[ -f "$conf" ]]; then
        # Try to match "# Profile: Name"
        local name
        name=$(grep -m 1 "^# Profile:" "$conf" | cut -d':' -f2 | xargs)
        if [[ -n "$name" ]]; then
            echo "$name"
            return 0
        fi
    fi
    return 1
}
