"""Real Video arrow navigation against the former sort-then-filter contract.

The model, source context, sort/filter and navigation bodies are production
inputs. Only manager state is a recording boundary. Comparison counters observe
the actual sort closures; they do not replace the ordering expressions.
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
from script.tests.test_steam_library_interactions import method


ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / 'MyWallpaperX'
SELECTION = APP / 'Modules/VideoLibrary/Core/WallpaperManager+Selection.swift'
CONTEXT = APP / 'Shell/WallpaperSelectionContext.swift'
SUPPORT = APP / 'Modules/VideoLibrary/Core/WallpaperLibrarySupport.swift'
SETTINGS = APP / 'Models/WallpaperSettings.swift'
MODEL = APP / 'Models/VideoWallpaper.swift'
CONTROLS = APP / 'Models/WallpaperControls.swift'
FIXTURE = ROOT / 'script/tests/fixtures/VideoSelectionNavigationHarness.swift'
CHECKS = {
    'matrixArrowResultMatchesLegacySortThenFilter',
    'matrixSelectionWritesMatchHandledNavigation',
    'matrixNavigationLeavesInputsUnchanged',
    'settingsCategoryUsesRealLibraryFallback',
    'selectedTagOverridesCategoryAndSortKey',
    'equalNameKeysReverseTheirInputOrderWhenDescending',
    'unknownAndMaximumSizesKeepTheFormerTieOrder',
    'dateSortUsesLastUsedAndKeepsItsFormerTieOrder',
    'defaultSortIgnoresDescendingAndKeepsSourceOrder',
    'displayTitleFallbackSortDoesNotMakeThePathSearchable',
    'normalizedQueryMatchesTitlesAndTagsInVisibleOrder',
    'duplicateIDsStillLocateTheFirstVisibleOccurrence',
    'missingCurrentSelectionStillStartsFromIndexZero',
    'directionalBoundsAndColumnFallbackStayUnchanged',
    'emptyContextAndNoMatchDoNotWriteSelection',
    'multiSelectSearchFieldAndUnsupportedGuardsDoNotSortOrWrite',
    'explicitIgnoreSearchFieldStillNavigates',
    'largeNarrowSearchKeepsLegacySelection',
    'narrowSearchSortsOnlyMatchingInputs',
    'noMatchSearchDoesNoSortComparisons',
    'emptyQueryRetainsFullSortingInput',
    'defaultModeAlwaysAvoidsSortComparisons',
}


class VideoSelectionNavigationTests(unittest.TestCase):
    def test_cross_runtime_checks_only_visited_targets_and_cards_do_no_io(self):
        access = (APP / 'Modules/SteamWorkshop/Core/SteamWorkshopService+DownloadAccessors.swift').read_text()
        validation = (APP / 'Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebValidation.swift').read_text()
        admission = method(access, '    func canLaunchDownloadRecord(')
        opening = admission.index('{')
        admission = admission[:opening + 1] + '\n        targetChecks.append(record.id)' + admission[opening + 1:]
        harness = r'''
import Foundation
enum ManualNavigationDirection { case next, previous }
enum Runtime { case video, web, scene, other }
enum ContentType { case video, web, scene, unknown }
enum Status { case ready, queued, downloading, failed }
enum Dependency { case none, available(String), missing(String) }
struct VideoWallpaper { let id: String }
@MainActor struct SteamWorkshopDownloadRecord {
    var id: String
    var contentType = ContentType.web
    var status = Status.ready
    var dependencyStatus = Dependency.none
    var dependencyItemID: String?
    var entryHTMLURL: URL?
    var exportedVideoURL: URL?
    var sourceVideoURL: URL?
    var folderURL: URL
    var videoURL: URL? { preconditionFailure("playing projection must not repeat the exists getter") }
    var isPlayableOrLaunchable: Bool {
        precondition(!SteamWorkshopService.shared.forbidFileReads, "card used a filesystem getter")
        let target = contentType == .scene ? folderURL.appendingPathComponent("scene.pkg") : entryHTMLURL
        return target.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }
    var webEntryURL: URL? {
        precondition(!SteamWorkshopService.shared.forbidFileReads, "card used a filesystem getter")
        guard let entryHTMLURL, FileManager.default.fileExists(atPath: entryHTMLURL.path) else { return nil }
        return entryHTMLURL
    }
}
@MainActor final class WallpaperManager {
    static let shared = WallpaperManager()
    var wallpapers: [VideoWallpaper] = []
    var currentWallpaper: VideoWallpaper?
    var activeWallpaperRuntime = Runtime.other
    var requests: [String] = []
    func requestSetAsWallpaper(_ wallpaper: VideoWallpaper) { requests.append(wallpaper.id) }
}
@MainActor final class WallpaperEngine {
    static let shared = WallpaperEngine()
    var currentWebRecordID: String?
    var currentPlaybackContentKind = Runtime.other
    var currentContentPath: String?
}
@MainActor final class SceneDaemonClient {
    struct State { let recordID: String }
    static let shared = SceneDaemonClient()
    var activeRecordID: String?
    var launchState: State?
}
@MainActor final class SteamWorkshopService {
    static let shared = SteamWorkshopService()
    var downloads: [SteamWorkshopDownloadRecord] = []
    var requests: [String] = []
    var targetChecks: [String] = []
    var forbidFileReads = false
    func setAsWallpaper(_ record: SteamWorkshopDownloadRecord) { requests.append(record.id) }
    // ADMISSION
    // CARD_PROJECTION
    // SELECTED_ENTRY
    func isActiveWebRecord(_ record: SteamWorkshopDownloadRecord) -> Bool {
        WallpaperEngine.shared.currentWebRecordID == record.id
    }
    // PLAYING_PROJECTION
}
@main enum Harness {
    @MainActor static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let manager = WallpaperManager.shared, service = SteamWorkshopService.shared
        func record(_ id: String, present: Bool = true) throws -> SteamWorkshopDownloadRecord {
            let folder = root.appendingPathComponent(id, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let entry = folder.appendingPathComponent("index.html")
            if present { try Data("<html></html>".utf8).write(to: entry) }
            return SteamWorkshopDownloadRecord(id: id, entryHTMLURL: entry, folderURL: folder)
        }
        let a = try record("A"), missing = try record("deleted", present: false)
        let c = try record("C"), untouched = try record("untouched")
        var scene = try record("legacy-scene"); scene.contentType = .scene; scene.entryHTMLURL = nil
        var dependency = c; dependency.dependencyItemID = "host"; dependency.dependencyStatus = .missing("host")
        var available = dependency; available.dependencyStatus = .available("host")
        var noEntry = c; noEntry.entryHTMLURL = nil
        var queued = c; queued.status = .queued
        var video = noEntry; video.contentType = .video; video.sourceVideoURL = root.appendingPathComponent("movie.mov")
        var exported = noEntry; exported.contentType = .unknown; exported.exportedVideoURL = video.sourceVideoURL
        service.forbidFileReads = true
        for _ in 0..<100 {
            precondition(service.cachedCanLaunchDownloadRecord(a))
            precondition(service.cachedCanLaunchDownloadRecord(missing), "card must not stat an externally deleted entry")
            precondition(service.cachedCanLaunchDownloadRecord(scene), "legacy Scene does not require project JSON in a card")
            precondition(!service.cachedCanLaunchDownloadRecord(dependency))
            precondition(service.cachedCanLaunchDownloadRecord(available))
            precondition(!service.cachedCanLaunchDownloadRecord(noEntry))
            precondition(!service.cachedCanLaunchDownloadRecord(queued))
            precondition(service.cachedCanLaunchDownloadRecord(video) && service.cachedCanLaunchDownloadRecord(exported))
        }
        precondition(service.targetChecks.isEmpty)
        let movie = root.appendingPathComponent("actual.mov")
        try Data("video".utf8).write(to: movie)
        let alias = root.appendingPathComponent("movie-link.mov")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: movie)
        video.sourceVideoURL = alias
        // Engine.prepareVideoSwitch stores normalizedPath(wallpaper.path),
        // including Foundation's canonical spelling of temporary directories.
        let activePath = movie.resolvingSymlinksInPath().standardizedFileURL.path
        WallpaperEngine.shared.currentPlaybackContentKind = .video
        WallpaperEngine.shared.currentContentPath = activePath
        precondition(service.isRecordCurrentlyPlaying(video), "raw source symlink must match the active canonical path")
        video.sourceVideoURL = nil; video.exportedVideoURL = alias
        precondition(service.isRecordCurrentlyPlaying(video), "raw exported path must match without another exists getter")
        WallpaperEngine.shared.currentContentPath = root.appendingPathComponent("different.mov").path
        precondition(!service.isRecordCurrentlyPlaying(video))
        WallpaperEngine.shared.currentPlaybackContentKind = .web
        WallpaperEngine.shared.currentContentPath = activePath
        precondition(!service.isRecordCurrentlyPlaying(video), "another runtime's matching path is not Video playback")
        service.forbidFileReads = false
        manager.activeWallpaperRuntime = .web; WallpaperEngine.shared.currentWebRecordID = "A"
        service.downloads = [a, missing, c, untouched]
        CrossRuntimeWallpaperNavigator.navigate(.next)
        precondition(service.requests == ["C"] && service.targetChecks == ["deleted", "C"],
            "next must skip deleted targets without inspecting unvisited records")
        service.requests = []; service.targetChecks = []
        WallpaperEngine.shared.currentWebRecordID = "C"
        CrossRuntimeWallpaperNavigator.navigate(.previous)
        precondition(service.requests == ["A"] && service.targetChecks == ["deleted", "A"])
        service.requests = []; service.targetChecks = []
        WallpaperEngine.shared.currentWebRecordID = "A"; service.downloads = [a, missing, scene, dependency]
        CrossRuntimeWallpaperNavigator.navigate(.next)
        precondition(service.requests.isEmpty && service.targetChecks == ["deleted", "legacy-scene"],
            "all invalid candidates must stop before restarting current or prompting for a dependency")
        service.targetChecks = []; manager.activeWallpaperRuntime = .other
        service.downloads = [missing, scene]
        CrossRuntimeWallpaperNavigator.navigate(.previous)
        precondition(service.targetChecks == ["legacy-scene", "deleted"] && service.requests.isEmpty,
            "an unknown current target must inspect at most one complete rotation")
        service.targetChecks = []; manager.activeWallpaperRuntime = .scene
        service.downloads = [scene, c]; SceneDaemonClient.shared.launchState = .init(recordID: scene.id)
        CrossRuntimeWallpaperNavigator.navigate(.next)
        precondition(service.requests == ["C"] && service.targetChecks == ["C"])
        service.requests = []; service.targetChecks = []
        manager.wallpapers = [.init(id: "V0"), .init(id: "V1")]
        manager.currentWallpaper = manager.wallpapers[0]; manager.activeWallpaperRuntime = .video
        CrossRuntimeWallpaperNavigator.navigate(.next)
        precondition(manager.requests == ["V1"] && service.targetChecks.isEmpty,
            "video navigation must not inspect unrelated workshop files")
        manager.currentWallpaper = manager.wallpapers[1]
        CrossRuntimeWallpaperNavigator.navigate(.next)
        precondition(service.requests == ["C"] && service.targetChecks == ["legacy-scene", "C"])
        print("cross-runtime-target-admission-pass")
    }
}
'''
        for marker, fragment in [
            ('// ADMISSION', admission),
            ('// CARD_PROJECTION', method(access, '    func cachedCanLaunchDownloadRecord(')),
            ('// SELECTED_ENTRY', method(validation, '    func webLaunchEntryIsValid(')),
            ('// PLAYING_PROJECTION', method(access, '    func isRecordCurrentlyPlaying(')),
        ]:
            harness = harness.replace(marker, fragment)
        with tempfile.TemporaryDirectory(prefix='mwx-cross-runtime-targets-', dir='/private/tmp') as directory:
            work = Path(directory)
            source = work / 'Harness.swift'; source.write_text(harness)
            binary = work / 'navigation'
            compiled = subprocess.run(['xcrun', 'swiftc', '-parse-as-library',
                str(APP / 'App/CrossRuntimeWallpaperNavigator.swift'), str(source),
                '-module-cache-path', str(work / 'modules'), '-o', str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            run = subprocess.run([str(binary), str(work)], capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertIn('cross-runtime-target-admission-pass', run.stdout)

    def test_real_navigation_order_guards_and_filtered_sort_work(self):
        paths = [SELECTION, CONTEXT, SUPPORT, SETTINGS, MODEL, CONTROLS, FIXTURE, Path(__file__)]

        def fingerprints():
            return {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}

        identities = fingerprints()
        selection, context = SELECTION.read_text(), CONTEXT.read_text()
        support, settings = SUPPORT.read_text(), SETTINGS.read_text()
        sort = declaration(selection, '    func sortedWallpapers(')
        opening = sort.index('{')
        sort = sort[:opening + 1] + '\n        sortInputs.append(wallpapers.map(\\.id))' + sort[opening + 1:]
        for expression in [
            '$0.displayTitle.localizedCompare($1.displayTitle) == .orderedAscending',
            '($0.fileSize ?? Int64.max) < ($1.fileSize ?? Int64.max)',
            '$0.lastUsed < $1.lastUsed',
        ]:
            self.assertEqual(sort.count(expression), 1)
            sort = sort.replace(expression, 'sortComparisons += 1\n                return ' + expression)
        fragments = {
            '// PRODUCTION_VALUE_TYPES': '\n'.join([
                declaration(settings, 'public enum WallpaperSortMode:'),
                declaration(settings, 'public struct SortState:'),
                declaration(support, 'enum ImportContext:'),
                declaration(support, 'enum WallpaperRemovalScope {'),
                declaration(context, 'enum WallpaperSelectionContext:'),
            ]),
            '// PRODUCTION_MANAGER_METHODS': '\n'.join([
                declaration(selection, '    var favoriteWallpapers:'),
                declaration(selection, '    var normalizedSearchQuery:'),
                declaration(selection, '    func filterWallpapers('), sort,
                declaration(selection, '    func moveSingleSelectionByArrowKey('),
                declaration(selection, '    func setSingleSelection('),
                declaration(context, '    var currentSelectionContext:'),
            ]),
        }
        template = FIXTURE.read_text()
        for marker, fragment in fragments.items():
            self.assertEqual(template.count(marker), 1)
            template = template.replace(marker, fragment)
        with tempfile.TemporaryDirectory(prefix='mwx-video-navigation-', dir='/private/tmp') as directory:
            work = Path(directory)
            proof = os.environ.get('MWX_VIDEO_NAVIGATION_PROOF_DIR')
            target = Path(proof) if proof else None
            if target:
                target.mkdir(parents=True, exist_ok=True)

            def save(name, value):
                if target:
                    (target / name).write_text(value)

            save('inputs.json', json.dumps({'inputs': identities,
                'transforms': ['sort entry input IDs', 'three real comparator counters with explicit return'],
                'flags': SWIFT_ISOLATION_FLAGS, 'scope': __doc__}, indent=2) + '\n')
            source = work / 'Harness.swift'
            source.write_text(template)
            binary = work / 'video-navigation'
            build = subprocess.run(['xcrun', 'swiftc', *SWIFT_ISOLATION_FLAGS, '-warnings-as-errors',
                '-parse-as-library', str(MODEL), str(CONTROLS), str(source),
                '-module-cache-path', str(work / 'modules'), '-o', str(binary)],
                capture_output=True, text=True, timeout=120)
            save('compile.log', build.stdout + build.stderr)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            self.assertEqual(identities, fingerprints())
            home = work / 'home'
            home.mkdir()
            run = subprocess.run([str(binary)], env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)),
                capture_output=True, text=True, timeout=30)
            save('runtime.log', run.stderr)
            save('stdout.log', run.stdout)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            save('checks.json', json.dumps(checks, indent=2) + '\n')
            self.assertEqual(set(checks), CHECKS)
            for name, passed in checks.items():
                with self.subTest(name=name):
                    self.assertTrue(passed, run.stderr)
            self.assertEqual(identities, fingerprints())


if __name__ == '__main__':
    unittest.main()
