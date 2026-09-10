"""Operator-only invitation CLI, deliberately not an administrative HTTP API."""
import argparse
from datetime import datetime, timedelta, timezone
from getpass import getpass
import secrets
import sys

from sqlalchemy.exc import SQLAlchemyError

from .db import SessionLocal, ensure_schema
from .models import InviteCode


def positive(value):
    number = int(value)
    if number < 1:
        raise argparse.ArgumentTypeError("must be positive")
    return number


def main():
    parser = argparse.ArgumentParser(description="Manage Beta invitations; creation prints the new secret once")
    commands = parser.add_subparsers(dest="command", required=True)
    create = commands.add_parser("create")
    create.add_argument("--max-uses", type=positive, default=1)
    create.add_argument("--expires-days", type=positive, default=7)
    commands.add_parser("disable", help="Read invitation from hidden prompt, never a process argument")
    args = parser.parse_args()
    try:
        ensure_schema()
        with SessionLocal.begin() as db:
            if args.command == "create":
                code = secrets.token_urlsafe(32)
                db.add(InviteCode(code=code, max_uses=args.max_uses, expires_at=datetime.now(timezone.utc) + timedelta(days=args.expires_days)))
            else:
                code = getpass("Invitation to disable: ").strip()
                row = db.get(InviteCode, code)
                if row is None:
                    parser.exit(1, "Invitation not found\n")
                row.enabled = False
        print(code if args.command == "create" else "Invitation disabled")
    except (SQLAlchemyError, RuntimeError):
        # Database exception strings may contain URLs or secret parameters.
        print("Invitation operation failed; check database connectivity and migrations", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

