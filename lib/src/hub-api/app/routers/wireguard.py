"""WireGuard VPN client and profile management router for the Privacy Hub API.

This module provides endpoints for managing WireGuard clients via the WG-Easy API
and listing available VPN uplink profiles.
"""

import os

import httpx
from fastapi import APIRouter, Depends, HTTPException, Response
from pydantic import BaseModel

from ..core.config import settings
from ..core.security import get_admin_user
from ..utils.logging import log_structured

router = APIRouter()


async def get_wgeasy_session():
    """Authenticates with the WG-Easy API and returns session cookies.

    Returns:
        A CookieJar containing the authentication session, or None on failure.
    """
    password = settings.VPN_PASS_RAW or settings.ADMIN_PASS_RAW or ""
    wg_host = settings.WG_HOST or settings.LAN_IP
    try:
        url = f"http://{wg_host}:51821/api/session"
        async with httpx.AsyncClient() as client:
            resp = await client.post(url, json={"password": password}, timeout=5.0)
            if resp.status_code in (200, 204):
                return resp.cookies
    except Exception as err:
        log_structured("ERROR", f"WG Sign in Error: {err}", "NETWORK")
    return None


@router.get("/wg/clients")
async def get_clients(user: str = Depends(get_admin_user)):
    """Retrieves the list of configured WireGuard clients from WG-Easy.

    Args:
        user: Authenticated admin user.

    Returns:
        JSON list of WireGuard clients.
    """
    cookies = await get_wgeasy_session()
    if not cookies:
        raise HTTPException(status_code=500, detail="Failed to auth with WG-Easy")

    wg_host = settings.WG_HOST or settings.LAN_IP
    try:
        url = f"http://{wg_host}:51821/api/wireguard/client"
        async with httpx.AsyncClient(cookies=cookies) as client:
            resp = await client.get(url, timeout=5.0)
            return resp.json()
    except Exception as err:
        raise HTTPException(status_code=500, detail=str(err))


class CreateClientRequest(BaseModel):
    """Schema for creating a new WireGuard client."""

    name: str


@router.post("/wg/clients")
async def create_client(req: CreateClientRequest, user: str = Depends(get_admin_user)):
    """Creates a new WireGuard client configuration.

    Args:
        req: Request body containing the client name.
        user: Authenticated admin user.

    Returns:
        JSON representation of the created client.
    """
    cookies = await get_wgeasy_session()
    if not cookies:
        raise HTTPException(status_code=500, detail="Failed to auth with WG-Easy")

    wg_host = settings.WG_HOST or settings.LAN_IP
    try:
        url = f"http://{wg_host}:51821/api/wireguard/client"
        async with httpx.AsyncClient(cookies=cookies) as client:
            resp = await client.post(url, json={"name": req.name}, timeout=5.0)
            return resp.json()
    except Exception as err:
        raise HTTPException(status_code=500, detail=str(err))


@router.delete("/wg/clients/{client_id}")
async def delete_client(client_id: str, user: str = Depends(get_admin_user)):
    """Revokes and deletes a WireGuard client configuration.

    Args:
        client_id: ID of the client to delete.
        user: Authenticated admin user.

    Returns:
        JSON status or empty object.
    """
    cookies = await get_wgeasy_session()
    if not cookies:
        raise HTTPException(status_code=500, detail="Failed to auth with WG-Easy")

    wg_host = settings.WG_HOST or settings.LAN_IP
    try:
        url = f"http://{wg_host}:51821/api/wireguard/client/{client_id}"
        async with httpx.AsyncClient(cookies=cookies) as client:
            resp = await client.delete(url, timeout=5.0)
            return resp.json() if resp.content else {}
    except Exception as err:
        raise HTTPException(status_code=500, detail=str(err))


@router.get("/wg/clients/{client_id}/configuration")
async def get_client_config(client_id: str, user: str = Depends(get_admin_user)):
    """Downloads the WireGuard .conf file for a specific client.

    Args:
        client_id: ID of the client to retrieve configuration for.
        user: Authenticated admin user.

    Returns:
        A Response containing the raw .conf content.
    """
    cookies = await get_wgeasy_session()

    wg_host = settings.WG_HOST or settings.LAN_IP
    try:
        url = f"http://{wg_host}:51821/api/wireguard/client/{client_id}/configuration"
        async with httpx.AsyncClient(cookies=cookies) as client:
            resp = await client.get(url, timeout=5.0)
            return Response(content=resp.content, media_type="text/plain")
    except Exception as err:
        raise HTTPException(status_code=500, detail=str(err))


@router.get("/profiles")
def list_profiles(user: str = Depends(get_admin_user)):
    """Lists all available VPN uplink profiles (.conf files).

    Args:
        user: Authenticated admin user.

    Returns:
        A dictionary containing the list of profile names.
    """
    try:
        files = [
            f.replace(".conf", "")
            for f in os.listdir(settings.PROFILES_DIR)
            if f.endswith(".conf") and f != "active.conf" and f != "active"
        ]
        return {"profiles": sorted(files)}
    except Exception:
        return {"profiles": [], "error": "Failed to list profiles"}
