# ZimaOS Privacy Hub - Self-Hosted Stack

A comprehensive self-hosted privacy stack for ZimaOS with WireGuard VPN access, AdGuard Home DNS filtering, and various privacy-respecting frontend services.

## Table of Contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Network Setup](#network-setup)
  - [ISP Router Port Forwarding](#isp-router-port-forwarding)
  - [OpenWRT Configuration](#openwrt-configuration)
  - [Double NAT Setup](#double-nat-setup)
- [deSEC DynDNS Setup](#desec-dyndns-setup)
- [Architecture](#architecture)
- [Troubleshooting](#troubleshooting)
- [Odido Bundle Booster](#odido-bundle-booster)

## Features

- **WireGuard VPN**: Secure remote access to your home network
- **AdGuard Home**: DNS filtering with DoH/DoT/DoQ support
- **Privacy Frontends**: Invidious, Redlib, Wikiless, and more
- **Automatic IP Updates**: DynDNS support via deSEC
- **Let's Encrypt Certificates**: Automatic SSL certificate management

## Prerequisites

- ZimaOS or Docker-compatible Linux system
- Public IP address (static or dynamic with deSEC DynDNS)
- deSEC account (free) for domain and DynDNS: https://desec.io/
- Proton VPN WireGuard configuration (for privacy frontends)

## Quick Start

```bash
# Basic deployment (interactive prompts)
./zima.sh

# Force clean deployment (wipes all data)
./zima.sh -c

# Auto-generate passwords
./zima.sh -p

# Combined: force clean + auto passwords
./zima.sh -c -p
```

## Network Setup

### Overview: Double NAT Scenario

If you have a setup like this:
```
Internet → ISP Router → OpenWRT Router → ZimaOS Device (192.168.69.206)
```

You need to configure port forwarding on **both** routers.

### ISP Router Port Forwarding

Your ISP router is the first point of entry from the internet. You need to forward WireGuard traffic to your OpenWRT router.

#### Required Port Forward on ISP Router:

| Service | External Port | Internal IP | Internal Port | Protocol |
|---------|---------------|-------------|---------------|----------|
| WireGuard | 51820 | 192.168.1.209 | 51820 | UDP |

**Steps (varies by router brand):**

1. Log into your ISP router admin panel (usually http://192.168.1.1)
2. Find "Port Forwarding" or "NAT" settings
3. Create a new port forward rule:
   - **Service Name**: WireGuard VPN
   - **External Port**: 51820
   - **Internal IP**: `192.168.1.209` (OpenWRT router's static WAN IP)
   - **Internal Port**: 51820
   - **Protocol**: UDP only
4. Save and apply changes

### OpenWRT Configuration

Your OpenWRT router needs to forward traffic from the ISP router to your ZimaOS device.

#### Step 1: Set Static IP for OpenWRT WAN Interface

First, configure your OpenWRT router's WAN interface with a static IP so the ISP router can reliably forward traffic to it.

**Via LuCI Web Interface:**

1. Go to **Network → Interfaces**
2. Click **Edit** on the **WAN** interface
3. Change **Protocol** to `Static address`
4. Configure:
   - **IPv4 address**: `192.168.1.209`
   - **IPv4 netmask**: `255.255.255.0`
   - **IPv4 gateway**: `192.168.1.1` (your ISP router)
   - **Use custom DNS servers**: `1.1.1.1` (or your preferred DNS)
5. Click **Save & Apply**

**Via SSH/Command Line:**

```bash
# SSH into your OpenWRT router
ssh root@192.168.69.1

# Configure WAN interface with static IP
uci set network.wan.proto='static'
uci set network.wan.ipaddr='192.168.1.209'
uci set network.wan.netmask='255.255.255.0'
uci set network.wan.gateway='192.168.1.1'
uci set network.wan.dns='1.1.1.1'

# Commit and restart network
uci commit network
/etc/init.d/network restart
```

**Important:** After setting the static IP on OpenWRT's WAN, update your ISP router's port forward to point to `192.168.1.209`.

#### Step 2: Configure Port Forwarding

##### Option A: LuCI Web Interface

1. Go to **Network → Firewall → Port Forwards**
2. Click **Add** and configure:
   - **Name**: `WireGuard-VPN`
   - **Protocol**: `UDP`
   - **Source zone**: `wan`
   - **External port**: `51820`
   - **Destination zone**: `lan`
   - **Internal IP address**: `192.168.69.206` (your ZimaOS IP)
   - **Internal port**: `51820`
3. Click **Save & Apply**

##### Option B: SSH/Command Line

```bash
# SSH into your OpenWRT router
ssh root@192.168.69.1

# Add port forward rule
uci add firewall redirect
uci set firewall.@redirect[-1].name='WireGuard-VPN'
uci set firewall.@redirect[-1].src='wan'
uci set firewall.@redirect[-1].src_dport='51820'
uci set firewall.@redirect[-1].dest='lan'
uci set firewall.@redirect[-1].dest_ip='192.168.69.206'
uci set firewall.@redirect[-1].dest_port='51820'
uci set firewall.@redirect[-1].proto='udp'
uci set firewall.@redirect[-1].target='DNAT'

# Allow WireGuard traffic in firewall
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-WireGuard'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].dest_port='51820'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].target='ACCEPT'

# Commit and restart firewall
uci commit firewall
/etc/init.d/firewall restart
```

##### Option C: Direct /etc/config/firewall Edit

Add to `/etc/config/firewall`:

```
config redirect 'wireguard_vpn'
    option name 'WireGuard-VPN'
    option src 'wan'
    option src_dport '51820'
    option dest 'lan'
    option dest_ip '192.168.69.206'
    option dest_port '51820'
    option proto 'udp'
    option target 'DNAT'

config rule 'allow_wireguard'
    option name 'Allow-WireGuard'
    option src 'wan'
    option dest_port '51820'
    option proto 'udp'
    option target 'ACCEPT'
```

Then restart the firewall:
```bash
/etc/init.d/firewall restart
```

### Double NAT Setup

When you have double NAT (ISP Router → OpenWRT → ZimaOS):

```
┌─────────────────────────────────────────────────────────────────────┐
│                         INTERNET                                     │
│                            │                                         │
│                            ▼                                         │
│              ┌─────────────────────────┐                            │
│              │      ISP ROUTER         │                            │
│              │   (192.168.1.1)         │                            │
│              │                         │                            │
│              │ Port Forward:           │                            │
│              │ UDP 51820 → 192.168.1.209                            │
│              └───────────┬─────────────┘                            │
│                          │                                          │
│                          ▼                                          │
│              ┌─────────────────────────┐                            │
│              │    OpenWRT ROUTER       │                            │
│              │   WAN: 192.168.1.209    │  ← Static IP on WAN        │
│              │   LAN: 192.168.69.1     │                            │
│              │                         │                            │
│              │ Port Forward:           │                            │
│              │ UDP 51820 → 192.168.69.206                           │
│              └───────────┬─────────────┘                            │
│                          │                                          │
│                          ▼                                          │
│              ┌─────────────────────────┐                            │
│              │      ZimaOS DEVICE      │                            │
│              │   (192.168.69.206)      │                            │
│              │                         │                            │
│              │ Services:               │                            │
│              │ - WireGuard (51820/UDP) │                            │
│              │ - WG-Easy UI (51821)    │                            │
│              │ - AdGuard (53, 8083)    │                            │
│              │ - Dashboard (8081)      │                            │
│              └─────────────────────────┘                            │
└─────────────────────────────────────────────────────────────────────┘
```

**Important Notes for Double NAT:**

1. **OpenWRT WAN must have a static IP** (192.168.1.209) so the ISP router can reliably forward traffic
2. Only port 51820/UDP needs to be forwarded through both routers
3. All other services (DNS, web interfaces) are accessed via WireGuard tunnel
4. The WireGuard endpoint in client configs will be your ISP's public IP or deSEC domain

## deSEC DynDNS Setup

deSEC provides free dynamic DNS that automatically updates when your public IP changes.

### How It Works

1. **Initial Setup**: When you run `zima.sh`, it creates an A record pointing to your current public IP
2. **Automatic Updates**: A cron job runs every 5 minutes to check if your IP has changed
3. **IP Change Detection**: If your IP changes, the script automatically:
   - Updates the deSEC DNS A record via API
   - Updates the WG_HOST in docker-compose.yml
   - Restarts the WireGuard container

### Setting Up deSEC

1. **Create Account**: Sign up at https://desec.io/
2. **Create Domain**: 
   - In the deSEC dashboard, create a domain (e.g., `myhome.dedyn.io`)
   - Free `.dedyn.io` subdomains are available
3. **Get API Token**:
   - Go to Account Settings → Token Management
   - Create a new token with write permissions
   - Save this token securely
4. **Run the Script**:
   - When prompted, enter your domain and token
   - The script handles the rest

### DynDNS vs Local IP Monitoring

**Q: Do we still need local IP monitoring if using deSEC DynDNS?**

**A: Yes, for two reasons:**

1. **WG-Easy Configuration**: The WireGuard Easy container needs the current IP in its `WG_HOST` environment variable. When clients scan the QR code or download configs, they get this IP/hostname.

2. **Faster Response**: Local monitoring detects IP changes within 5 minutes and updates both deSEC AND the local container. This is faster than waiting for DNS propagation.

**Could we get IP from deSEC instead?**

Technically yes, but it adds latency and API calls. The local approach is more reliable:
- No dependency on external API for local operations
- Works even if deSEC API is temporarily unavailable
- Faster detection and response to IP changes

### Monitor Script Location

The IP monitor script is installed at:
```
/DATA/AppData/privacy-hub/wg-ip-monitor.sh
```

Logs are written to:
```
/DATA/AppData/privacy-hub/wg-ip-monitor.log
```

## Architecture

### DNS Resolution Chain

```
Users → AdGuard Home (ad blocking) → Unbound (recursive) → Root DNS Servers
```

**Key Points:**
- **AdGuard Home**: Filters ads and trackers, provides DoH/DoT/DoQ
- **Unbound**: Fully recursive resolver, queries root servers directly
- **deSEC**: Only used for domain registration and Let's Encrypt certificates, NOT in DNS resolution chain

### Services Overview

| Service | Port | Access | Description |
|---------|------|--------|-------------|
| Dashboard | 8081 | LAN/VPN | Service overview and management |
| AdGuard Home | 8083 | LAN/VPN | DNS filtering web UI |
| WireGuard UI | 51821 | LAN only | VPN client management |
| WireGuard VPN | 51820/UDP | Internet | VPN tunnel endpoint |
| DNS (plain) | 53 | LAN/VPN | Standard DNS |
| DoH | 443 | LAN/VPN | DNS over HTTPS |
| DoT/DoQ | 853 | LAN/VPN | DNS over TLS/QUIC |
| Invidious | 3000 | LAN/VPN | YouTube frontend |
| Redlib | 8080 | LAN/VPN | Reddit frontend |
| Wikiless | 8180 | LAN/VPN | Wikipedia frontend |
| LibremDB | 3001 | LAN/VPN | IMDb frontend |
| Rimgo | 3002 | LAN/VPN | Imgur frontend |
| Scribe | 8280 | LAN/VPN | Medium frontend |
| BreezeWiki | 8380 | LAN/VPN | Fandom wiki frontend |
| AnonymousOverflow | 8480 | LAN/VPN | StackOverflow frontend |
| VERT | 5555 | LAN/VPN | Local file conversion service |
| Portainer | 9000 | LAN/VPN | Docker container management |
| Odido Booster | 8085 | LAN/VPN | Odido bundle management (optional) |

### Security Model

- **Only WireGuard (51820/UDP) is exposed to the internet**
- All other services are accessible only via:
  - Local network (LAN)
  - WireGuard VPN tunnel
- No direct DNS exposure - requires VPN authentication
- All privacy frontends route through Proton VPN (Gluetun)

## Troubleshooting

### WireGuard Connection Issues

1. **Verify port forwarding**:
   ```bash
   # From outside your network (e.g., mobile data)
   nc -u -v your-domain.dedyn.io 51820
   ```

2. **Check WireGuard is running**:
   ```bash
   docker ps | grep wg-easy
   docker logs wg-easy
   ```

3. **Verify firewall rules (OpenWRT)**:
   ```bash
   iptables -t nat -L PREROUTING -n -v | grep 51820
   ```

### DNS Not Working

1. **Check AdGuard is running**:
   ```bash
   docker ps | grep adguard
   docker logs adguard
   ```

2. **Check Unbound is running**:
   ```bash
   docker ps | grep unbound
   docker logs unbound
   ```

3. **Test DNS resolution**:
   ```bash
   # From ZimaOS device
   dig @192.168.69.206 google.com
   ```

### IP Not Updating

1. **Check monitor script**:
   ```bash
   cat /DATA/AppData/privacy-hub/wg-ip-monitor.log
   ```

2. **Run manually**:
   ```bash
   /DATA/AppData/privacy-hub/wg-ip-monitor.sh
   ```

3. **Check cron**:
   ```bash
   crontab -l | grep wg-ip-monitor
   ```

### Certificate Issues

1. **Check certificate files exist**:
   ```bash
   ls -la /DATA/AppData/privacy-hub/config/adguard/ssl.*
   ```

2. **Inspect the last ACME run for errors (including rate limits)**:
   ```bash
   cat /DATA/AppData/privacy-hub/config/adguard/certbot/last_run.log
   ```
   The deployment script now surfaces the "retry after" timestamp from Let's Encrypt so you know exactly how long you must wait before requesting another certificate.

3. **Regenerate certificates**:
   - Run `./zima.sh -c` to do a clean deployment

## License

MIT License - See LICENSE file for details.

## Odido Bundle Booster

The Odido Bundle Booster is an optional service for Dutch Odido mobile customers that automatically manages data bundles.

### Obtaining Odido Credentials

The Odido Bundle Booster requires an OAuth Token to function. The script will automatically fetch your User ID once you provide the token.

#### Using Odido.Authenticator (Recommended - Works on Any Platform)

Since [odido-aap](https://github.com/ink-splatters/odido-aap) requires an iPhone or Apple Silicon Mac, you can use [Odido.Authenticator](https://github.com/GuusBackup/Odido.Authenticator) instead, which works on any platform with .NET.

**Step-by-Step Guide:**

1. **Clone and build the Authenticator**:
   ```bash
   git clone --recursive https://github.com/GuusBackup/Odido.Authenticator.git
   cd Odido.Authenticator
   dotnet run --project Odido.Authenticator
   ```

2. **Follow the login flow**:
   - The tool will display a login URL
   - Open the URL in your browser and log in with 2FA
   - After login, you'll be redirected to a blank page
   - Copy the URL from your browser's address bar (looks like: `https://www.odido.nl/loginappresult?token=XXXXXXXX`)

3. **Get your OAuth Token**:
   - Paste the URL when prompted
   - The tool will show your **Refresh Token** (one-time use, ignore this)
   - Press Y to generate the **OAuth Token** - **THIS is what you need**

4. **Run the setup script**:
   - When running `./zima.sh`, enter the OAuth Token when prompted
   - The script will **automatically fetch your User ID** using the Odido API
   - No manual User ID entry required!

> **Note**: The User ID is a 12-character hexadecimal string that the script extracts from the Odido API response URL (format: `https://capi.odido.nl/{12-char-hex-userid}/...`).

### Configuration via Dashboard

After deployment, you can configure the Odido Bundle Booster via the web dashboard:
- **Dashboard API Key**: The API key shown after deployment (required for authentication). It is now persisted in `/DATA/AppData/privacy-hub/.secrets` as `ODIDO_API_KEY` and is automatically prefilled on the dashboard.
- **Odido OAuth Token**: Enter your OAuth token and the dashboard will automatically fetch your User ID using the hub-api service
- **Bundle Code**: Default is `A0DAY01` (2GB daily bundle), can also use `A0DAY05` (5GB daily)
- **Threshold**: Minimum MB before auto-renewal triggers (default: 100 MB)
- **Lead Time**: Minutes before depletion to trigger renewal (default: 30 min)

### API Endpoints

The Odido Bundle Booster service is accessible at `http://<LAN_IP>:8085` with the following endpoints:

- `GET /api/status` - Current status and configuration
- `GET /api/odido/remaining` - Fetch remaining data from Odido
- `POST /api/odido/buy-bundle` - Purchase a bundle manually
- `GET /docs` - Interactive API documentation

All endpoints require the `X-API-Key` header with the generated API key (shown after deployment).
