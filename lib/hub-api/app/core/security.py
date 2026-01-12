import json
import time
import os
import threading
import secrets
import tempfile
from fastapi import HTTPException, Security, Request, Depends, Query
from fastapi.security.api_key import APIKeyHeader
from .config import settings
from ..utils.logging import log_structured

api_key_header = APIKeyHeader(name="X-API-Key", auto_error=False)
session_token_header = APIKeyHeader(name="X-Session-Token", auto_error=False)

# Global session store
valid_sessions = {}
session_lock = threading.Lock()
session_state = {"cleanup_enabled": True}

def load_sessions():
    """Load auth sessions from disk and purge expired ones."""
    global valid_sessions
    try:
        if os.path.exists(settings.SESSIONS_FILE):
            with open(settings.SESSIONS_FILE, 'r') as f:
                data = json.load(f)
                now = time.time()
                with session_lock:
                    valid_sessions = {t: expiry for t, expiry in data.items() if expiry > now}
    except Exception as e:
        print(f"Session Load Error: {e}")

def save_sessions():
    """Save valid auth sessions to disk atomically with restricted permissions."""
    try:
        os.makedirs(os.path.dirname(settings.SESSIONS_FILE), exist_ok=True)
        with session_lock:
            # Use os.open with O_WRONLY | O_CREAT | O_TRUNC and mode 0o600
            # to ensure the file is created with restricted permissions from the start.
            fd = os.open(settings.SESSIONS_FILE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, 'w') as f:
                json.dump(valid_sessions, f)
    except Exception as e:
        print(f"Session Save Error: {e}")

def cleanup_sessions_thread():
    """Background thread to purge expired auth sessions."""
    global valid_sessions
    while True:
        if session_state["cleanup_enabled"]:
            now = time.time()
            with session_lock:
                expired = [t for t, expiry in valid_sessions.items() if now > expiry]
                if expired:
                    for t in expired:
                        del valid_sessions[t]
                    # We save immediately if we removed something
                    save_sessions()
        time.sleep(60)

# Init sessions
load_sessions()
threading.Thread(target=cleanup_sessions_thread, daemon=True).start()

async def get_current_user(
    request: Request,
    api_key: str = Security(api_key_header),
    session_token: str = Security(session_token_header)
):
    # 1. Check Session Token (Header) - Admin Privileges
    if session_token:
        with session_lock:
            if session_token in valid_sessions:
                if not session_state["cleanup_enabled"] or time.time() < valid_sessions[session_token]:
                    # Refresh session (slide window)
                    valid_sessions[session_token] = time.time() + 1800
                    return "admin"
                else:
                    del valid_sessions[session_token]

    # 2. Check API Key (Header) - API Key Privileges
    if settings.HUB_API_KEY and api_key and secrets.compare_digest(api_key, settings.HUB_API_KEY):
        return "api_key"

    raise HTTPException(status_code=401, detail="Unauthorized")

async def get_api_key_or_query_token(
    api_key: str = Security(api_key_header),
    query_token: str = Query(None, alias="token")
):
    """Specific dependency for routes that must support query tokens (e.g. Watchtower)."""
    token = api_key or query_token
    if settings.HUB_API_KEY and token and secrets.compare_digest(token, settings.HUB_API_KEY):
        return "api_key"
    raise HTTPException(status_code=401, detail="Unauthorized")

async def get_admin_user(user: str = Depends(get_current_user)):
    """Enforce admin-only access for sensitive management routes."""
    if user != "admin":
        raise HTTPException(status_code=403, detail="Forbidden: Admin session required")
    return user

def create_session(timeout_seconds=1800):
    token = secrets.token_hex(24)
    with session_lock:
        valid_sessions[token] = time.time() + timeout_seconds
    save_sessions()
    return token
