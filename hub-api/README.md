# Privacy Hub API

## Overview
The **Hub API** is the local control plane for the self-hosted privacy stack. It is a lightweight Python service responsible for:
- Managing WireGuard VPN profiles (generation, retrieval, deletion).
- Monitoring system status (service health, disk usage).
- Handling updates for stack services (via Git or Docker).
- Interfacing with the core deployment scripts (zima.sh, patches.sh).

## Architecture
- **Language:** Python 3.11 (Alpine Linux)
- **Framework:** Custom `http.server` implementation (no heavy framework dependencies like Flask/FastAPI to keep the container minimal ~50MB).
- **Security:** 
    - Runs on an internal Docker network (`dhi-frontnet`).
    - API endpoints are protected by the `HUB_API_KEY` (for Odido Booster) or `ADMIN_PASS_RAW` (for dashboard operations).

## API Endpoints

### System & Health
- `GET /status`: Returns JSON object with service health (healthy/unhealthy), VPN status, and storage metrics.
- `GET /logs`: Streams the main deployment log.

### WireGuard Management
- `GET /wg/config`: Returns the active WireGuard client configuration (conf/QR code data).
- `POST /wg/gen`: Generates a new WireGuard peer config.
- `DELETE /wg/profile`: Revokes an existing profile.

### Service Control
- `POST /update`: Triggers a stack update (git pull + rebuild).
- `POST /restart`: Restarts specific containers.

## Development
To run locally for testing (outside the stack):
```bash
# Install dependencies
pip install psutil

# Run server
python3 server.py
```

## Docker Integration
This service mounts the host's Docker socket (`/var/run/docker.sock`) to perform container management tasks.
