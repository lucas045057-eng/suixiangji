import os
import unittest
from pathlib import Path
from unittest.mock import patch

from app.config import Settings


class V104ReleaseMetadataTest(unittest.TestCase):
    def test_deployment_templates_target_v105_build8(self):
        root = Path(__file__).resolve().parents[1]
        compose = (root / 'docker-compose.yml').read_text()
        example = (root / '.env.example').read_text()
        self.assertIn('${WEALTHMATE_APP_LATEST_VERSION:-1.0.5}', compose)
        self.assertIn('${WEALTHMATE_APP_LATEST_BUILD:-8}', compose)
        self.assertIn('WEALTHMATE_APP_LATEST_VERSION=1.0.5', example)
        self.assertIn('WEALTHMATE_APP_LATEST_BUILD=8', example)

    def test_default_release_metadata_targets_v105_build8(self):
        with patch.dict(os.environ, {}, clear=True):
            settings = Settings(_env_file=None)

        self.assertEqual(settings.app_latest_version, "1.0.5")
        self.assertEqual(settings.app_latest_build, 8)
        self.assertEqual(settings.app_minimum_supported_version, "1.0.0")
        self.assertEqual(settings.app_minimum_supported_build, 3)
        self.assertFalse(settings.app_force_update)


if __name__ == "__main__":
    unittest.main()
