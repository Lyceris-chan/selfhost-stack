#!/usr/bin/env bash
set -euo pipefail

# --- Constants ---
readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ASSETS_DIR="${ROOT_DIR}/assets"
readonly UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

log() {
	printf '[setup-assets] %s\n' "$*"
}

mkdir -p "$ASSETS_DIR"

if [[ -d "../data/AppData/privacy-hub/assets" ]] && [[ ! -s "$ASSETS_DIR/ms.css" ]]; then
	log "Copying assets from ../data/AppData/privacy-hub/assets"
	cp -a ../data/AppData/privacy-hub/assets/. "$ASSETS_DIR/" || true
fi

readonly URL_GS_PRIMARY="https://fontlay.com/css2?family=Google+Sans+Flex:wght@400;500;600;700&display=swap"
readonly URL_CC_PRIMARY="https://fontlay.com/css2?family=Cascadia+Code:ital,wght@0,200..700;1,200..700&display=swap"
readonly URL_MS_PRIMARY="https://fontlay.com/css2?family=Material+Symbols+Rounded:opsz,wght,FILL,GRAD@20..48,100..700,0..1,-50..200&display=swap"
readonly URL_MCU_PRIMARY="https://cdn.jsdelivr.net/npm/@material/material-color-utilities@0.3.0/+esm"
readonly URL_QR_PRIMARY="https://cdn.jsdelivr.net/npm/qrcode@1.5.4/lib/browser.min.js"
readonly SHA_MCU="3U1awaKd5cEaag6BP1vFQ7y/99n+Iz/n/QiGuRX0BmKncek9GxW6I42Enhwn9QN9"
readonly SHA_QR="2uWjh7bYzfKGVoVDTonR9UW20rvRGIIgp0ejV/Vp8fmJKrzAiL4PBfmj37qqgatV"

download_css() {
	local dest="$1"
	local primary="$2"

	if curl -fsSL -A "$UA" "$primary" -o "$dest"; then
		return 0
	fi

	log "Asset source failed: $primary"
	return 1
}

download_js() {
	local dest="$1"
	local url="$2"
	local expected_sha="$3"
	local actual_sha

	if curl -fsSL -A "$UA" "$url" -o "$dest"; then
		actual_sha=$(openssl dgst -sha384 -binary "$dest" | openssl base64 -A)
		if [[ "$actual_sha" == "$expected_sha" ]]; then
			log "Verified checksum for $(basename "$dest")"
			return 0
		else
			log "Checksum mismatch for $(basename "$dest")! Got $actual_sha"
			rm -f "$dest"
			return 1
		fi
	fi
	log "Failed to download: $url"
	return 1
}

if [[ ! -s "$ASSETS_DIR/gs.css" ]]; then
	download_css "$ASSETS_DIR/gs.css" "$URL_GS_PRIMARY" || true
fi

if [[ ! -s "$ASSETS_DIR/cc.css" ]]; then
	download_css "$ASSETS_DIR/cc.css" "$URL_CC_PRIMARY" || true
fi

if [[ ! -s "$ASSETS_DIR/ms.css" ]]; then
	download_css "$ASSETS_DIR/ms.css" "$URL_MS_PRIMARY" || true
fi

if [[ ! -s "$ASSETS_DIR/mcu.js" ]]; then
	download_js "$ASSETS_DIR/mcu.js" "$URL_MCU_PRIMARY" "$SHA_MCU" || true
fi

if [[ ! -s "$ASSETS_DIR/qrcode.min.js" ]]; then
	download_js "$ASSETS_DIR/qrcode.min.js" "$URL_QR_PRIMARY" "$SHA_QR" || true
fi

css_origin() {
	echo "$1" | sed -E 's#(https?://[^/]+).*#\1#'
}

download_fonts_from_css() {
	local css_file="$1"
	local origin="$2"
	local base_name="${css_file%.css}"

	if [[ ! -s "$css_file" ]]; then
		log "Skipping $css_file (missing or empty)."
		return
	fi

	# Find all url() references and extract JUST the content between parens
	grep -o "url([^)]*)" "$css_file" | sed -E 's/url\(["'\'']?([^"'\'')]+)["'\'']?\)/\1/' | sort | uniq | while read -r url; do
		if [[ -z "$url" ]]; then
			continue
		fi

		# Determine extension
		local ext="ttf"
		if [[ "$url" == *.woff2* ]]; then ext="woff2"; elif [[ "$url" == *.woff* ]]; then ext="woff"; fi

		local filename="${base_name}.${ext}"
		local fetch_url="$url"

		if [[ "$url" == //* ]]; then
			fetch_url="https:$url"
		elif [[ "$url" == /* ]]; then
			fetch_url="${origin}${url}"
		elif [[ "$url" != http* ]]; then
			fetch_url="${origin}/${url}"
		fi

		if [[ ! -f "$filename" ]]; then
			log "Downloading font $filename from $fetch_url"
			if ! curl -fsSL -A "$UA" "$fetch_url" -o "$filename"; then
				log "Failed to download asset: $filename"
				continue
			fi
		fi

		# Robust replacement
		sed -i "s|$url|$filename|g" "$css_file"
	done || true
}

cd "$ASSETS_DIR"
download_fonts_from_css "gs.css" "$(css_origin "$URL_GS_PRIMARY")"
download_fonts_from_css "cc.css" "$(css_origin "$URL_CC_PRIMARY")"
download_fonts_from_css "ms.css" "$(css_origin "$URL_MS_PRIMARY")"
cd - >/dev/null

if [[ ! -s "$ASSETS_DIR/privacy-hub.svg" ]]; then
	cat >"$ASSETS_DIR/privacy-hub.svg" <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" height="128" viewBox="0 -960 960 960" width="128" fill="#D0BCFF">
    <path d="M480-80q-139-35-229.5-159.5S160-516 160-666v-134l320-120 320 120v134q0 151-90.5 275.5T480-80Zm0-84q104-33 172-132t68-210v-105l-240-90-240 90v105q0 111 68 210t172 132Zm0-316Z"/>
</svg>
EOF
fi

log "Assets ready in $ASSETS_DIR"

if [ ! -s "$ASSETS_DIR/privacy-hub.svg" ]; then
	cat >"$ASSETS_DIR/privacy-hub.svg" <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" height="128" viewBox="0 -960 960 960" width="128" fill="#D0BCFF">
    <path d="M480-80q-139-35-229.5-159.5S160-516 160-666v-134l320-120 320 120v134q0 151-90.5 275.5T480-80Zm0-84q104-33 172-132t68-210v-105l-240-90-240 90v105q0 111 68 210t172 132Zm0-316Z"/>
</svg>
EOF
fi

log "Assets ready in $ASSETS_DIR"
