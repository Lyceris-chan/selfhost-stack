# 🧪 Testing Procedures

This document outlines the testing standards and procedures for the ZimaOS Privacy Hub. Following these guidelines ensures that the stack remains stable, secure, and performant.

---

## 📖 Table of Contents
- [Overview](#-overview)
- [Automated UI Testing](#-automated-ui-testing)
- [Integration Testing](#-integration-testing)
- [Manual Verification](#-manual-verification)
- [Log Auditing](#-log-auditing)

---

## 🚀 Overview

Testing is divided into three main layers:
1.  **Unit/Functional Tests**: Validating individual components (Hub API, helper scripts).
2.  **Integration Tests**: Ensuring services communicate correctly (DNS resolution, VPN routing).
3.  **UI Audit**: Verifying the Material Design 3 dashboard and user interactions.

---

## 🎭 Automated UI Testing

The Hub uses a Puppeteer-based suite to perform visual and functional audits of the management dashboard.

### Running the UI Audit
Ensure the stack is running, then execute:
```bash
cd test
npm install
node verify_ui.js
```

### What is verified?
-   **Visual Regression**: Checks for overlapping components or layout shifts in M3 elements.
-   **Theme Switching**: Verifies that dynamic theming applies correctly to the DOM.
-   **Authentication**: Simulates admin sign-in and session persistence.
-   **Interaction**: Tests "Click-to-Copy" and modal behavior.

---

## 🔗 Integration Testing

Verification of the network stack and service orchestration.

### DNS Integrity
Verify that Unbound is resolving recursively and AdGuard is filtering:
```bash
# Test local resolution
dig @<HUB_IP> example.com

# Test blocklist filtering (should return 0.0.0.0 or NXDOMAIN)
dig @<HUB_IP> doubleclick.net
```

### VPN Kill-Switch
Verify that VPN-isolated services cannot reach the internet when Gluetun is down:
```bash
docker stop hub-gluetun
docker exec -it hub-invidious curl -I example.com # Should fail
```

---

## 📝 Log Auditing

During testing, logs should be audited for high-severity errors or repeated warnings.

### Automated Log Check
The Hub API provides a structured log endpoint that is audited during the UI suite:
```bash
curl -H "X-Session-Token: <TOKEN>" http://<HUB_IP>:8088/api/logs?level=ERROR
```

---

## 🛠️ Manual Verification

Before every release, the following manual checks are performed:
1.  **WireGuard Connectivity**: Connect a mobile device via QR code and verify ad-blocking on LTE.
2.  **Source Rebuilds**: Trigger a manual update for a source-built service (e.g., Wikiless) and verify success.
3.  **Credential Export**: Import the generated `protonpass_import.csv` into a test vault.

---

*Built with ❤️ for digital sovereignty.*
