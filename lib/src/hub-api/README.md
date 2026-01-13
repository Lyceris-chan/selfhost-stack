# Privacy Hub API

## Overview
The **Hub API** is the local control plane for the self-hosted privacy stack. This lightweight Python service manages the following tasks:
- Managing WireGuard VPN profiles (generation, retrieval, and deletion).
- Monitoring system status (service health and disk usage).
- Handling updates for stack services (through Git or Docker).
- Interfacing with the core deployment scripts (`zima.sh` and `patches.sh`).

## Architecture
- **Language:** Python 3.11 (Alpine Linux)
- **Framework:** Custom `http.server` implementation (no heavy framework dependencies to keep the container size around 50MB).
- **Security:** 
    - Runs on an internal Docker network.
    - API endpoints are protected by the `HUB_API_KEY` or `ADMIN_PASS_RAW`.

## API Endpoints

### System and Health
- `GET /status`: Returns a JSON object with service health (healthy or unhealthy), VPN status, and storage metrics.
- `GET /logs`: Streams the main deployment log.

### WireGuard Management
- `GET /wg/config`: Returns the active WireGuard client configuration.
- `POST /wg/gen`: Generates a new WireGuard peer configuration.
- `DELETE /wg/profile`: Revokes an existing profile.

### Service Control
- `POST /update`: Triggers a stack update (Git pull and rebuild).
- `POST /restart`: Restarts specific containers.

## Proxied Connections and Integration
The Hub API acts as a secure intermediary for several stack components:
- **WireGuard Client Management**: Proxies requests to the `wg-easy` API (port 51821) to create, list, and delete inbound VPN clients.
- **VPN Status and Telemetry**: Interfaces with the `gluetun` control server (port 8000) to retrieve real-time tunnel status and public IP information.
- **Asset Download Proxy**: External resources (fonts and scripts) are fetched through the `gluetun` HTTP proxy (port 8888). This ensures that the host's home IP address is never exposed to CDNs; they only see the VPN tunnel IP address.
- **Odido API Integration**: Retrieves mobile data metrics by proxying authenticated requests to the Odido API.

## Development
To run locally for testing (outside the stack):
```bash
# Install dependencies
pip install psutil

# Run the server
python3 server.py
```

## Docker Integration
This service mounts the host's Docker socket (`/var/run/docker.sock`) to perform container management tasks.
