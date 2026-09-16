import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import unittest


class AppVersionTest(unittest.TestCase):
    def _version_response(self) -> dict:
        fd, db_path = tempfile.mkstemp(prefix="app-version-", suffix=".sqlite")
        os.close(fd)
        script = textwrap.dedent(
            """
            import json
            from fastapi.testclient import TestClient
            from app.main import app

            with TestClient(app) as client:
                response = client.get("/app/version")
            print(json.dumps({"status": response.status_code, "body": response.json()}))
            """
        )
        environment = os.environ.copy()
        environment.pop("APP_GIT_SHA", None)
        environment.pop("WEALTHMATE_GIT_SHA", None)
        environment["WEALTHMATE_DATABASE_URL"] = "sqlite:///" + Path(db_path).as_posix()
        environment["WEALTHMATE_JWT_SECRET"] = "app-version-test-secret"
        environment["WEALTHMATE_ENVIRONMENT"] = "test"
        environment["WEALTHMATE_TEST_SCHEMA_INIT"] = "true"
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
            return json.loads(output.strip().splitlines()[-1])
        finally:
            try:
                Path(db_path).unlink()
            except PermissionError:
                pass

    def test_public_endpoint_returns_release_metadata(self):
        result = self._version_response()

        self.assertEqual(result["status"], 200)
        self.assertEqual(
            result["body"],
            {
                "latest_version": "1.0.2",
                "latest_build": 5,
                "minimum_supported_version": "1.0.0",
                "minimum_supported_build": 3,
                "force_update": False,
                "download_url": None,
                "release_notes": "",
            },
        )

    def test_production_rejects_non_https_download_url(self):
        from app.config import Settings

        settings = Settings(
            _env_file=None,
            environment="production",
            jwt_secret="x" * 40,
            cors_origins="https://app.invalid",
            app_download_url="http://download.invalid/app.apk",
        )
        with self.assertRaisesRegex(ValueError, "HTTPS"):
            settings.validate_runtime()


if __name__ == "__main__":
    unittest.main()
