"""Online viewport consumers: eviction reuse, retained handoff and real ancestor visibility.

Production prefetch methods/fields and complete downloaded demand extension are
retained. Controllable cache/card leaves expose demand and cancellation, while
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
DOWNLOADS = MODULE / 'UI/AppKitOLDownloadsGridView.swift'
DEMAND = MODULE / 'UI/AppKitOLDownloadsGridView+ThumbnailDemand.swift'
HELPER = ROOT / 'MyWallpaperX/Shared/UI/GridThumbnailPrefetchDemand.swift'
FIXTURE = ROOT / 'script/tests/fixtures/OnlineGridThumbnailDemandHarness.swift'
SOURCES = [SERVICE, BROWSER, DOWNLOADS, DEMAND, HELPER, FIXTURE]


def harness_source():
    service, browser, downloads = [path.read_text() for path in (SERVICE, BROWSER, DOWNLOADS)]
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
    template = template.replace('// DOWNLOADS_LIFECYCLE', '\n'.join(declaration(downloads, value) for value in lifecycle))
    template = template.replace('// BROWSER_LIFECYCLE', '\n'.join(declaration(browser, value) for value in lifecycle))
    template = template.replace('// BROWSER_DEMAND_METHODS', '\n'.join(declaration(browser, value) for value in (
        '    private var canLoadThumbnails:', '    private func updateThumbnailWindowVisibility(',
        '    private func pauseThumbnailDemand(', '    private func updateVisibleThumbnailPriorities(',
        '    private func applyThumbnailDemand(')))
    return HELPER.read_text() + '\n' + DEMAND.read_text() + '\n' + template


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
                       str(source), '-module-cache-path', str(work / 'modules'), '-o', str(binary)]
            build = subprocess.run(command, capture_output=True, text=True, timeout=120)
            proof = None
            if destination := os.environ.get('MWX_ONLINE_SCHEDULING_PROOF_DIR'):
                Path(destination).mkdir(parents=True, exist_ok=True)
                proof = Path(tempfile.mkdtemp(prefix='grid-demand-', dir=destination))
                (proof / 'compile.log').write_text(build.stdout + build.stderr)
                (proof / 'inputs.json').write_text(json.dumps({'inputs': inputs, 'command': command,
                    'scope': __doc__, 'transforms': ['extract full production prefetch state/methods and lifecycle declarations',
                        'complete downloaded demand extension unchanged', 'controlled cache/card transport leaves']}, indent=2))
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
