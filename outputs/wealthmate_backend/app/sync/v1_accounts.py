"""Limited V1 repairs; failures elsewhere still roll back the entire batch."""
from datetime import datetime
from ..assets.domain import json_value
from ..assets.names import available_account_name
from ..models import Account, AccountMutationAudit


def normalize_v1_account(db, user, operation, data, existing):
    data = dict(data)

    def repair(field, value, event, reason):
        before = {field: data.get(field)}
        data[field] = value
        db.add(AccountMutationAudit(user_id=user.id, account_id=operation.entity_id,
            client_op_id=operation.client_op_id, event_kind=event,
            before_json=json_value(before), after_json=json_value({field: value}), reason=reason))

    if "name" in data or existing is None:
        name = str(data.get("name") or "").strip()
        occupied = {row.normalized_name for row in db.query(Account.normalized_name).filter(
            Account.user_id == user.id, Account.deleted_at.is_(None),
            Account.id != operation.entity_id).all()}
        safe = available_account_name(name, operation.entity_id, occupied)
        if safe != name:
            repair("name", safe, "v1_name_repaired", "empty, overlong or duplicate normalized name")
    if "note" in data and len(str(data["note"] or "")) > 256:
        repair("note", str(data["note"])[:256], "v1_note_truncated", "note exceeds 256 Unicode code points")
    if data.get("archived_at") is not None:
        raw = data["archived_at"]
        try:
            if not isinstance(raw, str):
                raise ValueError("timestamp must be a string")
            datetime.fromisoformat(raw.replace("Z", "+00:00"))
        except ValueError:
            repair("archived_at", existing.archived_at if existing else None,
                   "v1_archive_repaired", "invalid archived_at; retain existing value or NULL")
    return data
