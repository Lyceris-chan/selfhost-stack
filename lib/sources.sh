#!/usr/bin/env bash

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
    clone_repo "https://github.com/klutchell/unbound-docker.git" "$SRC_DIR/unbound"
    clone_repo "https://github.com/usememos/memos.git" "$SRC_DIR/memos"
    clone_repo "https://github.com/redlib-org/redlib.git" "$SRC_DIR/redlib"
    clone_repo "https://github.com/iv-org/invidious-companion.git" "$SRC_DIR/invidious-companion"
    clone_repo "https://github.com/wg-easy/wg-easy.git" "$SRC_DIR/wg-easy"
    clone_repo "https://github.com/portainer/portainer.git" "$SRC_DIR/portainer"
    clone_repo "https://github.com/imputnet/cobalt.git" "$SRC_DIR/cobalt"
    clone_repo "https://github.com/searxng/searxng.git" "$SRC_DIR/searxng"
    clone_repo "https://github.com/immich-app/immich.git" "$SRC_DIR/immich"

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

# Apply generic patches to all others
for srv in wikiless scribe invidious odido-booster vert rimgo anonymousoverflow gluetun adguard unbound memos redlib wg-easy portainer cobalt searxng immich; do
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
    # Copy from repo root (priority) or create fallback if missing (dev mode)
    if [ -d "$BASE_DIR/../../hub-api" ]; then
        # When running from repo structure: data/AppData/privacy-hub/../../hub-api -> hub-api
        $SUDO cp -r "$BASE_DIR/../../hub-api" "$SRC_DIR/"
    elif [ -d "/workspaces/selfhost-stack/hub-api" ]; then
        # Codespace absolute path fallback
        $SUDO cp -r "/workspaces/selfhost-stack/hub-api" "$SRC_DIR/"
    else
        # Fallback creation (e.g. standalone script usage)
        $SUDO mkdir -p "$SRC_DIR/hub-api"
        cat > "$SRC_DIR/hub-api/Dockerfile" <<EOF
FROM dhi.io/python:3.11-alpine3.22-dev
  },
  wikimedia_useragent: process.env.wikimedia_useragent || 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36',
  cache_control: process.env.CACHE_CONTROL !== 'true' || true,
  cache_control_interval: process.env.CACHE_CONTROL_INTERVAL || 24,
}
module.exports = config
EOF

    # Apply patches after cloning
    if [ -f "$PATCHES_SCRIPT" ]; then
        log_info "Applying patches to source code..."
        sh "$PATCHES_SCRIPT" "all" "$SRC_DIR"
    fi

    $SUDO chmod -R 777 "$SRC_DIR/invidious" "$SRC_DIR/vert" "$ENV_DIR" "$CONFIG_DIR" "$WG_PROFILES_DIR"
}
