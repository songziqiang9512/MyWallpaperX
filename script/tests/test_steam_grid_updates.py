"""Exercise production Steam snapshot transactions with real AppKit diffable grids."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_steam_library_interactions import method

ROOT = Path(__file__).resolve().parents[2]
UI = ROOT / 'MyWallpaperX/Modules/SteamWorkshop/UI'


class SteamGridUpdateTests(unittest.TestCase):
    def test_other_flow_grids_use_viewport_and_resize_safely(self):
        paths = ['VideoLibrary/UI/AppKitLibraryGridView.swift',
                 'SteamWorkshop/UI/AppKitSteamWorkshopDownloadsGridView.swift',
                 'OnlineLibrary/UI/AppKitOLBrowserGridView.swift',
                 'OnlineLibrary/UI/AppKitOLDownloadsGridView.swift']
        classes = []
        for index, path in enumerate(paths):
            source = (ROOT / 'MyWallpaperX/Modules' / path).read_text()
            signatures = ['    override func layout(', '    private func updateLayoutItemSize(']
            signatures += ['    private func scheduleLayoutInvalidation('] if index == 1 else [
                '    private func scheduleLayoutItemSizeUpdate(']
            if index == 0:
                signatures += ['    private func calculateColumnCount(']
            classes.append(f'final class P{index}: Probe {{\n' + '\n'.join(
                method(source, signature) for signature in signatures) + ('\nfunc restoreAuthorReturnScrollIfNeeded() {}' if index == 1 else '') + '\n}')
        template = (ROOT / 'script/tests/fixtures/GridViewportSizingHarness.swift').read_text()
        with tempfile.TemporaryDirectory(prefix='mwx-grid-viewport-', dir='/private/tmp') as folder:
            work = Path(folder)
            source = work / 'Sizing.swift'
            source.write_text(template.replace('// PRODUCTION_SIZING_CLASSES', '\n'.join(classes)))
            binary = work / 'sizing'
            inputs = [source, ROOT / 'MyWallpaperX/Shared/UI/GridLayoutHelper.swift',
                      UI / 'SteamWorkshopGridLayoutSupport.swift',
                      ROOT / 'MyWallpaperX/Modules/OnlineLibrary/UI/OnlineLibraryGridLayoutSupport.swift']
            build = subprocess.run(['xcrun', 'swiftc', '-parse-as-library', *map(str, inputs),
                                    '-o', str(binary)], capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
            if proof := os.environ.get('MWX_STEAM_GRID_PROOF_DIR'):
                Path(proof).mkdir(parents=True, exist_ok=True)
                (Path(proof) / 'all-grid-sizing.log').write_text(run.stdout + run.stderr)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertIn('All four production sizing owners PASS', run.stdout)
            self.assertNotIn('not defined because', run.stderr)
            self.assertNotIn('UICollectionViewFlowLayoutBreakForInvalidSizes', run.stderr)

    def test_real_container_layout_and_page_replacement(self):
        with tempfile.TemporaryDirectory(prefix='mwx-steam-container-', dir='/private/tmp') as folder:
            work = Path(folder)
            source = work / 'ActualGrid.swift'
            # Only expose state for settling/geometry checks. Keep the real
            # provider, delegate, bindings and layout/snapshot scheduling.
            source.write_text((UI / 'AppKitSteamWorkshopBrowserGridView.swift').read_text().replace('private ', ''))
            names = ['SteamWorkshopKeyboardCollectionView.swift', 'SteamWorkshopGridLayoutSupport.swift',
                     'SteamWorkshopGridKeyboardNavigation.swift', 'SteamWorkshopBrowserFooterSupport.swift',
                     'AppKitSteamWorkshopBrowserFooterComponents.swift']
            binary = work / 'container'
            sources = [ROOT / 'MyWallpaperX/Shared/UI/GridThumbnailPrefetchDemand.swift', ROOT / 'MyWallpaperX/Shared/UI/GridThumbnailDecoder.swift', ROOT / 'script/tests/fixtures/SteamBrowserContainerHarness.swift', source,
                       *[UI / name for name in names], ROOT / 'MyWallpaperX/Shared/UI/GridLayoutHelper.swift',
                       ROOT / 'MyWallpaperX/Shared/UI/WallpaperGridScrollView.swift']
            build = subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-default-isolation', 'MainActor',
                                    *map(str, sources), '-o', str(binary)], capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=40)
            if proof := os.environ.get('MWX_STEAM_GRID_PROOF_DIR'):
                Path(proof).mkdir(parents=True, exist_ok=True)
                (Path(proof) / 'container-runtime.log').write_text(run.stdout + run.stderr)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertIn('checks 77 failures 0', run.stdout)
            self.assertNotIn('not defined because', run.stderr)
            self.assertNotIn('UICollectionViewFlowLayoutBreakForInvalidSizes', run.stderr)

    def test_coalesced_removals_and_native_reflow(self):
        browser = (UI / 'AppKitSteamWorkshopBrowserGridView.swift').read_text()
        downloads = (UI / 'AppKitSteamWorkshopDownloadsGridView.swift').read_text()
        browser_methods = '\n'.join(method(browser, signature) for signature in [
            '    private func applyItems(', '    private func applyPendingItemsIfReady(',
            '    private func commitItems(', '    private func refreshFooterState(',
            '    private func ensureKeyboardFocus(', '    private func restoreScrollOffset(',
            '    private func restorePendingScrollOffsetIfReady('])
        download_methods = '\n'.join(method(downloads, signature) for signature in [
            '    private func applyRecords(', '    private func applyPendingRecords(',
            '    private func commitRecords(', '    private func ensureKeyboardFocus(',
            '    private func restoreAuthorReturnScrollIfNeeded('])
        core = ROOT / 'MyWallpaperX/Modules/SteamWorkshop/Core'
        selection = (core / 'SteamWorkshopService+DownloadSelection.swift').read_text()
        filtering = (core / 'SteamWorkshopService+DownloadFiltering.swift').read_text()
        accessors = (core / 'SteamWorkshopService+DownloadAccessors.swift').read_text()
        selection_methods = '\n'.join(method(selection, signature) for signature in [
            '    func selectDownload(', '    func replaceSelectedDownloads(',
            '    func publishDownloadSelectionState(', '    private func applyDownloadSelectionState('])
        selection_methods += '\n' + method(filtering, '    func sanitizeDownloadSelectionAgainstDisplayedDownloads(')
        selection_methods += '\n' + method(accessors, '    func firstDisplayedDownloadID(')
        # Use the two production publishers/sinks, including receive(on:), so
        # restoring data and offset in one turn exercises their real ordering.
        start = browser.index('        service.$displayedBrowserItems')
        end = browser.index('.store(in: &cancellables)', start) + len('.store(in: &cancellables)')
        bindings = browser[start:end]
        start = browser.index('        service.$pendingBrowserScrollRestoreOffset')
        end = browser.index('.store(in: &cancellables)', start) + len('.store(in: &cancellables)')
        bindings += '\n' + browser[start:end]
        template = (ROOT / 'script/tests/fixtures/SteamGridUpdateHarness.swift').read_text()
        with tempfile.TemporaryDirectory(prefix='mwx-steam-grid-test-', dir='/private/tmp') as folder:
            work = Path(folder)
            source = work / 'Harness.swift'
            source.write_text(template.replace('// BROWSER_METHODS', browser_methods).replace('// DOWNLOAD_METHODS', download_methods)
                .replace('// SELECTION_METHODS', selection_methods).replace('// BROWSER_BINDINGS', bindings))
            binary = work / 'grids'
            sources = [UI / 'SteamWorkshopGridLayoutSupport.swift', UI / 'SteamWorkshopBrowserFooterSupport.swift',
                UI / 'AppKitSteamWorkshopBrowserFooterComponents.swift', ROOT / 'MyWallpaperX/Shared/UI/GridLayoutHelper.swift', source]
            build = subprocess.run(['xcrun', 'swiftc', '-parse-as-library', *map(str, sources),
                '-module-cache-path', str(work / 'modules'), '-o', str(binary)], capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            home = work / 'home'
            home.mkdir()
            run = subprocess.run([str(binary)], env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)),
                capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            facts = json.loads(run.stdout)
            if proof := os.environ.get('MWX_STEAM_GRID_PROOF_DIR'):
                output = Path(proof)
                output.mkdir(parents=True, exist_ok=True)
                (output / 'checks.json').write_text(json.dumps(facts, indent=2) + '\n')
                (output / 'runtime.log').write_text(run.stderr)
            for name, passed in facts.items():
                with self.subTest(name=name):
                    self.assertTrue(passed)
            self.assertTrue(facts)


if __name__ == '__main__':
    unittest.main()
