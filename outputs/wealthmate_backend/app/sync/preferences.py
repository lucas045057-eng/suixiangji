from sqlalchemy import select
from ..assets.domain import json_value
from ..models import Account, UserPreference
from .v2_errors import Rejected


def preference_json(row):
    return json_value(dict(id="self", default_account_id=row.default_account_id,
        server_version=row.server_version, updated_at=row.updated_at))


def next_version(user):
    user.sync_version += 1
    return user.sync_version


def set_preference(db, user, default_id):
    if default_id is not None:
        account = db.get(Account, default_id, populate_existing=True)
        if account is None or account.user_id != user.id:
            raise Rejected("invalid_default_account", "Default account is unavailable", "default_account_id")
        if account.deleted_at is not None or account.archived_at is not None or account.kind != "asset":
            raise Rejected("invalid_default_account", "Default must be an active asset account", "default_account_id")
    row = db.get(UserPreference, user.id, populate_existing=True)
    # Flags are a projection; each changed account needs its own pull-visible version.
    accounts = db.scalars(select(Account).where(Account.user_id == user.id)
                          .order_by(Account.id).execution_options(populate_existing=True)).all()
    for account in accounts:
        desired = account.id == default_id
        if account.is_default_payment != desired:
            account.is_default_payment = desired
            account.server_version = next_version(user)
    if row is None:
        row = UserPreference(user_id=user.id, default_account_id=default_id,
                             server_version=next_version(user))
        db.add(row)
    elif row.default_account_id != default_id:
        row.default_account_id = default_id
        row.server_version = next_version(user)
    db.flush()
    return row


def clear_inactive_default(db, user, account):
    if account.deleted_at is None and account.archived_at is None and account.kind == "asset":
        return
    preference = db.get(UserPreference, user.id, populate_existing=True)
    if preference and preference.default_account_id == account.id:
        set_preference(db, user, None)
