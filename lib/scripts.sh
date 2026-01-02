#!/usr/bin/env bash

# --- SECTION 12: ADMINISTRATIVE CONTROL ARTIFACTS ---

generate_scripts() {
    # 1. Migrate Script
    if [ -f "$SCRIPT_DIR/lib/templates/migrate.sh" ]; then
        sed "s/__CONTAINER_PREFIX__/${CONTAINER_PREFIX}/g" "$SCRIPT_DIR/lib/templates/migrate.sh" > "$MIGRATE_SCRIPT"
        chmod +x "$MIGRATE_SCRIPT"
    else
        echo "[WARN] templates/migrate.sh not found at $SCRIPT_DIR/lib/templates/migrate.sh"
    fi

    # 2. WG Control Script
    if [ -f "$SCRIPT_DIR/lib/templates/wg_control.sh" ]; then
        sed "s/__CONTAINER_PREFIX__/${CONTAINER_PREFIX}/g; s/__ADMIN_PASS_RAW__/${ADMIN_PASS_RAW}/g" "$SCRIPT_DIR/lib/templates/wg_control.sh" > "$WG_CONTROL_SCRIPT"
        chmod +x "$WG_CONTROL_SCRIPT"
    else
        echo "[WARN] templates/wg_control.sh not found at $SCRIPT_DIR/lib/templates/wg_control.sh"
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
      "source_url": "https://github.com/iv-org/invidious",
      "patch_url": "https://github.com/iv-org/invidious/blob/master/docker/Dockerfile",
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
      "url": "http://$LAN_IP:$PORT_REDLIB",
      "source_url": "https://github.com/redlib-org/redlib",
      "patch_url": "https://github.com/redlib-org/redlib/blob/main/Dockerfile.alpine"
    },
    "wikiless": {
      "name": "Wikiless",
      "description": "A privacy-focused Wikipedia frontend. Prevents cookie-based tracking and cross-site telemetry while providing an optimized reading environment.",
      "category": "apps",
      "order": 30,
      "url": "http://$LAN_IP:$PORT_WIKILESS",
      "source_url": "https://github.com/Metastem/Wikiless",
      "patch_url": "https://github.com/Metastem/Wikiless/blob/main/Dockerfile"
    },
    "rimgo": {
      "name": "Rimgo",
      "description": "An anonymous Imgur viewer that removes telemetry and tracking scripts. Access visual content without facilitating behavioral profiling.",
      "category": "apps",
      "order": 40,
      "url": "http://$LAN_IP:$PORT_RIMGO",
      "source_url": "https://codeberg.org/rimgo/rimgo",
      "patch_url": "https://codeberg.org/rimgo/rimgo/src/branch/main/Dockerfile"
    },
    "breezewiki": {
      "name": "BreezeWiki",
      "description": "A clean interface for Fandom. Neutralizes aggressive advertising networks and tracking scripts that compromise standard browsing security.",
      "category": "apps",
      "order": 50,
      "url": "http://$LAN_IP:$PORT_BREEZEWIKI/",
      "source_url": "https://github.com/breezewiki/breezewiki",
      "patch_url": "https://github.com/PussTheCat-org/docker-breezewiki-quay/blob/master/docker/Dockerfile"
    },
    "anonymousoverflow": {
      "name": "AnonOverflow",
      "description": "A private StackOverflow interface. Facilitates information retrieval for developers without facilitating cross-site corporate surveillance.",
      "category": "apps",
      "order": 60,
      "url": "http://$LAN_IP:$PORT_ANONYMOUS",
      "source_url": "https://github.com/httpjamesm/AnonymousOverflow",
      "patch_url": "https://github.com/httpjamesm/AnonymousOverflow/blob/main/Dockerfile"
    },
    "scribe": {
      "name": "Scribe",
      "description": "An alternative Medium frontend. Bypasses paywalls and eliminates tracking scripts to provide direct access to long-form content.",
      "category": "apps",
      "order": 70,
      "url": "http://$LAN_IP:$PORT_SCRIBE",
      "source_url": "https://git.sr.ht/~edwardloveall/scribe",
      "patch_url": "https://git.sr.ht/~edwardloveall/scribe"
    },
    "memos": {
      "name": "Memos",
      "description": "A private notes and knowledge base. Capture ideas, snippets, and personal documentation without third-party tracking.",
      "category": "apps",
      "order": 80,
      "url": "http://$LAN_IP:$PORT_MEMOS",
      "source_url": "https://github.com/usememos/memos",
      "patch_url": "https://github.com/usememos/memos/blob/main/scripts/Dockerfile",
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
    "companion": {
      "name": "Invidious Companion",
      "description": "A helper service for Invidious that facilitates enhanced video retrieval and bypasses certain platform-specific limitations.",
      "category": "apps",
      "order": 100,
      "url": "http://$LAN_IP:$PORT_COMPANION",
      "source_url": "https://github.com/iv-org/invidious-companion",
      "patch_url": "https://github.com/iv-org/invidious-companion/blob/master/Dockerfile"
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
    "unbound": {
      "name": "Unbound",
      "description": "A validating, recursive, caching DNS resolver. Ensures that your DNS queries are resolved independently and securely.",
      "category": "system",
      "order": 15,
      "url": "#",
      "source_url": "https://github.com/NLnetLabs/unbound",
      "patch_url": "https://github.com/klutchell/unbound-docker/blob/main/Dockerfile"
    },
    "portainer": {
      "name": "Portainer",
      "description": "A comprehensive management interface for the Docker environment. Facilitates granular control over container orchestration and infrastructure lifecycle management.",
      "category": "system",
      "order": 20,
      "url": "http://$LAN_IP:$PORT_PORTAINER",
      "source_url": "https://github.com/portainer/portainer",
      "patch_url": "https://github.com/portainer/portainer/blob/develop/build/linux/alpine.Dockerfile",
      "chips": [{"label": "Local Access", "icon": "lan", "variant": "tertiary"}]
    },
    "wg-easy": {
      "name": "WireGuard",
      "description": "The primary gateway for secure remote access. Provides a cryptographically sound tunnel to your home network, maintaining your privacy boundary on external networks.",
      "category": "system",
      "order": 30,
      "url": "http://$LAN_IP:$PORT_WG_WEB",
      "source_url": "https://github.com/wg-easy/wg-easy",
      "patch_url": "https://github.com/wg-easy/wg-easy/blob/master/Dockerfile",
      "chips": [{"label": "Local Access", "icon": "lan", "variant": "tertiary"}]
    },
    "hub-api": {
      "name": "Hub API",
      "description": "The central orchestration and management API for the Privacy Hub. Handles service lifecycles, metrics, and security policies.",
      "category": "system",
      "order": 40,
      "url": "http://$LAN_IP:$PORT_DASHBOARD_WEB/api/status",
      "source_url": "https://github.com/Lyceris-chan/selfhost-stack"
    },
    "vertd": {
      "name": "VERTd",
      "description": "The background daemon for the VERT file conversion service. Handles intensive processing tasks and hardware acceleration logic.",
      "category": "system",
      "order": 50,
      "url": "http://$LAN_IP:$PORT_VERTD/api/v1/health",
      "source_url": "https://github.com/VERT-sh/vertd",
      "patch_url": "https://github.com/VERT-sh/vertd/blob/main/Dockerfile"
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
}