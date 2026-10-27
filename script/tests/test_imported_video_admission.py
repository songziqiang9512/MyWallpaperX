"""Actual download-click admission -> notification -> async import -> original Video ticket."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import uuid

from script.tests.test_imported_video_autoplay_gate import GATE_SOURCES, MANAGER, product_harness
from script.tests.test_steam_library_interactions import method
from script.tests.test_ui_library_algorithms import declaration
from script.tests.test_wallpaper_library_import import video_import_cache_methods

ROOT = Path(__file__).resolve().parents[2]


class ImportedVideoAdmissionTests(unittest.TestCase):
    def test_admission_async_import_stop_failure_and_queued_navigation(self):
        source = product_harness().replace('struct VideoWallpaper {let path:String;var id:String{path}}', '')
        source = source.replace('import Foundation', 'import AppKit\nimport QuartzCore\nimport CryptoKit\nimport Foundation', 1)
        source = source.replace('var autoSwitchEnabled=true,randomInterval=', 'var volume: Double = 100\n        var autoSwitchEnabled=true,randomInterval=')
        normalized = declaration((MANAGER / 'WallpaperManager.swift').read_text(), '    func normalizedPath(')
        source = source.replace('func normalizedPath(_ path:String)->String{path}', normalized.strip(), 1)
        fields = '''
    var wallpaperIndexSaveEpoch: UInt64 = 0
    var libraryBackingPublished: ((WallpaperContentBackingPublication) -> Void)?
    var backingPublications: [WallpaperContentBackingPublication] = []
    var onImportSummary: (() -> Void)?
    var importPreparationGeneration: UInt64 = 0
    let importPreparationStateLock = NSLock()
    var importPreparationWorkItem: DispatchWorkItem?
    let importPreparationQueue = DispatchQueue(label: "mwx.admission.test-import")
    let thumbnailCacheDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).appendingPathComponent("thumbnails")
    let staticFrameCacheDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).appendingPathComponent("static-frames")
    var importSummaryCount = 0, recentRequests = 0, historyRequests = 0, unexpectedMissingFallbacks = 0
    var timerRefreshAudit = 0
    var migrationRecoveryMessage: String?
    var migrationWarnings = 0
    var importedAssetRequests: [URL] = []
    var pendingManualNavigationDirection: ManualNavigationDirection?
    var pendingManualNavigationWorkItem: DispatchWorkItem?
    var lastManualNavigationAt: CFTimeInterval = 0
    let manualNavigationMinInterval: CFTimeInterval = 0.18
    var manualNavigationExecutions = 0
    var manualNavigationDirections: [ManualNavigationDirection] = []
    var manualNavigationPolicies: [WallpaperPlaybackSequence.NavigationPolicy] = []
'''
        marker = '@MainActor final class WallpaperManager: ObservableObject {'
        self.assertEqual(source.count(marker), 1)
        source = source.replace(marker, marker + fields)
        # This richer harness replaces the bounded Stop leaf with the actual
        # product Stop body below, retaining all reentrant endpoint assertions.
        source = source.replace('func stopCurrentPlayback(){_ = beginPlaybackIntent();currentWallpaper=nil;pendingWallpaper=nil;isPlaying=false;stopAutoSwitchTimer()}', '')
        # Observe refresh calls in the test copy, retaining the actual policy body.
        refresh = "func refreshAutoSwitchTimerIfNeeded() {"
        self.assertEqual(source.count(refresh), 1)
        source = source.replace(refresh, refresh + "\n        timerRefreshAudit += 1")
        imports = (MANAGER / 'WallpaperManager+ImportProcessing.swift').read_text()
        presentation = (MANAGER / 'WallpaperManager+ImportPresentation.swift').read_text()
        application = (MANAGER / 'WallpaperManager+WallpaperApplication.swift').read_text()
        removal = (MANAGER / 'WallpaperManager+Removal.swift').read_text()
        navigation = (MANAGER / 'WallpaperManager+PlaybackControl.swift').read_text()
        library = (MANAGER / 'WallpaperLibrarySupport.swift').read_text()
        types = '\n'.join(declaration(library, sig) for sig in ['struct ImportSummary', 'enum ImportContext', 'enum ManualNavigationDirection'])
        methods = '\n'.join(declaration(imports, sig) for sig in [
            '    private struct ImportCounters', '    private enum ImportSourceValidationResult',
            '    private struct PreparedImportEntry', '    private struct ImportPreparationResult',
            '    func processImportedVideos(', '    private func prepareImportEntries(',
            '    private func beginImportPreparationRequest(', '    private func setImportPreparationWorkItem(',
            '    private func isImportPreparationRequestCurrent(', '    private func applyPreparedImportResult(',
            '    private func makeImportSummary(', '    private func makePreparedWallpaper(',
            '    private func appendWallpapersInBatches(', '    private func validateImportSourceURL(',
        ])
        methods += '\n' + declaration(presentation, '    func importFailureBreakdown(')
        methods += '\n' + declaration(application, '    func setAsWallpaper(')
        methods += '\n' + declaration(removal, '    func clearCurrentWallpaperReference(')
        methods += '\n' + declaration(removal, '    func stopCurrentPlayback(')
        methods += '\n' + '\n'.join(declaration(navigation, signature) for signature in (
            '    func navigateWallpaperManually(', '    private func scheduleManualNavigationIfNeeded('))
        persistence = (MANAGER / 'WallpaperManager+Persistence.swift').read_text()
        methods += '\n' + declaration(persistence, '    func saveCodableValue<')
        methods += '\n' + declaration(persistence, '    private func encode<')
        online = (ROOT / 'MyWallpaperX/Modules/OnlineLibrary/Core/OnlineLibraryService.swift').read_text()
        online_methods = '\n'.join(method(online, sig) for sig in [
            'func downloadAndSet(', 'private func postReadyToPlay(', 'func setLocalFileAsWallpaper(',
            'private func existingDownloadedURL(', 'private func publishDownloadedContent(',
        ])
        support = (ROOT / 'script/tests/fixtures/ImportedVideoAdmissionSupport.swift').read_text()
        support = support.replace('// IMPORT_AND_APPLY_METHODS', methods).replace('// ONLINE_METHODS', online_methods)
        support = support.replace('// IMPORT_CACHE_METHODS', video_import_cache_methods(ROOT))
        program = (ROOT / 'script/tests/fixtures/ImportedVideoAdmissionHarness.swift').read_text()
        with tempfile.TemporaryDirectory(prefix='mwx-import-admission-', dir='/private/tmp') as temporary:
            work = Path(temporary)
            harness = work / 'Checks.swift'
            harness.write_text(source + '\n' + types + '\n' + support + '\n' + program)
            originals = [*GATE_SOURCES, ROOT / 'MyWallpaperX/Modules/OnlineLibrary/Core/OnlineLibraryDownloadedContent.swift', ROOT / 'MyWallpaperX/Models/VideoWallpaper.swift', ROOT / 'MyWallpaperX/Models/WallpaperContent.swift', ROOT / 'MyWallpaperX/Models/WallpaperSourceImportResult.swift',
                         ROOT / 'MyWallpaperX/Models/WallpaperIndexStartupChanges.swift',
                         ROOT / 'MyWallpaperX/App/ImportedVideoPlaybackObserver.swift']
            copied = []
            for original in originals:
                target = work / original.name
                target.write_bytes(original.read_bytes())
                copied.append(str(target))
            binary = work / 'checks'
            build = subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
                *copied, str(harness), '-module-cache-path', str(work / 'modules'), '-o', str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            home = work / 'home'
            home.mkdir()
            run = subprocess.run([str(binary), str(home)], capture_output=True, text=True, timeout=30,
                                 env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home),
                                          MWX_IMPORT_ADMISSION_DOMAIN="MWX.ImportAdmission." + uuid.uuid4().hex))
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertGreaterEqual(len(checks), 9)
            self.assertTrue({
                'actualCacheLookupReachesImportedAndPreparedWallpaper',
                'uncachedLatestSourceDoesNotBorrowPreviousAssetPaths',
                'stopRevokesQueuedDirectionFlagsAndWorkItem',
                'manualNavigationFirstRequestDispatchesImmediatelyThroughRandomHistory',
                'manualNavigationDebounceKeepsOnlyTheLastDirection',
                'manualNavigationDelayedDispatchRunsExactlyOnceAndClearsItsReceipt',
                'manualNavigationOldGenerationCannotDispatchItsQueuedDirection',
            }.issubset(checks), checks)
            for name, passed in checks.items():
                with self.subTest(name=name):
                    self.assertIs(passed, True)
            print(json.dumps(checks, sort_keys=True))


if __name__ == '__main__':
    unittest.main()
