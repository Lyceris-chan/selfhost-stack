# 🛡️ ZimaOS Privacy Hub: Private Network Infrastructure

Digital privacy begins with hardware and code ownership. This project provides a production-grade security gateway that centralizes DNS resolution and routes frontend traffic through a hardened [**VPN Proxy**](#gluetun). This allows you to utilize services like YouTube and Reddit via private interfaces without exposing your home IP address to third-party providers.

## <a id="contents"></a>📋 Table of Contents
- [Project Overview](#overview)
- [Beginner-Friendly Overview](#beginner-friendly-overview-how-it-works)
- [What This Stack Provides](#what-this-stack-provides)
- [Privacy Benefits](#privacy-benefits)
- [Telemetry & Data Collection](#telemetry)
- [Required Credentials & Configuration](#credentials)
- [Quick Start](#quick-start)
- [Independent DNS & RFC Compliance](#encrypted-dns)
- [VPN-Routed Frontends (Gluetun)](#gluetun)
- [Management Dashboard](#dashboard)
- [Network Configuration](#network-config)
- [WireGuard Split Tunneling](#split-tunnel)
- [Advanced Setup: OpenWrt & Double NAT](#advanced-setup)
- [Security Model](#security)
- [Services & Ports](#catalog)
- [System Resilience](#resilience)
- [Data Ownership](#ownership)

## <a id="overview"></a>🌟 Project Overview
Privacy Hub centralizes network traffic through a secure WireGuard tunnel and filters DNS queries at the source. By utilizing [**Gluetun**](#gluetun) as an internal VPN proxy, the stack anonymizes outgoing requests from privacy frontends (Invidious, Redlib, etc.). This allows you to host your own private instances—removing the need to trust third-party hosts—while ensuring your home IP remains hidden from end-service providers.

## Beginner-Friendly Overview (How It Works)
1. **Devices → DNS**: All your devices send DNS lookups to [AdGuard Home](https://adguard.com/en/adguard-home/overview.html) + [Unbound](https://nlnetlabs.nl/projects/unbound/about/). Unbound resolves directly from root DNS servers with DNSSEC validation, and AdGuard blocks trackers and malware at the DNS layer.
2. **Apps → VPN Proxy**: Privacy frontends (Invidious, Redlib, etc.) route outbound traffic through [Gluetun](https://github.com/qdm12/gluetun), so external sites see the VPN exit IP instead of your home IP.
3. **You → Home**: When away from home, [WireGuard (WG-Easy)](https://github.com/wg-easy/wg-easy) provides secure access back into your network so you can use services privately.
4. **Dashboard → Local**: The management UI loads local assets only and includes a redaction mode so sensitive info can be hidden during demos or screenshots.

## What This Stack Provides
- **Recursive, encrypted DNS**: [Unbound](https://nlnetlabs.nl/projects/unbound/about/) with DNSSEC and QNAME minimization, plus RFC-compliant DOH/DOT/DOQ endpoints.
- **Network-wide filtering**: [AdGuard Home](https://adguard.com/en/adguard-home/overview.html) blocks ads, trackers, and malicious domains before they reach your devices.
- **Secure remote access**: [WireGuard (WG-Easy)](https://github.com/wg-easy/wg-easy) provides encrypted connectivity back to your home network.
- **VPN-isolated frontends**: [Gluetun](https://github.com/qdm12/gluetun) routes privacy frontends (YouTube, Reddit, Wikipedia, etc.) through a VPN to prevent upstream services from seeing your home IP. See [Services & Ports](#catalog).
- **Local-first management**: A Material Design 3 dashboard with zero external assets and a built-in redaction mode.

## Privacy Benefits
- **No third-party DNS dependency**: Queries resolve from root servers with DNSSEC validation instead of forwarding to large public resolvers.
- **Reduced metadata leakage**: Encrypted DNS over standard ports and optional ECH support limit passive monitoring.
- **Self-hosted trust boundary**: Frontends and logs live on your hardware, not a public instance you do not control.
- **Home IP shielding**: VPN-routed services prevent destination platforms from linking traffic to your residential address.
- **Privacy-First IP Detection**: Public IP detection (used for dynamic DNS and VPN synchronization) utilizes verified privacy-respecting services:
    - **ipify.org**: [Privacy Policy](https://www.ipify.org) (No visitor information is ever logged).
    - **ip-api.com**: [Privacy Policy](https://ip-api.com/docs/legal) (Explicitly does not log requests for free users).
- **Minimal exposure**: Management interfaces stay on the LAN or inside the WireGuard tunnel by default.

## <a id="telemetry"></a>🧾 Telemetry & Data Collection
This stack is configured to minimize telemetry and local logging by default. Verify or adjust as needed:

- **[AdGuard Home](https://adguard.com/en/adguard-home/overview.html)**: AdGuard Home states it does not collect usage statistics by default ([privacy policy](https://adguard.com/en/privacy/home.html)). We keep local query logs and statistics for 30 days in `/DATA/AppData/privacy-hub/config/adguard/AdGuardHome.yaml` (`querylog.enabled=true`, `statistics.enabled=true`, `interval=720h`). Adjust retention or disable in the AdGuard UI or config if you want less local logging.
- **[Portainer CE](https://www.portainer.io/)**: The deployment attempts to disable anonymous usage statistics via the Portainer API. Verify in **Settings → General → Allow the collection of anonymous statistics** ([docs](https://docs.portainer.io/admin/settings/general), [privacy policy](https://www.portainer.io/legal/privacy-policy)). The legacy `--no-analytics` flag is deprecated, so use the UI toggle.
- **Other services**: No extra telemetry is enabled by this stack. External calls occur only for core functionality (e.g., VPN provider endpoints or update checks).

## <a id="credentials"></a>🔑 Required Credentials & Configuration

Before deployment, ensure you have the following credentials ready. The script will prompt for these to establish secure communication and automated management.

### 1. Registry Authentication (Hardened Images)
- **Source**: [dhi.io](https://dhi.io) and [Docker Hub](https://hub.docker.com).
- **Required**: Username and a Personal Access Token (PAT).
- **Purpose**: Facilitates pulling hardened, minimal-vulnerability container images.

### 2. DNS & SSL Management (deSEC)
- **Source**: [deSEC.io](https://desec.io).
- **Required**: A registered domain (e.g., `yourname.dedyn.io`) and an **API Token**.
- **Purpose**: Automates Dynamic DNS updates and Let's Encrypt SSL certificate issuance via DNS-01 challenges.

### 3. WireGuard Configuration (VPN Provider)
To route frontend traffic through a VPN, you need a WireGuard configuration file. This stack is optimized for **ProtonVPN**, though other providers utilizing standard WireGuard `.conf` files should also function (untested).

- **Source**: [ProtonVPN Account Dashboard](https://account.protonvpn.com).
- **Steps**:
    1. Log in and navigate to **Downloads** in the left sidebar.
    2. Select **WireGuard configuration**.
    3. **Region Selection**: You may choose any available region. If you have a paid subscription, select a high-performance server; if utilizing the free tier, select a free region.
    4. **Name & Options**: Prior to creation, provide a recognizable **name** for the configuration.
    5. **Port Forwarding**: Ensure you **enable the Port Forwarding toggle** on the dashboard for this configuration before proceeding.
    6. Click **Create** and download the `.conf` file.
- **Usage**: Copy the text inside the `.conf` file and paste it when the `zima.sh` script prompts for the "WireGuard Configuration."

### 4. Optional Utility Tokens
- **GitHub Token**: Required for the **Scribe** Medium frontend to bypass gist rate limits. Generate a "Classic" token with only the `gist` scope at [GitHub Settings](https://github.com/settings/tokens).
- **Odido Token**: Required for the **Odido Booster** utility. Obtain via the [Odido Authenticator](https://github.com/GuusBackup/Odido.Authenticator) tool.

## <a id="quick-start"></a>🚀 Quick Start

Before you run:
- Review the [Required Credentials & Configuration](#credentials).

```bash
# 1. Clone the repository and enter the directory
# 2. Make the deployment script executable
chmod +x zima.sh

# 3. Execute the script
./zima.sh

# Options:
# -c : Environment reset (Nuke all data/configs)
# -p : Automated credential generation
```

## <a id="encrypted-dns"></a>⚡ Independent DNS & RFC Compliance

We eliminate middlemen (Google, Cloudflare) by communicating directly with Root DNS servers using **Unbound** with **QNAME Minimization** ([RFC 7816](https://datatracker.ietf.org/doc/html/rfc7816)) and **DNSSEC** ([RFC 4033](https://datatracker.ietf.org/doc/html/rfc4033)) verification.

<details>
<summary>Technical: How Independent DNS and QNAME Minimization work</summary>

- **Talking to the Source**: Instead of using an ISP's "censored phonebook," Unbound talks directly to the **Root DNS servers**. It then follows the chain to the TLD servers (like `.com`) and finally to the **Authoritative Server** for the domain.
- **QNAME Minimization**: Traditional resolvers tell every server in the chain the full domain you're visiting. Unbound only tells the `.com` server it's looking for something in `.com`, and the `example.com` server it's looking for `example.com`. Your intent remains private until the very last step.
- **DNSSEC Validation**: Every response is verified cryptographically. If an ISP tries to hijack your connection, the system detects the fake signature and blocks it.
</details>

### RFC-Standard Encrypted DNS (Port 853 / 443)
Standardized ports ensure seamless compatibility with native OS resolvers without custom configuration.

- **DNS-over-TLS (DOT) [[RFC 7858](https://datatracker.ietf.org/doc/html/rfc7858)]**: Uses Port **853/TCP**. Standard for Android "Private DNS" and system-level Linux resolvers.
- **DNS-over-QUIC (DOQ) [[RFC 9250](https://datatracker.ietf.org/doc/html/rfc9250)]**: Uses Port **853/UDP**. High-performance encrypted DNS designed for superior latency and stability.
- **DNS-over-HTTPS (DOH) [[RFC 8484](https://datatracker.ietf.org/doc/html/rfc8484)]**: Uses Port **443/TCP**. Standard for browsers; traffic is indistinguishable from normal HTTPS.

### Metadata Shielding (ECH)
We support **Encrypted Client Hello (ECH)** to protect the initial stage of your HTTPS connections.

<details>
<summary>🛡️ Technical: What is ECH and why do you need it?</summary>

In traditional HTTPS, the very first part of the connection contains the domain name you're visiting in plain text (the SNI). This means even though the *content* is encrypted, your ISP still knows which website you are visiting. **ECH** ([IETF Draft](https://datatracker.ietf.org/doc/html/draft-ietf-tls-esni)) encrypts that initial greeting, ensuring that metadata observers see only a connection to a general infrastructure provider.
</details>

### Default DNS Filtering
The stack utilizes a high-performance filtering engine within AdGuard Home, powered by **Lyceris-chan/dns-blocklist-generator**, which is configured to neutralize advertisements, telemetry, and malicious domains before they reach your devices.

- **Generation Process**: The list is automatically generated by the [sleepy list](https://github.com/Lyceris-chan/dns-blocklist-generator). It compiles a comprehensive DNS blocklist by merging multiple sources (including **Hagezi Multi Pro ++**) and removing duplicates to ensure maximum coverage with minimal resource overhead.
- **Customization**: Users are encouraged to review the default project for source transparency or to configure custom filtering rules and additional blocklists directly within the AdGuard Home management interface.

## <a id="gluetun"></a>🔒 VPN-Routed Frontends (Gluetun)

When you self-host private frontends without a VPN, your home IP address is directly exposed to the destination servers (e.g., Google or Reddit). While public instances exist to mitigate this, they require you to move your trust to a third-party instance owner who may log your data.

Privacy Hub eliminates this trade-off by isolating your local services within a hardened **Gluetun VPN container**, allowing you to be your own proxy:
- **Self-Managed Trust**: You own the instance and the logs. You no longer have to trust a third-party host with your browsing metadata.
- **IP & Detail Protection**: Although you are hosting the service, your home IP is never visible to the end provider. All outgoing requests are routed through an anonymous VPN endpoint.
- **Zero Tracking & Analytics**: The combination of private frontends and a VPN proxy ensures you bypass intrusive corporate logging, behavioral analytics, and telemetry engines.
- **Kill-Switch Enforcement**: Gluetun strictly enforces a network kill-switch; if the VPN connection drops, all outgoing traffic is immediately terminated to prevent any accidental home IP exposure.

## <a id="dashboard"></a>🖥️ Management Dashboard: Zero-Leak UI

Built on Material Design 3, the dashboard follows a strict zero-tracking philosophy:
- **Local Assets**: All fonts, icons, and libraries are hosted locally. 
- **Redaction Mode**: Built-in toggle to mask sensitive metrics (IPs, profiles) for safe display.
- **Native Integration**: One-click access from the ZimaOS/CasaOS interface via local Material Design icon.
- **Visibility**: Service health badges, certificate status, and a live deployment log help surface what’s wrong when something fails.

## <a id="network-config"></a>🌐 Network Configuration

### Standard Setup
**Forward port 51820/UDP** to your host's local IP. This is the only exposed port and is cryptographically silent.

### Local LAN Mode
AdGuard Home utilizes **DNS Rewrites** to direct internal traffic to your local IP, ensuring optimal performance and local SSL access.

## <a id="split-tunnel"></a>🧭 WireGuard Split Tunneling (Default)

WireGuard is configured for split tunneling so remote devices only route **private LAN ranges** through the VPN, while normal internet traffic stays direct. This keeps browsing fast and avoids unnecessary VPN routing.

- **Current default**: `WG_ALLOWED_IPS=10.0.0.0/8,172.16.0.0/12,192.168.0.0/16`
- **Full tunnel option**: change to `0.0.0.0/0, ::/0` if you want all traffic routed through your home VPN.
- **Where to adjust**: edit `zima.sh` before deployment and re-run the script so WG-Easy regenerates profiles with the new allowed IPs.

## <a id="advanced-setup"></a>📡 Advanced Setup: OpenWrt & Double NAT

<details>
<summary>💻 CLI: UCI Commands for OpenWrt Configuration</summary>

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

uci commit firewall
/etc/init.d/firewall restart
```
</details>

## <a id="security"></a>🛡️ Security Model

- **Stealth VPN**: The WireGuard port does not respond to unauthenticated packets, remaining invisible to port scans ([WireGuard Protocol](https://www.wireguard.com/protocol/)).
- **Hardened Infrastructure**: To minimize the attack surface, this stack enforces the use of **DHI hardened base images**. The `zima.sh` script automatically applies these security standards through direct service definitions and dynamic source-code patching:
    - **Infrastructure & Databases**:
        - **Nginx**: `dhi.io/nginx:1.28-alpine3.21` (Powers the Dashboard and VERT frontend).
        - **Redis**: `dhi.io/redis:7.2-debian13` (Hardened backend for Wikiless).
        - **PostgreSQL**: `dhi.io/postgres:14-alpine3.22` (Secures the Invidious database).
    - **Automated Source Patching**: During deployment, the script injects DHI runtimes into upstream Dockerfiles before building:
        - **Python**: `dhi.io/python:3.11-alpine3.22-dev` (Enforced for Hub-API and Odido Booster).
        - **Node.js/Bun**: Build pipelines for Wikiless, Scribe, and VERT are patched to use `dhi.io/node:20-alpine3.22-dev` and `dhi.io/bun:1-alpine3.22-dev`.
        - **Alpine Base**: All services utilizing Alpine are automatically repinned to `dhi.io/alpine-base:3.22-dev` to ensure a minimal, hardened OS layer.
- **Official Specialized Apps**: High-level applications (Gluetun, AdGuard, etc.) utilize their official registry sources to ensure maximum compatibility and up-to-date functionality.
- **Zero Public Access**: Internal APIs and management interfaces are only accessible via the encrypted VPN tunnel or local network.

## <a id="catalog"></a>📦 Services & Ports

All links below point to official project pages or maintainer repositories (no Google/Cloudflare sources).

| Service | Category | Connectivity |
| :--- | :--- | :--- |
| **[Management Dashboard](#dashboard)** | Infrastructure | Port 8081 |
| **[AdGuard Home](https://github.com/AdguardTeam/AdGuardHome)** | DNS/Filtering | Port 8083 |
| **[WireGuard (WG-Easy)](https://github.com/wg-easy/wg-easy)** | Remote Access | **Gateway** (Port 51821) |
| **[Portainer CE](https://github.com/portainer/portainer)** | Management | Port 9000 |
| **[Invidious](https://github.com/iv-org/invidious)** | YouTube | **🔒 VPN Routed** |
| **[Redlib](https://github.com/redlib-org/redlib)** | Reddit | **🔒 VPN Routed** |
| **[Wikiless](https://github.com/Metastem/Wikiless)** | Wikipedia | **🔒 VPN Routed** |
| **[Memos](https://github.com/usememos/memos)** | Notes | Port 5230 |
| **[Rimgo](https://codeberg.org/rimgo/rimgo)** | Imgur | **🔒 VPN Routed** |
| **[Scribe](https://git.sr.ht/~edwardloveall/scribe)** | Medium | **🔒 VPN Routed** |
| **[BreezeWiki](https://gitdab.com/cadence/breezewiki)** | Fandom | **🔒 VPN Routed** |
| **[AnonOverflow](https://github.com/httpjamesm/anonymousoverflow)** | Stack Overflow | **🔒 VPN Routed** |
| **[VERT](https://github.com/vert-sh/vert)** | File Conversion | Port 5555 |
| **[Odido Booster](https://github.com/Lyceris-chan/odido-bundle-booster)** | Utility | Port 8085 |

*Note: **WireGuard (WG-Easy)** is the required gateway for maintaining your privacy boundary when away from home.*

### Service Details

#### Infrastructure & Core
- **[Management Dashboard](#dashboard)**: The central control plane for the stack. Built with Material Design 3, it provides live telemetry, VPN profile management, and service status monitoring with zero external dependencies.
- **[AdGuard Home](https://github.com/AdguardTeam/AdGuardHome)**: A network-wide advertisement and tracker filtration engine. It intercepts DNS requests to neutralize telemetry and malicious domains at the source.
- **[WireGuard (WG-Easy)](https://github.com/wg-easy/wg-easy)**: A high-performance VPN server that provides secure remote access to your home network. It is the mandatory gateway for utilizing your privacy boundary on external or untrusted networks.
- **[Portainer CE](https://github.com/portainer/portainer)**: A comprehensive management interface for the Docker environment, facilitating granular control over container orchestration and infrastructure lifecycle.
- **[Unbound](https://nlnetlabs.nl/projects/unbound/about/)**: A validating, recursive, caching DNS resolver. It communicates directly with Root DNS servers, eliminating the need for third-party upstream providers.
- **[Gluetun](https://github.com/qdm12/gluetun)**: A specialized VPN client that acts as an internal proxy. It isolates privacy frontends and routes their outgoing traffic through an external VPN provider to ensure your home IP remains anonymous.

#### Privacy Frontends (VPN-Routed)
- **[Invidious](https://github.com/iv-org/invidious)**: Access YouTube content privately (Port 3000). It strips all tracking and advertisements, routes traffic through the VPN to hide your IP, and provides a lightweight interface without proprietary telemetry.
- **[Redlib](https://github.com/redlib-org/redlib)**: A hardened Reddit frontend (Port 8080). It eliminates tracking pixels, intrusive analytics, and advertisements, ensuring your browsing habits remain confidential and your home IP is never disclosed.
- **[Wikiless](https://github.com/Metastem/Wikiless)**: Wikipedia without the cookies or telemetry (Port 8180). All requests are routed through the VPN to maintain total anonymity.
- **[Rimgo](https://codeberg.org/rimgo/rimgo)**: An anonymous Imgur viewer (Port 3002) that removes telemetry and tracking scripts while hiding your location behind the VPN proxy.
- **[Scribe](https://git.sr.ht/~edwardloveall/scribe)**: Read Medium articles without the paywalls, tracking scripts, or IP logging common on the standard platform (Port 8280).
- **[BreezeWiki](https://gitdab.com/cadence/breezewiki)**: Clean Fandom interface (Port 8380). Neutralizes aggressive advertising networks and prevents tracking scripts from monitoring your visits.
- **[AnonOverflow](https://github.com/httpjamesm/anonymousoverflow)**: Private StackOverflow interface (Port 8480). Facilitates information retrieval for developers without facilitating cross-site corporate surveillance or IP tracking.

#### Utilities & Automation
- **[VERT](https://github.com/vert-sh/vert)**: A local file conversion service that maintains data sovereignty by processing sensitive documents on your own hardware using GPU acceleration.
- **[Memos](https://github.com/usememos/memos)**: A private notes and knowledge base for capturing ideas, snippets, and personal documentation locally.
- **[Odido Booster](https://github.com/Lyceris-chan/odido-bundle-booster)**: An automated data management utility for Odido users that monitors usage and handles bundle procurement via API.
- **[Watchtower](https://github.com/containrrr/watchtower)**: A background utility that monitors for container image updates and automates the update process to ensure security patches are applied.

### Background Management Scripts
- **cert-monitor.sh**: Manages the automated SSL certificate lifecycle. It handles Let's Encrypt issuance via DNS-01 challenges and implements rate-limit recovery by deploying temporary self-signed certificates.
- **wg-ip-monitor.sh**: A proactive network monitor that detects changes in your public IP address. It automatically synchronizes DNS records and restarts the WireGuard endpoint to maintain persistent connectivity.
- **wg-control.sh**: An administrative control script that facilitates profile switching, status reporting, and service dependency management for the VPN tunnel.

## <a id="resilience"></a>🏗️ System Resilience

- **Automated SSL**: `cert-monitor.sh` manages Let's Encrypt renewals, logs failures, and retries after rate limits.
- **Dynamic IP**: `wg-ip-monitor.sh` detects public IP changes, updates deSEC DNS records, and restarts WireGuard with the new endpoint.
- **Auto-updates**: Watchtower checks for container image updates and applies them on a nightly schedule.
- **Self-healing**: The stack retries background tasks and exposes status in the dashboard so most issues resolve without manual intervention.

## <a id="ownership"></a>🤝 Data Ownership

This infrastructure is designed for those who refuse to be a product. By self-hosting this stack, you establish absolute ownership over your data, metadata, and digital footprint. You are no longer a tenant on corporate infrastructure; you are the owner of your network.
