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
    """Save valid auth sessions to disk atomically."""
    try:
        os.makedirs(os.path.dirname(settings.SESSIONS_FILE), exist_ok=True)
        with session_lock:
            with tempfile.NamedTemporaryFile('w', dir=os.path.dirname(settings.SESSIONS_FILE), delete=False) as tf:
                json.dump(valid_sessions, tf)
                temp_name = tf.name
            os.replace(temp_name, settings.SESSIONS_FILE)
    except Exception as e:
        print(f"Session Save Error: {e}")
        if 'temp_name' in locals() and os.path.exists(temp_name):
            os.remove(temp_name)

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
    session_token: str = Security(session_token_header),
    query_token: str = Query(None, alias="token")
):
    # 1. Allow Read-Only Dashboard Endpoints without Auth
    # Note: In FastAPI, this is usually handled by not protecting those routes.
    # But since we might apply this globally or to a router, we can check logic here or structure it.
    # For now, we assume this dependency is used on PROTECTED routes.
    
    # 2. Watchtower
    if request.url.path.startswith('/watchtower'):
        return "watchtower"

    # 3. Check Session Token (Header or Query)
    token_to_check = session_token or query_token
    if token_to_check:
        with session_lock:
            if token_to_check in valid_sessions:
                if not session_cleanup_enabled or time.time() < valid_sessions[token_to_check]:
                    # Refresh session (slide window)
                    valid_sessions[token_to_check] = time.time() + 1800
                    return "admin"
                else:
                    del valid_sessions[token_to_check]

    # 4. Check API Key (Header or Query)
    key_to_check = api_key or query_token
    if settings.HUB_API_KEY and key_to_check and secrets.compare_digest(key_to_check, settings.HUB_API_KEY):
        return "api_key"

    raise HTTPException(status_code=401, detail="Unauthorized")

def create_session(timeout_seconds=1800):
    token = secrets.token_hex(24)
    with session_lock:
        valid_sessions[token] = time.time() + timeout_seconds
    save_sessions()
    return token
