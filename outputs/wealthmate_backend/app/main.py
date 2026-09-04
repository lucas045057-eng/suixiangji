from contextlib import asynccontextmanager

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware

from .api import router
from .config import get_settings
from .db import ensure_schema
from .scheduler import create_scheduler


@asynccontextmanager
async def lifespan(_: FastAPI):
    ensure_schema()
    scheduler = create_scheduler()
    scheduler.start()
    yield
    scheduler.shutdown(wait=False)


app = FastAPI(title=get_settings().app_name, version="1.0.0", lifespan=lifespan)
origins = [item.strip() for item in get_settings().cors_origins.split(",")]
app.add_middleware(CORSMiddleware, allow_origins=origins, allow_credentials=True, allow_methods=["*"], allow_headers=["*"])
app.include_router(router)


@app.websocket("/ws/sync")
async def sync_socket(websocket: WebSocket, token: str = ""):
    await websocket.accept()
    try:
        await websocket.send_json({"type": "connected", "message": "同步通道已连接"})
        while True:
            message = await websocket.receive_json()
            await websocket.send_json({"type": "sync_status", "status": "received", "request": message})
    except WebSocketDisconnect:
        return
