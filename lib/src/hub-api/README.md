# Privacy Hub API

The Privacy Hub API is the central control plane for your self-hosted privacy stack. It provides a secure interface for managing network configurations, monitoring system health, and orchestrating service updates.

## Core responsibilities

*   **VPN management**: Generates, retrieves, and deletes WireGuard VPN profiles.
*   **System monitoring**: Tracks service health, resource usage, and disk space.
*   **Service orchestration**: Handles service restarts and stack updates.
*   **Secure proxying**: Facilitates communication between the dashboard and backend services (like `wg-easy` and `gluetun`) while maintaining IP privacy.

## Architecture

*   **Language**: Python 3.11 (Alpine Linux)
*   **Framework**: [FastAPI](https://fastapi.tiangolo.com/) for high-performance, asynchronous API handling.
*   **Server**: [Uvicorn](https://www.uvicorn.org/) as the ASGI web server.
*   **Database**: SQLite for local structured logging and metrics.

## Security

The API implements several layers of security:

*   **Network isolation**: Operates on internal Docker networks (`frontend`, `mgmt`).
*   **Authentication**: Endpoints are protected by a unique `HUB_API_KEY` or the administrative password.
*   **Least privilege**: Uses a Docker proxy to limit access to the Docker socket.

## API reference

For a complete list of endpoints and their schemas, see the interactive documentation at `/docs` (Swagger UI) or `/redoc` when the service is running.

### Key endpoints

*   `GET /status`: Retrieves real-time stack health and VPN status.
*   `GET /metrics`: Returns resource usage metrics for all containers.
*   `POST /wg/gen`: Creates a new WireGuard peer configuration.
*   `POST /restart-stack`: Initiates a controlled restart of all stack services.

## Local development

To run the API locally for development:

1.  **Install dependencies**:
    ```bash
    pip install -r requirements.txt
    ```

2.  **Start the server**:
    ```bash
    python3 -m app.main
    ```

Note: Some features require access to the Docker socket or specific environment variables defined by the `zima.sh` script.

## Docker integration

This service interacts with the host's Docker daemon via a secure proxy to manage container states and retrieve real-time telemetry.