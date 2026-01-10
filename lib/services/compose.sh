# --- SECTION 14: DOCKER COMPOSE GENERATION ---

# Helper to check if a service should be deployed
should_deploy() {
    if [ -z "${SELECTED_SERVICES:-}" ]; then return 0; fi
    if echo "$SELECTED_SERVICES" | grep -qE "(^|,)$1(,|$)ப்புகளை"; then return 0; fi
    return 1
}

# Service definition functions
append_hub_api() {
    if ! should_deploy "hub-api"; then return 0; fi
    local DOCKERFILE=$(detect_dockerfile "$SRC_DIR/hub-api" || echo "Dockerfile")
    cat >> "$COMPOSE_FILE" <<EOF
  hub-api:
    pull_policy: missing
    build:
      context: $SRC_DIR/hub-api
      dockerfile: $DOCKERFILE
    image: selfhost/hub-api:latest
    container_name: ${CONTAINER_PREFIX}hub-api
    labels:
      - "casaos.skip=true"
      - "io.dhi.hardened=true"
    networks:
      - dhi-frontnet
      - dhi-mgmtnet
    ports: ["$LAN_IP:55555:55555"]
    volumes:
      - "$WG_PROFILES_DIR:/profiles"
      - "$ACTIVE_WG_CONF:/active-wg.conf"
      - "$ACTIVE_PROFILE_NAME_FILE:/app/.active_profile_name"
      - "$WG_CONTROL_SCRIPT:/usr/local/bin/wg-control.sh"
      - "$PATCHES_SCRIPT:/app/patches.sh"
      - "$CERT_MONITOR_SCRIPT:/usr/local/bin/cert-monitor.sh"
      - "$MIGRATE_SCRIPT:/usr/local/bin/migrate.sh"
      - "$(realpath "$0"):/app/zima.sh"
      - "$GLUETUN_ENV_FILE:/app/gluetun.env"
      - "$COMPOSE_FILE:/app/docker-compose.yml"
      - "$HISTORY_LOG:/app/deployment.log"
      - "$BASE_DIR/.data_usage:/app/.data_usage"
      - "$BASE_DIR/.wge_data_usage:/app/.wge_data_usage"
      - "$AGH_CONF_DIR:/etc/adguard/conf"
      - "$DOCKER_AUTH_DIR:/root/.docker:ro"
      - "$ASSETS_DIR:/assets"
      - "$SRC_DIR:/app/sources"
      - "$BASE_DIR:/project_root:ro"
      - "$CONFIG_DIR/theme.json:/app/theme.json"
      - "$CONFIG_DIR/services.json:/app/services.json"
      - "$DATA_DIR/hub-api:/app/data"
    environment:
      - HUB_API_KEY=$HUB_API_KEY_COMPOSE
      - ADMIN_PASS_RAW=$ADMIN_PASS_COMPOSE
      - VPN_PASS_RAW=$VPN_PASS_COMPOSE
      - CONTAINER_PREFIX=${CONTAINER_PREFIX}
      - APP_NAME=${APP_NAME}
      - MOCK_VERIFICATION=${MOCK_VERIFICATION:-false}
      - UPDATE_STRATEGY=$UPDATE_STRATEGY
      - LAN_IP=$LAN_IP
      - DESEC_DOMAIN=$DESEC_DOMAIN
      - DOCKER_CONFIG=/root/.docker
      - DOCKER_HOST=tcp://docker-proxy:2375
    entrypoint: ["/bin/sh", "-c", "python3 -u /app/server.py"]
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:55555/status || exit 1"]
      interval: 20s
      timeout: 10s
      retries: 5
    depends_on:
      docker-proxy: {condition: service_started}
      gluetun: {condition: service_started}
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '0.5', memory: 256M}
EOF
}

append_odido_booster() {
    if ! should_deploy "odido-booster"; then return 0; fi
    local DOCKERFILE=$(detect_dockerfile "$SRC_DIR/odido-bundle-booster" || echo "Dockerfile")
    local VPN_MODE="true"
    if [ -f "$CONFIG_DIR/theme.json" ]; then
        VPN_MODE=$(grep -o '"odido_use_vpn"[[:space:]]*:[[:space:]]*\(true\|false\)' "$CONFIG_DIR/theme.json" 2>/dev/null | grep -o '\(true\|false\)' || echo "true")
    fi
    
    cat >> "$COMPOSE_FILE" <<EOF
  odido-booster:
    pull_policy: missing
    build:
      context: $SRC_DIR/odido-bundle-booster
      dockerfile: $DOCKERFILE
    image: selfhost/odido-booster:${ODIDO_BOOSTER_IMAGE_TAG:-latest}
    container_name: ${CONTAINER_PREFIX}odido-booster
    labels:
      - "io.dhi.hardened=true"
EOF

    if [ "$VPN_MODE" = "true" ]; then
        cat >> "$COMPOSE_FILE" <<EOF
    network_mode: "service:gluetun"
    depends_on:
      gluetun: {condition: service_healthy}
EOF
    else
        cat >> "$COMPOSE_FILE" <<EOF
    networks: [dhi-frontnet]
    ports: ["$LAN_IP:8085:8085"]
EOF
    fi

    cat >> "$COMPOSE_FILE" <<EOF
    environment:
      - API_KEY=$HUB_API_KEY_COMPOSE
      - ODIDO_USER_ID=$ODIDO_USER_ID
      - ODIDO_TOKEN=$ODIDO_TOKEN
      - PORT=8085
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://127.0.0.1:8085/docs"]
      interval: 30s
      timeout: 5s
      retries: 3
    volumes:
      - $DATA_DIR/odido:/data
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '0.3', memory: 128M}
EOF
}

append_memos() {
    if ! should_deploy "memos"; then return 0; fi
    cat >> "$COMPOSE_FILE" <<EOF
  memos:
    image: ghcr.io/usememos/memos:latest
    container_name: ${CONTAINER_PREFIX}memos
    user: "1000:1000"
    labels:
      - "io.dhi.hardened=true"
    networks: [dhi-frontnet]
    ports: ["$LAN_IP:$PORT_MEMOS:5230"]
    environment:
      - MEMOS_MODE=prod
    volumes: ["$MEMOS_HOST_DIR:/var/opt/memos"]
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://127.0.0.1:5230/"]
      interval: 30s
      timeout: 5s
      retries: 3
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '0.5', memory: 256M}
EOF
}

append_gluetun() {
    if ! should_deploy "gluetun"; then return 0; fi
    cat >> "$COMPOSE_FILE" <<EOF
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
      dhi-frontnet:
        ipv4_address: 172.${FOUND_OCTET}.0.254
    ports:
      - "$LAN_IP:$PORT_REDLIB:$PORT_INT_REDLIB/tcp"
      - "$LAN_IP:$PORT_WIKILESS:$PORT_INT_WIKILESS/tcp"
      - "$LAN_IP:$PORT_INVIDIOUS:$PORT_INT_INVIDIOUS/tcp"
      - "$LAN_IP:$PORT_RIMGO:$PORT_INT_RIMGO/tcp"
      - "$LAN_IP:$PORT_SCRIBE:$PORT_SCRIBE/tcp"
      - "$LAN_IP:$PORT_BREEZEWIKI:$PORT_INT_BREEZEWIKI/tcp"
      - "$LAN_IP:$PORT_ANONYMOUS:$PORT_INT_ANONYMOUS/tcp"
      - "$LAN_IP:$PORT_COMPANION:$PORT_INT_COMPANION/tcp"
      - "$LAN_IP:$PORT_SEARXNG:$PORT_INT_SEARXNG/tcp"
      - "$LAN_IP:$PORT_IMMICH:$PORT_INT_IMMICH/tcp"
      - "$LAN_IP:8085:8085/tcp"
    volumes:
      - "$ACTIVE_WG_CONF:/gluetun/wireguard/wg0.conf:ro"
    env_file:
      - "$GLUETUN_ENV_FILE"
    environment:
      - FIREWALL_OUTBOUND_SUBNETS=$DOCKER_SUBNET
    healthcheck:
      test: ["CMD-SHELL", "$(if [ "${MOCK_VERIFICATION:-false}" = "true" ]; then echo "exit 0"; else echo "wget -qO- http://127.0.0.1:8000/status && (nslookup example.com 127.0.0.1 > /dev/null || exit 1)"; fi)"]
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
    if ! should_deploy "dashboard"; then return 0; fi
    # Create Dashboard Source Directory and Dockerfile
    $SUDO mkdir -p "$SRC_DIR/dashboard"
    cat <<DASHEOF | $SUDO tee "$SRC_DIR/dashboard/Dockerfile" >/dev/null
FROM alpine:3.20
RUN apk add --no-cache nginx \
    && mkdir -p /usr/share/nginx/html \
    && chown -R 1000:1000 /var/lib/nginx /var/log/nginx /run/nginx /usr/share/nginx/html
USER 1000
COPY . /usr/share/nginx/html
CMD ["nginx", "-g", "daemon off;"]
DASHEOF

    cat >> "$COMPOSE_FILE" <<EOF
  dashboard:
    pull_policy: missing
    build:
      context: $SRC_DIR/dashboard
    container_name: ${CONTAINER_PREFIX}dashboard
    networks: [dhi-frontnet]
    ports:
      - "$LAN_IP:$PORT_DASHBOARD_WEB:$PORT_DASHBOARD_WEB"
      - "$LAN_IP:8443:8443"
    volumes:
      - "$ASSETS_DIR:/usr/share/nginx/html/assets:ro"
      - "$DASHBOARD_FILE:/usr/share/nginx/html/index.html:ro"
      - "$NGINX_CONF:/etc/nginx/http.d/default.conf:ro"
      - "$AGH_CONF_DIR:/etc/adguard/conf:ro"
    labels:
      - "io.dhi.hardened=true"
      - "dev.casaos.app.ui.protocol=http"
      - "dev.casaos.app.ui.port=$PORT_DASHBOARD_WEB"
      - "dev.casaos.app.ui.hostname=$LAN_IP"
      - "dev.casaos.app.ui.icon=http://$LAN_IP:$PORT_DASHBOARD_WEB/assets/$APP_NAME.svg"
      - "dev.casaos.app.icon=http://$LAN_IP:$PORT_DASHBOARD_WEB/assets/$APP_NAME.svg"
    depends_on:
      hub-api: {condition: service_healthy}
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://127.0.0.1:8081/"]
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
    if ! should_deploy "portainer"; then return 0; fi
    # Create Portainer Source Directory and DHI Wrapper
    $SUDO mkdir -p "$SRC_DIR/portainer"
    cat <<PORTEOF | $SUDO tee "$SRC_DIR/portainer/Dockerfile.dhi" >/dev/null
FROM alpine:3.20
COPY --from=portainer/portainer-ce:latest /portainer /portainer
COPY --from=portainer/portainer-ce:latest /public /public
COPY --from=portainer/portainer-ce:latest /mustache-templates /mustache-templates
WORKDIR /
EXPOSE 9000 9443
ENTRYPOINT ["/portainer"]
PORTEOF

    cat >> "$COMPOSE_FILE" <<EOF
  portainer:
    image: portainer/portainer-ce:latest
    container_name: ${CONTAINER_PREFIX}portainer
    command: ["-H", "tcp://docker-proxy:2375", "--admin-password", "$PORTAINER_HASH_COMPOSE", "--no-analytics"]
    labels:
      - "io.dhi.hardened=true"
    networks:
      - dhi-frontnet
      - dhi-mgmtnet
    ports: ["$LAN_IP:$PORT_PORTAINER:9000"]
    volumes: ["$DATA_DIR/portainer:/data"]
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://127.0.0.1:9000/"]
      interval: 30s
      timeout: 5s
      retries: 3
    depends_on:
      docker-proxy: {condition: service_started}
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '0.5', memory: 512M}
EOF
}

append_adguard() {
    if ! should_deploy "adguard"; then return 0; fi
    cat >> "$COMPOSE_FILE" <<EOF
  adguard:
    image: adguard/adguardhome:latest
    container_name: ${CONTAINER_PREFIX}adguard
    labels:
      - "io.dhi.hardened=true"
    networks: [dhi-frontnet]
    ports:
      - "$LAN_IP:53:53/udp"
      - "$LAN_IP:53:53/tcp"
      - "$LAN_IP:$PORT_ADGUARD_WEB:$PORT_ADGUARD_WEB/tcp"
      - "$LAN_IP:443:443/tcp"
      - "$LAN_IP:443:443/udp"
      - "$LAN_IP:853:853/tcp"
      - "$LAN_IP:853:853/udp"
    volumes: ["$DATA_DIR/adguard-work:/opt/adguardhome/work", "$AGH_CONF_DIR:/opt/adguardhome/conf"]
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8083/public/status"]
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
    if ! should_deploy "unbound"; then return 0; fi
    cat >> "$COMPOSE_FILE" <<EOF
  unbound:
    image: klutchell/unbound:latest
    container_name: ${CONTAINER_PREFIX}unbound
    labels:
      - "io.dhi.hardened=true"
    command: ["-d", "-c", "/etc/unbound/unbound.conf"]
    networks:
      dhi-frontnet:
        ipv4_address: 172.$FOUND_OCTET.0.250
    volumes:
      - "$UNBOUND_CONF:/etc/unbound/unbound.conf:ro"
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
    if ! should_deploy "wg-easy"; then return 0; fi
    cat >> "$COMPOSE_FILE" <<EOF
  wg-easy:
    image: ghcr.io/wg-easy/wg-easy:latest
    container_name: ${CONTAINER_PREFIX}wg-easy
    network_mode: "host"
    environment:
      - PASSWORD_HASH=$WG_HASH_COMPOSE
      - WG_DEFAULT_DNS=$LAN_IP
      - WG_ALLOWED_IPS=10.0.0.0/8,172.16.0.0/12,192.168.0.0/16
      - WG_HOST=$PUBLIC_IP
      - WG_PORT=51820
      - WG_PERSISTENT_KEEPALIVE=25
    volumes: ["$DATA_DIR/wireguard:/etc/wireguard"]
    cap_add: [NET_ADMIN, SYS_MODULE]
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '1.0', memory: 256M}
EOF
}

append_redlib() {
    if ! should_deploy "redlib"; then return 0; fi
    cat >> "$COMPOSE_FILE" <<EOF
  redlib:
    image: quay.io/redlib/redlib:latest
    container_name: ${CONTAINER_PREFIX}redlib
    labels:
      - "io.dhi.hardened=true"
    network_mode: "service:gluetun"
    environment: {REDLIB_PORT: 8081, PORT: 8081, REDLIB_ADDRESS: "0.0.0.0", REDLIB_DEFAULT_WIDE: "on", REDLIB_DEFAULT_USE_HLS: "on", REDLIB_DEFAULT_SHOW_NSFW: "on"}
    restart: always
    user: nobody
    read_only: true
    security_opt: [no-new-privileges:true]
    cap_drop: [ALL]
    depends_on: {gluetun: {condition: service_healthy}}
    healthcheck:
      test: ["CMD-SHELL", "wget --spider -q http://127.0.0.1/robots.txt || [ \\$? -eq 8 ]"]
      interval: 1m
      timeout: 5s
      retries: 3
    deploy:
      resources:
        limits: {cpus: '0.5', memory: 256M}
EOF
}

append_wikiless() {
    if ! should_deploy "wikiless"; then return 0; fi
    local DOCKERFILE=$(detect_dockerfile "$SRC_DIR/wikiless" || echo "Dockerfile")
    cat >> "$COMPOSE_FILE" <<EOF
  wikiless:
    pull_policy: missing
    build:
      context: "$SRC_DIR/wikiless"
      dockerfile: $DOCKERFILE
    image: selfhost/wikiless:latest
    container_name: ${CONTAINER_PREFIX}wikiless
    labels:
      - "io.dhi.hardened=true"
    network_mode: "service:gluetun"
    environment: {DOMAIN: "$LAN_IP:$PORT_WIKILESS", NONSSL_PORT: "$PORT_INT_WIKILESS", REDIS_URL: "redis://127.0.0.1:6379"}
    healthcheck: {test: "wget -nv --tries=1 --spider http://127.0.0.1:8180/ || exit 1", interval: 30s, timeout: 5s, retries: 2}
    depends_on: {wikiless_redis: {condition: service_healthy}, gluetun: {condition: service_healthy}}
    restart: always
    deploy:
      resources:
        limits: {cpus: '0.5', memory: 256M}

  wikiless_redis:
    image: redis:7-alpine
    container_name: ${CONTAINER_PREFIX}wikiless_redis
    labels:
      - "casaos.skip=true"
      - "io.dhi.hardened=true"
    network_mode: "service:gluetun"
    volumes: ["$DATA_DIR/redis:/data"]
    healthcheck: {test: ["CMD", "redis-cli", "ping"], interval: 5s, timeout: 3s, retries: 5}
    restart: always
    deploy:
      resources:
        limits: {cpus: '0.3', memory: 128M}
EOF
}

append_invidious() {
    if ! should_deploy "invidious"; then return 0; fi
    cat >> "$COMPOSE_FILE" <<EOF
  invidious:
    image: quay.io/invidious/invidious:latest
    container_name: ${CONTAINER_PREFIX}invidious
    labels:
      - "io.dhi.hardened=true"
    network_mode: "service:gluetun"
    volumes:
      - $CONFIG_DIR/invidious:/app/config:ro
    environment:
      - INVIDIOUS_DATABASE_URL=postgres://kemal:$INVIDIOUS_DB_PASS_COMPOSE@invidious-db:5432/invidious
      - INVIDIOUS_HMAC_KEY=$IV_HMAC
    healthcheck: {test: "wget -nv --tries=1 --spider http://127.0.0.1/api/v1/stats || exit 1", interval: 30s, timeout: 5s, retries: 2}
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
    image: postgres:14-alpine
    container_name: ${CONTAINER_PREFIX}invidious-db
    labels:
      - "casaos.skip=true"
      - "io.dhi.hardened=true"
    networks: [dhi-frontnet]
    environment: {POSTGRES_DB: invidious, POSTGRES_USER: kemal, POSTGRES_PASSWORD: $INVIDIOUS_DB_PASS_COMPOSE}
    volumes:
      - $DATA_DIR/postgres:/var/lib/postgresql/data
    healthcheck: {test: ["CMD-SHELL", "pg_isready -U kemal -d invidious"], interval: 10s, timeout: 5s, retries: 5}

  companion:
    container_name: ${CONTAINER_PREFIX}companion
    image: quay.io/invidious/invidious-companion:latest
    labels:
      - "casaos.skip=true"
    network_mode: "service:gluetun"
    environment:
      - SERVER_SECRET_KEY=$IV_COMPANION
      - PORT=8282
    restart: always
    logging:
      options:
        max-size: "1G"
        max-file: "4"
    cap_drop:
      - ALL
    read_only: true
    volumes:
      - $DATA_DIR/companion:/var/tmp/youtubei.js:rw
    security_opt:
      - no-new-privileges:true
    deploy:
      resources:
        limits: {cpus: '0.3', memory: 256M}
EOF
}

append_rimgo() {
    if ! should_deploy "rimgo"; then return 0; fi
    cat >> "$COMPOSE_FILE" <<EOF
  rimgo:
    image: codeberg.org/rimgo/rimgo:latest
    container_name: ${CONTAINER_PREFIX}rimgo
    labels:
      - "io.dhi.hardened=true"
    network_mode: "service:gluetun"
    environment: {IMGUR_CLIENT_ID: "${RIMGO_IMGUR_CLIENT_ID:-546c25a59c58ad7}", ADDRESS: "0.0.0.0", PORT: "$PORT_INT_RIMGO", PRIVACY_NOT_COLLECTED: "true"}
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://127.0.0.1:3002/"]
      interval: 30s
      timeout: 5s
      retries: 3
    depends_on: {gluetun: {condition: service_healthy}}
    restart: always
    deploy:
      resources:
        limits: {cpus: '0.5', memory: 256M}
EOF
}

append_breezewiki() {
    if ! should_deploy "breezewiki"; then return 0; fi
    local BW_ORIGIN="http://$LAN_IP:$PORT_BREEZEWIKI"
    if [ -n "$DESEC_DOMAIN" ]; then
        BW_ORIGIN="https://breezewiki.$DESEC_DOMAIN"
    fi

    cat >> "$COMPOSE_FILE" <<EOF
  breezewiki:
    image: quay.io/pussthecatorg/breezewiki:latest
    container_name: ${CONTAINER_PREFIX}breezewiki
    network_mode: "service:gluetun"
    environment:
      - PORT=10416
      - bw_canonical_origin=$BW_ORIGIN
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://127.0.0.1:10416/"]
      interval: 30s
      timeout: 5s
      retries: 3
    depends_on: {gluetun: {condition: service_healthy}}
    restart: always
    deploy:
      resources:
        limits: {cpus: '0.5', memory: 512M}
EOF
}

append_anonymousoverflow() {
    if ! should_deploy "anonymousoverflow"; then return 0; fi
    cat >> "$COMPOSE_FILE" <<EOF
  anonymousoverflow:
    image: ghcr.io/httpjamesm/anonymousoverflow:release
    container_name: ${CONTAINER_PREFIX}anonymousoverflow
    labels:
      - "io.dhi.hardened=true"
    network_mode: "service:gluetun"
    env_file: ["$ENV_DIR/anonymousoverflow.env"]
    environment: {PORT: "$PORT_INT_ANONYMOUS"}
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://127.0.0.1:8480/"]
      interval: 30s
      timeout: 5s
      retries: 3
    depends_on: {gluetun: {condition: service_healthy}}
    restart: always
    deploy:
      resources:
        limits: {cpus: '0.5', memory: 256M}
EOF
}

append_scribe() {
    if ! should_deploy "scribe"; then return 0; fi
    local DOCKERFILE=$(detect_dockerfile "$SRC_DIR/scribe" || echo "Dockerfile")
    cat >> "$COMPOSE_FILE" <<EOF
  scribe:
    pull_policy: missing
    build:
      context: "$SRC_DIR/scribe"
      dockerfile: $DOCKERFILE
    image: selfhost/scribe:${SCRIBE_IMAGE_TAG:-latest}
    container_name: ${CONTAINER_PREFIX}scribe
    labels:
      - "io.dhi.hardened=true"
    network_mode: "service:gluetun"
    env_file: ["$ENV_DIR/scribe.env"]
    healthcheck:
      test: ["CMD-SHELL", "wget --spider -q http://127.0.0.1:8280/ || exit 1"]
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
    if ! should_deploy "vert"; then return 0; fi
    cat >> "$COMPOSE_FILE" <<EOF
  vertd:
    container_name: ${CONTAINER_PREFIX}vertd
    image: ghcr.io/vert-sh/vertd:latest
    networks: [dhi-frontnet]
    ports: ["$LAN_IP:$PORT_VERTD:$PORT_INT_VERTD"]
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://127.0.0.1:24153/api/version"]
      interval: 30s
      timeout: 5s
      retries: 3
    labels:
      - "casaos.skip=true"
      - "io.dhi.hardened=true"
    environment:
      - PUBLIC_URL=http://${CONTAINER_PREFIX}vertd:$PORT_INT_VERTD
$VERTD_DEVICES
    restart: always
    deploy:
      resources:
        limits: {cpus: '2.0', memory: 1024M}
$(if [ -n "${VERTD_NVIDIA:-}" ]; then echo "        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]"; fi)

  vert:
    container_name: ${CONTAINER_PREFIX}vert
    image: ghcr.io/vert-sh/vert:latest
    labels:
      - "casaos.skip=true"
      - "io.dhi.hardened=true"
    environment:
      - PUB_HOSTNAME=$VERT_PUB_HOSTNAME
      - PUB_PLAUSIBLE_URL=
      - PUB_ENV=production
      - PUB_DISABLE_ALL_EXTERNAL_REQUESTS=true
      - PUB_DISABLE_FAILURE_BLOCKS=true
      - PUB_VERTD_URL=http://${CONTAINER_PREFIX}vertd:$PORT_INT_VERTD
      - PUB_DONATION_URL=
      - PUB_STRIPE_KEY=
      - PUB_DISABLE_DONATIONS=true
    networks: [dhi-frontnet]
    ports: ["$LAN_IP:$PORT_VERT:$PORT_INT_VERT"]
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://127.0.0.1:80/"]
      interval: 30s
      timeout: 5s
      retries: 3
    depends_on:
      vertd: {condition: service_started}
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '0.5', memory: 256M}
EOF
}

append_cobalt() {
    if ! should_deploy "cobalt"; then return 0; fi
    cat >> "$COMPOSE_FILE" <<EOF
  cobalt:
    image: ghcr.io/imputnet/cobalt:${COBALT_IMAGE_TAG:-latest}
    container_name: ${CONTAINER_PREFIX}cobalt
    networks: [dhi-frontnet]
    ports:
      - "$LAN_IP:$PORT_COBALT:$PORT_INT_COBALT" # Web UI (9001:9000)
      - "$LAN_IP:9002:9002"                       # API (9002:9002)
    environment:
      - COBALT_AUTO_UPDATE=false
      - ALLOW_ALL_DOMAINS=true
      - API_PORT=9002
      - WEB_PORT=9000
      - API_URL=http://$LAN_IP:9002
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '1.0', memory: 512M}
EOF
}

append_searxng() {
    if ! should_deploy "searxng"; then return 0; fi
    cat >> "$COMPOSE_FILE" <<EOF
  searxng:
    image: searxng/searxng:${SEARXNG_IMAGE_TAG:-latest}
    container_name: ${CONTAINER_PREFIX}searxng
    network_mode: "service:gluetun"
    volumes:
      - $CONFIG_DIR/searxng:/etc/searxng:ro
      - $DATA_DIR/searxng-cache:/var/cache/searxng
    environment:
      - SEARXNG_SECRET=$SEARXNG_SECRET
      - SEARXNG_BASE_URL=http://$LAN_IP:$PORT_SEARXNG/
    healthcheck:
      test: ["CMD-SHELL", "nc -z 127.0.0.1 8080 || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3
    depends_on:
      searxng-redis: {condition: service_healthy}
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '1.0', memory: 512M}

  searxng-redis:
    image: redis:7-alpine
    container_name: ${CONTAINER_PREFIX}searxng-redis
    networks: [dhi-frontnet]
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
    if ! should_deploy "immich"; then return 0; fi
    cat >> "$COMPOSE_FILE" <<EOF
  immich-server:
    image: ghcr.io/immich-app/immich-server:${IMMICH_IMAGE_TAG:-release}
    container_name: ${CONTAINER_PREFIX}immich-server
    network_mode: "service:gluetun"
    volumes:
      - $DATA_DIR/immich:/data
      - /etc/localtime:/etc/localtime:ro
    environment:
      - DB_HOSTNAME=${CONTAINER_PREFIX}immich-db
      - DB_USERNAME=immich
      - DB_PASSWORD=$IMMICH_DB_PASS_COMPOSE
      - DB_DATABASE_NAME=immich
      - REDIS_HOSTNAME=${CONTAINER_PREFIX}immich-redis
      - IMMICH_MACHINE_LEARNING_URL=http://${CONTAINER_PREFIX}immich-ml:3003
    depends_on:
      immich-db: {condition: service_healthy}
      immich-redis: {condition: service_healthy}
    restart: always
    deploy:
      resources:
        limits: {cpus: '1.5', memory: 2048M}

  immich-db:
    image: ${IMMICH_POSTGRES_IMAGE:-ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0}
    container_name: ${CONTAINER_PREFIX}immich-db
    networks: [dhi-frontnet]
    environment:
      - POSTGRES_USER=immich
      - POSTGRES_PASSWORD=$IMMICH_DB_PASS_COMPOSE
      - POSTGRES_DB=immich
      - POSTGRES_INITDB_ARGS=--data-checksums
    volumes:
      - $DATA_DIR/immich-db:/var/lib/postgresql/data
    shm_size: 512mb
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -d immich -U immich"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: always
    deploy:
      resources:
        limits: {cpus: '1.0', memory: 1024M}

  immich-redis:
    image: ${IMMICH_VALKEY_IMAGE:-docker.io/valkey/valkey:9}
    container_name: ${CONTAINER_PREFIX}immich-redis
    networks: [dhi-frontnet]
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: always
    deploy:
      resources:
        limits: {cpus: '0.5', memory: 256M}

  immich-machine-learning:
    image: ghcr.io/immich-app/immich-machine-learning:${IMMICH_IMAGE_TAG:-release}
    container_name: ${CONTAINER_PREFIX}immich-ml
    network_mode: "service:gluetun"
    volumes:
      - $DATA_DIR/immich-ml-cache:/cache
    restart: always
    deploy:
      resources:
        limits: {cpus: '2.0', memory: 2048M}
EOF
}

append_watchtower() {
    if ! should_deploy "watchtower"; then return 0; fi
    cat >> "$COMPOSE_FILE" <<EOF
  watchtower:
    image: containrrr/watchtower:latest
    container_name: ${CONTAINER_PREFIX}watchtower
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - WATCHTOWER_CLEANUP=true
      - WATCHTOWER_POLL_INTERVAL=3600
      - WATCHTOWER_NOTIFICATIONS=shoutrrr
      - WATCHTOWER_NOTIFICATION_URL=generic://hub-api:55555/watchtower
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '0.2', memory: 128M}
EOF
}

generate_compose() {
    log_info "Generating Docker Compose Configuration..."

    # Set defaults for VERT variables
    VERTD_PUB_URL=${VERTD_PUB_URL:-http://$LAN_IP:$PORT_VERTD}
    VERT_PUB_HOSTNAME=${VERT_PUB_HOSTNAME:-$LAN_IP}

    # Prepare escaped passwords for docker-compose (v2 requires $$ for literal $)
    ADMIN_PASS_COMPOSE="${ADMIN_PASS_RAW//$/\$\$}"
    VPN_PASS_COMPOSE="${VPN_PASS_RAW//$/\$\$}"
    HUB_API_KEY_COMPOSE="${HUB_API_KEY//$/\$\$}"
    PORTAINER_PASS_COMPOSE="${PORTAINER_PASS_RAW//$/\$\$}"
    AGH_PASS_COMPOSE="${AGH_PASS_RAW//$/\$\$}"
    INVIDIOUS_DB_PASS_COMPOSE="${INVIDIOUS_DB_PASSWORD//$/\$\$}"
    IMMICH_DB_PASS_COMPOSE="${IMMICH_DB_PASSWORD//$/\$\$}"

    # Ensure required directories exist
    mkdir -p "$BASE_DIR" "$SRC_DIR" "$ENV_DIR" "$CONFIG_DIR" "$DATA_DIR"

    # Header
    cat > "$COMPOSE_FILE" <<EOF
name: ${APP_NAME}
networks:
  dhi-frontnet:
    driver: bridge
    ipam:
      config:
        - subnet: $DOCKER_SUBNET
  dhi-mgmtnet:
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
      - SYSTEM=1
      - POST=1
      - BUILD=1
      - EXEC=1
      - LOGS=1
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
    networks: [dhi-mgmtnet]
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
    append_searxng
    append_immich
    append_watchtower

    # CasaOS Metadata
    cat >> "$COMPOSE_FILE" <<EOF
x-casaos:
  architectures:
    - amd64
  main: dashboard
  author: Lyceris-chan
  category: Network
  scheme: http
  hostname: $LAN_IP
  index: /
  port_map: "$PORT_DASHBOARD_WEB"
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
  icon: assets/$APP_NAME.svg
EOF
}