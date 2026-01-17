"""Gluetun VPN profile management router for the Privacy Hub API.

This module provides endpoints for uploading, activating, and deleting
WireGuard VPN uplink profiles for the Gluetun container.
"""

import os
import re
import subprocess
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from ..core.config import settings
from ..core.security import get_admin_user
from ..utils.logging import log_structured

router = APIRouter()


class UploadProfileRequest(BaseModel):
    """Schema for uploading a VPN profile."""

    name: str
    config: str


class ActivateProfileRequest(BaseModel):
    """Schema for activating a VPN profile."""

    name: str


class DeleteProfileRequest(BaseModel):
    """Schema for deleting a VPN profile."""

    name: str


def sanitize_profile_name(name: str) -> str:
    """Sanitizes profile name to prevent path traversal attacks.

    Args:
        name: The profile name to sanitize.

    Returns:
        Sanitized profile name safe for filesystem operations.
    """
    # Remove any path separators and only allow alphanumeric, dash, underscore
    sanitized = re.sub(r"[^a-zA-Z0-9_-]", "", name)
    if not sanitized or sanitized != name:
        raise HTTPException(
            status_code=400,
            detail="Invalid profile name. Use only letters, numbers, dash, underscore.",
        )
    return sanitized


@router.post("/upload")
def upload_profile(req: UploadProfileRequest, user: str = Depends(get_admin_user)):
    """Uploads a new WireGuard VPN configuration profile.

    Args:
        req: Upload request containing profile name and config content.
        user: Authenticated admin user.

    Returns:
        Success status and the sanitized profile name.
    """
    try:
        # Extract profile name from config if not provided or use provided name
        profile_name = req.name.strip() if req.name else None
        config_content = req.config.strip()

        if not config_content:
            raise HTTPException(status_code=400, detail="Config content is required")

        # Try to extract name from config comments if not provided
        if not profile_name:
            for line in config_content.split("\n"):
                line = line.strip()
                if line.startswith("#") and "=" not in line:
                    # First non-key comment line is likely the profile name
                    potential_name = line.lstrip("#").strip()
                    if potential_name and len(potential_name) < 50:
                        profile_name = potential_name
                        break

        if not profile_name:
            profile_name = "vpn-profile"

        # Sanitize the name
        safe_name = sanitize_profile_name(profile_name)

        # Write to profiles directory
        profile_path = os.path.join(settings.PROFILES_DIR, f"{safe_name}.conf")

        # Ensure directory exists
        os.makedirs(settings.PROFILES_DIR, exist_ok=True)

        with open(profile_path, "w", encoding="utf-8") as f:
            f.write(config_content)

        # Set appropriate permissions
        os.chmod(profile_path, 0o600)

        log_structured(
            "INFO", f"VPN profile '{safe_name}' uploaded successfully", "VPN"
        )
        return {
            "success": True,
            "name": safe_name,
            "message": "Profile uploaded successfully",
        }

    except HTTPException:
        raise
    except Exception as err:
        log_structured("ERROR", f"Profile upload failed: {err}", "VPN")
        raise HTTPException(status_code=500, detail=str(err))


@router.post("/activate")
def activate_profile(req: ActivateProfileRequest, user: str = Depends(get_admin_user)):
    """Activates a VPN profile by symlinking it and restarting Gluetun.

    Args:
        req: Activation request containing the profile name.
        user: Authenticated admin user.

    Returns:
        Success status.
    """
    try:
        safe_name = sanitize_profile_name(req.name)
        profile_path = os.path.join(settings.PROFILES_DIR, f"{safe_name}.conf")

        if not os.path.exists(profile_path):
            raise HTTPException(status_code=404, detail="Profile not found")

        # Create symlink to active.conf
        active_link = os.path.join(settings.PROFILES_DIR, "active.conf")

        # Remove existing symlink if present
        if os.path.exists(active_link) or os.path.islink(active_link):
            os.remove(active_link)

        # Create new symlink
        os.symlink(profile_path, active_link)

        # Restart Gluetun container to apply new profile
        try:
            subprocess.run(
                ["docker", "restart", f"{settings.CONTAINER_PREFIX}gluetun"],
                check=True,
                timeout=30,
                capture_output=True,
            )
        except subprocess.TimeoutExpired:
            log_structured("WARN", "Gluetun restart timed out", "VPN")
        except subprocess.CalledProcessError as e:
            log_structured("ERROR", f"Failed to restart Gluetun: {e.stderr}", "VPN")

        log_structured("INFO", f"VPN profile '{safe_name}' activated", "VPN")
        return {"success": True, "message": "Profile activated. VPN restarting."}

    except HTTPException:
        raise
    except Exception as err:
        log_structured("ERROR", f"Profile activation failed: {err}", "VPN")
        raise HTTPException(status_code=500, detail=str(err))


@router.post("/delete")
def delete_profile(req: DeleteProfileRequest, user: str = Depends(get_admin_user)):
    """Deletes a VPN profile from the filesystem.

    Args:
        req: Delete request containing the profile name.
        user: Authenticated admin user.

    Returns:
        Success status.
    """
    try:
        safe_name = sanitize_profile_name(req.name)
        profile_path = os.path.join(settings.PROFILES_DIR, f"{safe_name}.conf")

        if not os.path.exists(profile_path):
            raise HTTPException(status_code=404, detail="Profile not found")

        # Don't allow deletion of active profile
        active_link = os.path.join(settings.PROFILES_DIR, "active.conf")
        if os.path.islink(active_link):
            if os.path.realpath(active_link) == os.path.realpath(profile_path):
                raise HTTPException(
                    status_code=400,
                    detail="Cannot delete active profile. Switch to another profile first.",
                )

        os.remove(profile_path)

        log_structured("INFO", f"VPN profile '{safe_name}' deleted", "VPN")
        return {"success": True, "message": "Profile deleted successfully"}

    except HTTPException:
        raise
    except Exception as err:
        log_structured("ERROR", f"Profile deletion failed: {err}", "VPN")
        raise HTTPException(status_code=500, detail=str(err))
