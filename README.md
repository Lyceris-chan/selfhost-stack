# 🛡️ ZimaOS Privacy Hub: Private Network Infrastructure

Digital privacy begins with hardware and code ownership. This project provides a production-grade security gateway that centralizes DNS resolution and routes frontend traffic through a hardened [**VPN Proxy**](#gluetun). This allows you to utilize services like YouTube and Reddit via private interfaces without exposing your home IP address to third-party providers.

## <a id="contents"></a>📋 Table of Contents
- [Project Overview](#overview)
- [Quick Start](#quick-start)
- [Required Credentials & Configuration](#credentials)
- [Independent DNS & RFC Compliance](#encrypted-dns)
- [VPN-Routed Frontends (Gluetun)](#gluetun)
- [Management Dashboard](#dashboard)
- [Network Configuration](#network-config)
- [Advanced Setup: OpenWrt & Double NAT](#advanced-setup)
- [Security Model](#security)
- [Service Catalog & Ports](#catalog)
- [System Resilience](#resilience)
- [Data Ownership](#ownership)

## <a id="overview"></a>🌟 Project Overview
Privacy Hub centralizes network traffic through a secure WireGuard tunnel and filters DNS queries at the source. By utilizing [**Gluetun**](#gluetun) as an internal VPN proxy, the stack anonymizes outgoing requests from privacy frontends (Invidious, Redlib, etc.). This allows you to host your own private instances—removing the need to trust third-party hosts—while ensuring your home IP remains hidden from end-service providers.

## <a id="quick-start"></a>🚀 Quick Start

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

## <a id="encrypted-dns"></a>⚡ Independent DNS & RFC Compliance

We eliminate middlemen (Google, Cloudflare) by communicating directly with Root DNS servers using **Unbound** with **QNAME Minimization** ([RFC 7816](https://datatracker.ietf.org/doc/html/rfc7816)) and **DNSSEC** ([RFC 4033](https://datatracker.ietf.org/doc/html/rfc4033)) verification.

<details>
<summary>🤓 Technical: How Independent DNS and QNAME Minimization work</summary>

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
The stack utilizes a high-performance filtering engine within AdGuard Home. By default, the **Lyceris-chan Blocklist** is configured to neutralize advertisements, telemetry, and malicious domains before they reach your devices.

- **Generation Process**: The list is automatically generated by the [Lyceris-chan DNS Blocklist project](https://github.com/Lyceris-chan/dns-blocklist-generator). It utilizes the industry-standard **Hagezi Multi Pro ++** as its primary foundation, merging it with several additional specialized sources. The generation pipeline executes a deduplication pass and optimizes the final dataset to ensure maximum coverage with minimal resource overhead.
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

## <a id="network-config"></a>🌐 Network Configuration

### Standard Setup
**Forward port 51820/UDP** to your host's local IP. This is the only exposed port and is cryptographically silent.

### Local LAN Mode
AdGuard Home utilizes **DNS Rewrites** to direct internal traffic to your local IP, ensuring optimal performance and local SSL access.

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
- **Hardened Infrastructure**: Generic base images (Nginx, databases, runtimes) utilize **DHI hardened versions** which reduce the attack surface by over 70% according to [CIS Benchmarks](https://www.cisecurity.org/benchmark/docker).
- **Official Specialized Apps**: High-level applications (Gluetun, AdGuard, etc.) utilize their official registry sources to ensure maximum compatibility and up-to-date functionality.
- **Zero Public Access**: Internal APIs and management interfaces are only accessible via the encrypted VPN tunnel or local network.

## <a id="catalog"></a>📦 Service Catalog & Access

| Service | Category | Connectivity |
| :--- | :--- | :--- |
| **Management Dashboard** | Infrastructure | Port 8081 |
| **AdGuard Home** | DNS/Filtering | Port 8083 |
| **WireGuard (WG-Easy)** | Remote Access | **Gateway** (Port 51821) |
| **Portainer** | Management | Port 9000 |
| **Invidious** | YouTube | **🔒 VPN Routed** |
| **Redlib** | Reddit | **🔒 VPN Routed** |
| **Wikiless** | Wikipedia | **🔒 VPN Routed** |
| **LibremDB** | Movies/TV | **🔒 VPN Routed** |
| **Rimgo** | Imgur | **🔒 VPN Routed** |
| **Scribe** | Medium | **🔒 VPN Routed** |
| **BreezeWiki** | Fandom | **🔒 VPN Routed** |
| **AnonOverflow** | Stack Overflow | **🔒 VPN Routed** |
| **VERT** | File Conversion | Port 5555 |
| **Odido Booster** | Utility | Port 8085 |

*Note: **WireGuard (WG-Easy)** is the required gateway for maintaining your privacy boundary when away from home.*

### Instance Reference & Functionality

#### Infrastructure & Core
- **Management Dashboard**: The central control plane for the stack. Built with Material Design 3, it provides live telemetry, VPN profile management, and service status monitoring with zero external dependencies.
- **AdGuard Home**: A network-wide advertisement and tracker filtration engine. It intercepts DNS requests to neutralize telemetry and malicious domains at the source.
- **WireGuard (WG-Easy)**: A high-performance VPN server that provides secure remote access to your home network. It is the mandatory gateway for utilizing your privacy boundary on external or untrusted networks.
- **Portainer**: A comprehensive management interface for the Docker environment, facilitating granular control over container orchestration and infrastructure lifecycle.
- **Unbound**: A validating, recursive, caching DNS resolver. It communicates directly with Root DNS servers, eliminating the need for third-party upstream providers.
- **Gluetun**: A specialized VPN client that acts as an internal proxy. It isolates privacy frontends and routes their outgoing traffic through an external VPN provider to ensure your home IP remains anonymous.

#### Privacy Frontends (VPN-Routed)
- **Invidious**: Access YouTube content privately. It strips all tracking and advertisements, routes traffic through the VPN to hide your IP, and provides a lightweight interface without proprietary telemetry.
- **Redlib**: A hardened Reddit frontend. It eliminates tracking pixels, intrusive analytics, and advertisements, ensuring your browsing habits remain confidential and your home IP is never disclosed.
- **Wikiless**: Wikipedia without the cookies or telemetry. All requests are routed through the VPN to maintain total anonymity.
- **LibremDB**: Private metadata engine for media collections. Retrieves information without allowing data brokers to profile your interests or track your IP.
- **Rimgo**: An anonymous Imgur viewer that removes telemetry and tracking scripts while hiding your location behind the VPN proxy.
- **Scribe**: Read Medium articles without the paywalls, tracking scripts, or IP logging common on the standard platform.
- **BreezeWiki**: Clean Fandom interface. Neutralizes aggressive advertising networks and prevents tracking scripts from monitoring your visits.
- **AnonOverflow**: Private StackOverflow interface. Facilitates information retrieval for developers without facilitating cross-site corporate surveillance or IP tracking.

#### Utilities & Automation
- **VERT**: A local file conversion service that maintains data sovereignty by processing sensitive documents on your own hardware using GPU acceleration.
- **Odido Booster**: An automated data management utility for Odido users that monitors usage and handles bundle procurement via API.
- **Watchtower**: A background utility that monitors for container image updates and automates the update process to ensure security patches are applied.

### Background Management Scripts
- **cert-monitor.sh**: Manages the automated SSL certificate lifecycle. It handles Let's Encrypt issuance via DNS-01 challenges and implements rate-limit recovery by deploying temporary self-signed certificates.
- **wg-ip-monitor.sh**: A proactive network monitor that detects changes in your public IP address. It automatically synchronizes DNS records and restarts the WireGuard endpoint to maintain persistent connectivity.
- **wg-control.sh**: An administrative control script that facilitates profile switching, status reporting, and service dependency management for the VPN tunnel.

## <a id="resilience"></a>🏗️ System Resilience

- **Automated SSL**: `cert-monitor.sh` manages Let's Encrypt renewals and rate-limit recovery.
- **Dynamic IP**: `wg-ip-monitor.sh` automatically updates DNS records and VPN endpoints on public IP changes.

## <a id="ownership"></a>🤝 Data Ownership

This infrastructure is designed for those who refuse to be a product. By self-hosting this stack, you establish absolute ownership over your data, metadata, and digital footprint. You are no longer a tenant on corporate infrastructure; you are the owner of your network.
