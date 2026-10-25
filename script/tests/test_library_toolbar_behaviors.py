"""Preserve live Steam rating/intent/history behavior and shared remote toolbar popovers."""
import hashlib
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
    def test_source_facts_and_unified_query_preserve_download_contracts(self):
        self.run_behavior_harness(source_only=True)

    def test_cross_module_commands_and_toolbar_panels(self):
        self.run_behavior_harness(source_only=False)

    def run_behavior_harness(self, *, source_only):
        core = STEAM / 'Core'
        watched = [core / 'SteamWorkshopService.swift', core / 'SteamWorkshopService+DownloadFiltering.swift',
                   core / 'SteamWorkshopService+LibraryRecords.swift',
                   ROOT / 'MyWallpaperX/Models/WallpaperReference.swift', ROOT / 'MyWallpaperX/Models/WallpaperContent.swift',
                   ROOT / 'MyWallpaperX/Models/WallpaperLibraryPage.swift',
                   ROOT / 'MyWallpaperX/Core/LibraryCollections/WallpaperLibraryQuery.swift',
                   ROOT / 'script/tests/fixtures/LibraryToolbarBehaviorHarness.swift',
                   ROOT / 'MyWallpaperX/Shared/UI/ToolbarMenuPopover.swift',
                   ROOT / 'MyWallpaperX/Shared/Components/ActionMenuItem.swift',
                   core / 'SteamWorkshopBrowseFilters.swift', core / 'SteamWorkshopAgeRatingSupport.swift']
        identities = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in watched}
        service = (core / 'SteamWorkshopService.swift').read_text()
        filtering = (core / 'SteamWorkshopService+DownloadFiltering.swift').read_text()
        steam_methods = method(service, '    private func refreshDownloadIntentProjection(')
        steam_methods += '\n' + method(service, '    private func observeDownloadJobStoreForProjection(')
        records = (core / 'SteamWorkshopService+LibraryRecords.swift').read_text()
        steam_methods += '\n' + method(records, '    func upsertTransientRecord(')
        steam_methods += '\n' + '\n'.join(method(filtering, signature) for signature in [
            '    func excludedDownloadReferences(',
            '    func downloadsWithFailedIntents(', '    var currentSteamDownloadAccount:',
            '    func hasFailedDownloadHistory('])
        merge_start = '    func downloadsWithFailedIntents(from records: [SteamWorkshopDownloadRecord]) -> [SteamWorkshopDownloadRecord] {'
        self.assertEqual(steam_methods.count(merge_start), 1)
        steam_methods = steam_methods.replace(merge_start, merge_start + '\n        mergeCalls += 1')
        # Count reads at the unchanged history input leaf; production visibility,
        # merge, value guards and jobs/history publisher subscription stay real.
        steam_methods = steam_methods.replace('downloadJobStore.history.lazy', 'downloadJobStore.historyForProjection.lazy')
        steam_methods += '\n' + next(line for line in service.splitlines() if '    @Published var downloadsShowsAdultContent =' in line)
        template = (ROOT / 'script/tests/fixtures/LibraryToolbarBehaviorHarness.swift').read_text()
        template = template.replace('// DOWNLOADS_PROPERTY', method(service, '    @Published var downloads:'))
        for marker, fragment in {
            '// STEAM_METHODS': steam_methods,
        }.items():
            template = template.replace(marker, fragment)
        with tempfile.TemporaryDirectory(prefix='mwx-library-toolbar-', dir='/private/tmp') as folder:
            work = Path(folder)
            source = work / 'Harness.swift'
            source.write_text(template)
            binary = work / 'toolbar-behaviors'
            sources = [source, ROOT / 'MyWallpaperX/Shared/UI/ToolbarMenuPopover.swift',
                       ROOT / 'MyWallpaperX/Shared/Components/ActionMenuItem.swift',
                       core / 'SteamWorkshopBrowseFilters.swift', core / 'SteamWorkshopAgeRatingSupport.swift',
                       *[ROOT / p for p in ['MyWallpaperX/Models/WallpaperReference.swift',
                          'MyWallpaperX/Models/WallpaperContent.swift', 'MyWallpaperX/Models/WallpaperLibraryPage.swift',
                          'MyWallpaperX/Core/LibraryCollections/WallpaperLibraryQuery.swift']]]
            build = subprocess.run(['xcrun', 'swiftc', '-parse-as-library', *map(str, sources),
                '-module-cache-path', str(work / 'modules'), '-o', str(binary)], capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            home = work / 'home'
            home.mkdir()
            run = subprocess.run([str(binary), *(['--source-only'] if source_only else [])], env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)),
                capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            if proof := os.environ.get('MWX_LIBRARY_TOOLBAR_PROOF_DIR'):
                out = Path(proof)
                out.mkdir(parents=True, exist_ok=True)
                (out / 'checks.json').write_text(json.dumps(checks, indent=2) + '\n')
                (out / 'runtime.log').write_text(run.stderr)
            self.assertEqual(identities, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in watched})
            self.assertTrue(checks)
            for name, passed in checks.items():
                with self.subTest(name=name):
                    self.assertTrue(passed)
            print(json.dumps(checks, sort_keys=True))


if __name__ == '__main__':
    unittest.main()
