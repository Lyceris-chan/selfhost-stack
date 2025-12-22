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
- [Getting Started](#getting-started)
- [Architecture & Privacy](#architecture--privacy)
- [Included Services](#included-services)
- [Management Dashboard](#management-dashboard)
- [Network Configuration](#network-configuration)
- [Advanced Setup](#advanced-setup)

## 🏗️ Getting Started

### Prerequisites & Credentials
Prepare these credentials to ensure a smooth deployment.

*   **Docker Hub / DHI Access**: A username and Personal Access Token (PAT) with `read` permissions is required to pull hardened images and avoid rate limits.
    *   *Create at:* [Docker Hub Security Settings](https://hub.docker.com/settings/security)
*   **WireGuard Configuration**: A `.conf` file from your VPN provider (e.g., ProtonVPN, Mullvad) to enable the privacy tunnel.
    *   *Note:* Ensure "Port Forwarding" is enabled if supported by your provider for optimal P2P performance (optional).
*   **deSEC Domain (Recommended)**: A free domain and API token from [deSEC.io](https://desec.io) enables trusted SSL certificates and automated Dynamic DNS (DDNS).
*   **GitHub Token (Optional)**: A classic PAT with `gist` scope is required for the **Scribe** service to function.

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
*   **Reset Environment**: `./zima.sh -c` (Cleans up containers and networks, keeps data).
*   **Uninstall**: `./zima.sh -x` (⚠️ Removes everything including data).

## 🔒 Architecture & Privacy

This stack is engineered to minimize your digital footprint.

### Zero-Leaks & Asset Proxying
Most self-hosted dashboards leak your IP by loading fonts or icons from Google or CDNs.
*   **Local Serving**: We download all necessary assets (fonts, icons, libraries) to the host during the initial setup. Your browser only ever loads files from your local server.
*   **Anonymized Fetching**: The asset download process is routed through the **Gluetun VPN container**. Your public home IP is never exposed to asset providers (Fontlay, JSDelivr) during setup or updates.

### Data Minimization
While requests are proxied to hide your IP, upstream providers may still log standard access metadata (timestamps). However, because these requests originate from the isolated `hub-api` container using a generic User-Agent, they cannot fingerprint your specific host device, browser, or operating system. They see a generic Linux client coming from a commercial VPN IP.

### Network Isolation
*   **Public Interface**: Only one port (`51820/UDP` for WireGuard remote access) is exposed to the internet.
*   **Internal Network**: Services communicate over an isolated Docker bridge network (`frontnet`).
*   **VPN Tunnel**: Privacy frontends (Redlib, Invidious, etc.) use `network_mode: service:gluetun`, forcing all their outbound traffic through your VPN provider.

## 📦 Included Services

| Service | Type | Function |
| :--- | :--- | :--- |
| **[Invidious](https://github.com/iv-org/invidious)** | Frontend | Private YouTube browsing (No ads/tracking) |
| **[Redlib](https://github.com/redlib-org/redlib)** | Frontend | Lightweight, tracker-free Reddit interface |
| **[Wikiless](https://github.com/Metastem/Wikiless)** | Frontend | Private Wikipedia access |
| **[Rimgo](https://codeberg.org/rimgo/rimgo)** | Frontend | Lightweight Imgur interface |
| **[Scribe](https://git.sr.ht/~edwardloveall/scribe)** | Frontend | Alternative Medium frontend |
| **[BreezeWiki](https://gitdab.com/cadence/breezewiki)** | Frontend | De-fandomized Wiki interface |
| **[AnonOverflow](https://github.com/httpjamesm/anonymousoverflow)** | Frontend | Private Stack Overflow viewer |
| **[AdGuard Home](https://github.com/AdguardTeam/AdGuardHome)** | Core | Network-wide DNS filtering & Ad-blocking |
| **[Unbound](https://github.com/NLnetLabs/unbound)** | Core | Recursive DNS resolver |
| **[WireGuard](https://github.com/wg-easy/wg-easy)** | Core | Secure remote access gateway |
| **[Memos](https://github.com/usememos/memos)** | Utility | Private knowledge base & note-taking |
| **[VERT](https://github.com/vert-sh/vert)** | Utility | Local, GPU-accelerated file conversion |
| **[Portainer](https://github.com/portainer/portainer)** | Admin | Advanced container management |

## 🖥️ Management Dashboard

Access the unified dashboard at `http://<LAN_IP>:8081`.

### Update Engine
The stack features a sophisticated update management system:
*   **Changelogs**: View commit logs (for source builds) or release notes (for images) directly in the UI before updating.
*   **Granular Control**: Update all services at once or select specific ones.
*   **Safety First**: The system automatically creates database backups before applying any updates.
*   **Rollback**: If an update fails, you can restore data from the automatically generated backups via the `migrate.sh` helper.

### Customization
*   **Dynamic Theming**: Upload a wallpaper or pick a color to generate a custom Material Design 3 theme.
*   **Privacy Masking**: One-click toggle to blur sensitive IPs and data for screenshots.

## 🌐 Network Configuration

### Router Setup (DNS)
To protect your entire network, configure your router's **LAN DNS** (DHCP settings) to point to the Privacy Hub's IP address. This forces all connected devices to use AdGuard Home.

### DNS Hijacking (Advanced)
Some devices (IoT, Smart TVs) hardcode DNS servers (like `8.8.8.8`) to bypass your filters. You can force them to comply using a router with advanced firewall capabilities (like OpenWrt or pfSense).

**Goal:** Redirect all port `53` (UDP/TCP) traffic originating from the LAN to the Privacy Hub's IP.

## 📡 Advanced Setup

### OpenWrt Configuration
If using OpenWrt, you can automate the network configuration (Static IP, Port Forwarding, and DNS Hijacking) using these UCI commands. Replace the placeholders with your specific values.

<details>
<summary><strong>Click to view UCI Commands</strong></summary>

```bash
# 1. Static IP Assignment
uci add dhcp host
uci set dhcp.@host[-1].name='ZimaOS-Privacy-Hub'
uci set dhcp.@host[-1].mac='00:11:22:33:44:55' # <--- YOUR MAC
uci set dhcp.@host[-1].ip='192.168.1.100'      # <--- YOUR IP
uci commit dhcp
/etc/init.d/dnsmasq restart

# 2. Firewall Port Forwarding (WireGuard)
uci add firewall redirect
uci set firewall.@redirect[-1].name='Forward-WireGuard'
uci set firewall.@redirect[-1].src='wan'
uci set firewall.@redirect[-1].proto='udp'
uci set firewall.@redirect[-1].src_dport='51820'
uci set firewall.@redirect[-1].dest_ip='192.168.1.100' # <--- YOUR IP
uci set firewall.@redirect[-1].dest_port='51820'
uci set firewall.@redirect[-1].target='DNAT'
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-WireGuard-Inbound'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].dest_port='51820'
uci set firewall.@rule[-1].target='ACCEPT'

# 3. Forced DNS (Hijacking)
uci add firewall redirect
uci set firewall.@redirect[-1].name='Forced-DNS'
uci set firewall.@redirect[-1].src='lan'
uci set firewall.@redirect[-1].proto='tcpudp'
uci set firewall.@redirect[-1].src_dport='53'
uci set firewall.@redirect[-1].dest_ip='192.168.1.100' # <--- YOUR IP
uci set firewall.@redirect[-1].dest_port='53'
uci set firewall.@redirect[-1].target='DNAT'

uci commit firewall
/etc/init.d/firewall restart
```
</details>

### External Policy References
*   **Fontlay**: [Privacy Policy & Source](https://github.com/miroocloud/fontlay)
*   **JSDelivr**: [Privacy Policy](https://www.jsdelivr.com/terms/privacy-policy)
*   **GitHub**: [Privacy Statement](https://docs.github.com/en/site-policy/privacy-policies/github-privacy-statement)

---
*Built with ❤️ for the self-hosting community.*