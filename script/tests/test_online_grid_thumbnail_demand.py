"""Online viewport consumers: eviction reuse, retained handoff and real ancestor visibility.

Production remote prefetch/lifecycle and unified Grid + App adapter downloaded
demand methods are retained. Controllable cache/card leaves expose demand and cancellation, while
real AppKit NSView hierarchy sends hide/unhide/detach callbacks. This gate does
not measure HTTP, pixels, collection layout, frame rate, or full App behavior.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from script.tests.test_ui_request_schedulers import declaration

ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / 'MyWallpaperX/Modules/OnlineLibrary'
SERVICE = MODULE / 'Core/OnlineLibraryService.swift'
BROWSER = MODULE / 'UI/AppKitOLBrowserGridView.swift'
ADAPTER = ROOT / 'MyWallpaperX/App/WallpaperLibraryCellAdapter.swift'
GRID = ROOT / 'MyWallpaperX/Shell/WallpaperLibraryGridController.swift'
HELPER = ROOT / 'MyWallpaperX/Shared/UI/GridThumbnailPrefetchDemand.swift'
FIXTURE = ROOT / 'script/tests/fixtures/OnlineGridThumbnailDemandHarness.swift'
GRID_SOURCES = [ROOT / 'MyWallpaperX' / name for name in (
    'Models/WallpaperReference.swift', 'Models/WallpaperContent.swift', 'Models/WallpaperLibraryPage.swift',
    'Core/OnlineImages/OnlineImageModels.swift', 'Core/OnlineImages/OnlineImageContentProjection.swift',
    'Shared/Components/WallpaperLibraryGridMetrics.swift', 'Shared/Components/WallpaperCardInteractionView.swift',
    'Shared/UI/WallpaperGridScrollView.swift', 'Shared/UI/BoxSelectionState.swift')]
GRID_SOURCES.append(ROOT / 'script/tests/fixtures/OnlineImageLibraryAppStub.swift')
SOURCES = [SERVICE, BROWSER, ADAPTER, GRID, HELPER, FIXTURE, *GRID_SOURCES]


def harness_source():
    service, browser, adapter = [path.read_text() for path in (SERVICE, BROWSER, ADAPTER)]
    state = declaration(service, '    private struct ThumbnailPrefetch')
    for name in ('thumbnailPrefetches', 'itemIndexByID', 'previousVisibleStart'):
        state += '\n' + next(line for line in service.splitlines() if 'private var ' + name in line)
    methods = '\n'.join(declaration(service, signature) for signature in (
        '    func prioritizeVisibleItemIDs(', '    func cancelThumbnailPrefetch(', '    func thumbnailPrefetchNeedsRefresh(',
        '    private func prefetchThumbnailImages('))
    template = FIXTURE.read_text().replace('// ONLINE_PREFETCH_STATE', state)
    template = template.replace('// ONLINE_PREFETCH_METHODS', methods)
    lifecycle = ('    override func viewDidMoveToWindow(', '    override func viewDidHide(',
                 '    override func viewDidUnhide(')
    template = template.replace('// ADAPTER_DEMAND_DECLARATIONS', '\n'.join(declaration(adapter, value).replace('private ', '') for value in (
        '    private enum Source:', '    private final class Prefetch', '    func updateViewport(',
        '    private func prefetchAssets(', '    private func resolveSource(')))
    template = template.replace('// BROWSER_LIFECYCLE', '\n'.join(declaration(browser, value) for value in lifecycle))
    template = template.replace('// BROWSER_DEMAND_METHODS', '\n'.join(declaration(browser, value) for value in (
        '    private var canLoadThumbnails:', '    private func updateThumbnailWindowVisibility(',
        '    private func pauseThumbnailDemand(', '    private func updateVisibleThumbnailPriorities(',
        '    private func applyThumbnailDemand(')))
    return template


@unittest.skipUnless(sys.platform == 'darwin', 'native NSView visibility requires macOS')
class OnlineGridThumbnailDemandTests(unittest.TestCase):
    def test_production_consumer_sets_reheat_after_eviction_and_follow_ancestor_visibility(self):
        with tempfile.TemporaryDirectory(prefix='mwx-online-grid-demand-', dir='/private/tmp') as directory:
            work = Path(directory)
            source = work / 'Harness.swift'
            source.write_text(harness_source())
            inputs = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in SOURCES}
            binary = work / 'online-grid-demand'
            command = ['xcrun', 'swiftc', '-parse-as-library', '-default-isolation', 'MainActor',
                       '-swift-version', '5', *map(str, GRID_SOURCES), str(GRID), str(HELPER), str(source), '-module-cache-path', str(work / 'modules'), '-o', str(binary)]
            build = subprocess.run(command, capture_output=True, text=True, timeout=120)
            proof = None
            if destination := os.environ.get('MWX_ONLINE_SCHEDULING_PROOF_DIR'):
                Path(destination).mkdir(parents=True, exist_ok=True)
                proof = Path(tempfile.mkdtemp(prefix='grid-demand-', dir=destination))
                (proof / 'compile.log').write_text(build.stdout + build.stderr)
                (proof / 'inputs.json').write_text(json.dumps({'inputs': inputs, 'command': command,
                    'scope': __doc__, 'transforms': ['extract full production prefetch state/methods and lifecycle declarations',
                        'full unified native GridController and actual App adapter viewport methods', 'controlled cache/card transport leaves']}, indent=2))
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            self.assertEqual(inputs, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in SOURCES})
            home = work / 'home'
            home.mkdir()
            result = subprocess.run([str(binary)], env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)),
                                    capture_output=True, text=True, timeout=20)
            if proof:
                (proof / 'stdout.log').write_text(result.stdout)
                (proof / 'stderr.log').write_text(result.stderr)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            facts = json.loads(result.stdout)
            self.assertEqual(set(facts), {'onlineEvictionFailureAndNearVisible',
                                         'downloadEvictionSourceAndNearVisible', 'ancestorHideUnhideAndDetach'})
            self.assertTrue(all(facts.values()), facts)


if __name__ == '__main__':
    unittest.main()
