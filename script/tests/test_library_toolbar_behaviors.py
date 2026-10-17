"""Exercise bulk-delete completion, official rating filtering and native toolbar popovers."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_steam_library_interactions import method

ROOT = Path(__file__).resolve().parents[2]
STEAM = ROOT / 'MyWallpaperX/Modules/SteamWorkshop'


class LibraryToolbarBehaviorTests(unittest.TestCase):
    def test_cross_module_commands_and_toolbar_panels(self):
        core = STEAM / 'Core'
        service = (core / 'SteamWorkshopService.swift').read_text()
        selection = (core / 'SteamWorkshopService+DownloadSelection.swift').read_text()
        filtering = (core / 'SteamWorkshopService+DownloadFiltering.swift').read_text()
        accessors = (core / 'SteamWorkshopService+DownloadAccessors.swift').read_text()
        steam_methods = '\n'.join(method(selection, signature) for signature in [
            '    func deleteSelectedDownload(', '    func exitDownloadsMultiSelectMode(',
            '    func publishDownloadSelectionState('])
        steam_methods += '\n' + method(accessors, '    var effectiveSelectedDownloadIDs:')
        steam_methods += '\n' + method(accessors, '    func firstDisplayedDownloadID(')
        steam_methods += '\n' + method(service, '    private func refreshDisplayedDownloads(')
        steam_methods += '\n' + method(service, '    @Published var downloadsShowsAdultContent')
        steam_methods += '\n' + '\n'.join(method(filtering, signature) for signature in [
            '    func filteredAndSortedDownloads(', '    private func sortedDownloadRecords(',
            '    private func downloadRecordStableComparison(', '    func sanitizeDownloadSelectionAgainstDisplayedDownloads('])
        online = (ROOT / 'MyWallpaperX/Modules/OnlineLibrary/UI/AppKitOLDownloadsGridView.swift').read_text()
        online_methods = '\n'.join(method(online, signature) for signature in [
            '    func deleteSelected(', '    func toggleMultiSelect(',
            '    private var effectiveSelectedIDs:', '    var primarySelectedID:',
            '    func selectAll(', '    private func syncSelectionFromQuickLook(',
            '    private func resolveSelectionAfterSnapshot(', '    private func applySnapshot('])
        sil = (ROOT / 'MyWallpaperX/Modules/StaticImageLibrary/Core/SILService.swift').read_text()
        sil_methods = '\n'.join(method(sil, signature) for signature in [
            '    func remove(ids:', '    func removeFromSILTag(', '    func clearSelectionState(',
            '    private func resolveNextSelectionID('])
        video_selection = (ROOT / 'MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+Selection.swift').read_text()
        video_removal = (ROOT / 'MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+Removal.swift').read_text()
        video_methods = method(video_selection, '    func clearSelectionState(') + '\n' + method(
            video_removal, '    func clearSelectionAndPendingState(')
        video_methods += '\n' + '\n'.join(method(video_removal, signature) for signature in [
            '    func removeWallpapers(', '    private func removeLibraryWallpapers('])

        video_methods += '\n' + method(video_selection, '    var effectiveSelectedWallpaperIDs:')
        ui_helper = (ROOT / 'MyWallpaperX/Shell/UIActionHelper.swift').read_text()
        helper_methods = '\n'.join(method(ui_helper, signature) for signature in [
            '    static func performDelete(', '    static func performDeleteWithoutConfirmation(',
            '    private static func selectedWallpapers(', '    private static func resolvedHostWindow('])
        actions = (STEAM / 'Toolbar/SteamWorkshopToolbarController+Actions.swift').read_text()
        template = (ROOT / 'script/tests/fixtures/LibraryToolbarBehaviorHarness.swift').read_text()
        for marker, fragment in {
            '// STEAM_METHODS': steam_methods,
            '// ONLINE_METHODS': online_methods,
            '// SIL_METHODS': sil_methods,
            '// VIDEO_METHODS': video_methods,
            '// VIDEO_UI_HELPER': helper_methods,
            '// SORT_ACTION': method(actions, '    @objc func handleDownloadsSortAction('),
        }.items():
            template = template.replace(marker, fragment)
        with tempfile.TemporaryDirectory(prefix='mwx-library-toolbar-', dir='/private/tmp') as folder:
            work = Path(folder)
            source = work / 'Harness.swift'
            download_models = (core / 'SteamWorkshopModels.swift').read_text()
            template += '\n' + method(download_models, 'enum SteamWorkshopDownloadsDisplayMode')
            template += '\n' + method(download_models, 'enum SteamWorkshopDownloadsSortMode')
            source.write_text(template)
            binary = work / 'toolbar-behaviors'
            sources = [source, ROOT / 'MyWallpaperX/Shared/UI/ToolbarMenuPopover.swift',
                       core / 'SteamWorkshopBrowseFilters.swift', core / 'SteamWorkshopAgeRatingSupport.swift']
            build = subprocess.run(['xcrun', 'swiftc', '-parse-as-library', *map(str, sources),
                '-module-cache-path', str(work / 'modules'), '-o', str(binary)], capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            home = work / 'home'
            home.mkdir()
            run = subprocess.run([str(binary)], env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)),
                capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            if proof := os.environ.get('MWX_LIBRARY_TOOLBAR_PROOF_DIR'):
                out = Path(proof)
                out.mkdir(parents=True, exist_ok=True)
                (out / 'checks.json').write_text(json.dumps(checks, indent=2) + '\n')
                (out / 'runtime.log').write_text(run.stderr)
            self.assertTrue(checks)
            for name, passed in checks.items():
                with self.subTest(name=name):
                    self.assertTrue(passed)


if __name__ == '__main__':
    unittest.main()
