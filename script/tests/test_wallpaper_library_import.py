"""Actual source workers/receipt publishers and App mixed-import consumer.

Only cache/thumbnail/runtime presentation leaves are controlled; production
preparation, file validation, source model commits and relationship SQLite run.
No product App, window, renderer, user media or global service is created.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_ui_library_algorithms import declaration
from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS

ROOT = Path(__file__).resolve().parents[2]


def actual_import_fixture():
    """Shared unchanged source workers and controlled non-importer leaves."""
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
    video_path = ROOT / 'MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+ImportProcessing.swift'
    image_path = ROOT / 'MyWallpaperX/Modules/StaticImageLibrary/Core/SILService.swift'
    summary_path = ROOT / 'MyWallpaperX/Modules/VideoLibrary/Core/WallpaperLibrarySupport.swift'
    presentation_path = ROOT / 'MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+ImportPresentation.swift'
    fixture_path = ROOT / 'script/tests/fixtures/WallpaperLibraryImportHarness.swift'
    inputs = [ROOT / p for p in paths] + [video_path, image_path, summary_path, presentation_path, fixture_path]
    video, image = video_path.read_text(), image_path.read_text()
    fixture = fixture_path.read_text()
    fixture = fixture.replace('// PRODUCTION_IMAGE_MODEL', declaration(image, 'struct SILWallpaper:'))
    image_methods = '\n'.join(declaration(image, marker) for marker in (
        '    static var allowedUTTypes:', '    static func isSupportedImage(', '    func importImages(',
        '    private func finishImport(', '    private static func normalizedPath(',
        '    func persistWallpaperMetadata(',
))
    # Hold the original worker before enumeration, not a replacement
    # importer/metadata result, to exercise its actual reset generation.
    worker = 'DispatchQueue.global(qos: .userInitiated).async { [weak self] in'
    if image_methods.count(worker) != 1: raise AssertionError("Image worker injection must be unique")
    image_methods = image_methods.replace(worker, worker + '\n            ImageImportProbe.shared.waitIfHeld()')
    sync = 'try handle.synchronize()'
    if image_methods.count(sync) != 1: raise AssertionError("Image sync fault leaf must be unique")
    image_methods = image_methods.replace(sync, sync + '\n        if ImageImportProbe.shared.consumeSynchronizationFailure() { throw CocoaError(.fileWriteUnknown) }')
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
    return paths, fixture, inputs


class WallpaperLibraryImportTests(unittest.TestCase):
    def test_workspace_alias_pending_and_deleted_captured_source(self):
        paths = ['MyWallpaperX/' + p for p in (
            'Models/WallpaperReference.swift', 'Models/WallpaperContent.swift', 'Models/WallpaperLibraryPage.swift',
            'Core/LibraryCollections/UserCollectionsStore.swift', 'Core/LibraryCollections/UserCollectionsController.swift',
            'Core/LibraryCollections/LibraryCollectionsMigration.swift', 'Core/LibraryCollections/WallpaperLibraryViewPreferencesMigration.swift',
            'Core/LibraryCollections/WallpaperLibraryQuery.swift', 'Core/PlaybackControl/WallpaperRuntimeSwitch.swift',
            'Core/PlaybackControl/PlaybackSwitchTransaction.swift', 'Core/PlaybackControl/WallpaperPlaybackSequence.swift',
            'Shell/WallpaperLibraryPresentation.swift', 'App/WallpaperLibraryWorkspace.swift')]
        leaf_path = ROOT / 'script/tests/fixtures/WallpaperLibraryWorkspaceHarness.swift'
        fixture_path = ROOT / 'script/tests/fixtures/WallpaperLibraryWorkspaceAliasHarness.swift'
        startup_path = ROOT / 'MyWallpaperX/Core/LibraryCollections/LibraryCollectionsStartupAdmission.swift'
        publication_path = ROOT / 'MyWallpaperX/Core/LibraryCollections/LibraryCollectionsMigrationPublication.swift'
        inputs = [ROOT / p for p in paths] + [leaf_path, fixture_path, startup_path, publication_path]
        hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
        prelude = leaf_path.read_text().split('@main struct WallpaperLibraryWorkspaceHarness')[0]
        prelude = prelude.replace('// STARTUP_OUTCOME', declaration(startup_path.read_text(), 'nonisolated enum LibraryCollectionsStartupOutcome:'))
        prelude = prelude.replace('// PUBLICATION_VALUE', declaration(publication_path.read_text(), 'nonisolated struct LibraryCollectionsMigrationPublicationResult:'))
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
        paths, fixture, inputs = actual_import_fixture()
        hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
        with tempfile.TemporaryDirectory(prefix='mwx-library-import-', dir='/private/tmp') as directory:
            work = Path(directory)
            source = work / 'Checks.swift'; source.write_text(fixture)
            binary = work / 'checks'
            build = subprocess.run(['xcrun', 'swiftc', *SWIFT_ISOLATION_FLAGS, '-parse-as-library',
                *[str(ROOT / p) for p in paths], str(source), '-module-cache-path', str(work / 'modules'),
                '-o', str(binary)], capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            home = work / 'home'; home.mkdir()
            run = subprocess.run([str(binary), str(work)], capture_output=True, text=True, timeout=45,
                env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)))
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertGreaterEqual(len(checks), 15)
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True, run.stdout + run.stderr)
        self.assertEqual(hashes, {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs})


if __name__ == '__main__':
    unittest.main()
