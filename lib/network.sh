#!/usr/bin/env bash

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
    else
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
    fi

    # 2. Public IP Detection
    log_info "Detecting public IP address (for VPN endpoint)..."
    # Use a privacy-conscious IP check service as requested, via proxy if possible
    local proxy="http://172.${FOUND_OCTET}.0.254:8888"
    PUBLIC_IP=$(curl --proxy "$proxy" -s --max-time 10 https://api.ipify.org || curl -s --max-time 10 https://api.ipify.org || curl -s --max-time 10 http://ip-api.com/line?fields=query || echo "FAILED")
    if [ "$PUBLIC_IP" = "FAILED" ]; then
        log_warn "Failed to detect public IP. VPN may not be reachable from external networks."
        PUBLIC_IP="$LAN_IP"
    fi
    log_info "Public IP: $PUBLIC_IP"
}

