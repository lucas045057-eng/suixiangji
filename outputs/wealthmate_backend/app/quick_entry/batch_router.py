from fastapi import APIRouter, Depends, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from fastapi.routing import APIRoute
from sqlalchemy.orm import Session
from starlette.exceptions import HTTPException

from ..core.dependencies import get_current_user_readonly
from ..core.rate_limit import AuthLimiter
from ..db import get_db
from ..models import User
from . import batch_service
from .batch_schemas import BatchError, DraftsIn


def _error_response(error):
    headers = {"Retry-After": "60"} if error.code == "rate_limited" else None
    return JSONResponse(
        status_code=error.status_code,
        content={"detail": error.detail, "code": error.code},
        headers=headers,
    )


class DraftsRoute(APIRoute):
    def get_route_handler(self):
        original = super().get_route_handler()

        async def handler(request: Request):
            try:
                return await original(request)
            except RequestValidationError as exc:
                too_large = any(
                    error["type"] == "string_too_long"
                    and tuple(error["loc"]) == ("body", "text")
                    for error in exc.errors()
                )
                return _error_response(BatchError("text_too_large" if too_large else "validation_error"))
            except BatchError as exc:
                return _error_response(exc)
            except HTTPException:
                raise
            except Exception:
                return _error_response(BatchError("internal_error"))

        return handler


router = APIRouter(route_class=DraftsRoute)
drafts_limiter = AuthLimiter()


@router.post("/agent/drafts")
async def agent_drafts(
    payload: DraftsIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user_readonly),
) -> dict:
    if not drafts_limiter.allow(user.id, 20):
        raise BatchError("rate_limited")
    return await batch_service.make_drafts(db, user, payload)
