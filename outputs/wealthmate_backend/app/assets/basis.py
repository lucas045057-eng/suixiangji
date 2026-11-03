"""Short-lived, user-bound signed financial content tokens; no client-side hashing."""
import base64
import binascii
import hashlib
import hmac
import json
import re
from datetime import date, datetime, timezone
from decimal import Decimal

from fastapi import HTTPException
from sqlalchemy import or_
from ..config import get_settings
from ..core.financial_lock import lock_current_user
from ..core.protocol import enforce_sync_floor
from ..models import Transaction
from .replay import replay, decimal_text

TTL_SECONDS = 600
BASIS_VERSION = 1


def failure(status, code, message):
    raise HTTPException(status, detail=dict(code=code, message=message))


def _now():
    return int(datetime.now(timezone.utc).timestamp())


def fingerprint(token):
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _key():
    return hmac.new(get_settings().jwt_secret.encode(), b"wealthmate.balance-basis.v1", hashlib.sha256).digest()


def _encode(data):
    return base64.urlsafe_b64encode(data).decode().rstrip("=")


def _decode(text):
    return base64.b64decode(text+"="*((-len(text)) % 4), altchars=b"-_", validate=True)


def financial_basis(db, user, account, effective_on):
    rows = db.query(Transaction).filter(Transaction.user_id == user.id,
        Transaction.deleted_at.is_(None), Transaction.occurred_on <= effective_on,
        or_(Transaction.account_id == account.id, Transaction.from_account_id == account.id,
            Transaction.to_account_id == account.id)).populate_existing().all()
    state = replay(account, rows, as_of_date=effective_on)
    if state.pending:
        failure(409, "conversion_pending", "Complete missing CNY snapshots before calibrating")
    # Retain the existing calibration/backup monetary domain for the stored basis metadata.
    if state.balance.copy_abs() >= Decimal(10)**14:
        failure(422, "basis_out_of_range", "Balance exceeds the supported calibration range")
    content = dict(basis_version=BASIS_VERSION, user_id=user.id, account_id=account.id,
        as_of=effective_on.isoformat(), kind=account.kind, currency=account.currency,
        opening_cny=decimal_text(state.opening), effects=state.effects)
    encoded = json.dumps(content, ensure_ascii=True, sort_keys=True, separators=(",", ":")).encode()
    return state.balance, hashlib.sha256(encoded).hexdigest()


def issue(db, user, account_id, effective_on=None, *, protocol=1):
    from .calibration import _active_account
    effective_on = effective_on or date.today()
    if effective_on > date.today():
        failure(422, "invalid_effective_on", "Basis date must not be in the future")
    try:
        user = lock_current_user(db, user.id, verified_auth_version=user.auth_version or 0, shared=True)
        enforce_sync_floor(user, protocol)
        account = _active_account(db, user, account_id)
        balance, digest = financial_basis(db, user, account, effective_on)
        issued = _now()
        claims = dict(basis_version=BASIS_VERSION, user_id=user.id, account_id=account_id,
            as_of=effective_on.isoformat(), balance_cny=decimal_text(balance), digest=digest,
            issued_at=issued, expires_at=issued+TTL_SECONDS)
        body = _encode(json.dumps(claims, sort_keys=True, separators=(",", ":")).encode())
        wire = "b1."+body
        token = wire+"."+_encode(hmac.new(_key(), wire.encode(), hashlib.sha256).digest())
        return dict(account_id=account_id, effective_on=effective_on.isoformat(), balance_cny=claims["balance_cny"],
            basis_version=BASIS_VERSION, basis_token=token, ttl_seconds=TTL_SECONDS,
            expires_at=datetime.fromtimestamp(claims["expires_at"], timezone.utc).isoformat(), server_version=user.sync_version)
    except BaseException:
        db.rollback()
        raise


def verify(token, user_id, account_id, effective_on):
    try:
        prefix, body, signature = token.split(".")
        wire = prefix+"."+body
        signature_bytes = _decode(signature)
        if (prefix != "b1" or _encode(signature_bytes) != signature
                or not hmac.compare_digest(signature_bytes, hmac.new(_key(), wire.encode(), hashlib.sha256).digest())):
            raise ValueError()
        claims = json.loads(_decode(body))
        if (set(claims) != {"basis_version", "user_id", "account_id", "as_of", "balance_cny", "digest", "issued_at", "expires_at"}
                or type(claims["basis_version"]) is not int or claims["basis_version"] != BASIS_VERSION
                or type(claims["issued_at"]) is not int or type(claims["expires_at"]) is not int
                or claims["expires_at"] != claims["issued_at"]+TTL_SECONDS
                or not isinstance(claims["balance_cny"], str) or not re.fullmatch(r"-?(?:0|[1-9]\d*)\.\d{6}", claims["balance_cny"])
                or not isinstance(claims["digest"], str) or not re.fullmatch(r"[0-9a-f]{64}", claims["digest"])):
            raise ValueError()
    except (ValueError, TypeError, KeyError, UnicodeError, binascii.Error):
        failure(400, "invalid_basis_token", "Malformed or modified balance basis token")
    if claims["user_id"] != user_id or claims["account_id"] != account_id or claims["as_of"] != effective_on.isoformat():
        failure(422, "basis_scope_mismatch", "Basis belongs to another user, account or date")
    if claims["issued_at"] > _now()+5:
        failure(400, "invalid_basis_token", "Basis issuance time is invalid")
    if _now() >= claims["expires_at"]:
        failure(409, "basis_expired", "Balance basis expired; obtain a new basis")
    return claims
