# 🛡️ Privacy Hub Stack

A comprehensive, self-hosted privacy infrastructure built on **Material Design 3**. Own your data, route through VPNs, and eliminate tracking with zero external dependencies.

---

<details>
<summary><strong>🚀 Quick Start</strong></summary>

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
</details>

<details>
<summary><strong>🖥️ Management Dashboard</strong></summary>

Built with strict adherence to **Material 3** principles, the dashboard provides a high-fidelity control plane:

- **Live Telemetry**: Real-time CPU and Memory usage per service.
- **Human Logs**: Cryptic system logs translated into plain English with meaningful icons.
- **Theme Support**: Native Light/Dark mode with system preference detection.
- **Maintenance**: One-click database optimization, log clearing, and schema migrations.
- **Secure Setup**: Integrated wizard for first-time deSEC and SSL configuration.
</details>

<details>
<summary><strong>📦 Included Services</strong></summary>

| Service | Category | Purpose |
| :--- | :--- | :--- |
| **Invidious** | Privacy Frontend | Anonymous YouTube browsing (No ads/tracking) |
| **Redlib** | Privacy Frontend | Lightweight Reddit interface |
| **Wikiless** | Privacy Frontend | Private Wikipedia access |
| **Memos** | Utility | Private knowledge base & note-taking |
| **AdGuard Home** | Infrastructure | Network-wide DNS filtering & Ad-blocking |
| **WireGuard** | Infrastructure | Secure remote access gateway |
| **Portainer** | Management | Advanced container orchestration |
| **VERT** | Utility | Local GPU-accelerated file conversion |
</details>

<details>
<summary><strong>🔧 Advanced: Adding Your Own Services</strong></summary>

You can easily extend the stack. Simply add a new block to **SECTION 13** in `zima.sh`:

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
*Note: Add a corresponding card in the Dashboard section to enable status monitoring.*
</details>

<details>
<summary><strong>🔒 Security & Credentials</strong></summary>

- **HUB_API_KEY**: Required for sensitive dashboard actions. Can be rotated via UI.
- **Zero-Leaks**: No external CDNs or trackers. All assets (fonts, icons) are hosted locally.
- **Redaction Mode**: "Safe Display Mode" blurs IPs and sensitive metadata for screenshots.
- **Secrets**: Core credentials stored in `/DATA/AppData/privacy-hub/.secrets`.
</details>

---
*Built with ❤️ for the self-hosting community.*