"""Execute the production AppKit menu against observable command receivers."""
import pathlib
import subprocess
import tempfile
import unittest
from script.tests.test_ui_library_algorithms import declaration
ROOT = pathlib.Path(__file__).resolve().parents[2]
class SteamItemMenuTests(unittest.TestCase):
    def test_menu_rechecks_identity_and_state_at_dispatch(self):
        with tempfile.TemporaryDirectory(prefix='mwx-item-menu-', dir='/private/tmp') as folder:
            binary = pathlib.Path(folder) / 'menu'
            grid = (ROOT / 'MyWallpaperX/Modules/SteamWorkshop/UI/AppKitSteamWorkshopBrowserGridView.swift').read_text()
            source = pathlib.Path(folder) / 'Checks.swift'
            fixture = (ROOT / 'script/tests/fixtures/SteamItemMenuHarness.swift').read_text()
            commands = (ROOT / 'MyWallpaperX/App/WallpaperLibraryCommands.swift').read_text()
            composition = (ROOT / 'script/tests/fixtures/WallpaperLibraryMenuCompositionChecks.swift').read_text()
            composition = composition.replace('// ACTUAL_LIBRARY_FAVORITE_STATE', declaration(commands, 'nonisolated struct WallpaperLibraryFavoriteActionState'))
            composition = composition.replace('// ACTUAL_LIBRARY_FAVORITE_FACTORY', declaration(commands, '    func makeFavoriteAction('))
            composition = composition.replace('// ACTUAL_LIBRARY_CONTEXT_MENU', declaration(commands, '    func contextMenu('))
            source.write_text(fixture.replace('// ACTUAL_BROWSER_ITEM_MENU', declaration(grid, '    private func itemMenu(')) + '\n' + composition)
            result = subprocess.run(['xcrun', 'swiftc', '-parse-as-library',
                str(ROOT / 'MyWallpaperX/Modules/SteamWorkshop/UI/SteamWorkshopItemMenu.swift'),
                str(ROOT / 'MyWallpaperX/Shared/Components/ActionMenuItem.swift'),
                str(source), '-o', str(binary)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('dispatch PASS', result.stdout)
