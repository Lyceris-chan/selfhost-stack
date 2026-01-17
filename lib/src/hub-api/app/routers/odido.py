"""Odido Booster service proxy router for the Privacy Hub API.

This module provides a secure proxy to the internal Odido Booster service,
injecting necessary authentication headers.
"""

import httpx
from fastapi import APIRouter, Depends, HTTPException, Request, Response

from ..core.config import settings
from ..core.security import get_admin_user

router = APIRouter(prefix="/odido-proxy")

ODIDO_URL = f"http://{settings.CONTAINER_PREFIX}odido-booster:8085"


@router.api_route("/{path:path}", methods=["GET", "POST", "PUT", "DELETE"])
async def proxy_odido(path: str, request: Request, user: str = Depends(get_admin_user)):
    """Proxies requests to the internal Odido Booster service.

    Injects the HUB_API_KEY into the request headers for authentication with
    the downstream service.

    Args:
        path: The subpath to proxy.
        request: The incoming FastAPI request.
        user: Authenticated admin user.

    Returns:
        The response from the Odido Booster service.
    """
    url = f"{ODIDO_URL}/api/{path}"

    # Forward query parameters
    params = dict(request.query_params)

    # Forward body for POST/PUT
    body = await request.body()

    headers = {"X-API-Key": settings.HUB_API_KEY, "Content-Type": "application/json"}

    async with httpx.AsyncClient() as client:
        try:
            resp = await client.request(
                method=request.method,
                url=url,
                params=params,
                content=body,
                headers=headers,
                timeout=30.0,
            )
            return Response(
                content=resp.content,
                status_code=resp.status_code,
                headers=dict(resp.headers),
            )
        except Exception as err:
            raise HTTPException(status_code=502, detail=f"Odido Proxy Error: {err}")
