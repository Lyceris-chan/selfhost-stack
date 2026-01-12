# --- SECTION 12: ADMINISTRATIVE CONTROL ARTIFACTS ---

generate_scripts() {
    # 1. Migrate Script
    if [ -f "$SCRIPT_DIR/lib/templates/migrate.sh" ]; then
        safe_replace "$SCRIPT_DIR/lib/templates/migrate.sh" "$MIGRATE_SCRIPT" \
            "__CONTAINER_PREFIX__" "${CONTAINER_PREFIX}" \
            "__INVIDIOUS_DB_PASSWORD__" "${INVIDIOUS_DB_PASSWORD}" \
            "__IMMICH_DB_PASSWORD__" "${IMMICH_DB_PASSWORD}"
        chmod +x "$MIGRATE_SCRIPT"
    else
        echo "[WARN] templates/migrate.sh not found at $SCRIPT_DIR/lib/templates/migrate.sh"
    fi

    # 2. WG Control Script
    if [ -f "$SCRIPT_DIR/lib/templates/wg_control.sh" ]; then
        safe_replace "$SCRIPT_DIR/lib/templates/wg_control.sh" "$WG_CONTROL_SCRIPT" \
            "__CONTAINER_PREFIX__" "${CONTAINER_PREFIX}" \
            "__ADMIN_PASS_RAW__" "${ADMIN_PASS_RAW}"
        chmod +x "$WG_CONTROL_SCRIPT"
    else
        echo "[WARN] templates/wg_control.sh not found at $SCRIPT_DIR/lib/templates/wg_control.sh"
    fi

    # 3. Certificate Monitor Script
    cat > "$CERT_MONITOR_SCRIPT" <<EOF
#!/bin/sh
# Auto-generated certificate monitor
AGH_CONF_DIR="$AGH_CONF_DIR"
DESEC_TOKEN="$DESEC_TOKEN"
DESEC_DOMAIN="$DESEC_DOMAIN"
DOCKER_CMD="$DOCKER_CMD"

if [ -z "\$DESEC_DOMAIN" ]; then
    echo "No domain configured. Skipping certificate check."
    exit 0
fi

echo "Starting certificate renewal check for \$DESEC_DOMAIN..."

\$DOCKER_CMD run --rm \\
    -v "\$AGH_CONF_DIR:/acme" \\
    -e "DESEC_Token=\$DESEC_TOKEN" \\
    neilpang/acme.sh:latest --cron --home /acme --config-home /acme --cert-home /acme/certs

if [ \$? -eq 0 ]; then
    echo "Certificate check completed successfully."
    # Reload services to pick up new certs if they were renewed
    # We can lazily restart them; checking if file changed is harder in shell without state
    \$DOCKER_CMD restart ${CONTAINER_PREFIX}dashboard ${CONTAINER_PREFIX}adguard 2>/dev/null || true
else
    echo "Certificate check failed."
fi
EOF
    chmod +x "$CERT_MONITOR_SCRIPT"

    # 5. Hardware & Services Configuration
    VERTD_DEVICES=""
    GPU_LABEL="GPU Accelerated"
    GPU_TOOLTIP="Utilizes local GPU (/dev/dri) for high-performance conversion"

    if [ -d "/dev/dri" ]; then
        VERTD_DEVICES="    devices:
      - /dev/dri"
        if [ -d "/dev/vulkan" ]; then
            VERTD_DEVICES="${VERTD_DEVICES}
      - /dev/vulkan"
        fi
        
        if grep -iq "intel" /sys/class/drm/card*/device/vendor 2>/dev/null || (command -v lspci >/dev/null 2>&1 && lspci 2>/dev/null | grep -iq "intel.*graphics"); then
            GPU_LABEL="Intel Quick Sync"
            GPU_TOOLTIP="Utilizes Intel Quick Sync Video (QSV) for high-performance hardware conversion."
        elif grep -iq "1002" /sys/class/drm/card*/device/vendor 2>/dev/null || (command -v lspci >/dev/null 2>&1 && lspci 2>/dev/null | grep -iq "amd.*graphics"); then
            GPU_LABEL="AMD VA-API"
            GPU_TOOLTIP="Utilizes AMD VA-API hardware acceleration for high-performance conversion."
        fi
    fi

    VERTD_NVIDIA=""
    if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
        VERTD_NVIDIA="    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]"
        GPU_LABEL="NVIDIA NVENC"
        GPU_TOOLTIP="Utilizes NVIDIA NVENC/NVDEC hardware acceleration for high-performance conversion."
    fi

    if [ ! -f "$CONFIG_DIR/theme.json" ]; then echo "{}" | $SUDO tee "$CONFIG_DIR/theme.json" >/dev/null; fi
    $SUDO chmod 644 "$CONFIG_DIR/theme.json"
    SERVICES_JSON="$CONFIG_DIR/services.json"
    CUSTOM_SERVICES_JSON="$PROJECT_ROOT/custom_services.json"
    
    cat > "$SERVICES_JSON" <<EOF
{
  "services": {
    "anonymousoverflow": {
      "name": "AnonOverflow",
      "description": "A private StackOverflow interface. Facilitates information retrieval for developers without facilitating cross-site corporate surveillance.",
      "category": "apps",
      "order": 10,
      "url": "http://$LAN_IP:$PORT_ANONYMOUS",
      "source_url": "https://github.com/httpjamesm/AnonymousOverflow",
      "patch_url": "https://github.com/httpjamesm/AnonymousOverflow/blob/main/Dockerfile"
    },
    "breezewiki": {
      "name": "BreezeWiki",
      "description": "A clean interface for Fandom. Neutralizes aggressive advertising networks and tracking scripts that compromise standard browsing security.",
      "category": "apps",
      "order": 20,
      "url": "http://$LAN_IP:$PORT_BREEZEWIKI/",
      "source_url": "https://github.com/breezewiki/breezewiki",
      "patch_url": "https://github.com/PussTheCat-org/docker-breezewiki-quay/blob/master/docker/Dockerfile"
    },
    "cobalt": {
      "name": "Cobalt",
      "description": "The ultimate media downloader. Clean, efficient web interface for extracting content from dozens of platforms.",
      "category": "apps",
      "order": 30,
      "url": "http://$LAN_IP:$PORT_COBALT",
      "source_url": "https://github.com/imputnet/cobalt",
      "patch_url": "https://github.com/imputnet/cobalt/blob/master/Dockerfile",
      "chips": [
        {"label": "Local Only", "icon": "lan", "variant": "tertiary"}
      ]
    },
    "immich": {
      "name": "Immich",
      "description": "High-performance self-hosted photo and video management solution. Feature-rich alternative to mainstream cloud photo services.",
      "category": "apps",
      "order": 40,
      "url": "http://$LAN_IP:$PORT_IMMICH",
      "source_url": "https://github.com/immich-app/immich",
      "patch_url": "https://github.com/immich-app/immich/blob/main/Dockerfile",
      "chips": []
    },
    "invidious": {
      "name": "Invidious",
      "description": "A privacy-respecting YouTube frontend. Eliminates advertisements and tracking while providing a lightweight interface without proprietary JavaScript.",
      "category": "apps",
      "order": 50,
      "url": "http://$LAN_IP:$PORT_INVIDIOUS",
      "source_url": "https://github.com/iv-org/invidious",
      "patch_url": "https://github.com/iv-org/invidious/blob/master/docker/Dockerfile",
      "actions": [
        {"type": "migrate", "label": "Migrate DB", "icon": "database_upload", "mode": "migrate", "confirm": true},
        {"type": "migrate", "label": "Clear Logs", "icon": "delete_sweep", "mode": "clear-logs", "confirm": false}
      ]
    },
    "companion": {
      "name": "Invidious Companion",
      "description": "A helper service for Invidious that facilitates enhanced video retrieval and bypasses certain platform-specific limitations.",
      "category": "apps",
      "order": 60,
      "url": "http://$LAN_IP:$PORT_COMPANION",
      "source_url": "https://github.com/iv-org/invidious-companion",
      "patch_url": "https://github.com/iv-org/invidious-companion/blob/master/Dockerfile",
      "allowed_strategies": ["stable"]
    },
    "memos": {
      "name": "Memos",
      "description": "A private notes and knowledge base. Capture ideas, snippets, and personal documentation without third-party tracking.",
      "category": "apps",
      "order": 70,
      "url": "http://$LAN_IP:$PORT_MEMOS",
      "source_url": "https://github.com/usememos/memos",
      "patch_url": "https://github.com/usememos/memos/blob/main/scripts/Dockerfile",
      "actions": [
        {"type": "vacuum", "label": "Optimize DB", "icon": "compress"}
      ]
    },
    "redlib": {
      "name": "Redlib",
      "description": "A lightweight Reddit frontend that prioritizes privacy. Strips tracking pixels and unnecessary scripts to ensure a clean, performant browsing experience.",
      "category": "apps",
      "order": 80,
      "url": "http://$LAN_IP:$PORT_REDLIB",
      "source_url": "https://github.com/redlib-org/redlib",
      "patch_url": "https://github.com/redlib-org/redlib/blob/main/Dockerfile.alpine"
    },
    "rimgo": {
      "name": "Rimgo",
      "description": "An anonymous Imgur viewer that removes telemetry and tracking scripts. Access visual content without facilitating behavioral profiling.",
      "category": "apps",
      "order": 90,
      "url": "http://$LAN_IP:$PORT_RIMGO",
      "source_url": "https://codeberg.org/rimgo/rimgo",
      "patch_url": "https://codeberg.org/rimgo/rimgo/src/branch/main/Dockerfile"
    },
    "scribe": {
      "name": "Scribe",
      "description": "An alternative Medium frontend. Bypasses paywalls and eliminates tracking scripts to provide direct access to long-form content.",
      "category": "apps",
      "order": 100,
      "url": "http://$LAN_IP:$PORT_SCRIBE",
      "source_url": "https://git.sr.ht/~edwardloveall/scribe",
      "patch_url": "https://git.sr.ht/~edwardloveall/scribe"
    },
    "searxng": {
      "name": "SearXNG",
      "description": "A privacy-respecting, hackable metasearch engine that aggregates results from more than 70 search services.",
      "category": "apps",
      "order": 110,
      "url": "http://$LAN_IP:$PORT_SEARXNG",
      "source_url": "https://github.com/searxng/searxng",
      "patch_url": "https://github.com/searxng/searxng/blob/master/Dockerfile",
      "chips": []
    },
    "vert": {
      "name": "VERT",
      "description": "Local file conversion service. Maintains data autonomy by processing sensitive documents on your own hardware using GPU acceleration.",
      "category": "apps",
      "order": 120,
      "url": "http://$LAN_IP:$PORT_VERT",
      "source_url": "https://github.com/VERT-sh/VERT",
      "patch_url": "https://github.com/VERT-sh/VERT/blob/main/Dockerfile",
      "local": true,
      "chips": [
        {
          "label": "$GPU_LABEL",
          "icon": "memory",
          "variant": "tertiary",
          "tooltip": "$GPU_TOOLTIP",
          "portainer": false
        }
      ]
    },
    "wikiless": {
      "name": "Wikiless",
      "description": "A privacy-focused Wikipedia frontend. Prevents cookie-based tracking and cross-site telemetry while providing an optimized reading environment.",
      "category": "apps",
      "order": 130,
      "url": "http://$LAN_IP:$PORT_WIKILESS",
      "source_url": "https://github.com/Metastem/Wikiless",
      "patch_url": "https://github.com/Metastem/Wikiless/blob/main/Dockerfile"
    },
    "adguard": {
      "name": "AdGuard Home",
      "description": "Network-wide advertisement and tracker filtration. Centralizes DNS management to prevent data leakage at the source and ensure complete visibility of network traffic.",
      "category": "system",
      "order": 10,
      "url": "http://$LAN_IP:$PORT_ADGUARD_WEB",
      "source_url": "https://github.com/AdguardTeam/AdGuardHome",
      "patch_url": "https://github.com/AdguardTeam/AdGuardHome/blob/master/docker/Dockerfile",
      "actions": [
        {"type": "clear-logs", "label": "Clear Logs", "icon": "auto_delete"}
      ],
      "chips": [{"label": "Local Access", "icon": "lan", "variant": "tertiary"}, "Encrypted DNS"]
    },
    "hub-api": {
      "name": "Hub API",
      "description": "The central orchestration and management API for the Privacy Hub. Handles service lifecycles, metrics, and security policies.",
      "category": "system",
      "order": 20,
      "url": "http://$LAN_IP:$PORT_DASHBOARD_WEB/api/status",
      "source_url": "https://github.com/Lyceris-chan/selfhost-stack"
    },
    "portainer": {
      "name": "Portainer",
      "description": "A comprehensive management interface for the Docker environment. Facilitates granular control over container orchestration and infrastructure lifecycle management.",
      "category": "system",
      "order": 30,
      "url": "http://$LAN_IP:$PORT_PORTAINER",
      "source_url": "https://github.com/portainer/portainer",
      "patch_url": "https://github.com/portainer/portainer/blob/develop/build/linux/alpine.Dockerfile",
      "chips": [{"label": "Local Access", "icon": "lan", "variant": "tertiary"}]
    },
    "unbound": {
      "name": "Unbound",
      "description": "A validating, recursive, caching DNS resolver. Ensures that your DNS queries are resolved independently and securely.",
      "category": "system",
      "order": 40,
      "url": "#",
      "source_url": "https://github.com/NLnetLabs/unbound",
      "patch_url": "https://github.com/klutchell/unbound-docker/blob/main/Dockerfile"
    },
    "vertd": {
      "name": "VERTd",
      "description": "The background daemon for the VERT file conversion service. Handles intensive processing tasks and hardware acceleration logic.",
      "category": "system",
      "order": 50,
      "url": "http://$LAN_IP:$PORT_VERTD/api/version",
      "source_url": "https://github.com/VERT-sh/vertd",
      "patch_url": "https://github.com/VERT-sh/vertd/blob/main/Dockerfile",
      "allowed_strategies": ["nightly"]
    },
    "wg-easy": {
      "name": "WireGuard",
      "description": "The primary gateway for secure remote access. Provides a cryptographically sound tunnel to your home network, maintaining your privacy boundary on external networks.",
      "category": "system",
      "order": 60,
      "url": "http://$LAN_IP:$PORT_WG_WEB",
      "source_url": "https://github.com/wg-easy/wg-easy",
      "patch_url": "https://github.com/wg-easy/wg-easy/blob/master/Dockerfile",
      "chips": [{"label": "Local Access", "icon": "lan", "variant": "tertiary"}]
    },
    "odido-booster": {
      "name": "Odido Booster",
      "description": "Automated data management for Odido mobile connections. Ensures continuous connectivity by managing data bundles and usage thresholds.",
      "category": "tools",
      "order": 10,
      "url": "http://$LAN_IP:8085",
      "source_url": "https://github.com/Lyceris-chan/odido-bundle-booster",
      "patch_url": "https://github.com/Lyceris-chan/odido-bundle-booster/blob/main/Dockerfile"
    }
  }
}
EOF

    if [ -f "$CUSTOM_SERVICES_JSON" ]; then
        log_info "Integrating custom services from custom_services.json..."
        if TMP_MERGED=$(mktemp) && jq -s '.[0].services * .[1].services | {services: .}' "$SERVICES_JSON" "$CUSTOM_SERVICES_JSON" > "$TMP_MERGED"; then
            mv "$TMP_MERGED" "$SERVICES_JSON"
            log_info "Custom services successfully integrated."
        else
            log_warn "Failed to merge custom_services.json."
            [ -f "${TMP_MERGED:-}" ] && rm "$TMP_MERGED"
        fi
    fi
}

setup_static_assets() {
    log_info "Initializing local asset directories and icons..."
    $SUDO mkdir -p "$ASSETS_DIR"
    local svg_content="<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 128 128\">
    <rect width=\"128\" height=\"128\" rx=\"28\" fill=\"#141218\"/>
    <path d=\"M64 104q-23-6-38-26.5T11 36v-22l53-20 53 20v22q0 25-15 45.5T64 104Zm0-14q17-5.5 28.5-22t11.5-35V21L64 6 24 21v12q0 18.5 11.5 35T64 90Zm0-52Z\" fill=\"#D0BCFF\" transform=\"translate(0, 15) scale(1)\"/>
    <circle cx=\"64\" cy=\"55\" r=\"12\" fill=\"#D0BCFF\" opacity=\"0.8\"/>
</svg>"
    echo "$svg_content" | $SUDO tee "$ASSETS_DIR/$APP_NAME.svg" >/dev/null
    echo "$svg_content" | $SUDO tee "$ASSETS_DIR/icon.svg" >/dev/null
}

download_remote_assets() {
    log_info "Downloading remote assets..."
    $SUDO mkdir -p "$ASSETS_DIR"
    
    if [ -f "$ASSETS_DIR/gs.css" ] && [ -f "$ASSETS_DIR/cc.css" ] && [ -f "$ASSETS_DIR/ms.css" ]; then
        log_info "Remote assets already present."
        return 0
    fi

    log_info "Downloading remote assets using proxy on octet ${FOUND_OCTET:-unknown}..."
    local proxy="http://172.${FOUND_OCTET:-20}.0.254:8888"
    local ua="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    local proxy_ready=false
    if [ "${MOCK_VERIFICATION:-false}" = "true" ]; then
        proxy_ready=true
        proxy=""
    else
        log_info "Waiting for Gluetun proxy to stabilize..."
        for i in {1..30}; do
            if curl --proxy "$proxy" -fsSL --max-time 2 https://fontlay.com -o /dev/null >/dev/null 2>&1; then
                proxy_ready=true
                break
            fi
            [ $((i % 5)) -eq 0 ] && log_info "Retrying proxy connection ($i/30)..."
            sleep 1
        done
    fi

    if [ "$proxy_ready" = false ]; then
        log_crit "Gluetun proxy not responding. Asset download aborted."
        return 1
    fi

    URL_GS="https://fontlay.com/css2?family=Google+Sans+Flex:wght@400;500;600;700&display=swap"
    URL_CC="https://fontlay.com/css2?family=Cascadia+Code:ital,wght@0,200..700;1,200..700&display=swap"
    URL_MS="https://fontlay.com/css2?family=Material+Symbols+Rounded:opsz,wght,FILL,GRAD@20..48,100..700,0..1,-50..200&display=swap"

    download_asset() {
        local dest="$1"
        local url="$2"
        local curl_args=(-fsSL --max-time 10 -A "$ua")
        if [ -n "$proxy" ]; then curl_args+=("--proxy" "$proxy"); fi
        for i in {1..3}; do
            if curl "${curl_args[@]}" "$url" -o "$dest"; then
                return 0
            fi
            log_warn "Retrying download ($i/3): $url"
            sleep 1
        done
        return 1
    }

    css_origin() {
        echo "$1" | sed -E 's#(https?://[^/]+).*#\1#'
    }

    log_info "Downloading fonts..."
    download_asset "$ASSETS_DIR/gs.css" "$URL_GS"
    download_asset "$ASSETS_DIR/cc.css" "$URL_CC"
    download_asset "$ASSETS_DIR/ms.css" "$URL_MS"

    log_info "Downloading libraries..."
    local mcu_url="https://cdn.jsdelivr.net/npm/@material/material-color-utilities@0.3.0/+esm"
    local qr_url="https://cdn.jsdelivr.net/npm/qrcode@1.4.4/build/qrcode.min.js"
    
    download_asset "$ASSETS_DIR/mcu.js" "$mcu_url"
    download_asset "$ASSETS_DIR/qrcode.min.js" "$qr_url"

    cd "$ASSETS_DIR"
    declare -A ORIGINS
    ORIGINS[gs.css]=$(css_origin "$URL_GS")
    ORIGINS[cc.css]=$(css_origin "$URL_CC")
    ORIGINS[ms.css]=$(css_origin "$URL_MS")

    for css_file in gs.css cc.css ms.css; do
        if [ ! -s "$css_file" ]; then continue; fi
        local origin="${ORIGINS[$css_file]}"
        grep -o 'url([^)]*)' "$css_file" | sed 's/url(//;s/)//' | tr -d "'\"" | sort | uniq | while read -r url; do
            [ -z "$url" ] && continue
            local filename=$(basename "$url")
            local clean_name="${filename%%	*}"
            if [ ! -f "$clean_name" ]; then
                local fetch_url="$url"
                if [[ "$url" == //* ]]; then fetch_url="https:$url"
                elif [[ "$url" == /* ]]; then fetch_url="${origin}${url}"
                elif [[ "$url" != http* ]]; then fetch_url="${origin}/${url}"; fi
                download_asset "$clean_name" "$fetch_url"
            fi
            sed -i "s|url(['\"]\{0,1\}$url['\"]\{0,1\})|url($clean_name)|g" "$css_file"
        done
    done
    cd - >/dev/null
}

setup_configs() {
    log_info "Compiling Infrastructure Configs..."
    touch "$HISTORY_LOG" "$ACTIVE_WG_CONF" "$BASE_DIR/.data_usage" "$BASE_DIR/.wge_data_usage"
    if [ ! -f "$ACTIVE_PROFILE_NAME_FILE" ]; then echo "Initial-Setup" | $SUDO tee "$ACTIVE_PROFILE_NAME_FILE" >/dev/null; fi
    $SUDO chmod 644 "$ACTIVE_PROFILE_NAME_FILE" "$HISTORY_LOG" "$BASE_DIR/.data_usage" "$BASE_DIR/.wge_data_usage"

    DNS_SERVER_NAME="$LAN_IP"
    if [ -n "$DESEC_DOMAIN" ] && [ -n "$DESEC_TOKEN" ]; then
        log_info "Configuring deSEC and LE..."
        DESEC_RESPONSE=$(curl -s --max-time 5 -X PATCH "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/" \
            -H "Authorization: Token $DESEC_TOKEN" -H "Content-Type: application/json" \
            -d "[{\"subname\": \"\", \"ttl\": 3600, \"type\": \"A\", \"records\": [\"$PUBLIC_IP\"]}, {\"subname\": \"*\", \"ttl\": 3600, \"type\": \"A\", \"records\": [\"$PUBLIC_IP\"]}]" 2>&1 || echo "CURL_ERROR")
        
        if [ "$DESEC_RESPONSE" = "CURL_ERROR" ]; then log_warn "deSEC API failed"; fi
        
        mkdir -p "$AGH_CONF_DIR/certbot"
        SKIP_CERT_REQ=false
        if [ -f "$AGH_CONF_DIR/ssl.crt" ] && [ -f "$AGH_CONF_DIR/ssl.key" ]; then
            if $DOCKER_CMD run --rm -v "$AGH_CONF_DIR:/certs" neilpang/acme.sh:latest /bin/sh -c "openssl x509 -in /certs/ssl.crt -checkend 2592000 -noout" >/dev/null 2>&1; then
                SKIP_CERT_REQ=true
            fi
        fi

        if [ "$SKIP_CERT_REQ" = false ]; then
            if [ "${MOCK_VERIFICATION:-false}" = "true" ]; then
                log_info "Mock verification enabled: Skipping real LE cert request."
                $DOCKER_CMD run --rm -v "$AGH_CONF_DIR:/certs" neilpang/acme.sh:latest /bin/sh -c "openssl req -x509 -newkey rsa:2048 -sha256 -days 1 -nodes -keyout /certs/ssl.key -out /certs/ssl.crt -subj '/CN=$DESEC_DOMAIN'" >/dev/null 2>&1
            else
                log_info "Requesting LE cert..."
                $DOCKER_CMD run --rm -v "$AGH_CONF_DIR:/acme" -e "DESEC_Token=$DESEC_TOKEN" -e "DESEC_DOMAIN=$DESEC_DOMAIN" \
                    neilpang/acme.sh:latest --issue --dns dns_desec --dnssleep 10 -d "$DESEC_DOMAIN" -d "*.$DESEC_DOMAIN" \
                    --keylength ec-256 --server letsencrypt --home /acme --config-home /acme --cert-home /acme/certs > /dev/null 2>&1
                
                if [ -f "$AGH_CONF_DIR/certs/${DESEC_DOMAIN}_ecc/fullchain.cer" ]; then
                    cp "$AGH_CONF_DIR/certs/${DESEC_DOMAIN}_ecc/fullchain.cer" "$AGH_CONF_DIR/ssl.crt"
                    cp "$AGH_CONF_DIR/certs/${DESEC_DOMAIN}_ecc/${DESEC_DOMAIN}.key" "$AGH_CONF_DIR/ssl.key"
                else
                    log_warn "LE failed, generating self-signed..."
                    $DOCKER_CMD run --rm -v "$AGH_CONF_DIR:/certs" neilpang/acme.sh:latest /bin/sh -c "openssl req -x509 -newkey rsa:4096 -sha256 -days 365 -nodes -keyout /certs/ssl.key -out /certs/ssl.crt -subj '/CN=$DESEC_DOMAIN'" >/dev/null 2>&1
                fi
            fi
        fi
        DNS_SERVER_NAME="$DESEC_DOMAIN"
    else
        log_info "Generating self-signed cert..."
        $DOCKER_CMD run --rm -v "$AGH_CONF_DIR:/certs" neilpang/acme.sh:latest /bin/sh -c "openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes -keyout /certs/ssl.key -out /certs/ssl.crt -subj '/CN=$LAN_IP'" >/dev/null 2>&1
    fi

    UNBOUND_STATIC_IP="172.${FOUND_OCTET}.0.250"
    $SUDO mkdir -p "$(dirname "$UNBOUND_CONF")" "$(dirname "$NGINX_CONF")" "$AGH_CONF_DIR" "$DATA_DIR/hub-api"
    $SUDO chown -R 1000:1000 "$DATA_DIR/hub-api"

    cat <<UNBOUNDEOF | $SUDO tee "$UNBOUND_CONF" >/dev/null
server:
  interface: 0.0.0.0
  port: 53
  access-control: 0.0.0.0/0 refuse
  access-control: 172.16.0.0/12 allow
  access-control: 192.168.0.0/16 allow
  access-control: 10.0.0.0/8 allow
  auto-trust-anchor-file: "/var/unbound/root.key"

  # Privacy & Security Settings (RFC Compliance)
  qname-minimisation: yes          # RFC 7816: Minimize data leakage
  aggressive-nsec: yes             # RFC 8198: Aggressive Caching
  use-caps-for-id: yes             # DNS 0x20: Case randomization
  hide-identity: yes               # Fingerprint Resistance
  hide-version: yes                # Fingerprint Resistance
  prefetch: yes                    # Cache Prefetching
  rrset-roundrobin: yes            # RFC 1794: Load balancing
  minimal-responses: yes           # RFC 4472: Data minimization
  harden-glue: yes                 # RFC 1034: Poison protection
  harden-dnssec-stripped: yes      # DNSSEC Stripping protection
  harden-algo-downgrade: yes       # Downgrade protection
  harden-large-queries: yes        # DoS protection
  harden-short-bufsize: yes        # DoS protection
UNBOUNDEOF

    cat <<EOF | $SUDO tee "$AGH_YAML" >/dev/null
schema_version: 29
http: {address: 0.0.0.0:$PORT_ADGUARD_WEB}
users: [{name: $AGH_USER, password: $AGH_PASS_HASH}]
dns:
  upstream_dns: ["$UNBOUND_STATIC_IP"]
  bootstrap_dns: ["$UNBOUND_STATIC_IP"]
filters:
  - enabled: true
    url: https://raw.githubusercontent.com/Lyceris-chan/dns-blocklist-generator/main/blocklist.txt
    name: Sleepy Blocklist
    id: 1
filters_update_interval: 6
tls:
  enabled: true
  server_name: $DNS_SERVER_NAME
  certificate_path: /opt/adguardhome/conf/ssl.crt
  private_key_path: /opt/adguardhome/conf/ssl.key
user_rules:
$(if [ "$ALLOW_PROTON_VPN" = true ]; then
    echo "  - @@||getproton.me^"
    echo "  - @@||vpn-api.proton.me^"
    echo "  - @@||protonstatus.com^"
    echo "  - @@||protonvpn.ch^"
    echo "  - @@||protonvpn.com^"
    echo "  - @@||protonvpn.net^"
fi)
EOF

    NGINX_REDIRECT=""
    if [ -n "$DESEC_DOMAIN" ]; then
        NGINX_REDIRECT="if (\$http_x_forwarded_proto != 'https') { return 301 https://\$host:8443\$request_uri; }"
    fi

    cat <<EOF | $SUDO tee "$NGINX_CONF" >/dev/null
error_log /dev/stderr info;
access_log /dev/stdout;
set_real_ip_from 172.${FOUND_OCTET}.0.0/16;
real_ip_header X-Forwarded-For;
real_ip_recursive on;
map \$http_host \$backend {
    hostnames;
    default "";
    invidious.$DESEC_DOMAIN  http://${CONTAINER_PREFIX}gluetun:3000;
    redlib.$DESEC_DOMAIN     http://${CONTAINER_PREFIX}gluetun:8081;
    wikiless.$DESEC_DOMAIN   http://${CONTAINER_PREFIX}gluetun:8180;
    memos.$DESEC_DOMAIN      http://${CONTAINER_PREFIX}memos:5230;
    adguard.$DESEC_DOMAIN    http://${CONTAINER_PREFIX}adguard:8083;
}
server {
    listen $PORT_DASHBOARD_WEB;
    listen 8443 ssl;
    ssl_certificate /etc/adguard/conf/ssl.crt;
    ssl_certificate_key /etc/adguard/conf/ssl.key;
    location / {
        $NGINX_REDIRECT
        proxy_set_header Host \$host;
        if (\$backend != "") { proxy_pass \$backend; break; }
        root /usr/share/nginx/html;
        index index.html;
    }
    location /api/ {
        proxy_pass http://hub-api:55555/;
    }
}
EOF

    generate_libredirect_export

    # Generate Service Environment Files
    $SUDO mkdir -p "$ENV_DIR"
    cat <<EOF | $SUDO tee "$ENV_DIR/scribe.env" >/dev/null
SECRET_KEY_BASE=$SCRIBE_SECRET
GITHUB_USER=$SCRIBE_GH_USER
GITHUB_TOKEN=$SCRIBE_GH_TOKEN
PORT=8280
APP_DOMAIN=$LAN_IP:8280
EOF

    cat <<EOF | $SUDO tee "$ENV_DIR/anonymousoverflow.env" >/dev/null
APP_SECRET=$ANONYMOUS_SECRET
JWT_SIGNING_SECRET=$ANONYMOUS_SECRET
PORT=8480
APP_URL=http://$LAN_IP:8480
EOF
    $SUDO chmod 600 "$ENV_DIR/scribe.env" "$ENV_DIR/anonymousoverflow.env"

    # Generate SearXNG Config
    $SUDO mkdir -p "$CONFIG_DIR/searxng"
    cat <<EOF | $SUDO tee "$CONFIG_DIR/searxng/settings.yml" >/dev/null
use_default_settings: true
server:
  secret_key: "$SEARXNG_SECRET"
  base_url: "http://$LAN_IP:8082/"
  image_proxy: true
search:
  safe_search: 0
  autocomplete: ""
EOF
    $SUDO chmod 644 "$CONFIG_DIR/searxng/settings.yml"
}

generate_libredirect_export() {
    if [ -z "$DESEC_DOMAIN" ] || [ ! -f "$AGH_CONF_DIR/ssl.crt" ]; then return 0; fi
    local export_file="$BASE_DIR/libredirect_import.json"
    local template_file="$SCRIPT_DIR/lib/templates/libredirect_template.json"
    [ ! -f "$template_file" ] && return 0

    local host="$DESEC_DOMAIN"
    local port=":8443"
    jq --arg inv "https://invidious.${host}${port}" \
       --arg red "https://redlib.${host}${port}" \
       --arg wiki "https://wikiless.${host}${port}" \
       '.invidious = [$inv] | .redlib = [$red] | .wikiless = [$wiki] | .youtube.enabled = true | .reddit.enabled = true | .wikipedia.enabled = true' \
       "$template_file" > "$export_file"
}