from fastapi import APIRouter

from .schemas import AppVersionResponse
from .service import app_version


router = APIRouter()


@router.get("/app/version", response_model=AppVersionResponse)
def version() -> AppVersionResponse:
    return app_version()
