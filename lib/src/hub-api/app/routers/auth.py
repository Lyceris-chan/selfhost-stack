"""Authentication and session management router for the Privacy Hub API.

This module provides endpoints for admin verification, session cleanup control,
and API key rotation.
"""

import os
import json
import secrets
from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel
from ..core.security import create_session, get_admin_user
from ..core.config import settings
from ..utils.logging import log_structured

router = APIRouter()


class VerifyAdminRequest(BaseModel):
    """Schema for admin password verification."""

    password: str


class ToggleSessionRequest(BaseModel):
    """Schema for toggling session cleanup."""

    enabled: bool


class RotateKeyRequest(BaseModel):
    """Schema for API key rotation."""

    new_key: str


@router.post("/verify-admin")
def verify_admin(request: VerifyAdminRequest):
    """Verifies the admin password and creates a session token.

    Args:
        request: The verification request containing the password.

    Returns:
        A dictionary with success status, session token, and cleanup state.
    """
    if (
        settings.ADMIN_PASS_RAW
        and request.password
        and secrets.compare_digest(request.password, settings.ADMIN_PASS_RAW)
    ):
        # Determine timeout
        timeout_seconds = 1800
        theme_file = os.path.join(settings.CONFIG_DIR, "theme.json")
        if os.path.exists(theme_file):
            try:
                with open(theme_file, "r") as f:
                    t = json.load(f)
                    if "session_timeout" in t:
                        timeout_seconds = int(t["session_timeout"]) * 60
            except Exception:
                pass

        token = create_session(timeout_seconds)
        # Import global var to get current state
        from ..core.security import session_state

        return {
            "success": True,
            "token": token,
            "cleanup": session_state["cleanup_enabled"],
        }
    else:
        raise HTTPException(status_code=401, detail="Invalid admin password")


@router.post("/toggle-session-cleanup")
def toggle_session_cleanup(
    request: ToggleSessionRequest, user: str = Depends(get_admin_user)
):
    """Toggles the automated session cleanup background task.

    Args:
        request: Toggle request containing the desired state.
        user: The authenticated admin user.

    Returns:
        The updated cleanup state.
    """
    from ..core.security import session_state

    session_state["cleanup_enabled"] = request.enabled
    return {"success": True, "enabled": request.enabled}


@router.post("/rotate-api-key")
def rotate_api_key(request: RotateKeyRequest, user: str = Depends(get_admin_user)):
    """Rotates the HUB_API_KEY used for inter-service communication.

    Args:
        request: Key rotation request containing the new key.
        user: The authenticated admin user.

    Returns:
        Success status of the rotation.
    """
    if request.new_key:
        # Security: Sanitize the key to prevent environment variable injection.
        # We only allow alphanumeric characters.
        sanitized_key = "".join(c for c in request.new_key if c.isalnum())
        if not sanitized_key or len(sanitized_key) < 16:
            raise HTTPException(
                status_code=400, detail="Key does not meet security requirements."
            )

        file_secrets = {}
        if os.path.exists(settings.SECRETS_FILE):
            with open(settings.SECRETS_FILE, "r") as f:
                for line in f:
                    if "=" in line:
                        k, v = line.strip().split("=", 1)
                        # Remove quotes if present to avoid nesting
                        v = v.strip("'").strip('"')
                        file_secrets[k] = v

        file_secrets["HUB_API_KEY"] = sanitized_key
        # Also update ODIDO_API_KEY for consistency as they are used interchangeably in the stack
        file_secrets["ODIDO_API_KEY"] = sanitized_key

        # Write back with restricted permissions and proper quoting
        try:
            fd = os.open(
                settings.SECRETS_FILE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600
            )
            with os.fdopen(fd, "w") as f:
                for k, v in file_secrets.items():
                    f.write(f"{k}='{v}'\n")
        except Exception as e:
            raise HTTPException(
                status_code=500, detail=f"Failed to update secrets: {str(e)}"
            )

        log_structured("SECURITY", "Dashboard API key rotated", "AUTH")
        return {"success": True}
    else:
        raise HTTPException(status_code=400, detail="New key required")
