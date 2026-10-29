"""Production Video provider demand leases, with controlled asset validation."""
from __future__ import annotations

import json
import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

from script.tests.native_app_harness import prepare_native_app, run_native_app
from script.tests.test_ui_library_algorithms import declaration

ROOT = Path(__file__).resolve().parents[2]

# Match product isolation/conformance inference rather than the compiler defaults.
SWIFT_ISOLATION_FLAGS = ["-swift-version", "5", "-default-isolation", "MainActor"] + [
    argument
    for feature in ["DisableOutwardActorInference", "InferSendableFromCaptures",
                    "GlobalActorIsolatedTypesUsability", "MemberImportVisibility",
                    "InferIsolatedConformances", "NonisolatedNonsendingByDefault"]
    for argument in ["-enable-upcoming-feature", feature]
]


def prepare_video_thumbnail_generator_sources(tree: Path, work: Path, fixture: Path | None = None):
    """Compile real generator/path/clear owners; observe only copied API leaves."""
    core = tree / 'MyWallpaperX/Modules/VideoLibrary/Core'
    pipeline = core / 'WallpaperManager+CachePipeline.swift'
    manager = core / 'WallpaperManager.swift'
    persistence = core / 'WallpaperManager+Persistence.swift'
    static_frames = core / 'WallpaperManager+StaticFramePipeline.swift'
    import_processing = core / 'WallpaperManager+ImportProcessing.swift'
    application = core / 'WallpaperManager+WallpaperApplication.swift'
    model = tree / 'MyWallpaperX/Models/VideoWallpaper.swift'
    still_frame = tree / 'MyWallpaperX/Shared/VideoStillFrame.swift'
    fixture = fixture or tree / 'script/tests/fixtures/VideoThumbnailGeneratorChecks.swift'
    inputs = [pipeline, manager, persistence, static_frames, application, import_processing, model, still_frame, fixture]
    hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
    manager_source = manager.read_text()
    fields = []
    for name in ['thumbnailQueue', 'deletionQueue', 'importAssetPipelineQueue', 'thumbnailCache', 'thumbnailCacheLock', 'thumbnailGenerationLimiter',
                 'thumbnailInFlightHandlers', 'thumbnailInFlightLock', 'scheduledStaticFramePaths',
                 'staticFrameScheduleLock', 'cacheGeneration', 'cacheGenerationLock',
                 'thumbnailGenerationFailures', 'thumbnailGenerationFailureLock', 'thumbnailFailureRetryCooldown']:
        lines = re.findall(r'^    (?:let|var) ' + name + r'\b.*$', manager_source, re.MULTILINE)
        if len(lines) != 1: raise AssertionError('unique original cache field required: ' + name)
        fields.append('    ' + lines[0].strip())
    normalizer = declaration(manager_source, '    func normalizedPath(')
    normalize_leaf = '        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path'
    if normalizer.count(normalize_leaf) != 1: raise AssertionError('unique original normalization leaf required')
    normalizer = normalizer.replace(normalize_leaf,
        '        VideoThumbnailObservations.shared.normalized()\n        return ' + normalize_leaf.strip())
    harness = fixture.read_text().replace('// ACTUAL_CACHE_FIELDS', '\n'.join(fields))
    harness = harness.replace('// ACTUAL_IMPORT_BATCH', declaration(import_processing.read_text(),
        '    private func scheduleImportedAssetsProcessing(').replace('    private func ', '    func ', 1))
    harness = harness.replace('// ACTUAL_PATH_METHODS', normalizer + '\n' + declaration(manager_source, '    func pathExists('))
    harness = harness.replace('// ACTUAL_CLEAR_METHOD', declaration(persistence.read_text(), '    func clearPreviewCacheArtifacts(')
        + '\n' + declaration(application.read_text(), '    func clearUnprotectedStaticFrameFiles('))
    harness = harness.replace('// ACTUAL_STATIC_FRAME_OUTPUT', declaration(static_frames.read_text(), '    func staticFrameOutputURL('))
    observed = pipeline.read_text()
    shared_decode = still_frame.read_text()
    entry = '        let result = ImageResult()'
    hash_leaf = '        let digest = SHA256.hash(data: Data(normalized.utf8))'
    if shared_decode.count(entry) != 1 or observed.count(hash_leaf) != 1:
        raise AssertionError('unique real AV and key observation leaves required')
    shared_decode = shared_decode.replace(entry, '        VideoThumbnailObservations.shared.beginDecode(generator)\n'
        '        defer { VideoThumbnailObservations.shared.endDecode() }\n' + entry)
    observed = observed.replace(hash_leaf, '        VideoThumbnailObservations.shared.hashed()\n' + hash_leaf)
    source = work / pipeline.name; source.write_text(observed)
    support = work / 'VideoThumbnailGeneratorChecks.swift'; support.write_text(harness)
    frozen_model = work / model.name; shutil.copy2(model, frozen_model)
    frozen_still_frame = work / still_frame.name; frozen_still_frame.write_text(shared_decode)
    return [source, frozen_model, frozen_still_frame, support], hashes


def prepare_video_static_frame_sources(tree: Path, work: Path, fixtures: Path | None = None):
    """Real StaticFrame/AV, sync callback and removal; only desktop/state leaves."""
    fixtures = fixtures or tree
    folder = fixtures / 'script/tests/fixtures'
    common = folder / 'VideoThumbnailGeneratorChecks.swift'
    fixture = folder / 'VideoStaticFramePipelineChecks.swift'
    shared = '\n'.join(declaration(common.read_text(), name) for name in (
        'nonisolated final class DecodeHold', 'nonisolated final class VideoThumbnailObservations',
        'nonisolated final class ThumbnailCompletions'))
    combined = work / 'VideoStaticFrameCombined.swift'
    combined.write_text(fixture.read_text() + '\n' + shared)
    sources, hashes = prepare_video_thumbnail_generator_sources(tree, work, combined)
    core = tree / 'MyWallpaperX/Modules/VideoLibrary/Core'
    manager = core / 'WallpaperManager.swift'
    application = core / 'WallpaperManager+WallpaperApplication.swift'
    removal = core / 'WallpaperManager+Removal.swift'
    types = core / 'WallpaperLibrarySupport.swift'
    queues = re.findall(r'^    let staticFrameQueue\b.*$', manager.read_text(), re.MULTILINE)
    if len(queues) != 1: raise AssertionError('one actual static frame queue required')
    support = sources[-1]
    body = support.read_text().replace('// ACTUAL_STATIC_QUEUE', queues[0])
    body = body.replace('// ACTUAL_SYNC_METHOD', declaration(application.read_text(), '    func syncSystemWallpaper('))
    body = body.replace('// ACTUAL_REMOVAL_METHODS', '\n'.join(declaration(removal.read_text(), name) for name in (
        '    struct RemovalRecord', '    func removeDerivedAssets(', '    private func removeFileIfExists(')))
    body = body.replace('// ACTUAL_DELETION_FAILURE', declaration(types.read_text(), 'struct WallpaperDeletionFailure'))
    support.write_text(body)
    static = core / 'WallpaperManager+StaticFramePipeline.swift'
    actual_static = work / static.name; shutil.copy2(static, actual_static)
    for path in [common, fixture, application, removal, types]:
        hashes[str(path)] = hashlib.sha256(path.read_bytes()).hexdigest()
    return [*sources, actual_static], hashes


class VideoThumbnailPrefetchTests(unittest.TestCase):
    def test_steam_scheduler_cancellation_and_visible_promotion(self):
        source = (ROOT / 'MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopPreviewRequestCoordinator.swift').read_text()
        start = source.index('nonisolated enum SteamWorkshopPreviewRequestPriority:')
        end = source.index('nonisolated final class SteamWorkshopPreviewLoadCancellation:', start)
        scheduler = source[source.index('actor SteamWorkshopPreviewRequestScheduler {'):]
        with tempfile.TemporaryDirectory(prefix='mwx-steam-preview-demand-', dir='/private/tmp') as directory:
            work = Path(directory)
            actual = work / 'Scheduler.swift'
            actual.write_text('import Foundation\n' + source[start:end] + scheduler + '\n' +
                (ROOT / 'script/tests/fixtures/SteamPreviewSchedulingChecks.swift').read_text())
            binary = work / 'checks'
            build = subprocess.run(['xcrun', 'swiftc', *SWIFT_ISOLATION_FLAGS, '-warnings-as-errors', '-parse-as-library', str(actual),
                '-module-cache-path', str(work / 'modules'), '-o', str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=20)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            if proof := os.environ.get("MWX_VIDEO_PREFETCH_PROOF_DIR"):
                target = Path(proof); target.mkdir(parents=True, exist_ok=True)
                (target / "steam-scheduler.json").write_text(json.dumps(checks, indent=2) + "\n")
                (target / "steam-scheduler-build.log").write_text(build.stdout + build.stderr)
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertTrue(passed)

    def test_validation_handoff_cancel_and_deleted_asset(self):
        provider = (ROOT / 'MyWallpaperX/Modules/VideoLibrary/UI/AppKitLibraryGridSupport.swift').read_text()
        provider = provider[provider.index('enum VideoLibraryThumbnailStore {'):]
        with tempfile.TemporaryDirectory(prefix='mwx-video-demand-', dir='/private/tmp') as directory:
            work = Path(directory)
            actual = work / 'Provider.swift'
            item = (ROOT / 'MyWallpaperX/Modules/VideoLibrary/UI/AppKitLibraryGridItemView.swift').read_text()
            start = item.index('    func configure(')
            end = item.index('    private func setupViews()', start)
            actual.write_text('import AppKit\n' + provider + '\n@MainActor final class VideoCardProbe {\n' +
                (ROOT / 'script/tests/fixtures/VideoCardProbeFields.swift').read_text() + item[start:end] + '\n}')
            shared = ROOT / 'MyWallpaperX/Shared/UI'
            sources = [actual, shared / 'GridThumbnailDecoder.swift', shared / 'DecodedThumbnailMemoryCache.swift',
                       shared / 'ThumbnailCache.swift', ROOT / 'script/tests/fixtures/VideoThumbnailPrefetchChecks.swift']
            # Preserve the original memory-pressure/reheat case without adding
            # a product memory-only cache API solely for this fixture.
            cache_source = shared / 'ThumbnailCache.swift'
            cache = cache_source.read_text()
            self.assertEqual(cache.count('private let imageCache:'), 1)
            cache_copy = work / 'ThumbnailCache.swift'
            cache_copy.write_text(cache.replace('private let imageCache:', 'let imageCache:', 1))
            sources[sources.index(cache_source)] = cache_copy
            binary = work / 'checks'
            build = subprocess.run(['xcrun', 'swiftc', *SWIFT_ISOLATION_FLAGS, '-warnings-as-errors', '-parse-as-library', *map(str, sources),
                '-module-cache-path', str(work / 'modules'), '-o', str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(binary)], env=dict(os.environ, HOME=str(work / 'home'),
                CFFIXED_USER_HOME=str(work / 'home'), VIDEO_DEMAND_ROOT=str(work)),
                capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            if proof := os.environ.get("MWX_VIDEO_PREFETCH_PROOF_DIR"):
                target = Path(proof); target.mkdir(parents=True, exist_ok=True)
                (target / "checks.json").write_text(json.dumps(checks, indent=2) + "\n")
                (target / "build.log").write_text(build.stdout + build.stderr)
                (target / "runtime.log").write_text(run.stderr)
            self.assertGreaterEqual(len(checks), 12)
            for name, passed in checks.items():
                with self.subTest(name=name):
                    self.assertTrue(passed)

    def test_visible_preview_repair_is_scoped_to_original_provider_and_current_row(self):
        support = (ROOT / 'MyWallpaperX/Modules/VideoLibrary/UI/AppKitLibraryGridSupport.swift').read_text()
        with tempfile.TemporaryDirectory(prefix='mwx-visible-preview-repair-', dir='/private/tmp') as directory:
            work = Path(directory)
            source = work / 'Provider.swift'; source.write_text(support)
            shared = ROOT / 'MyWallpaperX/Shared/UI'
            sources = [source, shared / 'GridThumbnailDecoder.swift', shared / 'DecodedThumbnailMemoryCache.swift',
                shared / 'ThumbnailCache.swift', ROOT / 'script/tests/fixtures/VideoVisiblePreviewRepairChecks.swift']
            binary = work / 'checks'
            build = subprocess.run(['xcrun', 'swiftc', *SWIFT_ISOLATION_FLAGS, '-warnings-as-errors', '-parse-as-library',
                *map(str, sources), '-module-cache-path', str(work / 'modules'), '-o', str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30,
                env=dict(os.environ, HOME=str(work / 'home'), CFFIXED_USER_HOME=str(work / 'home')))
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertGreaterEqual(len(checks), 16)
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True)

    def test_complete_video_card_hover_click_exit_and_restore_never_scale(self):
        ui = ROOT / 'MyWallpaperX/Modules/VideoLibrary/UI'
        shared = ROOT / 'MyWallpaperX/Shared/UI'
        fixtures = ROOT / 'script/tests/fixtures'
        support = (ui / 'AppKitLibraryGridSupport.swift').read_text()
        provider = support[support.index('enum VideoLibraryThumbnailStore {'):]
        # Reuse only the existing model/controlled asset-validation leaves. The
        # complete card (including its real hierarchy/events) replaces no method.
        leaves = (fixtures / 'VideoThumbnailPrefetchChecks.swift').read_text().split('@main struct VideoThumbnailPrefetchChecks {')[0]
        card = re.sub(r"\bprivate\s+", "", (ui / 'AppKitLibraryGridItemView.swift').read_text())
        with tempfile.TemporaryDirectory(prefix='mwx-video-card-interaction-', dir='/private/tmp') as directory:
            work = Path(directory)
            actual = work / 'ActualCard.swift'
            actual.write_text(leaves + '\n' + provider + '\n' + card)
            sources = [actual, ROOT / 'MyWallpaperX/Shared/Components/WallpaperCardInteractionView.swift',
                       ROOT / 'MyWallpaperX/Shared/Components/WallpaperCardSupportViews.swift',
                       ROOT / 'MyWallpaperX/Shared/Components/WallpaperCardControlsView.swift', fixtures / 'VideoCardInteractionHarness.swift',
                       fixtures / 'GridCardInteractionChecks.swift', fixtures / 'NativeAppHarness.swift', *[shared / name for name in [
                           'GridThumbnailDecoder.swift', 'DecodedThumbnailMemoryCache.swift', 'ThumbnailCache.swift',
                           'AppearanceAwareContainerView.swift', 'NSViewExtensions.swift',
                           'UIInteractionAnimation.swift', 'WallpaperGridScrollView.swift',
                           'WallpaperGridIdentifiable.swift', 'GridCollectionViewProtocol.swift',
                           'BoxSelectionState.swift', 'GridThumbnailPrefetchDemand.swift']]]
            sources += [ROOT / 'MyWallpaperX' / path for path in [
                'Models/WallpaperReference.swift', 'Models/WallpaperContent.swift', 'Models/WallpaperLibraryPage.swift',
                'Shared/Components/WallpaperLibraryGridMetrics.swift', 'Shell/WallpaperLibraryGridController.swift']]
            sources.append(fixtures / 'WallpaperLibraryGridCardReflowChecks.swift')
            binary = prepare_native_app(work, 'VideoCardInteractionChecks')
            build = subprocess.run(['xcrun', 'swiftc', *SWIFT_ISOLATION_FLAGS, '-warnings-as-errors', '-parse-as-library',
                *map(str, sources), '-module-cache-path', str(work / 'modules'), '-o', str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = run_native_app(binary, timeout=30, proof_environment="MWX_VIDEO_PREFETCH_PROOF_DIR")
            if proof := os.environ.get("MWX_VIDEO_PREFETCH_PROOF_DIR"):
                target = Path(proof); target.mkdir(parents=True, exist_ok=True)
                (target / "whole-card-interaction-build.log").write_text(build.stdout + build.stderr)
                (target / "whole-card-interaction.json").write_text(run.stdout)
                (target / "whole-card-interaction-runtime.log").write_text(run.stderr)
            # LaunchServices reports launcher status; this added group does not
            # replace either pre-existing direct-child exit assertion.
            self.assertEqual(run.launch_returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertGreaterEqual(len(checks), 17)
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True)
            reflow = run_native_app(binary, ["--card-reflow"], timeout=30)
            self.assertEqual(reflow.launch_returncode, 0, reflow.stdout + reflow.stderr)
            if proof := os.environ.get("MWX_VIDEO_PREFETCH_PROOF_DIR"):
                (Path(proof) / "reflow.json").write_text(reflow.stdout)
                (Path(proof) / "reflow-runtime.log").write_text(reflow.stderr)
            reflow_checks = json.loads(reflow.stdout)
            self.assertEqual(len(reflow_checks), 17)
            for name, passed in reflow_checks.items():
                with self.subTest(name=name): self.assertIs(passed, True, reflow.stderr)


@unittest.skipUnless(sys.platform == 'darwin' and shutil.which('ffmpeg'),
                     'macOS and ffmpeg owned fixture generator required')
class VideoThumbnailGeneratorTests(unittest.TestCase):
    def test_real_generator_cache_aliases_clear_generation_and_jpeg_results(self):
        proof = os.environ.get('MWX_VIDEO_THUMBNAIL_GENERATOR_PROOF_DIR')
        with tempfile.TemporaryDirectory(prefix='mwx-video-generator-', dir='/private/tmp') as directory:
            root = Path(directory)
            clip = root / 'owned.mp4'
            generated = subprocess.run(['ffmpeg', '-nostdin', '-v', 'error', '-f', 'lavfi',
                '-i', 'testsrc2=size=512x288:rate=2', '-t', '2', '-c:v', 'libx264',
                '-pix_fmt', 'yuv420p', '-crf', '20', '-preset', 'fast', '-threads', '1', str(clip)],
                capture_output=True, text=True, timeout=15)
            self.assertEqual(generated.returncode, 0, generated.stdout + generated.stderr)
            configuration_results = []
            for configuration, flags in [('debug', ['-D', 'DEBUG']), ('release', ['-O', '-whole-module-optimization'])]:
                with self.subTest(configuration=configuration):
                    work = root / configuration; work.mkdir()
                    home = work / 'home'; home.mkdir()
                    for name in ['first.mp4', 'renamed.mp4', 'stale.mp4', 'clear.mp4']:
                        shutil.copyfile(clip, work / name)
                    (work / 'invalid.mp4').write_bytes(b'owned invalid video fixture')
                    sources, hashes = prepare_video_thumbnail_generator_sources(ROOT, work)
                    binary = work / 'generator'
                    command = ['xcrun', 'swiftc', *SWIFT_ISOLATION_FLAGS, *flags, '-parse-as-library',
                        *map(str, sources), '-module-cache-path', str(work / 'modules'), '-o', str(binary)]
                    compiled = subprocess.run(command, capture_output=True, text=True, timeout=150)
                    if proof:
                        output = Path(proof) / configuration; output.mkdir(parents=True, exist_ok=True)
                        (output / 'compile.json').write_text(json.dumps({'command': command, 'returncode': compiled.returncode,
                            'stdout': compiled.stdout, 'stderr': compiled.stderr, 'inputSHA256': hashes,
                            'clipSHA256': hashlib.sha256(clip.read_bytes()).hexdigest(),
                            'observation': 'Original path and SHA entry calls counted; real AV entry paused/observed, its complete body preserved.'}, indent=2))
                        for source in sources: shutil.copy2(source, output / source.name)
                    self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
                    run = subprocess.run([str(binary), str(work)], capture_output=True, text=True, timeout=90,
                        env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)))
                    if proof:
                        (output / 'runtime.json').write_text(json.dumps({'returncode': run.returncode,
                            'stdout': run.stdout, 'stderr': run.stderr}, indent=2))
                    self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
                    result = json.loads(run.stdout)
                    self.assertTrue(result['checks'])
                    for name, passed in result['checks'].items():
                        with self.subTest(configuration=configuration, check=name): self.assertIs(passed, True, result)
                    self.assertEqual(result['work'], {'coldThreeRequests': {'normalizations': 3, 'hashes': 3},
                        'memoryHit': {'normalizations': 1, 'hashes': 1}, 'diskHit': {'normalizations': 1, 'hashes': 1},
                        'resolvedDisk': {'normalizations': 1, 'hashes': 1}})
                    self.assertEqual(hashes, {path: hashlib.sha256(Path(path).read_bytes()).hexdigest() for path in hashes})
                    configuration_results.append(result)
            self.assertEqual(configuration_results[0], configuration_results[1])


@unittest.skipUnless(sys.platform == 'darwin' and shutil.which('ffmpeg'),
                     'macOS and ffmpeg owned fixture generator required')
class VideoStaticFramePipelineTests(unittest.TestCase):
    def test_actual_static_worker_queue_retarget_generation_sync_and_removal(self):
        proof = os.environ.get('MWX_VIDEO_STATIC_FRAME_PROOF_DIR')
        with tempfile.TemporaryDirectory(prefix='mwx-video-static-frame-', dir='/private/tmp') as directory:
            root = Path(directory)
            seeds = []
            for name, filters in [('a', []), ('b', ['-vf', 'hue=h=120'])]:
                seed = root / (name + '.mp4'); seeds.append(seed)
                generated = subprocess.run(['ffmpeg', '-nostdin', '-v', 'error', '-f', 'lavfi',
                    '-i', 'testsrc2=size=512x288:rate=2', '-t', '2', *filters, '-c:v', 'libx264',
                    '-pix_fmt', 'yuv420p', '-crf', '20', '-preset', 'fast', '-threads', '1', str(seed)],
                    capture_output=True, text=True, timeout=15)
                self.assertEqual(generated.returncode, 0, generated.stdout + generated.stderr)
            results = []
            for configuration, flags in [('debug', ['-D', 'DEBUG']), ('release', ['-O', '-whole-module-optimization'])]:
                work = root / configuration; work.mkdir()
                home = work / 'home'; home.mkdir()
                for seed in seeds: shutil.copy2(seed, work / seed.name)
                (work / 'invalid.mp4').write_bytes(b'owned corrupt static frame source')
                sources, hashes = prepare_video_static_frame_sources(ROOT, work)
                binary = work / 'static-frame'
                command = ['xcrun', 'swiftc', *SWIFT_ISOLATION_FLAGS, *flags, '-parse-as-library',
                    *map(str, sources), '-module-cache-path', str(work / 'modules'), '-o', str(binary)]
                built = subprocess.run(command, capture_output=True, text=True, timeout=150)
                output = Path(proof) / configuration if proof else None
                if output:
                    output.mkdir(parents=True, exist_ok=True)
                    (output / 'compile.json').write_text(json.dumps({'command': command,
                        'returncode': built.returncode, 'stdout': built.stdout, 'stderr': built.stderr,
                        'inputs': hashes, 'seedSHA256': [hashlib.sha256(s.read_bytes()).hexdigest() for s in seeds]}, indent=2))
                    for source in sources: shutil.copy2(source, output / source.name)
                self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
                run = subprocess.run([str(binary), str(work)], capture_output=True, text=True, timeout=90,
                    env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)))
                if output:
                    (output / 'runtime.json').write_text(json.dumps({'returncode': run.returncode,
                        'stdout': run.stdout, 'stderr': run.stderr}, indent=2))
                self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
                result = json.loads(run.stdout)
                self.assertTrue(result['checks'])
                for name, passed in result['checks'].items():
                    with self.subTest(configuration=configuration, check=name): self.assertIs(passed, True, result)
                self.assertEqual(result['work'], {
                    'scheduleTwoSynchronousMisses': {'normalizations': 2, 'hashes': 2},
                    'systemSyncSynchronousMiss': {'normalizations': 1, 'hashes': 1},
                    'derivedRemoval': {'normalizations': 1, 'hashes': 1}})
                self.assertEqual(hashes, {path: hashlib.sha256(Path(path).read_bytes()).hexdigest() for path in hashes})
                results.append(result)
            self.assertEqual(results[0], results[1])


if __name__ == '__main__':
    unittest.main()
