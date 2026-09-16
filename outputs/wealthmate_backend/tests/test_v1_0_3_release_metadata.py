import os
import unittest
from unittest.mock import patch

from app.config import Settings


class V103ReleaseMetadataTest(unittest.TestCase):
    def test_default_release_metadata_targets_v103_build6(self):
        with patch.dict(os.environ, {}, clear=True):
            settings = Settings(_env_file=None)

        self.assertEqual(settings.app_latest_version, "1.0.3")
        self.assertEqual(settings.app_latest_build, 6)
        self.assertEqual(settings.app_minimum_supported_version, "1.0.0")
        self.assertEqual(settings.app_minimum_supported_build, 3)
        self.assertFalse(settings.app_force_update)


if __name__ == "__main__":
    unittest.main()
