import os
import json
import requests
import urllib.parse
from fastapi import APIRouter, Depends, HTTPException, Request, Response
from pydantic import BaseModel
from ..core.security import get_current_user
from ..core.config import settings

router = APIRouter()

def get_wgeasy_session():
    password = settings.VPN_PASS_RAW or settings.ADMIN_PASS_RAW or ""
    try:
        url = f"http://{settings.CONTAINER_PREFIX}wg-easy:51821/api/session"
        resp = requests.post(url, json={"password": password}, timeout=5)
        if resp.status_code == 200 or resp.status_code == 204:
            return resp.cookies
    except Exception as e:
        print(f"WG Login Error: {e}")
    return None

@router.get("/wg/clients")
def get_clients(user: str = Depends(get_current_user)):
    cookies = get_wgeasy_session()
    if not cookies:
        raise HTTPException(status_code=500, detail="Failed to auth with WG-Easy")
    try:
        url = f"http://{settings.CONTAINER_PREFIX}wg-easy:51821/api/wireguard/client"
        resp = requests.get(url, cookies=cookies, timeout=5)
        return resp.json()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

class CreateClientRequest(BaseModel):
    name: str

@router.post("/wg/clients")
def create_client(req: CreateClientRequest, user: str = Depends(get_current_user)):
    cookies = get_wgeasy_session()
    if not cookies:
        raise HTTPException(status_code=500, detail="Failed to auth with WG-Easy")
    try:
        url = f"http://{settings.CONTAINER_PREFIX}wg-easy:51821/api/wireguard/client"
        resp = requests.post(url, json={"name": req.name}, cookies=cookies, timeout=5)
        return resp.json()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.delete("/wg/clients/{client_id}")
def delete_client(client_id: str, user: str = Depends(get_current_user)):
    cookies = get_wgeasy_session()
    if not cookies:
        raise HTTPException(status_code=500, detail="Failed to auth with WG-Easy")
    try:
        url = f"http://{settings.CONTAINER_PREFIX}wg-easy:51821/api/wireguard/client/{client_id}"
        resp = requests.delete(url, cookies=cookies, timeout=5)
        return resp.json() if resp.content else {}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/wg/clients/{client_id}/configuration")
def get_client_config(client_id: str, user: str = Depends(get_current_user)):
    cookies = get_wgeasy_session()
    try:
        url = f"http://{settings.CONTAINER_PREFIX}wg-easy:51821/api/wireguard/client/{client_id}/configuration"
        resp = requests.get(url, cookies=cookies, timeout=5)
        return Response(content=resp.content, media_type="text/plain")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/profiles")
def list_profiles(user: str = Depends(get_current_user)):
    try:
        files = [f.replace('.conf', '') for f in os.listdir(settings.PROFILES_DIR) if f.endswith('.conf')]
        return {"profiles": files}
    except:
        return {"error": "Failed to list profiles"}
