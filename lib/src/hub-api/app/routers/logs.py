import os
import time
import json
import sqlite3
import asyncio
from anyio import to_thread
from fastapi import APIRouter, Depends, Request
from fastapi.responses import StreamingResponse
from ..core.security import get_current_user
from ..core.config import settings

router = APIRouter()

@router.get("/logs")
def get_logs(level: str = None, category: str = None, user: str = Depends(get_current_user)):
    try:
        if level == "ALL": level = None
        if category == "ALL": category = None

        conn = sqlite3.connect(settings.DB_FILE)
        c = conn.cursor()
        sql = "SELECT timestamp, level, category, message FROM logs"
        args = []
        if level or category:
            sql += " WHERE"
            if level:
                sql += " level = ?"
                args.append(level)
            if category:
                if level: sql += " AND"
                sql += " category = ?"
                args.append(category)
        sql += " ORDER BY id DESC LIMIT 100"
        c.execute(sql, tuple(args))
        rows = c.fetchall()
        conn.close()
        
        logs = [{"timestamp": r[0], "level": r[1], "category": r[2], "message": r[3]} for r in rows]
        logs.reverse() 
        return {"logs": logs}
    except Exception as e:
        return {"error": str(e)}

@router.get("/events")
async def events_stream(request: Request, user: str = Depends(get_current_user)):
    # This endpoint is often accessed by frontend EventSource, handling auth via query param or cookie might be needed 
    # if headers aren't supported by EventSource in all browsers. 
    # For now, we'll leave it open or assume cookie auth if we implemented it.
    
    async def event_generator():
        retry_count = 0
        while retry_count < 10:
            if os.path.exists(settings.LOG_FILE):
                break
            await asyncio.sleep(1)
            retry_count += 1
        
        if not os.path.exists(settings.LOG_FILE):
            yield "data: Log file initializing...\n\n"
            return

        try:
            # Open file in a thread to avoid blocking, though typically open() is fast enough.
            # But reading (tailing) effectively requires non-blocking logic.
            # We'll run the file operations in a thread.
            
            # Since we can't easily share the file handle across threads in a loop with run_sync(f.readline),
            # we will use a dedicated thread for the file tailing logic or just use run_sync for the blocking read.
            
            # Simplified approach: blocking open (acceptable for once), async read loop.
            with open(settings.LOG_FILE, 'r') as f:
                f.seek(0, 2) # Tail
                yield ": keepalive\n\n"
                
                keepalive_counter = 0
                while True:
                    if await request.is_disconnected():
                        break
                        
                    # Offload the blocking readline to a worker thread
                    line = await to_thread.run_sync(f.readline)
                    
                    if line:
                        yield f"data: {line.strip()}\n\n"
                        keepalive_counter = 0
                    else:
                        await asyncio.sleep(1)
                        keepalive_counter += 1
                        if keepalive_counter >= 15:
                            yield ": keepalive\n\n"
                            keepalive_counter = 0
        except Exception as e:
            log_structured("ERROR", f"Log stream error: {e}", "SYSTEM")

    return StreamingResponse(event_generator(), media_type="text/event-stream")
