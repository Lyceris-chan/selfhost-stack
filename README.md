# 🛡️ ZimaOS Privacy Hub

A comprehensive, self-hosted privacy infrastructure designed for digital independence.
Route your traffic through secure VPNs, eliminate tracking with isolated frontends, and manage everything from a unified **Material Design 3** dashboard.

## 🌟 Key Features & Benefits

*   **Data Independence & Ownership**: By hosting your own frontends (Invidious, Redlib, etc.), you stop upstream giants like Google and Reddit from collecting, profiling, and selling your behavioral data. You own the instance; you own the data.
*   **Ad-Free by Design**: Enjoy a clean, distraction-free web. AdGuard Home blocks trackers and ads at the DNS level for your entire home, while frontends eliminate in-video ads and sponsored content natively.
*   **No App Prompts**: Say goodbye to "Install our app" popups. These frontends provide a premium mobile-web experience that works perfectly in any browser without requiring invasive native applications.
*   **VPN-Gated Privacy**: Sensitive services are routed through a **Gluetun VPN** tunnel. This ensures that even when you browse, end-service providers only see your VPN's IP address, keeping your home location and identity hidden.
*   **Zero-Leaks Architecture**: Our "Privacy First" asset engine ensures your browser never contacts third-party CDNs. Fonts, icons, and scripts are served locally from your machine.
*   **Privacy Guarantee**: Within this stack, **none** of the services you interact with can see your public IP or identifying metadata. The *only* time your IP is exposed is during the initial setup when cloning source code from GitHub/Codeberg, which is a one-time deployment event.
*   **Material Design 3**: A beautiful, accessible management dashboard with dynamic theming and real-time health metrics.

## ⚡ Quick Start

**Want to deploy immediately?** Run this single command:
```bash
./zima.sh -p -y
```

This automated mode:
- ✅ Generates secure random passwords automatically
- ✅ Skips all interactive prompts
- ✅ Creates a complete privacy stack in ~15 minutes
- ✅ Exports credentials to `protonpass_import.csv`

**Read the full [Prerequisites](#prerequisites--infrastructure) below for advanced configuration options.**

---

<a id="disclaimer--security-warning"></a>
## 🚨 Disclaimer & Security Warning

### Provided "As Is"
This script and associated configuration files are provided **as is**. While I appreciate improvements and contributions, please ensure your code is fully tested and functional before submitting it. I cannot guarantee that everything will work in every unique environment. It has been verified to work on GitHub Codespaces and locally.

### 🔐 Security Best Practices
- **DO NOT** use GitHub Codespaces for an actual production deployment. 
- **NEVER** upload your production secrets (API keys, tokens, VPN configs) to the internet or public repositories.
- **Minimal Permissions**: Ensure any tokens or PATs you create have the absolute minimal permissions required for their task.
- **Revoke Immediately**: Revoke and delete any tokens as soon as you are finished with them. **Do not forget this**, as it can compromise your entire infrastructure security.

---

<a id="getting-started"></a>
## 🏗️ Getting Started

### Prerequisites & Infrastructure

**Pre-Flight Checklist** - Gather these before running the installation:

#### ✅ Required Items

- [ ] **Docker Hub Credentials** ([Create here](https://hub.docker.com/settings/security))
  - Username (same for Docker Hub and `dhi.io`)
  - Personal Access Token with **read/pull permissions only**
  - Used to pull hardened images and avoid rate limits
  
- [ ] **ProtonVPN WireGuard Configuration** ([Get your .conf file](#protonvpn-wireguard-conf---the-anonymity-engine))
  - Required for Gluetun VPN gateway
  - Hides your home IP from upstream services
  - Only ProtonVPN is explicitly tested (other WireGuard providers untested)

#### 🔧 Optional (But Recommended)

- [ ] **deSEC Domain + Token** ([Sign up at deSEC.io](https://desec.io))
  - Enables trusted SSL certificates (no browser warnings)
  - Unlocks Private DNS for Android/iOS
  - Free dynamic DNS service
  
- [ ] **GitHub Personal Access Token** (For Scribe frontend)
  - Classic token with `gist` scope only
  - [Generate here](https://github.com/settings/tokens)
  - Avoids rate limits (60/hr → 5000/hr)

- [ ] **Odido OAuth Token** (Dutch users only)
  - Required for automated data bundle management
  - Obtain via [Odido Authenticator](https://github.com/GuusBackup/Odido.Authenticator)

---

<details>
<summary><strong>🔍 Quick Explainers - Click to expand</strong></summary>

<a id="explainer-1"></a>
1. **DHI (Docker Hardened Images)**: Security-focused base images from `dhi.io` that strip telemetry, minimize attack surface, and optimize performance for self-hosting environments.

<a id="explainer-2"></a>
2. **DDNS (Dynamic DNS)**: Automatically updates your domain when your home IP changes, keeping services accessible without manual DNS edits.

<a id="explainer-3"></a>
3. **SSL / Trusted SSL**: 
   - **Trusted**: Certificate from Let's Encrypt (public CA) - no browser warnings
   - **Self-Signed**: Also encrypted, but triggers security warnings without manual trust

<a id="explainer-4"></a>
4. **Classic PAT (Personal Access Token)**: API authentication token you create in account settings (GitHub, Docker Hub, etc.) with specific permissions/scopes.

<a id="explainer-5"></a>
5. **CDN (Content Delivery Network)**: Third-party servers that host common libraries/assets. This stack serves everything locally for privacy.

</details>

---

<details>
<summary><strong>📥 ProtonVPN WireGuard (.conf) - The Anonymity Engine</strong></summary>

This configuration is **critical** for privacy. It routes all frontend traffic (Invidious, Redlib, etc.) through an encrypted tunnel, ensuring upstream services never see your home IP address.

**Step-by-Step Guide:**

1. **Login** to [ProtonVPN Downloads](https://account.protonvpn.com/downloads)
2. **Navigate** to the WireGuard section
3. **Name** your configuration (e.g., "Privacy-Hub-Main")
4. **Select** a Free server in your preferred region
5. **Download** the `.conf` file

**During Installation:**
- You'll be prompted to paste the entire file contents
- Or set `WG_CONF_B64` environment variable with base64-encoded config

**🛡️ Privacy Impact:**  
Without this configuration, services will expose your real home IP to YouTube, Reddit, and other providers. With it enabled, they only see ProtonVPN's shared commercial IP address.

**📊 Bandwidth Considerations:**  
The script tracks VPN data usage. On mobile devices connected via your home WireGuard (WG-Easy), only privacy frontend traffic routes through the ProtonVPN tunnel - streaming apps like Netflix/Spotify maintain full direct speed.

</details>

### Installation
Run the deployment script. It will validate your environment, prompt for credentials, and build the stack.

```bash
# Standard Deployment (Interactive)
./zima.sh

# Deployment with Auto-generated Passwords (Recommended for Beginners)
./zima.sh -p

# Deployment with ProtonVPN Allowlist
./zima.sh -a
```

### ✅ Verify Installation

After deployment completes, run these checks to confirm everything is operational:

**1. Check Container Health:**
```bash
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

Expected output: All containers should show `Up` or `healthy` status.

**2. Test Dashboard Access:**
```bash
curl -I http://localhost:8081
```

Expected: HTTP 200 response

**3. Verify DNS Resolution:**
```bash
dig @localhost example.com
```

Expected: Valid A record response (confirms AdGuard/Unbound are working)

**4. Check VPN Tunnel:**
```bash
docker exec gluetun wget -qO- http://ifconfig.me
```

Expected: ProtonVPN IP address (different from your home IP)

**🚨 Troubleshooting:** If any check fails, review deployment logs:
```bash
tail -f /DATA/AppData/privacy-hub/deployment.log
```

### 🔑 Post-Install: Where are my passwords?
If you used the `-p` flag, the script auto-generated secure credentials for you.

1.  **Secret File**: All passwords are stored on your host at:
    ```bash
    /DATA/AppData/privacy-hub/.secrets
    ```
    > ⚠️ **SECURITY WARNING**: This file contains unencrypted administrative passwords and API keys. Ensure access to your host machine is restricted.

2.  **Proton Pass Import**: A CSV file ready for import into password managers is generated at:
    ```bash
    /DATA/AppData/privacy-hub/protonpass_import.csv
    ```
3.  **Default Username**:
    *   **Portainer**: `portainer` (or `admin`)
    *   **AdGuard**: `adguard`
    *   **Dashboard API**: `HUB_API_KEY` (Found in `.secrets`)

### Management & Troubleshooting
*   **Update Services**: Use the "Check Updates" button in the dashboard.
*   **Restart Stack**: `./zima.sh` (Running it again updates configuration and restarts containers safely).

| Flag | Description | Action |
| :--- | :--- | :--- |
| `-c` | **Maintenance Reset** | Removes active containers and networks to resolve glitches, while strictly preserving persistent user data. |
| `-x` | **REVERT (Factory Reset)** | ⚠️ **REVERT: Total Cleanup** — This erases only the parts we added. It wipes the Invidious database and any data saved inside our apps during your usage. If you didn't back up your app data, it will be gone forever. It does not touch your personal files (like your Documents or Photos folders); it only clears out our software. |
| `-p` | **Auto-Passwords** | Generates secure random passwords for all services automatically. |
| `-a` | **Allow Proton VPN** | Allowlists essential ProtonVPN domains in AdGuard Home. **Warning:** This may break DNS isolation and frontend access. |
| `-y` | **Auto-Confirm** | Skips all interactive confirmation prompts. |

## 🛡️ Privacy & Security Features

### Recursive DNS Engine (Independent Resolution)
This stack eliminates reliance on centralized upstream providers. By resolving queries directly with Root Servers, we operate on a **Zero-Trust** model that prioritizes your independence:
*   **Zero Third-Parties**: We bypass "public" resolvers like **Google** (to prevent behavioral data harvesting and sale) and **Cloudflare** (to avoid centralized censorship and single-point-of-failure risks).
*   **Least Trust Architecture**: Your browsing queries never leave your hardware in a readable or profileable format.
*   **QNAME Minimization**: Only sends the absolute minimum metadata to root servers, closing the "full-history" visibility gap inherent in standard DNS.
*   **ECH (Encrypted Client Hello)**: Optimized for modern browsers to prevent ISP-level SNI snooping.
*   **Encrypted Local Path**: Native support for **DoH** (RFC 8484) and **DoQ** (RFC 9250) ensures your internal queries are invisible to your ISP.
*   **Aggressive Caching & Prefetching**: Reduces external network exposure while significantly speeding up frequent queries by resolving expired records in the background.
*   **Identity Hiding**: Server identity and version metadata are scrubbed to prevent fingerprinting.

### 🛡️ Blocklist Information & DNS Filtering
Our DNS filtering is powered by a custom-generated blocklist, ensuring a clean and secure browsing experience:
*   **Source Citation**: Blocklists are generated using the [Lyceris-chan DNS Blocklist Generator](https://github.com/Lyceris-chan/dns-blocklist-generator/).
*   **Composition**: The list is primarily based on **Hagezi Pro++**, combined with selected AdGuard default lists (deduplicated) for maximum coverage.
*   **Curation**: We have specifically curated these lists and integrated [Easy List Dutch](https://easylist-downloads.adblockplus.org/easylistdutch.txt) to improve performance for Dutch users.
*   **🛡️ Note on Aggression**: This blocklist is **aggressive** by design to ensure total privacy. If you experience "over-blocking," we suggest exploring AdGuard's standard default lists as a more balanced alternative.

## 🧪 Automated Verification & Quality Assurance

To ensure a "set and forget" experience, every release of this stack undergoes a rigorous automated verification pipeline:
*   **Interaction Audit**: A Puppeteer-based test suite (`test_user_interactions.js`) simulates a real user by clicking, toggling, and switching every UI element (Theme, Privacy Mode, Filters, Modals) to verify stability and zero console errors.
*   **Non-Interactive Deployment**: The `-p -y` flow is verified for zero-prompt success, ensuring the stack can be deployed via scripts or CI/CD without human input.
*   **M3 Compliance Check**: Automated layout audits ensure the dynamic grid (3x3, 4x4) and chip auto-layout correctly adapt to any screen size without clipping or hardcoded overflows.
*   **Log & Metric Integrity**: Container logs are audited for 502/504 errors, and real-time CPU/RAM telemetry is verified across all service management modals.


### ⚠️ Common Pitfalls - Read Before Proceeding

<details>
<summary><strong>❌ Mistake #1: Dynamic MAC Addresses Enabled</strong></summary>

**Symptom:** Port forwarding stops working after reboot, services unreachable remotely

**Cause:** iOS "Private Wi-Fi Address" or Android "Randomized MAC" rotates your machine's hardware ID. The router treats it as a **new device** and assigns a different IP, breaking all static bindings.

**Fix:**
1. **iOS**: Settings → Wi-Fi → (i) → Private Wi-Fi Address → **OFF**
2. **Android**: Wi-Fi → Advanced → Privacy → Use Randomized MAC → **OFF**
3. **Windows**: Network Adapter Properties → Configure → Locally Administered Address → **Disabled**

**Verify:**
```bash
ip link show | grep ether
# MAC should be consistent across reboots
```
</details>

<details>
<summary><strong>❌ Mistake #2: Google DNS as Secondary</strong></summary>

**Symptom:** Ads still appear, tracking still occurs

**Cause:** Devices try primary DNS first, but fall back to secondary if primary is "slow". Secondary public resolvers **do not block ads or trackers**.

**Fix:**
- **Router DHCP Settings:**
  - Primary DNS: `<YOUR_PRIVACY_HUB_IP>`
  - Secondary DNS: **Leave Empty** or set to same as primary
- **Never use:** Public resolvers as secondary

**Why?** Your privacy infrastructure must be the **only** DNS resolver. Any fallback defeats the purpose.
</details>

<details>
<summary><strong>❌ Mistake #3: Skipping Port Forward on ISP Router</strong></summary>

**Symptom:** WireGuard connects on home network, fails from coffee shop/mobile data

**Cause:** Double NAT scenario - forwarded port 51820 on your OpenWrt router, but forgot to forward it on the ISP-provided modem/router.

**Fix:**
1. Login to **ISP router** (often 192.168.0.1 or 192.168.1.1)
2. Port Forwarding section
3. Forward **UDP 51820** to your **OpenWrt router's WAN IP**
4. Confirm with: `curl ifconfig.me` (should match WG_HOST in logs)

**Diagram:**
```
Internet → ISP Router (NAT1) → OpenWrt Router (NAT2) → Privacy Hub
            ↑ Forward 51820     ↑ Forward 51820
```
</details>

<details>
<summary><strong>❌ Mistake #4: Expecting Instant Updates</strong></summary>

**Symptom:** Dashboard shows "No updates", but I know there are new commits

**Cause:** The update check system relies on Watchtower (for images) and git fetch (for source repos). Initial check takes 2-5 minutes.

**Timeline:**
- Click "Check Updates" → Triggers background job
- Wait **5 minutes**
- Refresh dashboard → Updates appear in banner

**Manual verification:**
```bash
cd /DATA/AppData/privacy-hub/sources/invidious
git fetch
git log HEAD..origin/master  # Shows commits you're behind
```
</details>

### 🔧 Troubleshooting

#### "My Internet Broke" - Critical Recovery

**What Happened?**  
Your Privacy Hub machine hosts your DNS resolver. If it loses power, crashes, or the script fails mid-update, devices lose the ability to translate domain names (like `google.com`) into IP addresses.

**Immediate Fix:**

1. **Restart the Hub:**
```bash
   cd /DATA/AppData/privacy-hub
   ./zima.sh
```

2. **Emergency Fallback DNS** (If restart fails):

   - Open your router's DHCP settings

   - Change Primary DNS to: **`9.9.9.9`** (Quad9) or **`194.242.2.2`** (Mullvad)

   - This restores internet access while you repair the Privacy Hub.

   - **⚠️ Implications:** When using fallback DNS, your local Privacy Hub services (e.g., `adguard.your-domain.dedyn.io`) will not resolve locally. You will be accessing them via their public IPs, which may trigger SSL warnings if the local DNS override is not active. This is an emergency measure; the stack is designed for production stability and such failures should not generally occur.

   

   **Why these providers?**
   - [Mullvad DNS](https://mullvad.net/en/help/dns-over-https-and-dns-over-tls): Privacy-focused, supports DoH/DoT. [Read their Privacy Policy here](https://mullvad.net/en/help/privacy-policy/).
   - [Quad9](https://www.quad9.net/): Non-profit, GDPR compliant, and filters malicious domains. [Read their Privacy Policy here](https://www.quad9.net/privacy/policy/).

3. **Fix the Hub**, then switch DNS back to your Privacy Hub IP

---

#### Container Won't Start

**Check logs for specific service:**
```bash
docker logs <container_name> --tail 50
```

**Common Issues:**

| Error Message | Cause | Fix |
|--------------|-------|-----|
| `port is already allocated` | Another service using the port | `docker ps -a` → Stop conflicting container |
| `no space left on device` | Disk full | `docker system prune -a` |
| `rate limit exceeded` | Docker Hub throttling | Run `./zima.sh` to re-authenticate |
| `OCI runtime error` | Corrupted container state | `./zima.sh -c` (maintenance reset) |

---

#### VPN Tunnel Not Connecting

**Diagnose Gluetun health:**
```bash
docker exec gluetun wget -qO- http://127.0.0.1:8000/v1/vpn/status
```

**Expected:** `{"status":"running"}`

**If status is "stopped":**
1. Verify your WireGuard config: `cat /DATA/AppData/privacy-hub/active-wg.conf`
2. Confirm it contains a valid `PrivateKey` (44 base64 characters)
3. Re-upload config via Dashboard → WireGuard Profiles

---

#### Services Show "Offline" in Dashboard

**Check Hub API connectivity:**
```bash
curl http://localhost:8081/api/status
```

- **401 Unauthorized**: API key mismatch. Check `.secrets` file for correct `HUB_API_KEY`
- **Connection refused**: Hub API container crashed. Restart: `docker restart hub-api`
- **Timeout**: Network issue between containers. Run: `./zima.sh -c` to reset networking

---

#### SSL Certificate Shows Self-Signed (Stuck)

**Check Let's Encrypt logs:**
```bash
cat /DATA/AppData/privacy-hub/config/adguard/certbot/last_run.log
```

**Common causes:**

1. **Rate Limited**: You've hit Let's Encrypt's limit (5 certs/week for same domain)
   - **Solution**: Wait for retry time shown in logs. Background job will auto-retry.

2. **Invalid deSEC Token**: Token expired or wrong permissions
   - **Solution**: Generate new token at [deSEC.io](https://desec.io) → Dashboard → Certificate Configuration

3. **DNS Verification Failed**: deSEC records not propagating
   - **Solution**: Check records: `dig @194.242.2.2 _acme-challenge.<YOUR_DOMAIN>` (Uses **[`194.242.2.2`](https://mullvad.net/en/help/dns-over-https-and-dns-over-tls)** - [Mullvad Privacy Policy](https://mullvad.net/en/help/privacy-policy/))
   - If empty, manually trigger update in Dashboard → deSEC Configuration

**Force manual retry:**
```bash
bash /DATA/AppData/privacy-hub/cert-monitor.sh
```

<a id="management-dashboard"></a>
## 🖥️ Management Dashboard

Access the unified dashboard at `http://<LAN_IP>:8081`.

### Material Design 3 Compliance
The dashboard is built to strictly follow **[Google's Material Design 3](https://m3.material.io/)** guidelines.
*   **Color System**: We use the official `material-color-utilities` library to generate accessible color palettes from your seed color or wallpaper.
*   **Components**: All UI elements (cards, chips, buttons) adhere to M3 specifications for shape, elevation, and state layers.

### Customization
*   **Theme Engine**: Upload a wallpaper to automatically extract a coordinated palette (Android folder style), or pick a color manually.
*   **Presets**: Choose from curated Material Design color presets.
*   **Safe Display Mode**: One-click toggle to blur sensitive IPs and data for screenshots.

### Update Engine
*   **Changelogs**: View commit logs (for source builds) or release notes (for images) directly in the UI before updating.
*   **Granular Control**: Update all services at once or select specific ones.
*   **Safety First**: Automatic database backups are created before any update is applied.

<a id="included-services"></a>
## 📦 Included Services

| Service & Source | Category | Purpose |
| :--- | :--- | :--- |
| **[Invidious](https://github.com/iv-org/invidious)** | Privacy Frontend | Anonymous YouTube (No ads/tracking) |
| **[Redlib](https://github.com/redlib-org/redlib)** | Privacy Frontend | Lightweight Reddit interface |
| **[Wikiless](https://github.com/Metastem/Wikiless)** | Privacy Frontend | Private Wikipedia access |
| **[Memos](https://github.com/usememos/memos)** | Utility | Private knowledge base & notes |
| **[AdGuard Home](https://github.com/AdguardTeam/AdGuardHome)** | Core | DNS filtering & Ad-blocking |
| **[WireGuard](https://github.com/wg-easy/wg-easy)** | Core | Secure remote access gateway |
| **[Portainer](https://github.com/portainer/portainer)** | Admin | Advanced container management |
| **[VERT](https://github.com/vert-sh/vert)** | Utility | Local, GPU-accelerated file conversion (VERTD requires a valid <sup>[3](#explainer-3)</sup> cert due to quirks) |
| **[Rimgo](https://codeberg.org/rimgo/rimgo)** | Frontend | Lightweight Imgur interface |
| **[BreezeWiki](https://gitdab.com/cadence/breezewiki)** | Frontend | De-fandomized Wiki interface |
| **[AnonOverflow](https://github.com/httpjamesm/anonymousoverflow)** | Frontend | Private Stack Overflow viewer |
| **[Scribe](https://git.sr.ht/~edwardloveall/scribe)** | Frontend | Alternative Medium frontend |
| **[Odido Booster](https://github.com/Lyceris-chan/odido-bundle-booster)** | Utility | Automated NL data bundle booster |

> 💡 **Tip: Migrating your data to Invidious**
> You can easily import your existing data to your private Invidious instance. Navigate to **Settings → Import/Export** to upload:
> *   **Invidious Data**: JSON backup from another instance.
> *   **YouTube**: Subscriptions (CSV/OPML), Playlists (CSV), or Watch History (JSON).
> *   **Other Clients**: FreeTube (`.db`) or NewPipe (`.json`/`.zip`) subscriptions and data.

### Service Access & URLs
The dashboard provides one-click launch cards for every service. 

| Service | Local LAN URL | Category |
| :--- | :--- | :--- |
| **Dashboard** | `http://<LAN_IP>:8081` | Management |
| **Invidious** | `http://<LAN_IP>:3000` | Privacy Frontend |
| **Redlib** | `http://<LAN_IP>:8080` | Privacy Frontend |
| **Wikiless** | `http://<LAN_IP>:8180` | Privacy Frontend |
| **Rimgo** | `http://<LAN_IP>:3002` | Privacy Frontend |
| **BreezeWiki** | `http://<LAN_IP>:8380` | Privacy Frontend |
| **AnonOverflow** | `http://<LAN_IP>:8480` | Privacy Frontend |
| **Scribe** | `http://<LAN_IP>:8280` | Privacy Frontend |
| **Memos** | `http://<LAN_IP>:5230` | Utility |
| **VERT** | `http://<LAN_IP>:5555` | Utility |
| **Odido Booster** | `http://<LAN_IP>:8085` | Utility |

### 📦 Docker Hardened Images (DHI)
This stack utilizes **Digital Independence (DHI)** images (`dhi.io`) to ensure maximum security and privacy. These images are purpose-built for self-hosting:

*   **Zero Telemetry**: All built-in tracking and "phone home" features found in standard images are strictly removed.
*   **Security Hardened**: Attack surfaces are minimized by stripping unnecessary binaries and tools. Base images use minimal, audited Alpine or Debian builds.
*   **Performance Optimized**: Pre-configured for low-resource environments (like ZimaBoard/CasaOS) with faster startup times.
*   **Replacement Mapping**:
    *   `dhi.io/nginx` replaces standard `nginx:alpine` (Hardened config, no server headers).
    *   `dhi.io/python` replaces standard `python:alpine` (Stripped of build-time dependencies).
    *   `dhi.io/node` & `dhi.io/bun` (Optimized for JS-heavy frontends).
    *   `dhi.io/redis` & `dhi.io/postgres` (Hardened database engines).
| **AdGuard Home** | `http://<LAN_IP>:8083` | Infrastructure |
| **WireGuard UI** | `http://<LAN_IP>:51821` | Infrastructure |
| **Portainer** | `http://<LAN_IP>:9000` | Admin |

> 🔒 **Domain Access**: When deSEC is configured, all services automatically become available via trusted HTTPS at `https://<service>.<domain>:8443/`.

### 🔑 Inbound Access: WireGuard (WG-Easy)
While **Gluetun** handles the outbound VPN tunnel for privacy, **WG-Easy** provides the *inbound* tunnel for secure remote access.

*   **Secure Entry**: To access your services from outside your home, connect to your Privacy Hub using a WireGuard client. Only **UDP Port 51820** is exposed, and it remains completely "invisible" to unauthorized scanners without the correct cryptographic key.
*   **Client Configuration**: 
    1. Open the WireGuard UI (`http://<LAN_IP>:51821`).
    2. Create a new client (e.g., "Mobile").
    3. **Scan QR Code**: Use the WireGuard app on your phone to scan the generated QR code.
    4. **Download .conf**: Alternatively, download the configuration file for your laptop.
*   **Routing**: Once connected, your device is virtually "inside" your home network. You can access all services using their local LAN IPs or deSEC subdomains.

### 🌐 Personal Browsing via VPN Proxy
Your Privacy Hub includes a built-in **HTTP Proxy** routed through your VPN. This allows you to use your ProtonVPN (or other provider) connection for general browsing on any device in your home without installing VPN clients on every machine.

*   **Proxy Address**: `http://<LAN_IP>:8888`
*   **How to use**: 
    1.  Go to your browser or system proxy settings.
    2.  Set the **HTTP Proxy** to your Privacy Hub's LAN IP and port `8888`.
    3.  All traffic from that browser will now exit via the secure VPN tunnel.
*   **Benefit**: Ideal for "browser-only" VPN needs while keeping other system traffic direct.

<a id="network-configuration"></a>
## 🌐 Network Configuration

### 1. Enable Remote Access (ISP Router)
To access your services from anywhere via WireGuard, you must forward the VPN port on your main router:
*   **Port Forwarding**: Forward **UDP Port 51820** to the **Local IP** of your Privacy Hub (e.g., `192.168.1.100`).
*   This allows the WireGuard handshake to complete securely. No other ports need to be exposed.

### 2. Router Configuration (OpenWrt Example)
If you use a custom router like OpenWrt, ensure your Privacy Hub has a stable address and precise firewall rules. **Step 1 is critical** as it binds the hardware (MAC) to the IP, allowing the firewall to target only your Privacy Hub host.

```bash
# 1. Assign Static IP (Binds hardware MAC to IP)
uci add dhcp host
uci set dhcp.@host[-1].name='Privacy-Hub'
uci set dhcp.@host[-1].mac='00:11:22:33:44:55' # <--- YOUR DEVICE MAC
uci set dhcp.@host[-1].ip='192.168.1.100'      # <--- YOUR DESIRED IP
uci commit dhcp

# 2. Port Forwarding (Redirect WAN traffic to Hub IP)
uci add firewall redirect
uci set firewall.@redirect[-1].name='Forward-WireGuard'
uci set firewall.@redirect[-1].src='wan'
uci set firewall.@redirect[-1].proto='udp'
uci set firewall.@redirect[-1].src_dport='51820'
uci set firewall.@redirect[-1].dest_ip='192.168.1.100'
uci set firewall.@redirect[-1].dest_port='51820'
uci set firewall.@redirect[-1].target='DNAT'
uci commit firewall
/etc/init.d/firewall restart
```

### 3. Network-Wide DNS Protection
To filter ads and trackers for every device on your WiFi:
*   **DHCP Settings**: Set the **Primary DNS** server in your router's LAN/DHCP settings to your Privacy Hub's IP (`192.168.1.100`).
*   **Secondary DNS**: Leave empty or set to the same IP. *Adding a public resolver here breaks your privacy.*
*   **⚠️ IMPORTANT: Disable Dynamic MAC Addresses**: Ensure that "Private WiFi Address" (iOS) or "Randomized MAC" (Android/Windows) is **DISABLED** for your home network on the host machine. Your router binds a **MAC address → IP** lease; if the MAC rotates, the router treats it as a new device and assigns a new IP, which breaks port forwarding, firewall rules, and any DNS rewrites that point to the old address.

> ⚠️ **Critical Troubleshooting: If Your Internet "Breaks"**
>
> **What is DNS?** DNS (Domain Name System) is the "phonebook" of the internet. It translates human-friendly names (like `google.com`) into computer IPs (like `142.250.1.1`). **Resolving a name** is the process of your computer asking your hub for this translation.
>
> If your Privacy Hub machine loses power, crashes, or the script breaks during an update, your devices may lose internet access because they can no longer "resolve names."
>
> **What to do:**
> 1.  **Restart the Hub**: Run `./zima.sh` again to fix configurations and restart containers.
> 2.  **Emergency Fallback**: If you cannot fix the hub immediately, change your router or device DNS to a trusted public provider like **Mullvad DNS**. They offer advanced [DoH/DoT options](https://mullvad.net/en/help/dns-over-https-and-dns-over-tls) and have a verified [Privacy Policy](https://mullvad.net/en/help/privacy-policy) that aligns with our least-trust model. Use this to restore connectivity until you can repair your self-hosted instance.

### 4. Split Tunnel Configuration (VPN Routing) & Bandwidth Optimization
This stack uses a **Split Tunnel** architecture via Gluetun. This means only specific traffic is sent through the VPN, while the rest of your home network remains untouched.
*   **VPN-Gated Services**: Privacy frontends (Invidious, Redlib, etc.) are locked inside the VPN container. They cannot access the internet if the VPN disconnects (Killswitch enabled).
*   **Local-Direct Services**: Core management tools (Dashboard, Portainer, AdGuard UI) are accessible directly via your LAN IP. This ensures you never lose control of your hub even if the VPN provider has an outage.
*   **🚀 Bandwidth Benefits**: Only self-hosted privacy services route through your home WireGuard connection. This preserves your mobile data speed: high-bandwidth streaming services like Netflix or native YouTube apps maintain their full, direct speed on your device rather than being forced to route back through your home upload connection first.

### 🔀 VPN Architecture: Two Tunnels Explained

This stack uses **two separate VPN systems** for different purposes. Understanding the distinction is critical:

#### 1️⃣ Gluetun (Outbound Privacy Tunnel)
- **Purpose**: Hides your home IP from upstream services
- **Route**: Privacy Hub → ProtonVPN → Internet (YouTube, Reddit, etc.)
- **Protects**: Your privacy frontends (Invidious, Redlib, Wikiless, etc.)
- **Configuration**: ProtonVPN WireGuard `.conf` file

**What It Does:**
- When Invidious fetches a YouTube video, YouTube's servers see ProtonVPN's IP
- When Redlib loads Reddit posts, Reddit sees ProtonVPN's IP
- Your real home location remains hidden from all upstream providers

**Health Check:**
```bash
docker exec gluetun wget -qO- http://ifconfig.me
# Expected: ProtonVPN IP (NOT your home IP)
```

---

#### 2️⃣ WG-Easy (Inbound Remote Access)
- **Purpose**: Lets you access your Privacy Hub from anywhere
- **Route**: Your Phone/Laptop → WG-Easy → Privacy Hub → LAN Services
- **Protects**: Secure tunnel into your home network
- **Configuration**: Automatic (generates client configs via web UI)

**What It Does:**
- Connect from coffee shop → VPN tunnel → Access your private services
- Only **UDP Port 51820** is exposed to internet (encrypted, invisible to port scanners)
- Once connected, you can use http://<LAN_IP>:8081 as if you were home

**Setup Guide:**
1. Open WireGuard UI: `http://<YOUR_LAN_IP>:51821`
2. Create client config (e.g., "My-Phone")
3. Scan QR code with WireGuard mobile app
4. Connect → You're now "inside" your home network

---

#### 📊 Bandwidth Optimization

**Split Tunnel Architecture** = Smart routing for optimal speeds:

✅ **Routes Through Home VPN** (WG-Easy):
- Privacy Hub Dashboard
- Local services (Portainer, AdGuard UI)
- Self-hosted apps (Memos, VERT)

❌ **Does NOT Route Through Home** (Direct connection):
- Netflix, Spotify, YouTube app, etc.
- General web browsing
- Large file downloads

**Why?** Your home upload speed becomes the bottleneck for VPN traffic. By only routing Privacy Hub access through the tunnel, streaming services maintain full direct speeds on your mobile device.

### 5. Encrypted DNS via Local Rewrites
By leveraging AdGuard Home's **DNS Rewrites**, you can use advanced encrypted protocols (DoH/DoQ) without needing a constant VPN connection while at home.
*   **The Logic**: AdGuard is configured to "rewrite" your deSEC domain (e.g., `your-domain.dedyn.io`) to your Hub's **Internal IP**.
*   **The Benefit**: Your phone/laptop can use **Private DNS** (Android) or system-level DoH pointing to your domain. When you are home, the request never leaves your network; when you are away, the same settings route securely back to your hub via deSEC.

### 6. Advanced Network Hardening (Explore!)
Some "smart" devices (TVs, IoT, Google Home) are hardcoded to bypass your DNS and talk directly to Google. You can force them to respect your privacy rules using advanced firewall techniques.

*   **DNS Hijacking (NAT Redirect)**: Catch all rogue traffic on port 53 and force it into your AdGuard instance. [OpenWrt Guide](https://openwrt.org/docs/guide-user/firewall/firewall_configuration/intercept_dns)
*   **Block DoH/DoT**: Modern apps try to use "DNS over HTTPS" to sneak past filters. You can block this by banning known DoH IPs and ports (853/443). [OpenWrt banIP Guide](https://openwrt.org/docs/guide-user/firewall/firewall_configuration/ban_ip)

> 🚀 **Why do this?** This ensures *total* network independence. Not a single packet leaves your house without your permission. It's a deep rabbit hole, but worth exploring!

<a id="security-privacy"></a>
## 🔒 Security & Privacy

### Zero-Leaks Architecture
External assets (fonts, icons, scripts) are fetched once via the **Gluetun VPN proxy** and served locally. Your public home IP is never exposed to CDNs.

**Privacy Enforcement:**
1.  **Container Initiation**: When the Hub API container starts, it initiates an asset verification check.
2.  **Proxy Routing**: If assets are missing, the Hub API routes download requests through the Gluetun VPN container (acting as an HTTP proxy on port 8888).
3.  **Encapsulated Fetching**: All requests to external CDNs (Fontlay, JSDelivr) occur *inside* the VPN tunnel. Upstream providers only see the VPN IP.
4.  **Local Persistence**: Assets are saved to a persistent Docker volume (`/assets`).
5.  **Offline Serving**: The Management Dashboard (Nginx) serves all UI resources exclusively from this local volume.

### DNS Privacy Controls (Unbound + AdGuard)
The stack pairs a recursive Unbound resolver with AdGuard Home. These settings are enabled in `zima.sh` and are active by default:
*   **DNSSEC Hardening**: Unbound uses a root trust anchor and rejects stripped DNSSEC responses to prevent downgrade attacks.
*   **QNAME Minimization**: Only the minimum necessary DNS labels are sent upstream.
*   **Identity & Version Hiding**: Server identity/version are suppressed to reduce fingerprinting.
*   **0x20 Bit Randomization**: Randomized query casing helps mitigate spoofing.
*   **Hardened Glue + Cache Prefetch**: Reduces poisoning risk and limits upstream round trips.
*   **Private-Network Access Controls**: Resolver access is restricted to RFC1918 subnets only.
*   **Encrypted DNS Endpoints**: AdGuard exposes **DoH**, **DoT**, and **DoQ** on TLS with `allow_unencrypted_doh` disabled.
*   **Curated Blocklists**: AdGuard consumes the "sleepy list" generator output and includes explicit allow-rules for VPN and deSEC.

### VPN Firewall & HTTPS Hardening
*   **Gluetun Firewall Killswitch**: VPN-gated services can only reach the internet when the tunnel is up, with explicit inbound port whitelists.
*   **LAN Connectivity**: All traffic to upstream providers like YouTube and Reddit is relayed through the Gluetun VPN, ensuring these services never see your real home IP address. Local management tools remain directly accessible on your network.
*   **Hardened TLS Gateway**: Nginx is configured for TLS 1.2/1.3 with strong ciphers for HTTPS endpoints.

### 🛡️ Self-Healing & High Availability
The Privacy Hub is designed for long-term stability with automated recovery mechanisms:
*   **VPN Tunnel Monitoring**: The **Gluetun** container is continuously monitored for both control-plane health and actual internet connectivity (via `connectivity-check.ubuntu.com`). If the VPN tunnel stalls or the provider rotates the session, Docker automatically marks it unhealthy and restarts the gateway.
*   **Frontend Auto-Recovery**: All privacy frontends (Invidious, Redlib, etc.) utilize a `restart: always` policy. This ensures that if the underlying VPN network resets, the services will automatically restart and reconnect to the fresh tunnel.
*   **Resource Management**: Every service has strict **CPU and Memory limits** (e.g., Invidious is capped at 1024MB RAM) to prevent memory leaks or background processes from causing host-system starvation during idle periods.
*   **Upstream Rate Limits & Blocking**: Frontends like Invidious or Scribe may occasionally appear "unavailable" if the upstream provider (YouTube/Medium) blocks the shared VPN IP. Our health checks detect these hangs and automatically restart the frontend, which often triggers a VPN session rotation to a fresh IP.
*   **Health-Gated Launch**: Infrastructure services (DNS, VPN) must be verified as `healthy` before the high-level frontends are allowed to start, preventing "zombie" containers that have no network access.

### Telemetry Controls
*   **Portainer Analytics Disabled**: Portainer is programmatically configured with the `--no-analytics` flag during deployment, ensuring no telemetry is sent to third-party servers without user intervention. This can be verified in the Portainer settings UI under "Anonymous Statistics".

### Data Minimization & Anonymous Interactions
The stack is engineered to prevent identifying leaks during external interactions:
*   **Encapsulated Requests**: All external calls (asset synchronization, update checks, and connectivity health checks) are routed through the **Gluetun VPN proxy**. Upstream providers see only the VPN's shared commercial IP, never your home address.
*   **Specific User-Agent Signatures**: Requests originate using industry-standard signatures to blend in with legitimate traffic:
    *   **General Requests**: Uses a modern Linux Chrome signature (`Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36...`) for asset synchronization and connectivity checks.
    *   **Service Specifics**: The Odido booster utilizes a specialized mobile signature (`T-Mobile 5.3.28 (Android 10; 10)`) to perfectly mimic the official application environment and avoid "unauthorized client" blocks.
    *   **Impact**: This prevents upstream providers from identifying the traffic as coming from a specialized self-hosting tool, reducing the likelihood of automated blocking.
*   **Zero Personal Data**: No API keys, hardware IDs, or account-linked tokens are transmitted to external infrastructure during these routine maintenance and stability checks.
*   **Isolated Environment**: Requests are executed from within the `hub-api` container, which lacks access to your personal files or host-system environment variables.

### Proton Pass Export
When using `-p`, a verified CSV is generated at `/DATA/AppData/privacy-hub/protonpass_import.csv` for easy import.

<a id="proton-pass-import"></a>
**👇 How to Import into Proton Pass**

1.  **Download the CSV**: Transfer `protonpass_import.csv` to your machine.
2.  **Open Proton Pass**: Settings → Import → Select Proton Pass (CSV).
3.  **Upload**: The format matches the official template (`name,url,email,username,password,note,totp,vault`).

---
*Built with ❤️ for the self-hosting community.*

## 🖥️ System Requirements & Scaling

### Minimum Specifications

| Component | Minimum | Recommended | Notes |
|-----------|---------|-------------|-------|
| **CPU** | 2 Physical Cores | 4+ Cores (8 threads) | Compilation is **core-bound** not thread-bound |
| **RAM** | 4 GB | 8 GB | Invidious database requires 512MB minimum |
| **Storage** | 32 GB | 64 GB SSD | Postgres WAL logs grow over time |
| **Network** | 100 Mbps | Gigabit | VPN tunnel limited by upstream provider |
| **OS** | Ubuntu 22.04 LTS | Debian 12 / Alpine 3.19+ | Must support Docker 24.0+ |

---

### Pre-Configured Resource Limits

Each service has strict CPU/RAM caps to prevent host exhaustion:
```yaml
# Example from docker-compose.yml
invidious:
  deploy:
    resources:
      limits: {cpus: '1.5', memory: 1024M}

gluetun:
  deploy:
    resources:
      limits: {cpus: '2.0', memory: 512M}
```

**Supports up to 30 concurrent users** on a 16GB RAM machine (based on load testing).

---

### Scaling Strategies

**For Households (1-5 users):**
- Default configuration is optimal
- No tuning required

**For Small Organizations (6-30 users):**
- Increase Invidious memory: `memory: 2048M`
- Add Redis cache: `maxmemory 512mb`
- Enable Postgres connection pooling

### ⏱️ Performance Expectations

**Initial Deployment Timeline:**

| Phase | Duration | What's Happening |
|-------|----------|------------------|
| Environment Validation | 1-2 min | Checking dependencies, authenticating registries |
| Image Downloads | 3-5 min | Pulling base images (nginx, postgres, redis, etc.) |
| Source Code Compilation | 8-15 min | Building Invidious, Wikiless, Scribe from source |
| Service Startup | 2-3 min | Containers initializing, databases migrating |
| **Total** | **15-25 min** | *First-time deployment on typical hardware* |

**🔥 CPU/RAM Spike Warning:**  
During the "Source Code Compilation" phase, expect:
- CPU: 80-100% utilization (all cores)
- RAM: 4-6 GB active usage
- Disk I/O: Heavy write activity

**This is normal.** Modern compilers are aggressive. The dashboard will show elevated metrics during builds.

**Subsequent Updates:**  
Rebuilding a single service (e.g., Invidious) takes 3-5 minutes. The background update system prevents UI lockups.

<a id="advanced-setup"></a>
## 📡 Advanced Setup: OpenWrt & Double NAT

If you are behind an ISP modem *and* an OpenWrt router (Double NAT), you must ensure traffic reaches the Hub by repeating the port forwarding step on both devices.

**Configuration Workflow:**
1.  **ISP Modem**: Forward UDP Port 51820 to the **WAN IP** of your OpenWrt router.
2.  **OpenWrt Router**: Forward UDP Port 51820 to the **Local IP** of your Privacy Hub (using the commands in the [Network Configuration](#network-configuration) section).
3.  **Forced DNS**: Apply the NAT redirection rules on your OpenWrt router to catch rogue DNS traffic as described above.

## 💾 Migration & Backup

### Automated Backups

The stack creates **automatic safety backups** before any destructive operation:

- **Service Updates**: Pre-update snapshot saved to `/DATA/AppData/privacy-hub/data/backups/`
- **Database Migrations**: Timestamped SQL dumps before schema changes
- **Full System**: `./zima.sh -c` triggers complete backup before cleanup

**Manual Backup Command:**
```bash
docker exec hub-api python3 -c "import sys; sys.path.append('/app'); from server import *; migrate_service('all', 'backup-all', 'yes')"
```

---

### Restore from Backup

**Restore Invidious Database:**
```bash
# Find latest backup
ls -lh /DATA/AppData/privacy-hub/data/backups/invidious_*.sql

# Restore (replace TIMESTAMP with your backup date)
cat /DATA/AppData/privacy-hub/data/backups/invidious_TIMESTAMP.sql | \
  docker exec -i invidious-db psql -U kemal invidious
```

**Restore Entire Stack Configuration:**
```bash
# Backup location
tar -czf ~/privacy-hub-backup.tar.gz /DATA/AppData/privacy-hub/

# Restore on new machine
tar -xzf ~/privacy-hub-backup.tar.gz -C /
cd /DATA/AppData/privacy-hub
./zima.sh  # Rebuild containers with existing config
```

---

### Migrate to New Hardware

1. **On Old Machine:**
```bash
   # Stop stack
   docker compose -f /DATA/AppData/privacy-hub/docker-compose.yml down
   
   # Backup everything
   tar -czf /tmp/privacy-hub-migration.tar.gz /DATA/AppData/privacy-hub/
```

2. **Transfer File** (`scp`, USB drive, etc.)

3. **On New Machine:**
```bash
   # Extract
   sudo tar -xzf /tmp/privacy-hub-migration.tar.gz -C /
   
   # Update LAN IP in configs
   cd /DATA/AppData/privacy-hub
   OLD_IP="192.168.1.100"  # Your old IP
   NEW_IP="192.168.1.200"  # Your new IP
   find . -type f -exec sed -i "s/$OLD_IP/$NEW_IP/g" {} +
   
   # Rebuild
   ./zima.sh
```

4. **Update Router DNS** to point to new machine IP

<a id="add-your-own-services"></a>
<details>
<summary><strong>🔧 Add Your Own Services</strong> (advanced)</summary>

### 1) Service Definition (Orchestration Layer)
Locate **SECTION 13** in `zima.sh` (search for `# --- SECTION 13: ORCHESTRATION LAYER`). Add your service block using the `should_deploy` check to enable selective deployment.

```bash
if should_deploy "myservice"; then
cat >> "$COMPOSE_FILE" <<EOF
  myservice:
    image: my-image:latest
    container_name: myservice
    networks: [frontnet]
    # For VPN routing, uncomment the next two lines:
    # network_mode: "service:gluetun"
    # depends_on: gluetun: {condition: service_healthy}
    restart: unless-stopped
EOF
fi
```

### 2) Monitoring & Health (Status Logic)
Update the service status loop inside the `WG_API_SCRIPT` heredoc in `zima.sh` (search for `Check individual privacy services status internally`).

- Add `"myservice:1234"` to the `for srv in ...` list.
- If the service is routed through Gluetun, add `myservice` to the case that maps `TARGET_HOST="gluetun"`.

### 3) Dashboard UI
Add your service metadata to the `services.json` catalog generated in `zima.sh` (search for `services.json`). The dashboard reads this catalog at runtime and renders cards dynamically.

</details>

---
*Built with ❤️ for the self-hosting community.*
