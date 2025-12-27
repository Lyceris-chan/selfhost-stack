# 🛡️ ZimaOS Privacy Hub

![Privacy Hub Banner](https://img.shields.io/badge/Privacy-Hub-D0BCFF?style=for-the-badge&logo=shield&logoColor=381E72)
![Security](https://img.shields.io/badge/Security-Hardened-success?style=for-the-badge&logo=check)
![License](https://img.shields.io/badge/License-MIT-blue?style=for-the-badge)

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
4.  [Privacy Architecture](#-privacy--architecture)
5.  [System Requirements](#-system-requirements)
6.  [Troubleshooting](#-troubleshooting)
7.  [Advanced Usage](#-advanced-usage)

---

## 🏗️ Getting Started

### Prerequisites

Before you begin, gather these essentials:

*   **Docker Hub Account**: Username & Access Token (Read-only) to avoid rate limits.
*   **ProtonVPN WireGuard Config**: Required for the `Gluetun` VPN gateway to hide your IP.
    *   *Download a free config from your ProtonVPN account dashboard.*
*   **deSEC Domain (Optional)**: For trusted SSL certificates and mobile "Private DNS" support.

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
| `-a` | **Allow Proton**: Whitelists ProtonVPN domains in AdGuard. |
| `-c` | **Reset**: Clears containers but keeps data. |
| `-x` | **Uninstall**: Wipes the stack (Data loss risk!). |
| `-s` | **Selective**: Deploy only specific services (e.g., `-s invidious,memos`). |

### ✅ Verification

After installation, verify your stack:
1.  **Dashboard**: `http://<LAN_IP>:8081` (Should be accessible).
2.  **VPN Check**: `docker exec gluetun wget -qO- http://ifconfig.me` (Should show VPN IP).
3.  **DNS Check**: `dig @localhost example.com` (Should resolve).

---

## 🖥️ Dashboard & Services

Access your unified control center at `http://<LAN_IP>:8081`.

### Included Privacy Services

| Service | Local URL | Category | Description |
| :--- | :--- | :--- | :--- |
| **Invidious** | `http://<LAN_IP>:3000` | Frontend | YouTube without ads or tracking. |
| **Redlib** | `http://<LAN_IP>:8080` | Frontend | Private Reddit viewer. |
| **Rimgo** | `http://<LAN_IP>:3002` | Frontend | Anonymous Imgur browser. |
| **Wikiless** | `http://<LAN_IP>:8180` | Frontend | Private Wikipedia reader. |
| **Scribe** | `http://<LAN_IP>:8280` | Frontend | Alternative Medium frontend. |
| **BreezeWiki** | `http://<LAN_IP>:8380` | Frontend | De-fandomized Wiki interface. |
| **AnonOverflow** | `http://<LAN_IP>:8480` | Frontend | Private Stack Overflow viewer. |
| **Memos** | `http://<LAN_IP>:5230` | Utility | Self-hosted notes & knowledge base. |
| **VERT** | `http://<LAN_IP>:5555` | Utility | Secure local file conversion. |
| **AdGuard Home** | `http://<LAN_IP>:8083` | Core | Network-wide DNS ad-blocking. |
| **WireGuard** | `http://<LAN_IP>:51821` | Core | Secure remote access to your home LAN. |

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

---

## 🛡️ Privacy & Architecture

### The "Zero-Leaks" Promise
1.  **Split Tunneling**:
    *   **Privacy Traffic** (Invidious, Redlib) -> **ProtonVPN** -> Internet.
    *   **Home Traffic** (Netflix, Gaming) -> **ISP** -> Internet (Full Speed).
2.  **Asset Proxying**: The dashboard downloads fonts and icons via the VPN proxy. Your home IP is never exposed to CDNs.
3.  **Hardened Images**: We use custom `dhi.io` docker images that strip telemetry and reduce attack surface.

### Security Best Practices
*   **Never expose** the dashboard port (8081) to the internet directly. Use the WireGuard VPN to access it remotely.
*   **Backup** your `.secrets` file located at `/DATA/AppData/privacy-hub/.secrets`.

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

*   **"My internet stopped working!"**
    *   If the Privacy Hub goes offline, DNS resolution fails. Set your router DNS to `1.1.1.1` temporarily to restore access.
*   **"I can't connect remotely."**
    *   Check Port 51820 forwarding.
    *   Ensure your ISP isn't using CGNAT (Double NAT).
*   **"Services are slow."**
    *   Check your VPN connection speed in the dashboard.
    *   Try a different ProtonVPN server config.

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
    *(Warning: This deletes data!)*

---

## 📡 Advanced Usage

### Double NAT & OpenWrt
If you are behind an ISP modem *and* an OpenWrt router (Double NAT), you must forward UDP Port 51820 on **both** devices sequentially.

<details>
<summary><strong>🔧 Add Your Own Services</strong> (Click to expand)</summary>

1. **Definition**: Add your service block to Section 13 of `zima.sh`.
2. **Monitoring**: Update the status loop in `WG_API_SCRIPT` inside `zima.sh`.
3. **UI**: Add metadata to the `services.json` catalog generated in `zima.sh`.
</details>

<details>
<summary><strong>🧪 Automated Verification</strong> (Click to expand)</summary>

To ensure a "set and forget" experience, every release undergoes a rigorous automated verification pipeline:
*   **Interaction Audit**: Puppeteer-based suite simulates real user behavior.
*   **Non-Interactive Deployment**: verified `-p -y` flow for zero-prompt success.
*   **M3 Compliance Check**: Automated layout audits ensure the dynamic grid and chips adapt to any screen size.
*   **Log & Metric Integrity**: Container logs audited for 502/504 errors.
</details>

---

## 🚨 Disclaimer

This software is provided "as is". While designed for security, the user is responsible for ensuring their specific network configuration is safe. **Do not use GitHub Codespaces for production deployment.**

---

*Built with ❤️ for digital sovereignty.*
