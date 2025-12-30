#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS_DIR="${ROOT_DIR}/assets"
UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

log() {
  printf '[setup-assets] %s\n' "$*"
}

mkdir -p "$ASSETS_DIR"

if [ -d "../data/AppData/privacy-hub/assets" ] && [ ! -s "$ASSETS_DIR/ms.css" ]; then
  log "Copying assets from ../data/AppData/privacy-hub/assets"
  cp -a ../data/AppData/privacy-hub/assets/. "$ASSETS_DIR/" || true
fi

URL_GS_PRIMARY="https://fontlay.com/css2?family=Google+Sans+Flex:wght@400;500;600;700&display=swap"
URL_GS_FALLBACK="https://fonts.googleapis.com/css2?family=Google+Sans+Flex:wght@400;500;600;700&display=swap"
URL_CC_PRIMARY="https://fontlay.com/css2?family=Cascadia+Code:ital,wght@0,200..700;1,200..700&display=swap"
URL_CC_FALLBACK="https://fonts.googleapis.com/css2?family=Cascadia+Code:ital,wght@0,200..700;1,200..700&display=swap"
URL_MS_PRIMARY="https://fontlay.com/css2?family=Material+Symbols+Rounded:opsz,wght,FILL,GRAD@20..48,100..700,0..1,-50..200&display=swap"
URL_MS_FALLBACK="https://fonts.googleapis.com/css2?family=Material+Symbols+Rounded:opsz,wght,FILL,GRAD@20..48,100..700,0..1,-50..200&display=swap"
URL_MCU_PRIMARY="https://cdn.jsdelivr.net/npm/@material/material-color-utilities@0.3.0/dist/material-color-utilities.min.js"

GS_CSS_URL="$URL_GS_PRIMARY"
CC_CSS_URL="$URL_CC_PRIMARY"
MS_CSS_URL="$URL_MS_PRIMARY"

download_css() {
  local dest="$1"
  local primary="$2"
  local fallback="$3"
  local varname="$4"

  printf -v "$varname" '%s' "$primary"
  if curl -fsSL -A "$UA" "$primary" -o "$dest"; then
    return 0
  fi

  log "Asset source failed: $primary"
  if [ -n "$fallback" ]; then
    printf -v "$varname" '%s' "$fallback"
    if curl -fsSL -A "$UA" "$fallback" -o "$dest"; then
      return 0
    fi
    log "Fallback asset source failed: $fallback"
  fi
  return 1
}

download_js() {
  local dest="$1"
  local url="$2"

  if curl -fsSL -A "$UA" "$url" -o "$dest"; then
    return 0
  fi
  log "Failed to download: $url"
  return 1
}

if [ ! -s "$ASSETS_DIR/gs.css" ]; then
  download_css "$ASSETS_DIR/gs.css" "$URL_GS_PRIMARY" "$URL_GS_FALLBACK" GS_CSS_URL || true
fi

if [ ! -s "$ASSETS_DIR/cc.css" ]; then
  download_css "$ASSETS_DIR/cc.css" "$URL_CC_PRIMARY" "$URL_CC_FALLBACK" CC_CSS_URL || true
fi

if [ ! -s "$ASSETS_DIR/ms.css" ]; then
  download_css "$ASSETS_DIR/ms.css" "$URL_MS_PRIMARY" "$URL_MS_FALLBACK" MS_CSS_URL || true
fi

if [ ! -s "$ASSETS_DIR/mcu.js" ]; then
  download_js "$ASSETS_DIR/mcu.js" "$URL_MCU_PRIMARY" || true
fi

css_origin() {
  echo "$1" | sed -E 's#(https?://[^/]+).*#\1#'
}

download_fonts_from_css() {
  local css_file="$1"
  local origin="$2"

  if [ ! -s "$css_file" ]; then
    log "Skipping $css_file (missing or empty)."
    return
  fi

  grep -o "url([^)]*)" "$css_file" | sed 's/url(//;s/)//' | tr -d "'\"" | sort | uniq | while read -r url; do
    if [ -z "$url" ]; then
      continue
    fi
    local filename
    filename=$(basename "$url")
    local clean_name="${filename%%\?*}"
    local fetch_url="$url"

    if [[ "$url" == //* ]]; then
      fetch_url="https:$url"
    elif [[ "$url" == /* ]]; then
      fetch_url="${origin}${url}"
    elif [[ "$url" != http* ]]; then
      fetch_url="${origin}/${url}"
    fi

    if [ ! -f "$clean_name" ]; then
      if ! curl -fsSL -A "$UA" "$fetch_url" -o "$clean_name"; then
        log "Failed to download asset: $clean_name"
        continue
      fi
    fi

    local escaped_url
    escaped_url=$(echo "$url" | sed 's/[\\/&|]/\\\\&/g')
    sed -i "s|url(['\"]\\{0,1\\}${escaped_url}['\"]\\{0,1\\})|url(${clean_name})|g" "$css_file"
  done || true
}

cd "$ASSETS_DIR"
download_fonts_from_css "gs.css" "$(css_origin "$GS_CSS_URL")"
download_fonts_from_css "cc.css" "$(css_origin "$CC_CSS_URL")"
download_fonts_from_css "ms.css" "$(css_origin "$MS_CSS_URL")"
cd - >/dev/null

if [ ! -s "$ASSETS_DIR/privacy-hub.svg" ]; then
  cat > "$ASSETS_DIR/privacy-hub.svg" <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" height="128" viewBox="0 -960 960 960" width="128" fill="#D0BCFF">
    <path d="M480-80q-139-35-229.5-159.5S160-516 160-666v-134l320-120 320 120v134q0 151-90.5 275.5T480-80Zm0-84q104-33 172-132t68-210v-105l-240-90-240 90v105q0 111 68 210t172 132Zm0-316Z"/>
</svg>
EOF
fi

log "Assets ready in $ASSETS_DIR"
