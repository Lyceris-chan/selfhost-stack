"""Privacy Hub API Gateway.

This module initializes the FastAPI application, configures middleware (CORS),
includes all service routers, and manages background worker threads for
telemetry and log synchronization.
"""

import json
import threading
from contextlib import asynccontextmanager

import uvicorn
from fastapi import Depends, FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware

from .core.config import settings
from .core.security import get_api_key_or_query_token, get_current_user
from .routers import auth, logs, odido, services, system, wireguard
from .services.background import (log_sync_thread, metrics_collector_thread,
                                  odido_retrieval_thread,
                                  update_metrics_activity)
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
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include Routers
app.include_router(auth.router)
app.include_router(system.router)
app.include_router(services.router)
app.include_router(wireguard.router)
app.include_router(logs.router)
app.include_router(odido.router)


@app.post("/watchtower")
async def watchtower_notification(
        request: Request, user: str = Depends(get_api_key_or_query_token)):
    """Receives and logs notifications from the Watchtower update service.

    Args:
        request: Incoming webhook request.
        user: Authenticated service user.

    Returns:
        Success status.
    """
    try:
        data = await request.json()
        log_structured("INFO", f"Watchtower Notification: {json.dumps(data)}",
                       "MAINTENANCE")
        return {"success": True}
    except Exception:
        # Fallback for non-JSON notifications
        body = await request.body()
        log_structured(
            "INFO",
            f"Watchtower Notification (Plain): {body.decode(errors='replace')}",
            "MAINTENANCE")
        return {"success": True}


@app.middleware("http")
async def update_activity_middleware(request: Request, call_next):
    """Middleware to track active monitoring for metrics collection.

    Args:
        request: The incoming request.
        call_next: The next middleware or endpoint.

    Returns:
        The response from the next middleware.
    """
    if request.url.path == "/metrics":
        update_metrics_activity()
    response = await call_next(request)
    return response


if __name__ == "__main__":
    uvicorn.run(
        "app.main:app", host="0.0.0.0", port=settings.PORT, log_level="info", access_log=False)