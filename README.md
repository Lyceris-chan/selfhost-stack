# 🛡️ ZimaOS Privacy Hub

**Stop being the product.**
A comprehensive, self-hosted privacy infrastructure designed for digital independence. Route your traffic through secure VPNs, eliminate tracking with isolated frontends, and manage everything from a unified **Material Design 3** dashboard.

---

## 🚀 Key Features

*   **🔒 Data Independence**: Host your own frontends (Invidious, Redlib, etc.) to stop upstream giants like Google and Reddit from profiling you.
*   **🚫 Ad-Free by Design**: Network-wide ad blocking via AdGuard Home + native removal of sponsored content in video/social feeds.
*   **🕵️ VPN-Gated Privacy**: All external requests are routed through a **Gluetun VPN** tunnel. Upstream providers only see your VPN IP, keeping your home identity hidden.
*   **📱 No App Prompts**: Premium mobile-web experience without "Install our app" popups.
*   **🎨 Material Design 3**: A beautiful, responsive dashboard with dynamic theming and real-time health metrics.

---

## ⚡ Quick Start

**Ready to launch?** Run this single command on your ZimaOS terminal:

```bash
./zima.sh -p -y
```

This **Automated Mode**:
1.  Generates secure passwords automatically.
2.  Builds the entire privacy stack (~15 mins).
3.  Exports credentials to `protonpass_import.csv` for safe keeping.

---

## 📚 Contents

1.  [Getting Started](#-getting-started)
2.  [Dashboard & Services](#-dashboard--services)
3.  [Network Configuration](#-network-configuration)
4.  [Advanced Setup (OpenWrt)](#-advanced-setup-openwrt--double-nat)
5.  [Privacy & Architecture](#-privacy--architecture)
6.  [Security Standards](#-security-standards)
7.  [System Requirements](#-system-requirements)
8.  [Troubleshooting](#-troubleshooting)
9.  [Maintenance](#-maintenance)

---

## 🏗️ Getting Started

### Prerequisites

Gather these essentials before starting the installation. Each token should be created with the **least privilege** required.

#### 🛠️ Essential Tokens
*   **Docker Hub Account**: Required to pull hardened images and avoid rate limits.
    *   **Token Rights**: Create a "Personal Access Token" with **Public Read-only** (or Read-only) permissions.
    *   **Source**: [Docker Hub Security Settings](https://hub.docker.com/settings/security).
*   **ProtonVPN WireGuard Config**: Critical for the `Gluetun` VPN gateway to mask your IP.
    *   **Source**: [ProtonVPN Downloads](https://account.protonvpn.com/downloads). (See [ProtonVPN Guide](#-protonvpn-wireguard-setup) below).
*   **deSEC Domain (Optional)**: For trusted SSL certificates and mobile "Private DNS" support.
    *   **Source**: [deSEC.io](https://desec.io).

#### 🔧 Service-Specific Secrets (Optional)
*   **GitHub Token**: Required for the **Scribe** frontend to avoid API rate limits.
    *   **Token Rights**: "Classic" token with `gist` scope only.
    *   **Source**: [GitHub Personal Access Tokens](https://github.com/settings/tokens).
*   **Odido OAuth Token**: For Dutch users utilizing the **Odido Booster**.
    *   **Source**: [Odido Authenticator](https://github.com/GuusBackup/Odido.Authenticator/releases/latest).

---

<details>
<summary>📥 <strong>ProtonVPN WireGuard Setup</strong> (Click to expand)</summary>

1.  **Login** to your [ProtonVPN Account](https://account.protonvpn.com/downloads).
2.  Navigate to **Downloads** -> **WireGuard configuration**.
3.  **Name** your configuration (e.g., `Zima-Privacy-Hub`).
4.  Select a **Free** (or Paid) server in your preferred region.
5.  **Toggle ON** "NAT-PMP" (Optional but recommended).
6.  **Download** the `.conf` file.
7.  **Usage**: You will be prompted to paste the text content of this file during installation.

> 🛡️ **Privacy Impact**: Without this config, your home IP is exposed to YouTube/Reddit. With it, they only see Proton's commercial IP.
</details>

<details>
<summary>🔑 <strong>Token & Secret Guides</strong> (Click to expand)</summary>

*   **Docker Hub PAT**:
    1. Go to [Security Settings](https://hub.docker.com/settings/security).
    2. Click **New Access Token**.
    3. Set Access permissions to **Read-only**.
*   **GitHub PAT (Scribe)**:
    1. Go to [Token Settings](https://github.com/settings/tokens).
    2. Select **Generate new token (classic)**.
    3. Check **only** the `gist` box.
*   **deSEC Domain**:
    1. Register at [deSEC.io](https://desec.io).
    2. Create a domain (e.g., `your-name.dedyn.io`).
    3. Generate an API token in the dashboard.
</details>

---

### Installation

**Standard Interactive Install**:
```bash
./zima.sh
```

**Custom Flags**:
| Flag | Description |
| :--- | :--- |
| `-p` | **Auto-Passwords**: Generates random secure credentials. |
| `-y` | **Auto-Confirm**: Skips yes/no prompts (Headless mode). |
| `-a` | **Allow Proton (Optional)**: **Not required**. Whitelists ProtonVPN domains in AdGuard. (Author uses this for personal usage to enable the **Proton VPN Browser Extension**). |
| `-c` | **Maintenance Reset**: Removes only the containers and networks created by this stack to resolve glitches. strictly preserves persistent user data. Does not touch unrelated containers. |
| `-x` | **REVERT (Factory Reset)**: ⚠️ **Targeted Cleanup** - This erases only the software and databases added by this specific project. It does not touch your personal files or other Docker containers you may have running. |
| `-s` | **Selective**: Deploy only specific services (e.g., `-s invidious,memos`). |

> ⚠️ **VPN Access Warning**: When you are connected to a commercial VPN (like ProtonVPN, NordVPN, etc.) directly on your device, you will **not** be able to access your Privacy Hub services. You must be connected to your home **WireGuard (wg-easy)** tunnel to reach them remotely. Using a different VPN will result in a `Connection Timed Out` or `DNS_PROBE_FINISHED_NXDOMAIN` error because your device can no longer "see" your home network.

### ✅ Verification

After installation, verify your stack:
1.  **Dashboard**: `http://<LAN_IP>:8081` (Should be accessible).
2.  **VPN Check**: `docker exec gluetun wget -qO- http://ifconfig.me` (Should show VPN IP).
3.  **DNS Check**: `dig @localhost example.com` (Should resolve).

---

## 🖥️ Dashboard & Services

Access your unified control center at `http://<LAN_IP>:8081`.

### Included Privacy Services

| Service | Source | Category | Description |
| :--- | :--- | :--- | :--- |
| **Invidious** | [iv-org/invidious](https://github.com/iv-org/invidious) | Frontend | YouTube without ads or tracking. |
| **Redlib** | [redlib-org/redlib](https://github.com/redlib-org/redlib) | Frontend | Private Reddit viewer. |
| **Rimgo** | [rimgo/rimgo](https://codeberg.org/rimgo/rimgo) | Frontend | Anonymous Imgur browser. |
| **Wikiless** | [Metastem/Wikiless](https://github.com/Metastem/Wikiless) | Frontend | Private Wikipedia reader. |
| **Scribe** | [edwardloveall/scribe](https://git.sr.ht/~edwardloveall/scribe) | Frontend | Alternative Medium frontend. |
| **BreezeWiki** | [breezewiki/breezewiki](https://gitdab.com/cadence/breezewiki) | Frontend | De-fandomized Wiki interface. |
| **AnonOverflow** | [httpjamesm/anonymousoverflow](https://github.com/httpjamesm/anonymousoverflow) | Frontend | Private Stack Overflow viewer. |
| **Memos** | [usememos/memos](https://github.com/usememos/memos) | Utility | Self-hosted notes & knowledge base. |
| **VERT** | [vert-sh/vert](https://github.com/vert-sh/vert) | Utility | Secure local file conversion. |
| **AdGuard Home** | [AdguardTeam/AdGuardHome](https://github.com/AdguardTeam/AdGuardHome) | Core | Network-wide DNS ad-blocking. |
| **WireGuard** | [wg-easy/wg-easy](https://github.com/wg-easy/wg-easy) | Core | Secure remote access gateway. |

> **Note**: All "Frontend" services are routed through the VPN tunnel automatically.

---

## 🌐 Network Configuration

To fully utilize the stack, configure your network:

### 1. Remote Access (VPN)
Forward **UDP Port 51820** on your router to your ZimaOS device.
*   This allows you to connect *back* to your home securely from anywhere using the WireGuard app.

### 2. DNS Protection
Point your router's **Primary DNS** to your ZimaOS IP address.
*   This forces all devices on your WiFi to use AdGuard Home for ad-blocking.
*   **Important**: Disable "Random MAC Address" on your devices for persistent protection.

### 3. Mobile Private DNS (Android)
If you configured deSEC:
*   Set your Android "Private DNS" to: `your-domain.dedyn.io`
*   You now have ad-blocking and encryption on 4G/5G without a VPN app!

### 4. Split Tunnel Configuration & Bandwidth Optimization
This stack uses a **Dual Split Tunnel** architecture via Gluetun and WG-Easy to ensure performance:
*   **VPN-Gated Services (Gluetun)**: Privacy frontends (Invidious, Redlib, etc.) are locked inside the VPN container. They cannot access the internet if the VPN disconnects (Killswitch enabled).
*   **Remote Access Optimization (WG-Easy)**: When connected via the WireGuard app, only your requests to the Hub and DNS queries are sent home. This preserves your mobile data and speed: high-bandwidth streaming services like Netflix or native YouTube apps maintain their full, direct speed on your device rather than being forced to route back through your home upload connection first.
*   **Local-Direct Services**: Core management tools (Dashboard, Portainer, AdGuard UI) remain accessible directly via your LAN IP. This ensures you never lose control of your hub even if the VPN provider has an outage.

---

## 📡 Advanced Setup: OpenWrt & Double NAT

If you are running a real router like **OpenWrt** behind your ISP modem, you are in a **Double NAT** situation. You need to fix the routing so your packets actually arrive.

### 1. Static IP Assignment (DHCP Lease)
Assign a static lease so your Privacy Hub doesn't wander off to a different IP every time the power cycles.

<details>
<summary>💻 <strong>CLI: UCI Commands for Static Lease</strong> (Click to expand)</summary>

```bash
# Add the static lease (Replace MAC and IP with your own hardware's values)
uci add dhcp host
uci set dhcp.@host[-1].name='ZimaOS-Privacy-Hub'
uci set dhcp.@host[-1].mac='00:11:22:33:44:55' # <--- REPLACE THIS WITH YOUR MAC
uci set dhcp.@host[-1].ip='192.168.1.100'      # <--- REPLACE THIS WITH YOUR DESIRED IP
uci commit dhcp
/etc/init.d/dnsmasq restart
```
</details>

### 2. Port Forwarding & Firewall
OpenWrt is the gatekeeper. Point the traffic to your machine and then actually open the door.

<details>
<summary>💻 <strong>CLI: UCI Commands for Firewall</strong> (Click to expand)</summary>

```bash
# 1. Add Port Forwarding (Replace dest_ip with your ZimaOS machine's IP)
uci add firewall redirect
uci set firewall.@redirect[-1].name='Forward-WireGuard'
uci set firewall.@redirect[-1].src='wan'
uci set firewall.@redirect[-1].proto='udp'
uci set firewall.@redirect[-1].src_dport='51820'
uci set firewall.@redirect[-1].dest_ip='192.168.1.100' # <--- REPLACE THIS WITH YOUR IP
uci set firewall.@redirect[-1].dest_port='51820'
uci set firewall.@redirect[-1].target='DNAT'

# 2. Add Traffic Rule (Allowance)
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-WireGuard-Inbound'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].dest_port='51820'
uci set firewall.@rule[-1].target='ACCEPT'

# Apply the changes
uci commit firewall
/etc/init.d/firewall restart
```
</details>

### 3. DNS Hijacking (Force Compliance)
Some devices (IoT, Smart TVs) hardcode DNS servers (like `8.8.8.8`) to bypass your filters. You can force them to comply using a **NAT Redirect** rule.

To implement this on your router, refer to the following official guides:
*   [OpenWrt Guide: Intercepting DNS](https://openwrt.org/docs/guide-user/firewall/fw3_configurations/intercept_dns) (Step-by-step NAT Redirection)
*   [OpenWrt Guide: Blocking DoH (banIP)](https://openwrt.org/docs/guide-user/firewall/firewall_configuration/ban_ip) (Preventing filter bypass via encrypted DNS)

---

## 🛡️ Privacy & Architecture

### The "Trust Gap"
If you don't own the hardware and the code running your network, you don't own your privacy. You're just renting a temporary privilege.

<details>
<summary>🔍 <strong>Deep Dive: Why Self-Host?</strong> (Click to expand)</summary>

*   **The Google Profile**: Google's DNS (8.8.8.8) turns you into a data source. They build profiles on your health, finances, and interests based on every domain you resolve.
*   **The Cloudflare Illusion**: Even "neutral" providers can be forced to censor content by local governments.
*   **ISP Predation**: Your ISP sees everything. They log, monetize, and sell your browsing history to data brokers.

**This stack cuts out the middleman.**
</details>

### Zero-Leaks Asset Architecture
External assets (fonts, icons, scripts) are fetched once via the **Gluetun VPN proxy** and served locally. Your public home IP is never exposed to CDNs.

**Privacy Enforcement Logic:**
1.  **Container Initiation**: When the Hub API container starts, it initiates an asset verification check.
2.  **Proxy Routing**: If assets are missing, the Hub API routes download requests through the Gluetun VPN container (acting as an HTTP proxy on port 8888).
3.  **Encapsulated Fetching**: All requests to external CDNs (Fontlay, JSDelivr) occur *inside* the VPN tunnel. Upstream providers only see the VPN IP.
4.  **Local Persistence**: Assets are saved to a persistent Docker volume (`/assets`).
5.  **Offline Serving**: The Management Dashboard (Nginx) serves all UI resources exclusively from this local volume.

### Recursive DNS Engine (Independent Resolution)
*   **Zero Third-Parties**: We bypass "public" resolvers like **Google** and **Cloudflare**.
*   **QNAME Minimization**: Only sends absolute minimum metadata upstream (RFC 7816).
*   **Encrypted Local Path**: Native support for **DoH** (RFC 8484) and **DoQ** (RFC 9250).
*   **High Performance**: 
    *   **Intelligent Caching**: Large message and RRset caches reduce external lookups.
    *   **Proactive Prefetching**: Frequently requested records are renewed before they expire.
    *   **Glue Hardening**: Protects against cache poisoning by strictly verifying delegation records.
    *   **0x20 Bit Randomization**: Mitigates spoofing attempts through query casing.

### 🛡️ Blocklist Information & DNS Filtering
*   **Source**: Blocklists are generated using the [Lyceris-chan DNS Blocklist Generator](https://github.com/Lyceris-chan/dns-blocklist-generator/).
*   **Composition**: Based on **Hagezi Pro++**, curated for performance and dutch users.
*   **Note**: This blocklist is **aggressive** by design.

### 📦 Docker Hardened Images (DHI)
This stack utilizes **Digital Independence (DHI)** images (`dhi.io`) to ensure maximum security. These images follow the principle of least privilege by stripping unnecessary binaries and telemetry.

**Transparent Hardening**:
To ensure transparency, the deployment script [dynamically patches](https://github.com/Lyceris-chan/selfhost-stack/blob/main/zima.sh#L6229) upstream Dockerfiles during build to replace standard base images with hardened alternatives:
*   **Node.js**: Replaced with `dhi.io/node:20-alpine3.22-dev`
*   **Bun**: Replaced with `dhi.io/bun:1-alpine3.22-dev`
*   **Python**: Replaced with `dhi.io/python:3.11-alpine3.22-dev`
*   **Alpine Base**: All Alpine-based services are repinned to `dhi.io/alpine-base:3.22-dev`
*   **Nginx**: The dashboard uses `dhi.io/nginx:1.28-alpine3.21`

### 🛡️ Self-Healing & High Availability
*   **VPN Monitoring**: Gluetun is continuously monitored. Docker restarts the gateway if the tunnel stalls.
*   **Frontend Auto-Recovery**: Privacy frontends utilize `restart: always`.
*   **Health-Gated Launch**: Infrastructure services must be `healthy` before frontends start.

### Data Minimization & Anonymity
*   **Specific User-Agent Signatures**: Requests use industry-standard signatures to blend in.
*   **Zero Personal Data**: No API keys or hardware IDs are transmitted during checks.
*   **Isolated Environment**: Requests execute from within containers without host-level access.

---

## 🔒 Security Standards

### DHI Hardened Images
We don't use standard "official" images where we can avoid it. We use **DHI hardened images** (`dhi.io`).
*   **Why?**: Standard images are often packed with "convenience" tools that are security liabilities.
*   **The Benefit**: Hardened images minimize the attack surface by removing unnecessary binaries and libraries, following the principle of least privilege. (Concept based on [CIS Benchmarks](https://www.cisecurity.org/benchmark/docker) and minimal base image best practices).

### The "Silent" Security Model
Opening a port for WireGuard does **not** expose your home to scanning.
*   **Silent Drop**: WireGuard does not respond to packets it doesn't recognize. To a scanner, the port looks closed.
*   **DDoS Mitigation**: Because it's silent to unauthenticated packets, it is inherently resistant to flooding attacks.
*   **Cryptographic Ownership**: You can't "guess" a password. You need a valid 256-bit key.

---

## 🖥️ System Requirements

### Verified Environment (ZimaOS)
*   **CPU**: Intel® Core™ i3-10105T @ 3.00GHz (or better)
*   **RAM**: 8 GB Recommended (4 GB Minimum)
*   **Storage**: 64 GB SSD Recommended (32 GB Minimum)
*   **OS**: ZimaOS, Ubuntu 22.04 LTS, or Debian 12+

### Performance Expectations
*   **Validation**: 1-2 min
*   **Build & Deploy**: 15-25 min (Source compilation is CPU-intensive)

---

## 🔧 Troubleshooting

| Issue | Potential Solution |
| :--- | :--- |
| **"My internet broke!"** | DNS resolution likely failed. Set your router DNS to `9.9.9.9` or `1.1.1.1` temporarily to restore access, then restart the Hub. |
| **"I can't connect remotely"** | **1.** Check Port 51820 forwarding. **2.** Verify Double NAT (Forward on both ISP and OpenWrt routers). **3.** Check for CGNAT. |
| **"Services are slow"** | **1.** Check VPN speed in dashboard. **2.** Try a different ProtonVPN server config. **3.** Monitor system CPU/RAM usage. |
| **"SSL is invalid"** | Ensure port 80/443 aren't blocked and your deSEC token is correct. Check `certbot/monitor.log`. |

> 💡 **Pro-Tip**: Use `docker ps` to verify all containers are `Up (healthy)`. If a container is stuck, use `docker logs <name>` to see why.

---

## 💾 Maintenance

*   **Update**: Click "Check Updates" in the dashboard or run `./zima.sh` again.
*   **Backup**:
    ```bash
    # Manual backup of critical data (Secrets, Configs, Databases)
    cp -r /DATA/AppData/privacy-hub /backup/location/
    ```
*   **Uninstall**:
    ```bash
    ./zima.sh -x
    ```
    *(Note: This **only** removes the containers and volumes created by this specific privacy stack. Your personal documents, photos, and unrelated Docker containers are **never** touched.)*

---

## 🧩 Advanced Usage: Add Your Own Services

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

### 3) Dashboard UI (Dynamic Catalog)
The dashboard renders cards dynamically from a `services.json` file. To add your service to the UI, find the **`SERVICES_JSON`** block in `zima.sh` (Section 13) and add a new entry:

```json
"myservice": {
  "name": "My Service",
  "description": "Short description of what it does.",
  "category": "apps",
  "order": 100,
  "url": "http://\$LAN_IP:1234"
}
```
*   **Category**: Use `apps`, `system`, or `tools`.
*   **Order**: Determines the display position in the grid.
*   **Actions**: (Optional) Add buttons for migrations or maintenance.

### 4) Watchtower Updates

- Watchtower updates all image-based containers by default.
- To opt out, add `com.centurylinklabs.watchtower.enable=false` under the service labels.
- For build-based services, Watchtower won't rebuild; re-run `./zima.sh` or use the dashboard Update flow.

### 5) Dashboard Update Banner (optional)

The Update banner checks git repos under `/app/sources/<service>`. If you want your service to appear there, keep its source repo in that path with a remote configured.

</details>

<details>
<summary><strong>🧪 Automated Verification</strong> (Click to expand)</summary>

To ensure a "set and forget" experience, every release undergoes a rigorous automated verification pipeline:
*   **Interaction Audit**: Puppeteer-based suite simulates real user behavior.
*   **Non-Interactive Deployment**: verified `-p -y` flow for zero-prompt success.
*   **M3 Compliance Check**: Automated layout audits ensure the dynamic grid and chips adapt to any screen size.
*   **Log & Metric Integrity**: Container logs audited for 502/504 errors.
</details>

<details>
<summary><strong>External Services & Privacy Policies</strong></summary>

- **Public IP Detection & Health**:
  - [ipify.org](https://www.ipify.org/) (IP retrieval)
  - [ip-api.com](https://ip-api.com/docs/legal) (IP retrieval)
  - [connectivity-check.ubuntu.com](https://ubuntu.com/legal/data-privacy) (VPN health check)
- **Infrastructure & Automation**:
  - [deSEC.io](https://desec.io/privacy-policy) (DNS & SSL automation)
  - [fontlay.com](https://github.com/miroocloud/fontlay) (Google Fonts proxy)
  - [cdn.jsdelivr.net](https://www.jsdelivr.com/terms/privacy-policy-jsdelivr-net) (MCU library hosting)
- **Container Registries & Sources**:
  - [Docker Hub / dhi.io](https://www.docker.com/legal/docker-privacy-policy/) (Hardened images)
  - [GitHub / GHCR](https://docs.github.com/en/site-policy/privacy-policies/github-privacy-statement) (Sources & Images)
  - [Codeberg](https://codeberg.org/privacy) (Sources & Images)
  - [Quay.io](https://quay.io/privacy) (Images)
  - [SourceHut](https://man.sr.ht/privacy.md) (Scribe source)
  - [Gitdab](https://gitdab.com/) (BreezeWiki source)
- **DNS blocklist compiler ([sleepy list](https://github.com/Lyceris-chan/dns-blocklist-generator))**:
  - [Blocklist Retrieval](https://docs.github.com/en/site-policy/privacy-policies/github-privacy-statement) (Combines and filters out duplicates every 6 hours using the set of default lists provided by AdGuard, using **Hagezi Pro ++** as the anchor. Merges additional lists for broad coverage without false positives. *Note: This list is for personal usage and won't be updated to allow specific lists or for the usage of others.*)
- **Optional Service APIs**:
  - [Odido API](https://www.odido.nl/privacy) (Data bundle management)

</details>

---

## 🚨 Disclaimer

This software is provided "as is". While designed for security, the user is responsible for ensuring their specific network configuration is safe. **Do not use GitHub Codespaces for production deployment.**

---

*Built with ❤️ for digital sovereignty.*