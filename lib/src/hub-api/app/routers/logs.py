import asyncio
import json
import os
import sqlite3
import time

from anyio import to_thread
from fastapi import APIRouter, Depends, Request
from fastapi.responses import StreamingResponse

from ..core.config import settings
from ..core.security import get_current_user

router = APIRouter()


@router.get("/logs")
def get_logs(level: str = None,
             category: str = None,
             user: str = Depends(get_current_user)):
  """Retrieves the last 100 log entries from the database with filtering."""
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

    logs = [{
        "timestamp": r[0],
        "level": r[1],
        "category": r[2],
        "message": r[3]
    } for r in rows]
    logs.reverse()
    return {"logs": logs}
  except Exception as e:
    return {"error": str(e)}


@router.get("/events")
async def events_stream(request: Request, user: str = Depends(get_current_user)):
  """Provides a real-time Server-Sent Events (SSE) stream of system logs."""

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
      with open(settings.LOG_FILE, 'r') as f:
        f.seek(0, 2)  # Tail
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
      # Use internal logger directly to avoid circular dependency
      import logging
      logging.getLogger("api").error(f"Log stream error: {e}")

  return StreamingResponse(event_generator(), media_type="text/event-stream")
