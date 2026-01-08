
# --- SECTION 11: SOURCE REPOSITORY SYNCHRONIZATION ---
# Initialize or update external source code for locally-built application containers.

sync_sources() {
    log_info "Synchronizing Source Repositories..."
    
    clone_repo() { 
        local repo_url="$1"
        local target_dir="$2"
        local version="${3:-}"
        local max_retries=3
        local attempt=1
        local delay=5

        while [ $attempt -le $max_retries ]; do
            if [ ! -d "$target_dir/.git" ]; then 
                log_info "Cloning $repo_url (Attempt $attempt/$max_retries)..."
                $SUDO mkdir -p "$target_dir"
                $SUDO chown "$(whoami)" "$target_dir"
                # If version is specified, we might not want --depth 1 if it's a specific commit
                # But for tags and branches --depth 1 usually works if it's recent
                local clone_opts="--depth 1"
                if [ -n "$version" ] && [[ "$version" != "latest" ]]; then
                    clone_opts="--branch $version --depth 1"
                fi
                
                if git clone $clone_opts "$repo_url" "$target_dir"; then
                    return 0
                fi
                
                # Fallback: if shallow clone fails with branch, try full clone and checkout
                if [ -n "$version" ] && [[ "$version" != "latest" ]]; then
                    log_warn "Shallow clone failed for $version. Trying full clone..."
                    if git clone "$repo_url" "$target_dir"; then
                        if (cd "$target_dir" && git fetch --all --tags && git checkout "$version"); then
                            return 0
                        fi
                    fi
                fi
            else 
                if [ "${FORCE_UPDATE:-false}" = "true" ]; then
                    log_info "Updating $target_dir (Attempt $attempt/$max_retries)..."
                    if (cd "$target_dir" && git fetch --all && git checkout -f "${version:-HEAD}" && git reset --hard "origin/${version:-$(git rev-parse --abbrev-ref HEAD)}" && git pull); then
                        return 0
                    fi
                else
                    log_info "Repository exists at $target_dir. Ensuring correct version ($version)..."
                    if [ -n "$version" ] && [[ "$version" != "latest" ]]; then
                        (cd "$target_dir" && git fetch --all --tags && git checkout -f "$version") || true
                    fi
                    return 0
                fi
            fi

            log_warn "Repository operation failed for $repo_url."
            if [[ "$repo_url" == *"codeberg.org"* ]]; then
                log_warn "Codeberg appears to be having issues. Check status at: https://status.codeberg.org/status/codeberg"
            fi
            log_warn "Retrying in ${delay}s..."
            sleep $delay
            attempt=$((attempt + 1))
            delay=$((delay * 2))
        done

        log_crit "Failed to sync repository $repo_url after $max_retries attempts."
        return 1
    }

    # Clone repositories containing the Dockerfiles in parallel
    # Note: For some services, we clone the docker-packaging repo instead of the source repo
    # to adhere to "modify upstream Dockerfiles" rather than creating our own.
    
    local pids=""
    
    clone_repo "https://github.com/Metastem/Wikiless" "$SRC_DIR/wikiless" "$WIKILESS_IMAGE_TAG" & pids="$pids $!"
    (
        if clone_repo "https://git.sr.ht/~edwardloveall/scribe" "$SRC_DIR/scribe" "$SCRIBE_IMAGE_TAG"; then
            cat > "$SRC_DIR/scribe/Dockerfile" <<'EOF'
# Multi-stage build for Scribe (Crystal + Lucky framework)
FROM node:16-alpine AS node_build
WORKDIR /tmp_build
COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile
COPY . .
RUN yarn prod

FROM 84codes/crystal:1.11.2-alpine AS lucky_build
# Install development libraries for static linking, fixing OpenSSL conflicts
RUN apk add --no-cache yaml-dev yaml-static zlib-dev zlib-static openssl-dev openssl-libs-static
WORKDIR /tmp_build
COPY shard.yml shard.lock ./
# Skip postinstall to avoid problematic dependencies like ameba during build
RUN shards install --production --skip-postinstall
COPY . .
# Copy generated assets from node stage for manifest loading during compilation
COPY --from=node_build /tmp_build/public ./public
RUN crystal build --release --static src/start_server.cr -o start_server
RUN crystal build --release --static tasks.cr -o run_task

FROM alpine:latest
RUN apk add --no-cache ca-certificates
WORKDIR /app
COPY --from=lucky_build /tmp_build/start_server /tmp_build/run_task ./
COPY --from=lucky_build /tmp_build/config ./config
COPY --from=node_build /tmp_build/public ./public
# Lucky framework expectations
ENV LUCKY_ENV=production
EXPOSE 8080
CMD ["./start_server"]
EOF
        else
            exit 1
        fi
    ) & pids="$pids $!"
    clone_repo "https://github.com/iv-org/invidious.git" "$SRC_DIR/invidious" "$INVIDIOUS_IMAGE_TAG" & pids="$pids $!"
    clone_repo "https://github.com/Lyceris-chan/odido-bundle-booster.git" "$SRC_DIR/odido-bundle-booster" "$ODIDO_BOOSTER_IMAGE_TAG" & pids="$pids $!"
    clone_repo "https://github.com/VERT-sh/VERT.git" "$SRC_DIR/vert" "$VERT_IMAGE_TAG" & pids="$pids $!"
    clone_repo "https://github.com/VERT-sh/vertd.git" "$SRC_DIR/vertd" "$VERTD_IMAGE_TAG" & pids="$pids $!"
    clone_repo "https://codeberg.org/rimgo/rimgo.git" "$SRC_DIR/rimgo" "$RIMGO_IMAGE_TAG" & pids="$pids $!"
    clone_repo "https://github.com/PussTheCat-org/docker-breezewiki-quay.git" "$SRC_DIR/breezewiki" "$BREEZEWIKI_IMAGE_TAG" & pids="$pids $!"
    clone_repo "https://github.com/httpjamesm/AnonymousOverflow.git" "$SRC_DIR/anonymousoverflow" "$ANONYMOUSOVERFLOW_IMAGE_TAG" & pids="$pids $!"
    clone_repo "https://github.com/qdm12/gluetun.git" "$SRC_DIR/gluetun" "$GLUETUN_IMAGE_TAG" & pids="$pids $!"
    
    (
        if clone_repo "https://github.com/AdguardTeam/AdGuardHome.git" "$SRC_DIR/adguardhome" "$ADGUARD_IMAGE_TAG"; then
            # AdGuard Home custom build Dockerfile (Upstream expects pre-built binaries)
            # We remove .dockerignore because it ignores everything by default, breaking our custom build
            rm -f "$SRC_DIR/adguardhome/.dockerignore"

            # Patch Webpack config for Webpack 5 compatibility ([hash] -> [fullhash])
            if [ -f "$SRC_DIR/adguardhome/client/webpack.prod.js" ]; then
                sed -i 's/\[hash\]/[fullhash]/g' "$SRC_DIR/adguardhome/client/webpack.prod.js"
            fi
            if [ -f "$SRC_DIR/adguardhome/client/webpack.dev.js" ]; then
                sed -i 's/\[hash\]/[fullhash]/g' "$SRC_DIR/adguardhome/client/webpack.dev.js"
            fi

            cat > "$SRC_DIR/adguardhome/Dockerfile.dhi" <<'EOF'
FROM golang:1-alpine AS builder
WORKDIR /build
COPY . .
RUN apk add --no-cache nodejs npm
# Build the frontend assets
# Force core-js update to avoid deprecation warnings and install dependencies
RUN cd client && npm install core-js@^3.30.0 --save && npm install && npm audit fix --audit-level=moderate || true && npm run build-prod
# Build the binary
RUN go build -ldflags="-s -w" -o AdGuardHome main.go

FROM alpine:3.20
WORKDIR /opt/adguardhome
COPY --from=builder /build/AdGuardHome /opt/adguardhome/AdGuardHome
RUN apk add --no-cache libcap tzdata
RUN setcap 'cap_net_bind_service=+eip' /opt/adguardhome/AdGuardHome
    EXPOSE 53/udp 53/tcp 80/tcp 443/tcp 443/udp 3000/tcp 853/tcp 853/udp
    CMD ["/opt/adguardhome/AdGuardHome", "--work-dir", "/opt/adguardhome/work", "--config", "/opt/adguardhome/conf/AdGuardHome.yaml", "--no-check-update"]
EOF
        else
            exit 1
        fi
    ) & pids="$pids $!"

    clone_repo "https://github.com/klutchell/unbound-docker.git" "$SRC_DIR/unbound" "$UNBOUND_IMAGE_TAG" & pids="$pids $!"
    clone_repo "https://github.com/usememos/memos.git" "$SRC_DIR/memos" "$MEMOS_IMAGE_TAG" & pids="$pids $!"
    clone_repo "https://github.com/redlib-org/redlib.git" "$SRC_DIR/redlib" "$REDLIB_IMAGE_TAG" & pids="$pids $!"
    clone_repo "https://github.com/iv-org/invidious-companion.git" "$SRC_DIR/invidious-companion" "$COMPANION_IMAGE_TAG" & pids="$pids $!"
    clone_repo "https://github.com/wg-easy/wg-easy.git" "$SRC_DIR/wg-easy" "$WG_EASY_IMAGE_TAG" & pids="$pids $!"
    clone_repo "https://github.com/portainer/portainer.git" "$SRC_DIR/portainer" "$PORTAINER_IMAGE_TAG" & pids="$pids $!"

    local success=true
    for pid in $pids; do
        if ! wait "$pid"; then
            success=false
        fi
    done

    if [ "$success" = false ]; then
        log_crit "One or more source repositories failed to synchronize."
        return 1
    fi

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
    
    # Create a backup before patching
    cp "$file" "${file}.bak"

    # [1] Link Source
    if ! grep -qi "Original:" "$file"; then
        # Use a more robust way to prepend to a file
        printf "# Original: %s\n%s" "$link" "$(cat "$file")" > "$file"
    fi

    # [2] Base Image (DHI/Alpine)
    # Only replace if it is already an Alpine base to ensure package manager compatibility
    # if grep -qiE "^FROM[[:space:]]+alpine:" "$file"; then
    #    sed -i -E 's/^FROM[[:space:]]+alpine:[^[:space:]]*/FROM dhi.io\/alpine-base:3.22-dev/gI' "$file"
    # fi
    
    # [2.1] Fix for EOL Debian Buster
    if grep -qi "debian:buster-slim" "$file"; then
        log "    [FIX] Upgrading legacy debian:buster-slim base to bookworm-slim..."
        sed -i 's/debian:buster-slim/debian:bookworm-slim/gI' "$file"
    fi
    
    # [3] Runtimes (Only if they are alpine-based runtimes)
    # sed -i -E 's/^FROM[[:space:]]+node:[0-9.]+-alpine[^[:space:]]*/FROM dhi.io\/node:20-alpine3.22-dev/gI' "$file"
    # sed -i -E 's/^FROM[[:space:]]+golang:[0-9.]+-alpine[^[:space:]]*/FROM dhi.io\/golang:1-alpine3.22-dev/gI' "$file"
    # sed -i -E 's/^FROM[[:space:]]+python:[0-9.]+-alpine[^[:space:]]*/FROM dhi.io\/python:3.11-alpine3.22-dev/gI' "$file"
    # sed -i -E 's/^FROM[[:space:]]+rust:[0-9.]+-alpine[^[:space:]]*/FROM dhi.io\/rust:1-alpine3.22-dev/gI' "$file"
    # sed -i -E 's/^FROM[[:space:]]+oven\/bun:[0-9.]+-alpine[^[:space:]]*/FROM dhi.io\/bun:1-alpine3.22-dev/gI' "$file"

    # [4] Package Manager (apt -> apk) - ONLY if we are sure we are on Alpine now
    if grep -qi "dhi.io/alpine-base" "$file" || grep -qiE "^FROM[[:space:]]+alpine:" "$file"; then
        # Remove apt commands if any (some multi-stage might have both)
        if grep -qi "apt-get" "$file"; then
            log "    [WARN] Detected apt-get in potentially Alpine-based image. Attempting conversion..."
            sed -i 's/apt-get[[:space:]]\+update[[:space:]]*&&[[:space:]]*//g' "$file"
            sed -i 's/apt-get[[:space:]]\+update//g' "$file"
            sed -i 's/apt-get[[:space:]]\+install[[:space:]]\+-y[[:space:]]\+--no-install-recommends/apk add --no-cache/g' "$file"
            sed -i 's/apt-get[[:space:]]\+install[[:space:]]\+-y/apk add --no-cache/g' "$file"
            sed -i '/rm[[:space:]]\+-rf[[:space:]]\+\/var\/lib\/apt\/lists/d' "$file"
            sed -i '/apt-get[[:space:]]\+clean/d' "$file"
            # Fix basic package names
            sed -i 's/[[:space:]]\+libssl-dev[[:space:]]\+/ openssl-dev /g' "$file"
            sed -i 's/[[:space:]]\+ca-certificates[[:space:]]\+/ /g' "$file"
        fi
    fi

    # Sanity check: Ensure at least one FROM line exists and no obvious corruption
    if ! grep -qi "^FROM " "$file"; then
        log "  [ERROR] Patching corrupted $(basename "$file"): No FROM line found. Rolling back."
        mv "${file}.bak" "$file"
        return 1
    fi
    rm -f "${file}.bak"
}

# --- Service Specific Patches ---

if [ "$SERVICE" = "breezewiki" ] || [ "$SERVICE" = "all" ]; then
    D_FILE=$(detect_dockerfile "$SRC_ROOT/breezewiki" "docker/Dockerfile")
    if [ -n "$D_FILE" ]; then
        log "Patching BreezeWiki (Upstream)..."
        patch_bare "$SRC_ROOT/breezewiki/$D_FILE" "https://github.com/PussTheCat-org/docker-breezewiki-quay/blob/master/docker/Dockerfile"
        
        # Replace the Debian base with Alpine
        sed -i 's|^FROM .*|FROM alpine:3.21|g' "$SRC_ROOT/breezewiki/$D_FILE"
        
        # Replace the Debian run block with Alpine instructions
        # Upstream uses a single RUN for apt update... git clone... raco...
        # We replace it with the Alpine equivalent.
        sed -i '/RUN apt update/,/raco req -d/c\
RUN apk add --no-cache git racket ca-certificates curl sqlite-libs fontconfig cairo libjpeg-turbo glib pango build-base libffi-dev \\ \
    && git clone --depth=1 https://gitdab.com/cadence/breezewiki.git . \\ \
    && raco pkg install --scope installation --auto --batch --no-docs html-writing json-pointer typed-ini-lib memo db html-parsing http-easy-lib sequence-tools-lib net-cookies-lib web-server-lib rackunit-lib' "$SRC_ROOT/breezewiki/$D_FILE"
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
             log "  No NVIDIA GPU detected. Switching VERTd to Debian-slim base..."
             sed -i 's|^FROM nvidia/cuda:[^ ]*|FROM debian:bookworm-slim|g' "$SRC_ROOT/vertd/$D_FILE"
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
        
        # Fix user creation in Alpine (add group first)
        sed -i 's/adduser -u 10001 -S appuser/addgroup -S appuser \&\& adduser -u 10001 -S -G appuser appuser/' "$SRC_ROOT/invidious-companion/$D_FILE"
        sed -i 's/useradd --uid 1993 --user-group deno/addgroup -g 1993 -S deno \&\& adduser -u 1993 -S -G deno deno/' "$SRC_ROOT/invidious-companion/$D_FILE"

        # Fix dpkg dependency in Alpine
        sed -i "s@dpkg --print-architecture@uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/'@" "$SRC_ROOT/invidious-companion/$D_FILE"

        # Use denoland/deno:alpine as the base for builder stages
        sed -i 's|^FROM debian:.* AS dependabot-debian|FROM denoland/deno:alpine AS dependabot-debian|g' "$SRC_ROOT/invidious-companion/$D_FILE"
        # Remove redundant commands since we now use the deno image as base
        sed -i '/COPY --from=deno-bin/d' "$SRC_ROOT/invidious-companion/$D_FILE"
        sed -i '/RUN apk add --no-cache gcompat/d' "$SRC_ROOT/invidious-companion/$D_FILE"
        # Carefully remove the user creation logic (it's in the debian-deno stage)
        sed -i '/RUN addgroup -g 1993 -S deno/,/chown deno:deno/d' "$SRC_ROOT/invidious-companion/$D_FILE"
        # Also ensure we don't have a stray && if the RUN was different
        sed -i '/RUN useradd --uid 1993/d' "$SRC_ROOT/invidious-companion/$D_FILE"
        
        # Add necessary directory creation to the correct stage
        # We match the standalone ARG DENO_DIR line (not the one with default value)
        sed -i '/^ARG DENO_DIR$/a RUN mkdir -p ${DENO_DIR} && chown deno:deno ${DENO_DIR}' "$SRC_ROOT/invidious-companion/$D_FILE"

        # Fix final stage to Alpine
        sed -i 's|^FROM gcr.io/distroless/cc.*|FROM alpine:3.20|g' "$SRC_ROOT/invidious-companion/$D_FILE"
        
        # Switch Debian stages to Alpine (since we replaced apt with apk)
        sed -i 's/^FROM debian:.* AS dependabot-debian/FROM dhi.io\/alpine-base:3.22-dev AS dependabot-debian/' "$SRC_ROOT/invidious-companion/$D_FILE"
        
        # Fix package names for Alpine
        sed -i 's/xz-utils/xz/g' "$SRC_ROOT/invidious-companion/$D_FILE"
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

if [ "$SERVICE" = "rimgo" ] || [ "$SERVICE" = "all" ]; then
    D_FILE=$(detect_dockerfile "$SRC_ROOT/rimgo")
    if [ -n "$D_FILE" ]; then
        log "Patching rimgo..."
        patch_bare "$SRC_ROOT/rimgo/$D_FILE" "https://codeberg.org/rimgo/rimgo/src/branch/main/Dockerfile"
        # Fix missing tailwindcss dependency for the CLI
        sed -i 's/npx @tailwindcss\/cli/npm install tailwindcss \&\& npx @tailwindcss\/cli/g' "$SRC_ROOT/rimgo/$D_FILE"
    fi
fi

# Apply generic patches to all others
# PATCHABLE_SERVICES is defined in constants.sh (sourced via core.sh)
for srv in $PATCHABLE_SERVICES; do
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
        sed "s|__CONTAINER_PREFIX__|${CONTAINER_PREFIX}|g; s|__INVIDIOUS_DB_PASSWORD__|${INVIDIOUS_DB_PASSWORD}|g" "$SCRIPT_DIR/lib/templates/migrate.sh" > "$MIGRATE_SCRIPT"
        chmod +x "$MIGRATE_SCRIPT"
    else
        echo "[WARN] templates/migrate.sh not found at $SCRIPT_DIR/lib/templates/migrate.sh"
    fi

    # 2. WG Control Script
    if [ -f "$SCRIPT_DIR/lib/templates/wg_control.sh" ]; then
        sed "s|__CONTAINER_PREFIX__|${CONTAINER_PREFIX}|g; s|__ADMIN_PASS_RAW__|${ADMIN_PASS_RAW}|g" "$SCRIPT_DIR/lib/templates/wg_control.sh" > "$WG_CONTROL_SCRIPT"
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
    CUSTOM_SERVICES_JSON="$PROJECT_ROOT/custom_services.json"
    
    # Generate Base Services
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
      "description": "Powerful media downloader. Extract content from dozens of platforms with a clean, efficient interface.",
      "category": "apps",
      "order": 30,
      "url": "http://$LAN_IP:$PORT_COBALT",
      "source_url": "https://github.com/imputnet/cobalt",
      "patch_url": "https://github.com/imputnet/cobalt/blob/master/Dockerfile",
      "chips": [
        {"label": "Local Only", "icon": "lan", "variant": "tertiary"},
        {"label": "Upstream Image", "icon": "package", "variant": "secondary"}
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
      "chips": [{"label": "Upstream Image", "icon": "package", "variant": "secondary"}]
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
      "chips": [{"label": "Upstream Image", "icon": "package", "variant": "secondary"}]
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

    # Merge Custom Services if exists
    if [ -f "$CUSTOM_SERVICES_JSON" ]; then
        log_info "Integrating custom services from custom_services.json..."
        if TMP_MERGED=$(mktemp) && jq -s '.[0].services * .[1].services | {services: .}' "$SERVICES_JSON" "$CUSTOM_SERVICES_JSON" > "$TMP_MERGED"; then
            mv "$TMP_MERGED" "$SERVICES_JSON"
            log_info "Custom services successfully integrated."
        else
            log_warn "Failed to merge custom_services.json. Ensure it contains valid JSON with a 'services' object."
            [ -f "${TMP_MERGED:-}" ] && rm "$TMP_MERGED"
        fi
    fi
}

# --- SECTION 9: INFRASTRUCTURE CONFIGURATION ---
# Generate configuration files for core system services (DNS, SSL, Nginx).

setup_static_assets() {
    log_info "Initializing local asset directories and icons..."
    $SUDO mkdir -p "$ASSETS_DIR"
    
    # Create local SVG icon for CasaOS/ZimaOS dashboard
    log_info "Creating local SVG icon for the dashboard..."
    cat > "$ASSETS_DIR/$APP_NAME.svg" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128">
    <rect width="128" height="128" rx="28" fill="#141218"/>
    <path d="M64 104q-23-6-38-26.5T11 36v-22l53-20 53 20v22q0 25-15 45.5T64 104Zm0-14q17-5.5 28.5-22t11.5-35V21L64 6 24 21v12q0 18.5 11.5 35T64 90Zm0-52Z" fill="#D0BCFF" transform="translate(0, 15) scale(1)"/>
    <circle cx="64" cy="55" r="12" fill="#D0BCFF" opacity="0.8"/>
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

    local proxy="http://172.${FOUND_OCTET}.0.254:8888"
    local ua="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    # Wait for Gluetun proxy to be ready (up to 60s)
    log_info "Verifying Gluetun proxy availability (Privacy Mode)..."
    local proxy_ready=false
    for i in {1..30}; do
        if curl --proxy "$proxy" -fsSL --max-time 3 https://fontlay.com -o /dev/null >/dev/null 2>&1; then
            proxy_ready=true
            break
        fi
        sleep 2
    done

    if [ "$proxy_ready" = false ]; then
        log_crit "Gluetun proxy is not responding. Aborting asset localization to prevent home IP leakage."
        log_crit "Please ensure your WireGuard configuration is valid and the VPN can connect."
        return 1
    fi

    # URLs (Fontlay)
    URL_GS="https://fontlay.com/css2?family=Google+Sans+Flex:wght@400;500;600;700&display=swap"
    URL_CC="https://fontlay.com/css2?family=Cascadia+Code:ital,wght@0,200..700;1,200..700&display=swap"
    URL_MS="https://fontlay.com/css2?family=Material+Symbols+Rounded:opsz,wght,FILL,GRAD@20..48,100..700,0..1,-50..200&display=swap"

    download_css() {
        local dest="$1"
        local url="$2"
        if ! curl --proxy "$proxy" -fsSL --max-time 15 -A "$ua" "$url" -o "$dest"; then
            log_warn "Asset source failed via proxy: $url"
            return 1
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
    local mcu_url="https://cdn.jsdelivr.net/npm/@material/material-color-utilities@0.3.0/+esm"
    local mcu_sha384="3U1awaKd5cEaag6BP1vFQ7y/99n+Iz/n/QiGuRX0BmKncek9GxW6I42Enhwn9QN9"
    if curl --proxy "$proxy" -fsSL --max-time 15 -A "$ua" "$mcu_url" -o "$ASSETS_DIR/mcu.js"; then
        if $PYTHON_CMD -c "import hashlib, base64, sys; d=hashlib.sha384(open(sys.argv[1],'rb').read()).digest(); h=base64.b64encode(d).decode(); sys.exit(0) if h==sys.argv[2] else sys.exit(1)" "$ASSETS_DIR/mcu.js" "$mcu_sha384"; then
            log_info "Verified Material Color Utilities checksum."
        else
            log_warn "Material Color Utilities checksum mismatch! Deleting file."
            rm -f "$ASSETS_DIR/mcu.js"
        fi
    else
        log_warn "Failed to download Material Color Utilities via proxy."
    fi

    # QRCode JS (Local for privacy)
    log_info "Downloading QRCode library..."
    local qr_url="https://cdn.jsdelivr.net/npm/qrcode@1.4.4/build/qrcode.min.js"
    if curl --proxy "$proxy" -fsSL --max-time 15 -A "$ua" "$qr_url" -o "$ASSETS_DIR/qrcode.min.js"; then
        log_info "Downloaded QRCode library."
    else
        log_warn "Failed to download QRCode library via proxy."
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
                    if ! curl --proxy "$proxy" -fsSL --max-time 15 -A "$ua" "$fetch_url" -o "$clean_name"; then
                        log_warn "Failed to download font asset via proxy: $fetch_url"
                    fi
                fi
            ) &
        done
        wait

        # Update CSS file sequentially after all fonts are downloaded
        for url in $urls; do
            filename=$(basename "$url")
            clean_name="${filename%%\?*}"
            escaped_url=$(echo "$url" | sed 's/[\/&|]/\\&/g')
            sed -i "s|url(['\"]\{0,1\}${escaped_url}['\"]\{0,1\})|url($clean_name)|g" "$css_file"
        done
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
                 openssl x509 -in /certs/ssl.crt -noout -subject | grep -q '$DESEC_DOMAIN' && \
                 openssl x509 -in /certs/ssl.crt -noout -issuer | grep -qE 'Let.s Encrypt|R3|ISRG|ZeroSSL'" >/dev/null 2>&1; then
                log_info "Existing SSL certificate is valid for $DESEC_DOMAIN and has >30 days remaining."
                log_info "Skipping new certificate request to conserve rate limits."
                SKIP_CERT_REQ=true
            else
                log_info "Existing certificate is invalid, expired, or self-signed. Requesting new one..."
            fi
        fi

        if [ "$SKIP_CERT_REQ" = false ]; then
            log_info "Attempting Let's Encrypt certificate issuance..."
            log_info "Note: This process includes a 120-second wait for DNS propagation and typically takes 3-5 minutes."
            CERT_SUCCESS=false
            CERT_LOG_FILE="$AGH_CONF_DIR/certbot/last_run.log"

            # Request Let's Encrypt certificate via DNS-01 challenge
            CERT_TMP_OUT=$(mktemp)
            
            # Start acme.sh in background and provide progress feedback
            $DOCKER_CMD run --rm \
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
                --cert-home /acme/certs > "$CERT_TMP_OUT" 2>&1 &
            
            ACME_PID=$!
            
            # Simple progress indicator
            local elapsed=0
            while kill -0 $ACME_PID 2>/dev/null; do
                if [ $((elapsed % 30)) -eq 0 ] && [ $elapsed -ne 0 ]; then
                    log_info "Still working on SSL certificate... ($elapsed seconds elapsed)"
                fi
                sleep 1
                elapsed=$((elapsed + 1))
            done
            
            wait $ACME_PID
            if [ $? -eq 0 ]; then
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
    $SUDO mkdir -p "$DATA_DIR/hub-api"
    $SUDO chown -R 1000:1000 "$DATA_DIR/hub-api"

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
    searxng.$DESEC_DOMAIN    http://${CONTAINER_PREFIX}gluetun:8082;
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
    "searxng.$DESEC_DOMAIN:8443"    http://${CONTAINER_PREFIX}gluetun:8082;
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
        set \$hub_api_backend "http://hub-api:55555";
        rewrite ^/api/(.*) /\$1 break;
        proxy_pass \$hub_api_backend;
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
        set \$odido_backend "http://odido-booster:8080";
        rewrite ^/odido-api/(.*) /\$1 break;
        proxy_pass \$odido_backend;
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
    $SUDO chmod -R 777 "$CONFIG_DIR/searxng"

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
    # Configure Scribe Environment
    # We use SCRIBE_HOST=0.0.0.0 to bind to all interfaces
    # We use LUCKY_ENV=production to disable development features like the watcher
    # Scribe requires a DATABASE_URL even if it doesn't use it.
    cat <<EOF | $SUDO tee "$ENV_DIR/scribe.env" >/dev/null
SCRIBE_HOST=0.0.0.0
PORT=$PORT_SCRIBE
LUCKY_ENV=production
SECRET_KEY_BASE=$SCRIBE_SECRET
DATABASE_URL=postgres://dummy:dummy@127.0.0.1/dummy
APP_DOMAIN=http://$LAN_IP:$PORT_SCRIBE
EOF

    generate_libredirect_export
}

    generate_libredirect_export() {
    log_info "Generating LibRedirect import file from template..."
    
    # Validation: Only generate if deSEC domain AND certificates are present
    if [ -z "$DESEC_DOMAIN" ]; then
        log_info "Skipping LibRedirect export: No deSEC domain provided."
        return 0
    fi
    
    if [ ! -f "$AGH_CONF_DIR/ssl.crt" ] || [ ! -f "$AGH_CONF_DIR/ssl.key" ]; then
        log_info "Skipping LibRedirect export: SSL certificates not found at $AGH_CONF_DIR."
        return 0
    fi

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
    local host="$DESEC_DOMAIN"
    local port_suffix=":8443"
    
    # Subdomain-based URLs for Nginx proxy
    local url_invidious="${proto}://invidious.${host}${port_suffix}"
    local url_redlib="${proto}://redlib.${host}${port_suffix}"
    local url_wikiless="${proto}://wikiless.${host}${port_suffix}"
    local url_rimgo="${proto}://rimgo.${host}${port_suffix}"
    local url_scribe="${proto}://scribe.${host}${port_suffix}"
    local url_breezewiki="${proto}://breezewiki.${host}${port_suffix}"
    local url_anonoverflow="${proto}://anonymousoverflow.${host}${port_suffix}"
    local url_searxng="${proto}://searxng.${host}${port_suffix}"

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

    # Prepare escaped passwords for docker-compose (v2 requires $$ for literal $)
    # This prevents Compose from attempting to interpolate variables inside passwords.
    ADMIN_PASS_COMPOSE="${ADMIN_PASS_RAW//\$/\$\$}"
    VPN_PASS_COMPOSE="${VPN_PASS_RAW//\$/\$\$}"
    HUB_API_KEY_COMPOSE="${HUB_API_KEY//\$/\$\$}"
    PORTAINER_PASS_COMPOSE="${PORTAINER_PASS_RAW//\$/\$\$}"
    AGH_PASS_COMPOSE="${AGH_PASS_RAW//\$/\$\$}"
    INVIDIOUS_DB_PASS_COMPOSE="${INVIDIOUS_DB_PASSWORD//\$/\$\$}"
    IMMICH_DB_PASS_COMPOSE="${IMMICH_DB_PASSWORD//\$/\$\$}"

    # Ensure required directories exist
    mkdir -p "$BASE_DIR" "$SRC_DIR" "$ENV_DIR" "$CONFIG_DIR" "$DATA_DIR"

    cat > "$COMPOSE_FILE" <<EOF
name: ${APP_NAME}
# ... (rest of the file follows, replacing raw variables with _COMPOSE versions)
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
  # Docker Socket Proxy: Mediates access to the Docker daemon for security
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
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
    networks: [dhi-mgmtnet]
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '0.2', memory: 64M}

EOF

    if should_deploy "hub-api"; then
        HUB_API_DOCKERFILE=$(detect_dockerfile "$SRC_DIR/hub-api" || echo "Dockerfile")
    cat >> "$COMPOSE_FILE" <<EOF
  hub-api:
    pull_policy: missing
    build:
      context: $SRC_DIR/hub-api
      dockerfile: $HUB_API_DOCKERFILE
    image: selfhost/hub-api:${HUB_API_IMAGE_TAG:-latest}
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
    pull_policy: missing
    build:
      context: $SRC_DIR/odido-bundle-booster
      dockerfile: $ODIDO_DOCKERFILE
    image: selfhost/odido-booster:${ODIDO_BOOSTER_IMAGE_TAG:-latest}
    container_name: ${CONTAINER_PREFIX}odido-booster
    labels:
      - "io.dhi.hardened=true"
    network_mode: "service:gluetun"
    environment:
      - API_KEY=$HUB_API_KEY_COMPOSE
      - ODIDO_USER_ID=$ODIDO_USER_ID
      - ODIDO_TOKEN=$ODIDO_TOKEN
      - PORT=8080
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://127.0.0.1:8080/docs"]
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
    pull_policy: missing
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
      - API_KEY=$HUB_API_KEY_COMPOSE
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
    pull_policy: missing
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
    pull_policy: missing
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
      - "$LAN_IP:8085:8080/tcp"
    volumes:
      - "$ACTIVE_WG_CONF:/gluetun/wireguard/wg0.conf:ro"
    env_file:
      - "$GLUETUN_ENV_FILE"
    healthcheck:
      test: ["CMD", "true"]
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '2.0', memory: 512M}
EOF
    fi

    # Create Dashboard Source Directory and Dockerfile
    $SUDO mkdir -p "$SRC_DIR/dashboard"
    cat <<EOF | $SUDO tee "$SRC_DIR/dashboard/Dockerfile" >/dev/null
FROM alpine:3.20
RUN apk add --no-cache nginx \
    && mkdir -p /usr/share/nginx/html \
    && chown -R 1000:1000 /var/lib/nginx /var/log/nginx /run/nginx /usr/share/nginx/html
USER 1000
COPY . /usr/share/nginx/html
# Nginx default configuration is handled by volume mount for flexibility
CMD ["nginx", "-g", "daemon off;"]
EOF

    if should_deploy "dashboard"; then
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
    fi

    # Create Portainer Source Directory and DHI Wrapper
    $SUDO mkdir -p "$SRC_DIR/portainer"
    cat <<EOF | $SUDO tee "$SRC_DIR/portainer/Dockerfile.dhi" >/dev/null
FROM alpine:3.20
COPY --from=portainer/portainer-ce:latest /portainer /portainer
COPY --from=portainer/portainer-ce:latest /public /public
COPY --from=portainer/portainer-ce:latest /mustache-templates /mustache-templates
# Portainer expectations
WORKDIR /
EXPOSE 9000 9443
ENTRYPOINT ["/portainer"]
EOF

    if should_deploy "portainer"; then
    cat >> "$COMPOSE_FILE" <<EOF
  portainer:
    pull_policy: missing
    build:
      context: $SRC_DIR/portainer
      dockerfile: Dockerfile.dhi
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
    pull_policy: missing
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
    pull_policy: missing
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
      test: ["CMD", "/usr/bin/drill-hc", "@127.0.0.1", "example.com"]
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
    pull_policy: missing
    build:
      context: $SRC_DIR/wg-easy
      dockerfile: ${WG_EASY_DOCKERFILE:-Dockerfile}
    image: selfhost/wg-easy:${WG_EASY_IMAGE_TAG:-latest}
    container_name: ${CONTAINER_PREFIX}wg-easy
    network_mode: "host"
    environment:
      - INIT_ENABLED=true
      - INIT_USERNAME=admin
      - INIT_PASSWORD=$VPN_PASS_COMPOSE
      - INIT_DNS=$LAN_IP
      - INIT_ALLOWED_IPS=10.0.0.0/8,172.16.0.0/12,192.168.0.0/16
      - INIT_HOST=$PUBLIC_IP
      - INIT_PORT=51820
      - WG_PORT=51820
      - WG_PERSISTENT_KEEPALIVE=0
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
    pull_policy: missing
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
    environment: {REDLIB_PORT: 8081, PORT: 8081, REDLIB_ADDRESS: "0.0.0.0", REDLIB_DEFAULT_WIDE: "on", REDLIB_DEFAULT_USE_HLS: "on", REDLIB_DEFAULT_SHOW_NSFW: "on"}
    restart: always
    user: nobody
    read_only: true
    security_opt: [no-new-privileges:true]
    cap_drop: [ALL]
    depends_on: {gluetun: {condition: service_healthy}}
    healthcheck:
      test: ["CMD-SHELL", "wget --spider -q http://127.0.0.1:8081/robots.txt || [ $? -eq 8 ]"]
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
    pull_policy: missing
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
    image: redis:${REDIS_IMAGE_TAG:-7.2.6-alpine}
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
    pull_policy: missing
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
          password: $INVIDIOUS_DB_PASSWORD
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
    image: postgres:${INVIDIOUS_DB_IMAGE_TAG:-14.15-alpine3.21}
    container_name: ${CONTAINER_PREFIX}invidious-db
    labels:
      - "casaos.skip=true"
      - "io.dhi.hardened=true"
    network_mode: "service:gluetun"
    environment: {POSTGRES_DB: invidious, POSTGRES_USER: kemal, POSTGRES_PASSWORD: $INVIDIOUS_DB_PASS_COMPOSE}
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
    container_name: ${CONTAINER_PREFIX}companion
    pull_policy: missing
    build:
      context: $SRC_DIR/invidious-companion
      dockerfile: ${COMPANION_DOCKERFILE:-Dockerfile}
    image: selfhost/invidious-companion:${COMPANION_IMAGE_TAG:-latest}
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
    depends_on: {gluetun: {condition: service_healthy}}
    deploy:
      resources:
        limits: {cpus: '0.3', memory: 128M}
EOF
    fi

    if should_deploy "rimgo"; then
        RIMGO_DOCKERFILE=$(detect_dockerfile "$SRC_DIR/rimgo" || echo "Dockerfile")
    cat >> "$COMPOSE_FILE" <<EOF
  rimgo:
    pull_policy: missing
    build:
      context: $SRC_DIR/rimgo
      dockerfile: ${RIMGO_DOCKERFILE:-Dockerfile}
    image: selfhost/rimgo:${RIMGO_IMAGE_TAG:-latest}
    container_name: ${CONTAINER_PREFIX}rimgo
    labels:
      - "io.dhi.hardened=true"
    network_mode: "service:gluetun"
    environment: {IMGUR_CLIENT_ID: "${RIMGO_IMGUR_CLIENT_ID:-546c25a59c58ad7}", ADDRESS: "0.0.0.0", PORT: "$PORT_INT_RIMGO"}
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
        
        if [ -n "$DESEC_DOMAIN" ]; then
            BW_ORIGIN="https://breezewiki.$DESEC_DOMAIN"
        else
            BW_ORIGIN="http://$LAN_IP:$PORT_BREEZEWIKI"
        fi

    cat >> "$COMPOSE_FILE" <<EOF
  breezewiki:
    pull_policy: missing
    build:
      context: $SRC_DIR/breezewiki
      dockerfile: ${BREEZEWIKI_DOCKERFILE:-Dockerfile.alpine}
    image: selfhost/breezewiki:${BREEZEWIKI_IMAGE_TAG:-latest}
    container_name: ${CONTAINER_PREFIX}breezewiki
    labels:
      - "io.dhi.hardened=true"
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
    fi

    if should_deploy "anonymousoverflow"; then
        ANONYMOUS_DOCKERFILE=$(detect_dockerfile "$SRC_DIR/anonymousoverflow" || echo "Dockerfile")
    cat >> "$COMPOSE_FILE" <<EOF
  anonymousoverflow:
    pull_policy: missing
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
    pull_policy: missing
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
    pull_policy: missing
    build:
      context: $SRC_DIR/vertd
      dockerfile: ${VERTD_DOCKERFILE:-Dockerfile}
    image: selfhost/vertd:${VERTD_IMAGE_TAG:-latest}
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
    pull_policy: missing
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
    image: ghcr.io/imputnet/cobalt:${COBALT_IMAGE_TAG:-latest}
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
    image: searxng/searxng:${SEARXNG_IMAGE_TAG:-latest}
    container_name: ${CONTAINER_PREFIX}searxng
    network_mode: "service:gluetun"
    volumes:
      - $CONFIG_DIR/searxng:/etc/searxng:ro
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
    image: redis:alpine
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
    fi

    if should_deploy "immich"; then
    cat >> "$COMPOSE_FILE" <<EOF
  # Immich: High-performance self-hosted photo and video management
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
    shm_size: 256mb
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