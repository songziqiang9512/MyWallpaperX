"""Execute the production AppKit menu against observable command receivers."""
import pathlib
import subprocess
import tempfile
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
class SteamItemMenuTests(unittest.TestCase):
    def test_menu_rechecks_identity_and_state_at_dispatch(self):
        with tempfile.TemporaryDirectory(prefix='mwx-item-menu-', dir='/private/tmp') as folder:
            binary = pathlib.Path(folder) / 'menu'
            result = subprocess.run(['xcrun', 'swiftc', '-parse-as-library',
                str(ROOT / 'MyWallpaperX/Modules/SteamWorkshop/UI/SteamWorkshopItemMenu.swift'),
                str(ROOT / 'script/tests/fixtures/SteamItemMenuHarness.swift'), '-o', str(binary)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('dispatch PASS', result.stdout)
