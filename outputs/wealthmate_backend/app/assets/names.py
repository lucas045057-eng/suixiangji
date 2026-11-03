"""Account naming shared by writes and data migration (no database imports)."""
import unicodedata


def normalize_account_name(name: str) -> str:
    return unicodedata.normalize("NFKC", name.strip()).casefold()


def available_account_name(name: str, entity_id: str, occupied: set[str]) -> str:
    if name and len(name) <= 128 and normalize_account_name(name) not in occupied:
        return name
    base = name or "账户"
    number = 0
    while True:
        suffix = " ·" + entity_id[:8] + (f"-{number}" if number else "")
        candidate = base[:128 - len(suffix)] + suffix
        if normalize_account_name(candidate) not in occupied:
            return candidate
        number += 1
