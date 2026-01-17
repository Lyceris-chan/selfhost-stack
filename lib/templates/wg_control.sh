#!/usr/bin/env bash
set -euo pipefail
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

log_maintenance() {
	if [ -f "/app/deployment.log" ]; then
		printf '{"timestamp": "%s", "level": "INFO", "category": "MAINTENANCE", "source": "orchestrator", "message": "%s"}\n' "$(date +"%Y-%m-%d %H:%M:%S")" "$1" >>"/app/deployment.log"
	fi
}

if [ "$ACTION" = "activate" ]; then
	if ! flock -n 9; then
		echo "Error: Another control operation is in progress"
		exit 1
	fi
	if [ -f "$PROFILES_DIR/$PROFILE_NAME.conf" ]; then
		log_maintenance "Activating VPN profile: $PROFILE_NAME"
		ln -sf "$PROFILES_DIR/$PROFILE_NAME.conf" "$ACTIVE_CONF"
		echo "$PROFILE_NAME" >"$NAME_FILE"
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
			i=$((i + 1))
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
		log_maintenance "Deleting VPN profile: $PROFILE_NAME"
		rm "$PROFILES_DIR/$PROFILE_NAME.conf"
	fi
elif [ "$ACTION" = "status" ]; then
	# Disable exit on error for status check to ensure we always return JSON
	set +e
	GLUETUN_STATUS="down"
	GLUETUN_HEALTHY="false"
	HANDSHAKE_AGO="N/A"
	ENDPOINT="--"
	PUBLIC_IP="--"
	DATA_FILE="/app/.data_usage"

	# Check if gluetun container is running
	if docker ps --filter "name=^${CONTAINER_PREFIX}gluetun$" --filter "status=running" --format '{{.Names}}' 2>/dev/null | grep -q "gluetun"; then
		HEALTH=$(docker inspect --format='{{.State.Health.Status}}' ${CONTAINER_PREFIX}gluetun 2>/dev/null || echo "unknown")
		if [ "$HEALTH" = "healthy" ]; then
			GLUETUN_HEALTHY="true"
			GLUETUN_STATUS="up"
		else
			GLUETUN_STATUS="starting"
		fi

		if [ "$GLUETUN_HEALTHY" = "true" ]; then
			VPN_STATUS_RESPONSE=$(docker exec ${CONTAINER_PREFIX}gluetun wget --user=gluetun --password="__ADMIN_PASS_RAW__" -qO- --timeout=3 http://127.0.0.1:8000/v1/vpn/status 2>/dev/null || echo "")
			if [ -n "$VPN_STATUS_RESPONSE" ]; then
				if echo "$VPN_STATUS_RESPONSE" | grep -q '"status":"running"'; then
					HANDSHAKE_AGO="Connected"
				else
					GLUETUN_STATUS="starting"
					HANDSHAKE_AGO="Connecting..."
				fi
			else
				HANDSHAKE_AGO="Connected (API unavailable)"
			fi
		else
			HANDSHAKE_AGO="Waiting for health check..."
		fi

		PUBLIC_IP_RESPONSE=$(docker exec ${CONTAINER_PREFIX}gluetun wget --user=gluetun --password="__ADMIN_PASS_RAW__" -qO- --timeout=3 http://127.0.0.1:8000/v1/publicip/ip 2>/dev/null || echo "")
		if [ -n "$PUBLIC_IP_RESPONSE" ]; then
			EXTRACTED_IP=$(echo "$PUBLIC_IP_RESPONSE" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "")
			[ -n "$EXTRACTED_IP" ] && PUBLIC_IP="$EXTRACTED_IP"
		fi

		if [ "$PUBLIC_IP" = "--" ]; then
			PUBLIC_IP=$(docker exec ${CONTAINER_PREFIX}gluetun wget -qO- --timeout=5 https://api.ipify.org 2>/dev/null || echo "--")
		fi

		WG_CONF_ENDPOINT=$(docker exec ${CONTAINER_PREFIX}gluetun cat /gluetun/wireguard/wg0.conf 2>/dev/null | grep -i '^Endpoint' | cut -d'=' -f2 | tr -d ' ' | head -1 || echo "")
		[ -n "$WG_CONF_ENDPOINT" ] && ENDPOINT="$WG_CONF_ENDPOINT"

		NET_DEV=$(docker exec ${CONTAINER_PREFIX}gluetun cat /proc/net/dev 2>/dev/null || echo "")
		CURRENT_RX="0"
		CURRENT_TX="0"
		if [ -n "$NET_DEV" ]; then
			VPN_LINE=$(echo "$NET_DEV" | grep -E '^\s*(tun0|wg0):' | head -1 || echo "")
			if [ -n "$VPN_LINE" ]; then
				CURRENT_RX=$(echo "$VPN_LINE" | awk '{print $2}' 2>/dev/null || echo "0")
				CURRENT_TX=$(echo "$VPN_LINE" | awk '{print $10}' 2>/dev/null || echo "0")
				case "$CURRENT_RX" in '' | *[!0-9]*) CURRENT_RX="0" ;; esac
				case "$CURRENT_TX" in '' | *[!0-9]*) CURRENT_TX="0" ;; esac
			fi
		fi

		TOTAL_RX="0"
		TOTAL_TX="0"
		LAST_RX="0"
		LAST_TX="0"
		if [ -f "$DATA_FILE" ]; then
			# shellcheck disable=SC1090
			. "$DATA_FILE" 2>/dev/null || true
		fi

		if [ "$CURRENT_RX" -lt "$LAST_RX" ] 2>/dev/null || [ "$CURRENT_TX" -lt "$LAST_TX" ] 2>/dev/null; then
			TOTAL_RX=$((TOTAL_RX + LAST_RX))
			TOTAL_TX=$((TOTAL_TX + LAST_TX))
		fi

		SESSION_RX="$CURRENT_RX"
		SESSION_TX="$CURRENT_TX"
		ALLTIME_RX=$((TOTAL_RX + CURRENT_RX))
		ALLTIME_TX=$((TOTAL_TX + CURRENT_TX))

		cat >"$DATA_FILE" <<DATAEOF
LAST_RX=$CURRENT_RX
LAST_TX=$CURRENT_TX
TOTAL_RX=$TOTAL_RX
TOTAL_TX=$TOTAL_TX
DATAEOF
	else
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

	ACTIVE_NAME=$(tr -d '\n\r' <"$NAME_FILE" 2>/dev/null || echo "Unknown")
	[ -z "$ACTIVE_NAME" ] && ACTIVE_NAME="Unknown"

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
		[ -z "$WGE_HOST" ] && WGE_HOST="Unknown"
		WG_PEER_DATA=$(docker exec ${CONTAINER_PREFIX}wg-easy wg show wg0 2>/dev/null || echo "")
		if [ -n "$WG_PEER_DATA" ]; then
			WGE_CLIENTS=$(echo "$WG_PEER_DATA" | grep -c '^peer:' 2>/dev/null || echo "0")
			CONNECTED_COUNT=0
			WGE_CURRENT_RX=0
			WGE_CURRENT_TX=0
			for rx in $(echo "$WG_PEER_DATA" | grep "transfer:" | awk '{print $2}' | sed 's/[^0-9]//g' 2>/dev/null || echo ""); do
				case "$rx" in '' | *[!0-9]*) ;; *) WGE_CURRENT_RX=$((WGE_CURRENT_RX + rx)) ;; esac
			done
			for tx in $(echo "$WG_PEER_DATA" | grep "transfer:" | awk '{print $4}' | sed 's/[^0-9]//g' 2>/dev/null || echo ""); do
				case "$tx" in '' | *[!0-9]*) ;; *) WGE_CURRENT_TX=$((WGE_CURRENT_TX + tx)) ;; esac
			done

			WGE_LAST_RX="0"
			WGE_LAST_TX="0"
			WGE_SAVED_TOTAL_RX="0"
			WGE_SAVED_TOTAL_TX="0"
			if [ -f "$WGE_DATA_FILE" ]; then . "$WGE_DATA_FILE" 2>/dev/null || true; fi
			if [ "$WGE_CURRENT_RX" -lt "$WGE_LAST_RX" ] 2>/dev/null || [ "$WGE_CURRENT_TX" -lt "$WGE_LAST_TX" ] 2>/dev/null; then
				WGE_SAVED_TOTAL_RX=$((WGE_SAVED_TOTAL_RX + WGE_LAST_RX))
				WGE_SAVED_TOTAL_TX=$((WGE_SAVED_TOTAL_TX + WGE_LAST_TX))
			fi
			WGE_SESSION_RX="$WGE_CURRENT_RX"
			WGE_SESSION_TX="$WGE_CURRENT_TX"
			WGE_TOTAL_RX=$((WGE_SAVED_TOTAL_RX + WGE_CURRENT_RX))
			WGE_TOTAL_TX=$((WGE_SAVED_TOTAL_TX + WGE_CURRENT_TX))
			cat >"$WGE_DATA_FILE" <<WGEDATAEOF
WGE_LAST_RX=$WGE_CURRENT_RX
WGE_LAST_TX=$WGE_CURRENT_TX
WGE_SAVED_TOTAL_RX=$WGE_SAVED_TOTAL_RX
WGE_SAVED_TOTAL_TX=$WGE_SAVED_TOTAL_TX
WGEDATAEOF
			for hs in $(echo "$WG_PEER_DATA" | grep "latest handshake:" | sed 's/.*latest handshake: //' | sed 's/ seconds.*//' | grep -E '^[0-9]+' 2>/dev/null || echo ""); do
				if [ -n "$hs" ] && [ "$hs" -lt 180 ] 2>/dev/null; then CONNECTED_COUNT=$((CONNECTED_COUNT + 1)); fi
			done
			WGE_CONNECTED="$CONNECTED_COUNT"
		fi
	fi

	ACTIVE_NAME=$(sanitize_json_string "$ACTIVE_NAME")
	ENDPOINT=$(sanitize_json_string "$ENDPOINT")
	PUBLIC_IP=$(sanitize_json_string "$PUBLIC_IP")
	HANDSHAKE_AGO=$(sanitize_json_string "$HANDSHAKE_AGO")
	WGE_HOST=$(sanitize_json_string "$WGE_HOST")

	SERVICES_JSON="{"
	HEALTH_DETAILS_JSON="{"
	FIRST_SRV=1
	for srv in "invidious:3000" "redlib:8081" "wikiless:8180" "memos:5230" "rimgo:3002" "scribe:8280" "breezewiki:10416" "anonymousoverflow:8480" "vert:80" "vertd:24153" "adguard:8083" "portainer:9000" "wg-easy:51821" "cobalt:9000" "searxng:8080" "immich:2283" "odido-booster:8085"; do
		s_key=${srv%:*}
		s_port=${srv#*:}
		s_name_real="${CONTAINER_PREFIX}${s_key}"
		if [ "$s_key" = "immich" ]; then s_name_real="${CONTAINER_PREFIX}immich-server"; fi
		if [ "$s_key" = "cobalt" ]; then s_name_real="${CONTAINER_PREFIX}cobalt-web"; fi
		[ $FIRST_SRV -eq 0 ] && {
			SERVICES_JSON="$SERVICES_JSON,"
			HEALTH_DETAILS_JSON="$HEALTH_DETAILS_JSON,"
		}
		HEALTH="unknown"
		DETAILS=""
		if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${s_name_real}$"; then
			HEALTH=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$s_name_real" 2>/dev/null || echo "running")
			if [ "$HEALTH" = "unhealthy" ]; then
				DETAILS=$(docker inspect --format='{{range .State.Health.Log}}{{println .Output}}{{end}}' "$s_name_real" 2>/dev/null | tail -1 | tr -d '\n' | sed 's/\\/\\\\/g; s/"/\\"/g' | cut -c1-100)
			fi
		fi
		if [ "$HEALTH" = "healthy" ] || [ "$HEALTH" = "running" ]; then
			SERVICES_JSON="${SERVICES_JSON}\"${s_key}\":\"up\""
		else
			TARGET_HOST="$s_name_real"
			case "$s_key" in invidious | redlib | wikiless | rimgo | scribe | breezewiki | anonymousoverflow | cobalt | searxng | immich | odido-booster)
				if docker inspect --format='{{.HostConfig.NetworkMode}}' "$s_name_real" 2>/dev/null | grep -q "gluetun"; then TARGET_HOST="${CONTAINER_PREFIX}gluetun"; fi
				;;
			esac
			if nc -z -w 2 "$TARGET_HOST" "$s_port" >/dev/null 2>&1; then
				SERVICES_JSON="${SERVICES_JSON}\"${s_key}\":\"up\""
			else
				SERVICES_JSON="${SERVICES_JSON}\"${s_key}\":\"${HEALTH}\""
			fi
		fi
		HEALTH_DETAILS_JSON="${HEALTH_DETAILS_JSON}\"${s_key}\":\"$(sanitize_json_string "$DETAILS")\""
		FIRST_SRV=0
	done
	SERVICES_JSON="$SERVICES_JSON}"
	HEALTH_DETAILS_JSON="$HEALTH_DETAILS_JSON}"
	printf '{"gluetun":{"status":"%s","healthy":%s,"active_profile":"%s","endpoint":"%s","public_ip":"%s","handshake_ago":"%s","session_rx":"%s","session_tx":"%s","total_rx":"%s","total_tx":"%s"},"wgeasy":{"status":"%s","host":"%s","clients":"%s","connected":"%s","session_rx":"%s","session_tx":"%s","total_rx":"%s","total_tx":"%s"},"services":%s,"health_details":%s}' \
		"$GLUETUN_STATUS" "$GLUETUN_HEALTHY" "$ACTIVE_NAME" "$ENDPOINT" "$PUBLIC_IP" "$HANDSHAKE_AGO" "$SESSION_RX" "$SESSION_TX" "$ALLTIME_RX" "$ALLTIME_TX" \
		"$WGE_STATUS" "$WGE_HOST" "$WGE_CLIENTS" "$WGE_CONNECTED" "$WGE_SESSION_RX" "$WGE_SESSION_TX" "$WGE_TOTAL_RX" "$WGE_TOTAL_TX" \
		"$SERVICES_JSON" "$HEALTH_DETAILS_JSON"
	set -e
fi
