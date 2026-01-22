"""Privacy Hub API Gateway.

This module serves as the main entry point for the Privacy Hub FastAPI
application. It orchestrates all API endpoints, manages background workers,
and configures middleware for security and CORS.

Architecture:
    - FastAPI application with lifespan management
    - Router-based modular endpoint organization
    - Background worker threads for continuous tasks
    - CORS middleware for cross-origin requests
    - Security headers middleware for XSS protection

Key Components:
    - Authentication & Session Management (auth router)
    - System Health & Metrics (system router)
    - Service Management (services router)
    - WireGuard VPN Configuration (wireguard router)
    - Gluetun VPN Status (gluetun router)
    - Log Streaming (logs router)
    - Odido Bundle Management (odido router)

Background Workers:
    - metrics_collector_thread: Collects Docker container metrics
    - log_sync_thread: Synchronizes deployment logs to database
    - odido_retrieval_thread: Polls Odido API for bundle status

Security Features:
    - API key authentication for service-to-service communication
    - Admin session tokens with configurable timeout
    - Security headers (X-Content-Type-Options, X-Frame-Options, etc.)
    - CORS with configurable origins
    - Input sanitization and validation via Pydantic

API Prefix:
    All routers are mounted under /api prefix to match dashboard expectations.
    Example: POST /api/verify-admin, GET /api/status

External Webhooks:
    - POST /watchtower: Receives update notifications from Watchtower

Lifecycle:
    1. Startup: Initialize database, ensure assets, start background threads
    2. Runtime: Handle API requests, background tasks run continuously
    3. Shutdown: Graceful termination (if configured)

Configuration:
    Environment variables managed via app.core.config.Settings
    See config.py for full configuration options

References:
    - FastAPI: https://fastapi.tiangolo.com/
    - Google Python Style Guide
    - Privacy Hub Documentation

Author: ZimaOS Privacy Hub Team
Version: 2.0.0
"""

import json
import threading
from contextlib import asynccontextmanager

import uvicorn
from fastapi import Depends, FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware

from .core.config import settings
from .core.security import get_api_key_or_query_token
from .routers import auth, gluetun, logs, odido, services, system, wireguard
from .services.background import (
    log_sync_thread,
    metrics_collector_thread,
    odido_retrieval_thread,
    update_metrics_activity,
)
from .utils.assets import ensure_assets
from .utils.logging import init_db, log_structured


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manages the application lifecycle, initializing DB and background workers."""
    # Startup
    init_db()
    ensure_assets()
    # Start background threads
    threading.Thread(target=metrics_collector_thread, daemon=True).start()
    threading.Thread(target=log_sync_thread, daemon=True).start()
    threading.Thread(target=odido_retrieval_thread, daemon=True).start()
    yield
    # Shutdown logic (if any) can go here


app = FastAPI(title=settings.APP_NAME, lifespan=lifespan)

# CORS configuration
allow_all_origins = "*" in settings.CORS_ORIGINS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"] if allow_all_origins else settings.CORS_ORIGINS,
    allow_credentials=not allow_all_origins,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include Routers with /api prefix to match Dashboard requests
app.include_router(auth.router, prefix="/api")
app.include_router(system.router, prefix="/api")
app.include_router(services.router, prefix="/api")
app.include_router(wireguard.router, prefix="/api")
app.include_router(gluetun.router, prefix="/api")
app.include_router(logs.router, prefix="/api")
app.include_router(odido.router, prefix="/api")


@app.post("/watchtower")
async def watchtower_notification(
    request: Request, user: str = Depends(get_api_key_or_query_token)
):
    """Receives and logs notifications from the Watchtower update service.

    Args:
        request: Incoming webhook request.
        user: Authenticated service user.

    Returns:
        Success status.
    """
    try:
        data = await request.json()
        log_structured(
            "INFO", f"Watchtower Notification: {json.dumps(data)}", "MAINTENANCE"
        )
        return {"success": True}
    except Exception:
        # Fallback for non-JSON notifications
        body = await request.body()
        log_structured(
            "INFO",
            f"Watchtower Notification (Plain): {body.decode(errors='replace')}",
            "MAINTENANCE",
        )
        return {"success": True}


@app.middleware("http")
async def security_headers_middleware(request: Request, call_next):
    """Middleware to add security headers and track active monitoring.

    Args:
        request: The incoming request.
        call_next: The next middleware or endpoint.

    Returns:
        The response from the next middleware with security headers.
    """
    if request.url.path == "/metrics":
        update_metrics_activity()
    response = await call_next(request)

    # Add security headers
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"

    return response


if __name__ == "__main__":
    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=settings.PORT,
        log_level="info",
        access_log=False,
    )
