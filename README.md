# 🛡️ ZimaOS Privacy Hub

A comprehensive, self-hosted privacy infrastructure designed for digital independence.
Route your traffic through secure VPNs, eliminate tracking with isolated frontends, and manage everything from a unified **Material Design 3** dashboard.

## 🌟 Key Features

*   **VPN-Gated Frontends**: Services like Invidious (YouTube), Redlib (Reddit), and Wikiless are routed through a **Gluetun VPN** tunnel. Upstream providers see your VPN IP, not your home IP.
*   **Zero-Leaks Architecture**: No external CDNs or trackers. All assets (fonts, icons, scripts) are fetched once via an anonymized proxy and served locally.
*   **Network-Wide Filtering**: AdGuard Home provides DNS-level ad blocking and tracking protection for your entire home network.
*   **Automated Lifecycle**: Built-in "Update Engine" handles backups, database migrations, container rebuilds, and rollbacks automatically.
*   **Material Design 3**: A modern, responsive management dashboard with dynamic theming and real-time system metrics.
*   **Hardened Infrastructure**: Built on DHI (Docker Hardened Images) with minimal-footprint Alpine Linux bases.

## 📚 Contents
- [🚀 Quick Start](#quick-start)
- [🖥️ Management Dashboard](#management-dashboard)
- [📦 Included Services](#included-services)
- [🔗 Service Access](#service-access-after-deploy)
- [🔧 Add Your Own Services](#add-your-own-services)
- [🌐 Network Configuration](#network-configuration)
- [📡 Advanced Setup: OpenWrt & Double NAT](#advanced-setup-openwrt--double-nat)
- [🔒 Security & Credentials](#security--credentials)

## 🏗️ Getting Started

### Prerequisites & Credentials
Prepare these ahead of time to ensure a smooth deployment.

*   **Docker Hub / DHI Access**: A username and Personal Access Token (PAT) with `read` permissions is required to pull hardened images and avoid rate limits.
    *   *Create at:* [Docker Hub Security Settings](https://hub.docker.com/settings/security)
*   **WireGuard Configuration**: A `.conf` file from your VPN provider (e.g., ProtonVPN, Mullvad) to enable the privacy tunnel.
    *   *Note:* Only ProtonVPN is explicitly tested. Ensure "Port Forwarding" is enabled if supported by your provider.
*   **deSEC Domain (Recommended)**: A free domain and API token from [deSEC.io](https://desec.io) enables trusted SSL certificates and automated Dynamic DNS (DDNS).
*   **GitHub Token (Optional)**: A classic PAT with `gist` scope is required for the **Scribe** service to function.
*   **Odido OAuth token (optional, NL unlimited data)**: Used by Odido Booster. Get the OAuth token using [Odido Authenticator](https://github.com/GuusBackup/Odido.Authenticator).

### Installation
Run the deployment script. It will validate your environment, prompt for credentials, and build the stack.

```bash
# Standard Deployment (Interactive)
./zima.sh

# Deployment with Auto-generated Passwords (Recommended for Beginners)
./zima.sh -p
```

### 🔑 Post-Install: Where are my passwords?
If you used the `-p` flag, the script auto-generated secure credentials for you.

1.  **Secret File**: All passwords are stored on your host at:
    ```bash
    /DATA/AppData/privacy-hub/.secrets
    ```
    > ⚠️ **SECURITY WARNING**: This file contains unencrypted administrative passwords and API keys. Ensure access to your host machine is restricted. Consider deleting this file after safely storing your credentials in a password manager, though `hub-api` uses it for some operations.

2.  **Proton Pass Import**: A CSV file ready for import into password managers is generated at:
    ```bash
    /DATA/AppData/privacy-hub/protonpass_import.csv
    ```
3.  **Default Username**:
    *   **Portainer**: `portainer` (or `admin`)
    *   **AdGuard**: `adguard`
    *   **Dashboard API**: `HUB_API_KEY` (Found in `.secrets`)

### Management & Troubleshooting
*   **Update Services**: Use the "Check Updates" button in the dashboard.
*   **Restart Stack**: `./zima.sh` (Running it again updates configuration and restarts containers safely).

| Flag | Description | Action |
| :--- | :--- | :--- |
| `-c` | **Clean Reset** | Removes all containers and networks but preserves user data. Useful for fixing network glitches. |
| `-x` | **Uninstall** | ⚠️ **DESTRUCTIVE**. Removes containers, networks, volumes, and ALL data. |
| `-p` | **Auto-Passwords** | Generates secure random passwords for all services automatically. |
| `-y` | **Auto-Confirm** | Skips confirmation prompts (for automated deployments). |
| `-s` | **Select Services** | Deploy specific services only (e.g., `./zima.sh -s invidious,memos`). |

## 🖥️ Management Dashboard

Access the unified dashboard at `http://<LAN_IP>:8081`.

### Material Design 3 Compliance
The dashboard is built to strictly follow **[Google's Material Design 3](https://m3.material.io/)** guidelines.
*   **Color System**: We use the official `material-color-utilities` library to generate scientifically accurate accessible color palettes from your seed color.
*   **Components**: All UI elements (cards, chips, buttons) adhere to M3 specifications for shape, elevation, and state layers.

### Customization
*   **Theme Engine**: Upload a wallpaper to automatically extract a coordinated palette (Android folder style), or pick a color manually.
*   **Presets**: Choose from curated Material Design color presets.
*   **Dark/Light Mode**: Fully supported with automatic system preference detection.
*   **Privacy Masking**: One-click toggle to blur sensitive IPs and data for screenshots.

### Update Engine
The stack features a sophisticated update management system:
*   **Changelogs**: View commit logs (for source builds) or release notes (for images) directly in the UI before updating.
*   **Granular Control**: Update all services at once or select specific ones.
*   **Safety First**: The system automatically creates database backups before applying any updates.
*   **Rollback**: If an update fails, you can restore data from the automatically generated backups via the `migrate.sh` helper.

## 📦 Included Services

| Service | Category | Purpose |
| :--- | :--- | :--- |
| **[Invidious](https://github.com/iv-org/invidious)** | Privacy Frontend | Anonymous YouTube browsing (No ads/tracking) |
| **[Redlib](https://github.com/redlib-org/redlib)** | Privacy Frontend | Lightweight Reddit interface |
| **[Wikiless](https://github.com/Metastem/Wikiless)** | Privacy Frontend | Private Wikipedia access |
| **[Memos](https://github.com/usememos/memos)** | Utility | Private knowledge base & note-taking |
| **[AdGuard Home](https://github.com/AdguardTeam/AdGuardHome)** | Infrastructure | Network-wide DNS filtering & Ad-blocking |
| **[WireGuard (WG-Easy)](https://github.com/wg-easy/wg-easy)** | Infrastructure | Secure remote access gateway |
| **[Portainer](https://github.com/portainer/portainer)** | Management | Advanced container orchestration |
| **[VERT](https://github.com/vert-sh/vert)** | Utility | Local file conversion with optional GPU acceleration |
| **[Rimgo](https://codeberg.org/rimgo/rimgo)** | Privacy Frontend | Lightweight Imgur interface |
| **[BreezeWiki](https://gitdab.com/cadence/breezewiki)** | Privacy Frontend | De-fandomized Wikipedia/Wiki interface |
| **[AnonymousOverflow](https://github.com/httpjamesm/anonymousoverflow)** | Privacy Frontend | Privacy-focused Stack Overflow viewer |
| **[Scribe](https://git.sr.ht/~edwardloveall/scribe)** | Privacy Frontend | Alternative Medium frontend |
| **[Odido Booster](https://github.com/Lyceris-chan/odido-bundle-booster)** | Utility | Automated data bundle booster (NL Odido) |

## 🔗 Service Access (After Deploy)

The dashboard provides one-click launch cards for every service at `http://<LAN_IP>:8081`. If you prefer direct access, use the LAN URLs below. When deSEC is configured, HTTPS URLs are available at `https://<service>.<domain>:8443/` (or `https://<domain>:8443/` for the dashboard).

| Service | Local URL | HTTPS (deSEC) | Notes |
| :--- | :--- | :--- | :--- |
| Dashboard | `http://<LAN_IP>:8081` | `https://<domain>:8443/` | Management UI and service launcher. |
| Invidious | `http://<LAN_IP>:3000` | `https://invidious.<domain>:8443/` | VPN-routed; upstream sees VPN IP. |
| Redlib | `http://<LAN_IP>:8080` | `https://redlib.<domain>:8443/` | VPN-routed; upstream sees VPN IP. |
| Wikiless | `http://<LAN_IP>:8180` | `https://wikiless.<domain>:8443/` | VPN-routed; upstream sees VPN IP. |
| Memos | `http://<LAN_IP>:5230` | `https://memos.<domain>:8443/` | Local notes and knowledge base. |
| AdGuard Home | `http://<LAN_IP>:8083` | `https://adguard.<domain>:8443/` | DNS filtering UI. |
| WireGuard (WG-Easy) | `http://<LAN_IP>:51821` | `https://wireguard.<domain>:8443/` | VPN management UI. |
| Portainer | `http://<LAN_IP>:9000` | `https://portainer.<domain>:8443/` | Container management. |
| VERT | `http://<LAN_IP>:5555` | `https://vert.<domain>:8443/` | GPU acceleration uses `https://vertd.<domain>:8443/`. |
| Rimgo | `http://<LAN_IP>:3002` | `https://rimgo.<domain>:8443/` | VPN-routed; upstream sees VPN IP. |
| BreezeWiki | `http://<LAN_IP>:8380` | `https://breezewiki.<domain>:8443/` | VPN-routed; upstream sees VPN IP. |
| AnonOverflow | `http://<LAN_IP>:8480` | `https://anonymousoverflow.<domain>:8443/` | VPN-routed; upstream sees VPN IP. |
| Scribe | `http://<LAN_IP>:8280` | `https://scribe.<domain>:8443/` | VPN-routed; upstream sees VPN IP. |
| Odido Booster | `http://<LAN_IP>:8085` | `https://odido.<domain>:8443/` | NL Odido automated booster UI. |

<a id="add-your-own-services"></a>
<details>
<summary><strong>🔧 Add Your Own Services</strong> (advanced)</summary>

Everything lives in `zima.sh`, so one run rebuilds Docker Compose and the dashboard. Keep the service name consistent everywhere (Compose, monitoring, and UI IDs).

### 1) Service Definition (Orchestration Layer)
Locate **SECTION 13** in `zima.sh` (search for `# --- SECTION 13: ORCHESTRATION LAYER`). This is where the `docker-compose.yml` file is generated. Add your service block using the `should_deploy` check to enable selective deployment.

```bash
if should_deploy "myservice"; then
cat >> "$COMPOSE_FILE" <<EOF
  myservice:
    image: my-image:latest
    container_name: myservice
    networks: [frontnet]
    # For VPN routing, uncomment the next two lines:
    # network_mode: "service:gluetun"
    # depends_on: gluetun: {condition: service_healthy}
    restart: unless-stopped
EOF
fi
```

### 2) Monitoring & Health (Status Logic)

Update the service status loop inside the `WG_API_SCRIPT` heredoc in `zima.sh` (search for `Check individual privacy services status internally`).

- Add `"myservice:1234"` to the `for srv in ...` list.
- If the service is routed through Gluetun, add `myservice` to the case that maps `TARGET_HOST="gluetun"`.
- Optional: add a Docker `healthcheck` to surface `Healthy` rather than just `Online`.

### 3) Dashboard Card + Metrics + Portainer

Add a card in the dashboard HTML (SECTION 14 in `zima.sh`):

- Use `id="link-myservice"` and `data-container="myservice"`.
- Set `data-url="http://$LAN_IP:<port>"` for the LAN link.
- Add a `portainer-link` chip if you want one-click container management.
- Add a `metrics-myservice` block if you want CPU/memory chips to show.

### 4) Update Checks (Optional)

The Update banner checks git repos under `/app/sources/<service>`. If you want your service to appear there, keep its source repo in that path with a remote configured. For image-based services, add your mapping to the `SERVICE_REPOS` dictionary in `hub-api`.

</details>

## 🖥️ System Requirements

| Specification | Minimum | Recommended |
| :--- | :--- | :--- |
| **Processor** | 2 Physical Cores | 4+ Physical Cores (8+ Threads) |
| **RAM** | 4 GB | 8 GB+ |
| **Storage** | 20 GB | 40 GB+ (SSD preferred) |
| **OS** | Linux (Ubuntu/Debian/Alpine) | Linux (Ubuntu/Debian/Alpine) |

### Scaling & Resource Management
The current configuration is pre-tuned to support up to **30 users** on a machine with 16 GB RAM. Each service is constrained by **Docker Resource Limits** to prevent host exhaustion.

> **Note:** Building containers from source (e.g., Invidious, Wikiless) is intensive. Physical cores significantly improve build speed compared to logical threads.

## 🌐 Network Configuration

### Router Integration (Default DNS)
Set your router's **LAN DNS** to the local IP of this stack. This ensures all connected devices automatically use AdGuard Home for filtering.

### DNS Hijacking (Forced Resolution)
Redirect all traffic on port `53` (TCP/UDP) not originating from the Privacy Hub to the Privacy Hub's IP. This forces rogue devices (IoT, Smart TVs) to use your filtered DNS even if they have hardcoded servers.

## 📡 Advanced Setup: OpenWrt & Double NAT

<details>
<summary><strong>UCI Commands for OpenWrt Configuration</strong></summary>

```bash
# Static IP, Port Forwarding (51820), and NAT Redirect (53)
uci add dhcp host
uci set dhcp.@host[-1].name='Privacy-Hub'
uci set dhcp.@host[-1].mac='00:11:22:33:44:55'
uci set dhcp.@host[-1].ip='192.168.1.100'
uci commit dhcp
/etc/init.d/dnsmasq restart
```
</details>

## 🔒 Security & Privacy

- **Zero-Leaks Architecture**: External assets (fonts, icons, scripts) are fetched once via the **Gluetun VPN proxy** and served locally. Your public home IP is never exposed to CDNs.
- **Data Minimization**: Requests originate from the isolated `hub-api` container using generic User-Agents, preventing host or browser fingerprinting.
- **Proton Pass Export**: When using `-p`, a verified CSV is generated at `/DATA/AppData/privacy-hub/protonpass_import.csv` for easy import ([See Guide](#proton-pass-import)).

<a id="proton-pass-import"></a>
<details>
<summary><strong>👇 How to Import into Proton Pass</strong></summary>

1.  **Download the CSV**: Transfer `protonpass_import.csv` to your machine.
2.  **Open Proton Pass**: Settings → Import → Select Proton Pass (CSV).
3.  **Upload**: The format matches the official template (`name,url,email,username,password,note,totp,vault`).
</details>

---
*Built with ❤️ for the self-hosting community.*