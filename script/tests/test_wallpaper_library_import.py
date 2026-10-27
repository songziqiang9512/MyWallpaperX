"""Actual source workers/receipt publishers and App mixed-import consumer.

Cache-key/path queries, preparation, file validation, source model commits and
relationship SQLite are real; thumbnail work and runtime presentation are controlled.
No product App, window, renderer, user media or global service is created.
"""
import hashlib
import json
import os
import re
import shutil
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_ui_library_algorithms import declaration
from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS

ROOT = Path(__file__).resolve().parents[2]


def video_import_cache_methods(tree=ROOT):
    """The original five cache-key/output/query leaves shared by importer gates."""
    core = Path(tree) / 'MyWallpaperX/Modules/VideoLibrary/Core'
    cache = (core / 'WallpaperManager+CachePipeline.swift').read_text()
    static = (core / 'WallpaperManager+StaticFramePipeline.swift').read_text()
    return '\n'.join(declaration(cache, marker) for marker in (
        '    func cacheKey(', '    func thumbnailOutputURL(', '    func existingThumbnailPath(')) + '\n' + '\n'.join(
        declaration(static, marker) for marker in ('    func staticFrameOutputURL(', '    func existingStaticFramePath('))


def actual_import_fixture(tree=ROOT, import_processing_override=None, fixture_tree=None, *, observe_request_work=False,
                          sil_service_override=None, observe_image_work=False):
    """Shared unchanged source workers and controlled non-importer leaves."""
    tree = Path(tree)
    fixture_tree = Path(fixture_tree) if fixture_tree is not None else tree
    paths = ['MyWallpaperX/' + p for p in (
        'Models/WallpaperReference.swift', 'Models/WallpaperContent.swift', 'Models/VideoWallpaper.swift',
        'Models/WallpaperLibraryPage.swift', 'Models/WallpaperSourceImportResult.swift',
        'Core/LibraryCollections/WallpaperLibraryQuery.swift', 'Core/LibraryCollections/UserCollectionsStore.swift',
        'Core/LibraryCollections/UserCollectionsController.swift', 'Core/PlaybackControl/PlaybackResourceLifetime.swift',
        'Core/PlaybackControl/WallpaperRuntimeSwitch.swift', 'Core/PlaybackControl/PlaybackSwitchTransaction.swift',
        'Core/PlaybackControl/ImportedVideoPlaybackAdmission.swift', 'Core/PlaybackControl/ImportedVideoAutoplayGate.swift',
        'App/WallpaperLibraryImportCoordinator.swift',
        'Modules/VideoLibrary/Core/WallpaperManager+LibraryContent.swift',
        'Modules/StaticImageLibrary/Core/SILService+LibraryContent.swift',
        'Modules/VideoLibrary/Core/VideoLibraryContentProjection.swift',
        'Modules/StaticImageLibrary/Core/StaticImageLibraryContentProjection.swift')]
    core = tree / 'MyWallpaperX/Modules/VideoLibrary/Core'
    video_path = Path(import_processing_override) if import_processing_override is not None else core / 'WallpaperManager+ImportProcessing.swift'
    image_path = Path(sil_service_override) if sil_service_override is not None else tree / 'MyWallpaperX/Modules/StaticImageLibrary/Core/SILService.swift'
    summary_path = core / 'WallpaperLibrarySupport.swift'
    presentation_path = core / 'WallpaperManager+ImportPresentation.swift'
    fixture_path = fixture_tree / 'script/tests/fixtures/WallpaperLibraryImportHarness.swift'
    manager_path, cache_path, static_path = (core / name for name in (
        'WallpaperManager.swift', 'WallpaperManager+CachePipeline.swift', 'WallpaperManager+StaticFramePipeline.swift'))
    inputs = [tree / p for p in paths] + [Path(__file__).resolve(), video_path, image_path, summary_path,
        presentation_path, fixture_path, manager_path, cache_path, static_path]
    video, image = video_path.read_text(), image_path.read_text()
    fixture = fixture_path.read_text()
    image_model = declaration(image, 'struct SILWallpaper:')
    if observe_image_work:
        initializer = declaration(image_model, '    init(path:')
        observed = initializer.replace('{', '{\n        ImageWorkProbe.shared.record("metadataInitializations")', 1)
        observed = observed.replace('FileManager.default.attributesOfItem(atPath: path)',
            'ImageWorkProbe.shared.attributesOfItem(atPath: path)')
        observed = observed.replace('CGImageSourceCreateWithURL(', 'ImageWorkProbe.shared.imageSource(')
        observed = observed.replace('        self.addedAt = Date()', '        self.addedAt = Date()\n'
            '        ImageWorkProbe.shared.model(id: id, path: path, addedAt: addedAt, width: pixelWidth, height: pixelHeight)')
        image_model = image_model.replace(initializer, observed)
    fixture = fixture.replace('// PRODUCTION_IMAGE_MODEL', image_model)
    fixture = fixture.replace('@MainActor final class SILService {', '@MainActor final class SILService: ObservableObject {')
    image_field = next(line for line in image.splitlines() if '    @Published var wallpapers:' in line)
    fixture = fixture.replace('    var wallpapers: [SILWallpaper] = []', image_field)
    image_methods = '\n'.join(declaration(image, marker) for marker in (
        '    static var allowedUTTypes:', '    static func isSupportedImage(', '    func importImages(',
        '    private func finishImport(', '    private static func normalizedPath(',
        '    func persistWallpaperMetadata(', '    func invalidatePendingMetadataLoad(',
))
    # Hold the original worker before enumeration, not a replacement
    # importer/metadata result, to exercise its actual reset generation.
    worker = 'DispatchQueue.global(qos: .userInitiated).async { [weak self] in'
    if image_methods.count(worker) != 1: raise AssertionError("Image worker injection must be unique")
    image_methods = image_methods.replace(worker, worker + '\n            ImageImportProbe.shared.waitIfHeld()')
    dispatch = '            DispatchQueue.main.async { [weak self] in'
    if image_methods.count(dispatch) != 1: raise AssertionError("One actual image commit dispatch required")
    image_methods = image_methods.replace(dispatch, '            ImageImportProbe.shared.waitBeforeCommit()\n' + dispatch)
    sync = 'try handle.synchronize()'
    if image_methods.count(sync) != 1: raise AssertionError("Image sync fault leaf must be unique")
    image_methods = image_methods.replace(sync, sync + '\n        if ImageImportProbe.shared.consumeSynchronizationFailure() { throw CocoaError(.fileWriteUnknown) }')
    if observe_image_work:
        candidate_loop = '            for url in fileURLs {'
        if image_methods.count(candidate_loop) != 1: raise AssertionError("One actual image candidate loop required")
        image_methods = image_methods.replace(candidate_loop,
            candidate_loop + '\n                ImageImportProbe.shared.beforeCandidate(url)')
        fixture = fixture.replace('    var metadataLoadGeneration: UInt64 = 0', '''    private var observedGeneration: UInt64 = 0
    var metadataLoadGeneration: UInt64 {
        get { ImageWorkProbe.shared.record("epochReads"); return observedGeneration }
        set { observedGeneration = newValue }
    }''')
        summary = re.search(r'(?m)^([ \t]*)var lines: \[String\] = \[', image_methods)
        if summary is None: raise AssertionError("Actual image summary construction required")
        image_methods = image_methods[:summary.start()] + summary.group(1) + 'ImageWorkProbe.shared.record("summaryBuilds")\n' + image_methods[summary.start():]
        persistence = declaration(image_methods, '    func persistWallpaperMetadata(')
        observed = persistence.replace('{', '{\n        ImageWorkProbe.shared.record("persistEntries")', 1)
        observed = observed.replace('        try data.write(to: persistenceURL, options: .atomic)',
            '        if ImageImportProbe.shared.consumeWriteFailure() { throw CocoaError(.fileWriteNoPermission) }\n        try data.write(to: persistenceURL, options: .atomic)')
        observed = observed.replace(sync, 'ImageWorkProbe.shared.record("syncEntries")\n        ' + sync)
        image_methods = image_methods.replace(persistence, observed)
        image_methods = image_methods.replace(dispatch, dispatch + '\n                defer { ImageWorkProbe.shared.record("finished") }')
    fixture = fixture.replace('// PRODUCTION_IMAGE_METHODS', image_methods)
    fixture = fixture.replace('// PRODUCTION_VIDEO_METHODS', '\n'.join(declaration(video, marker) for marker in (
        '    private struct ImportCounters', '    private enum ImportSourceValidationResult',
        '    private struct PreparedImportEntry', '    private struct ImportPreparationResult',
        '    func processImportedVideos(', '    private func makeImportSummary(', '    private func prepareImportEntries(',
        '    private func beginImportPreparationRequest(', '    private func setImportPreparationWorkItem(',
        '    private func isImportPreparationRequestCurrent(', '    private func applyPreparedImportResult(',
        '    private func validateImportSourceURL(', '    private func makePreparedWallpaper(',
        '    private func appendWallpapersInBatches(')))
    fixture = fixture.replace('// PRODUCTION_IMPORT_VALUES', '\n'.join(declaration(summary_path.read_text(), marker)
        for marker in ('struct ImportSummary', 'enum ImportContext')))
    fixture = fixture.replace('// PRODUCTION_FAILURE_SUMMARY',
        declaration(presentation_path.read_text(), '    func importFailureBreakdown('))
    manager = manager_path.read_text()
    leaves = '\n'.join(declaration(manager, marker) for marker in (
        '    func normalizedPath(', '    func pathExists(', '    func isReadablePath(')) + '\n' + video_import_cache_methods(tree)
    if observe_request_work:
        metrics = {'normalizedPath': 'normalize', 'cacheKey': 'key', 'thumbnailOutputURL': 'thumbnailOutput',
                   'staticFrameOutputURL': 'staticFrameOutput', 'pathExists': 'exists'}
        for name, metric in metrics.items():
            method = declaration(leaves, '    func ' + name + '(')
            observed = method.replace('{', '{\n        ImportRequestWorkProbe.shared.record("' + metric + '")', 1)
            if name in ('normalizedPath', 'pathExists', 'thumbnailOutputURL', 'staticFrameOutputURL'):
                lines = observed.splitlines()
                lines[-2] = lines[-2].replace('        ', '        return ', 1)
                observed = '\n'.join(lines)
            leaves = leaves.replace(method, observed)
    fixture = fixture.replace('// ACTUAL_VIDEO_CACHE_LEAVES', leaves)
    return paths, fixture, inputs


def prepare_video_import_request_sources(tree, work, import_processing_override=None, fixture_tree=None):
    """One existing importer assembly for the gate and task-only before/after."""
    paths, fixture, inputs = actual_import_fixture(tree, import_processing_override, fixture_tree, observe_request_work=True)
    source = Path(work) / 'Checks.swift'
    source.write_text(fixture)
    return [*[Path(tree) / p for p in paths], source], {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}


def prepare_sil_import_work_sources(tree, work, sil_service_override=None, fixture_tree=None):
    """Original image worker/JSON/receipt chain with test-copy observations."""
    paths, fixture, inputs = actual_import_fixture(tree, fixture_tree=fixture_tree,
        sil_service_override=sil_service_override, observe_image_work=True)
    source = Path(work) / 'Checks.swift'
    source.write_text(fixture)
    return [*[Path(tree) / p for p in paths], source], {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}


class WallpaperLibraryImportTests(unittest.TestCase):
    def test_actual_request_paths_cache_queries_and_reentrant_boundaries(self):
        results = []
        expected_normalize = {"nilMiss": 1, "receiptMixed": 11, "bothHits": 5, "thumbnailOnly": 5,
            "staticOnly": 5, "queuedAliasRetarget": 5, "reset": 1, "summaryEpochReentry": 2, "summaryAliasRetarget": 5}
        with tempfile.TemporaryDirectory(prefix='mwx-import-work-', dir='/private/tmp') as directory:
            root = Path(directory)
            runtime = root / 'runtime'
            for configuration, flags in [('debug', ['-D', 'DEBUG']), ('release', ['-O', '-whole-module-optimization'])]:
                work = root / configuration
                work.mkdir()
                sources, inputs = prepare_video_import_request_sources(ROOT, work)
                binary = work / 'checks'
                build = subprocess.run(['xcrun', 'swiftc', *SWIFT_ISOLATION_FLAGS, '-parse-as-library', *flags,
                    *map(str, sources), '-module-cache-path', str(work / 'modules'), '-o', str(binary)],
                    capture_output=True, text=True, timeout=120)
                retained = None
                if evidence := os.environ.get('MWX_IMPORT_REQUEST_EVIDENCE'):
                    retained = Path(evidence) / configuration
                    retained.mkdir(parents=True, exist_ok=True)
                    (retained / 'Checks.swift').write_bytes(sources[-1].read_bytes())
                    (retained / 'inputs.json').write_text(json.dumps(inputs, indent=2) + '\n')
                    (retained / 'compile.stdout').write_text(build.stdout)
                    (retained / 'compile.stderr').write_text(build.stderr)
                self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
                runtime.mkdir()
                run = subprocess.run([str(binary), str(runtime), 'request-work'], capture_output=True, text=True,
                    timeout=35, env=dict(os.environ, HOME=str(runtime), CFFIXED_USER_HOME=str(runtime)))
                if retained:
                    (retained / 'runtime.stdout').write_text(run.stdout)
                    (retained / 'runtime.stderr').write_text(run.stderr)
                self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
                result = json.loads(run.stdout)
                self.assertEqual(set(result), {'functional', 'work'})
                self.assertEqual(set(result['functional']), set(expected_normalize))
                self.assertEqual(set(result['work']), set(expected_normalize))
                for phase, normalizations in expected_normalize.items():
                    for check, passed in result['functional'][phase]['checks'].items():
                        with self.subTest(configuration=configuration, phase=phase, check=check):
                            self.assertIs(passed, True, run.stdout)
                    self.assertEqual(result['work'][phase], {'normalize': normalizations, 'key': 1,
                        'thumbnailOutput': 1, 'staticFrameOutput': 1, 'exists': 5 if phase == 'receiptMixed' else 3}, run.stdout)
                self.assertEqual(inputs, {path: hashlib.sha256(Path(path).read_bytes()).hexdigest() for path in inputs})
                results.append(result)
                print(json.dumps({'configuration': configuration, **result}, sort_keys=True))
                shutil.rmtree(runtime)
        self.assertEqual(results[0], results[1])

    def test_workspace_alias_pending_and_deleted_captured_source(self):
        paths = ['MyWallpaperX/' + p for p in (
            'Models/WallpaperReference.swift', 'Models/WallpaperContent.swift', 'Models/WallpaperLibraryPage.swift',
            'Core/OnlineImages/OnlineImageModels.swift', 'Core/OnlineImages/OnlineImageContentProjection.swift',
            'Core/LibraryCollections/UserCollectionsStore.swift', 'Core/LibraryCollections/UserCollectionsController.swift',
            'Core/LibraryCollections/LibraryCollectionsMigration.swift', 'Core/LibraryCollections/WallpaperLibraryViewPreferencesMigration.swift',
            'Core/LibraryCollections/WallpaperLibraryQuery.swift', 'Core/PlaybackControl/WallpaperRuntimeSwitch.swift',
            'Core/PlaybackControl/PlaybackSwitchTransaction.swift', 'Core/PlaybackControl/WallpaperPlaybackSequence.swift',
            'Core/PlaybackControl/WallpaperRotationDeadline.swift',
            'Shell/WallpaperLibraryPresentation.swift', 'App/WallpaperLibraryWorkspace.swift')]
        paths.append('script/tests/fixtures/OnlineImageLibraryAppStub.swift')
        leaf_path = ROOT / 'script/tests/fixtures/WallpaperLibraryWorkspaceHarness.swift'
        fixture_path = ROOT / 'script/tests/fixtures/WallpaperLibraryWorkspaceAliasHarness.swift'
        startup_path = ROOT / 'MyWallpaperX/Core/LibraryCollections/LibraryCollectionsStartupAdmission.swift'
        publication_path = ROOT / 'MyWallpaperX/Core/LibraryCollections/LibraryCollectionsMigrationPublication.swift'
        gate_path = ROOT / 'MyWallpaperX/Core/PlaybackControl/ImportedVideoAutoplayGate.swift'
        navigation_path = ROOT / 'MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+PlaybackControl.swift'
        settings_path = ROOT / 'MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+PlaybackSettings.swift'
        rotation_path = ROOT / 'script/tests/fixtures/WallpaperLibraryRotationSourceChecks.swift'
        inputs = [ROOT / p for p in paths] + [leaf_path, fixture_path, startup_path, publication_path, gate_path,
                                            navigation_path, settings_path, rotation_path]
        hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
        prelude = leaf_path.read_text().split('@main struct WallpaperLibraryWorkspaceHarness')[0]
        prelude = prelude.replace('// STARTUP_OUTCOME', declaration(startup_path.read_text(), 'nonisolated enum LibraryCollectionsStartupOutcome:'))
        prelude = prelude.replace('// PUBLICATION_VALUE', declaration(publication_path.read_text(), 'nonisolated struct LibraryCollectionsMigrationPublicationResult:'))
        prelude = prelude.replace('// IMPORT_GATE', declaration(gate_path.read_text(), 'final class ImportedVideoAutoplayGate:'))
        navigation, settings = navigation_path.read_text(), settings_path.read_text()
        rotation = '\n'.join(declaration(navigation, signature) for signature in (
            '    var librarySequenceMode:', '    @discardableResult\n    func advanceLibraryPlayback('))
        rotation += '\n' + '\n'.join(declaration(settings, signature) for signature in (
            '    var libraryRotationInterval:', '    var libraryRotationEligible:', '    func rescheduleLibraryRotationTimer(',
            '    func stopAutoSwitchTimer(', '    func refreshAutoSwitchTimerIfNeeded('))
        for marker in ('let timer = Timer(timeInterval:', 'RunLoop.main.add(timer, forMode: .common)'):
            self.assertEqual(rotation.count(marker), 1, marker)
        self.assertEqual(prelude.count('// ACTUAL_SOURCE_ROTATION'), 1)
        rotation = rotation.replace('let timer = Timer(timeInterval:', 'let timer = WorkspaceRotationTimer(timeInterval:')
        rotation = rotation.replace('RunLoop.main.add(timer, forMode: .common)', 'WorkspaceRotationTimer.add(timer)')
        rotation = rotation.replace('CACurrentMediaTime()', 'WorkspaceRotationClock.now')
        prelude = prelude.replace('// ACTUAL_SOURCE_ROTATION', rotation) + '\n' + rotation_path.read_text()
        with tempfile.TemporaryDirectory(prefix='mwx-workspace-alias-', dir='/private/tmp') as directory:
            work = Path(directory)
            source = work / 'Checks.swift'; source.write_text(prelude + '\n' + fixture_path.read_text())
            binary = work / 'checks'
            build = subprocess.run(['xcrun', 'swiftc', *SWIFT_ISOLATION_FLAGS, '-parse-as-library',
                *[str(ROOT / p) for p in paths], str(source), '-module-cache-path', str(work / 'modules'),
                '-o', str(binary)], capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(binary), str(work)], capture_output=True, text=True, timeout=35)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertGreaterEqual(len(checks), 6)
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True, run.stdout + run.stderr)
        self.assertEqual(hashes, {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs})

    def test_actual_workers_receipts_reset_and_mixed_order(self):
        paths, fixture, inputs = actual_import_fixture(observe_image_work=True)
        hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
        with tempfile.TemporaryDirectory(prefix='mwx-library-import-', dir='/private/tmp') as directory:
            work = Path(directory)
            source = work / 'Checks.swift'; source.write_text(fixture)
            binary = work / 'checks'
            build = subprocess.run(['xcrun', 'swiftc', *SWIFT_ISOLATION_FLAGS, '-parse-as-library',
                *[str(ROOT / p) for p in paths], str(source), '-module-cache-path', str(work / 'modules'),
                '-o', str(binary)], capture_output=True, text=True, timeout=120)
            retained = None
            if evidence := os.environ.get('MWX_IMAGE_IMPORT_WORK_EVIDENCE') or os.environ.get('MWX_LIBRARY_IMPORT_EVIDENCE'):
                retained = Path(evidence)
                retained.mkdir(parents=True, exist_ok=True)
                (retained / 'Checks.swift').write_text(fixture)
                (retained / 'inputs.json').write_text(json.dumps(hashes, indent=2) + '\n')
                (retained / 'compile.stdout').write_text(build.stdout)
                (retained / 'compile.stderr').write_text(build.stderr)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            home = work / 'home'; home.mkdir()
            run = subprocess.run([str(binary), str(work)], capture_output=True, text=True, timeout=45,
                env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)))
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertGreaterEqual(len(checks), 15)
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True, run.stdout + run.stderr)
            image_run = subprocess.run([str(binary), str(work), 'image-work'], capture_output=True, text=True, timeout=45,
                env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)))
            if retained:
                (retained / 'mixed.stdout').write_text(run.stdout)
                (retained / 'mixed.stderr').write_text(run.stderr)
                (retained / 'image-work.stdout').write_text(image_run.stdout)
                (retained / 'image-work.stderr').write_text(image_run.stderr)
            self.assertEqual(image_run.returncode, 0, image_run.stdout + image_run.stderr)
            result = json.loads(image_run.stdout)
            expected = {
                # epoch / summary / publication / model construction / persist / sync
                'newReceipt': (3, 0, 1, 1, 1, 1), 'duplicatesOnly': (3, 0, 0, 3, 1, 1),
                'missingOnly': (3, 0, 0, 0, 0, 0), 'noReceiptDuplicate': (3, 0, 0, 3, 0, 0),
                'noReceiptNew': (3, 0, 1, 1, 1, 0), 'ackFailure': (3, 0, 1, 1, 1, 0),
                'syncUncertain': (3, 0, 1, 1, 1, 1), 'workerReset': (3, 0, 1, 1, 1, 0),
                'publicationEpoch': (4, 0, 1, 1, 1, 1), 'summaryReset': (5, 1, 2, 1, 2, 1),
                'membershipChanged': (3, 0, 2, 1, 2, 1),
            }
            self.assertEqual(set(result), {'functional', 'work'})
            self.assertEqual(set(result['functional']), set(expected))
            self.assertEqual(set(result['work']), set(expected))
            metrics = ('epochReads', 'summaryBuilds', 'publications', 'metadataInitializations', 'persistEntries', 'syncEntries')
            for phase, counters in expected.items():
                for check, passed in result['functional'][phase]['checks'].items():
                    with self.subTest(imagePhase=phase, check=check):
                        self.assertIs(passed, True, image_run.stdout)
                self.assertEqual(tuple(result['work'][phase][key] for key in metrics), counters, phase + image_run.stdout)
                expected_reads = 2 if phase in ('duplicatesOnly', 'noReceiptDuplicate') else counters[3]
                self.assertEqual(result['work'][phase]['metadataStatReads'], expected_reads, phase + image_run.stdout)
                self.assertEqual(result['work'][phase]['metadataHeaderReads'], expected_reads, phase + image_run.stdout)
            metadata_run = subprocess.run([str(binary), str(work), 'image-metadata'], capture_output=True, text=True,
                timeout=45, env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)))
            if retained:
                (retained / 'image-metadata.stdout').write_text(metadata_run.stdout)
                (retained / 'image-metadata.stderr').write_text(metadata_run.stderr)
            self.assertEqual(metadata_run.returncode, 0, metadata_run.stdout + metadata_run.stderr)
            metadata = json.loads(metadata_run.stdout)
            metadata_expected = {'repeatOverlap': (3, 0, 1, 6, 1, 1, 3, 3),
                'availabilityChanges': (3, 0, 1, 2, 1, 1, 1, 1),
                'aliasAndNextRequest': (9, 0, 2, 4, 3, 3, 4, 4)}
            self.assertEqual(set(metadata), {'functional', 'work'})
            self.assertEqual(set(metadata['functional']), set(metadata_expected))
            self.assertEqual(set(metadata['work']), set(metadata_expected))
            for phase, counters in metadata_expected.items():
                for check, passed in metadata['functional'][phase]['checks'].items():
                    with self.subTest(metadataPhase=phase, check=check):
                        self.assertIs(passed, True, metadata_run.stdout)
                self.assertEqual(tuple(metadata['work'][phase][key] for key in
                    (*metrics, 'metadataStatReads', 'metadataHeaderReads')), counters, phase + metadata_run.stdout)
            print(json.dumps({'imageWork': result, 'imageMetadata': metadata}, sort_keys=True))
        self.assertEqual(hashes, {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs})


if __name__ == '__main__':
    unittest.main()
