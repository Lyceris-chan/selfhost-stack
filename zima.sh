#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2001,SC2015,SC2016,SC2034,SC2024,SC2086
set -euo pipefail

# ==============================================================================
# 🛡️ ZIMAOS PRIVACY HUB: SECURE NETWORK STACK
# ==============================================================================
# This deployment provides a self-hosted network security environment.
# Digital independence requires ownership of the hardware and software that 
# manages your data.
#
# Core Components:
# - WireGuard: Secure remote access gateway for untrusted networks.
# - AdGuard Home + Unbound: Recursive, filtered DNS resolution for 
#   independent network visibility.
# - Privacy Frontends: Clean, telemetry-free interfaces for web services.
#
# ESTABLISH CONTROL. MAINTAIN PRIVACY.
# ==============================================================================

# --- SECTION 0: ARGUMENT PARSING & INITIALIZATION ---
usage() {
    echo "Usage: $0 [-c (reset environment)] [-x (cleanup and exit)] [-p (auto-passwords)] [-y (auto-confirm)] [-a (allow Proton VPN)] [-s services)] [-D (dashboard only)] [-h]"
}

FORCE_CLEAN=false
CLEAN_ONLY=false
AUTO_PASSWORD=false
CLEAN_EXIT=false
RESET_ENV=false
AUTO_CONFIRM=false
ALLOW_PROTON_VPN=false
SELECTED_SERVICES=""
DASHBOARD_ONLY=false

while getopts "cxpyas:Dh" opt; do
    case ${opt} in
        c) RESET_ENV=true; FORCE_CLEAN=true ;;
        x) CLEAN_EXIT=true; RESET_ENV=true; CLEAN_ONLY=true; FORCE_CLEAN=true ;;
        p) AUTO_PASSWORD=true ;;
        y) AUTO_CONFIRM=true ;;
        a) ALLOW_PROTON_VPN=true ;;
        s) SELECTED_SERVICES="${OPTARG}" ;;
        D) DASHBOARD_ONLY=true ;;
        h) 
            usage
            exit 0
            ;;
        *) usage; exit 1 ;;
    esac
done
shift $((OPTIND -1))

# --- SECTION 1: ENVIRONMENT VALIDATION & DIRECTORY SETUP ---
# Verify core dependencies before proceeding.
REQUIRED_COMMANDS="docker curl git crontab iptables flock"
for cmd in $REQUIRED_COMMANDS; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "[CRIT] '$cmd' is required but not installed. Please install it."
        exit 1
    fi
done

# Docker Compose Check (Plugin or Standalone)
if docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    if docker-compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE_CMD="docker-compose"
    else
        echo "[CRIT] Docker Compose is installed but not executable."
        exit 1
    fi
else
    echo "[CRIT] Docker Compose v2 is required. Please update your environment."
    exit 1
fi

APP_NAME="privacy-hub"
BASE_DIR="/DATA/AppData/$APP_NAME"

# Docker Auth Config (stored in /tmp to survive -c cleanup)
DOCKER_AUTH_DIR="/tmp/$APP_NAME-docker-auth"
# Ensure clean state for auth
if [ -d "$DOCKER_AUTH_DIR" ]; then
    sudo rm -rf "$DOCKER_AUTH_DIR"
fi
mkdir -p "$DOCKER_AUTH_DIR"
sudo chown -R "$(whoami)" "$DOCKER_AUTH_DIR"

# Detect Python interpreter
if command -v python3 >/dev/null 2>&1; then
    PYTHON_CMD="python3"
elif command -v python >/dev/null 2>&1; then
    PYTHON_CMD="python"
else
    echo "[CRIT] Python is required but not installed. Please install python3."
    exit 1
fi

# Define consistent docker command using custom config for auth
DOCKER_CMD="sudo env DOCKER_CONFIG=$DOCKER_AUTH_DIR docker"

# Paths
SRC_DIR="$BASE_DIR/sources"
ENV_DIR="$BASE_DIR/env"
CONFIG_DIR="$BASE_DIR/config"
DATA_DIR="$BASE_DIR/data"
COMPOSE_FILE="$BASE_DIR/docker-compose.yml"
DASHBOARD_FILE="$BASE_DIR/dashboard.html"
GLUETUN_ENV_FILE="$BASE_DIR/gluetun.env"
ASSETS_DIR="$BASE_DIR/assets"
HISTORY_LOG="$BASE_DIR/deployment.log"

# Initialize deSEC variables to prevent unbound variable errors
DESEC_DOMAIN=""
DESEC_TOKEN=""
DESEC_MONITOR_DOMAIN=""
DESEC_MONITOR_TOKEN=""
SCRIBE_GH_USER=""
SCRIBE_GH_TOKEN=""
ODIDO_USER_ID=""
ODIDO_TOKEN=""
ODIDO_API_KEY=""
WG_HASH_CLEAN=""
FOUND_OCTET=""

# WireGuard Profiles
WG_PROFILES_DIR="$BASE_DIR/wg-profiles"
ACTIVE_WG_CONF="$BASE_DIR/active-wg.conf"
ACTIVE_PROFILE_NAME_FILE="$BASE_DIR/.active_profile_name"
mkdir -p "$WG_PROFILES_DIR"

# Service Configurations
NGINX_CONF_DIR="$CONFIG_DIR/nginx"
NGINX_CONF="$NGINX_CONF_DIR/default.conf"
UNBOUND_CONF="$CONFIG_DIR/unbound/unbound.conf"
AGH_CONF_DIR="$CONFIG_DIR/adguard"
AGH_YAML="$AGH_CONF_DIR/AdGuardHome.yaml"

# Scripts
MONITOR_SCRIPT="$BASE_DIR/wg-ip-monitor.sh"
IP_LOG_FILE="$BASE_DIR/wg-ip-monitor.log"
CURRENT_IP_FILE="$BASE_DIR/.current_public_ip"
WG_CONTROL_SCRIPT="$BASE_DIR/wg-control.sh"
WG_API_SCRIPT="$BASE_DIR/wg-api.py"
CERT_MONITOR_SCRIPT="$BASE_DIR/cert-monitor.sh"
MIGRATE_SCRIPT="$BASE_DIR/migrate.sh"

# Memos storage
MEMOS_HOST_DIR="/DATA/AppData/memos"
mkdir -p "$MEMOS_HOST_DIR"

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

# --- SECTION 2: CLEANUP & ENVIRONMENT RESET ---
# Functions to clear out existing garbage for a clean start.
ask_confirm() {
    if [ "$AUTO_CONFIRM" = true ]; then return 0; fi
    read -r -p "$1 [y/N]: " response
    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

safe_remove_network() {
    local net="$1"
    local endpoints=""
    endpoints=$($DOCKER_CMD network inspect -f '{{range $id, $conf := .Containers}}{{printf "%s\n" $conf.Name}}{{end}}' "$net" 2>/dev/null || true)
    if [ -n "$endpoints" ]; then
        log_warn "  Network $net has active endpoints; disconnecting."
        for endpoint in $endpoints; do
            $DOCKER_CMD network disconnect -f "$net" "$endpoint" 2>/dev/null || true
        done
    fi
    $DOCKER_CMD network rm "$net" 2>/dev/null || true
}

authenticate_registries() {
if [ "$DASHBOARD_ONLY" = true ]; then
    log_info "Dashboard-only mode active. Skipping installation and only generating UI."
    LAN_IP="${LAN_IP:-10.0.1.183}"
    PUBLIC_IP="${PUBLIC_IP:-1.2.3.4}"
    ODIDO_API_KEY="${ODIDO_API_KEY:-mock_key}"
    mkdir -p "$BASE_DIR"
    mkdir -p "$ASSETS_DIR"
    generate_dashboard
    log_info "Dashboard generation complete. Exiting."
    exit 0
fi
generate_dashboard() {
# Generate the Material Design 3 management dashboard.
log_info "Compiling Management Dashboard UI..."
cat > "$DASHBOARD_FILE" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ZimaOS Privacy Hub</title>
    <link rel="icon" type="image/svg+xml" href="assets/privacy-hub.svg">
    <!-- Local privacy friendly assets (Hosted Locally) -->
    <link href="assets/gs.css" rel="stylesheet">
    <link href="assets/cc.css" rel="stylesheet">
    <link href="assets/ms.css" rel="stylesheet">
    <script>
        // HTTPS Auto-Switch & Default Logic
        const isLocalHost = (window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1');
        const isIpHost = window.location.hostname.match(/^\d+\.\d+\.\d+\.\d+$/);
        if (window.location.protocol === 'http:' && !isLocalHost && !isIpHost) {
            const httpsPort = '8443';
            const httpsUrl = 'https://' + window.location.hostname + ':' + httpsPort + window.location.pathname + window.location.search;
            // Only redirect if we're not on a standard port or if specifically requested
            // Use a small delay to ensure page load doesnt flicker
            setTimeout(() => {
                fetch(httpsUrl, { mode: 'no-cors' }).then(() => {
                    window.location.href = httpsUrl;
                }).catch(() => {
                    console.log("HTTPS port not reachable, staying on HTTP");
                });
            }, 500);
        }
        
        // Prevent extension injection errors - defined early
        globalThis.configureInjection = globalThis.configureInjection || (() => {});
    </script>
    <script type="module">
        import * as MaterialColorUtilities from './assets/mcu.js';
        window.MaterialColorUtilities = MaterialColorUtilities;
    </script>
    <style>
        /* Alignment & Flicker Fixes */
        .card, .chip, .btn {
            backface-visibility: hidden;
            transform: translateZ(0);
            -webkit-font-smoothing: subpixel-antialiased;
        }
        
        /* Admin Mode Controls */
        .admin-only {
            display: none !important;
        }
        body.admin-mode .admin-only {
            display: flex !important;
        }
        body.admin-mode .admin-only.btn-icon {
            display: inline-flex !important;
        }
        body.admin-mode .admin-only.chip {
            display: inline-flex !important;
        }
        body.admin-mode .admin-only.section-label, 
        body.admin-mode .admin-only.section-hint {
            display: block !important;
        }
        
        .filter-bar {
            display: flex;
            gap: 8px;
            margin-bottom: 24px;
            overflow-x: auto;
            padding: 4px;
            scrollbar-width: none;
            position: sticky;
            top: 0;
            z-index: 100;
            background: var(--md-sys-color-surface);
            border-bottom: 1px solid var(--md-sys-color-outline-variant);
            flex-wrap: wrap;
        }
        .filter-bar::-webkit-scrollbar { display: none; }
        
        .filter-chip {
            cursor: pointer;
            user-select: none;
            transition: all 200ms ease;
        }
        .filter-chip.active {
            background: var(--md-sys-color-primary-container) !important;
            color: var(--md-sys-color-on-primary-container) !important;
            border-color: var(--md-sys-color-primary) !important;
        }

        @media (max-width: 720px) {
            .filter-bar {
                flex-wrap: nowrap;
                overflow-x: auto;
            }
            .filter-chip {
                flex: 0 0 auto;
            }
        }
        
        section {
            display: block;
            opacity: 1;
            transition: opacity 200ms ease-in-out;
        }
        section.hidden {
            display: none;
            opacity: 0;
        }
        
        /* Ensure chips don't flicker during hover */
        .chip:hover {
            transform: translateY(-1px);
            box-shadow: var(--md-sys-elevation-1);
        }
        /* ============================================
           Material 3 Dark Theme - Strict Implementation
           Reference: https://m3.material.io/
           ============================================ */
        
        :root {
            color-scheme: dark;
            /* M3 Dark Theme Color Tokens (Default) */
            --md-sys-color-primary: #D0BCFF;
            --md-sys-color-on-primary: #381E72;
            --md-sys-color-primary-container: #4F378B;
            --md-sys-color-on-primary-container: #EADDFF;
            --md-sys-color-secondary: #CCC2DC;
            --md-sys-color-on-secondary: #332D41;
            --md-sys-color-secondary-container: #4A4458;
            --md-sys-color-on-secondary-container: #E8DEF8;
            --md-sys-color-tertiary: #EFB8C8;
            --md-sys-color-on-tertiary: #492532;
            --md-sys-color-tertiary-container: #633B48;
            --md-sys-color-on-tertiary-container: #FFD8E4;
            --md-sys-color-error: #F2B8B5;
            --md-sys-color-on-error: #601410;
            --md-sys-color-error-container: #8C1D18;
            --md-sys-color-on-error-container: #F9DEDC;
            --md-sys-color-surface: #141218;
            --md-sys-color-on-surface: #E6E1E5;
            --md-sys-color-surface-variant: #49454F;
            --md-sys-color-on-surface-variant: #CAC4D0;
            --md-sys-color-surface-container-low: #1D1B20;
            --md-sys-color-surface-container: #211F26;
            --md-sys-color-surface-container-high: #2B2930;
            --md-sys-color-surface-container-highest: #36343B;
            --md-sys-color-surface-bright: #3B383E;
            --md-sys-color-outline: #938F99;
            --md-sys-color-outline-variant: #49454F;
            --md-sys-color-inverse-surface: #E6E1E5;
            --md-sys-color-inverse-on-surface: #313033;
            --md-sys-color-success: #A8DAB5;
            --md-sys-color-on-success: #003912;
            --md-sys-color-success-container: #00522B;
            --md-sys-color-warning: #FFCC80;
            --md-sys-color-on-warning: #4A2800;

            /* MD3 Expressive Motion */
            --md-sys-motion-easing-emphasized: cubic-bezier(0.2, 0.0, 0, 1.0);
            --md-sys-motion-duration-short: 150ms;
            --md-sys-motion-duration-medium: 300ms;
            --md-sys-motion-duration-long: 500ms;
            
            /* MD3 Expressive Shapes */
            --md-sys-shape-corner-extra-large: 28px;
            --md-sys-shape-corner-large: 16px;
            --md-sys-shape-corner-medium: 12px;
            --md-sys-shape-corner-small: 8px;
            --md-sys-shape-corner-full: 100px;

            /* Elevation */
            --md-sys-elevation-1: 0 1px 3px 1px rgba(0,0,0,0.15), 0 1px 2px rgba(0,0,0,0.3);
            --md-sys-elevation-2: 0 2px 6px 2px rgba(0,0,0,0.15), 0 1px 2px rgba(0,0,0,0.3);
            --md-sys-elevation-3: 0 4px 8px 3px rgba(0,0,0,0.15), 0 1px 3px rgba(0,0,0,0.3);
            
            /* State Opacities */
            --md-sys-state-hover-opacity: 0.08;
            --md-sys-state-focus-opacity: 0.12;
            --md-sys-state-pressed-opacity: 0.12;
        }

        /* M3 Light Theme Tokens */
        :root.light-mode {
            color-scheme: light;
            --md-sys-color-primary: #6750A4;
            --md-sys-color-on-primary: #FFFFFF;
            --md-sys-color-primary-container: #EADDFF;
            --md-sys-color-on-primary-container: #21005D;
            --md-sys-color-secondary: #625B71;
            --md-sys-color-on-secondary: #FFFFFF;
            --md-sys-color-secondary-container: #E8DEF8;
            --md-sys-color-on-secondary-container: #1D192B;
            --md-sys-color-tertiary: #7D5260;
            --md-sys-color-on-tertiary: #FFFFFF;
            --md-sys-color-tertiary-container: #FFD8E4;
            --md-sys-color-on-tertiary-container: #31111D;
            --md-sys-color-error: #B3261E;
            --md-sys-color-on-error: #FFFFFF;
            --md-sys-color-error-container: #F9DEDC;
            --md-sys-color-on-error-container: #410E0B;
            --md-sys-color-surface: #FEF7FF;
            --md-sys-color-on-surface: #1D1B20;
            --md-sys-color-surface-variant: #E7E0EC;
            --md-sys-color-on-surface-variant: #49454F;
            --md-sys-color-surface-container-low: #F7F2FA;
            --md-sys-color-surface-container: #F3EDF7;
            --md-sys-color-surface-container-high: #ECE6F0;
            --md-sys-color-surface-container-highest: #E6E0E9;
            --md-sys-color-surface-bright: #FEF7FF;
            --md-sys-color-outline: #79747E;
            --md-sys-color-outline-variant: #C4C7C5;
            --md-sys-color-inverse-surface: #313033;
            --md-sys-color-inverse-on-surface: #F4EFF4;
            --md-sys-color-success: #2E7D32;
            --md-sys-color-on-success: #FFFFFF;
            --md-sys-color-success-container: #C8E6C9;
            --md-sys-color-warning: #ED6C02;
            --md-sys-color-on-warning: #FFFFFF;
            
            /* Adjust elevations for light mode */
            --md-sys-elevation-1: 0 1px 2px 0 rgba(0,0,0,0.3), 0 1px 3px 1px rgba(0,0,0,0.15);
            --md-sys-elevation-2: 0 1px 2px 0 rgba(0,0,0,0.3), 0 2px 6px 2px rgba(0,0,0,0.15);
        }
        
        * { box-sizing: border-box; margin: 0; padding: 0; }
        
        a {
            color: var(--md-sys-color-primary);
            text-decoration: none;
            transition: opacity var(--md-sys-motion-duration-short) linear;
        }
        
        a:hover {
            opacity: 0.8;
            text-decoration: underline;
        }
        
        body {
            background: var(--md-sys-color-surface);
            color: var(--md-sys-color-on-surface);
            font-family: 'Google Sans Flex', 'Google Sans', system-ui, -apple-system, sans-serif;
            margin: 0;
            padding: 24px;
            display: flex;
            flex-direction: column;
            align-items: center;
            min-height: 100vh;
            line-height: 1.6;
            -webkit-font-smoothing: antialiased;
            transition: background-color 300ms ease, color 300ms ease;
            overflow-x: hidden;
        }

        .code-block, .log-container, .text-field, .stat-value, .monospace {
            font-family: 'Cascadia Code', 'Consolas', monospace;
        }
        
        .material-symbols-rounded {
            font-family: 'Material Symbols Rounded';
            font-display: block;
            font-weight: normal;
            font-style: normal;
            font-size: 24px;
            line-height: 1;
            letter-spacing: normal;
            text-transform: none;
            display: inline-block;
            white-space: nowrap;
            word-wrap: normal;
            direction: ltr;
            -webkit-font-smoothing: antialiased;
        }

        .container { max-width: 1600px; width: 100%; margin: 0 auto; position: relative; }

        .full-bleed {
            width: 100vw;
            max-width: 100vw;
            margin-left: calc(50% - 50vw);
            margin-right: calc(50% - 50vw);
        }
        
        /* Header */
        header {
            margin-bottom: 56px;
            padding: 16px 0;
        }

        .header-row {
            display: flex;
            justify-content: space-between;
            align-items: center;
            gap: 24px;
            flex-wrap: wrap;
        }

        .header-row > div:first-child {
            flex: 1 1 auto;
        }
        
        h1 {
            font-family: 'Google Sans Flex', 'Google Sans', sans-serif;
            font-weight: 400;
            font-size: 45px;
            line-height: 52px;
            margin: 0;
            color: var(--md-sys-color-primary);
            letter-spacing: 0;
        }
        
        .subtitle {
            font-size: 22px;
            color: var(--md-sys-color-on-surface-variant);
            margin-top: 12px;
            font-weight: 400;
            letter-spacing: 0;
        }

        .label-large {
            font-size: 14px;
            line-height: 20px;
            font-weight: 500;
            letter-spacing: 0.1px;
        }

        .body-medium {
            font-size: 14px;
            line-height: 20px;
            letter-spacing: 0.25px;
        }

        .body-small {
            font-size: 12px;
            line-height: 16px;
            letter-spacing: 0.4px;
        }

        .code-label {
            font-size: 12px;
            line-height: 16px;
            letter-spacing: 0.4px;
            font-weight: 500;
            color: var(--md-sys-color-on-surface-variant);
            margin-top: 12px;
        }

        .profile-hint {
            color: var(--md-sys-color-on-surface-variant);
            margin-top: 12px;
        }

        .feedback {
            margin-top: 12px;
            padding: 8px 12px;
            border-radius: var(--md-sys-shape-corner-medium);
            background: var(--md-sys-color-surface-container-highest);
            color: var(--md-sys-color-on-surface-variant);
            font-size: 12px;
            line-height: 16px;
            letter-spacing: 0.4px;
        }

        .feedback.info { border: 1px solid var(--md-sys-color-outline-variant); }
        .feedback.success { background: var(--md-sys-color-success-container); color: var(--md-sys-color-on-success); }
        .feedback.error { background: var(--md-sys-color-error-container); color: var(--md-sys-color-on-error-container); }
        
        /* Section Labels */
        .section-label {
            color: var(--md-sys-color-primary);
            font-size: 14px;
            font-weight: 500;
            letter-spacing: 0.1px;
            margin: 48px 0 16px 4px;
            text-transform: none;
        }
        
        .section-label:first-of-type {
            margin-top: 8px;
        }
        
        .section-hint {
            font-size: 14px;
            color: var(--md-sys-color-on-surface-variant);
            margin: 0 0 24px 4px;
            letter-spacing: 0.25px;
            display: flex;
            gap: 12px;
            flex-wrap: wrap;
        }
        
        /* Grid Layouts - M3 Responsive (3x3, 4x4) */
        .grid { 
            display: grid; 
            grid-template-columns: repeat(auto-fit, minmax(min(100%, 300px), 1fr));
            gap: 24px; 
            margin-bottom: 32px; 
            width: 100%;
        }
        
        @media (min-width: 1200px) {
            .grid { grid-template-columns: repeat(auto-fit, minmax(340px, 1fr)); }
        }

        @media (min-width: 1600px) {
            .grid { grid-template-columns: repeat(auto-fit, minmax(350px, 1fr)); }
        }
        
        .grid-2 { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 450px), 1fr)); gap: 24px; margin-bottom: 32px; }
        .grid-3 { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 350px), 1fr)); gap: 24px; margin-bottom: 32px; }
        
        /* MD3 Component Refinements - Elevated Cards */
        .card {
            background: var(--md-sys-color-surface-container-low);
            border-radius: var(--md-sys-shape-corner-extra-large);
            padding: 32px;
            text-decoration: none;
            color: inherit;
            transition: all var(--md-sys-duration-medium) var(--md-sys-motion-easing-emphasized);
            position: relative;
            display: flex;
            flex-direction: column;
            min-height: 240px;
            overflow: visible; 
            box-sizing: border-box;
            box-shadow: var(--md-sys-elevation-1);
            height: 100%;
            cursor: pointer;
            contain: content;
            will-change: transform, box-shadow;
        }
        
        .card::before {
            content: '';
            position: absolute;
            inset: 0;
            border-radius: inherit;
            background: var(--md-sys-color-on-surface);
            opacity: 0;
            transition: opacity var(--md-sys-motion-duration-short) linear;
            pointer-events: none;
            z-index: 1;
        }
        
        .card:hover::before { opacity: var(--md-sys-state-hover-opacity); }
        .card:active::before { opacity: var(--md-sys-state-pressed-opacity); }

        .card:hover { 
            background: var(--md-sys-color-surface-container);
            box-shadow: var(--md-sys-elevation-2);
            transform: translateY(-4px);
        }
        
        /* Strict M3 Button & Chip States */
        .btn::before, .chip::before {
            content: '';
            position: absolute;
            inset: 0;
            background: currentColor;
            opacity: 0;
            transition: opacity var(--md-sys-motion-duration-short) linear;
            pointer-events: none;
        }

        .btn:hover::before, .chip:hover::before { opacity: 0.08; }
        .btn:active::before, .chip:active::before { opacity: 0.12; }
        .btn:focus::before, .chip:focus::before { opacity: 0.12; }

        .card.full-width { grid-column: 1 / -1; }
        
        .card-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 16px;
            gap: 12px;
            flex-wrap: wrap;
        }

        .card-header h2 {
            margin: 0;
            font-size: 20px;
            font-weight: 500;
            color: var(--md-sys-color-on-surface);
            line-height: 24px;
            flex: 1;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: normal;
        }

        .card-header-actions {
            display: flex;
            align-items: center;
            gap: 12px;
            flex-shrink: 0;
            margin-right: 4px;
        }

        .settings-btn {
        }

        .card .description {
            font-size: 14px;
            color: var(--md-sys-color-on-surface-variant);
            margin: 0 0 16px 0; /* Uniform vertical spacing */
            line-height: 20px;
            flex-grow: 1;
            display: -webkit-box;
            -webkit-line-clamp: 3;
            -webkit-box-orient: vertical;
            overflow: hidden;
        }
        
        .card h3 {
            margin: 0 0 16px 0;
            font-size: 16px; /* Title Medium */
            font-weight: 500;
            color: var(--md-sys-color-on-surface);
            line-height: 24px;
            letter-spacing: 0.15px;
        }
        
        /* MD3 Assist Chips - Intelligent Auto-layout */
        .chip-box { 
            display: flex;
            flex-wrap: wrap;
            gap: 8px; 
            padding-top: 12px;
            position: relative;
            z-index: 2;
            align-items: center;
            margin-top: auto;
            width: 100%;
        }
        
        .chip {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            gap: 8px; 
            height: 32px;
            padding: 0 16px;
            border-radius: 8px;
            font-size: 14px;
            font-weight: 500;
            font-family: inherit;
            letter-spacing: 0.1px;
            text-decoration: none;
            transition: all var(--md-sys-motion-duration-short) linear;
            border: 1px solid var(--md-sys-color-outline);
            background: transparent;
            color: var(--md-sys-color-on-surface);
            position: relative;
            overflow: hidden;
            white-space: nowrap;
            text-overflow: ellipsis;
            max-width: 100%;
            flex: 1 1 auto; /* Allow chips to grow and fill space */
        }

        .chip .material-symbols-rounded {
            font-size: 18px;
            pointer-events: none;
            transition: transform var(--md-sys-motion-duration-short) var(--md-sys-motion-easing-emphasized);
        }

        .chip:hover .material-symbols-rounded.move-on-hover {
            transform: translateX(4px);
        }
        
        .chip::before, .btn::before {
            content: '';
            position: absolute;
            inset: 0;
            background: currentColor;
            opacity: 0;
            transition: opacity var(--md-sys-motion-duration-short) linear;
            pointer-events: none;
        }
        
        .chip:hover::before, .btn:hover::before { opacity: var(--md-sys-state-hover-opacity); }
        .chip:active::before, .btn:active::before { opacity: var(--md-sys-state-pressed-opacity); }
        
        .chip.vpn { background: var(--md-sys-color-primary-container); color: var(--md-sys-color-on-primary-container); border: none; }
        .chip.admin { background: var(--md-sys-color-secondary-container); color: var(--md-sys-color-on-secondary-container); border: none; }
        .chip.tertiary { background: var(--md-sys-color-tertiary-container); color: var(--md-sys-color-on-tertiary-container); border: none; }
        
        /* Category Badges (Informational) */
        .category-badge {
            border: none;
            background: var(--md-sys-color-surface-container-high);
            color: var(--md-sys-color-on-surface-variant);
            padding: 0 12px 0 8px;
            pointer-events: none;
        }
        
        /* Status Indicator */
        .status-indicator {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            gap: 8px;
            background: var(--md-sys-color-surface-container-highest);
            padding: 6px 12px;
            border-radius: var(--md-sys-shape-corner-full);
            font-size: 12px;
            color: var(--md-sys-color-on-surface-variant);
            width: fit-content;
            min-width: auto;
            flex-shrink: 0;
        }
        
        .status-dot {
            width: 8px;
            height: 8px;
            border-radius: 50%;
            background: var(--md-sys-color-outline);
        }
        
        .status-dot.up { background: var(--md-sys-color-success); box-shadow: 0 0 8px var(--md-sys-color-success); }
        .status-dot.down { background: var(--md-sys-color-error); box-shadow: 0 0 8px var(--md-sys-color-error); }
        .status-dot.healthy { background: var(--md-sys-color-success); box-shadow: 0 0 8px var(--md-sys-color-success); }
        .status-dot.starting { background: var(--md-sys-color-warning); box-shadow: 0 0 8px var(--md-sys-color-warning); }
        .status-dot.unhealthy { background: var(--md-sys-color-error); box-shadow: 0 0 8px var(--md-sys-color-error); }
        
        /* MD3 Text Fields */
        .text-field {
            width: 100%;
            background: var(--md-sys-color-surface-container-highest);
            border: none;
            border-bottom: 1px solid var(--md-sys-color-on-surface-variant);
            color: var(--md-sys-color-on-surface);
            padding: 16px;
            border-radius: 4px 4px 0 0;
            font-size: 16px;
            box-sizing: border-box;
            outline: none;
            transition: all var(--md-sys-motion-duration-short) linear;
        }
        
        .text-field:focus {
            border-bottom: 2px solid var(--md-sys-color-primary);
            background: var(--md-sys-color-surface-container-highest);
        }
        
        textarea.text-field { min-height: 120px; resize: vertical; }
        
        /* MD3 Buttons */
        .btn {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            gap: 8px;
            padding: 0 24px;
            height: 40px;
            border-radius: 20px;
            font-size: 14px;
            font-weight: 500;
            letter-spacing: 0.1px;
            cursor: pointer;
            transition: all var(--md-sys-motion-duration-short) linear;
            border: none;
            position: relative;
            overflow: hidden;
            text-decoration: none;
            font-family: inherit;
        }
        
        .btn-filled { background: var(--md-sys-color-primary); color: var(--md-sys-color-on-primary); box-shadow: var(--md-sys-elevation-1); }
        .btn-tonal { background: var(--md-sys-color-secondary-container); color: var(--md-sys-color-on-secondary-container); }
        .btn-outlined { background: transparent; color: var(--md-sys-color-primary); border: 1px solid var(--md-sys-color-outline); }
        .btn-tertiary { background: var(--md-sys-color-tertiary-container); color: var(--md-sys-color-on-tertiary-container); }
        
        .btn-icon:hover {
            background: rgba(202, 196, 208, 0.08);
            border-color: var(--md-sys-color-outline);
        }
        
        .portainer-link {
            text-decoration: none;
            cursor: pointer;
            transition: all var(--md-sys-motion-duration-short) linear;
            position: relative;
            pointer-events: auto;
            z-index: 10;
        }
        .portainer-link:hover {
            background: var(--md-sys-color-secondary-container);
            color: var(--md-sys-color-on-secondary-container);
            border-color: transparent;
            opacity: 0.9;
        }
        .portainer-link:hover .material-symbols-rounded {
            transform: translateX(4px);
        }

        .nav-arrow {
            opacity: 0;
            transform: translateX(-8px);
            transition: all var(--md-sys-motion-duration-short) var(--md-sys-motion-easing-emphasized);
            color: var(--md-sys-color-primary);
            pointer-events: none;
            font-family: 'Material Symbols Rounded';
            font-display: block;
        }

        .card:hover .nav-arrow {
            opacity: 1;
            transform: translateX(0);
        }
        
        .btn-action {
            background: var(--md-sys-color-secondary-container);
            color: var(--md-sys-color-on-secondary-container);
            border-radius: var(--md-sys-shape-corner-medium);
            box-shadow: var(--md-sys-elevation-1);
        }
        
        .btn-icon { width: 40px; height: 40px; padding: 0; border-radius: 20px; }
        .btn-icon svg { width: 24px; height: 24px; fill: currentColor; }
        
        /* MD3 Switch */
        .switch-container {
            display: inline-flex;
            align-items: center;
            gap: 16px;
            cursor: pointer;
            padding: 8px 0;
            flex-shrink: 0;
            white-space: nowrap;
        }

        .switch-track {
            width: 52px;
            height: 32px;
            background: var(--md-sys-color-surface-container-highest);
            border: 2px solid var(--md-sys-color-outline);
            border-radius: 16px;
            position: relative;
            transition: all var(--md-sys-motion-duration-short) linear;
        }

        .switch-thumb {
            width: 16px;
            height: 16px;
            background: var(--md-sys-color-outline);
            border-radius: 50%;
            position: absolute;
            top: 50%;
            left: 6px;
            transform: translateY(-50%);
            transition: all var(--md-sys-motion-duration-short) var(--md-sys-motion-easing-emphasized);
            display: flex;
            align-items: center;
            justify-content: center;
        }

        .switch-container.active .switch-track { background: var(--md-sys-color-primary); border-color: var(--md-sys-color-primary); }
        .switch-container.active .switch-thumb { width: 24px; height: 24px; left: 24px; background: var(--md-sys-color-on-primary); }

        /* Tooltips */
        [data-tooltip] { 
            position: relative; 
        }
        
        .tooltip-box {
            position: fixed;
            background: var(--md-sys-color-inverse-surface);
            color: var(--md-sys-color-inverse-on-surface);
            padding: 8px 12px;
            border-radius: 8px;
            font-size: 12px;
            font-weight: 400;
            line-height: 16px;
            max-width: 280px;
            z-index: 10000;
            box-shadow: var(--md-sys-elevation-2);
            pointer-events: none;
            opacity: 0;
            display: none;
            transition: opacity 150ms var(--md-sys-motion-easing-emphasized);
            text-align: center;
        }
        
        .tooltip-box.visible { opacity: 1; }

        /* Ensure parent elements don't clip tooltips */
        .card, .chip, .status-indicator, li, span, div {
            /* Tooltip container safety */
        }
        
        .card {
            /* ... existing ... */
            overflow: visible; /* Changed from hidden to allow tooltips to escape */
        }
        
        /* Prevent card content overlapping */
        .card > * {
            position: relative;
            z-index: 2;
        }
        
        .card::before {
            /* ... existing ... */
            z-index: 1;
        }

        .log-container {
            background: var(--md-sys-color-surface-container-highest);
            border-radius: var(--md-sys-shape-corner-large);
            padding: 16px;
            flex-grow: 1;
            max-height: 400px;
            overflow-y: auto;
            font-size: 13px;
            color: var(--md-sys-color-on-surface-variant);
            display: flex;
            flex-direction: column;
            gap: 4px;
        }

        .log-entry {
            display: flex;
            gap: 12px;
            align-items: flex-start;
            line-height: 1.5;
            padding: 2px 0;
            border-bottom: 1px solid rgba(255,255,255,0.05);
        }

        .log-entry:last-child { border-bottom: none; }
        
        .log-icon {
            font-size: 18px !important;
            flex-shrink: 0;
            margin-top: 2px;
        }

        .log-content {
            flex-grow: 1;
            overflow-wrap: anywhere;
        }

        .log-time {
            opacity: 0.5;
            font-size: 0.85em;
            white-space: nowrap;
            flex-shrink: 0;
            margin-top: 3px;
        }

        /* Snackbar / Toast */
        .snackbar-container {
            position: fixed;
            bottom: 24px;
            left: 50%;
            transform: translateX(-50%);
            z-index: 20000;
            display: flex;
            flex-direction: column;
            gap: 8px;
            pointer-events: none;
        }

        .snackbar {
            min-width: 320px;
            max-width: 560px;
            background: var(--md-sys-color-inverse-surface);
            color: var(--md-sys-color-inverse-on-surface);
            border-radius: var(--md-sys-shape-corner-small);
            padding: 14px 16px;
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 16px;
            box-shadow: var(--md-sys-elevation-3);
            pointer-events: auto;
            opacity: 0;
            transform: translateY(20px);
            transition: all var(--md-sys-motion-duration-long) var(--md-sys-motion-easing-emphasized);
        }

        .snackbar.visible {
            opacity: 1;
            transform: translateY(0);
        }

        .snackbar-content { flex-grow: 1; font-size: 14px; letter-spacing: 0.25px; }
        .snackbar-action { 
            color: var(--md-sys-color-primary); 
            font-weight: 500; 
            text-transform: uppercase; 
            cursor: pointer; 
            font-size: 14px;
            background: none;
            border: none;
            padding: 8px;
            margin: -8px;
        }

        /* Theme Toggle */
        .theme-toggle {
            width: 40px;
            height: 40px;
            border-radius: 20px;
            display: flex;
            align-items: center;
            justify-content: center;
            cursor: pointer;
            background: var(--md-sys-color-surface-container-high);
            color: var(--md-sys-color-on-surface);
            transition: all var(--md-sys-motion-duration-short) linear;
        }
        
        .theme-toggle:hover { background: var(--md-sys-color-surface-container-highest); }

        /* Service Modal */
        .modal-overlay {
            position: fixed;
            inset: 0;
            background: rgba(0,0,0,0.6);
            backdrop-filter: blur(4px);
            z-index: 25000;
            display: none;
            align-items: center;
            justify-content: center;
            padding: 24px;
        }

        .modal-card {
            background: var(--md-sys-color-surface-container-high);
            border-radius: var(--md-sys-shape-corner-extra-large);
            max-width: 500px;
            width: 100%;
            padding: 32px;
            box-shadow: var(--md-sys-elevation-3);
            display: flex;
            flex-direction: column;
            gap: 24px;
        }
        .modal-card h2 { font-weight: 400; font-size: 24px; color: var(--md-sys-color-on-surface); margin: 0; }

        .settings-btn { 
            opacity: 0.5; 
            transition: all var(--md-sys-motion-duration-short) linear; 
        }
        .card:hover .settings-btn { opacity: 1; color: var(--md-sys-color-primary); }

        .modal-header { display: flex; align-items: center; justify-content: space-between; }
        
        .metric-bar {
            height: 4px;
            width: 100%;
            background: var(--md-sys-color-surface-container-highest);
            border-radius: 2px;
            margin-top: 4px;
            overflow: hidden;
        }
        
        .metric-fill {
            height: 100%;
            background: var(--md-sys-color-primary);
            transition: width 1s ease-in-out;
        }
        
        .code-block {
            background: var(--md-sys-color-surface-container-highest);
            border-radius: var(--md-sys-shape-corner-small);
            padding: 14px 16px;
            font-size: 13px;
            color: var(--md-sys-color-primary);
            margin: 8px 0;
            overflow-x: auto;
        }
        
        .sensitive { transition: filter 400ms var(--md-sys-motion-easing-emphasized); }
        .privacy-mode .sensitive { filter: blur(6px); opacity: 0.4; }

        .sensitive-masked { opacity: 0.7; letter-spacing: 0.3px; }
        
        .text-success { color: var(--md-sys-color-success); }
        .success { color: var(--md-sys-color-success); }
        .error { color: var(--md-sys-color-error); }
        .stat-row { 
            display: flex; 
            justify-content: space-between; 
            align-items: center;
            flex-wrap: wrap;
            margin-bottom: 12px; 
            font-size: 14px; 
            gap: 12px;
        }
        .stat-label { 
            color: var(--md-sys-color-on-surface-variant); 
            flex: 1 1 160px;
        }
        .stat-value {
            text-align: right;
            flex: 1 1 200px;
            overflow-wrap: anywhere;
        }
        
        .btn-group { display: flex; gap: 8px; margin-top: 16px; flex-wrap: wrap; }
        .list-item { 
            display: flex; 
            justify-content: space-between; 
            align-items: center; 
            padding: 12px 16px; 
            margin: 0 -16px;
            border-bottom: 1px solid var(--md-sys-color-outline-variant); 
            gap: 16px; 
            flex-wrap: wrap;
            transition: background-color var(--md-sys-motion-duration-short) linear;
            border-radius: var(--md-sys-shape-corner-small);
        }
        .list-item:hover {
            background-color: rgba(230, 225, 229, 0.08);
        }
        .list-item:last-child { border-bottom: none; }
        .list-item-text { cursor: pointer; flex: 1 1 220px; font-weight: 500; overflow-wrap: anywhere; font-size: 16px; letter-spacing: 0.5px; }

        @keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }

        @media (max-width: 720px) {
            body { padding: 16px; }
            h1 { font-size: 36px; line-height: 42px; }
            .subtitle { font-size: 18px; line-height: 24px; }
        }

        @media (max-width: 600px) {
            .header-row { gap: 16px; }
            .switch-container { width: 100%; justify-content: space-between; }
            .stat-row, .list-item { flex-direction: column; align-items: flex-start; }
            .stat-value { text-align: left; }
            .card-header { align-items: flex-start; }
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <div class="header-row">
                <div>
                    <h1>Privacy Hub</h1>
                    <div class="subtitle">Self-hosted network security and private service infrastructure.</div>
                </div>
                <div style="display: flex; align-items: center; gap: 16px;">
                    <div id="https-badge" class="chip vpn" style="gap:4px; display:none; height: 32px; padding: 0 12px; border-radius: 16px;" data-tooltip="Connection is secured with end-to-end encryption.">
                        <span class="material-symbols-rounded" style="font-size:18px;">lock</span>
                        <span style="font-size: 12px; font-weight: 600;">Secure HTTPS</span>
                    </div>
                    <div class="switch-container" id="privacy-switch" onclick="togglePrivacy()" data-tooltip="Redact identifying metrics for privacy">
                        <span class="label-large">Safe Display Mode</span>
                        <div class="switch-track">
                            <div class="switch-thumb"></div>
                        </div>
                    </div>
                    <div class="status-indicator" style="background: var(--md-sys-color-surface-container-high); border: 1px solid var(--md-sys-color-outline-variant);">
                        <span class="status-dot" id="api-dot"></span>
                        <span class="status-text" id="api-text">API: ...</span>
                    </div>
                    <div class="theme-toggle" onclick="toggleTheme()" data-tooltip="Switch between Light and Dark mode">
                        <span class="material-symbols-rounded" id="theme-icon">light_mode</span>
                    </div>
                    <div class="theme-toggle" id="admin-lock-btn" onclick="toggleAdminMode()" data-tooltip="Enter Admin Mode to manage services">
                        <span class="material-symbols-rounded" id="admin-icon">admin_panel_settings</span>
                    </div>
                </div>
            </div>
        </header>

        <div class="filter-bar" id="category-filters">
            <div class="chip filter-chip active" data-target="all" onclick="filterCategory('all')">All Services</div>
            <div class="chip filter-chip" data-target="apps" onclick="filterCategory('apps')">Applications</div>
            <div class="chip filter-chip" data-target="system" onclick="filterCategory('system')">Infrastructure</div>
            <div class="chip filter-chip" data-target="dns" onclick="filterCategory('dns')">DNS & Security</div>
            <div class="chip filter-chip" data-target="tools" onclick="filterCategory('tools')">Utilities</div>
            <div class="chip filter-chip admin-only" data-target="logs" onclick="filterCategory('logs')">System Logs</div>
        </div>

        <div id="update-banner" class="admin-only full-bleed" style="display:none; margin-bottom: 32px; width: 100%;">
            <div class="card" style="min-height: auto; padding: 24px; background: var(--md-sys-color-primary-container); color: var(--md-sys-color-on-primary-container);">
                <div style="display: flex; justify-content: space-between; align-items: center; gap: 24px; flex-wrap: wrap;">
                    <div>
                        <h3 style="margin:0; color: inherit;">Updates Available</h3>
                        <p class="body-medium" id="update-list" style="margin: 8px 0 0 0; color: inherit; opacity: 0.9;">New versions detected for some services.</p>
                    </div>
                    <div style="display: flex; gap: 12px;">
                        <button onclick="updateAllServices()" class="btn btn-filled" style="background: var(--md-sys-color-primary); color: var(--md-sys-color-on-primary);" data-tooltip="Pull latest source code and rebuild containers for all pending services.">Update All</button>
                        <button onclick="this.closest('#update-banner').style.display='none'" class="btn btn-outlined" style="border-color: currentColor; color: inherit;">Dismiss</button>
                    </div>
                </div>
            </div>
        </div>

        <div id="mac-advisory" class="full-bleed" style="margin-bottom: 32px; width: 100%;">
            <div class="card" style="min-height: auto; padding: 16px 24px; background: var(--md-sys-color-error-container); color: var(--md-sys-color-on-error-container);">
                <div style="display: flex; justify-content: space-between; align-items: flex-start; gap: 24px;">
                    <div style="display: flex; gap: 16px; align-items: flex-start;">
                        <span class="material-symbols-rounded" style="margin-top: 2px;">warning</span>
                        <div>
                            <h3 style="margin:0; color: inherit; font-size: 16px;">Critical Network Advisory</h3>
                            <p class="body-medium" style="margin: 4px 0 0 0; color: inherit; opacity: 0.9;">
                                To ensure firewall persistence and static IP reliability, you <strong>must disable Dynamic/Random MAC addresses</strong> in your host device's network settings.
                            </p>
                        </div>
                    </div>
                    <button onclick="dismissMacAdvisory()" class="btn btn-icon" style="color: inherit; margin: -8px -8px 0 0;" data-tooltip="Dismiss">
                        <span class="material-symbols-rounded">close</span>
                    </button>
                </div>
            </div>
        </div>



        <section data-category="all" id="section-all">
        <div class="section-label">All Services</div>
        <div id="grid-all" class="grid">
            <!-- Dynamic Cards Injected Here -->
        </div>
        </section>

        <section data-category="apps">
        <div class="section-label">Applications</div>
        <div class="section-hint" style="display: flex; gap: 8px; flex-wrap: wrap;">
            <span class="chip category-badge" data-tooltip="Services isolated within a secure VPN tunnel (Gluetun). This allows you to host your own private instances—removing the need to trust third-party hosts—while ensuring your home IP remains hidden from end-service providers."><span class="material-symbols-rounded">vpn_lock</span> VPN Protected</span>
            <span class="chip category-badge" data-tooltip="Local services accessed directly through the internal network interface."><span class="material-symbols-rounded">lan</span> Direct Access</span>
            <span class="chip category-badge" data-tooltip="Advanced infrastructure control and container telemetry via Portainer."><span class="material-symbols-rounded">hub</span> Infrastructure</span>
        </div>
        <div id="grid-apps" class="grid">
            <!-- Dynamic Cards Injected Here -->
        </div>
        </section>

        <section data-category="system">
        <div class="section-label">System Management</div>
        <div class="section-hint" style="display: flex; gap: 8px; flex-wrap: wrap;">
            <span class="chip category-badge" data-tooltip="Core infrastructure management and gateway orchestration"><span class="material-symbols-rounded">settings_input_component</span> Core Services</span>
        </div>
        <div id="grid-system" class="grid">
            <!-- Dynamic Cards Injected Here -->
        </div>
        </section>

        <section data-category="dns">
        <div class="section-label">DNS Configuration</div>
        <div class="grid">
            <div class="card">
                <h3>Certificate Status</h3>
                <div id="cert-status-content" style="padding-top: 12px; flex-grow: 1;">
                    <div class="stat-row" data-tooltip="Type of SSL certificate currently installed"><span class="stat-label">Type</span><span class="stat-value" id="cert-type">Checking...</span></div>
                    <div class="stat-row" data-tooltip="The domain name this certificate protects"><span class="stat-label">Domain</span><span class="stat-value sensitive" id="cert-subject">Checking...</span></div>
                    <div class="stat-row" data-tooltip="The authority that issued this certificate"><span class="stat-label">Issuer</span><span class="stat-value sensitive" id="cert-issuer">Checking...</span></div>
                    <div class="stat-row" data-tooltip="Date when this certificate will expire"><span class="stat-label">Expires</span><span class="stat-value sensitive" id="cert-to">Checking...</span></div>
                    <div id="ssl-failure-info" style="display:none; margin-top: 16px; padding: 16px; border-radius: var(--md-sys-shape-corner-medium); background: var(--md-sys-color-error-container); color: var(--md-sys-color-on-error-container); border: 1px solid var(--md-sys-color-error);">
                        <div class="body-small" style="font-weight:600; margin-bottom:4px; display: flex; align-items: center; gap: 8px;">
                            <span class="material-symbols-rounded" style="font-size: 16px;">error</span>
                            Pipeline Error
                        </div>
                        <div class="body-small" id="ssl-failure-reason" style="opacity: 0.9;">--</div>
                    </div>
                    <div id="cert-loading" class="chip admin" style="width: 100%; justify-content: flex-start; gap: 12px; height: auto; padding: 12px; border-radius: var(--md-sys-shape-corner-medium); border: none; margin-top: 16px;">
                        <div style="width: 24px; height: 24px; border: 3px solid var(--md-sys-color-on-secondary-container); border-top: 3px solid transparent; border-radius: 50%; animation: spin 1s linear infinite;"></div>
                        <div style="display: flex; flex-direction: column; gap: 2px;">
                            <span style="font-weight: 600;">Verifying Pipeline</span>
                            <span class="body-medium" style="opacity: 0.8; white-space: normal;">Checking SSL certificate validity and issuance status...</span>
                        </div>
                    </div>
                </div>
                <div style="display: flex; align-items: center; justify-content: space-between; margin-top: 24px; gap: 16px; flex-wrap: wrap;">
                    <div id="cert-status-badge" class="chip" style="width: fit-content;" data-tooltip="Overall health of the SSL certificate issuance pipeline">Not Installed</div>
                    <button id="ssl-retry-btn" class="btn btn-icon btn-action" style="display:none;" data-tooltip="Force Let's Encrypt re-attempt" onclick="requestSslCheck()">
                        <span class="material-symbols-rounded">refresh</span>
                    </button>
                </div>
            </div>
            <div class="card admin-only">
                <h3>deSEC Configuration</h3>
                <p class="body-medium description">Manage your dynamic DNS and SSL certificate parameters:</p>
                <form onsubmit="saveDesecConfig(); return false;">
                    <input type="text" id="desec-domain-input" class="text-field" placeholder="Domain (e.g. yourname.dedyn.io)" style="margin-bottom:12px;" autocomplete="username" data-tooltip="Enter your registered deSEC domain (e.g. yourname.dedyn.io). You can create one for free at desec.io.">
                    <input type="password" id="desec-token-input" class="text-field sensitive" placeholder="deSEC API Token" style="margin-bottom:12px;" autocomplete="current-password" data-tooltip="The secret API token from your deSEC account used to verify domain ownership.">
                    <p class="body-small" style="margin-bottom:16px; color: var(--md-sys-color-on-surface-variant);">
                        Get your domain and token at <a href="https://desec.io" target="_blank" style="color: var(--md-sys-color-primary);">desec.io</a>.
                    </p>
                    <div style="text-align:right;">
                        <button type="submit" class="btn btn-tonal">Save deSEC Config</button>
                    </div>
                </form>
            </div>
            <div class="card">
                <h3>Device DNS Settings</h3>
                <p class="body-medium description">Utilize these RFC-compliant encrypted endpoints to maintain digital independence:</p>
                <div class="code-label" data-tooltip="Standard unencrypted DNS (Port 53). Recommended only for use within your local LAN.">Standard IPv4 (Local LAN Only)</div>
                <div class="code-block sensitive">$LAN_IP:53</div>
                <div class="code-label" data-tooltip="DNS-over-QUIC (DOQ) - RFC 9250. Port 853. High-performance encrypted DNS designed for superior latency and stability.">Secure DOQ (Modern Clients)</div>
                <div class="code-block sensitive">quic://$LAN_IP</div>
EOF
if [ -n "$DESEC_DOMAIN" ]; then
    cat >> "$DASHBOARD_FILE" <<EOF
                <div class="code-label" data-tooltip="DNS-over-HTTPS (DOH) - RFC 8484. Standard for web browsers. Queries are indistinguishable from HTTPS traffic.">Secure DOH (Browsers)</div>
                <div class="code-block sensitive">https://$DESEC_DOMAIN/dns-query</div>
                <div class="code-label" data-tooltip="DNS-over-TLS (DOT) - RFC 7858. Port 853. The industry standard for Android 'Private DNS' and system resolvers.">Secure DOT (Android / System)</div>
                <div class="code-block sensitive">$DESEC_DOMAIN:853</div>
            </div>
            <div class="card">
                <h3>Endpoint Provisioning</h3>
                <div id="dns-setup-trusted" style="display:none; height: 100%; display: flex; flex-direction: column;">
                    <p class="body-medium description">Globally trusted SSL is active via Let's Encrypt and deSEC. This enables zero-trust encrypted DNS on mobile devices without requiring certificate installation.</p>
                    <ol style="margin:12px 0; padding-left:20px; font-size:14px; color:var(--md-sys-color-on-surface); line-height:1.8; flex-grow: 1;">
                        <li data-tooltip="For legacy devices within your home network."><b>Local LAN:</b> Configure devices to use <code class="sensitive">$LAN_IP</code>.</li>
                        <li data-tooltip="Requires establishing the WireGuard VPN tunnel when away from home."><b>VPN Tunnel:</b> Route all traffic through the Privacy Hub.</li>
                        <li data-tooltip="Android 9+ native feature. Encrypts all DNS queries automatically."><b>Mobile Private DNS:</b> Use the hostname below for native encryption.</li>
                    </ol>
                    <div class="code-label" style="margin-top:12px;" data-tooltip="Use this hostname in your Android 'Private DNS' settings.">Mobile Private DNS Hostname</div>
                    <div class="code-block sensitive" style="margin-top:4px;">$DESEC_DOMAIN</div>
                    <div style="margin-top: auto; padding-top: 16px;">
                        <div class="chip vpn" style="width: 100%; justify-content: flex-start; gap: 12px; height: auto; padding: 12px; border-radius: var(--md-sys-shape-corner-medium);">
                            <span class="material-symbols-rounded" style="color: var(--md-sys-color-on-primary-container);">verified_user</span>
                            <div style="display: flex; flex-direction: column; gap: 2px;">
                                <span style="font-weight: 600;">Verified Certificate Authority</span>
                                <span class="body-small" style="opacity: 0.8; white-space: normal;">Trust chain established with Let's Encrypt. Fully compatible with native Private DNS.</span>
                            </div>
                        </div>
                    </div>
                </div>
                <div id="dns-setup-untrusted" style="display:none; height: 100%; display: flex; flex-direction: column;">
                    <p class="body-medium description" style="color:var(--md-sys-color-error);">Limited Encrypted DNS Coverage</p>
                    <p class="body-small description">Android 'Private DNS' requires a FQDN. Since no domain is configured, your mobile devices cannot utilize native encrypted DNS without the VPN.</p>
                    <div style="flex-grow: 1;">
                        <div class="code-label" data-tooltip="The local IP address of your privacy hub.">Primary Gateway</div>
                        <div class="code-block sensitive">$LAN_IP</div>
                    </div>
                    <div style="margin-top: auto; padding-top: 16px;">
                        <div class="chip admin" style="width: 100%; justify-content: flex-start; gap: 12px; height: auto; padding: 12px; border-radius: var(--md-sys-shape-corner-medium);">
                            <span class="material-symbols-rounded" style="color: var(--md-sys-color-error);">warning</span>
                            <div style="display: flex; flex-direction: column; gap: 2px;">
                                <span style="font-weight: 600;">Self-Signed (Local)</span>
                                <span class="body-small" style="opacity: 0.8; white-space: normal;">Security warnings will appear. Configure deSEC for trusted SSL and Private DNS.</span>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
EOF
else
    cat >> "$DASHBOARD_FILE" <<EOF
                <div class="code-label" data-tooltip="Secured DNS via HTTPS">DNS-over-HTTPS</div>
                <div class="code-block sensitive">https://$LAN_IP/dns-query</div>
                <div class="code-label" data-tooltip="Secured DNS via TLS">DNS-over-TLS</div>
                <div class="code-block sensitive">$LAN_IP:853</div>
            </div>
            <div class="card">
                <h3>Endpoint Provisioning</h3>
                <p class="body-medium description">The system is currently operating in local-only mode. To maintain privacy, all external traffic should be routed via the local infrastructure:</p>
                <ol style="margin:12px 0; padding-left:20px; font-size:14px; color:var(--md-sys-color-on-surface); line-height:1.8; flex-grow: 1;">
                    <li>Configure router WAN/LAN DNS to: <b class="sensitive">$LAN_IP</b></li>
                    <li>Remote Access: Establish WireGuard tunnel before accessing services.</li>
                    <li>Legacy Support: Standard Port 53 resolution for older hardware.</li>
                </ol>
                <div class="code-block sensitive" style="margin-top:12px;">$LAN_IP</div>
                <div style="margin-top: auto; padding-top: 16px;">
                    <div class="chip admin" style="width: 100%; justify-content: flex-start; gap: 12px; height: auto; padding: 12px; border-radius: var(--md-sys-shape-corner-medium);">
                        <span class="material-symbols-rounded" style="color: var(--md-sys-color-error);">warning</span>
                        <div style="display: flex; flex-direction: column; gap: 2px;">
                            <span style="font-weight: 600;">Self-Signed (Local)</span>
                            <span class="body-small" style="opacity: 0.8; white-space: normal;">Security warnings will appear. Configure deSEC for trusted SSL and full mobile support.</span>
                        </div>
                    </div>
                </div>
            </div>
EOF
fi
cat >> "$DASHBOARD_FILE" <<EOF
        </div>
        </section>

        <section data-category="tools">
        <div class="section-label">Service Utilities</div>
        <div id="grid-tools" class="grid">
            <!-- Dynamic Cards Injected Here -->
        </div>
        <div class="grid">
            <div class="card">
                <div style="display: flex; justify-content: space-between; align-items: flex-start;">
                    <h3>Odido Status</h3>
                    <div id="odido-speed-indicator" class="body-small" style="color: var(--md-sys-color-primary); font-weight: 500; display:none;">0 Mb/s</div>
                </div>
                <div id="odido-status-container" style="display: flex; flex-direction: column; height: 100%;">
                    <div id="odido-not-configured" style="display:none;">
                        <p class="body-medium" style="color:var(--md-sys-color-on-surface-variant);">Odido Bundle Booster service available. Configure credentials via API or link below.</p>
                        <a href="http://$LAN_IP:8085/docs" target="_blank" class="btn btn-tonal" style="margin-top:12px;">Open API Docs</a>
                    </div>
                    <div id="odido-configured" style="display:none; padding-top: 8px; flex-grow: 1; display: flex; flex-direction: column;">
                        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 16px;">
                            <div>
                                <div class="stat-row"><span class="stat-label">Remaining</span><span class="stat-value" id="odido-remaining">--</span></div>
                                <div class="stat-row"><span class="stat-label">Bundle</span><span class="stat-value" id="odido-bundle-code">--</span></div>
                                <div class="stat-row"><span class="stat-label">Rate</span><span class="stat-value" id="odido-rate">--</span></div>
                            </div>
                            <div>
                                <div class="stat-row"><span class="stat-label">Status</span><span class="stat-value" id="odido-api-status">--</span></div>
                                <div class="stat-row"><span class="stat-label">Threshold</span><span class="stat-value" id="odido-threshold">--</span></div>
                                <div class="stat-row"><span class="stat-label">Auto-Renew</span><span class="stat-value" id="odido-auto-renew">--</span></div>
                            </div>
                        </div>
                        
                        <div style="margin-top: 24px; flex-grow: 1; min-height: 120px; position: relative; background: var(--md-sys-color-surface-container-low); border-radius: 12px; padding: 12px;">
                            <div style="position: absolute; top: 8px; left: 12px; font-size: 10px; color: var(--md-sys-color-on-surface-variant); text-transform: uppercase; letter-spacing: 0.5px; font-weight: 600;">Consumption Rate (MB/min)</div>
                            <svg id="odido-graph" width="100%" height="100%" viewBox="0 0 400 120" preserveAspectRatio="none" style="overflow: visible;">
                                <defs>
                                    <linearGradient id="graph-gradient" x1="0" y1="0" x2="0" y2="1">
                                        <stop offset="0%" stop-color="var(--md-sys-color-primary)" stop-opacity="0.3"></stop>
                                        <stop offset="100%" stop-color="var(--md-sys-color-primary)" stop-opacity="0"></stop>
                                    </linearGradient>
                                </defs>
                                <path id="graph-area" fill="url(#graph-gradient)" d=""></path>
                                <path id="graph-line" fill="none" stroke="var(--md-sys-color-primary)" stroke-width="2.5" stroke-linejoin="round" d=""></path>
                                <line x1="0" y1="120" x2="400" y2="120" stroke="var(--md-sys-color-outline-variant)" stroke-width="1"></line>
                                <g id="graph-grid" stroke="var(--md-sys-color-outline-variant)" stroke-width="0.5" stroke-dasharray="2,2">
                                    <line x1="0" y1="30" x2="400" y2="30"></line>
                                    <line x1="0" y1="60" x2="400" y2="60"></line>
                                    <line x1="0" y1="90" x2="400" y2="90"></line>
                                </g>
                            </svg>
                        </div>

                        <div id="odido-buy-status" class="body-small" style="text-align: center; margin-top: 8px; font-weight: 500;"></div>
                        <div class="btn-group" style="justify-content:center; margin-top: 16px;">
                            <button onclick="buyOdidoBundle()" class="btn btn-tertiary admin-only" id="odido-buy-btn">Buy Bundle</button>
                            <button onclick="refreshOdidoRemaining()" class="btn btn-tonal">Refresh Status</button>
                            <a href="http://$LAN_IP:8085/docs" target="_blank" class="btn btn-outlined">API</a>
                        </div>
                    </div>
                    <div id="odido-loading" class="chip admin" style="width: 100%; justify-content: flex-start; gap: 12px; height: auto; padding: 12px; border-radius: var(--md-sys-shape-corner-medium); border: none; margin-top: 8px;">
                        <div style="width: 24px; height: 24px; border: 3px solid var(--md-sys-color-on-secondary-container); border-top: 3px solid transparent; border-radius: 50%; animation: spin 1s linear infinite;"></div>
                        <div style="display: flex; flex-direction: column; gap: 2px;">
                            <span style="font-weight: 600;">Synchronizing Data</span>
                            <span class="body-medium" style="opacity: 0.8; white-space: normal;">Connecting to Odido API to retrieve latest bundle status...</span>
                        </div>
                    </div>
                </div>
            </div>
            <div class="card admin-only">
                <h3>Configuration</h3>
                <p class="body-medium description">Authentication and automation settings for backend services:</p>
                <form onsubmit="saveOdidoConfig(); return false;">
                    <input type="text" id="odido-api-key" class="text-field sensitive" placeholder="Dashboard API Key" style="margin-bottom:12px;" autocomplete="username" data-tooltip="The HUB_API_KEY from your .secrets file.">
                    <p class="body-small" style="margin-bottom:16px; color: var(--md-sys-color-on-surface-variant);">
                        The <strong>Dashboard API Key</strong> (HUB_API_KEY) is required to authorize sensitive actions like saving settings. You can find this in your <code>.secrets</code> file on the host.
                    </p>
                    <input type="password" id="odido-oauth-token" class="text-field sensitive" placeholder="Odido OAuth Token" style="margin-bottom:12px;" autocomplete="current-password" data-tooltip="OAuth token for Odido API authentication.">
                    <p class="body-small" style="margin-bottom:16px; color: var(--md-sys-color-on-surface-variant);">
                        Obtain your OAuth token using the <a href="https://github.com/GuusBackup/Odido.Authenticator" target="_blank" style="color: var(--md-sys-color-primary);">Odido Authenticator</a>.
                    </p>
                    <input type="text" id="odido-bundle-code-input" class="text-field" placeholder="Bundle Code (default: A0DAY01)" style="margin-bottom:12px;" data-tooltip="The product code for your data bundle.">
                    <input type="number" id="odido-threshold-input" class="text-field" placeholder="Min Threshold MB (default: 100)" style="margin-bottom:12px;" data-tooltip="Automatic renewal triggers when data falls below this level.">
                    <input type="number" id="odido-lead-time-input" class="text-field" placeholder="Lead Time Minutes (default: 30)" style="margin-bottom:12px;" data-tooltip="Lead time before expiration to trigger renewal.">
                    <div style="display: flex; justify-content: space-between; align-items: center; margin-top: 16px;">
                        <div id="odido-config-status" class="body-small" style="font-weight: 500;"></div>
                        <button type="submit" class="btn btn-tonal">Save Configuration</button>
                    </div>
                </form>
            </div>
        </div>

        <div class="section-label">WireGuard Profiles</div>
        <div class="grid">
            <div class="card admin-only">
                <h3>Upload Profile</h3>
                <input type="text" id="prof-name" class="text-field" placeholder="Optional: Custom Name" style="margin-bottom:12px;" data-tooltip="Give your profile a recognizable name.">
                <textarea id="prof-conf" class="text-field sensitive" placeholder="Paste .conf content here..." style="margin-bottom:16px;" data-tooltip="Paste the contents of your WireGuard .conf file."></textarea>
                <div style="text-align:right;"><button onclick="uploadProfile()" class="btn btn-filled" data-tooltip="Save this profile. The VPN service will automatically restart to apply the new configuration (~15 seconds).">Upload & Activate</button></div>
            </div>
            <div class="card profile-card admin-only">
                <h3 data-tooltip="Select a profile to activate it. The dashboard will automatically restart dependent services to route their traffic through the new tunnel.">Available Profiles</h3>
                <div id="profile-list" style="flex-grow: 1; display: flex; align-items: center; justify-content: center; min-height: 100px;">
                    <div style="display: flex; flex-direction: column; align-items: center; gap: 12px; opacity: 0.7;">
                        <div style="width: 24px; height: 24px; border: 3px solid var(--md-sys-color-primary); border-top: 3px solid transparent; border-radius: 50%; animation: spin 1s linear infinite;"></div>
                        <span class="body-medium">Scanning Profiles...</span>
                    </div>
                </div>
                <p class="body-small profile-hint" style="margin-top: auto; padding-top: 12px;">Click name to activate.</p>
            </div>
        </div>

        <div class="section-label">Customization & Info</div>
        <div class="grid">
            <div class="card admin-only">
                <div class="card-header">
                    <h3>Theme Customization</h3>
                    <div class="card-header-actions">
                        <button onclick="localStorage.removeItem('theme_seed'); location.reload();" class="btn btn-icon" data-tooltip="Reset theme to default"><span class="material-symbols-rounded">refresh</span></button>
                    </div>
                </div>
                <p class="body-medium description">Personalize the dashboard using Material Design 3 dynamic color algorithms (HCT color space).</p>
                <div style="display: flex; flex-direction: column; gap: 20px; margin-top: 16px;">
                    <div style="background: var(--md-sys-color-surface-container-high); padding: 16px; border-radius: 16px; display: flex; align-items: center; gap: 16px; border: 1px solid var(--md-sys-color-outline-variant);">
                        <div style="position: relative; width: 48px; height: 48px; border-radius: 24px; overflow: hidden; border: 2px solid var(--md-sys-color-primary);">
                            <input type="color" id="theme-seed-color" onchange="applySeedColor(this.value)" style="position: absolute; top: -10px; left: -10px; width: 80px; height: 80px; cursor: pointer; border: none; background: transparent;">
                        </div>
                        <div style="flex: 1;">
                            <div style="display: flex; justify-content: space-between; align-items: center;">
                                <span class="label-large">Custom Seed Color</span>
                                <span class="body-small monospace" id="theme-seed-hex" style="opacity: 0.7;">#D0BCFF</span>
                            </div>
                            <p class="body-small" style="color: var(--md-sys-color-on-surface-variant);">Tap the circle to choose a primary tone</p>
                        </div>
                    </div>

                    <div style="background: var(--md-sys-color-surface-container-high); padding: 16px; border-radius: 16px; display: flex; flex-direction: column; gap: 16px; border: 1px solid var(--md-sys-color-outline-variant);">
                        <div style="display: flex; align-items: center; justify-content: space-between;">
                            <span class="label-large">Theme Presets</span>
                        </div>
                        <div id="static-presets" style="display: flex; gap: 12px; flex-wrap: wrap;">
                            <!-- Static presets injected here -->
                        </div>

                        <div style="height: 1px; background: var(--md-sys-color-outline-variant); opacity: 0.5;"></div>

                        <div style="display: flex; align-items: center; gap: 16px;">
                            <label for="theme-image-upload" class="btn btn-filled" style="width: 48px; height: 48px; padding: 0; border-radius: 24px; cursor: pointer; flex-shrink: 0;" data-tooltip="Pick a wallpaper to extract colors">
                                <span class="material-symbols-rounded">wallpaper</span>
                            </label>
                            <input type="file" id="theme-image-upload" accept="image/*" onchange="extractColorsFromImage(event)" style="display: none;">
                            <div style="flex: 1;">
                                <span class="label-large">Wallpaper Extraction</span>
                                <p class="body-small" style="color: var(--md-sys-color-on-surface-variant);">Upload image to generate palettes</p>
                            </div>
                        </div>
                        
                        <!-- Extracted Palette -->
                        <div id="extracted-palette" style="display: flex; gap: 12px; flex-wrap: wrap; min-height: 48px; align-items: center;">
                            <span class="body-small" style="opacity: 0.5; font-style: italic;">Extracted palettes will appear here...</span>
                        </div>

                        <!-- Manual Add -->
                        <div style="display: flex; gap: 8px;">
                            <input type="text" id="manual-color-input" class="text-field" placeholder="Add Hex (e.g. #FF0000)" style="border-radius: 8px; height: 40px; padding: 0 12px; font-family: monospace;">
                            <button onclick="addManualColor()" class="btn btn-tonal" style="height: 40px;">Add</button>
                        </div>
                    </div>

                    <div style="display: flex; justify-content: flex-end; gap: 12px; margin-top: 8px;">
                        <button onclick="saveThemeSettings()" class="btn btn-tonal" style="flex-grow: 1;"><span class="material-symbols-rounded">save</span> Save Theme</button>
                    </div>
                </div>
            </div>
            <div class="card admin-only">
                <h3>Security & Privacy</h3>
                <p class="body-medium description">Manage administrative session behavior and authentication security.</p>
                <div style="display: flex; flex-direction: column; gap: 16px; margin-top: 16px;">
                    <div style="background: var(--md-sys-color-surface-container-high); padding: 16px; border-radius: 16px; display: flex; align-items: center; gap: 16px; border: 1px solid var(--md-sys-color-outline-variant);">
                        <div style="flex: 1;">
                            <span class="label-large">Session Auto-Cleanup</span>
                            <p class="body-small" style="color: var(--md-sys-color-on-surface-variant);">Automatically expire admin sessions after 30 minutes of inactivity.</p>
                        </div>
                        <div class="switch" id="session-cleanup-switch" onclick="toggleSessionCleanup()" data-tooltip="When enabled, your admin session will expire automatically.">
                            <div class="switch-thumb"></div>
                        </div>
                    </div>
                    <div id="session-cleanup-warning" class="chip admin" style="display: none; width: 100%; justify-content: flex-start; gap: 12px; height: auto; padding: 12px; border-radius: 12px; background: var(--md-sys-color-error-container); color: var(--md-sys-color-on-error-container); border: none;">
                        <span class="material-symbols-rounded">warning</span>
                        <div style="display: flex; flex-direction: column; gap: 2px;">
                            <span style="font-weight: 600;">Security Warning</span>
                            <span class="body-medium" style="opacity: 0.8; white-space: normal;">Session auto-cleanup is disabled. Administrative access will remain active indefinitely on this browser until manually exited.</span>
                        </div>
                    </div>
                </div>
            </div>
            <div class="card">
                <h3>System Information</h3>
                <p class="body-medium description">Sensitive credentials and core configuration details are stored securely on the host filesystem:</p>
                <div style="display: flex; flex-direction: column; gap: 12px; flex-grow: 1;">
                    <div class="stat-row"><span class="stat-label">Secrets Location</span><span class="stat-value monospace" style="font-size: 12px;">/DATA/AppData/privacy-hub/.secrets</span></div>
                    <div class="stat-row"><span class="stat-label">Config Root</span><span class="stat-value monospace" style="font-size: 12px;">/DATA/AppData/privacy-hub/config</span></div>
                    <div class="stat-row"><span class="stat-label">Dashboard Port</span><span class="stat-value">8081</span></div>
                    <div class="stat-row"><span class="stat-label">Safe Display Mode</span><span class="stat-value">Active (Local)</span></div>
                </div>
                <div class="admin-only" style="margin-top: 24px; display: grid; grid-template-columns: 1fr 1fr; gap: 12px;">
                    <button onclick="checkUpdates()" class="btn btn-tonal" data-tooltip="Check for updates">
                        <span class="material-symbols-rounded">system_update_alt</span> Check
                    </button>
                    <button onclick="updateAllServices()" class="btn btn-filled" data-tooltip="Update all services">
                        <span class="material-symbols-rounded">upgrade</span> Update All
                    </button>
                    <button onclick="restartStack()" class="btn btn-tonal" style="grid-column: span 1; background: var(--md-sys-color-surface-container-highest);">
                        <span class="material-symbols-rounded">restart_alt</span> Restart
                    </button>
                    <button onclick="uninstallStack()" class="btn btn-tonal" style="grid-column: span 1; background: var(--md-sys-color-error-container); color: var(--md-sys-color-on-error-container);" data-tooltip="Permanently remove all containers and data.">
                        <span class="material-symbols-rounded">delete_forever</span> Uninstall
                    </button>
                </div>
            </div>
        </div>
        </section>

        <section data-category="logs">
        <div class="section-label">System & Logs</div>
        <div class="grid">
            <div class="card">
                <div class="card-header">
                    <h3>System Health</h3>
                    <div class="card-header-actions">
                        <div class="status-indicator" id="health-status-indicator" style="background: var(--md-sys-color-success-container); color: var(--md-sys-color-on-success-container); border: none; padding: 4px 12px; min-width: auto; margin-right: -8px;">
                            <span class="status-dot up" id="health-dot" style="background: var(--md-sys-color-on-success-container); box-shadow: none;"></span>
                            <span class="status-text" id="health-text" style="color: inherit; font-weight: 600;">Optimal</span>
                        </div>
                    </div>
                </div>
                <div style="display: flex; flex-direction: column; gap: 12px; flex-grow: 1;">
                    <div class="stat-row"><span class="stat-label">System CPU</span><span class="stat-value" id="sys-cpu">0%</span></div>
                    <div class="metric-bar"><div id="sys-cpu-fill" class="metric-fill" style="width: 0%"></div></div>
                    
                    <div class="stat-row" style="margin-top:8px;"><span class="stat-label">System RAM</span><span class="stat-value" id="sys-ram">0 MB / 0 MB</span></div>
                    <div class="metric-bar"><div id="sys-ram-fill" class="metric-fill" style="width: 0%"></div></div>

                    <div style="margin-top: 16px; display: grid; grid-template-columns: 1fr 1fr; gap: 16px;">
                        <div style="background: var(--md-sys-color-surface-container-highest); padding: 12px; border-radius: 12px; display: flex; flex-direction: column; gap: 4px;">
                            <span class="body-small" style="opacity: 0.7;">Project Size</span>
                            <span class="label-large" id="sys-project-size">-- MB</span>
                        </div>
                        <div style="background: var(--md-sys-color-surface-container-highest); padding: 12px; border-radius: 12px; display: flex; flex-direction: column; gap: 4px;">
                            <span class="body-small" style="opacity: 0.7;">System Uptime</span>
                            <span class="label-large" id="sys-uptime">--</span>
                        </div>
                    </div>

                    <div style="margin-top: auto; padding-top: 16px; border-top: 1px solid var(--md-sys-color-outline-variant); display: flex; justify-content: space-between; align-items: center;">
                        <div style="display: flex; align-items: center; gap: 8px;">
                            <span class="material-symbols-rounded" style="font-size: 20px; color: var(--md-sys-color-primary);">hard_drive</span>
                            <span class="body-medium" data-tooltip="SMART Health Status" id="drive-health-container">Drive Health: <strong id="sys-drive-status">Checking...</strong> <span id="sys-drive-pct"></span></span>
                        </div>
                        <span class="body-small" id="sys-disk-percent">--% used</span>
                    </div>
                </div>
            </div>
            <div class="card">
                <div class="card-header">
                    <h3>System & Deployment Logs</h3>
                    <div class="card-header-actions">
                        <select id="log-filter-level" onchange="filterLogs()" class="btn btn-tonal" style="height: 32px; padding: 0 16px 0 8px; font-size: 12px; border-radius: 8px;">
                            <option value="ALL">All Levels</option>
                            <option value="INFO">Info</option>
                            <option value="WARN">Warn</option>
                            <option value="ERROR">Error</option>
                            <option value="SECURITY">Security</option>
                        </select>
                        <select id="log-filter-cat" onchange="filterLogs()" class="btn btn-tonal" style="height: 32px; padding: 0 16px 0 8px; font-size: 12px; border-radius: 8px;">
                            <option value="ALL">All Categories</option>
                            <option value="SYSTEM">System</option>
                            <option value="NETWORK">Network</option>
                            <option value="MAINTENANCE">Maintenance</option>
                        </select>
                    </div>
                </div>
                <div id="log-container" class="log-container sensitive" style="display: flex; align-items: center; justify-content: center;">
                    <div style="display: flex; flex-direction: column; align-items: center; gap: 12px; opacity: 0.7;">
                        <div style="width: 24px; height: 24px; border: 3px solid var(--md-sys-color-primary); border-top: 3px solid transparent; border-radius: 50%; animation: spin 1s linear infinite;"></div>
                        <span class="body-medium">Connecting to Log Stream...</span>
                    </div>
                </div>
                <div id="log-status" class="body-small" style="color:var(--md-sys-color-on-surface-variant); text-align:right; margin-top:8px;">Connecting...</div>
            </div>
        </div>
        </section>

    <!-- Setup Wizard removed (Automated Deployment) -->

    <!-- Update Selection Modal -->
    <div id="update-selection-modal" class="modal-overlay">
        <div class="modal-card" style="max-width: 600px;">
            <div class="modal-header">
                <h2>Select Updates</h2>
                <button onclick="closeUpdateModal()" class="btn btn-icon"><span class="material-symbols-rounded">close</span></button>
            </div>
            <div style="padding: 16px 0;">
                <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px;">
                    <span class="body-medium" id="update-fetch-status" style="color: var(--md-sys-color-on-surface-variant);">Scanning for updates...</span>
                    <button onclick="toggleAllUpdates()" class="btn btn-tonal" style="height: 32px; font-size: 12px;">Reset / Undo</button>
                </div>
                <div id="update-list-container" style="background: var(--md-sys-color-surface-container-low); border-radius: 12px; padding: 8px; max-height: 300px; overflow-y: auto;">
                    <!-- Checkboxes injected here -->
                    <div style="padding: 24px; text-align: center; opacity: 0.6;">
                        <div style="width: 24px; height: 24px; border: 3px solid var(--md-sys-color-primary); border-top: 3px solid transparent; border-radius: 50%; animation: spin 1s linear infinite; margin: 0 auto 12px auto;"></div>
                        <span class="body-medium">Checking repositories...</span>
                    </div>
                </div>
            </div>
            <div class="btn-group" style="justify-content: flex-end;">
                <button onclick="startBatchUpdate()" class="btn btn-filled" id="start-update-btn" disabled>Update Selected</button>
            </div>
        </div>
    </div>

    <!-- Changelog Modal -->
    <div id="changelog-modal" class="modal-overlay" style="z-index: 26000;">
        <div class="modal-card" style="max-width: 600px; max-height: 80vh; display: flex; flex-direction: column;">
            <div class="modal-header">
                <h2 id="changelog-title">Changelog</h2>
                <button onclick="document.getElementById('changelog-modal').style.display='none'" class="btn btn-icon"><span class="material-symbols-rounded">close</span></button>
            </div>
            <div id="changelog-content" class="code-block" style="flex-grow: 1; overflow-y: auto; white-space: pre-wrap; margin-top: 16px; font-family: monospace; font-size: 13px;">
                Loading...
            </div>
        </div>
    </div>

    <!-- Service Management Modal -->
    <div id="service-modal" class="modal-overlay">
        <div class="modal-card">
            <div class="modal-header">
                <h2 id="modal-service-name">Service Settings</h2>
                <button onclick="closeServiceModal()" class="btn btn-icon"><span class="material-symbols-rounded">close</span></button>
            </div>
            <div id="modal-metrics" style="background: var(--md-sys-color-surface-container-low); padding: 16px; border-radius: 12px;">
                <div class="stat-row">
                    <span class="stat-label">CPU Usage <span id="modal-cpu-text" style="float:right; font-family:monospace; opacity:0.8;">0%</span></span>
                    <span class="stat-value" id="modal-cpu" style="display:none;">0%</span>
                </div>
                <div class="metric-bar"><div id="modal-cpu-fill" class="metric-fill" style="width: 0%"></div></div>
                
                <div class="stat-row" style="margin-top:12px;">
                                <span class="stat-label">Memory <span id="modal-mem-text" style="float:right; font-family:monospace; opacity:0.8;">0 MB / 0 MB</span></span>
                                <span class="stat-value" id="modal-mem" style="display:none;">0 MB / 0 MB</span>                </div>
                <div class="metric-bar"><div id="modal-mem-fill" class="metric-fill" style="width: 0%"></div></div>
            </div>
            <div id="modal-actions" class="btn-group" style="flex-direction: column; gap: 8px;">
                <!-- Actions injected via JS -->
            </div>
        </div>
    </div>

    <script>
        // Dynamic Service Rendering
        let serviceCatalog = {};

        function humanizeServiceId(id) {
            return id
                .replace(/[-_]+/g, ' ')
                .replace(/\b\w/g, (c) => c.toUpperCase());
        }

        async function loadServiceCatalog() {
            if (Object.keys(serviceCatalog).length) return serviceCatalog;
            try {
                const res = await fetch(API + "/services");
                const data = await res.json();
                serviceCatalog = data.services || {};
            } catch (e) {
                console.warn("Failed to load service catalog:", e);
                serviceCatalog = {};
            }
            return serviceCatalog;
        }

        function normalizeServiceMeta(id, meta) {
            const safe = (meta && typeof meta === 'object') ? meta : {};
            return {
                name: safe.name || humanizeServiceId(id),
                description: safe.description || 'Private service hosted locally.',
                category: safe.category || 'apps',
                url: safe.url || '',
                actions: Array.isArray(safe.actions) ? safe.actions : [],
                chips: Array.isArray(safe.chips) ? safe.chips : [],
                order: Number.isFinite(safe.order) ? safe.order : 999
            };
        }

        function handleServiceAction(id, action, event) {
            if (event) {
                event.preventDefault();
                event.stopPropagation();
            }
            if (!action || !action.type) return;
            if (action.type === 'migrate') {
                const mode = action.mode || 'migrate';
                const confirmFlag = action.confirm ? 'yes' : 'no';
                migrateService(id, mode, confirmFlag, event);
                return;
            }
            if (action.type === 'vacuum') {
                vacuumServiceDb(id, event);
                return;
            }
            if (action.type === 'clear-logs') {
                clearServiceLogs(id, event);
            }
        }

        function createActionButton(id, action) {
            const button = document.createElement('button');
            button.className = 'chip admin admin-only';
            button.type = 'button';
            const label = action.label || 'Action';
            if (action.icon) {
                const icon = document.createElement('span');
                icon.className = 'material-symbols-rounded';
                icon.textContent = action.icon;
                button.appendChild(icon);
            }
            button.appendChild(document.createTextNode(label));
            button.setAttribute('data-tooltip', label);
            button.onclick = (e) => handleServiceAction(id, action, e);
            return button;
        }

        function createChipElement(id, chip) {
            const chipEl = document.createElement('span');
            const isObject = chip && typeof chip === 'object';
            const label = isObject ? (chip.label || '') : String(chip || '');
            const variant = isObject ? (chip.variant || '') : 'admin';
            const classes = ['chip'];
            if (variant) {
                variant.split(' ').forEach((c) => c && classes.push(c));
                if (variant.includes('admin')) classes.push('admin-only');
            }
            if (!isObject || chip.portainer) {
                classes.push('portainer-link');
                chipEl.dataset.container = id;
            }
            chipEl.className = classes.join(' ');
            if (isObject && chip.tooltip) chipEl.setAttribute('data-tooltip', chip.tooltip);
            if (isObject && chip.icon) {
                const icon = document.createElement('span');
                icon.className = 'material-symbols-rounded';
                icon.textContent = chip.icon;
                chipEl.appendChild(icon);
            }
            chipEl.appendChild(document.createTextNode(label));
            return chipEl;
        }

        async function renderDynamicGrid() {
            try {
                const [containerRes, catalog] = await Promise.all([
                    fetch(API + "/containers"),
                    loadServiceCatalog()
                ]);
                const data = await containerRes.json();
                const activeContainers = data.containers || {};
                containerIds = activeContainers;

                const appsGrid = document.getElementById('grid-apps');
                const systemGrid = document.getElementById('grid-system');
                const toolsGrid = document.getElementById('grid-tools');
                const allGrid = document.getElementById('grid-all');
                
                if (appsGrid) appsGrid.innerHTML = '';
                if (systemGrid) systemGrid.innerHTML = '';
                if (toolsGrid) toolsGrid.innerHTML = '';
                if (allGrid) allGrid.innerHTML = '';

                const entries = Object.entries(catalog)
                    .filter(([id]) => activeContainers[id])
                    .map(([id, meta]) => [id, normalizeServiceMeta(id, meta)]);

                const buckets = { apps: [], system: [], tools: [], all: [] };
                entries.forEach(([id, meta]) => {
                    if (!buckets[meta.category]) buckets[meta.category] = [];
                    buckets[meta.category].push([id, meta]);
                    buckets.all.push([id, meta]);
                });

                const sortByOrder = (a, b) => {
                    const orderDelta = (a[1].order || 999) - (b[1].order || 999);
                    if (orderDelta !== 0) return orderDelta;
                    return a[1].name.localeCompare(b[1].name);
                };

                // Render categorized grids
                ['apps', 'system', 'tools'].forEach((category) => {
                    if (!buckets[category]) return;
                    const grid = document.getElementById(\`grid-\${category}\`);
                    if (!grid) return;
                    
                    buckets[category].sort(sortByOrder).forEach(([id, meta]) => {
                        const hardened = activeContainers[id] && activeContainers[id].hardened;
                        const card = createServiceCard(id, meta, hardened);
                        grid.appendChild(card);
                    });
                });

                // Render All Services grid
                if (allGrid && buckets.all) {
                    buckets.all.sort(sortByOrder).forEach(([id, meta]) => {
                        const hardened = activeContainers[id] && activeContainers[id].hardened;
                        const card = createServiceCard(id, meta, hardened);
                        allGrid.appendChild(card);
                    });
                }

                // Update metrics after rendering
                fetchMetrics();
            } catch (e) {
                console.error("Failed to render dynamic grid:", e);
            }
        }

        function createServiceCard(id, meta, hardened = false) {
            const card = document.createElement('div');
            card.id = \`link-\${id}\`;
            card.className = 'card';
            card.dataset.url = meta.url || '';
            card.dataset.container = id;
            card.dataset.check = 'true';
            card.onclick = (e) => navigate(card, e);

            const header = document.createElement('div');
            header.className = 'card-header';

            const title = document.createElement('h2');
            title.textContent = meta.name || humanizeServiceId(id);

            const actionsWrap = document.createElement('div');
            actionsWrap.className = 'card-header-actions';

            const indicator = document.createElement('div');
            indicator.className = 'status-indicator';
            const dot = document.createElement('span');
            dot.className = 'status-dot';
            const text = document.createElement('span');
            text.className = 'status-text';
            text.textContent = 'Connecting...';
            indicator.appendChild(dot);
            indicator.appendChild(text);

            const settingsBtn = document.createElement('button');
            settingsBtn.className = 'btn btn-icon settings-btn admin-only';
            settingsBtn.setAttribute('data-tooltip', 'Service Management & Metrics');
            settingsBtn.onclick = (e) => openServiceSettings(id, e);
            const settingsIcon = document.createElement('span');
            settingsIcon.className = 'material-symbols-rounded';
            settingsIcon.textContent = 'settings';
            settingsBtn.appendChild(settingsIcon);

            const navArrow = document.createElement('span');
            navArrow.className = 'material-symbols-rounded nav-arrow';
            navArrow.textContent = 'arrow_forward';

            actionsWrap.appendChild(indicator);
            actionsWrap.appendChild(settingsBtn);
            actionsWrap.appendChild(navArrow);

            header.appendChild(title);
            header.appendChild(actionsWrap);

            const desc = document.createElement('p');
            desc.className = 'description';
            desc.textContent = meta.description || 'Private service hosted locally.';

            const chipBox = document.createElement('div');
            chipBox.className = 'chip-box';

            if (hardened) {
                const hardenedBadge = document.createElement('span');
                hardenedBadge.className = 'chip tertiary';
                hardenedBadge.style.gap = '4px';
                hardenedBadge.style.padding = '0 8px';
                hardenedBadge.style.height = '24px';
                hardenedBadge.style.fontSize = '11px';
                hardenedBadge.setAttribute('data-tooltip', 'This container uses a Digital Independence (DHI) hardened image.');
                hardenedBadge.innerHTML = '<span class="material-symbols-rounded" style="font-size:14px;">verified_user</span> Hardened';
                chipBox.appendChild(hardenedBadge);
            }

            if (Array.isArray(meta.actions)) {
                meta.actions.forEach((action) => {
                    chipBox.appendChild(createActionButton(id, action));
                });
            }
            if (Array.isArray(meta.chips)) {
                meta.chips.forEach((chip) => {
                    chipBox.appendChild(createChipElement(id, chip));
                });
            }

            card.appendChild(header);
            card.appendChild(desc);
            card.appendChild(chipBox);
            return card;
        }

        // Initialize dynamic grid
        document.addEventListener('DOMContentLoaded', () => {
            renderDynamicGrid();
            initMacAdvisory();
            // Refresh grid occasionally to catch new services
            setInterval(renderDynamicGrid, 30000);
        });

        const API = "/api"; 
        const ODIDO_API = "/odido-api/api";
        
        function filterCategory(cat) {
            document.querySelectorAll('.filter-chip').forEach(c => c.classList.remove('active'));
            const targetChip = document.querySelector(\`.filter-chip[data-target="\${cat}"]\`);
            if (targetChip) targetChip.classList.add('active');
            
            const allSection = document.getElementById('section-all');
            const otherSections = document.querySelectorAll('section[data-category]:not(#section-all)');
            
            if (cat === 'all') {
                if (allSection) allSection.style.display = 'block';
                otherSections.forEach(s => s.style.display = 'none');
            } else {
                if (allSection) allSection.style.display = 'none';
                otherSections.forEach(s => {
                    if (s.dataset.category === cat) {
                        s.style.display = 'block';
                        s.classList.remove('hidden');
                    } else {
                        s.style.display = 'none';
                    }
                });
            }

            localStorage.setItem('dashboard_filter', cat);
            syncSettings();
            showSnackbar(\`Filtering by: \${cat.charAt(0).toUpperCase() + cat.slice(1)}\`, "Dismiss");
        }

        // Global State & Data
        let isAdmin = sessionStorage.getItem('is_admin') === 'true';
        let sessionToken = sessionStorage.getItem('session_token') || '';
        let sessionCleanupEnabled = true;
        let containerMetrics = {};
        let containerIds = {};
        let pendingUpdates = [];

        function updateAdminUI() {
            document.body.classList.toggle('admin-mode', isAdmin);
            const icon = document.getElementById('admin-icon');
            if (icon) {
                icon.textContent = isAdmin ? 'admin_panel_settings' : 'lock_person';
                icon.parentElement.style.background = isAdmin ? 'var(--md-sys-color-primary-container)' : '';
                icon.style.color = isAdmin ? 'var(--md-sys-color-on-primary-container)' : 'inherit';
            }
            const btn = document.getElementById('admin-lock-btn');
            if (btn) btn.dataset.tooltip = isAdmin ? "Exit Admin Mode" : "Enter Admin Mode";

            // Session cleanup UI
            const switchEl = document.getElementById('session-cleanup-switch');
            const warningEl = document.getElementById('session-cleanup-warning');
            if (switchEl) switchEl.classList.toggle('active', sessionCleanupEnabled);
            if (warningEl) warningEl.style.display = (isAdmin && !sessionCleanupEnabled) ? 'flex' : 'none';
        }

        async function toggleSessionCleanup() {
            const newState = !sessionCleanupEnabled;
            try {
                const res = await fetch(API + "/toggle-session-cleanup", {
                    method: 'POST',
                    headers: getAuthHeaders(),
                    body: JSON.stringify({ enabled: newState })
                });
                const data = await res.json();
                if (data.success) {
                    sessionCleanupEnabled = data.enabled;
                    updateAdminUI();
                    showSnackbar(sessionCleanupEnabled ? "Session auto-cleanup enabled" : "Session auto-cleanup disabled (Persistent Mode)");
                }
            } catch (e) {
                showSnackbar("Failed to toggle session cleanup");
            }
        }

        async function toggleAdminMode() {
            if (isAdmin) {
                if (confirm("Exit Admin Mode? Management features will be hidden.")) {
                    isAdmin = false;
                    sessionStorage.setItem('is_admin', 'false');
                    sessionStorage.removeItem('session_token');
                    sessionToken = '';
                    updateAdminUI();
                    syncSettings();
                    showSnackbar("Admin Mode disabled");
                }
            } else {
                const pass = prompt("Enter Admin Password to enable management features:");
                if (!pass) return;
                
                try {
                    const res = await fetch(API + "/verify-admin", {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ password: pass })
                    });
                    if (res.ok) {
                        const data = await res.json();
                        isAdmin = true;
                        sessionToken = data.token || '';
                        sessionCleanupEnabled = data.cleanup !== false;
                        sessionStorage.setItem('is_admin', 'true');
                        if (sessionToken) sessionStorage.setItem('session_token', sessionToken);
                        updateAdminUI();
                        syncSettings();
                        showSnackbar("Admin Mode enabled. Management tools unlocked.", "Dismiss");
                    } else {
                        showSnackbar("Authentication failed: Invalid password", "Retry");
                    }
                } catch(e) {
                    showSnackbar("Error connecting to auth service");
                }
            }
        }
        let realProfileName = '';
        let maskedProfileId = '';
        const profileMaskMap = {};
        let odidoHistory = [];

        async function updateOdidoGraph(rate, remaining) {
            const now = Date.now();
            odidoHistory.push({ time: now, rate: rate, remaining: remaining });
            if (odidoHistory.length > 50) odidoHistory.shift();

            const svg = document.getElementById('odido-graph');
            const line = document.getElementById('graph-line');
            const area = document.getElementById('graph-area');
            const speedIndicator = document.getElementById('odido-speed-indicator');
            if (!svg || !line || !area) return;

            const width = 400;
            const height = 120;
            
            // Smooth the rate for the graph
            const smoothHistory = odidoHistory.map((d, i) => {
                const start = Math.max(0, i - 2);
                const end = Math.min(odidoHistory.length - 1, i + 2);
                const subset = odidoHistory.slice(start, end + 1);
                const avgRate = subset.reduce((acc, curr) => acc + curr.rate, 0) / subset.length;
                return { ...d, smoothRate: avgRate };
            });

            const maxRate = Math.max(...smoothHistory.map(d => d.smoothRate), 0.1);
            
            // Speed indicator (MB/min to Mb/s: * 8 / 60)
            const speedMbs = (rate * 8 / 60).toFixed(2);
            if (speedIndicator) {
                speedIndicator.textContent = speedMbs + " Mb/s";
                speedIndicator.style.display = rate > 0 ? 'block' : 'none';
            }

            if (smoothHistory.length < 2) return;

            let points = "";
            smoothHistory.forEach((d, i) => {
                const x = (i / (smoothHistory.length - 1)) * width;
                const y = height - (d.smoothRate / (maxRate * 1.2)) * height;
                points += (i === 0 ? "M" : " L") + x + "," + y;
            });

            line.setAttribute("d", points);
            area.setAttribute("d", points + " L" + width + "," + height + " L0," + height + " Z");
        }

        async function fetchMetrics() {
            try {
                const res = await fetch(API + "/metrics", { headers: getAuthHeaders() });
                if (!res.ok) return;
                const data = await res.json();
                containerMetrics = data.metrics || {};
            } catch(e) { console.error("Metrics fetch error:", e); }
        }

        function getPortainerBaseUrl() {
            if (window.location.hostname !== '$LAN_IP' && !window.location.hostname.match(/^\d+\.\d+\.\d+\.\d+$/)) {
                const parts = window.location.hostname.split('.');
                if (parts.length >= 2) {
                    const domain = parts.slice(-2).join('.');
                    const port = window.location.port ? ":" + window.location.port : "";
                    return "https://portainer." + domain + port;
                }
            }
            return "http://$LAN_IP:$PORT_PORTAINER";
        }

        const PORTAINER_URL = getPortainerBaseUrl();
        const DEFAULT_ODIDO_API_KEY = "$ODIDO_API_KEY";
        let storedOdidoKey = sessionStorage.getItem('odido_api_key');
        if (DEFAULT_ODIDO_API_KEY && !storedOdidoKey) {
            // Keep default key in session only
            storedOdidoKey = DEFAULT_ODIDO_API_KEY;
            sessionStorage.setItem('odido_api_key', DEFAULT_ODIDO_API_KEY);
        }
        let odidoApiKey = storedOdidoKey || DEFAULT_ODIDO_API_KEY;

        function getAuthHeaders() {
            const headers = { 'Content-Type': 'application/json' };
            if (sessionToken) headers['X-Session-Token'] = sessionToken;
            else if (odidoApiKey) headers['X-API-Key'] = odidoApiKey;
            return headers;
        }

        async function fetchUpdates() {
            try {
                const res = await fetch(API + "/updates", { headers: getAuthHeaders() });
                if (!res.ok) return;
                const data = await res.json();
                const updates = data.updates || {};
                pendingUpdates = Object.keys(updates);
                
                const banner = document.getElementById('update-banner');
                const list = document.getElementById('update-list');
                
                if (pendingUpdates.length > 0) {
                    if (banner) banner.style.display = 'block';
                    if (list) list.textContent = "Updates available for: " + pendingUpdates.join(", ");
                } else {
                    if (banner) banner.style.display = 'none';
                }
            } catch(e) {}
        }

        async function openServiceSettings(name, e) {
            if (e) { e.preventDefault(); e.stopPropagation(); }
            await showServiceModal(name);
        }

        async function showServiceModal(name) {
            const modal = document.getElementById('service-modal');
            const title = document.getElementById('modal-service-name');
            const actions = document.getElementById('modal-actions');
            title.textContent = name.charAt(0).toUpperCase() + name.slice(1) + " Management";
            
            // Ensure we have the latest IDs
            await fetchContainerIds();
            
            // Basic actions for all
            const containerInfo = containerIds[name];
            const cid = containerInfo ? containerInfo.id : null;
            const portainerLink = cid ?
                PORTAINER_URL + "/#!/1/docker/containers/" + cid :
                PORTAINER_URL + "/#!/1/docker/containers";
            
            actions.innerHTML = \`<button onclick="updateService('\${name}')" class="btn btn-tonal" style="width:100%"><span class="material-symbols-rounded">update</span> Update Service</button><p class="body-small" style="margin: 4px 0 12px 0; color: var(--md-sys-color-on-surface-variant);">Note: Updates may cause temporary high CPU/RAM usage during build.</p><button onclick="window.open('\${portainerLink}', '_blank')" class="btn btn-outlined" style="width:100%"><span class="material-symbols-rounded">dock</span> View in Portainer</button>\`;

            // Specialized actions
            if (name === 'invidious') {
                actions.innerHTML += "<button onclick=\"migrateService('invidious', event)\" class=\"btn btn-filled\" style=\"width:100%\"><span class=\"material-symbols-rounded\">database_upload</span> Migrate Database</button><button onclick=\"clearServiceDb('invidious', event)\" class=\"btn btn-tonal\" style=\"width:100%; color:var(--md-sys-color-error)\"><span class=\"material-symbols-rounded\">delete_forever</span> Wipe All Data</button>";
            } else if (name === 'adguard') {
                actions.innerHTML += "<button onclick=\"clearServiceLogs('adguard', event)\" class=\"btn btn-tonal\" style=\"width:100%\"><span class=\"material-symbols-rounded\">auto_delete</span> Clear Query Logs</button>";
            } else if (name === 'memos') {
                actions.innerHTML += "<button onclick=\"vacuumServiceDb('memos', event)\" class=\"btn btn-tonal\" style=\"width:100%\"><span class=\"material-symbols-rounded\">compress</span> Optimize Database</button>";
            }

            modal.style.display = 'flex';
            updateModalMetrics(name);
        }

        function closeServiceModal() {
            document.getElementById('service-modal').style.display = 'none';
        }

        function updateModalMetrics(name) {
            const m = containerMetrics[name];
            if (m) {
                const cpu = parseFloat(m.cpu) || 0;
                document.getElementById('modal-cpu-text').textContent = cpu.toFixed(1) + "%";
                document.getElementById('modal-cpu-fill').style.width = Math.min(100, cpu) + "%";
                
                const mem = parseFloat(m.mem) || 0;
                const limit = parseFloat(m.limit) || 1;
                const memPercent = Math.min(100, (mem / limit) * 100);
                document.getElementById('modal-mem-text').textContent = Math.round(mem) + " MB / " + Math.round(limit) + " MB";
                document.getElementById('modal-mem-fill').style.width = memPercent + "%";
            }
        }

        async function updateAllServices() {
            openUpdateModal();
        }

        let isAllSelected = true;

        function openUpdateModal() {
            const modal = document.getElementById('update-selection-modal');
            modal.style.display = 'flex';
            document.getElementById('start-update-btn').disabled = true;
            
            // Trigger check
            fetch(API + "/check-updates", { headers: odidoApiKey ? { 'X-API-Key': odidoApiKey } : {} });
            
            // Poll for results
            const listContainer = document.getElementById('update-list-container');
            const statusLabel = document.getElementById('update-fetch-status');
            
            let attempts = 0;
            const poll = setInterval(async () => {
                attempts++;
                statusLabel.textContent = "Scanning repositories... (" + attempts + ")";
                try {
                    const res = await fetch(API + "/updates", { headers: odidoApiKey ? { 'X-API-Key': odidoApiKey } : {} });
                    const data = await res.json();
                    const updates = data.updates || {};
                    const keys = Object.keys(updates);
                    
                    if (keys.length > 0 || attempts > 5) {
                        clearInterval(poll);
                        renderUpdateList(keys);
                        statusLabel.textContent = keys.length + " updates found.";
                        document.getElementById('start-update-btn').disabled = keys.length === 0;
                    }
                } catch(e) {}
            }, 2000);
        }

        function closeUpdateModal() {
            document.getElementById('update-selection-modal').style.display = 'none';
        }

        function renderUpdateList(services) {
            const el = document.getElementById('update-list-container');
            el.innerHTML = '';
            if (services.length === 0) {
                el.innerHTML = '<div style="padding: 24px; text-align: center; opacity: 0.7;">No updates found. System is up to date.</div>';
                return;
            }
            services.forEach(svc => {
                const row = document.createElement('div');
                row.className = 'list-item';
                row.style.margin = '4px 0';
                row.style.background = 'transparent';
                row.style.border = 'none';
                row.innerHTML = \`
                    <div style="display:flex; align-items:center; justify-content:space-between; width:100%;">
                        <label style="display:flex; align-items:center; gap:12px; cursor:pointer; flex-grow:1;">
                            <input type="checkbox" class="update-checkbox" value="\${svc}" checked style="width:18px; height:18px; accent-color:var(--md-sys-color-primary);">
                            <span class="list-item-text">\${svc}</span>
                        </label>
                        <div style="display:flex; gap:8px; align-items:center;">
                            <button onclick="viewChangelog('\${svc}')" class="btn btn-icon" style="width:32px; height:32px;" data-tooltip="View Changes">
                                <span class="material-symbols-rounded" style="font-size:18px;">description</span>
                            </button>
                            <span class="chip tertiary" style="height:24px; font-size:11px;">Update Available</span>
                        </div>
                    </div>
                \`;
                el.appendChild(row);
            });
        }

        async function viewChangelog(service) {
            const modal = document.getElementById('changelog-modal');
            const title = document.getElementById('changelog-title');
            const content = document.getElementById('changelog-content');
            
            title.textContent = "Changes: " + service;
            content.textContent = "Fetching release notes...";
            modal.style.display = 'flex';
            
            try {
                const headers = odidoApiKey ? { 'X-API-Key': odidoApiKey } : {};
                const res = await fetch(API + "/changelog?service=" + service, { headers });
                const data = await res.json();
                
                if (data.error) throw new Error(data.error);
                content.textContent = data.changelog || "No changelog information available.";
            } catch (e) {
                content.textContent = "Failed to load changelog: " + e.message;
            }
        }

        function toggleAllUpdates() {
            const checkboxes = document.querySelectorAll('.update-checkbox');
            isAllSelected = !isAllSelected;
            // If the user wants to "Undo" (reset), we assume resetting to ALL checked.
            // The prompt says "undo button for the unchecked checkboxes list", which I interpret as "Check All".
            checkboxes.forEach(cb => cb.checked = true);
            isAllSelected = true; 
        }

        async function startBatchUpdate() {
            const checkboxes = document.querySelectorAll('.update-checkbox:checked');
            const selected = Array.from(checkboxes).map(cb => cb.value);
            
            if (selected.length === 0) {
                showSnackbar("No services selected.", "Dismiss");
                return;
            }

            if (!confirm("Update " + selected.length + " services? This will trigger backups, updates, and rebuilds (Expect high CPU usage).")) return;
            
            closeUpdateModal();
            showSnackbar(\`Batch update initiated for \${selected.length} services. Rebuilding in background...\`, "Dismiss");
            
            try {
                const res = await fetch(API + "/batch-update", {
                    method: 'POST',
                    headers: getAuthHeaders(),
                    body: JSON.stringify({ services: selected })
                });
                const data = await res.json();
                if (data.error) throw new Error(data.error);
                showSnackbar("Batch update request accepted. Check logs for detailed progress.", "OK");
            } catch(e) {
                showSnackbar("Batch update failed: " + e.message, "Error");
            }
        }

        async function updateService(name) {
            const btn = event?.target.closest('button');
            const originalHtml = btn ? btn.innerHTML : '';
            if (btn) {
                btn.disabled = true;
                btn.innerHTML = \`<span class="material-symbols-rounded" style="animation: spin 2s linear infinite;">sync</span> Updating...\`;
            }
            showSnackbar(\`Initiating update for \${name}...\`, "Dismiss");

            try {
                const res = await fetch(API + "/update-service", {
                    method: 'POST',
                    headers: getAuthHeaders(),
                    body: JSON.stringify({ service: name })
                });
                const data = await res.json();
                if (data.error) throw new Error(data.error);
                
                showSnackbar(\`\${name} update complete.\`, "Success");
                return true;
            } catch(e) {
                showSnackbar(\`Update failed: \${e.message}\`, "Error");
                return false;
            } finally {
                if (btn) {
                    btn.disabled = false;
                    btn.innerHTML = originalHtml;
                }
            }
        }
        async function migrateService(name, event) {
            if (event) { event.preventDefault(); event.stopPropagation(); }
            const doBackup = document.getElementById('invidious-backup-toggle')?.checked ? 'yes' : 'no';
            if (!confirm("Run foolproof migration for " + name + "?" + (doBackup === 'yes' ? " This will create a database backup first." : " WARNING: No backup will be created."))) return;
            try {
                const res = await fetch(API + "/migrate?service=" + name + "&backup=" + doBackup);
                const data = await res.json();
                if (data.error) throw new Error(data.error);
                alert("Migration successful!\n\n" + data.output);
            } catch(e) {
                alert("Migration failed: " + e.message);
            }
        }

        async function clearServiceDb(name, event) {
            if (event) { event.preventDefault(); event.stopPropagation(); }
            const doBackup = document.getElementById('invidious-backup-toggle')?.checked ? 'yes' : 'no';
            if (!confirm("DANGER: This will permanently DELETE all subscriptions and preferences for " + name + "." + (doBackup === 'yes' ? " A backup will be created first." : " WARNING: NO BACKUP WILL BE CREATED.") + " Continue?")) return;
            try {
                const res = await fetch(API + "/clear-db?service=" + name + "&backup=" + doBackup);
                const data = await res.json();
                if (data.error) throw new Error(data.error);
                alert("Database cleared successfully!\n\n" + data.output);
            } catch(e) {
                showSnackbar("Action failed: " + e.message);
            }
        }

        async function clearServiceLogs(name, event) {
            if (event) { event.preventDefault(); event.stopPropagation(); }
            if (!confirm("Clear all historical query logs for " + name + "? This cannot be undone.")) return;
            try {
                const res = await fetch(API + "/clear-logs?service=" + name);
                const data = await res.json();
                if (data.error) throw new Error(data.error);
                showSnackbar("Logs cleared successfully!");
            } catch(e) {
                showSnackbar("Failed to clear logs: " + e.message);
            }
        }

        async function vacuumServiceDb(name, event) {
            if (event) { event.preventDefault(); event.stopPropagation(); }
            showSnackbar("Optimizing database... please wait.");
            try {
                const res = await fetch(API + "/vacuum?service=" + name);
                const data = await res.json();
                if (data.error) throw new Error(data.error);
                showSnackbar("Database optimized successfully!");
            } catch(e) {
                showSnackbar("Optimization failed: " + e.message);
            }
        }
        
        async function rotateApiKey() {
            const newKey = prompt("Enter new HUB_API_KEY. Warning: You must update your local .secrets manually if this fails!");
            if (!newKey) return;
            try {
                const res = await fetch(API + "/rotate-api-key", {
                    method: 'POST',
                    headers: getAuthHeaders(),
                    body: JSON.stringify({ new_key: newKey })
                });
                const data = await res.json();
                if (data.success) {
                    odidoApiKey = newKey;
                    sessionStorage.setItem('odido_api_key', newKey);
                    showSnackbar("API Key rotated successfully!");
                } else { throw new Error(data.error); }
            } catch(e) { showSnackbar("Rotation failed: " + e.message); }
        }

        async function filterLogs() {
            const level = document.getElementById('log-filter-level').value;
            const category = document.getElementById('log-filter-cat').value;
            let url = API + "/logs";
            const params = [];
            if (level !== 'ALL') params.push("level=" + level);
            if (category !== 'ALL') params.push("category=" + category);
            if (params.length) url += "?" + params.join("&");
            
            try {
                const res = await fetch(url);
                const data = await res.json();
                const el = document.getElementById('log-container');
                el.innerHTML = '';
                (data.logs || []).forEach(log => {
                    el.appendChild(parseLogLine(JSON.stringify(log)));
                });
            } catch(e) { showSnackbar("Failed to filter logs"); }
        }
        
        async function fetchContainerIds() {
            try {
                const res = await fetch(API + "/containers");
                if (!res.ok) throw new Error("API " + res.status);
                const data = await res.json();
                containerIds = data.containers || {};
                
                // Update all portainer links
                document.querySelectorAll('.portainer-link').forEach(el => {
                    const containerName = el.dataset.container;
                    const containerInfo = containerIds[containerName];
                    const cid = containerInfo ? containerInfo.id : null;
                    const originalText = el.getAttribute('data-original-text') || el.textContent.trim();
                    if (!el.getAttribute('data-original-text')) el.setAttribute('data-original-text', originalText);

                    if (cid) {
                        el.style.opacity = '1';
                        el.style.cursor = 'pointer';
                        el.dataset.tooltip = "Manage " + containerName + " in Portainer";
                        el.textContent = originalText;
                        
                        // Use a fresh onclick handler
                        el.onclick = (e) => {
                            e.preventDefault();
                            e.stopPropagation();
                            window.open(PORTAINER_URL + "/#!/1/docker/containers/" + cid, '_blank');
                        };
                    } else {
                        el.style.opacity = '0.6';
                        el.style.cursor = 'default';
                        el.onclick = (e) => { e.preventDefault(); e.stopPropagation(); };
                    }
                });
            } catch(e) { console.error('Container fetch error:', e); }
        }
        
        function navigate(el, e) {
            if (e && (e.target.closest('.portainer-link') || e.target.closest('.btn') || e.target.closest('.chip'))) return;
            const url = el.getAttribute('data-url');
            if (url && (url.startsWith('http://') || url.startsWith('https://'))) {
                window.open(url, '_blank');
            }
        }

        function generateRandomId() {
            const chars = 'abcdef0123456789';
            let id = '';
            for (let i = 0; i < 8; i++) id += chars.charAt(Math.floor(Math.random() * chars.length));
            return 'profile-' + id;
        }
        
        function updateProfileDisplay() {
            const vpnActive = document.getElementById('vpn-active');
            const isPrivate = document.body.classList.contains('privacy-mode');
            if (vpnActive && realProfileName) {
                if (isPrivate) {
                    if (!maskedProfileId) maskedProfileId = generateRandomId();
                    vpnActive.textContent = maskedProfileId;
                    vpnActive.classList.add('sensitive-masked');
                } else {
                    vpnActive.textContent = realProfileName;
                    vpnActive.classList.remove('sensitive-masked');
                }
            }
            updateProfileListDisplay();
        }

        function getProfileLabel(name) {
            const isPrivate = document.body.classList.contains('privacy-mode');
            if (!isPrivate) return name;
            if (!profileMaskMap[name]) profileMaskMap[name] = generateRandomId();
            return profileMaskMap[name];
        }

        function updateProfileListDisplay() {
            const items = document.querySelectorAll('#profile-list .list-item-text');
            items.forEach((item) => {
                const realName = item.dataset.realName;
                if (realName) item.textContent = getProfileLabel(realName);
            });
        }
        
        async function saveDesecConfig() {
            const domain = document.getElementById('desec-domain-input').value.trim();
            const token = document.getElementById('desec-token-input').value.trim();
            if (!domain && !token) {
                showSnackbar("Please provide domain or token");
                return;
            }
            try {
                const headers = { 'Content-Type': 'application/json' };
                if (odidoApiKey) headers['X-API-Key'] = odidoApiKey;
                const res = await fetch(API + "/config-desec", {
                    method: 'POST',
                    headers,
                    body: JSON.stringify({ domain, token })
                });
                const result = await res.json();
                if (result.success) {
                    showSnackbar("deSEC configuration saved! Certificates updating in background.");
                    document.getElementById('desec-domain-input').value = '';
                    document.getElementById('desec-token-input').value = '';
                } else {
                    throw new Error(result.error || "Unknown error");
                }
            } catch (e) {
                showSnackbar("Failed to save deSEC config: " + e.message);
            }
        }
        
        async function fetchStatus() {
            const controller = new AbortController();
            const timeoutId = setTimeout(() => controller.abort(), 10000);
            try {
                const headers = odidoApiKey ? { 'X-API-Key': odidoApiKey } : {};
                const res = await fetch(API + "/status", { headers, signal: controller.signal });
                clearTimeout(timeoutId);
                
                if (res.status === 401) {
                    throw new Error("401 Unauthorized");
                }
                
                const data = await res.json();
                const setText = (id, value) => {
                    const el = document.getElementById(id);
                    if (el) el.textContent = value;
                    return el;
                };
                const g = data.gluetun || {};
                const vpnStatus = document.getElementById('vpn-status');
                if (vpnStatus) {
                    if (g.status === "up" && g.healthy) {
                        vpnStatus.textContent = "Connected (Healthy)";
                        vpnStatus.className = "stat-value text-success";
                        vpnStatus.title = "VPN tunnel is active and passing health checks";
                    } else if (g.status === "up") {
                        vpnStatus.textContent = "Connected";
                        vpnStatus.className = "stat-value text-success";
                        vpnStatus.title = "VPN tunnel is active";
                    } else {
                        vpnStatus.textContent = "Disconnected";
                        vpnStatus.className = "stat-value error";
                        vpnStatus.title = "VPN tunnel is not established";
                    }
                }
                realProfileName = g.active_profile || "Unknown";
                updateProfileDisplay();
                setText('vpn-endpoint', g.endpoint || "--");
                setText('vpn-public-ip', g.public_ip || "--");
                setText('vpn-connection', g.handshake_ago || "Never");
                setText('vpn-session-rx', formatBytes(g.session_rx || 0));
                setText('vpn-session-tx', formatBytes(g.session_tx || 0));
                setText('vpn-total-rx', formatBytes(g.total_rx || 0));
                setText('vpn-total-tx', formatBytes(g.total_tx || 0));
                const w = data.wgeasy || {};
                const wgeStat = document.getElementById('wge-status');
                if (wgeStat) {
                    if (w.status === "up") {
                        wgeStat.textContent = "Running";
                        wgeStat.className = "stat-value text-success";
                        wgeStat.title = "WireGuard management service is operational";
                    } else {
                        wgeStat.textContent = "Stopped";
                        wgeStat.className = "stat-value error";
                        wgeStat.title = "WireGuard management service is not running";
                    }
                }
                setText('wge-host', w.host || "--");
                setText('wge-clients', w.clients || "0");
                const wgeConnected = document.getElementById('wge-connected');
                const connectedCount = parseInt(w.connected) || 0;
                if (wgeConnected) {
                    wgeConnected.textContent = connectedCount > 0 ? connectedCount + " active" : "None";
                    wgeConnected.className = connectedCount > 0 ? "stat-value text-success" : "stat-value";
                }
                setText('wge-session-rx', formatBytes(w.session_rx || 0));
                setText('wge-session-tx', formatBytes(w.session_tx || 0));
                setText('wge-total-rx', formatBytes(w.total_rx || 0));
                setText('wge-total-tx', formatBytes(w.total_tx || 0));

                // Update service statuses from server-side checks
                if (data.services) {
                    for (const [name, status] of Object.entries(data.services)) {
                        const card = document.getElementById('link-' + name);
                        if (card) {
                            const dot = card.querySelector('.status-dot');
                            const txt = card.querySelector('.status-text');
                            const indicator = card.querySelector('.status-indicator');
                            
                            if (dot && txt && indicator) {
                                if (status === 'unhealthy' && data.health_details && data.health_details[name]) {
                                    txt.textContent = 'Issue Detected';
                                    dot.className = 'status-dot down';
                                    indicator.title = data.health_details[name];
                                } else if (status === 'healthy' || status === 'up') {
                                    txt.textContent = 'Connected';
                                    dot.className = 'status-dot up';
                                    indicator.title = 'Service is connected and operational';
                                } else if (status === 'starting') {
                                    txt.textContent = 'Connecting...';
                                    dot.className = 'status-dot starting';
                                    indicator.title = 'Service is currently initializing';
                                } else {
                                    txt.textContent = 'Offline';
                                    dot.className = 'status-dot down';
                                    indicator.title = 'Service is unreachable';
                                }
                            }

                        }
                    }
                }
                
                const dot = document.getElementById('api-dot');
                const txt = document.getElementById('api-text');
                if (dot && txt) {
                    dot.className = 'status-dot up';
                    txt.textContent = 'Connected';
                }
            } catch(e) {
                console.error("Status fetch error:", e);
                const dot = document.getElementById('api-dot');
                const txt = document.getElementById('api-text');
                if (dot && txt) {
                    dot.className = 'status-dot down';
                    txt.textContent = 'Offline';
                }
                // Force indicators out of "Connecting..." state on API failure
                document.querySelectorAll('.status-indicator').forEach(indicator => {
                    const dot = indicator.querySelector('.status-dot');
                    const text = indicator.querySelector('.status-text');
                    if (dot && text && !dot.id.includes('api')) {
                        dot.className = 'status-dot down';
                        text.textContent = 'API Offline';
                        indicator.title = 'The Management Hub is unreachable. Real-time metrics, VPN switching, and service update controls are unavailable until connection is restored.';
                    }
                });
            }
        }
        
        async function fetchOdidoStatus() {
            const controller = new AbortController();
            const timeoutId = setTimeout(() => controller.abort(), 10000);
            try {
                const headers = odidoApiKey ? { 'X-API-Key': odidoApiKey } : {};
                const res = await fetch(ODIDO_API + "/status", { headers, signal: controller.signal });
                clearTimeout(timeoutId);
                if (!res.ok) {
                    const data = await res.json().catch(() => ({}));
                    document.getElementById('odido-loading').style.display = 'none';
                    document.getElementById('odido-not-configured').style.display = 'none';
                    document.getElementById('odido-configured').style.display = 'block';
                    document.getElementById('odido-remaining').textContent = '--';
                    document.getElementById('odido-bundle-code').textContent = '--';
                    document.getElementById('odido-threshold').textContent = '--';
                    const apiStatus = document.getElementById('odido-api-status');
                    
                    if (res.status === 401) {
                        apiStatus.textContent = 'Dashboard API Key Invalid';
                        apiStatus.style.color = 'var(--md-sys-color-error)';
                    } else if (res.status === 400 || (data.detail && data.detail.includes('credentials'))) {
                        apiStatus.textContent = 'Odido Account Not Linked';
                        apiStatus.style.color = 'var(--md-sys-color-warning)';
                    } else {
                        apiStatus.textContent = "Service Error: " + res.status;
                        apiStatus.style.color = 'var(--md-sys-color-error)';
                    }
                    return;
                }
                const data = await res.json();
                document.getElementById('odido-loading').style.display = 'none';
                document.getElementById('odido-not-configured').style.display = 'none';
                document.getElementById('odido-configured').style.display = 'block';
                const state = data.state || {};
                const config = data.config || {};
                const remaining = state.remaining_mb || 0;
                const threshold = config.absolute_min_threshold_mb || 100;
                const rate = data.consumption_rate_mb_per_min || 0;
                const bundleCode = config.bundle_code || 'A0DAY01';
                const hasOdidoCreds = config.odido_user_id && config.odido_token;
                // Also consider as "connected" if we have real data from the API
                const hasRealData = remaining > 0 || state.last_updated_ts;
                const isConfigured = hasOdidoCreds || hasRealData;
                document.getElementById('odido-remaining').textContent = Math.round(remaining) + " MB";
                document.getElementById('odido-bundle-code').textContent = bundleCode;
                document.getElementById('odido-threshold').textContent = threshold + " MB";
                document.getElementById('odido-auto-renew').textContent = config.auto_renew_enabled ? 'Enabled' : 'Disabled';
                document.getElementById('odido-rate').textContent = rate.toFixed(3) + " MB/min";
                const apiStatus = document.getElementById('odido-api-status');
                apiStatus.textContent = isConfigured ? 'Connected' : 'Not configured';
                apiStatus.style.color = isConfigured ? 'var(--md-sys-color-success)' : 'var(--md-sys-color-warning)';
                
                updateOdidoGraph(rate, remaining);

                const maxData = config.bundle_size_mb || 1024;
                const percent = Math.min(100, (remaining / maxData) * 100);
                const bar = document.getElementById('odido-bar');
                if (bar) {
                    bar.style.width = percent + "%";
                    bar.className = 'progress-indicator';
                    if (remaining < threshold) bar.classList.add('critical');
                    else if (remaining < threshold * 2) bar.classList.add('low');
                }
            } catch(e) {
                // Network error or service unavailable - show not-configured with error info
                const loading = document.getElementById('odido-loading');
                if (loading) loading.style.display = 'none';
                const notConf = document.getElementById('odido-not-configured');
                if (notConf) notConf.style.display = 'block';
                const conf = document.getElementById('odido-configured');
                if (conf) conf.style.display = 'none';
                console.error('Odido status error:', e);
            }
        }
        
        async function saveOdidoConfig() {
            const st = document.getElementById('odido-config-status');
            const data = {};
            const apiKey = document.getElementById('odido-api-key').value.trim();
            const oauthToken = document.getElementById('odido-oauth-token').value.trim();
            const bundleCode = document.getElementById('odido-bundle-code-input').value.trim();
            const threshold = document.getElementById('odido-threshold-input').value.trim();
            const leadTime = document.getElementById('odido-lead-time-input').value.trim();
            
            if (apiKey) {
                odidoApiKey = apiKey;
                sessionStorage.setItem('odido_api_key', apiKey);
                data.api_key = apiKey;
            }
            
            // If OAuth token provided, fetch User ID automatically via hub-api API (uses curl)
            if (oauthToken) {
                if (st) {
                    st.textContent = 'Fetching User ID from Odido API...';
                    st.style.color = 'var(--p)';
                }
                try {
                    const res = await fetch(API + "/odido-userid", {
                        method: 'POST',
                        headers: getAuthHeaders(),
                        body: JSON.stringify({ oauth_token: oauthToken })
                    });
                    const result = await res.json();
                    if (result.error) throw new Error(result.error);
                    if (result.user_id) {
                        data.odido_user_id = result.user_id;
                        data.odido_token = oauthToken;
                        if (st) {
                            st.textContent = "User ID fetched: " + result.user_id;
                            st.style.color = 'var(--ok)';
                        }
                    } else {
                        throw new Error('Could not extract User ID from Odido API response');
                    }
                } catch(e) {
                    if (st) {
                        st.textContent = "Failed to fetch User ID: " + e.message;
                        st.style.color = 'var(--err)';
                    }
                    return;
                }
            }
            
            if (bundleCode) data.bundle_code = bundleCode;
            if (threshold) data.absolute_min_threshold_mb = parseInt(threshold);
            if (leadTime) data.lead_time_minutes = parseInt(leadTime);
            
            if (Object.keys(data).length === 0) {
                if (st) {
                    st.textContent = 'Please fill in at least one field';
                    st.style.color = 'var(--err)';
                }
                return;
            }
            if (st) {
                st.textContent = 'Saving configuration...';
                st.style.color = 'var(--p)';
            }
            try {
                const res = await fetch(ODIDO_API + "/config", {
                    method: 'POST',
                    headers: getAuthHeaders(),
                    body: JSON.stringify(data)
                });
                const result = await res.json();
                if (result.detail) throw new Error(result.detail);
                if (st) {
                    st.textContent = 'Configuration saved!';
                    st.style.color = 'var(--ok)';
                }
                document.getElementById('odido-api-key').value = '';
                document.getElementById('odido-oauth-token').value = '';
                document.getElementById('odido-bundle-code-input').value = '';
                document.getElementById('odido-threshold-input').value = '';
                document.getElementById('odido-lead-time-input').value = '';
                fetchOdidoStatus();
            } catch(e) {
                if (st) {
                    st.textContent = e.message;
                    st.style.color = 'var(--err)';
                }
            }
        }
        
        async function buyOdidoBundle() {
            const st = document.getElementById('odido-buy-status');
            const btn = document.getElementById('odido-buy-btn');
            btn.disabled = true;
            if (st) {
                st.textContent = 'Purchasing bundle from Odido...';
                st.style.color = 'var(--p)';
            }
            try {
                const headers = { 'Content-Type': 'application/json' };
                if (odidoApiKey) headers['X-API-Key'] = odidoApiKey;
                const res = await fetch(ODIDO_API + "/odido/buy-bundle", {
                    method: 'POST',
                    headers,
                    body: JSON.stringify({})
                });
                const result = await res.json();
                if (result.detail) throw new Error(result.detail);
                if (st) {
                    st.textContent = 'Bundle purchased successfully!';
                    st.style.color = 'var(--ok)';
                }
                setTimeout(fetchOdidoStatus, 2000);
            } catch(e) {
                if (st) {
                    st.textContent = e.message;
                    st.style.color = 'var(--err)';
                }
            }
            btn.disabled = false;
        }
        
        async function refreshOdidoRemaining() {
            const st = document.getElementById('odido-buy-status');
            if (st) {
                st.textContent = 'Fetching from Odido API...';
                st.style.color = 'var(--p)';
            }
            try {
                const headers = {};
                if (odidoApiKey) headers['X-API-Key'] = odidoApiKey;
                const res = await fetch(ODIDO_API + "/odido/remaining", { headers });
                const result = await res.json();
                if (result.detail) throw new Error(result.detail);
                if (st) {
                    st.textContent = "Live data: " + Math.round(result.remaining_mb || 0) + " MB remaining";
                    st.style.color = 'var(--ok)';
                }
                setTimeout(fetchOdidoStatus, 1000);
            } catch(e) {
                if (st) {
                    st.textContent = e.message;
                    st.style.color = 'var(--err)';
                }
            }
        }
        
        async function fetchProfiles() {
            try {
                const headers = odidoApiKey ? { 'X-API-Key': odidoApiKey } : {};
                const res = await fetch(API + "/profiles", { headers });
                if (res.status === 401) throw new Error("401");
                const data = await res.json();
                const el = document.getElementById('profile-list');
                el.innerHTML = '';
                el.style.flexDirection = 'column';
                el.style.alignItems = 'stretch';
                el.style.justifyContent = 'flex-start';
                el.style.gap = '4px';
                
                if (data.profiles.length === 0) {
                    el.innerHTML = '<div style="text-align:center; padding: 24px; opacity: 0.6;"><span class="material-symbols-rounded" style="font-size: 48px;">folder_open</span><p class="body-medium">No profiles found</p></div>';
                    return;
                }

                data.profiles.forEach(p => {
                    const row = document.createElement('div');
                    row.className = 'list-item';
                    row.style.margin = '0';
                    row.style.borderRadius = '12px';
                    row.style.background = 'var(--md-sys-color-surface-container-low)';
                    row.style.border = '1px solid var(--md-sys-color-outline-variant)';

                    const content = document.createElement('div');
                    content.style.display = 'flex';
                    content.style.alignItems = 'center';
                    content.style.gap = '12px';
                    content.style.flex = '1';
                    content.style.cursor = 'pointer';
                    content.onclick = function() { activateProfile(p); };

                    const icon = document.createElement('span');
                    icon.className = 'material-symbols-rounded';
                    icon.textContent = 'vpn_key';
                    icon.style.color = 'var(--md-sys-color-primary)';

                    const name = document.createElement('span');
                    name.className = 'list-item-text';
                    name.style.flex = '1';
                    name.dataset.realName = p;
                    name.textContent = getProfileLabel(p);

                    content.appendChild(icon);
                    content.appendChild(name);

                    const delBtn = document.createElement('button');
                    delBtn.className = 'btn btn-icon';
                    delBtn.style.color = 'var(--md-sys-color-on-surface-variant)';
                    delBtn.title = 'Delete';
                    delBtn.innerHTML = '<span class="material-symbols-rounded">delete</span>';
                    delBtn.onclick = function(e) { e.stopPropagation(); deleteProfile(p); };

                    row.appendChild(content);
                    row.appendChild(delBtn);
                    el.appendChild(row);
                });
                updateProfileListDisplay();
            } catch(e) {
                console.error("Profile fetch error:", e);
            }
        }
        async function uploadProfile() {
            const nameInput = document.getElementById('prof-name').value;
            const config = document.getElementById('prof-conf').value;
            const st = document.getElementById('upload-status');
            if(!config) { if(st) st.textContent="Error: Config content missing"; else alert("Error: Config content missing"); return; }
            if(st) st.textContent = "Uploading...";
            try {
                const headers = { 'Content-Type': 'application/json' };
                if (odidoApiKey) headers['X-API-Key'] = odidoApiKey;
                const upRes = await fetch(API + "/upload", { 
                    method:'POST', 
                    headers: headers,
                    body:JSON.stringify({name: nameInput, config: config}) 
                });
                const upData = await upRes.json();
                if(upData.error) throw new Error(upData.error);
                const activeName = upData.name;
                if(st) st.textContent = "Activating " + activeName + "...";
                await fetch(API + "/activate", { 
                    method:'POST', 
                    headers: headers,
                    body:JSON.stringify({name: activeName}) 
                });
                if(st) st.textContent = "Success! VPN restarting."; else alert("Success! VPN restarting.");
                fetchProfiles(); document.getElementById('prof-name').value=""; document.getElementById('prof-conf').value="";
            } catch(e) { if(st) st.textContent = e.message; else alert(e.message); }
        }
        
        async function activateProfile(name) {
            if(!confirm("Switch to " + name + "?")) return;
            try { 
                const headers = { 'Content-Type': 'application/json' };
                if (odidoApiKey) headers['X-API-Key'] = odidoApiKey;
                await fetch(API + "/activate", { 
                    method:'POST', 
                    headers: headers,
                    body:JSON.stringify({name: name}) 
                }); 
                alert("Profile switched. VPN restarting."); 
            } catch(e) { alert("Error"); }
        }
        
        async function deleteProfile(name) {
            if(!confirm("Delete " + name + "?")) return;
            try { 
                const headers = { 'Content-Type': 'application/json' };
                if (odidoApiKey) headers['X-API-Key'] = odidoApiKey;
                await fetch(API + "/delete", { 
                    method:'POST', 
                    headers: headers,
                    body:JSON.stringify({name: name}) 
                }); 
                fetchProfiles(); 
            } catch(e) { alert("Error"); }
        }
        
        function startLogStream() {
            const el = document.getElementById('log-container');
            const status = document.getElementById('log-status');
            const evtSource = new EventSource(API + "/events");
            
            function parseLogLine(line) {
                let logData = null;
                try {
                    logData = JSON.parse(line);
                } catch(e) {
                    logData = { message: line, level: 'INFO', category: 'SYSTEM', timestamp: '' };
                }

                // Apply active filters
                const filterLevel = document.getElementById('log-filter-level').value;
                const filterCat = document.getElementById('log-filter-cat').value;
                if (filterLevel !== 'ALL' && logData.level !== filterLevel) return null;
                if (filterCat !== 'ALL' && logData.category !== filterCat) return null;

                // Filter out common noise
                const m = logData.message || "";
                if (m.includes('HTTP/1.1" 200') || m.includes('HTTP/1.1" 304')) {
                    // Only filter if it doesn't match a known humanization pattern
                    const knownPatterns = ['GET /status', 'GET /metrics', 'GET /containers', 'GET /updates', 'GET /logs', 'GET /certificate-status', 'GET /theme', 'POST /theme', 'GET /system-health', 'GET /profiles', 'POST /update-service', 'POST /batch-update', 'POST /restart-stack', 'POST /rotate-api-key', 'POST /activate', 'POST /upload', 'POST /delete', 'GET /check-updates', 'GET /changelog'];
                    if (!knownPatterns.some(p => m.includes(p))) return null;
                }
                
                const div = document.createElement('div');
                div.className = 'log-entry';
                
                let icon = 'info';
                let iconColor = 'var(--md-sys-color-primary)';
                let message = logData.message;
                let timestamp = logData.timestamp;

                // Humanization logic
                if (message.includes('GET /system-health')) message = 'System telemetry synchronized';
                if (message.includes('POST /update-service')) message = 'Service update initiated';
                if (message.includes('POST /theme')) message = 'UI theme preferences saved';
                if (message.includes('GET /theme')) message = 'UI theme assets synchronized';
                if (message.includes('GET /profiles')) message = 'VPN profiles synchronized';
                if (message.includes('POST /activate')) message = 'VPN profile switch triggered';
                if (message.includes('POST /upload')) message = 'VPN profile upload completed';
                if (message.includes('POST /delete')) message = 'VPN profile deletion requested';
                if (message.includes('Watchtower Notification')) message = 'Container update availability checked';
                if (message.includes('GET /status')) message = 'Service health status refreshed';
                if (message.includes('GET /metrics')) message = 'Performance metrics updated';
                if (message.includes('POST /batch-update')) message = 'Batch update sequence started';
                if (message.includes('GET /updates')) message = 'Checking repository update status';
                if (message.includes('GET /services')) message = 'Service catalog synchronized';
                if (message.includes('GET /check-updates')) message = 'Update availability check requested';
                if (message.includes('GET /changelog')) message = 'Service changelog retrieved';
                if (message.includes('POST /config-desec')) message = 'deSEC dynamic DNS updated';
                if (message.includes('GET /certificate-status')) message = 'SSL certificate validity checked';
                if (message.includes('GET /containers')) message = 'Container orchestration state audited';
                if (message.includes('GET /logs')) message = 'System logs retrieved';
                if (message.includes('GET /events')) message = 'Live log stream connection established';
                if (message.includes('POST /restart-stack')) message = 'Full system stack restart triggered';
                if (message.includes('POST /rotate-api-key')) message = 'Dashboard API security key rotated';

                // Category based icons
                if (logData.category === 'NETWORK') icon = 'lan';
                if (logData.category === 'AUTH' || logData.category === 'SECURITY') icon = 'lock';
                if (logData.category === 'MAINTENANCE') icon = 'build';
                if (logData.category === 'ORCHESTRATION') icon = 'hub';

                // Level based colors
                if (logData.level === 'WARN') {
                    icon = 'warning';
                    iconColor = 'var(--md-sys-color-warning)';
                } else if (logData.level === 'ERROR') {
                    icon = 'error';
                    iconColor = 'var(--md-sys-color-error)';
                } else if (logData.level === 'ACCESS') {
                    icon = 'api';
                    // Simplify common access logs
                    if (message.includes('GET /status')) message = 'Health check processed';
                    if (message.includes('GET /events')) message = 'Log stream connection';
                }

                div.innerHTML = \`
                    <span class="material-symbols-rounded log-icon" style="color: \${iconColor}">\${icon}</span>
                    <div class="log-content">\${message}</div>
                    <span class="log-time">\${timestamp}</span>
                \`;
                return div;
            }

            evtSource.onmessage = function(e) {
                if (!e.data) return;
                const entry = parseLogLine(e.data);
                if (!entry) return;
                
                // Clear the loader if it's still there
                if (el.querySelector('.body-medium')) {
                    el.innerHTML = '';
                    el.style.alignItems = 'flex-start';
                    el.style.justifyContent = 'flex-start';
                }
                
                el.appendChild(entry);
                if (el.childNodes.length > 500) el.removeChild(el.firstChild);
                el.scrollTop = el.scrollHeight;
            };
            evtSource.onopen = function() { status.textContent = "Live"; status.style.color = "var(--md-sys-color-success)"; };
            evtSource.onerror = function() { status.textContent = "Reconnecting..."; status.style.color = "var(--md-sys-color-error)"; evtSource.close(); setTimeout(startLogStream, 3000); };
        }
        
        function formatBytes(a,b=2){if(!+a)return"0 B";const c=0>b?0:b,d=Math.floor(Math.log(a)/Math.log(1024));return parseFloat((a/Math.pow(1024,d)).toFixed(c)) + " " + ["B","KiB","MiB","GiB","TiB"][d]}
        
        // Snackbar implementation
        const snackbarContainer = document.createElement('div');
        snackbarContainer.className = 'snackbar-container';
        document.body.appendChild(snackbarContainer);

        function showSnackbar(message, actionText = '', actionCallback = null) {
            const snackbar = document.createElement('div');
            snackbar.className = 'snackbar';
            
            let html = \`<div class="snackbar-content">\${message}</div>\`;
            if (actionText) {
                html += \`<button class="snackbar-action">\${actionText}</button>\`;
            }
            snackbar.innerHTML = html;
            
            if (actionCallback) {
                snackbar.querySelector('.snackbar-action').onclick = () => {
                    actionCallback();
                    snackbar.classList.remove('visible');
                    setTimeout(() => snackbar.remove(), 500);
                };
            }

            snackbarContainer.appendChild(snackbar);
            // Trigger reflow
            snackbar.offsetHeight;
            snackbar.classList.add('visible');

            setTimeout(() => {
                snackbar.classList.remove('visible');
                setTimeout(() => snackbar.remove(), 500);
            }, 1500);
        }

        // Theme customization logic
        async function applySeedColor(hex) {
            const hexEl = document.getElementById('theme-seed-hex');
            if (hexEl) hexEl.textContent = hex.toUpperCase();
            const colors = generateM3Palette(hex);
            applyThemeColors(colors);
            await syncSettings();
        }

        function renderThemePreset(seedHex) {
            const colors = generateM3Palette(seedHex);
            const container = document.createElement('div');
            container.style.width = '48px';
            container.style.height = '48px';
            container.style.borderRadius = '24px';
            container.style.backgroundColor = colors.surfaceContainer; // Background of the "folder"
            container.style.cursor = 'pointer';
            container.style.border = '1px solid var(--md-sys-color-outline-variant)';
            container.style.transition = 'transform 0.2s, border-color 0.2s';
            container.title = "Apply " + seedHex;
            container.style.display = 'grid';
            container.style.gridTemplateColumns = '1fr 1fr';
            container.style.gridTemplateRows = '1fr 1fr';
            container.style.overflow = 'hidden';
            container.style.padding = '4px';
            container.style.gap = '2px';

            const c1 = document.createElement('div'); c1.style.background = colors.primary; c1.style.borderRadius = '50%';
            const c2 = document.createElement('div'); c2.style.background = colors.secondary; c2.style.borderRadius = '50%';
            const c3 = document.createElement('div'); c3.style.background = colors.tertiary; c3.style.borderRadius = '50%';
            const c4 = document.createElement('div'); c4.style.background = colors.primaryContainer; c4.style.borderRadius = '50%';

            container.appendChild(c1); container.appendChild(c2); container.appendChild(c3); container.appendChild(c4);

            container.onmouseover = () => { container.style.transform = 'scale(1.1)'; container.style.borderColor = 'var(--md-sys-color-primary)'; };
            container.onmouseout = () => { container.style.transform = 'scale(1)'; container.style.borderColor = 'var(--md-sys-color-outline-variant)'; };
            container.onclick = () => { applySeedColor(seedHex); };
            
            return container;
        }

        function initStaticPresets() {
            const presets = ['#D0BCFF', '#93000A', '#FFA500', '#006e1c', '#0061a4', '#555555'];
            const container = document.getElementById('static-presets');
            if(container) {
                container.innerHTML = '';
                presets.forEach(hex => container.appendChild(renderThemePreset(hex)));
            }
        }

        async function extractColorsFromImage(event) {
            const file = event.target.files[0];
            if (!file) return;
            
            const reader = new FileReader();
            reader.onload = async function(e) {
                const img = new Image();
                img.src = e.target.result;
                await new Promise(r => img.onload = r);

                // Downscale for performance (max 128x128 is usually enough for color extraction)
                const canvas = document.createElement('canvas');
                const ctx = canvas.getContext('2d');
                const scale = Math.min(1, 128 / Math.max(img.width, img.height));
                canvas.width = img.width * scale;
                canvas.height = img.height * scale;
                ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
                
                const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height);
                const pixels = imageData.data;
                const argbPixels = [];
                
                for (let i = 0; i < pixels.length; i += 4) {
                    const r = pixels[i];
                    const g = pixels[i + 1];
                    const b = pixels[i + 2];
                    const a = pixels[i + 3];
                    if (a < 255) continue; // Skip transparent
                    // ARGB int format
                    const argb = (a << 24) | (r << 16) | (g << 8) | b;
                    argbPixels.push(argb);
                }

                if (typeof MaterialColorUtilities !== 'undefined' && MaterialColorUtilities.QuantizerCelebi) {
                    // Use official extraction
                    const result = MaterialColorUtilities.QuantizerCelebi.quantize(argbPixels, 128);
                    const ranked = MaterialColorUtilities.Score.score(result);
                    
                    // Clear previous
                    const container = document.getElementById('extracted-palette');
                    container.innerHTML = '';
                    
                    // Take top 4 or all if fewer
                    const topColors = ranked.slice(0, 4);
                    if (topColors.length === 0) {
                        // Fallback to naive average if algo fails
                        fallbackExtraction(pixels);
                        return;
                    }

                    topColors.forEach(argb => {
                        const hex = hexFromArgb(argb);
                        container.appendChild(renderThemePreset(hex));
                    });
                    
                    // Auto-select first
                    applySeedColor(hexFromArgb(topColors[0]));
                } else {
                    // Library missing? Fallback
                    fallbackExtraction(pixels);
                }
            };
            reader.readAsDataURL(file);
        }

        function fallbackExtraction(data) {
            let r = 0, g = 0, b = 0;
            const step = Math.max(1, Math.floor(data.length / 4000));
            let count = 0;
            for (let i = 0; i < data.length; i += step * 4) { 
                r += data[i]; g += data[i+1]; b += data[i+2];
                count++;
            }
            const avgHex = rgbToHex(Math.round(r/count), Math.round(g/count), Math.round(b/count));
            const container = document.getElementById('extracted-palette');
            container.innerHTML = '';
            container.appendChild(renderThemePreset(avgHex));
            applySeedColor(avgHex);
        }

        function addManualColor() {
            const input = document.getElementById('manual-color-input');
            let val = input.value.trim();
            if (!val.startsWith('#')) val = '#' + val;
            if (/^#[0-9A-F]{6}$/i.test(val)) {
                // Clear placeholder text if it exists
                const container = document.getElementById('extracted-palette');
                if (container.querySelector('span')) container.innerHTML = '';
                
                container.appendChild(renderThemePreset(val));
                applySeedColor(val);
                input.value = '';
            } else {
                alert("Invalid Hex Code");
            }
        }

        function addColorChip(hex) {
            // Deprecated, replaced by renderThemePreset but kept if needed for fallback logic not using renderThemePreset
            // For now we remove it to keep code clean as we replaced calls
        }

        function rgbToHex(r, g, b) {
            return "#" + ((1 << 24) + (r << 16) + (g << 8) + b).toString(16).slice(1);
        }

        function hexFromArgb(argb) {
            const r = (argb >> 16) & 255;
            const g = (argb >> 8) & 255;
            const b = argb & 255;
            return "#" + ((1 << 24) + (r << 16) + (g << 8) + b).toString(16).slice(1);
        }

        function getLuminance(hex) {
            const rgb = hexToRgb(hex);
            const rs = rgb.r / 255;
            const gs = rgb.g / 255;
            const bs = rgb.b / 255;
            const r = rs <= 0.03928 ? rs / 12.92 : Math.pow((rs + 0.055) / 1.055, 2.4);
            const g = gs <= 0.03928 ? gs / 12.92 : Math.pow((gs + 0.055) / 1.055, 2.4);
            const b = bs <= 0.03928 ? bs / 12.92 : Math.pow((bs + 0.055) / 1.055, 2.4);
            return 0.2126 * r + 0.7152 * g + 0.0722 * b;
        }

        function generateM3Palette(seedHex) {
            if (typeof MaterialColorUtilities === 'undefined') {
                // Fallback if library fails to load
                const rgb = hexToRgb(seedHex);
                const hsl = rgbToHsl(rgb.r, rgb.g, rgb.b);
                const lum = getLuminance(seedHex);
                const onPrimary = lum > 0.4 ? '#000000' : '#ffffff';
                return {
                    primary: seedHex,
                    onPrimary: onPrimary,
                    primaryContainer: hslToHex(hsl.h, hsl.s, Math.min(0.9, hsl.l + 0.3)),
                    onPrimaryContainer: hslToHex(hsl.h, hsl.s, Math.max(0.1, hsl.l - 0.4)),
                    secondary: hslToHex((hsl.h + 0.1) % 1, hsl.s * 0.5, hsl.l),
                    onSecondary: onPrimary,
                    secondaryContainer: hslToHex((hsl.h + 0.1) % 1, hsl.s * 0.5, Math.min(0.9, hsl.l + 0.3)),
                    onSecondaryContainer: hslToHex((hsl.h + 0.1) % 1, hsl.s * 0.5, Math.max(0.1, hsl.l - 0.4)),
                    tertiary: hslToHex((hsl.h + 0.5) % 1, hsl.s, hsl.l),
                    onTertiary: onPrimary,
                    tertiaryContainer: hslToHex((hsl.h + 0.5) % 1, hsl.s, Math.min(0.9, hsl.l + 0.3)),
                    onTertiaryContainer: hslToHex((hsl.h + 0.5) % 1, hsl.s, Math.max(0.1, hsl.l - 0.4)),
                    error: '#ba1a1a',
                    onError: '#ffffff',
                    errorContainer: '#ffdad6',
                    onErrorContainer: '#410002',
                    outline: '#79747e',
                    outlineVariant: '#c4c7c5',
                    surface: '#141218',
                    onSurface: '#e6e1e5',
                    surfaceVariant: '#49454f',
                    onSurfaceVariant: '#cac4d0'
                };
            }

            const argb = MaterialColorUtilities.argbFromHex(seedHex);
            const isDark = !document.documentElement.classList.contains('light-mode');
            const theme = MaterialColorUtilities.themeFromSourceColor(argb);
            const scheme = isDark ? theme.schemes.dark : theme.schemes.light;

            return {
                primary: hexFromArgb(scheme.primary),
                onPrimary: hexFromArgb(scheme.onPrimary),
                primaryContainer: hexFromArgb(scheme.primaryContainer),
                onPrimaryContainer: hexFromArgb(scheme.onPrimaryContainer),
                secondary: hexFromArgb(scheme.secondary),
                onSecondary: hexFromArgb(scheme.onSecondary),
                secondaryContainer: hexFromArgb(scheme.secondaryContainer),
                onSecondaryContainer: hexFromArgb(scheme.onSecondaryContainer),
                tertiary: hexFromArgb(scheme.tertiary),
                onTertiary: hexFromArgb(scheme.onTertiary),
                tertiaryContainer: hexFromArgb(scheme.tertiaryContainer),
                onTertiaryContainer: hexFromArgb(scheme.onTertiaryContainer),
                error: hexFromArgb(scheme.error),
                onError: hexFromArgb(scheme.onError),
                errorContainer: hexFromArgb(scheme.errorContainer),
                onErrorContainer: hexFromArgb(scheme.onErrorContainer),
                outline: hexFromArgb(scheme.outline),
                outlineVariant: hexFromArgb(scheme.outlineVariant),
                surface: hexFromArgb(scheme.surface),
                onSurface: hexFromArgb(scheme.onSurface),
                surfaceVariant: hexFromArgb(scheme.surfaceVariant),
                onSurfaceVariant: hexFromArgb(scheme.onSurfaceVariant)
            };
        }

        function applyThemeColors(colors) {
            const root = document.documentElement;
            for (const [key, value] of Object.entries(colors)) {
                root.style.setProperty('--md-sys-color-' + key.replace(/[A-Z]/g, m => "-" + m.toLowerCase()), value);
            }
        }

        async function syncSettings() {
            const seed = document.getElementById('theme-seed-color').value;
            const isLight = document.documentElement.classList.contains('light-mode');
            const isPrivacy = document.body.classList.contains('privacy-mode');
            const activeFilter = localStorage.getItem('dashboard_filter') || 'all';
            
            const settings = {
                seed,
                theme: isLight ? 'light' : 'dark',
                privacy_mode: isPrivacy,
                dashboard_filter: activeFilter,
                is_admin: isAdmin,
                timestamp: Date.now()
            };

            try {
                await fetch(API + "/theme", {
                    method: 'POST',
                    headers: getAuthHeaders(),
                    body: JSON.stringify(settings)
                });
            } catch(e) { console.warn("Failed to sync settings to server", e); }
        }

        async function saveThemeSettings() {
            await syncSettings();
            showSnackbar("Settings synchronized to server");
        }

        async function uninstallStack() {
            if (!confirm("⚠️ DANGER: This will permanently remove all containers, volumes, and data. This cannot be undone. Are you absolutely sure?")) return;
            if (!confirm("LAST WARNING: Final confirmation required to proceed with uninstallation.")) return;
            
            showSnackbar("Uninstallation sequence initiated...");
            try {
                const res = await fetch(API + "/uninstall", { 
                    method: 'POST', 
                    headers: getAuthHeaders() 
                });
                const result = await res.json();
                if (result.success) {
                    showSnackbar("System removed. Redirecting...");
                    setTimeout(() => window.location.href = "about:blank", 3000);
                } else {
                    throw new Error(result.error || "Uninstall failed");
                }
            } catch (e) {
                showSnackbar("Error during uninstall: " + e.message);
            }
        }

        async function loadAllSettings() {
            try {
                const res = await fetch(API + "/theme", { headers: getAuthHeaders() });
                const data = await res.json();
                
                // 1. Seed & Colors
                if (data.seed) {
                    const picker = document.getElementById('theme-seed-color');
                    if (picker) picker.value = data.seed;
                    applyThemeColors(data.colors || generateM3Palette(data.seed));
                }
                
                // 2. Theme (Light/Dark)
                if (data.theme) {
                    const isLight = data.theme === 'light';
                    document.documentElement.classList.toggle('light-mode', isLight);
                    localStorage.setItem('theme', data.theme);
                    updateThemeIcon();
                }
                
                // 3. Privacy Mode
                if (data.hasOwnProperty('privacy_mode')) {
                    const toggle = document.getElementById('privacy-switch');
                    if (toggle) toggle.classList.toggle('active', data.privacy_mode);
                    document.body.classList.toggle('privacy-mode', data.privacy_mode);
                    localStorage.setItem('privacy_mode', data.privacy_mode ? 'true' : 'false');
                    updateProfileDisplay();
                }
                
                // 4. Dashboard Filter
                if (data.dashboard_filter) {
                    localStorage.setItem('dashboard_filter', data.dashboard_filter);
                    filterCategory(data.dashboard_filter);
                }

                // 5. Admin Mode
                if (data.hasOwnProperty('is_admin')) {
                    isAdmin = data.is_admin;
                    sessionStorage.setItem('is_admin', isAdmin ? 'true' : 'false');
                    updateAdminUI();
                }
            } catch(e) { console.warn("Failed to load settings from server", e); }
        }

        function hexToRgb(hex) {
            const result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
            return result ? {
                r: parseInt(result[1], 16),
                g: parseInt(result[2], 16),
                b: parseInt(result[3], 16)
            } : { r:0, g:0, b:0 };
        }

        function rgbToHsl(r, g, b) {
            r /= 255, g /= 255, b /= 255;
            const max = Math.max(r, g, b), min = Math.min(r, g, b);
            let h, s, l = (max + min) / 2;
            if (max == min) h = s = 0;
            else {
                const d = max - min;
                s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
                switch (max) {
                    case r: h = (g - b) / d + (g < b ? 6 : 0); break;
                    case g: h = (b - r) / d + 2; break;
                    case b: h = (r - g) / d + 4; break;
                }
                h /= 6;
            }
            return { h, s, l };
        }

        function hslToHex(h, s, l) {
            let r, g, b;
            if (s == 0) r = g = b = l;
            else {
                const hue2rgb = (p, q, t) => {
                    if (t < 0) t += 1;
                    if (t > 1) t -= 1;
                    if (t < 1/6) return p + (q - p) * 6 * t;
                    if (t < 1/2) return q;
                    if (t < 2/3) return p + (q - p) * (2/3 - t) * 6;
                    return p;
                };
                const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
                const p = 2 * l - q;
                r = hue2rgb(p, q, h + 1/3);
                g = hue2rgb(p, q, h);
                b = hue2rgb(p, q, h - 1/3);
            }
            return rgbToHex(Math.round(r * 255), Math.round(g * 255), Math.round(b * 255));
        }

        // Theme management
        function toggleTheme() {
            const isLight = document.documentElement.classList.toggle('light-mode');
            localStorage.setItem('theme', isLight ? 'light' : 'dark');
            updateThemeIcon();
            
            // Regenerate palette for new mode if seed exists
            const picker = document.getElementById('theme-seed-color');
            if (picker && picker.value) {
                applySeedColor(picker.value);
            }
            
            syncSettings();
            showSnackbar(\`Switched to \${isLight ? 'Light' : 'Dark'} mode\`);
        }

        function updateThemeIcon() {
            const icon = document.getElementById('theme-icon');
            const isLight = document.documentElement.classList.contains('light-mode');
            if (icon) icon.textContent = isLight ? 'dark_mode' : 'light_mode';
        }

        function initTheme() {
            const savedTheme = localStorage.getItem('theme');
            const systemPrefersLight = window.matchMedia('(prefers-color-scheme: light)').matches;
            
            if (savedTheme === 'light' || (!savedTheme && systemPrefersLight)) {
                document.documentElement.classList.add('light-mode');
            }
            updateThemeIcon();
        }

        // Privacy toggle functionality
        function togglePrivacy() {
            const toggle = document.getElementById('privacy-switch');
            const body = document.body;
            const isPrivate = toggle.classList.toggle('active');
            if (isPrivate) {
                body.classList.add('privacy-mode');
                localStorage.setItem('privacy_mode', 'true');
            } else {
                body.classList.remove('privacy-mode');
                localStorage.setItem('privacy_mode', 'false');
            }
            updateProfileDisplay();
            syncSettings();
        }
        
        function initPrivacyMode() {
            const savedMode = localStorage.getItem('privacy_mode');
            if (savedMode === 'true') {
                const toggle = document.getElementById('privacy-switch');
                if (toggle) toggle.classList.add('active');
                document.body.classList.add('privacy-mode');
            }
            updateProfileDisplay();
        }

        function dismissMacAdvisory() {
            document.getElementById('mac-advisory').style.display = 'none';
            localStorage.setItem('mac_advisory_dismissed', 'true');
        }

        function initMacAdvisory() {
            if (localStorage.getItem('mac_advisory_dismissed') === 'true') {
                const el = document.getElementById('mac-advisory');
                if (el) el.style.display = 'none';
            }
        }
        
        async function fetchCertStatus() {
            try {
                const controller = new AbortController();
                const timeoutId = setTimeout(() => controller.abort(), 10000);
                const res = await fetch(API + "/certificate-status", { signal: controller.signal });
                clearTimeout(timeoutId);
                
                if (res.status === 401) throw new Error("401");
                const data = await res.json();
                
                const loadingBox = document.getElementById('cert-loading');
                if (loadingBox) loadingBox.style.display = 'none';

                document.getElementById('cert-type').textContent = data.type || "--";
                document.getElementById('cert-subject').textContent = data.subject || "--";
                document.getElementById('cert-issuer').textContent = data.issuer || "--";
                
                // Make the year slightly bolder
                const expiresEl = document.getElementById('cert-to');
                if (data.expires && data.expires !== "--") {
                    const parts = data.expires.split(' ');
                    if (parts.length > 0) {
                        const lastPart = parts[parts.length - 1];
                        const rest = data.expires.substring(0, data.expires.lastIndexOf(lastPart));
                        expiresEl.innerHTML = rest + '<span style="font-weight: 600;">' + lastPart + '</span>';
                    } else {
                        expiresEl.textContent = data.expires;
                    }
                } else {
                    expiresEl.textContent = "--";
                }
                
                const badge = document.getElementById('cert-status-badge');
                const isTrusted = data.status && data.status.includes("Trusted");
                const isSelfSigned = data.status && data.status.includes("Self-Signed");
                const domain = isTrusted ? data.subject : "";

                if (isTrusted) {
                    badge.className = "chip vpn"; // Use primary-container color
                    badge.innerHTML = '<span class="material-symbols-rounded" style="font-size:16px;">verified</span> Trusted';
                    badge.dataset.tooltip = "✓ Globally Trusted: Valid certificate from Let's Encrypt.";
                } else if (isSelfSigned) {
                    badge.className = "chip admin"; // Use secondary-container color
                    badge.innerHTML = '<span class="material-symbols-rounded" style="font-size:16px;">warning</span> Self-Signed';
                    badge.dataset.tooltip = "⚠ Self-Signed (Local): Devices will show security warnings. deSEC configuration recommended.";
                } else {
                    badge.className = "chip tertiary";
                    badge.textContent = data.status || "Unknown";
                    badge.dataset.tooltip = "Status unknown or certificate missing.";
                }
                
                const failInfo = document.getElementById('ssl-failure-info');
                const trustedInfo = document.getElementById('dns-setup-trusted');
                const untrustedInfo = document.getElementById('dns-setup-untrusted');
                const retryBtn = document.getElementById('ssl-retry-btn');

                if (data.error) {
                    failInfo.style.display = 'block';
                    document.getElementById('ssl-failure-reason').textContent = data.error;
                    if (trustedInfo) trustedInfo.style.display = 'none';
                    if (untrustedInfo) untrustedInfo.style.display = 'block';
                    if (retryBtn) retryBtn.style.display = 'inline-flex';
                    
                    // Handle authentication or rate limit errors
                    if (data.status === "Auth Error") {
                        showSnackbar("SSL Authentication Error: Please check your deSEC credentials.");
                    } else if (data.status === "Rate Limited" || data.status === "Issuance Failed") {
                        showSnackbar("SSL Issue: " + data.error);
                    }
                } else {
                    failInfo.style.display = 'none';
                    if (isTrusted) {
                        if (trustedInfo) trustedInfo.style.display = 'block';
                        if (untrustedInfo) untrustedInfo.style.display = 'none';
                        if (retryBtn) retryBtn.style.display = 'none';
                    } else {
                        if (trustedInfo) trustedInfo.style.display = 'none';
                        if (untrustedInfo) untrustedInfo.style.display = 'block';
                        if (retryBtn) retryBtn.style.display = 'inline-flex';
                    }
                }
            } catch(e) { 
                console.error('Cert status fetch error:', e);
            } finally {
                const loadingBox = document.getElementById('cert-loading');
                if (loadingBox) loadingBox.style.display = 'none';
            }
        }

        async function requestSslCheck() {
            const btn = document.getElementById('ssl-retry-btn');
            btn.disabled = true;
            btn.style.opacity = '0.5';
            try {
                const res = await fetch(API + "/request-ssl-check", { headers: getAuthHeaders() });
                const data = await res.json();
                if (data.success) {
                    alert("SSL Check triggered in background. This may take 2-3 minutes. Refresh the dashboard later.");
                } else {
                    alert("Failed to trigger SSL check: " + (data.error || "Unknown error"));
                }
            } catch (e) {
                alert("Network error while triggering SSL check.");
            }
            setTimeout(() => { btn.disabled = false; btn.style.opacity = '1'; }, 10000);
        }

        async function checkUpdates() {
            showSnackbar("Update check initiated... checking images and sources.");
            try {
                const res = await fetch(API + "/check-updates", { headers: getAuthHeaders() });
                const data = await res.json();
                if (data.success) {
                    showSnackbar("Update check is running in background. Results will appear in logs and banners shortly.");
                    // Refresh source updates after a short delay
                    setTimeout(fetchUpdates, 5000);
                } else {
                    throw new Error(data.error);
                }
            } catch(e) {
                showSnackbar("Failed to initiate update check: " + e.message);
            }
        }

        async function restartStack() {
            if (!confirm("Are you sure you want to restart the entire stack? The dashboard and all services will be unreachable for approximately 30 seconds.")) return;
            
            try {
                const res = await fetch(API + "/restart-stack", {
                    method: 'POST',
                    headers: getAuthHeaders()
                });
                
                const data = await res.json();
                if (data.success) {
                    // Show a persistent overlay or alert
                    document.body.innerHTML = \`
                        <div style="display:flex; flex-direction:column; align-items:center; justify-content:center; height:100vh; background:var(--md-sys-color-surface); color:var(--md-sys-color-on-surface); font-family:sans-serif; text-align:center; padding:24px;">
                            <span class="material-symbols-rounded" style="font-size:64px; color:var(--md-sys-color-primary); margin-bottom:24px;">restart_alt</span>
                            <h1>Restarting Stack...</h1>
                            <p style="margin-top:16px; opacity:0.8;">The management interface is rebooting. This page will automatically refresh when the services are back online.</p>
                            <div style="margin-top:32px; width:48px; height:48px; border:4px solid var(--md-sys-color-surface-container-highest); border-top:4px solid var(--md-sys-color-primary); border-radius:50%; animation: spin 1s linear infinite;"></div>
                            <style>
                                @keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }
                            </style>
                        </div>
                    \`;
                    
                    // Poll for availability
                    let attempts = 0;
                    const checkAvailability = setInterval(async () => {
                        attempts++;
                        try {
                            const ping = await fetch(window.location.href, { mode: 'no-cors' });
                            clearInterval(checkAvailability);
                            window.location.reload();
                        } catch (e) {
                            if (attempts > 60) {
                                clearInterval(checkAvailability);
                                alert("Restart is taking longer than expected. Please refresh the page manually.");
                            }
                        }
                    }, 2000);
                } else {
                    throw new Error(data.error || "Unknown error");
                }
            } catch (e) {
                alert("Failed to initiate restart: " + e.message);
            }
        }
        
        async function fetchSystemHealth() {
            try {
                const res = await fetch(API + "/system-health", { headers: getAuthHeaders() });
                if (res.status === 401) throw new Error("401");
                const data = await res.json();
                
                const cpu = Math.round(data.cpu_percent || 0);
                const ramUsed = Math.round(data.ram_used || 0);
                const ramTotal = Math.round(data.ram_total || 0);
                const ramPct = Math.round((ramUsed / ramTotal) * 100);

                const sysCpu = document.getElementById('sys-cpu');
                if(sysCpu) sysCpu.textContent = cpu + "%";
                const sysCpuFill = document.getElementById('sys-cpu-fill');
                if(sysCpuFill) sysCpuFill.style.width = cpu + "%";
                
                const sysRam = document.getElementById('sys-ram');
                if(sysRam) sysRam.textContent = ramUsed + " MB / " + ramTotal + " MB";
                const sysRamFill = document.getElementById('sys-ram-fill');
                if(sysRamFill) sysRamFill.style.width = ramPct + "%";
                
                const sysProj = document.getElementById('sys-project-size');
                if(sysProj) sysProj.textContent = (data.project_size || 0).toFixed(1) + " MB";
                
                const uptime = data.uptime || 0;
                const d = Math.floor(uptime / 86400);
                const h = Math.floor((uptime % 86400) / 3600);
                const m = Math.floor((uptime % 3600) / 60);
                const sysUp = document.getElementById('sys-uptime');
                if(sysUp) sysUp.textContent = d + "d " + h + "h " + m + "m";

                const driveStatus = document.getElementById('sys-drive-status');
                const drivePct = document.getElementById('sys-drive-pct');
                const driveContainer = document.getElementById('drive-health-container');
                const diskPercent = document.getElementById('sys-disk-percent');
                
                if(driveStatus) driveStatus.textContent = data.drive_status || "Unknown";
                if(drivePct) drivePct.textContent = (data.drive_health_pct || 0) + "% Health";
                if(diskPercent) diskPercent.textContent = (data.disk_percent || 0).toFixed(1) + "% used";

                if (driveStatus) {
                    if (data.drive_status === "Action Required") {
                        driveStatus.style.color = "var(--md-sys-color-error)";
                    } else if (data.drive_status && data.drive_status.includes("Warning")) {
                        driveStatus.style.color = "var(--md-sys-color-warning)";
                    } else {
                        driveStatus.style.color = "var(--md-sys-color-success)";
                    }
                }

                if (driveContainer) {
                    if (data.smart_alerts && data.smart_alerts.length > 0) {
                        driveContainer.dataset.tooltip = "SMART Alerts:\n" + data.smart_alerts.join("\n");
                    } else {
                        driveContainer.dataset.tooltip = "Drive is reporting healthy SMART status.";
                    }
                }

            } catch(e) { console.error("Health fetch error:", e); }
        }

        document.addEventListener('DOMContentLoaded', () => {
            // Load deSEC config if available
            fetch(API + "/status").then(r => r.json()).then(data => {
                if (data.gluetun && data.gluetun.desec_domain) {
                    document.getElementById('desec-domain-input').placeholder = data.gluetun.desec_domain;
                }
            }).catch(() => {});

            // Tooltip Initialization
            const tooltipBox = document.createElement('div');
            tooltipBox.className = 'tooltip-box';
            document.body.appendChild(tooltipBox);
            
            let tooltipTimeout = null;

            document.addEventListener('mouseover', (e) => {
                const target = e.target.closest('[data-tooltip]');
                if (!target) return;

                if (tooltipTimeout) clearTimeout(tooltipTimeout);
                
                tooltipTimeout = setTimeout(() => {
                    tooltipBox.textContent = target.dataset.tooltip;
                    tooltipBox.style.display = 'block';
                    // Trigger reflow
                    tooltipBox.offsetHeight;
                    tooltipBox.classList.add('visible');

                    const rect = target.getBoundingClientRect();
                    const boxRect = tooltipBox.getBoundingClientRect();
                    
                    let top = rect.top - boxRect.height - 12;
                    let left = rect.left + (rect.width / 2) - (boxRect.width / 2);

                    // Edge collision detection (with 12px safety margin)
                    if (top < 12) top = rect.bottom + 12;
                    if (left < 12) left = 12;
                    if (left + boxRect.width > window.innerWidth - 12) {
                        left = window.innerWidth - boxRect.width - 12;
                    }
                    
                    // Final safety: ensure it doesn't go off bottom
                    if (top + boxRect.height > window.innerHeight - 12) {
                        top = window.innerHeight - boxRect.height - 12;
                    }

                    tooltipBox.style.top = top + 'px';
                    tooltipBox.style.left = left + 'px';
                }, 150); 
            });

            document.addEventListener('mouseout', (e) => {
                if (e.target.closest('[data-tooltip]')) {
                    if (tooltipTimeout) clearTimeout(tooltipTimeout);
                    tooltipBox.classList.remove('visible');
                    // Hide after transition
                    setTimeout(() => {
                        if (!tooltipBox.classList.contains('visible')) {
                            tooltipBox.style.display = 'none';
                        }
                    }, 150);
                }
            });

            // Pre-populate Odido API key from deployment
            if (DEFAULT_ODIDO_API_KEY && !sessionStorage.getItem('odido_api_key')) {
                sessionStorage.setItem('odido_api_key', DEFAULT_ODIDO_API_KEY);
                odidoApiKey = DEFAULT_ODIDO_API_KEY;
            }
            // Pre-populate the API key input field so users can see their dashboard API key
            const apiKeyInput = document.getElementById('odido-api-key');
            if (apiKeyInput && odidoApiKey) {
                apiKeyInput.value = odidoApiKey;
            }
            
            // Restore filter and check HTTPS
            const savedFilter = localStorage.getItem('dashboard_filter') || 'all';
            filterCategory(savedFilter);
            if (window.location.protocol === 'https:') {
                const badge = document.getElementById('https-badge');
                if (badge) badge.style.display = 'inline-flex';
            }

            initPrivacyMode();
            initTheme();
            initStaticPresets();
            fetchContainerIds();
            updateAdminUI();
            fetchStatus(); fetchProfiles(); fetchOdidoStatus(); fetchCertStatus(); startLogStream(); fetchUpdates(); fetchMetrics(); loadAllSettings(); fetchSystemHealth();
            setInterval(fetchStatus, 15000);
            setInterval(fetchSystemHealth, 15000);
            setInterval(fetchMetrics, 30000);
            setInterval(fetchUpdates, 300000); // Check for source updates every 5 mins
            setInterval(fetchOdidoStatus, 60000);  // Reduced polling frequency to respect Odido API
            setInterval(fetchContainerIds, 60000);
        });
    </script>
</body>
</html>
EOF
}
    # Export DOCKER_CONFIG globally
    export DOCKER_CONFIG="$DOCKER_AUTH_DIR"
    
        # Non-interactive login via environment variables
        if [ -n "${REG_USER:-}" ] && [ -n "${REG_TOKEN:-}" ]; then
            log_info "Credentials detected in environment: Attempting non-interactive registry login."
            
            # DHI Login
            if echo "$REG_TOKEN" | sudo env DOCKER_CONFIG="$DOCKER_CONFIG" docker login dhi.io -u "$REG_USER" --password-stdin >/dev/null 2>&1; then
                log_info "dhi.io: Authentication successful."
            else
                log_warn "dhi.io: Authentication failed."
            fi
    
            # Docker Hub Login (Optional)
            if [ -n "${HUB_USER:-}" ] && [ -n "${HUB_TOKEN:-}" ]; then
                if echo "$HUB_TOKEN" | sudo env DOCKER_CONFIG="$DOCKER_CONFIG" docker login -u "$HUB_USER" --password-stdin >/dev/null 2>&1; then
                     log_info "Docker Hub: Authentication successful."
                else
                     log_warn "Docker Hub: Authentication failed."
                fi
            else
                log_info "No Docker Hub credentials provided (HUB_USER/HUB_TOKEN). Skipping login (anonymous pull)."
            fi
            return 0
        fi
    
        # If running with AUTO_CONFIRM but no credentials, warn but proceed to prompt 
        echo ""
        echo "--- REGISTRY AUTHENTICATION ---"
        echo "Please provide your credentials for dhi.io and Docker Hub."
        echo ""
    
        while true; do
            read -r -p "Username: " REG_USER
            read -rs -p "Access Token (PAT): " REG_TOKEN
            echo ""
            
            # DHI Login
            if echo "$REG_TOKEN" | sudo env DOCKER_CONFIG="$DOCKER_CONFIG" docker login dhi.io -u "$REG_USER" --password-stdin; then
                log_info "dhi.io: Authentication successful."
                return 0
            else
                log_crit "dhi.io: Authentication failed."
            fi
    
            if ! ask_confirm "Authentication failed. Would you like to retry?"; then return 1; fi
        done
}

setup_assets() {
    log_info "Downloading local assets to ensure dashboard privacy and eliminate third-party dependencies."
    mkdir -p "$ASSETS_DIR"
    
    # Check if assets are already set up
    if [ -f "$ASSETS_DIR/gs.css" ] && [ -f "$ASSETS_DIR/cc.css" ] && [ -f "$ASSETS_DIR/ms.css" ]; then
        log_info "Local assets are present."
        return 0
    fi

    # URLs (Fontlay)
    URL_GS="https://fontlay.com/css2?family=Google+Sans+Flex:wght@400;500;600;700&display=swap"
    URL_CC="https://fontlay.com/css2?family=Cascadia+Code:ital,wght@0,200..700;1,200..700&display=swap"
    URL_MS="https://fontlay.com/css2?family=Material+Symbols+Rounded:opsz,wght,FILL,GRAD@20..48,100..700,0..1,-50..200&display=swap"

    download_css() {
        local dest="$1"
        local url="$2"
        local varname="$3"
        if ! curl -fsSL -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" "$url" -o "$dest"; then
            log_warn "Asset source failed: $url"
        fi
        printf -v "$varname" '%s' "$url"
    }

    css_origin() {
        echo "$1" | sed -E 's#(https?://[^/]+).*#\1#'
    }

    download_css "$ASSETS_DIR/gs.css" "$URL_GS" GS_CSS_URL
    download_css "$ASSETS_DIR/cc.css" "$URL_CC" CC_CSS_URL
    download_css "$ASSETS_DIR/ms.css" "$URL_MS" MS_CSS_URL

    # Material Color Utilities (Local for privacy)
    log_info "Downloading Material Color Utilities..."
    if ! curl -fsSL -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" "https://cdn.jsdelivr.net/npm/@material/material-color-utilities@0.3.0/dist/material-color-utilities.min.js" -o "$ASSETS_DIR/mcu.js"; then
        log_warn "Failed to download Material Color Utilities. Using fallback logic."
    fi

    # Parse and download woff2 files for each CSS file
    cd "$ASSETS_DIR"
    declare -A CSS_ORIGINS
    CSS_ORIGINS[gs.css]="$(css_origin "$GS_CSS_URL")"
    CSS_ORIGINS[cc.css]="$(css_origin "$CC_CSS_URL")"
    CSS_ORIGINS[ms.css]="$(css_origin "$MS_CSS_URL")"
    for css_file in gs.css cc.css ms.css; do
        if [ ! -s "$css_file" ]; then
            log_warn "Skipping $css_file (missing or empty)."
            continue
        fi
        css_origin="${CSS_ORIGINS[$css_file]}"
        # Extract URLs from url(...) - handle optional quotes
        grep -o "url([^)]*)" "$css_file" | sed 's/url(//;s/)//' | tr -d "'\"" | sort | uniq | while read -r url; do
            if [ -z "$url" ]; then continue; fi
            filename=$(basename "$url")
            # Strip everything after ?
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
                # log_info "Downloading font: $clean_name"
                if ! curl -sL "$fetch_url" -o "$clean_name"; then
                    log_warn "Failed to download asset: $clean_name"
                    continue
                fi
            fi
            
            # Escape URL for sed: escape / and & and |
            escaped_url=$(echo "$url" | sed 's/[\/&|]/\\&/g')
            # Replace the URL in the CSS file
            sed -i "s|url(['\"]\{0,1\}${escaped_url}['\"]\{0,1\})|url($clean_name)|g" "$css_file"
        done || true
    done
    cd - >/dev/null
    
    log_info "Assets setup complete (Separate files retained for reliability)."

    # Create local SVG icon for CasaOS/ZimaOS dashboard
    log_info "Creating local SVG icon for the dashboard..."
    cat > "$ASSETS_DIR/privacy-hub.svg" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" height="128" viewBox="0 -960 960 960" width="128" fill="#D0BCFF">
    <path d="M480-80q-139-35-229.5-159.5S160-516 160-666v-134l320-120 320 120v134q0 151-90.5 275.5T480-80Zm0-84q104-33 172-132t68-210v-105l-240-90-240 90v105q0 111 68 210t172 132Zm0-316Z"/>
</svg>
EOF
}

check_docker_rate_limit() {
    log_info "Checking if Docker Hub is going to throttle you..."
    # Export DOCKER_CONFIG globally
    export DOCKER_CONFIG="$DOCKER_AUTH_DIR"
    
    if ! output=$(sudo env DOCKER_CONFIG="$DOCKER_CONFIG" docker pull hello-world 2>&1); then
        if echo "$output" | grep -iaE "toomanyrequests|rate.*limit|pull.*limit|reached.*limit" >/dev/null; then
            log_crit "Docker Hub Rate Limit Reached! They want you to log in."
            # We already tried to auth at start, but maybe it failed or they skipped?
            # Or maybe they want to try a different account now.
            if ! authenticate_registries; then
                exit 1
            fi
        else
            log_warn "Docker pull check failed. We'll proceed, but don't be surprised if image pulls fail later."
        fi
    else
        log_info "Docker Hub connection is fine."
    fi
}

clean_environment() {
    echo "=========================================================="
    echo "🛡️  ENVIRONMENT VALIDATION & CLEANUP"
    echo "=========================================================="
    
    if [ "$CLEAN_ONLY" = false ]; then
        check_docker_rate_limit
    fi

    if [ "$FORCE_CLEAN" = true ]; then
        log_warn "FORCE CLEAN ENABLED (-c): All existing data, configurations, and volumes will be permanently removed."
    fi

    TARGET_CONTAINERS="gluetun adguard dashboard portainer watchtower wg-easy hub-api odido-booster redlib wikiless wikiless_redis invidious invidious-db companion memos rimgo breezewiki anonymousoverflow scribe vert vertd"
    
    FOUND_CONTAINERS=""
    for c in $TARGET_CONTAINERS; do
        if $DOCKER_CMD ps -a --format '{{.Names}}' | grep -q "^${c}$"; then
            FOUND_CONTAINERS="$FOUND_CONTAINERS $c"
        fi
    done

    if [ -n "$FOUND_CONTAINERS" ]; then
        if ask_confirm "Existing containers detected. Would you like to remove them to ensure a clean deployment?"; then
            $DOCKER_CMD rm -f $FOUND_CONTAINERS 2>/dev/null || true
            log_info "Previous containers have been removed."
        fi
    fi

    CONFLICT_NETS=$($DOCKER_CMD network ls --format '{{.Name}}' | grep -E '(privacy-hub_frontnet|privacyhub_frontnet|privacy-hub_default|privacyhub_default)' || true)
    if [ -n "$CONFLICT_NETS" ]; then
        if ask_confirm "Conflicting networks detected. Should they be cleared?"; then
            for net in $CONFLICT_NETS; do
                log_info "  Removing network conflict: $net"
                safe_remove_network "$net"
            done
        fi
    fi

    if [ -d "$BASE_DIR" ] || $DOCKER_CMD volume ls -q | grep -q "portainer"; then
        if ask_confirm "Wipe ALL application data? This action is irreversible."; then
            log_info "Clearing BASE_DIR data..."
            if [ -d "$BASE_DIR" ]; then
                sudo rm -f "$BASE_DIR/.secrets" 2>/dev/null || true
                sudo rm -f "$BASE_DIR/.current_public_ip" 2>/dev/null || true
                sudo rm -f "$BASE_DIR/.active_profile_name" 2>/dev/null || true
                sudo rm -rf "$BASE_DIR/config" 2>/dev/null || true
                sudo rm -rf "$BASE_DIR/env" 2>/dev/null || true
                sudo rm -rf "$BASE_DIR/sources" 2>/dev/null || true
                sudo rm -rf "$BASE_DIR/wg-profiles" 2>/dev/null || true
                sudo rm -f "$BASE_DIR/active-wg.conf" 2>/dev/null || true
                sudo rm -f "$BASE_DIR/wg-ip-monitor.sh" 2>/dev/null || true
                sudo rm -f "$BASE_DIR/wg-control.sh" 2>/dev/null || true
                sudo rm -f "$BASE_DIR/wg-api.sh" 2>/dev/null || true
                sudo rm -f "$BASE_DIR/deployment.log" 2>/dev/null || true
                sudo rm -f "$BASE_DIR/wg-ip-monitor.log" 2>/dev/null || true
generate_dashboard
                sudo rm -f "$BASE_DIR/docker-compose.yml" 2>/dev/null || true
                sudo rm -f "$BASE_DIR/dashboard.html" 2>/dev/null || true
                sudo rm -f "$BASE_DIR/gluetun.env" 2>/dev/null || true
                sudo rm -rf "$BASE_DIR" 2>/dev/null || true
            fi
            # Remove volumes - try both unprefixed and prefixed names (docker compose uses project prefix)
            for vol in portainer-data adguard-work redis-data postgresdata wg-config companioncache odido-data; do
                $DOCKER_CMD volume rm -f "$vol" 2>/dev/null || true
                $DOCKER_CMD volume rm -f "${APP_NAME}_${vol}" 2>/dev/null || true
            done
            log_info "Application data and volumes have been cleared."
        fi
    fi
    
    if [ "$FORCE_CLEAN" = true ]; then
        log_warn "REVERT: Rolling back deployment. This process will undo changes, restore system defaults, and clean up all created files..."
        echo ""
        
        # ============================================================
        # PHASE 1: Stop all containers to release locks
        # ============================================================
        log_info "Phase 1: Terminating running containers..."
        for c in $TARGET_CONTAINERS; do
            if $DOCKER_CMD ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${c}$"; then
                log_info "  Stopping: $c"
                $DOCKER_CMD stop "$c" 2>/dev/null || true
            fi
        done
        sleep 3
        
        # ============================================================
        # PHASE 2: Remove all containers
        # ============================================================
        log_info "Phase 2: Removing containers..."
        REMOVED_CONTAINERS=""
        for c in $TARGET_CONTAINERS; do
            if $DOCKER_CMD ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${c}$"; then
                log_info "  Removing: $c"
                $DOCKER_CMD rm -f "$c" 2>/dev/null || true
                REMOVED_CONTAINERS="${REMOVED_CONTAINERS}$c "
            fi
        done
        
        # ============================================================
        # PHASE 3: Remove ALL volumes (list everything, match patterns)
        # ============================================================
        log_info "Phase 3: Removing volumes..."
        REMOVED_VOLUMES=""
        ALL_VOLUMES=$($DOCKER_CMD volume ls -q 2>/dev/null || echo "")
        for vol in $ALL_VOLUMES; do
            case "$vol" in
                # Match exact names
                portainer-data|adguard-work|redis-data|postgresdata|wg-config|companioncache|odido-data)
                    log_info "  Removing volume: $vol"
                    $DOCKER_CMD volume rm -f "$vol" 2>/dev/null || true
                    REMOVED_VOLUMES="${REMOVED_VOLUMES}$vol "
                    ;;
                # Match prefixed names (docker compose project prefix)
                privacy-hub_*|privacyhub_*)
                    log_info "  Removing volume: $vol"
                    $DOCKER_CMD volume rm -f "$vol" 2>/dev/null || true
                    REMOVED_VOLUMES="${REMOVED_VOLUMES}$vol "
                    ;;
                # Match any volume containing our identifiers
                *portainer*|*adguard*|*redis*|*postgres*|*wg-config*|*companion*|*odido*)
                    log_info "  Removing volume: $vol"
                    $DOCKER_CMD volume rm -f "$vol" 2>/dev/null || true
                    REMOVED_VOLUMES="${REMOVED_VOLUMES}$vol "
                    ;;
            esac
        done
        
        # ============================================================
        # PHASE 4: Remove ALL networks created by this deployment
        # ============================================================
        log_info "Phase 4: Removing networks..."
        REMOVED_NETWORKS=""
        ALL_NETWORKS=$($DOCKER_CMD network ls --format '{{.Name}}' 2>/dev/null || echo "")
        for net in $ALL_NETWORKS; do
            case "$net" in
                # Skip default Docker networks
                bridge|host|none) continue ;;
                # Match our networks
                privacy-hub_*|privacyhub_*|*frontnet*)
                    log_info "  Removing network: $net"
                    safe_remove_network "$net"
                    REMOVED_NETWORKS="${REMOVED_NETWORKS}$net "
                    ;;
            esac
        done
        
        # ============================================================
        # PHASE 5: Remove ALL images built/pulled by this deployment
        # ============================================================
        log_info "Phase 5: Removing images..."
        REMOVED_IMAGES=""
        # Remove images by known names
        KNOWN_IMAGES="qmcgaw/gluetun adguard/adguardhome nginx:alpine portainer/portainer-ce containrrr/watchtower python:3.11-alpine ghcr.io/wg-easy/wg-easy redis:7.2 quay.io/invidious/invidious quay.io/invidious/invidious-companion postgres:14-alpine neosmemo/memos:stable codeberg.org/rimgo/rimgo quay.io/pussthecatorg/breezewiki ghcr.io/httpjamesm/anonymousoverflow:release klutchell/unbound ghcr.io/vert-sh/vertd ghcr.io/vert-sh/vert httpd:alpine alpine:latest node:20-alpine 84codes/crystal:1.8.1-alpine 84codes/crystal:1.16.3-alpine oven/bun:1 neilpang/acme.sh"
        for img in $KNOWN_IMAGES; do
            if $DOCKER_CMD images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -q "$img"; then
                log_info "  Removing: $img"
                $DOCKER_CMD rmi -f "$img" 2>/dev/null || true
                REMOVED_IMAGES="${REMOVED_IMAGES}$img "
            fi
        done
        # Remove locally built images
        ALL_IMAGES=$($DOCKER_CMD images --format '{{.Repository}}:{{.Tag}} {{.ID}}' 2>/dev/null || echo "")
        echo "$ALL_IMAGES" | while read -r img_info; do
            img_name=$(echo "$img_info" | awk '{print $1}')
            img_id=$(echo "$img_info" | awk '{print $2}')
            case "$img_name" in
                *privacy-hub*|*privacyhub*|*odido*|*redlib*|*wikiless*|*scribe*|*vert*|*invidious*|*sources_*)
                    log_info "  Removing local image: $img_name"
                    $DOCKER_CMD rmi -f "$img_id" 2>/dev/null || true
                    # Note: We can't easily append to REMOVED_IMAGES inside a subshell/pipe loop
                    # but the main ones are captured above.
                    ;;
                "<none>:<none>")
                    # Remove dangling images
                    $DOCKER_CMD rmi -f "$img_id" 2>/dev/null || true
                    ;;
            esac
        done
        
        # ============================================================
        # PHASE 6: Remove ALL data directories and files
        # ============================================================
        log_info "Phase 6: Removing data directories..."
        
        # Main data directory
        if [ -d "$BASE_DIR" ]; then
            log_info "  Removing: $BASE_DIR"
            sudo rm -rf "$BASE_DIR"
        fi
        
        # Alternative locations that might have been created
        if [ -d "/DATA/AppData/privacy-hub" ]; then
            log_info "  Removing directory: /DATA/AppData/privacy-hub"
            sudo rm -rf "/DATA/AppData/privacy-hub"
        fi
        
        # ============================================================
        # PHASE 7: Remove cron jobs added by this script
        # ============================================================
        log_info "Phase 7: Clearing scheduled tasks..."
        EXISTING_CRON=$(crontab -l 2>/dev/null || true)
        REMOVED_CRONS=""
        if echo "$EXISTING_CRON" | grep -q "wg-ip-monitor"; then REMOVED_CRONS="${REMOVED_CRONS}wg-ip-monitor "; fi
        if echo "$EXISTING_CRON" | grep -q "cert-monitor"; then REMOVED_CRONS="${REMOVED_CRONS}cert-monitor "; fi
        
        if [ -n "$REMOVED_CRONS" ]; then
            log_info "  Clearing cron entries: $REMOVED_CRONS"
            echo "$EXISTING_CRON" | grep -v "wg-ip-monitor" | grep -v "cert-monitor" | grep -v "privacy-hub" | crontab - 2>/dev/null || true
        fi
        
        # ============================================================
        # PHASE 8: Docker system cleanup
        # ============================================================
        log_info "Phase 8: Docker system cleanup..."
        # $DOCKER_CMD volume prune -f 2>/dev/null || true
        # $DOCKER_CMD network prune -f 2>/dev/null || true
        $DOCKER_CMD image prune -af 2>/dev/null || true
        $DOCKER_CMD builder prune -af 2>/dev/null || true
        $DOCKER_CMD system prune -f 2>/dev/null || true
        
       
        # ============================================================
        # PHASE 9: Reset stack-specific iptables rules
        # ============================================================
        log_info "Phase 9: Cleaning up specific networking rules (existing host rules will be preserved)..."
        # Only remove rules if they exist to avoid affecting other system configurations
        if sudo iptables -t nat -C POSTROUTING -s 10.8.0.0/24 -j MASQUERADE 2>/dev/null; then
            sudo iptables -t nat -D POSTROUTING -s 10.8.0.0/24 -j MASQUERADE 2>/dev/null || true
        fi
        if sudo iptables -C FORWARD -i wg0 -j ACCEPT 2>/dev/null; then
            sudo iptables -D FORWARD -i wg0 -j ACCEPT 2>/dev/null || true
        fi
        if sudo iptables -C FORWARD -o wg0 -j ACCEPT 2>/dev/null; then
            sudo iptables -D FORWARD -o wg0 -j ACCEPT 2>/dev/null || true
        fi
        
        echo ""
        log_info "============================================================"
        log_info "RESTORE COMPLETE: ENVIRONMENT HAS BEEN RESET"
        log_info "============================================================"
        log_info "The host system has been returned to its original state."
        log_info "============================================================"
    fi
}

# Clean-only mode: reset environment and exit early
if [ "$CLEAN_ONLY" = true ]; then
    clean_environment
    log_info "Clean-only mode enabled. Deployment skipped."
    exit 0
fi

# Authenticate to registries (DHI & Docker Hub)
authenticate_registries

# Run cleanup
clean_environment

# Ensure authentication works by pulling critical utility images now
log_info "Pre-pulling ALL deployment images to avoid rate limits..."
# Explicitly pull images used by 'docker run' commands or as base images later in the script
# We only pull core infrastructure and base images. App images built from source are skipped.
CRITICAL_IMAGES="qmcgaw/gluetun adguard/adguardhome nginx:alpine portainer/portainer-ce containrrr/watchtower python:3.11-alpine ghcr.io/wg-easy/wg-easy redis:7.2 quay.io/invidious/invidious-companion postgres:14-alpine neosmemo/memos:stable codeberg.org/rimgo/rimgo ghcr.io/httpjamesm/anonymousoverflow:release klutchell/unbound ghcr.io/vert-sh/vertd ghcr.io/vert-sh/vert alpine:latest node:20-alpine 84codes/crystal:1.8.1-alpine 84codes/crystal:1.16.3-alpine oven/bun:1 neilpang/acme.sh"

for img in $CRITICAL_IMAGES; do
    MAX_RETRIES=3
    count=0
    success=false
    while [ $count -lt $MAX_RETRIES ]; do
        if $DOCKER_CMD pull "$img"; then
            success=true
            break
        fi
        count=$((count + 1))
        log_warn "Failed to pull $img. Retrying ($count/$MAX_RETRIES)..."
        sleep 2
    done
    
    if [ "$success" = false ]; then
        log_crit "Failed to pull critical image $img after $MAX_RETRIES attempts. Aborting."
        exit 1
    fi
done

mkdir -p "$BASE_DIR" "$SRC_DIR" "$ENV_DIR" "$CONFIG_DIR/unbound" "$AGH_CONF_DIR" "$NGINX_CONF_DIR" "$WG_PROFILES_DIR"
mkdir -p "$DATA_DIR/postgres" "$DATA_DIR/redis" "$DATA_DIR/wireguard" "$DATA_DIR/adguard-work" "$DATA_DIR/portainer" "$DATA_DIR/odido" "$DATA_DIR/companion"

# setup_assets (Moved to hub-api container for privacy)

# Initialize log files and data files
touch "$HISTORY_LOG" "$ACTIVE_WG_CONF" "$BASE_DIR/.data_usage" "$BASE_DIR/.wge_data_usage"
if [ ! -f "$ACTIVE_PROFILE_NAME_FILE" ]; then echo "Initial-Setup" > "$ACTIVE_PROFILE_NAME_FILE"; fi
chmod 666 "$ACTIVE_PROFILE_NAME_FILE" "$HISTORY_LOG" "$BASE_DIR/.data_usage" "$BASE_DIR/.wge_data_usage"

# --- SECTION 3: DYNAMIC SUBNET ALLOCATION ---
# Automatically identify and assign a free bridge subnet to prevent network conflicts.
log_info "Allocating private virtual subnet for container isolation."

FOUND_SUBNET=""
FOUND_OCTET=""

for i in {20..30}; do
    TEST_SUBNET="172.$i.0.0/16"
    TEST_NET_NAME="probe_net_$i"
    if $DOCKER_CMD network create --subnet="$TEST_SUBNET" "$TEST_NET_NAME" >/dev/null 2>&1; then
        $DOCKER_CMD network rm "$TEST_NET_NAME" >/dev/null 2>&1
        FOUND_SUBNET="$TEST_SUBNET"
        FOUND_OCTET="$i"
        break
    fi
done

if [ -z "$FOUND_SUBNET" ]; then
    log_crit "Fatal: No available subnets identified. Please verify host network configuration."
    exit 1
fi

DOCKER_SUBNET="$FOUND_SUBNET"
log_info "Assigned Virtual Subnet: $DOCKER_SUBNET"

# --- SECTION 4: NETWORK TOPOLOGY ANALYSIS ---
# Detect primary LAN interface and public IP for VPN endpoint configuration.
log_info "Analyzing network topology and interface configuration..."

is_private_ipv4() {
    local ip=$1
    [[ $ip =~ ^10\. ]] || [[ $ip =~ ^192\.168\. ]] || [[ $ip =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]]
}

sanitize_iface_ip() {
    local iface=$1
    ip -o -4 addr show dev "$iface" scope global up 2>/dev/null \
        | awk '{print $4}' \
        | cut -d/ -f1 \
        | grep -Ev '^(127\.|169\.254\.)' \
        | head -n1
}

detect_route_iface_ip() {
    local iface
    iface=$(ip route show default 2>/dev/null | awk 'NR==1 {print $5}')
    if [ -n "$iface" ] && [[ ! $iface =~ ^(docker0|br-[0-9a-f]{12}|veth|tailscale0|wg.*)$ ]]; then
        sanitize_iface_ip "$iface"
    fi
}

detect_lan_ip() {
    ip -o -4 addr show scope global up 2>/dev/null \
        | awk '$2 !~ /^(docker0|br-[0-9a-f]{12}|veth|lo|tailscale0|wg.*)$/ {print $4}' \
        | cut -d/ -f1 \
        | grep -Ev '^(127\.|169\.254\.)' \
        | head -n1
}

fallback_hostname_ip() {
    hostname -I 2>/dev/null | awk '{print $1}' | grep -Ev '^(127\.|169\.254\.)' | head -n1
}

LAN_IP=${LAN_IP_OVERRIDE:-$(detect_route_iface_ip || true)}
DETECTION_HINT="default route"
if [ -n "${LAN_IP_OVERRIDE:-}" ]; then
    DETECTION_HINT="manual override"
fi

if [ -z "$LAN_IP" ] || ! is_private_ipv4 "$LAN_IP"; then
    LAN_IP=$(detect_lan_ip || true)
    DETECTION_HINT="primary interface"
fi

if [ -z "$LAN_IP" ] || ! is_private_ipv4 "$LAN_IP"; then
    LAN_IP=$(fallback_hostname_ip || true)
    DETECTION_HINT="hostname -I"
fi

if [ -z "$LAN_IP" ] || ! is_private_ipv4 "$LAN_IP"; then
    LAN_IP="192.168.0.100"
    DETECTION_HINT="static fallback"
    log_warn "Automatic LAN IP detection failed; defaulting to $LAN_IP. Set LAN_IP_OVERRIDE if necessary."
else
    log_info "Detected LAN IP ($DETECTION_HINT): $LAN_IP"
fi

PUBLIC_IP=$(curl -s --max-time 5 https://api.ipify.org || curl -s --max-time 5 https://ip-api.com/line?fields=query || echo "$LAN_IP")
echo "$PUBLIC_IP" > "$CURRENT_IP_FILE"

# --- SECTION 5: AUTHENTICATION & CREDENTIAL MANAGEMENT ---
# Initialize or retrieve system secrets and administrative passwords.
if [ ! -f "$BASE_DIR/.secrets" ]; then
    echo "========================================"
    echo " CREDENTIAL CONFIGURATION"
    echo "========================================"
    
    if [ "$AUTO_PASSWORD" = true ]; then
        log_info "Automated password generation initialized."
        VPN_PASS_RAW=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 24)
        AGH_PASS_RAW=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 24)
        ADMIN_PASS_RAW=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 24)
        log_info "Credentials generated and will be displayed upon completion."
        echo ""
    else
        echo -n "1. Enter password for VPN Web UI: "
        read -rs VPN_PASS_RAW
        echo ""
        echo -n "2. Enter password for AdGuard Home: "
        read -rs AGH_PASS_RAW
        echo ""
        echo -n "3. Enter administrative password (for Portainer/Services): "
        read -rs ADMIN_PASS_RAW
        echo ""
    fi
    
    if [ "$AUTO_CONFIRM" = true ]; then
        log_info "Auto-confirm enabled: Skipping interactive deSEC/GitHub/Odido setup (preserving environment variables)."
        DESEC_DOMAIN="${DESEC_DOMAIN:-}"
        DESEC_TOKEN="${DESEC_TOKEN:-}"
        SCRIBE_GH_USER="${SCRIBE_GH_USER:-}"
        SCRIBE_GH_TOKEN="${SCRIBE_GH_TOKEN:-}"
        ODIDO_TOKEN="${ODIDO_TOKEN:-}"
        ODIDO_USER_ID="${ODIDO_USER_ID:-}"
    else
        echo "--- deSEC Domain & Certificate Setup ---"
        echo "   Steps:"
        echo "   1. Sign up at https://desec.io/"
        echo "   2. Create a domain (e.g., myhome.dedyn.io)"
        echo "   3. Create a NEW Token in Token Management (if you lost the old one)"
        echo ""
        echo -n "3. deSEC Domain (e.g., myhome.dedyn.io, or Enter to skip): "
        read -r DESEC_DOMAIN
        if [ -n "$DESEC_DOMAIN" ]; then
            echo -n "4. deSEC API Token: "
            read -rs DESEC_TOKEN
            echo ""
        else
            DESEC_TOKEN=""
            echo "   Skipping deSEC (will use self-signed certificates)"
        fi
        echo ""
        
        echo "--- Scribe (Medium Frontend) GitHub Integration ---"
        echo "   Scribe proxies GitHub gists and needs a token to avoid rate limits (60/hr vs 5000/hr)."
        echo "   1. Go to https://github.com/settings/tokens"
        echo "   2. Generate a new 'Classic' token"
        echo "   3. Scopes: Select 'gist' only"
        if [ -n "$DESEC_DOMAIN" ]; then
            echo -n "5. GitHub Username: "
            read -r SCRIBE_GH_USER
            echo -n "6. GitHub Personal Access Token: "
            read -rs SCRIBE_GH_TOKEN
            echo ""
        else
            echo -n "4. GitHub Username: "
            read -r SCRIBE_GH_USER
            echo -n "5. GitHub Personal Access Token: "
            read -rs SCRIBE_GH_TOKEN
            echo ""
        fi
        
        echo ""
        echo "--- Odido Bundle Booster (Optional) ---"
        echo "   Obtain the OAuth Token using https://github.com/GuusBackup/Odido.Authenticator"
        echo "   (works on any platform with .NET, no Apple device needed)"
        echo ""
        echo "   Steps:"
        echo "   1. Clone and run: git clone --recursive https://github.com/GuusBackup/Odido.Authenticator.git"
        echo "   2. Run: dotnet run --project Odido.Authenticator"
        echo "   3. Follow the login flow and get the OAuth Token"
        echo "   4. Enter the OAuth Token below - the script will fetch your User ID automatically"
        echo ""
        echo -n "Odido Access Token (OAuth Token from Authenticator, or Enter to skip): "
        read -rs ODIDO_TOKEN
        echo ""
        if [ -n "$ODIDO_TOKEN" ]; then
            log_info "Fetching Odido User ID automatically..."
            # Use curl with -L to follow redirects and capture the effective URL
            # Note: curl may fail on network issues, so we use || true to prevent script exit
            ODIDO_REDIRECT_URL=$(curl -sL -o /dev/null -w '%{url_effective}' \
                -H "Authorization: Bearer $ODIDO_TOKEN" \
                -H "User-Agent: T-Mobile 5.3.28 (Android 10; 10)" \
                "https://capi.odido.nl/account/current" 2>/dev/null || true)
            
            # Extract User ID from URL path - it's a 12-character hex string after capi.odido.nl/
            # Format: https://capi.odido.nl/{12-char-hex-userid}/account/...
            # Note: grep may not find a match, so we use || true to prevent pipeline failure with set -euo pipefail
            ODIDO_USER_ID=$(echo "$ODIDO_REDIRECT_URL" | grep -oiE 'capi\.odido\.nl/[0-9a-f]{12}' | sed 's|capi\.odido\.nl/||I' | head -1 || true)
            
            # Fallback: try to extract first path segment if hex pattern doesn't match
            if [ -z "$ODIDO_USER_ID" ]; then
                ODIDO_USER_ID=$(echo "$ODIDO_REDIRECT_URL" | sed -n 's|https://capi.odido.nl/\([^/]*\)/.*|\1|p')
            fi
            
            if [ -n "$ODIDO_USER_ID" ] && [ "$ODIDO_USER_ID" != "account" ]; then
                log_info "Successfully retrieved Odido User ID: $ODIDO_USER_ID"
            else
                log_warn "Could not automatically retrieve User ID from Odido API"
                log_warn "The API may be temporarily unavailable or the token may be invalid"
                echo -n "   Enter Odido User ID manually (or Enter to skip): "
                read -r ODIDO_USER_ID
                if [ -z "$ODIDO_USER_ID" ]; then
                    log_warn "No User ID provided, skipping Odido integration"
                    ODIDO_TOKEN=""
                fi
            fi
        else
            ODIDO_USER_ID=""
            echo "   Skipping Odido API integration (manual mode only)"
        fi
    fi
    
    log_info "Generating Secrets..."
    ODIDO_API_KEY=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32)
    $DOCKER_CMD pull -q ghcr.io/wg-easy/wg-easy:latest > /dev/null || log_warn "Failed to pull wg-easy image, attempting to use local if available."
    
    # Safely generate WG hash
    HASH_OUTPUT=$($DOCKER_CMD run --rm ghcr.io/wg-easy/wg-easy wgpw "$VPN_PASS_RAW" 2>&1 || echo "FAILED")
    if [[ "$HASH_OUTPUT" == "FAILED" ]]; then
        log_crit "Failed to generate WireGuard password hash. Check Docker status."
        exit 1
    fi
    WG_HASH_CLEAN=$(echo "$HASH_OUTPUT" | grep -oP "(?<=PASSWORD_HASH=')[^']+")
    WG_HASH_ESCAPED="${WG_HASH_CLEAN//\$/\$\$}"

    AGH_USER="adguard"
    # Safely generate AGH hash
    AGH_PASS_HASH=$($DOCKER_CMD run --rm alpine:latest sh -c 'apk add --no-cache apache2-utils >/dev/null 2>&1 && htpasswd -B -n -b "$1" "$2"' -- "$AGH_USER" "$AGH_PASS_RAW" 2>&1 | cut -d ":" -f 2 || echo "FAILED")
    if [[ "$AGH_PASS_HASH" == "FAILED" ]]; then
        log_crit "Failed to generate AdGuard password hash. Check Docker status."
        exit 1
    fi

    # Safely generate Portainer hash (bcrypt)
    PORTAINER_PASS_HASH=$($DOCKER_CMD run --rm alpine:latest sh -c 'apk add --no-cache apache2-utils >/dev/null 2>&1 && htpasswd -B -n -b "admin" "$1"' -- "$ADMIN_PASS_RAW" 2>&1 | cut -d ":" -f 2 || echo "FAILED")
    if [[ "$PORTAINER_PASS_HASH" == "FAILED" ]]; then
        log_crit "Failed to generate Portainer password hash. Check Docker status."
        exit 1
    fi
    
    cat > "$BASE_DIR/.secrets" <<EOF
VPN_PASS_RAW=$VPN_PASS_RAW
AGH_PASS_RAW=$AGH_PASS_RAW
ADMIN_PASS_RAW=$ADMIN_PASS_RAW
WG_HASH_CLEAN='$WG_HASH_CLEAN'
AGH_PASS_HASH='$AGH_PASS_HASH'
PORTAINER_PASS_HASH='$PORTAINER_PASS_HASH'
DESEC_DOMAIN=$DESEC_DOMAIN
DESEC_TOKEN=$DESEC_TOKEN
SCRIBE_GH_USER=$SCRIBE_GH_USER
SCRIBE_GH_TOKEN=$SCRIBE_GH_TOKEN
ODIDO_USER_ID=$ODIDO_USER_ID
ODIDO_TOKEN=$ODIDO_TOKEN
ODIDO_API_KEY=$ODIDO_API_KEY
EOF
else
    source "$BASE_DIR/.secrets"
    if [ -z "${ADMIN_PASS_RAW:-}" ]; then
        ADMIN_PASS_RAW=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 24)
        echo "ADMIN_PASS_RAW=$ADMIN_PASS_RAW" >> "$BASE_DIR/.secrets"
    fi
    # Generate Portainer hash if missing from existing .secrets
    if [ -z "${PORTAINER_PASS_HASH:-}" ]; then
        log_info "Generating missing Portainer hash..."
        PORTAINER_PASS_HASH=$($DOCKER_CMD run --rm alpine:latest sh -c 'apk add --no-cache apache2-utils >/dev/null 2>&1 && htpasswd -B -n -b "admin" "$1"' -- "$ADMIN_PASS_RAW" 2>&1 | cut -d ":" -f 2 || echo "FAILED")
        echo "PORTAINER_PASS_HASH='$PORTAINER_PASS_HASH'" >> "$BASE_DIR/.secrets"
    fi
    if [ -z "${ODIDO_API_KEY:-}" ]; then
        ODIDO_API_KEY=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32)
        echo "ODIDO_API_KEY=$ODIDO_API_KEY" >> "$BASE_DIR/.secrets"
    fi
    # If using an old .secrets file that has WG_HASH_ESCAPED but not WG_HASH_CLEAN
    if [ -z "${WG_HASH_CLEAN:-}" ] && [ -n "${WG_HASH_ESCAPED:-}" ]; then
        WG_HASH_CLEAN="${WG_HASH_ESCAPED//\$\$/\$}"
    fi
    AGH_USER="adguard"
fi

echo ""
echo "=========================================================="
echo " PROTON WIREGUARD CONFIGURATION"
echo "=========================================================="

# WireGuard Configuration Validation
validate_wg_config() {
    if [ ! -s "$ACTIVE_WG_CONF" ]; then return 1; fi
    if ! grep -q "PrivateKey" "$ACTIVE_WG_CONF"; then
        return 1
    fi
    local PK_VAL
    PK_VAL=$(grep "PrivateKey" "$ACTIVE_WG_CONF" | cut -d'=' -f2 | tr -d '[:space:]')
    if [ -z "$PK_VAL" ]; then
        return 1
    fi
    # WireGuard private keys are exactly 44 base64 characters
    if [ "${#PK_VAL}" -lt 40 ]; then
        return 1
    fi
    return 0
}

# Check existing WireGuard configuration
if validate_wg_config; then
    log_info "Existing WireGuard config found and validated. Skipping paste."
else
    if [ -f "$ACTIVE_WG_CONF" ] && [ -s "$ACTIVE_WG_CONF" ]; then
        log_warn "Existing WireGuard config was invalid/empty. Removed."
        rm "$ACTIVE_WG_CONF"
    fi

    if [ -n "${WG_CONF_B64:-}" ]; then
        log_info "WireGuard configuration provided in environment. Decoding..."
        echo "$WG_CONF_B64" | base64 -d > "$ACTIVE_WG_CONF"
    else
        echo "PASTE YOUR WIREGUARD .CONF CONTENT BELOW."
        echo "Make sure to include the [Interface] block with PrivateKey."
        echo "Press ENTER, then Ctrl+D (Linux/Mac) or Ctrl+Z (Windows) to save."
        echo "----------------------------------------------------------"
        cat > "$ACTIVE_WG_CONF"
        echo "" >> "$ACTIVE_WG_CONF" 
        echo "----------------------------------------------------------"
    fi
    # Sanitize the configuration file
    $PYTHON_CMD - "$ACTIVE_WG_CONF" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()
text = text.replace("\r", "")
lines = text.splitlines()
while lines and not lines[0].strip():
    lines.pop(0)
lines = [line.rstrip() for line in lines]
lines = [re.sub(r"\s*=\s*", "=", line) for line in lines]
path.write_text("\n".join(lines) + ("\n" if lines else ""))
PY

    if ! validate_wg_config; then
        log_crit "The pasted WireGuard configuration is invalid (missing PrivateKey or malformed)."
        log_crit "Please ensure you are pasting the full contents of the .conf file."
        log_crit "Aborting to prevent container errors."
        exit 1
    fi
fi

# --- SECTION 6: VPN PROXY CONFIGURATION (GLUETUN) ---
# Configure the anonymizing VPN gateway for privacy frontends.
log_info "Configuring Gluetun VPN Client..."
$DOCKER_CMD pull -q qmcgaw/gluetun:latest > /dev/null

cat > "$GLUETUN_ENV_FILE" <<EOF
VPN_SERVICE_PROVIDER=custom
VPN_TYPE=wireguard
HTTPPROXY=on
HTTP_CONTROL_SERVER_AUTH_USER=gluetun
HTTP_CONTROL_SERVER_AUTH_PASSWORD=$ADMIN_PASS_RAW
FIREWALL_VPN_INPUT_PORTS=8080,8180,3000,3002,8280,10416,8480
FIREWALL_OUTBOUND_SUBNETS=10.0.0.0/8,172.16.0.0/12,192.168.0.0/16
EOF

# Extract profile name from WireGuard config
extract_wg_profile_name() {
    local config_file="$1"
    local in_peer=0
    local profile_name=""
    while IFS= read -r line; do
        stripped=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if echo "$stripped" | grep -qi '^\[peer\]$'; then
            in_peer=1
            continue
        fi
        if [ "$in_peer" -eq 1 ] && echo "$stripped" | grep -q '^#'; then
            profile_name=$(echo "$stripped" | sed 's/^#[[:space:]]*//')
            if [ -n "$profile_name" ]; then
                echo "$profile_name"
                return 0
            fi
        fi
        if [ "$in_peer" -eq 1 ] && echo "$stripped" | grep -q '^\['; then
            break
        fi
    done < "$config_file"
    # Fallback: look for any comment
    while IFS= read -r line; do
        stripped=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if echo "$stripped" | grep -q '^#' && ! echo "$stripped" | grep -q '='; then
            profile_name=$(echo "$stripped" | sed 's/^#[[:space:]]*//')
            if [ -n "$profile_name" ]; then
                echo "$profile_name"
                return 0
            fi
        fi
    done < "$config_file"
    echo ""
    return 1
}

# Initialize profile
INITIAL_PROFILE_NAME=$(extract_wg_profile_name "$ACTIVE_WG_CONF" || true)
if [ -z "$INITIAL_PROFILE_NAME" ]; then
    INITIAL_PROFILE_NAME="Initial-Setup"
fi
INITIAL_PROFILE_NAME_SAFE=$(echo "$INITIAL_PROFILE_NAME" | tr -cd 'a-zA-Z0-9-_#')
if [ -z "$INITIAL_PROFILE_NAME_SAFE" ]; then
    INITIAL_PROFILE_NAME_SAFE="Initial-Setup"
fi

cp "$ACTIVE_WG_CONF" "$WG_PROFILES_DIR/${INITIAL_PROFILE_NAME_SAFE}.conf"
chmod 644 "$GLUETUN_ENV_FILE" "$ACTIVE_WG_CONF" "$WG_PROFILES_DIR/${INITIAL_PROFILE_NAME_SAFE}.conf"
echo "$INITIAL_PROFILE_NAME_SAFE" > "$ACTIVE_PROFILE_NAME_FILE"

# --- SECTION 7: CRYPTOGRAPHIC SECRET GENERATION ---
# Generate high-entropy unique keys for various service-level authentication mechanisms.
SCRIBE_SECRET=$(head -c 64 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 64)
ANONYMOUS_SECRET=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32)
IV_HMAC=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 16)
IV_COMPANION=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 16)

# --- SECTION 8: PORT MAPPING CONFIGURATION ---
# Define internal and external port mappings for all infrastructure components.
PORT_INT_REDLIB=8080; PORT_INT_WIKILESS=8180; PORT_INT_INVIDIOUS=3000
PORT_INT_RIMGO=3002; PORT_INT_BREEZEWIKI=10416
PORT_INT_ANONYMOUS=8480; PORT_INT_VERT=80; PORT_INT_VERTD=24153
PORT_ADGUARD_WEB=8083; PORT_DASHBOARD_WEB=8081
PORT_PORTAINER=9000; PORT_WG_WEB=51821
PORT_REDLIB=8080; PORT_WIKILESS=8180; PORT_INVIDIOUS=3000; PORT_MEMOS=5230
PORT_RIMGO=3002; PORT_SCRIBE=8280; PORT_BREEZEWIKI=8380; PORT_ANONYMOUS=8480
PORT_VERT=5555; PORT_VERTD=24153

# VERT dynamic URLs for different access modes
if [ -n "$DESEC_DOMAIN" ]; then
    VERT_PUB_HOSTNAME="vert.$DESEC_DOMAIN:8443"
    VERTD_PUB_URL="https://vertd.$DESEC_DOMAIN:8443"
else
    VERT_PUB_HOSTNAME="$LAN_IP:$PORT_VERT"
    VERTD_PUB_URL="http://$LAN_IP:$PORT_VERTD"
fi

# --- SECTION 9: INFRASTRUCTURE CONFIGURATION ---
# Generate configuration files for core system services (DNS, SSL, Nginx).
log_info "Compiling Infrastructure Configs..."

# DNS & Certificate Setup
log_info "Setting up DNS and certificates..."

if [ -n "$DESEC_DOMAIN" ] && [ -n "$DESEC_TOKEN" ]; then
    log_info "deSEC domain provided: $DESEC_DOMAIN"
    log_info "Configuring Let's Encrypt with DNS-01 challenge..."
    
    log_info "Updating deSEC DNS record to point to $PUBLIC_IP..."
    DESEC_RESPONSE=$(curl -s -X PATCH "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/" \
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
        # We use a temp file to capture output to avoid 'set -e' issues with $(...) assignments in some shells
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

# Unbound recursive DNS configuration
cat > "$UNBOUND_CONF" <<'UNBOUNDEOF'
server:
  interface: 0.0.0.0
  port: 53
  do-ip4: yes
  do-udp: yes
  do-tcp: yes
  access-control: 0.0.0.0/0 refuse
  access-control: 172.16.0.0/12 allow
  access-control: 192.168.0.0/16 allow
  access-control: 10.0.0.0/8 allow
  hide-identity: yes
  hide-version: yes
  qname-minimization: yes
  harden-glue: yes
  harden-dnssec-stripped: yes
  use-caps-for-id: yes
  num-threads: 2
  msg-cache-size: 50m
  rrset-cache-size: 100m
  prefetch: yes
  prefetch-key: yes
  rrset-roundrobin: yes
  minimal-responses: yes
  auto-trust-anchor-file: "/var/lib/unbound/root.key"
UNBOUNDEOF

cat > "$AGH_YAML" <<EOF
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
  force_https: false
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

cat > "$NGINX_CONF" <<EOF
error_log /dev/stderr info;
access_log /dev/stdout;

# Dynamic backend mapping for subdomains
map \$http_host \$backend {
    hostnames;
    default "";
    invidious.$DESEC_DOMAIN  http://gluetun:3000;
    redlib.$DESEC_DOMAIN     http://gluetun:8080;
    wikiless.$DESEC_DOMAIN   http://gluetun:8180;
    memos.$DESEC_DOMAIN      http://$LAN_IP:$PORT_MEMOS;
    rimgo.$DESEC_DOMAIN      http://gluetun:3002;
    scribe.$DESEC_DOMAIN     http://gluetun:8280;
    breezewiki.$DESEC_DOMAIN http://gluetun:10416;
    anonymousoverflow.$DESEC_DOMAIN http://gluetun:8480;
    vert.$DESEC_DOMAIN       http://vert:80;
    vertd.$DESEC_DOMAIN      http://vertd:24153;
    adguard.$DESEC_DOMAIN    http://adguard:8083;
    portainer.$DESEC_DOMAIN  http://portainer:9000;
    wireguard.$DESEC_DOMAIN  http://$LAN_IP:51821;
    odido.$DESEC_DOMAIN      http://odido-booster:8080;
    
    # Handle the 8443 port in the host header
    "invidious.$DESEC_DOMAIN:8443"  http://gluetun:3000;
    "redlib.$DESEC_DOMAIN:8443"     http://gluetun:8080;
    "wikiless.$DESEC_DOMAIN:8443"   http://gluetun:8180;
    "memos.$DESEC_DOMAIN:8443"      http://$LAN_IP:$PORT_MEMOS;
    "rimgo.$DESEC_DOMAIN:8443"      http://gluetun:3002;
    "scribe.$DESEC_DOMAIN:8443"     http://gluetun:8280;
    "breezewiki.$DESEC_DOMAIN:8443" http://gluetun:10416;
    "anonymousoverflow.$DESEC_DOMAIN:8443" http://gluetun:8480;
    "vert.$DESEC_DOMAIN:8443"       http://vert:80;
    "vertd.$DESEC_DOMAIN:8443"      http://vertd:24153;
    "adguard.$DESEC_DOMAIN:8443"    http://adguard:8083;
    "portainer.$DESEC_DOMAIN:8443"  http://portainer:9000;
    "wireguard.$DESEC_DOMAIN:8443"  http://$LAN_IP:51821;
    "odido.$DESEC_DOMAIN:8443"      http://odido-booster:8080;
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
        proxy_pass http://hub-api:55555/;
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
        proxy_pass http://odido-booster:8080/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 30s;
        proxy_read_timeout 120s;
    }
}
EOF

# --- SECTION 10: PERSISTENT ENVIRONMENT CONFIGURATION ---
# Generate environment variables for specialized privacy frontends.
cat > "$ENV_DIR/anonymousoverflow.env" <<EOF
APP_URL=http://$LAN_IP:$PORT_ANONYMOUS
JWT_SIGNING_SECRET=$ANONYMOUS_SECRET
EOF
cat > "$ENV_DIR/scribe.env" <<EOF
SCRIBE_HOST=0.0.0.0
PORT=$PORT_SCRIBE
SECRET_KEY_BASE=$SCRIBE_SECRET
LUCKY_ENV=production
APP_DOMAIN=$LAN_IP:$PORT_SCRIBE
GITHUB_USERNAME="$SCRIBE_GH_USER"
GITHUB_PERSONAL_ACCESS_TOKEN="$SCRIBE_GH_TOKEN"
EOF

# --- SECTION 11: SOURCE REPOSITORY SYNCHRONIZATION ---
# Initialize or update external source code for locally-built application containers.
log_info "Synchronizing Source Repositories..."
clone_repo() { 
    if [ ! -d "$2/.git" ]; then 
        git clone --depth 1 "$1" "$2"
    else 
        (cd "$2" && git fetch --all && git reset --hard "origin/$(git rev-parse --abbrev-ref HEAD)" && git pull)
    fi
}

detect_dockerfile() {
    local repo_dir="$1"
    local preferred="${2:-}"
    local found=""

    if [ -n "$preferred" ] && [ -f "$repo_dir/$preferred" ]; then
        echo "$preferred"
        return 0
    fi
    if [ -f "$repo_dir/Dockerfile" ]; then
        echo "Dockerfile"
        return 0
    fi
    if [ -f "$repo_dir/docker/Dockerfile" ]; then
        echo "docker/Dockerfile"
        return 0
    fi

    found=$(find "$repo_dir" -maxdepth 3 -type f -name 'Dockerfile*' 2>/dev/null | head -n 1 || true)
    if [ -n "$found" ]; then
        echo "${found#"$repo_dir/"}"
        return 0
    fi
    return 1
}
clone_repo "https://github.com/Metastem/Wikiless" "$SRC_DIR/wikiless"
# Patch Wikiless to use DHI Node and Alpine images
WIKILESS_DOCKERFILE=$(detect_dockerfile "$SRC_DIR/wikiless" || true)
if [ -z "$WIKILESS_DOCKERFILE" ]; then
    log_warn "Wikiless Dockerfile not found - build may fail."
    WIKILESS_DOCKERFILE="Dockerfile"
fi
if [ -f "$SRC_DIR/wikiless/$WIKILESS_DOCKERFILE" ]; then
    # Use -dev for build stages to ensure npm/yarn are present
    sed -i '/[Aa][Ss] builder/ s|^FROM node:[^ ]*|FROM node:20-alpine|' "$SRC_DIR/wikiless/$WIKILESS_DOCKERFILE"
    sed -i '/[Aa][Ss] build/ s|^FROM node:[^ ]*|FROM node:20-alpine|' "$SRC_DIR/wikiless/$WIKILESS_DOCKERFILE"
    sed -i 's|^FROM gcr.io/distroless/nodejs[^ ]*|FROM node:20-alpine|g' "$SRC_DIR/wikiless/$WIKILESS_DOCKERFILE"
    sed -i 's|^FROM node:[^ ]*|FROM node:20-alpine|g' "$SRC_DIR/wikiless/$WIKILESS_DOCKERFILE"
    sed -i 's|^FROM alpine:[^ ]*|FROM alpine:latest|g' "$SRC_DIR/wikiless/$WIKILESS_DOCKERFILE"
    sed -i 's|^FROM alpine[[:space:]]|FROM alpine:latest |g' "$SRC_DIR/wikiless/$WIKILESS_DOCKERFILE"
    sed -i 's|^FROM alpine$|FROM alpine:latest|g' "$SRC_DIR/wikiless/$WIKILESS_DOCKERFILE"
    sed -i 's|CMD \["src/wikiless.js"\]|CMD ["node", "src/wikiless.js"]|g' "$SRC_DIR/wikiless/$WIKILESS_DOCKERFILE"
    log_info "Patched Wikiless Dockerfile to use DHI hardened images."
fi

cat > "$SRC_DIR/wikiless/wikiless.config" <<'EOF'
const config = {
  /**
  * Set these configs below to suite your environment.
  */
  domain: process.env.DOMAIN || '', // Set to your own domain
  default_lang: process.env.DEFAULT_LANG || 'en', // Set your own language by default
  theme: process.env.THEME || 'dark', // Set to 'white' or 'dark' by default
  http_addr: process.env.HTTP_ADDR || '0.0.0.0', // don't touch, unless you know what your doing
  nonssl_port: process.env.NONSSL_PORT || 8080, // don't touch, unless you know what your doing
  
  /**
  * You can configure redis below if needed.
  * By default Wikiless uses 'redis://127.0.0.1:6379' as the Redis URL.
  * Versions before 0.1.1 Wikiless used redis_host and redis_port properties,
  * but they are not supported anymore.
  * process.env.REDIS_HOST is still here for backwards compatibility.
  */
  redis_url: process.env.REDIS_URL || process.env.REDIS_HOST || 'redis://127.0.0.1:6379',
  redis_password: process.env.REDIS_PASSWORD,
  
  /**
  * You might need to change these configs below if you host through a reverse
  * proxy like nginx.
  */
  trust_proxy: process.env.TRUST_PROXY === 'true' || true,
  trust_proxy_address: process.env.TRUST_PROXY_ADDRESS || '127.0.0.1',

  /**
  * Redis cache expiration values (in seconds).
  * When the cache expires, new content is fetched from Wikipedia (when the
  * given URL is revisited).
  */
  setexs: {
    wikipage: process.env.WIKIPAGE_CACHE_EXPIRATION || (60 * 60 * 1), // 1 hour
  },

  /**
  * Wikimedia requires a HTTP User-agent header for all Wikimedia related
  * requests. It's a good idea to change this to something unique.
  * Read more: https://useragents.me/
  */
  wikimedia_useragent: process.env.wikimedia_useragent || 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36',

  /**
  * Cache control. Wikiless can automatically remove the cached media files from
  * the server. Cache control is on by default.
  * 'cache_control_interval' sets the interval for often the cache directory
  * is emptied (in hours). Default is every 24 hours.
  */
  cache_control: process.env.CACHE_CONTROL !== 'true' || true,
  cache_control_interval: process.env.CACHE_CONTROL_INTERVAL || 24,
}

module.exports = config
EOF
clone_repo "https://git.sr.ht/~edwardloveall/scribe" "$SRC_DIR/scribe"
# Patch Scribe to use pinned Crystal, DHI Node, and DHI Alpine images
SCRIBE_DOCKERFILE=$(detect_dockerfile "$SRC_DIR/scribe" || true)
if [ -z "$SCRIBE_DOCKERFILE" ]; then
    log_warn "Scribe Dockerfile not found - build may fail."
    SCRIBE_DOCKERFILE="Dockerfile"
fi
if [ -f "$SRC_DIR/scribe/$SCRIBE_DOCKERFILE" ]; then
    sed -i 's|^FROM 84codes/crystal:[^ ]*|FROM 84codes/crystal:1.8.1-alpine|g' "$SRC_DIR/scribe/$SCRIBE_DOCKERFILE"
    sed -i 's|^FROM node:[^ ]*|FROM node:20-alpine|g' "$SRC_DIR/scribe/$SCRIBE_DOCKERFILE"
    sed -i 's|^FROM alpine:[^ ]*|FROM alpine:latest|g' "$SRC_DIR/scribe/$SCRIBE_DOCKERFILE"
    sed -i 's|^FROM alpine[[:space:]]|FROM alpine:latest |g' "$SRC_DIR/scribe/$SCRIBE_DOCKERFILE"
    sed -i 's|^FROM alpine$|FROM alpine:latest|g' "$SRC_DIR/scribe/$SCRIBE_DOCKERFILE"
    sed -i 's|CMD \["/home/lucky/app/docker_entrypoint"\]|CMD ["/bin/sh", "/home/lucky/app/docker_entrypoint"]|g' "$SRC_DIR/scribe/$SCRIBE_DOCKERFILE"
    log_info "Patched Scribe Dockerfile to use hardened base images."
fi

clone_repo "https://github.com/iv-org/invidious.git" "$SRC_DIR/invidious"
# Patch Invidious to use DHI Alpine and pinned Crystal images (Dockerfile lives in docker/)
INVIDIOUS_DOCKERFILE=$(detect_dockerfile "$SRC_DIR/invidious" "docker/Dockerfile" || true)
if [ -z "$INVIDIOUS_DOCKERFILE" ]; then
    log_warn "Invidious Dockerfile not found - build may fail."
    INVIDIOUS_DOCKERFILE="Dockerfile"
fi
for dockerfile in "$SRC_DIR/invidious/$INVIDIOUS_DOCKERFILE" "$SRC_DIR/invidious/docker/Dockerfile.arm64"; do
    if [ -f "$dockerfile" ]; then
        sed -i 's|^FROM crystallang/crystal:[^ ]*|FROM 84codes/crystal:1.16.3-alpine|g' "$dockerfile"
        sed -i 's|^FROM alpine:[^ ]*|FROM alpine:latest|g' "$dockerfile"
        sed -i 's|^FROM alpine[[:space:]]|FROM alpine:latest |g' "$dockerfile"
        sed -i 's|^FROM alpine$|FROM alpine:latest|g' "$dockerfile"
        log_info "Patched Invidious Dockerfile base images: $(basename "$dockerfile")"
    fi
done
clone_repo "https://github.com/Lyceris-chan/odido-bundle-booster.git" "$SRC_DIR/odido-bundle-booster"
# Patch Odido Booster to use DHI Python image
ODIDO_DOCKERFILE=$(detect_dockerfile "$SRC_DIR/odido-bundle-booster" || true)
if [ -z "$ODIDO_DOCKERFILE" ]; then
    log_warn "Odido Booster Dockerfile not found - build may fail."
    ODIDO_DOCKERFILE="Dockerfile"
fi
if [ -f "$SRC_DIR/odido-bundle-booster/$ODIDO_DOCKERFILE" ]; then
    cat > "$SRC_DIR/odido-bundle-booster/$ODIDO_DOCKERFILE" <<'ODIDOEOF'
FROM python:3.11-alpine

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    APP_DIR=/app \
    APP_DATA_DIR=/data \
    PORT=8080

RUN apk add --no-cache su-exec sqlite-libs sqlite-dev build-base

WORKDIR $APP_DIR
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app
COPY entrypoint.sh /entrypoint.sh

EXPOSE 8080

ENTRYPOINT ["/bin/sh", "/entrypoint.sh"]
CMD ["python", "-m", "app.main"]
ODIDOEOF
    log_info "Overwrote Odido Booster Dockerfile to use DHI hardened images and non-privileged port."
fi

mkdir -p "$SRC_DIR/hub-api"
cat > "$SRC_DIR/hub-api/Dockerfile" <<EOF
FROM python:3.11-alpine
RUN apk add --no-cache docker-cli docker-cli-compose openssl netcat-openbsd curl git
RUN pip install --no-cache-dir psutil
WORKDIR /app
CMD ["python", "server.py"]
EOF
HUB_API_DOCKERFILE="Dockerfile"

clone_repo "https://github.com/VERT-sh/VERT.git" "$SRC_DIR/vert"
# Patch VERT to use DHI Node and Alpine images
VERT_DOCKERFILE=$(detect_dockerfile "$SRC_DIR/vert" || true)
if [ -z "$VERT_DOCKERFILE" ]; then
    log_warn "VERT Dockerfile not found - build may fail."
    VERT_DOCKERFILE="Dockerfile"
fi
if [ -f "$SRC_DIR/vert/$VERT_DOCKERFILE" ]; then
    # Use -dev variant for build stages to ensure npm/yarn are present
    sed -i '/[Aa][Ss] build/ s|^FROM node:[^ ]*|FROM node:20-alpine|' "$SRC_DIR/vert/$VERT_DOCKERFILE"
    sed -i '/[Aa][Ss] runtime/ s|^FROM node:[^ ]*|FROM node:20-alpine|' "$SRC_DIR/vert/$VERT_DOCKERFILE"
    # Use DHI bun alpine dev for builder to keep hardened alpine base
    sed -i 's|^FROM oven/bun[^ ]*|FROM oven/bun:1|g' "$SRC_DIR/vert/$VERT_DOCKERFILE"
    sed -i 's|^FROM oven/bun[[:space:]][[:space:]]*AS|FROM oven/bun:1 AS|g' "$SRC_DIR/vert/$VERT_DOCKERFILE"
    sed -i 's|^FROM oven/bun$|FROM oven/bun:1|g' "$SRC_DIR/vert/$VERT_DOCKERFILE"
    sed -i 's|^FROM oven/bun[[:space:]]|FROM oven/bun:1 |g' "$SRC_DIR/vert/$VERT_DOCKERFILE"
    sed -i 's|^RUN apt-get update.*|RUN apk add --no-cache git|g' "$SRC_DIR/vert/$VERT_DOCKERFILE"
    sed -i '/apt-get install -y --no-install-recommends git/d' "$SRC_DIR/vert/$VERT_DOCKERFILE"
    sed -i '/rm -rf \/var\/lib\/apt\/lists/d' "$SRC_DIR/vert/$VERT_DOCKERFILE"
    sed -i 's|^FROM nginx:stable-alpine|FROM nginx:alpine|g' "$SRC_DIR/vert/$VERT_DOCKERFILE"
    sed -i 's@CMD curl --fail --silent --output /dev/null http://localhost || exit 1@CMD nginx -t || exit 1@' "$SRC_DIR/vert/$VERT_DOCKERFILE"
    log_info "Patched VERT Dockerfile to use DHI hardened images."
fi

# Patch VERT Dockerfile to add missing build args
if [ -f "$SRC_DIR/vert/$VERT_DOCKERFILE" ]; then
    # Patch PUB_DISABLE_FAILURE_BLOCKS if missing
    if ! grep -q "ARG PUB_DISABLE_FAILURE_BLOCKS" "$SRC_DIR/vert/$VERT_DOCKERFILE"; then
        if grep -q "^ARG PUB_STRIPE_KEY$" "$SRC_DIR/vert/$VERT_DOCKERFILE"; then
            sed -i '/^ARG PUB_STRIPE_KEY$/a ARG PUB_DISABLE_FAILURE_BLOCKS' "$SRC_DIR/vert/$VERT_DOCKERFILE"
            sed -i '/^ENV PUB_STRIPE_KEY=${PUB_STRIPE_KEY}$/a ENV PUB_DISABLE_FAILURE_BLOCKS=${PUB_DISABLE_FAILURE_BLOCKS}' "$SRC_DIR/vert/$VERT_DOCKERFILE"
            log_info "Patched VERT Dockerfile to add missing PUB_DISABLE_FAILURE_BLOCKS"
        fi
    fi
    # Patch PUB_DISABLE_DONATIONS if missing
    if ! grep -q "ARG PUB_DISABLE_DONATIONS" "$SRC_DIR/vert/$VERT_DOCKERFILE"; then
        if grep -q "^ARG PUB_STRIPE_KEY$" "$SRC_DIR/vert/$VERT_DOCKERFILE"; then
            sed -i '/^ARG PUB_STRIPE_KEY$/a ARG PUB_DISABLE_DONATIONS' "$SRC_DIR/vert/$VERT_DOCKERFILE"
            sed -i '/^ENV PUB_STRIPE_KEY=${PUB_STRIPE_KEY}$/a ENV PUB_DISABLE_DONATIONS=${PUB_DISABLE_DONATIONS}' "$SRC_DIR/vert/$VERT_DOCKERFILE"
            log_info "Patched VERT Dockerfile to add missing PUB_DISABLE_DONATIONS"
        fi
    fi
fi

clone_repo "https://gitdab.com/cadence/breezewiki" "$SRC_DIR/breezewiki"
# Patch BreezeWiki to use DHI Alpine image
BREEZEWIKI_DOCKERFILE="Dockerfile.alpine"
if [ -f "$SRC_DIR/breezewiki/$BREEZEWIKI_DOCKERFILE" ]; then
    log_info "Updating BreezeWiki Dockerfile.alpine..."
else
    log_info "Creating BreezeWiki Dockerfile.alpine..."
fi

    cat > "$SRC_DIR/breezewiki/$BREEZEWIKI_DOCKERFILE" <<'BWEOF'
FROM alpine:latest
WORKDIR /app

# Install system dependencies
RUN apk add --no-cache \
    git \
    racket \
    ca-certificates \
    curl \
    sqlite-libs \
    fontconfig \
    cairo \
    libjpeg-turbo \
    glib \
    pango

COPY . .

# Install Racket dependencies explicitly (matches info.rkt build-deps) to avoid lock mismatch
RUN raco pkg config --set default-scope installation
RUN raco pkg install --batch --auto --no-docs --skip-installed \
    rackunit-lib \
    web-server-lib \
    http-easy-lib \
    html-parsing \
    html-writing \
    json-pointer \
    typed-ini-lib \
    memo \
    net-cookies-lib \
    db \
    sequence-tools-lib

EXPOSE 10416
CMD ["racket", "dist.rkt"]
BWEOF
log_info "BreezeWiki Dockerfile.alpine is ready."
if [ -f "$SRC_DIR/breezewiki/$BREEZEWIKI_DOCKERFILE" ]; then
    sed -i 's|^FROM alpine:[^ ]*|FROM alpine:latest|g' "$SRC_DIR/breezewiki/$BREEZEWIKI_DOCKERFILE"
    sed -i 's|^FROM alpine[[:space:]]|FROM alpine:latest |g' "$SRC_DIR/breezewiki/$BREEZEWIKI_DOCKERFILE"
    sed -i 's|^FROM alpine$|FROM alpine:latest|g' "$SRC_DIR/breezewiki/$BREEZEWIKI_DOCKERFILE"
    log_info "Patched BreezeWiki Dockerfile to use DHI hardened images."
fi

sudo chmod -R 777 "$SRC_DIR/invidious" "$SRC_DIR/vert" "$SRC_DIR/breezewiki" "$ENV_DIR" "$CONFIG_DIR" "$WG_PROFILES_DIR"

# --- SECTION 12: ADMINISTRATIVE CONTROL ARTIFACTS ---

# Generate administrative scripts for profile management and internal health monitoring.

cat > "$MIGRATE_SCRIPT" <<'EOF'
#!/bin/sh
# 🛡️ FOOLPROOF DATABASE MIGRATION SCRIPT
# This script handles automated database schema updates and backups.

SERVICE=$1
ACTION=$2
BACKUP=$3 # "yes" or "no"
DATA_DIR="/app/data"
BACKUP_DIR="$DATA_DIR/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

log() { echo "{\"timestamp\":\"$(date +'%Y-%m-%d %H:%M:%S')\",\"level\":\"DATABASE\",\"category\":\"MAINTENANCE\",\"message\":\"$1\"}"; }

mkdir -p "$BACKUP_DIR"

        if [ "$ACTION" = "backup-all" ]; then

            log "Starting full system backup (pre-update safety)..."

            tar -czf "$BACKUP_DIR/full_backup_$TIMESTAMP.tar.gz" -C "$DATA_DIR" . 2>/dev/null || true

            log "Full system backup completed: full_backup_$TIMESTAMP.tar.gz"

            exit 0

        fi

    

        if [ "$ACTION" = "restore" ]; then

            log "Attempting to restore latest backup for $SERVICE..."

            LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/${SERVICE}_*.sql 2>/dev/null | head -n1)

            if [ -n "$LATEST_BACKUP" ]; then

                log "Restoring from $LATEST_BACKUP..."

                if [ "$SERVICE" = "invidious" ]; then

                    docker exec invidious-db dropdb -U kemal invidious

                    docker exec invidious-db createdb -U kemal invidious

                    cat "$LATEST_BACKUP" | docker exec -i invidious-db psql -U kemal invidious

                    log "Restore complete."

                else

                    log "Restore not fully automated for $SERVICE yet. Check $BACKUP_DIR."

                fi

            else

                log "No sql backup found for $SERVICE."

            fi

            exit 0

        fi

    

        if [ "$SERVICE" = "invidious" ]; then

            if [ "$ACTION" = "clear" ]; then
            log "CLEARING Invidious database (resetting to defaults)..."
            if [ "$BACKUP" != "no" ]; then
                log "Creating safety backup..."
                docker exec invidious-db pg_dump -U kemal invidious > "$BACKUP_DIR/invidious_BEFORE_CLEAR_$TIMESTAMP.sql"
            fi
            # Drop and recreate
            docker exec invidious-db dropdb -U kemal invidious
            docker exec invidious-db createdb -U kemal invidious
            docker exec invidious-db /bin/sh /docker-entrypoint-initdb.d/init-invidious-db.sh
            log "Invidious database cleared."
        elif [ "$ACTION" = "migrate" ]; then
            log "Starting Invidious migration..."
            # 1. Backup existing data
            if [ "$BACKUP" != "no" ] && [ -d "$DATA_DIR/postgres" ]; then
                log "Backing up Invidious database..."
                docker exec invidious-db pg_dump -U kemal invidious > "$BACKUP_DIR/invidious_$TIMESTAMP.sql"
            fi
            # 2. Run migrations
            log "Applying schema updates..."
            docker exec invidious-db /bin/sh /docker-entrypoint-initdb.d/init-invidious-db.sh 2>&1 | grep -v "already exists" || true
            log "Invidious migration complete."
        elif [ "$ACTION" = "vacuum" ]; then
             log "Invidious (Postgres) handles vacuuming automatically. Skipping."
        fi
    elif [ "$SERVICE" = "adguard" ]; then
        if [ "$ACTION" = "clear-logs" ]; then
            log "Clearing AdGuard Home query logs..."
            find "$DATA_DIR/adguard-work" -name "querylog.json" -exec truncate -s 0 {} +
            log "AdGuard logs cleared."
        fi
    elif [ "$SERVICE" = "memos" ]; then
        if [ "$ACTION" = "vacuum" ]; then
            log "Optimizing Memos database (VACUUM)..."
            docker exec memos sqlite3 /var/opt/memos/memos_prod.db "VACUUM;" 2>/dev/null || log "Memos container not ready or sqlite3 missing."
            log "Memos database optimized."
        fi
    else
        if [ "$ACTION" = "vacuum" ]; then
            log "Vacuum not required/supported for $SERVICE."
        else
            log "No custom migration logic defined for $SERVICE."
        fi
    fi
EOF
chmod +x "$MIGRATE_SCRIPT"

cat > "$WG_CONTROL_SCRIPT" <<'EOF'
#!/bin/sh
ACTION=$1
PROFILE_NAME=$2
PROFILES_DIR="/profiles"
ACTIVE_CONF="/active-wg.conf"
NAME_FILE="/app/.active_profile_name"
LOCK_FILE="/app/.wg-control.lock"

exec 9>"$LOCK_FILE"

sanitize_json_string() {
    printf '%s' "$1" | tr -d '\000-\037' | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

if [ "$ACTION" = "activate" ]; then
    if ! flock -n 9; then
        echo "Error: Another control operation is in progress"
        exit 1
    fi
    if [ -f "$PROFILES_DIR/$PROFILE_NAME.conf" ]; then
        ln -sf "$PROFILES_DIR/$PROFILE_NAME.conf" "$ACTIVE_CONF"
        echo "$PROFILE_NAME" > "$NAME_FILE"
        DEPENDENTS="redlib wikiless wikiless_redis invidious invidious-db companion rimgo breezewiki anonymousoverflow scribe"
        # shellcheck disable=SC2086
        docker stop $DEPENDENTS 2>/dev/null || true
        docker compose -f /app/docker-compose.yml up -d --force-recreate gluetun 2>/dev/null || true
        
        # Wait for gluetun to be healthy (max 30s)
        i=0
        while [ $i -lt 30 ]; do
            HEALTH=$(docker inspect --format='{{.State.Health.Status}}' gluetun 2>/dev/null || echo "unknown")
            if [ "$HEALTH" = "healthy" ]; then
                break
            fi
            sleep 1
            i=$((i+1))
        done

        # shellcheck disable=SC2086
        docker compose -f /app/docker-compose.yml up -d --force-recreate $DEPENDENTS 2>/dev/null || true
    else
        echo "Error: Profile not found"
        exit 1
    fi
elif [ "$ACTION" = "delete" ]; then
    if ! flock -n 9; then
        echo "Error: Another control operation is in progress"
        exit 1
    fi
    if [ -f "$PROFILES_DIR/$PROFILE_NAME.conf" ]; then
        rm "$PROFILES_DIR/$PROFILE_NAME.conf"
    fi
elif [ "$ACTION" = "status" ]; then
    GLUETUN_STATUS="down"
    GLUETUN_HEALTHY="false"
    HANDSHAKE_AGO="N/A"
    ENDPOINT="--"
    PUBLIC_IP="--"
    DATA_FILE="/app/.data_usage"
    
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^gluetun$"; then
        # Check container health status
        HEALTH=$(docker inspect --format='{{.State.Health.Status}}' gluetun 2>/dev/null || echo "unknown")
        if [ "$HEALTH" = "healthy" ]; then
            GLUETUN_HEALTHY="true"
        fi
        
        # Use gluetun's HTTP control server API (port 8000) for status
        # API docs: https://github.com/qdm12/gluetun-wiki/blob/main/setup/advanced/control-server.md
        
        # Get VPN status from control server
        VPN_STATUS_RESPONSE=$(docker exec gluetun wget --user=gluetun --password="$ADMIN_PASS_RAW" -qO- --timeout=3 http://127.0.0.1:8000/v1/vpn/status 2>/dev/null || echo "")
        if [ -n "$VPN_STATUS_RESPONSE" ]; then
            # Extract status from {"status":"running"} or {"status":"stopped"}
            VPN_RUNNING=$(echo "$VPN_STATUS_RESPONSE" | grep -o '"status":"running"' || echo "")
            if [ -n "$VPN_RUNNING" ]; then
                GLUETUN_STATUS="up"
                HANDSHAKE_AGO="Connected"
            else
                GLUETUN_STATUS="down"
                HANDSHAKE_AGO="Disconnected"
            fi
        elif [ "$GLUETUN_HEALTHY" = "true" ]; then
            # Fallback: if container is healthy, assume VPN is up
            GLUETUN_STATUS="up"
            HANDSHAKE_AGO="Connected (API unavailable)"
        fi
        
        # Get public IP from control server
        PUBLIC_IP_RESPONSE=$(docker exec gluetun wget --user=gluetun --password="$ADMIN_PASS_RAW" -qO- --timeout=3 http://127.0.0.1:8000/v1/publicip/ip 2>/dev/null || echo "")
        if [ -n "$PUBLIC_IP_RESPONSE" ]; then
            # Extract IP from {"public_ip":"x.x.x.x"}
            EXTRACTED_IP=$(echo "$PUBLIC_IP_RESPONSE" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "")
            if [ -n "$EXTRACTED_IP" ]; then
                PUBLIC_IP="$EXTRACTED_IP"
            fi
        fi
        
        # Fallback to external IP check if control server didn't return an IP
        if [ -z "$PUBLIC_IP" ] || [ "$PUBLIC_IP" = "--" ]; then
            PUBLIC_IP=$(docker exec gluetun wget -qO- --timeout=5 https://api.ipify.org 2>/dev/null || echo "--")
        fi
        
        # Try to get endpoint from WireGuard config if available
        WG_CONF_ENDPOINT=$(docker exec gluetun cat /gluetun/wireguard/wg0.conf 2>/dev/null | grep -i "^Endpoint" | cut -d'=' -f2 | tr -d ' ' | head -1 || echo "")
        if [ -n "$WG_CONF_ENDPOINT" ]; then
            ENDPOINT="$WG_CONF_ENDPOINT"
        fi
        
        # Get current RX/TX from /proc/net/dev (works for tun0 or wg0 interface)
        # Format: iface: rx_bytes rx_packets ... tx_bytes tx_packets ...
        NET_DEV=$(docker exec gluetun cat /proc/net/dev 2>/dev/null || echo "")
        CURRENT_RX="0"
        CURRENT_TX="0"
        if [ -n "$NET_DEV" ]; then
            # Try tun0 first (OpenVPN), then wg0 (WireGuard)
            VPN_LINE=$(echo "$NET_DEV" | grep -E "^\s*(tun0|wg0):" | head -1 || echo "")
            if [ -n "$VPN_LINE" ]; then
                # Extract RX bytes (field 2) and TX bytes (field 10)
                CURRENT_RX=$(echo "$VPN_LINE" | awk '{print $2}' 2>/dev/null || echo "0")
                CURRENT_TX=$(echo "$VPN_LINE" | awk '{print $10}' 2>/dev/null || echo "0")
                case "$CURRENT_RX" in ''|*[!0-9]*) CURRENT_RX="0" ;; esac
                case "$CURRENT_TX" in ''|*[!0-9]*) CURRENT_TX="0" ;; esac
            fi
        fi
        
        # Load previous values and calculate cumulative total
        TOTAL_RX="0"
        TOTAL_TX="0"
        LAST_RX="0"
        LAST_TX="0"
        if [ -f "$DATA_FILE" ]; then
            # shellcheck disable=SC1090
            . "$DATA_FILE" 2>/dev/null || true
        fi
        
        # Detect counter reset (container restart) - current < last means reset
        if { [ "$CURRENT_RX" -lt "$LAST_RX" ] || [ "$CURRENT_TX" -lt "$LAST_TX" ]; } 2>/dev/null; then
            # Counter reset detected - add last values to total before reset
            TOTAL_RX=$((TOTAL_RX + LAST_RX))
            TOTAL_TX=$((TOTAL_TX + LAST_TX))
        fi
        
        # Calculate session values (current readings)
        SESSION_RX="$CURRENT_RX"
        SESSION_TX="$CURRENT_TX"
        
        # Calculate all-time totals
        ALLTIME_RX=$((TOTAL_RX + CURRENT_RX))
        ALLTIME_TX=$((TOTAL_TX + CURRENT_TX))
        
        # Save state
        cat > "$DATA_FILE" <<DATAEOF
LAST_RX=$CURRENT_RX
LAST_TX=$CURRENT_TX
TOTAL_RX=$TOTAL_RX
TOTAL_TX=$TOTAL_TX
DATAEOF
    else
        # Container not running - load saved totals
        ALLTIME_RX="0"
        ALLTIME_TX="0"
        SESSION_RX="0"
        SESSION_TX="0"
        if [ -f "$DATA_FILE" ]; then
            # shellcheck disable=SC1090
            . "$DATA_FILE" 2>/dev/null || true
            ALLTIME_RX=$((TOTAL_RX + LAST_RX))
            ALLTIME_TX=$((TOTAL_TX + LAST_TX))
        fi
    fi
    
    ACTIVE_NAME=$(tr -d '\n\r' < "$NAME_FILE" 2>/dev/null || echo "Unknown")
    if [ -z "$ACTIVE_NAME" ]; then ACTIVE_NAME="Unknown"; fi
    
    WGE_STATUS="down"
    WGE_HOST="Unknown"
    WGE_CLIENTS="0"
    WGE_CONNECTED="0"
    
    WGE_SESSION_RX="0"
    WGE_SESSION_TX="0"
    WGE_TOTAL_RX="0"
    WGE_TOTAL_TX="0"
    WGE_DATA_FILE="/app/.wge_data_usage"
    
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^wg-easy$"; then
        WGE_STATUS="up"
        WGE_HOST=$(docker exec wg-easy printenv WG_HOST 2>/dev/null | tr -d '\n\r' || echo "Unknown")
        if [ -z "$WGE_HOST" ]; then WGE_HOST="Unknown"; fi
        WG_PEER_DATA=$(docker exec wg-easy wg show wg0 2>/dev/null || echo "")
        if [ -n "$WG_PEER_DATA" ]; then
            WGE_CLIENTS=$(echo "$WG_PEER_DATA" | grep -c "^peer:" 2>/dev/null || echo "0")
            CONNECTED_COUNT=0
            
            # Calculate total RX/TX from all peers
            WGE_CURRENT_RX=0
            WGE_CURRENT_TX=0
            for rx in $(echo "$WG_PEER_DATA" | grep "transfer:" | awk '{print $2}' | sed 's/[^0-9]//g' 2>/dev/null || echo ""); do
                case "$rx" in ''|*[!0-9]*) ;; *) WGE_CURRENT_RX=$((WGE_CURRENT_RX + rx)) ;; esac
            done
            for tx in $(echo "$WG_PEER_DATA" | grep "transfer:" | awk '{print $4}' | sed 's/[^0-9]//g' 2>/dev/null || echo ""); do
                case "$tx" in ''|*[!0-9]*) ;; *) WGE_CURRENT_TX=$((WGE_CURRENT_TX + tx)) ;; esac
            done
            
            # Load previous values for WG-Easy
            WGE_LAST_RX="0"
            WGE_LAST_TX="0"
            WGE_SAVED_TOTAL_RX="0"
            WGE_SAVED_TOTAL_TX="0"
            if [ -f "$WGE_DATA_FILE" ]; then
                # shellcheck disable=SC1090
                . "$WGE_DATA_FILE" 2>/dev/null || true
            fi
            
            # Detect counter reset
            if { [ "$WGE_CURRENT_RX" -lt "$WGE_LAST_RX" ] || [ "$WGE_CURRENT_TX" -lt "$WGE_LAST_TX" ]; } 2>/dev/null; then
                WGE_SAVED_TOTAL_RX=$((WGE_SAVED_TOTAL_RX + WGE_LAST_RX))
                WGE_SAVED_TOTAL_TX=$((WGE_SAVED_TOTAL_TX + WGE_LAST_TX))
            fi
            
            WGE_SESSION_RX="$WGE_CURRENT_RX"
            WGE_SESSION_TX="$WGE_CURRENT_TX"
            WGE_TOTAL_RX=$((WGE_SAVED_TOTAL_RX + WGE_CURRENT_RX))
            WGE_TOTAL_TX=$((WGE_SAVED_TOTAL_TX + WGE_CURRENT_TX))
            
            # Save state
            cat > "$WGE_DATA_FILE" <<WGEDATAEOF
WGE_LAST_RX=$WGE_CURRENT_RX
WGE_LAST_TX=$WGE_CURRENT_TX
WGE_SAVED_TOTAL_RX=$WGE_SAVED_TOTAL_RX
WGE_SAVED_TOTAL_TX=$WGE_SAVED_TOTAL_TX
WGEDATAEOF
            
            for hs in $(echo "$WG_PEER_DATA" | grep "latest handshake:" | sed 's/.*latest handshake: //' | sed 's/ seconds.*//' | grep -E '^[0-9]+' 2>/dev/null || echo ""); do
                if [ -n "$hs" ] && [ "$hs" -lt 180 ] 2>/dev/null; then
                    CONNECTED_COUNT=$((CONNECTED_COUNT + 1))
                fi
            done
            WGE_CONNECTED="$CONNECTED_COUNT"
        fi
    fi
    
    ACTIVE_NAME=$(sanitize_json_string "$ACTIVE_NAME")
    ENDPOINT=$(sanitize_json_string "$ENDPOINT")
    PUBLIC_IP=$(sanitize_json_string "$PUBLIC_IP")
    HANDSHAKE_AGO=$(sanitize_json_string "$HANDSHAKE_AGO")
    WGE_HOST=$(sanitize_json_string "$WGE_HOST")
    
    # Check individual privacy services status internally
    SERVICES_JSON="{"
    HEALTH_DETAILS_JSON="{"
    FIRST_SRV=1
    # Added core infrastructure services to the monitoring loop
    for srv in "invidious:3000" "redlib:8080" "wikiless:8180" "memos:5230" "rimgo:3002" "scribe:8280" "breezewiki:10416" "anonymousoverflow:8480" "vert:80" "vertd:24153" "adguard:8083" "portainer:9000" "wg-easy:51821"; do
        s_name=${srv%:*}
        s_port=${srv#*:}
        [ $FIRST_SRV -eq 0 ] && { SERVICES_JSON="$SERVICES_JSON,"; HEALTH_DETAILS_JSON="$HEALTH_DETAILS_JSON,"; }
        
        # Priority 1: Check Docker container health if it exists
        HEALTH="unknown"
        DETAILS=""
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${s_name}$"; then
            STATE_JSON=$(docker inspect --format='{{json .State}}' "$s_name" 2>/dev/null)
            HEALTH=$(echo "$STATE_JSON" | grep -oP '"Health":.*?"Status":"\K[^"]+' || echo "running")
            # If unhealthy, extract last error
            if [ "$HEALTH" = "unhealthy" ]; then
                DETAILS=$(echo "$STATE_JSON" | grep -oP '"Log":\[\{"Start":".*?","End":".*?","ExitCode":\d+,"Output":"\K[^"]+' | tail -1 | sed 's/\\n/ /g' | sed 's/\\//g')
            fi
        fi

        if [ "$HEALTH" = "healthy" ] || [ "$HEALTH" = "running" ]; then
            SERVICES_JSON="$SERVICES_JSON\"$s_name\":\"up\""
        elif [ "$HEALTH" = "unhealthy" ] || [ "$HEALTH" = "starting" ]; then
            # If Docker says unhealthy but port is reachable, count as up
            # For services in gluetun network, we check against gluetun container
            TARGET_HOST="$s_name"
            case "$s_name" in
                invidious|redlib|wikiless|rimgo|scribe|breezewiki|anonymousoverflow) TARGET_HOST="gluetun" ;;
            esac
            if nc -z -w 2 "$TARGET_HOST" "$s_port" >/dev/null 2>&1; then
                SERVICES_JSON="$SERVICES_JSON\"$s_name\":\"up\""
            else
                SERVICES_JSON="$SERVICES_JSON\"$s_name\":\"$HEALTH\""
            fi
        else
            # Fallback to network check
            TARGET_HOST="$s_name"
            case "$s_name" in
                invidious|redlib|wikiless|rimgo|scribe|breezewiki|anonymousoverflow) TARGET_HOST="gluetun" ;;
            esac
            
            if nc -z -w 2 "$TARGET_HOST" "$s_port" >/dev/null 2>&1; then
                SERVICES_JSON="$SERVICES_JSON\"$s_name\":\"up\""
            else
                SERVICES_JSON="$SERVICES_JSON\"$s_name\":\"down\""
            fi
        fi
        HEALTH_DETAILS_JSON="$HEALTH_DETAILS_JSON\"$s_name\":\"$(sanitize_json_string "$DETAILS")\""
        FIRST_SRV=0
    done
    SERVICES_JSON="$SERVICES_JSON}"
    HEALTH_DETAILS_JSON="$HEALTH_DETAILS_JSON}"

    printf '{"gluetun":{"status":"%s","healthy":%s,"active_profile":"%s","endpoint":"%s","public_ip":"%s","handshake_ago":"%s","session_rx":"%s","session_tx":"%s","total_rx":"%s","total_tx":"%s"},"wgeasy":{"status":"%s","host":"%s","clients":"%s","connected":"%s","session_rx":"%s","session_tx":"%s","total_rx":"%s","total_tx":"%s"},"services":%s,"health_details":%s}' \
        "$GLUETUN_STATUS" "$GLUETUN_HEALTHY" "$ACTIVE_NAME" "$ENDPOINT" "$PUBLIC_IP" "$HANDSHAKE_AGO" "$SESSION_RX" "$SESSION_TX" "$ALLTIME_RX" "$ALLTIME_TX" \
        "$WGE_STATUS" "$WGE_HOST" "$WGE_CLIENTS" "$WGE_CONNECTED" "$WGE_SESSION_RX" "$WGE_SESSION_TX" "$WGE_TOTAL_RX" "$WGE_TOTAL_TX" \
        "$SERVICES_JSON" "$HEALTH_DETAILS_JSON"
fi
fi
EOF
chmod +x "$WG_CONTROL_SCRIPT"

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
    if [ -f "$repo_dir/Dockerfile" ]; then echo "Dockerfile"; return 0; fi
    if [ -f "$repo_dir/docker/Dockerfile" ]; then echo "docker/Dockerfile"; return 0; fi
    found=$(find "$repo_dir" -maxdepth 3 -type f -name 'Dockerfile*' 2>/dev/null | head -n 1 || true)
    if [ -n "$found" ]; then echo "${found#"$repo_dir/"}"; return 0; fi
    return 1
}

if [ "$SERVICE" = "wikiless" ] || [ "$SERVICE" = "all" ]; then
    log "Patching Wikiless..."
    D_FILE=$(detect_dockerfile "$SRC_ROOT/wikiless")
    if [ -n "$D_FILE" ]; then
        sed -i '/[Aa][Ss] builder/ s|^FROM node:[^ ]*|FROM node:20-alpine|' "$SRC_ROOT/wikiless/$D_FILE"
        sed -i '/[Aa][Ss] build/ s|^FROM node:[^ ]*|FROM node:20-alpine|' "$SRC_ROOT/wikiless/$D_FILE"
        sed -i 's|^FROM gcr.io/distroless/nodejs[^ ]*|FROM node:20-alpine|g' "$SRC_ROOT/wikiless/$D_FILE"
        sed -i 's|^FROM node:[^ ]*|FROM node:20-alpine|g' "$SRC_ROOT/wikiless/$D_FILE"
        sed -i 's|^FROM alpine:[^ ]*|FROM alpine:latest|g' "$SRC_ROOT/wikiless/$D_FILE"
        sed -i 's|^FROM alpine[[:space:]]|FROM alpine:latest |g' "$SRC_ROOT/wikiless/$D_FILE"
        sed -i 's|^FROM alpine$|FROM alpine:latest|g' "$SRC_ROOT/wikiless/$D_FILE"
        sed -i 's|CMD \["src/wikiless.js"\]|CMD ["node", "src/wikiless.js"]|g' "$SRC_ROOT/wikiless/$D_FILE"
    fi
fi

if [ "$SERVICE" = "scribe" ] || [ "$SERVICE" = "all" ]; then
    log "Patching Scribe..."
    D_FILE=$(detect_dockerfile "$SRC_ROOT/scribe")
    if [ -n "$D_FILE" ]; then
        sed -i 's|^FROM 84codes/crystal:[^ ]*|FROM 84codes/crystal:1.8.1-alpine|g' "$SRC_ROOT/scribe/$D_FILE"
        sed -i 's|^FROM node:[^ ]*|FROM node:20-alpine|g' "$SRC_ROOT/scribe/$D_FILE"
        sed -i 's|^FROM alpine:[^ ]*|FROM alpine:latest|g' "$SRC_ROOT/scribe/$D_FILE"
        sed -i 's|^FROM alpine[[:space:]]|FROM alpine:latest |g' "$SRC_ROOT/scribe/$D_FILE"
        sed -i 's|^FROM alpine$|FROM alpine:latest|g' "$SRC_ROOT/scribe/$D_FILE"
        sed -i 's|CMD \["/home/lucky/app/docker_entrypoint"\]|CMD ["/bin/sh", "/home/lucky/app/docker_entrypoint"]|g' "$SRC_ROOT/scribe/$D_FILE"
    fi
fi

if [ "$SERVICE" = "invidious" ] || [ "$SERVICE" = "all" ]; then
    log "Patching Invidious..."
    D_FILE=$(detect_dockerfile "$SRC_ROOT/invidious" "docker/Dockerfile")
    if [ -n "$D_FILE" ]; then
        sed -i 's|^FROM crystallang/crystal:[^ ]*|FROM 84codes/crystal:1.16.3-alpine|g' "$SRC_ROOT/invidious/$D_FILE"
        sed -i 's|^FROM alpine:[^ ]*|FROM alpine:latest|g' "$SRC_ROOT/invidious/$D_FILE"
        sed -i 's|^FROM alpine[[:space:]]|FROM alpine:latest |g' "$SRC_ROOT/invidious/$D_FILE"
        sed -i 's|^FROM alpine$|FROM alpine:latest|g' "$SRC_ROOT/invidious/$D_FILE"
    fi
    # Also patch arm64 if exists
    if [ -f "$SRC_ROOT/invidious/docker/Dockerfile.arm64" ]; then
        sed -i 's|^FROM crystallang/crystal:[^ ]*|FROM 84codes/crystal:1.16.3-alpine|g' "$SRC_ROOT/invidious/docker/Dockerfile.arm64"
        sed -i 's|^FROM alpine:[^ ]*|FROM alpine:latest|g' "$SRC_ROOT/invidious/docker/Dockerfile.arm64"
    fi
fi

if [ "$SERVICE" = "odido-booster" ] || [ "$SERVICE" = "all" ]; then
    log "Patching Odido..."
    D_FILE=$(detect_dockerfile "$SRC_ROOT/odido-bundle-booster")
    if [ -n "$D_FILE" ]; then
        cat > "$SRC_ROOT/odido-bundle-booster/$D_FILE" <<'ODIDOEOF'
FROM python:3.11-alpine

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    APP_DIR=/app \
    APP_DATA_DIR=/data \
    PORT=8080

RUN apk add --no-cache su-exec sqlite-libs sqlite-dev build-base

WORKDIR $APP_DIR
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app
COPY entrypoint.sh /entrypoint.sh

EXPOSE 8080

ENTRYPOINT ["/bin/sh", "/entrypoint.sh"]
CMD ["python", "-m", "app.main"]
ODIDOEOF
    fi
fi

if [ "$SERVICE" = "vert" ] || [ "$SERVICE" = "all" ]; then
    log "Patching VERT..."
    D_FILE=$(detect_dockerfile "$SRC_ROOT/vert")
    if [ -n "$D_FILE" ]; then
        sed -i '/[Aa][Ss] build/ s|^FROM node:[^ ]*|FROM node:20-alpine|' "$SRC_ROOT/vert/$D_FILE"
        sed -i '/[Aa][Ss] runtime/ s|^FROM node:[^ ]*|FROM node:20-alpine|' "$SRC_ROOT/vert/$D_FILE"
        sed -i 's|^FROM oven/bun[^ ]*|FROM oven/bun:1|g' "$SRC_ROOT/vert/$D_FILE"
        sed -i 's|^FROM oven/bun[[:space:]][[:space:]]*AS|FROM oven/bun:1 AS|g' "$SRC_ROOT/vert/$D_FILE"
        sed -i 's|^FROM oven/bun$|FROM oven/bun:1|g' "$SRC_ROOT/vert/$D_FILE"
        sed -i 's|^FROM oven/bun[[:space:]]|FROM oven/bun:1 |g' "$SRC_ROOT/vert/$D_FILE"
        sed -i 's|^RUN apt-get update.*|RUN apk add --no-cache git|g' "$SRC_ROOT/vert/$D_FILE"
        sed -i '/apt-get install -y --no-install-recommends git/d' "$SRC_ROOT/vert/$D_FILE"
        sed -i '/rm -rf \/var\/lib\/apt\/lists/d' "$SRC_ROOT/vert/$D_FILE"
        sed -i 's|^FROM nginx:stable-alpine|FROM nginx:alpine|g' "$SRC_ROOT/vert/$D_FILE"
        sed -i 's@CMD curl --fail --silent --output /dev/null http://localhost || exit 1@CMD nginx -t || exit 1@' "$SRC_ROOT/vert/$D_FILE"
        
        # Build args patches
        if ! grep -q "ARG PUB_DISABLE_FAILURE_BLOCKS" "$SRC_ROOT/vert/$D_FILE"; then
            if grep -q "^ARG PUB_STRIPE_KEY$" "$SRC_ROOT/vert/$D_FILE"; then
                sed -i '/^ARG PUB_STRIPE_KEY$/a ARG PUB_DISABLE_FAILURE_BLOCKS' "$SRC_ROOT/vert/$D_FILE"
                sed -i '/^ENV PUB_STRIPE_KEY=${PUB_STRIPE_KEY}$/a ENV PUB_DISABLE_FAILURE_BLOCKS=${PUB_DISABLE_FAILURE_BLOCKS}' "$SRC_ROOT/vert/$D_FILE"
            fi
        fi
        if ! grep -q "ARG PUB_DISABLE_DONATIONS" "$SRC_ROOT/vert/$D_FILE"; then
            if grep -q "^ARG PUB_STRIPE_KEY$" "$SRC_ROOT/vert/$D_FILE"; then
                sed -i '/^ARG PUB_STRIPE_KEY$/a ARG PUB_DISABLE_DONATIONS' "$SRC_ROOT/vert/$D_FILE"
                sed -i '/^ENV PUB_STRIPE_KEY=${PUB_STRIPE_KEY}$/a ENV PUB_DISABLE_DONATIONS=${PUB_DISABLE_DONATIONS}' "$SRC_ROOT/vert/$D_FILE"
            fi
        fi
    fi
fi

if [ "$SERVICE" = "breezewiki" ] || [ "$SERVICE" = "all" ]; then
    log "Recreating BreezeWiki Dockerfile.alpine..."
    cat > "$SRC_ROOT/breezewiki/Dockerfile.alpine" <<'BWEOF'
FROM alpine:latest
WORKDIR /app
RUN apk add --no-cache git racket ca-certificates curl sqlite-libs fontconfig cairo libjpeg-turbo glib pango
COPY . .
RUN raco pkg config --set default-scope installation
RUN raco pkg install --batch --auto --no-docs --skip-installed \
    rackunit-lib \
    web-server-lib \
    http-easy-lib \
    html-parsing \
    html-writing \
    json-pointer \
    typed-ini-lib \
    memo \
    net-cookies-lib \
    db \
    sequence-tools-lib
EXPOSE 10416
CMD ["racket", "dist.rkt"]
BWEOF
fi
PATCHEOF
chmod +x "$PATCHES_SCRIPT"

cat > "$WG_API_SCRIPT" <<'APIEOF'
#!/usr/bin/env python3
import http.server
import socketserver
import json
import os
import re
import subprocess
import time
import sqlite3
import threading
import urllib.request
import urllib.parse
import psutil
import socket
import secrets
import uuid

# Global session tracking for authorized browser sessions (cookie-free)
# Dictionary: {token: expiry_timestamp}
valid_sessions = {}
session_cleanup_enabled = True

def cleanup_sessions_thread():
    """Background thread to purge expired auth sessions."""
    global valid_sessions
    while True:
        if session_cleanup_enabled:
            now = time.time()
            expired = [t for t, expiry in valid_sessions.items() if now > expiry]
            for t in expired:
                del valid_sessions[t]
        time.sleep(60)

# Start cleanup thread
threading.Thread(target=cleanup_sessions_thread, daemon=True).start()

PORT = 55555
CONFIG_DIR = "/app"
PROFILES_DIR = "/profiles"
CONTROL_SCRIPT = "/usr/local/bin/wg-control.sh"
LOG_FILE = "/app/deployment.log"
DB_FILE = "/app/data/logs.db"
ASSETS_DIR = "/assets"
SERVICES_FILE = os.path.join(CONFIG_DIR, "services.json")

FONT_SOURCES = {
    "gs.css": [
        "https://fontlay.com/css2?family=Google+Sans+Flex:wght@400;500;600;700&display=swap",
    ],
    "cc.css": [
        "https://fontlay.com/css2?family=Cascadia+Code:ital,wght@0,200..700;1,200..700&display=swap",
    ],
    "ms.css": [
        "https://fontlay.com/css2?family=Material+Symbols+Rounded:opsz,wght,FILL,GRAD@20..48,100..700,0..1,-50..200&display=swap",
    ],
}
FONT_ORIGINS = [
    "https://fontlay.com",
]

def extract_profile_name(config):
    """Extract profile name from WireGuard config."""
    lines = config.split('\n')
    in_peer = False
    for line in lines:
        stripped = line.strip()
        if stripped.lower() == '[peer]':
            in_peer = True
            continue
        if in_peer and stripped.startswith('#'):
            name = stripped.lstrip('#').strip()
            if name:
                return name
        if in_peer and stripped.startswith('['):
            break
    for line in lines:
        stripped = line.strip()
        if stripped.startswith('#'):
            name = stripped.lstrip('#').strip()
            if name and '=' not in name:
                return name
    return None

def init_db():
    """Initialize the SQLite database for logs and metrics."""
    os.makedirs(os.path.dirname(DB_FILE), exist_ok=True)
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    c.execute('''CREATE TABLE IF NOT EXISTS logs
                 (id INTEGER PRIMARY KEY AUTOINCREMENT, 
                  timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                  level TEXT, category TEXT, message TEXT)''')
    c.execute('''CREATE TABLE IF NOT EXISTS metrics
                 (id INTEGER PRIMARY KEY AUTOINCREMENT,
                  timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                  container TEXT, cpu_percent REAL, mem_usage REAL, mem_limit REAL)''')
    conn.commit()
    conn.close()

def metrics_collector():
    """Background thread to collect container metrics."""
    while True:
        try:
            res = subprocess.run(
                ['docker', 'stats', '--no-stream', '--format', '{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}'],
                capture_output=True, text=True, timeout=30
            )
            if res.returncode == 0:
                conn = sqlite3.connect(DB_FILE)
                c = conn.cursor()
                for line in res.stdout.strip().split('\n'):
                    if not line: continue
                    parts = line.split('\t')
                    if len(parts) == 3:
                        name, cpu_str, mem_combined = parts
                        cpu = float(cpu_str.replace('%', ''))
                        
                        def to_mb(val):
                            val = val.upper()
                            if 'GIB' in val: return float(val.replace('GIB', '')) * 1024
                            if 'MIB' in val: return float(val.replace('MIB', ''))
                            if 'KIB' in val: return float(val.replace('KIB', '')) / 1024
                            if 'B' in val: return float(val.replace('B', '')) / 1024 / 1024
                            return 0.0

                        mem_parts = mem_combined.split(' / ')
                        mem_usage = to_mb(mem_parts[0])
                        mem_limit = to_mb(mem_parts[1]) if len(mem_parts) > 1 else 0.0
                        
                        c.execute("INSERT INTO metrics (container, cpu_percent, mem_usage, mem_limit) VALUES (?, ?, ?, ?)",
                                  (name, cpu, mem_usage, mem_limit))
                
                c.execute("DELETE FROM metrics WHERE timestamp < datetime('now', '-1 hour')")
                conn.commit()
                conn.close()
        except Exception as e:
            print(f"Metrics Error: {e}")
        time.sleep(15)

def log_structured(level, message, category="SYSTEM"):
    """Log to both file and SQLite."""
    # Humanize common logs
    if "GET /system-health" in message:
        message = "System health telemetry synchronized"
    elif "POST /update-service" in message:
        message = "Service update sequence initiated"
    elif "POST /theme" in message:
        message = "UI theme preferences updated"
    elif "GET /theme" in message:
        message = "UI theme configuration synchronized"
    elif "GET /profiles" in message:
        message = "VPN profile list retrieved"
    elif "POST /activate" in message:
        message = "VPN profile activation triggered"
    elif "POST /upload" in message:
        message = "VPN configuration profile uploaded"
    elif "POST /delete" in message:
        message = "VPN configuration profile deleted"
    elif "POST /restart-stack" in message:
        message = "Full system stack restart triggered"
    elif "POST /batch-update" in message:
        message = "Batch service update sequence started"
    elif "POST /rotate-api-key" in message:
        message = "Dashboard API security key rotated"
    elif "GET /check-updates" in message:
        message = "Update availability check requested"
    elif "GET /changelog" in message:
        message = "Service changelog retrieved"
    elif "GET /services" in message:
        message = "Service catalog synchronized"
    elif "GET /status" in message:
        return # Too noisy
    elif "GET /metrics" in message:
        return # Too noisy
    elif "GET /containers" in message:
        return # Too noisy
    elif "GET /updates" in message:
        return # Too noisy
    elif "GET /certificate-status" in message:
        return # Too noisy
        
    entry = {
        "timestamp": time.strftime('%Y-%m-%d %H:%M:%S'),
        "level": level,
        "category": category,
        "message": message
    }
    # Log to file
    try:
        with open(LOG_FILE, 'a') as f:
            f.write(json.dumps(entry) + "\n")
    except: pass
    
    # Log to DB
    try:
        conn = sqlite3.connect(DB_FILE)
        c = conn.cursor()
        c.execute("INSERT INTO logs (level, category, message) VALUES (?, ?, ?)",
                  (level, category, message))
        conn.commit()
        conn.close()
    except Exception as e:
        print(f"DB Log Error: {e}")
    
    print(f"[{level}] {message}")

def log_fonts(message, level="SYSTEM"):
    try:
        log_structured(level, message, "FONTS")
    except Exception:
        print(f"[{level}] {message}")

def load_services():
    try:
        if os.path.exists(SERVICES_FILE):
            with open(SERVICES_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
            if isinstance(data, dict) and "services" in data:
                data = data["services"]
            if isinstance(data, dict):
                return data
    except Exception as e:
        print(f"[WARN] Service catalog load failed: {e}")
    return {}

def get_proxy_opener():
    # Gluetun proxy is usually available at gluetun:8888 within the same docker network
    proxy_handler = urllib.request.ProxyHandler({'http': 'http://gluetun:8888', 'https': 'http://gluetun:8888'})
    opener = urllib.request.build_opener(proxy_handler)
    return opener

def download_text(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"})
    try:
        opener = get_proxy_opener()
        with opener.open(req, timeout=30) as resp:
            return resp.read().decode("utf-8", errors="replace")
    except:
        # Fallback to direct if proxy fails
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.read().decode("utf-8", errors="replace")

def download_binary(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"})
    try:
        opener = get_proxy_opener()
        with opener.open(req, timeout=30) as resp:
            return resp.read()
    except:
        # Fallback to direct if proxy fails
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.read()

def ensure_assets():
    if os.path.exists(ASSETS_DIR) and not os.path.isdir(ASSETS_DIR):
        log_fonts(f"Asset path is not a directory: {ASSETS_DIR}", "WARN")
        return
    os.makedirs(ASSETS_DIR, exist_ok=True)

    for css_name, sources in FONT_SOURCES.items():
        css_path = os.path.join(ASSETS_DIR, css_name)
        css_text = ""

        if not os.path.exists(css_path) or os.path.getsize(css_path) == 0:
            css_text = None
            for url in sources:
                try:
                    css_text = download_text(url)
                    with open(css_path, "w", encoding="utf-8") as f:
                        f.write(css_text)
                    log_fonts(f"Downloaded {css_name} from {url}")
                    break
                except Exception as e:
                    log_fonts(f"Failed to download {css_name} from {url}: {e}", "WARN")
            if not css_text:
                continue

        if not css_text:
            try:
                with open(css_path, "r", encoding="utf-8") as f:
                    css_text = f.read()
            except Exception as e:
                log_fonts(f"Failed to read {css_name}: {e}", "WARN")
                continue

        if "url(" not in css_text:
            continue

        urls_in_css = re.findall(r"url\(([^)]+)\)", css_text)
        if not urls_in_css:
            continue

        updated = False
        for raw in urls_in_css:
            cleaned = raw.strip().strip("\"'")
            if not cleaned or cleaned.startswith("data:"):
                continue

            filename = os.path.basename(cleaned.split("?")[0])
            if not filename:
                continue

            local_path = os.path.join(ASSETS_DIR, filename)
            if not os.path.exists(local_path):
                candidates = []
                if cleaned.startswith("//"):
                    candidates = [f"https:{cleaned}"]
                elif cleaned.startswith("http"):
                    candidates = [cleaned]
                else:
                    for origin in FONT_ORIGINS:
                        candidates.append(urllib.parse.urljoin(origin + "/", cleaned.lstrip("/")))

                last_err = None
                for candidate in candidates:
                    try:
                        data = download_binary(candidate)
                        with open(local_path, "wb") as f:
                            f.write(data)
                        log_fonts(f"Downloaded asset {filename} from {candidate}")
                        last_err = None
                        break
                    except Exception as e:
                        last_err = e

                if last_err is not None and not os.path.exists(local_path):
                    log_fonts(f"Failed to download asset {filename}: {last_err}", "WARN")
                    continue

            if raw != filename:
                css_text = css_text.replace(raw, filename)
                updated = True

        if updated:
            try:
                with open(css_path, "w", encoding="utf-8") as f:
                    f.write(css_text)
            except Exception as e:
                log_fonts(f"Failed to update {css_name}: {e}", "WARN")

    # Ensure MCU library
    mcu_path = os.path.join(ASSETS_DIR, "mcu.js")
    if not os.path.exists(mcu_path):
        try:
            # Use verified ESM bundle
            url = "https://cdn.jsdelivr.net/npm/@material/material-color-utilities@0.2.7/+esm"
            data = download_binary(url)
            with open(mcu_path, "wb") as f:
                f.write(data)
            log_fonts(f"Downloaded mcu.js from {url}")
        except Exception as e:
            log_fonts(f"Failed to download mcu.js: {e}", "WARN")

    # Ensure local SVG icon
    svg_path = os.path.join(ASSETS_DIR, "privacy-hub.svg")
    if not os.path.exists(svg_path):
        try:
            svg = """<svg xmlns=\\"http://www.w3.org/2000/svg\\" height=\\"128\\" viewBox=\\"0 -960 960 960\\" width=\\"128\\" fill=\\"#D0BCFF\\">\\n    <path d=\\"M480-80q-139-35-229.5-159.5S160-516 160-666v-134l320-120 320 120v134q0 151-90.5 275.5T480-80Zm0-84q104-33 172-132t68-210v-105l-240-90-240 90v105q0 111 68 210t172 132Zm0-316Z\\"/>\\n</svg>\\n"""
            with open(svg_path, "w", encoding="utf-8") as f:
                f.write(svg)
            log_fonts("Generated privacy-hub.svg")
        except Exception as e:
            log_fonts(f"Failed to generate privacy-hub.svg: {e}", "WARN")

class ThreadingHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True

class APIHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        # Filter out common health check and static asset logs to reduce noise
        msg = format % args
        
        # Humanize common logs
        if "GET /system-health" in msg:
            log_structured("INFO", "System health telemetry synchronized", "NETWORK")
            return
        elif "POST /update-service" in msg:
            log_structured("INFO", "Service update sequence initiated", "NETWORK")
            return
        elif "POST /theme" in msg:
            log_structured("INFO", "UI theme preferences updated", "NETWORK")
            return
        elif "GET /theme" in msg:
            log_structured("INFO", "UI theme configuration synchronized", "NETWORK")
            return
        elif "POST /restart-stack" in msg:
            log_structured("INFO", "Full system stack restart triggered", "ORCHESTRATION")
            return
        elif "POST /rotate-api-key" in msg:
            log_structured("SECURITY", "Dashboard API security key rotated", "AUTH")
            return
        elif "POST /batch-update" in msg:
            log_structured("INFO", "Batch service update sequence started", "MAINTENANCE")
            return
        elif "POST /activate" in msg:
            log_structured("INFO", "VPN profile switch triggered", "NETWORK")
            return
        elif "POST /upload" in msg:
            log_structured("INFO", "VPN configuration profile uploaded", "NETWORK")
            return
        elif "POST /delete" in msg:
            log_structured("INFO", "VPN configuration profile deleted", "NETWORK")
            return
        elif "GET /check-updates" in msg:
            log_structured("INFO", "Update availability check requested", "MAINTENANCE")
            return
        elif "GET /changelog" in msg:
            log_structured("INFO", "Service changelog retrieved", "MAINTENANCE")
            return
        elif "GET /services" in msg:
            log_structured("INFO", "Service catalog synchronized", "NETWORK")
            return
            
        if any(x in msg for x in ['GET /status', 'GET /metrics', 'GET /containers', 'GET /services', 'GET /updates', 'GET /logs', 'GET /certificate-status', 'GET /odido-api/api/status', 'HTTP/1.1" 200', 'HTTP/1.1" 304']):
            return
        log_structured("INFO", msg, "NETWORK")
    
    def _send_json(self, data, code=200):
        try:
            body = json.dumps(data).encode('utf-8')
            self.send_response(code)
            self.send_header('Content-type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.send_header('Access-Control-Allow-Origin', '*')
            self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
            self.send_header('Access-Control-Allow-Headers', 'Content-Type, X-API-Key')
            self.end_headers()
            self.wfile.write(body)
        except Exception as e:
            print(f"Error sending JSON: {e}")

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, X-API-Key')
        self.end_headers()

    def _check_auth(self):
        # Allow certain GET endpoints without auth for the dashboard
        base_path = self.path.split('?')[0]
        if self.command == 'GET' and base_path in ['/', '/status', '/profiles', '/containers', '/services', '/certificate-status', '/events', '/updates', '/metrics', '/check-updates', '/master-update', '/logs', '/system-health']:
            return True
        
        # Watchtower notification (comes from docker network, simple path check)
        if self.path.startswith('/watchtower'):
            return True

        # Check for Session Token (per-session authorization)
        session_token = self.headers.get('X-Session-Token')
        if session_token and session_token in valid_sessions:
            if not session_cleanup_enabled or time.time() < valid_sessions[session_token]:
                return True
            else:
                # Token expired
                del valid_sessions[session_token]

        # Check for API Key in headers (permanent automation key)
        api_key = self.headers.get('X-API-Key')
        expected_key = os.environ.get('HUB_API_KEY')
        
        if expected_key and api_key == expected_key:
            return True
            
        return False

    def do_GET(self):
        if not self._check_auth():
            self._send_json({"error": "Unauthorized"}, 401)
            return

        elif self.path == '/system-health':
            try:
                # System Uptime
                uptime_seconds = time.time() - psutil.boot_time()
                
                # CPU & RAM
                cpu_usage = psutil.cpu_percent(interval=None)
                ram = psutil.virtual_memory()
                
                # Disk Health (Root Partition)
                disk = psutil.disk_usage('/')
                
                # Project Size (Comprehensive)
                project_size_bytes = 0
                try:
                    # Sum up BASE_DIR (mounted as /project_root), and check volume sizes via docker
                    res = subprocess.run(['du', '-sb', '/project_root'], capture_output=True, text=True, timeout=15)
                    if res.returncode == 0:
                        project_size_bytes += int(res.stdout.split()[0])
                    
                    # Also include Docker volumes if possible
                    vol_res = subprocess.run(['docker', 'system', 'df', '-v', '--format', 'json'], capture_output=True, text=True, timeout=10)
                    if vol_res.returncode == 0:
                        try:
                            vdata = json.loads(vol_res.stdout)
                            for vol in vdata.get('Volumes', []):
                                if 'privacy-hub' in vol.get('Name', '') or 'privacyhub' in vol.get('Name', ''):
                                    # size is string like "1.2MB", "45.1kB"
                                    sz_str = vol.get('Size', '0B').upper()
                                    mult = 1
                                    if 'GB' in sz_str: mult = 1024*1024*1024
                                    elif 'MB' in sz_str: mult = 1024*1024
                                    elif 'KB' in sz_str: mult = 1024
                                    sz_val = float(re.sub(r'[^0-9.]', '', sz_str))
                                    project_size_bytes += int(sz_val * mult)
                        except: pass
                except: pass

                # Drive Health Logic (SMART-lite)
                drive_health_pct = 100 - disk.percent
                drive_status = "Healthy"
                smart_alerts = []
                
                if disk.percent > 90:
                    drive_status = "Warning (High Usage)"
                    smart_alerts.append("Disk space is critical (>90%)")
                
                # Try to get real SMART info if smartctl is available
                try:
                    s_res = subprocess.run(['smartctl', '-H', '/dev/sda'], capture_output=True, text=True, timeout=5)
                    if s_res.returncode == 0:
                        if "PASSED" not in s_res.stdout:
                            drive_status = "Action Required"
                            smart_alerts.append("SMART health check failed")
                except: pass

                health_data = {
                    "uptime": uptime_seconds,
                    "cpu_percent": cpu_usage,
                    "ram_used": ram.used / (1024 * 1024),
                    "ram_total": ram.total / (1024 * 1024),
                    "disk_used": disk.used / (1024 * 1024 * 1024),
                    "disk_total": disk.total / (1024 * 1024 * 1024),
                    "disk_percent": disk.percent,
                    "project_size": project_size_bytes / (1024 * 1024),
                    "drive_status": drive_status,
                    "drive_health_pct": drive_health_pct,
                    "smart_alerts": smart_alerts
                }
                self._send_json(health_data)
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path == '/uninstall':
            try:
                def run_uninstall():
                    time.sleep(2)
                    subprocess.run(["bash", "/app/zima.sh", "-x"], cwd="/app")
                
                import threading
                threading.Thread(target=run_uninstall).start()
                self._send_json({"success": True, "message": "Uninstall sequence started"})
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path == '/status':
            try:
                result = subprocess.run([CONTROL_SCRIPT, "status"], capture_output=True, text=True, timeout=30)
                output = result.stdout.strip()
                output = re.sub(r'[\x00-\x1f\x7f-\x9f]', '', output)
                json_start = output.find('{')
                json_end = output.rfind('}')
                if json_start != -1 and json_end != -1:
                    output = output[json_start:json_end+1]
                self._send_json(json.loads(output))
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path == '/theme':
            theme_file = os.path.join(CONFIG_DIR, "theme.json")
            if os.path.exists(theme_file):
                try:
                    with open(theme_file, 'r') as f:
                        self._send_json(json.load(f))
                except:
                    self._send_json({})
            else:
                self._send_json({})
        elif self.path == '/master-update':
            try:
                def run_master_update():
                    try:
                        # 1. Start Logging
                        subprocess.run(['bash', '-c', f'echo \'{{"timestamp":"$(date +"%Y-%m-%d %H:%M:%S")","level":"INFO","category":"MAINTENANCE","message":"[Update Engine] Starting Master Update process."}}\' >> {HISTORY_LOG}'])
                        
                        # 2. Perform Full Backup
                        subprocess.run(['bash', '-c', f'echo \'{{"timestamp":"$(date +"%Y-%m-%d %H:%M:%S")","level":"INFO","category":"MAINTENANCE","message":"[Update Engine] Creating pre-update backup..."}}\' >> {HISTORY_LOG}'])
                        subprocess.run(["/usr/local/bin/migrate.sh", "all", "backup-all"], timeout=300)
                        
                        # 3. Trigger Watchtower for all images
                        subprocess.run(['bash', '-c', f'echo \'{{"timestamp":"$(date +"%Y-%m-%d %H:%M:%S")","level":"INFO","category":"MAINTENANCE","message":"[Update Engine] Pulling latest container images..."}}\' >> {HISTORY_LOG}'])
                        subprocess.run(['docker', 'run', '--rm', '-v', '/var/run/docker.sock:/var/run/docker.sock', 'containrrr/watchtower', '--run-once', '--cleanup'])
                        
                        # 4. Trigger source updates for all
                        src_root = "/app/sources"
                        if os.path.exists(src_root):
                            subprocess.run(['bash', '-c', f'echo \'{{"timestamp":"$(date +"%Y-%m-%d %H:%M:%S")","level":"INFO","category":"MAINTENANCE","message":"[Update Engine] Refreshing service source code..."}}\' >> {HISTORY_LOG}'])
                            for repo in os.listdir(src_root):
                                repo_path = os.path.join(src_root, repo)
                                if os.path.isdir(os.path.join(repo_path, ".git")):
                                    subprocess.run(["git", "fetch", "--all"], cwd=repo_path)
                        
                        subprocess.run(['bash', '-c', f'echo \'{{"timestamp":"$(date +"%Y-%m-%d %H:%M:%S")","level":"INFO","category":"MAINTENANCE","message":"[Update Engine] Master Update successfully completed."}}\' >> {HISTORY_LOG}'])
                    except Exception as e:
                        subprocess.run(['bash', '-c', f'echo \'{{"timestamp":"$(date +"%Y-%m-%d %H:%M:%S")","level":"ERROR","category":"MAINTENANCE","message":"[Update Engine] Master Update failed: {str(e)}"}}\' >> {HISTORY_LOG}'])

                import threading
                threading.Thread(target=run_master_update).start()
                self._send_json({"success": True, "message": "Master update process started in background"})
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path == '/check-updates':
            try:
                log_structured("INFO", "Checking for system-wide container and source updates...", "MAINTENANCE")
                # Trigger Watchtower run-once to check for image updates
                subprocess.Popen(['docker', 'run', '--rm', '-v', '/var/run/docker.sock:/var/run/docker.sock', 'containrrr/watchtower', '--run-once', '--cleanup', '--include-stopped'])
                # Also trigger git fetch for sources in background
                src_root = "/app/sources"
                if os.path.exists(src_root):
                    for repo in os.listdir(src_root):
                        repo_path = os.path.join(src_root, repo)
                        if os.path.isdir(os.path.join(repo_path, ".git")):
                            log_structured("INFO", f"Refreshing repository: {repo}", "MAINTENANCE")
                            subprocess.Popen(["git", "fetch"], cwd=repo_path)
                self._send_json({"success": True, "message": "Update check initiated in background"})
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path == '/updates':
            try:
                # Check for updates in source repositories
                src_root = "/app/sources"
                updates = {}
                if os.path.exists(src_root):
                    for repo in os.listdir(src_root):
                        repo_path = os.path.join(src_root, repo)
                        if os.path.isdir(os.path.join(repo_path, ".git")):
                            # Fetch remote and check status
                            subprocess.run(["git", "fetch"], cwd=repo_path, capture_output=True, timeout=15)
                            res = subprocess.run(["git", "status", "-uno"], cwd=repo_path, capture_output=True, text=True, timeout=10)
                            if "behind" in res.stdout:
                                updates[repo] = "Update Available"
                self._send_json({"updates": updates})
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path.startswith('/migrate'):
            try:
                # Usage: /migrate?service=invidious&backup=yes
                from urllib.parse import urlparse, parse_qs
                query = urlparse(self.path).query
                params = parse_qs(query)
                service = params.get('service', [''])[0]
                do_backup = params.get('backup', ['yes'])[0]
                if service:
                    res = subprocess.run(["/usr/local/bin/migrate.sh", service, "migrate", do_backup], capture_output=True, text=True, timeout=120)
                    self._send_json({"success": True, "output": res.stdout})
                else:
                    self._send_json({"error": "Service parameter missing"}, 400)
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path.startswith('/clear-db'):
            try:
                # Usage: /clear-db?service=invidious&backup=yes
                from urllib.parse import urlparse, parse_qs
                query = urlparse(self.path).query
                params = parse_qs(query)
                service = params.get('service', [''])[0]
                do_backup = params.get('backup', ['yes'])[0]
                if service:
                    res = subprocess.run(["/usr/local/bin/migrate.sh", service, "clear", do_backup], capture_output=True, text=True, timeout=120)
                    self._send_json({"success": True, "output": res.stdout})
                else:
                    self._send_json({"error": "Service parameter missing"}, 400)
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path.startswith('/clear-logs'):
            try:
                from urllib.parse import urlparse, parse_qs
                query = urlparse(self.path).query
                params = parse_qs(query)
                service = params.get('service', [''])[0]
                if service:
                    res = subprocess.run(["/usr/local/bin/migrate.sh", service, "clear-logs"], capture_output=True, text=True, timeout=60)
                    self._send_json({"success": True, "output": res.stdout})
                else:
                    self._send_json({"error": "Service parameter missing"}, 400)
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path.startswith('/vacuum'):
            try:
                from urllib.parse import urlparse, parse_qs
                query = urlparse(self.path).query
                params = parse_qs(query)
                service = params.get('service', [''])[0]
                if service:
                    res = subprocess.run(["/usr/local/bin/migrate.sh", service, "vacuum"], capture_output=True, text=True, timeout=60)
                    self._send_json({"success": True, "output": res.stdout})
                else:
                    self._send_json({"error": "Service parameter missing"}, 400)
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path == '/containers':
            try:
                # Get container IDs and labels
                result = subprocess.run(
                    ['docker', 'ps', '-a', '--no-trunc', '--format', '{{.Names}}\t{{.ID}}\t{{.Labels}}'],
                    capture_output=True, text=True, timeout=10
                )
                containers = {}
                for line in result.stdout.strip().split('\n'):
                    parts = line.split('\t')
                    if len(parts) >= 2:
                        name, cid = parts[0], parts[1]
                        labels = parts[2] if len(parts) > 2 else ""
                        is_hardened = "io.dhi.hardened=true" in labels
                        containers[name] = {"id": cid, "hardened": is_hardened}
                self._send_json({"containers": containers})
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path == '/services':
            try:
                self._send_json({"services": load_services()})
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path == '/certificate-status':
            try:
                cert_file = "/etc/adguard/conf/ssl.crt"
                status = {"type": "None", "subject": "--", "issuer": "--", "expires": "--", "status": "No Certificate"}
                if os.path.exists(cert_file):
                    res = subprocess.run(['openssl', 'x509', '-in', cert_file, '-noout', '-subject', '-issuer', '-dates'], capture_output=True, text=True)
                    if res.returncode == 0:
                        lines = res.stdout.split('\n')
                        status["type"] = "RSA/ECC"
                        for line in lines:
                            if line.startswith('subject='): status['subject'] = line.replace('subject=', '').strip()
                            if line.startswith('issuer='): status['issuer'] = line.replace('issuer=', '').strip()
                            if line.startswith('notAfter='): status['expires'] = line.replace('notAfter=', '').strip()
                        
                        # Check for self-signed
                        if status['subject'] == status['issuer'] or "PrivacyHub" in status['issuer']:
                            status["status"] = "Self-Signed (Local)"
                        else:
                            status["status"] = "Valid (Trusted)"
                
                # Check for acme.sh failure logs for more info
                log_file = "/etc/adguard/conf/certbot/last_run.log"
                if os.path.exists(log_file):
                    with open(log_file, 'r') as f:
                        log_content = f.read()
                        if "Verify error" in log_content or "Challenge failed" in log_content:
                            status["error"] = "deSEC verification failed. Check your token and domain."
                            status["status"] = "Issuance Failed"
                        elif "Rate limit" in log_content or "too many certificates" in log_content:
                            status["error"] = "Let's Encrypt rate limit reached. Retrying later."
                            status["status"] = "Rate Limited"
                        elif "Invalid token" in log_content:
                            status["error"] = "Invalid deSEC token."
                            status["status"] = "Auth Error"
                
                self._send_json(status)
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path.startswith('/logs'):
            try:
                from urllib.parse import urlparse, parse_qs
                query = urlparse(self.path).query
                params = parse_qs(query)
                level = params.get('level', [None])[0]
                category = params.get('category', [None])[0]
                
                conn = sqlite3.connect(DB_FILE)
                c = conn.cursor()
                sql = "SELECT timestamp, level, category, message FROM logs"
                args = []
                if level or category:
                    sql += " WHERE"
                    if level:
                        sql += " level = ?"
                        args.append(level)
                    if category:
                        if level: sql += " AND"
                        sql += " category = ?"
                        args.append(category)
                sql += " ORDER BY id DESC LIMIT 100"
                c.execute(sql, tuple(args))
                rows = c.fetchall()
                conn.close()
                
                logs = [{"timestamp": r[0], "level": r[1], "category": r[2], "message": r[3]} for r in rows]
                self._send_json({"logs": logs})
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path == '/metrics':
            try:
                conn = sqlite3.connect(DB_FILE)
                c = conn.cursor()
                # Get latest metrics for each container
                c.execute('''SELECT container, cpu_percent, mem_usage, mem_limit 
                             FROM metrics WHERE id IN (SELECT MAX(id) FROM metrics GROUP BY container)''')
                rows = c.fetchall()
                conn.close()
                metrics = {r[0]: {"cpu": r[1], "mem": r[2], "limit": r[3]} for r in rows}
                self._send_json({"metrics": metrics})
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path == '/config-desec' and self.command == 'POST':
            try:
                content_length = int(self.headers['Content-Length'])
                post_data = json.loads(self.rfile.read(content_length))
                domain = post_data.get('domain')
                token = post_data.get('token')
                
                if domain or token:
                    # Update .secrets or similar file
                    secrets_file = "/app/.secrets"
                    secrets = {}
                    if os.path.exists(secrets_file):
                        with open(secrets_file, 'r') as f:
                            for line in f:
                                if '=' in line:
                                    k, v = line.strip().split('=', 1)
                                    secrets[k] = v
                    
                    if domain: secrets['DESEC_DOMAIN'] = domain
                    if token: secrets['DESEC_TOKEN'] = token
                    
                    with open(secrets_file, 'w') as f:
                        for k, v in secrets.items():
                            f.write(f"{k}={v}\n")
                    
                    self._send_json({"success": True})
                else:
                    self._send_json({"error": "Missing domain or token"}, 400)
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path == '/profiles':
            try:
                files = [f.replace('.conf', '') for f in os.listdir(PROFILES_DIR) if f.endswith('.conf')]
                self._send_json({"profiles": files})
            except:
                self._send_json({"error": "Failed to list profiles"}, 500)
        elif self.path == '/events':
            self.send_response(200)
            self.send_header('Content-type', 'text/event-stream')
            self.send_header('Cache-Control', 'no-cache')
            self.send_header('Connection', 'keep-alive')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.send_header('X-Accel-Buffering', 'no')
            self.end_headers()
            try:
                for _ in range(10):
                    if os.path.exists(LOG_FILE):
                        break
                    time.sleep(1)
                if not os.path.exists(LOG_FILE):
                    self.wfile.write(b"data: Log file initializing...\n\n")
                    self.wfile.flush()
                f = open(LOG_FILE, 'r')
                f.seek(0, 2)
                # Send initial keepalive
                self.wfile.write(b": keepalive\n\n")
                self.wfile.flush()
                keepalive_counter = 0
                while True:
                    line = f.readline()
                    if line:
                        self.wfile.write(f"data: {line.strip()}\n\n".encode('utf-8'))
                        self.wfile.flush()
                        keepalive_counter = 0
                    else:
                        time.sleep(1)
                        keepalive_counter += 1
                        # Send keepalive comment every 15 seconds to prevent timeout
                        if keepalive_counter >= 15:
                            self.wfile.write(b": keepalive\n\n")
                            self.wfile.flush()
                            keepalive_counter = 0
            except (BrokenPipeError, ConnectionResetError):
                pass
            except Exception:
                pass

    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length).decode('utf-8')
        
        try:
            data = json.loads(post_data)
        except:
            data = {}

        if self.path == '/toggle-session-cleanup':
            global session_cleanup_enabled
            session_cleanup_enabled = data.get('enabled', True)
            self._send_json({"success": True, "enabled": session_cleanup_enabled})
            return

        if self.path == '/verify-admin':
            password = data.get('password')
            expected_admin = os.environ.get('ADMIN_PASS_RAW')
            if expected_admin and password == expected_admin:
                # Generate a new session token for this browser session
                token = secrets.token_hex(24)
                # Session expires in 30 minutes
                valid_sessions[token] = time.time() + 1800 
                self._send_json({"success": True, "token": token, "cleanup": session_cleanup_enabled})
            else:
                self._send_json({"error": "Invalid admin password"}, 401)
            return

        if not self._check_auth():
            self._send_json({"error": "Unauthorized"}, 401)
            return

        if self.path == '/watchtower' and self.command == 'POST':
            try:
                content_length = int(self.headers.get('Content-Length', 0))
                body = self.rfile.read(content_length).decode('utf-8')
                # Watchtower sends a JSON list of messages or a single message depending on template
                # We configured it with template=json, so we expect a JSON structure.
                # However, the generic webhook usually sends a simple JSON payload.
                # Let's just log it and mark updates as available.
                # Since we can't easily parse specific container names from standard generic webhooks reliably without a custom template,
                # we will just trigger a 'check-updates' logic or store a generic flag.
                # BUT, better yet, let's try to parse the message if possible.
                
                # To keep it robust: We will store "Image Updates Available" in a file that /updates can read.
                # Actually, /updates logic for images is tricky because we don't persist "pending updates" state for images easily
                # without querying the registry. Watchtower run-once in /check-updates does the checking.
                # If this webhook is called, it means Watchtower found something (if it's running in notification mode).
                
                # We will simply log the event for now as "Update Available"
                log_structured("INFO", f"Watchtower Notification: {body}", "MAINTENANCE")
                self._send_json({"success": True})
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
            return

        if self.path == '/theme':
            theme_file = os.path.join(CONFIG_DIR, "theme.json")
            try:
                with open(theme_file, 'w') as f:
                    json.dump(data, f)
                self._send_json({"success": True})
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path == '/upload':
            try:
                l = int(self.headers['Content-Length'])
                data = json.loads(self.rfile.read(l).decode('utf-8'))
                raw_name = data.get('name', '').strip()
                config = data.get('config')
                if not raw_name:
                    extracted = extract_profile_name(config)
                    raw_name = extracted if extracted else f"Imported_{int(time.time())}"
                safe = "".join([c for c in raw_name if c.isalnum() or c in ('-', '_', '#')])
                with open(os.path.join(PROFILES_DIR, f"{safe}.conf"), "w") as f:
                    f.write(config.replace('\r', ''))
                self._send_json({"success": True, "name": safe})
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path == '/activate':
            try:
                l = int(self.headers['Content-Length'])
                name = json.loads(self.rfile.read(l).decode('utf-8')).get('name')
                safe = "".join([c for c in name if c.isalnum() or c in ('-', '_', '#')])
                subprocess.run([CONTROL_SCRIPT, "activate", safe], check=True, timeout=60)
                self._send_json({"success": True})
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path == '/delete':
            try:
                l = int(self.headers['Content-Length'])
                name = json.loads(self.rfile.read(l).decode('utf-8')).get('name')
                safe = "".join([c for c in name if c.isalnum() or c in ('-', '_', '#')])
                subprocess.run([CONTROL_SCRIPT, "delete", safe], check=True, timeout=30)
                self._send_json({"success": True})
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path == '/restart-stack':
            try:
                # Trigger a full stack restart in the background
                log_structured("SYSTEM", "Full stack restart triggered via Dashboard", "ORCHESTRATION")
                
                # We use a detached process to avoid killing the API before it responds
                # The restart will take 20-30 seconds.
                subprocess.Popen(["/bin/sh", "-c", "sleep 2 && docker compose -f /app/docker-compose.yml restart"])
                self._send_json({"success": True, "message": "Stack restart initiated"})
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path == '/batch-update':
            try:
                l = int(self.headers['Content-Length'])
                data = json.loads(self.rfile.read(l).decode('utf-8'))
                services = data.get('services', [])
                if not services or not isinstance(services, list):
                    self._send_json({"error": "List of services required"}, 400)
                    return

                def run_batch_update(svc_list):
                    try:
                        log_structured("INFO", f"[Update Engine] Starting batch update for {len(svc_list)} services...", "MAINTENANCE")
                        for name in svc_list:
                            try:
                                log_structured("INFO", f"[Update Engine] Processing {name}...", "MAINTENANCE")
                                
                                # 1. Backup
                                subprocess.run(["/usr/local/bin/migrate.sh", name, "backup", "yes"], timeout=120)
                                
                                # 2. Refresh source
                                repo_path = f"/app/sources/{name}"
                                if os.path.exists(repo_path) and os.path.isdir(os.path.join(repo_path, ".git")):
                                    log_structured("INFO", f"[Update Engine] Pulling latest source for {name}...", "MAINTENANCE")
                                    subprocess.run(["git", "fetch", "--all"], cwd=repo_path, check=True, timeout=60)
                                    subprocess.run(["git", "reset", "--hard", "origin/master"], cwd=repo_path, timeout=30) # Try master
                                    subprocess.run(["git", "reset", "--hard", "origin/main"], cwd=repo_path, timeout=30)   # Try main
                                    subprocess.run(["git", "pull"], cwd=repo_path, check=True, timeout=60)
                                    if os.path.exists("/app/patches.sh"):
                                        subprocess.run(["/app/patches.sh", name], check=True, timeout=30)
                                
                                # 3. Rebuild and restart
                                log_structured("INFO", f"[Update Engine] Rebuilding {name}...", "MAINTENANCE")
                                subprocess.run(['docker', 'compose', '-f', '/app/docker-compose.yml', 'up', '-d', '--build', name], timeout=600)
                                
                                # 4. Migrate
                                log_structured("INFO", f"[Update Engine] Running migrations for {name}...", "MAINTENANCE")
                                subprocess.run(["/usr/local/bin/migrate.sh", name, "migrate", "no"], timeout=120) # No backup needed, just done
                                
                                # 5. Vacuum
                                log_structured("INFO", f"[Update Engine] Optimizing database for {name}...", "MAINTENANCE")
                                subprocess.run(["/usr/local/bin/migrate.sh", name, "vacuum"], timeout=60)
                                
                                log_structured("INFO", f"[Update Engine] {name} update complete.", "MAINTENANCE")
                            except Exception as ex:
                                log_structured("ERROR", f"[Update Engine] Failed to update {name}: {str(ex)}", "MAINTENANCE")
                        
                        log_structured("INFO", "[Update Engine] Batch update finished.", "MAINTENANCE")
                    except Exception as e:
                        log_structured("ERROR", f"[Update Engine] Batch update crashed: {str(e)}", "MAINTENANCE")

                import threading
                threading.Thread(target=run_batch_update, args=(services,)).start()
                self._send_json({"success": True, "message": "Batch update started in background"})
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path == '/update-service':
            try:
                l = int(self.headers['Content-Length'])
                data = json.loads(self.rfile.read(l).decode('utf-8'))
                service = data.get('service')
                if not service:
                    self._send_json({"error": "Service name required"}, 400)
                    return
                
                def run_service_update(name):
                    try:
                        subprocess.run(['bash', '-c', f'echo \'{{"timestamp":"$(date +"%Y-%m-%d %H:%M:%S")","level":"INFO","category":"MAINTENANCE","message":"[Update Engine] Starting update for {name}..."}}\' >> {HISTORY_LOG}'])
                        # 1. Pre-update Backup
                        subprocess.run(['bash', '-c', f'echo \'{{"timestamp":"$(date +"%Y-%m-%d %H:%M:%S")","level":"INFO","category":"MAINTENANCE","message":"[Update Engine] Creating safety backup for {name}..."}}\' >> {HISTORY_LOG}'])
                        subprocess.run(["/usr/local/bin/migrate.sh", name, "backup"], timeout=120)
                        
                        # 2. Refresh source
                        repo_path = f"/app/sources/{name}"
                        if os.path.exists(repo_path) and os.path.isdir(os.path.join(repo_path, ".git")):
                            subprocess.run(["git", "reset", "--hard"], cwd=repo_path, check=True, timeout=30)
                            subprocess.run(["git", "pull"], cwd=repo_path, check=True, timeout=60)
                            if os.path.exists("/app/patches.sh"):
                                subprocess.run(["/app/patches.sh", name], check=True, timeout=30)
                        
                        # 3. Rebuild and restart
                        subprocess.run(['bash', '-c', f'echo \'{{"timestamp":"$(date +"%Y-%m-%d %H:%M:%S")","level":"INFO","category":"MAINTENANCE","message":"[Update Engine] Build process for {name} initiated (Expect increased resource usage)."}}\' >> {HISTORY_LOG}'])
                        subprocess.run(['docker', 'compose', '-f', '/app/docker-compose.yml', 'up', '-d', '--build', name], timeout=600)
                        subprocess.run(['bash', '-c', f'echo \'{{"timestamp":"$(date +"%Y-%m-%d %H:%M:%S")","level":"INFO","category":"MAINTENANCE","message":"[Update Engine] {name} update completed successfully."}}\' >> {HISTORY_LOG}'])
                    except Exception as ex:
                        subprocess.run(['bash', '-c', f'echo \'{{"timestamp":"$(date +"%Y-%m-%d %H:%M:%S")","level":"ERROR","category":"MAINTENANCE","message":"[Update Engine] {name} update failed: {str(ex)}"}}\' >> {HISTORY_LOG}'])

                import threading
                threading.Thread(target=run_service_update, args=(service,)).start()
                self._send_json({"success": True, "message": f"Update for {service} started in background"})
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path == '/rotate-api-key' and self.command == 'POST':
            try:
                content_length = int(self.headers['Content-Length'])
                post_data = json.loads(self.rfile.read(content_length))
                new_key = post_data.get('new_key')
                if new_key:
                    secrets_file = "/app/.secrets"
                    secrets = {}
                    if os.path.exists(secrets_file):
                        with open(secrets_file, 'r') as f:
                            for line in f:
                                if '=' in line:
                                    k, v = line.strip().split('=', 1)
                                    secrets[k] = v
                    secrets['HUB_API_KEY'] = new_key
                    with open(secrets_file, 'w') as f:
                        for k, v in secrets.items():
                            f.write(f"{k}={v}\n")
                    
                    log_structured("SECURITY", "Dashboard API key rotated", "AUTH")
                    self._send_json({"success": True})
                else:
                    self._send_json({"error": "New key required"}, 400)
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path.startswith('/changelog'):
            try:
                from urllib.parse import urlparse, parse_qs
                query = urlparse(self.path).query
                params = parse_qs(query)
                service = params.get('service', [''])[0]
                
                if not service:
                    self._send_json({"error": "Service required"}, 400)
                    return

                SERVICE_REPOS = {
                    "adguard": {"repo": "AdguardTeam/AdGuardHome", "type": "github"},
                    "portainer": {"repo": "portainer/portainer", "type": "github"},
                    "wg-easy": {"repo": "wg-easy/wg-easy", "type": "github"},
                    "redlib": {"repo": "redlib-org/redlib", "type": "github"},
                    "gluetun": {"repo": "qdm12/gluetun", "type": "github"},
                    "anonymousoverflow": {"repo": "httpjamesm/AnonymousOverflow", "type": "github"},
                    "rimgo": {"repo": "rimgo/rimgo", "type": "codeberg"},
                    "memos": {"repo": "usememos/memos", "type": "github"},
                    "watchtower": {"repo": "containrrr/watchtower", "type": "github"},
                    "unbound": {"repo": "klutchell/unbound", "type": "github"},
                    "vertd": {"repo": "VERT-sh/vertd", "type": "github"}
                }

                # Check if it's a source-based service
                repo_path = f"/app/sources/{service}"
                if os.path.exists(repo_path) and os.path.isdir(os.path.join(repo_path, ".git")):
                    # Fetch first
                    subprocess.run(["git", "fetch"], cwd=repo_path, timeout=15)
                    branch = "origin/master"
                    if subprocess.run(["git", "rev-parse", "--verify", "origin/main"], cwd=repo_path).returncode == 0:
                        branch = "origin/main"
                    
                    res = subprocess.run(
                        ["git", "log", "--pretty=format:%h - %s (%cr)", f"HEAD..{branch}"], 
                        cwd=repo_path, capture_output=True, text=True, timeout=5
                    )
                    
                    if res.returncode == 0 and res.stdout.strip():
                        self._send_json({"changelog": res.stdout})
                    else:
                        self._send_json({"changelog": "No new commits found in source repo."})
                
                # Check if it's a known image-based service
                elif service in SERVICE_REPOS:
                    meta = SERVICE_REPOS[service]
                    try:
                        url = ""
                        if meta["type"] == "github":
                            url = f"https://api.github.com/repos/{meta['repo']}/releases/latest"
                        elif meta["type"] == "codeberg":
                            url = f"https://codeberg.org/api/v1/repos/{meta['repo']}/releases/latest"
                        
                        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"})
                        opener = get_proxy_opener()
                        with opener.open(req, timeout=10) as resp:
                            data = json.loads(resp.read().decode())
                            body = data.get("body", "No description available.")
                            name = data.get("name") or data.get("tag_name") or "Latest Release"
                            self._send_json({"changelog": f"## {name}\n\n{body}"})
                    except Exception as e:
                        self._send_json({"changelog": f"Failed to fetch release notes: {str(e)}"})
                else:
                    self._send_json({"changelog": "Changelog not available for this service."})
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        elif self.path == '/odido-userid':
            try:
                l = int(self.headers['Content-Length'])
                data = json.loads(self.rfile.read(l).decode('utf-8'))
                oauth_token = data.get('oauth_token', '').strip()
                if not oauth_token:
                    self._send_json({"error": "oauth_token is required"}, 400)
                    return
                # Use curl to fetch the User ID from Odido API
                result = subprocess.run([
                    'curl', '-sL', '-o', '/dev/null', '-w', '%{url_effective}',
                    '-H', f'Authorization: Bearer {oauth_token}',
                    '-H', 'User-Agent: T-Mobile 5.3.28 (Android 10; 10)',
                    'https://capi.odido.nl/account/current'
                ], capture_output=True, text=True, timeout=30)
                redirect_url = result.stdout.strip()
                # Extract 12-character hex User ID from URL (case-insensitive)
                match = re.search(r'capi\.odido\.nl/([0-9a-fA-F]{12})', redirect_url, re.IGNORECASE)
                if match:
                    user_id = match.group(1)
                    self._send_json({"success": True, "user_id": user_id})
                else:
                    # Fallback: extract first path segment after capi.odido.nl/
                    match = re.search(r'capi\.odido\.nl/([^/]+)/', redirect_url, re.IGNORECASE)
                    if match and match.group(1).lower() != 'account':
                        user_id = match.group(1)
                        self._send_json({"success": True, "user_id": user_id})
                    else:
                        self._send_json({"error": "Could not extract User ID from Odido API response", "url": redirect_url}, 400)
            except Exception as e:
                self._send_json({"error": str(e)}, 500)

if __name__ == "__main__":
    print(f"Starting API server on port {PORT}...")
    init_db()

    # Wait for Gluetun proxy to be ready
    print("Waiting for proxy...", flush=True)
    proxy_ready = False
    for _ in range(60):
        try:
            with socket.create_connection(("gluetun", 8888), timeout=2):
                proxy_ready = True
                break
        except (OSError, ConnectionRefusedError):
            time.sleep(2)
    
    if proxy_ready:
        print("Proxy available. Syncing assets...", flush=True)
        try:
            ensure_assets()
        except Exception as e:
            log_structured("WARN", f"Asset sync failed: {e}", "FONTS")
    else:
        log_structured("WARN", "Proxy unavailable after 60s. Asset sync skipped.", "FONTS")
    
    # Start metrics collector thread
    t = threading.Thread(target=metrics_collector, daemon=True)
    t.start()
    
    if not os.path.exists(LOG_FILE):
        os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
        open(LOG_FILE, 'a').close()
    with ThreadingHTTPServer(("", PORT), APIHandler) as httpd:
        print(f"API server running on port {PORT}")
        httpd.serve_forever()
APIEOF
chmod +x "$WG_API_SCRIPT"

# --- SECTION 13: ORCHESTRATION LAYER (DOCKER COMPOSE) ---
# Compile the unified multi-container definition for the complete privacy stack.
log_info "Compiling Orchestration Layer (docker-compose.yml)..."

# Helper function to check if a service should be deployed
should_deploy() {
    local srv=$1
    if [ -z "$SELECTED_SERVICES" ]; then return 0; fi
    # Core infrastructure always deployed
    if [[ "$srv" =~ ^(hub-api|gluetun|dashboard|adguard|unbound|watchtower|wg-easy)$ ]]; then return 0; fi
    # Dependencies
    if [[ "$srv" == "invidious-db" || "$srv" == "companion" ]]; then srv="invidious"; fi
    if [[ "$srv" == "wikiless_redis" ]]; then srv="wikiless"; fi
    if [[ "$srv" == "vertd" ]]; then srv="vert"; fi
    # Check if in selected list
    if [[ ",$SELECTED_SERVICES," == *",$srv,"* ]]; then return 0; fi
    return 1
}

VERTD_DEVICES=""
# Hardware acceleration detection (Independent checks for Intel/AMD and NVIDIA)
if [ -d "/dev/dri" ]; then
    VERTD_DEVICES="    devices:
      - /dev/dri"
    if [ -d "/dev/vulkan" ]; then
        VERTD_DEVICES="${VERTD_DEVICES}
      - /dev/vulkan"
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
      ],
      "chips": ["Direct Access"]
    },
    "vert": {
      "name": "VERT",
      "description": "Local file conversion service. Maintains data autonomy by processing sensitive documents on your own hardware using GPU acceleration.",
      "category": "tools",
      "order": 10,
      "url": "http://$LAN_IP:$PORT_VERT",
      "chips": [
        "Utility",
        {
          "label": "GPU Accelerated",
          "icon": "memory",
          "variant": "tertiary",
          "tooltip": "Utilizes local GPU (/dev/dri) for high-performance conversion",
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
      "chips": ["Local Access", "Encrypted DNS"]
    },
    "portainer": {
      "name": "Portainer",
      "description": "A comprehensive management interface for the Docker environment. Facilitates granular control over container orchestration and infrastructure lifecycle management.",
      "category": "system",
      "order": 20,
      "url": "http://$LAN_IP:$PORT_PORTAINER",
      "chips": ["Local Access"]
    },
    "wg-easy": {
      "name": "WireGuard",
      "description": "The primary gateway for secure remote access. Provides a cryptographically sound tunnel to your home network, maintaining your privacy boundary on external networks.",
      "category": "system",
      "order": 30,
      "url": "http://$LAN_IP:$PORT_WG_WEB",
      "chips": ["Local Access"]
    }
  }
}
EOF
chmod 666 "$SERVICES_JSON"

cat > "$COMPOSE_FILE" <<EOF
networks:
  frontnet:
    driver: bridge
    ipam:
      config:
        - subnet: $DOCKER_SUBNET

services:
EOF

if should_deploy "hub-api"; then
cat >> "$COMPOSE_FILE" <<EOF
  hub-api:
    build:
      context: $SRC_DIR/hub-api
      dockerfile: $HUB_API_DOCKERFILE
    container_name: hub-api
    labels:
      - "casaos.skip=true"
      - "com.centurylinklabs.watchtower.enable=false"
      - "io.dhi.hardened=true"
    networks: [frontnet]
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
      - "$WG_API_SCRIPT:/app/server.py"
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
      - DOCKER_CONFIG=/root/.docker
    entrypoint: ["/bin/sh", "-c", "mkdir -p /app && touch /app/deployment.log /app/.data_usage /app/.wge_data_usage && python3 -u /app/server.py"]
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
cat >> "$COMPOSE_FILE" <<EOF
  odido-booster:
    build:
      context: $SRC_DIR/odido-bundle-booster
      dockerfile: $ODIDO_DOCKERFILE
    container_name: odido-booster
    labels:
      - "com.centurylinklabs.watchtower.enable=false"
      - "io.dhi.hardened=true"
    networks: [frontnet]
    ports: ["$LAN_IP:8085:8080"]
    environment:
      - API_KEY=$ODIDO_API_KEY
      - ODIDO_USER_ID=$ODIDO_USER_ID
      - ODIDO_TOKEN=$ODIDO_TOKEN
      - PORT=8080
    volumes:
      - $DATA_DIR/odido:/data
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '0.3', memory: 128M}
EOF
fi

if should_deploy "watchtower"; then
cat >> "$COMPOSE_FILE" <<EOF
  watchtower:
    image: containrrr/watchtower
    container_name: watchtower
    labels:
      - "casaos.skip=true"
    networks: [frontnet]
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    command: >
      --schedule "0 0 3 * * *"
      --cleanup
      --include-stopped
      --disable-containers watchtower
      --notification-url "generic://hub-api:55555/watchtower?template=json&disabletls=yes"
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '0.2', memory: 128M}
EOF
fi

if should_deploy "memos"; then
cat >> "$COMPOSE_FILE" <<EOF
  memos:
    image: neosmemo/memos:stable
    container_name: memos
    labels:
      - "io.dhi.hardened=true"
    networks: [frontnet]
    ports: ["$LAN_IP:$PORT_MEMOS:5230"]
    volumes: ["$MEMOS_HOST_DIR:/var/opt/memos"]
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '0.5', memory: 256M}
EOF
fi

if should_deploy "gluetun"; then
cat >> "$COMPOSE_FILE" <<EOF
  gluetun:
    image: qmcgaw/gluetun
    container_name: gluetun
    labels:
      - "casaos.skip=true"
    cap_add: [NET_ADMIN]
    sysctls:
      - net.ipv4.conf.all.src_valid_mark=1
      - net.ipv4.ip_forward=1
    devices:
      - /dev/net/tun:/dev/net/tun
    networks: [frontnet]
    ports:
      - "$LAN_IP:$PORT_REDLIB:$PORT_INT_REDLIB/tcp"
      - "$LAN_IP:$PORT_WIKILESS:$PORT_INT_WIKILESS/tcp"
      - "$LAN_IP:$PORT_INVIDIOUS:$PORT_INT_INVIDIOUS/tcp"
      - "$LAN_IP:$PORT_RIMGO:$PORT_INT_RIMGO/tcp"
      - "$LAN_IP:$PORT_SCRIBE:$PORT_SCRIBE/tcp"
      - "$LAN_IP:$PORT_BREEZEWIKI:$PORT_INT_BREEZEWIKI/tcp"
      - "$LAN_IP:$PORT_ANONYMOUS:$PORT_INT_ANONYMOUS/tcp"
    volumes:
      - "$ACTIVE_WG_CONF:/gluetun/wireguard/wg0.conf:ro"
    env_file:
      - "$GLUETUN_ENV_FILE"
    healthcheck:
      # Check both the control server and actual VPN tunnel connectivity
      test: ["CMD-SHELL", "wget --user=gluetun --password=$ADMIN_PASS_RAW -qO- http://127.0.0.1:8000/v1/vpn/status | grep -q '\"status\":\"running\"' && wget -U \"Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36\" --spider -q --timeout=5 http://connectivity-check.ubuntu.com || exit 1"]
      interval: 1m
      timeout: 10s
      retries: 3
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '2.0', memory: 512M}
EOF
fi

if should_deploy "dashboard"; then
cat >> "$COMPOSE_FILE" <<EOF
  dashboard:
    image: nginx:alpine
    container_name: dashboard
    networks: [frontnet]
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
cat >> "$COMPOSE_FILE" <<EOF
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    command: ["-H", "unix:///var/run/docker.sock", "--admin-password", "$PORTAINER_HASH_COMPOSE", "--no-analytics"]
    networks: [frontnet]
    ports: ["$LAN_IP:$PORT_PORTAINER:9000"]
    volumes: ["/var/run/docker.sock:/var/run/docker.sock", "$DATA_DIR/portainer:/data"]
    # Admin password is saved in protonpass_import.csv for initial setup
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '0.5', memory: 512M}
EOF
fi

if should_deploy "adguard"; then
cat >> "$COMPOSE_FILE" <<EOF
  adguard:
    image: adguard/adguardhome:latest
    container_name: adguard
    labels:
      - "io.dhi.hardened=true"
    networks: [frontnet]
    ports:
      - "$LAN_IP:53:53/udp"
      - "$LAN_IP:53:53/tcp"
      - "$LAN_IP:$PORT_ADGUARD_WEB:$PORT_ADGUARD_WEB/tcp"
      - "$LAN_IP:443:443/tcp"
      - "$LAN_IP:443:443/udp"
      - "$LAN_IP:853:853/tcp"
      - "$LAN_IP:853:853/udp"
    volumes: ["$DATA_DIR/adguard-work:/opt/adguardhome/work", "$AGH_CONF_DIR:/opt/adguardhome/conf"]
    depends_on:
      - unbound
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '0.5', memory: 512M}
EOF
fi

if should_deploy "unbound"; then
cat >> "$COMPOSE_FILE" <<EOF
  unbound:
    image: klutchell/unbound:latest
    container_name: unbound
    labels:
      - "io.dhi.hardened=true"
    networks:
      frontnet:
        ipv4_address: 172.20.0.250
    volumes:
      - "$UNBOUND_CONF:/opt/unbound/etc/unbound/unbound.conf:ro"
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '0.5', memory: 256M}
EOF
fi

if should_deploy "wg-easy"; then
cat >> "$COMPOSE_FILE" <<EOF
  # WG-Easy: Remote access VPN server (only 51820/UDP exposed to internet)
  wg-easy:
    image: ghcr.io/wg-easy/wg-easy:latest
    container_name: wg-easy
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
cat >> "$COMPOSE_FILE" <<EOF
  redlib:
    image: quay.io/redlib/redlib:latest
    container_name: redlib
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
cat >> "$COMPOSE_FILE" <<EOF
  wikiless:
    build:
      context: "$SRC_DIR/wikiless"
      dockerfile: $WIKILESS_DOCKERFILE
    container_name: wikiless
    labels:
      - "com.centurylinklabs.watchtower.enable=false"
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
    image: redis:7.2
    container_name: wikiless_redis
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
cat >> "$COMPOSE_FILE" <<EOF
  invidious:
    build:
      context: "$SRC_DIR/invidious"
      dockerfile: $INVIDIOUS_DOCKERFILE
    container_name: invidious
    labels:
      - "com.centurylinklabs.watchtower.enable=false"
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
    image: postgres:14-alpine
    container_name: invidious-db
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
    image: quay.io/invidious/invidious-companion:latest
    container_name: companion
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
cat >> "$COMPOSE_FILE" <<EOF
  rimgo:
    image: codeberg.org/rimgo/rimgo:latest
    pull_policy: if_not_present
    container_name: rimgo
    labels:
      - "io.dhi.hardened=true"
    network_mode: "service:gluetun"
    environment: {IMGUR_CLIENT_ID: "546c25a59c58ad7", ADDRESS: "0.0.0.0", PORT: "$PORT_INT_RIMGO"}
    depends_on: {gluetun: {condition: service_healthy}}
    restart: always
    deploy:
      resources:
        limits: {cpus: '0.5', memory: 256M}
EOF
fi

if should_deploy "breezewiki"; then
cat >> "$COMPOSE_FILE" <<EOF
  breezewiki:
    build:
      context: $SRC_DIR/breezewiki
      dockerfile: Dockerfile.alpine
    container_name: breezewiki
    labels:
      - "io.dhi.hardened=true"
    network_mode: "service:gluetun"
    environment:
      - bw_bind_host=0.0.0.0
      - bw_port=$PORT_INT_BREEZEWIKI
      - bw_canonical_origin=http://$LAN_IP:$PORT_BREEZEWIKI
      - bw_debug=false
      - bw_feature_search_suggestions=true
      - bw_strict_proxy=true
    healthcheck:
      test: ["CMD-SHELL", "wget --spider -q http://127.0.0.1:$PORT_INT_BREEZEWIKI/ || exit 1"]
      interval: 1m
      timeout: 5s
      retries: 3
    depends_on: {gluetun: {condition: service_healthy}}
    restart: always
    deploy:
      resources:
        limits: {cpus: '0.5', memory: 1024M}
EOF
fi

if should_deploy "anonymousoverflow"; then
cat >> "$COMPOSE_FILE" <<EOF
  anonymousoverflow:
    image: ghcr.io/httpjamesm/anonymousoverflow:release
    container_name: anonymousoverflow
    labels:
      - "io.dhi.hardened=true"
    network_mode: "service:gluetun"
    env_file: ["./env/anonymousoverflow.env"]
    environment: {PORT: "$PORT_INT_ANONYMOUS"}
    depends_on: {gluetun: {condition: service_healthy}}
    restart: always
    deploy:
      resources:
        limits: {cpus: '0.5', memory: 256M}
EOF
fi

if should_deploy "scribe"; then
cat >> "$COMPOSE_FILE" <<EOF
  scribe:
    build:
      context: "$SRC_DIR/scribe"
      dockerfile: $SCRIBE_DOCKERFILE
    labels:
      - "com.centurylinklabs.watchtower.enable=false"
      - "io.dhi.hardened=true"
    network_mode: "service:gluetun"
    env_file: ["./env/scribe.env"]
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
cat >> "$COMPOSE_FILE" <<EOF
  # VERT: Local file conversion service
  vertd:
    container_name: vertd
    image: ghcr.io/vert-sh/vertd:latest
    networks: [frontnet]
    ports: ["$LAN_IP:$PORT_VERTD:$PORT_INT_VERTD"]
    labels:
      - "casaos.skip=true"
      - "io.dhi.hardened=true"
    environment:
      - PUBLIC_URL=$VERTD_PUB_URL
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
    container_name: vert
    build:
      context: "$SRC_DIR/vert"
      dockerfile: $VERT_DOCKERFILE
    labels:
      - "casaos.skip=true"
      - "com.centurylinklabs.watchtower.enable=false"
      - "io.dhi.hardened=true"
    environment:
      - PUB_HOSTNAME=$VERT_PUB_HOSTNAME
      - PUB_PLAUSIBLE_URL=
      - PUB_ENV=production
      - PUB_DISABLE_ALL_EXTERNAL_REQUESTS=true
      - PUB_DISABLE_FAILURE_BLOCKS=true
      - PUB_VERTD_URL=$VERTD_PUB_URL
      - PUB_DONATION_URL=
      - PUB_STRIPE_KEY=
      - PUB_DISABLE_DONATIONS=true
    networks: [frontnet]
    ports: ["$LAN_IP:$PORT_VERT:$PORT_INT_VERT"]
    depends_on:
      vertd: {condition: service_started}
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '0.5', memory: 256M}
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
      \(Invidious, Redlib, etc.\) that reduce tracking and prevent home IP exposure.
  icon: http://$LAN_IP:8081/assets/privacy-hub.svg
EOF

# --- SECTION 14: DASHBOARD & UI GENERATION ---

# --- SECTION 15: BACKGROUND DAEMONS & PROACTIVE MONITORING ---
# Initialize automated background tasks for SSL renewal and Dynamic DNS updates.
if [ -n "$DESEC_DOMAIN" ] && [ -n "$DESEC_TOKEN" ]; then
    DESEC_MONITOR_DOMAIN="$DESEC_DOMAIN"
    DESEC_MONITOR_TOKEN="$DESEC_TOKEN"
else
    DESEC_MONITOR_DOMAIN=""
    DESEC_MONITOR_TOKEN=""
fi

cat > "$CERT_MONITOR_SCRIPT" <<EOF
#!/usr/bin/env bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
AGH_CONF_DIR="$AGH_CONF_DIR"
DESEC_TOKEN="$DESEC_MONITOR_TOKEN"
DESEC_DOMAIN="$DESEC_DOMAIN"
COMPOSE_FILE="$COMPOSE_FILE"
LAN_IP="$LAN_IP"
PORT_DASHBOARD_WEB="$PORT_DASHBOARD_WEB"
DOCKER_AUTH_DIR="$DOCKER_AUTH_DIR"
DOCKER_CMD="sudo env DOCKER_CONFIG=\$DOCKER_AUTH_DIR docker"
LOG_FILE="\$AGH_CONF_DIR/certbot/monitor.log"
LOCK_FILE="\$AGH_CONF_DIR/certbot/monitor.lock"
EOF

cat >> "$CERT_MONITOR_SCRIPT" <<'EOF'
# Use flock to prevent concurrent runs
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    exit 0
fi

if [ -z "$DESEC_DOMAIN" ]; then exit 0; fi

# Auto-detect if action is needed:
# - Certificate file is missing
# - Certificate is self-signed (not Let's Encrypt)
# - Certificate expires in less than 30 days
NEEDS_ACTION=false
if [ ! -f "$AGH_CONF_DIR/ssl.crt" ]; then
    NEEDS_ACTION=true
elif ! grep -qE "Let's Encrypt|R3|ISRG" "$AGH_CONF_DIR/ssl.crt"; then
    NEEDS_ACTION=true
elif ! $DOCKER_CMD run --rm \
    -v "$AGH_CONF_DIR:/certs" \
    neilpang/acme.sh:latest /bin/sh -c \
    "openssl x509 -checkend 2592000 -noout -in /certs/ssl.crt" >/dev/null 2>&1; then
    NEEDS_ACTION=true
fi

if [ "$NEEDS_ACTION" = false ]; then
    exit 0
fi

# Check if we should wait due to previous rate limit failure
CERT_LOG_FILE="$AGH_CONF_DIR/certbot/last_run.log"
if [ -f "$CERT_LOG_FILE" ]; then
    RETRY_TIME=$(grep -oiE 'retry after [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]+ UTC' "$CERT_LOG_FILE" | head -1 | sed 's/retry after //I')
    if [ -n "$RETRY_TIME" ]; then
        RETRY_EPOCH=$(date -u -d "$RETRY_TIME" +%s 2>/dev/null || echo "")
        NOW_EPOCH=$(date -u +%s)
        if [ -n "$RETRY_EPOCH" ] && [ "$NOW_EPOCH" -lt "$RETRY_EPOCH" ]; then
            # Still in rate limit window
            exit 0
        fi
    fi
fi

echo "$(date) [INFO] Auto-detected that certificate requires attention (recovery/renewal)." >> "$LOG_FILE"

# Attempt Let's Encrypt
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
    -d "$DESEC_DOMAIN" \
    -d "*.$DESEC_DOMAIN" \
    --keylength ec-256 \
    --server letsencrypt \
    --home /acme \
    --config-home /acme \
    --cert-home /acme/certs \
    --force > "$CERT_TMP_OUT" 2>&1; then
    
    if [ -f "$AGH_CONF_DIR/certs/${DESEC_DOMAIN}_ecc/fullchain.cer" ]; then
        cp "$AGH_CONF_DIR/certs/${DESEC_DOMAIN}_ecc/fullchain.cer" "$AGH_CONF_DIR/ssl.crt"
        cp "$AGH_CONF_DIR/certs/${DESEC_DOMAIN}_ecc/${DESEC_DOMAIN}.key" "$AGH_CONF_DIR/ssl.key"
        
        # Update docker-compose metadata for CasaOS dashboard transition to HTTPS/Domain
        if [ -f "$COMPOSE_FILE" ]; then
            sed -i "s|dev.casaos.app.ui.protocol=http|dev.casaos.app.ui.protocol=https|g" "$COMPOSE_FILE"
            sed -i "s|dev.casaos.app.ui.port=$PORT_DASHBOARD_WEB|dev.casaos.app.ui.port=8443|g" "$COMPOSE_FILE"
            sed -i "s|dev.casaos.app.ui.hostname=$LAN_IP|dev.casaos.app.ui.hostname=$DESEC_DOMAIN|g" "$COMPOSE_FILE"
            sed -i "s|scheme: http|scheme: https|g" "$COMPOSE_FILE"
            $DOCKER_CMD compose -f "$COMPOSE_FILE" up -d --no-deps dashboard
        fi

        $DOCKER_CMD restart adguard
        $DOCKER_CMD restart dashboard
        echo "$(date) [INFO] Successfully updated Let's Encrypt certificate and synchronized dashboard config." >> "$LOG_FILE"
    elif [ -f "$AGH_CONF_DIR/certs/${DESEC_DOMAIN}/fullchain.cer" ]; then
        cp "$AGH_CONF_DIR/certs/${DESEC_DOMAIN}/fullchain.cer" "$AGH_CONF_DIR/ssl.crt"
        cp "$AGH_CONF_DIR/certs/${DESEC_DOMAIN}/${DESEC_DOMAIN}.key" "$AGH_CONF_DIR/ssl.key"

        # Update docker-compose metadata for CasaOS dashboard transition to HTTPS/Domain
        if [ -f "$COMPOSE_FILE" ]; then
            sed -i "s|dev.casaos.app.ui.protocol=http|dev.casaos.app.ui.protocol=https|g" "$COMPOSE_FILE"
            sed -i "s|dev.casaos.app.ui.port=$PORT_DASHBOARD_WEB|dev.casaos.app.ui.port=8443|g" "$COMPOSE_FILE"
            sed -i "s|dev.casaos.app.ui.hostname=$LAN_IP|dev.casaos.app.ui.hostname=$DESEC_DOMAIN|g" "$COMPOSE_FILE"
            sed -i "s|scheme: http|scheme: https|g" "$COMPOSE_FILE"
            $DOCKER_CMD compose -f "$COMPOSE_FILE" up -d --no-deps dashboard
        fi

        $DOCKER_CMD restart adguard
        $DOCKER_CMD restart dashboard
        echo "$(date) [INFO] Successfully updated Let's Encrypt certificate and synchronized dashboard config." >> "$LOG_FILE"
    fi
else
    cat "$CERT_TMP_OUT" > "$CERT_LOG_FILE"
    echo "$(date) [WARN] Let's Encrypt attempt failed. Will retry later." >> "$LOG_FILE"
fi
rm -f "$CERT_TMP_OUT"
EOF
chmod +x "$CERT_MONITOR_SCRIPT"
EXISTING_CRON=$(crontab -l 2>/dev/null || true)
echo "$EXISTING_CRON" | grep -v "$CERT_MONITOR_SCRIPT" | { cat; echo "*/5 * * * * $CERT_MONITOR_SCRIPT"; } | crontab -

# --- SECTION 15.1: DYNAMIC IP AUTOMATION ---
# Detect public IP changes and synchronize DNS records and VPN endpoints.
cat > "$MONITOR_SCRIPT" <<EOF
#!/usr/bin/env bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
COMPOSE_FILE="$COMPOSE_FILE"
CURRENT_IP_FILE="$CURRENT_IP_FILE"
LOG_FILE="$IP_LOG_FILE"
LOCK_FILE="$BASE_DIR/.ip-monitor.lock"
DESEC_DOMAIN="$DESEC_MONITOR_DOMAIN"
DESEC_TOKEN="$DESEC_MONITOR_TOKEN"
DOCKER_CONFIG="$DOCKER_AUTH_DIR"
export DOCKER_CONFIG
EOF

cat >> "$MONITOR_SCRIPT" <<'EOF'
# Use flock to prevent concurrent runs
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    exit 0
fi

NEW_IP=$(curl -s --max-time 5 https://api.ipify.org || curl -s --max-time 5 https://ip-api.com/line?fields=query || echo "FAILED")

if [[ ! "$NEW_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "$(date) [ERROR] Failed to get valid public IP (Response: $NEW_IP)" >> "$LOG_FILE"
    exit 1
fi

OLD_IP=$(cat "$CURRENT_IP_FILE" 2>/dev/null || echo "")

if [ "$NEW_IP" != "$OLD_IP" ]; then
    echo "$(date) [INFO] IP Change detected: $OLD_IP -> $NEW_IP" >> "$LOG_FILE"
    echo "$NEW_IP" > "$CURRENT_IP_FILE"
    
    if [ -n "$DESEC_DOMAIN" ] && [ -n "$DESEC_TOKEN" ]; then
        echo "$(date) [INFO] Updating deSEC DNS record for $DESEC_DOMAIN..." >> "$LOG_FILE"
        DESEC_RESPONSE=$(curl -s -X PATCH "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/" \
            -H "Authorization: Token $DESEC_TOKEN" \
            -H "Content-Type: application/json" \
            -d "[{\"subname\": \"\", \"ttl\": 3600, \"type\": \"A\", \"records\": [\"$NEW_IP\"]}, {\"subname\": \"*\", \"ttl\": 3600, \"type\": \"A\", \"records\": [\"$NEW_IP\"]}]" 2>&1 || echo "CURL_ERROR")
        
        NEW_IP_ESCAPED=$(echo "$NEW_IP" | sed 's/\./\\./g')
        if [[ "$DESEC_RESPONSE" == "CURL_ERROR" ]]; then
            echo "$(date) [ERROR] Failed to communicate with deSEC API" >> "$LOG_FILE"
        elif [ -z "$DESEC_RESPONSE" ] || echo "$DESEC_RESPONSE" | grep -qE "(${NEW_IP_ESCAPED}|\[\]|\"records\")" ; then
            echo "$(date) [INFO] deSEC DNS updated successfully to $NEW_IP" >> "$LOG_FILE"
        else
            echo "$(date) [WARN] deSEC DNS update may have failed: $DESEC_RESPONSE" >> "$LOG_FILE"
        fi
    fi
    
    sed -i "s|WG_HOST=.*|WG_HOST=$NEW_IP|g" "$COMPOSE_FILE"
    docker compose -f "$COMPOSE_FILE" up -d --no-deps --force-recreate wg-easy
    echo "$(date) [INFO] WireGuard container restarted with new IP" >> "$LOG_FILE"
fi
EOF
chmod +x "$MONITOR_SCRIPT"
CRON_CMD="*/5 * * * * $MONITOR_SCRIPT"
EXISTING_CRON=$(crontab -l 2>/dev/null || true)
echo "$EXISTING_CRON" | grep -v "$MONITOR_SCRIPT" | { cat; echo "$CRON_CMD"; } | crontab -

# --- SECTION 15.2: EXPORT CREDENTIALS ---
# Generate a CSV file compatible with Proton Pass for easy credential management.
generate_protonpass_export() {
    log_info "Generating Proton Pass import file (CSV)..."
    local export_file="$BASE_DIR/protonpass_import.csv"
    
    # Proton Pass CSV Import Format: Name,URL,Username,Password,Note
    # We use this generic format for maximum compatibility.
    cat > "$export_file" <<EOF
Name,URL,Username,Password,Note
AdGuard Home,http://$LAN_IP:$PORT_ADGUARD_WEB,adguard,$AGH_PASS_RAW,Network-wide advertisement and tracker filtration.
WireGuard VPN UI,http://$LAN_IP:$PORT_WG_WEB,admin,$VPN_PASS_RAW,WireGuard remote access management interface.
Portainer UI,http://$LAN_IP:$PORT_PORTAINER,portainer,$ADMIN_PASS_RAW,Docker container management interface.
Gluetun Control Server,http://$LAN_IP:8000,gluetun,$ADMIN_PASS_RAW,Internal VPN gateway control API.
deSEC DNS API,,$DESEC_DOMAIN,$DESEC_TOKEN,API token for deSEC dynamic DNS management.
GitHub Scribe Token,,$SCRIBE_GH_USER,$SCRIBE_GH_TOKEN,GitHub Personal Access Token for Scribe Medium frontend.
EOF
    chmod 600 "$export_file"
    log_info "Credential export file created: $export_file"
}

# --- SECTION 16: STACK ORCHESTRATION & DEPLOYMENT ---
# Execute system deployment and verify global infrastructure integrity.
check_iptables() {
    log_info "Verifying iptables rules..."
    if sudo iptables -t nat -C POSTROUTING -s 10.8.0.0/24 -j MASQUERADE 2>/dev/null && \
       sudo iptables -C FORWARD -i wg0 -j ACCEPT 2>/dev/null && \
       sudo iptables -C FORWARD -o wg0 -j ACCEPT 2>/dev/null; then
        log_info "Network routing rules verified (WireGuard traffic allowed)."
    else
        log_warn "Network routing rules incomplete. External VPN access may be limited."
        log_warn "Manual firewall adjustment may be required for remote connectivity."
    fi
}

sudo modprobe tun || true

# Explicitly remove portainer and hub-api if they exist to ensure clean state
log_info "Launching core infrastructure services..."
sudo env DOCKER_CONFIG="$DOCKER_AUTH_DIR" docker compose -f "$COMPOSE_FILE" up -d --build hub-api adguard unbound gluetun

# Wait for critical backends to be healthy before starting Nginx (dashboard)
log_info "Waiting for backend services to stabilize (this may take up to 60s)..."
for i in $(seq 1 60); do
    HUB_HEALTH=$(sudo docker inspect --format='{{.State.Health.Status}}' hub-api 2>/dev/null || echo "unknown")
    GLU_HEALTH=$(sudo docker inspect --format='{{.State.Status}}' gluetun 2>/dev/null || echo "unknown")
    
    if [ "$HUB_HEALTH" = "healthy" ] && [ "$GLU_HEALTH" = "running" ]; then
        log_info "Backends are stable. Finalizing stack launch..."
        break
    fi
    [ "$i" -eq 60 ] && log_warn "Backends taking longer than expected to stabilize. Proceeding anyway..."
    sleep 1
done

# Launch the rest of the stack
sudo env DOCKER_CONFIG="$DOCKER_AUTH_DIR" docker compose -f "$COMPOSE_FILE" up -d --remove-orphans

log_info "Verifying control plane connectivity..."
sleep 5
API_TEST=$(curl -s -o /dev/null -w "%{http_code}" "http://$LAN_IP:$PORT_DASHBOARD_WEB/api/status" || echo "FAILED")
if [ "$API_TEST" = "200" ]; then
    log_info "Control plane is reachable."
elif [ "$API_TEST" = "401" ]; then
    log_info "Control plane is reachable (Security handshake verified)."
else
    log_warn "Control plane returned status $API_TEST. The dashboard may show 'Offline (API Error)' initially."
fi

# --- SECTION 16.1: PORTAINER AUTOMATION ---
if [ "$AUTO_PASSWORD" = true ]; then
    log_info "Synchronizing Portainer administrative settings..."
    PORTAINER_READY=false
    for _ in {1..12}; do
        if curl -s --max-time 2 "http://$LAN_IP:$PORT_PORTAINER/api/system/status" > /dev/null; then
            PORTAINER_READY=true
            break
        fi
        sleep 5
    done

    if [ "$PORTAINER_READY" = true ]; then
        # Authenticate to get JWT (user was initialized via --admin-password CLI flag)
        # Try 'admin' first, then 'portainer' (in case it was already renamed in a previous run)
        AUTH_RESPONSE=$(curl -s -X POST "http://$LAN_IP:$PORT_PORTAINER/api/auth" \
            -H "Content-Type: application/json" \
            -d "{\"Username\":\"admin\",\"Password\":\"$ADMIN_PASS_RAW\"}" 2>&1 || echo "CURL_ERROR")
        
        if ! echo "$AUTH_RESPONSE" | grep -q "jwt"; then
            AUTH_RESPONSE=$(curl -s -X POST "http://$LAN_IP:$PORT_PORTAINER/api/auth" \
                -H "Content-Type: application/json" \
                -d "{\"Username\":\"portainer\",\"Password\":\"$ADMIN_PASS_RAW\"}" 2>&1 || echo "CURL_ERROR")
        fi
        
        if echo "$AUTH_RESPONSE" | grep -q "jwt"; then
            PORTAINER_JWT=$(echo "$AUTH_RESPONSE" | grep -oP '"jwt":"\K[^"]+')
            
            # 1. Disable Telemetry/Analytics
            log_info "Disabling Portainer anonymous telemetry..."
            curl -s -X PUT "http://$LAN_IP:$PORT_PORTAINER/api/settings" \
                -H "Authorization: Bearer $PORTAINER_JWT" \
                -H "Content-Type: application/json" \
                -d '{"AllowAnalytics": false, "EnableTelemetry": false}' > /dev/null
            
            # 2. Change admin username to 'portainer'
            log_info "Updating Portainer administrator username to 'portainer'..."
            # Portainer user ID 1 is always the initial admin
            curl -s -X PUT "http://$LAN_IP:$PORT_PORTAINER/api/users/1" \
                -H "Authorization: Bearer $PORTAINER_JWT" \
                -H "Content-Type: application/json" \
                -d '{"Username": "portainer"}' > /dev/null
            log_info "Portainer username updated successfully."
            
            # Verify settings
            # Note: We must re-auth if we want to verify using the NEW username, 
            # but we can verify settings with the old JWT if it hasn't expired.
            CHECK_SETTINGS=$(curl -s -H "Authorization: Bearer $PORTAINER_JWT" "http://$LAN_IP:$PORT_PORTAINER/api/settings")
            if echo "$CHECK_SETTINGS" | grep -q '"AllowAnalytics":false' && echo "$CHECK_SETTINGS" | grep -q '"EnableTelemetry":false'; then
                log_info "Portainer privacy settings verified successfully."
            else
                log_warn "Portainer privacy settings verification failed. Check Portainer UI manually."
            fi
            log_info "Portainer automation complete."
        else
            log_warn "Failed to authenticate with Portainer for automation: $AUTH_RESPONSE"
        fi
    else
        log_warn "Portainer did not become ready in time for automated settings synchronization."
    fi
else
    echo -e "\e[33m[NOTE]\e[0m Administrative credentials for Portainer are available in: $BASE_DIR/.secrets"
    echo -e "\e[33m[NOTE]\e[0m Remember to disable 'Anonymous statistics' in Portainer settings for maximum privacy."
fi

if $DOCKER_CMD ps | grep -q adguard; then
    log_info "AdGuard Home is operational. Network-wide filtering is active."
    log_info "Waiting for AdGuard web interface..."
    
    AGH_UP=false
    for _ in {1..12}; do
        if curl -s --max-time 5 "http://$LAN_IP:$PORT_ADGUARD_WEB" > /dev/null; then
            AGH_UP=true
            break
        fi
        sleep 5
    done

    if [ "$AGH_UP" = true ]; then
        log_info "AdGuard web interface is accessible."
    else
        log_warn "AdGuard web interface is still initializing (timeout)."
    fi
fi

check_iptables

generate_protonpass_export

echo "[+] Finalizing environment (cleaning up dangling images)..."
$DOCKER_CMD image prune -f

$DOCKER_CMD restart portainer 2>/dev/null || true

echo "=========================================================="
echo "SYSTEM DEPLOYED: PRIVATE INFRASTRUCTURE ESTABLISHED"
echo "=========================================================="
echo "[NOTE] Please disable browser-based 'privacy' extensions for this local address."
echo "[NOTE] Some extensions may interfere with local dashboard telemetry."
echo ""
echo "MANAGEMENT DASHBOARD:"
echo "http://$LAN_IP:$PORT_DASHBOARD_WEB"
echo ""
echo "ADGUARD HOME (DNS CONTROL):"
echo "http://$LAN_IP:$PORT_ADGUARD_WEB"
echo ""
echo "WIREGUARD VPN (REMOTE ACCESS GATEWAY):"
echo "http://$LAN_IP:$PORT_WG_WEB"
echo ""
echo "CONFIGURATION INSTRUCTIONS:"
echo "  [ LOCAL LAN USAGE ]"
echo "  Primary DNS: $LAN_IP"
echo "  -> ACTION: Configure your router's DNS to $LAN_IP for network-wide protection."
echo ""
echo "  [ REMOTE ACCESS USAGE ]"
echo "  - Utilize the WireGuard VPN when connecting from external or untrusted networks."
echo "  - Once the VPN tunnel is established, your home DNS settings and local services"
echo "    become securely accessible via your own hardware proxy."
echo ""
echo "SECURITY OVERVIEW:"
echo "  ✓ Only WireGuard (51820/udp) is exposed to the internet."
echo "  ✓ DNS resolution is independent and communicates directly with Root Servers."
echo "  ✓ Frontend services are isolated via Gluetun VPN to hide your home IP."
echo ""
if [ -f "$AGH_CONF_DIR/ssl.crt" ]; then
    if grep -q "BEGIN CERTIFICATE" "$AGH_CONF_DIR/ssl.crt"; then
        if ! grep -q "Let's Encrypt" "$AGH_CONF_DIR/ssl.crt" && ! grep -q "R3" "$AGH_CONF_DIR/ssl.crt"; then
            echo -e "\e[33m[IMPORTANT]\e[0m CURRENTLY UTILIZING A SELF-SIGNED CERTIFICATE"
            echo "  - Mobile devices require a trusted CA for Encrypted DNS (DoH/DoT/DoQ)."
            echo "  - An automated background process is managing Let's Encrypt issuance."
            echo "  - Standard DNS (Port 53) is functional over LAN and VPN."
            echo ""
        fi
    fi
fi
if [ "$AUTO_PASSWORD" = true ]; then
    echo "=========================================================="
    echo "GENERATED CREDENTIALS"
    echo "=========================================================="
    echo "Portainer Password: $ADMIN_PASS_RAW"
    echo "VPN Web UI Password: $VPN_PASS_RAW"
        echo "AdGuard Home Password: $AGH_PASS_RAW"
            echo "AdGuard Home Username: $AGH_USER"
            echo "Portainer Username: portainer (Fallback: admin)"
                        echo "Odido Booster API Key: $ODIDO_API_KEY"
                        echo ""
                        echo "IMPORT TO PROTON PASS:"
            echo "A CSV file has been generated for easy import into Proton Pass:"
    echo "$BASE_DIR/protonpass_import.csv"
    echo ""
    echo "Please save these credentials. They are also stored in: $BASE_DIR/.secrets"
fi
echo "=========================================================="

echo ""
echo "=========================================================="
echo "🛡️  DEPLOYMENT COMPLETE: INFRASTRUCTURE IS OPERATIONAL"
echo "=========================================================="
echo ""
