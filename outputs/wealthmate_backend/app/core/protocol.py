from fastapi import Header


def adjustment_view(x_wealthmate_sync_protocol: str | None = Header(default=None)) -> bool:
    return x_wealthmate_sync_protocol == "2"
