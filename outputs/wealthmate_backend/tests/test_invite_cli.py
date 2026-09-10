import os
from pathlib import Path
import subprocess
import sys

from sqlalchemy import create_engine, text

from test_migrations import upgrade


def test_cli_creates_high_entropy_invite_with_expiry_and_no_credentials_in_errors(tmp_path):
    url = f"sqlite:///{tmp_path / 'cli.db'}"
    assert upgrade(url).returncode == 0
    env = {**os.environ, "WEALTHMATE_DATABASE_URL": url, "PYTHONIOENCODING": "utf-8"}
    args = [sys.executable, "-m", "app.invites", "create", "--max-uses", "3", "--expires-days", "7"]
    result = subprocess.run(args, env=env, cwd=Path(__file__).resolve().parents[1], capture_output=True, text=True, encoding="utf-8")
    assert result.returncode == 0, result.stderr
    code = result.stdout.strip()
    assert 32 <= len(code) <= 128
    engine = create_engine(url)
    with engine.connect() as db:
        row = db.execute(text("SELECT code, enabled, max_uses, used_count, expires_at FROM invite_codes")).one()
        assert row.code == code
        assert row.enabled and row.max_uses == 3 and row.used_count == 0 and row.expires_at
    engine.dispose()

