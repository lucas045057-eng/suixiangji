"""Keep pytest's generated files inside the isolated workspace.

The Windows host's shared pytest temp root can be ACL-protected between test
runs.  This is test infrastructure only; application runtime storage remains
configured by the individual test fixtures.
"""

from pathlib import Path
import tempfile


_workspace_temp_root = Path(__file__).resolve().parents[1] / ".pytest-tmp"
_workspace_temp_root.mkdir(parents=True, exist_ok=True)
tempfile.tempdir = str(_workspace_temp_root)
