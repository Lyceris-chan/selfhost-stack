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

1.  [Getting Started](#getting-started)
2.  [Dashboard & Services](#dashboard--services)
3.  [Network Configuration](#network-configuration)
4.  [Advanced Setup (OpenWrt)](#advanced-setup)
5.  [Privacy & Architecture](#privacy--architecture)
6.  [Security Standards](#security-standards)
7.  [System Requirements](#system-requirements)
8.  [Troubleshooting](#troubleshooting)
9.  [Maintenance](#maintenance)
10. [External Services & Privacy Policies](#external-services--privacy-policies)

---

<a id="getting-started"></a>
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

<a id="dashboard--services"></a>
## 🖥️ Dashboard & Services

Access your unified control center at `http://<LAN_IP>:8081`.

### Included Privacy Services

| Service | Source | Category | Description |
| :--- | :--- | :--- | :--- |
| **Invidious** | [iv-org/invidious](https://github.com/iv-org/invidious) ⁽[¹](https://github.com/iv-org/invidious/blob/master/docker/Dockerfile)⁾ | Frontend | YouTube without ads or tracking. |
| **Invidious Companion** | [iv-org/invidious-companion](https://github.com/iv-org/invidious-companion) ⁽[²](https://github.com/iv-org/invidious-companion/blob/master/Dockerfile)⁾ | Helper | Token generator for Invidious. |
| **Redlib** | [redlib-org/redlib](https://github.com/redlib-org/redlib) ⁽[³](https://github.com/redlib-org/redlib/blob/main/Dockerfile.alpine)⁾ | Frontend | Private Reddit viewer. |
| **Rimgo** | [rimgo/rimgo](https://codeberg.org/rimgo/rimgo) ⁽[⁴](https://codeberg.org/rimgo/rimgo/src/branch/main/Dockerfile)⁾ | Frontend | Anonymous Imgur browser. |
| **Wikiless** | [Metastem/Wikiless](https://github.com/Metastem/Wikiless) ⁽[⁵](https://github.com/Metastem/Wikiless/blob/main/Dockerfile)⁾ | Frontend | Private Wikipedia reader. |
| **Scribe** | [edwardloveall/scribe](https://git.sr.ht/~edwardloveall/scribe) ⁽[⁶](https://git.sr.ht/~edwardloveall/scribe/tree/master/item/Dockerfile)⁾ | Frontend | Alternative Medium frontend. |
| **BreezeWiki** | [breezewiki/breezewiki](https://gitdab.com/cadence/breezewiki) ⁽[⁷](https://github.com/PussTheCat-org/docker-breezewiki-quay/blob/master/docker/Dockerfile)⁾ | Frontend | De-fandomized Wiki interface. |
| **AnonOverflow** | [httpjamesm/anonymousoverflow](https://github.com/httpjamesm/anonymousoverflow) ⁽[⁸](https://github.com/httpjamesm/anonymousoverflow/blob/main/Dockerfile)⁾ | Frontend | Private Stack Overflow viewer. |
| **Memos** | [usememos/memos](https://github.com/usememos/memos) ⁽[⁹](https://github.com/usememos/memos/blob/main/scripts/Dockerfile)⁾ | Utility | Self-hosted notes & knowledge base. |
| **VERT** | [vert-sh/vert](https://github.com/vert-sh/vert) ⁽[¹⁰](https://github.com/VERT-sh/VERT/blob/main/Dockerfile)⁾ | Utility | Secure local file conversion UI. |
| **VERTd** | [vert-sh/vertd](https://github.com/VERT-sh/vertd) ⁽[¹¹](https://github.com/VERT-sh/vertd/blob/main/Dockerfile)⁾ | Utility | File conversion daemon. |
| **AdGuard Home** | [AdguardTeam/AdGuardHome](https://github.com/AdguardTeam/AdGuardHome) ⁽[¹²](https://github.com/AdguardTeam/AdGuardHome/blob/master/docker/Dockerfile)⁾ | Core | Network-wide DNS ad-blocking. |
| **Unbound** | [NLnetLabs/unbound](https://github.com/NLnetLabs/unbound) ⁽[¹³](https://github.com/klutchell/unbound-docker/blob/main/Dockerfile)⁾ | Core | Recursive DNS resolver. |
| **WireGuard** | [wg-easy/wg-easy](https://github.com/wg-easy/wg-easy) ⁽[¹⁴](https://github.com/wg-easy/wg-easy/blob/master/Dockerfile)⁾ | Core | Secure remote access gateway. |
| **Gluetun** | [qdm12/gluetun](https://github.com/qdm12/gluetun) ⁽[¹⁵](https://github.com/qdm12/gluetun/blob/master/Dockerfile)⁾ | Core | VPN client and port forwarding gateway. |
| **Portainer** | [portainer/portainer](https://github.com/portainer/portainer) ⁽[¹⁶](https://github.com/portainer/portainer/blob/develop/build/linux/alpine.Dockerfile)⁾ | Core | Container management interface. |
| **Odido Booster** | [Lyceris-chan/odido-bundle-booster](https://github.com/Lyceris-chan/odido-bundle-booster) ⁽[¹⁷](https://github.com/Lyceris-chan/odido-bundle-booster/blob/main/Dockerfile)⁾ | Utility | Mobile data automation tool. |
| **Hub API** | [Local Source](/hub-api) | Core | Stack orchestration and API. |

> **Note**: All "Frontend" services are routed through the VPN tunnel automatically.

---

<a id="network-configuration"></a>
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

<a id="advanced-setup"></a>
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

<a id="privacy--architecture"></a>
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
*   **Hardened Security**:
    *   **DNSSEC Stripping Protection**: Rejects responses that have been stripped of security signatures.
    *   **Access Control**: Resolver strictly restricted to local RFC1918 subnets only.
    *   **Fingerprint Resistance**: Identity and version queries are explicitly hidden.
    *   **0x20 Bit Randomization**: Mitigates spoofing attempts through query casing.
    *   **Glue Hardening**: Strictly verifies delegation records to prevent cache poisoning.
*   **Optimized Performance**: 
    *   **Intelligent Caching**: Large message (50MB) and RRset (100MB) caches.
    *   **Proactive Prefetching**: Automatically renews popular records before they expire.
    *   **Minimal Responses**: Reduces packet size and amplification risks.

### 🛡️ Blocklist Information & DNS Filtering
*   **Source**: Blocklists are generated using the [Lyceris-chan DNS Blocklist Generator](https://github.com/Lyceris-chan/dns-blocklist-generator/).
*   **Composition**: Based on **Hagezi Pro++**, curated for performance and dutch users.
*   **Note**: This blocklist is **aggressive** by design.

### 📦 Docker Hardened Images (DHI)
This stack utilizes **Digital Independence (DHI)** images (`dhi.io`) to ensure maximum security. These images follow the principle of least privilege by stripping unnecessary binaries and telemetry.

**Transparent Hardening**:
To ensure transparency and compatibility, the deployment script [dynamically patches](zima.sh) upstream Dockerfiles during build. This **surgical hardening** replaces standard base images with hardened alternatives while preserving all original multi-stage structures (including `scratch` and `distroless` runtimes):
*   **Node.js**: Replaced with `dhi.io/node:20-alpine3.22-dev` (Build stage)
*   **Bun**: Replaced with `dhi.io/bun:1-alpine3.22-dev` (Build/Runtime)
*   **Python**: Replaced with `dhi.io/python:3.11-alpine3.22-dev` (Build/Runtime)
*   **Go**: Replaced with `dhi.io/golang:1-alpine3.22-dev` (Build stage)
*   **Alpine Base**: All Alpine-based services are repinned to `dhi.io/alpine-base:3.22-dev`
*   **Nginx**: The dashboard uses `dhi.io/nginx:1.28-alpine3.21`

**Automatic Version Pinning (Update Strategy)**:
The system supports two deployment strategies, configurable via the Management Dashboard:
*   **Stable (Default)**: Automatically identifies the latest semantic version tag (e.g., `v1.2.3`) across all git sources. This ensures a production-ready stack while still utilizing local hardened builds.
*   **Latest**: Tracks the default upstream branch (e.g., `main` or `master`) for bleeding-edge updates and immediate fixes.

### 🛡️ Self-Healing & High Availability
*   **VPN Monitoring**: Gluetun is continuously monitored. Docker restarts the gateway if the tunnel stalls.
*   **Frontend Auto-Recovery**: Privacy frontends utilize `restart: always`.
*   **Health-Gated Launch**: Infrastructure services must be `healthy` before frontends start.

### Data Minimization & Anonymity
*   **Specific User-Agent Signatures**: Requests use industry-standard signatures to blend in.
*   **Zero Personal Data**: No API keys or hardware IDs are transmitted during checks.
*   **Isolated Environment**: Requests execute from within containers without host-level access.

---

<a id="security-standards"></a>
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

<a id="system-requirements"></a>
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

<a id="troubleshooting"></a>
## 🔧 Troubleshooting

| Issue | Potential Solution |
| :--- | :--- |
| **"My internet broke!"** | DNS resolution failed. Temporarily set your router DNS to **Quad9** (`9.9.9.9`) or **Mullvad** (`194.242.2.2`) to restore access, then check the Hub status. |
| **"I can't connect remotely"** | **1.** Verify Port 51820 (UDP) is forwarded. **2.** If using OpenWrt, ensure "Double NAT" is handled (ISP -> OpenWrt -> Hub). **3.** Check if your ISP uses CGNAT. |
| **"Services are slow"** | **1.** Check VPN throughput in the dashboard. **2.** Try a different ProtonVPN server config. **3.** Ensure your host has sufficient CPU/RAM for compilation tasks. |
| **"SSL is invalid"** | Check `certbot/monitor.log` via dashboard. Ensure ports 80/443 are reachable for validation. Verify your deSEC token. |

> 💡 **Pro-Tip**: Use `docker ps` to verify all containers are `Up (healthy)`. If a container is stuck, use `docker logs <name>` to see why.

---

<a id="maintenance"></a>
## 💾 Maintenance

*   **Update**: Click "Check Updates" in the dashboard or run `./zima.sh` again.
*   **Backup**:
    ```bash
    # Manual backup of critical data (Secrets, Configs, Databases)
    cp -r /data/AppData/privacy-hub /backup/location/
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

The stack uses a modular generation system. To add a new service, you will need to modify the generator scripts in the `lib/` directory.

### 1) Add to Compose (`lib/compose_gen.sh`)

Locate the `generate_compose` function and add your service block:

```bash
    if should_deploy "myservice"; then
    cat >> "$COMPOSE_FILE" <<EOF
  myservice:
    image: my-image:latest
    container_name: myservice
    networks: [dhi-frontnet]
    restart: unless-stopped
EOF
    fi
```

If you want the service to run through the VPN, use `network_mode: "service:gluetun"` and `depends_on: gluetun`.

### 2) Monitoring & Health (`lib/scripts.sh`)

Update the service status loop inside the `generate_scripts` function (specifically the `wg_api.py` generation block or `wg_control.sh` template).

- Add `"myservice:1234"` to the service list in the API handler.
- If routed through Gluetun, map it to the `gluetun` target host.

### 3) Dashboard UI (`lib/scripts.sh`)

The dashboard catalog is generated in `lib/scripts.sh`. Find the `cat > "$SERVICES_JSON"` block and add your entry:

```json
"myservice": {
  "name": "My Service",
  "description": "Short description.",
  "category": "apps",
  "order": 100,
  "url": "http://\$LAN_IP:1234"
}
```

### 4) Watchtower Updates

- To opt out, add `com.centurylinklabs.watchtower.enable=false` under the service labels.
- For build-based services, the dashboard's "Update" feature handles the rebuild process.

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
<summary><strong>🌍 External Services & Privacy Policies</strong> (What connects where?)</summary>

We believe in radical transparency. Here is every external connection this stack makes.

### Connection Exposure Map

| Service / Domain | Purpose | Exposure |
| :--- | :--- | :--- |
| **Frontends (YouTube/Reddit)** | Privacy content retrieval | **🔒 VPN IP** (Gluetun) |
| **Dashboard Assets** | Fonts (Fontlay) & Icons (JSDelivr) | **🔒 VPN IP** (Proxied via Hub-API) |
| **VPN Client Management** | Managing WireGuard clients | **🔒 VPN IP** (Proxied via Hub-API) |
| **VPN Status & IP Check** | Tunnel health monitoring | **🔒 VPN IP** (Proxied via Hub-API) |
| **Health Checks** | VPN Connectivity Verification | **🔒 VPN IP** (Gluetun) |
| **Container Registries** | Pulling Docker images (Docker/GHCR) | **🏠 Home IP** (Direct) |
| **Git Repositories** | Cloning source code (GitHub/Codeberg) | **🏠 Home IP** (Direct) |
| **DNS Blocklists** | AdGuard filter updates | **🏠 Home IP** (Direct) |
| **deSEC.io** | SSL DNS Challenges | **🏠 Home IP** (Direct) |
| **Odido API** | Mobile Data fetching | **🏠 Home IP** (Direct/Proxied) |

### Detailed Privacy Policies

- **Public IP Detection & Health**:
  - [ipify.org](https://www.ipify.org/)
  - [ip-api.com](https://ip-api.com/docs/legal)
  - [connectivity-check.ubuntu.com](https://ubuntu.com/legal/data-privacy)
- **Infrastructure & Assets**:
  - [deSEC.io](https://desec.io/privacy-policy)
  - [fontlay.com](https://github.com/miroocloud/fontlay)
  - [cdn.jsdelivr.net](https://www.jsdelivr.com/terms/privacy-policy-jsdelivr-net)
- **Registries & Source Code**:
  - [Docker Hub / dhi.io](https://www.docker.com/legal/docker-privacy-policy/)
  - [GitHub / GHCR](https://docs.github.com/en/site-policy/privacy-policies/github-privacy-statement)
  - [Codeberg](https://codeberg.org/privacy)
  - [Quay.io](https://quay.io/privacy)
  - [SourceHut](https://man.sr.ht/privacy.md)
  - [Gitdab](https://gitdab.com/)
- **Data Providers**:
  - [DNS Blocklists (GitHub)](https://docs.github.com/en/site-policy/privacy-policies/github-privacy-statement)
  - [Odido API](https://www.odido.nl/privacy)

</details>

---

## 🚨 Disclaimer

This software is provided "as is". While designed for security, the user is responsible for ensuring their specific network configuration is safe. **Do not use GitHub Codespaces for production deployment.**

---

*Built with ❤️ for digital sovereignty.*