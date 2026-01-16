"""Security and authentication utilities for the Privacy Hub API.

This module provides session management, API key validation, and FastAPI
dependencies for securing endpoints.
"""

import json
import os
import secrets
import threading
import time

from fastapi import Depends, HTTPException, Query, Request, Security
from fastapi.security.api_key import APIKeyHeader

from ..utils.logging import log_structured
from .config import settings

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
            with open(settings.SESSIONS_FILE, 'r', encoding='utf-8') as f:
                data = json.load(f)
                now = time.time()
                with session_lock:
                    valid_sessions = {
                        t: expiry
                        for t, expiry in data.items() if expiry > now
                    }
    except Exception as err:
        log_structured("ERROR", f"Session Load Error: {err}", "SECURITY")


def save_sessions():
    """Save valid auth sessions to disk atomically with restricted permissions."""
    try:
        os.makedirs(os.path.dirname(settings.SESSIONS_FILE), exist_ok=True)
        with session_lock:
            # Use os.open with O_WRONLY | O_CREAT | O_TRUNC and mode 0o600
            # to ensure the file is created with restricted permissions from the start.
            fd = os.open(settings.SESSIONS_FILE,
                         os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, 'w') as f:
                json.dump(valid_sessions, f)
    except Exception as err:
        log_structured("ERROR", f"Session Save Error: {err}", "SECURITY")


def cleanup_sessions_thread():
    """Background thread to purge expired auth sessions."""
    while True:
        if session_state["cleanup_enabled"]:
            now = time.time()
            with session_lock:
                expired = [
                    t for t, expiry in valid_sessions.items() if now > expiry
                ]
                if expired:
                    for t in expired:
                        del valid_sessions[t]
                    # We save immediately if we removed something
                    save_sessions()
        time.sleep(60)


# Init sessions
load_sessions()
threading.Thread(target=cleanup_sessions_thread, daemon=True).start()


async def get_current_user(request: Request,
                           api_key: str = Security(api_key_header),
                           session_token: str = Security(session_token_header),
                           token_query: str = Query(None, alias="token")):
    """Authenticates the user via session token or API key.

    Args:
        request: The incoming request.
        api_key: Provided X-API-Key header.
        session_token: Provided X-Session-Token header.
        token_query: Provided 'token' query parameter (for EventSource).

    Returns:
        A string identifying the user role ('admin' or 'api_key').

    Raises:
        HTTPException: 401 if authentication fails.
    """
    # 1. Check Session Token (Header or Query) - Admin Privileges
    actual_session_token = session_token or token_query
    if actual_session_token:
        with session_lock:
            if actual_session_token in valid_sessions:
                if not session_state["cleanup_enabled"] or time.time(
                ) < valid_sessions[actual_session_token]:
                    # Refresh session (slide window)
                    valid_sessions[actual_session_token] = time.time() + 1800
                    return "admin"
                else:
                    del valid_sessions[actual_session_token]
            else:
                # Log invalid session token for debugging
                log_structured(
                    "WARN",
                    f"Invalid session token attempted: {actual_session_token[:8]}...",
                    "AUTH")

    # 2. Check API Key (Header) - API Key Privileges
    if settings.HUB_API_KEY and api_key and secrets.compare_digest(
            api_key, settings.HUB_API_KEY):
        return "api_key"

    raise HTTPException(status_code=401, detail="Unauthorized")


async def get_optional_user(request: Request,
                            api_key: str = Security(api_key_header),
                            session_token: str = Security(session_token_header)):
    """Dependency that returns 'guest' if no valid auth is found."""
    try:
        return await get_current_user(request, api_key, session_token, token_query=None)
    except HTTPException:
        return "guest"


async def get_api_key_or_query_token(api_key: str = Security(api_key_header),
                                     query_token: str = Query(None,
                                                              alias="token")):
    """Specific dependency for routes that support query tokens."""
    token = api_key or query_token
    if settings.HUB_API_KEY and token and secrets.compare_digest(
            token, settings.HUB_API_KEY):
        return "api_key"
    raise HTTPException(status_code=401, detail="Unauthorized")


async def get_admin_user(user: str = Depends(get_current_user)):
    """Enforces admin or API Key access for sensitive management routes."""
    if user == "admin" or user == "api_key":
        return user
    raise HTTPException(status_code=403,
                        detail="Forbidden: Admin session required")


def create_session(timeout_seconds=1800):
    """Creates a new admin session and persists it to disk.

    Returns:
        The generated session token.
    """
    token = secrets.token_hex(24)
    with session_lock:
        valid_sessions[token] = time.time() + timeout_seconds
    save_sessions()
    return token
