import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import unittest


class HealthVersionTest(unittest.TestCase):
    def _health_body(self, *, git_sha: str | None) -> dict:
        fd, db_path = tempfile.mkstemp(prefix="health-version-", suffix=".sqlite")
        os.close(fd)
        script = textwrap.dedent(
            """
            import json
            from fastapi.testclient import TestClient
            from app.main import app

            with TestClient(app) as client:
                response = client.get("/health")
            print(json.dumps({"status": response.status_code, "body": response.json()}))
            """
        )
        environment = os.environ.copy()
        environment.pop("APP_GIT_SHA", None)
        environment.pop("WEALTHMATE_GIT_SHA", None)
        environment["WEALTHMATE_DATABASE_URL"] = "sqlite:///" + Path(db_path).as_posix()
        environment["WEALTHMATE_JWT_SECRET"] = "health-version-secret"
        environment["WEALTHMATE_ENVIRONMENT"] = "test"
        environment["WEALTHMATE_TEST_SCHEMA_INIT"] = "true"
        if git_sha is not None:
            environment["APP_GIT_SHA"] = git_sha
        try:
            completed = subprocess.run(
                [sys.executable, "-X", "utf8", "-"],
                input=("# -*- coding: utf-8 -*-\n" + script).encode("utf-8"),
                cwd=Path(__file__).resolve().parents[1],
                env=environment,
                capture_output=True,
                check=False,
            )
            output = completed.stdout.decode("utf-8", errors="replace")
            errors = completed.stderr.decode("utf-8", errors="replace")
            self.assertEqual(completed.returncode, 0, output + errors)
            return json.loads(output.strip().splitlines()[-1])["body"]
        finally:
            try:
                Path(db_path).unlink()
            except PermissionError:
                pass

    def test_health_exposes_injected_git_sha(self):
        body = self._health_body(git_sha="test-sha-123")

        self.assertEqual(body["status"], "ok")
        self.assertEqual(body["git_sha"], "test-sha-123")

    def test_health_uses_safe_default_without_git_sha(self):
        body = self._health_body(git_sha=None)

        self.assertEqual(body["status"], "ok")
        self.assertEqual(body["git_sha"], "unknown")


if __name__ == "__main__":
    unittest.main()
