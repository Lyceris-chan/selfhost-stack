# 🛡️ ZimaOS Privacy Hub

**Stop being the product.**

A comprehensive, self-hosted privacy infrastructure designed for digital independence. Route your traffic through secure VPNs, eliminate tracking with isolated frontends, and manage everything from a unified **Material Design 3** dashboard.

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
- [Dashboard & Services](#️-dashboard--services)
  - [WireGuard Client Management](#-wireguard-client-management)
  - [Credential Management](#-credential-management)
  - [LibRedirect Integration](#-libredirect-integration)
  - [Included Privacy Services](#included-privacy-services)
  - [Hardware Acceleration](#-hardware-acceleration-gpuqsv)
  - [Network Configuration](#-network-configuration)
- [Advanced Setup: OpenWrt & Double NAT](#-advanced-setup-openwrt--double-nat)
- [Privacy & Architecture](#️-privacy--architecture)
  - [A/B Update System](#automatic-version-pinning--ab-system)
  - [Surgical Patch Registry](#surgical-patch-registry)
- [Security Standards](#-security-standards)
- [System Requirements](#️-system-requirements)
- [Troubleshooting](#-troubleshooting)
- [Maintenance](#-maintenance)

---

## 🚀 Key Features

*   **🔒 Data Independence**: Host your own frontends (Invidious, Redlib, etc.) to stop upstream giants like Google and Reddit from profiling you.
*   **🚫 Ad-Free by Design**: Network-wide ad blocking via AdGuard Home + native removal of sponsored content in video/social feeds.
*   **🕵️ VPN-Gated Privacy**: All external requests are routed through a **Gluetun VPN** tunnel. Upstream providers only see your VPN IP, keeping your home identity hidden.
*   **📺 No Adblock Nags (Invidious)**: Watch YouTube without annoying "please disable your adblocker" popups. Invidious fetches video data server-side, so YouTube never knows you're using an adblocker—because you're not even using their website.
*   **📱 Frictionless Browsing (Redlib)**: Redlib eliminates aggressive "Open in App" prompts and mobile-web trackers. Enjoy a fast, premium Reddit experience on any device without being forced into the official app's data-harvesting ecosystem.
*   **🚀 Faster & Safer**: Self-hosted frontends strip out tracking scripts, telemetry, and bloated JavaScript. The result? Pages load faster and your browser isn't executing code designed to spy on you.
*   **🔑 Easy Remote Access**: Built-in **WireGuard** management. Generate client configs and **QR codes** directly from the dashboard to connect your phone or laptop securely.
*   **🔄 Atomic A/B Updates**: Safe, zero-downtime updates with automated rollback capability. Switch between "Slot A" and "Slot B" to ensure high availability during service maintenance.
*   **⚡ Hardware Performance**: Automatically detects and provisions GPU acceleration (Intel QSV, AMD VA-API, or NVIDIA) for media-heavy services like Immich and VERT. Code is built from source locally to ensure compatibility with your host environment.
*   **🎨 Material Design 3**: A beautiful, responsive dashboard with dynamic theming and real-time health metrics.

> ⚠️ **Heads Up: The Cat-and-Mouse Game**  
> Companies like Google and Reddit **actively try to break** these privacy frontends. Why? Because every user on Invidious or Redlib is a user they can't track, monetize, or serve ads to. They regularly change their APIs, add new anti-bot measures, and modify their page structures specifically to break these tools. This stack uses **local builds** so we can apply fixes quickly when upstream breaks—but occasional outages are part of the privacy game. It's worth it.

---

## 🚀 Deployment

**Don't worry—this is easier than it looks!** The Privacy Hub guides you through everything. Just follow these steps, and you'll have your own private internet in about 20 minutes.

### Before You Start (Checklist)

You'll need:
- [ ] A computer running **ZimaOS**, **Ubuntu 22.04+**, or **Debian 12+** (this will be your "hub")
- [ ] **Docker** installed on that computer ([Get Docker](https://docs.docker.com/get-docker/))
- [ ] A **ProtonVPN** account (free tier works!) for your VPN tunnel
- [ ] *(Optional)* A **deSEC** account for a free domain name (for remote access with SSL)

---

### Step 1: Get Your VPN Configuration

*Think of this as getting the "key" to your secret tunnel.*

1.  **Create a ProtonVPN account** (if you don't have one): [ProtonVPN Signup](https://account.protonvpn.com/signup)
2.  Go to [ProtonVPN Downloads](https://account.protonvpn.com/downloads)
3.  Scroll down to **WireGuard configuration**
4.  Click **Create** and choose any server (Netherlands or Switzerland are good for privacy)
5.  **⚠️ IMPORTANT**: Ensure **NAT-PMP (Port Forwarding)** is set to **OFF** (see warning below)
6.  Click **Download** to save the `.conf` file
7.  **Open** the downloaded file in a text editor—you'll paste its contents during setup

> 📝 **What you're getting**: This file contains your personal "tunnel key" that lets your hub connect to ProtonVPN's servers. Your real home IP stays hidden!

> ⚠️ **NAT-PMP WARNING**: Do **NOT** enable NAT-PMP (Port Forwarding) when generating your WireGuard config!
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

### Step 2: Get Your Domain Token *(Optional but Recommended)*

*This gives your hub a memorable name like `my-home.dedyn.io` instead of an IP address.*

1.  Register at [deSEC.io](https://desec.io) (it's free and privacy-focused)
2.  Verify your email and log in
3.  Click **"+ Add Domain"** and create a subdomain (e.g., `my-privacy-hub.dedyn.io`)
4.  Go to **Token Management** → **"+"** to create a new token
5.  **Copy and save this token**—you'll need it during setup

> 📝 **What you're getting**: This token lets the installer automatically set up SSL certificates so your connection is encrypted.

> ⚠️ **Why you need this for HTTPS**: Without a domain, your browser will show scary "Your connection is not private" warnings because SSL certificates can only be issued for domain names, not IP addresses. The deSEC domain + token allows the installer to automatically obtain a free **Let's Encrypt** certificate, so your dashboard and services load securely without any browser warnings. If you skip this step, you'll need to click through security warnings every time you access your hub.

---

### Step 3: Download and Run the Installer

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
1.  **Paste your WireGuard config** (from Step 1)
2.  **Enter your deSEC domain and token** (from Step 2, or skip if you didn't set this up)
3.  **Choose your password preferences** (auto-generate or set your own)

That's it! Sit back and let it build (~15-20 minutes).

> 💡 **The "I'm in a hurry" Way**: Use `./zima.sh -P` to fast-track setup with automated passwords and parallel builds.

<a id="customization-flags"></a>
### 🛠️ Customization Flags (Optional)

Before running the installer, you can customize your deployment using these flags:

| Flag | Description |
| :--- | :--- |
| `-p` | **Auto-Passwords**: Generates random secure credentials automatically. |
| `-y` | **Auto-Confirm**: Skips yes/no prompts (Headless mode). |
| `-P` | **Personal Mode**: Fast-track setup (combines `-p`, `-y`, and `-j`). |
| `-j` | **Parallel Deploy**: Builds everything at once. Faster, but high CPU usage! |
| `-s` | **Selective**: Install only specific apps (e.g., `-s invidious,memos`). |
| `-S` | **Swap Slots**: A/B Update toggle. Deploys the new version to the standby slot before swapping. |
| `-c` | **Maintenance**: Recreates containers and networks to fix glitches while **preserving** your persistent data. |
| `-x` | **Factory Reset**: ⚠️ **Deletes everything**. Wipes all containers, volumes, and application data. |
| `-a` | **Allow ProtonVPN**: Adds ProtonVPN domains to the AdGuard allowlist for browser extension users. Entries added: `getproton.me`, `vpn-api.proton.me`, `protonstatus.com`, `protonvpn.ch`, `protonvpn.com`, `protonvpn.net`. This does not affect other privacy services or VPN functionality. |
| `-D` | **Dashboard Only**: Regenerates only the dashboard without rebuilding services. Useful for UI testing and development. |
| `-h` | **Help**: Displays usage information and available flags. |

**Example usage:**
```bash
# Fast-track personal deployment
./zima.sh -P

# Selective deployment with auto-passwords
./zima.sh -p -y -s invidious,memos,searxng

# Dashboard-only rebuild (development/testing)
./zima.sh -D
```

> 💡 **Development Tip**: Use `-s` for Codespaces or limited storage environments. Use `-D` when testing UI changes without rebuilding all services.

---

### What Happens Next?

1.  **🔨 Privacy Build**: The system clones and builds your private apps
2.  **✅ Ready to Use**: You get a link to your dashboard (e.g., `http://192.168.1.100:8081`)
3.  **🔐 Credential Export**: Your passwords are saved for safe keeping
4.  **🔀 Instant Redirection**: A `libredirect_import.json` is created—import this into the [LibRedirect](https://libredirect.github.io/) browser extension to automatically redirect YouTube/Reddit to your hub

> 📁 **Where are my passwords?**: Check the [Credential Management](#-credential-management) section for details on accessing your generated credentials.

---

## 🛡️ How It Works (Architecture)

This section explains the technical details behind the privacy features listed above.

### Recursive DNS Engine (Independent Resolution)
This stack features a hardened, recursive DNS engine built on **Unbound** and **AdGuard Home**, designed to eliminate upstream reliance and prevent data leakage.

#### 🛡️ Advanced Security & RFC Compliance
*   **QNAME Minimization ([RFC 7816](https://datatracker.ietf.org/doc/html/rfc7816))**: Dramatically improves privacy by only sending the absolute minimum part of a domain name to upstream authoritative servers. Instead of asking a root server for `very.private.example.com`, it only asks for the `.com` TLD, keeping your full intent hidden.
*   **DNSSEC Validation ([RFC 4033](https://datatracker.ietf.org/doc/html/rfc4033))**: Protects against DNS spoofing and cache poisoning by cryptographically verifying the authenticity of DNS records. The resolver strictly rejects responses that have been stripped of security signatures.
*   **Aggressive Caching ([RFC 8198](https://datatracker.ietf.org/doc/html/rfc8198))**: Uses NSEC records to generate negative responses locally, reducing traffic to authoritative servers and improving performance while resisting certain types of enumeration.
*   **Recursive Resolution**: Unlike standard DNS which forwards your queries to a "Public" resolver (Google/Cloudflare), this engine talks directly to authoritative root servers. This cuts out the middleman and prevents corporate profiling of your browsing history.
*   **Encrypted DNS ([RFC 7858](https://datatracker.ietf.org/doc/html/rfc7858), [RFC 8484](https://datatracker.ietf.org/doc/html/rfc8484), [RFC 9250](https://datatracker.ietf.org/doc/html/rfc9250))**: Supports DNS-over-TLS, DNS-over-HTTPS, and DNS-over-QUIC to prevent local network eavesdropping.
*   **0x20 Bit Randomization**: A security technique that mitigates spoofing attempts by randomly varying the capitalization of query names (e.g., `ExAmPlE.CoM`), which authoritative servers must match in their response.
*   **Privacy Considerations ([RFC 7626](https://datatracker.ietf.org/doc/html/rfc7626))**: Implements best practices for DNS privacy, minimizing data leakage to third parties.
*   **Hardened Access Control ([RFC 1918](https://datatracker.ietf.org/doc/html/rfc1918))**: Restricts resolution to private subnets, preventing unauthorized external usage and potential amplification attacks.
*   **Fingerprint Resistance**: Identity and version queries are explicitly hidden to prevent scanners from identifying the specific resolver software.

### 🔍 Why Self-Host? (The "Trust Gap")
If you don't own the hardware and the code running your network, you don't own your privacy. 
*   **The Google Profile**: Google's DNS (8.8.8.8) turns you into a data source for profiling your health, finances, and interests.
*   **The Cloudflare Illusion**: Even "neutral" providers can be forced to censor or log content.
*   **ISP Predation**: ISPs log and sell your browsing history to data brokers.
*   **Search Engine Isolation**: By routing **SearXNG** through the VPN tunnel, upstream search engines (Google, Bing) see queries coming from a generic VPN IP shared by thousands, making it impossible to profile your individual search behavior or serve targeted ads.

> 📚 **Trusted Sources**: For more on why these measures matter, see the **EFF's [Surveillance Self-Defense](https://ssd.eff.org/)** and their guide on **[DNS Privacy](https://www.eff.org/deeplinks/2020/12/dns-privacy-all-way-root-your-lan)**.

---

<a id="dashboard--services"></a>
## 🖥️ Dashboard & Services

Access your unified control center at `http://<LAN_IP>:8081`.

### 🔑 WireGuard Client Management
Connect your devices securely to your home network:
1.  **Add Client**: Click "New Client" in the dashboard.
2.  **Connect Mobile**: Click the **QR Code** icon and scan it with the WireGuard app on your phone.
3.  **Connect Desktop**: Download the `.conf` file and import it into your WireGuard client.

### 🔐 Credential Management
When using the `-p` (Auto-Passwords) flag, the system generates secure, unique credentials for all core infrastructure.

| Service | Default Username | Password Type | Note |
| :--- | :--- | :--- | :--- |
| **Management Dashboard** | `admin` | Auto-generated | Protects the main control plane. |
| **AdGuard Home** | `adguard` | Auto-generated | DNS management and filtering rules. |
| **WireGuard (Web UI)** | `admin` | Auto-generated | Required to manage VPN peers/clients. |
| **Portainer** | `portainer` | Auto-generated | System-level container orchestration. |
| **Odido Booster** | `admin` | Auto-generated | API key for mobile data automation. |

> 📁 **Where are they?**: All generated credentials are saved to `data/AppData/privacy-hub/.secrets` and exported to `data/AppData/privacy-hub/protonpass_import.csv` for easy importing into your password manager.

### 🔀 LibRedirect Integration
To automatically redirect your browser from big-tech sites to your private Hub:
1.  Install the **LibRedirect** extension ([Firefox](https://addons.mozilla.org/en-US/firefox/addon/libredirect/) / [Chrome](https://chromewebstore.google.com/detail/libredirect/pobhoodpcdojmedmielocclicpfbednh)).
2.  Open the extension settings and go to **Backup/Restore**.
3.  Click **Import Settings** and select the `libredirect_import.json` file found in your project root.
4.  Your browser will now automatically use your local instances for YouTube, Reddit, Wikipedia, and more.

### Included Privacy Services

Every service in this stack is either built from source (and hardened) or pulled from a trusted minimal image. All services marked with **🔒 VPN** are locked inside the VPN tunnel—they cannot "see" the real internet, and the real internet cannot "see" them.

| Service | Category | 🛡️ Routing | Source & Patched Dockerfile |
| :--- | :--- | :--- | :--- |
| **Invidious** | Frontend | **🔒 VPN** | [iv-org/invidious](https://github.com/iv-org/invidious) ([Patched](https://github.com/iv-org/invidious/blob/master/Dockerfile)) |
| **Companion** | Helper | **🔒 VPN** | [iv-org/companion](https://github.com/iv-org/invidious-companion) ([Patched](https://github.com/iv-org/invidious-companion/blob/master/Dockerfile)) |
| **Redlib** | Frontend | **🔒 VPN** | [redlib-org/redlib](https://github.com/redlib-org/redlib) ([Patched](https://github.com/redlib-org/redlib/blob/master/Dockerfile)) |
| **SearXNG** | Frontend | **🔒 VPN** | [searxng/searxng](https://github.com/searxng/searxng) (Pre-built Image) |
| **Scribe** | Frontend | **🔒 VPN** | [edwardloveall/scribe](https://git.sr.ht/~edwardloveall/scribe) ([Patched](https://github.com/edwardloveall/scribe/blob/main/Dockerfile)) |
| **Rimgo** | Frontend | **🔒 VPN** | [rimgo/rimgo](https://codeberg.org/rimgo/rimgo) ([Patched](https://codeberg.org/rimgo/rimgo/src/branch/main/Dockerfile)) |
| **Wikiless** | Frontend | **🔒 VPN** | [Metastem/Wikiless](https://github.com/Metastem/Wikiless) ([Patched](https://github.com/Metastem/Wikiless/blob/master/Dockerfile)) |
| **BreezeWiki** | Frontend | **🔒 VPN** | [breezewiki](https://gitdab.com/cadence/breezewiki) ([Patched](https://github.com/PussTheCat-org/docker-breezewiki-quay/blob/master/docker/Dockerfile)) |
| **AnonOverflow** | Frontend | **🔒 VPN** | [anonymousoverflow](https://github.com/httpjamesm/anonymousoverflow) ([Patched](https://github.com/httpjamesm/anonymousoverflow/blob/master/Dockerfile)) |
| **Cobalt** | Utility | **🏠 Local** | [imputnet/cobalt](https://github.com/imputnet/cobalt) (Pre-built Image) |
| **Memos** | Utility | **🏠 Local** | [usememos/memos](https://github.com/usememos/memos) ([Patched](https://github.com/usememos/memos/blob/main/Dockerfile)) |
| **Immich** | Utility | **🔒 VPN*** | [immich-app/immich](https://github.com/immich-app/immich) (Pre-built Image) |
| **VERT / VERTd** | Utility | **🏠 Local** | [vert-sh/vert](https://github.com/vert-sh/vert) ([Patched](https://github.com/vert-sh/vert/blob/main/Dockerfile)) |
| **AdGuard Home** | Core | **🏠 Local** | [AdGuardHome](https://github.com/AdguardTeam/AdGuardHome) ([Patched](https://github.com/AdguardTeam/AdGuardHome/blob/master/Dockerfile)) |
| **Unbound** | Core | **🏠 Local** | [unbound](https://github.com/klutchell/unbound-docker) ([Patched](https://github.com/klutchell/unbound-docker/blob/master/Dockerfile)) |
| **WireGuard** | Core | **🏠 Local** | [wg-easy](https://github.com/wg-easy/wg-easy) ([Patched](https://github.com/wg-easy/wg-easy/blob/master/Dockerfile)) |
| **Gluetun** | Core | **🌍 Exit** | [gluetun](https://github.com/qdm12/gluetun) ([Patched](https://github.com/qdm12/gluetun/blob/master/Dockerfile)) |
| **Portainer** | Core | **🏠 Local** | [portainer](https://github.com/portainer/portainer) (Pre-built Image) |
| **Dashboard** | Core | **🏠 Local** | [nginx](https://github.com/nginx/nginx) (Pre-built Image) |
| **Hub API** | Core | **🏠 Local** | [Local Source](/hub-api) ([Custom](/hub-api/Dockerfile)) |
| **Odido Booster** | Utility | **🏠 Local** | [odido-booster](https://github.com/Lyceris-chan/odido-bundle-booster) ([Patched](https://github.com/Lyceris-chan/odido-bundle-booster/blob/master/Dockerfile)) |

*\*Immich uses the VPN only for specific machine learning model downloads and metadata fetching. Your photos stay local.

> **Note**: All "Frontend" services (and Immich/SearXNG) are routed through the VPN tunnel automatically. VERT, Cobalt UI, and core management tools are strictly local-only.

### ⚡ Hardware Acceleration (GPU/QSV)
To ensure peak performance for media-heavy tasks, this stack supports hardware-accelerated transcoding and machine learning:
*   **Immich**: Utilizes Intel Quick Sync (QSV), VA-API, or NVIDIA GPUs for localized image auto-tagging and video transcoding.
*   **VERT / VERTd**: Optimized for high-speed local file conversion using hardware encoders to minimize CPU load.
*   **Detection & Provisioning**: The stack automatically identifies your hardware vendor (Intel, AMD, or NVIDIA) during deployment via [lib/scripts.sh](lib/scripts.sh) and provisions the necessary devices (`/dev/dri`, `/dev/vulkan`) or container reservations.
*   **Surgical Fixes**: Specific compilation flags and static library injections are applied in [lib/sources.sh](lib/sources.sh) to ensure these drivers function correctly within the hardened Alpine environments.
*   **Requirements**: Ensure your ZimaOS/host device has the correct drivers installed (e.g., `intel-media-driver` or `nvidia-container-toolkit`).

### 🌐 Network Configuration

These settings help you get the most out of your Privacy Hub on your local network.

#### 1. Remote Access (VPN)
**Stop! You probably don't need to do anything here.**
*   **Default State**: Your hub is invisible to the internet. This is the safest way to live.
*   **Remote Access**: Forward **UDP Port 51820** on your router *only* if you want to connect to your hub while away from home. 
*   **Why No Other Ports?**: Every other service (Dashboard, AdGuard, etc.) is reached *through* this WireGuard tunnel once you're connected. Opening more ports is like leaving your back door open when you already have a key to the front door.

#### 2. DNS Protection
Your hub runs its own **recursive DNS resolver** (Unbound + AdGuard Home). This means:
*   **No third-party DNS**: Your queries go directly to authoritative root servers, not Google or Cloudflare
*   **Built-in ad blocking**: Network-wide filtering for all devices on your network
*   **Encrypted queries**: Supports DNS-over-TLS, DNS-over-HTTPS, and DNS-over-QUIC

To use it, point your router's DHCP settings to hand out your hub's IP as the DNS server for all devices.

#### 3. Split Tunnel Architecture

This stack uses a **Dual Split Tunnel** architecture to balance privacy, performance, and reliability. Traffic is intelligently routed through three distinct zones:

##### Zone 1: VPN-Isolated Services (Gluetun Tunnel)
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

**Kill Switch Protection**: If the VPN tunnel fails, these services lose internet access entirely—they cannot accidentally expose your home IP.

##### Zone 2: Remote Access (WireGuard Tunnel)
When connecting from outside your home network (phone, laptop), traffic flows through your personal WireGuard tunnel:

- **DNS requests** → Routed to your home AdGuard for ad-blocking everywhere
- **Hub services** → Direct access to your dashboard and private apps
- **Other internet traffic** → Exits directly from your device (not routed home)

**Benefit**: Your phone stays fast (Netflix doesn't lag) while you still get network-wide ad-blocking and access to your private services.

##### Zone 3: Local-Only Services
Management tools and utilities that never touch the internet:

| Service | Purpose | Why Local |
| :--- | :--- | :--- |
| **Dashboard** | Unified control center | No external dependencies |
| **AdGuard Home** | DNS filtering | Must be accessible even if VPN fails |
| **Portainer** | Container management | Security-critical, no external exposure |
| **Memos** | Private notes | Your data never leaves your network |
| **Cobalt** | Media downloader | Runs locally, downloads via your IP |
| **VERT / VERTd** | File conversion | GPU-accelerated, all processing local |
| **Unbound** | Recursive DNS | Talks directly to root servers |
| **WireGuard (wg-easy)** | VPN server | Manages your remote access peers |

*\*Immich uses VPN only for ML model downloads and external metadata; your photos remain strictly local.*

---

<a id="advanced-setup"></a>
## 📡 Advanced Setup: OpenWrt & Double NAT

If you are running a real router like **OpenWrt** behind your ISP modem, you are in a **Double NAT** situation. You need to fix the routing so your packets actually arrive.

### 1. Static IP & WAN Configuration
*   **Static Hub Lease**: Assign a static lease on your **OpenWrt** router so your Privacy Hub remains at a fixed internal IP (e.g., `192.168.69.206`).
*   **Static Router WAN**: In a Double NAT setup (ISP Modem -> OpenWrt -> Hub), ensure your OpenWrt router has a **Static IP** (e.g., `192.168.1.209`) assigned by the ISP modem on its WAN interface. This ensures the port forwarding rule on the ISP modem remains stable.

<details>
<summary>💻 <strong>CLI: UCI Commands for Static Lease</strong> (Click to expand)</summary>

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
uci set firewall.@redirect[-1].dest_ip='192.168.69.206' # <--- HUB LAN IP
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

### Zero-Leaks Asset Architecture
External assets (fonts, icons, scripts) are fetched once via the **Gluetun VPN proxy** and served locally. Your public home IP is never exposed to CDNs.

**Privacy Enforcement Logic:**
1.  **Container Initiation**: When the Hub API container starts, it initiates an asset verification check.
2.  **Proxy Routing**: If assets are missing, the Hub API routes download requests through the Gluetun VPN container (acting as an HTTP proxy on port 8888).
3.  **Encapsulated Fetching**: All requests to external CDNs (Fontlay, JSDelivr) occur *inside* the VPN tunnel. Upstream providers only see the VPN IP.
4.  **Local Persistence**: Assets are saved to a persistent Docker volume (`/assets`).
5.  **Offline Serving**: The Management Dashboard (Nginx) serves all UI resources exclusively from this local volume.

---

### 🛡️ Blocklist Information & DNS Filtering
*   **Source**: Blocklists are generated using the [Lyceris-chan DNS Blocklist Generator](https://github.com/Lyceris-chan/dns-blocklist-generator/).
*   **Composition**: Based on **Hagezi Pro++**, curated for performance and dutch users.
*   **Note**: This blocklist is **aggressive** by design.

### 📦 Docker Hardened Images (DHI) & Source Strategy
This stack uses a hybrid deployment model to balance extreme privacy with system stability. We don't just "run" apps; we surgically improve them.

#### 🔨 Services Built from Source
The following services are cloned from their official repositories and compiled locally on your machine:
*   **Infrastructure**: `hub-api`, `gluetun`, `adguard-home`, `unbound`, `wg-easy`.
*   **Frontends**: `invidious`, `redlib`, `wikiless`, `rimgo`, `breezewiki`, `scribe`, `anonymousoverflow`.
*   **Utilities**: `memos`, `vert`, `vertd`, `odido-booster`, `invidious-companion`.

**Why build from source?**
1.  **Transparent Hardening**: We replace standard base images (Debian/Ubuntu) with our own minimal, hardened Alpine variants.
2.  **Telemetry Stripping**: We remove "phone home" signals and tracking scripts at the build level.
3.  **Surgical Patches**: We apply critical fixes (like the VERT stack-size fix or BreezeWiki native conversion) that aren't available in upstream Docker images.
4.  **Hardware Optimization**: Code is compiled specifically for your CPU architecture, ensuring better performance.

#### 📦 Services using Pre-built Images
The following services use trusted upstream images:
*   **`Immich`**, **`SearXNG`**, **`Cobalt`**, **`Portainer`**, **`Nginx` (Dashboard)**.

**Why use images?**
*   **Complexity**: Some apps (like Immich) have extremely complex build pipelines that would take hours to compile on home hardware.
*   **Security by Design**: These specific upstreams already provide excellent, minimal images that meet our standards without further surgical modification.

---

#### 🛡️ Global Hardening Logic
The following modifications are applied automatically to **every** service built from source:
*   **Base Image Migration**: Surgically replaces `FROM alpine`, `FROM debian`, and `FROM ubuntu` with `dhi.io/alpine-base:3.22-dev`.
*   **Runtime Hardening**: 
    *   **Node.js**: Replaced with `dhi.io/node:20-alpine3.22-dev`
    *   **Bun**: Replaced with `dhi.io/bun:1-alpine3.22-dev`
    *   **Python**: Replaced with `dhi.io/python:3.11-alpine3.22-dev`
    *   **Go**: Replaced with `dhi.io/golang:1-alpine3.22-dev`
    *   **Rust**: Replaced with `dhi.io/rust:1-alpine3.22-dev`
*   **Package Manager Translation**: 
    *   Converts `apt-get install` to `apk add --no-cache`.
    *   Removes `apt-get update`, `apt-get clean`, and `/var/lib/apt/lists` cleanup blocks.
    *   Translates common package names (e.g., `libssl-dev` → `openssl-dev`).
*   **Telemetry Removal**: All patched runtimes are configured to disable upstream telemetry and phone-home signals by default.

For service-specific modifications (such as memory limits and GPU fallbacks), see the [Surgical Patch Registry](#surgical-patch-registry) below.

### Automatic Version Pinning & A/B System

The stack implements a robust A/B deployment strategy for safe, zero-downtime updates with automatic rollback capability.

#### How A/B Slots Work

| Concept | Description |
| :--- | :--- |
| **Slot A / Slot B** | Two independent deployment environments. Only one is active at a time. |
| **Active Slot** | The slot currently serving traffic (stored in `.active_slot` file). |
| **Standby Slot** | The inactive slot used for building and testing new versions. |
| **Swap Operation** | Atomically switches traffic from one slot to the other. |

#### Update Workflow

1. **Build Phase**: New versions are built in the standby slot while the active slot continues serving traffic.
2. **Verification**: Health checks validate the new build before any traffic swap.
3. **Swap**: The `-S` flag triggers the swap, making the standby slot active.
4. **Rollback**: If issues occur, simply swap back to the previous slot (instant recovery).

#### Version Strategies

| Strategy | Tag | Behavior | Use Case |
| :--- | :--- | :--- | :--- |
| **Stable** (Default) | `latest` | Automatically identifies the latest semantic version tag (e.g., `v1.2.3`) from upstream repositories. | Production use—predictable, tested releases. |
| **Latest** | `latest` | Tracks the default upstream branch (`main` or `master`) for bleeding-edge updates. | Early adopters wanting immediate fixes. |

#### Benefits

- **Zero Downtime**: Users experience no interruption during updates.
- **Instant Rollback**: If a new version has issues, swap back in seconds.
- **Safe Testing**: Verify new builds in isolation before exposing them to traffic.
- **Parallel Builds**: Use `-j` flag to build all services simultaneously for faster deployments.

<a id="surgical-patch-registry"></a>
<details>
<summary>🛠️ <strong>Surgical Patch Registry</strong> (Click to expand)</summary>

The following modifications are applied to upstream Dockerfiles and source code to ensure security, compatibility, and optimal performance.

#### Service-Specific Patches

| Service | Upstream Source | Modifications Applied | Implementation |
| :--- | :--- | :--- | :--- |
| **BreezeWiki** | [PussTheCat-org/docker-breezewiki](https://github.com/PussTheCat-org/docker-breezewiki-quay) | **Native Conversion**: Migrated from Debian to Alpine. Replaced `apt` logic with `apk`. Implemented localized Racket package management. | [lib/sources.sh#L104-L117](lib/sources.sh#L104-L117) |
| **Invidious Companion** | [iv-org/invidious-companion](https://github.com/iv-org/invidious-companion) | **Build Reliability**: Resolved Rust compilation stack overflow by injecting `ENV RUST_MIN_STACK=16777216`. Forced lockfile regeneration to prevent stale dependency issues. | [lib/sources.sh#L141-L149](lib/sources.sh#L141-L149) |
| **VERTd** | [VERT-sh/vertd](https://github.com/VERT-sh/vertd) | **Hybrid Optimization**: Implemented NVIDIA GPU detection logic. Added Alpine fallback for non-GPU environments. Fixed static compilation with `openssl-libs-static`. | [lib/sources.sh#L120-L138](lib/sources.sh#L120-L138) |
| **Hub API** | [Local Source](/hub-api) | **Custom Build**: Purpose-built orchestration API using DHI Python base. Full telemetry isolation. | [lib/sources.sh#L167-L187](lib/sources.sh#L167-L187) |

#### Standard Hardening (Generic Patch Loop)

The following services receive standard DHI hardening via the [`patch_bare` function](lib/sources.sh#L62-L100), applied through the [generic patch loop](lib/sources.sh#L153-L162):

| Service | Upstream Source | Hardening Applied |
| :--- | :--- | :--- |
| **VERT** | [VERT-sh/vert](https://github.com/VERT-sh/VERT) | DHI Alpine base, Bun/Node runtime hardening, telemetry disabled |
| **Invidious** | [iv-org/invidious](https://github.com/iv-org/invidious) | DHI Alpine base, standard package translation |
| **Redlib** | [redlib-org/redlib](https://github.com/redlib-org/redlib) | DHI Alpine base, runs as `nobody` user, read-only filesystem |
| **Wikiless** | [Metastem/Wikiless](https://github.com/Metastem/Wikiless) | DHI Alpine base, Node.js runtime hardening |
| **Rimgo** | [rimgo/rimgo](https://codeberg.org/rimgo/rimgo) | DHI Alpine base, Go runtime hardening |
| **AnonOverflow** | [httpjamesm/AnonymousOverflow](https://github.com/httpjamesm/AnonymousOverflow) | DHI Alpine base, standard package translation |
| **Scribe** | [edwardloveall/scribe](https://git.sr.ht/~edwardloveall/scribe) | DHI Alpine base, Crystal runtime compatibility fixes |
| **Memos** | [usememos/memos](https://github.com/usememos/memos) | DHI Alpine base, Go and Node.js runtime hardening |
| **Gluetun** | [qdm12/gluetun](https://github.com/qdm12/gluetun) | DHI Alpine base, standard package translation |
| **AdGuard Home** | [AdguardTeam/AdGuardHome](https://github.com/AdguardTeam/AdGuardHome) | DHI Alpine base, Go runtime hardening |
| **Unbound** | [klutchell/unbound-docker](https://github.com/klutchell/unbound-docker) | DHI Alpine base, recursive resolver hardening |
| **WG-Easy** | [wg-easy/wg-easy](https://github.com/wg-easy/wg-easy) | DHI Alpine base, Node.js runtime hardening |
| **Odido Booster** | [Lyceris-chan/odido-bundle-booster](https://github.com/Lyceris-chan/odido-bundle-booster) | DHI Alpine base, Python runtime hardening |

#### Global Patches (Applied to All Built Services)

These modifications are defined in the [`patch_bare` function](lib/sources.sh#L62-L100) and applied to every service built from source:

| Patch Category | Description | Benefit |
| :--- | :--- | :--- |
| **Base Image Migration** | Replaces `FROM alpine`, `FROM debian`, and `FROM ubuntu` with `dhi.io/alpine-base:3.22-dev`. | Minimal attack surface, consistent security baseline. |
| **Runtime Hardening** | Replaces Node.js, Go, Python, Rust, and Bun images with DHI hardened equivalents (e.g., `dhi.io/node:20-alpine3.22-dev`). | Telemetry disabled, security patches applied, optimized for containers. |
| **Package Manager Translation** | Converts `apt-get install` to `apk add --no-cache`. Removes Debian-specific cleanup commands. | Cross-distribution compatibility, smaller image sizes. |
| **Package Name Translation** | Translates common package names (e.g., `libssl-dev` → `openssl-dev`). | Seamless Alpine compatibility. |
| **Telemetry Removal** | All patched runtimes configured to disable upstream telemetry and analytics by default. | Privacy by design—no "phone home" signals. |

</details>

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

### Verified Environment (High Performance)
*   **CPU**: Intel® Core™ i3-10105T (4 Cores / 8 Threads)
    *   Base: 2.90 GHz, Turbo: 3.00 GHz
*   **RAM**: 32 GB DDR4 @ 3200 MHz
*   **GPU**: Intel® UHD Graphics 630 (CometLake-S GT2)
    *   *Note: Fully compatible with Intel Quick Sync (QSV) for hardware-accelerated media tasks.*
*   **OS**: ZimaOS, Ubuntu 22.04 LTS, or Debian 12+

### Minimum Requirements
*   **CPU**: 2 Cores (64-bit)
*   **RAM**: 4 GB (8 GB+ Recommended for Immich/VERT usage)
*   **Storage**: 32 GB SSD (64 GB+ Recommended for media storage)

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

**Backup commands:**

> 💡 **Note**: Replace `/data/AppData/privacy-hub` with your actual installation path. The default path is shown below, but yours may differ based on your system configuration.

```bash
# Full backup of all Privacy Hub data
# Adjust the path to match your installation (check your BASE_DIR)
tar -czf privacy-hub-backup-$(date +%Y%m%d).tar.gz /data/AppData/privacy-hub

# Backup only secrets and configs (minimal)
cp /data/AppData/privacy-hub/.secrets ~/privacy-hub-secrets-backup.txt
cp -r /data/AppData/privacy-hub/config ~/privacy-hub-config-backup/

# Backup specific service data
tar -czf memos-backup.tar.gz /data/AppData/privacy-hub/memos
tar -czf immich-backup.tar.gz /data/AppData/privacy-hub/immich
```

*   **Update**: Click "Check Updates" in the dashboard or run `./zima.sh` again.
*   **Backup**:
    ```bash
    # Manual backup of critical data (Secrets, Configs, Databases)
    # Adjust path to match your installation
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
<summary><strong>🌐 Connection Exposure Map & Privacy Policies</strong> (Click to expand)</summary>

### Connection Exposure Map

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
| **deSEC.io** | SSL DNS Challenges | **🏠 Home IP** (Direct) |
| **Odido API** | Mobile Data fetching | **🏠 Home IP** (Direct) |
| **SearXNG / Immich** | Search & Media sync | **🔒 VPN IP** (Gluetun) |
| **Cobalt** | Media downloads | **🏠 Home IP** (Direct) |

### Detailed Privacy Policies

- **Public IP Detection & Health**:
  - [ipify.org](https://www.ipify.org/) (Used to display VPN status; exposes **🔒 VPN IP**)
  - [ip-api.com](https://ip-api.com/docs/legal) (Used for geolocation health; exposes **🔒 VPN IP**)
  - [connectivity-check.ubuntu.com](https://ubuntu.com/legal/data-privacy) (Used for VPN tunnel verification; exposes **🔒 VPN IP**)
- **Infrastructure & Assets**:
  - [deSEC.io](https://desec.io/privacy-policy) (SSL challenges via **🏠 Home IP**)
  - [fontlay.com](https://github.com/miroocloud/fontlay) (Fetched via **🔒 VPN IP**)
  - [cdn.jsdelivr.net](https://www.jsdelivr.com/terms/privacy-policy-jsdelivr-net) (Fetched via **🔒 VPN IP**)
- **Registries & Source Code**:
  - [Docker Hub / dhi.io](https://www.docker.com/legal/docker-privacy-policy/) (Image pulls via **🏠 Home IP**)
  - [GitHub / GHCR](https://docs.github.com/en/site-policy/privacy-policies/github-privacy-statement) (Source cloning via **🏠 Home IP**)
  - [Codeberg](https://codeberg.org/privacy) (Source cloning via **🏠 Home IP**)
  - [Quay.io](https://quay.io/privacy) (Image pulls via **🏠 Home IP**)
  - [SourceHut](https://man.sr.ht/privacy.md) (Source cloning via **🏠 Home IP**)
  - [Gitdab](https://gitdab.com/) (Source cloning via **🏠 Home IP**)
- **Data Providers**:
  - [DNS Blocklists (GitHub)](https://docs.github.com/en/site-policy/privacy-policies/github-privacy-statement) (Fetched via **🔒 VPN IP**)
  - [Odido API](https://www.odido.nl/privacy) (Automated data via **🏠 Home IP**)
  - [Immich Privacy Policy](https://docs.immich.app/privacy-policy)

</details>

---

## 🚨 Disclaimer

This software is provided "as is". While designed for security, the user is responsible for ensuring their specific network configuration is safe. **Do not use GitHub Codespaces for production deployment.**

---

*Built with ❤️ for digital sovereignty.*
