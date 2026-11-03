from fastapi import Header


def adjustment_view(x_wealthmate_sync_protocol: str | None = Header(default=None)) -> bool:
    return x_wealthmate_sync_protocol == "2"


def sync_protocol(x_wealthmate_sync_protocol: str | None = Header(default=None)) -> int:
    from fastapi import HTTPException
    if x_wealthmate_sync_protocol is None:
        return 1
    if x_wealthmate_sync_protocol not in {"1", "2"}:
        raise HTTPException(status_code=400, detail="Unsupported sync protocol")
    return int(x_wealthmate_sync_protocol)


def enforce_sync_floor(user, protocol):
    from fastapi import HTTPException
    from ..config import get_settings
    minimum = max(user.min_client_protocol or 1, get_settings().min_client_protocol)
    if protocol < minimum:
        raise HTTPException(status_code=426, detail={"code": "upgrade_required", "min_protocol": minimum})
