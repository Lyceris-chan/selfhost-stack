# 🛡️ ZimaOS Privacy Hub

**Stop being the product.**

A comprehensive, self-hosted privacy infrastructure designed for digital independence. Route your traffic through secure VPNs, eliminate tracking with isolated frontends, and manage everything from a unified **Material Design 3** dashboard.

---

## 📖 Table of Contents

- [Introduction](#-introduction)
- [Key Features](#-key-features)
- [Prerequisites](#-prerequisites)
- [Installation](#-installation)
  - [Deployment Steps](#deployment-steps)
  - [Customization & Options](#️-customization--options)
- [Architecture & RFC Compliance](#️-architecture--rfc-compliance)
  - [Recursive DNS Engine](#recursive-dns-engine)
  - [Network Topology](#network-topology)
- [Services & Usage](#️-services--usage)
  - [Dashboard](#dashboard)
  - [Service Catalog](#service-catalog)
  - [LibRedirect Integration](#-libredirect-integration)
- [Advanced Configuration](#-advanced-configuration)
  - [OpenWrt & Double NAT](#openwrt--double-nat)
  - [Technical Patch Registry](#technical-patch-registry)
- [Verification & Quality Assurance](#-verification--quality-assurance)
- [Maintenance & Recovery](#-maintenance--recovery)
- [System Requirements & Troubleshooting](#-system-requirements--troubleshooting)
- [Advanced Usage & Policies](#-advanced-usage--policies)

---

## 🚀 Introduction

Your personal fortress of solitude in a noisy internet.
1.  **Block Ads Everywhere**: Clean up the web on your phone, TV, and computer.
2.  **Browse in Peace**: Access Reddit, YouTube, and search engines without being tracked.
3.  **Stay Invisible**: Hide your home IP address behind a secure VPN.

Simple enough for a weekend project, powerful enough for a sysadmin.

---

## 🌟 Key Features

*   **🔒 Complete Independence**: Host your own frontends (Invidious, Redlib) to stop data harvesting.
*   **🚫 Network-Wide Adblock**: Powered by AdGuard Home. No plugins required.
*   **🕵️ VPN Kill-Switch**: If the VPN drops, your private traffic stops instantly.
*   **📱 Frictionless Experience**: Enjoy fast, premium-feeling apps without the nags.
*   **🔑 WireGuard Manager**: Generate QR codes for secure remote access in seconds.
*   **🔄 Atomic Updates**: Risk-free updates with instant rollback capabilities (A/B Slots).
*   **⚡ Hardware Acceleration**: Uses **Intel, NVIDIA, or AMD** GPUs for smooth media transcoding.

---

## 📋 Prerequisites

*   **OS**: ZimaOS, Ubuntu 22.04+, or Debian 12+ (x86_64).
*   **Docker**: Must be installed.
*   **ProtonVPN**: A Free or Paid account.
    *   *Important: Disable **NAT-PMP (Port Forwarding)** when downloading your WireGuard config.*
*   **Domain (Optional)**: A **deSEC** account for custom domains/SSL (Recommended for remote access).

---

## 💿 Installation

### Deployment Steps

1.  **Get Your VPN Configuration**:
    - Go to [ProtonVPN WireGuard Config](https://account.protonvpn.com/downloads#wireguard-configuration).
    - Ensure **NAT-PMP** is **OFF** and **VPN Accelerator** is **ON**.
    - Download the `.conf` file.

2.  **Clone the Repository**:
    ```bash
    git clone https://github.com/Lyceris-chan/selfhost-stack.git
    cd selfhost-stack
    ```

3.  **Run the Installer**:
    Review the [Options Table](#️-customization--options) below to build the perfect command for your needs.
    ```bash
    ./zima.sh [YOUR_FLAGS]
    ```

4.  **Follow the Prompts**:
    Paste your WireGuard config and set your credentials when asked.

### 🛠️ Customization & Options

| Flag | Description |
| :--- | :--- |
| `-p` | **Auto-Passwords**: Generates random secure credentials automatically. |
| `-y` | **Auto-Confirm**: Skips yes/no prompts (Headless mode). |
| `-j` | **Parallel Deploy**: Builds everything at once. High CPU usage. |
| `-s` | **Selective**: Install only specific apps (e.g., `-s invidious,memos`). |
| `-S` | **Swap Slots**: A/B Update toggle. Deploys to the standby slot. |
| `-c` | **Maintenance**: Recreates containers preserving data. |
| `-x` | **Factory Reset**: ⚠️ **Deletes everything**. Wipes all data. |
| `-a` | **Allow ProtonVPN**: Adds ProtonVPN domains to AdGuard allowlist. |
| `-D` | **Dashboard Only**: Regenerates only the dashboard. |
| `-h` | **Help**: Displays usage information. |

---

## 🛡️ Architecture & RFC Compliance

We use **Unbound** and **AdGuard Home** to handle your DNS. It's built to strict standards to ensure no one can spy on your queries.

### Recursive DNS Engine
Instead of asking Google where a website is, your hub asks the internet's root servers directly.

<details>
<summary>📐 <strong>Technical Deep Dive: RFC Implementation</strong> (Click to expand)</summary>

*   **QNAME Minimization ([RFC 7816](https://datatracker.ietf.org/doc/html/rfc7816))**: Privacy preservation by limiting query data sent to upstream servers.
*   **DNSSEC Validation ([RFC 4033](https://datatracker.ietf.org/doc/html/rfc4033))**: Authenticates the origin and integrity of DNS data using cryptographic signatures.
*   **Aggressive Caching ([RFC 8198](https://datatracker.ietf.org/doc/html/rfc8198))**: Improves performance and privacy by using NSEC bitmaps to synthesize negative responses.
*   **Encrypted Transport ([RFC 7858](https://datatracker.ietf.org/doc/html/rfc7858), [RFC 8484](https://datatracker.ietf.org/doc/html/rfc8484))**: Native Support for DNS-over-TLS (DoT) and DNS-over-HTTPS (DoH).
*   **0x20 Bit Randomization**: Injects entropy into queries to provide resistance against DNS spoofing attacks.
*   **Minimal Responses ([RFC 4472](https://datatracker.ietf.org/doc/html/rfc4472))**: Bandwidth efficiency and mitigation of DNS amplification attacks.
*   **Hardened Glue ([RFC 1034](https://datatracker.ietf.org/doc/html/rfc1034))**: Prevents cache poisoning by verifying glue records.
*   **RRSet Round-Robin**: Ensures fair load distribution for multi-homed services.

</details>

### Configuration & Hardening
We've pre-tuned the engine so you don't have to.

#### AdGuard Home
*   **Blocklists**: Includes *Sleepy List* (Trackers), *AdAway* (Mobile Ads), and *Steven Black's List* (Unified Hosts).
*   **Split DNS**: Automatically rewrites your custom domain (e.g., `hub.example.com`) to your LAN IP, ensuring fast local access without hair-pinning.
*   **TLS Hardening**: Forced HTTPS/TLS for all administrative and DNS traffic when a domain is provided.
*   **Upstream**: Exclusively uses the local Unbound instance at `172.x.0.250`, ensuring no leakage to third-party providers.

#### Unbound
*   **Access Control**: Strictly limited to private IP ranges (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`).
*   **Security**: Hardened against DNS cache poisoning and algorithm downgrade attacks.
*   **Performance**: Multi-threaded processing with aggressive prefetching (`prefetch: yes`) to keep the cache warm.

### Network Topology
Traffic is split into three zones to balance security and convenience.

1.  **Zone 1 (VPN-Isolated)**: Privacy apps (Invidious, Redlib). Locked to the VPN. Upstream see only the VPN IP.
2.  **Zone 2 (Remote Access)**: Your devices connecting from outside via your personal WireGuard tunnel.
3.  **Zone 3 (Local-Only)**: Admin tools and utilities that never touch the internet (Memos, Dashboard).

---

## 🖥️ Services & Usage

### Dashboard
Access your control center at `http://<LAN_IP>:8081`. From here, you can manage services, view logs, and monitor system health.

### Service Catalog

<details>
<summary>📦 <strong>View Included Services</strong> (Click to expand)</summary>

All services are either built from source with hardened configurations or use trusted minimal images.

| Service | Category | Routing | Description |
| :--- | :--- | :--- | :--- |
| **Invidious** | Frontend | **🔒 VPN** | Private YouTube frontend. |
| **Redlib** | Frontend | **🔒 VPN** | Private Reddit frontend. |
| **SearXNG** | Frontend | **🔒 VPN** | Meta-search engine. |
| **Rimgo** | Frontend | **🔒 VPN** | Private Imgur frontend. |
| **Wikiless** | Frontend | **🔒 VPN** | Private Wikipedia frontend. |
| **Scribe** | Frontend | **🔒 VPN** | Private Medium frontend. |
| **BreezeWiki** | Frontend | **🔒 VPN** | Private Fandom frontend. |
| **AnonOverflow** | Frontend | **🔒 VPN** | Private StackOverflow frontend. |
| **Immich** | Utility | **🔒 VPN*** | Self-hosted photo & video management. |
| **Memos** | Utility | **🏠 Local** | Privacy-focused note-taking. |
| **Cobalt** | Utility | **🏠 Local** | Media downloader. |
| **VERT** | Utility | **🏠 Local** | File conversion (**Intel/NVIDIA/AMD** accelerated). |
| **AdGuard Home** | Core | **🏠 Local** | Network-wide ad blocking & DNS. |
| **WireGuard** | Core | **🏠 Local** | VPN server for remote access. |

*\*Immich uses the VPN for metadata fetching; personal media remains local.*

</details>

### 🔀 LibRedirect Integration
To automatically redirect your browser from big-tech sites to your private Hub:
1.  Install the **LibRedirect** extension ([Firefox](https://addons.mozilla.org/en-US/firefox/addon/libredirect/) / [Chrome](https://chromewebstore.google.com/detail/libredirect/pobhoodpcdojmedmielocclicpfbednh)).
2.  Import the `libredirect_import.json` file generated in your project root during installation.

---

## 📡 Advanced Configuration

### OpenWrt & Double NAT
If you are behind an ISP modem *and* your own router (OpenWrt), you are in a Double NAT configuration.

1.  **Static IP**: Assign a static LAN IP to your Hub machine.
2.  **Port Forwarding**: Forward UDP port `51820` from the ISP modem to your router, and then from your router to the Hub.
3.  **DNS Redirection**: Use OpenWrt's firewall to force all LAN DNS traffic to your Hub's AdGuard instance.

### Technical Patch Registry
We apply surgical patches to upstream code during the synchronization phase to ensure a minimal footprint, fix bugs, and optimize for hardware acceleration.

| Service | File Patched | Logic Applied |
| :--- | :--- | :--- |
| **BreezeWiki** | `docker/Dockerfile` | Replaces Debian base with **Alpine 3.21**; installs Racket dependencies via `apk` for a 70% smaller image. |
| **Invidious Companion** | `Dockerfile` | Injects `ENV RUST_MIN_STACK=16777216` to prevent recursion-based stack overflows; corrects user creation logic for Alpine. |
| **VERTd** | `Dockerfile` | Detects and links development libraries for **Intel (QSV)**, **NVIDIA (NVENC)**, and **AMD (VA-API)**; fallbacks to Debian-slim on non-GPU systems. |
| **Gluetun** | `Dockerfile` | Injects Alpine compatibility flags and simplifies the OpenVPN binary symlinking for consistent initialization. |
| **Rimgo** | `Dockerfile` | Injects TailwindCSS build step into the CI/CD pipeline to ensure UI consistency without external assets. |
| **Generic** | `Dockerfile*` | Upgrades legacy `debian:buster-slim` to `bookworm-slim`; converts `apt-get` patterns to `apk` when Alpine bases are detected. |

---

## ✅ Verification & Quality Assurance

This repository includes a comprehensive test suite to ensure stability, privacy, and performance across different environments.

*   **Automated Stage-Based Deployment**: The stack is verified in 6 distinct stages to manage resource consumption and ensure dependency integrity.
*   **UI/UX Interaction Testing**: Puppeteer-based tests simulate real user interactions on the dashboard, verifying theme persistence, administrative authentication, and real-time log streaming.
*   **Protocol Integrity**: DNS queries are audited to ensure **RFC compliance** and prevent leakage to third-party resolvers.
*   **Hardware Acceleration**: Auto-detection logic is tested against Intel, NVIDIA, and AMD hardware to ensure seamless media transcoding.

---

## 💾 Maintenance & Recovery

### Backup
**Always backup your data.** The hub stores personal information in `data/AppData/privacy-hub`.
```bash
# Example backup
tar -czf privacy-hub-backup.tar.gz /data/AppData/privacy-hub
```

### Recovery
*   **Slow/Glitchy?**: Run `./zima.sh -c` to recreate containers without data loss.
*   **Bad Update?**: Run `./zima.sh -S` to swap back to the previous stable version (A/B Rollback).
*   **Total Reset**: Run `./zima.sh -x` to wipe everything and start fresh (Data loss warning!).

---

## 🖥️ System Requirements & Troubleshooting

### Verified Environment
*   **CPU**: 2 Cores (64-bit) minimum.
*   **RAM**: 4 GB minimum (8 GB+ recommended for Immich/VERT).
*   **Storage**: 32 GB SSD minimum.

### Troubleshooting
| Issue | Potential Solution |
| :--- | :--- |
| **"My internet broke!"** | DNS resolution failed. Temporarily set your router DNS to `9.9.9.9` (Quad9) to restore access, then check the Hub status. |
| **"Can't connect remotely"** | Verify UDP Port 51820 is forwarded. Check if your ISP uses CGNAT. |
| **"SSL is invalid"** | Ensure ports 80/443 are reachable for Let's Encrypt validation. Check `deployment.log`. |

---

## 🧩 Advanced Usage & Policies

<details>
<summary>🧪 <strong>Staged Headless Verification</strong></summary>

For developers, the hub includes a state-aware orchestrator for multi-stage deployments:
```bash
./test/manual_verification.sh
```
It features auto-resume logic, timeout protection, and automated Puppeteer UI audits.

</details>

<details>
<summary>🌐 <strong>Connection Exposure Map</strong></summary>

| Service | Purpose | Exposure |
| :--- | :--- | :--- |
| **Frontends** | Content retrieval | **🔒 VPN IP** |
| **Dashboard Assets** | Fonts & Icons | **🔒 VPN IP** |
| **Container Registries** | Pulling images | **🏠 Home IP** |
| **Git Repositories** | Cloning source | **🏠 Home IP** |
| **deSEC.io** | SSL Challenges | **🏠 Home IP** |

</details>

---

## 🚨 Disclaimer

This software is provided "as is". While designed for security, the user is responsible for ensuring their specific network configuration is safe. **Do not use GitHub Codespaces for production deployment.**

*Built with ❤️ for digital sovereignty.*