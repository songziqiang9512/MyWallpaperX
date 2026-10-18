"""The launch profile consumes descriptor facts without an inspector model."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class WebLaunchProfileTests(unittest.TestCase):
    def test_descriptor_only_profile_preserves_compatibility_policy(self):
        source = ROOT / "MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopWebResolvedRuntimeRiskFlags.swift"
        fixture = ROOT / "script/tests/fixtures/WebLaunchProfileChecks.swift"
        with tempfile.TemporaryDirectory(prefix="mwx-web-launch-profile-") as raw:
            directory = Path(raw)
            binary = directory / "check"
            compiled = subprocess.run(
                ["xcrun", "swiftc", "-parse-as-library", str(source), str(fixture),
                 "-module-cache-path", str(directory / "modules"), "-o", str(binary)],
                capture_output=True, text=True,
            )
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            run = subprocess.run([str(binary)], capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertIn("web-launch-profile-pass", run.stdout)


if __name__ == "__main__":
    unittest.main()
