
# --- SECTION 11: SOURCE REPOSITORY SYNCHRONIZATION ---
# Initialize or update external source code for locally-built application containers.

sync_sources() {
    log_info "Synchronizing Source Repositories..."
    
    clone_repo() { 
        if [ ! -d "$2/.git" ]; then 
            $SUDO mkdir -p "$2"
            $SUDO chown "$(whoami)" "$2"
            git clone --depth 1 "$1" "$2"
        else 
            (cd "$2" && git fetch --all && git reset --hard "origin/$(git rev-parse --abbrev-ref HEAD)" && git pull)
        fi
    }

    # Clone repositories containing the Dockerfiles
    # Note: For some services, we clone the docker-packaging repo instead of the source repo
    # to adhere to "modify upstream Dockerfiles" rather than creating our own.
    
    clone_repo "https://github.com/Metastem/Wikiless" "$SRC_DIR/wikiless"
    clone_repo "https://git.sr.ht/~edwardloveall/scribe" "$SRC_DIR/scribe"
    clone_repo "https://github.com/iv-org/invidious.git" "$SRC_DIR/invidious"
    clone_repo "https://github.com/Lyceris-chan/odido-bundle-booster.git" "$SRC_DIR/odido-bundle-booster"
    clone_repo "https://github.com/VERT-sh/VERT.git" "$SRC_DIR/vert"
    clone_repo "https://github.com/VERT-sh/vertd.git" "$SRC_DIR/vertd"
    clone_repo "https://codeberg.org/rimgo/rimgo.git" "$SRC_DIR/rimgo"
    clone_repo "https://github.com/PussTheCat-org/docker-breezewiki-quay.git" "$SRC_DIR/breezewiki"
    clone_repo "https://github.com/httpjamesm/AnonymousOverflow.git" "$SRC_DIR/anonymousoverflow"
    clone_repo "https://github.com/qdm12/gluetun.git" "$SRC_DIR/gluetun"
    clone_repo "https://github.com/AdguardTeam/AdGuardHome.git" "$SRC_DIR/adguardhome"
    
    # AdGuard Home custom build Dockerfile (Upstream expects pre-built binaries)
    # We remove .dockerignore because it ignores everything by default, breaking our custom build
    rm -f "$SRC_DIR/adguardhome/.dockerignore"

    cat > "$SRC_DIR/adguardhome/Dockerfile.dhi" <<'EOF'
FROM dhi.io/golang:1-alpine3.22-dev AS builder
WORKDIR /build
COPY . .
RUN apk add --no-cache nodejs npm
# Build the frontend assets
RUN cd client && npm install && npm run build-prod
# Build the binary
RUN go build -ldflags="-s -w" -o AdGuardHome main.go

FROM dhi.io/alpine-base:3.22-dev
WORKDIR /opt/adguardhome
COPY --from=builder /build/AdGuardHome /opt/adguardhome/AdGuardHome
RUN apk add --no-cache libcap tzdata
RUN setcap 'cap_net_bind_service=+eip' /opt/adguardhome/AdGuardHome
    EXPOSE 53/udp 53/tcp 80/tcp 443/tcp 443/udp 3000/tcp 853/tcp 853/udp
    CMD ["/opt/adguardhome/AdGuardHome", "--work-dir", "/opt/adguardhome/work", "--config", "/opt/adguardhome/conf/AdGuardHome.yaml", "--no-check-update"]
EOF
    clone_repo "https://github.com/klutchell/unbound-docker.git" "$SRC_DIR/unbound"
    clone_repo "https://github.com/usememos/memos.git" "$SRC_DIR/memos"
    clone_repo "https://github.com/redlib-org/redlib.git" "$SRC_DIR/redlib"
    clone_repo "https://github.com/iv-org/invidious-companion.git" "$SRC_DIR/invidious-companion"
    clone_repo "https://github.com/wg-easy/wg-easy.git" "$SRC_DIR/wg-easy"
    clone_repo "https://github.com/portainer/portainer.git" "$SRC_DIR/portainer"

    PATCHES_SCRIPT="$BASE_DIR/patches.sh"

cat > "$PATCHES_SCRIPT" <<'PATCHEOF'
#!/bin/sh
SERVICE=$1
SRC_ROOT=${2:-/app/sources}

log() { echo "[PATCH] $1"; }

detect_dockerfile() {
    local repo_dir="$1"
    local preferred="${2:-}"
    if [ -n "$preferred" ] && [ -f "$repo_dir/$preferred" ]; then echo "$preferred"; return 0; fi
    # Common locations
    for f in Dockerfile.alpine Dockerfile build/linux/alpine.Dockerfile docker/Dockerfile src/branch/main/Dockerfile scripts/Dockerfile; do
        if [ -f "$repo_dir/$f" ]; then echo "$f"; return 0; fi
    done
    # Fallback search
    find "$repo_dir" -maxdepth 4 -type f -name 'Dockerfile*' -not -path '*/.*' 2>/dev/null | head -n 1 | sed "s|^$repo_dir/||" || return 1
}

patch_bare() {
    local file="$1"
    local link="$2"
    [ ! -f "$file" ] && return
    log "  Patching $(basename "$file")..."
    
    # [1] Link Source
    if ! grep -q "Original:" "$file"; then
        sed -i "1s|^|# Original: $link\n|" "$file"
    fi

    # [2] Base Image (DHI/Alpine)
    # Don't replace scratch/distroless or specific builder images unless necessary
    if ! grep -q "FROM scratch" "$file" && ! grep -q "FROM .*distroless" "$file"; then
        sed -i 's|^FROM alpine:[^ ]*|FROM dhi.io/alpine-base:3.22-dev|g' "$file"
        sed -i 's|^FROM debian:[^ ]*|FROM dhi.io/alpine-base:3.22-dev|g' "$file"
        sed -i 's|^FROM ubuntu:[^ ]*|FROM dhi.io/alpine-base:3.22-dev|g' "$file"
    fi
    
    # [3] Runtimes
    sed -i 's|^FROM node:[^ ]*|FROM dhi.io/node:20-alpine3.22-dev|g' "$file"
    sed -i 's|^FROM golang:[^ ]*|FROM dhi.io/golang:1-alpine3.22-dev|g' "$file"
    sed -i 's|^FROM python:[^ ]*|FROM dhi.io/python:3.11-alpine3.22-dev|g' "$file"
    sed -i 's|^FROM rust:[^ ]*|FROM dhi.io/rust:1-alpine3.22-dev|g' "$file"
    sed -i 's|^FROM oven/bun:[^ ]*|FROM dhi.io/bun:1-alpine3.22-dev|g' "$file"

    # [4] Package Manager (apt -> apk)
    if grep -q "dhi.io/alpine-base" "$file"; then
        # Remove apt commands
        sed -i 's/apt-get update//g' "$file"
        sed -i 's/apt-get install -y --no-install-recommends/apk add --no-cache/g' "$file"
        sed -i 's/apt-get install -y/apk add --no-cache/g' "$file"
        sed -i '/rm -rf \/var\/lib\/apt\/lists/d' "$file"
        sed -i '/apt-get clean/d' "$file"
        # Fix basic package names
        sed -i 's/ libssl-dev / openssl-dev /g' "$file"
        sed -i 's/ ca-certificates / /g' "$file" # Usually included or added separately
    fi
}

# --- Service Specific Patches ---

if [ "$SERVICE" = "breezewiki" ] || [ "$SERVICE" = "all" ]; then
    D_FILE=$(detect_dockerfile "$SRC_ROOT/breezewiki" "docker/Dockerfile")
    if [ -n "$D_FILE" ]; then
        log "Patching BreezeWiki (Upstream)..."
        patch_bare "$SRC_ROOT/breezewiki/$D_FILE" "https://github.com/PussTheCat-org/docker-breezewiki-quay/blob/master/docker/Dockerfile"
        
        # Replace the Debian run block with Alpine instructions
        # Upstream uses a single RUN for apt update... git clone... raco...
        # We replace it with the Alpine equivalent.
        sed -i '/RUN apt update/,/raco req -d/c\
RUN apk add --no-cache git racket ca-certificates curl sqlite-libs fontconfig cairo libjpeg-turbo glib pango build-base libffi-dev \\ \
    && git clone --depth=1 https://gitdab.com/cadence/breezewiki.git . \\ \
    && raco pkg install --scope installation --auto --batch --no-docs html-writing json-pointer typed-ini-lib memo db html-parsing http-easy-lib' "$SRC_ROOT/breezewiki/$D_FILE"
    fi
fi

if [ "$SERVICE" = "vertd" ] || [ "$SERVICE" = "all" ]; then
    D_FILE=$(detect_dockerfile "$SRC_ROOT/vertd")
    if [ -n "$D_FILE" ]; then
        log "Patching VERTd..."
        patch_bare "$SRC_ROOT/vertd/$D_FILE" "https://github.com/VERT-sh/vertd/blob/main/Dockerfile"
        
        # Fix static build deps
        if ! grep -q "openssl-libs-static" "$SRC_ROOT/vertd/$D_FILE"; then
             sed -i '/apk add/ s/$/ openssl-dev openssl-libs-static pkgconfig/' "$SRC_ROOT/vertd/$D_FILE"
        fi
        
        # Switch runtime if no GPU
        if ! command -v nvidia-smi >/dev/null 2>&1; then
             log "  No NVIDIA GPU detected. Switching VERTd to Alpine base..."
             sed -i 's|^FROM nvidia/cuda:[^ ]*|FROM dhi.io/alpine-base:3.22-dev|g' "$SRC_ROOT/vertd/$D_FILE"
             # Replace the apt-get runtime block
             sed -i '/RUN apt-get update/,/fi/c\RUN apk add --no-cache ffmpeg ca-certificates curl' "$SRC_ROOT/vertd/$D_FILE"
        fi
    fi
fi

if [ "$SERVICE" = "companion" ] || [ "$SERVICE" = "all" ]; then
    D_FILE=$(detect_dockerfile "$SRC_ROOT/invidious-companion")
    if [ -n "$D_FILE" ]; then
        log "Patching Companion..."
        patch_bare "$SRC_ROOT/invidious-companion/$D_FILE" "https://github.com/iv-org/invidious-companion/blob/master/Dockerfile"
        # Fix stack overflow
        sed -i '/RUN .*deno task compile/i ENV RUST_MIN_STACK=16777216' "$SRC_ROOT/invidious-companion/$D_FILE"
        sed -i '/RUN .*deno task compile/i RUN rm -f deno.lock' "$SRC_ROOT/invidious-companion/$D_FILE"
    fi
fi

if [ "$SERVICE" = "gluetun" ] || [ "$SERVICE" = "all" ]; then
    D_FILE=$(detect_dockerfile "$SRC_ROOT/gluetun")
    if [ -n "$D_FILE" ]; then
        log "Patching Gluetun..."
        patch_bare "$SRC_ROOT/gluetun/$D_FILE" "https://github.com/qdm12/gluetun/blob/master/Dockerfile"
        
        # Ensure /etc/alpine-release exists for OS detection
        if grep -q "dhi.io/alpine-base" "$SRC_ROOT/gluetun/$D_FILE"; then
            sed -i '/FROM dhi.io\/alpine-base:3.22-dev/a RUN echo "3.22.0" > /etc/alpine-release' "$SRC_ROOT/gluetun/$D_FILE"
        fi

        # Simplify OpenVPN installation to avoid version mixing issues on DHI base
        # Replace the entire multi-line RUN block starting with apk add --no-cache --update -l wget
        sed -i '/RUN apk add --no-cache --update -l wget/,/mkdir \/gluetun/c\RUN apk add --no-cache --update wget openvpn iptables iptables-legacy tzdata && ln -s /usr/sbin/openvpn /usr/sbin/openvpn2.5 && ln -s /usr/sbin/openvpn /usr/sbin/openvpn2.6 && mkdir /gluetun' "$SRC_ROOT/gluetun/$D_FILE"
    fi
fi

# Apply generic patches to all others
for srv in wikiless scribe invidious odido-booster vert rimgo anonymousoverflow gluetun adguard unbound memos redlib wg-easy portainer; do
    if [ "$SERVICE" = "$srv" ] || [ "$SERVICE" = "all" ]; then
        D_PATH="$SRC_ROOT/$srv"
        if [ "$srv" = "adguard" ]; then D_PATH="$SRC_ROOT/adguardhome"; fi
        D_FILE=$(detect_dockerfile "$D_PATH")
        if [ -n "$D_FILE" ]; then
            patch_bare "$D_PATH/$D_FILE" "Upstream"
        fi
    fi
done

PATCHEOF
    chmod +x "$PATCHES_SCRIPT"

    # Hub API (Local Service)
    if [ -d "$SCRIPT_DIR/lib/hub-api" ]; then
        $SUDO cp -r "$SCRIPT_DIR/lib/hub-api" "$SRC_DIR/hub-api"
    else
        log_crit "Hub API source not found at $SCRIPT_DIR/lib/hub-api"
        exit 1
    fi

    # Apply patches after cloning
    if [ -f "$PATCHES_SCRIPT" ]; then
        log_info "Applying patches to source code..."
        sh "$PATCHES_SCRIPT" "all" "$SRC_DIR"
    fi

    $SUDO chmod -R 777 "$SRC_DIR/invidious" "$SRC_DIR/vert" "$ENV_DIR" "$CONFIG_DIR" "$WG_PROFILES_DIR"
}

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
    },
    "cobalt": {
      "name": "Cobalt",
      "description": "Powerful media downloader. Extract content from dozens of platforms with a clean, efficient interface.",
      "category": "apps",
      "order": 110,
      "url": "http://$LAN_IP:$PORT_COBALT",
      "source_url": "https://github.com/imputnet/cobalt",
      "patch_url": "https://github.com/imputnet/cobalt/blob/master/Dockerfile",
      "chips": [
        {"label": "Local Only", "icon": "lan", "variant": "tertiary"},
        {"label": "Upstream Image", "icon": "package", "variant": "secondary"}
      ]
    },
    "searxng": {
      "name": "SearXNG",
      "description": "A privacy-respecting, hackable metasearch engine that aggregates results from more than 70 search services.",
      "category": "apps",
      "order": 120,
      "url": "http://$LAN_IP:$PORT_SEARXNG",
      "source_url": "https://github.com/searxng/searxng",
      "patch_url": "https://github.com/searxng/searxng/blob/master/Dockerfile",
      "chips": [{"label": "Upstream Image", "icon": "package", "variant": "secondary"}]
    },
    "immich": {
      "name": "Immich",
      "description": "High-performance self-hosted photo and video management solution. Feature-rich alternative to mainstream cloud photo services.",
      "category": "apps",
      "order": 130,
      "url": "http://$LAN_IP:$PORT_IMMICH",
      "source_url": "https://github.com/immich-app/immich",
      "patch_url": "https://github.com/immich-app/immich/blob/main/Dockerfile",
      "chips": [{"label": "Upstream Image", "icon": "package", "variant": "secondary"}]
    }
  }
}
EOF
}

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
  qname-minimisation: yes
  aggressive-nsec: yes
  rrset-roundrobin: yes
  minimal-responses: yes
  use-caps-for-id: yes
  harden-glue: yes
  harden-dnssec-stripped: yes
  harden-algo-downgrade: yes
  harden-large-queries: yes
  harden-short-bufsize: yes
  auto-trust-anchor-file: "/var/unbound/root.key"
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
  force_https: $([ -n "$DESEC_DOMAIN" ] && echo "true" || echo "false")
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
    invidious.$DESEC_DOMAIN  http://${CONTAINER_PREFIX}gluetun:3000;
    redlib.$DESEC_DOMAIN     http://${CONTAINER_PREFIX}gluetun:8080;
    wikiless.$DESEC_DOMAIN   http://${CONTAINER_PREFIX}gluetun:8180;
    memos.$DESEC_DOMAIN      http://$LAN_IP:$PORT_MEMOS;
    rimgo.$DESEC_DOMAIN      http://${CONTAINER_PREFIX}gluetun:3002;
    scribe.$DESEC_DOMAIN     http://${CONTAINER_PREFIX}gluetun:8280;
    breezewiki.$DESEC_DOMAIN http://${CONTAINER_PREFIX}gluetun:10416;
    anonymousoverflow.$DESEC_DOMAIN http://${CONTAINER_PREFIX}gluetun:8480;
    vert.$DESEC_DOMAIN       http://${CONTAINER_PREFIX}vert:80;
    vertd.$DESEC_DOMAIN      http://${CONTAINER_PREFIX}vertd:24153;
    adguard.$DESEC_DOMAIN    http://${CONTAINER_PREFIX}adguard:8083;
    portainer.$DESEC_DOMAIN  http://${CONTAINER_PREFIX}portainer:9000;
    wireguard.$DESEC_DOMAIN  http://$LAN_IP:51821;
    odido.$DESEC_DOMAIN      http://${CONTAINER_PREFIX}odido-booster:8080;
    cobalt.$DESEC_DOMAIN     http://${CONTAINER_PREFIX}cobalt:9000;
    searxng.$DESEC_DOMAIN    http://${CONTAINER_PREFIX}gluetun:8080;
    immich.$DESEC_DOMAIN     http://${CONTAINER_PREFIX}gluetun:2283;
    
    # Handle the 8443 port in the host header
    "invidious.$DESEC_DOMAIN:8443"  http://${CONTAINER_PREFIX}gluetun:3000;
    "redlib.$DESEC_DOMAIN:8443"     http://${CONTAINER_PREFIX}gluetun:8080;
    "wikiless.$DESEC_DOMAIN:8443"   http://${CONTAINER_PREFIX}gluetun:8180;
    "memos.$DESEC_DOMAIN:8443"      http://$LAN_IP:$PORT_MEMOS;
    "rimgo.$DESEC_DOMAIN:8443"      http://${CONTAINER_PREFIX}gluetun:3002;
    "scribe.$DESEC_DOMAIN:8443"     http://${CONTAINER_PREFIX}gluetun:8280;
    "breezewiki.$DESEC_DOMAIN:8443" http://${CONTAINER_PREFIX}gluetun:10416;
    "anonymousoverflow.$DESEC_DOMAIN:8443" http://${CONTAINER_PREFIX}gluetun:8480;
    "vert.$DESEC_DOMAIN:8443"       http://${CONTAINER_PREFIX}vert:80;
    "vertd.$DESEC_DOMAIN:8443"      http://${CONTAINER_PREFIX}vertd:24153;
    "adguard.$DESEC_DOMAIN:8443"    http://${CONTAINER_PREFIX}adguard:8083;
    "portainer.$DESEC_DOMAIN:8443"  http://${CONTAINER_PREFIX}portainer:9000;
    "wireguard.$DESEC_DOMAIN:8443"  http://$LAN_IP:51821;
    "odido.$DESEC_DOMAIN:8443"      http://${CONTAINER_PREFIX}odido-booster:8080;
    "cobalt.$DESEC_DOMAIN:8443"     http://${CONTAINER_PREFIX}cobalt:9000;
    "searxng.$DESEC_DOMAIN:8443"    http://${CONTAINER_PREFIX}gluetun:8080;
    "immich.$DESEC_DOMAIN:8443"     http://${CONTAINER_PREFIX}gluetun:2283;
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
$(if [ -n "$DESEC_DOMAIN" ]; then echo "        set \$should_redirect \"\";
        if (\$http_x_forwarded_proto != \"https\") { set \$should_redirect \"R\"; }
        if (\$host ~* \"${DESEC_DOMAIN}\$\") { set \$should_redirect \"\${should_redirect}D\"; }
        if (\$server_port = \"$PORT_DASHBOARD_WEB\") { set \$should_redirect \"\${should_redirect}P\"; }
        if (\$should_redirect = \"RDP\") {
            return 301 https://\$host:8443\$request_uri;
        }" ; fi)

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
        set \$hub_upstream http://hub-api:55555;
        proxy_pass \$hub_upstream/;
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
        set \$odido_upstream http://odido-booster:8080;
        proxy_pass \$odido_upstream/;
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
    log_info "Generating LibRedirect import file from template..."
    local export_file="$BASE_DIR/libredirect_import.json"
    local template_file="$SCRIPT_DIR/lib/libredirect_template.json"

    if [ ! -f "$template_file" ]; then
        log_warn "LibRedirect template not found in lib/. Fallback to root template if available."
        local root_template
        root_template=$(ls "$SCRIPT_DIR"/libredirect-settings-*.json 2>/dev/null | head -n 1)
        if [ -n "$root_template" ]; then
            cp "$root_template" "$template_file"
            jq 'walk(if type == "object" and has("enabled") then .enabled = false else . end)' "$template_file" > "${template_file}.tmp" && mv "${template_file}.tmp" "$template_file"
        else
            log_crit "No LibRedirect template found anywhere!"
            return 1
        fi
    fi

    local proto="https"
    local host="$LAN_IP"
    local port_suffix=""
    
    if [ -n "$DESEC_DOMAIN" ]; then
        host="$DESEC_DOMAIN"
        port_suffix=":8443"
        
        # Subdomain-based URLs for Nginx proxy
        local url_invidious="${proto}://invidious.${host}${port_suffix}"
        local url_redlib="${proto}://redlib.${host}${port_suffix}"
        local url_wikiless="${proto}://wikiless.${host}${port_suffix}"
        local url_rimgo="${proto}://rimgo.${host}${port_suffix}"
        local url_scribe="${proto}://scribe.${host}${port_suffix}"
        local url_breezewiki="${proto}://breezewiki.${host}${port_suffix}"
        local url_anonoverflow="${proto}://anonymousoverflow.${host}${port_suffix}"
        local url_searxng="${proto}://searxng.${host}${port_suffix}"
    else
        # IP-based URLs (direct access)
        local url_invidious="${proto}://${host}:3000"
        local url_redlib="${proto}://${host}:8080"
        local url_wikiless="${proto}://${host}:8180"
        local url_rimgo="${proto}://${host}:3002"
        local url_scribe="${proto}://${host}:8280"
        local url_breezewiki="${proto}://${host}:8380"
        local url_anonoverflow="${proto}://${host}:8480"
        local url_searxng="${proto}://${host}:8082"
    fi

    log_info "Using template: lib/libredirect_template.json"
    # Use jq to update the template with local URLs and enable used services
    jq --arg inv "$url_invidious" \
       --arg red "$url_redlib" \
       --arg wiki "$url_wikiless" \
       --arg rim "$url_rimgo" \
       --arg scri "$url_scribe" \
       --arg breeze "$url_breezewiki" \
       --arg anon "$url_anonoverflow" \
       --arg searx "$url_searxng" \
       '.invidious = [$inv] | .youtube.enabled = true | .youtube.frontend = "invidious" |
        .redlib = [$red] | .reddit.enabled = true | .reddit.frontend = "redlib" | .reddit.instance = "custom" |
        .wikiless = [$wiki] | .wikipedia.enabled = true | .wikipedia.frontend = "wikiless" |
        .rimgo = [$rim] | .imgur.enabled = true | .imgur.frontend = "rimgo" | .imgur.instance = "custom" |
        .scribe = [$scri] | .medium.enabled = true | .medium.frontend = "scribe" |
        .breezeWiki = [$breeze] | .fandom.enabled = true | .fandom.frontend = "breezeWiki" | .fandom.instance = "custom" |
        .anonymousOverflow = [$anon] | .stackOverflow.enabled = true | .stackOverflow.frontend = "anonymousOverflow" | .stackOverflow.instance = "custom" |
        .searxng = [$searx] | .search.enabled = true | .search.frontend = "searxng" | .search.instance = "custom"' \
       "$template_file" > "$export_file"

    chmod 644 "$export_file"
    log_info "LibRedirect import file created at $export_file"
}


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
    ports: ["$LAN_IP:55555:55555"]
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
        # Check if odido should use VPN (default: true for privacy)
        # Read from theme.json if it exists, otherwise default to VPN mode
        ODIDO_VPN_MODE="true"
        if [ -f "$CONFIG_DIR/theme.json" ]; then
            ODIDO_VPN_MODE=$(grep -o '"odido_use_vpn"[[:space:]]*:[[:space:]]*\(true\|false\)' "$CONFIG_DIR/theme.json" 2>/dev/null | grep -o '\(true\|false\)' || echo "true")
        fi
        
        if [ "$ODIDO_VPN_MODE" = "true" ]; then
            # VPN mode: route through gluetun for privacy
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
    network_mode: "service:gluetun"
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
    depends_on:
      gluetun: {condition: service_healthy}
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '0.3', memory: 128M}
EOF
        else
            # Direct mode: use home IP (fallback for troubleshooting)
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
      - "$LAN_IP:$PORT_SEARXNG:$PORT_INT_SEARXNG/tcp"
      - "$LAN_IP:$PORT_IMMICH:$PORT_INT_IMMICH/tcp"
      - "$LAN_IP:8085:8080/tcp"
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
    image: nginx:${DASHBOARD_IMAGE_TAG:-1.27-alpine}
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
    command: ["-d", "-c", "/etc/unbound/unbound.conf"]
    networks:
      dhi-frontnet:
        ipv4_address: 172.$FOUND_OCTET.0.250
    volumes:
      - "$UNBOUND_CONF:/etc/unbound/unbound.conf:ro"
    healthcheck:
      test: ["CMD", "/usr/bin/drill-hc", "@127.0.0.1", "google.com"]
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
    image: redis:${REDIS_IMAGE_TAG:-7.2-alpine}
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
    image: postgres:${INVIDIOUS_DB_IMAGE_TAG:-14-alpine3.21}
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
      - PUBLIC_URL=http://${CONTAINER_PREFIX}vertd:$PORT_INT_VERTD
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
    fi

    if should_deploy "cobalt"; then
    cat >> "$COMPOSE_FILE" <<EOF
  # Cobalt: Media downloader (Local access only)
  cobalt:
    image: ghcr.io/imputnet/cobalt:7
    container_name: ${CONTAINER_PREFIX}cobalt
    networks: [dhi-frontnet]
    ports: ["$LAN_IP:$PORT_COBALT:$PORT_INT_COBALT"]
    environment:
      - API_URL=http://$LAN_IP:$PORT_COBALT/
      - FRONTEND_URL=http://$LAN_IP:$PORT_COBALT/
      - COBALT_AUTO_UPDATE=false
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
    volumes:
      - $CONFIG_DIR/searxng:/etc/searxng:ro
    environment:
      - SEARXNG_SECRET=$SEARXNG_SECRET
      - BASE_URL=http://$LAN_IP:$PORT_SEARXNG/
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
      - IMMICH_MACHINE_LEARNING_URL=http://${CONTAINER_PREFIX}immich-ml:3003
      - IMMICH_CONFIG_FILE=/config/immich.json
    volumes:
      - $DATA_DIR/immich:/usr/src/app/upload
      - $CONFIG_DIR/immich:/config
    depends_on:
      immich-db: {condition: service_healthy}
      immich-redis: {condition: service_healthy}
    restart: unless-stopped

  immich-db:
    image: postgres:14-alpine
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
generate_dashboard() {
    log_info "Generating Dashboard UI from template..."

    local template="$SCRIPT_DIR/lib/templates/dashboard.html"
    local css_file="$SCRIPT_DIR/lib/templates/assets/dashboard.css"
    local js_file="$SCRIPT_DIR/lib/templates/assets/dashboard.js"

    if [ ! -f "$template" ]; then
        log_crit "Dashboard template not found at $template"
        return 1
    fi

    # Initialize dashboard file from template
    cat "$template" > "$DASHBOARD_FILE"

    # Inject CSS (Replace placeholder with file content)
    # Using a temporary file to avoid sed issues with large inclusions
    sed -i "/{{DHI_CSS}}/{
        r $css_file
        d
    }" "$DASHBOARD_FILE"

    # Inject JS (Replace placeholder with file content)
    sed -i "/{{DHI_JS}}/{
        r $js_file
        d
    }" "$DASHBOARD_FILE"

    # Perform variable substitutions
    # Note: Using | as delimiter because some variables might contain /
    sed -i "s|\$LAN_IP|$LAN_IP|g" "$DASHBOARD_FILE"
    sed -i "s|\$DESEC_DOMAIN|$DESEC_DOMAIN|g" "$DASHBOARD_FILE"
    sed -i "s|\$PORT_PORTAINER|$PORT_PORTAINER|g" "$DASHBOARD_FILE"
    sed -i "s|\$BASE_DIR|$BASE_DIR|g" "$DASHBOARD_FILE"
    sed -i "s|\$PORT_DASHBOARD_WEB|$PORT_DASHBOARD_WEB|g" "$DASHBOARD_FILE"
    sed -i "s|\$APP_NAME|$APP_NAME|g" "$DASHBOARD_FILE"
    sed -i "s|\\\${CURRENT_SLOT}|$CURRENT_SLOT|g" "$DASHBOARD_FILE"
    sed -i "s|\$CURRENT_SLOT|$CURRENT_SLOT|g" "$DASHBOARD_FILE"

    log_info "Dashboard generated successfully at $DASHBOARD_FILE"
}