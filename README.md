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
