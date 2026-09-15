"""Actual shared footer controls and production detail action layout."""
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

class SteamDetailLayoutTests(unittest.TestCase):
    def test_long_primary_actions_and_narrow_widths(self):
        with tempfile.TemporaryDirectory(prefix='mwx-steam-detail-layout-', dir='/private/tmp') as temporary:
            binary = pathlib.Path(temporary) / 'footer'
            build = subprocess.run(['xcrun', 'swiftc', '-parse-as-library',
                str(ROOT / 'MyWallpaperX/Shared/UI/InspectorFooterMetrics.swift'),
                str(ROOT / 'MyWallpaperX/Modules/SteamWorkshop/UI/SteamWorkshopDetailFooterView.swift'),
                str(ROOT / 'script/tests/fixtures/SteamDetailFooterHarness.swift'), '-o', str(binary)],
                capture_output=True, text=True, timeout=60)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('dispatch PASS', result.stdout)

if __name__ == '__main__':
    unittest.main()
