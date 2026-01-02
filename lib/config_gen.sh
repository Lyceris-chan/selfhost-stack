#!/usr/bin/env bash

# --- SECTION 9: INFRASTRUCTURE CONFIGURATION ---
# Generate configuration files for core system services (DNS, SSL, Nginx).

setup_static_assets() {
    log_info "Initializing local asset directories and icons..."
    $SUDO mkdir -p "$ASSETS_DIR"
    
    # Create local SVG icon for CasaOS/ZimaOS dashboard
    log_info "Creating local SVG icon for the dashboard..."
    cat > "$ASSETS_DIR/$APP_NAME.svg" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" height="128" viewBox="0 -960 960 960" width="128" fill="#D0BCFF">
    <path d="M480-80q-139-35-229.5-159.5S160-516 160-666v-134l320-120 320 120v134q0 151-90.5 275.5T480-80Zm0-84q104-33 172-132t68-210v-105l-240-90-240 90v105q0 111 68 210t172 132Zm0-316Z"/>
</svg>
EOF
}

download_remote_assets() {
    log_info "Downloading remote assets to ensure dashboard privacy and eliminate third-party dependencies."
    $SUDO mkdir -p "$ASSETS_DIR"
    
    # Check if assets are already set up
    if [ -f "$ASSETS_DIR/gs.css" ] && [ -f "$ASSETS_DIR/cc.css" ] && [ -f "$ASSETS_DIR/ms.css" ]; then
        log_info "Remote assets are already present. Skipping download."
        return 0
    fi

    # URLs (Fontlay)
    URL_GS="https://fontlay.com/css2?family=Google+Sans+Flex:wght@400;500;600;700&display=swap"
    URL_CC="https://fontlay.com/css2?family=Cascadia+Code:ital,wght@0,200..700;1,200..700&display=swap"
    URL_MS="https://fontlay.com/css2?family=Material+Symbols+Rounded:opsz,wght,FILL,GRAD@20..48,100..700,0..1,-50..200&display=swap"

    download_css() {
        local dest="$1"
        local url="$2"
        local proxy="http://172.${FOUND_OCTET}.0.254:8888" # Gluetun proxy in frontnet
        if ! curl --proxy "$proxy" -fsSL --max-time 15 -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" "$url" -o "$dest"; then
            log_warn "Asset source failed: $url (via $proxy). Retrying without proxy..."
            if ! curl -fsSL --max-time 15 -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" "$url" -o "$dest"; then
                log_warn "Asset source failed again: $url"
            fi
        fi
    }

    css_origin() {
        echo "$1" | sed -E 's#(https?://[^/]+).*#\1#'
    }

    download_css "$ASSETS_DIR/gs.css" "$URL_GS" &
    download_css "$ASSETS_DIR/cc.css" "$URL_CC" &
    download_css "$ASSETS_DIR/ms.css" "$URL_MS" &
    wait

    # Material Color Utilities (Local for privacy)
    log_info "Downloading Material Color Utilities..."
    local proxy="http://172.${FOUND_OCTET}.0.254:8888"
    if ! curl --proxy "$proxy" -fsSL --max-time 15 -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" "https://cdn.jsdelivr.net/npm/@material/material-color-utilities@0.3.0/dist/material-color-utilities.min.js" -o "$ASSETS_DIR/mcu.js"; then
        log_warn "Failed to download Material Color Utilities via proxy. Retrying direct..."
        if ! curl -fsSL --max-time 15 -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" "https://cdn.jsdelivr.net/npm/@material/material-color-utilities@0.3.0/dist/material-color-utilities.min.js" -o "$ASSETS_DIR/mcu.js"; then
            log_warn "Failed to download Material Color Utilities."
        fi
    fi

    # Parse and download woff2 files for each CSS file
    cd "$ASSETS_DIR"
    declare -A CSS_ORIGINS
    CSS_ORIGINS[gs.css]="$(css_origin "$URL_GS")"
    CSS_ORIGINS[cc.css]="$(css_origin "$URL_CC")"
    CSS_ORIGINS[ms.css]="$(css_origin "$URL_MS")"

    log_info "Localizing font assets in parallel..."
    for css_file in gs.css cc.css ms.css; do
        if [ ! -s "$css_file" ]; then continue; fi
        css_origin="${CSS_ORIGINS[$css_file]}"
        
        # Collect all unique URLs
        urls=$(grep -o "url([^)]*)" "$css_file" | sed 's/url(//;s/)//' | tr -d "'\"" | sort | uniq)
        
        for url in $urls; do
            (
                if [ -z "$url" ]; then exit 0; fi
                filename=$(basename "$url")
                clean_name="${filename%%\?*}"
                fetch_url="$url"
                if [[ "$url" == //* ]]; then
                    fetch_url="https:$url"
                elif [[ "$url" == /* ]]; then
                    fetch_url="${css_origin}${url}"
                elif [[ "$url" != http* ]]; then
                    fetch_url="${css_origin}/${url}"
                fi
                
                if [ ! -f "$clean_name" ]; then
                    if ! curl --proxy "$proxy" -sL --max-time 15 "$fetch_url" -o "$clean_name"; then
                        log_warn "Font asset download failed via proxy: $fetch_url. Retrying direct..."
                        curl -sL --max-time 15 "$fetch_url" -o "$clean_name"
                    fi
                fi
                
                escaped_url=$(echo "$url" | sed 's/[\/&|]/\\&/g')
                sed -i "s|url(['\"]\{0,1\}${escaped_url}['\"]\{0,1\})|url($clean_name)|g" "$css_file"
            ) &
        done
        wait
    done
    cd - >/dev/null
    
    log_info "Remote assets download and localization complete."
}

setup_configs() {
    log_info "Compiling Infrastructure Configs..."

    # Initialize log files and data files
    touch "$HISTORY_LOG" "$ACTIVE_WG_CONF" "$BASE_DIR/.data_usage" "$BASE_DIR/.wge_data_usage"
    if [ ! -f "$ACTIVE_PROFILE_NAME_FILE" ]; then echo "Initial-Setup" > "$ACTIVE_PROFILE_NAME_FILE"; fi
    chmod 666 "$ACTIVE_PROFILE_NAME_FILE" "$HISTORY_LOG" "$BASE_DIR/.data_usage" "$BASE_DIR/.wge_data_usage"

    # DNS & Certificate Setup
    log_info "Setting up DNS and certificates..."

    if [ -n "$DESEC_DOMAIN" ] && [ -n "$DESEC_TOKEN" ]; then
        log_info "deSEC domain provided: $DESEC_DOMAIN"
        log_info "Configuring Let's Encrypt with DNS-01 challenge..."
        
        log_info "Updating deSEC DNS record to point to $PUBLIC_IP..."
        DESEC_RESPONSE=$(curl -s --max-time 15 -X PATCH "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/" \
            -H "Authorization: Token $DESEC_TOKEN" \
            -H "Content-Type: application/json" \
            -d "[{\"subname\": \"\", \"ttl\": 3600, \"type\": \"A\", \"records\": [\"$PUBLIC_IP\"]}, {\"subname\": \"*\", \"ttl\": 3600, \"type\": \"A\", \"records\": [\"$PUBLIC_IP\"]}]" 2>&1 || echo "CURL_ERROR")
        
        PUBLIC_IP_ESCAPED="${PUBLIC_IP//./\\.}"
        if [[ "$DESEC_RESPONSE" == "CURL_ERROR" ]]; then
            log_warn "Failed to communicate with deSEC API (network error)."
        elif [ -z "$DESEC_RESPONSE" ] || echo "$DESEC_RESPONSE" | grep -qE "(${PUBLIC_IP_ESCAPED}|\[\]|\"records\")" ; then
            log_info "DNS record updated successfully"
        else
            log_warn "DNS update response: $DESEC_RESPONSE"
        fi
        
        log_info "Setting up SSL certificates..."
        mkdir -p "$AGH_CONF_DIR/certbot"
        
        # Check for existing valid certificate to avoid rate limits
        SKIP_CERT_REQ=false
        if [ -f "$AGH_CONF_DIR/ssl.crt" ] && [ -f "$AGH_CONF_DIR/ssl.key" ]; then
            log_info "Checking validity of existing SSL certificate..."
            if $DOCKER_CMD run --rm -v "$AGH_CONF_DIR:/certs" neilpang/acme.sh:latest /bin/sh -c \
                "openssl x509 -in /certs/ssl.crt -checkend 2592000 -noout && \
                 openssl x509 -in /certs/ssl.crt -noout -subject | grep -q '$DESEC_DOMAIN'" >/dev/null 2>&1; then
                log_info "Existing SSL certificate is valid for $DESEC_DOMAIN and has >30 days remaining."
                log_info "Skipping new certificate request to conserve rate limits."
                SKIP_CERT_REQ=true
            else
                log_info "Existing certificate is invalid, expired, or for a different domain. Requesting new one..."
            fi
        fi

        if [ "$SKIP_CERT_REQ" = false ]; then
            log_info "Attempting Let's Encrypt certificate..."
            CERT_SUCCESS=false
            CERT_LOG_FILE="$AGH_CONF_DIR/certbot/last_run.log"

            # Request Let's Encrypt certificate via DNS-01 challenge
            CERT_TMP_OUT=$(mktemp)
            if $DOCKER_CMD run --rm \
                -v "$AGH_CONF_DIR:/acme" \
                -e "DESEC_Token=$DESEC_TOKEN" \
                -e "DEDYN_TOKEN=$DESEC_TOKEN" \
                -e "DESEC_DOMAIN=$DESEC_DOMAIN" \
                neilpang/acme.sh:latest \
                --issue \
                --dns dns_desec \
                --dnssleep 120 \
                --debug 2 \
                -d "$DESEC_DOMAIN" \
                -d "*.$DESEC_DOMAIN" \
                --keylength ec-256 \
                --server letsencrypt \
                --home /acme \
                --config-home /acme \
                --cert-home /acme/certs > "$CERT_TMP_OUT" 2>&1; then
                CERT_SUCCESS=true
            else
                CERT_SUCCESS=false
            fi
            CERT_OUTPUT=$(cat "$CERT_TMP_OUT")
            echo "$CERT_OUTPUT" > "$CERT_LOG_FILE"
            rm -f "$CERT_TMP_OUT"

            if [ "$CERT_SUCCESS" = true ] && [ -f "$AGH_CONF_DIR/certs/${DESEC_DOMAIN}_ecc/fullchain.cer" ]; then
                cp "$AGH_CONF_DIR/certs/${DESEC_DOMAIN}_ecc/fullchain.cer" "$AGH_CONF_DIR/ssl.crt"
                cp "$AGH_CONF_DIR/certs/${DESEC_DOMAIN}_ecc/${DESEC_DOMAIN}.key" "$AGH_CONF_DIR/ssl.key"
                log_info "Let's Encrypt certificate installed successfully!"
                log_info "Certificate log saved to $CERT_LOG_FILE"
            elif [ "$CERT_SUCCESS" = true ] && [ -f "$AGH_CONF_DIR/certs/${DESEC_DOMAIN}/fullchain.cer" ]; then
                cp "$AGH_CONF_DIR/certs/${DESEC_DOMAIN}/fullchain.cer" "$AGH_CONF_DIR/ssl.crt"
                cp "$AGH_CONF_DIR/certs/${DESEC_DOMAIN}/${DESEC_DOMAIN}.key" "$AGH_CONF_DIR/ssl.key"
                log_info "Let's Encrypt certificate installed successfully!"
                log_info "Certificate log saved to $CERT_LOG_FILE"
            else
                RETRY_TIME=$(echo "$CERT_OUTPUT" | grep -oiE 'retry after [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]+ UTC' | head -1 | sed 's/retry after //I')
                if [ -n "$RETRY_TIME" ]; then
                    RETRY_EPOCH=$(date -u -d "$RETRY_TIME" +%s 2>/dev/null || echo "")
                    NOW_EPOCH=$(date -u +%s)
                    if [ -n "$RETRY_EPOCH" ] && [ "$RETRY_EPOCH" -gt "$NOW_EPOCH" ] 2>/dev/null; then
                        SECS_LEFT=$((RETRY_EPOCH - NOW_EPOCH))
                        HRS_LEFT=$((SECS_LEFT / 3600))
                        MINS_LEFT=$(((SECS_LEFT % 3600) / 60))
                        log_warn "Let's Encrypt rate limited. Retry after $RETRY_TIME (~${HRS_LEFT}h ${MINS_LEFT}m)."
                        log_info "A background task has been scheduled to automatically retry at exactly this time."
                    else
                        log_warn "Let's Encrypt rate limited. Retry after $RETRY_TIME."
                        log_info "A background task has been scheduled to automatically retry at exactly this time."
                    fi
                else
                    log_warn "Let's Encrypt failed (see $CERT_LOG_FILE)."
                fi
                log_warn "Let's Encrypt failed, generating self-signed certificate..."
                $DOCKER_CMD run --rm \
                    -v "$AGH_CONF_DIR:/certs" \
                    neilpang/acme.sh:latest /bin/sh -c "
                    openssl req -x509 -newkey rsa:4096 -sha256 \
                        -days 365 -nodes \
                        -keyout /certs/ssl.key -out /certs/ssl.crt \
                        -subj '/CN=$DESEC_DOMAIN' \
                        -addext 'subjectAltName=DNS:$DESEC_DOMAIN,DNS:*.$DESEC_DOMAIN,IP:$PUBLIC_IP'
                    "
                log_info "Generated self-signed certificate for $DESEC_DOMAIN"
            fi
        fi
        
        DNS_SERVER_NAME="$DESEC_DOMAIN"
        
        if [ -f "$AGH_CONF_DIR/ssl.crt" ] && [ -f "$AGH_CONF_DIR/ssl.key" ]; then
            log_info "SSL certificate ready for $DESEC_DOMAIN"
        else
            log_warn "SSL certificate files not found - AdGuard may not start with TLS"
        fi
        
    else
        log_info "No deSEC domain provided, generating self-signed certificate..."
        $DOCKER_CMD run --rm -v "$AGH_CONF_DIR:/certs" neilpang/acme.sh:latest /bin/sh -c \
            "openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
             -keyout /certs/ssl.key -out /certs/ssl.crt \
             -subj '/CN=$LAN_IP' \
             -addext 'subjectAltName=IP:$LAN_IP,IP:$PUBLIC_IP'"
        
        log_info "Self-signed certificate generated"
        DNS_SERVER_NAME="$LAN_IP"
    fi

    UNBOUND_STATIC_IP="172.${FOUND_OCTET}.0.250"
    log_info "Unbound will use static IP: $UNBOUND_STATIC_IP"

    # Ensure config directories exist
    $SUDO mkdir -p "$(dirname "$UNBOUND_CONF")"
    $SUDO mkdir -p "$(dirname "$NGINX_CONF")"
    $SUDO mkdir -p "$AGH_CONF_DIR"

    # Unbound recursive DNS configuration
    cat <<'UNBOUNDEOF' | $SUDO tee "$UNBOUND_CONF" >/dev/null
server:
  interface: 0.0.0.0
  port: 53
  do-ip4: yes
  do-udp: yes
  do-tcp: yes
  use-syslog: no
  log-queries: yes
  verbosity: 1
  chroot: ""
  access-control: 0.0.0.0/0 refuse
  access-control: 172.16.0.0/12 allow
  access-control: 192.168.0.0/16 allow
  access-control: 10.0.0.0/8 allow
  hide-identity: yes
  hide-version: yes
  num-threads: 2
  msg-cache-size: 50m
  rrset-cache-size: 100m
  prefetch: yes
  prefetch-key: yes
  auto-trust-anchor-file: "/etc/unbound/root.key"
UNBOUNDEOF

    cat <<EOF | $SUDO tee "$AGH_YAML" >/dev/null
schema_version: 29
bind_host: 0.0.0.0
bind_port: $PORT_ADGUARD_WEB
users: [{name: $AGH_USER, password: $AGH_PASS_HASH}]
auth_attempts: 5
block_auth_min: 15
http: {address: 0.0.0.0:$PORT_ADGUARD_WEB}
dns:
  bind_hosts: [0.0.0.0]
  port: 53
  upstream_dns:
    - "$UNBOUND_STATIC_IP"
  bootstrap_dns:
    - "$UNBOUND_STATIC_IP"
  protection_enabled: true
  filtering_enabled: true
  blocking_mode: default
  safesearch_enabled: true
querylog:
  enabled: true
  file_enabled: true
  interval: 720h
  size_memory: 1000
  ignored: []
statistics:
  enabled: true
  interval: 720h
  ignored: []
tls:
  enabled: true
  server_name: $DNS_SERVER_NAME
  force_https: false
  port_https: 443
  port_dns_over_tls: 853
  port_dns_over_quic: 853
  certificate_path: /opt/adguardhome/conf/ssl.crt
  private_key_path: /opt/adguardhome/conf/ssl.key
  allow_unencrypted_doh: false
EOF

    # Build user_rules list for AdGuard Home
    AGH_USER_RULES=""
    if [ -n "$DESEC_DOMAIN" ]; then
        log_info "Allowlisting $DESEC_DOMAIN by default."
        AGH_USER_RULES="${AGH_USER_RULES}  - '@@||${DESEC_DOMAIN}^'\n"
    fi

    if [ "$ALLOW_PROTON_VPN" = true ]; then
        log_info "Allowlisting ProtonVPN domains."
        for domain in getproton.me vpn-api.proton.me protonstatus.com protonvpn.ch protonvpn.com protonvpn.net; do
            AGH_USER_RULES="${AGH_USER_RULES}  - '@@||${domain}^'\n"
        done
    fi

    if [ -n "$AGH_USER_RULES" ]; then
        echo "user_rules:" >> "$AGH_YAML"
        echo -e "$AGH_USER_RULES" >> "$AGH_YAML"
    else
        echo "user_rules: []" >> "$AGH_YAML"
    fi

    cat >> "$AGH_YAML" <<EOF
  # Default DNS blocklist powered by sleepy list ([Lyceris-chan/dns-blocklist-generator](https://github.com/Lyceris-chan/dns-blocklist-generator))
filters:
  - enabled: true
    url: https://raw.githubusercontent.com/Lyceris-chan/dns-blocklist-generator/refs/heads/main/blocklist.txt
    name: "sleepy list"
    id: 1
  - enabled: true
    url: https://adaway.org/hosts.txt
    name: "AdAway Default"
    id: 2
  - enabled: true
    url: https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts
    name: "Steven Black's List"
    id: 3
filters_update_interval: 1
EOF

    if [ -n "$DESEC_DOMAIN" ]; then
        cat >> "$AGH_YAML" <<EOF
rewrites:
  - domain: $DESEC_DOMAIN
    answer: $LAN_IP
  - domain: "*.$DESEC_DOMAIN"
    answer: $LAN_IP
EOF
    fi

    # Prepare escaped hash for docker-compose (v2 requires $$ for literal $)
    WG_HASH_COMPOSE="${WG_HASH_CLEAN//\$/\$\$}"
    PORTAINER_HASH_COMPOSE="${PORTAINER_PASS_HASH//\$/\$\$}"

    cat <<EOF | $SUDO tee "$NGINX_CONF" >/dev/null
error_log /dev/stderr info;
access_log /dev/stdout;

# Dynamic backend mapping for subdomains
map \$http_host \$backend {
    hostnames;
    default "";
    invidious.$DESEC_DOMAIN  http://gluetun:3000;
    redlib.$DESEC_DOMAIN     http://gluetun:8080;
    wikiless.$DESEC_DOMAIN   http://gluetun:8180;
    memos.$DESEC_DOMAIN      http://$LAN_IP:$PORT_MEMOS;
    rimgo.$DESEC_DOMAIN      http://gluetun:3002;
    scribe.$DESEC_DOMAIN     http://gluetun:8280;
    breezewiki.$DESEC_DOMAIN http://gluetun:10416;
    anonymousoverflow.$DESEC_DOMAIN http://gluetun:8480;
    vert.$DESEC_DOMAIN       http://vert:80;
    vertd.$DESEC_DOMAIN      http://vertd:24153;
    adguard.$DESEC_DOMAIN    http://adguard:8083;
    portainer.$DESEC_DOMAIN  http://portainer:9000;
    wireguard.$DESEC_DOMAIN  http://$LAN_IP:51821;
    odido.$DESEC_DOMAIN      http://odido-booster:8080;
    cobalt.$DESEC_DOMAIN     http://cobalt:9000;
    searxng.$DESEC_DOMAIN    http://gluetun:8080;
    immich.$DESEC_DOMAIN     http://gluetun:2283;
    
    # Handle the 8443 port in the host header
    "invidious.$DESEC_DOMAIN:8443"  http://gluetun:3000;
    "redlib.$DESEC_DOMAIN:8443"     http://gluetun:8080;
    "wikiless.$DESEC_DOMAIN:8443"   http://gluetun:8180;
    "memos.$DESEC_DOMAIN:8443"      http://$LAN_IP:$PORT_MEMOS;
    "rimgo.$DESEC_DOMAIN:8443"      http://gluetun:3002;
    "scribe.$DESEC_DOMAIN:8443"     http://gluetun:8280;
    "breezewiki.$DESEC_DOMAIN:8443" http://gluetun:10416;
    "anonymousoverflow.$DESEC_DOMAIN:8443" http://gluetun:8480;
    "vert.$DESEC_DOMAIN:8443"       http://vert:80;
    "vertd.$DESEC_DOMAIN:8443"      http://vertd:24153;
    "adguard.$DESEC_DOMAIN:8443"    http://adguard:8083;
    "portainer.$DESEC_DOMAIN:8443"  http://portainer:9000;
    "wireguard.$DESEC_DOMAIN:8443"  http://$LAN_IP:51821;
    "odido.$DESEC_DOMAIN:8443"      http://odido-booster:8080;
    "cobalt.$DESEC_DOMAIN:8443"     http://cobalt:9000;
    "searxng.$DESEC_DOMAIN:8443"    http://gluetun:8080;
    "immich.$DESEC_DOMAIN:8443"     http://gluetun:2283;
}

server {
    listen $PORT_DASHBOARD_WEB default_server;
    listen 8443 ssl default_server;
    
    ssl_certificate /etc/adguard/conf/ssl.crt;
    ssl_certificate_key /etc/adguard/conf/ssl.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    # Use Docker DNS resolver
    resolver 127.0.0.11 valid=30s;

    # If the host matches a service subdomain, proxy it
    location / {
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        if (\$backend != "") {
            proxy_pass \$backend;
            break;
        }
        root /usr/share/nginx/html;
        index index.html;
    }

    location /api/ {
        proxy_pass http://hub-api:55555/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering off;
        proxy_cache off;
        proxy_connect_timeout 30s;
        proxy_read_timeout 120s;
        proxy_send_timeout 30s;
    }

    location /odido-api/ {
        proxy_pass http://odido-booster:8080/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 30s;
        proxy_read_timeout 120s;
    }
}
EOF

    # Generate environment variables for specialized privacy frontends.
    $SUDO mkdir -p "$ENV_DIR"
    
    # SearXNG Configuration
    $SUDO mkdir -p "$CONFIG_DIR/searxng"
    cat <<EOF | $SUDO tee "$CONFIG_DIR/searxng/settings.yml" >/dev/null
use_default_settings: true
server:
  secret_key: "$SEARXNG_SECRET"
  limiter: false
  image_proxy: true
ui:
  static_use_hash: true
  infinite_scroll: true
search:
  safe_search: 0
  autocomplete: google
  favicons: true
redis:
  url: redis://${CONTAINER_PREFIX}searxng-redis:6379/0
EOF

    # Immich Configuration
    $SUDO mkdir -p "$CONFIG_DIR/immich"
    cat <<EOF | $SUDO tee "$CONFIG_DIR/immich/immich.json" >/dev/null
{
  "database": {
    "host": "${CONTAINER_PREFIX}immich-db",
    "port": 5432,
    "user": "immich",
    "password": "$IMMICH_DB_PASSWORD",
    "database": "immich"
  },
  "redis": {
    "host": "${CONTAINER_PREFIX}immich-redis",
    "port": 6379
  },
  "machineLearning": {
    "enabled": true,
    "url": "http://${CONTAINER_PREFIX}immich-ml:3003"
  }
}
EOF

    cat <<EOF | $SUDO tee "$ENV_DIR/anonymousoverflow.env" >/dev/null
APP_URL=http://$LAN_IP:$PORT_ANONYMOUS
JWT_SIGNING_SECRET=$ANONYMOUS_SECRET
EOF
    cat <<EOF | $SUDO tee "$ENV_DIR/scribe.env" >/dev/null
SCRIBE_HOST=0.0.0.0
PORT=$PORT_SCRIBE
SECRET_KEY_BASE=$SCRIBE_SECRET
LUCKY_ENV=production
APP_DOMAIN=$LAN_IP:$PORT_SCRIBE
GITHUB_USERNAME="$SCRIBE_GH_USER"
GITHUB_PERSONAL_ACCESS_TOKEN="$SCRIBE_GH_TOKEN"
EOF

    generate_libredirect_export
}

generate_libredirect_export() {
    log_info "Generating LibRedirect import file..."
    local export_file="$PROJECT_ROOT/libredirect_import.json"
    
    # Construct URLs using the current LAN IP
    local url_invidious="http://$LAN_IP:3000"
    local url_redlib="http://$LAN_IP:8080"
    local url_wikiless="http://$LAN_IP:8180"
    local url_rimgo="http://$LAN_IP:3002"
    local url_scribe="http://$LAN_IP:8280"
    local url_breezewiki="http://$LAN_IP:8380"
    local url_anonoverflow="http://$LAN_IP:8480"
    local url_searxng="http://$LAN_IP:8082"

    cat > "$export_file" <<EOF
{
  "4get": ["https://4get.ca"],
  "anonymousOverflow": ["$url_anonoverflow"],
  "baiduTieba": {"enabled": false, "frontend": "ratAintTieba", "redirectOnlyInIncognito": false, "unsupportedUrls": "bypass"},
  "bandcamp": {"enabled": false, "frontend": "tent", "redirectOnlyInIncognito": false, "unsupportedUrls": "bypass"},
  "biblioReads": [],
  "bilibili": {"enabled": false, "frontend": "mikuInvidious", "redirectOnlyInIncognito": false, "unsupportedUrls": "bypass"},
  "binternet": ["https://bn.bloat.cat"],
  "bluesky": {"enabled": false, "frontend": "skyview", "redirectOnlyInIncognito": false, "unsupportedUrls": "bypass"},
  "breezeWiki": ["$url_breezewiki"],
  "chatGpt": {"enabled": false, "frontend": "duckDuckGoAiChat", "redirectOnlyInIncognito": false, "unsupportedUrls": "bypass"},
  "chefkoch": {"enabled": false, "frontend": "gocook", "redirectOnlyInIncognito": false, "unsupportedUrls": "bypass"},
  "cloudtube": ["https://tube.cadence.moe"],
  "coub": {"enabled": false, "frontend": "koub", "redirectOnlyInIncognito": false, "unsupportedUrls": "bypass"},
  "cryptPad": ["https://cryptpad.org"],
  "destructables": ["https://ds.vern.cc"],
  "deviantArt": {"enabled": false, "frontend": "skunkyArt", "redirectOnlyInIncognito": false, "redirectType": "main_frame", "unsupportedUrls": "bypass"},
  "ducksForDucks": ["https://ducksforducks.private.coffee"],
  "dumb": ["https://dm.vern.cc"],
  "eddrit": ["https://eddrit.com"],
  "exceptions": {"regex": [], "url": []},
  "fandom": {"enabled": true, "frontend": "breezeWiki", "instance": "custom", "redirectOnlyInIncognito": false, "unsupportedUrls": "bypass"},
  "fetchInstances": "github",
  "freedium": ["https://freedium.cfd"],
  "freetar": ["https://freetar.de"],
  "geeksForGeeks": {"enabled": false, "frontend": "nerdsForNerds", "redirectOnlyInIncognito": false, "redirectType": "main_frame", "unsupportedUrls": "bypass"},
  "genius": {"enabled": true, "frontend": "dumb", "instance": "custom", "redirectOnlyInIncognito": false, "unsupportedUrls": "bypass"},
  "github": {"enabled": false, "frontend": "gothub", "redirectOnlyInIncognito": false, "unsupportedUrls": "bypass"},
  "gitlab": {"enabled": false, "frontend": "laboratory", "redirectOnlyInIncognito": false, "unsupportedUrls": "bypass"},
  "gocook": ["https://cook.adminforge.de"],
  "goodreads": {"enabled": false, "frontend": "biblioReads", "instance": "public", "redirectOnlyInIncognito": false, "unsupportedUrls": "bypass"},
  "gothub": [],
  "hyperpipe": ["https://hyperpipe.surge.sh"],
  "ifunny": {"enabled": false, "frontend": "unfunny", "redirectOnlyInIncognito": false, "unsupportedUrls": "bypass"},
  "imdb": {"enabled": true, "frontend": "libremdb", "instance": "public", "redirectOnlyInIncognito": false, "unsupportedUrls": "bypass"},
  "imgur": {"enabled": true, "frontend": "rimgo", "instance": "custom", "redirectOnlyInIncognito": false, "redirectType": "main_frame", "unsupportedUrls": "bypass"},
  "indestructables": ["https://indestructables.private.coffee"],
  "instagram": {"enabled": false, "frontend": "proxigram", "instance": "public", "redirectOnlyInIncognito": false, "unsupportedUrls": "bypass"},
  "instructables": {"enabled": false, "frontend": "structables", "redirectOnlyInIncognito": false, "unsupportedUrls": "bypass"},
  "intellectual": ["https://intellectual.insprill.net"],
  "invidious": ["$url_invidious"],
  "invidiousMusic": [],
  "jitsi": [],
  "knowyourmeme": {"enabled": false, "frontend": "meme", "redirectOnlyInIncognito": false, "redirectType": "main_frame", "unsupportedUrls": "bypass"},
  "koub": ["https://koub.clovius.club"],
  "laboratory": ["https://lab.vern.cc"],
  "libMedium": ["https://md.vern.cc"],
  "libreTranslate": [],
  "libreddit": [],
  "libremdb": ["https://libremdb.iket.me"],
  "librey": [],
  "lightTube": ["https://tube.kuylar.dev"],
  "liteXiv": ["https://litexiv.exozy.me"],
  "maps": {"enabled": false, "frontend": "osm", "redirectOnlyInIncognito": false, "redirectType": "main_frame", "unsupportedUrls": "bypass"},
  "materialious": ["https://app.materialio.us"],
  "medium": {"enabled": true, "frontend": "scribe", "redirectOnlyInIncognito": false, "redirectType": "main_frame", "unsupportedUrls": "bypass"},
  "meet": {"enabled": false, "frontend": "jitsi", "redirectOnlyInIncognito": false, "unsupportedUrls": "bypass"},
  "meme": ["https://mm.vern.cc"],
  "mikuInvidious": [],
  "mozhi": ["https://mozhi.aryak.me"],
  "nerdsForNerds": ["https://nn.vern.cc"],
  "neuters": ["https://neuters.de"],
  "nitter": ["https://nitter.privacydev.net"],
  "office": {"enabled": false, "frontend": "cryptPad", "redirectOnlyInIncognito": false, "unsupportedUrls": "bypass"},
  "offtiktok": ["https://www.offtiktok.com"],
  "osm": ["https://www.openstreetmap.org"],
  "painterest": ["https://pt.bloat.cat"],
  "pastebin": {"enabled": false, "frontend": "pasted", "instance": "public", "redirectOnlyInIncognito": false, "unsupportedUrls": "bypass"},
  "pasted": ["https://pasted.drakeerv.com"],
  "pasty": ["https://pasty.lus.pm"],
  "pinterest": {"enabled": false, "frontend": "binternet", "redirectOnlyInIncognito": false, "redirectType": "main_frame", "unsupportedUrls": "bypass"},
  "piped": ["https://pipedapi-libre.kavin.rocks"],
  "pipedMaterial": ["https://piped-material.xn--17b.net"],
  "pixiv": {"enabled": false, "frontend": "pixivFe", "redirectOnlyInIncognito": false, "unsupportedUrls": "bypass"},
  "pixivFe": ["https://pixivfe.exozy.me"],
  "pixivViewer": ["https://pixiv.pictures"],
  "poketube": ["https://poketube.fun"],
  "popupServices": ["tiktok", "imgur", "reddit", "quora", "translate", "maps"],
  "privateBin": [],
  "priviblur": ["https://pb.bloat.cat"],
  "proxiTok": ["https://proxitok.pabloferreiro.es"],
  "proxigram": ["https://ig.opnxng.com"],
  "quetre": ["https://quetre.iket.me"],
  "quora": {"enabled": false, "frontend": "quetre", "instance": "public", "redirectOnlyInIncognito": false, "unsupportedUrls": "bypass"},
  "ratAintTieba": ["https://rat.fis.land"],
  "reddit": {"enabled": true, "frontend": "redlib", "instance": "custom", "redirectOnlyInIncognito": false, "redirectType": "main_frame", "unsupportedUrls": "bypass"},
  "redirectOnlyInIncognito": false,
  "redlib": ["$url_redlib"],
  "reuters": {"enabled": false, "frontend": "neuters", "redirectOnlyInIncognito": false, "unsupportedUrls": "bypass"},
  "rimgo": ["$url_rimgo"],
  "ruralDictionary": ["https://rd.vern.cc"],
  "safetwitch": ["https://safetwitch.drgns.space"],
  "scribe": ["$url_scribe"],
  "search": {"enabled": true, "frontend": "searxng", "instance": "custom", "redirectGoogle": false, "redirectOnlyInIncognito": false, "unsupportedUrls": "bypass"},
  "searx": [],
  "searxng": ["$url_searxng"],
  "send": [],
  "sendFiles": {"enabled": false, "frontend": "send", "redirectOnlyInIncognito": false, "unsupportedUrls": "bypass"},
  "shoelace": ["https://shoelace.mint.lgbt"],
  "simplyTranslate": ["https://simplytranslate.org"],
  "skunkyArt": ["https://skunky.bloat.cat"],
  "skyview": ["https://skyview.social"],
  "small": ["https://small.bloat.cat"],
  "snopes": {"enabled": false, "frontend": "suds", "redirectOnlyInIncognito": false, "unsupportedUrls": "bypass"},
  "soprano": ["https://sp.vern.cc"],
  "soundcloak": ["https://soundcloak.fly.dev"],
  "soundcloud": {"enabled": false, "frontend": "tuboSoundcloud", "redirectOnlyInIncognito": false, "redirectType": "main_frame", "unsupportedUrls": "bypass"},
  "stackOverflow": {"enabled": true, "frontend": "anonymousOverflow", "instance": "custom", "redirectOnlyInIncognito": false, "unsupportedUrls": "bypass"},
  "structables": ["https://structables.private.coffee"],
  "suds": ["https://sd.vern.cc"],
  "teddit": [],
  "tekstoLibre": ["https://davilarek.github.io/TekstoLibre"],
  "tekstowo": {"enabled": false, "frontend": "tekstoLibre", "redirectOnlyInIncognito": false, "unsupportedUrls": "bypass"},
  "tenor": {"enabled": false, "frontend": "soprano", "redirectOnlyInIncognito": false, "unsupportedUrls": "bypass"},
  "tent": ["https://tent.sny.sh"],
  "textStorage": {"enabled": false, "frontend": "privateBin", "redirectOnlyInIncognito": false, "unsupportedUrls": "bypass"},
  "theme": "detect",
  "threads": {"enabled": true, "frontend": "shoelace", "redirectOnlyInIncognito": false, "redirectType": "main_frame", "unsupportedUrls": "bypass"},
  "tiktok": {"enabled": false, "frontend": "proxiTok", "instance": "public", "redirectOnlyInIncognito": false, "redirectType": "main_frame", "unsupportedUrls": "bypass"},
  "translate": {"enabled": false, "frontend": "simplyTranslate", "instance": "public", "redirectOnlyInIncognito": false, "unsupportedUrls": "bypass"},
  "translite": ["https://tl.bloat.cat"],
  "troddit": ["https://www.troddit.com"],
  "tuboSoundcloud": ["https://tubo.media"],
  "tuboYoutube": ["https://tubo.media"],
  "tumblr": {"enabled": false, "frontend": "priviblur", "instance": "public", "redirectOnlyInIncognito": false, "redirectType": "main_frame", "unsupportedUrls": "bypass"},
  "twineo": ["https://twineo.exozy.me"],
  "twitch": {"enabled": false, "frontend": "safetwitch", "instance": "public", "redirectOnlyInIncognito": false, "redirectType": "main_frame", "unsupportedUrls": "bypass"},
  "twitter": {"enabled": false, "frontend": "nitter", "instance": "public", "redirectOnlyInIncognito": false, "redirectType": "main_frame", "unsupportedUrls": "bypass"},
  "ultimateGuitar": {"enabled": false, "frontend": "freetar", "redirectOnlyInIncognito": false, "unsupportedUrls": "bypass"},
  "ultimateTab": ["https://ultimate-tab.com"],
  "unfunny": ["https://uf.vern.cc"],
  "urbanDictionary": {"enabled": false, "frontend": "ruralDictionary", "redirectOnlyInIncognito": false, "unsupportedUrls": "bypass"},
  "viewtube": ["https://viewtube.io"],
  "vixipy": ["https://vx.maid.zone"],
  "waybackClassic": ["https://wayback-classic.net"],
  "waybackMachine": {"enabled": false, "frontend": "waybackClassic", "redirectOnlyInIncognito": false, "unsupportedUrls": "bypass"},
  "websurfx": ["https://alamin655-spacex.hf.space"],
  "whoogle": [],
  "wikiless": ["$url_wikiless"],
  "wikimore": ["https://wikimore.private.coffee"],
  "wikipedia": {"enabled": true, "frontend": "wikiless", "redirectOnlyInIncognito": false, "redirectType": "main_frame", "unsupportedUrls": "bypass"},
  "wolframAlpha": {"enabled": false, "frontend": "wolfreeAlpha", "redirectOnlyInIncognito": false, "unsupportedUrls": "bypass"},
  "wolfreeAlpha": ["https://gqq.gitlab.io", "https://uqq.gitlab.io"],
  "youtube": {"embedFrontend": "invidious", "enabled": true, "frontend": "invidious", "redirectOnlyInIncognito": false, "redirectType": "both", "unsupportedUrls": "bypass"},
  "youtubeMusic": {"enabled": false, "frontend": "hyperpipe", "redirectOnlyInIncognito": false, "redirectType": "main_frame", "unsupportedUrls": "bypass"},
  "ytify": ["https://ytify.us.kg"],
  "version": "3.2.0"
}
EOF
    chmod 644 "$export_file"
    log_info "LibRedirect import file created at $export_file"
}

