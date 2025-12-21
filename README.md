# 🛡️ Privacy Hub Stack

A comprehensive, self-hosted privacy infrastructure built on **Material Design 3**.
Own your data, route through VPNs, and eliminate tracking with zero external dependencies.

## 📚 Contents
- [🚀 Quick Start](#quick-start)
- [🖥️ Management Dashboard](#management-dashboard)
- [📦 Included Services](#included-services)
- [🔗 Service Access](#service-access-after-deploy)
- [🔧 Add Your Own Services](#add-your-own-services)
- [🌐 Network Configuration](#network-configuration)
- [📡 Advanced Setup: OpenWrt & Double NAT](#advanced-setup-openwrt--double-nat)
- [🔒 Security & Credentials](#security--credentials)

## 🚀 Quick Start

### Before You Run (Credentials)

Prepare these ahead of time so setup is smooth:

- **Docker Hub / DHI PAT (required)**: One username + PAT is used for both Docker Hub and `dhi.io`. Use a token with **pull/read** permissions only. This is required to pull hardened images and avoid rate limits. Create it at [Docker Hub Access Tokens](https://hub.docker.com/settings/security).
- **WireGuard config (recommended)**: A `.conf` from your VPN provider if you want VPN-routed frontends (Gluetun). Only ProtonVPN is tested (details below).
- **deSEC domain + API token (recommended)**: Enables DDNS + trusted SSL. Create a token in your deSEC account at [deSEC](https://desec.io).
- **GitHub token (optional)**: Classic PAT with `gist` scope only, used by the Scribe frontend for gist access. Create it at [GitHub Tokens](https://github.com/settings/tokens).
- **Odido OAuth token (optional, NL unlimited data)**: Used by Odido Booster. Get the OAuth token using [Odido Authenticator](https://github.com/GuusBackup/Odido.Authenticator). The Odido API may incur costs or limits; use at your own risk.

<details>
<summary><strong>ProtonVPN WireGuard (.conf) - tested path</strong></summary>

Only ProtonVPN is tested. The free tier works fine; premium servers might be faster, but we only use the VPN to proxy frontends and hide our IPs, so higher speeds and extra security features aren’t necessary here. In the ProtonVPN dashboard:

1. Go to **Downloads → WireGuard configuration**.
2. Enable **Port Forwarding** before creating the config.
3. Give the config a recognizable **name**.
4. Choose a server/region and download the `.conf`.
5. Paste the contents when the script prompts for the WireGuard configuration.

</details>

### Standard Deployment
```bash
./zima.sh
```

### Selective Deployment
Only deploy specific services to save resources (Infrastructure is always included):
```bash
./zima.sh -s invidious,memos,redlib
```

### Reset Environment
```bash
./zima.sh -c
```

## 🖥️ Management Dashboard

Built with strict adherence to **Material 3** principles, the dashboard provides a high-fidelity control plane:

- **Live Telemetry**: Real-time CPU and Memory usage per service.
- **Human Logs**: Cryptic system logs translated into plain English with meaningful icons.
- **Theme Support**: Native Light/Dark mode with system preference detection.
- **Maintenance**: One-click database optimization, log clearing, and schema migrations.
- **Easy Access**: Launch any service from a single dashboard with auto-switching links when SSL is configured.
- **Sensitive Actions**: No login is required to view the dashboard, but sensitive actions require the dashboard API key from `.secrets`.
- **Secure Setup**: Integrated wizard for first-time deSEC and SSL configuration.

## 📦 Included Services

| Service | Category | Purpose |
| :--- | :--- | :--- |
| **[Invidious](https://github.com/iv-org/invidious)** | Privacy Frontend | Anonymous YouTube browsing (No ads/tracking) |
| **[Redlib](https://github.com/redlib-org/redlib)** | Privacy Frontend | Lightweight Reddit interface |
| **[Wikiless](https://github.com/Metastem/Wikiless)** | Privacy Frontend | Private Wikipedia access |
| **[Memos](https://github.com/usememos/memos)** | Utility | Private knowledge base & note-taking |
| **[AdGuard Home](https://github.com/AdguardTeam/AdGuardHome)** | Infrastructure | Network-wide DNS filtering & Ad-blocking |
| **[WireGuard (WG-Easy)](https://github.com/wg-easy/wg-easy)** | Infrastructure | Secure remote access gateway |
| **[Portainer](https://github.com/portainer/portainer)** | Management | Advanced container orchestration |
| **[VERT](https://github.com/vert-sh/vert)** | Utility | Local file conversion with optional GPU acceleration (VERTD requires a valid SSL cert due to quirks, still local) |

## 🔗 Service Access (After Deploy)

The dashboard provides one-click launch cards for every service at `http://<LAN_IP>:8081`. If you prefer direct access, use the LAN URLs below. When deSEC is configured, HTTPS URLs are available at `https://<service>.<domain>:8443/` (or `https://<domain>:8443/` for the dashboard).

| Service | Local URL | HTTPS (deSEC) | Notes |
| :--- | :--- | :--- | :--- |
| Dashboard | `http://<LAN_IP>:8081` | `https://<domain>:8443/` | Management UI and service launcher. |
| Invidious | `http://<LAN_IP>:3000` | `https://invidious.<domain>:8443/` | VPN-routed; upstream sees VPN IP. |
| Redlib | `http://<LAN_IP>:8080` | `https://redlib.<domain>:8443/` | VPN-routed; upstream sees VPN IP. |
| Wikiless | `http://<LAN_IP>:8180` | `https://wikiless.<domain>:8443/` | VPN-routed; upstream sees VPN IP. |
| Memos | `http://<LAN_IP>:5230` | `https://memos.<domain>:8443/` | Local notes and knowledge base. |
| AdGuard Home | `http://<LAN_IP>:8083` | `https://adguard.<domain>:8443/` | DNS filtering UI. |
| WireGuard (WG-Easy) | `http://<LAN_IP>:51821` | `https://wireguard.<domain>:8443/` | VPN management UI. |
| Portainer | `http://<LAN_IP>:9000` | `https://portainer.<domain>:8443/` | Container management. |
| VERT | `http://<LAN_IP>:5555` | `https://vert.<domain>:8443/` | GPU acceleration uses `https://vertd.<domain>:8443/` and needs a valid SSL cert (still local). |

<details>
<summary><strong>🔧 Add Your Own Services</strong> (advanced, not needed for new users)</summary>

Everything lives in `zima.sh`, so one run rebuilds Docker Compose and the dashboard. Keep the service name consistent everywhere (Compose, monitoring, and UI IDs).

### 1) Add it to Compose (SECTION 13)

```bash
if should_deploy "myservice"; then
cat >> "$COMPOSE_FILE" <<EOF
  myservice:
    image: my-image:latest
    container_name: myservice
    networks: [frontnet]
    restart: unless-stopped
EOF
fi
```

If you want the service to run through the VPN, use `network_mode: "service:gluetun"` and `depends_on: gluetun` like the existing privacy frontends.

### 2) Monitoring & Health (status pill)

Update the service status loop inside the `wg-control.sh` heredoc in `zima.sh` (search for `Check individual privacy services status internally`).

- Add `"myservice:1234"` to the `for srv in ...` list.
- If the service is routed through Gluetun, add `myservice` to the case that maps `TARGET_HOST="gluetun"`.
- Optional: add a Docker `healthcheck` to surface `Healthy` rather than just `Online`.

### 3) Dashboard Card + Metrics + Portainer

Add a card in the dashboard HTML (SECTION 14 in `zima.sh`):

- Use `id="link-myservice"` and `data-container="myservice"`.
- Set `data-url="http://$LAN_IP:<port>"` for the LAN link.
- Add a `portainer-link` chip if you want one-click container management.
- Add a `metrics-myservice` block if you want CPU/memory chips to show.

Then add the service to the `const services = { ... }` map so the dashboard can auto-switch links to `https://<subdomain>.<domain>:8443/` when SSL is configured.

### 4) Watchtower Updates

- Watchtower updates all image-based containers by default.
- To opt out, add `com.centurylinklabs.watchtower.enable=false` under the service labels.
- For build-based services, Watchtower won't rebuild; re-run `./zima.sh` or use the dashboard Update flow.

### 5) Dashboard Update Banner (optional)

The Update banner checks git repos under `/app/sources/<service>`. If you want your service to appear there, keep its source repo in that path with a remote configured.

</details>

## 🌐 Network Configuration

### Standard Setup
Forward port **51820/UDP** to your host's local IP. This is the only exposed port and is cryptographically silent.

### Local LAN Mode
AdGuard Home utilizes DNS rewrites to direct internal traffic to your local IP, ensuring optimal performance and local SSL access.

## 📡 Advanced Setup: OpenWrt & Double NAT

<details>
<summary><strong>CLI: UCI Commands for OpenWrt Configuration</strong></summary>

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

## 🔒 Security & Credentials

- **HUB_API_KEY**: Required for sensitive dashboard actions. Can be rotated via UI.
- **Zero-Leaks**: No external CDNs or trackers. We never contact Google directly; fonts are downloaded once during setup (or if the cache is missing) via the Coollabs Google Fonts proxy ([privacy policy](https://coollabs.io/privacy-policy/)), with Fontlay as a fallback if Coollabs is unreachable. After download, fonts are served locally so no further font requests leave your machine.
- **Redaction Mode**: "Safe Display Mode" blurs IPs and sensitive metadata for screenshots.
- **Secrets**: Core credentials stored in `/DATA/AppData/privacy-hub/.secrets`.

### API Keys & Cost Notes

- **deSEC**: Domain + API token for dynamic DNS and SSL automation.
- **Docker Hub / DHI**: Username + PAT for registry pulls and rate-limit avoidance.
- **Odido Booster (NL unlimited data)**: OAuth token + user ID for Dutch Odido customers using the booster. The Odido API may incur costs or limits you are not expecting; use at your own risk.
- **Optional**: GitHub token (gist scope) for the Scribe frontend.

External services, registries, and APIs can change terms, rate limits, or pricing without notice. Usage is at your own risk, and the same caution applies to anything in this script that talks to third-party systems.

This script is provided as-is and may change whenever necessary or when I feel like it. Contributions are welcome, but I cannot guarantee updates will not break your setup. If you need to return to a clean state, the `-x` option removes everything and brings you back to where you were before running the script.

### Proton Pass Export (Auto-Generated Credentials)

When you run with `-p` (auto-passwords), the script generates a Proton Pass import CSV at `/DATA/AppData/privacy-hub/protonpass_import.csv`. Passwords and API tokens go into the **Password** column; descriptive context goes into **Note**.

| Entry | URL | Username | Password | Note |
| :--- | :--- | :--- | :--- | :--- |
| AdGuard Home | `http://<LAN_IP>:8083` | `adguard` | AdGuard password | DNS filtering UI. |
| WireGuard VPN UI | `http://<LAN_IP>:51821` | `admin` | WireGuard UI password | Remote access management. |
| Portainer UI | `http://<LAN_IP>:9000` | `portainer` | Portainer password | Container management. |
| deSEC DNS API | (none) | your deSEC domain | deSEC API token | Dynamic DNS + SSL automation. |
| GitHub Scribe Token | (none) | GitHub username | GitHub token | Scribe gist access. |

<details>
<summary><strong>External Services & Privacy Policies</strong></summary>

- **Public IP detection (used for DDNS and VPN sync)**:
  - [ipify.org](https://www.ipify.org/)
  - [ip-api.com](https://ip-api.com/docs/legal)
- **Fonts proxy and CDN**:
  - Coollabs Google Fonts proxy + CDN: [privacy policy](https://coollabs.io/privacy-policy/)
  - Fontlay Google Fonts proxy + CDN: [privacy policy + source code](https://github.com/miroocloud/fontlay)
- **DNS & SSL automation**:
  - deSEC API: [privacy policy](https://desec.io/privacy-policy)
- **Container registries**:
  - Docker Hub (includes DHI pulls): [privacy policy](https://www.docker.com/legal/docker-privacy-policy/)
  - GitHub Container Registry (GHCR): [privacy policy](https://docs.github.com/en/site-policy/privacy-policies/github-privacy-statement)
  - Quay.io: [privacy policy](https://quay.io/privacy)
  - Codeberg registry: [privacy policy](https://codeberg.org/privacy)
- **Source repositories (build-from-source + update checks)**:
  - GitHub: [privacy policy](https://docs.github.com/en/site-policy/privacy-policies/github-privacy-statement)
  - SourceHut: [privacy policy](https://man.sr.ht/privacy.md)
- **Blocklist source**:
  - GitHub raw (sleepy list): [privacy policy](https://docs.github.com/en/site-policy/privacy-policies/github-privacy-statement)
- **Odido API**:
  - Odido privacy policy: [privacy policy](https://www.odido.nl/privacy)

</details>

---
*Built with ❤️ for the self-hosting community.*
