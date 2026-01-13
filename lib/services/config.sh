#!/usr/bin/env bash
set -euo pipefail

# --- SECTION 12: ADMINISTRATIVE CONTROL ARTIFACTS ---

generate_scripts() {
  local vertd_devices=""
  local gpu_label="GPU Accelerated"
  local gpu_tooltip="Utilizes local GPU (/dev/dri) for high-performance conversion"
  local vertd_nvidia=""
  local tmp_merged=""

  # 1. Migrate Script
  if [[ -f "${SCRIPT_DIR}/lib/templates/migrate.sh" ]]; then
    safe_replace "${SCRIPT_DIR}/lib/templates/migrate.sh" "${MIGRATE_SCRIPT}" \
      "__CONTAINER_PREFIX__" "${CONTAINER_PREFIX}" \
      "__INVIDIOUS_DB_PASSWORD__" "${INVIDIOUS_DB_PASSWORD}" \
      "__IMMICH_DB_PASSWORD__" "${IMMICH_DB_PASSWORD}"
    chmod +x "${MIGRATE_SCRIPT}"
  else
    log_warn "templates/migrate.sh not found at ${SCRIPT_DIR}/lib/templates/migrate.sh"
  fi

  # 2. WG Control Script
  if [[ -f "${SCRIPT_DIR}/lib/templates/wg_control.sh" ]]; then
    safe_replace "${SCRIPT_DIR}/lib/templates/wg_control.sh" "${WG_CONTROL_SCRIPT}" \
      "__CONTAINER_PREFIX__" "${CONTAINER_PREFIX}" \
      "__ADMIN_PASS_RAW__" "${ADMIN_PASS_RAW}"
    chmod +x "${WG_CONTROL_SCRIPT}"
  else
    log_warn "templates/wg_control.sh not found at ${SCRIPT_DIR}/lib/templates/wg_control.sh"
  fi

  # 3. Certificate Monitor Script
  cat > "${CERT_MONITOR_SCRIPT}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
# Auto-generated certificate monitor
readonly AGH_CONF_DIR="${AGH_CONF_DIR}"
readonly DESEC_TOKEN="${DESEC_TOKEN}"
readonly DESEC_DOMAIN="${DESEC_DOMAIN}"
readonly DOCKER_CMD="${DOCKER_CMD}"

if [[ -z "\${DESEC_DOMAIN}" ]]; then
  echo "No domain configured. Skipping certificate check."
  exit 0
fi

echo "Starting certificate renewal check for \${DESEC_DOMAIN}..."

\${DOCKER_CMD} run --rm \
  -v "\${AGH_CONF_DIR}:/acme" \
  -e "DESEC_Token=\${DESEC_TOKEN}" \
  neilpang/acme.sh:latest --cron --home /acme --config-home /acme --cert-home /acme/certs

if [[ \$? -eq 0 ]]; then
  echo "Certificate check completed successfully."
  \${DOCKER_CMD} restart ${CONTAINER_PREFIX}dashboard ${CONTAINER_PREFIX}adguard 2>/dev/null || true
else
  echo "Certificate check failed."
fi
EOF
  chmod +x "${CERT_MONITOR_SCRIPT}"

  # 5. Hardware & Services Configuration
  if [[ -d "/dev/dri" ]]; then
    vertd_devices="    devices:
      - /dev/dri"
    if [[ -d "/dev/vulkan" ]]; then
      vertd_devices="${vertd_devices}
      - /dev/vulkan"
    fi

    if grep -iq "intel" /sys/class/drm/card*/device/vendor 2>/dev/null || (command -v lspci >/dev/null 2>&1 && lspci 2>/dev/null | grep -iq "intel.*graphics"); then
      gpu_label="Intel Quick Sync"
      gpu_tooltip="Utilizes Intel Quick Sync Video (QSV) for hardware acceleration."
    elif grep -iq "1002" /sys/class/drm/card*/device/vendor 2>/dev/null || (command -v lspci >/dev/null 2>&1 && lspci 2>/dev/null | grep -iq "amd.*graphics"); then
      gpu_label="AMD VA-API"
      gpu_tooltip="Utilizes AMD VA-API hardware acceleration."
    fi
  fi

  if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
    vertd_nvidia="    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]"
    gpu_label="NVIDIA NVENC"
    gpu_tooltip="Utilizes NVIDIA NVENC/NVDEC hardware acceleration."
  fi

  if [[ ! -f "${CONFIG_DIR}/theme.json" ]]; then
    echo "{}" | "${SUDO}" tee "${CONFIG_DIR}/theme.json" >/dev/null
  fi
  "${SUDO}" chmod 644 "${CONFIG_DIR}/theme.json"
  
  readonly SERVICES_JSON="${CONFIG_DIR}/services.json"
  readonly CUSTOM_SERVICES_JSON="${PROJECT_ROOT}/custom_services.json"

  cat > "${SERVICES_JSON}" <<EOF
{
  "services": {
    "anonymousoverflow": {
      "name": "AnonOverflow",
      "description": "A private StackOverflow interface.",
      "category": "apps",
      "order": 10,
      "url": "http://${LAN_IP}:${PORT_ANONYMOUS}",
      "source_url": "https://github.com/httpjamesm/AnonymousOverflow"
    },
    "breezewiki": {
      "name": "BreezeWiki",
      "description": "A clean interface for Fandom.",
      "category": "apps",
      "order": 20,
      "url": "http://${LAN_IP}:${PORT_BREEZEWIKI}/",
      "source_url": "https://github.com/breezewiki/breezewiki"
    },
    "invidious": {
      "name": "Invidious",
      "description": "A privacy-respecting YouTube frontend.",
      "category": "apps",
      "order": 50,
      "url": "http://${LAN_IP}:${PORT_INVIDIOUS}",
      "source_url": "https://github.com/iv-org/invidious"
    },
    "adguard": {
      "name": "AdGuard Home",
      "description": "Network-wide advertisement and tracker filtration.",
      "category": "system",
      "order": 10,
      "url": "http://${LAN_IP}:${PORT_ADGUARD_WEB}",
      "source_url": "https://github.com/AdguardTeam/AdGuardHome"
    },
    "unbound": {
      "name": "Unbound",
      "description": "A validating, recursive, caching DNS resolver.",
      "category": "system",
      "order": 40,
      "url": "#",
      "source_url": "https://github.com/NLnetLabs/unbound"
    }
  }
}
EOF

  if [[ -f "${CUSTOM_SERVICES_JSON}" ]]; then
    log_info "Integrating custom services from custom_services.json..."
    if tmp_merged=$(mktemp) && jq -s '.[0].services * .[1].services | {services: .}' "${SERVICES_JSON}" "${CUSTOM_SERVICES_JSON}" > "${tmp_merged}"; then
      mv "${tmp_merged}" "${SERVICES_JSON}"
      log_info "Custom services successfully integrated."
    else
      log_warn "Failed to merge custom_services.json."
      [[ -f "${tmp_merged:-}" ]] && rm "${tmp_merged}"
    fi
  fi
}

setup_static_assets() {
  log_info "Initializing local asset directories and icons..."
  local svg_content=""
  "${SUDO}" mkdir -p "${ASSETS_DIR}"
  svg_content="<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 128 128\">
    <rect width=\"128\" height=\"128\" rx=\"28\" fill=\"#141218\"/>
    <path d=\"M64 104q-23-6-38-26.5T11 36v-22l53-20 53 20v22q0 25-15 45.5T64 104Zm0-14q17-5.5 28.5-22t11.5-35V21L64 6 24 21v12q0 18.5 11.5 35T64 90Zm0-52Z\" fill=\"#D0BCFF\"/>
</svg>"
  echo "${svg_content}" | "${SUDO}" tee "${ASSETS_DIR}/${APP_NAME}.svg" >/dev/null
  echo "${svg_content}" | "${SUDO}" tee "${ASSETS_DIR}/icon.svg" >/dev/null
}

download_remote_assets() {
  log_info "Downloading remote assets..."
  local found_octet_val="${FOUND_OCTET:-20}"
  local proxy="http://172.${found_octet_val}.0.254:8888"
  local ua="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
  local proxy_ready=false
  local url_gs="https://fontlay.com/css2?family=Google+Sans+Flex:wght@400;500;600;700&display=swap"
  local url_cc="https://fontlay.com/css2?family=Cascadia+Code:ital,wght@0,200..700;1,200..700&display=swap"
  local url_ms="https://fontlay.com/css2?family=Material+Symbols+Rounded:opsz,wght,FILL,GRAD@20..48,100..700,0..1,-50..200&display=swap"
  local i=0

  "${SUDO}" mkdir -p "${ASSETS_DIR}"

  if [[ -f "${ASSETS_DIR}/gs.css" ]] && [[ -f "${ASSETS_DIR}/cc.css" ]] && [[ -f "${ASSETS_DIR}/ms.css" ]]; then
    log_info "Remote assets already present."
    return 0
  fi

  if [[ "${MOCK_VERIFICATION:-false}" == "true" ]]; then
    proxy_ready=true
    proxy=""
  else
    log_info "Waiting for proxy to stabilize..."
    for i in {1..30}; do
      if curl --proxy "${proxy}" -fsSL --max-time 2 https://fontlay.com -o /dev/null >/dev/null 2>&1; then
        proxy_ready=true
        break
      fi
      sleep 1
    done
  fi

  if [[ "${proxy_ready}" == "false" ]]; then
    log_crit "Proxy not responding. Asset download aborted."
    return 1
  fi

  download_asset() {
    local dest="$1"
    local url="$2"
    local curl_args=(-fsSL --max-time 10 -A "${ua}")
    local j=0
    if [[ -n "${proxy}" ]]; then
      curl_args+=("--proxy" "${proxy}")
    fi
    for j in {1..3}; do
      if curl "${curl_args[@]}" "${url}" -o "${dest}"; then
        return 0
      fi
      log_warn "Retrying download (\$j/3): \${url}"
      sleep 1
    done
    return 1
  }

  log_info "Downloading fonts..."
  download_asset "${ASSETS_DIR}/gs.css" "${url_gs}"
  download_asset "${ASSETS_DIR}/cc.css" "${url_cc}"
  download_asset "${ASSETS_DIR}/ms.css" "${url_ms}"

  log_info "Downloading libraries..."
  download_asset "${ASSETS_DIR}/mcu.js" "https://cdn.jsdelivr.net/npm/@material/material-color-utilities@0.3.0/+esm"
  download_asset "${ASSETS_DIR}/qrcode.min.js" "https://cdn.jsdelivr.net/npm/qrcode@1.4.4/build/qrcode.min.js"
}

setup_configs() {
  log_info "Compiling Infrastructure Configs..."
  local dns_server_name="${LAN_IP}"
  local found_octet_val="${FOUND_OCTET:-20}"
  local unbound_static_ip="172.${found_octet_val}.0.250"
  local nginx_redirect=""

  touch "${HISTORY_LOG}" "${ACTIVE_WG_CONF}" "${BASE_DIR}/.data_usage" "${BASE_DIR}/.wge_data_usage"
  if [[ ! -f "${ACTIVE_PROFILE_NAME_FILE}" ]]; then
    echo "Initial-Setup" | "${SUDO}" tee "${ACTIVE_PROFILE_NAME_FILE}" >/dev/null
  fi
  "${SUDO}" chmod 644 "${ACTIVE_PROFILE_NAME_FILE}" "${HISTORY_LOG}" "${BASE_DIR}/.data_usage" "${BASE_DIR}/.wge_data_usage"

  if [[ -n "${DESEC_DOMAIN}" ]] && [[ -n "${DESEC_TOKEN}" ]]; then
    log_info "Configuring deSEC..."
    local proxy="http://172.${found_octet_val}.0.254:8888"
    curl --proxy "${proxy}" -s --max-time 5 -X PATCH "https://desec.io/api/v1/domains/${DESEC_DOMAIN}/rrsets/" \
      -H "Authorization: Token ${DESEC_TOKEN}" -H "Content-Type: application/json" \
      -d "[{\"subname\": \"\", \"ttl\": 3600, \"type\": \"A\", \"records\": [\"${PUBLIC_IP}\"]}, {\"subname\": \"*\", \"ttl\": 3600, \"type\": \"A\", \"records\": [\"${PUBLIC_IP}\"]}]" > /dev/null 2>&1 || \
    curl -s --max-time 5 -X PATCH "https://desec.io/api/v1/domains/${DESEC_DOMAIN}/rrsets/" \
      -H "Authorization: Token ${DESEC_TOKEN}" -H "Content-Type: application/json" \
      -d "[{\"subname\": \"\", \"ttl\": 3600, \"type\": \"A\", \"records\": [\"${PUBLIC_IP}\"]}, {\"subname\": \"*\", \"ttl\": 3600, \"type\": \"A\", \"records\": [\"${PUBLIC_IP}\"]}]" > /dev/null 2>&1 || log_warn "deSEC API failed"

    if [[ "${MOCK_VERIFICATION:-false}" == "true" ]]; then
      "${DOCKER_CMD}" run --rm -v "${AGH_CONF_DIR}:/certs" neilpang/acme.sh:latest /bin/sh -c "openssl req -x509 -newkey rsa:2048 -sha256 -days 1 -nodes -keyout /certs/ssl.key -out /certs/ssl.crt -subj '/CN=${DESEC_DOMAIN}'" >/dev/null 2>&1
    else
      "${DOCKER_CMD}" run --rm -v "${AGH_CONF_DIR}:/acme" -e "DESEC_Token=${DESEC_TOKEN}" -e "DESEC_DOMAIN=${DESEC_DOMAIN}" \
        neilpang/acme.sh:latest --issue --dns dns_desec --dnssleep 10 -d "${DESEC_DOMAIN}" -d "*.\$DESEC_DOMAIN" \
        --keylength ec-256 --server letsencrypt --home /acme --config-home /acme --cert-home /acme/certs > /dev/null 2>&1

      if [[ -f "${AGH_CONF_DIR}/certs/${DESEC_DOMAIN}_ecc/fullchain.cer" ]]; then
        cp "${AGH_CONF_DIR}/certs/${DESEC_DOMAIN}_ecc/fullchain.cer" "${AGH_CONF_DIR}/ssl.crt"
        cp "${AGH_CONF_DIR}/certs/${DESEC_DOMAIN}_ecc/${DESEC_DOMAIN}.key" "${AGH_CONF_DIR}/ssl.key"
      else
        "${DOCKER_CMD}" run --rm -v "${AGH_CONF_DIR}:/certs" neilpang/acme.sh:latest /bin/sh -c "openssl req -x509 -newkey rsa:4096 -sha256 -days 365 -nodes -keyout /certs/ssl.key -out /certs/ssl.crt -subj '/CN=${DESEC_DOMAIN}'" >/dev/null 2>&1
      fi
    fi
    dns_server_name="${DESEC_DOMAIN}"
  else
    log_info "Generating self-signed cert..."
    "${DOCKER_CMD}" run --rm -v "${AGH_CONF_DIR}:/certs" neilpang/acme.sh:latest /bin/sh -c "openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes -keyout /certs/ssl.key -out /certs/ssl.crt -subj '/CN=${LAN_IP}'" >/dev/null 2>&1
  fi

  "${SUDO}" mkdir -p "$(dirname "${UNBOUND_CONF}")" "$(dirname "${NGINX_CONF}")" "${AGH_CONF_DIR}" "${DATA_DIR}/hub-api"
  "${SUDO}" chown -R 1000:1000 "${DATA_DIR}/hub-api"

  cat <<UNBOUNDEOF | "${SUDO}" tee "${UNBOUND_CONF}" >/dev/null
server:
  interface: 0.0.0.0
  port: 53
  access-control: 0.0.0.0/0 refuse
  access-control: 172.16.0.0/12 allow
  access-control: 192.168.0.0/16 allow
  access-control: 10.0.0.0/8 allow
  auto-trust-anchor-file: "/var/unbound/root.key"
  qname-minimisation: yes          # RFC 7816
  aggressive-nsec: yes             # RFC 8198
  use-caps-for-id: yes             # DNS 0x20
  hide-identity: yes
  hide-version: yes
  prefetch: yes
  rrset-roundrobin: yes            # RFC 1794
  minimal-responses: yes           # RFC 4472
  harden-glue: yes                 # RFC 1034
  harden-dnssec-stripped: yes
  harden-algo-downgrade: yes
  harden-large-queries: yes
  harden-short-bufsize: yes
UNBOUNDEOF

  cat <<EOF | "${SUDO}" tee "${AGH_YAML}" >/dev/null
schema_version: 29
http: {address: 0.0.0.0:${PORT_ADGUARD_WEB}}
users: [{name: "${AGH_USER}", password: "${AGH_PASS_HASH}"}]
dns:
  upstream_dns: ["${unbound_static_ip}"]
  bootstrap_dns: ["${unbound_static_ip}"]
filters:
  - enabled: true
    url: https://raw.githubusercontent.com/Lyceris-chan/dns-blocklist-generator/main/blocklist.txt
    name: Sleepy Blocklist
    id: 1
filters_update_interval: 6
tls:
  enabled: true
  server_name: "\${dns_server_name}"
  certificate_path: /opt/adguardhome/conf/ssl.crt
  private_key_path: /opt/adguardhome/conf/ssl.key
EOF

  if [[ -n "\${DESEC_DOMAIN}" ]]; then
    nginx_redirect="if (\$http_host = '\${DESEC_DOMAIN}') { return 301 https://\$host:8443\$request_uri; }"
  fi

  cat <<EOF | "${SUDO}" tee "${NGINX_CONF}" >/dev/null
error_log /dev/stderr info;
access_log /dev/stdout;
set_real_ip_from 172.\${found_octet_val}.0.0/16;
real_ip_header X-Forwarded-For;
real_ip_recursive on;
map \$http_host \$backend {
    hostnames;
    default "";
    adguard.\${DESEC_DOMAIN}    http://\${CONTAINER_PREFIX}adguard:8083;
}
server {
    listen \${PORT_DASHBOARD_WEB};
    listen 8443 ssl;
    ssl_certificate /etc/adguard/conf/ssl.crt;
    ssl_certificate_key /etc/adguard/conf/ssl.key;
    location / {
        \${nginx_redirect}
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

  "${SUDO}" mkdir -p "${ENV_DIR}"
  cat <<EOF | "${SUDO}" tee "${ENV_DIR}/scribe.env" >/dev/null
SECRET_KEY_BASE=${SCRIBE_SECRET}
GITHUB_USER=${SCRIBE_GH_USER}
GITHUB_TOKEN=${SCRIBE_GH_TOKEN}
PORT=8280
APP_DOMAIN=${LAN_IP}:8280
EOF

  cat <<EOF | "${SUDO}" tee "${ENV_DIR}/anonymousoverflow.env" >/dev/null
APP_SECRET=${ANONYMOUS_SECRET}
JWT_SIGNING_SECRET=${ANONYMOUS_SECRET}
PORT=8480
APP_URL=http://${LAN_IP}:8480
EOF
  "${SUDO}" chmod 600 "${ENV_DIR}/scribe.env" "${ENV_DIR}/anonymousoverflow.env"

  "${SUDO}" mkdir -p "${CONFIG_DIR}/searxng"
  cat <<EOF | "${SUDO}" tee "${CONFIG_DIR}/searxng/settings.yml" >/dev/null
use_default_settings: true
server:
  secret_key: "${SEARXNG_SECRET}"
  base_url: "http://${LAN_IP}:8082/"
  image_proxy: true
search:
  safe_search: 0
  autocomplete: "duckduckgo"
EOF
  "${SUDO}" chmod 644 "${CONFIG_DIR}/searxng/settings.yml"
}

generate_libredirect_export() {
  local export_file="${BASE_DIR}/libredirect_import.json"
  local template_file="${SCRIPT_DIR}/lib/templates/libredirect_template.json"
  local host=""
  local port=":8443"

  if [[ -z "${DESEC_DOMAIN:-}" ]] || [[ ! -f "${AGH_CONF_DIR}/ssl.crt" ]]; then
    return 0
  fi
  if [[ ! -f "${template_file}" ]]; then
    return 0
  fi

  host="${DESEC_DOMAIN}"
  jq --arg inv "https://invidious.\${host}\${port}" \
     --arg red "https://redlib.\${host}\${port}" \
     --arg wiki "https://wikiless.\${host}\${port}" \
     '.invidious = [\$inv] | .redlib = [\$red] | .wikiless = [\$wiki] | .youtube.enabled = true | .reddit.enabled = true | .wikipedia.enabled = true' \
     "${template_file}" > "${export_file}"
}
