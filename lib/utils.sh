#!/usr/bin/env bash

# Logging Functions
log_info() { 
    echo -e "\e[34m[INFO]\e[0m $1"
    if [ -d "$(dirname "$HISTORY_LOG")" ]; then
        echo "$(date) [INFO] $1" >> "$HISTORY_LOG" 2>/dev/null || true
    fi
}
log_warn() { 
    echo -e "\e[33m[WARN]\e[0m $1"
    if [ -d "$(dirname "$HISTORY_LOG")" ]; then
        echo "$(date) [WARN] $1" >> "$HISTORY_LOG" 2>/dev/null || true
    fi
}
log_crit() { 
    echo -e "\e[31m[CRIT]\e[0m $1"
    if [ -d "$(dirname "$HISTORY_LOG")" ]; then
        echo "$(date) [CRIT] $1" >> "$HISTORY_LOG" 2>/dev/null || true
    fi
}

ask_confirm() {
    if [ "$AUTO_CONFIRM" = true ]; then return 0; fi
    read -r -p "$1 [y/N]: " response
    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

pull_with_retry() {
    local img=$1
    local max_retries=3
    local count=0
    while [ $count -lt $max_retries ]; do
        if $DOCKER_CMD pull "$img" >/dev/null 2>&1; then
            log_info "Successfully pulled $img"
            return 0
        fi
        count=$((count + 1))
        log_warn "Failed to pull $img. Retrying ($count/$max_retries)..."
        sleep 1
    done
    log_crit "Failed to pull critical image $img after $max_retries attempts."
    return 1
}

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


