# 🛡️ ZimaOS Privacy Hub

A self-hosted privacy stack for people who actually want to own their data instead of renting a false sense of security.

## 📋 Table of Contents
- [Project Overview](#-project-overview)
- [Quick Start](#-quick-start)
- [Privacy & Ownership](#-privacy--ownership)
- [Network Configuration](#-network-configuration)
- [Advanced Setup: OpenWrt & Double NAT](#-advanced-setup-openwrt--double-nat)
- [Remote Access: Taking Your Network With You](#-remote-access-taking-your-network-with-you)
- [Security Audit & Privacy Standards](#-security-audit--privacy-standards)
- [Service Catalog](#-service-catalog)
- [Service Access & Port Reference](#-service-access--port-reference)
- [System Resilience](#-system-resilience)

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

### The "Third Party" Trust Gap
For many, NextDNS is the gold standard. I’ve had a great experience with them - it’s convenient, reliable, and has a polished dashboard. But no matter how "trustable" a provider is, you are still handing your entire digital footprint to a third party. If they get a subpoena, or they get bought, or they just change their minds, your data is gone. This stack is for people who want to stop trusting and start owning.

- **The Google Profile**: Google's DNS (8.8.8.8) turns you into a data source. They build profiles on your health, finances, and interests based on every domain you resolve, then sell that access to target you through their massive advertising machine.
- **The Cloudflare Illusion**: Recent shifts in 2025 have shown that even "neutral" providers like Cloudflare aren't neutral when a government knocks. In Germany, Cloudflare processes global blocks based on local self-regulatory bodies (FSM-Hotline). Their CDN is now ruled a "host," allowing governments to force censorship. Do you really want your "neutral pipe" to be a global censorship tool?
- **ISP Predation**: Your ISP sees everything. They log, monetize, and sell your history to brokers. They also use DNS hijacking to redirect you to government warning pages. They are the gatekeepers, and they don't have your interests in mind.

### Independent DNS Resolution (QNAME Minimization)
This stack cuts out the middleman by using **Unbound** as a recursive resolver with **QNAME Minimization (RFC 7816)** enabled.
- **How it works**: Most resolvers tell every server in the chain the full domain you're visiting. Unbound only tells the `.com` server it's looking for something in `.com`, and the `stuff.com` server it's looking for `stuff.com`. 
- **Direct Talk**: Unbound talks directly to the Root DNS servers. You aren't using the ISP's "censored phonebook." You're talking to the source.
- **The Result**: No single server in the chain - besides the last authoritative one - ever knows the full domain you're trying to reach. Your intent remains private.
- **DNSSEC Validation**: Every response is verified cryptographically. If an ISP tries to hijack your connection, the system detects the signature mismatch and blocks it.

### ECH & Modern Standards
We support **Encrypted Client Hello (ECH)**. It shields your metadata, ensuring that even the "handshake" of your connection is invisible to snooping eyes.

## 🌐 Network Configuration

### Standard Setup: ISP Router Only
If you just have the standard router your ISP gave you, you only need to do one thing:
1.  **Forward port 51820/UDP** to your ZimaOS machine's local IP.
This is the only open door. As explained in the [Security Model](#-security-audit--privacy-standards), this port is cryptographically silent and does not increase your attack surface.

### Local "Home" Mode: DNS Rewrites
When you're at home, you shouldn't have to bounce traffic off a satellite just to see your own dashboard. 
- **How it works**: AdGuard Home uses **DNS Rewrites**. When your device asks for `yourdomain.dedyn.io`, it's given the local LAN IP (`192.168.1.100`) instead of your public IP.
- **The Result**: You get to use your SSL certificate and local speeds without needing a VPN tunnel.

## 📡 Advanced Setup: OpenWrt & Double NAT

If you're running a real router like OpenWrt behind your ISP modem, you are in a **Double NAT** situation. This means your data has to pass through two layers of address translation before reaching your machine. You need to fix the routing so your packets actually arrive.

### 1. OpenWrt: Static IP Assignment (DHCP Lease)
Assign a static lease so your Privacy Hub doesn't wander off to a different IP every time the power cycles.
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

## 📡 Remote Access: Taking Your Network With You

Privacy Hub isn't just for your house; it's a portable security boundary. Using **WG-Easy (WireGuard)**, you can route all your traffic back through your ZimaOS from anywhere.

### Bandwidth-Optimized Split Tunneling
By default, we use **Split Tunneling**. This means only your private traffic and DNS go through the tunnel. 

VPN companies love to scare you into thinking your ISP seeing your data is a disaster. It's 2025. [Over 95% of web traffic is HTTPS encrypted](https://transparencyreport.google.com/https/overview). Your ISP can see you're connected to an IP, but they can't see what's inside the packet. HTTPS already took care of that.

The **real leak** is DNS. If you don't own your DNS, your ISP logs every domain you visit. By using split tunneling:
- **Efficiency**: Your heavy, already-encrypted traffic (Netflix, updates) goes direct. You save bandwidth and don't lag.
- **Privacy**: Your DNS is still forced through AdGuard Home and Unbound. Your "phonebook" requests are never seen or sold.

### Why use WireGuard for Remote Access?
- **Public Wi-Fi Safety**: Don't trust the airport Wi-Fi. Encrypt your DNS and internal traffic.
- **Accessing Local Services**: Use internal IPs (like `http://192.168.1.100:8081`) as if you were at home.
- **Seamless Domain Access (dedyn.io)**: Your hostnames (see [Service Access](#-service-access--port-reference)) resolve correctly over the VPN, allowing you to use SSL certificates globally.

## 🛡️ Security Audit & Privacy Standards

### DHI Hardened Images
We don't use standard "official" images where we can avoid it. We use **DHI hardened images** (`dhi.io`). 
- **Why?**: Standard images are packed with "convenience" tools that are actually just security holes waiting to be exploited. Hardened images are stripped down to the absolute bare essentials.
- **The Stats**: Hardened images can reduce the attack surface by **over 70%** by removing unnecessary binaries and libraries. Less code means fewer bugs, and fewer bugs mean fewer ways for someone to break into your house. (Source: [CIS Benchmarks](https://www.cisecurity.org/benchmark/docker))

### The "Silent" Security Model (DDoS & Scan Resistance)
Opening a port for WireGuard does **not** expose your home to DDoS or unauthorized access. In fact, this setup is significantly more secure than typical corporate "cloud" logins.
- **WireGuard is Silent**: Unlike OpenVPN or SSH, WireGuard does not respond to packets it doesn't recognize. If an attacker scans your IP, your port 51820 looks **closed**. It won't even send a "go away" packet. 
- **DDoS Mitigation**: Because WireGuard is silent to unauthenticated packets, it is inherently resistant to most DDoS and scanning attacks. Since it doesn't keep state for unauthorized connections, an attacker can't exhaust your machine's memory with "half-open" connections (like a SYN flood). You're effectively invisible to the "noise" of the internet.
- **Cryptographic Ownership**: You can't "guess" a password. You need a valid 256-bit cryptographic key. Without it, you don't exist to the server.
- **No Domain-to-Home Path**: Your domain is just a pointer. Since Nginx only listens internally and the only entry point is the secure tunnel, there is **no way** for someone to connect to your dashboard from the internet without being inside your tunnel first. You aren't just hidden; you're unreachable.

## 📦 Service Catalog

### Core Infrastructure
- **WireGuard (WG-Easy)**: A VPN server that actually works. Secure remote access without the corporate "cloud" middleman.
- **AdGuard Home**: Network-wide security and ad-filtering. It stops the trackers before they even touch your device.
- **Unbound**: A validating, recursive, caching DNS resolver. You talk to the root servers directly. You don't ask for permission.
- **Gluetun**: VPN client that routes specific service traffic through an external provider you trust.
- **Nginx & Hub-API**: The dashboard and the brains of the operation. No external dependencies.

### Security & Resilience
- **Reliable Local Fonts**: Font CSS files are served locally. Why let Google track your IP just because you wanted a nice-looking font?
- **Reactive SSL**: Automated Let's Encrypt management with proactive rate-limit recovery.
- **IP Monitoring**: Real-time detection of public IP changes with automated DNS synchronization.

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
