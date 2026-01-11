import os
import json
import secrets
from fastapi import APIRouter, HTTPException, Depends, Request
from pydantic import BaseModel
from ..core.security import create_session, session_state, get_current_user
from ..core.config import settings
from ..utils.logging import log_structured

router = APIRouter()

class VerifyAdminRequest(BaseModel):
    password: str

class ToggleSessionRequest(BaseModel):
    enabled: bool

class RotateKeyRequest(BaseModel):
    new_key: str

@router.post("/verify-admin")
def verify_admin(request: VerifyAdminRequest):
    if settings.ADMIN_PASS_RAW and request.password and secrets.compare_digest(request.password, settings.ADMIN_PASS_RAW):
        # Determine timeout
        timeout_seconds = 1800
        theme_file = os.path.join(settings.CONFIG_DIR, "theme.json")
        if os.path.exists(theme_file):
            try:
                with open(theme_file, 'r') as f:
                    t = json.load(f)
                    if 'session_timeout' in t:
                        timeout_seconds = int(t['session_timeout']) * 60
            except Exception as e:
                pass
        
        token = create_session(timeout_seconds)
        # Import global var to get current state
        from ..core.security import session_state
        return {"success": True, "token": token, "cleanup": session_state["cleanup_enabled"]}
    else:
        raise HTTPException(status_code=401, detail="Invalid admin password")

@router.post("/toggle-session-cleanup")
def toggle_session_cleanup(request: ToggleSessionRequest, user: str = Depends(get_current_user)):
    from ..core.security import session_state
    session_state["cleanup_enabled"] = request.enabled
    return {"success": True, "enabled": request.enabled}

@router.post("/rotate-api-key")
def rotate_api_key(request: RotateKeyRequest, user: str = Depends(get_current_user)):
    if request.new_key:
        file_secrets = {}
        if os.path.exists(settings.SECRETS_FILE):
            with open(settings.SECRETS_FILE, 'r') as f:
                for line in f:
                    if '=' in line:
                        k, v = line.strip().split('=', 1)
                        file_secrets[k] = v
        
        file_secrets['HUB_API_KEY'] = request.new_key
        
        with open(settings.SECRETS_FILE, 'w') as f:
            for k, v in file_secrets.items():
                f.write(f"{k}={v}\n")
        
        log_structured("SECURITY", "Dashboard API key rotated", "AUTH")
        return {"success": True}
    else:
        raise HTTPException(status_code=400, detail="New key required")
