# Project Status & Todo

## Progress Tracker
- [x] **Rename "System Reset"**: Renamed to "REVERT: Rolling back deployment..." in all scripts.
- [x] **Documentation**: Update README with secrets warning.
- [x] **Architecture**: Document CDN/Asset fetching flow.
- [x] **Testing**: 
    - [x] Full deployment (`zima.sh`).
    - [x] Service health checks.
    - [x] Log verification (Containers & Console).
    - [x] UI Interaction tests (via Puppeteer/Scripts).
- [x] **Fixes**:
    - [x] Hub API socket import missing.
    - [x] Proxy wait loop logic.
    - [x] Gluetun HTTPPROXY env var.
    - [x] MCU.js download URL.

## CDN & Asset Fetching Flowchart

```mermaid
graph TD
    A[User/Script] -->|Starts Container| B(Hub API)
    B -->|Checks /assets Volume| C{Assets Exist?}
    C -->|Yes| D[Serve Locally via Nginx]
    C -->|No| E[Initiate Download]
    E -->|Configure Proxy| F[Gluetun Proxy :8888]
    F -->|Request| G[External CDNs]
    G -->|Fontlay/JSDelivr| F
    F -->|Response| E
    E -->|Save to Disk| H[/assets Volume]
    H --> D
```

**Status:** System Verified & Stable.