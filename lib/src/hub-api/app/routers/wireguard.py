import os
import json
import httpx
import urllib.parse
from fastapi import APIRouter, Depends, HTTPException, Request, Response
from pydantic import BaseModel
from ..core.security import get_current_user, get_admin_user
from ..core.config import settings

router = APIRouter()

async def get_wgeasy_session():
    password = settings.VPN_PASS_RAW or settings.ADMIN_PASS_RAW or ""
    try:
        url = f"http://{settings.CONTAINER_PREFIX}wg-easy:51821/api/session"
        async with httpx.AsyncClient() as client:
            resp = await client.post(url, json={"password": password}, timeout=5.0)
            if resp.status_code in (200, 204):
                return resp.cookies
    except Exception as e:
        print(f"WG Sign in Error: {e}")
    return None

@router.get("/wg/clients")
async def get_clients(user: str = Depends(get_admin_user)):
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
    name: str

@router.post("/wg/clients")
async def create_client(req: CreateClientRequest, user: str = Depends(get_admin_user)):
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
    try:
        files = [f.replace('.conf', '') for f in os.listdir(settings.PROFILES_DIR) if f.endswith('.conf')]
        return {"profiles": files}
    except:
        return {"error": "Failed to list profiles"}
