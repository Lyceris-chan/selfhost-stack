# 🛡️ ZimaOS Privacy Hub

A comprehensive, self-hosted privacy infrastructure designed for digital independence.
Route your traffic through secure VPNs, eliminate tracking with isolated frontends, and manage everything from a unified **Material Design 3** dashboard.

---

<a id="disclaimer--security-warning"></a>
## 🚨 Disclaimer & Security Warning

### Provided "As Is"
This script and associated configuration files are provided **as is**. While I appreciate improvements and contributions, please ensure your code is fully tested and functional before submitting it. I cannot guarantee that everything will work in every unique environment. It has been verified to work on GitHub Codespaces and locally.

### 🔐 Security Best Practices
- **DO NOT** use GitHub Codespaces for an actual production deployment. 
- **NEVER** upload your production secrets (API keys, tokens, VPN configs) to the internet or public repositories.
- **Minimal Permissions**: Ensure any tokens or PATs you create have the absolute minimal permissions required for their task.
- **Revoke Immediately**: Revoke and delete any tokens as soon as you are finished with them. **Do not forget this**, as it can compromise your entire infrastructure security.

---

## 🌟 Key Features & Benefits

*   **Data Independence & Ownership**: By hosting your own frontends (Invidious, Redlib, etc.), you stop upstream giants like Google and Reddit from collecting, profiling, and selling your behavioral data. You own the instance; you own the data.
*   **Ad-Free by Design**: Enjoy a clean, distraction-free web. AdGuard Home blocks trackers and ads at the DNS level for your entire home, while frontends eliminate in-video ads and sponsored content natively.
*   **No App Prompts**: Say goodbye to "Install our app" popups. These frontends provide a premium mobile-web experience that works perfectly in any browser without requiring invasive native applications.
*   **VPN-Gated Privacy**: Sensitive services are routed through a **Gluetun VPN** tunnel. This ensures that even when you browse, end-service providers only see your VPN's IP address, keeping your home location and identity hidden.
### Zero-Leaks Asset Architecture
External assets (fonts, icons, scripts) are fetched once via the **Gluetun VPN proxy** and served locally. Your public home IP is never exposed to CDNs.

**Privacy Enforcement Logic:**
1.  **Container Initiation**: When the Hub API container starts, it initiates an asset verification check.
2.  **Proxy Routing**: If assets are missing, the Hub API routes download requests through the Gluetun VPN container (acting as an HTTP proxy on port 8888).
3.  **Encapsulated Fetching**: All requests to external CDNs (Fontlay, JSDelivr) occur *inside* the VPN tunnel. Upstream providers only see the VPN IP.
4.  **Local Persistence**: Assets are saved to a persistent Docker volume (`/assets`).
5.  **Offline Serving**: The Management Dashboard (Nginx) serves all UI resources exclusively from this local volume.
*   **Privacy Guarantee**: Within this stack, **none** of the services you interact with can see your public IP or identifying metadata. The *only* time your IP is exposed is during the initial setup when cloning source code from GitHub/Codeberg, which is a one-time deployment event.
*   **Material Design 3**: A beautiful, accessible management dashboard with dynamic theming and real-time health metrics.

---

## 📚 Contents
- [Quick Start](#quick-start) ⚡ **New users start here**
- [Disclaimer & Security Warning](#disclaimer--security-warning) 🚨 **Must read**
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites--infrastructure)
  - [Installation](#installation)
  - [Verification](#-verify-installation)
  - [Flags & Options](#-script-flags--options)
- [Management Dashboard](#management-dashboard)
- [Included Services](#included-services)
- [Network Configuration](#network-configuration)
  - [Remote Access](#1-enable-remote-access-isp-router)
  - [Router Setup](#2-router-configuration-openwrt-example)
  - [DNS Protection](#3-network-wide-dns-protection)
  - [VPN Architecture](#-vpn-architecture-two-tunnels-explained)
- [Troubleshooting & Pitfalls](#-troubleshooting--common-pitfalls)
- [Privacy & Security Architecture](#-privacy--security-architecture)
- [Maintenance](#-migration--backup)
- [System Requirements](#-system-requirements--scaling)

---

## ⚡ Quick Start

**Want to deploy immediately?** Run this single command:
```bash
./zima.sh -p -y
```

This automated mode:
- ✅ Generates secure random passwords automatically
- ✅ Skips all interactive prompts
- ✅ Creates a complete privacy stack in ~15 minutes
- ✅ Exports credentials to `protonpass_import.csv`

**Read the full [Prerequisites](#prerequisites--infrastructure) below for advanced configuration options.**

---

<a id="getting-started"></a>
## 🏗️ Getting Started

### Prerequisites & Infrastructure

**Pre-Flight Checklist** - Gather these before running the installation:

#### ✅ Required Items

- [ ] **Docker Hub Credentials** ([Create here](https://hub.docker.com/settings/security))
  - Username (same for Docker Hub and `dhi.io`)
  - Personal Access Token with **read/pull permissions only**
  - Used to pull hardened images and avoid rate limits
  
- [ ] **ProtonVPN WireGuard Configuration** ([Get your .conf file](#protonvpn-wireguard-conf---the-anonymity-engine))
  - Required for Gluetun VPN gateway
  - Hides your home IP from upstream services
  - Only ProtonVPN is explicitly tested (other WireGuard providers untested)

#### 🔧 Optional (But Recommended)

- [ ] **deSEC Domain + Token** ([Sign up at deSEC.io](https://desec.io))
  - Enables trusted SSL certificates (no browser warnings)
  - Unlocks Private DNS for Android/iOS
  - Free dynamic DNS service
  
- [ ] **GitHub Personal Access Token** (For Scribe frontend)
  - Classic token with `gist` scope only
  - [Generate here](https://github.com/settings/tokens)
  - Avoids rate limits (60/hr → 5000/hr)

- [ ] **Odido OAuth Token** (Dutch users only)
  - Required for automated data bundle management
  - Obtain via [Odido Authenticator](https://github.com/GuusBackup/Odido.Authenticator)

---

<details>
<summary><strong>🔍 Quick Explainers - Click to expand</strong></summary>

1. **DHI (Docker Hardened Images)**: Security-focused base images from `dhi.io` that strip telemetry, minimize attack surface, and optimize performance for self-hosting environments.
2. **DDNS (Dynamic DNS)**: Automatically updates your domain when your home IP changes, keeping services accessible without manual DNS edits.
3. **SSL / Trusted SSL**: 
   - **Trusted**: Certificate from Let's Encrypt (public CA) - no browser warnings
   - **Self-Signed**: Also encrypted, but triggers security warnings without manual trust
4. **Classic PAT (Personal Access Token)**: API authentication token you create in account settings (GitHub, Docker Hub, etc.) with specific permissions/scopes.
5. **CDN (Content Delivery Network)**: Third-party servers that host common libraries/assets. This stack serves everything locally for privacy.

</details>

---

<details>
<summary><strong>📥 ProtonVPN WireGuard (.conf) - The Anonymity Engine</strong></summary>

This configuration is **critical** for privacy. It routes all frontend traffic (Invidious, Redlib, etc.) through an encrypted tunnel, ensuring upstream services never see your home IP address.

**Step-by-Step Guide:**

1. **Login** to [ProtonVPN Downloads](https://account.protonvpn.com/downloads)
2. **Navigate** to the WireGuard section
3. **Name** your configuration (e.g., "Privacy-Hub-Main")
4. **Select** a Free server in your preferred region
5. **Download** the `.conf` file

**During Installation:**
- You'll be prompted to paste the entire file contents
- Or set `WG_CONF_B64` environment variable with base64-encoded config

**🛡️ Privacy Impact:**  
Without this configuration, services will expose your real home IP to YouTube, Reddit, and other providers. With it enabled, they only see ProtonVPN's shared commercial IP address.

**📊 Bandwidth Considerations:**  
The script tracks VPN data usage. On mobile devices connected via your home WireGuard (WG-Easy), only privacy frontend traffic routes through the ProtonVPN tunnel - streaming apps like Netflix/Spotify maintain full direct speed.

</details>

### Installation
Run the deployment script. It will validate your environment, prompt for credentials, and build the stack.

```bash
# Standard Deployment (Interactive)
./zima.sh

# Deployment with Auto-generated Passwords (Recommended for Beginners)
./zima.sh -p

# Deployment with Allow Proton VPN flag
./zima.sh -a
```

### ✅ Verify Installation

After deployment completes, run these checks to confirm everything is operational:

**1. Check Container Health:**
```bash
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

Expected output: All containers should show `Up` or `healthy` status.

**2. Test Dashboard Access:**
```bash
curl -I http://localhost:8081
```

Expected: HTTP 200 response

**3. Verify DNS Resolution:**
```bash
dig @localhost example.com
```

Expected: Valid A record response (confirms AdGuard/Unbound are working)

**4. Check VPN Tunnel:**
```bash
docker exec gluetun wget -qO- http://ifconfig.me
```

Expected: ProtonVPN IP address (different from your home IP)

**🚨 Troubleshooting:** If any check fails, review deployment logs:
```bash
tail -f /DATA/AppData/privacy-hub/deployment.log
```

### 🔑 Post-Install: Where are my passwords?
If you used the `-p` flag, the script auto-generated secure credentials for you.

1.  **Secret File**: All passwords are stored on your host at:
    ```bash
    /DATA/AppData/privacy-hub/.secrets
    ```
    > ⚠️ **SECURITY WARNING**: This file contains unencrypted administrative passwords and API keys. Ensure access to your host machine is restricted.

2.  **Proton Pass Import**: A CSV file ready for import into password managers is generated at:
    ```bash
    /DATA/AppData/privacy-hub/protonpass_import.csv
    ```
3.  **Default Username**:
    *   **Portainer**: `portainer` (or `admin`)
    *   **AdGuard**: `adguard`
    *   **Dashboard API**: `HUB_API_KEY` (Found in `.secrets`)

---

### 🛠️ Script Flags & Options

| Flag | Description | Action | 
| :--- | :--- | :--- |
| `-c` | **Maintenance Reset** | Removes active containers and networks to resolve glitches, while strictly preserving persistent user data. |
| `-x` | **REVERT (Factory Reset)** | ⚠️ **REVERT: Total Cleanup** — This erases only the parts we added. It wipes the Invidious database and any data saved inside our apps during your usage. If you didn't back up your app data, it will be gone forever. It does not touch your personal files; it only clears out our software. |
| `-p` | **Auto-Passwords** | Generates secure random passwords for all services automatically. |
| `-a` | **Allow Proton VPN** | Allowlists essential ProtonVPN domains in AdGuard Home. **Warning:** This may break DNS isolation and frontend access. |
| `-y` | **Auto-Confirm** | Skips all interactive confirmation prompts (Best for automated CI/CD). |
| `-s` | **Selective** | Deploy only specific services (e.g., `-s invidious,memos`). |

---

<a id="management-dashboard"></a>
## 🖥️ Management Dashboard

Access the unified dashboard at `http://<LAN_IP>:8081`.

### Material Design 3 Compliance
The dashboard is built to strictly follow **[Google's Material Design 3](https://m3.material.io/)** guidelines.
*   **Color System**: We use the official `material-color-utilities` library to generate accessible color palettes from your seed color or wallpaper.
*   **Components**: All UI elements (cards, chips, buttons) adhere to M3 specifications for shape, elevation, and state layers.

### Customization
*   **Theme Engine**: Upload a wallpaper to automatically extract a coordinated palette (Android folder style), or pick a color manually.
*   **Presets**: Choose from curated Material Design color presets.
*   **Safe Display Mode**: One-click toggle to blur sensitive IPs and data for screenshots.

### Update Engine
*   **Changelogs**: View commit logs (for source builds) or release notes (for images) directly in the UI before updating.
*   **Granular Control**: Update all services at once or select specific ones.
*   **Safety First**: Automatic database backups are created before any update is applied.

<a id="included-services"></a>
## 📦 Included Services

| Service & Source | Category | Purpose | 
| :--- | :--- | :--- |
| **[Invidious](https://github.com/iv-org/invidious)** | Privacy Frontend | Anonymous YouTube (No ads/tracking) |
| **[Redlib](https://github.com/redlib-org/redlib)** | Privacy Frontend | Lightweight Reddit interface |
| **[Wikiless](https://github.com/Metastem/Wikiless)** | Privacy Frontend | Private Wikipedia access |
| **[Memos](https://github.com/usememos/memos)** | Utility | Private knowledge base & notes |
| **[AdGuard Home](https://github.com/AdguardTeam/AdGuardHome)** | Core | DNS filtering & Ad-blocking |
| **[WireGuard](https://github.com/wg-easy/wg-easy)** | Core | Secure remote access gateway |
| **[Portainer](https://github.com/portainer/portainer)** | Admin | Advanced container management |
| **[VERT](https://github.com/vert-sh/vert)** | Utility | Local, GPU-accelerated file conversion (VERTD requires a valid cert due to quirks) |
| **[Rimgo](https://codeberg.org/rimgo/rimgo)** | Frontend | Lightweight Imgur interface |
| **[BreezeWiki](https://gitdab.com/cadence/breezewiki)** | Frontend | De-fandomized Wiki interface |
| **[AnonOverflow](https://github.com/httpjamesm/anonymousoverflow)** | Frontend | Private Stack Overflow viewer |
| **[Scribe](https://git.sr.ht/~edwardloveall/scribe)** | Frontend | Alternative Medium frontend |
| **[Odido Booster](https://github.com/Lyceris-chan/odido-bundle-booster)** | Utility | Automated NL data bundle booster |

### Service Access & URLs
The dashboard provides one-click launch cards for every service. 

| Service | Local LAN URL | Category | 
| :--- | :--- | :--- |
| **Dashboard** | `http://<LAN_IP>:8081` | Management |
| **Invidious** | `http://<LAN_IP>:3000` | Privacy Frontend |
| **Redlib** | `http://<LAN_IP>:8080` | Privacy Frontend |
| **Wikiless** | `http://<LAN_IP>:8180` | Privacy Frontend |
| **Rimgo** | `http://<LAN_IP>:3002` | Privacy Frontend |
| **BreezeWiki** | `http://<LAN_IP>:8380` | Privacy Frontend |
| **AnonOverflow** | `http://<LAN_IP>:8480` | Privacy Frontend |
| **Scribe** | `http://<LAN_IP>:8280` | Privacy Frontend |
| **Memos** | `http://<LAN_IP>:5230` | Utility |
| **VERT** | `http://<LAN_IP>:5555` | Utility |
| **Odido Booster** | `http://<LAN_IP>:8085` | Utility |
| **AdGuard Home** | `http://<LAN_IP>:8083` | Infrastructure |
| **WireGuard UI** | `http://<LAN_IP>:51821` | Infrastructure |
| **Portainer** | `http://<LAN_IP>:9000` | Admin |

> 🔒 **Domain Access**: When deSEC is configured, all services automatically become available via trusted HTTPS at `https://<service>.<domain>:8443/`.

<a id="network-configuration"></a>
## 🌐 Network Configuration

### 1. Enable Remote Access (ISP Router)
To access your services from anywhere via WireGuard, you must forward the VPN port on your main router:
*   **Port Forwarding**: Forward **UDP Port 51820** to the **Local IP** of your Privacy Hub (e.g., `192.168.1.100`).
*   This allows the WireGuard handshake to complete securely. No other ports need to be exposed.

### 2. Router Configuration (OpenWrt Example)
If you use a custom router like OpenWrt, ensure your Privacy Hub has a stable address and precise firewall rules. **Step 1 is critical** as it binds the hardware (MAC) to the IP, allowing the firewall to target only your Privacy Hub host.

```bash
# 1. Assign Static IP (Binds hardware MAC to IP)
 uci add dhcp host
 uci set dhcp.@host[-1].name='Privacy-Hub'
 uci set dhcp.@host[-1].mac='00:11:22:33:44:55' # <--- YOUR DEVICE MAC
 uci set dhcp.@host[-1].ip='192.168.1.100'      # <--- YOUR DESIRED IP
 uci commit dhcp

# 2. Port Forwarding (Redirect WAN traffic to Hub IP)
 uci add firewall redirect
 uci set firewall.@redirect[-1].name='Forward-WireGuard'
 uci set firewall.@redirect[-1].src='wan'
 uci set firewall.@redirect[-1].proto='udp'
 uci set firewall.@redirect[-1].src_dport='51820'
 uci set firewall.@redirect[-1].dest_ip='192.168.1.100'
 uci set firewall.@redirect[-1].dest_port='51820'
 uci set firewall.@redirect[-1].target='DNAT'
 uci commit firewall
/etc/init.d/firewall restart
```

### 3. Network-Wide DNS Protection
To filter ads and trackers for every device on your WiFi:
*   **DHCP Settings**: Set the **Primary DNS** server in your router's LAN/DHCP settings to your Privacy Hub's IP (`192.168.1.100`).
*   **Secondary DNS**: Leave empty or set to the same IP. *Adding a public resolver here breaks your privacy.*
*   **⚠️ IMPORTANT: Disable Dynamic MAC Addresses**: Ensure that "Private WiFi Address" (iOS) or "Randomized MAC" (Android/Windows) is **DISABLED** for your home network on the host machine. Your router binds a **MAC address → IP** lease; if the MAC rotates, the router treats it as a new device and assigns a new IP, which breaks port forwarding, firewall rules, and any DNS rewrites that point to the old address.

### 4. Split Tunnel Configuration (VPN Routing) & Bandwidth Optimization
This stack uses a **Split Tunnel** architecture via Gluetun. This means only specific traffic is sent through the VPN, while the rest of your home network remains untouched.
*   **VPN-Gated Services**: Privacy frontends (Invidious, Redlib, etc.) are locked inside the VPN container. They cannot access the internet if the VPN disconnects (Killswitch enabled).
*   **Local-Direct Services**: Core management tools (Dashboard, Portainer, AdGuard UI) are accessible directly via your LAN IP. This ensures you never lose control of your hub even if the VPN provider has an outage.
*   **🚀 Bandwidth Benefits**: Only self-hosted privacy services route through your home WireGuard connection. This preserves your mobile data speed: high-bandwidth streaming services like Netflix or native YouTube apps maintain their full, direct speed on your device rather than being forced to route back through your home upload connection first.

### 🔀 VPN Architecture: Two Tunnels Explained

This stack uses **two separate VPN systems** for different purposes. Understanding the distinction is critical:

#### 1️⃣ Gluetun (Outbound Privacy Tunnel)
- **Purpose**: Hides your home IP from upstream services
- **Route**: Privacy Hub → ProtonVPN → Internet (YouTube, Reddit, etc.)
- **Protects**: Your privacy frontends (Invidious, Redlib, Wikiless, etc.)
- **Configuration**: ProtonVPN WireGuard `.conf` file

**What It Does**: When Invidious fetches a YouTube video, YouTube's servers see ProtonVPN's IP. Your real home location remains hidden from all upstream providers.

---

#### 2️⃣ WG-Easy (Inbound Remote Access)
- **Purpose**: Lets you access your Privacy Hub from anywhere
- **Route**: Your Phone/Laptop → WG-Easy → Privacy Hub → LAN Services
- **Protects**: Secure tunnel into your home network
- **Configuration**: Automatic (generates client configs via web UI)

**What It Does**: Connect from coffee shop → VPN tunnel → Access your private services. Only **UDP Port 51820** is exposed to internet (encrypted, invisible to port scanners).

---

#### 📊 Bandwidth Optimization

**Split Tunnel Architecture** = Smart routing for optimal speeds:

✅ **Routes Through Home VPN** (WG-Easy):
- Privacy Hub Dashboard
- Local services (Portainer, AdGuard UI)
- Self-hosted apps (Memos, VERT)

❌ **Does NOT Route Through Home** (Direct connection):
- Netflix, Spotify, YouTube app, etc.
- General web browsing
- Large file downloads

### 5. Encrypted DNS via Local Rewrites
By leveraging AdGuard Home's **DNS Rewrites**, you can use advanced encrypted protocols (DoH/DoQ) without needing a constant VPN connection while at home.
*   **The Logic**: AdGuard is configured to "rewrite" your deSEC domain (e.g., `your-domain.dedyn.io`) to your Hub's **Internal IP**.
*   **The Benefit**: Your phone/laptop can use **Private DNS** (Android) or system-level DoH pointing to your domain.

### 6. Advanced Network Hardening (Explore!)
Some "smart" devices (TVs, IoT, Google Home) are hardcoded to bypass your DNS and talk directly to Google. You can force them to respect your privacy rules using advanced firewall techniques.

*   **DNS Hijacking (NAT Redirect)**: Catch all rogue traffic on port 53 and force it into your AdGuard instance. [OpenWrt Guide](https://openwrt.org/docs/guide-user/firewall/firewall_configuration/intercept_dns)
*   **Block DoH/DoT**: Modern apps try to use "DNS over HTTPS" to sneak past filters. You can block this by banning known DoH IPs and ports (853/443). [OpenWrt banIP Guide](https://openwrt.org/docs/guide-user/firewall/firewall_configuration/ban_ip)

---

### 🛠️ Troubleshooting & Common Pitfalls

#### "My Internet Broke" - Critical Recovery

**What Happened?**  
Your Privacy Hub machine hosts your DNS resolver. If it loses power, crashes, or the script fails mid-update, devices lose the ability to translate domain names into IP addresses.

**Immediate Fix**:
1.  **Restart the Hub**: Run `./zima.sh` again to fix configurations and restart containers.
2.  **Emergency Fallback**: If you cannot fix the hub immediately, change your router or device DNS to a trusted public provider like **Mullvad DNS** (`194.242.2.2`). Use this to restore connectivity until you can repair your self-hosted instance.
3.  **⚠️ Fallback Implications**: When using fallback DNS, your local Privacy Hub services (e.g., `adguard.your-domain.dedyn.io`) will not resolve locally. You will be accessing them via their public IPs, which may trigger SSL warnings.

---

#### ⚠️ Common Pitfalls

<details>
<summary><strong>❌ Mistake #1: Dynamic MAC Addresses Enabled</strong></summary>

**Symptom**: Port forwarding stops working after reboot, services unreachable remotely.
**Fix**: Ensure "Private WiFi Address" (iOS) or "Randomized MAC" (Android/Windows) is **DISABLED** for your home network.
</details>

<details>
<summary><strong>❌ Mistake #2: Google DNS as Secondary</strong></summary>

**Symptom**: Ads still appear, tracking still occurs.
**Fix**: Primary DNS must be Hub IP. **Leave Secondary DNS Empty**.
</details>

<details>
<summary><strong>❌ Mistake #3: Skipping Port Forward on ISP Router</strong></summary>

**Symptom**: WireGuard connects on home network, fails from coffee shop.
**Fix**: Ensure UDP 51820 is forwarded on **BOTH** your ISP modem and your OpenWrt router.
</details>

<details>
<summary><strong>❌ Mistake #4: Expecting Instant Updates</strong></summary>

**Symptom**: Dashboard shows "No updates", but I know there are new commits.
**Fix**: Initial check takes 2-5 minutes. Click "Check Updates" and wait for background background jobs to complete.
</details>

---

#### Service & Container Issues

**Check logs for specific service:**
```bash
docker logs <container_name> --tail 50
```

**Common Status Issues:**

| Error Message | Cause | Fix | 
|--------------|-------|-----|
| `port is already allocated` | Another service using the port | `docker ps -a` → Stop conflicting container |
| `no space left on device` | Disk full | `docker system prune -a` |
| `rate limit exceeded` | Docker Hub throttling | Run `./zima.sh` to re-authenticate |
| `OCI runtime error` | Corrupted container state | `./zima.sh -c` (maintenance reset) |

---

## 🛡️ Privacy & Security Architecture

### Recursive DNS Engine (Independent Resolution)
*   **Zero Third-Parties**: We bypass "public" resolvers like **Google** and **Cloudflare**.
*   **QNAME Minimization**: Only sends absolute minimum metadata upstream.
*   **Encrypted Local Path**: Native support for **DoH** and **DoQ**.

### 🛡️ Blocklist Information & DNS Filtering
*   **Source**: Blocklists are generated using the [Lyceris-chan DNS Blocklist Generator](https://github.com/Lyceris-chan/dns-blocklist-generator/).
*   **Composition**: Based on **Hagezi Pro++**, curated for performance and dutch users.
*   **Note**: This blocklist is **aggressive** by design.

### 📦 Docker Hardened Images (DHI)
This stack utilizes **Digital Independence (DHI)** images (`dhi.io`) to ensure maximum security and privacy. These images are purpose-built for self-hosting:
*   **Zero Telemetry**: All built-in tracking features are strictly removed.
*   **Security Hardened**: Attack surfaces minimized by stripping unnecessary binaries.
*   **Performance Optimized**: Pre-configured for low-resource environments.
*   **Replacement Mapping**:
    *   [`dhi.io/nginx:1.28-alpine3.21`](https://github.com/docker-hardened-images/catalog/pkgs/container/nginx) replaces standard `nginx:alpine` (Hardened config, no server headers).
    *   [`dhi.io/python:3.11-alpine3.22-dev`](https://github.com/docker-hardened-images/catalog/pkgs/container/python) replaces standard `python:alpine` (Stripped of build-time dependencies).
    *   [`dhi.io/node:20-alpine3.22-dev`](https://github.com/docker-hardened-images/catalog/pkgs/container/node) & [`dhi.io/bun:1-alpine3.22-dev`](https://github.com/docker-hardened-images/catalog/pkgs/container/bun) (Optimized for JS-heavy frontends).
    *   [`dhi.io/redis:7.2-debian13`](https://github.com/docker-hardened-images/catalog/pkgs/container/redis) & [`dhi.io/postgres:14-alpine3.22`](https://github.com/docker-hardened-images/catalog/pkgs/container/postgres) (Hardened database engines).

### 🛡️ Self-Healing & High Availability
*   **VPN Monitoring**: Gluetun is continuously monitored. Docker restarts the gateway if the tunnel stalls.
*   **Frontend Auto-Recovery**: Privacy frontends utilize `restart: always`.
*   **Health-Gated Launch**: Infrastructure services must be `healthy` before frontends start.

### Data Minimization & Anonymity
*   **Specific User-Agent Signatures**: Requests use industry-standard signatures to blend in.
*   **Zero Personal Data**: No API keys or hardware IDs are transmitted during checks.
*   **Isolated Environment**: Requests execute from within containers without host-level access.

---

## 🧪 Automated Verification & Quality Assurance

To ensure a "set and forget" experience, every release undergoes a rigorous automated verification pipeline:
*   **Interaction Audit**: Puppeteer-based suite (`test_user_interactions.js`) simulates real user behavior.
*   **Non-Interactive Deployment**: verified `-p -y` flow for zero-prompt success.
*   **M3 Compliance Check**: Automated layout audits ensure the dynamic grid and chips adapt to any screen size.
*   **Log & Metric Integrity**: Container logs audited for 502/504 errors; real-time telemetry verified.

---

## 🖥️ System Requirements & Scaling

### Verified Local Environment
This stack is verified for production usage on **ZimaOS** with the following hardware specifications:
*   **CPU**: Intel® Core™ i3-10105T @ 3.00GHz (4 Cores, 8 Threads)
*   **RAM**: 32 GB DDR4 @ 2666 MHz
*   **GPU**: Intel® UHD Graphics 630 (Comet Lake-S GT2)
*   **Acceleration**: Full support for **Intel Quick Sync** via `vertd` for high-performance file conversion.

> 🚀 **Hardware Transcoding**: While optimized for Intel Quick Sync, `vertd` also supports **AMD (VA-API)** and **NVIDIA (NVENC)** acceleration according to the official VERTD documentation and source code. Ensure the appropriate drivers and `/dev/dri` access are available on your host.

### Minimum Specifications

| Component | Minimum | Recommended | Notes | 
|-----------|---------|-------------|-------|
| **CPU** | 2 Physical Cores | 4+ Cores | Compilation is **core-bound** | 
| **RAM** | 4 GB | 8 GB | Invidious DB requires 512MB min | 
| **Storage** | 32 GB | 64 GB SSD | WAL logs grow over time | 
| **OS** | Ubuntu 22.04 LTS | Debian 12+ | Docker 24.0+ required | 

### ⏱️ Performance Expectations

| Phase | Duration | 
|-------|----------|
| Environment Validation | 1-2 min | 
| Image Downloads | 3-5 min | 
| Source Compilation | 8-15 min | 
| Service Startup | 2-3 min | 
| **Total** | **15-25 min** | 

---

## 💾 Migration & Backup

### Automated Backups
The stack creates automatic snapshots before destructive operations.
- **Manual Backup**: `docker exec hub-api python3 -c "import sys; sys.path.append('/app'); from server import *; migrate_service('all', 'backup-all', 'yes')"`

### Restore & Migration
- **Invidious DB**: `cat backup.sql | docker exec -i invidious-db psql -U kemal invidious`
- **Full Stack**: Backup `/DATA/AppData/privacy-hub/`, restore on new machine, update LAN IP in configs, and run `./zima.sh`.

---

<a id="advanced-setup"></a>
## 📡 Advanced Setup: OpenWrt & Double NAT

If you are behind an ISP modem *and* an OpenWrt router (Double NAT), you must forward UDP Port 51820 on **both** devices sequentially.

<details>
<summary><strong>🔧 Add Your Own Services</strong> (advanced)</summary>

1. **Definition**: Add your service block to Section 13 of `zima.sh`.
2. **Monitoring**: Update the status loop in `WG_API_SCRIPT`.
3. **UI**: Add metadata to the `services.json` catalog.

</details>

---
*Built with ❤️ for the self-hosting community.*