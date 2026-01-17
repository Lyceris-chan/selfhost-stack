# Adding New Services to Privacy Hub

This guide details the process for integrating a new service into the Privacy Hub stack. The system generates a `docker-compose.yml` file dynamically using shell scripts, so adding a service requires modifying the generation logic.

## Overview

The core logic for defining services resides in `lib/services/compose.sh`. This script contains functions that conditionally append Docker Compose service definitions to the final configuration file.

## Source-Built Base Images

To ensure security and compatibility, services built from source (rather than pulled from a registry) use optimized base images defined within this repository.

| Service | Base Image Location | Description |
| :--- | :--- | :--- |
| **Hub API** | [`lib/src/hub-api/Dockerfile`](../lib/src/hub-api/Dockerfile) | `python:3.11-alpine` with build tools. |
| **Dashboard** | [`lib/src/dashboard/Dockerfile`](../lib/src/dashboard/Dockerfile) | `nginx:alpine` with hardened permissions. |
| **Scribe** | `lib/services/compose.sh` (Inline) | Multi-stage build using `node:16-alpine`, `crystal:1.11.2-alpine`, and `alpine:latest`. |
| **Cobalt (Web)** | `lib/services/compose.sh` (Inline) | Multi-stage build using `node:24-alpine` and `nginx:alpine`. |
| **Portainer** | `lib/services/compose.sh` (Inline) | `alpine:3.20` repackaged with Portainer binary. |

When adding a source-built service, prefer using **Alpine Linux** base images (`alpine:latest`, `python:3.11-alpine`, `node:lts-alpine`) to minimize footprint and attack surface.

## Step-by-Step Implementation

### 1. Define the Service Function

Open `lib/services/compose.sh` and create a new function named `append_<service_name>`. This function must follow the standard pattern:

1.  **Check Deployment Status:** Use `should_deploy` to verify if the user enabled this service.
2.  **Define Docker Configuration:** Append the YAML definition to `${COMPOSE_FILE}`.

**Example Template:**

```bash
append_myservice() {
  # 1. Check if service is enabled
  if ! should_deploy "myservice"; then
    return 0
  fi

  # 2. Append configuration
  cat >> "${COMPOSE_FILE}" <<EOF
  myservice:
    image: myservice/image:latest
    container_name: ${CONTAINER_PREFIX}myservice
    networks: [frontend]
    ports:
      - "${LAN_IP}:8080:80"
    environment:
      - "MY_ENV_VAR=value"
    volumes:
      - "${DATA_DIR}/myservice:/data"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:80/health"]
      interval: 30s
      timeout: 5s
      retries: 3
    restart: unless-stopped
    deploy:
      resources:
        limits: {cpus: '0.5', memory: 512M}
EOF
}
```

### 2. Service Configuration Guidelines

*   **Container Name:** Always use `${CONTAINER_PREFIX}servicename` to ensure consistent naming (default prefix is `hub-`).
*   **Networks:**
    *   `frontend`: For services that need to communicate with other stack containers or be exposed to the LAN.
    *   `mgmt`: For management services like Portainer or the Hub API.
    *   **VPN Routing:** To route traffic through Gluetun, use `network_mode: "container:${CONTAINER_PREFIX}gluetun"` instead of defining networks/ports.
*   **Volumes:** Use `${DATA_DIR}` for persistent storage.
*   **Resources:** Always define CPU and Memory limits to prevent one service from destabilizing the host.

### 3. Register the Service

After defining the function, scroll down to the `generate_compose` function in `lib/services/compose.sh`. Add a call to your new function in the appropriate section (e.g., "Utilities & Others").

```bash
generate_compose() {
  # ... existing code ...

  # Core Infrastructure
  append_hub_api
  # ...

  # Your New Service
  append_myservice

  # ...
}
```

### 4. (Optional) Advanced Configuration

If your service requires complex configuration files (e.g., Nginx configs, JSON settings) to be generated at runtime:

1.  Modify `lib/services/config.sh`.
2.  Create a `setup_myservice_config` function.
3.  Call this function in `lib/core/operations.sh` or within your `append_myservice` logic (if it's a simple pre-flight check).

### 5. Verify the Integration

To test your new service:

1.  Run the deployment script, enabling your service:
    ```bash
    ./zima.sh -s myservice
    ```
2.  Verify the generated `docker-compose.yml` in your project root or `tmp` directory contains your service definition.
3.  Check container status:
    ```bash
    docker logs hub-myservice
    ```

## Style Guide Compliance

Ensure your modifications adhere to the project's style standards:
*   **Indentation:** Use 2 spaces for indentation in shell scripts.
*   **Variables:** Quote all variables (e.g., `"${VAR}"`).
*   **Functions:** Use `lower_case_with_underscores` for function names.
*   **Locals:** Declare variables as `local` inside functions.
