from .schemas import AppVersionResponse
from ..config import get_settings


def app_version() -> AppVersionResponse:
    settings = get_settings()
    return AppVersionResponse(
        latest_version=settings.app_latest_version.strip(),
        latest_build=settings.app_latest_build,
        minimum_supported_version=settings.app_minimum_supported_version.strip(),
        minimum_supported_build=settings.app_minimum_supported_build,
        force_update=settings.app_force_update,
        download_url=settings.app_download_url.strip() or None,
        release_notes=settings.app_release_notes.strip(),
    )
