from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from ..core.dependencies import get_current_user
from ..db import get_db
from ..models import User
from . import service as quick_entry_service
from .schemas import DraftIn
from .batch_router import router as batch_router
from .stream_router import router as stream_router


router = APIRouter()


@router.post("/agent/draft")
async def agent_draft(
    payload: DraftIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    return await quick_entry_service.make_draft(db, user, payload)


router.include_router(batch_router)
router.include_router(stream_router)
