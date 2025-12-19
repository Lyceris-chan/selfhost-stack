# 🛡️ ZimaOS Privacy Hub

A self-hosted privacy stack for people who want to own their data instead of renting a false sense of security.

## 📋 Table of Contents
- [Project Overview](#project-overview)
- [Quick Start](#quick-start)
- [Privacy & Ownership](#privacy--ownership)
- [Technical Architecture](#technical-architecture)
- [Network Configuration](#network-configuration)
- [Advanced Setup: OpenWrt & Double NAT](#advanced-setup-openwrt--double-nat)
- [Remote Access: Taking Your Network With You](#remote-access-taking-your-network-with-you)
- [Security Audit & Privacy Standards](#security-audit--privacy-standards)
- [Service Catalog](#service-catalog)
- [Service Access & Port Reference](#service-access--port-reference)
- [System Resilience](#system-resilience)
- [Community & Contributions](#community--contributions)

## 🌟 Project Overview
Privacy Hub is a security gateway for ZimaOS. It centralizes network traffic through a secure WireGuard tunnel, filters DNS at the source using recursive resolution, and routes application frontends through a dedicated VPN gateway (Gluetun). It's designed to stop your data from being a product sold to the highest bidder.

## 🚀 Quick Start

```bash
# 1. Clone the repo and enter the directory
# 2. Make the script executable
chmod +x zima.sh

# 3. Run it and take back your network
./zima.sh

# Options:
# -c : Nuclear cleanup (Wipes everything to start over)
# -p : Auto-generate passwords
```

## 🛡️ Privacy & Ownership

If you don't own the hardware and the code running your network, you don't own your privacy. You're just renting a temporary privilege from a company that will sell you out the second a court order or a profitable data-sharing deal comes along.

<details>
<summary>🔍 Deep Dive: The "Third Party" Trust Gap (NextDNS, Google, Cloudflare)</summary>

For many, **NextDNS** is the gold standard. I’ve had a great experience with them - it’s convenient, reliable, and has a polished dashboard. But no matter how "trustable" a provider is, you are still handing your entire digital footprint to a third party. If they get a subpoena, or they get bought, or they just change their minds, your data is gone. This stack is for those who want to stop trusting and start owning.

- **The Google Profile**: Google's DNS (8.8.8.8) turns you into a data source. They build profiles on your health, finances, and interests based on every domain you resolve, then sell that access to target you through their massive advertising machine.
- **The Cloudflare Illusion**: Recent shifts in 2025 have shown that even "neutral" providers like Cloudflare aren't neutral when a government knocks. In Germany, Cloudflare processes global blocks based on local self-regulatory bodies (FSM-Hotline). Their CDN is now ruled a "host," allowing governments to force censorship. Do you really want your "neutral pipe" to be a global censorship tool?
- **ISP Predation**: Your ISP sees everything. They log, monetize, and sell your history to brokers. They also use DNS hijacking to redirect you to government warning pages. They are the gatekeepers, and they don't have your interests in mind.
</details>

### Independent DNS Resolution (QNAME Minimization)
This stack cuts out the middleman by using **Unbound** as a recursive resolver with **QNAME Minimization (RFC 7816)** enabled.

<details>
<summary>🤓 Technical: How Independent DNS and QNAME Minimization work</summary>

- **Talking to the Source**: Instead of using the ISP's "censored phonebook," Unbound talks directly to the **Root DNS servers**. It then follows the chain to the TLD servers (like `.com`) and finally to the **Authoritative Server** - the last server in the chain that actually owns the record.
- **Why the Authoritative Server?**: It's the only one that needs to know exactly where you're going. By reaching it directly, you ensure no middleman (like Google) is logging your request.
- **QNAME Minimization**: Most resolvers tell every server in the chain the full domain you're visiting. Unbound only tells the `.com` server it's looking for something in `.com`, and the `stuff.com` server it's looking for `stuff.com`. Your intent remains private until the very last step.
- **DNSSEC Validation**: Every response is verified cryptographically. If an ISP tries to hijack your connection, the system detects the fake signature and blocks it.
</details>

### Metadata Shielding (ECH)
We support **Encrypted Client Hello (ECH)**. 

<details>
<summary>🛡️ Technical: What is ECH and why do you need it?</summary>

In traditional HTTPS, the very first part of the connection (the "Client Hello") contains the domain name you're visiting in plain text (the SNI). This means even though the *content* of your visit is encrypted, your ISP still knows you're on `specific-website.com`.

**ECH** encrypts that initial greeting. It puts a bag over the head of your connection request, ensuring that metadata observers see only that you are connecting to a general infrastructure provider, but not which specific site or service you are using.
</details>

## 🏗️ Technical Architecture

### The DNS Chain
`Your Device` → `AdGuard Home (Filtering)` → `Unbound (Recursive + QNAME Minimization)` → `Root DNS Servers`

### The Privacy Path
`Dashboard (Zero-Leak UI)` → `Nginx Proxy` → `Gluetun (VPN Tunnel)` → `Privacy Frontend` → `External VPN Provider` → `Internet`

## 🌐 Network Configuration

### Standard Setup: ISP Router Only
If you just have the standard router your ISP gave you, you only need to do one thing:
1.  **Forward port 51820/UDP** to your ZimaOS machine's local IP.
This is the only open door. It is cryptographically silent and does not increase your attack surface (see the [Security Model](#security-audit--privacy-standards)).

### Local "Home" Mode: DNS Rewrites
When you're at home, you shouldn't have to bounce traffic off a satellite just to see your own dashboard. AdGuard Home uses **DNS Rewrites** to tell your devices the local LAN IP (`192.168.1.100`) instead of your public IP. You get SSL and local speeds without needing a VPN tunnel.

## 📡 Advanced Setup: OpenWrt & Double NAT

If you're running a real router like OpenWrt behind your ISP modem, you are in a **Double NAT** situation. This means your data has to pass through two layers of address translation. You need to fix the routing so your packets actually arrive.

### 1. OpenWrt: Static IP Assignment (DHCP Lease)
Assign a static lease so your Privacy Hub doesn't wander off to a new IP every time the power cycles.
1.  Navigate to **Network** → **DHCP and DNS** → **Static Leases**.
2.  Click **Add**. **Hostname**: `ZimaOS-Privacy-Hub`. **IPv4-Address**: `192.168.1.100`.
3.  **Save & Apply**.

<details>
<summary>💻 CLI: UCI Commands for Static Lease</summary>

```bash
# Add the static lease (Replace MAC and IP with your own hardware's values)
uci add dhcp host
uci set dhcp.@host[-1].name='ZimaOS-Privacy-Hub'
uci set dhcp.@host[-1].dns='1'
uci set dhcp.@host[-1].mac='00:11:22:33:44:55' # <--- REPLACE THIS WITH YOUR MAC
uci set dhcp.@host[-1].ip='192.168.1.100'      # <--- REPLACE THIS WITH YOUR DESIRED IP
uci commit dhcp
/etc/init.d/dnsmasq restart
```
</details>

### 2. OpenWrt: Port Forwarding & Firewall
OpenWrt is the gatekeeper. Point the traffic to your machine and then actually open the door.
1.  **Port Forwarding (DNAT)**: Points the internet request to your ZimaOS.
2.  **Traffic Rules**: Explicitly tells the firewall that this traffic is allowed.

<details>
<summary>💻 CLI: UCI Commands for Firewall (Port Forward + Traffic Rule)</summary>

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

### 3. ISP Modem: Primary Port Forward
You have to forward the entry point to your OpenWrt router first.
- **Forward**: `51820/UDP` → **OpenWrt WAN IP**.
- This completes the chain of custody for your data: `Internet` → `ISP Modem` → `OpenWrt` → `ZimaOS`.

## 🛡️ Security Audit & Privacy Standards

### DHI Hardened Images
Standard images are packed with unnecessary binaries and vulnerabilities. We use **DHI hardened images** (`dhi.io`) which reduce the attack surface by **over 70%** according to CIS Benchmarks. Less junk means fewer ways for someone to break into your house. (Source: [CIS Benchmarks](https://www.cisecurity.org/benchmark/docker))

### The "Silent" Security Model (DDoS & Scan Resistance)
Opening a port for WireGuard does **not** increase your attack surface to DDoS or unauthorized access. 
- **WireGuard is Silent**: Unlike OpenVPN, WireGuard does not respond to packets it doesn't recognize. If an attacker scans your IP, your port looks **closed**. It won't even send a "go away" packet. 
- **DDoS Mitigation**: Because it's silent to unauthenticated packets, WireGuard is inherently resistant to scanning. Since it doesn't keep state for unauthorized connections, attackers cannot exhaust your memory with "half-open" connection floods (like SYN floods). You're effectively invisible to internet noise.
- **Cryptographic Ownership**: You can't "guess" a password. You need a valid 256-bit cryptographic key. Without it, you don't exist to the server.
- **No Domain-to-Home Path**: Your domain is just a pointer. Since Nginx only listens internally, there is **no way** for someone to connect to your dashboard from the internet without being inside your encrypted tunnel first.

## 📡 Remote Access: Taking Your Network With You

Privacy Hub turns your ZimaOS into a portable security boundary. Using **WG-Easy**, you can route all your traffic back through your home from anywhere.

- **Bandwidth-Optimized Split Tunneling**: By default, only private traffic and DNS go through the tunnel. 
- **The HTTPS Myth**: VPN companies love to scare you, but [over 95% of web traffic is HTTPS encrypted](https://transparencyreport.google.com/https/overview). Your ISP can't see inside your packets; HTTPS already handles that. The **real leak is DNS**, which we solve by forcing "phonebook" requests through the tunnel while letting encrypted data go direct for speed.
- **Seamless Domain Access (dedyn.io)**: Your hostnames (see [Service Access](#service-access--port-reference)) resolve correctly over the VPN, allowing you to use SSL certificates globally.

## 📦 Service Catalog

### Core Infrastructure
- **WireGuard (WG-Easy)**: A VPN server that actually works. Secure remote access without the corporate "cloud" middleman.
- **AdGuard Home**: Network-wide security and ad-filtering. It stops the trackers before they even touch your device.
- **Unbound**: A validating, recursive, caching DNS resolver. You talk to the root servers directly. You don't ask for permission.
- **Gluetun**: VPN client that routes specific service traffic through an external provider you trust.
- **Nginx & Hub-API**: The dashboard and the brains of the operation. No external dependencies.

### Privacy Frontends (VPN-Routed)
- **Invidious**: YouTube without tracking, ads, or Google accounts.
- **Redlib**: Reddit without the bloat or trackers. 
- **Wikiless**: Wikipedia without tracking cookies.
- **LibremDB**: Private metadata engine for movies and TV.
- **Rimgo**: Anonymous Imgur viewer.
- **Scribe**: Clutter-free Medium reader.
- **BreezeWiki**: Tracker-free Fandom interface.
- **AnonOverflow**: Private Stack Overflow interface.

### Utility Services
- **VERT & VERTD**: Local-first file conversion with Intel GPU acceleration.
- **Odido Booster**: Automated data bundle management for Odido users.
- **Watchtower**: Automated container image updates and cleanup.

## 🔌 Service Access & Port Reference

| Service | LAN Port | Subdomain (HTTPS) | Connectivity |
| :--- | :--- | :--- | :--- |
| **Management Dashboard** | `8081` | `https://yourdomain.dedyn.io:8443` | Direct |
| **AdGuard Home (Admin)** | `8083` | `https://adguard.yourdomain.dedyn.io:8443` | Direct |
| **Portainer (Docker UI)** | `9000` | `https://portainer.yourdomain.dedyn.io:8443` | Direct |
| **WireGuard (Web UI)** | `51821` | `https://wireguard.yourdomain.dedyn.io:8443` | Direct |
| **Invidious** | `3000` | `https://invidious.yourdomain.dedyn.io:8443` | **🔒 VPN Routed** |
| **Redlib** | `8080` | `https://redlib.yourdomain.dedyn.io:8443` | **🔒 VPN Routed** |
| **Wikiless** | `8180` | `https://wikiless.yourdomain.dedyn.io:8443` | **🔒 VPN Routed** |
| **LibremDB** | `3001` | `https://libremdb.yourdomain.dedyn.io:8443` | **🔒 VPN Routed** |
| **Rimgo** | `3002` | `https://rimgo.yourdomain.dedyn.io:8443` | **🔒 VPN Routed** |
| **Scribe** | `8280` | `https://scribe.yourdomain.dedyn.io:8443` | **🔒 VPN Routed** |
| **BreezeWiki** | `8380` | `https://breezewiki.yourdomain.dedyn.io:8443` | **🔒 VPN Routed** |
| **AnonOverflow** | `8480` | `https://anonymousoverflow.yourdomain.dedyn.io:8443` | **🔒 VPN Routed** |
| **VERT** | `5555` | `https://vert.yourdomain.dedyn.io:8443` | Direct |

## 🏗️ System Resilience

### Reactive SSL Management
The `cert-monitor.sh` script manages Let's Encrypt certificates. If it hits a rate limit, it detects it, installs a temporary self-signed cert, and retries the moment the window opens.

### Intelligent IP Monitoring
`wg-ip-monitor.sh` checks your IP every 5 minutes. If it changes, it updates deSEC and restarts WireGuard. Your ISP's dynamic IP garbage won't knock you offline.

## 🤝 Community & Contributions

This project is built on the principles of digital autonomy and transparency. While it was originally developed for ZimaOS, the scripts and configurations are portable and can be adapted for other Linux-based platforms.

- **Fork and Experiment**: I encourage you to fork this repository and make it your own. I’d love to see what you do with it and how you improve the stack.
- **Contributions**: Pull requests are welcome. If you find a bug, have an idea for a new feature, or want to improve the documentation, don't hesitate to contribute.
- **Showcase**: If you've built something cool based on this hub, feel free to share it!