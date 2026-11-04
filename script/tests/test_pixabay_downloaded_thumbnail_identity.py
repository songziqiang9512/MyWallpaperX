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
import shutil
import subprocess
import sys
import tempfile
import unittest

from script.tests.test_ui_request_schedulers import declaration
from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'MyWallpaperX/Modules/Pixabay/UI/AppKitPixabayDownloadsItem.swift'
CORE = ROOT / 'MyWallpaperX/Modules/Pixabay/Core/PixabayDownloadedContent.swift'
FIXTURE = ROOT / 'script/tests/fixtures/PixabayDownloadedIdentityHarness.swift'
CACHE = ROOT / 'MyWallpaperX/Shared/UI/ThumbnailCache.swift'
MEMORY = ROOT / 'MyWallpaperX/Shared/UI/DecodedThumbnailMemoryCache.swift'


@unittest.skipUnless(sys.platform == 'darwin', 'native shared thumbnail cache requires macOS')
class PixabayDownloadedThumbnailIdentityTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('ffmpeg'), 'owned video fixture generator required')
    def test_real_av_target_sizes_rotation_and_legacy_derivative_upgrade(self):
        fixture = ROOT / 'script/tests/fixtures/PixabayThumbnailGenerationChecks.swift'
        decoder = MEMORY.with_name('GridThumbnailDecoder.swift')
        request = ROOT / 'MyWallpaperX/Shared/ThumbnailRequest.swift'
        paths = [SOURCE, CORE, fixture, CACHE, MEMORY, decoder, request]
        hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
        with tempfile.TemporaryDirectory(prefix='mwx-pixabay-av-', dir='/private/tmp') as directory:
            work = Path(directory); home = work / 'home'; home.mkdir()
            media = work / 'media'; media.mkdir()
            commands = []
            for name, size in [('landscape', '3840x2160'), ('rotatable', '1280x720'), ('tiny', '160x90')]:
                command = ['ffmpeg', '-nostdin', '-v', 'error', '-f', 'lavfi', '-i',
                    'testsrc2=size=' + size + ':rate=2', '-t', '2', '-c:v', 'libx264',
                    '-pix_fmt', 'yuv420p', '-preset', 'fast', '-threads', '1', str(media / (name + '.mp4'))]
                commands.append(command)
                made = subprocess.run(command, capture_output=True, text=True, timeout=30)
                self.assertEqual(made.returncode, 0, made.stdout + made.stderr)
            shutil.copy2(media / 'landscape.mp4', media / 'legacy.mp4')
            command = ['ffmpeg', '-nostdin', '-v', 'error', '-display_rotation:v:0', '90', '-i',
                str(media / 'rotatable.mp4'), '-c', 'copy', str(media / 'portrait.mp4')]
            commands.append(command)
            made = subprocess.run(command, capture_output=True, text=True, timeout=20)
            self.assertEqual(made.returncode, 0, made.stdout + made.stderr)
            product = SOURCE.read_text(); core = CORE.read_text()
            generator = declaration(product, 'nonisolated private final class PixabayThumbnailVideoGeneration')
            call = 'generator.generateCGImageAsynchronously(for: CMTime(seconds: 0.5, preferredTimescale: 600))'
            self.assertEqual(generator.count(call), 1)
            observed = generator.replace(call,
                'generator.generateCGImageAsynchronously(for: PixabayAVProbe.time(CMTime(seconds: 0.5, preferredTimescale: 600), generator: generator))')
            harness = work / 'Harness.swift'
            harness.write_text('import AppKit\nimport AVFoundation\n' + '\n'.join([
                declaration(core, 'nonisolated struct PixabayDownloadedAssetMetadata'),
                declaration(core, 'nonisolated enum PixabayDownloadedFileIdentity'),
                declaration(product, 'enum PixabayDownloadedThumbnailStore'), observed,
                declaration(product, 'extension PixabayDownloadedThumbnailStore'), fixture.read_text()]))
            cache_copy = work / 'ThumbnailCache.swift'
            cache_source = CACHE.read_text()
            self.assertEqual(cache_source.count('private func diskCacheURL('), 1)
            cache_copy.write_text(cache_source.replace('private func diskCacheURL(', 'func diskCacheURL(', 1))
            sources = [MEMORY, cache_copy, decoder, request, harness]
            command = ['xcrun', 'swiftc', *SWIFT_ISOLATION_FLAGS, '-warnings-as-errors', '-parse-as-library',
                *map(str, sources), '-module-cache-path', str(work / 'modules'), '-o', str(work / 'checks')]
            build = subprocess.run(command, capture_output=True, text=True, timeout=150)
            proof = None
            if destination := os.environ.get('MWX_PIXABAY_AV_PROOF_DIR'):
                proof = Path(destination); proof.mkdir(parents=True, exist_ok=True)
                (proof / 'compile.log').write_text(build.stdout + build.stderr)
                (proof / 'inputs.json').write_text(json.dumps(dict(inputs=hashes, command=command,
                    fixtureCommands=commands, observation='Only wraps the actual AV request time to observe its input, maximumSize and thread; no producer or cache body replaced.'), indent=2))
                shutil.copy2(harness, proof / 'Harness.swift')
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(work / 'checks'), str(media)], env=dict(os.environ,
                HOME=str(home), CFFIXED_USER_HOME=str(home)), capture_output=True, text=True, timeout=60)
            if proof:
                (proof / 'stdout.log').write_text(run.stdout); (proof / 'stderr.log').write_text(run.stderr)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            facts = json.loads(run.stdout)
            for name, passed in facts['checks'].items():
                with self.subTest(name=name): self.assertIs(passed, True, facts)
            self.assertEqual(hashes, {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths})
            print(json.dumps({'pixabayActualAV': facts}, sort_keys=True))

    def test_real_store_revalidates_scan_identity_and_retains_other_consumers(self):
        with tempfile.TemporaryDirectory(prefix='mwx-online-identity-', dir='/private/tmp') as directory:
            work = Path(directory)
            production = SOURCE.read_text()
            store = declaration(production, 'enum PixabayDownloadedThumbnailStore')
            store += '\n' + declaration(production, 'extension PixabayDownloadedThumbnailStore')
            leaf = 'await PixabayThumbnailVideoGeneration(url: url, request: request).image()'
            self.assertEqual(store.count(leaf), 1)
            store = store.replace(leaf, 'await IdentityMediaGate.shared.input(request: request)')
            observe = 'var fileURL = url.standardizedFileURL'
            identity = declaration(CORE.read_text(), 'nonisolated enum PixabayDownloadedFileIdentity')
            self.assertEqual(identity.count(observe), 1)
            identity = identity.replace(observe, 'IdentityProbe.shared.record(url.path)\n        ' + observe)
            harness = work / 'Harness.swift'
            harness.write_text('import AppKit\nimport Foundation\n' + identity + '\n' + store + '\n' + FIXTURE.read_text())
            decoder = MEMORY.with_name("GridThumbnailDecoder.swift")
            sources = [SOURCE, CORE, FIXTURE, CACHE, MEMORY, decoder]
            sources.append(ROOT / "MyWallpaperX/Shared/ThumbnailRequest.swift")
            inputs = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in sources}
            command = ['xcrun', 'swiftc', '-parse-as-library', '-default-isolation', 'MainActor',
                str(MEMORY), str(CACHE), str(decoder), str(ROOT / "MyWallpaperX/Shared/ThumbnailRequest.swift"), str(harness), '-module-cache-path', str(work / 'modules'), '-o', str(work / 'checks')]
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
                'prefetchAndVisibleShareLiveIdentity', 'cachedFailureAndSingleKeyInvalidationUseOriginalResult',
                'actualTargetReachesGenerationAndCompatibleWarmPixelsAvoidAV', 'nativeCappedPixelsRemainWarmForLargeTarget', 'fingerprintOffMain'})
            self.assertTrue(all(facts.values()), facts)


if __name__ == '__main__':
    unittest.main()
