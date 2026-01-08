# 🛡️ ZimaOS Privacy Hub

**Stop being the product.**

A comprehensive, self-hosted privacy infrastructure designed for digital independence. Route your traffic through secure VPNs, eliminate tracking with isolated frontends, and manage everything from a unified **Material Design 3** dashboard.

---

## 📖 Quick Navigation

*   **[🚀 Getting Started](#-getting-started)** - *Simple setup for everyone.*
*   **[🌟 Key Features](#-key-features)** - *What does it actually do?*
*   **[🧩 Adding Your Own Services](#-adding-your-own-services)** - *Customize your hub.*
*   **[🛡️ Architecture (Nerds Only)](#️-architecture-nerds-only)** - *How it works under the hood.*
*   **[🛠️ Advanced Options](#️-advanced-options)** - *Command-line power tools.*
*   **[💾 Maintenance & Recovery](#-maintenance--recovery)** - *Backups and fixes.*

---

## 🚀 Getting Started

Setting up your privacy fortress is easy. Follow these simple steps:

### 1. Simple Setup (The "Patrick Star" Way)
1.  **Get a VPN File**: Go to [ProtonVPN](https://account.protonvpn.com/downloads#wireguard-configuration) and download a **WireGuard** `.conf` file. 
    *   *Make sure **NAT-PMP** is **OFF**.*
2.  **Clone & Run**: Open your terminal and type:
    ```bash
    git clone https://github.com/Lyceris-chan/selfhost-stack.git
    cd selfhost-stack
    ./zima.sh -p -y
    ```
3.  **Paste & Relax**: Paste your VPN file content when asked. The hub will do the rest!

### 2. Accessing Your Hub
Once finished, open your browser to: `http://your-machine-ip:8081`
*   **Username**: `admin`
*   **Password**: *Generated during setup (check your terminal or `.secrets` file)*

> [!IMPORTANT]
> **DNS Setup**: To use the secure features on your phone or laptop, you must set your device's DNS server to your Hub's IP address.

---

## 🌟 Key Features

*   **🚫 Ads? What Ads?**: Network-wide ad blocking. No more YouTube or Reddit ads.
*   **🕵️ Stay Hidden**: Your home IP is replaced by a VPN IP for all privacy apps.
*   **🔄 Unbreakable Updates**: Two "Slots" (A/B) mean you can update safely. If it breaks, just switch back.
*   **📱 Secure Remote Access**: Generate a QR code, scan it, and browse securely from anywhere.
*   **⚡ Supercharged Media**: Uses your computer's GPU (**Intel, NVIDIA, or AMD**) for lightning-fast video.

---

## 🧩 Adding Your Own Services

Want to add something that isn't in the list? You can!

### How to add a custom service to the Dashboard:
1.  Create a file named `custom_services.json` in the project folder.
2.  Add your service details like this:
```json
{
  "services": {
    "my-cool-app": {
      "name": "My Custom App",
      "description": "A personal service I added myself!",
      "category": "apps",
      "url": "http://your-ip:1234",
      "order": 100
    }
  }
}
```
3.  Run `./zima.sh -D` to refresh the dashboard. Your new app will appear instantly!

> [!TIP]
> You should also add your app to the `docker-compose.yml` if you want the Hub to manage the container for you.

---

## 🛡️ Architecture (Nerds Only)

For those who want to see the gears turning.

### Recursive DNS Stack
We don't trust third-party DNS. We use **Unbound** as a recursive resolver.
*   **RFC Compliance**: Strict adherence to **QNAME Minimization ([RFC 7816](https://datatracker.ietf.org/doc/html/rfc7816))** and **DNSSEC Validation**.
*   **Encryption**: Native support for **DoH ([RFC 8484](https://datatracker.ietf.org/doc/html/rfc8484))** and **DoT ([RFC 7858](https://datatracker.ietf.org/doc/html/rfc7858))**.
*   **Hardening**: Protection against cache poisoning, 0x20 bit randomization, and minimal responses.

### Network Isolation
The stack is split into three distinct security zones:
1.  **Zone 1 (Isolated)**: Apps like Redlib/Invidious are locked to the **Gluetun** VPN container.
2.  **Zone 2 (Ingress)**: **WireGuard-Easy** provides a secure entry point for external devices.
3.  **Zone 3 (Management)**: The Hub API and Dashboard run on a local bridge for maximum performance.

### Atomic Slot System (A/B)
The project uses an A/B update strategy.
*   Slot A and Slot B are independent container groups.
*   The dashboard allows you to "Swap Slots" to test new versions without touching your stable environment.

---

## 🛠️ Advanced Options

| Flag | What it does |
| :--- | :--- |
| `-p` | **Auto-Passwords**: Generates random secure passwords for you. |
| `-y` | **Auto-Confirm**: Skips all "Are you sure?" prompts. |
| `-j` | **Parallel Mode**: Build everything at the same time (Fast but Heavy). |
| `-S` | **Swap Slots**: Moves everything to the other A/B slot. |
| `-s <list>` | **Selective**: Only install what you want (e.g., `-s invidious,memos`). |
| `-x` | **Factory Reset**: ⚠️ **Wipes everything**. Use with caution! |

---

## 💾 Maintenance & Recovery

### Backups
Data is stored in `data/AppData/privacy-hub`. Copy this folder to keep your settings safe.
```bash
tar -czf privacy-hub-backup.tar.gz ./data/AppData/privacy-hub
```

### Common Fixes
*   **Network Issues?**: Run `./zima.sh -c` to reset containers without losing data.
*   **Forgot Passwords?**: Check the `.secrets` file in your project folder.
*   **Broken Update?**: Use the **Swap Slot** button on the dashboard to roll back.

---

## 🚨 Disclaimer

This software is provided "as is". Digital sovereignty requires personal responsibility. Ensure your hardware is secure and your backups are regular.

*Built with ❤️ for digital sovereignty.*
