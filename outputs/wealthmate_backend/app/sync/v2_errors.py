import math
from decimal import Decimal
from pydantic import ValidationError


class Rejected(Exception):
    def __init__(self, code, detail, field=None):
        super().__init__(detail)
        self.code, self.detail, self.field = code, detail, field


class VersionConflict(Exception):
    def __init__(self, row):
        self.row = row


def validate(schema, data):
    try:
        values = schema(**data).model_dump(exclude_unset=True)
    except ValidationError as exc:
        error = exc.errors()[0]
        raise Rejected("invalid_field", error["msg"], str(error["loc"][0]) if error["loc"] else None) from None
    if "currency" in values and not (values["currency"].isascii() and values["currency"].isalpha()):
        raise Rejected("invalid_field", "Currency must be an alphabetic code", "currency")
    limits = {"id": 64, "client_op_id": 128, "account_id": 64, "from_account_id": 64,
              "to_account_id": 64, "category_id": 64, "category_name": 128,
              "occurred_at": 64, "opening_rate_source": 256, "exchange_rate_source": 256}
    for field, value in values.items():
        if isinstance(value, str) and field in limits and len(value) > limits[field]:
            raise Rejected("invalid_field", "Value exceeds storage length", field)
        if not isinstance(value, Decimal):
            continue
        scale = 10 if field.endswith("rate") else 6
        if not value.is_finite() or abs(value) >= Decimal(10) ** (20-scale):
            raise Rejected("invalid_amount", "Amount exceeds storage range", field)
        if value != value.quantize(Decimal(10) ** -scale):
            raise Rejected("invalid_amount", "Amount exceeds storage precision", field)
        if field.endswith("rate") and value <= 0:
            raise Rejected("invalid_amount", "Exchange rate must be positive", field)
    return values


def base_version(op):
    value = op.base_version if op.base_version is not None else op.payload.get("server_version")
    if value is not None and (type(value) is not int or value < 0):
        raise Rejected("invalid_base_version", "base_version must be a nonnegative integer", "base_version")
    if op.base is not None and not isinstance(op.base, dict):
        raise Rejected("invalid_base", "base must be an object", "base")
    return value


def check_version(existing, op):
    expected = base_version(op)
    if expected is not None and expected != (existing.server_version if existing else 0):
        raise VersionConflict(existing)


def clean_payload(op, allowed, aliases=None):
    values = dict(op.payload)
    if values.get("id") not in (None, op.entity_id):
        raise Rejected("identity_mismatch", "Payload ID differs from entity_id", "id")
    if "client_op_id" in values and values["client_op_id"] != op.client_op_id:
        raise Rejected("identity_mismatch", "Payload operation ID differs from envelope", "client_op_id")
    for old, new in (aliases or {}).items():
        if old in values:
            value = values.pop(old)
            if new in values and values[new] != value:
                raise Rejected("invalid_field", "Conflicting aliases", new)
            values[new] = value
    if values.get("deleted_at") is not None:
        raise Rejected("read_only_field", "Use a delete operation for tombstones", "deleted_at")
    if "conversion_status" in values:
        if not isinstance(values["conversion_status"], str) or values["conversion_status"] not in {"ready", "pending"}:
            raise Rejected("invalid_field", "Unknown conversion status", "conversion_status")
        values.pop("conversion_status")
    for key in ("id", "server_version", "updated_at", "client_op_id", "deleted_at"):
        values.pop(key, None)
    unknown = set(values) - set(allowed)
    if unknown:
        raise Rejected("unsupported_field", "Unsupported field", sorted(unknown)[0])
    return values


def finite_json(value, path=""):
    if isinstance(value, str) and "\x00" in value:
        raise Rejected("invalid_field", "NUL characters are not supported", path)
    if isinstance(value, float) and not math.isfinite(value):
        raise Rejected("invalid_field", "Nonfinite JSON numbers are not supported", path)
    if isinstance(value, dict):
        for key, child in value.items():
            finite_json(child, path + "." + key if path else key)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            finite_json(child, path + "." + str(index))
