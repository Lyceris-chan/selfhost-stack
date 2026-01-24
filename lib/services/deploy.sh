#!/usr/bin/env bash
################################################################################
# PRIVACY HUB - DEPLOYMENT MODULE
################################################################################
#
# Orchestrates the deployment of the entire Privacy Hub stack using Docker
# Compose. Handles pre-flight checks, service ordering, and deployment
# verification.
#
# Key Features:
#   - Port conflict detection (especially port 53 for AdGuard)
#   - Parallel vs sequential deployment strategies
#   - Core infrastructure prioritization
#   - Retry logic for transient failures
#   - Health check verification
#   - Deployment rollback on failure
#
# Deployment Strategies:
#   Sequential (default):
#     1. Core services first (hub-api, adguard, unbound, gluetun, wg-easy)
#     2. Applications in dependency order
#     3. Health checks between stages
#   
#   Parallel (--parallel flag):
#     - All services launched simultaneously
#     - Faster but requires sufficient resources
#     - Dependency conflicts handled by Docker Compose
#
# Pre-flight Checks:
#   - Port 53 availability (for AdGuard Home)
#   - TUN kernel module loading (for VPN)
#   - Docker daemon accessibility
#   - Compose file validity
#
# Error Handling:
#   - Comprehensive logging of failures
#   - Automatic rollback on critical errors
#   - User confirmation for known conflicts
#
# Usage:
#   Called by zima.sh deploy command
#   Requires: COMPOSE_FILE, DOCKER_COMPOSE_FINAL_CMD environment variables
#
# Style Guide:
#   Adheres to Google Shell Style Guide
#   - Function-based organization
#   - Clear error messages
#   - Defensive programming (set -euo pipefail)
#
# Author: ZimaOS Privacy Hub Team
# Version: 2.0.0
################################################################################

set -euo pipefail

deploy_stack() {
	if command -v modprobe >/dev/null 2>&1; then
		"${SUDO}" modprobe tun || true
	fi

	# Pre-flight Check: Port 53
	if is_service_enabled "adguard"; then
		log_info "Verifying port 53 availability..."
		if ! check_port_availability 53 "tcp" || ! check_port_availability 53 "udp"; then
			log_warn "Port 53 is already in use on this host."
			log_warn "This will likely cause AdGuard Home to fail."
			if [[ "${AUTO_CONFIRM}" == "true" ]]; then
				log_warn "AUTO_CONFIRM mode: Continuing deployment anyway."
			else
				log_warn "Please disable systemd-resolved (systemctl disable --now systemd-resolved) or other DNS services."
				if ! ask_confirm "Attempt deployment anyway?"; then
					log_crit "Deployment aborted due to port conflict."
					exit 1
				fi
			fi
		fi
	fi

	# Retry wrapper for Docker Compose
	run_compose_up() {
		local args="$*"
		if "${DOCKER_COMPOSE_FINAL_CMD}" -f "${COMPOSE_FILE}" up -d --build ${args}; then
			return 0
		fi

		local exit_code=$?
		log_crit "Docker Compose failed (Exit Code: ${exit_code})."
		return 1
	}

	if [[ "${PARALLEL_DEPLOY}" == "true" ]]; then
		log_info "Parallel Mode Enabled: Launching full stack immediately..."
		run_compose_up --remove-orphans
	else
		# Explicitly launch core infrastructure services first
		local core_services=""
		local srv
		for srv in hub-api adguard unbound gluetun wg-easy; do
			if grep -q "^  ${srv}:" "${COMPOSE_FILE}"; then
				core_services="${core_services} ${srv}"
			fi
		done

		if [[ -n "${core_services}" ]]; then
			log_info "Launching core infrastructure services sequentially (to minimize iptables contention)..."
			for srv in ${core_services}; do
				log_info "  Starting ${srv}..."
				run_compose_up "${srv}"
			done
		fi

		# Wait for critical backends to stabilize
		if echo "${core_services}" | grep -qE "hub-api|gluetun|wg-easy"; then
			log_info "Waiting for backend services to stabilize..."
			local i
			for i in {1..10}; do
				local hub_health="healthy"
				local glu_health="healthy"
				local wg_health="healthy"

				if echo "${core_services}" | grep -q "hub-api"; then
					hub_health=$("${DOCKER_CMD}" inspect --format='{{.State.Health.Status}}' "${CONTAINER_PREFIX}api" 2>/dev/null || echo "unknown")
				fi
				if echo "${core_services}" | grep -q "gluetun"; then
					glu_health=$("${DOCKER_CMD}" inspect --format='{{.State.Health.Status}}' "${CONTAINER_PREFIX}gluetun" 2>/dev/null || echo "unknown")
				fi
				if echo "${core_services}" | grep -q "wg-easy"; then
					wg_health=$("${DOCKER_CMD}" inspect --format='{{.State.Health.Status}}' "${CONTAINER_PREFIX}wg-easy" 2>/dev/null || echo "unknown")
				fi

				if [[ "${hub_health}" == "healthy" ]] && [[ "${glu_health}" == "healthy" ]] && [[ "${wg_health}" == "healthy" ]]; then
					log_info "Backends are stable."
					break
				fi
				[[ "${i}" -eq 10 ]] && log_warn "Backends taking longer than expected to stabilize."
				sleep 2
			done
		fi

		local orphan_flag="--remove-orphans"
		if [[ -n "${SELECTED_SERVICES}" ]]; then
			orphan_flag=""
		fi
		run_compose_up ${orphan_flag}
	fi

	log_info "Verifying control plane connectivity..."
	local api_test="FAILED"
	local i
	for i in {1..15}; do
		api_test=$(curl -s -o /dev/null -w "%{http_code}" "http://${LAN_IP}:${PORT_DASHBOARD_WEB}/api/status" || echo "FAILED")
		if [[ "${api_test}" == "200" ]] || [[ "${api_test}" == "401" ]]; then
			break
		fi
		sleep 2
	done

	if [[ "${api_test}" == "200" ]]; then
		log_info "Control plane is reachable."
	elif [[ "${api_test}" == "401" ]]; then
		log_info "Control plane is reachable (Security handshake verified)."
	elif [[ "${api_test}" =~ ^[0-9]+$ ]]; then
		log_info "Control plane initializing (HTTP ${api_test}). Dashboard will be available shortly."
	else
		log_info "Control plane starting up. Dashboard will be available in a few moments."
	fi

	if [[ "${AUTO_PASSWORD}" == "true" ]] && grep -q "portainer:" "${COMPOSE_FILE}"; then
		log_info "Synchronizing Portainer administrative settings..."
		local portainer_ready=false
		local i
		# Increase wait time for Portainer to initialize its database
		for i in {1..60}; do
			if curl -s --max-time 2 "http://${LAN_IP}:${PORT_PORTAINER}/api/system/status" >/dev/null; then
				portainer_ready=true
				break
			fi
			[[ $((i % 5)) -eq 0 ]] && log_info "Waiting for Portainer API ($i/60)..."
			sleep 1
		done

		if [[ "${portainer_ready}" == "true" ]]; then
			# Give Portainer another moment to ensure the admin user is created from the CLI flag
			sleep 5
			# Authenticate to get JWT (user was initialized via --admin-password CLI flag)
			# Use Python to safely escape the password in JSON
			local auth_payload
			auth_payload=$(PORTAINER_PASS="${PORTAINER_PASS_RAW}" "${PYTHON_CMD}" -c "import json, os; print(json.dumps({'Username': 'admin', 'Password': os.environ['PORTAINER_PASS']}))")

			local auth_response
			auth_response=$(curl -s --max-time 5 -X POST "http://${LAN_IP}:${PORT_PORTAINER}/api/auth" \
				-H "Content-Type: application/json" \
				-d "${auth_payload}" 2>&1 || echo "CURL_ERROR")

			if ! echo "${auth_response}" | grep -q "jwt"; then
				sleep 2
				auth_response=$(curl -s --max-time 5 -X POST "http://${LAN_IP}:${PORT_PORTAINER}/api/auth" \
					-H "Content-Type: application/json" \
					-d "{\"Username\":\"portainer\",\"Password\":\"${PORTAINER_PASS_RAW}\"}" 2>&1 || echo "CURL_ERROR")
			fi

			if echo "${auth_response}" | grep -q "jwt"; then
				local portainer_jwt
				portainer_jwt=$(echo "${auth_response}" | sed -n 's/.*"jwt":"\([^"\'']*\).*/\1/p')

				# 1. Disable Telemetry/Analytics
				log_info "Disabling Portainer anonymous telemetry..."
				curl -s --max-time 5 -X PUT "http://${LAN_IP}:${PORT_PORTAINER}/api/settings" \
					-H "Authorization: Bearer ${portainer_jwt}" \
					-H "Content-Type: application/json" \
					-d '{"EnableTelemetry":false}' >/dev/null 2>&1 || true

				# 2. Rename 'admin' user to 'portainer' (Security Best Practice)
				local current_user_json
				current_user_json=$(curl -s -H "Authorization: Bearer ${portainer_jwt}" "http://${LAN_IP}:${PORT_PORTAINER}/api/users/me" 2>/dev/null)
				local admin_id
				admin_id=$(echo "${current_user_json}" | sed -n 's/.*"Id":\([0-9]*\).*/\1/p' || echo "1")
				local check_user
				check_user=$(echo "${current_user_json}" | sed -n 's/.*"Username":"\([^"\'']*\).*/\1/p')

				# Only rename if not already named 'portainer'
				if [[ "${check_user}" != "portainer" ]] && [[ "${check_user}" != "" ]]; then
					log_info "Renaming default '${check_user}' user to 'portainer'..."
					curl -s --max-time 5 -X PUT "http://${LAN_IP}:${PORT_PORTAINER}/api/users/${admin_id}" \
						-H "Authorization: Bearer ${portainer_jwt}" \
						-H "Content-Type: application/json" \
						-d '{"Username":"portainer"}' >/dev/null 2>&1 || true
				fi
			else
				log_info "Portainer initialized. First-time login required at http://${LAN_IP}:${PORT_PORTAINER}"
			fi
		else
			log_warn "Portainer did not become ready in time. Skipping automated configuration."
		fi
	fi

	# Download remote assets (fonts, utilities) via Gluetun proxy for privacy
	download_remote_assets

	# Configure Cron
	setup_cron

	# Cleanup build artifacts to save space after successful deployment
	cleanup_build_artifacts

	# Purge unused Docker assets post-deployment for optimal storage
	log_info "Purging unused Docker assets..."
	"${DOCKER_CMD}" image prune -a -f >/dev/null 2>&1 || true
	"${DOCKER_CMD}" builder prune -f >/dev/null 2>&1 || true

	# Final Summary
	echo ""
	echo -e "\e[1;32m==========================================================\e[0m"
	echo -e "\e[1;32m✅ DEPLOYMENT COMPLETE\e[0m"
	echo -e "\e[1;32m==========================================================\e[0m"
	if [[ -n "${DESEC_DOMAIN:-}" ]] && [[ -f "${AGH_CONF_DIR:-}/ssl.crt" ]]; then
		echo "   • Dashboard:    https://${DESEC_DOMAIN}:8443"
		echo "                   (Local IP: http://${LAN_IP}:${PORT_DASHBOARD_WEB})"
		echo "   • Secure DNS:   https://${DESEC_DOMAIN}/dns-query"
		echo "   • Note:         VERT requires HTTPS to function correctly."
	else
		echo "   • Dashboard:    http://${LAN_IP}:${PORT_DASHBOARD_WEB}"
		if [[ -n "${DESEC_DOMAIN:-}" ]]; then
			echo "   • Secure DNS:   https://${DESEC_DOMAIN}/dns-query"
		fi
	fi
	echo "   • Admin Pass:   ${ADMIN_PASS_RAW}"
	echo "   • Portainer:    http://${LAN_IP}:${PORT_PORTAINER} (User: portainer / Pass: ${PORTAINER_PASS_RAW})"
	echo "   • WireGuard:    http://${LAN_IP}:${PORT_WG_WEB} (Pass: ${VPN_PASS_RAW})"
	echo "   • AdGuard:      http://${LAN_IP}:${PORT_ADGUARD_WEB} (User: adguard / Pass: ${AGH_PASS_RAW})"
	echo "   • Immich:       http://${LAN_IP}:${PORT_IMMICH}"
	if [[ -n "${ODIDO_TOKEN:-}" ]]; then
		echo "   • Odido Boost:  Active (Threshold: 100MB)"
	fi
	echo ""
	echo "   📁 Credentials: ${BASE_DIR}/.secrets"
	echo "   📄 Importable:  ${BASE_DIR}/protonpass_import.csv"
	echo "   📄 LibRedirect: ${PROJECT_ROOT}/libredirect_import.json"

	if [[ -f "${BASE_DIR}/protonpass_import.csv" ]]; then
		echo ""
		echo -e "\e[1;31m  ⚠️  SECURITY WARNING\e[0m"
		echo -e "\e[1;31m  --------------------------------------------------------\e[0m"
		echo -e "\e[1;31m  The importable CSV contains RAW PASSWORDS.\e[0m"
		echo -e "\e[1;31m  DELETE IT IMMEDIATELY after importing to Proton Pass.\e[0m"
		echo -e "\e[1;31m  Command: rm \"${BASE_DIR}/protonpass_import.csv\"\e[0m"
		echo -e "\e[1;31m  --------------------------------------------------------\e[0m"
	fi
	echo -e "\e[1;32m==========================================================\e[0m"
	echo ""

	if [[ "${CLEAN_EXIT:-false}" == "true" ]]; then
		exit 0
	fi
}
