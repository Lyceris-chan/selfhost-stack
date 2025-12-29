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

