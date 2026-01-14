# 🛡️ ZimaOS Privacy Hub

**Stop being the product.**

The ZimaOS Privacy Hub is a comprehensive, self-hosted privacy infrastructure designed for digital independence. Route your traffic through secure VPNs, eliminate tracking with isolated frontends, and manage everything from a unified **Material Design 3** dashboard.

---

## 📖 Table of Contents

- [Key Features](#-key-features)
- [Deployment](#-deployment)
  - [Before You Start](#before-you-start-checklist)
  - [Step 1: Get Your VPN Configuration](#step-1-get-your-vpn-configuration)
  - [Step 2: Get Your Domain Token](#step-2-get-your-domain-token-optional-but-recommended)
  - [Step 3: Download and Run the Installer](#step-3-download-and-run-the-installer)
  - [Customization Flags](#️-customization-flags-optional)
  - [What Happens Next?](#what-happens-next)
- [How It Works (Architecture)](#️-how-it-works-architecture)
  - [Recursive DNS Engine](#recursive-dns-engine-independent-resolution)
  - [Why Self-Host?](#-why-self-host-the-trust-gap)
- [Dashboard and Services](#️-dashboard--services)
  - [WireGuard Client Management](#-wireguard-client-management)
  - [Credential Management](#-credential-management)
  - [LibRedirect Integration](#-libredirect-integration)
  - [Included Privacy Services](#included-privacy-services)
  - [Hardware Acceleration](#-hardware-acceleration-gpuqsv)
  - [Network Configuration](#-network-configuration)
- [Advanced Setup: OpenWrt and Double NAT](#-advanced-setup-openwrt--double-nat)
- [Privacy and Architecture](#️-privacy--architecture)
- [Security Standards](#-security-standards)
- [System Requirements](#️-system-requirements)
- [Troubleshooting](#-troubleshooting)
- [Maintenance](#-maintenance)

---

## 🚀 Key Features

*   **🔒 Data Independence**: Host your own frontends (Invidious, Redlib, etc.) to prevent upstream entities like Google and Reddit from profiling you.
*   **🚫 Ad-free by Design**: Network-wide ad blocking through AdGuard Home and native removal of sponsored content in video and social feeds.
*   **🕵️ VPN-gated Privacy**: All external requests route through a **Gluetun VPN** tunnel. Upstream providers only see your VPN IP, keeping your home identity hidden.
*   **📺 No Adblock Nags (Invidious)**: Watch YouTube without ad-blocking popups. Invidious fetches video data server-side, so YouTube does not detect your ad-blocking tools.
*   **📱 Frictionless Browsing (Redlib)**: Redlib eliminates "Open in App" prompts and mobile-web trackers. Enjoy a fast Reddit experience on any device without using the official app.
*   **🚀 Faster and Safer**: Self-hosted frontends remove tracking scripts, telemetry, and bloated JavaScript. This results in faster page loads and improved browser security.
*   **🔑 Easy Remote Access**: Built-in **WireGuard** management. Generate client configurations and **QR codes** directly from the dashboard to connect your phone or laptop securely.
*   **⚡ Hardware Performance**: Automatically detects and provisions GPU acceleration (Intel QSV, AMD VA-API, or NVIDIA) for media-heavy services like Immich and VERT.
*   **🎨 Material Design 3**: A responsive dashboard with dynamic theming and real-time health metrics.

> ⚠️ **Heads up: The cat-and-mouse game**  
> Companies like Google and Reddit **actively try to break** these privacy frontends. Why? Because every user on Invidious or Redlib is a user they can't track, monetize, or serve ads to. They regularly change their APIs, add new anti-bot measures, and modify their page structures specifically to break these tools. This stack uses **pre-built images** and automated updates so we can apply fixes quickly. Occasional outages are part of the privacy game. It's worth it.

> 🔌 **Service availability and redundancy**  
> These services are **only available** while the device you are hosting on is powered on and network-accessible. In the event of a power outage, network failure, or hardware issue, access to your self-hosted services will be lost. We strongly recommend exploring redundancy options (such as UPS backups or secondary failover nodes) to ensure continuous access to your privacy infrastructure. Be aware that you are your own "cloud provider" now!

---

## 🚀 Deployment

**Don't worry: this is easier than it looks!** The Privacy Hub guides you through everything.

 Just follow these steps, and you'll have your own private internet in about **2–5 minutes**.

### Before you start (checklist)

You'll need:
- [ ] A modern 64-bit computer (ZimaBoard, Raspberry Pi 5, NUC, or any PC)
- [ ] **ZimaOS**, **Ubuntu 22.04+**, or **Debian 12+**
- [ ] **Docker** installed ([Get Docker](https://docs.docker.com/get-docker/))
- [ ] A **ProtonVPN** account (free tier works!)
- [ ] *(Optional)* A **deSEC** account for free SSL/domain

---

### Step 1: Get your VPN configuration

*Think of this as getting the "key" to your secret tunnel.*

1.  **Create a ProtonVPN account** (if you don't have one): [ProtonVPN Signup](https://account.protonvpn.com/signup)
2.  Go to [ProtonVPN Downloads](https://account.protonvpn.com/downloads)
3.  Scroll down to **WireGuard configuration**
4.  Click **Create** and choose any server (Netherlands or Switzerland are good for privacy)
5.  **⚠️ IMPORTANT**: Ensure **NAT-PMP (Port Forwarding)** is set to **OFF** (see warning below)
6.  Click **Download** to save the `.conf` file
7.  **Open** the downloaded file in a text editor. You will paste its contents during setup

> 📝 **What you're getting**: This file contains your personal "tunnel key" that lets your hub connect to ProtonVPN's servers. Your real home IP stays hidden!

> ⚠️ **NAT-PMP warning**: Do **NOT** enable NAT-PMP (Port Forwarding) when generating your WireGuard configuration!
>
> **Why?** NAT-PMP opens a port on Proton's VPN server that forwards traffic directly to your Privacy Hub. This means:
> - Your services become **publicly accessible** on the internet
> - Anyone scanning Proton's IP ranges could find and attack your hub
> - Your home IP stays hidden, but your services are exposed to the world
>
> **Correct settings:**
> - ✅ NAT-PMP (Port Forwarding) = **OFF**
> - ✅ VPN Accelerator = **ON** (recommended for performance)

---

### Step 2: Get your domain token *(Mandatory)*

*This gives your hub a memorable name like `my-home.dedyn.io` instead of an IP address.*

1.  Register at [deSEC.io](https://desec.io) (it's free and privacy-focused)
2.  Verify your email and sign in
3.  Click **"+ Add Domain"** and create a subdomain (e.g., `my-privacy-hub.dedyn.io`)
4.  Go to **Token Management** → **"+"** to create a new token
5.  **Copy and save this token**. You will need it during setup

> 📝 **What you're getting**: This token lets the installer automatically set up SSL certificates so your connection is encrypted.

> ⚠️ **Why you need this for HTTPS**: Without a domain, your browser will show scary "Your connection is not private" warnings because SSL certificates can only be issued for domain names, not IP addresses. The deSEC domain and token allow the installer to automatically obtain a free **Let's Encrypt** certificate, so your dashboard and services load securely without any browser warnings.
>
> **Mandatory for DNS-over-HTTPS (DoH) and DNS-over-QUIC (DoQ)**: A valid, globally trusted certificate is mandatory for DoH and DoQ to function correctly on modern devices. Without it, your phone or browser will refuse to use your hub as a secure DNS provider.
>
> **VERT Requirement**: VERT requires a valid HTTPS connection for secure communication with its daemon API (VERTd).

---

### Step 3: Download and run the installer

Now the fun part! Open a terminal on your hub computer and run:

```bash
# Clone the repository
git clone https://github.com/Lyceris-chan/selfhost-stack.git

# Enter the directory
cd selfhost-stack

# Run the installer
./zima.sh
```

The script will ask you a few questions:
1.  **Paste your WireGuard configuration** (from Step 1)
2.  **Enter your deSEC domain and token** (from Step 2)
3.  **Choose your password preferences** (auto-generate or set your own)

That's it! Sit back and let it build.

<a id="customization-flags"></a>
### 🛠️ Customization flags (optional)

Before running the installer, you can customize your deployment using these flags:

| Flag | Description |
| :--- | :--- |
| `-j` | **Parallel Deploy**: Deploys services in parallel. Faster, but higher CPU usage! |
| `-s` | **Selective**: Install only specific apps (e.g., `-s invidious,memos`). |
| `-c` | **Maintenance**: Recreates containers and networks to fix glitches while **preserving** your persistent data. |
| `-x` | **Factory Reset**: ⚠️ **Deletes everything**. Wipes all containers, volumes, and application data. |
| `-a` | **Allow ProtonVPN**: Adds ProtonVPN domains to the AdGuard allowlist for browser extension users. |
| `-h` | **Help**: Displays usage information and available flags. |

**Example usage:**
```bash
# Automated deployment with parallel builds
./zima.sh -j

# Selective deployment with auto-passwords
./zima.sh -s invidious,memos,searxng
```

---

### What happens next?

1.  **🚀 Instant deployment**: The system pulls and starts your private apps.
2.  **✅ Ready to use**: You get a link to your dashboard (e.g., `http://192.168.1.100:8088`).
3.  **🔐 Credential export**: Your passwords are saved for safekeeping.
4.  **🔀 Instant redirection**: A `libredirect_import.json` is created. Import this into the [LibRedirect](https://libredirect.github.io/) browser extension to automatically redirect YouTube and Reddit to your hub.

---

<details>
<summary>🖥️ <strong>System requirements</strong> (Click to expand)</summary>

To ensure a smooth experience, your hub should meet the following minimum specifications:

*   **Operating system**: 64-bit Linux (ZimaOS, Ubuntu 22.04+, or Debian 12+).
*   **Processor**: x86_64 or ARM64 (ZimaBoard, Raspberry Pi 5, NUC, or any modern PC).
*   **Memory**: 2GB RAM minimum (4GB+ highly recommended for optimal performance with Immich and SearXNG).
*   **Storage**: 16GB+ available space on a fast SSD/NVMe (plus additional space for your personal data and media).
*   **Network**: Stable internet connection. Public IP only required for remote access via WireGuard.

</details>

---

<details>
<summary>🛡️ <strong>How it works (Architecture)</strong> (Click to expand)</summary>

This section explains the technical details behind the privacy features listed above.

### Recursive DNS engine (independent resolution)
This stack features a hardened, recursive DNS engine built on **Unbound** and **AdGuard Home**, designed to eliminate upstream reliance and prevent data leakage.

*   **AdGuard Home configuration**: Generated at `/opt/adguardhome/conf/AdGuardHome.yaml`
*   **Unbound configuration**: Generated at `/etc/unbound/unbound.conf`

<details>
<summary>🛡️ <strong>Production Service Overrides and RFC Compliance</strong> (Click to expand)</summary>

To achieve high-standard security and performance, this stack implements specific overrides for core infrastructure services. These choices are grounded in established Internet Engineering Task Force (IETF) standards.

### Unbound (Recursive DNS)
The Unbound configuration ([lib/services/config.sh:285](lib/services/config.sh#L285)) is hardened beyond default settings to ensure maximum privacy and protection against common DNS-based attacks:

*   **QNAME Minimization ([RFC 7816](https://datatracker.ietf.org/doc/html/rfc7816))**: `qname-minimisation: yes`. Prevents authoritative servers from seeing the full query, protecting user browsing patterns.
*   **Aggressive NSEC Caching ([RFC 8198](https://datatracker.ietf.org/doc/html/rfc8198))**: `aggressive-nsec: yes`. Mitigates certain DoS vectors and reduces load on authoritative servers.
*   **DNS 0x20 Entropy**: `use-caps-for-id: yes`. Randomizes query name case to protect against DNS cache poisoning.
*   **Data Minimization ([RFC 4472](https://datatracker.ietf.org/doc/html/rfc4472))**: `minimal-responses: yes`. Reduces packet size and information leakage.
*   **Round Robin Selection ([RFC 1794](https://datatracker.ietf.org/doc/html/rfc1794))**: `rrset-roundrobin: yes`. Distributes load and improves reliability.
*   **Harden Glue ([RFC 1034](https://datatracker.ietf.org/doc/html/rfc1034))**: `harden-glue: yes`. Prevents cache poisoning by trusting only records within the authoritative zone.
*   **Trust Anchor Management ([RFC 5011](https://datatracker.ietf.org/doc/html/rfc5011))**: `auto-trust-anchor-file`. Maintains DNSSEC integrity through automated root key updates.
*   **Performance Tuning**: `prefetch: yes` and `prefetch-key: yes` are enabled to ensure low-latency resolution by refreshing popular records before they expire.
*   **VPN DNS Isolation**: The **Gluetun** VPN container is explicitly configured to use **Quad9** (`DOT_PROVIDERS=quad9`) for its internal DNS-over-TLS resolution instead of the default Cloudflare, ensuring no traffic is routed to 1.1.1.1.

### AdGuard Home (Filtering & TLS)
AdGuard Home acts as the primary gateway and policy engine ([lib/services/config.sh:309](lib/services/config.sh#L309)):

*   **Upstream Consolidation**: All queries are routed exclusively to the local Unbound instance (`172.x.0.250`) via a dedicated Docker network bridge.
*   **Encrypted DNS Standard ([RFC 9250](https://datatracker.ietf.org/doc/html/rfc9250))**: Full support for **DNS-over-QUIC (DoQ)**, providing superior performance and privacy on mobile networks compared to traditional DoH/DoT.
*   **Automated TLS Pipeline**: Integrates with `acme.sh` and deSEC to manage valid Let's Encrypt certificates, ensuring native compatibility with Android/iOS encrypted DNS.
*   **Dutch-Curated Filtering**: Uses a specialized blocklist based on **Hagezi Pro++**, optimized for performance and privacy.

### SearXNG (Privacy Search)
SearXNG is configured to ensure total query anonymity ([lib/services/config.sh:382](lib/services/config.sh#L382)):

*   **Image Proxy Enabled**: All images in search results are proxied through your hub. This prevents source websites from tracking your IP address when you view results.
*   **VPN Routing**: SearXNG exits exclusively through the VPN tunnel, ensuring search engines only see the VPN shared IP.

</details>

### 🔍 Why self-host? (the "trust gap")
If you don't own the hardware and the code running your network, you don't own your privacy. 
*   **The Google profile**: Google's DNS (8.8.8.8) turns you into a data source for profiling your health, finances, and interests.
*   **The Cloudflare illusion**: Even "neutral" providers can be forced to censor or log content.
*   **ISP predation**: ISPs log and sell your browsing history to data brokers.
*   **Search engine isolation**: By routing **SearXNG** through the VPN tunnel, upstream search engines (Google, Bing) see queries coming from a generic VPN IP shared by thousands, making it impossible to profile your individual search behavior or serve targeted ads.

> 📚 **Trusted sources**: For more on why these measures matter, see the **EFF's [Surveillance Self-Defense](https://ssd.eff.org/)** and their guide on **[DNS Privacy](https://www.eff.org/deeplinks/2020/12/dns-privacy-all-way-root-your-lan)**.

---

<a id="dashboard--services"></a>
## 🖥️ Dashboard and services

Access your unified control center at `http://<LAN_IP>:8088`.

### 🔑 WireGuard client management
Connect your devices securely to your home network:
1.  **Add client**: Click "New client" in the dashboard.
2.  **Connect mobile**: Click the **QR code** icon and scan it with the WireGuard app on your phone.
3.  **Connect desktop**: Download the `.conf` file and import it into your WireGuard client.

### 🔐 Credential management
The system generates secure, unique credentials for all core infrastructure during installation.

| Service | Default username | Password type | Note |
| :--- | :--- | :--- | :--- |
| **Management Dashboard** | `admin` | Auto-generated | Protects the main control plane. |
| **AdGuard Home** | `adguard` | Auto-generated | DNS management and filtering rules. |
| **WireGuard (web UI)** | `admin` | Auto-generated | Required to manage VPN peers and clients. |
| **Portainer** | `portainer` | Auto-generated | System-level container orchestration. |
| **Odido Booster** | `admin` | Auto-generated | API key for mobile data automation. |

> 📁 **Where are they?**: All generated credentials are saved to `data/AppData/privacy-hub/.secrets` and exported to `data/AppData/privacy-hub/protonpass_import.csv` for easy importing into your password manager.

### 🔀 LibRedirect integration
To automatically redirect your browser from big-tech sites to your private Hub:
1.  Install the **LibRedirect** extension ([Firefox](https://addons.mozilla.org/en-US/firefox/addon/libredirect/) / [Chrome](https://chromewebstore.google.com/detail/libredirect/pobhoodpcdojmedmielocclicpfbednh)).
2.  Open the extension settings and go to **Backup/restore**.
3.  Click **Import settings** and select the `libredirect_import.json` file found in your project root.
4.  Your browser will now automatically use your local instances for YouTube, Reddit, Wikipedia, and more.

### Included privacy services

Services marked with 🔒 VPN are routed through a secure tunnel. These services only access the internet via the VPN gateway and are not reachable from the public internet.

<details>
<summary>📋 <strong>View full service catalog and routing</strong> (Click to expand)</summary>

| Service | Category | 🛡️ Routing | Source / Image |
| :--- | :--- | :--- | :--- |
| **Invidious** | Frontend | **🔒 VPN** | [Source](https://github.com/iv-org/invidious) / [Image](https://quay.io/repository/invidious/invidious) |
| **Companion** | Helper | **🔒 VPN** | [Source](https://github.com/iv-org/invidious-companion) / [Image](https://quay.io/repository/invidious/invidious-companion) |
| **Redlib** | Frontend | **🔒 VPN** | [Source](https://github.com/redlib-org/redlib) / [Image](https://quay.io/repository/redlib/redlib) |
| **SearXNG** | Frontend | **🔒 VPN** | [Source](https://github.com/searxng/searxng) / [Image](https://hub.docker.com/r/searxng/searxng) |
| **Scribe** | Frontend | **🔒 VPN** | [Source](https://git.sr.ht/~edwardloveall/scribe) / *(local build)* |
| **Rimgo** | Frontend | **🔒 VPN** | [Source](https://codeberg.org/rimgo/rimgo) / [Image](https://codeberg.org/rimgo/rimgo/packages) |
| **Wikiless** | Frontend | **🔒 VPN** | [Source](https://github.com/Metastem/Wikiless) / *(local build)* |
| **BreezeWiki** | Frontend | **🔒 VPN** | [Source](https://github.com/breezewiki/breezewiki) / [Image](https://quay.io/repository/pussthecatorg/breezewiki) |
| **AnonOverflow** | Frontend | **🔒 VPN** | [Source](https://github.com/httpjamesm/anonymousoverflow) / [Image](https://github.com/httpjamesm/AnonymousOverflow/pkgs/container/anonymousoverflow) |
| **Cobalt** | Utility | **🔒 VPN** | [Source](https://github.com/imputnet/cobalt) / [Image](https://github.com/imputnet/cobalt/pkgs/container/cobalt) |
| **Memos** | Utility | **🔒 VPN** | [Source](https://github.com/usememos/memos) / [Image](https://github.com/usememos/memos/pkgs/container/memos) |
| **Immich** | Utility | **🔒 VPN*** | [Source](https://github.com/immich-app/immich) / [Image](https://github.com/immich-app/immich/pkgs/container/immich-server) |
| **VERT / VERTd** | Utility | **🏠 Local** | [Source](https://github.com/vert-sh/vert) / [Image](https://github.com/vert-sh/vert/pkgs/container/vert) |
| **AdGuard Home*** | Core | **🏠 Local** | [Source](https://github.com/AdguardTeam/AdGuardHome) / [Image](https://hub.docker.com/r/adguard/adguardhome) |
| **Unbound** | Core | **🏠 Local** | [Source](https://github.com/NLnetLabs/unbound) / [Image](https://hub.docker.com/r/klutchell/unbound) |
| **WireGuard** | Core | **🏠 Local** | [Source](https://github.com/wg-easy/wg-easy) / [Image](https://github.com/wg-easy/wg-easy/pkgs/container/wg-easy) |
| **Gluetun** | Core | **🌍 Exit** | [Source](https://github.com/qdm12/gluetun) / [Image](https://hub.docker.com/r/qmcgaw/gluetun) |
| **Portainer** | Core | **🏠 Local** | [Source](https://github.com/portainer/portainer) / [Image](https://hub.docker.com/r/portainer/portainer-ce) |
| **Watchtower** | Core | **🏠 Local** | [Source](https://github.com/containrrr/watchtower) / [Image](https://hub.docker.com/r/containrrr/watchtower) |
| **Dashboard** | Core | **🏠 Local** | [local source](/lib/templates/assets) |
| **Hub API** | Core | **🏠 Local** | [local source](/lib/src/hub-api) |
| **Odido Booster** | Utility | **🏠 Local** | [Source](https://github.com/Lyceris-chan/odido-bundle-booster) / *(local build)* |

*\*Immich uses the VPN only for specific machine learning model downloads and metadata fetching. Your photos stay local.
\**AdGuard Home fetches DNS blocklists and updates via your home IP address.

</details>

### 🔄 Updates and lifecycle

This stack employs a dual-strategy for keeping your services secure and up-to-date.

#### 1. Automated updates (Watchtower)
For services using pre-built Docker images (like **AdGuard**, **Invidious**, **Redlib**), updates are fully automated.
*   **Mechanism**: **Watchtower** checks for new upstream images every hour.
*   **Action**: If a new image is found, Watchtower seamlessly restarts the container with the new version.
*   **Notification**: Updates are reported to the **Hub API** and logged in the dashboard's event log, so you always know when a service has been patched.

#### 2. Source-built updates (manual)
For services built securely from source code to ensure hardware compatibility (like **Wikiless**, **Scribe**, **Odido Booster**):
*   **Mechanism**: These do not update automatically to prevent build breakages.
*   **Notification**: The dashboard will show an "Update available" badge when the upstream source code changes.
*   **Action**:
    1.  Sign in to the dashboard as administrator.
    2.  Open the **Service settings**.
    3.  Click **"Update service"**.
    4.  The system will pull the latest source code, rebuild the container in the background, and restart it once ready.

> **Note**: All "frontend" services (and Immich, SearXNG, and Cobalt) are routed through the VPN tunnel automatically. VERT and core management tools are strictly local-only.

### ⚡ Hardware acceleration (GPU and QSV)
To ensure peak performance for media-heavy tasks, this stack supports hardware-accelerated transcoding and machine learning:

<details>
<summary>🚀 <strong>View hardware acceleration details</strong> (Click to expand)</summary>

*   **Immich**: Utilizes Intel Quick Sync (QSV), VA-API, or NVIDIA GPUs for localized image auto-tagging and video transcoding.
*   **VERT / VERTd**: Optimized for high-speed local file conversion using hardware encoders to minimize CPU load. **Note: VERT requires an HTTPS connection to securely communicate with VERTd.**
*   **Detection and provisioning**: The stack automatically identifies your hardware vendor (Intel, AMD, or NVIDIA) during deployment via [lib/scripts.sh](lib/scripts.sh) and provisions the necessary devices (`/dev/dri`, `/dev/vulkan`) or container reservations.
*   **Requirements**: Ensure your ZimaOS or host device has the correct drivers installed (e.g., `intel-media-driver` or `nvidia-container-toolkit`).

</details>

---

<details>
<summary>🌐 <strong>Network & Advanced Configuration</strong> (Click to expand)</summary>

## 🌐 Network configuration

These settings help you get the most out of your Privacy Hub on your local network.

#### 1. Remote access and split-tunneling
**Stop: you probably do not need to do anything here.**
*   **Default state**: Your hub remains invisible to the internet. This is the safest way to live.
*   **Remote access**: Forward **UDP port 51820** on your router only if you want to connect to your hub while away from home. Valid public/private keys are required for access.
*   **Split-tunneling**: We use split-tunneling to ensure your connection remains fast. Only DNS requests and hub services route through the tunnel, while other traffic exits directly from your device.
*   **Why no other ports?**: Every other service (Dashboard, AdGuard, etc.) is reached through this WireGuard tunnel once you are connected. Opening more ports is like leaving your back door open when you already have a key to the front door. This is essential for users to securely access their DNS and services outside their home network.

#### 2. DNS protection
Your hub runs its own **recursive DNS resolver** (Unbound and AdGuard Home). This means:
*   **No third-party DNS**: Your queries go directly to authoritative root servers, not Google or Cloudflare.
*   **Built-in ad blocking**: Network-wide filtering for all devices on your network.
*   **Encrypted queries**: Supports DNS-over-TLS, DNS-over-HTTPS, and DNS-over-QUIC.

To use it, point your router's DHCP settings to hand out your hub's IP as the DNS server for all devices.

#### 3. Split tunnel architecture

This stack uses a **dual split tunnel** architecture to balance privacy, performance, and reliability. Traffic is intelligently routed through three distinct zones:

<details>
<summary>🗺️ <strong>View routing zones and logic</strong> (Click to expand)</summary>

##### Zone 1: VPN-isolated services (Gluetun tunnel)
Privacy frontends and external-facing services are routed exclusively through the VPN tunnel:

| Service | Purpose | Benefit |
| :--- | :--- | :--- |
| **Invidious** | YouTube frontend | Prevents Google from linking your home IP to video watches |
| **Companion** | Invidious helper | Enhanced video retrieval through VPN |
| **Redlib** | Reddit frontend | Stops Reddit tracking and "Open in App" harassment |
| **SearXNG** | Meta search engine | Search queries anonymized through shared VPN IP |
| **Wikiless** | Wikipedia frontend | Removes Wikimedia cross-site tracking |
| **Rimgo** | Imgur frontend | Anonymous image viewing |
| **BreezeWiki** | Fandom frontend | Blocks aggressive ad networks |
| **AnonOverflow** | StackOverflow frontend | Developer research without corporate profiling |
| **Scribe** | Medium frontend | Paywall bypass and tracking removal |
| **Immich** | Photo management | ML model downloads and metadata fetched via VPN* |
| **Cobalt** | Media downloader | Downloads anonymized through VPN |
| **Memos** | Note taking | Version checks and metadata fetched via VPN |

**Kill switch protection**: If the VPN tunnel fails, these services lose internet access entirely. They cannot accidentally expose your home IP.

##### Zone 2: Remote access (WireGuard tunnel)
When connecting from outside your home network (phone, laptop), traffic flows through your personal WireGuard tunnel:

- **DNS requests** → Routed to your home AdGuard for ad-blocking everywhere
- **Hub services** → Direct access to your dashboard and private apps
- **Other internet traffic** → Exits directly from your device (not routed home)

**Benefit**: Your phone stays fast (Netflix doesn't lag) while you still get network-wide ad-blocking and access to your private services.

##### Zone 3: Local-only services
Management tools and utilities that never touch the internet:

| Service | Purpose | Why local |
| :--- | :--- | :--- |
| **Dashboard** | Unified control center | No external dependencies |
| **AdGuard Home** | DNS filtering | Must be accessible even if VPN fails |
| **Portainer** | Container management | Security-critical, no external exposure |
| **VERT / VERTd** | File conversion | GPU-accelerated, all processing local |
| **Unbound** | Recursive DNS | Talks directly to root servers |
| **WireGuard (wg-easy)** | VPN server | Manages your remote access peers |

*\*Immich uses VPN only for ML model downloads and external metadata; your photos remain strictly local.*

</details>

---

<a id="advanced-setup"></a>
## 📡 Advanced setup: OpenWrt and double NAT

If you are running a real router like **OpenWrt** behind your ISP modem, you are in a **double NAT** situation. You need to fix the routing so your packets actually arrive.

### 1. Static IP and WAN configuration
*   **Static hub lease**: Assign a static lease on your **OpenWrt** router so your Privacy Hub remains at a fixed internal IP (e.g., `192.168.69.206`).
*   **Static router WAN**: In a double NAT setup (ISP Modem -> OpenWrt -> Hub), ensure your OpenWrt router has a **static IP** (e.g., `192.168.1.209`) assigned by the ISP modem on its WAN interface. This ensures the port forwarding rule on the ISP modem remains stable.

<details>
<summary>💻 <strong>CLI: UCI commands for static lease</strong> (Click to expand)</summary>

```bash
# Add the static lease on OpenWrt (Replace MAC with your hardware's values)
uci add dhcp host
uci set dhcp.@host[-1].name='ZimaOS-Privacy-Hub'
uci set dhcp.@host[-1].mac='00:11:22:33:44:55' # <--- REPLACE THIS WITH YOUR MAC
uci set dhcp.@host[-1].ip='192.168.69.206'     # <--- HUB LAN IP
uci commit dhcp
/etc/init.d/dnsmasq restart
```
</details>

### 2. Port forwarding and firewall
OpenWrt is the gatekeeper. Point the traffic to your machine and then actually open the door.

<details>
<summary>💻 <strong>CLI: UCI commands for firewall</strong> (Click to expand)</summary>

```bash
# 1. Add port forwarding (Replace dest_ip with your ZimaOS machine's IP)
uci add firewall redirect
uci set firewall.@redirect[-1].name='Forward-WireGuard'
uci set firewall.@redirect[-1].src='wan'
uci set firewall.@redirect[-1].proto='udp'
uci set firewall.@redirect[-1].src_dport='51820'
uci set firewall.@redirect[-1].dest_ip='192.168.69.206' # <--- HUB LAN IP
uci set firewall.@redirect[-1].dest_port='51820'
uci set firewall.@redirect[-1].target='DNAT'

# 2. Add traffic rule (allowance)
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

### 3. DNS hijacking (force compliance)
Some devices (IoT, smart TVs) hardcode DNS servers (like `8.8.8.8`) to bypass your filters. You can force them to comply using a **NAT redirect** rule.

To implement this on your router, refer to the following official guides:
*   [OpenWrt Guide: Intercepting DNS](https://openwrt.org/docs/guide-user/firewall/fw3_configurations/intercept_dns) (Step-by-step NAT redirection)
*   [OpenWrt Guide: Blocking DoH (banIP)](https://openwrt.org/docs/guide-user/firewall/firewall_configuration/ban_ip) (Preventing filter bypass via encrypted DNS)

### 🛡️ Privacy and architecture

#### Minimalist source strategy
To ensure maximum security and stability, this stack prioritizes official pre-built images for the majority of its services. Only a small number of core components and specific frontends are built from source locally:

*   **Core logic**: The Hub API and Odido Booster are built from local sources to ensure perfect integration with the host environment.
*   **Selected frontends**: Services like Wikiless and Scribe are built from their respective upstream repositories, ensuring you get the exact code intended by the developers while benefiting from local image optimization.

#### Dual-zone split tunneling
The stack implements an intelligent routing model to balance performance and total privacy:
- **🔒 VPN zone (kill-switch protected)**: Services like Invidious, SearXNG, and Redlib are locked inside the VPN. If the tunnel drops, they lose all connectivity instantly, preventing any IP leaks.
- **🏠 Home zone (direct access)**: Management tools (Dashboard, AdGuard, Portainer) are accessible directly via your LAN IP or WireGuard remote access tunnel for maximum reliability.

#### DNS subdomain mapping and HTTPS
When a **deSEC** domain is configured, the system automatically provisions:
- **Wildcard DNS rewrites**: `*.yourdomain.dedyn.io` resolves automatically to your hub's internal IP.
- **Nginx subdomain routing**: Each service is reachable via its own secure subdomain (e.g., `invidious.yourdomain.dedyn.io`).
- **End-to-end encryption**: Valid Let's Encrypt certificates are automatically managed and applied to all subdomain endpoints on port `8443`.

#### Unified deployment and continuous updates
This stack uses a **unified deployment** model combined with **Watchtower** for automated updates, ensuring you always have the latest privacy fixes without manual intervention.

- **Latest-stable strategy**: By default, all service frontends pull the `latest` stable image.
- **Automated lifecycle**: Watchtower monitors your containers and performs graceful restarts when new upstream security patches are released.
- **Single-stage verification**: The integrated test suite verifies the entire stack in one pass, ensuring inter-service dependencies are validated.

#### Human-Readable Event Logging
To simplify system administration, the dashboard includes a real-time event stream that translates technical API logs into human-readable actions.

- **Intelligent Translation**: Technical events (e.g., `POST /verify-admin`) are automatically humanized (e.g., "Administrative session authorized") before being displayed.
- **Categorized Auditing**: Logs are tagged by category (Network, Security, Maintenance, Orchestration) with corresponding Material Design icons for rapid visual scanning.
- **Live Stream**: The dashboard maintains a persistent EventSource connection to the Hub API, ensuring zero-latency visibility into system operations.

#### Zero-leaks asset architecture
External assets (fonts, icons, scripts) are fetched once via the **Gluetun VPN proxy** and served locally. Your public home IP is never exposed to CDNs.

**Privacy enforcement logic:**
1.  **Container initiation**: When the Hub API container starts, it initiates an asset verification check.
2.  **Proxy routing**: If assets are missing, the Hub API routes download requests through the Gluetun VPN container (acting as an HTTP proxy on port 8888).
3.  **Encapsulated fetching**: All requests to external CDNs occur *inside* the VPN tunnel. Upstream providers only see the VPN IP.
4.  **Local persistence**: Assets are saved to a persistent Docker volume (`/assets`).
5.  **Offline serving**: The Management Dashboard serves all UI resources exclusively from this local volume.

#### Backup and Portability
The stack includes an integrated backup and restoration engine designed for maximum portability and data sovereignty.

- **One-Click Backups**: Generate timestamped `.tar.gz` archives of all system secrets, environment variables, and core configurations directly from the dashboard.
- **State Restoration**: Restore your entire system state from any valid backup archive. The system automatically handles file extraction and triggers a stack-wide restart to apply restored settings.
- **Portability**: Backups are independent of hardware and can be used to migrate your privacy hub to a new host device by simply restoring the archive on a fresh installation.

---

### 🛡️ Blocklist information & DNS Filtering
*   **Source**: Blocklists are generated using the [Lyceris-chan DNS Blocklist Generator](https://github.com/Lyceris-chan/dns-blocklist-generator/).
*   **Composition**: Based on **Hagezi Pro++**, curated for performance and dutch users.
*   **Note**: This blocklist is **aggressive** by design.

### 🛡️ Deployment strategy
This stack uses a hybrid deployment model to balance privacy with system stability.

- **Pre-built Images**: Most services use trusted upstream images to ensure fast deployment and reliable updates.
- **Local Optimization**: Critical orchestration components and selected frontends are optimized for your environment through local builds.

### 🛡️ Self-healing & High availability
*   **VPN Monitoring**: Gluetun is continuously monitored. Docker restarts the gateway if the tunnel stalls.
*   **Frontend Auto-Recovery**: Privacy frontends utilize `restart: always`.
*   **Health-Gated Launch**: Infrastructure services must be `healthy` before frontends start.

### Data minimization & anonymity
*   **Specific User-Agent Signatures**: Requests use industry-standard signatures to blend in.
*   **Zero Personal Data**: No API keys or hardware IDs are transmitted during checks.
*   **Isolated Environment**: Requests execute from within containers without host-level access.

</details>

---

---

## 🛠️ Production deployment & disaster recovery

### Production Best Practices
For a stable, long-term deployment, follow these guidelines:

1.  **Dedicated Hardware**: While it runs on many systems, a dedicated machine (like a ZimaBoard or an old NUC) ensures your privacy hub is always available.
2.  **Static IP**: Assign a static LAN IP to your hub in your router settings.
3.  **Uninterruptible Power Supply (UPS)**: Protect against data corruption during power outages.
4.  **Automatic Backups**: Schedule regular backups of the `data/AppData/privacy-hub` directory.

### disaster recovery

#### Scenario 1: The system is slow or glitchy
Run the maintenance command to recreate containers without losing data:
```bash
./zima.sh -c
```

#### Scenario 2: Total hardware failure
1.  Set up a new machine with Docker and Git.
2.  Clone this repository.
3.  Restore your `data/AppData/privacy-hub` folder from your latest backup.
4.  Run `./zima.sh`. The script will detect your existing configs and restore the stack.

#### Scenario 3: "I need a fresh start"
To wipe everything and start over (Warning: IRREVERSIBLE):
```bash
./zima.sh -x
```

---

---

<details>
<summary>🛡️ <strong>Security and Networking</strong> (Click to expand)</summary>

## 🛡️ Security and networking

### Hardened security baseline
We prioritize minimal, security-focused images for all services.
*   **The Benefit**: Minimal images reduce the attack surface by removing unnecessary binaries and libraries, following the principle of least privilege. (Concept based on [CIS Benchmarks](https://www.cisecurity.org/benchmark/docker) and minimal base image best practices).

### Split-tunneling architecture
The stack uses a split-tunneling architecture. Only the WireGuard port (UDP 51820) is exposed to the public internet. 

*   **Key-Based Access**: Access is strictly gated by WireGuard public and private keys. This is required to allow users to securely use their DNS and services outside their home network.
*   **Silent Drop**: WireGuard does not respond to packets it does not recognize. To a scanner, the port looks closed.
*   **DDoS mitigation**: Because it is silent to unauthenticated packets, it is inherently resistant to flooding attacks.
*   **Cryptographic ownership**: You cannot "guess" a password. You need a valid 256-bit key.

### HTTPS and deSEC requirements
A valid SSL certificate (obtained via deSEC) is necessary for DNS-over-HTTPS (DoH) and DNS-over-QUIC (DoQ) to function correctly. Additionally, VERT requires HTTPS to connect securely with its daemon API.

</details>

---

<details>
<summary>🔧 <strong>Troubleshooting</strong> (Click to expand)</summary>

## 🔧 Troubleshooting

| Issue | Potential Solution |
| :--- | :--- |
| **"My internet broke!"** | DNS resolution failed. Temporarily set your router DNS to **[Quad9](https://www.quad9.net/)** (`9.9.9.9` - [Privacy Policy](https://www.quad9.net/privacy/)) or **[Mullvad](https://mullvad.net/en/help/dns-over-https-and-dns-over-tls/)** (`194.242.2.2` - [Privacy Policy](https://mullvad.net/en/help/privacy-policy/)) to restore access, then check the Hub status. <br><br> **⚠️ CRITICAL**: While we recommend these for their strong privacy focus and "no-logging" policies, **do not** set them as your secondary DNS IP if you want absolute privacy. Most operating systems will query both DNS servers simultaneously; if you have a "fast" public DNS as a secondary, your queries will leak to them even if your self-hosted one is working. Use your self-hosted DNS exclusively once it is stable. |
| **"I can't connect remotely"** | **1.** Verify Port 51820 (UDP) is forwarded. **2.** If using OpenWrt, ensure "Double NAT" is handled (ISP -> OpenWrt -> Hub). **3.** Check if your ISP uses CGNAT. <details><summary>What is CGNAT?</summary>Carrier-Grade NAT (CGNAT) is a technique used by ISPs to share a single public IP address among multiple customers. This makes port forwarding impossible because you don't have a unique public IP. If you are behind CGNAT, traditional VPN/Port Forwarding won't work without a middleman like Tailscale or a VPS relay.</details> |
| **"Services are slow"** | **1.** Check VPN throughput in the dashboard. **2.** Try a different ProtonVPN server config. **3.** Ensure your host has sufficient CPU/RAM for compilation tasks. |
| **"SSL is invalid"** | Check `certbot/monitor.log` via dashboard. Ensure ports 80/443 are reachable for validation. Verify your deSEC token. |

> 💡 **Pro-Tip**: Use `docker ps` to verify all containers are `Up (healthy)`. If a container is stuck, use `docker logs <name>` to see why.

</details>

---

<details>
<summary>💾 <strong>Maintenance and Restoration</strong> (Click to expand)</summary>

## 💾 Maintenance

### ⚠️ IMPORTANT: Back Up Your Data

Before performing any maintenance operations, **always back up your data first**. The Privacy Hub stores valuable personal information:

| Service | Data Stored |
| :--- | :--- |
| **Memos** | Personal notes, journal entries, attachments |
| **Invidious** | YouTube subscriptions, watch history, preferences |
| **Immich** | Photos, videos, albums, facial recognition data |
| **AdGuard** | DNS query logs, custom filtering rules |
| **WireGuard** | VPN client configurations |

> ⚠️ **WARNING**: Using `-x` (Factory Reset) or clearing service databases **permanently deletes all data**. This action **cannot be undone**!

**Backup and Restore:**

*   **Update**: Click "Check Updates" in the dashboard or run `./zima.sh` again.
*   **Backup**:
    *   **Dashboard**: Click **"Backup system"** in the System Information card. This creates a timestamped archive of your secrets, environment files, and service configurations.
    *   **CLI**: Run `./zima.sh -b`.
    *   **Manual**:
        ```bash
        # Manual backup of critical data (Secrets, Configs, Databases)
        # Adjust path to match your installation
        cp -r /data/AppData/privacy-hub /backup/location/
        ```
*   **Restore**:
    *   **Dashboard**: Click **"Restore from backup"**, select your desired archive, and confirm. The system will automatically overwrite current configurations and restart the stack.
    *   **CLI**: Run `./zima.sh -r /path/to/backup.tar.gz`.
*   **Uninstall**:
    ```bash
    ./zima.sh -x
    ```
    *(Note: This **only** removes the containers and volumes created by this specific privacy stack. Your personal documents, photos, and unrelated Docker containers are **never** touched.)*

</details>

---

---

## 🧩 Advanced usage

<details>
<summary><strong>🧪 Staged headless verification</strong> (CI/CD & Automation)</summary>

For developers and advanced users, the Privacy Hub includes a staged, headless verification system designed for rigorous CI/CD environments and automated stability testing. This system utilizes a state-aware orchestrator to manage multi-stage deployments with automatic crash recovery.

### Running the Verification

To execute the full verification suite in headless mode:

```bash
# Run the automated orchestrator
./test/manual_verification.sh
```

### Key features

*   **🧱 Multi-Stage Testing**: Tests are divided into logical stages (Core, Frontends, Management, etc.) to isolate failure points.
*   **🔄 Auto-Resume Logic**: If the verification is interrupted (e.g., system crash, timeout), simply running the script again will automatically resume from the last pending stage.
*   **⏱️ Timeout Protection**: The orchestrator includes an 18-minute cycle limit to ensure clean state transitions in restricted environments (like GitHub Actions).
*   **📊 Comprehensive Logging**: Each stage generates dedicated logs (e.g., `test/stage_1.log`) and a global `test/progress.log` for auditability.
*   **🎭 UI Audit**: Automatically executes Puppeteer-based interaction tests to ensure the Material Design 3 dashboard remains functional across all supported platforms.

</details>

<details>
<summary><strong>🔧 Add Your Own Services</strong> (advanced, not needed for new users)</summary>

The stack uses a modular generation system. To add a new service, you will need to modify the generator scripts in the `lib/` directory.

### 1) Registry and constants (`lib/core/constants.sh`)

Add your service ID to `STACK_SERVICES` and `ALL_CONTAINERS`. If it's a source-built service, add it to `SOURCE_BUILT_SERVICES`.

### 2) Add to compose (`lib/services/compose.sh`)

Create an `append_myservice` function and call it within `generate_compose`.

```bash
append_myservice() {
  if ! should_deploy "myservice"; then return 0; fi
  cat >> "${COMPOSE_FILE}" <<EOF
  myservice:
    image: my-image:latest
    container_name: \${CONTAINER_PREFIX}myservice
    networks: [frontend]
    restart: unless-stopped
EOF
}
```

If you want the service to run through the VPN, use `network_mode: "container:\${CONTAINER_PREFIX}gluetun"` and `depends_on: gluetun`.

### 3) Configuration and dashboard (`lib/services/config.sh`)

Add your service metadata to the `SERVICES_JSON` block inside `generate_scripts`. This enables the service to appear on the dashboard.

```json
"myservice": {
  "name": "My Service",
  "description": "Short description.",
  "category": "apps",
  "order": 100,
  "url": "http://\$LAN_IP:1234"
}
```

### 4) Automated updates and rollbacks

*   **Watchtower**: To opt out, add `com.centurylinklabs.watchtower.enable=false` under the service labels in `compose.sh`.
*   **Rollback support**: Enabled automatically for source-built services if "Rollback Support" is toggled ON in the dashboard settings.

</details>

<details>
<summary><strong>⏪ Version Rollback System</strong> (Recovery)</summary>

To ensure production stability, the Hub includes a version rollback system for services built from source (e.g., Wikiless, Scribe).

### How it works
1.  **Snapshot**: If "Rollback Support" is enabled in settings (Default: OFF), the system captures the current Git commit hash before performing any update.
2.  **Backup**: A service-specific state file is saved to `data/hub-api/rollback_<service>.json`.
3.  **Revert**: If an update causes issues, a "Rollback version" button appears in the service management modal.
4.  **Restoration**: Clicking "Rollback" checks out the previously saved Git hash and rebuilds the container immediately.

### Limitations
*   **Source-only**: Rollback is currently only available for services built from local Git repositories.
*   **Single-stage**: Only the version immediately preceding the current one is preserved.
*   **Data integrity**: Rollback reverts the application code but does not automatically revert database migrations unless specified in the service's migration logic.

</details>

<details>
<summary><strong>🧪 Automated verification</strong> (Click to expand)</summary>

To ensure a "set and forget" experience, every release undergoes a rigorous automated verification pipeline.
*   **Interaction Audit**: Puppeteer-based suite simulates real user behavior.
*   **Non-Interactive Deployment**: verified `-p -y` flow for zero-prompt success.
*   **M3 Compliance Check**: Automated layout audits ensure the dynamic grid and chips adapt to any screen size.
*   **Log & Metric Integrity**: Container logs audited for 502/504 errors.
</details>

<details>
<summary><strong>🌐 Connection exposure map & Privacy Policies</strong> (Click to expand)</summary>

### Connection exposure map

| Service / Domain | Purpose | Exposure |
| :--- | :--- | :--- |
| **Frontends (YouTube/Reddit)** | Privacy content retrieval | **🔒 VPN IP** (Gluetun) |
| **Dashboard Assets** | Fonts (Fontlay) & Icons (JSDelivr) | **🔒 VPN IP** (Gluetun) |
| **VPN Client Management** | Managing WireGuard clients | **🔒 VPN IP** (Gluetun) |
| **VPN Status & IP Check** | Tunnel health monitoring | **🔒 VPN IP** (Gluetun) |
| **Health Checks** | VPN Connectivity Verification | **🔒 VPN IP** (Gluetun) |
| **Container Registries** | Pulling Docker images (Docker/GHCR) | **🏠 Home IP** (Direct) |
| **Git Repositories** | Cloning source code (GitHub/Codeberg) | **🏠 Home IP** (Direct) |
| **DNS Blocklists** | AdGuard filter updates | **🔒 VPN IP** (Gluetun) |
| **deSEC.io** | SSL DNS Challenges | **🔒 VPN IP** (Gluetun)* |
| **Odido API (Setup)** | Initial User ID retrieval | **🔒 VPN IP** (Gluetun)* |
| **Odido API (Active)** | Mobile Data fetching | **🔒 VPN IP** (Gluetun) |
| **Cobalt** | Media downloads | **🔒 VPN IP** (Gluetun) |
| **SearXNG / Immich** | Search & Media sync | **🔒 VPN IP** (Gluetun) |

*\*Setup/Configuration tasks attempt to use the VPN proxy if available, but may fall back to direct Home IP if the VPN service is not yet established.*

### Detailed privacy policies

- **Public IP Detection & Health**:
  - [ipify.org](https://www.ipify.org/) (Used to display VPN status; exposes **🔒 VPN IP**)
  - [ip-api.com](https://ip-api.com/docs/legal) (Used for geolocation health; exposes **🔒 VPN IP**)
  - [connectivity-check.ubuntu.com](https://ubuntu.com/legal/data-privacy) (Used for VPN tunnel verification; exposes **🔒 VPN IP**)
- **Infrastructure & Assets**:
  - [deSEC.io](https://desec.io/privacy-policy) (SSL challenges via **🏠 Home IP**)
  - [fontlay.com](https://github.com/miroocloud/fontlay) (Fetched via **🔒 VPN IP**)
  - [cdn.jsdelivr.net](https://www.jsdelivr.com/terms/privacy-policy-jsdelivr-net) (Fetched via **🔒 VPN IP**)
| **Registries & Source Code** |
  - [Docker Hub](https://www.docker.com/legal/docker-privacy-policy/) (Image pulls via **🏠 Home IP**)
  - [GitHub / GHCR](https://docs.github.com/en/site-policy/privacy-policies/github-privacy-statement) (Source cloning via **🏠 Home IP**)
  - [Codeberg](https://codeberg.org/privacy) (Source cloning via **🏠 Home IP**)
  - [Quay.io](https://quay.io/privacy) (Image pulls via **🏠 Home IP**)
  - [SourceHut](https://man.sr.ht/privacy.md) (Source cloning via **🏠 Home IP**)
  - [Gitdab](https://gitdab.com/) (Source cloning via **🏠 Home IP**)
- **Data Providers**:
  - [DNS Blocklists (GitHub)](https://docs.github.com/en/site-policy/privacy-policies/github-privacy-statement) (Fetched via **🔒 VPN IP**)
  - [Odido API](https://www.odido.nl/privacy) (ID retrieval via **🏠 Home IP** during setup; automated data via **🔒 VPN IP**)
  - [Immich Privacy Policy](https://docs.immich.app/privacy-policy) (Note: Immich does not collect any data unless you choose to support the project via buy.immich.app, where data is used strictly for tax calculations.)

</details>

---

## 🚨 Disclaimer

This software is provided "as is". While designed for security, the user is responsible for ensuring their specific network configuration is safe. **Do not use GitHub Codespaces for production deployment.**

---

*Built with ❤️ for digital sovereignty.*
