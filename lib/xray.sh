#!/usr/bin/env bash

# --- XRAY / VLESS INTEGRATION ---

setup_xray() {
    if [ "$ENABLE_XRAY" != "true" ]; then return; fi
    log_info "Setting up Xray (VLESS) configuration..."

    mkdir -p "$CONFIG_DIR/xray"
    
    local xray_config="$CONFIG_DIR/xray/config.json"
    local uuid="${XRAY_UUID:-$(cat /proc/sys/kernel/random/uuid)}"
    local domain="${XRAY_DOMAIN:-$DESEC_DOMAIN}"
    
    if [ -z "$domain" ]; then
        log_warn "XRAY_DOMAIN is not set and DESEC_DOMAIN is empty. Xray might not work properly."
        domain="your-domain.com"
    fi

    # Generate a simple VLESS + TLS config
    # Note: For Russia, Reality is better, but requires more complex setup (dest, serverNames).
    # We'll start with a robust VLESS-TLS setup.
    cat > "$xray_config" <<EOF
{
    "log": {
        "loglevel": "warning"
    },
    "inbounds": [
        {
            "port": 443,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "$uuid",
                        "level": 0,
                        "email": "friend@dhi.io"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "tls",
                "tlsSettings": {
                    "certificates": [
                        {
                            "certificateFile": "/etc/adguard/conf/ssl.crt",
                            "keyFile": "/etc/adguard/conf/ssl.key"
                        }
                    ]
                }
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "settings": {}
        }
    ]
}
EOF
    # Note: We mount AdGuard SSL certs which are already managed by our pipeline
    
    log_info "Xray config generated with UUID: $uuid"
    
    # Save UUID for later use if it was generated
    if [ -z "${XRAY_UUID:-}" ]; then
        echo "XRAY_UUID=$uuid" >> "$SECRETS_FILE"
        export XRAY_UUID="$uuid"
    fi
}

patch_compose_xray() {
    if [ "$ENABLE_XRAY" != "true" ]; then return; fi
    log_info "Patching docker-compose.yml for Xray..."

    # 1. Add port 443 to gluetun
    # We look for the gluetun container definition and add the port to its ports list
    if ! grep -q "443:443" "$COMPOSE_FILE"; then
        # Use a more robust way to insert after the ports line in the gluetun block
        sed -i "/container_name: ${CONTAINER_PREFIX}gluetun/,/ports:/ { /ports:/ a\      - \"$LAN_IP:443:443\"
        }" "$COMPOSE_FILE"
    fi

    # 2. Append xray service
    if ! grep -q "container_name: ${CONTAINER_PREFIX}xray" "$COMPOSE_FILE"; then
        cat >> "$COMPOSE_FILE" <<EOF

  xray:
    image: teddysun/xray:latest
    container_name: ${CONTAINER_PREFIX}xray
    network_mode: "container:${CONTAINER_PREFIX}gluetun"
    volumes:
      - "$CONFIG_DIR/xray:/etc/xray"
      - "$AGH_CONF_DIR:/etc/adguard/conf:ro"
    restart: unless-stopped
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF
    fi
}

generate_xray_readme() {
    if [ "$ENABLE_XRAY" != "true" ]; then return; fi
    local xray_readme="$REPO_ROOT/README_XRAY.md"
    
    cat > "$xray_readme" <<EOF
# Xray (VLESS) Setup Instructions

This system is configured to host a VLESS tunnel that routes all traffic through your home VPN (Gluetun). This allows friends in restricted regions (like Russia) to connect via a domain that is not blocked and use your privacy-hardened outbound connection.

## Infrastructure Details
- **Protocol:** VLESS
- **Port:** 443 (TLS)
- **Routing:** All Xray traffic is forced through the active WireGuard profile in Gluetun.
- **Certificate:** Reuses the Let's Encrypt / deSEC certificate managed by the Privacy Hub.

## Required Action: Port Forwarding
**IMPORTANT:** You MUST forward port **443 (TCP)** on your router to this device's local IP: \`$LAN_IP\`.

## Client Configuration (for your friend)
Give these details to your friend to put in their V2Ray/Xray client (e.g., v2rayN, Shadowrocket, Nekobox):

- **Address:** \`${XRAY_DOMAIN:-$DESEC_DOMAIN}\`
- **Port:** 443
- **UUID:** \`$XRAY_UUID\`
- **Flow:** (empty)
- **Encryption:** none
- **Network:** tcp
- **Header Type:** none
- **Security:** tls
- **SNI:** \`${XRAY_DOMAIN:-$DESEC_DOMAIN}\`
- **Fingerprint:** chrome

---
*Note: This configuration is automatically generated and updated by the Privacy Hub scripts when ENABLE_XRAY=true is set.*
EOF
    log_info "Xray personal README generated at $xray_readme"
}
