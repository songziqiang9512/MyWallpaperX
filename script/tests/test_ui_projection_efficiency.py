"""Exercise production UI projection owners with real Combine/main-queue delivery.

The fixture replaces native grid rendering and product services with recording
boundaries. Subscription bodies, Shell routing/scheduling, Sidebar derivation,
and Online progress/visibility/data-source provider bodies come from production.
This is an event/output regression gate, not a visual or wall-clock benchmark.
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_steam_library_interactions import method


ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / 'MyWallpaperX'


def methods(source, signatures):
    return '\n'.join(method(source, signature) for signature in signatures)


class UIProjectionEfficiencyTests(unittest.TestCase):
    def test_production_projection_outputs_and_bounded_work(self):
        shell = (APP / 'Shell/AppKitDetailHostViewController.swift').read_text()
        sidebar = (APP / 'Shell/SidebarViews.swift').read_text()
        selection = (APP / 'Shell/WallpaperSelectionContext.swift').read_text()
        video = (APP / 'Modules/VideoLibrary/Core/WallpaperManager+Selection.swift').read_text()
        sil = (APP / 'Modules/StaticImageLibrary/Core/SILService.swift').read_text()
        online = (APP / 'Modules/OnlineLibrary/UI/AppKitOLBrowserGridView.swift').read_text()
        template = (ROOT / 'script/tests/fixtures/UIProjectionEfficiencyHarness.swift').read_text()

        # Keep the real subscription block, including throttle and all low-frequency
        # refreshes. Only setup's unrelated AppKit hierarchy construction is omitted.
        setup = method(online, '    private func setup()')
        bindings = setup[setup.index('        // 订阅 items 变化'):setup.rfind('\n    }')]
        provider = method(online, '    private lazy var dataSource:').replace(
            'private lazy var ', 'lazy var ').replace(
            'NSCollectionViewDiffableDataSource<', 'RecordingDataSource<') + '()'

        # Count calls at the derivation boundary without replacing its algorithm.
        video_sort = method(video, '    func sortedWallpapers(')
        opening = video_sort.index('{')
        video_sort = video_sort[:opening + 1] + '\n        derivations += 1' + video_sort[opening + 1:]
        sil_sort = method(sil, '    func sortedWallpapers(forSILTag')
        opening = sil_sort.index('{')
        sil_sort = sil_sort[:opening + 1] + '\n        derivations += 1' + sil_sort[opening + 1:]
        comparison = 'return filtered.sorted { a, b in'
        self.assertEqual(sil_sort.count(comparison), 1)
        sil_sort = sil_sort.replace(comparison, comparison + '\n            comparisons += 1')

        fragments = {
            '// VIDEO_PROJECTION_METHODS': video_sort + '\n' + methods(video, [
                '    var normalizedSearchQuery:', '    func filterWallpapers(']),
            '// SIL_PROJECTION_METHODS': method(sil, '    var sortedWallpapers:') + '\n' + sil_sort
                + '\n' + method(sil, '    func moveSingleSelectionByArrowKey('),
            '// SELECTION_SOURCE': method(selection, '    func sourceWallpapers('),
            '// SHELL_METHODS': methods(shell, [
                '    func update(selectedItem:', '    private func observeVideoLibraryState(',
                '    private func makeHostedController(', '    private func makeSILGridContainer(',
                '    private func scheduleCurrentLibraryGridUpdate(',
                '    private func updateCurrentVideoGridIfNeeded(', '    private func updateVideoGrid(',
                '    private func updateCurrentSILGridIfNeeded(',
                '    private func updateCurrentSILGridSelectionStateIfNeeded(',
                '    private func updateSILGrid(', '    private func replaceHostedController(']),
            '// SIDEBAR_METHODS': methods(sidebar, [
                '    private func sidebarLibraryStats(', '    private func currentTagOrder(',
                '    private func makeSidebarSnapshotSignature(', '    private func rebuildNodes(']),
            '// ONLINE_BINDINGS': bindings,
            '// ONLINE_PROVIDER': provider,
            '// ONLINE_METHODS': methods(online, [
                '    private func applyItems(', '    private func refreshDownloadProgress(',
                '    private func reloadVisibleItems(', '    private func isItemDownloaded(',
                '    private func updateVisibleThumbnailPriorities(',
                '    private func applyThumbnailDemand(']),
        }
        for marker, fragment in fragments.items():
            self.assertEqual(template.count(marker), 1, marker)
            template = template.replace(marker, fragment)
        with tempfile.TemporaryDirectory(prefix='mwx-ui-projection-', dir='/private/tmp') as directory:
            work = Path(directory)
            source = work / 'Harness.swift'
            source.write_text(template)
            binary = work / 'ui-projection'
            build = subprocess.run([
                'xcrun', 'swiftc', '-parse-as-library', str(source),
                str(APP / 'Shell/AppKitSidebarNode.swift'),
                '-module-cache-path', str(work / 'modules'), '-o', str(binary),
            ], capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            home = work / 'home'
            home.mkdir()
            run = subprocess.run([str(binary), str(work / 'downloads')],
                env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)),
                capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            if proof := os.environ.get('MWX_UI_PROJECTION_PROOF_DIR'):
                output = Path(proof)
                output.mkdir(parents=True, exist_ok=True)
                (output / 'checks.json').write_text(json.dumps(checks, indent=2) + '\n')
                (output / 'runtime.log').write_text(run.stderr)
            self.assertGreaterEqual(len(checks), 20)
            for name, passed in checks.items():
                with self.subTest(name=name):
                    self.assertTrue(passed)


if __name__ == '__main__':
    unittest.main()
