#!/bin/bash
# Full Deployment Test Runner for Privacy Hub
# Deploys zima.sh, waits for services, runs integration tests, and generates report

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

# Configuration
TEST_ID="ph_test_$(date +%s)"
TEST_BASE_DIR="${TEST_BASE_DIR:-/tmp/${TEST_ID}}"
LOG_DIR="${TEST_BASE_DIR}/logs"
REPORT_DIR="${TEST_BASE_DIR}/reports"
TIMEOUT=1800 # 30 minutes max
WG_CONF_B64="${WG_CONF_B64:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
	echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"
}

log_success() {
	echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} ✅ $1"
}

log_error() {
	echo -e "${RED}[$(date +'%H:%M:%S')]${NC} ❌ $1"
}

log_warn() {
	echo -e "${YELLOW}[$(date +'%H:%M:%S')]${NC} ⚠️  $1"
}

# Setup test environment
setup_environment() {
	log "Setting up test environment..."
	mkdir -p "$LOG_DIR" "$REPORT_DIR"

	# Check prerequisites
	if ! command -v docker &>/dev/null; then
		log_error "Docker is not installed"
		exit 1
	fi

	if ! command -v node &>/dev/null; then
		log_error "Node.js is not installed"
		exit 1
	fi

	# Install Python dependencies for deployment script
	if command -v python3 &>/dev/null; then
		log "Installing python dependencies..."
		pip install bcrypt >/dev/null 2>&1 || true
	fi

	# Install npm dependencies if needed
	if [ ! -d "test/node_modules" ]; then
		log "Installing test dependencies..."
		cd test && npm install puppeteer 2>&1 | tee "$LOG_DIR/npm_install.log"
		cd ..
	fi

	log_success "Environment ready"
}

# Clean previous deployment
cleanup_previous() {
	log "Cleaning up previous deployment..."

	# Stop and remove containers
	docker ps -a --filter "name=hub-" --format "{{.Names}}" | while read -r container; do
		log "  Removing $container..."
		docker rm -f "$container" 2>&1 | tee -a "$LOG_DIR/cleanup.log" || true
	done

	# Remove networks
	docker network ls --filter "name=privacy-hub" --format "{{.Name}}" | while read -r network; do
		log "  Removing network $network..."
		docker network rm "$network" 2>&1 | tee -a "$LOG_DIR/cleanup.log" || true
	done

	# Clean filesystem with sudo to handle docker-created root files
	if [ -d "$TEST_BASE_DIR" ]; then
		log "  Removing test directory $TEST_BASE_DIR..."
		sudo rm -rf "$TEST_BASE_DIR" || true
	fi

	log_success "Cleanup complete"
}

# Deploy with zima.sh
deploy_stack() {
	log "Starting deployment with zima.sh..."

	if [ -z "$WG_CONF_B64" ]; then
		log_error "WG_CONF_B64 environment variable not set"
		log_error "Please provide WireGuard configuration as base64"
		log_error "Example: WG_CONF_B64=\$(cat wg.conf | base64 -w0)"
		exit 1
	fi

	# Pre-create directory structure with correct ownership to avoid permission issues
	# zima.sh uses: $PROJECT_ROOT/data/AppData/$APP_NAME
	mkdir -p "$TEST_BASE_DIR/data/AppData/privacy-hub"
	mkdir -p "$LOG_DIR" # Re-create logs dir after cleanup

	export PROJECT_ROOT="$TEST_BASE_DIR"
	export WG_CONF_B64
	export VPN_SERVICE_PROVIDER="custom"
	export VPN_TYPE="wireguard"
	export VPN_FIREWALL="off"
	export RESTART_VPN_ON_HEALTHCHECK_FAILURE="no"
	export GLUETUN_DOT="off"

	# Use host docker config to leverage existing login
	export PH_DOCKER_AUTH_DIR="$HOME/.docker"

	log "Deployment configuration:"
	log "  PROJECT_ROOT: $PROJECT_ROOT"
	log "  WG_CONF_B64: ${#WG_CONF_B64} characters"

	# Run deployment
	timeout $TIMEOUT bash ./zima.sh -y >"$LOG_DIR/deployment.log" 2>&1 &
	DEPLOY_PID=$!

	log "Deployment started (PID: $DEPLOY_PID)"
	log "Monitoring deployment... (max ${TIMEOUT}s)"

	# Monitor deployment
	tail -f "$LOG_DIR/deployment.log" &
	TAIL_PID=$!

	if wait $DEPLOY_PID; then
		kill $TAIL_PID 2>/dev/null || true
		log_success "Deployment completed successfully"
		return 0
	else
		DEPLOY_EXIT=$?
		kill $TAIL_PID 2>/dev/null || true

		if [ $DEPLOY_EXIT -eq 124 ]; then
			log_error "Deployment timed out after ${TIMEOUT}s"
		else
			log_error "Deployment failed with exit code $DEPLOY_EXIT"
		fi

		log "Last 50 lines of deployment log:"
		tail -50 "$LOG_DIR/deployment.log"
		return $DEPLOY_EXIT
	fi
}

# Wait for services to be ready
wait_for_services() {
	log "Waiting for core services to be ready..."

	local max_wait=300 # 5 minutes
	local elapsed=0
	local check_interval=5

	local core_services=(
		"hub-dashboard"
		"hub-api"
		"hub-adguard"
		"hub-unbound"
	)

	while [ $elapsed -lt $max_wait ]; do
		local all_ready=true

		for service in "${core_services[@]}"; do
			if ! docker ps --filter "name=$service" --filter "status=running" --format "{{.Names}}" | grep -q "$service"; then
				all_ready=false
				log "  Waiting for $service..."
				break
			fi
		done

		if $all_ready; then
			log_success "All core services are running"

			# Additional wait for services to stabilize
			log "Waiting 30s for services to stabilize..."
			sleep 30
			return 0
		fi

		sleep $check_interval
		elapsed=$((elapsed + check_interval))
	done

	log_warn "Timeout waiting for services (${max_wait}s)"
	log "Starting tests anyway with available services..."
	return 0
}

# Check container health
check_container_health() {
	log "Checking container health..."

	local unhealthy_count=0

	docker ps --filter "name=hub-" --format "{{.Names}}\t{{.Status}}" | while IFS=$'\t' read -r name status; do
		if echo "$status" | grep -q "unhealthy"; then
			log_warn "$name is unhealthy: $status"
			unhealthy_count=$((unhealthy_count + 1))
		elif echo "$status" | grep -q "Up"; then
			log_success "$name is running"
		else
			log_error "$name status: $status"
		fi
	done

	log "Container health check complete"
}

# Collect container logs
collect_container_logs() {
	log "Collecting container logs..."

	local logs_subdir="$LOG_DIR/containers"
	mkdir -p "$logs_subdir"

	docker ps -a --filter "name=hub-" --format "{{.Names}}" | while read -r container; do
		log "  Collecting logs from $container..."
		docker logs "$container" >"$logs_subdir/${container}.log" 2>&1 || true
	done

	log_success "Container logs collected"
}

# Run integration tests
run_integration_tests() {
	log "Running integration test suite..."

	# Use detected LAN_IP or default to localhost
	local LAN_IP=$(hostname -I | awk '{print $1}')
	export TEST_BASE_URL="${TEST_BASE_URL:-http://$LAN_IP:8088}"
	export API_URL="${API_URL:-http://$LAN_IP:55555}"
	export HEADLESS="${HEADLESS:-true}"
	export TEST_BASE_DIR

	# Ensure dependencies are installed
	if [ ! -d "node_modules" ]; then
		log "Installing node modules..."
		npm install puppeteer >/dev/null 2>&1
	fi

	# Extract Admin Password from secrets if not set
	if [ -z "${ADMIN_PASSWORD:-}" ]; then
		local secrets_file="$TEST_BASE_DIR/data/AppData/privacy-hub/.secrets"
		if [ -f "$secrets_file" ]; then
			log "Extracting admin password from .secrets..."
			export ADMIN_PASSWORD=$(grep "^ADMIN_PASS_RAW" "$secrets_file" | cut -d'"' -f2)
			if [ -n "$ADMIN_PASSWORD" ]; then
				log_success "Admin password found and exported"
			else
				log_warn "Could not parse ADMIN_PASS_RAW from .secrets"
			fi
		else
			log_warn "Secrets file not found at $secrets_file"
		fi
	fi

	log "Test configuration:"
	log "  TEST_BASE_URL: $TEST_BASE_URL"
	log "  HEADLESS: $HEADLESS"

	cd test

	log "Running Integration Tests..."
	node test_integration.js >"$LOG_DIR/integration_tests.log" 2>&1
	INTEGRATION_EXIT=$?

	log "Running Dashboard UI Tests..."
	node test_dashboard.js >"$LOG_DIR/dashboard_tests.log" 2>&1
	DASHBOARD_EXIT=$?

	log "Running Functional Ops Tests..."
	node test_functional_ops.js >"$LOG_DIR/functional_ops.log" 2>&1
	OPS_EXIT=$?

	cd ..

	if [ $INTEGRATION_EXIT -eq 0 ] && [ $DASHBOARD_EXIT -eq 0 ] && [ $OPS_EXIT -eq 0 ]; then
		log_success "All test suites passed"
		TEST_EXIT=0
	else
		log_error "Some test suites failed:"
		[ $INTEGRATION_EXIT -ne 0 ] && log_error "  - Integration Tests: Failed"
		[ $DASHBOARD_EXIT -ne 0 ] && log_error "  - Dashboard Tests: Failed"
		[ $OPS_EXIT -ne 0 ] && log_error "  - Functional Ops Tests: Failed"
		TEST_EXIT=1
	fi

	# Copy test reports
	if [ -d "test/reports" ]; then
		cp -r test/reports/* "$REPORT_DIR/" 2>/dev/null || true
	fi
	if [ -d "test/screenshots" ]; then
		cp -r test/screenshots "$REPORT_DIR/" 2>/dev/null || true
	fi

	return $TEST_EXIT
}

# Analyze logs for errors
analyze_logs() {
	log "Analyzing logs for errors and warnings..."

	local analysis_report="$REPORT_DIR/log_analysis.txt"

	{
		echo "=========================================="
		echo "LOG ANALYSIS REPORT"
		echo "=========================================="
		echo "Generated: $(date)"
		echo ""

		echo "CONTAINER LOG ERRORS:"
		echo "----------------------------------------"

		for logfile in "$LOG_DIR/containers"/*.log; do
			if [ -f "$logfile" ]; then
				local container=$(basename "$logfile" .log)
				local error_count=$(grep -ci "error" "$logfile" 2>/dev/null || echo "0")
				error_count=${error_count//[!0-9]/}
				[ -z "$error_count" ] && error_count=0

				local warn_count=$(grep -ci "warn" "$logfile" 2>/dev/null || echo "0")
				warn_count=${warn_count//[!0-9]/}
				[ -z "$warn_count" ] && warn_count=0

				echo "$container: $error_count errors, $warn_count warnings"

				if [ "$error_count" -gt 0 ]; then
					echo "  Errors:"
					grep -i "error" "$logfile" | head -10 | sed 's/^/    /'
					echo ""
				fi
			fi
		done

		echo ""
		echo "DEPLOYMENT LOG ANALYSIS:"
		echo "----------------------------------------"

		if [ -f "$LOG_DIR/deployment.log" ]; then
			local deploy_errors=$(grep -ci "error\|failed\|critical" "$LOG_DIR/deployment.log" || true)
			echo "Errors/Failures in deployment: $deploy_errors"

			if [ "$deploy_errors" -gt 0 ]; then
				echo "Sample errors:"
				grep -i "error\|failed\|critical" "$LOG_DIR/deployment.log" | head -10 | sed 's/^/  /'
			fi
		fi

	} >"$analysis_report"

	cat "$analysis_report"
	log_success "Log analysis saved to $analysis_report"
}

# Generate final report
generate_final_report() {
	log "Generating final test report..."

	local final_report="$REPORT_DIR/FINAL_TEST_REPORT.md"
	local test_duration=$(($(date +%s) - START_TIME))

	{
		echo "# Privacy Hub - Full Deployment Test Report"
		echo ""
		echo "**Date**: $(date)"
		echo "**Duration**: ${test_duration}s"
		echo "**Environment**: $(uname -s) $(uname -m)"
		echo ""
		echo "---"
		echo ""
		echo "## Deployment Summary"
		echo ""
		echo "### Containers Deployed"
		echo "\`\`\`"
		docker ps --filter "name=hub-" --format "{{.Names}}: {{.Status}}"
		echo "\`\`\`"
		echo ""
		echo "### Services Count"
		echo "- Running: $(docker ps --filter 'name=hub-' --filter 'status=running' --format '{{.Names}}' | wc -l)"
		echo "- Total: $(docker ps -a --filter 'name=hub-' --format '{{.Names}}' | wc -l)"
		echo ""
		echo "---"
		echo ""
		echo "## Test Results"
		echo ""

		if [ -f "$LOG_DIR/integration_tests.log" ]; then
			echo "### Integration Tests"
			echo "\`\`\`"
			tail -100 "$LOG_DIR/integration_tests.log"
			echo "\`\`\`"
		fi

		echo ""
		echo "---"
		echo ""
		echo "## Log Analysis"
		echo ""

		if [ -f "$REPORT_DIR/log_analysis.txt" ]; then
			cat "$REPORT_DIR/log_analysis.txt"
		fi

		echo ""
		echo "---"
		echo ""
		echo "## Files Generated"
		echo ""
		echo "### Logs"
		find "$LOG_DIR" -type f -exec ls -lh {} \; | awk '{print "- " $9 " (" $5 ")"}'
		echo ""
		echo "### Reports"
		find "$REPORT_DIR" -type f -exec ls -lh {} \; | awk '{print "- " $9 " (" $5 ")"}'
		echo ""
		echo "---"
		echo ""
		echo "## Verification Checklist"
		echo ""
		echo "- [$([ -f "$LOG_DIR/deployment.log" ] && echo "x" || echo " ")] Deployment log captured"
		echo "- [$([ -d "$LOG_DIR/containers" ] && echo "x" || echo " ")] Container logs collected"
		echo "- [$([ -f "$LOG_DIR/integration_tests.log" ] && echo "x" || echo " ")] Integration tests executed"
		echo "- [$([ -d "$REPORT_DIR/screenshots" ] && echo "x" || echo " ")] Screenshots captured"
		echo "- [$([ $DEPLOY_EXIT -eq 0 ] && echo "x" || echo " ")] Deployment successful"
		echo "- [$([ $TEST_EXIT -eq 0 ] && echo "x" || echo " ")] Tests passed"
		echo ""

	} >"$final_report"

	log_success "Final report generated: $final_report"

	# Print summary
	echo ""
	echo "=========================================="
	echo "FINAL TEST SUMMARY"
	echo "=========================================="
	cat "$final_report"
	echo "=========================================="
}

# Main execution
main() {
	START_TIME=$(date +%s)
	DEPLOY_EXIT=0
	TEST_EXIT=0

	echo "=========================================="
	echo "🚀 PRIVACY HUB - FULL DEPLOYMENT TEST"
	echo "=========================================="
	echo ""

	setup_environment
	cleanup_previous

	if deploy_stack; then
		DEPLOY_EXIT=0
	else
		DEPLOY_EXIT=$?
		log_error "Deployment failed, continuing to collect data..."
	fi

	wait_for_services
	check_container_health
	collect_container_logs

	if run_integration_tests; then
		TEST_EXIT=0
	else
		TEST_EXIT=$?
	fi

	analyze_logs
	generate_final_report

	# Determine overall result
	if [ $DEPLOY_EXIT -eq 0 ] && [ $TEST_EXIT -eq 0 ]; then
		log_success "All tests passed! ✨"
		exit 0
	else
		log_error "Some tests failed. See reports for details."
		exit 1
	fi
}

# Run main function
main "$@"
