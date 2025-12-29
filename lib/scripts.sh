#!/usr/bin/env bash

# --- SECTION 12: ADMINISTRATIVE CONTROL ARTIFACTS ---

generate_scripts() {
    # 1. Migrate Script
    if [ -f "templates/migrate.sh" ]; then
        sed "s/__CONTAINER_PREFIX__/${CONTAINER_PREFIX}/g" "templates/migrate.sh" > "$MIGRATE_SCRIPT"
        chmod +x "$MIGRATE_SCRIPT"
    else
        echo "[WARN] templates/migrate.sh not found."
    fi

    # 2. WG Control Script
    if [ -f "templates/wg_control.sh" ]; then
        sed "s/__CONTAINER_PREFIX__/${CONTAINER_PREFIX}/g; s/__ADMIN_PASS_RAW__/${ADMIN_PASS_RAW}/g" "templates/wg_control.sh" > "$WG_CONTROL_SCRIPT"
        chmod +x "$WG_CONTROL_SCRIPT"
    else
        echo "[WARN] templates/wg_control.sh not found."
    fi

    # 3. WG API Script
    if [ -f "templates/wg_api.py" ]; then
        sed "s/__CONTAINER_PREFIX__/${CONTAINER_PREFIX}/g; s/__APP_NAME__/${APP_NAME}/g" "templates/wg_api.py" > "$WG_API_SCRIPT"
        chmod +x "$WG_API_SCRIPT"
    else
        echo "[WARN] templates/wg_api.py not found."
    fi

    # 5. Hardware & Services Configuration
    VERTD_DEVICES=""
    GPU_LABEL="GPU Accelerated"
    GPU_TOOLTIP="Utilizes local GPU (/dev/dri) for high-performance conversion"

    # Hardware acceleration detection (Independent checks for Intel/AMD and NVIDIA)
    if [ -d "/dev/dri" ]; then
        VERTD_DEVICES="    devices:
      - /dev/dri"
        if [ -d "/dev/vulkan" ]; then
            VERTD_DEVICES="${VERTD_DEVICES}
      - /dev/vulkan"
        fi
        
        # Vendor detection for better UI labeling
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

    if [ ! -f "$CONFIG_DIR/theme.json" ]; then echo "{}" > "$CONFIG_DIR/theme.json"; fi
    chmod 666 "$CONFIG_DIR/theme.json"
    SERVICES_JSON="$CONFIG_DIR/services.json"
    cat > "$SERVICES_JSON" <<EOF
{
  "services": {
    "invidious": {
      "name": "Invidious",
      "description": "A privacy-respecting YouTube frontend. Eliminates advertisements and tracking while providing a lightweight interface without proprietary JavaScript.",
      "category": "apps",
      "order": 10,
      "url": "http://$LAN_IP:$PORT_INVIDIOUS",
      "actions": [
        {"type": "migrate", "label": "Migrate DB", "icon": "database_upload", "mode": "migrate", "confirm": true},
        {"type": "migrate", "label": "Clear Logs", "icon": "delete_sweep", "mode": "clear-logs", "confirm": false}
      ]
    },
    "redlib": {
      "name": "Redlib",
      "description": "A lightweight Reddit frontend that prioritizes privacy. Strips tracking pixels and unnecessary scripts to ensure a clean, performant browsing experience.",
      "category": "apps",
      "order": 20,
      "url": "http://$LAN_IP:$PORT_REDLIB"
    },
    "wikiless": {
      "name": "Wikiless",
      "description": "A privacy-focused Wikipedia frontend. Prevents cookie-based tracking and cross-site telemetry while providing an optimized reading environment.",
      "category": "apps",
      "order": 30,
      "url": "http://$LAN_IP:$PORT_WIKILESS"
    },
    "rimgo": {
      "name": "Rimgo",
      "description": "An anonymous Imgur viewer that removes telemetry and tracking scripts. Access visual content without facilitating behavioral profiling.",
      "category": "apps",
      "order": 40,
      "url": "http://$LAN_IP:$PORT_RIMGO"
    },
    "breezewiki": {
      "name": "BreezeWiki",
      "description": "A clean interface for Fandom. Neutralizes aggressive advertising networks and tracking scripts that compromise standard browsing security.",
      "category": "apps",
      "order": 50,
      "url": "http://$LAN_IP:$PORT_BREEZEWIKI/"
    },
    "anonymousoverflow": {
      "name": "AnonOverflow",
      "description": "A private StackOverflow interface. Facilitates information retrieval for developers without facilitating cross-site corporate surveillance.",
      "category": "apps",
      "order": 60,
      "url": "http://$LAN_IP:$PORT_ANONYMOUS"
    },
    "scribe": {
      "name": "Scribe",
      "description": "An alternative Medium frontend. Bypasses paywalls and eliminates tracking scripts to provide direct access to long-form content.",
      "category": "apps",
      "order": 70,
      "url": "http://$LAN_IP:$PORT_SCRIBE"
    },
    "memos": {
      "name": "Memos",
      "description": "A private notes and knowledge base. Capture ideas, snippets, and personal documentation without third-party tracking.",
      "category": "apps",
      "order": 80,
      "url": "http://$LAN_IP:$PORT_MEMOS",
      "actions": [
        {"type": "vacuum", "label": "Optimize DB", "icon": "compress"}
      ]
    },
    "vert": {
      "name": "VERT",
      "description": "Local file conversion service. Maintains data autonomy by processing sensitive documents on your own hardware using GPU acceleration.",
      "category": "apps",
      "order": 90,
      "url": "http://$LAN_IP:$PORT_VERT",
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
    "adguard": {
      "name": "AdGuard Home",
      "description": "Network-wide advertisement and tracker filtration. Centralizes DNS management to prevent data leakage at the source and ensure complete visibility of network traffic.",
      "category": "system",
      "order": 10,
      "url": "http://$LAN_IP:$PORT_ADGUARD_WEB",
      "actions": [
        {"type": "clear-logs", "label": "Clear Logs", "icon": "auto_delete"}
      ],
      "chips": [{"label": "Local Access", "icon": "lan", "variant": "tertiary"}, "Encrypted DNS"]
    },
    "portainer": {
      "name": "Portainer",
      "description": "A comprehensive management interface for the Docker environment. Facilitates granular control over container orchestration and infrastructure lifecycle management.",
      "category": "system",
      "order": 20,
      "url": "http://$LAN_IP:$PORT_PORTAINER",
      "chips": [{"label": "Local Access", "icon": "lan", "variant": "tertiary"}]
    },
    "wg-easy": {
      "name": "WireGuard",
      "description": "The primary gateway for secure remote access. Provides a cryptographically sound tunnel to your home network, maintaining your privacy boundary on external networks.",
      "category": "system",
      "order": 30,
      "url": "http://$LAN_IP:$PORT_WG_WEB",
      "chips": [{"label": "Local Access", "icon": "lan", "variant": "tertiary"}]
    }
  }
}
EOF
}