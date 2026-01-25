"""Log management and real-time event streaming router for the Privacy Hub API.

This module provides endpoints for retrieving historical logs from SQLite
and streaming new log entries using Server-Sent Events (SSE).
"""

import asyncio
import os
import sqlite3
import logging

from anyio import to_thread
from fastapi import APIRouter, Depends, Request
from fastapi.responses import StreamingResponse

from ..core.config import settings
from ..core.security import get_current_user

router = APIRouter()


@router.get("/logs")
def get_logs(
    level: str = None, category: str = None, user: str = Depends(get_current_user)
):
    """Retrieves the last 100 log entries from the database with filtering.

    Args:
        level: Optional log level filter (e.g., INFO, WARN, CRIT).
        category: Optional log category filter.
        user: Authenticated user.

    Returns:
        A dictionary containing the list of log entries.
    """
    try:
        if level == "ALL":
            level = None
        if category == "ALL":
            category = None

        conn = sqlite3.connect(settings.DB_FILE)
        cursor = conn.cursor()
        sql = "SELECT timestamp, level, category, message FROM logs"
        query_args = []
        if level or category:
            sql += " WHERE"
            if level:
                sql += " level = ?"
                query_args.append(level)
            if category:
                if level:
                    sql += " AND"
                sql += " category = ?"
                query_args.append(category)
        sql += " ORDER BY id DESC LIMIT 100"
        cursor.execute(sql, tuple(query_args))
        rows = cursor.fetchall()
        conn.close()

        log_entries = [
            {"timestamp": r[0], "level": r[1], "category": r[2], "message": r[3]}
            for r in rows
        ]
        log_entries.reverse()
        return {"logs": log_entries}
    except Exception as e:
        return {"error": str(e)}


@router.get("/events")
async def events_stream(request: Request, user: str = Depends(get_current_user)):
    """Provides a real-time Server-Sent Events (SSE) stream of system logs.

    Args:
        request: The FastAPI request object.
        user: Authenticated user.

    Returns:
        A StreamingResponse for the event stream.
    """

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
            with open(settings.LOG_FILE, "r") as f:
                f.seek(0, 2)  # Tail
                yield ": connected\n\n"

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
        except Exception as err:
            # Use internal logger directly to avoid circular dependency
            logging.getLogger("api").error(f"Log stream error: {err}")

    return StreamingResponse(event_generator(), media_type="text/event-stream")
