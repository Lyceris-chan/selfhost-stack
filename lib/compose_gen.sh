#!/usr/bin/env bash

# --- SECTION 14: DOCKER COMPOSE GENERATION ---

generate_compose() {
    log_info "Generating Docker Compose Configuration..."

    should_deploy() {
        if [ -z "$SELECTED_SERVICES" ]; then return 0; fi
        if echo "$SELECTED_SERVICES" | grep -q "$1"; then return 0; fi
        return 1
    }

    # Set defaults for VERT variables
    VERTD_PUB_URL=${VERTD_PUB_URL:-http://$LAN_IP:$PORT_VERTD}
    VERT_PUB_HOSTNAME=${VERT_PUB_HOSTNAME:-$LAN_IP}

    # Prepare escaped passwords for docker-compose healthchecks
    ADMIN_PASS_COMPOSE="${ADMIN_PASS_RAW//\$/\$\$}"

    # Ensure required directories exist
    mkdir -p "$BASE_DIR" "$SRC_DIR" "$ENV_DIR" "$CONFIG_DIR" "$DATA_DIR"

    cat > "$COMPOSE_FILE" <<EOF
name: ${APP_NAME}
networks:
  dhi-frontnet:
    driver: bridge
    ipam:
      config:
        - subnet: $DOCKER_SUBNET

services:
EOF

    if should_deploy "hub-api"; then
        HUB_API_DOCKERFILE=$(detect_dockerfile "$SRC_DIR/hub-api" || echo "Dockerfile")
    cat >> "$COMPOSE_FILE" <<EOF
  hub-api:
    pull_policy: build
    build:
      context: $SRC_DIR/hub-api
      dockerfile: $HUB_API_DOCKERFILE
    image: selfhost/hub-api:${HUB_API_IMAGE_TAG:-latest}
    container_name: ${CONTAINER_PREFIX}hub-api
    labels:
      - "casaos.skip=true"
      - "io.dhi.hardened=true"
    networks: [dhi-frontnet]
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock"
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
    environment:
      - HUB_API_KEY=$ODIDO_API_KEY
      - ADMIN_PASS_RAW=$ADMIN_PASS_RAW
      - VPN_PASS_RAW=$VPN_PASS_RAW
      - CONTAINER_PREFIX=${CONTAINER_PREFIX}
      - APP_NAME=${APP_NAME}
      - UPDATE_STRATEGY=$UPDATE_STRATEGY
      - DOCKER_CONFIG=/root/.docker
    entrypoint: ["/bin/sh", "-c", "mkdir -p /app && touch /app/deployment.log && touch /app/.data_usage && touch /app/.wge_data_usage && python3 -u /app/server.py"]
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:55555/status || exit 1"]
      interval: 20s
      timeout: 10s
      retries: 5
    depends_on:
      gluetun: {condition: service_healthy}
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '0.5', memory: 256M}
EOF
    fi

    if should_deploy "odido-booster"; then
        ODIDO_DOCKERFILE=$(detect_dockerfile "$SRC_DIR/odido-bundle-booster" || echo "Dockerfile")
    cat >> "$COMPOSE_FILE" <<EOF
  odido-booster:
    pull_policy: build
    build:
      context: $SRC_DIR/odido-bundle-booster
      dockerfile: $ODIDO_DOCKERFILE
    image: selfhost/odido-booster:${ODIDO_BOOSTER_IMAGE_TAG:-latest}
    container_name: ${CONTAINER_PREFIX}odido-booster
    labels:
      - "io.dhi.hardened=true"
    networks: [dhi-frontnet]
    ports: ["$LAN_IP:8085:8080"]
    environment:
      - API_KEY=$ODIDO_API_KEY
      - ODIDO_USER_ID=$ODIDO_USER_ID
      - ODIDO_TOKEN=$ODIDO_TOKEN
      - PORT=8080
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://127.0.0.1:8080/"]
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
    fi

    if should_deploy "memos"; then
        MEMOS_DOCKERFILE=$(detect_dockerfile "$SRC_DIR/memos" || echo "Dockerfile")
    cat >> "$COMPOSE_FILE" <<EOF
  memos:
    pull_policy: build
    build:
      context: $SRC_DIR/memos
      dockerfile: ${MEMOS_DOCKERFILE:-Dockerfile}
    image: selfhost/memos:${MEMOS_IMAGE_TAG:-latest}
    container_name: ${CONTAINER_PREFIX}memos
    labels:
      - "io.dhi.hardened=true"
    networks: [dhi-frontnet]
    ports: ["$LAN_IP:$PORT_MEMOS:5230"]
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
    fi

    if should_deploy "gluetun"; then
        GLUETUN_DOCKERFILE=$(detect_dockerfile "$SRC_DIR/gluetun" || echo "Dockerfile")
    cat >> "$COMPOSE_FILE" <<EOF
  gluetun:
    pull_policy: build
    build:
      context: $SRC_DIR/gluetun
      dockerfile: ${GLUETUN_DOCKERFILE:-Dockerfile}
    image: selfhost/gluetun:${GLUETUN_IMAGE_TAG:-latest}
    container_name: ${CONTAINER_PREFIX}gluetun
    labels:
      - "casaos.skip=true"
    cap_add: [NET_ADMIN]
    sysctls:
      - net.ipv4.conf.all.src_valid_mark=1
      - net.ipv4.ip_forward=1
    devices:
      - /dev/net/tun:/dev/net/tun
    networks: [dhi-frontnet]
    ports:
      - "$LAN_IP:$PORT_REDLIB:$PORT_INT_REDLIB/tcp"
      - "$LAN_IP:$PORT_WIKILESS:$PORT_INT_WIKILESS/tcp"
      - "$LAN_IP:$PORT_INVIDIOUS:$PORT_INT_INVIDIOUS/tcp"
      - "$LAN_IP:$PORT_RIMGO:$PORT_INT_RIMGO/tcp"
      - "$LAN_IP:$PORT_SCRIBE:$PORT_SCRIBE/tcp"
      - "$LAN_IP:$PORT_BREEZEWIKI:$PORT_INT_BREEZEWIKI/tcp"
      - "$LAN_IP:$PORT_ANONYMOUS:$PORT_INT_ANONYMOUS/tcp"
      - "$LAN_IP:$PORT_COMPANION:$PORT_INT_COMPANION/tcp"
      - "$LAN_IP:$PORT_COBALT:$PORT_INT_COBALT/tcp"
      - "$LAN_IP:$PORT_SEARXNG:$PORT_INT_SEARXNG/tcp"
      - "$LAN_IP:$PORT_IMMICH:$PORT_INT_IMMICH/tcp"
    volumes:
      - "$ACTIVE_WG_CONF:/gluetun/wireguard/wg0.conf:ro"
    env_file:
      - "$GLUETUN_ENV_FILE"
    healthcheck:
      # Check both the control server and actual VPN tunnel connectivity
      test: ["CMD-SHELL", "wget --user=gluetun --password=$ADMIN_PASS_COMPOSE -qO- http://127.0.0.1:8000/v1/vpn/status | grep -q '\"status\":\"running\"' && wget -U \"Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36\" --spider -q --timeout=5 http://connectivity-check.ubuntu.com || exit 1"]
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '2.0', memory: 512M}
EOF
    fi

    if should_deploy "dashboard"; then
    cat >> "$COMPOSE_FILE" <<EOF
  dashboard:
    image: selfhost/nginx:${DASHBOARD_IMAGE_TAG:-1.28-alpine3.21}
    container_name: ${CONTAINER_PREFIX}dashboard
    networks: [dhi-frontnet]
    ports:
      - "$LAN_IP:$PORT_DASHBOARD_WEB:$PORT_DASHBOARD_WEB"
      - "$LAN_IP:8443:8443"
    volumes:
      - "$ASSETS_DIR:/usr/share/nginx/html/assets:ro"
      - "$DASHBOARD_FILE:/usr/share/nginx/html/index.html:ro"
      - "$NGINX_CONF:/etc/nginx/conf.d/default.conf:ro"
      - "$AGH_CONF_DIR:/etc/adguard/conf:ro"
    labels:
      - "io.dhi.hardened=true"
      - "dev.casaos.app.ui.protocol=http"
      - "dev.casaos.app.ui.port=$PORT_DASHBOARD_WEB"
      - "dev.casaos.app.ui.hostname=$LAN_IP"
      - "dev.casaos.app.ui.icon=/assets/$APP_NAME.svg"
      - "dev.casaos.app.icon=/assets/$APP_NAME.svg"
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
    fi

    if should_deploy "portainer"; then
        PORTAINER_DOCKERFILE=$(detect_dockerfile "$SRC_DIR/portainer" || echo "Dockerfile")
    cat >> "$COMPOSE_FILE" <<EOF
  portainer:
    image: portainer/portainer-ce:latest
    container_name: ${CONTAINER_PREFIX}portainer
    command: ["-H", "unix:///var/run/docker.sock", "--admin-password", "$PORTAINER_HASH_COMPOSE", "--no-analytics"]
    networks: [dhi-frontnet]
    ports: ["$LAN_IP:$PORT_PORTAINER:9000"]
    volumes: ["/var/run/docker.sock:/var/run/docker.sock", "$DATA_DIR/portainer:/data"]
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://127.0.0.1:9000/"]
      interval: 30s
      timeout: 5s
      retries: 3
    # Admin password is saved in protonpass_import.csv for initial setup
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '0.5', memory: 512M}
EOF
    fi

    if should_deploy "adguard"; then
        ADGUARD_DOCKERFILE=$(detect_dockerfile "$SRC_DIR/adguardhome" || echo "Dockerfile")
    cat >> "$COMPOSE_FILE" <<EOF
  adguard:
    pull_policy: build
    build:
      context: $SRC_DIR/adguardhome
      dockerfile: ${ADGUARD_DOCKERFILE:-Dockerfile}
    image: selfhost/adguard:${ADGUARD_IMAGE_TAG:-latest}
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
      test: ["CMD", "/opt/adguardhome/AdGuardHome", "--check-config"]
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
    fi

    if should_deploy "unbound"; then
        UNBOUND_DOCKERFILE=$(detect_dockerfile "$SRC_DIR/unbound" || echo "Dockerfile")
    cat >> "$COMPOSE_FILE" <<EOF
  unbound:
    pull_policy: build
    build:
      context: $SRC_DIR/unbound
      dockerfile: ${UNBOUND_DOCKERFILE:-Dockerfile}
    image: selfhost/unbound:${UNBOUND_IMAGE_TAG:-latest}
    container_name: ${CONTAINER_PREFIX}unbound
    labels:
      - "io.dhi.hardened=true"
    networks:
      dhi-frontnet:
        ipv4_address: 172.$FOUND_OCTET.0.250
    volumes:
      - "$UNBOUND_CONF:/etc/unbound/unbound.conf:ro"
    healthcheck:
      test: ["CMD-SHELL", "grep -q '127.0.0.1' /etc/resolv.conf || exit 0"]
      interval: 30s
      timeout: 5s
      retries: 3
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '0.5', memory: 256M}
EOF
    fi

    if should_deploy "wg-easy"; then
        WG_EASY_DOCKERFILE=$(detect_dockerfile "$SRC_DIR/wg-easy" || echo "Dockerfile")
    cat >> "$COMPOSE_FILE" <<EOF
  # WG-Easy: Remote access VPN server (only 51820/UDP exposed to internet)
  wg-easy:
    pull_policy: build
    build:
      context: $SRC_DIR/wg-easy
      dockerfile: ${WG_EASY_DOCKERFILE:-Dockerfile}
    image: selfhost/wg-easy:${WG_EASY_IMAGE_TAG:-latest}
    container_name: ${CONTAINER_PREFIX}wg-easy
    network_mode: "host"
    environment:
      - WG_HOST=$PUBLIC_IP
      - PASSWORD_HASH=$WG_HASH_COMPOSE
      - WG_DEFAULT_DNS=$LAN_IP
      - WG_ALLOWED_IPS=10.0.0.0/8,172.16.0.0/12,192.168.0.0/16
      - WG_PERSISTENT_KEEPALIVE=0
      - WG_PORT=51820
      - WG_DEVICE=eth0
      - WG_POST_UP=iptables -t nat -I POSTROUTING 1 -s 10.8.0.0/24 -j MASQUERADE; iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT
      - WG_POST_DOWN=iptables -t nat -D POSTROUTING -s 10.8.0.0/24 -j MASQUERADE; iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT
    volumes: ["$DATA_DIR/wireguard:/etc/wireguard"]
    cap_add: [NET_ADMIN, SYS_MODULE]
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '1.0', memory: 256M}
EOF
    fi

    if should_deploy "redlib"; then
        REDLIB_DOCKERFILE=$(detect_dockerfile "$SRC_DIR/redlib" || echo "Dockerfile")
    cat >> "$COMPOSE_FILE" <<EOF
  redlib:
    pull_policy: build
    build:
      context: $SRC_DIR/redlib
      dockerfile: ${REDLIB_DOCKERFILE:-Dockerfile}
      args:
        - TARGET=x86_64-unknown-linux-musl
    image: selfhost/redlib:${REDLIB_IMAGE_TAG:-latest}
    container_name: ${CONTAINER_PREFIX}redlib
    labels:
      - "io.dhi.hardened=true"
    network_mode: "service:gluetun"
    environment: {REDLIB_DEFAULT_WIDE: "on", REDLIB_DEFAULT_USE_HLS: "on", REDLIB_DEFAULT_SHOW_NSFW: "on"}
    restart: always
    user: nobody
    read_only: true
    security_opt: [no-new-privileges:true]
    cap_drop: [ALL]
    depends_on: {gluetun: {condition: service_healthy}}
    healthcheck:
      test: ["CMD-SHELL", "wget --spider -q http://127.0.0.1:8080/robots.txt || [ $? -eq 8 ]"]
      interval: 1m
      timeout: 5s
      retries: 3
    deploy:
      resources:
        limits: {cpus: '0.5', memory: 256M}
EOF
    fi

    if should_deploy "wikiless"; then
        WIKILESS_DOCKERFILE=$(detect_dockerfile "$SRC_DIR/wikiless" || echo "Dockerfile")
    cat >> "$COMPOSE_FILE" <<EOF
  wikiless:
    pull_policy: build
    build:
      context: $SRC_DIR/wikiless
      dockerfile: ${WIKILESS_DOCKERFILE:-Dockerfile}
    image: selfhost/wikiless:${WIKILESS_IMAGE_TAG:-latest}
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
    image: selfhost/redis:${REDIS_IMAGE_TAG:-7.2-debian}
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
    fi

    if should_deploy "invidious"; then
        INVIDIOUS_DOCKERFILE=$(detect_dockerfile "$SRC_DIR/invidious" || echo "Dockerfile")
        COMPANION_DOCKERFILE=$(detect_dockerfile "$SRC_DIR/invidious-companion" || echo "Dockerfile")
    cat >> "$COMPOSE_FILE" <<EOF
  invidious:
    pull_policy: build
    build:
      context: $SRC_DIR/invidious
      dockerfile: ${INVIDIOUS_DOCKERFILE:-Dockerfile}
    image: selfhost/invidious:${INVIDIOUS_IMAGE_TAG:-latest}
    container_name: ${CONTAINER_PREFIX}invidious
    labels:
      - "io.dhi.hardened=true"
    network_mode: "service:gluetun"
    environment:
      INVIDIOUS_CONFIG: |
        db:
          dbname: invidious
          user: kemal
          password: kemal
          host: 127.0.0.1
          port: 5432
        check_tables: true
        invidious_companion:
          - private_url: "http://127.0.0.1:8282/companion"
        invidious_companion_key: "$IV_COMPANION"
        hmac_key: "$IV_HMAC"
    healthcheck: {test: "wget -nv --tries=1 --spider http://127.0.0.1:3000/api/v1/stats || exit 1", interval: 30s, timeout: 5s, retries: 2}
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
    image: selfhost/postgres:${INVIDIOUS_DB_IMAGE_TAG:-14-alpine3.22}
    container_name: ${CONTAINER_PREFIX}invidious-db
    labels:
      - "casaos.skip=true"
      - "io.dhi.hardened=true"
    network_mode: "service:gluetun"
    environment: {POSTGRES_DB: invidious, POSTGRES_USER: kemal, POSTGRES_PASSWORD: kemal}
    volumes:
      - $DATA_DIR/postgres:/var/lib/postgresql/data
      - $SRC_DIR/invidious/config/sql:/config/sql
      - $SRC_DIR/invidious/docker/init-invidious-db.sh:/docker-entrypoint-initdb.d/init-invidious-db.sh
    healthcheck: {test: ["CMD-SHELL", "pg_isready -U kemal -d invidious"], interval: 10s, timeout: 5s, retries: 5}
    restart: always
    deploy:
      resources:
        limits: {cpus: '1.0', memory: 512M}

  companion:
    container_name: ${CONTAINER_PREFIX}invidious-companion
    pull_policy: build
    build:
      context: $SRC_DIR/invidious-companion
      dockerfile: ${COMPANION_DOCKERFILE:-Dockerfile}
    image: selfhost/invidious-companion:${COMPANION_IMAGE_TAG:-latest}
    labels:
      - "casaos.skip=true"
    network_mode: "service:gluetun"
    environment:
      - SERVER_SECRET_KEY=$IV_COMPANION
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
    depends_on: {gluetun: {condition: service_healthy}}
EOF
    fi

    if should_deploy "rimgo"; then
        RIMGO_DOCKERFILE=$(detect_dockerfile "$SRC_DIR/rimgo" || echo "Dockerfile")
    cat >> "$COMPOSE_FILE" <<EOF
  rimgo:
    pull_policy: build
    build:
      context: $SRC_DIR/rimgo
      dockerfile: ${RIMGO_DOCKERFILE:-Dockerfile}
    image: selfhost/rimgo:${RIMGO_IMAGE_TAG:-latest}
    container_name: ${CONTAINER_PREFIX}rimgo
    labels:
      - "io.dhi.hardened=true"
    network_mode: "service:gluetun"
    environment: {IMGUR_CLIENT_ID: "546c25a59c58ad7", ADDRESS: "0.0.0.0", PORT: "$PORT_INT_RIMGO"}
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
    fi

    if should_deploy "breezewiki"; then
        BREEZEWIKI_DOCKERFILE=$(detect_dockerfile "$SRC_DIR/breezewiki" || echo "Dockerfile.alpine")
    cat >> "$COMPOSE_FILE" <<EOF
  breezewiki:
    pull_policy: build
    build:
      context: $SRC_DIR/breezewiki
      dockerfile: ${BREEZEWIKI_DOCKERFILE:-Dockerfile.alpine}
    image: selfhost/breezewiki:${BREEZEWIKI_IMAGE_TAG:-latest}
    container_name: ${CONTAINER_PREFIX}breezewiki
    labels:
      - "io.dhi.hardened=true"
    network_mode: "service:gluetun"
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
    fi

    if should_deploy "anonymousoverflow"; then
        ANONYMOUS_DOCKERFILE=$(detect_dockerfile "$SRC_DIR/anonymousoverflow" || echo "Dockerfile")
    cat >> "$COMPOSE_FILE" <<EOF
  anonymousoverflow:
    pull_policy: build
    build:
      context: $SRC_DIR/anonymousoverflow
      dockerfile: ${ANONYMOUS_DOCKERFILE:-Dockerfile}
    image: selfhost/anonymousoverflow:${ANONYMOUSOVERFLOW_IMAGE_TAG:-latest}
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
    fi

    if should_deploy "scribe"; then
        SCRIBE_DOCKERFILE=$(detect_dockerfile "$SRC_DIR/scribe" || echo "Dockerfile")
    cat >> "$COMPOSE_FILE" <<EOF
  scribe:
    pull_policy: build
    build:
      context: "$SRC_DIR/scribe"
      dockerfile: $SCRIBE_DOCKERFILE
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
    fi

    if should_deploy "vert"; then
        VERT_DOCKERFILE=$(detect_dockerfile "$SRC_DIR/vert" || echo "Dockerfile")
        VERTD_DOCKERFILE=$(detect_dockerfile "$SRC_DIR/vertd" || echo "Dockerfile")
    cat >> "$COMPOSE_FILE" <<EOF
  # VERT: Local file conversion service
  vertd:
    container_name: ${CONTAINER_PREFIX}vertd
    pull_policy: build
    build:
      context: $SRC_DIR/vertd
      dockerfile: ${VERTD_DOCKERFILE:-Dockerfile}
    image: selfhost/vertd:${VERTD_IMAGE_TAG:-latest}
    networks: [dhi-frontnet]
    ports: ["$LAN_IP:$PORT_VERTD:$PORT_INT_VERTD"]
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://127.0.0.1:24153/api/v1/health"]
      interval: 30s
      timeout: 5s
      retries: 3
    labels:
      - "casaos.skip=true"
      - "io.dhi.hardened=true"
    environment:
      - PUBLIC_URL=$VERTD_PUB_URL
    # Hardware Acceleration (Intel Quick Sync, AMD VA-API, NVIDIA)
$VERTD_DEVICES
    restart: always
    deploy:
      resources:
        limits: {cpus: '2.0', memory: 1024M}
$(if [ -n "$VERTD_NVIDIA" ]; then echo "        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]"; fi)

  vert:
    container_name: ${CONTAINER_PREFIX}vert
    pull_policy: build
    build:
      context: "$SRC_DIR/vert"
      dockerfile: $VERT_DOCKERFILE
    image: selfhost/vert:${VERT_IMAGE_TAG:-latest}
    labels:
      - "casaos.skip=true"
      - "io.dhi.hardened=true"
    environment:
      - PUB_HOSTNAME=$VERT_PUB_HOSTNAME
      - PUB_PLAUSIBLE_URL=
      - PUB_ENV=production
      - PUB_DISABLE_ALL_EXTERNAL_REQUESTS=true
      - PUB_DISABLE_FAILURE_BLOCKS=true
      - PUB_VERTD_URL=$VERTD_PUB_URL
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
    fi

    if should_deploy "cobalt"; then
    cat >> "$COMPOSE_FILE" <<EOF
  # Cobalt: Media downloader
  cobalt:
    image: ghcr.io/imputnet/cobalt:7
    container_name: ${CONTAINER_PREFIX}cobalt
    network_mode: "service:gluetun"
    environment:
      - API_URL=http://$LAN_IP:$PORT_COBALT/
      - FRONTEND_URL=http://$LAN_IP:$PORT_COBALT/
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '1.0', memory: 512M}
EOF
    fi

    if should_deploy "searxng"; then
    cat >> "$COMPOSE_FILE" <<EOF
  # SearXNG: Privacy-respecting metasearch engine
  searxng:
    image: searxng/searxng:latest
    container_name: ${CONTAINER_PREFIX}searxng
    network_mode: "service:gluetun"
    environment:
      - SEARXNG_SECRET=$SEARXNG_SECRET
      - BASE_URL=http://$LAN_IP:$PORT_SEARXNG/
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '1.0', memory: 512M}
EOF
    fi

    if should_deploy "immich"; then
    cat >> "$COMPOSE_FILE" <<EOF
  # Immich: High-performance self-hosted photo and video management
  immich-server:
    image: ghcr.io/immich-app/immich-server:release
    container_name: ${CONTAINER_PREFIX}immich-server
    network_mode: "service:gluetun"
    environment:
      - DB_HOSTNAME=${CONTAINER_PREFIX}immich-db
      - DB_USERNAME=immich
      - DB_PASSWORD=$IMMICH_DB_PASSWORD
      - DB_DATABASE_NAME=immich
      - REDIS_HOSTNAME=${CONTAINER_PREFIX}immich-redis
      - IMMICH_CONFIG_FILE=/config/immich.json
    volumes:
      - $DATA_DIR/immich:/usr/src/app/upload
      - $CONFIG_DIR/immich:/config
    depends_on:
      immich-db: {condition: service_healthy}
      immich-redis: {condition: service_healthy}
    restart: unless-stopped

  immich-db:
    image: registry.opensource.zalan.do/acid/spilo-14:2.1-p3
    container_name: ${CONTAINER_PREFIX}immich-db
    networks: [dhi-frontnet]
    environment:
      - POSTGRES_USER=immich
      - POSTGRES_PASSWORD=$IMMICH_DB_PASSWORD
      - POSTGRES_DB=immich
    volumes:
      - $DATA_DIR/immich-db:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -d immich -U immich"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped

  immich-redis:
    image: redis:6.2-alpine
    container_name: ${CONTAINER_PREFIX}immich-redis
    networks: [dhi-frontnet]
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped

  immich-machine-learning:
    image: ghcr.io/immich-app/immich-machine-learning:release
    container_name: ${CONTAINER_PREFIX}immich-ml
    network_mode: "service:gluetun"
    volumes:
      - $DATA_DIR/immich-ml-cache:/cache
    restart: unless-stopped
EOF
    fi

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
  port_map: "8081"
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