"""Exercise the real AppKit login presentation without an account or helper."""
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

class SteamLoginLayoutTests(unittest.TestCase):
    def test_real_appkit_pages_fit_and_keep_controls_separate(self):
        with tempfile.TemporaryDirectory(prefix='mwx-steam-login-layout-', dir='/private/tmp') as temporary:
            folder = pathlib.Path(temporary)
            binary = folder / 'layout'
            subprocess.run(['xcrun', 'swiftc', '-parse-as-library',
                str(ROOT / 'MyWallpaperX/Shared/UI/WallpaperLibrarySheetPresentation.swift'),
                str(ROOT / 'MyWallpaperX/Modules/SteamWorkshop/UI/SteamLoginPanelView.swift'),
                str(ROOT / 'script/tests/fixtures/SteamLoginLayoutHarness.swift'), '-o', str(binary)],
                check=True, capture_output=True, text=True, timeout=60)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('page reuse PASS', result.stdout)

if __name__ == '__main__':
    unittest.main()
