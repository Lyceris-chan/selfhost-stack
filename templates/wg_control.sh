#!/bin/sh
ACTION=$1
PROFILE_NAME=$2
CONTAINER_PREFIX="__CONTAINER_PREFIX__"
PROFILES_DIR="/profiles"
ACTIVE_CONF="/active-wg.conf"
NAME_FILE="/app/.active_profile_name"
LOCK_FILE="/app/.wg-control.lock"

exec 9>"$LOCK_FILE"

sanitize_json_string() {
    printf '%s' "$1" | tr -d '\000-\037' | sed 's/\\/\\\\/g; s/"/\"/g' | tr -d '\n\r'
}

if [ "$ACTION" = "activate" ]; then
    if ! flock -n 9; then
        echo "Error: Another control operation is in progress"
        exit 1
    fi
    if [ -f "$PROFILES_DIR/$PROFILE_NAME.conf" ]; then
        ln -sf "$PROFILES_DIR/$PROFILE_NAME.conf" "$ACTIVE_CONF"
        echo "$PROFILE_NAME" > "$NAME_FILE"
        DEPENDENTS="${CONTAINER_PREFIX}redlib ${CONTAINER_PREFIX}wikiless ${CONTAINER_PREFIX}wikiless_redis ${CONTAINER_PREFIX}invidious ${CONTAINER_PREFIX}invidious-db ${CONTAINER_PREFIX}invidious-companion ${CONTAINER_PREFIX}rimgo ${CONTAINER_PREFIX}breezewiki ${CONTAINER_PREFIX}anonymousoverflow ${CONTAINER_PREFIX}scribe"
        # shellcheck disable=SC2086
        docker stop $DEPENDENTS 2>/dev/null || true
        docker compose -f /app/docker-compose.yml up -d --force-recreate gluetun 2>/dev/null || true
        
        # Wait for gluetun to be healthy (max 30s)
        i=0
        while [ $i -lt 30 ]; do
            HEALTH=$(docker inspect --format='{{.State.Health.Status}}' ${CONTAINER_PREFIX}gluetun 2>/dev/null || echo "unknown")
            if [ "$HEALTH" = "healthy" ]; then
                break
            fi
            sleep 1
            i=$((i+1))
        done

        # shellcheck disable=SC2086
        docker compose -f /app/docker-compose.yml up -d --force-recreate $DEPENDENTS 2>/dev/null || true
    else
        echo "Error: Profile not found"
        exit 1
    fi
elif [ "$ACTION" = "delete" ]; then
    if ! flock -n 9; then
        echo "Error: Another control operation is in progress"
        exit 1
    fi
    if [ -f "$PROFILES_DIR/$PROFILE_NAME.conf" ]; then
        rm "$PROFILES_DIR/$PROFILE_NAME.conf"
    fi
elif [ "$ACTION" = "status" ]; then
    GLUETUN_STATUS="down"
    GLUETUN_HEALTHY="false"
    HANDSHAKE_AGO="N/A"
    ENDPOINT="--"
    PUBLIC_IP="--"
    DATA_FILE="/app/.data_usage"
    
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_PREFIX}gluetun$"; then
        # Check container health status
        HEALTH=$(docker inspect --format='{{.State.Health.Status}}' ${CONTAINER_PREFIX}gluetun 2>/dev/null || echo "unknown")
        if [ "$HEALTH" = "healthy" ]; then
            GLUETUN_HEALTHY="true"
        fi
        
        # Use gluetun's HTTP control server API (port 8000) for status
        # API docs: https://github.com/qdm12/gluetun-wiki/blob/main/setup/advanced/control-server.md
        
        # Get VPN status from control server
        VPN_STATUS_RESPONSE=$(docker exec ${CONTAINER_PREFIX}gluetun wget --user=gluetun --password="__ADMIN_PASS_RAW__" -qO- --timeout=3 http://127.0.0.1:8000/v1/vpn/status 2>/dev/null || echo "")
        if [ -n "$VPN_STATUS_RESPONSE" ]; then
            # Extract status from {"status":"running"} or {"status":"stopped"}
            VPN_RUNNING=$(echo "$VPN_STATUS_RESPONSE" | grep -o '"status":"running"' || echo "")
            if [ -n "$VPN_RUNNING" ]; then
                GLUETUN_STATUS="up"
                HANDSHAKE_AGO="Connected"
            else
                GLUETUN_STATUS="down"
                HANDSHAKE_AGO="Disconnected"
            fi
        elif [ "$GLUETUN_HEALTHY" = "true" ]; then
            # Fallback: if container is healthy, assume VPN is up
            GLUETUN_STATUS="up"
            HANDSHAKE_AGO="Connected (API unavailable)"
        fi
        
        # Get public IP from control server
        PUBLIC_IP_RESPONSE=$(docker exec ${CONTAINER_PREFIX}gluetun wget --user=gluetun --password="__ADMIN_PASS_RAW__" -qO- --timeout=3 http://127.0.0.1:8000/v1/publicip/ip 2>/dev/null || echo "")
        if [ -n "$PUBLIC_IP_RESPONSE" ]; then
            # Extract IP from {"public_ip":"x.x.x.x"}
            EXTRACTED_IP=$(echo "$PUBLIC_IP_RESPONSE" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "")
            if [ -n "$EXTRACTED_IP" ]; then
                PUBLIC_IP="$EXTRACTED_IP"
            fi
        fi
        
        # Fallback to external IP check if control server didn't return an IP
        if [ -z "$PUBLIC_IP" ] || [ "$PUBLIC_IP" = "--" ]; then
            PUBLIC_IP=$(docker exec ${CONTAINER_PREFIX}gluetun wget -qO- --timeout=5 https://api.ipify.org 2>/dev/null || echo "--")
        fi
        
        # Try to get endpoint from WireGuard config if available
        WG_CONF_ENDPOINT=$(docker exec ${CONTAINER_PREFIX}gluetun cat /gluetun/wireguard/wg0.conf 2>/dev/null | grep -i '^Endpoint' | cut -d'=' -f2 | tr -d ' ' | head -1 || echo "")
        if [ -n "$WG_CONF_ENDPOINT" ]; then
            ENDPOINT="$WG_CONF_ENDPOINT"
        fi
        
        # Get current RX/TX from /proc/net/dev (works for tun0 or wg0 interface)
        # Format: iface: rx_bytes rx_packets ... tx_bytes tx_packets ...
        NET_DEV=$(docker exec ${CONTAINER_PREFIX}gluetun cat /proc/net/dev 2>/dev/null || echo "")
        CURRENT_RX="0"
        CURRENT_TX="0"
        if [ -n "$NET_DEV" ]; then
            # Try tun0 first (OpenVPN), then wg0 (WireGuard)
            VPN_LINE=$(echo "$NET_DEV" | grep -E '^\s*(tun0|wg0):' | head -1 || echo "")
            if [ -n "$VPN_LINE" ]; then
                # Extract RX bytes (field 2) and TX bytes (field 10)
                CURRENT_RX=$(echo "$VPN_LINE" | awk '{print $2}' 2>/dev/null || echo "0")
                CURRENT_TX=$(echo "$VPN_LINE" | awk '{print $10}' 2>/dev/null || echo "0")
                case "$CURRENT_RX" in ''|*[!0-9]*) CURRENT_RX="0" ;; esac
                case "$CURRENT_TX" in ''|*[!0-9]*) CURRENT_TX="0" ;; esac
            fi
        fi
        
        # Load previous values and calculate cumulative total
        TOTAL_RX="0"
        TOTAL_TX="0"
        LAST_RX="0"
        LAST_TX="0"
        if [ -f "$DATA_FILE" ]; then
            # shellcheck disable=SC1090
            . "$DATA_FILE" 2>/dev/null || true
        fi
        
        # Detect counter reset (container restart) - current < last means reset
        if { [ "$CURRENT_RX" -lt "$LAST_RX" ] || [ "$CURRENT_TX" -lt "$LAST_TX" ]; } 2>/dev/null; then
            # Counter reset detected - add last values to total before reset
            TOTAL_RX=$((TOTAL_RX + LAST_RX))
            TOTAL_TX=$((TOTAL_TX + LAST_TX))
        fi
        
        # Calculate session values (current readings)
        SESSION_RX="$CURRENT_RX"
        SESSION_TX="$CURRENT_TX"
        
        # Calculate all-time totals
        ALLTIME_RX=$((TOTAL_RX + CURRENT_RX))
        ALLTIME_TX=$((TOTAL_TX + CURRENT_TX))
        
        # Save state
        cat > "$DATA_FILE" <<DATAEOF
LAST_RX=$CURRENT_RX
LAST_TX=$CURRENT_TX
TOTAL_RX=$TOTAL_RX
TOTAL_TX=$TOTAL_TX
DATAEOF
    else
        # Container not running - load saved totals
        ALLTIME_RX="0"
        ALLTIME_TX="0"
        SESSION_RX="0"
        SESSION_TX="0"
        if [ -f "$DATA_FILE" ]; then
            # shellcheck disable=SC1090
            . "$DATA_FILE" 2>/dev/null || true
            ALLTIME_RX=$((TOTAL_RX + LAST_RX))
            ALLTIME_TX=$((TOTAL_TX + LAST_TX))
        fi
    fi
    
    ACTIVE_NAME=$(tr -d '\n\r' < "$NAME_FILE" 2>/dev/null || echo "Unknown")
    if [ -z "$ACTIVE_NAME" ]; then ACTIVE_NAME="Unknown"; fi
    
    WGE_STATUS="down"
    WGE_HOST="Unknown"
    WGE_CLIENTS="0"
    WGE_CONNECTED="0"
    
    WGE_SESSION_RX="0"
    WGE_SESSION_TX="0"
    WGE_TOTAL_RX="0"
    WGE_TOTAL_TX="0"
    WGE_DATA_FILE="/app/.wge_data_usage"
    
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_PREFIX}wg-easy$"; then
        WGE_STATUS="up"
        WGE_HOST=$(docker exec ${CONTAINER_PREFIX}wg-easy printenv WG_HOST 2>/dev/null | tr -d '\n\r' || echo "Unknown")
        if [ -z "$WGE_HOST" ]; then WGE_HOST="Unknown"; fi
        WG_PEER_DATA=$(docker exec ${CONTAINER_PREFIX}wg-easy wg show wg0 2>/dev/null || echo "")
        if [ -n "$WG_PEER_DATA" ]; then
            WGE_CLIENTS=$(echo "$WG_PEER_DATA" | grep -c '^peer:' 2>/dev/null || echo "0")
            CONNECTED_COUNT=0
            
            # Calculate total RX/TX from all peers
            WGE_CURRENT_RX=0
            WGE_CURRENT_TX=0
            for rx in $(echo "$WG_PEER_DATA" | grep "transfer:" | awk '{print $2}' | sed 's/[^0-9]//g' 2>/dev/null || echo ""); do
                case "$rx" in ''|*[!0-9]*) ;; *) WGE_CURRENT_RX=$((WGE_CURRENT_RX + rx)) ;; esac
            done
            for tx in $(echo "$WG_PEER_DATA" | grep "transfer:" | awk '{print $4}' | sed 's/[^0-9]//g' 2>/dev/null || echo ""); do
                case "$tx" in ''|*[!0-9]*) ;; *) WGE_CURRENT_TX=$((WGE_CURRENT_TX + tx)) ;; esac
            done
            
            # Load previous values for WG-Easy
            WGE_LAST_RX="0"
            WGE_LAST_TX="0"
            WGE_SAVED_TOTAL_RX="0"
            WGE_SAVED_TOTAL_TX="0"
            if [ -f "$WGE_DATA_FILE" ]; then
                # shellcheck disable=SC1090
                . "$WGE_DATA_FILE" 2>/dev/null || true
            fi
            
            # Detect counter reset
            if { [ "$WGE_CURRENT_RX" -lt "$WGE_LAST_RX" ] || [ "$WGE_CURRENT_TX" -lt "$WGE_LAST_TX" ]; } 2>/dev/null; then
                WGE_SAVED_TOTAL_RX=$((WGE_SAVED_TOTAL_RX + WGE_LAST_RX))
                WGE_SAVED_TOTAL_TX=$((WGE_SAVED_TOTAL_TX + WGE_LAST_TX))
            fi
            
            WGE_SESSION_RX="$WGE_CURRENT_RX"
            WGE_SESSION_TX="$WGE_CURRENT_TX"
            WGE_TOTAL_RX=$((WGE_SAVED_TOTAL_RX + WGE_CURRENT_RX))
            WGE_TOTAL_TX=$((WGE_SAVED_TOTAL_TX + WGE_CURRENT_TX))
            
            # Save state
            cat > "$WGE_DATA_FILE" <<WGEDATAEOF
WGE_LAST_RX=$WGE_CURRENT_RX
WGE_LAST_TX=$WGE_CURRENT_TX
WGE_SAVED_TOTAL_RX=$WGE_SAVED_TOTAL_RX
WGE_SAVED_TOTAL_TX=$WGE_SAVED_TOTAL_TX
WGEDATAEOF
            
            for hs in $(echo "$WG_PEER_DATA" | grep "latest handshake:" | sed 's/.*latest handshake: //' | sed 's/ seconds.*//' | grep -E '^[0-9]+' 2>/dev/null || echo ""); do
                if [ -n "$hs" ] && [ "$hs" -lt 180 ] 2>/dev/null; then
                    CONNECTED_COUNT=$((CONNECTED_COUNT + 1))
                fi
            done
            WGE_CONNECTED="$CONNECTED_COUNT"
        fi
    fi
    
    ACTIVE_NAME=$(sanitize_json_string "$ACTIVE_NAME")
    ENDPOINT=$(sanitize_json_string "$ENDPOINT")
    PUBLIC_IP=$(sanitize_json_string "$PUBLIC_IP")
    HANDSHAKE_AGO=$(sanitize_json_string "$HANDSHAKE_AGO")
    WGE_HOST=$(sanitize_json_string "$WGE_HOST")
    
    # Check individual privacy services status internally
    SERVICES_JSON="{"
    HEALTH_DETAILS_JSON="{"
    FIRST_SRV=1
    # Added core infrastructure services to the monitoring loop
    for srv in "invidious:3000" "redlib:8080" "wikiless:8180" "memos:5230" "rimgo:3002" "scribe:8280" "breezewiki:10416" "anonymousoverflow:8480" "vert:80" "vertd:24153" "adguard:8083" "portainer:9000" "wg-easy:51821"; do
        s_name=${srv%:*}.base # Temporary placeholder to avoid confusion
        s_name_real="${CONTAINER_PREFIX}${srv%:*} "
        s_port=${srv#*:} 
        [ $FIRST_SRV -eq 0 ] && { SERVICES_JSON="$SERVICES_JSON,"; HEALTH_DETAILS_JSON="$HEALTH_DETAILS_JSON,"; }
        
        # Priority 1: Check Docker container health if it exists
        HEALTH="unknown"
        DETAILS=""
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${s_name_real}$"; then
            STATE_JSON=$(docker inspect --format='{{json .State}}' "$s_name_real" 2>/dev/null)
            HEALTH=$(echo "$STATE_JSON" | grep -oP '"Health":.*"Status":"\K[^"\n]+' || echo "running")
            # If unhealthy, extract last error
            if [ "$HEALTH" = "unhealthy" ]; then
                DETAILS=$(echo "$STATE_JSON" | grep -oP '"Log":\[\{.*"Output":"\K[^"\\]+' | tail -1 | sed 's/\\n/ /g' | sed 's/\\//g')
            fi
        fi

        # We keep the JSON key as the original name for dashboard compatibility
        s_key=${srv%:*} 
        if [ "$HEALTH" = "healthy" ] || [ "$HEALTH" = "running" ]; then
            SERVICES_JSON="$SERVICES_JSON""$s_key":"up""
        elif [ "$HEALTH" = "unhealthy" ] || [ "$HEALTH" = "starting" ]; then
            # If Docker says unhealthy but port is reachable, count as up
            # For services in gluetun network, we check against gluetun container
            TARGET_HOST="$s_name_real"
            case "$s_key" in
                invidious|redlib|wikiless|rimgo|scribe|breezewiki|anonymousoverflow) TARGET_HOST="${CONTAINER_PREFIX}gluetun" ;; 
            esac
            if nc -z -w 2 "$TARGET_HOST" "$s_port" >/dev/null 2>&1; then
                SERVICES_JSON="$SERVICES_JSON""$s_key":"up""
            else
                SERVICES_JSON="$SERVICES_JSON""$s_key":"$HEALTH""
            fi
        else
            # Fallback to network check
            TARGET_HOST="$s_name_real"
            case "$s_key" in
                invidious|redlib|wikiless|rimgo|scribe|breezewiki|anonymousoverflow) TARGET_HOST="${CONTAINER_PREFIX}gluetun" ;; 
            esac
            
            if nc -z -w 2 "$TARGET_HOST" "$s_port" >/dev/null 2>&1; then
                SERVICES_JSON="$SERVICES_JSON""$s_key":"up""
            else
                SERVICES_JSON="$SERVICES_JSON""$s_key":"down""
            fi
        fi
        HEALTH_DETAILS_JSON="$HEALTH_DETAILS_JSON""$s_key":"$(sanitize_json_string "$DETAILS")""
        FIRST_SRV=0
    done
    SERVICES_JSON="$SERVICES_JSON}"
    HEALTH_DETAILS_JSON="$HEALTH_DETAILS_JSON}"

    printf '{"gluetun":{"status":"%s","healthy":%s,"active_profile":"%s","endpoint":"%s","public_ip":"%s","handshake_ago":"%s","session_rx":"%s","session_tx":"%s","total_rx":"%s","total_tx":"%s"},"wgeasy":{"status":"%s","host":"%s","clients":"%s","connected":"%s","session_rx":"%s","session_tx":"%s","total_rx":"%s","total_tx":"%s"},"services":%s,"health_details":%s}' \
        "$GLUETUN_STATUS" "$GLUETUN_HEALTHY" "$ACTIVE_NAME" "$ENDPOINT" "$PUBLIC_IP" "$HANDSHAKE_AGO" "$SESSION_RX" "$SESSION_TX" "$ALLTIME_RX" "$ALLTIME_TX" \
        "$WGE_STATUS" "$WGE_HOST" "$WGE_CLIENTS" "$WGE_CONNECTED" "$WGE_SESSION_RX" "$WGE_SESSION_TX" "$WGE_TOTAL_RX" "$WGE_TOTAL_TX" \
        "$SERVICES_JSON" "$HEALTH_DETAILS_JSON"
fi
