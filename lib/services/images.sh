#!/usr/bin/env bash
# Image management utilities.
# Handles image tag resolution and pre-pulling of critical images.
set -euo pipefail

#######################################
# Resolves dynamic image tags for services from environment or defaults.
# Globals:
#   STACK_SERVICES, DOTENV_FILE, SUDO
# Arguments:
#   None
# Outputs:
#   Exports service-specific image tag variables.
#######################################
resolve_service_tags() {
	log_info "Resolving service image tags..."
	local srv_upper
	local var_name
	local default_var_name
	local val
	local srv

	for srv in ${STACK_SERVICES}; do
		srv_upper=$(echo "${srv//-/_}" | tr '[:lower:]' '[:upper:]')
		var_name="${srv_upper}_IMAGE_TAG"
		default_var_name="${srv_upper}_DEFAULT_TAG"

		# Use specific default tag if defined, otherwise 'latest'
		val="${!default_var_name:-latest}"

		if [[ -f "${DOTENV_FILE}" ]] && "${SUDO}" grep -q "^${var_name}=" "${DOTENV_FILE}"; then
			val=$("${SUDO}" grep "^${var_name}=" "${DOTENV_FILE}" | cut -d'=' -f2)
		fi

		export "${var_name}=${val}"
	done
}

#######################################
# Pre-pulls critical infrastructure images in parallel.
# Globals:
#   CRITICAL_IMAGES
# Arguments:
#   None
# Outputs:
#   Writes status messages to stdout.
# Returns:
#   0 on success, 1 on failure.
#######################################
pull_critical_images() {
	log_info "Pre-pulling core infrastructure images sequentially..."
	local img
	for img in ${CRITICAL_IMAGES}; do
		if ! pull_with_retry "${img}"; then
			log_crit "Failed to pull critical image ${img}. Aborting."
			exit 1
		fi
	done
	log_info "All critical images pulled successfully."
}
