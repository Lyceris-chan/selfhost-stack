# Xray (VLESS) Setup & Port Forwarding Guide

This system is configured to host a VLESS tunnel that routes all traffic through your home VPN (Gluetun). This allows friends in restricted regions (like Russia) to connect via a domain that is not blocked and use your privacy-hardened outbound connection.

## Enabling the Service
The Xray VLESS service is disabled by default. To enable it during deployment, use the `-X` flag:
```bash
./zima.sh -P -X
```
Alternatively, toggle the **Global VLESS Tunnel** switch in the Dashboard under **Security & Privacy** and restart the stack.

## Recommended Domain
For users in restricted regions (e.g., Russia), it is highly recommended to use a standard **.com** or **.net** domain rather than dynamic DNS subdomains (like .dedyn.io), as generic TLDs are less likely to be flagged by ISP deep packet inspection (DPI).

## Infrastructure Details
- **Protocol:** VLESS
- **Port:** 443 (TLS)
- **Routing:** All Xray traffic is forced through the active WireGuard profile in Gluetun.
- **Certificate:** Reuses the Let's Encrypt / deSEC certificate managed by the Privacy Hub.

## Critical Action: Port Forwarding (Double NAT Setup)

Since your network is behind two routers (ISP Router and OpenWrt Router), you must perform a "chained" port forward.

### 1. ISP Router (Outer)
- **Goal:** Direct traffic from the internet to your OpenWrt router.
- **Action:** Forward Port **443 (TCP)** to the **WAN IP** of your OpenWrt router.
- *Note: Check your OpenWrt Status page to find its WAN IP (usually something like 192.168.1.x).*

### 2. OpenWrt Router (Inner)
- **Goal:** Direct traffic from the ISP router to this host machine.
- **Action:** 
    1. Go to **Network -> Firewall -> Port Forwards**.
    2. Add a new rule:
        - **Name:** `Xray-VLESS`
        - **Protocol:** `TCP`
        - **External port:** `443`
        - **Internal IP:** `10.0.12.135` (Your Host LAN IP)
        - **Internal port:** `443`
    3. Click **Save & Apply**.

## Client Configuration (for your friend)
Give these details to your friend to put in their V2Ray/Xray client (e.g., v2rayN, Shadowrocket, Nekobox):

- **Address:** Your deSEC Domain (e.g. `example.dedyn.io`)
- **Port:** 443
- **UUID:** (Find this in the Dashboard under Security & Privacy)
- **Flow:** (empty)
- **Encryption:** none
- **Network:** tcp
- **Header Type:** none
- **Security:** tls
- **SNI:** Your deSEC Domain
- **Fingerprint:** chrome

---
*Note: This configuration is automatically generated and updated by the Privacy Hub scripts when ENABLE_XRAY=true is set.*
