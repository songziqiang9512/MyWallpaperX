"""Actual downloaded-store source identity + shared cache, with controlled async frame leaf.

The full store and its prioritized load method are extracted unchanged; only the AV frame
leaf is replaced by a deterministic gate. Fingerprint entry is instrumented to
observe its calling thread, preserving the real URL metadata query. Real shared
cache, cancellation, publication and generation scheduling run in an isolated HOME.
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
SOURCE = ROOT / 'MyWallpaperX/Modules/Pixabay/UI/AppKitPixabayDownloadsItem.swift'
CORE = ROOT / 'MyWallpaperX/Modules/Pixabay/Core/PixabayDownloadedContent.swift'
FIXTURE = ROOT / 'script/tests/fixtures/PixabayDownloadedIdentityHarness.swift'
CACHE = ROOT / 'MyWallpaperX/Shared/UI/ThumbnailCache.swift'
MEMORY = ROOT / 'MyWallpaperX/Shared/UI/DecodedThumbnailMemoryCache.swift'


@unittest.skipUnless(sys.platform == 'darwin', 'native shared thumbnail cache requires macOS')
class PixabayDownloadedThumbnailIdentityTests(unittest.TestCase):
    def test_real_store_revalidates_scan_identity_and_retains_other_consumers(self):
        with tempfile.TemporaryDirectory(prefix='mwx-online-identity-', dir='/private/tmp') as directory:
            work = Path(directory)
            production = SOURCE.read_text()
            store = declaration(production, 'enum PixabayDownloadedThumbnailStore')
            store += '\n' + declaration(production, 'extension PixabayDownloadedThumbnailStore')
            leaf = 'await PixabayThumbnailVideoGeneration(url: url).image()'
            self.assertEqual(store.count(leaf), 1)
            store = store.replace(leaf, 'await IdentityMediaGate.shared.frame()')
            observe = 'var fileURL = url.standardizedFileURL'
            identity = declaration(CORE.read_text(), 'nonisolated enum PixabayDownloadedFileIdentity')
            self.assertEqual(identity.count(observe), 1)
            identity = identity.replace(observe, 'IdentityProbe.shared.record(url.path)\n        ' + observe)
            harness = work / 'Harness.swift'
            harness.write_text('import AppKit\nimport Foundation\n' + identity + '\n' + store + '\n' + FIXTURE.read_text())
            sources = [SOURCE, CORE, FIXTURE, CACHE, MEMORY]
            inputs = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in sources}
            command = ['xcrun', 'swiftc', '-parse-as-library', '-default-isolation', 'MainActor',
                str(MEMORY), str(CACHE), str(harness), '-module-cache-path', str(work / 'modules'), '-o', str(work / 'checks')]
            build = subprocess.run(command, capture_output=True, text=True, timeout=120)
            proof = None
            if destination := os.environ.get('MWX_ONLINE_IMAGE_THUMBNAIL_SCHEDULING_PROOF_DIR'):
                Path(destination).mkdir(parents=True, exist_ok=True)
                proof = Path(tempfile.mkdtemp(prefix='downloaded-identity-', dir=destination))
                (proof / 'compile.log').write_text(build.stdout + build.stderr)
                (proof / 'inputs.json').write_text(json.dumps({'inputs': inputs, 'command': command,
                    'scope': __doc__, 'transforms': ['full store enum/extension unchanged except controlled frame leaf and fingerprint-thread observer']}, indent=2))
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            self.assertEqual(inputs, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in sources})
            home = work / 'home'; home.mkdir()
            media = work / 'owned-media'; media.mkdir()
            result = subprocess.run([str(work / 'checks'), str(media)], env=dict(os.environ,
                HOME=str(home), CFFIXED_USER_HOME=str(home)), capture_output=True, text=True, timeout=25)
            if proof:
                (proof / 'stdout.log').write_text(result.stdout)
                (proof / 'stderr.log').write_text(result.stderr)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            facts = json.loads(result.stdout)
            self.assertEqual(set(facts), {'scanReplacementUsesActualIdentity', 'sameKeyVisibleSurvivesPrefetchCancel',
                'activeReplacementFinishesUncachedAndRetries', 'queuedReplacementFinishesBeforeSampling',
                'currentWarmKeyResolvesOnceWithoutAV', 'warmOldHintUsesCurrentSource',
                'prefetchAndVisibleShareLiveIdentity', 'cachedFailureAndSingleKeyInvalidationUseOriginalResult', 'fingerprintOffMain'})
            self.assertTrue(all(facts.values()), facts)


if __name__ == '__main__':
    unittest.main()
