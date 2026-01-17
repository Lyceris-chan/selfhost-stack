#!/usr/bin/env bash
# Docker Compose generation logic.
# Defines service configurations and appends them to the compose file.
set -euo pipefail

# Helper to check if a service should be deployed
should_deploy() {
	local srv="$1"
	if [[ -z "${SELECTED_SERVICES:-}" ]]; then
		return 0
	fi
	if echo "${SELECTED_SERVICES}" | grep -qE "(^|,)$srv(,|$)"; then
		return 0
	fi
	return 1
}

# Service definition functions
append_hub_api() {
	local dockerfile=""
	local cors_json=""

	if ! should_deploy "hub-api"; then
		return 0
	fi
	dockerfile=$(detect_dockerfile "${SRC_DIR}/hub-api" || echo "Dockerfile")

	# Generate robust JSON for CORS_ORIGINS using Python to avoid string formatting errors
	cors_json=$(LAN_IP="${LAN_IP}" DASH_PORT="${PORT_DASHBOARD_WEB}" DESEC_DOMAIN="${DESEC_DOMAIN}" "${PYTHON_CMD}" -c "
import json, os
try:
    lan_ip = os.environ.get('LAN_IP', '127.0.0.1')
    port = os.environ.get('DASH_PORT', '8088')
    domain = os.environ.get('DESEC_DOMAIN', '')
    origins = [
        'http://localhost',
        'http://localhost:' + port,
        'http://' + lan_ip,
        'http://' + lan_ip + ':' + port
    ]
    if domain:
        origins.append('https://' + domain)
    print(json.dumps(origins))
except Exception:
    print('[\"http://localhost\"]')
")

	cat >>"${COMPOSE_FILE}" <<EOF
    hub-api:
        pull_policy: build
        build:
            context: ${SRC_DIR}/hub-api
            dockerfile: ${dockerfile}
        image: selfhost/hub-api:latest
        container_name: ${CONTAINER_PREFIX}api
        labels:
            - "casaos.skip=true"
        networks:
            - frontend
            - mgmt
        ports: ["${LAN_IP}:${PORT_API}:55555"]
        extra_hosts:
            - "host.docker.internal:host-gateway"
        volumes:
            - "${WG_PROFILES_DIR}:/profiles"
            - "${ACTIVE_WG_CONF}:/active-wg.conf"
            - "${ACTIVE_PROFILE_NAME_FILE}:/app/.active_profile_name"
            - "${WG_CONTROL_SCRIPT}:/usr/local/bin/wg-control.sh"
            - "${PATCHES_SCRIPT}:/app/patches.sh"
            - "${CERT_MONITOR_SCRIPT}:/usr/local/bin/cert-monitor.sh"
            - "${MIGRATE_SCRIPT}:/usr/local/bin/migrate.sh"
            - "$(realpath "$0"):/app/zima.sh:ro"
            - "${COMPOSE_FILE}:/app/docker-compose.yml:ro"
            - "${HISTORY_LOG}:/app/deployment.log"
            - "${SECRETS_FILE}:/app/.secrets"
            - "${BASE_DIR}/.data_usage:/app/.data_usage"
            - "${BASE_DIR}/.wge_data_usage:/app/.wge_data_usage"
            - "${AGH_CONF_DIR}:/etc/adguard/conf"
            - "${DOCKER_AUTH_DIR}:/root/.docker:ro"
            - "${ASSETS_DIR}:/assets"
            - "${SRC_DIR}:/app/sources"
            - "${CONFIG_DIR}/theme.json:/app/theme.json"
            - "${CONFIG_DIR}/services.json:/app/services.json"
            - "${DATA_DIR}/hub-api:/app/data"
            - "${BACKUP_DIR}:/app/backups"
        environment:
            - "HUB_API_KEY=${HUB_API_KEY_COMPOSE}"
            - "ADMIN_PASS_RAW=${ADMIN_PASS_COMPOSE}"
            - "VPN_PASS_RAW=${VPN_PASS_COMPOSE}"
            - "CONTAINER_PREFIX=${CONTAINER_PREFIX}"
            - "APP_NAME=${APP_NAME}"
            - "BASE_DIR=/app"
            - "PROJECT_ROOT=/app"
            - "UPDATE_STRATEGY=${UPDATE_STRATEGY}"
            - "LAN_IP=${LAN_IP}"
            - "WG_HOST=${LAN_IP}"
            - "DESEC_DOMAIN=${DESEC_DOMAIN}"
            - "DOCKER_CONFIG=/root/.docker"
            - "DOCKER_HOST=tcp://docker-proxy:2375"
            - 'CORS_ORIGINS=${cors_json}'
        healthcheck:
            test: ["CMD-SHELL", "curl -f http://localhost:55555/api/health || exit 1"]
            interval: 20s
            timeout: 10s
            retries: 5
        depends_on:
            docker-proxy: {condition: service_started}
            gluetun: {condition: service_healthy}
        restart: unless-stopped
        deploy:
            resources:
                limits: {cpus: '0.5', memory: 256M}
EOF
}

append_odido_booster() {
	local dockerfile=""
	local vpn_mode="true"

	if ! should_deploy "odido-booster"; then
		return 0
	fi
	dockerfile=$(detect_dockerfile "${SRC_DIR}/odido-bundle-booster" || echo "Dockerfile")
	if [[ -f "${CONFIG_DIR}/theme.json" ]]; then
		vpn_mode=$(grep -o '"odido_use_vpn"[[:space:]]*:[[:space:]]*\(true\|false\)' "${CONFIG_DIR}/theme.json" 2>/dev/null | grep -o 'true\|false' || echo "true")
	fi

	cat >>"${COMPOSE_FILE}" <<EOF
    odido-booster:
        pull_policy: build
        build:
            context: ${SRC_DIR}/odido-bundle-booster
            dockerfile: ${dockerfile}
        image: selfhost/odido-booster:${ODIDO_BOOSTER_IMAGE_TAG:-latest}
        container_name: ${CONTAINER_PREFIX}odido-booster
EOF

	if [[ "${vpn_mode}" == "true" ]]; then
		cat >>"${COMPOSE_FILE}" <<EOF
        network_mode: "container:${CONTAINER_PREFIX}gluetun"
        depends_on:
            gluetun: {condition: service_healthy}
EOF
	else
		cat >>"${COMPOSE_FILE}" <<EOF
        networks: [frontend]
        ports: ["${LAN_IP}:${PORT_ODIDO}:8085"]
EOF
	fi

	cat >>"${COMPOSE_FILE}" <<EOF
        environment:
            - "API_KEY=${HUB_API_KEY_COMPOSE}"
            - "ODIDO_USER_ID=${ODIDO_USER_ID}"
            - "ODIDO_TOKEN=${ODIDO_TOKEN}"
            - "PORT=8085"
        healthcheck:
            test: ["CMD", "wget", "--spider", "-q", "http://127.0.0.1:8085/docs"]
            interval: 30s
            timeout: 5s
            retries: 3
        volumes:
            - ${DATA_DIR}/odido:/data
        restart: unless-stopped
        deploy:
            resources:
                limits: {cpus: '0.3', memory: 128M}
EOF
}

append_memos() {
	if ! should_deploy "memos"; then
		return 0
	fi
	cat >>"${COMPOSE_FILE}" <<EOF
    memos:
        image: ghcr.io/usememos/memos:latest
        container_name: ${CONTAINER_PREFIX}memos
        user: "1000:1000"
        networks: [frontend]
        ports: ["${LAN_IP}:${PORT_MEMOS}:5230"]
        environment:
            - "MEMOS_MODE=prod"
        volumes: ["${MEMOS_HOST_DIR}:/var/opt/memos"]
        healthcheck:
            test: ["CMD", "wget", "--spider", "-q", "http://127.0.0.1:5230/"]
            interval: 30s
            timeout: 5s
            retries: 3
        restart: unless-stopped
        shm_size: 1gb
        deploy:
            resources:
                limits: {cpus: '0.5', memory: 1G}
EOF
}

append_gluetun() {
	if ! should_deploy "gluetun"; then
		return 0
	fi

	cat >>"${COMPOSE_FILE}" <<EOF
    gluetun:
        image: qmcgaw/gluetun:latest
        container_name: ${CONTAINER_PREFIX}gluetun
        labels:
            - "casaos.skip=true"
        cap_add: [NET_ADMIN]
        sysctls:
            - net.ipv4.conf.all.src_valid_mark=1
            - net.ipv4.ip_forward=1
        devices:
            - /dev/net/tun:/dev/net/tun
        networks:
            frontend:
                ipv4_address: 172.${FOUND_OCTET}.0.254
EOF

	cat >>"${COMPOSE_FILE}" <<EOF
        ports:
            - "${LAN_IP}:${PORT_REDLIB}:${PORT_INT_REDLIB}/tcp"
            - "${LAN_IP}:${PORT_WIKILESS}:${PORT_INT_WIKILESS}/tcp"
            - "${LAN_IP}:${PORT_INVIDIOUS}:${PORT_INT_INVIDIOUS}/tcp"
            - "${LAN_IP}:${PORT_RIMGO}:${PORT_INT_RIMGO}/tcp"
            - "${LAN_IP}:${PORT_SCRIBE}:${PORT_SCRIBE}/tcp"
            - "${LAN_IP}:${PORT_BREEZEWIKI}:${PORT_INT_BREEZEWIKI}/tcp"
            - "${LAN_IP}:${PORT_ANONYMOUS}:${PORT_INT_ANONYMOUS}/tcp"
            - "${LAN_IP}:${PORT_COMPANION}:${PORT_INT_COMPANION}/tcp"
            - "${LAN_IP}:${PORT_SEARXNG}:${PORT_INT_SEARXNG}/tcp"
            - "${LAN_IP}:${PORT_IMMICH}:${PORT_INT_IMMICH}/tcp"
            - "${LAN_IP}:${PORT_COBALT}:${PORT_INT_COBALT}/tcp"
            - "${LAN_IP}:${PORT_COBALT_API}:${PORT_INT_COBALT_API}/tcp"
            - "${LAN_IP}:8085:8085/tcp"
EOF

	cat >>"${COMPOSE_FILE}" <<EOF
        volumes:
            - "${ACTIVE_WG_CONF}:/gluetun/wireguard/wg0.conf:ro"
        environment:
            - "VPN_SERVICE_PROVIDER=custom"
            - "VPN_TYPE=wireguard"
            - "FIREWALL=${VPN_FIREWALL:-on}"
            - "FIREWALL_OUTBOUND_SUBNETS=${DOCKER_SUBNET}"
            - "FIREWALL_VPN_INPUT_PORTS=10416,8080,8081,8085,8180,3000,3002,8280,8480,80,24153,8282,9000,2283"
            - "HTTPPROXY=on"
            - "DNS_ADDRESS=${GLUETUN_DNS_ADDRESS:-127.0.0.1}"
            - "DOT=${GLUETUN_DOT:-on}"
            - "DNS_KEEP_NAMESERVERS=off"
            - "DNS_UPSTREAM_RESOLVERS=quad9"
            - "HEALTH_TARGET_ADDRESSES=github.com:443"
            - "HEALTH_ICMP_TARGET_IPS=9.9.9.9"
            - "RESTART_VPN_ON_HEALTHCHECK_FAILURE=${RESTART_VPN_ON_HEALTHCHECK_FAILURE:-yes}"
            - "PUBLICIP_API_BACKUPS=ifconfigco,ip2location"
        healthcheck:
            test: ["CMD-SHELL", "${GLUETUN_HEALTHCHECK_COMMAND:-wget -qO- http://127.0.0.1:9999/ || exit 1}"]
            interval: 30s
            timeout: 10s
            retries: 5
        restart: unless-stopped
        deploy:
            resources:
                limits: {cpus: '2.0', memory: 512M}
EOF
}

append_dashboard() {
	if ! should_deploy "dashboard"; then
		return 0
	fi
	"${SUDO}" mkdir -p "${SRC_DIR}/dashboard"
	cat <<-DASHEOF | "${SUDO}" tee "${SRC_DIR}/dashboard/Dockerfile" >/dev/null
		FROM nginx:alpine
		RUN mkdir -p /var/cache/nginx /var/log/nginx /var/run/nginx /var/lib/nginx /usr/share/nginx/html && \
		    chown -R 1000:1000 /var/cache/nginx /var/log/nginx /var/run/nginx /var/lib/nginx /usr/share/nginx/html && \
		    chmod -R 755 /usr/share/nginx/html && \
		    sed -i 's/^user/#user/' /etc/nginx/nginx.conf && \
		    sed -i 's|pid .*|pid /tmp/nginx.pid;|g' /etc/nginx/nginx.conf
		USER 1000
		COPY . /usr/share/nginx/html
		EXPOSE ${PORT_DASHBOARD_WEB}
		CMD ["nginx", "-g", "daemon off;"]
	DASHEOF

	cat >>"${COMPOSE_FILE}" <<EOF
    dashboard:
        pull_policy: build
        build:
            context: ${SRC_DIR}/dashboard
        container_name: ${CONTAINER_PREFIX}dashboard
        networks: [frontend]
        ports:
            - "${LAN_IP}:${PORT_DASHBOARD_WEB}:${PORT_DASHBOARD_WEB}"
            - "${LAN_IP}:8443:8443"
        volumes:
            - "${ASSETS_DIR}:/usr/share/nginx/html/assets:ro"
            - "${DASHBOARD_FILE}:/usr/share/nginx/html/index.html:ro"
            - "${NGINX_CONF}:/etc/nginx/conf.d/default.conf:ro"
            - "${AGH_CONF_DIR}:/etc/adguard/conf:ro"
        labels:
            - "dev.casaos.app.ui.protocol=http"
            - "dev.casaos.app.ui.port=${PORT_DASHBOARD_WEB}"
            - "dev.casaos.app.ui.hostname=${LAN_IP}"
            - "dev.casaos.app.ui.icon=http://${LAN_IP}:${PORT_DASHBOARD_WEB}/assets/icon.svg"
            - "dev.casaos.app.icon=http://${LAN_IP}:${PORT_DASHBOARD_WEB}/assets/icon.svg"
            - "io.casaos.app.title=Privacy Hub"
            - "io.casaos.app.icon=http://${LAN_IP}:${PORT_DASHBOARD_WEB}/assets/icon.svg"
            - "casaos.icon=http://${LAN_IP}:${PORT_DASHBOARD_WEB}/assets/icon.svg"
            - "casaos.title=Privacy Hub"
            - "casaos.port=${PORT_DASHBOARD_WEB}"
            - "casaos.scheme=http"
        depends_on:
            hub-api: {condition: service_healthy}
        healthcheck:
            test: ["CMD", "wget", "-qO-", "http://127.0.0.1:${PORT_DASHBOARD_WEB}/"]
            interval: 30s
            timeout: 5s
            retries: 3
        restart: unless-stopped
        deploy:
            resources:
                limits: {cpus: '0.3', memory: 128M}
EOF
}

append_portainer() {
	if ! should_deploy "portainer"; then
		return 0
	fi
	"${SUDO}" mkdir -p "${SRC_DIR}/portainer"
	cat <<-PORTEOF | "${SUDO}" tee "${SRC_DIR}/portainer/Dockerfile" >/dev/null
		FROM alpine:3.20
		COPY --from=portainer/portainer-ce:latest /portainer /portainer
		COPY --from=portainer/portainer-ce:latest /public /public
		COPY --from=portainer/portainer-ce:latest /mustache-templates /mustache-templates
		WORKDIR /
		EXPOSE 9000 9443
		ENTRYPOINT ["/portainer"]
	PORTEOF

	cat >>"${COMPOSE_FILE}" <<EOF
    portainer:
        image: portainer/portainer-ce:latest
        container_name: ${CONTAINER_PREFIX}portainer
        command: ["-H", "tcp://docker-proxy:2375", "--admin-password", "${PORTAINER_HASH_COMPOSE}", "--no-analytics"]
        networks:
            - frontend
            - mgmt
        ports: ["${LAN_IP}:${PORT_PORTAINER}:9000"]
        volumes: ["${DATA_DIR}/portainer:/data"]
        healthcheck:
            test: ["NONE"]
        depends_on:
            docker-proxy: {condition: service_started}
        restart: unless-stopped
        deploy:
            resources:
                limits: {cpus: '0.5', memory: 512M}
EOF
}

append_adguard() {
	if ! should_deploy "adguard"; then
		return 0
	fi
	cat >>"${COMPOSE_FILE}" <<EOF
    adguard:
        image: adguard/adguardhome:latest
        container_name: ${CONTAINER_PREFIX}adguard
        networks: [frontend]
        ports:
            - "${LAN_IP}:53:53/udp"
            - "${LAN_IP}:53:53/tcp"
            - "${LAN_IP}:${PORT_ADGUARD_WEB}:${PORT_ADGUARD_WEB}/tcp"
            - "${LAN_IP}:443:443/tcp"
            - "${LAN_IP}:443:443/udp"
            - "${LAN_IP}:853:853/tcp"
            - "${LAN_IP}:853:853/udp"
        volumes: ["${DATA_DIR}/adguard-work:/opt/adguardhome/work", "${AGH_CONF_DIR}:/opt/adguardhome/conf"]
        healthcheck:
            test: ["CMD", "wget", "--spider", "-q", "http://localhost:8083/"]
            interval: 30s
            timeout: 10s
            retries: 3
        depends_on:
            - unbound
        restart: unless-stopped
        deploy:
            resources:
                limits: {cpus: '0.5', memory: 512M}
EOF
}

append_unbound() {
	if ! should_deploy "unbound"; then
		return 0
	fi
	cat >>"${COMPOSE_FILE}" <<EOF
    unbound:
        image: klutchell/unbound:latest
        container_name: ${CONTAINER_PREFIX}unbound
        command: ["-d", "-c", "/etc/unbound/unbound.conf"]
        networks:
            frontend:
                ipv4_address: 172.${FOUND_OCTET}.0.250
        volumes:
            - "${UNBOUND_CONF}:/etc/unbound/unbound.conf:ro"
        healthcheck:
            test: ["CMD", "drill", "@127.0.0.1", "example.com"]
            interval: 30s
            timeout: 5s
            retries: 3
        restart: unless-stopped
        deploy:
            resources:
                limits: {cpus: '0.5', memory: 256M}
EOF
}

append_wg_easy() {
	if ! should_deploy "wg-easy"; then
		return 0
	fi
	# WG_HASH needs special handling - bcrypt hashes contain $ which must be escaped
	# Docker Compose requires $$ to represent a literal $ sign
	local wg_hash_escaped="${WG_HASH_CLEAN//\$/\$\$}"
	cat >>"${COMPOSE_FILE}" <<EOF
    wg-easy:
        image: ghcr.io/wg-easy/wg-easy:latest
        container_name: ${CONTAINER_PREFIX}wg-easy
        network_mode: "host"
        environment:
            - "PASSWORD_HASH=${wg_hash_escaped}"
            - "WG_DEFAULT_DNS=${LAN_IP}"
            - "WG_ALLOWED_IPS=10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
            - "WG_HOST=${PUBLIC_IP}"
            - "WG_PORT=51820"
            - "WG_PERSISTENT_KEEPALIVE=25"
        volumes: ["${DATA_DIR}/wireguard:/etc/wireguard"]
        cap_add: [NET_ADMIN, SYS_MODULE]
        healthcheck:
            test: ["CMD", "wget", "-q", "--tries=1", "--spider", "http://127.0.0.1:51821/"]
            interval: 30s
            timeout: 10s
            retries: 3
        restart: unless-stopped
        deploy:
            resources:
                limits: {cpus: '1.0', memory: 256M}
EOF
}

append_redlib() {
	if ! should_deploy "redlib"; then
		return 0
	fi
	cat >>"${COMPOSE_FILE}" <<EOF
    redlib:
        image: quay.io/redlib/redlib:latest
        container_name: ${CONTAINER_PREFIX}redlib
EOF

	cat >>"${COMPOSE_FILE}" <<EOF
        network_mode: "container:${CONTAINER_PREFIX}gluetun"
        depends_on: {gluetun: {condition: service_healthy} }
EOF

	cat >>"${COMPOSE_FILE}" <<EOF
        environment:
            - "REDLIB_PORT=8081"
            - "PORT=8081"
            - "REDLIB_ADDRESS=0.0.0.0"
            - "REDLIB_DEFAULT_WIDE=on"
            - "REDLIB_DEFAULT_USE_HLS=on"
            - "REDLIB_DEFAULT_SHOW_NSFW=on"
        restart: always
        user: nobody
        read_only: true
        security_opt: [no-new-privileges:true]
        cap_drop: [ALL]
        healthcheck:
            test: ["CMD-SHELL", "wget --spider -q http://127.0.0.1:8081/robots.txt || [ $$? -eq 8 ]"]
            interval: 1m
            timeout: 5s
            retries: 3
        deploy:
            resources:
                limits: {cpus: '0.5', memory: 256M}
EOF
}

append_wikiless() {
	local dockerfile=""
	local redis_url="redis://127.0.0.1:6379"

	if ! should_deploy "wikiless"; then
		return 0
	fi
	dockerfile=$(detect_dockerfile "${SRC_DIR}/wikiless" || echo "Dockerfile")

	cat >>"${COMPOSE_FILE}" <<EOF
    wikiless:
        pull_policy: build
        build:
            context: "${SRC_DIR}/wikiless"
            dockerfile: ${dockerfile}
        image: selfhost/wikiless:latest
        container_name: ${CONTAINER_PREFIX}wikiless
EOF

	cat >>"${COMPOSE_FILE}" <<EOF
        network_mode: "container:${CONTAINER_PREFIX}gluetun"
EOF

	cat >>"${COMPOSE_FILE}" <<EOF
        environment:
            - "DOMAIN=${LAN_IP}:${PORT_WIKILESS}"
            - "NONSSL_PORT=${PORT_INT_WIKILESS}"
            - "REDIS_URL=${redis_url}"
        healthcheck:
            test: ["CMD", "/nodejs/bin/node", "-e", "require('http').get('http://127.0.0.1:8180', (r) => {if (r.statusCode !== 200) process.exit(1);}).on('error', () => process.exit(1));"]
            interval: 30s
            timeout: 10s
            retries: 3
        depends_on:
            wikiless_redis: {condition: service_healthy}
            gluetun: {condition: service_healthy}
        restart: always
        deploy:
            resources:
                limits: {cpus: '0.5', memory: 256M}

    wikiless_redis:
        image: redis:7-alpine
        container_name: ${CONTAINER_PREFIX}wikiless_redis
        labels:
            - "casaos.skip=true"
EOF

	cat >>"${COMPOSE_FILE}" <<EOF
        network_mode: "container:${CONTAINER_PREFIX}gluetun"
        depends_on:
            gluetun: {condition: service_healthy}
EOF

	cat >>"${COMPOSE_FILE}" <<EOF
        volumes: ["${DATA_DIR}/redis:/data"]
        healthcheck:
            test: ["CMD", "redis-cli", "ping"]
            interval: 10s
            timeout: 5s
            retries: 5
        restart: always
        deploy:
            resources:
                limits: {cpus: '0.3', memory: 128M}
EOF
}

append_invidious() {
	local companion_url="http://127.0.0.1:8282/companion"

	if ! should_deploy "invidious"; then
		return 0
	fi

	cat >>"${COMPOSE_FILE}" <<EOF
    invidious:
        image: quay.io/invidious/invidious:latest
        container_name: ${CONTAINER_PREFIX}invidious
        network_mode: "container:${CONTAINER_PREFIX}gluetun"
        environment:
            INVIDIOUS_CONFIG: |
                db:
                    dbname: invidious
                    user: kemal
                    password: ${INVIDIOUS_DB_PASS_COMPOSE}
                    host: 172.${FOUND_OCTET}.0.240
                    port: 5432
                check_tables: true
                invidious_companion:
                - private_url: "${companion_url}"
                invidious_companion_key: "${IV_COMPANION}"
                hmac_key: "${IV_HMAC}"
        healthcheck:
            test: ["CMD-SHELL", "wget -nv --tries=1 --spider http://127.0.0.1:3000/api/v1/stats || [ \$\$? -eq 8 ]"]
            interval: 30s
            timeout: 5s
            retries: 2
        logging:
            options:
                max-size: "1G"
                max-file: "4"
        depends_on:
            invidious-db: {condition: service_healthy}
            gluetun: {condition: service_healthy}
        restart: always
        deploy:
            resources:
                limits: {cpus: '1.5', memory: 1024M}

    invidious-db:
        image: postgres:14
        container_name: ${CONTAINER_PREFIX}invidious-db
        labels:
            - "casaos.skip=true"
        networks:
            frontend:
                ipv4_address: 172.${FOUND_OCTET}.0.240
        environment:
            - "POSTGRES_DB=invidious"
            - "POSTGRES_USER=kemal"
            - "POSTGRES_PASSWORD=${INVIDIOUS_DB_PASS_COMPOSE}"
        volumes:
            - ${DATA_DIR}/postgres:/var/lib/postgresql/data
            - ${SRC_DIR}/invidious/config/sql:/config/sql:ro
            - ${SRC_DIR}/invidious/docker/init-invidious-db.sh:/docker-entrypoint-initdb.d/init-invidious-db.sh:ro
        healthcheck: {test: ["CMD-SHELL", "pg_isready -d invidious -U kemal"], interval: 10s, timeout: 5s, retries: 15}

    companion:
        container_name: ${CONTAINER_PREFIX}companion
        image: quay.io/invidious/invidious-companion:latest
        labels:
            - "casaos.skip=true"
        network_mode: "container:${CONTAINER_PREFIX}gluetun"
        depends_on:
            gluetun: {condition: service_healthy}
        environment:
            - "SERVER_SECRET_KEY=${IV_COMPANION}"
            - "PORT=8282"
        restart: always
        logging:
            options:
                max-size: "1G"
                max-file: "4"
        cap_drop:
            - ALL
        read_only: true
        volumes:
            - ${DATA_DIR}/companion:/var/tmp/youtubei.js:rw
        security_opt:
            - no-new-privileges:true
        healthcheck:
            test: ["NONE"]
        deploy:
            resources:
                limits: {cpus: '0.3', memory: 512M}
EOF
}

append_rimgo() {
	if ! should_deploy "rimgo"; then
		return 0
	fi
	cat >>"${COMPOSE_FILE}" <<EOF
    rimgo:
        image: codeberg.org/rimgo/rimgo:latest
        container_name: ${CONTAINER_PREFIX}rimgo
EOF

	cat >>"${COMPOSE_FILE}" <<EOF
        network_mode: "container:${CONTAINER_PREFIX}gluetun"
EOF

	cat >>"${COMPOSE_FILE}" <<EOF
        environment:
            - "IMGUR_CLIENT_ID=${RIMGO_IMGUR_CLIENT_ID:-546c25a59c58ad7}"
            - "ADDRESS=0.0.0.0"
            - "PORT=${PORT_INT_RIMGO}"
            - "PRIVACY_NOT_COLLECTED=true"
        healthcheck:
            test: ["NONE"]
        depends_on: {gluetun: {condition: service_healthy}}
        restart: always
        deploy:
            resources:
                limits: {cpus: '0.5', memory: 256M}
EOF
}

append_breezewiki() {
	local bw_origin="fandom.com"

	if ! should_deploy "breezewiki"; then
		return 0
	fi
	if [[ -f "${CONFIG_DIR}/breezewiki/breezewiki.ini" ]]; then
		bw_origin=$(grep "^canonical_origin" "${CONFIG_DIR}/breezewiki/breezewiki.ini" | cut -d'=' -f2 | tr -d ' ' || echo "fandom.com")
	fi

	cat >>"${COMPOSE_FILE}" <<EOF
    breezewiki:
        image: quay.io/pussthecatorg/breezewiki:latest
        container_name: ${CONTAINER_PREFIX}breezewiki
EOF

	cat >>"${COMPOSE_FILE}" <<EOF
        network_mode: "container:${CONTAINER_PREFIX}gluetun"
EOF

	cat >>"${COMPOSE_FILE}" <<EOF
        environment:
            - "PORT=10416"
            - "bw_canonical_origin=${bw_origin}"
        healthcheck:
            test: ["CMD-SHELL", "curl -f http://localhost:10416/ || exit 1"]
            interval: 60s
            timeout: 20s
            retries: 5
        depends_on: {gluetun: {condition: service_healthy}}
        restart: always
        deploy:
            resources:
                limits: {cpus: '0.5', memory: 512M}
EOF
}

append_anonymousoverflow() {
	if ! should_deploy "anonymousoverflow"; then
		return 0
	fi
	cat >>"${COMPOSE_FILE}" <<EOF
    anonymousoverflow:
        image: ghcr.io/httpjamesm/anonymousoverflow:release
        container_name: ${CONTAINER_PREFIX}anonymousoverflow
EOF

	cat >>"${COMPOSE_FILE}" <<EOF
        network_mode: "container:${CONTAINER_PREFIX}gluetun"
EOF

	cat >>"${COMPOSE_FILE}" <<EOF
        env_file: ["${ENV_DIR}/anonymousoverflow.env"]
        environment:
            - "PORT=${PORT_INT_ANONYMOUS}"
        healthcheck:
            test: ["NONE"]
        depends_on: {gluetun: {condition: service_healthy}}
        restart: always
        deploy:
            resources:
                limits: {cpus: '0.5', memory: 256M}
EOF
}

append_scribe() {
	local dockerfile=""

	if ! should_deploy "scribe"; then
		return 0
	fi
	dockerfile=$(detect_dockerfile "${SRC_DIR}/scribe" || echo "Dockerfile")
	cat >>"${COMPOSE_FILE}" <<EOF
    scribe:
        pull_policy: build
        build:
            context: "${SRC_DIR}/scribe"
            dockerfile: ${dockerfile}
        image: selfhost/scribe:${SCRIBE_IMAGE_TAG:-latest}
        container_name: ${CONTAINER_PREFIX}scribe
EOF

	cat >>"${COMPOSE_FILE}" <<EOF
        network_mode: "container:${CONTAINER_PREFIX}gluetun"
EOF

	cat >>"${COMPOSE_FILE}" <<EOF
        env_file: ["${ENV_DIR}/scribe.env"]
        healthcheck:
            test: ["CMD-SHELL", "wget --spider -q http://127.0.0.1:8280/ || [ \$\$? -eq 8 ]"]
            interval: 1m
            timeout: 5s
            retries: 3
        depends_on: {gluetun: {condition: service_healthy}}
        restart: always
        deploy:
            resources:
                limits: {cpus: '0.5', memory: 256M}
EOF
}

append_vert() {
	if ! should_deploy "vert"; then
		return 0
	fi
	cat >>"${COMPOSE_FILE}" <<EOF
    vertd:
        container_name: ${CONTAINER_PREFIX}vertd
        image: ghcr.io/vert-sh/vertd:latest
        networks: [frontend]
        ports: ["${LAN_IP}:${PORT_VERTD}:${PORT_INT_VERTD}"]
        healthcheck:
            test: ["CMD", "curl", "-f", "http://127.0.0.1:24153/api/version"]
            interval: 30s
            timeout: 5s
            retries: 3
        labels:
            - "casaos.skip=true"
        environment:
            - "PUBLIC_URL=http://${CONTAINER_PREFIX}vertd:${PORT_INT_VERTD}"
${VERTD_DEVICES}
        restart: always
        deploy:
            resources:
                limits: {cpus: '2.0', memory: 1024M}
$(if [[ -n "${VERTD_NVIDIA:-}" ]]; then echo "        reservations:
                    devices:
                        - driver: nvidia
                            count: all
                            capabilities: [gpu]"; fi)

    vert:
        container_name: ${CONTAINER_PREFIX}vert
        image: ghcr.io/vert-sh/vert:latest
        labels:
            - "casaos.skip=true"
        environment:
            - "PUB_HOSTNAME=${VERT_PUB_HOSTNAME}"
            - "PUB_PLAUSIBLE_URL="
            - "PUB_ENV=production"
            - "PUB_DISABLE_ALL_EXTERNAL_REQUESTS=true"
            - "PUB_DISABLE_FAILURE_BLOCKS=true"
            - "PUB_VERTD_URL=http://${CONTAINER_PREFIX}vertd:${PORT_INT_VERTD}"
            - "PUB_DONATION_URL="
            - "PUB_STRIPE_KEY="
            - "PUB_DISABLE_DONATIONS=true"
        networks: [frontend]
        ports: ["${LAN_IP}:${PORT_VERT}:${PORT_INT_VERT}"]
        healthcheck:
            test: ["CMD", "wget", "--spider", "-q", "http://127.0.0.1:80/"]
            interval: 30s
            timeout: 5s
            retries: 3
        depends_on:
            vertd: {condition: service_healthy}
        restart: unless-stopped
        deploy:
            resources:
                limits: {cpus: '0.5', memory: 256M}
EOF
}

append_cobalt() {
	if ! should_deploy "cobalt"; then
		return 0
	fi
	cat >>"${COMPOSE_FILE}" <<EOF
    cobalt:
        image: ghcr.io/imputnet/cobalt:${COBALT_IMAGE_TAG:-latest}
        container_name: ${CONTAINER_PREFIX}cobalt
        init: true
        read_only: true
EOF

	cat >>"${COMPOSE_FILE}" <<EOF
        network_mode: "container:${CONTAINER_PREFIX}gluetun"
EOF

	cat >>"${COMPOSE_FILE}" <<EOF
        environment:
            - "API_URL=http://${LAN_IP}:${PORT_COBALT_API}"
            - "API_PORT=${PORT_INT_COBALT_API}"
        depends_on:
            gluetun: {condition: service_healthy}
        restart: unless-stopped
        deploy:
            resources:
                limits: {cpus: '2.0', memory: 2G}
EOF
}

append_cobalt_web() {
	if ! should_deploy "cobalt-web"; then
		return 0
	fi
	local dockerfile="web/Dockerfile"
	cat >>"${COMPOSE_FILE}" <<EOF
    cobalt-web:
        pull_policy: build
        build:
            context: ${SRC_DIR}/cobalt
            dockerfile: ${dockerfile}
            args:
                - WEB_DEFAULT_API=http://${LAN_IP}:${PORT_COBALT_API}
        image: selfhost/cobalt-web:${COBALT_WEB_IMAGE_TAG:-latest}
        container_name: ${CONTAINER_PREFIX}cobalt-web
EOF

	cat >>"${COMPOSE_FILE}" <<EOF
        network_mode: "container:${CONTAINER_PREFIX}gluetun"
EOF

	cat >>"${COMPOSE_FILE}" <<EOF
        depends_on:
            gluetun: {condition: service_healthy}
            cobalt: {condition: service_started}
        restart: unless-stopped
        deploy:
            resources:
                limits: {cpus: '0.5', memory: 512M}
EOF
}

append_searxng() {
	if ! should_deploy "searxng"; then
		return 0
	fi
	cat >>"${COMPOSE_FILE}" <<EOF
    searxng:
        image: searxng/searxng:${SEARXNG_IMAGE_TAG:-latest}
        container_name: ${CONTAINER_PREFIX}searxng
EOF

	cat >>"${COMPOSE_FILE}" <<EOF
        network_mode: "container:${CONTAINER_PREFIX}gluetun"
EOF

	cat >>"${COMPOSE_FILE}" <<EOF
        volumes:
            - ${CONFIG_DIR}/searxng:/etc/searxng
            - ${DATA_DIR}/searxng-cache:/var/cache/searxng
        environment:
            - "SEARXNG_SECRET=${SEARXNG_SECRET}"
            - "SEARXNG_BASE_URL=http://${LAN_IP}:${PORT_SEARXNG}/"
        healthcheck:
            test: ["CMD-SHELL", "echo -n | nc 127.0.0.1 8080 || exit 1"]
            interval: 30s
            timeout: 5s
            retries: 3
        depends_on:
            searxng-redis: {condition: service_healthy}
            gluetun: {condition: service_healthy}
        restart: unless-stopped
        deploy:
            resources:
                limits: {cpus: '1.0', memory: 512M}

    searxng-redis:
        image: redis:7-alpine
        container_name: ${CONTAINER_PREFIX}searxng-redis
        networks: [frontend]
        command: redis-server --save "" --appendonly no
        healthcheck:
            test: ["CMD", "redis-cli", "ping"]
            interval: 10s
            timeout: 5s
            retries: 5
        restart: unless-stopped
        deploy:
            resources:
                limits: {cpus: '0.3', memory: 128M}
EOF
}

append_immich() {
	if ! should_deploy "immich"; then
		return 0
	fi
	local db_host="172.${FOUND_OCTET}.0.241"
	local redis_host="172.${FOUND_OCTET}.0.242"
	local ml_url="http://127.0.0.1:3003"

	cat >>"${COMPOSE_FILE}" <<EOF
    immich-server:
        image: ghcr.io/immich-app/immich-server:${IMMICH_IMAGE_TAG:-release}
        container_name: ${CONTAINER_PREFIX}immich-server

EOF

	cat >>"${COMPOSE_FILE}" <<EOF
        network_mode: "container:${CONTAINER_PREFIX}gluetun"
EOF

	cat >>"${COMPOSE_FILE}" <<EOF
        volumes:
            - ${DATA_DIR}/immich:/data
            - /etc/localtime:/etc/localtime:ro
        environment:
            - "IMMICH_HOST=0.0.0.0"
            - "IMMICH_PORT=2283"
            - "DB_HOSTNAME=${db_host}"
            - "DB_USERNAME=immich"
            - "DB_PASSWORD=${IMMICH_DB_PASS_COMPOSE}"
            - "DB_DATABASE_NAME=immich"
            - "REDIS_HOSTNAME=${redis_host}"
            - "IMMICH_MACHINE_LEARNING_URL=${ml_url}"
        healthcheck:
            test: ["CMD", "curl", "-f", "http://localhost:2283/api/server/ping"]
            interval: 60s
            timeout: 20s
            retries: 5
        depends_on:
            immich-db: {condition: service_healthy}
            immich-redis: {condition: service_healthy}
            gluetun: {condition: service_healthy}
        restart: always
        deploy:
            resources:
                limits: {cpus: '1.5', memory: 3072M}

    immich-db:
        image: ${IMMICH_POSTGRES_IMAGE:-ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0}
        container_name: ${CONTAINER_PREFIX}immich-db
        networks:
            frontend:
                ipv4_address: 172.${FOUND_OCTET}.0.241
        environment:
            - "POSTGRES_USER=immich"
            - "POSTGRES_PASSWORD=${IMMICH_DB_PASS_COMPOSE}"
            - "POSTGRES_DB=immich"
            - "POSTGRES_INITDB_ARGS=--data-checksums"
        volumes:
            - ${DATA_DIR}/immich-db:/var/lib/postgresql/data
        shm_size: 512mb
        healthcheck:
            test: ["CMD-SHELL", "pg_isready -d immich -U immich"]
            interval: 10s
            timeout: 5s
            retries: 15
        restart: always
        deploy:
            resources:
                limits: {cpus: '1.0', memory: 1024M}

    immich-redis:
        image: ${IMMICH_VALKEY_IMAGE:-docker.io/valkey/valkey:9}
        container_name: ${CONTAINER_PREFIX}immich-redis
        networks:
            frontend:
                ipv4_address: 172.${FOUND_OCTET}.0.242
        healthcheck:
            test: ["CMD", "redis-cli", "ping"]
            interval: 10s
            timeout: 5s
            retries: 15
        restart: always
        deploy:
            resources:
                limits: {cpus: '0.5', memory: 256M}

    immich-machine-learning:
        image: ghcr.io/immich-app/immich-machine-learning:${IMMICH_IMAGE_TAG:-release}
        container_name: ${CONTAINER_PREFIX}immich-ml
EOF

	cat >>"${COMPOSE_FILE}" <<EOF
        network_mode: "container:${CONTAINER_PREFIX}gluetun"
EOF

	cat >>"${COMPOSE_FILE}" <<EOF
        depends_on:
            gluetun: {condition: service_healthy}
        volumes:
            - ${DATA_DIR}/immich-ml-cache:/cache
        restart: always
        deploy:
            resources:
                limits: {cpus: '2.0', memory: 2048M}
EOF
}

append_watchtower() {
	if ! should_deploy "watchtower"; then
		return 0
	fi
	cat >>"${COMPOSE_FILE}" <<EOF
    watchtower:
        image: containrrr/watchtower:latest
        container_name: ${CONTAINER_PREFIX}watchtower
        volumes:
            - /var/run/docker.sock:/var/run/docker.sock
        networks:
            - mgmt
        environment:
            - "WATCHTOWER_CLEANUP=true"
            - "WATCHTOWER_POLL_INTERVAL=3600"
            - "WATCHTOWER_NOTIFICATIONS=shoutrrr"
            - "WATCHTOWER_NOTIFICATION_URL=generic+http://hub-api:55555/watchtower?token=${HUB_API_KEY_COMPOSE}"
        restart: unless-stopped
        deploy:
            resources:
                limits: {cpus: '0.2', memory: 128M}
EOF
}

generate_compose() {
	log_info "Generating Docker Compose Configuration..."

	# Set defaults for VERT variables
	local VERTD_PUB_URL="${VERTD_PUB_URL:-http://$LAN_IP:$PORT_VERTD}"
	local VERT_PUB_HOSTNAME="${VERT_PUB_HOSTNAME:-$LAN_IP}"
	local VERTD_DEVICES="${VERTD_DEVICES:-}"

	# Prepare escaped passwords for docker-compose (v2 requires $$ for literal $)
	local ADMIN_PASS_COMPOSE="${ADMIN_PASS_RAW//$/$$}"
	local VPN_PASS_COMPOSE="${VPN_PASS_RAW//$/$$}"
	local HUB_API_KEY_COMPOSE="${HUB_API_KEY//$/$$}"
	local PORTAINER_PASS_COMPOSE="${PORTAINER_PASS_RAW//$/$$}"
	local AGH_PASS_COMPOSE="${AGH_PASS_RAW//$/$$}"
	local INVIDIOUS_DB_PASS_COMPOSE="${INVIDIOUS_DB_PASSWORD//$/$$}"
	local IMMICH_DB_PASS_COMPOSE="${IMMICH_DB_PASSWORD//$/$$}"
	local WG_HASH_COMPOSE="${WG_HASH_CLEAN//$/$$}"
	local PORTAINER_HASH_COMPOSE="${PORTAINER_PASS_HASH//$/$$}"

	# Ensure required directories exist
	mkdir -p "${BASE_DIR}" "${SRC_DIR}" "${ENV_DIR}" "${CONFIG_DIR}" "${DATA_DIR}"

	# Header
	cat >"${COMPOSE_FILE}" <<EOF
name: ${APP_NAME}
networks:
    frontend:
        driver: bridge
        ipam:
            config:
                - subnet: ${DOCKER_SUBNET}
    mgmt:
        internal: true
        driver: bridge

services:
    docker-proxy:
        image: tecnativa/docker-socket-proxy:latest
        container_name: ${CONTAINER_PREFIX}docker-proxy
        privileged: false
        environment:
            - CONTAINERS=1
            - IMAGES=1
            - NETWORKS=1
            - VOLUMES=1
            - SERVICES=1
            - TASKS=1
            - INFO=1
            - VERSION=1
            - EVENTS=1
            - PING=1
            - SYSTEM=1
            - POST=1
            - BUILD=0
            - EXEC=1
            - LOGS=1
        volumes:
            - "/var/run/docker.sock:/var/run/docker.sock:ro"
        networks: [mgmt]
        restart: unless-stopped
        deploy:
            resources:
                limits: {cpus: '0.2', memory: 64M}

EOF

	# Core Infrastructure
	append_hub_api
	append_gluetun
	append_adguard
	append_unbound
	append_wg_easy
	append_dashboard
	append_portainer

	# Privacy Frontends
	append_redlib
	append_wikiless
	append_invidious
	append_rimgo
	append_breezewiki
	append_anonymousoverflow
	append_scribe

	# Utilities & Others
	append_memos
	append_odido_booster
	append_vert
	append_cobalt
	append_cobalt_web
	append_searxng
	append_immich
	append_watchtower

	# CasaOS Metadata
	cat >>"${COMPOSE_FILE}" <<EOF
x-casaos:
    architectures:
        - amd64
    main: dashboard
    author: Lyceris-chan
    category: Network
    scheme: http
    hostname: ${LAN_IP}
    index: /
    port_map: "${PORT_DASHBOARD_WEB}"
    title:
        en_us: Privacy Hub
    tagline:
        en_us: Stop being the product. Own your data with VPN, DNS filtering, and private frontends.
    description:
        en_us: |
            A comprehensive self-hosted privacy stack for people who want to own their data
            instead of renting a false sense of security. Includes WireGuard VPN access,
            recursive DNS with AdGuard filtering, and VPN-isolated privacy frontends
            (Invidious, Redlib, etc.) that reduce tracking and prevent home IP exposure.
    icon: http://${LAN_IP}:${PORT_DASHBOARD_WEB}/assets/icon.svg
EOF
}
