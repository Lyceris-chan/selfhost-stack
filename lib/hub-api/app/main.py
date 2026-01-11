import threading
import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from .core.config import settings
from .utils.logging import init_db
from .utils.assets import ensure_assets
from .routers import auth, system, services, wireguard, logs
from .services.background import metrics_collector_thread, log_sync_thread, update_metrics_activity

app = FastAPI(title=settings.APP_NAME)

# CORS
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

@app.on_event("startup")
def startup_event():
    init_db()
    ensure_assets()
    # Start background threads
    threading.Thread(target=metrics_collector_thread, daemon=True).start()
    threading.Thread(target=log_sync_thread, daemon=True).start()
    # Note: Session cleanup is started in security.py on import.

@app.middleware("http")
async def update_activity_middleware(request, call_next):
    if request.url.path == "/metrics":
        update_metrics_activity()
    response = await call_next(request)
    return response

if __name__ == "__main__":
    uvicorn.run("app.main:app", host="0.0.0.0", port=settings.PORT, log_level="info")
