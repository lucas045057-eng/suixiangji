from contextlib import asynccontextmanager

from fastapi import FastAPI, WebSocket
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from .api import router
from .assets.router import router as assets_router
from .config import get_settings
from .db import ensure_schema
from .ledger.router import router as ledger_router
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
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.include_router(router)
app.include_router(assets_router)
app.include_router(ledger_router)


@app.exception_handler(RequestValidationError)
async def validation_error(_, exc: RequestValidationError):
    # Pydantic's default response includes submitted passwords in input.
    return JSONResponse(
        status_code=422,
        content={
            "detail": [
                {
                    "loc": list(error["loc"]),
                    "msg": error["msg"],
                    "type": error["type"],
                }
                for error in exc.errors()
            ]
        },
    )


@app.websocket("/ws/sync")
async def sync_socket(websocket: WebSocket, token: str = ""):
    # This legacy echo endpoint does not participate in REST push/pull.
    await websocket.close(code=1008, reason="Beta uses authenticated REST synchronization")
