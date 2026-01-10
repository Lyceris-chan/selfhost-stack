import os
import subprocess
import shutil
import stat

# Configuration
TEMP_DIR = "temp_verification"
SRC_DIR = os.path.join(TEMP_DIR, "sources")
PATCHES_SCRIPT = os.path.join(TEMP_DIR, "patches.sh")

# Repositories to clone
REPOS = [
    ("https://github.com/Metastem/Wikiless", "wikiless"),
    ("https://git.sr.ht/~edwardloveall/scribe", "scribe"),
    ("https://github.com/iv-org/invidious.git", "invidious"),
    ("https://github.com/Lyceris-chan/odido-bundle-booster.git", "odido-bundle-booster"),
    ("https://github.com/VERT-sh/VERT.git", "vert"),
    ("https://github.com/VERT-sh/vertd.git", "vertd"),
    ("https://codeberg.org/rimgo/rimgo.git", "rimgo"),
    ("https://github.com/PussTheCat-org/docker-breezewiki-quay.git", "breezewiki"),
    ("https://github.com/httpjamesm/AnonymousOverflow.git", "anonymousoverflow"),
    ("https://github.com/qdm12/gluetun.git", "gluetun"),
    ("https://github.com/AdguardTeam/AdGuardHome.git", "adguardhome"),
    ("https://github.com/klutchell/unbound-docker.git", "unbound"),
    ("https://github.com/usememos/memos.git", "memos"),
    ("https://github.com/redlib-org/redlib.git", "redlib"),
    ("https://github.com/iv-org/invidious-companion.git", "invidious-companion"),
    ("https://github.com/wg-easy/wg-easy.git", "wg-easy"),
    ("https://github.com/portainer/portainer.git", "portainer"),
]

PATCHABLE_SERVICES = "wikiless scribe invidious odido-booster vert rimgo anonymousoverflow gluetun adguard unbound memos redlib wg-easy portainer dashboard"

def run_command(command, cwd=None, shell=False):
    try:
        subprocess.check_call(command, cwd=cwd, shell=shell)
    except subprocess.CalledProcessError as e:
        print(f"Error running command: {command}")
        raise e

def clone_repos():
    if os.path.exists(SRC_DIR):
        shutil.rmtree(SRC_DIR)
    os.makedirs(SRC_DIR)

    for url, name in REPOS:
        print(f"Cloning {name} from {url}...")
        target_path = os.path.join(SRC_DIR, name)
        try:
            run_command(["git", "clone", "--depth", "1", url, target_path])
        except Exception as e:
            print(f"Failed to clone {name}: {e}")

def preprocess_adguard():
    print("Preprocessing AdGuardHome...")
    adguard_dir = os.path.join(SRC_DIR, "adguardhome")
    if not os.path.exists(adguard_dir):
        print("AdGuardHome directory not found, skipping preprocessing.")
        return

    # Remove .dockerignore
    dockerignore = os.path.join(adguard_dir, ".dockerignore")
    if os.path.exists(dockerignore):
        os.remove(dockerignore)

    # Patch Webpack config
    for f in ["client/webpack.prod.js", "client/webpack.dev.js"]:
        path = os.path.join(adguard_dir, f)
        if os.path.exists(path):
            with open(path, 'r') as file:
                content = file.read()
            content = content.replace('[hash]', '[fullhash]')
            with open(path, 'w') as file:
                file.write(content)

    # Create Dockerfile.alpine
    dockerfile_alpine = os.path.join(adguard_dir, "Dockerfile.alpine")
    with open(dockerfile_alpine, 'w') as f:
        f.write(r"""
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
""")

def create_patches_script():
    print("Creating patches.sh...")
    content = r"""#!/bin/sh
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

    # [2] Base Image (Alpine)
    # Only replace if it is already an Alpine base to ensure package manager compatibility
    # if grep -qiE "^FROM[[:space:]]+alpine:" "$file"; then
    #    sed -i -E 's/^FROM[[:space:]]+alpine:[^[:space:]]*/FROM alpine:latest/gI' "$file"
    # fi
    
    # [3] Runtimes (Only if they are alpine-based runtimes)
    # sed -i -E 's/^FROM[[:space:]]+node:[0-9.]+-alpine[^[:space:]]*/FROM node:20-alpine/gI' "$file"
    # sed -i -E 's/^FROM[[:space:]]+golang:[0-9.]+-alpine[^[:space:]]*/FROM golang:1-alpine/gI' "$file"
    # sed -i -E 's/^FROM[[:space:]]+python:[0-9.]+-alpine[^[:space:]]*/FROM python:3.11-alpine/gI' "$file"
    # sed -i -E 's/^FROM[[:space:]]+rust:[0-9.]+-alpine[^[:space:]]*/FROM rust:1-alpine/gI' "$file"
    # sed -i -E 's/^FROM[[:space:]]+oven\/bun:[0-9.]+-alpine[^[:space:]]*/FROM bun:1-alpine/gI' "$file"

    # [4] Package Manager (apt -> apk) - ONLY if we are sure we are on Alpine now
    if grep -qiE "^FROM[[:space:]]+alpine:" "$file"; then
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
        
        # Switch to Alpine 3.21 (Racket 8.15+)
        sed -i 's|^FROM .*|FROM alpine:3.21|g' "$SRC_ROOT/breezewiki/$D_FILE"
        
        # Inject Alpine dependencies and build commands
        # We need: git (clone), racket (runtime), build-base/libffi-dev (compilation)
        sed -i '/RUN apt update/,/raco req -d/c\
RUN apk add --no-cache git racket ca-certificates curl sqlite-libs fontconfig cairo libjpeg-turbo glib pango build-base libffi-dev \ \ 
    && git clone --depth=1 https://gitdab.com/cadence/breezewiki.git . \ 
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
             sed -i 's|^FROM nvidia/cuda:[^ ]*|FROM alpine:3.20|g' "$SRC_ROOT/vertd/$D_FILE"
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
        
        # Fix user creation in Alpine (add group first)
        sed -i 's/adduser -u 10001 -S appuser/addgroup -S appuser && adduser -u 10001 -S -G appuser appuser/' "$SRC_ROOT/invidious-companion/$D_FILE"
        sed -i 's/useradd --uid 1993 --user-group deno/addgroup -g 1993 -S deno && adduser -u 1993 -S -G deno deno/' "$SRC_ROOT/invidious-companion/$D_FILE"

        # Fix dpkg dependency in Alpine
        sed -i "s/dpkg --print-architecture/uname -m | sed -e 's\/x86_64\/amd64\/' -e 's\/aarch64\/arm64\/'/" "$SRC_ROOT/invidious-companion/$D_FILE"

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
        sed -i 's/^FROM debian:.* AS dependabot-debian/FROM alpine:latest AS dependabot-debian/' "$SRC_ROOT/invidious-companion/$D_FILE"
        
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
        if grep -q "alpine:" "$SRC_ROOT/gluetun/$D_FILE"; then
            sed -i '/FROM alpine:/a RUN echo "3.22.0" > /etc/alpine-release' "$SRC_ROOT/gluetun/$D_FILE"
        fi

        # Simplify OpenVPN installation to avoid version mixing issues
        # Replace the entire multi-line RUN block starting with apk add --no-cache --update -l wget
        sed -i '/RUN apk add --no-cache --update -l wget/,/mkdir \/gluetun/c\\RUN apk add --no-cache --update wget openvpn iptables iptables-legacy tzdata && ln -s /usr/sbin/openvpn /usr/sbin/openvpn2.5 && ln -s /usr/sbin/openvpn /usr/sbin/openvpn2.6 && mkdir /gluetun' "$SRC_ROOT/gluetun/$D_FILE"
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
"""
    with open(PATCHES_SCRIPT, 'w') as f:
        f.write(content)
    
    st = os.stat(PATCHES_SCRIPT)
    os.chmod(PATCHES_SCRIPT, st.st_mode | stat.S_IEXEC)

def main():
    clone_repos()
    preprocess_adguard()
    create_patches_script()
    
    print("Running patches.sh...")
    env = os.environ.copy()
    env["PATCHABLE_SERVICES"] = PATCHABLE_SERVICES
    
    # Use absolute paths to avoid confusion with cwd
    abs_patches_script = os.path.abspath(PATCHES_SCRIPT)
    abs_src_dir = os.path.abspath(SRC_DIR)
    
    try:
        run_command([abs_patches_script, "all", abs_src_dir], cwd=TEMP_DIR, shell=False)
        print("Patches applied successfully.")
    except Exception as e:
        print(f"Patches failed: {e}")

if __name__ == "__main__":
    main()
