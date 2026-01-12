import httpx
from fastapi import APIRouter, Depends, HTTPException, Request, Response
from ..core.security import get_admin_user
from ..core.config import settings

router = APIRouter(prefix="/odido-proxy")

ODIDO_URL = f"http://{settings.CONTAINER_PREFIX}odido-booster:8085"

@router.api_route("/{path:path}", methods=["GET", "POST", "PUT", "DELETE"])
async def proxy_odido(path: str, request: Request, user: str = Depends(get_admin_user)):
    """
    Proxies requests to the Odido Booster service.
    Injects the HUB_API_KEY server-side.
    Requires admin session.
    """
    url = f"{ODIDO_URL}/api/{path}"
    
    # Forward query parameters
    params = dict(request.query_params)
    
    # Forward body for POST/PUT
    body = await request.body()
    
    headers = {
        "X-API-Key": settings.HUB_API_KEY,
        "Content-Type": "application/json"
    }

    async with httpx.AsyncClient() as client:
        try:
            resp = await client.request(
                method=request.method,
                url=url,
                params=params,
                content=body,
                headers=headers,
                timeout=30.0
            )
            return Response(
                content=resp.content,
                status_code=resp.status_code,
                headers=dict(resp.headers)
            )
        except Exception as e:
            raise HTTPException(status_code=502, detail=f"Odido Proxy Error: {e}")
