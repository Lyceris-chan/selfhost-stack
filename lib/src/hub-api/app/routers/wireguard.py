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
  try:
    url = f"http://{settings.CONTAINER_PREFIX}wg-easy:51821/api/session"
    async with httpx.AsyncClient() as client:
      resp = await client.post(url, json={"password": password}, timeout=5.0)
      if resp.status_code in (200, 204):
        return resp.cookies
  except Exception as e:
    log_structured("ERROR", f"WG Sign in Error: {e}", "NETWORK")
  return None


@router.get("/wg/clients")
async def get_clients(user: str = Depends(get_admin_user)):
  """Retrieves the list of configured WireGuard clients from WG-Easy."""
  cookies = await get_wgeasy_session()
  if not cookies:
    raise HTTPException(status_code=500, detail="Failed to auth with WG-Easy")
  try:
    url = f"http://{settings.CONTAINER_PREFIX}wg-easy:51821/api/wireguard/client"
    async with httpx.AsyncClient(cookies=cookies) as client:
      resp = await client.get(url, timeout=5.0)
      return resp.json()
  except Exception as e:
    raise HTTPException(status_code=500, detail=str(e))


class CreateClientRequest(BaseModel):
  """Schema for creating a new WireGuard client."""
  name: str


@router.post("/wg/clients")
async def create_client(req: CreateClientRequest,
                        user: str = Depends(get_admin_user)):
  """Creates a new WireGuard client configuration."""
  cookies = await get_wgeasy_session()
  if not cookies:
    raise HTTPException(status_code=500, detail="Failed to auth with WG-Easy")
  try:
    url = f"http://{settings.CONTAINER_PREFIX}wg-easy:51821/api/wireguard/client"
    async with httpx.AsyncClient(cookies=cookies) as client:
      resp = await client.post(url, json={"name": req.name}, timeout=5.0)
      return resp.json()
  except Exception as e:
    raise HTTPException(status_code=500, detail=str(e))


@router.delete("/wg/clients/{client_id}")
async def delete_client(client_id: str, user: str = Depends(get_admin_user)):
  """Revokes and deletes a WireGuard client configuration."""
  cookies = await get_wgeasy_session()
  if not cookies:
    raise HTTPException(status_code=500, detail="Failed to auth with WG-Easy")
  try:
    url = f"http://{settings.CONTAINER_PREFIX}wg-easy:51821/api/wireguard/client/{client_id}"
    async with httpx.AsyncClient(cookies=cookies) as client:
      resp = await client.delete(url, timeout=5.0)
      return resp.json() if resp.content else {}
  except Exception as e:
    raise HTTPException(status_code=500, detail=str(e))


@router.get("/wg/clients/{client_id}/configuration")
async def get_client_config(client_id: str, user: str = Depends(get_admin_user)):
  """Downloads the WireGuard .conf file for a specific client."""
  cookies = await get_wgeasy_session()
  try:
    url = f"http://{settings.CONTAINER_PREFIX}wg-easy:51821/api/wireguard/client/{client_id}/configuration"
    async with httpx.AsyncClient(cookies=cookies) as client:
      resp = await client.get(url, timeout=5.0)
      return Response(content=resp.content, media_type="text/plain")
  except Exception as e:
    raise HTTPException(status_code=500, detail=str(e))


@router.get("/profiles")
def list_profiles(user: str = Depends(get_admin_user)):
  """Lists all available VPN uplink profiles (.conf files)."""
  try:
    files = [
        f.replace('.conf', '')
        for f in os.listdir(settings.PROFILES_DIR)
        if f.endswith('.conf')
    ]
    return {"profiles": files}
  except Exception:
    return {"error": "Failed to list profiles"}
