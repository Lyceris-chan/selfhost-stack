# 🛡️ Privacy Hub Stack

A comprehensive, self-hosted privacy infrastructure built on **Material Design 3**.
Own your data, route through VPNs, and eliminate tracking with zero external dependencies.

## 📚 Contents
- [🚀 Quick Start](#quick-start)
- [🖥️ Management Dashboard](#management-dashboard)
- [📦 Included Services](#included-services)
- [🔗 Service Access](#service-access-after-deploy)
- [🔧 Add Your Own Services](#add-your-own-services)
- [🌐 Network Configuration](#network-configuration)
- [📡 Advanced Setup: OpenWrt & Double NAT](#advanced-setup-openwrt--double-nat)
- [🔒 Security & Credentials](#security--credentials)

## 🚀 Quick Start

### Before You Run (Credentials)

Prepare these ahead of time so setup is smooth:

- **Docker Hub / <sup>[1](#explainer-1)</sup> <sup>[4](#explainer-4)</sup> (required)**: One username + <sup>[4](#explainer-4)</sup> is used for both Docker Hub and `dhi.io`. Use a token with **pull/read** permissions only. This is required to pull hardened images and avoid rate limits. Create it at [Docker Hub Access Tokens](https://hub.docker.com/settings/security). (<sup>[1](#explainer-1)</sup>, <sup>[4](#explainer-4)</sup>)
- **WireGuard config (recommended)**: A `.conf` from your VPN provider if you want VPN-routed frontends (Gluetun). Only ProtonVPN is tested (details below).
- **deSEC domain + API token (recommended)**: Enables <sup>[2](#explainer-2)</sup> + <sup>[3](#explainer-3)</sup>. Create a token in your deSEC account at [deSEC](https://desec.io). (<sup>[2](#explainer-2)</sup>, <sup>[3](#explainer-3)</sup>)
- **GitHub token (optional)**: <sup>[4](#explainer-4)</sup> with `gist` scope only, used by the Scribe frontend for gist access. Create it at [GitHub Tokens](https://github.com/settings/tokens). (<sup>[4](#explainer-4)</sup>)
- **Odido OAuth token (optional, NL unlimited data)**: Used by Odido Booster. Get the OAuth token using [Odido Authenticator](https://github.com/GuusBackup/Odido.Authenticator). The Odido API may incur costs or limits; use at your own risk.

### Key Concepts
*   **DHI (Docker Hardened Images)**: We use hardened base images from `dhi.io` to minimize security vulnerabilities.
*   **DDNS (Dynamic DNS)**: Automatically updates your domain name when your home IP address changes.
*   **SSL**: Provides encrypted (HTTPS) access. We use Let's Encrypt for trusted certificates.
*   **Gluetun**: The VPN client that "gates" your privacy frontends, hiding your home IP from the internet.

<details>
<summary><strong>ProtonVPN WireGuard (.conf) - tested path</strong></summary>

Only ProtonVPN is tested; other providers might work but are unverified. The free tier works fine; premium servers might be faster, but we only use the VPN to proxy frontends and hide our IPs, so higher speeds and extra security features aren’t necessary here. In the ProtonVPN dashboard:

1. Go to **Downloads → WireGuard configuration**.
2. Enable **Port Forwarding** before creating the config.
3. Give the config a recognizable **name**.
4. Choose a server/region and download the `.conf`.
5. Paste the contents when the script prompts for the WireGuard configuration.

</details>

### Standard Deployment
```bash
./zima.sh
```

### Selective Deployment
Only deploy specific services to save resources (Infrastructure is always included):
```bash
./zima.sh -s invidious,memos,redlib
```

### Reset Environment
```bash
./zima.sh -c
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

| Flag | Description | Action |
| :--- | :--- | :--- |
| `-c` | **Clean Reset** | Removes all containers and networks but preserves user data. Useful for fixing network glitches. |
| `-x` | **Uninstall** | ⚠️ **DESTRUCTIVE**. Removes containers, networks, volumes, and ALL data. |
| `-p` | **Auto-Passwords** | Generates secure random passwords for all services automatically. |
| `-y` | **Auto-Confirm** | Skips confirmation prompts (for automated deployments). |
| `-s` | **Select Services** | Deploy specific services only (e.g., `./zima.sh -s invidious,memos`). |

## 🖥️ Management Dashboard
The Privacy Hub features a custom-built, unified management interface designed with **Material Design 3**.

### 🎨 UI & Theme Customization
Personalize the dashboard appearance using Material Design 3 dynamic color principles:
- **Seed Color Selection:** Choose a primary color to generate a full compliant M3 theme.
- **Dynamic Image Extraction:** Upload a wallpaper to automatically extract its dominant color and apply it to the UI.
- **Server-Side Persistence:** Theme settings are saved directly to the host filesystem via the API (`config/theme.json`), ensuring your preferences persist across devices without cookies.
- **Fast Feedback:** UI transitions and notifications are optimized for performance and Material motion standards.


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
| **[VERT](https://github.com/vert-sh/vert)** | Utility | Local file conversion with optional GPU acceleration (VERTD requires a valid <sup>[3](#explainer-3)</sup> cert due to quirks, data won't leave your device) |
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
| VERT | `http://<LAN_IP>:5555` | `https://vert.<domain>:8443/` | GPU acceleration uses `https://vertd.<domain>:8443/` (data won't leave your device). |
| Rimgo | `http://<LAN_IP>:3002` | `https://rimgo.<domain>:8443/` | VPN-routed; upstream sees VPN IP. |
| BreezeWiki | `http://<LAN_IP>:8380` | `https://breezewiki.<domain>:8443/` | VPN-routed; upstream sees VPN IP. |
| AnonOverflow | `http://<LAN_IP>:8480` | `https://anonymousoverflow.<domain>:8443/` | VPN-routed; upstream sees VPN IP. |
| Scribe | `http://<LAN_IP>:8280` | `https://scribe.<domain>:8443/` | VPN-routed; upstream sees VPN IP. |
| Odido Booster | `http://<LAN_IP>:8085` | `https://odido.<domain>:8443/` | NL Odido automated booster UI. |

<details>
<summary><strong>🔧 Add Your Own Services</strong> (advanced, not needed for new users)</summary>

Everything lives in `zima.sh`, so one run rebuilds Docker Compose and the dashboard. Keep the service name consistent everywhere (Compose, monitoring, and UI IDs).

### 1) Add it to Compose (SECTION 13)

```bash
if should_deploy "myservice"; then
cat >> "$COMPOSE_FILE" <<EOF
  myservice:
    image: my-image:latest
    container_name: myservice
    networks: [frontnet]
    restart: unless-stopped
EOF
fi
```

If you want the service to run through the VPN, use `network_mode: "service:gluetun"` and `depends_on: gluetun` like the existing privacy frontends.

### 2) Monitoring & Health (status pill)

Update the service status loop inside the `wg-control.sh` heredoc in `zima.sh` (search for `Check individual privacy services status internally`).

- Add `"myservice:1234"` to the `for srv in ...` list.
- If the service is routed through Gluetun, add `myservice` to the case that maps `TARGET_HOST="gluetun"`.
- Optional: add a Docker `healthcheck` to surface `Healthy` rather than just `Online`.

### 3) Dashboard Card + Metrics + Portainer

Add a card in the dashboard HTML (SECTION 14 in `zima.sh`):

- Use `id="link-myservice"` and `data-container="myservice"`.
- Set `data-url="http://$LAN_IP:<port>"` for the LAN link.
- Add a `portainer-link` chip if you want one-click container management.
- Add a `metrics-myservice` block if you want CPU/memory chips to show.

Then add the service to the `const services = { ... }` map so the dashboard can auto-switch links to `https://<subdomain>.<domain>:8443/` when <sup>[3](#explainer-3)</sup> is configured.

### 4) Watchtower Updates

- Watchtower updates all image-based containers by default.
- It runs once every day at 3 AM.
- You can trigger a manual check via the "Check" button on the dashboard.

### 5) Selective Service Updates

The "Update All" button now opens a selection window:
- **Granular Control**: Choose exactly which services to update.
- **Opt-Out**: All available updates are selected by default; uncheck specific ones to skip.
- **Fetch Status**: Real-time feedback on the update scanning process.
- **Changelogs**: View "What's New" for each service directly in the dashboard before updating.
    - **Source Services**: Displays specific git commits (HEAD..upstream).
    - **Image Services**: Fetches latest release notes from GitHub/Codeberg APIs (e.g., AdGuard, Portainer).
- **Automated Maintenance**: The update engine automatically performs the following for each selected service:
    1.  **Backup**: Creates a pre-update backup.
    2.  **Pull**: Fetches the latest source code or images.
    3.  **Build**: Rebuilds the container.
    4.  **Migrate**: Runs necessary database migrations.
    5.  **Vacuum**: Optimizes the database (VACUUM) if supported.

### 6) Intelligent Rollback

If an update causes issues, the system includes a robust rollback mechanism:
- **Data Restoration**: Automatically restores the most recent database dump (`.sql` or volume snapshot).
- **Version Revert**: 
    - For source builds, resets `git` to the previous commit hash.
    - For images, instructions are provided to revert tags if needed.
- **Trigger**: Accessible via the `migrate.sh` helper or manual API call.
- **Automation**: Migration, backup, and rollback processes are fully automated by the update engine. No manual intervention is required for standard maintenance.

### 7) Logs & Monitoring

The Update banner checks git repos under `/app/sources/<service>`. If you want your service to appear there, keep its source repo in that path with a remote configured.

</details>

## 🖥️ System Requirements

Ensure your host meets these specifications for optimal performance, especially during build processes for services like Invidious, Wikiless, and BreezeWiki.

| Specification | Minimum | Recommended |
| :--- | :--- | :--- |
| **Processor** | 2 Physical Cores | 4+ Physical Cores (8+ Threads) |
| **RAM** | 4 GB | 8 GB+ |
| **Storage** | 20 GB | 40 GB+ (SSD preferred) |
| **OS** | Linux (Ubuntu/Debian/Alpine) | Linux (Ubuntu/Debian/Alpine) |
| **Architecture** | amd64 / arm64 | amd64 |

### Scaling by User Capacity

Resource usage scales primarily with simultaneous browsing and background sync tasks. For the best experience, prioritize **Physical Cores** over logical threads for heavy tasks like source builds.

| User Count | Physical Cores | Logical Threads (SMT) | RAM | Performance Notes |
| :--- | :--- | :--- | :--- | :--- |
| **1-2 Users** | 2 | 2-4 | 4 GB | Baseline. Fast browsing for a single household. |
| **3-10 Users** | 4 | 8 | 8 GB | Recommended for small groups. Handles 4K streams well. |
| **10-30+ Users** | 8 | 16 | 16 GB | High-capacity. Suitable for small communities or public instances. |

### Internal Resource Management (Container Isolation)

To ensure stability and prevent any single service from exhausting host resources, this stack utilizes native **Docker Resource Limits** (configured in `docker-compose.yml` via `zima.sh`).

- **Total Reserved Limit:** The combined maximum RAM limit for all services is capped at approximately **7.5 GB**. 
- **Isolation:** Even if one service (like Invidious) experiences a traffic spike, it cannot exceed its assigned limit (e.g., 1.5 Threads, 1 GB RAM), preserving the responsiveness of the Dashboard and AdGuard.
- **Scaling Capability:** The current configuration is pre-tuned to support up to **30 users** on a machine with 16 GB RAM, leaving 50% of host memory for the OS, filesystem cache, and Docker overhead.

> **Note:** Building containers from source (e.g., Invidious, Wikiless, BreezeWiki) is the most intensive task. On systems with fewer than **4 logical threads**, updates may cause temporary UI lag for other users during the compilation phase. Physical cores significantly improve build speed compared to logical threads.

## 🌐 Network Configuration

### Standard Setup
Forward port **51820/UDP** to your host's local IP. This is the only exposed port and is cryptographically silent.

### Router Integration (Default DNS)
To protect your entire network, set your router's **LAN DNS** (not WAN DNS) to the local IP of this stack. This ensures all DHCP clients automatically use AdGuard Home for filtering.

### DNS Hijacking (Forced Resolution)
Many "smart" devices (TVs, IoT) hardcode their own DNS (like `8.8.8.8`) to bypass local filters. You can "elevate" your setup by creating a **NAT Redirect** rule on your router:
- **Rule:** Redirect all traffic on port `53` (TCP/UDP) not originating from the Privacy Hub to the Privacy Hub's IP.
- This forces rogue devices to use your filtered DNS even if they think they are talking to Google or Cloudflare.
- **Advanced Blocking:** You can also explore blocking or redirecting other DNS ports such as `853` (DNS-over-TLS & DNS-over-QUIC) or port `443` for known DoH (DNS-over-HTTPS) endpoints to further close these bypass holes.

> **Note on Network Engineering:** While I personally use OpenWrt to implement these advanced redirects and encourage you to explore these techniques to harden your network, this project is not specifically a network engineering suite. My focus here is on providing the privacy frontends and the DNS filtering core; how you "force" your network to use them is a great area for personal exploration and learning.

> **Note on Certificate Pinning:** While DNS hijacking works for standard DNS, some high-security apps use **Certificate Pinning** combined with hardcoded Encrypted DNS (DoH/DoT) to prevent any interference. In these cases, the app may refuse to connect if it detects its traffic is being rerouted or if it cannot verify the upstream certificate. This is a deliberate security feature of those apps and cannot be bypassed via DNS manipulation.
>
> **Blocking DoH:** To mitigate this, you can block common public DoH/DoT endpoints (port 853 and known DoH IPs on 443) at the firewall level. References for OpenWrt:
> - [OpenWrt: Intercept DNS](https://openwrt.org/docs/guide-user/firewall/firewall_configuration/intercept_dns)
> - [OpenWrt: Ban IP addresses](https://openwrt.org/docs/guide-user/firewall/firewall_configuration/ban_ip)

## 📡 Advanced Setup: OpenWrt & Double NAT

<details>
<summary><strong>CLI: UCI Commands for OpenWrt Configuration</strong></summary>

If you're running a secondary router like OpenWrt behind your ISP modem, use these commands to fix routing:

**1. Static IP Assignment**
```bash
uci add dhcp host
uci set dhcp.@host[-1].name='ZimaOS-Privacy-Hub'
uci set dhcp.@host[-1].mac='00:11:22:33:44:55' # <--- YOUR MAC
uci set dhcp.@host[-1].ip='192.168.1.100'      # <--- YOUR IP
uci commit dhcp
/etc/init.d/dnsmasq restart
```

**2. Firewall Port Forwarding (51820/UDP)**
```bash
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

**3. Forced DNS (DNS Hijacking)**
```bash
# Redirect all LAN port 53 traffic to the Privacy Hub
uci add firewall redirect
uci set firewall.@redirect[-1].name='Forced-DNS'
uci set firewall.@redirect[-1].src='lan'
uci set firewall.@redirect[-1].proto='tcpudp'
uci set firewall.@redirect[-1].src_dport='53'
uci set firewall.@redirect[-1].dest_ip='192.168.1.100' # <--- YOUR IP
uci set firewall.@redirect[-1].dest_port='53'
uci set firewall.@redirect[-1].target='DNAT'
```

uci commit firewall
/etc/init.d/firewall restart
```
</details>

## 🔒 Security & Credentials

- **HUB_API_KEY**: Required for sensitive dashboard actions. Can be rotated via UI.
- **Zero-Leaks Architecture**: This stack is designed for complete isolation. External assets (fonts, icons, and scripts) are fetched only once during the initial setup or when the local cache is invalidated. These requests are made via **Fontlay** ([Privacy Policy](https://github.com/miroocloud/fontlay)) and **JSDelivr** ([Privacy Policy](https://www.jsdelivr.com/terms/privacy-policy)), then stored and served locally to ensure your machine never communicates with these providers during regular use.
- **Anonymized Fetching (CDN Proxying)**: To eliminate host IP exposure, all external asset downloads and changelog retrievals performed by the Management Hub are routed through the **Gluetun VPN proxy**. Even during maintenance or background updates, your public home IP remains hidden from third-party CDNs and asset providers.
- **Data Minimization & Fingerprinting**: While requests are proxied to hide your IP, upstream providers (GitHub, JSDelivr) may still log standard access metadata (timestamp, requested resource). However, because these requests originate from the isolated `hub-api` container using a generic User-Agent, they cannot fingerprint your specific host device, browser, or operating system. They see a generic Linux client coming from a commercial VPN IP.
- **Material Design 3 Compliance**: The dashboard strictly adheres to M3 specifications (`m3.material.io`). Dynamic color generation is powered by the [material-color-utilities](https://github.com/material-foundation/material-color-utilities) library, ensuring an accessible and consistent visual experience.

### External Assets & Libraries

This project stands on the shoulders of these incredible open-source projects and assets:

- **Fonts**: [Google Sans Flex](https://fonts.google.com/specimen/Google+Sans+Flex), [Cascadia Code](https://github.com/microsoft/cascadia-code), and [Material Symbols](https://fonts.google.com/icons).
- **Icons**: [Material Symbols Rounded](https://fonts.google.com/icons?icon.style=Rounded).
- **Backend Libraries**: [psutil](https://github.com/giampaolo/psutil) (System monitoring), [SQLite](https://www.sqlite.org/) (Logging & Metrics).
- **Frontend Libraries**: [@material/material-color-utilities](https://github.com/material-foundation/material-color-utilities) (M3 Color Engine) - *Fetched via JSDelivr proxy*.
- **Infrastructure**: [Gluetun](https://github.com/qdm12/gluetun) (VPN Gateway), [Unbound](https://github.com/NLnetLabs/unbound) (Recursive DNS), [AdGuard Home](https://github.com/AdguardTeam/AdGuardHome) (DNS Filtering).
- **Redaction Mode**: "Privacy Masking" blurs IPs and sensitive metadata for screenshots.
- **Secrets**: Core credentials stored in `/DATA/AppData/privacy-hub/.secrets`.

### API Keys & Cost Notes

- **deSEC**: Domain + API token for <sup>[2](#explainer-2)</sup> and <sup>[3](#explainer-3)</sup> automation.
- **Docker Hub / <sup>[1](#explainer-1)</sup>**: Username + <sup>[4](#explainer-4)</sup> for registry pulls and rate-limit avoidance.
- **Odido Booster (NL unlimited data)**: OAuth token + user ID for Dutch Odido customers using the booster. The Odido API may incur costs or limits you are not expecting; use at your own risk.
- **Optional**: GitHub token (gist scope) for the Scribe frontend.

External services, registries, and APIs can change terms, rate limits, or pricing without notice. Usage is at your own risk, and the same caution applies to anything in this script that talks to third-party systems.

This script is provided as-is and may change whenever necessary or when I feel like it. Contributions are welcome, but I cannot guarantee updates will not break your setup. If you need to return to a clean state, the `-x` option removes everything and brings you back to where you were before running the script.

### Proton Pass Export (Auto-Generated Credentials)

When you run with `-p` (auto-passwords), the script generates a Proton Pass import CSV at `/DATA/AppData/privacy-hub/protonpass_import.csv`.

<details>
<summary><strong>👇 How to Import into Proton Pass</strong></summary>

1.  **Download the CSV**: Transfer `/DATA/AppData/privacy-hub/protonpass_import.csv` from your server to your local machine.
2.  **Open Proton Pass**: Go to Settings → Import.
3.  **Select Proton Pass (CSV)**: Choose the "Proton Pass (CSV)" option (or generic CSV).
4.  **Upload**: Select the file. The columns are pre-formatted to match the official Proton Pass template:
    `name,url,email,username,password,note,totp,vault`

> **Note**: You can safely delete the CSV file from the server after importing.
</details>

| Entry | URL | Username | Password | Note |
| :--- | :--- | :--- | :--- | :--- |
| AdGuard Home | `http://<LAN_IP>:8083` | `adguard` | AdGuard password | DNS filtering UI. |
| WireGuard VPN UI | `http://<LAN_IP>:51821` | `admin` | WireGuard UI password | Remote access management. |
| Portainer UI | `http://<LAN_IP>:9000` | `portainer` | Portainer password | Container management. |
| deSEC DNS API | (none) | your deSEC domain | deSEC API token | <sup>[2](#explainer-2)</sup> + <sup>[3](#explainer-3)</sup> automation. |
| GitHub Scribe Token | (none) | GitHub username | GitHub token | Scribe gist access. |

- **Source repositories (build-from-source + update checks)**:
  - GitHub: [privacy policy](https://docs.github.com/en/site-policy/privacy-policies/github-privacy-statement)
  - SourceHut: [privacy policy](https://man.sr.ht/privacy.md)

### DHI Hardened Builds & Patches

This stack prioritizes security by utilizing **<sup>[1](#explainer-1)</sup>**. The following services are either built directly from <sup>[1](#explainer-1)</sup> base images or patched during setup to replace standard images with hardened alternatives:

- **Dashboard**: Built on `dhi.io/nginx`
- **Hub API**: Built on `dhi.io/python`
- **Wikiless**: Patched to use `dhi.io/node` and `dhi.io/alpine-base`
- **Scribe**: Patched to use `dhi.io/node` and `dhi.io/alpine-base`
- **BreezeWiki**: Patched to use `dhi.io/alpine-base`
- **Odido Booster**: Patched to use `dhi.io/python`
- **VERT / VERTD**: Patched to use `dhi.io/node`, `dhi.io/bun`, and `dhi.io/nginx`

Infrastructure services **Redis** (`dhi.io/redis`) and **PostgreSQL** (`dhi.io/postgres`) also utilize <sup>[1](#explainer-1)</sup>-provided hardened images.

---
*Built with ❤️ for the self-hosting community.*
