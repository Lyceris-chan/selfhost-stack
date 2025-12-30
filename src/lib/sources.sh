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

    PATCHES_SCRIPT="$BASE_DIR/patches.sh"

cat > "$PATCHES_SCRIPT" <<'PATCHEOF'
#!/bin/sh
SERVICE=$1
SRC_ROOT=${2:-/app/sources}

log() { echo "[PATCH] $1"; }

detect_dockerfile() {
    local repo_dir="$1"
    local preferred="${2:-}"
    local found=""
    if [ -n "$preferred" ] && [ -f "$repo_dir/$preferred" ]; then echo "$preferred"; return 0; fi
    if [ -f "$repo_dir/Dockerfile.dhi" ]; then echo "Dockerfile.dhi"; return 0; fi
    if [ -f "$repo_dir/Dockerfile" ]; then echo "Dockerfile"; return 0; fi
    if [ -f "$repo_dir/docker/Dockerfile" ]; then echo "docker/Dockerfile"; return 0; fi
    # Search deeper
    found=$(find "$repo_dir" -maxdepth 3 -type f -name 'Dockerfile*' -not -path '*/.*' 2>/dev/null | head -n 1 || true)
    if [ -n "$found" ]; then echo "${found#"$repo_dir/"}"; return 0; fi
    return 1
}

patch_generic() {
    local file="$1"
    [ ! -f "$file" ] && return
    log "  Applying generic patches to $(basename "$file")..."
    # Base OS (only if it's a FROM line and not FROM scratch/distroless)
    sed -i '/^FROM [^ ]*\(scratch\|distroless\)/! s|^FROM alpine:[^ ]*|FROM alpine:3.21|g' "$file"
    sed -i '/^FROM [^ ]*\(scratch\|distroless\)/! s|^FROM debian:[^ ]*|FROM alpine:3.21|g' "$file"
    # Node.js (build stages)
    sed -i 's|^FROM node:[^ ]*|FROM node:20-alpine3.21|g' "$file"
    # Go (build stages)
    sed -i 's|^FROM golang:[^ ]*|FROM golang:1.23-alpine3.21|g' "$file"
    # Python (build stages)
    sed -i 's|^FROM python:[^ ]*|FROM python:3.11-alpine3.21|g' "$file"
    # Strip apk version pins (e.g., package=1.2.3 -> package) to ensure compatibility with modern base images
    # We restrict this to lines that look like apk add commands
    sed -i '/apk add/ s/=[0-9][^[:space:]]*//g' "$file"
}

if [ "$SERVICE" = "wikiless" ] || [ "$SERVICE" = "all" ]; then
    log "Patching Wikiless..."
    D_FILE=$(detect_dockerfile "$SRC_ROOT/wikiless")
    if [ -n "$D_FILE" ]; then
        # Switch build stage to hardened
        sed -i 's|^FROM node:[^ ]* AS build|FROM dhi.io/node:20-alpine3.22-dev AS build|g' "$SRC_ROOT/wikiless/$D_FILE"
        # Keep distroless runtime as requested by user
        sed -i 's|CMD \["src/wikiless.js"\]|CMD ["node", "src/wikiless.js"]|g' "$SRC_ROOT/wikiless/$D_FILE"
    fi
fi

if [ "$SERVICE" = "scribe" ] || [ "$SERVICE" = "all" ]; then
    log "Patching Scribe..."
    D_FILE=$(detect_dockerfile "$SRC_ROOT/scribe")
    # If no Dockerfile found, create a hardened one from scratch
    if [ "$D_FILE" = "1" ] || [ ! -f "$SRC_ROOT/scribe/$D_FILE" ]; then
        log "  Creating missing Dockerfile for Scribe..."
        cat > "$SRC_ROOT/scribe/Dockerfile" <<'SCRIBEOF'
FROM 84codes/crystal:1.16.3-alpine AS build
RUN apk add --no-cache git nodejs yarn
WORKDIR /app
COPY . .
RUN shards install --production
RUN yarn install && yarn build:prod
RUN crystal build src/scribe.cr --release --static

FROM alpine:3.21
RUN apk add --no-cache libevent gc
WORKDIR /app
COPY --from=build /app/scribe /app/scribe
COPY --from=build /app/public /app/public
EXPOSE 8280
ENTRYPOINT ["/app/scribe"]
SCRIBEOF
        D_FILE="Dockerfile"
    fi
    patch_generic "$SRC_ROOT/scribe/$D_FILE"
    # Scribe needs crystal 1.14+ for modern versions
    sed -i 's|^FROM 84codes/crystal:[^ ]*|FROM 84codes/crystal:1.16.3-alpine|g' "$SRC_ROOT/scribe/$D_FILE"
    # Ensure root for entrypoint execution if using alpine base
    if grep -q "FROM alpine" "$SRC_ROOT/scribe/$D_FILE"; then
         sed -i '/FROM alpine:3.21/a USER root' "$SRC_ROOT/scribe/$D_FILE"
    fi
    sed -i 's|CMD \["/home/lucky/app/docker_entrypoint"\]|CMD ["/bin/sh", "/home/lucky/app/docker_entrypoint"]|g' "$SRC_ROOT/scribe/$D_FILE"
fi

if [ "$SERVICE" = "invidious" ] || [ "$SERVICE" = "all" ]; then
    log "Patching Invidious..."
    D_FILE=$(detect_dockerfile "$SRC_ROOT/invidious" "docker/Dockerfile")
    if [ -n "$D_FILE" ]; then
        patch_generic "$SRC_ROOT/invidious/$D_FILE"
        sed -i 's|^FROM crystallang/crystal:[^ ]*|FROM 84codes/crystal:1.16.3-alpine|g' "$SRC_ROOT/invidious/$D_FILE"
    fi
fi

if [ "$SERVICE" = "odido-booster" ] || [ "$SERVICE" = "all" ]; then
    log "Patching Odido..."
    D_FILE=$(detect_dockerfile "$SRC_ROOT/odido-bundle-booster")
    if [ -n "$D_FILE" ]; then
        patch_generic "$SRC_ROOT/odido-bundle-booster/$D_FILE"
    fi
fi

if [ "$SERVICE" = "vert" ] || [ "$SERVICE" = "all" ]; then
    log "Patching VERT..."
    D_FILE=$(detect_dockerfile "$SRC_ROOT/vert")
    if [ -n "$D_FILE" ]; then
        patch_generic "$SRC_ROOT/vert/$D_FILE"
        sed -i 's|^FROM oven/bun:[^ ]*|FROM dhi.io/bun:1-alpine3.22-dev|g' "$SRC_ROOT/vert/$D_FILE"
        sed -i 's|^FROM oven/bun$|FROM dhi.io/bun:1-alpine3.22-dev|g' "$SRC_ROOT/vert/$D_FILE"
        # Ensure we only have one apk add command and no apt-get
        if ! grep -q "apk add --no-cache git" "$SRC_ROOT/vert/$D_FILE"; then
             sed -i 's/RUN apt-get update \&\& apt-get install -y --no-install-recommends git/RUN apk add --no-cache git/g' "$SRC_ROOT/vert/$D_FILE"
        fi
        sed -i '/apt-get/d' "$SRC_ROOT/vert/$D_FILE"
        sed -i '/rm -rf \/var\/lib\/apt\/lists/d' "$SRC_ROOT/vert/$D_FILE"
        sed -i 's@CMD curl .*@CMD nginx -t || exit 1@' "$SRC_ROOT/vert/$D_FILE"
    fi
fi

if [ "$SERVICE" = "breezewiki" ] || [ "$SERVICE" = "all" ]; then
    log "Patching BreezeWiki..."
    D_FILE=$(detect_dockerfile "$SRC_ROOT/breezewiki" "Dockerfile.alpine")
    # If no Dockerfile found, create a hardened one from scratch
    if [ "$D_FILE" = "1" ] || [ ! -f "$SRC_ROOT/breezewiki/$D_FILE" ]; then
        log "  Creating missing Dockerfile.alpine for BreezeWiki..."
        cat > "$SRC_ROOT/breezewiki/Dockerfile.alpine" <<'BWEOF'
FROM alpine:3.21 AS build
RUN apk add --no-cache git racket ca-certificates curl sqlite-libs fontconfig cairo libjpeg-turbo glib pango
WORKDIR /app
COPY . .
RUN raco pkg install --batch --auto --no-docs --skip-installed req-lib && raco req -d
RUN racket dist.rkt

FROM alpine:3.21
RUN apk add --no-cache racket ca-certificates curl sqlite-libs fontconfig cairo libjpeg-turbo glib pango
WORKDIR /app
COPY --from=build /app/dist /app
EXPOSE 10416
ENTRYPOINT ["racket", "breezewiki.rkt"]
BWEOF
        D_FILE="Dockerfile.alpine"
    fi
    patch_generic "$SRC_ROOT/breezewiki/$D_FILE"
    if ! grep -q "apk add.*racket" "$SRC_ROOT/breezewiki/$D_FILE"; then
        sed -i '/FROM alpine/a RUN apk add --no-cache git racket ca-certificates curl sqlite-libs fontconfig cairo libjpeg-turbo glib pango' "$SRC_ROOT/breezewiki/$D_FILE"
    fi
    sed -i '/RUN raco pkg install/c\RUN raco pkg install --batch --auto --no-docs --skip-installed req-lib && raco req -d' "$SRC_ROOT/breezewiki/$D_FILE"
fi

if [ "$SERVICE" = "adguard" ] || [ "$SERVICE" = "all" ]; then
    log "Patching AdGuard Home..."
    D_FILE="$SRC_ROOT/adguardhome/docker/Dockerfile"
    if [ -f "$D_FILE" ]; then
        if ! grep -q "dhi.io" "$SRC_ROOT/adguardhome/Dockerfile.dhi" 2>/dev/null; then
            cat > "$SRC_ROOT/adguardhome/Dockerfile.dhi" <<'ADGBUILD'
# Build Stage - Frontend
FROM node:20-alpine3.21 AS fe-builder
WORKDIR /app
COPY . .
RUN npm install --prefix client && npm run --prefix client build-prod

# Build Stage - Backend
FROM golang:1.23-alpine3.21 AS builder
RUN apk add --no-cache git make gcc musl-dev
WORKDIR /app
COPY . .
COPY --from=fe-builder /app/build /app/build
RUN GOTOOLCHAIN=auto go build -trimpath -ldflags="-s -w" -o AdGuardHome_bin main.go

ADGBUILD
            START_LINE=$(grep -n "^FROM alpine" "$D_FILE" | head -n 1 | cut -d: -f1)
            if [ -n "$START_LINE" ]; then
                tail -n "+$START_LINE" "$D_FILE" >> "$SRC_ROOT/adguardhome/Dockerfile.dhi"
                patch_generic "$SRC_ROOT/adguardhome/Dockerfile.dhi"
                awk '/COPY --chown=nobody:nogroup/,/\/opt\/adguardhome\/AdGuardHome/ { if (!done) { print "COPY --from=builder /app/AdGuardHome_bin /opt/adguardhome/AdGuardHome"; done=1 } next } { print }' "$SRC_ROOT/adguardhome/Dockerfile.dhi" > "$SRC_ROOT/adguardhome/Dockerfile.dhi.tmp" && mv "$SRC_ROOT/adguardhome/Dockerfile.dhi.tmp" "$SRC_ROOT/adguardhome/Dockerfile.dhi"
            else
                echo "FROM alpine:3.21" >> "$SRC_ROOT/adguardhome/Dockerfile.dhi"
                echo "COPY --from=builder /app/AdGuardHome_bin /opt/adguardhome/AdGuardHome" >> "$SRC_ROOT/adguardhome/Dockerfile.dhi"
                grep "^ENTRYPOINT" "$D_FILE" >> "$SRC_ROOT/adguardhome/Dockerfile.dhi" || echo 'ENTRYPOINT ["/opt/adguardhome/AdGuardHome"]' >> "$SRC_ROOT/adguardhome/Dockerfile.dhi"
                grep "^CMD" "$D_FILE" >> "$SRC_ROOT/adguardhome/Dockerfile.dhi" || echo 'CMD ["--no-check-update", "-c", "/opt/adguardhome/conf/AdGuardHome.yaml", "-w", "/opt/adguardhome/work"]' >> "$SRC_ROOT/adguardhome/Dockerfile.dhi"
            fi
            rm -f "$SRC_ROOT/adguardhome/.dockerignore"
        fi
    fi
fi

if [ "$SERVICE" = "gluetun" ] || [ "$SERVICE" = "all" ]; then
    log "Patching Gluetun..."
    D_FILE=$(detect_dockerfile "$SRC_ROOT/gluetun" "Dockerfile")
    if [ -n "$D_FILE" ]; then
        if ! grep -q "dhi.io" "$SRC_ROOT/gluetun/Dockerfile.dhi" 2>/dev/null; then
            cp "$SRC_ROOT/gluetun/$D_FILE" "$SRC_ROOT/gluetun/Dockerfile.dhi"
            # Surgical replacements for ARG versions
            sed -i 's/ARG ALPINE_VERSION=.*/ARG ALPINE_VERSION=3.21/g' "$SRC_ROOT/gluetun/Dockerfile.dhi"
            sed -i 's/ARG GO_ALPINE_VERSION=.*/ARG GO_ALPINE_VERSION=3.21/g' "$SRC_ROOT/gluetun/Dockerfile.dhi"
            sed -i 's/ARG GO_VERSION=.*/ARG GO_VERSION=1.23/g' "$SRC_ROOT/gluetun/Dockerfile.dhi"
            # Base image replacement
            sed -i 's|^FROM alpine:${ALPINE_VERSION}|FROM alpine:3.21|g' "$SRC_ROOT/gluetun/Dockerfile.dhi"
            sed -i 's|^FROM --platform=${BUILDPLATFORM} golang:${GO_VERSION}-alpine${GO_ALPINE_VERSION}|FROM --platform=${BUILDPLATFORM} golang:1.23-alpine3.21|g' "$SRC_ROOT/gluetun/Dockerfile.dhi"
            
            # Replace complex apk add/del block with a single clean install
            sed -i '/RUN apk add --no-cache --update -l wget/,/mkdir \/gluetun/c\RUN apk add --no-cache --update wget openvpn ca-certificates iptables iptables-legacy tzdata && echo "3.21.0" > /etc/alpine-release && mkdir /gluetun' "$SRC_ROOT/gluetun/Dockerfile.dhi"
            
            # Link openvpn for consistency (gluetun expects 2.5/2.6 variants)
            sed -i '/mkdir \/gluetun/a RUN ln -s /usr/sbin/openvpn /usr/sbin/openvpn2.6 && ln -s /usr/sbin/openvpn /usr/sbin/openvpn2.5' "$SRC_ROOT/gluetun/Dockerfile.dhi"
        fi
    fi
fi

if [ "$SERVICE" = "unbound" ] || [ "$SERVICE" = "all" ]; then
    log "Patching Unbound..."
    D_FILE=$(detect_dockerfile "$SRC_ROOT/unbound")
    if [ -n "$D_FILE" ]; then
        patch_generic "$SRC_ROOT/unbound/$D_FILE"
        # Ensure build stage uses dev base
        sed -i 's|^FROM alpine:[^ ]* as build|FROM alpine:3.21 as build|g' "$SRC_ROOT/unbound/$D_FILE"
    fi
fi

if [ "$SERVICE" = "memos" ] || [ "$SERVICE" = "all" ]; then
    log "Patching Memos..."
    D_FILE=$(detect_dockerfile "$SRC_ROOT/memos")
    if [ -n "$D_FILE" ]; then
        patch_generic "$SRC_ROOT/memos/$D_FILE"
    fi
fi

if [ "$SERVICE" = "redlib" ] || [ "$SERVICE" = "all" ]; then
    log "Patching Redlib..."
    D_FILE=$(detect_dockerfile "$SRC_ROOT/redlib")
    if [ -n "$D_FILE" ]; then
        patch_generic "$SRC_ROOT/redlib/$D_FILE"
        # Redlib original uses debian, fix apt usage if generic patch missed it
        sed -i 's/apt-get update && apt-get install -y libcurl4/apk add --no-cache curl/g' "$SRC_ROOT/redlib/$D_FILE"
    fi
fi

if [ "$SERVICE" = "rimgo" ] || [ "$SERVICE" = "all" ]; then
    log "Patching Rimgo..."
    D_FILE=$(detect_dockerfile "$SRC_ROOT/rimgo")
    if [ -n "$D_FILE" ]; then
        # Switch build stage
        sed -i 's|^FROM --platform=$BUILDPLATFORM golang:alpine AS build|FROM --platform=$BUILDPLATFORM dhi.io/golang:1-alpine3.22-dev AS build|g' "$SRC_ROOT/rimgo/$D_FILE"
        # Rimgo needs tailwind installed locally for npx @tailwindcss/cli to find it
        if ! grep -q "npm install tailwindcss" "$SRC_ROOT/rimgo/$D_FILE"; then
            sed -i 's/RUN apk --no-cache add ca-certificates git nodejs npm/RUN apk --no-cache add ca-certificates git nodejs npm \&\& npm install tailwindcss/g' "$SRC_ROOT/rimgo/$D_FILE"
        fi
        # Keep scratch final stage
    fi
fi

if [ "$SERVICE" = "anonymousoverflow" ] || [ "$SERVICE" = "all" ]; then
    log "Patching AnonymousOverflow..."
    D_FILE=$(detect_dockerfile "$SRC_ROOT/anonymousoverflow")
    if [ -n "$D_FILE" ]; then
        # Switch build stage
        sed -i 's|^FROM golang:[^ ]* AS build|FROM dhi.io/golang:1-alpine3.22-dev AS build|g' "$SRC_ROOT/anonymousoverflow/$D_FILE"
        # Keep scratch final stage
    fi
fi

if [ "$SERVICE" = "vertd" ] || [ "$SERVICE" = "all" ]; then
    log "Patching VERTd..."
    D_FILE=$(detect_dockerfile "$SRC_ROOT/vertd")
    if [ -n "$D_FILE" ]; then
        patch_generic "$SRC_ROOT/vertd/$D_FILE"
    fi
fi

if [ "$SERVICE" = "companion" ] || [ "$SERVICE" = "all" ]; then
    log "Patching Companion..."
    D_FILE=$(detect_dockerfile "$SRC_ROOT/invidious-companion")
    if [ -n "$D_FILE" ]; then
        patch_generic "$SRC_ROOT/invidious-companion/$D_FILE"
        # Companion has custom stages using debian but we switched to alpine-base
        sed -i 's/apt-get update && apt-get install -y/apk add --no-cache/g' "$SRC_ROOT/invidious-companion/$D_FILE"
        # Alpine uses xz instead of xz-utils
        sed -i 's/xz-utils/xz/g' "$SRC_ROOT/invidious-companion/$D_FILE"
        # Fix adduser syntax for alpine and ensure nogroup exists
        sed -i 's/adduser -u 10001 -S appuser/addgroup -S nogroup 2>\/dev\/null || true \&\& adduser -u 10001 -D -S -G nogroup appuser/g' "$SRC_ROOT/invidious-companion/$D_FILE"
        # Replace useradd with adduser for deno user
        sed -i 's/useradd --uid 1993 --user-group deno/addgroup -S deno \&\& adduser -u 1993 -D -S -G deno deno/g' "$SRC_ROOT/invidious-companion/$D_FILE"
        # Fix arch detection (dpkg missing on alpine)
        sed -i 's/dpkg --print-architecture/uname -m/g' "$SRC_ROOT/invidious-companion/$D_FILE"
        # uname -m returns x86_64, debian amd64
        sed -i 's/tini-${arch}/tini-$(echo ${arch} | sed "s\/x86_64\/amd64\/")/g' "$SRC_ROOT/invidious-companion/$D_FILE"
    fi
fi

if [ "$SERVICE" = "wg-easy" ] || [ "$SERVICE" = "all" ]; then
    log "Patching WG-Easy..."
    D_FILE=$(detect_dockerfile "$SRC_ROOT/wg-easy")
    if [ -n "$D_FILE" ]; then
        patch_generic "$SRC_ROOT/wg-easy/$D_FILE"
    fi
fi

if [ "$SERVICE" = "portainer" ] || [ "$SERVICE" = "all" ]; then
    log "Patching Portainer..."
    D_FILE=$(detect_dockerfile "$SRC_ROOT/portainer")
    if [ -n "$D_FILE" ]; then
        patch_generic "$SRC_ROOT/portainer/$D_FILE"
        sed -i 's|^FROM portainer/base|FROM dhi.io/alpine-base:3.22-dev|g' "$SRC_ROOT/portainer/$D_FILE"
    fi
fi

PATCHEOF
    chmod +x "$PATCHES_SCRIPT"

    # Clone repos
    clone_repo "https://github.com/Metastem/Wikiless" "$SRC_DIR/wikiless"
    clone_repo "https://git.sr.ht/~edwardloveall/scribe" "$SRC_DIR/scribe"
    clone_repo "https://github.com/iv-org/invidious.git" "$SRC_DIR/invidious"
    clone_repo "https://github.com/Lyceris-chan/odido-bundle-booster.git" "$SRC_DIR/odido-bundle-booster"
    clone_repo "https://github.com/VERT-sh/VERT.git" "$SRC_DIR/vert"
    clone_repo "https://github.com/VERT-sh/vertd.git" "$SRC_DIR/vertd"
    clone_repo "https://codeberg.org/rimgo/rimgo.git" "$SRC_DIR/rimgo"
    clone_repo "https://gitdab.com/cadence/breezewiki.git" "$SRC_DIR/breezewiki"
    clone_repo "https://github.com/httpjamesm/AnonymousOverflow.git" "$SRC_DIR/anonymousoverflow"
    clone_repo "https://github.com/qdm12/gluetun.git" "$SRC_DIR/gluetun"
    clone_repo "https://github.com/AdguardTeam/AdGuardHome.git" "$SRC_DIR/adguardhome"
    clone_repo "https://github.com/NLnetLabs/unbound.git" "$SRC_DIR/unbound"
    clone_repo "https://github.com/usememos/memos.git" "$SRC_DIR/memos"
    clone_repo "https://github.com/redlib-org/redlib.git" "$SRC_DIR/redlib"
    clone_repo "https://github.com/iv-org/invidious-companion.git" "$SRC_DIR/invidious-companion"
    clone_repo "https://github.com/wg-easy/wg-easy.git" "$SRC_DIR/wg-easy"
    clone_repo "https://github.com/portainer/portainer.git" "$SRC_DIR/portainer"

    # Setup Hub API
    $SUDO mkdir -p "$SRC_DIR/hub-api"
    cat > "$SRC_DIR/hub-api/Dockerfile" <<EOF
FROM python:3.11-alpine3.21
RUN apk add --no-cache docker-cli docker-cli-compose openssl netcat-openbsd curl git
WORKDIR /app
CMD ["python", "server.py"]
EOF

    # Configure Wikiless
    cat > "$SRC_DIR/wikiless/wikiless.config" <<'EOF'
const config = {
  domain: process.env.DOMAIN || '', 
  default_lang: process.env.DEFAULT_LANG || 'en', 
  theme: process.env.THEME || 'dark', 
  http_addr: process.env.HTTP_ADDR || '0.0.0.0', 
  nonssl_port: process.env.NONSSL_PORT || 8080, 
  redis_url: process.env.REDIS_URL || process.env.REDIS_HOST || 'redis://127.0.0.1:6379',
  redis_password: process.env.REDIS_PASSWORD,
  trust_proxy: process.env.TRUST_PROXY === 'true' || true,
  trust_proxy_address: process.env.TRUST_PROXY_ADDRESS || '127.0.0.1',
  setexs: {
    wikipage: process.env.WIKIPAGE_CACHE_EXPIRATION || (60 * 60 * 1), 
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

