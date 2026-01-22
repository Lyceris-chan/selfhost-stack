# 🛡️ ZimaOS Privacy Hub

**Stop being the product.**

The ZimaOS Privacy Hub is a comprehensive, self-hosted privacy infrastructure
designed for digital independence. Route your traffic through secure VPNs,
eliminate tracking with isolated frontends, and manage everything from a unified **Material Design 3** dashboard.


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
- [Dashboard and Services](#️-dashboard--services)
  - [WireGuard Client Management](#-wireguard-client-management)
  - [Credential Management](#-credential-management)
  - [LibRedirect Integration](#-libredirect-integration)
  - [Included Privacy Services](#included-privacy-services)
  - [Hardware Acceleration](#-hardware-acceleration-gpuqsv)
  - [Network Configuration](#-network-configuration)
- [Advanced Setup: OpenWrt and Double NAT](#-advanced-setup-openwrt--double-nat)
- [Privacy and Architecture](#️-privacy--architecture)
- [Security Standards](#-security-standards)
- [System Requirements](#️-system-requirements)
- [Troubleshooting](#-troubleshooting)
- [Maintenance](#-maintenance)

---

## 🚀 Key Features

- **🔒 Data Independence**: Host your own frontends (Invidious, Redlib, etc.) to
  prevent upstream entities like Google and Reddit from profiling you.
- **🚫 Ad-free by Design**: Network-wide ad blocking through AdGuard Home and
  native removal of sponsored content in video and social feeds.
- **🕵️ VPN-gated Privacy**: All external requests route through a **Gluetun
  VPN** tunnel. Upstream providers only see your VPN IP, keeping your home
  identity hidden.
- **📺 No Adblock Nags (Invidious)**: Watch YouTube without ad-blocking popups.
  Invidious fetches video data server-side, so YouTube does not detect your
  ad-blocking tools.
- **📱 Frictionless Browsing (Redlib)**: Redlib eliminates "Open in App" prompts
  and mobile-web trackers. Enjoy a fast Reddit experience on any device without
  using the official app.
- **🚀 Faster and Safer**: Self-hosted frontends remove tracking scripts,
  telemetry, and bloated JavaScript. This results in faster page loads and
  improved browser security.
- **🔑 Easy Remote Access**: Built-in **WireGuard** management. Generate client
  configurations and **QR codes** directly from the dashboard to connect your
  phone or laptop securely.
- **⚡ Hardware Performance**: Automatically detects and provisions GPU
  acceleration (Intel QSV, AMD VA-API, or NVIDIA) for media-heavy services like
  Immich and VERT.
- **🎨 Material Design 3**: A responsive dashboard with dynamic theming and
  real-time health metrics.

> ⚠️ **Heads up: The cat-and-mouse game**  
> Companies like Google and Reddit **actively try to break** these privacy
> frontends. Why? Because every user on Invidious or Redlib is a user they can't
> track, monetize, or serve ads to. They regularly change their APIs, add new
> anti-bot measures, and modify their page structures specifically to break
> these tools. This stack uses **pre-built images** and automated updates so we
> can apply fixes quickly. Occasional outages are part of the privacy game. It's
> worth it.

> 🔌 **Service availability and redundancy**  
> These services are **only available** while the device you are hosting on is
> powered on and network-accessible. In the event of a power outage, network
> failure, or hardware issue, access to your self-hosted services will be lost.
> We strongly recommend exploring redundancy options (such as UPS backups or
> secondary failover nodes) to ensure continuous access to your privacy
> infrastructure. Be aware that you are your own "cloud provider" now!

---

## 💻 Hardware & Capacity

The Privacy Hub is designed to run efficiently on a wide range of hardware.
Below is a reference configuration based on a real-world deployment,
demonstrating the stack's efficiency.

### Reference Configuration

- **CPU**: Intel Core i3-10105T (4 Cores / 8 Threads, 3.00GHz)
- **RAM**: 32 GB DDR4 (2666 MHz)
- **GPU**: Intel UHD Graphics 630 (integrated)
- **Storage**: NVMe SSD (recommended for Docker volumes)

### Estimated Capacity

With the specs above, this stack can comfortably support:

- **Heavy Use**: 5-10 concurrent users (active Immich usage, video transcoding,
  machine learning tasks).
- **Moderate Use**: 20-50+ concurrent users (browsing Invidious, Redlib,
  searching SearXNG).
- **Light Use**: 100+ concurrent users (DNS queries, text-based services).

> 💡 **Resource Notes**:
>
> - **Immich** is the most resource-intensive service, utilizing CPU/GPU for
>   machine learning (facial recognition) and video transcoding. 32GB RAM is
>   excellent for this.
> - **Privacy Frontends** (Invidious, Redlib, etc.) are extremely lightweight.
> - **Intel Quick Sync (QSV)** on the UHD 630 is automatically detected and used
>   for hardware transcoding, significantly reducing CPU load.

---

## 🚀 Deployment

**Don't worry: this is easier than it looks!** The Privacy Hub guides you
through everything.

Just follow these steps, and you'll have your own private internet in about
**2–5 minutes**.

<details>
<summary>🤔 <strong>Never done this before? Start here!</strong> (Click to expand)</summary>

### What you're building

Think of this as your personal "Google" but one that:

- ✅ **Doesn't track you** - No browsing history sold to advertisers
- ✅ **Blocks ads everywhere** - On your phone, laptop, smart TV, everything
- ✅ **Speeds up the internet** - Removes tracking scripts and bloat
- ✅ **Works anywhere** - Access your services from coffee shops, hotels,
  anywhere

### What you need to know

**Zero technical experience needed!** If you can:

- Copy and paste text
- Type a password
- Press Enter

...then you can do this! The installer asks simple questions and does all the
hard work.

### What's a "hub"?

It's just a computer (could be an old laptop, a $50 Raspberry Pi, or a fancy
server) that runs these privacy tools 24/7 for you. Think of it like your
personal Netflix server, but for privacy.

### What's a "VPN"?

A Virtual Private Network is like a secret tunnel for your internet traffic.
When you use YouTube through this hub, YouTube doesn't see your home address -
it sees the VPN address shared by thousands of users. It's like using a P.O. Box
instead of your home address.

### Will this break my internet?

**No!** Everything is optional:

- ❌ Don't want to use the hub's DNS? Don't change your router settings.
- ❌ Don't want to redirect YouTube? Don't install LibRedirect.
- ❌ Something not working? Skip it and use the regular internet.

Your normal internet access stays exactly as it was. This only adds privacy
options.

</details>

### Before you start (checklist)

<details>
<summary>📋 <strong>What you'll need</strong> (Click to expand for explanations)</summary>

#### 1. A computer to run it on

- [ ] **Any of these work**: Old laptop, ZimaBoard, Raspberry Pi 5, NUC, or any
      64-bit computer
- [ ] **Why?** This will be your "hub" that runs 24/7 (or whenever you want
      privacy)
- [ ] **Cost?** $0 if you have an old laptop, or $50-200 for a Raspberry Pi or
      mini PC

#### 2. Operating system

- [ ] **ZimaOS**, **Ubuntu 22.04+**, or **Debian 12+** installed
- [ ] **Why?** These are free Linux systems that work great for servers
- [ ] **Never used Linux?** No problem! ZimaOS has a point-and-click installer
      like Windows

#### 3. Docker (the app runner)

- [ ] **Docker** installed on your hub computer
      ([Get Docker](https://docs.docker.com/get-docker/))
- [ ] **What's Docker?** It's like an app store for servers. Makes everything
      super easy.
- [ ] **How to get it?** Follow the link above, or on Ubuntu/Debian just run:
      `curl -fsSL https://get.docker.com | sh`

#### 4. ProtonVPN account

- [ ] **A ProtonVPN account** - **Free Tier is sufficient!**
      ([Sign up](https://account.protonvpn.com/signup))
- [ ] **Why ProtonVPN?** They're privacy-focused, based in Switzerland, and have
      a generous free tier.
- [ ] **Why Free?** We only route specific privacy frontend traffic (Invidious,
      Redlib) through the VPN to anonymize requests. High-bandwidth activities
      (like gaming or direct downloads) bypass the VPN via split-tunneling, so
      the free tier's speed limits are negligible for this use case. Premium is
      not required but supports Proton's mission.
- [ ] **Cost?** $0 for free tier.

#### 5. Domain for HTTPS (Required for Android/iOS DNS)

- [ ] **A deSEC account** for free SSL/domain ([Sign up](https://desec.io))
- [ ] **Why?** Gives you `https://my-hub.dedyn.io` instead of
      `http://192.168.1.100`.
- [ ] **Cost?** $0 - completely free forever.
- [ ] **Is this mandatory?**
  - **YES** for **Android Private DNS**: Android strictly requires a hostname
    (DoT) and cannot use a raw IP address.
  - **YES** for **iOS/macOS Encrypted DNS**: Apple configuration profiles
    require a hostname for TLS certificate validation.
  - **YES** for **VERT**: Requires HTTPS for secure API communication.
  - **YES** for **Privacy**: Encrypts your dashboard access and prevents browser
    warnings.
  - _Note_: If a valid certificate is found, the dashboard and LibRedirect
    settings will automatically default to using secure HTTPS links.

</details>

---

### Step 1: Get your VPN configuration

_Think of this as getting the "key" to your secret tunnel._

1.  **Create a ProtonVPN account** (if you don't have one):
    [ProtonVPN Signup](https://account.protonvpn.com/signup)
2.  Go to [ProtonVPN Downloads](https://account.protonvpn.com/downloads)
3.  Scroll down to **WireGuard configuration**
4.  Click **Create** and choose any server (Netherlands or Switzerland are good
    for privacy)
5.  **⚠️ IMPORTANT**: Ensure **NAT-PMP (Port Forwarding)** is set to **OFF**
    (see warning below)
6.  Click **Download** to save the `.conf` file
7.  **Open** the downloaded file in a text editor. You will paste its contents
    during setup

> 📝 **What you're getting**: This file contains your personal "tunnel key" that
> lets your hub connect to ProtonVPN's servers. Your real home IP stays hidden!

> ⚠️ **NAT-PMP warning**: Do **NOT** enable NAT-PMP (Port Forwarding) when
> generating your WireGuard configuration!
>
> **Why?** NAT-PMP opens a port on Proton's VPN server that forwards traffic
> directly to your Privacy Hub. This means:
>
> - Your services become **publicly accessible** on the internet
> - Anyone scanning Proton's IP ranges could find and attack your hub
> - Your home IP stays hidden, but your services are exposed to the world
>
> **Correct settings:**
>
> - ✅ NAT-PMP (Port Forwarding) = **OFF**
> - ✅ VPN Accelerator = **ON** (recommended for performance)

---

### Step 2: Get your domain token _(Mandatory)_

_This gives your hub a memorable name like `my-home.dedyn.io` instead of an IP
address._

1.  Register at [deSEC.io](https://desec.io) (it's free and privacy-focused)
2.  Verify your email and sign in
3.  Click **"+ Add Domain"** and create a subdomain (e.g.,
    `my-privacy-hub.dedyn.io`)
4.  Go to **Token Management** → **"+"** to create a new token
5.  **Copy and save this token**. You will need it during setup

> 📝 **What you're getting**: This token lets the installer automatically set up
> SSL certificates so your connection is encrypted.

> ⚠️ **Why you need this for HTTPS**: Without a domain, your browser will show
> scary "Your connection is not private" warnings because SSL certificates can
> only be issued for domain names, not IP addresses. The deSEC domain and token
> allow the installer to automatically obtain a free **Let's Encrypt**
> certificate, so your dashboard and services load securely without any browser
> warnings.
>
> **Mandatory for DNS-over-HTTPS (DoH) and DNS-over-QUIC (DoQ)**: A valid,
> globally trusted certificate is mandatory for DoH and DoQ to function
> correctly on modern devices. Without it, your phone or browser will refuse to
> use your hub as a secure DNS provider.
>
> **VERT Requirement**: VERT requires a valid HTTPS connection for secure
> communication with its daemon API (VERTd).

---

### Step 3: Download and run the installer

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

1.  **Paste your WireGuard configuration** (from Step 1)
2.  **Enter your deSEC domain and token** (from Step 2)
3.  **Choose your password preferences** (auto-generate or set your own)
4.  **Optional: GitHub credentials for Scribe** (see below)
5.  **Optional: Odido Booster integration** (for Dutch mobile users - see below)

> 📝 **About GitHub credentials (Optional)**: Scribe is a privacy-respecting
> Medium frontend that proxies GitHub gists. These credentials are **optional**
> but provide benefits:
>
> - **Without credentials**: GitHub allows 60 API requests/hour (sufficient for
>   light usage)
> - **With credentials**: Increased to 5,000 requests/hour (recommended for
>   regular use)
>
> **How to get a token:**
>
> 1. Visit [GitHub Settings → Tokens](https://github.com/settings/tokens)
> 2. Click **"Generate new token (classic)"**
> 3. Give it a name (e.g., "Privacy Hub - Scribe")
> 4. Select **only** the `gist` permission (nothing else needed!)
> 5. Click **"Generate token"** and copy it
>
> **You can also configure this after deployment** through the dashboard
> settings! The installer will ask for it, but you can skip and set it up later
> from the web interface at `http://<your-hub-ip>:8088`.

> 📱 **About Odido Booster (Optional - Dutch Mobile Users)**: Odido Booster
> automates mobile data bundle renewals for Odido/T-Mobile NL customers with
> **zero external tools required**:
>
> **How it works (all in the dashboard):**
>
> 1. Click "Generate Sign-In URL" button in the Configuration section
> 2. Click the generated URL to sign into your Odido account
> 3. After signing in, copy the callback URL you're redirected to
> 4. Paste the callback URL back into the dashboard
> 5. Click "Save" - the system automatically:
>    - Extracts and decrypts your OAuth token
>    - Retrieves your Odido User ID via API
>    - Configures monitoring for 24/7 bundle management
>
> **What you DON'T need to do:**
>
> - ❌ Download external tools (Odido.Authenticator)
> - ❌ Manually decrypt tokens
> - ❌ Find your Odido User ID
> - ❌ Configure API endpoints
> - ❌ Remember to renew bundles
>
> The entire OAuth flow is **built into the dashboard**! Everything happens
> through secure API endpoints (`/odido-exchange-token` and `/odido-userid`).
>
> **You can configure this after deployment** through the dashboard at
> `http://<your-hub-ip>:8088` under the Configuration section.

That's it! Sit back and let it build.

<a id="customization-flags"></a>

### 🛠️ Customization flags (optional)

Before running the installer, you can customize your deployment using these
flags:

| Flag | Description                                                                                                   |
| :--- | :------------------------------------------------------------------------------------------------------------ |
| `-j` | **Parallel Deploy**: Deploys services in parallel. Faster, but higher CPU usage!                              |
| `-s` | **Selective**: Install only specific apps (e.g., `-s invidious,memos`).                                       |
| `-c` | **Maintenance**: Recreates containers and networks to fix glitches while **preserving** your persistent data. |
| `-x` | **Factory Reset**: ⚠️ **Deletes everything**. Wipes all containers, volumes, and application data.            |
| `-p` | **Auto-Generate Passwords**: Generates secure passwords automatically without prompting.                      |
| `-a` | **Allow ProtonVPN**: Adds ProtonVPN domains to the AdGuard allowlist for browser extension users.             |
| `-h` | **Help**: Displays usage information and available flags.                                                     |

**Example usage:**

```bash
# Automated deployment with parallel builds
./zima.sh -j

# Selective deployment with auto-passwords
./zima.sh -s invidious,memos,searxng
```

---

### What happens next?

The installer will:

1.  **🔍 Check your system** - Makes sure Docker is installed and working
2.  **📦 Download services** - Pulls privacy apps (Invidious, Redlib, AdGuard,
    etc.)
3.  **🔐 Generate passwords** - Creates secure passwords and saves them
4.  **🚀 Start everything** - Launches all services in the background
5.  **✅ Give you a link** - Shows your dashboard URL (e.g.,
    `http://192.168.1.100:8088`)

**Total time**: 2-5 minutes depending on your internet speed.

**What you'll get**:

- 📊 **Dashboard** at `http://<your-ip>:8088` - Your control center
- 🔐 **Password file** saved to `protonpass_import.csv` - Import into your
  password manager
- 🔀 **Browser config** saved to `libredirect_import.json` - Import into
  LibRedirect extension
- 📝 **All your settings** saved to `data/AppData/privacy-hub/.secrets` - For
  backups

> 💡 **First-time tip**: Bookmark your dashboard URL immediately! You'll use it
> to access all your services.

---

---

## 🖥️ System Requirements

To ensure a smooth experience, your hub should meet these minimum
specifications:

| Component            | Minimum                                          | Recommended              | Why                                                                                        |
| :------------------- | :----------------------------------------------- | :----------------------- | :----------------------------------------------------------------------------------------- |
| **Operating System** | 64-bit Linux (ZimaOS, Ubuntu 22.04+, Debian 12+) | Same                     | Required for Docker support                                                                |
| **Processor**        | x86_64 or ARM64 (2 cores)                        | 4+ cores                 | More cores = faster builds and smoother multi-service performance                          |
| **Memory (RAM)**     | 2GB                                              | 4GB+                     | Immich and SearXNG benefit greatly from extra RAM                                          |
| **Storage**          | 16GB free on SSD/NVMe                            | 64GB+ on fast NVMe       | Fast storage improves Docker build times and service responsiveness                        |
| **Network**          | Stable internet connection                       | Wired gigabit connection | Required for deployment and updates. **Public IP only needed for remote WireGuard access** |

> 💡 **Can I use a Raspberry Pi?** Yes! The Pi 5 works great. Earlier models
> (Pi 4) work but may be slower during initial builds. Pi 3 and older are not
> recommended.

---

<details>
<summary>🛡️ <strong>How it works (Architecture)</strong> (Click to expand)</summary>

This section explains the technical details behind the privacy features listed
above.

### Recursive DNS engine (independent resolution)

This stack features a hardened, recursive DNS engine built on **Unbound** and
**AdGuard Home**, designed to eliminate upstream reliance and prevent data
leakage.

- **AdGuard Home configuration**: Generated at
  `/opt/adguardhome/conf/AdGuardHome.yaml`
- **Unbound configuration**: Generated at `/etc/unbound/unbound.conf`

<details>
<summary>🛡️ <strong>Configuration Transparency: What We Change and Why</strong> (Click to expand)</summary>

This section documents **every setting** we modify from defaults to ensure
complete transparency. You own this system - you deserve to know exactly what it
does.

---

### 🔧 Unbound (Recursive DNS Resolver)

**Where configured**:
[`lib/services/config.sh:455-477`](lib/services/config.sh#L455)

Unbound is your personal DNS resolver. Instead of asking Google or Cloudflare
"where is youtube.com?", Unbound asks the authoritative root servers directly.
We harden it beyond default settings for maximum privacy and security.

#### Network Settings

```ini
interface: 0.0.0.0              # Listen on all container interfaces
port: 53                        # Standard DNS port
access-control: 172.16.0.0/12 allow    # Allow Docker networks
access-control: 192.168.0.0/16 allow   # Allow home networks
access-control: 10.0.0.0/8 allow       # Allow private networks
access-control: 0.0.0.0/0 refuse       # Deny everything else
```

**Why**: Only your local devices can use this DNS resolver. Internet scanners
get silently refused.

#### Privacy & Security Hardening

```ini
qname-minimisation: yes         # RFC 7816 - Only send minimal query info
aggressive-nsec: yes            # RFC 8198 - Faster DNSSEC validation
use-caps-for-id: yes            # DNS 0x20 - Randomize case to prevent poisoning
hide-identity: yes              # Don't reveal server identity
hide-version: yes               # Don't reveal Unbound version
minimal-responses: yes          # RFC 4472 - Send only necessary data
```

**Why**:

- `qname-minimisation`: When you look up `mail.google.com`, Unbound only asks
  the `.com` server about `google.com`, not the full query. This prevents DNS
  servers from building a profile of your browsing.
- `use-caps-for-id`: Randomizes capitalization (e.g., `GoOgLe.CoM`) to make DNS
  spoofing attacks exponentially harder.
- `hide-*`: Prevents fingerprinting your DNS resolver.

#### DNSSEC Validation

```ini
auto-trust-anchor-file: "/var/unbound/root.key"  # RFC 5011
harden-glue: yes                # RFC 1034 - Prevent cache poisoning
harden-dnssec-stripped: yes     # Require DNSSEC if present
harden-algo-downgrade: yes      # Prevent downgrade attacks
harden-large-queries: yes       # Block potential DoS queries
harden-short-bufsize: yes       # Require proper buffer sizes
```

**Why**: DNSSEC is like HTTPS for DNS - it proves the answer you got is
authentic and hasn't been tampered with. These settings enforce it strictly.

#### Performance Optimization

```ini
prefetch: yes                   # Refresh popular records before expiry
rrset-roundrobin: yes           # RFC 1794 - Load balance between servers
```

**Why**: `prefetch` means frequently-accessed sites load faster because Unbound
refreshes their DNS records before they expire.

---

### 🛡️ AdGuard Home (DNS Filtering & Encrypted DNS)

**Where configured**:
[`lib/services/config.sh:479-489`](lib/services/config.sh#L479)

AdGuard Home sits in front of Unbound and adds ad-blocking, encrypted DNS
support, and per-device filtering.

#### Core Settings

```yaml
schema_version: 29 # AdGuard Home config version
http:
  address: 0.0.0.0:8083 # Web UI port (customizable)

users:
  - name: "adguard" # Default username
    password: "<bcrypt-hash>" # Auto-generated secure password

dns:
  bind_hosts: ["0.0.0.0"] # Listen on all interfaces
  port: 53 # Standard DNS port
  dot_port: 853 # DNS-over-TLS port
  quic_port: 853 # DNS-over-QUIC port
```

**Why**: We bind to all interfaces so Docker containers and your LAN devices can
reach it. The password is auto-generated and saved to your `.secrets` file.

#### Upstream DNS Configuration

```yaml
upstream_dns: ["172.x.0.250"] # Your local Unbound instance
bootstrap_dns: ["172.x.0.250"] # Used to resolve upstream addresses
```

**Why**: **Every DNS query** goes through your private Unbound resolver first.
This means:

- ✅ No data sent to Google (8.8.8.8), Cloudflare (1.1.1.1), or any third party
- ✅ You query root DNS servers directly
- ✅ Complete independence from DNS providers

#### Encrypted DNS (DoT, DoH, DoQ)

```yaml
tls:
  enabled: true
  server_name: "<your-domain>.dedyn.io"
  certificate_path: "/opt/adguardhome/conf/ssl.crt"
  private_key_path: "/opt/adguardhome/conf/ssl.key"
```

**Why**: With a valid Let's Encrypt certificate, your phone and laptop can use
your hub as a secure DNS resolver from anywhere using:

- **DNS-over-TLS (DoT)**: Port 853
- **DNS-over-HTTPS (DoH)**: `https://<your-domain>.dedyn.io/dns-query`
- **DNS-over-QUIC (DoQ)**: Port 853 (faster on mobile networks)

#### Filtering & Blocklists

```yaml
filters:
  - enabled: true
    url: "https://raw.githubusercontent.com/Lyceris-chan/dns-blocklist-generator/main/hagezi-pro-plus.txt"
    name: "Hagezi Pro++ (Dutch-Optimized)"
```

**Where managed**: Blocklists are auto-updated by AdGuard Home every 24 hours.

**Why**: Blocks ads, trackers, malware domains, and telemetry at the network
level. Based on Hagezi Pro++ with Dutch-specific optimizations.

---

### 🔍 SearXNG (Private Search Engine)

**Where configured**:
[`lib/services/config.sh:558-567`](lib/services/config.sh#L558)

SearXNG aggregates results from multiple search engines without tracking you.

#### Settings Applied

```yaml
use_default_settings: true # Use SearXNG's sane defaults
server:
  secret_key: "<random-64-char>" # Session encryption key
  base_url: "http://<your-ip>:8082/"
  image_proxy: true # Proxy all images through SearXNG
search:
  safe_search: 0 # No filtering (your choice)
  autocomplete: "duckduckgo" # Autocomplete provider
```

**Why**:

- `image_proxy: true`: When you search for images, SearXNG fetches them from
  Google/Bing on your behalf. The source sites never see your IP address.
- **VPN Routing**: SearXNG runs inside the VPN tunnel, so search engines see
  thousands of users sharing one IP, making individual tracking impossible.

---

### 📝 Scribe (Medium Frontend)

**Where configured**:
[`lib/services/config.sh:541-547`](lib/services/config.sh#L541)

Scribe proxies Medium articles without tracking or paywalls.

#### Settings Applied

```env
SECRET_KEY_BASE=<random-64-char>  # Session encryption
GITHUB_USER=<your-username>       # Optional: For GitHub Gist API
GITHUB_TOKEN=<your-pat-token>     # Optional: Increases rate limit
PORT=8280
APP_DOMAIN=<your-ip>:8280
```

**Why**:

- **GitHub credentials are optional**: Without them, you get 60 Gist API
  requests/hour. With them, you get 5,000/hour.
- **VPN Routing**: All requests to Medium go through the VPN tunnel, hiding your
  home IP.

---

### 📱 Odido Booster (Automated Mobile Data Management)

**Where configured**:

- Dashboard UI:
  [`lib/templates/dashboard.html:380-420`](lib/templates/dashboard.html#L380)
- Token Exchange:
  [`lib/src/hub-api/app/routers/system.py:552-622`](lib/src/hub-api/app/routers/system.py#L552)
- User ID Extraction:
  [`lib/src/hub-api/app/routers/system.py:625-675`](lib/src/hub-api/app/routers/system.py#L625)
- Background Service:
  [`lib/src/hub-api/app/services/background.py:64-122`](lib/src/hub-api/app/services/background.py#L64)

Odido Booster automates mobile data bundle renewals for Odido/T-Mobile NL
customers, eliminating manual intervention and external tools.

#### Integrated OAuth Flow (No External Tools Needed!)

The Privacy Hub **replicates the complete Odido.Authenticator workflow**
directly in the dashboard:

**How it works:**

1. **Generate Sign-In URL**: Dashboard creates OAuth URL with proper parameters
   ```javascript
   https://www.odido.nl/login?client_id=OdidoMobileApp&redirect_uri=...
   ```
2. **User Signs In**: User clicks URL → Signs into Odido → Gets redirected to
   callback URL
3. **Extract Token**: User pastes callback URL back into dashboard
4. **Token Exchange** (`/odido-exchange-token`):
   - Decodes base64-encoded callback token
   - Extracts refresh token from JSON payload
   - Exchanges refresh token for OAuth access token via
     `https://login.odido.nl/connect/token`
5. **User ID Extraction** (`/odido-userid`):
   - Makes authenticated request to `https://capi.odido.nl/account/current`
   - Follows redirect to extract 12-char hex User ID from URL pattern:
     `capi.odido.nl/{userid}/account/current`
6. **Save Configuration**: Both OAuth token and User ID saved to `.secrets`
7. **Background Monitoring**: Service monitors data usage every hour

**Why this approach:**

- ✅ **No external tools**: Entire OAuth flow built into dashboard
- ✅ **Zero manual configuration**: No need to find User ID or decrypt tokens
- ✅ **Secure**: OAuth token never leaves your network
- ✅ **Automatic**: Background service runs 24/7
- ✅ **VPN-routed**: All API requests go through Gluetun tunnel by default
- ✅ **Transparent**: All steps logged for full visibility

#### Settings Applied

```env
ODIDO_TOKEN="<oauth-token>"              # From Odido.Authenticator
ODIDO_USER_ID="<12-char-hex>"           # Auto-extracted via API
ODIDO_BUNDLE_CODE="A0DAY01"             # Default: 1GB/day bundle
ODIDO_ABSOLUTE_MIN_THRESHOLD_MB=100     # Trigger renewal at 100MB
ODIDO_LEAD_TIME_MINUTES=30              # Renew 30min before expiry
```

**Where managed**: Configuration is done through the dashboard at
`http://<your-ip>:8088`. All settings are stored in
`data/AppData/privacy-hub/.secrets`.

**Background Service**:

- Checks for missing User ID every hour
- Automatically retries User ID extraction if token exists but User ID is
  missing
- Logs all operations to the structured logging system

---

### 🌐 Gluetun (VPN Gateway)

**Where configured**:
[`lib/services/compose.sh:149-180`](lib/services/compose.sh#L149)

Gluetun creates the VPN tunnel that privacy services route through.

#### Settings Applied

```env
VPN_SERVICE_PROVIDER=custom     # Using your ProtonVPN config
VPN_TYPE=wireguard              # Modern, fast VPN protocol
DNS_UPSTREAM_RESOLVERS=quad9    # Gluetun's DNS (not yours!)
FIREWALL_VPN_INPUT_PORTS=8888   # Allow HTTP proxy for asset downloads
HTTPPROXY=on                    # Enable HTTP proxy
HTTPPROXY_LISTENING_ADDRESS=:8888
```

**Why**:

- `DNS_UPSTREAM_RESOLVERS=quad9`: This is **only for Gluetun's internal needs**
  (e.g., resolving VPN server addresses). Your actual browsing DNS goes through
  Unbound/AdGuard.
- `HTTPPROXY`: Used once during setup to download dashboard assets (fonts,
  icons) through the VPN so CDNs never see your home IP.

---

### 🔐 What We DON'T Change

To maintain transparency, here's what we **don't** modify:

- **Container base images**: We use official upstream images (e.g.,
  `adguard/adguardhome:latest`)
- **Service application logic**: No patched or forked source code (except local
  builds for hardware compatibility)
- **Browser behavior**: No browser extensions or modifications
- **Your files**: Your photos, documents, and media are never touched

</details>

### 🔍 Why self-host? (the "trust gap")

If you don't own the hardware and the code running your network, you don't own
your privacy.

- **The Google profile**: Google's DNS (8.8.8.8) turns you into a data source
  for profiling your health, finances, and interests.
- **The Cloudflare illusion**: Even "neutral" providers can be forced to censor
  or log content.
- **ISP predation**: ISPs log and sell your browsing history to data brokers.
- **Search engine isolation**: By routing **SearXNG** through the VPN tunnel,
  upstream search engines (Google, Bing) see queries coming from a generic VPN
  IP shared by thousands, making it impossible to profile your individual search
  behavior or serve targeted ads.

> 📚 **Trusted sources**: For more on why these measures matter, see the **EFF's
> [Surveillance Self-Defense](https://ssd.eff.org/)** and their guide on
> **[DNS Privacy](https://www.eff.org/deeplinks/2020/12/dns-privacy-all-way-root-your-lan)**.

---

<a id="dashboard--services"></a>

## 🖥️ Dashboard and services

Access your unified control center at `http://<LAN_IP>:8088`.

### 🔑 WireGuard client management

Connect your devices securely to your home network:

1.  **Add client**: Click "New client" in the dashboard.
2.  **Connect mobile**: Click the **QR code** icon and scan it with the
    WireGuard app on your phone.
3.  **Connect desktop**: Download the `.conf` file and import it into your
    WireGuard client.

### 🔐 Credential management

The system generates secure, unique credentials for all core infrastructure
during installation.

| Service                  | Default username | Password type  | Note                                      |
| :----------------------- | :--------------- | :------------- | :---------------------------------------- |
| **Management Dashboard** | `admin`          | Auto-generated | Protects the main control plane.          |
| **AdGuard Home**         | `adguard`        | Auto-generated | DNS management and filtering rules.       |
| **WireGuard (web UI)**   | `admin`          | Auto-generated | Required to manage VPN peers and clients. |
| **Portainer**            | `portainer`      | Auto-generated | System-level container orchestration.     |
| **Odido Booster**        | `admin`          | Auto-generated | API key for mobile data automation.       |

> 📁 **Where are they?**: All generated credentials are saved to
> `data/AppData/privacy-hub/.secrets` and exported to
> `data/AppData/privacy-hub/protonpass_import.csv` for easy importing into your
> password manager.

### 🔀 LibRedirect Integration (Auto-Redirect to Your Hub)

**What it does**: Automatically sends you to your private services instead of
big-tech sites. For example, when you click a YouTube link, it opens in your
Invidious instead!

**How to set it up**:

1.  **Install the extension**:
    [Firefox](https://addons.mozilla.org/en-US/firefox/addon/libredirect/) |
    [Chrome](https://chromewebstore.google.com/detail/libredirect/pobhoodpcdojmedmielocclicpfbednh)
2.  **Open extension settings** → Click the LibRedirect icon → **Options**
3.  **Import your config** → Go to **"Import/Export"** tab → Click **"Import"**
    → Select `libredirect_import.json` from your project folder
4.  **Done!** Your browser now automatically redirects:
    - YouTube → Invidious
    - Reddit → Redlib
    - Wikipedia → Wikiless
    - Medium → Scribe
    - Imgur → Rimgo

> 📝 **Can't find the file?** It's created in your project folder after
> deployment completes. Look for `libredirect_import.json` in the
> `selfhost-stack` directory.

### Included Privacy Services

This Privacy Hub includes 20+ self-hosted services designed to protect your
privacy and digital independence. All services are open-source and run entirely
on your hardware.

#### 🔐 How WireGuard Protects Your Privacy

**WireGuard creates a secure encrypted tunnel** that allows you to access your
self-hosted services from anywhere in the world. When you're connected:

- **Encryption**: All traffic between your device and home network is encrypted
  with state-of-the-art cryptography
- **Secure Remote Access**: Access your DNS filtering, private frontends, and
  services securely from coffee shops, hotels, or anywhere
- **Split Tunneling**: Only DNS queries and hub services route through the
  tunnel--your other traffic exits directly for maximum speed
- **No Exposure**: Your services remain invisible to the public internet; only
  devices with valid WireGuard keys can connect
- **Privacy in Transit**: Even on untrusted networks, your DNS queries and
  service requests are protected from snooping

**Why this matters**: Without WireGuard, accessing your hub remotely would
require exposing multiple ports to the internet, creating security risks.
WireGuard provides a single, encrypted gateway that keeps everything else locked
down.

<details>
<summary>📋 <strong>Complete Service Catalog</strong> (Click to expand)</summary>

Services marked with 🔒 are routed through the VPN tunnel, hiding your home IP
from upstream providers.

#### Privacy Frontends (VPN-Protected 🔒)

| Service                                                                  | What It Does                                      | Why Use It                                                                                                                           | Source & Privacy                                                                                                                                                    |
| :----------------------------------------------------------------------- | :------------------------------------------------ | :----------------------------------------------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **[Invidious](https://github.com/iv-org/invidious)**                     | Privacy-respecting YouTube frontend               | Watch YouTube without Google tracking, no ads, no "disable your ad blocker" nags, server-side video fetching prevents fingerprinting | [Source](https://github.com/iv-org/invidious) · [Image](https://quay.io/invidious/invidious) · No tracking                                                          |
| **[Redlib](https://github.com/redlib-org/redlib)**                       | Privacy-friendly Reddit frontend (Libreddit fork) | Browse Reddit without tracking cookies, no "Open in App" nags, JavaScript-free, faster page loads                                    | [Source](https://github.com/redlib-org/redlib) · [Image](https://quay.io/redlib/redlib) · No tracking                                                               |
| **[SearXNG](https://github.com/searxng/searxng)**                        | Privacy-respecting metasearch engine              | Search without profiling--aggregates results from multiple engines while hiding your identity                                        | [Source](https://github.com/searxng/searxng) · [Image](https://hub.docker.com/r/searxng/searxng) · [Privacy](https://docs.searxng.org/own-instance.html)            |
| **[Wikiless](https://codeberg.org/orenom/wikiless)**                     | Privacy-focused Wikipedia frontend                | Read Wikipedia without tracking, faster loading, no telemetry                                                                        | [Source](https://codeberg.org/orenom/wikiless) · Self-built · No tracking                                                                                           |
| **[Scribe](https://git.sr.ht/~edwardloveall/scribe)**                    | Privacy-friendly Medium reader                    | Read Medium articles without paywalls, tracking, or JavaScript bloat                                                                 | [Source](https://git.sr.ht/~edwardloveall/scribe) · Self-built · No tracking                                                                                        |
| **[Rimgo](https://codeberg.org/rimgo/rimgo)**                            | Privacy-respecting Imgur frontend                 | View Imgur images without tracking cookies or ads                                                                                    | [Source](https://codeberg.org/rimgo/rimgo) · [Image](https://codeberg.org/rimgo/-/packages) · No tracking                                                           |
| **[BreezeWiki](https://github.com/breezewiki/breezewiki)**               | Alternative Fandom wiki frontend                  | Read Fandom wikis without invasive ads, tracking, or slow JavaScript                                                                 | [Source](https://github.com/breezewiki/breezewiki) · [Image](https://quay.io/pussthecatorg/breezewiki) · No tracking                                                |
| **[AnonymousOverflow](https://github.com/httpjamesm/AnonymousOverflow)** | Privacy-focused Stack Overflow viewer             | View Stack Overflow content without tracking or user profiling                                                                       | [Source](https://github.com/httpjamesm/AnonymousOverflow) · [Image](https://github.com/httpjamesm/AnonymousOverflow/pkgs/container/anonymousoverflow) · No tracking |

#### Productivity & Media Tools (VPN-Protected 🔒)

| Service                                            | What It Does                                                 | Why Use It                                                                                                  | Source & Privacy                                                                                                                                                                                           |
| :------------------------------------------------- | :----------------------------------------------------------- | :---------------------------------------------------------------------------------------------------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **[Cobalt](https://github.com/imputnet/cobalt)**   | Universal media downloader                                   | Download videos from YouTube, TikTok, Twitter, and more without tracking or rate limits                     | [Source](https://github.com/imputnet/cobalt) · [Image](https://github.com/imputnet/cobalt/pkgs/container/cobalt) · No tracking                                                                             |
| **[Immich](https://github.com/immich-app/immich)** | Self-hosted photo & video backup (Google Photos alternative) | Keep your photos private with on-device ML tagging, no cloud surveillance, hardware-accelerated transcoding | [Source](https://github.com/immich-app/immich) · [Image](https://github.com/immich-app/immich/pkgs/container/immich-server) · [Privacy](https://immich.app/docs/overview/introduction) · Fully self-hosted |
| **[Memos](https://github.com/usememos/memos)**     | Privacy-first lightweight note-taking                        | Quick notes and journaling with full ownership of your data                                                 | [Source](https://github.com/usememos/memos) · [Image](https://github.com/usememos/memos/pkgs/container/memos) · Fully self-hosted                                                                          |
| **[VERT](https://github.com/vert-sh/vert)**        | Open-source video transcoding                                | Convert and optimize videos locally with GPU acceleration--no cloud processing                              | [Source](https://github.com/vert-sh/vert) · [Image](https://github.com/vert-sh/vert/pkgs/container/vert) · Local processing only                                                                           |

#### Core Infrastructure (Local Network 🏠)

| Service                                                        | What It Does                                  | Why Use It                                                                                                                      | Source & Privacy                                                                                                                                                 |
| :------------------------------------------------------------- | :-------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------ | :--------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **[AdGuard Home](https://github.com/AdguardTeam/AdGuardHome)** | Network-wide ad & tracker blocking DNS server | Block ads and trackers for every device on your network (phones, tablets, smart TVs)                                            | [Source](https://github.com/AdguardTeam/AdGuardHome) · [Image](https://hub.docker.com/r/adguard/adguardhome) · [Privacy](https://adguard.com/en/privacy.html)    |
| **[Unbound](https://github.com/NLnetLabs/unbound)**            | Recursive DNS resolver                        | Query DNS root servers directly--no Google (8.8.8.8) or Cloudflare logging your browsing history                                | [Source](https://github.com/NLnetLabs/unbound) · [Image](https://hub.docker.com/r/klutchell/unbound) · No external queries                                       |
| **[WG-Easy](https://github.com/wg-easy/wg-easy)**              | WireGuard VPN management interface            | Easy WireGuard setup with QR codes for instant mobile connection                                                                | [Source](https://github.com/wg-easy/wg-easy) · [Image](https://github.com/wg-easy/wg-easy/pkgs/container/wg-easy) · Self-hosted VPN                              |
| **[Gluetun](https://github.com/qdm12/gluetun)**                | VPN client container                          | Routes privacy frontend traffic through commercial VPN providers (supports 40+ providers including Mullvad, ProtonVPN, NordVPN) | [Source](https://github.com/qdm12/gluetun) · [Image](https://hub.docker.com/r/qmcgaw/gluetun) · No data collection                                               |
| **[Portainer](https://github.com/portainer/portainer)**        | Container management UI                       | Manage Docker containers through a web interface                                                                                | [Source](https://github.com/portainer/portainer) · [Image](https://hub.docker.com/r/portainer/portainer-ce) · [Privacy](https://www.portainer.io/privacy-policy) |
| **[Watchtower](https://github.com/containrrr/watchtower)**     | Automatic container updates                   | Keeps your services up-to-date with security patches automatically                                                              | [Source](https://github.com/containrrr/watchtower) · [Image](https://hub.docker.com/r/containrrr/watchtower) · No external communication except image pulls      |
| **Dashboard**                                                  | Unified control center                        | Material Design 3 dashboard for managing all services, monitoring system health, and viewing logs                               | Local build · No telemetry                                                                                                                                       |
| **Hub API**                                                    | Control plane orchestration                   | FastAPI backend providing service management, health monitoring, and WireGuard integration                                      | Local build · No telemetry                                                                                                                                       |

#### Optional Services

| Service                                                                   | What It Does                                                | Why Use It                                                                                                          | Source & Privacy                                                                                 |
| :------------------------------------------------------------------------ | :---------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------ | :----------------------------------------------------------------------------------------------- |
| **[Odido Booster](https://github.com/Lyceris-chan/odido-bundle-booster)** | Automated mobile data bundle management (Odido NL provider) | Automatically activates data bundles when approaching limits--specific to Odido mobile customers in the Netherlands | [Source](https://github.com/Lyceris-chan/odido-bundle-booster) · Self-built · No data collection |

---

**Key Privacy Notes:**

- **🔒 VPN-Protected Services**: Route all external requests through your
  commercial VPN (Gluetun). Upstream providers (YouTube, Reddit, etc.) only see
  the VPN's IP address, not your home IP
- **🏠 Local Services**: Run entirely on your network--no external communication
  except for updates and DNS blocklists
- **No Telemetry**: None of these services send usage data, analytics, or
  telemetry to third parties
- **Full Source Availability**: Every service is open-source and auditable
- **Data Ownership**: Your data stays on your hardware--you are not the product

**Privacy Policy Repository Links:**

- AdGuard Home: https://adguard.com/en/privacy.html
- Portainer: https://www.portainer.io/privacy-policy
- SearXNG: https://docs.searxng.org/own-instance.html
- Immich: https://immich.app/docs/overview/introduction
- All other services: Self-hosted with no external data collection

</details>

### 🔄 Updates and lifecycle

This stack employs a dual-strategy for keeping your services secure and
up-to-date.

#### 1. Automated updates (Watchtower)

For services using pre-built Docker images (like **AdGuard**, **Invidious**,
**Redlib**), updates are fully automated.

- **Mechanism**: **Watchtower** checks for new upstream images every hour.
- **Action**: If a new image is found, Watchtower seamlessly restarts the
  container with the new version.
- **Notification**: Updates are reported to the **Hub API** and logged in the
  dashboard's event log, so you always know when a service has been patched.

#### 2. Source-built updates (manual)

For services built securely from source code to ensure hardware compatibility
(like **Wikiless**, **Scribe**, **Odido Booster**):

- **Mechanism**: These do not update automatically to prevent build breakages.
- **Notification**: The dashboard will show an "Update available" badge when the
  upstream source code changes.
- **Action**:
  1.  Sign in to the dashboard as administrator.
  2.  Open the **Service settings**.
  3.  Click **"Update service"**.
  4.  The system will pull the latest source code, rebuild the container in the
      background, and restart it once ready.

> **Note**: All "frontend" services (and Immich, SearXNG, and Cobalt) are routed
> through the VPN tunnel automatically. VERT and core management tools are
> strictly local-only.

### ⚡ Hardware acceleration (GPU and QSV)

To ensure peak performance for media-heavy tasks, this stack supports
hardware-accelerated transcoding and machine learning:

<details>
<summary>🚀 <strong>View hardware acceleration details</strong> (Click to expand)</summary>

- **Immich**: Utilizes Intel Quick Sync (QSV), VA-API, or NVIDIA GPUs for
  localized image auto-tagging and video transcoding.
- **VERT / VERTd**: Optimized for high-speed local file conversion using
  hardware encoders to minimize CPU load. **Note: VERT requires an HTTPS
  connection to securely communicate with VERTd.**
- **Detection and provisioning**: The stack automatically identifies your
  hardware vendor (Intel, AMD, or NVIDIA) during deployment via
  [lib/scripts.sh](lib/scripts.sh) and provisions the necessary devices
  (`/dev/dri`, `/dev/vulkan`) or container reservations.
- **Requirements**: Ensure your ZimaOS or host device has the correct drivers
  installed (e.g., `intel-media-driver` or `nvidia-container-toolkit`).

</details>

---

<details>
<summary>🌐 <strong>Network & Advanced Configuration</strong> (Click to expand)</summary>

## 🌐 Network configuration

These settings help you get the most out of your Privacy Hub on your local
network.

#### 1. Remote access and split-tunneling

**Stop: you probably do not need to do anything here.**

- **Default state**: Your hub remains invisible to the internet. This is the
  safest way to live.
- **Remote access**: Forward **UDP port 51820** on your router only if you want
  to connect to your hub while away from home. Valid public/private keys are
  required for access.
- **Split-tunneling**: We use split-tunneling to ensure your connection remains
  fast. Only DNS requests and hub services route through the tunnel, while other
  traffic exits directly from your device.
- **Why no other ports?**: Every other service (Dashboard, AdGuard, etc.) is
  reached through this WireGuard tunnel once you are connected. Opening more
  ports is like leaving your back door open when you already have a key to the
  front door. This is essential for users to securely access their DNS and
  services outside their home network.

#### 2. DNS protection

Your hub runs its own **recursive DNS resolver** (Unbound and AdGuard Home).
This means:

- **No third-party DNS**: Your queries go directly to authoritative root
  servers, not Google or Cloudflare.
- **Built-in ad blocking**: Network-wide filtering for all devices on your
  network.
- **Encrypted queries**: Supports DNS-over-TLS, DNS-over-HTTPS, and
  DNS-over-QUIC.

To use it, point your router's DHCP settings to hand out your hub's IP as the
DNS server for all devices.

#### 3. Split tunnel architecture

This stack uses a **dual split tunnel** architecture to balance privacy,
performance, and reliability. Traffic is intelligently routed through three
distinct zones:

<details>
<summary>🗺️ <strong>View routing zones and logic</strong> (Click to expand)</summary>

##### Zone 1: VPN-isolated services (Gluetun tunnel)

Privacy frontends and external-facing services are routed exclusively through
the VPN tunnel:

| Service          | Purpose                | Benefit                                                    |
| :--------------- | :--------------------- | :--------------------------------------------------------- |
| **Invidious**    | YouTube frontend       | Prevents Google from linking your home IP to video watches |
| **Companion**    | Invidious helper       | Enhanced video retrieval through VPN                       |
| **Redlib**       | Reddit frontend        | Stops Reddit tracking and "Open in App" harassment         |
| **SearXNG**      | Meta search engine     | Search queries anonymized through shared VPN IP            |
| **Wikiless**     | Wikipedia frontend     | Removes Wikimedia cross-site tracking                      |
| **Rimgo**        | Imgur frontend         | Anonymous image viewing                                    |
| **BreezeWiki**   | Fandom frontend        | Blocks aggressive ad networks                              |
| **AnonOverflow** | StackOverflow frontend | Developer research without corporate profiling             |
| **Scribe**       | Medium frontend        | Paywall bypass and tracking removal                        |
| **Immich**       | Photo management       | ML model downloads and metadata fetched via VPN\*          |
| **Cobalt**       | Media downloader       | Downloads anonymized through VPN                           |
| **Memos**        | Note taking            | Version checks and metadata fetched via VPN                |

**Kill switch protection**: If the VPN tunnel fails, these services lose
internet access entirely. They cannot accidentally expose your home IP.

##### Zone 2: Remote access (WireGuard tunnel)

When connecting from outside your home network (phone, laptop), traffic flows
through your personal WireGuard tunnel:

- **DNS requests** → Routed to your home AdGuard for ad-blocking everywhere
- **Hub services** → Direct access to your dashboard and private apps
- **Other internet traffic** → Exits directly from your device (not routed home)

**Benefit**: Your phone stays fast (Netflix doesn't lag) while you still get
network-wide ad-blocking and access to your private services.

##### Zone 3: Local-only services

Management tools and utilities that never touch the internet:

| Service                 | Purpose                | Why local                               |
| :---------------------- | :--------------------- | :-------------------------------------- |
| **Dashboard**           | Unified control center | No external dependencies                |
| **AdGuard Home**        | DNS filtering          | Must be accessible even if VPN fails    |
| **Portainer**           | Container management   | Security-critical, no external exposure |
| **VERT / VERTd**        | File conversion        | GPU-accelerated, all processing local   |
| **Unbound**             | Recursive DNS          | Talks directly to root servers          |
| **WireGuard (wg-easy)** | VPN server             | Manages your remote access peers        |

_\*Immich uses VPN only for ML model downloads and external metadata; your
photos remain strictly local._

</details>

---

<a id="advanced-setup"></a>

## 📡 Advanced setup: OpenWrt and double NAT

If you are running a real router like **OpenWrt** behind your ISP modem, you are
in a **double NAT** situation. You need to fix the routing so your packets
actually arrive.

### OpenWrt Static IP and WAN configuration

- **Static hub lease**: Assign a static lease on your **OpenWrt** router so your
  Privacy Hub remains at a fixed internal IP (e.g., `192.168.69.206`).
- **Static router WAN**: In a double NAT setup (ISP Modem -> OpenWrt -> Hub),
  ensure your OpenWrt router has a **static IP** (e.g., `192.168.1.209`)
  assigned by the ISP modem on its WAN interface. This ensures the port
  forwarding rule on the ISP modem remains stable.

<details>
<summary>💻 <strong>CLI: UCI commands for static lease</strong> (Click to expand)</summary>

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

### OpenWrt Port forwarding and firewall

OpenWrt is the gatekeeper. Point the traffic to your machine and then actually
open the door.

<details>
<summary>💻 <strong>CLI: UCI commands for firewall</strong> (Click to expand)</summary>

```bash
# 1. Add port forwarding (Replace dest_ip with your ZimaOS machine's IP)
uci add firewall redirect
uci set firewall.@redirect[-1].name='Forward-WireGuard'
uci set firewall.@redirect[-1].src='wan'
uci set firewall.@redirect[-1].proto='udp'
uci set firewall.@redirect[-1].src_dport='51820'
uci set firewall.@redirect[-1].dest_ip='192.168.69.206' # <--- HUB LAN IP
uci set firewall.@redirect[-1].dest_port='51820'
uci set firewall.@redirect[-1].target='DNAT'

# 2. Add traffic rule (allowance)
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

### OpenWrt DNS hijacking (force compliance)

Some devices (IoT, smart TVs) hardcode DNS servers (like `8.8.8.8`) to bypass
your filters. You can force them to comply using a **NAT redirect** rule.

To implement this on your router, refer to the following official guides:

- [OpenWrt Guide: Intercepting DNS](https://openwrt.org/docs/guide-user/firewall/fw3_configurations/intercept_dns)
  (Step-by-step NAT redirection)
- [OpenWrt Guide: Blocking DoH (banIP)](https://openwrt.org/docs/guide-user/firewall/firewall_configuration/ban_ip)
  (Preventing filter bypass via encrypted DNS)

### 🛡️ Privacy and architecture

#### Minimalist source strategy

To ensure maximum security and stability, this stack prioritizes official
pre-built images for the majority of its services. Only a small number of core
components and specific frontends are built from source locally:

- **Core logic**: The Hub API and Odido Booster are built from local sources to
  ensure perfect integration with the host environment.
- **Selected frontends**: Services like Wikiless and Scribe are built from their
  respective upstream repositories, ensuring you get the exact code intended by
  the developers while benefiting from local image optimization.

#### Dual-zone split tunneling

The stack implements an intelligent routing model to balance performance and
total privacy:

- **🔒 VPN zone (kill-switch protected)**: Services like Invidious, SearXNG, and
  Redlib are locked inside the VPN. If the tunnel drops, they lose all
  connectivity instantly, preventing any IP leaks.
- **🏠 Home zone (direct access)**: Management tools (Dashboard, AdGuard,
  Portainer) are accessible directly via your LAN IP or WireGuard remote access
  tunnel for maximum reliability.

#### DNS subdomain mapping and HTTPS

When a **deSEC** domain is configured, the system automatically provisions:

- **Wildcard DNS rewrites**: `*.yourdomain.dedyn.io` resolves automatically to
  your hub's internal IP.
- **Nginx subdomain routing**: Each service is reachable via its own secure
  subdomain (e.g., `invidious.yourdomain.dedyn.io`).
- **End-to-end encryption**: Valid Let's Encrypt certificates are automatically
  managed and applied to all subdomain endpoints on port `8443`.

#### Unified deployment and continuous updates

This stack uses a **unified deployment** model combined with **Watchtower** for
automated updates, ensuring you always have the latest privacy fixes without
manual intervention.

- **Latest-stable strategy**: By default, all service frontends pull the
  `latest` stable image.
- **Automated lifecycle**: Watchtower monitors your containers and performs
  graceful restarts when new upstream security patches are released.
- **Single-stage verification**: The integrated test suite verifies the entire
  stack in one pass, ensuring inter-service dependencies are validated.

#### Human-Readable Event Logging

To simplify system administration, the dashboard includes a real-time event
stream that translates technical API logs into human-readable actions.

- **Intelligent Translation**: Technical events (e.g., `POST /verify-admin`) are
  automatically humanized (e.g., "Administrative session authorized") before
  being displayed.
- **Categorized Auditing**: Logs are tagged by category (Network, Security,
  Maintenance, Orchestration) with corresponding Material Design icons for rapid
  visual scanning.
- **Live Stream**: The dashboard maintains a persistent EventSource connection
  to the Hub API, ensuring zero-latency visibility into system operations.

#### Zero-leaks asset architecture

External assets (fonts, icons, scripts) are fetched once via the **Gluetun VPN
proxy** and served locally. Your public home IP is never exposed to CDNs.

**Privacy enforcement logic:**

1.  **Container initiation**: When the Hub API container starts, it initiates an
    asset verification check.
2.  **Proxy routing**: If assets are missing, the Hub API routes download
    requests through the Gluetun VPN container (acting as an HTTP proxy on port
    8888).
3.  **Encapsulated fetching**: All requests to external CDNs occur _inside_ the
    VPN tunnel. Upstream providers only see the VPN IP.
4.  **Local persistence**: Assets are saved to a persistent Docker volume
    (`/assets`).
5.  **Offline serving**: The Management Dashboard serves all UI resources
    exclusively from this local volume.

#### Backup and Portability

The stack includes an integrated backup and restoration engine designed for
maximum portability and data sovereignty.

- **One-Click Backups**: Generate timestamped `.tar.gz` archives of all system
  secrets, environment variables, and core configurations directly from the
  dashboard.
- **State Restoration**: Restore your entire system state from any valid backup
  archive. The system automatically handles file extraction and triggers a
  stack-wide restart to apply restored settings.
- **Portability**: Backups are independent of hardware and can be used to
  migrate your privacy hub to a new host device by simply restoring the archive
  on a fresh installation.

---

### 🛡️ Blocklist information & DNS Filtering

- **Source**: Blocklists are generated using the
  [Lyceris-chan DNS Blocklist Generator](https://github.com/Lyceris-chan/dns-blocklist-generator/).
- **Composition**: Based on **Hagezi Pro++**, curated for performance and dutch
  users.
- **Note**: This blocklist is **aggressive** by design.

### 🛡️ Deployment strategy

This stack uses a hybrid deployment model to balance privacy with system
stability.

- **Pre-built Images**: Most services use trusted upstream images to ensure fast
  deployment and reliable updates.
- **Local Optimization**: Critical orchestration components and selected
  frontends are optimized for your environment through local builds.

### 🛡️ Self-healing & High availability

- **VPN Monitoring**: Gluetun is continuously monitored. Docker restarts the
  gateway if the tunnel stalls.
- **Frontend Auto-Recovery**: Privacy frontends utilize `restart: always`.
- **Health-Gated Launch**: Infrastructure services must be `healthy` before
  frontends start.

### Data minimization & anonymity

- **Specific User-Agent Signatures**: Requests use industry-standard signatures
  to blend in.
- **Zero Personal Data**: No API keys or hardware IDs are transmitted during
  checks.
- **Isolated Environment**: Requests execute from within containers without
  host-level access.

</details>

---

---

## 🛠️ Production deployment & disaster recovery

### Production Best Practices

For a stable, long-term deployment, follow these guidelines:

1.  **Dedicated Hardware**: While it runs on many systems, a dedicated machine
    (like a ZimaBoard or an old NUC) ensures your privacy hub is always
    available.
2.  **Static IP**: Assign a static LAN IP to your hub in your router settings.
3.  **Uninterruptible Power Supply (UPS)**: Protect against data corruption
    during power outages.
4.  **Automatic Backups**: Schedule regular backups of the
    `data/AppData/privacy-hub` directory.

### disaster recovery

#### Scenario 1: The system is slow or glitchy

Run the maintenance command to recreate containers without losing data:

```bash
./zima.sh -c
```

#### Scenario 2: Total hardware failure

1.  Set up a new machine with Docker and Git.
2.  Clone this repository.
3.  Restore your `data/AppData/privacy-hub` folder from your latest backup.
4.  Run `./zima.sh`. The script will detect your existing configs and restore
    the stack.

#### Scenario 3: "I need a fresh start"

To wipe everything and start over (Warning: IRREVERSIBLE):

```bash
./zima.sh -x
```

---

---

<details>
<summary>🛡️ <strong>Security and Networking</strong> (Click to expand)</summary>

## 🛡️ Security and networking

### Hardened security baseline

We prioritize minimal, security-focused images for all services.

- **The Benefit**: Minimal images reduce the attack surface by removing
  unnecessary binaries and libraries, following the principle of least
  privilege. (Concept based on
  [CIS Benchmarks](https://www.cisecurity.org/benchmark/docker) and minimal base
  image best practices).

### Split-tunneling architecture

The stack uses a split-tunneling architecture. Only the WireGuard port
(UDP 51820) is exposed to the public internet.

- **Key-Based Access**: Access is strictly gated by WireGuard public and private
  keys. This is required to allow users to securely use their DNS and services
  outside their home network.
- **Silent Drop**: WireGuard does not respond to packets it does not recognize.
  To a scanner, the port looks closed.
- **DDoS mitigation**: Because it is silent to unauthenticated packets, it is
  inherently resistant to flooding attacks.
- **Cryptographic ownership**: You cannot "guess" a password. You need a valid
  256-bit key.

### HTTPS and deSEC requirements

A valid SSL certificate (obtained via deSEC) is necessary for DNS-over-HTTPS
(DoH) and DNS-over-QUIC (DoQ) to function correctly. Additionally, VERT requires
HTTPS to connect securely with its daemon API.

</details>

---

<details>
<summary>🔧 <strong>Troubleshooting</strong> (Click to expand)</summary>

## 🔧 Troubleshooting

| Issue                          | Potential Solution                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| :----------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **"My internet broke!"**       | DNS resolution failed. Temporarily set your router DNS to **[Quad9](https://www.quad9.net/)** (`9.9.9.9` - [Privacy Policy](https://www.quad9.net/privacy/)) or **[Mullvad](https://mullvad.net/en/help/dns-over-https-and-dns-over-tls/)** (`194.242.2.2` - [Privacy Policy](https://mullvad.net/en/help/privacy-policy/)) to restore access, then check the Hub status. <br><br> **⚠️ CRITICAL**: While we recommend these for their strong privacy focus and "no-logging" policies, **do not** set them as your secondary DNS IP if you want absolute privacy. Most operating systems will query both DNS servers simultaneously; if you have a "fast" public DNS as a secondary, your queries will leak to them even if your self-hosted one is working. Use your self-hosted DNS exclusively once it is stable. |
| **"I can't connect remotely"** | **1.** Verify Port 51820 (UDP) is forwarded. **2.** If using OpenWrt, ensure "Double NAT" is handled (ISP -> OpenWrt -> Hub). **3.** Check if your ISP uses CGNAT. <details><summary>What is CGNAT?</summary>Carrier-Grade NAT (CGNAT) is a technique used by ISPs to share a single public IP address among multiple customers. This makes port forwarding impossible because you don't have a unique public IP. If you are behind CGNAT, traditional VPN/Port Forwarding won't work without a middleman like Tailscale or a VPS relay.</details>                                                                                                                                                                                                                                                                   |
| **"Services are slow"**        | **1.** Check VPN throughput in the dashboard. **2.** Try a different ProtonVPN server config. **3.** Ensure your host has sufficient CPU/RAM for compilation tasks.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| **"SSL is invalid"**           | Check `certbot/monitor.log` via dashboard. Ensure ports 80/443 are reachable for validation. Verify your deSEC token.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |

> 💡 **Pro-Tip**: Use `docker ps` to verify all containers are `Up (healthy)`.
> If a container is stuck, use `docker logs <name>` to see why.

</details>

---

<details>
<summary>💾 <strong>Maintenance and Restoration</strong> (Click to expand)</summary>

## 💾 Maintenance

### ⚠️ IMPORTANT: Back Up Your Data

Before performing any maintenance operations, **always back up your data
first**. The Privacy Hub stores valuable personal information:

| Service       | Data Stored                                       |
| :------------ | :------------------------------------------------ |
| **Memos**     | Personal notes, journal entries, attachments      |
| **Invidious** | YouTube subscriptions, watch history, preferences |
| **Immich**    | Photos, videos, albums, facial recognition data   |
| **AdGuard**   | DNS query logs, custom filtering rules            |
| **WireGuard** | VPN client configurations                         |

> ⚠️ **WARNING**: Using `-x` (Factory Reset) or clearing service databases
> **permanently deletes all data**. This action **cannot be undone**!

**Backup and Restore:**

- **Update**: Click "Check Updates" in the dashboard or run `./zima.sh` again.
- **Backup**:
  - **Dashboard**: Click **"Backup system"** in the System Information card.
    This creates a timestamped archive of your secrets, environment files, and
    service configurations.
  - **CLI**: Run `./zima.sh -b`.
  - **Manual**:
    ```bash
    # Manual backup of critical data (Secrets, Configs, Databases)
    # Adjust path to match your installation
    cp -r /data/AppData/privacy-hub /backup/location/
    ```
- **Restore**:
  - **Dashboard**: Click **"Restore from backup"**, select your desired archive,
    and confirm. The system will automatically overwrite current configurations
    and restart the stack.
  - **CLI**: Run `./zima.sh -r /path/to/backup.tar.gz`.
- **Uninstall**:
  ```bash
  ./zima.sh -x
  ```
  _(Note: This **only** removes the containers and volumes created by this
  specific privacy stack. Your personal documents, photos, and unrelated Docker
  containers are **never** touched.)_

</details>

---

---

## 🧩 Advanced usage

<details>
<summary><strong>🧪 Staged headless verification</strong> (CI/CD & Automation)</summary>

For developers and advanced users, the Privacy Hub includes a staged, headless
verification system designed for rigorous CI/CD environments and automated
stability testing. This system utilizes a state-aware orchestrator to manage
multi-stage deployments with automatic crash recovery.

### Running the Verification

To execute the full verification suite in headless mode:

```bash
# Run the automated orchestrator
./test/manual_verification.sh
```

### Key features

- **🧱 Multi-Stage Testing**: Tests are divided into logical stages (Core,
  Frontends, Management, etc.) to isolate failure points.
- **🔄 Auto-Resume Logic**: If the verification is interrupted (e.g., system
  crash, timeout), simply running the script again will automatically resume
  from the last pending stage.
- **⏱️ Timeout Protection**: The orchestrator includes an 18-minute cycle limit
  to ensure clean state transitions in restricted environments (like GitHub
  Actions).
- **📊 Comprehensive Logging**: Each stage generates dedicated logs (e.g.,
  `test/stage_1.log`) and a global `test/progress.log` for auditability.
- **🎭 UI Audit**: Automatically executes Puppeteer-based interaction tests to
  ensure the Material Design 3 dashboard remains functional across all supported
  platforms.

</details>

<details>
<summary><strong>🔧 Add Your Own Services</strong> (advanced, not needed for new users)</summary>

The stack uses a modular generation system. To add a new service, you will need
to modify the generator scripts in the `lib/` directory.

### 1) Registry and constants (`lib/core/constants.sh`)

Add your service ID to `STACK_SERVICES` and `ALL_CONTAINERS`. If it's a
source-built service, add it to `SOURCE_BUILT_SERVICES`.

### 2) Add to compose (`lib/services/compose.sh`)

Create an `append_myservice` function and call it within `generate_compose`.

```bash
append_myservice() {
  if ! should_deploy "myservice"; then return 0; fi
  cat >> "${COMPOSE_FILE}" <<EOF
  myservice:
    image: my-image:latest
    container_name: \${CONTAINER_PREFIX}myservice
    networks: [frontend]
    restart: unless-stopped
EOF
}
```

If you want the service to run through the VPN, use
`network_mode: "container:\${CONTAINER_PREFIX}gluetun"` and
`depends_on: gluetun`.

### 3) Configuration and dashboard (`lib/services/config.sh`)

Add your service metadata to the `SERVICES_JSON` block inside
`generate_scripts`. This enables the service to appear on the dashboard.

```json
"myservice": {
  "name": "My Service",
  "description": "Short description.",
  "category": "apps",
  "order": 100,
  "url": "http://\$LAN_IP:1234"
}
```

### 4) Automated updates and rollbacks

- **Watchtower**: To opt out, add `com.centurylinklabs.watchtower.enable=false`
  under the service labels in `compose.sh`.
- **Rollback support**: Enabled automatically for source-built services if
  "Rollback Support" is toggled ON in the dashboard settings.

</details>

<details>
<summary><strong>⏪ Version Rollback System</strong> (Recovery)</summary>

To ensure production stability, the Hub includes a version rollback system for
services built from source (e.g., Wikiless, Scribe).

### How it works

1.  **Snapshot**: If "Rollback Support" is enabled in settings (Default: OFF),
    the system captures the current Git commit hash before performing any
    update.
2.  **Backup**: A service-specific state file is saved to
    `data/hub-api/rollback_<service>.json`.
3.  **Revert**: If an update causes issues, a "Rollback version" button appears
    in the service management modal.
4.  **Restoration**: Clicking "Rollback" checks out the previously saved Git
    hash and rebuilds the container immediately.

### Limitations

- **Source-only**: Rollback is currently only available for services built from
  local Git repositories.
- **Single-stage**: Only the version immediately preceding the current one is
  preserved.
- **Data integrity**: Rollback reverts the application code but does not
  automatically revert database migrations unless specified in the service's
  migration logic.

</details>

<details>
<summary><strong>🧪 Automated verification</strong> (Click to expand)</summary>

To ensure a "set and forget" experience, every release undergoes a rigorous
automated verification pipeline.

- **Interaction Audit**: Puppeteer-based suite simulates real user behavior.
- **Non-Interactive Deployment**: verified `-p -y` flow for zero-prompt success.
- **M3 Compliance Check**: Automated layout audits ensure the dynamic grid and
  chips adapt to any screen size.
- **Log & Metric Integrity**: Container logs audited for 502/504 errors.
</details>

<details>
<summary><strong>🌐 Connection exposure map & Privacy Policies</strong> (Click to expand)</summary>

### Connection exposure map

| Service / Domain               | Purpose                               | Exposure                  |
| :----------------------------- | :------------------------------------ | :------------------------ |
| **Frontends (YouTube/Reddit)** | Privacy content retrieval             | **🔒 VPN IP** (Gluetun)   |
| **Dashboard Assets**           | Fonts (Fontlay) & Icons (JSDelivr)    | **🔒 VPN IP** (Gluetun)   |
| **VPN Client Management**      | Managing WireGuard clients            | **🔒 VPN IP** (Gluetun)   |
| **VPN Status & IP Check**      | Tunnel health monitoring              | **🔒 VPN IP** (Gluetun)   |
| **Health Checks**              | VPN Connectivity Verification         | **🔒 VPN IP** (Gluetun)   |
| **Container Registries**       | Pulling Docker images (Docker/GHCR)   | **🏠 Home IP** (Direct)   |
| **Git Repositories**           | Cloning source code (GitHub/Codeberg) | **🏠 Home IP** (Direct)   |
| **DNS Blocklists**             | AdGuard filter updates                | **🔒 VPN IP** (Gluetun)   |
| **deSEC.io**                   | SSL DNS Challenges                    | **🔒 VPN IP** (Gluetun)\* |
| **Odido API (Setup)**          | Initial User ID retrieval             | **🔒 VPN IP** (Gluetun)\* |
| **Odido API (Active)**         | Mobile Data fetching                  | **🔒 VPN IP** (Gluetun)   |
| **Cobalt**                     | Media downloads                       | **🔒 VPN IP** (Gluetun)   |
| **SearXNG / Immich**           | Search & Media sync                   | **🔒 VPN IP** (Gluetun)   |

_\*Setup/Configuration tasks attempt to use the VPN proxy if available, but may
fall back to direct Home IP if the VPN service is not yet established._

### Detailed privacy policies

- **Public IP Detection & Health**:
  - [ipify.org](https://www.ipify.org/) (Used to display VPN status; exposes
    **🔒 VPN IP**)
  - [ip-api.com](https://ip-api.com/docs/legal) (Used for geolocation health;
    exposes **🔒 VPN IP**)
  - [connectivity-check.ubuntu.com](https://ubuntu.com/legal/data-privacy) (Used
    for VPN tunnel verification; exposes **🔒 VPN IP**)
- **Infrastructure & Assets**:
  - [deSEC.io](https://desec.io/privacy-policy) (SSL challenges via **🏠 Home
    IP**)
  - [fontlay.com](https://github.com/miroocloud/fontlay) (Fetched via **🔒 VPN
    IP**)
  - [cdn.jsdelivr.net](https://www.jsdelivr.com/terms/privacy-policy-jsdelivr-net)
    (Fetched via **🔒 VPN IP**) | **Registries & Source Code** |
  - [Docker Hub](https://www.docker.com/legal/docker-privacy-policy/) (Image
    pulls via **🏠 Home IP**)
  - [GitHub / GHCR](https://docs.github.com/en/site-policy/privacy-policies/github-privacy-statement)
    (Source cloning via **🏠 Home IP**)
  - [Codeberg](https://codeberg.org/privacy) (Source cloning via **🏠 Home IP**)
  - [Quay.io](https://quay.io/privacy) (Image pulls via **🏠 Home IP**)
  - [SourceHut](https://man.sr.ht/privacy.md) (Source cloning via **🏠 Home
    IP**)
  - [Gitdab](https://gitdab.com/) (Source cloning via **🏠 Home IP**)
- **Data Providers**:
  - [DNS Blocklists (GitHub)](https://docs.github.com/en/site-policy/privacy-policies/github-privacy-statement)
    (Fetched via **🔒 VPN IP**)
  - [Odido API](https://www.odido.nl/privacy) (ID retrieval via **🏠 Home IP**
    during setup; automated data via **🔒 VPN IP**)
  - [Immich Privacy Policy](https://docs.immich.app/privacy-policy) (Note:
    Immich does not collect any data unless you choose to support the project
    via buy.immich.app, where data is used strictly for tax calculations.)

</details>

---

## 🚨 Disclaimer

This software is provided "as is". While designed for security, the user is
responsible for ensuring their specific network configuration is safe. **Do not
use GitHub Codespaces for production deployment.**

---

_Built with ❤️ for digital sovereignty._
