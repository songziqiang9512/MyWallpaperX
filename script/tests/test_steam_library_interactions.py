"""Run production local-content admission, queue actions and author-selection routing."""
import pathlib
import subprocess
import tempfile
import unittest
from script.tests.test_steam_library_transaction import SOURCES, CORE, ROOT

def method(source, signature):
    start = source.index(signature)
    opening = source.index('{', start)
    depth = 0
    for index in range(opening, len(source)):
        depth += (source[index] == '{') - (source[index] == '}')
        if depth == 0:
            return source[start:index + 1].replace('private func ', 'func ')
    raise AssertionError(signature)

class SteamLibraryInteractionTests(unittest.TestCase):
    def test_local_content_queue_actions_and_author_route(self):
        ui = (ROOT / 'MyWallpaperX/App/DownloadTasksController.swift').read_text()
        navigation = (CORE / 'SteamWorkshopService+BrowseNavigation.swift').read_text()
        shell = (ROOT / 'MyWallpaperX/App/WallpaperLibraryWindowComposition.swift').read_text()
        pages = (ROOT / 'MyWallpaperX/Models/WallpaperLibraryPage.swift').read_text()
        records = (CORE / 'SteamWorkshopService+LibraryRecords.swift').read_text()
        downloads = (CORE / 'SteamWorkshopService+Downloads.swift').read_text()
        harness = r'''
import AppKit
import Combine
@MainActor final class Auth { var steamId: String? = "A"; var isOnline = true }
enum Source { case featured, mySubscriptions; var isPersonal: Bool { self == .mySubscriptions } }
enum Choice { case all, none }
enum SteamWorkshopBrowseSection { case personal, discovery }
extension Notification.Name { static let appKitSelectItemRequested = Notification.Name("select"); static let appKitRequestScrollToTopForCurrentSelection = Notification.Name("top") }
@MainActor final class SteamWorkshopService {
    static var current: SteamWorkshopService!
    static var shared: SteamWorkshopService { current! }
    let steamAuth = Auth()
    let downloadJobStore: SteamDownloadJobStore
    let downloadProgressStore = SteamWorkshopDownloadProgressStore()
    var downloadError: String?
    var retried: [String] = []
    var source = Source.featured
    var browserEntryChecks = 0, browserSectionEntries = 0
    var browserQuery = "author-query", currentBrowserScrollOffsetY: CGFloat = 317.25
    var pendingDownloadsScrollRestoreOffsetY: CGFloat?
    var isBrowsingAuthorWorkshop = true
    var canReturnFromBrowse: Bool { isBrowsingAuthorWorkshop || source.isPersonal }
    var suppressAutomaticBrowseNavigation = false
    var browserContentMode = Choice.all
    var facetFilters = Choice.none
    init(_ root: URL) { downloadJobStore = SteamDownloadJobStore(persistenceURL: root.appendingPathComponent("jobs.json")) }
    func returnToDiscoveryBrowse(selectOrigin: Bool = true) { isBrowsingAuthorWorkshop = false }
    func enterBrowseSection(_ section: SteamWorkshopBrowseSection) { browserSectionEntries += 1; source = section == .personal ? .mySubscriptions : .featured }
    func showMySubscriptions() { if steamAuth.isOnline { enterBrowseSection(.personal); requestSteamWorkshopBrowserSelection() } }
    func setBrowserQuery(_ query: String) {}
    func prepareForBrowserEntry() { browserEntryChecks += 1 }
    func removeTransientRecord(id: String) {}
    func scheduleTerminalDownloadCleanup() {}
    func downloadWorkshopItem(id: String, pageTitle: String) { retried.append(id) }
    func downloadRecord(for id: String) -> URL? { nil }
    func revealItem(_ url: URL) {}
    func cancelDownloadImmediately(itemID: String, showFeedback: Bool) {}
    func pauseDownload(itemID: String) {}
    func resumeDownload(itemID: String) {}
    func promoteQueuedDownload(itemID: String) {}
''' + method(downloads, '    func discardFailedDownload(') + '\n' + method(records, '    nonisolated static func hasLocalWorkshopContent(') + '\n' + method(navigation, '    func requestSteamWorkshopBrowserSelection(') + r'''
}
// Unselected source/file/history effects are recording leaves. The entire
// generic action dispatcher and real Steam discard/JobStore execute unchanged.
@MainActor final class PixabayActions {
    struct Entry { let id: Int; let localURL: URL; let isAvailable: Bool }
    struct Content { var entries: [Entry] = [] }
    var downloadedContent = Content()
    func retryDownload(id: Int) {}
    func cancelDownload(id: Int, attemptID: UUID) {}
}
@MainActor final class ImageActions {
    var snapshot = OnlineImageLocalSnapshot()
    func retryDownload(_ reference: WallpaperReference, title: String) {}
    func cancel(_ id: OnlineImageAssetID, attemptID: UUID) {}
    func record(for reference: WallpaperReference) -> OnlineImageLocalRecord? { nil }
    func localURL(for record: OnlineImageLocalRecord) -> URL? { nil }
}
@MainActor final class HistoryActions {
    func remove(_ id: DownloadTaskIdentity) throws {}
    func clear() throws {}
}
@MainActor final class Actions: NSObject {
    let steam: SteamWorkshopService
    let pixabay = PixabayActions(), images = ImageActions()
    let history: HistoryActions? = HistoryActions()
    var historyError: String?
    let changed = PassthroughSubject<Void, Never>()
    init(_ service: SteamWorkshopService) { steam = service }
''' + method(ui, '    private func clearHistory(') + '\n' + method(ui, '    private func perform(') + r'''
}
@MainActor final class Presentation {
    var page = WallpaperLibraryPage.downloads
    private(set) var switchTargets: [WallpaperLibraryPage] = []
    func switchPage(_ page: WallpaperLibraryPage) -> Bool {
        switchTargets.append(page)
        guard self.page != page else { return false }
        self.page = page
        return true
    }
}
@MainActor final class Workspace { let presentation = Presentation() }
@MainActor final class Grid {
    private(set) var scrollToTopCalls = 0
    func scrollToTop() { scrollToTopCalls += 1 }
}
''' + method(pages, 'nonisolated enum WallpaperLibraryPage:') + r'''
@MainActor final class WallpaperLibraryWindowComposition {
    let workspace = Workspace()
    let grid = Grid()
    var steam: SteamWorkshopService { .shared }
    var selected: WallpaperLibraryPage { workspace.presentation.page }
    var onNavigationContextChanged: (() -> Void)?
''' + method(shell, '    private struct DirectoryReturnContext:') + '\n' + method(shell, '    private var directoryReturnContext:') + r'''
    func establishDirectoryReturnContext() {
        directoryReturnContext = DirectoryReturnContext(playlistID: UUID(), resetEpoch: UUID())
    }
    var hasDirectoryReturnContext: Bool { directoryReturnContext != nil }
''' + method(shell, '    func navigate(') + '\n' + method(shell, '    private func navigatePage(') + '\n' + method(shell, '    private func handleNavigation(') + r'''
}
@main struct Harness {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let service = SteamWorkshopService(root)
        SteamWorkshopService.current = service
        let actions = Actions(service)
        let store = service.downloadJobStore
        func job(_ id: String, _ state: SteamDownloadJobState, account: String = "A") -> SteamDownloadJob {
            let job = store.enqueue(workshopItemId: id, title: id, accountSteamId: account).job
            if state != .queued { precondition(store.apply(.started, toID: job.id) != nil) }
            if state == .failed { precondition(store.apply(.failed("network"), toID: job.id) != nil) }
            if state == .cancelled { precondition(store.cancel(id: job.id) != nil) }
            return store.job(id: job.id)!
        }
        let running = job("1", .running)
        let queued = job("2", .queued)
        let failed = job("3", .failed)
        _ = job("4", .cancelled)
        let other = job("5", .failed, account: "B")
        func row(_ job: SteamDownloadJob, phase: DownloadTaskPhase) -> DownloadTaskRow {
            .init(id: .init(reference: .init(provider: .steamWorkshop, sourceID: job.workshopItemId),
                attemptID: "\(job.id)-\(job.attempt)"), title: job.title, phase: phase, actions: [.retry, .abandon])
        }
        let failedRow = row(failed, phase: .failed)
        actions.perform(failedRow, action: .abandon)
        precondition(store.job(id: running.id) == running && store.job(id: queued.id) == queued)
        precondition(store.job(id: failed.id)?.state == .cancelled)
        precondition(store.job(id: other.id) == other)
        precondition(store.history.contains { $0.accountSteamId == "A" })
        precondition(store.history.contains { $0.accountSteamId == "B" })
        actions.clearHistory()
        precondition(store.history.isEmpty && store.job(id: running.id) == running && store.job(id: queued.id) == queued
            && store.job(id: other.id) == other, "clearing local history changes neither another account's intent nor active queue")
        actions.perform(failedRow, action: .retry)
        precondition(service.retried == ["3"])
        service.steamAuth.steamId = "B"
        actions.perform(failedRow, action: .retry)
        actions.perform(failedRow, action: .abandon)
        actions.clearHistory()
        precondition(service.retried == ["3"] && store.job(id: other.id) == other)

        let shell = WallpaperLibraryWindowComposition()
        shell.establishDirectoryReturnContext()
        var contextChanges = 0
        shell.onNavigationContextChanged = { contextChanges += 1 }
        let observer = NotificationCenter.default.addObserver(forName: .appKitSelectItemRequested,
            object: nil, queue: nil) { note in
                MainActor.assumeIsolated { shell.handleNavigation(note) }
            }
        service.requestSteamWorkshopBrowserSelection()
        precondition(shell.selected == .workshop && service.isBrowsingAuthorWorkshop)
        precondition(!shell.hasDirectoryReturnContext && contextChanges == 1,
            "actual navigate must clear the directory return context before preserving the author browser")
        service.source = .mySubscriptions
        service.requestSteamWorkshopBrowserSelection()
        precondition(shell.selected == .workshop && service.isBrowsingAuthorWorkshop)
        service.pendingDownloadsScrollRestoreOffsetY = 42
        let originalQuery = service.browserQuery, originalScroll = service.currentBrowserScrollOffsetY
        shell.navigate(to: .videos); shell.navigate(to: .workshop)
        precondition(service.isBrowsingAuthorWorkshop && service.source == .mySubscriptions && service.browserEntryChecks == 0
            && service.browserSectionEntries == 0 && service.browserQuery == originalQuery
            && service.currentBrowserScrollOffsetY == originalScroll && service.pendingDownloadsScrollRestoreOffsetY == 42,
            "returning to Workshop must preserve the source-owned author context, query and scroll without entry work")
        shell.navigate(to: .workshop)
        precondition(service.browserEntryChecks == 0 && service.browserSectionEntries == 0,
            "same-row reselection must preserve the existing source context")
        precondition(shell.grid.scrollToTopCalls == 0,
            "remote browser navigation must not scroll the unrelated local grid")
        service.returnToDiscoveryBrowse(selectOrigin: false)
        service.enterBrowseSection(.discovery)
        shell.navigate(to: .workshop)
        precondition(!service.isBrowsingAuthorWorkshop && service.source == .featured && service.browserSectionEntries == 1,
            "explicit source-owned Back can still choose discovery without Shell recreating an author context")
        service.showMySubscriptions()
        precondition(shell.selected == .workshop && service.source.isPersonal,
            "personal entry retains the existing Workshop browser host")
        shell.navigate(to: .downloads); shell.navigate(to: .workshop)
        precondition(shell.selected == .workshop && service.source.isPersonal && service.browserSectionEntries == 2,
            "personal context survives the same shared Workshop sidebar roundtrip")
        service.steamAuth.isOnline = false
        let entriesBeforeSignedOut = service.browserSectionEntries, switchesBeforeSignedOut = shell.workspace.presentation.switchTargets
        service.showMySubscriptions()
        precondition(shell.selected == .workshop && service.source.isPersonal
            && service.browserSectionEntries == entriesBeforeSignedOut && shell.workspace.presentation.switchTargets == switchesBeforeSignedOut,
            "signed-out personal entry does not navigate, start authentication or mutate its source leaf")
        NotificationCenter.default.removeObserver(observer)

        shell.navigate(to: .downloads)
        let switchesBeforeReselect = shell.workspace.presentation.switchTargets.count
        shell.establishDirectoryReturnContext()
        shell.navigate(to: .downloads)
        precondition(shell.selected == .downloads && shell.grid.scrollToTopCalls == 1
            && shell.workspace.presentation.switchTargets.count == switchesBeforeReselect
            && !shell.hasDirectoryReturnContext,
            "the real local-page branch scrolls the existing grid without switching page or retaining directory context")
        shell.navigate(to: .playlists)
        shell.navigate(to: .playlists)
        precondition(shell.selected == .playlists && shell.grid.scrollToTopCalls == 1
            && Array(shell.workspace.presentation.switchTargets.suffix(2)) == [.playlists, .playlists],
            "the playlists directory keeps its original presentation route rather than scrolling the wallpaper grid")

        let content = root.appendingPathComponent("Scene/123456")
        try FileManager.default.createDirectory(at: content, withIntermediateDirectories: true)
        func admitted(scene: String? = nil, video: URL? = nil, web: URL? = nil, dependency: Bool = false) -> Bool {
            SteamWorkshopService.hasLocalWorkshopContent(directory: content, sceneEntry: scene,
                videoURL: video, htmlURL: web, hasDependency: dependency)
        }
        precondition(!admitted())
        try Data("{}".utf8).write(to: content.appendingPathComponent(".mywallpaperx-steam-metadata.json"))
        try Data("{}".utf8).write(to: content.appendingPathComponent("project.json"))
        precondition(!admitted(scene: "scene.json"), "metadata and project without content must not make a card")
        precondition(admitted(dependency: true), "a real dependency preset is local content")
        let entry = content.appendingPathComponent("scene.json")
        try Data("{}".utf8).write(to: entry)
        precondition(admitted(scene: "scene.json"))
        precondition(admitted(video: entry) && admitted(web: entry))
        try FileManager.default.removeItem(at: entry)
        precondition(!admitted(scene: "scene.json") && !admitted(video: entry) && !admitted(web: entry))
        let outside = content.deletingLastPathComponent().appendingPathComponent("outside.json")
        try Data("{}".utf8).write(to: outside)
        precondition(!admitted(scene: "../outside.json"))
        try FileManager.default.removeItem(at: content)
        precondition(!admitted(dependency: true))
        print("Local disk, queue actions and author routing PASS")
    }
}
'''
        with tempfile.TemporaryDirectory(prefix='mwx-library-actions-', dir='/private/tmp') as folder:
            root = pathlib.Path(folder)
            source = root / 'Harness.swift'
            source.write_text(harness)
            binary = root / 'test'
            result = subprocess.run(['xcrun', 'swiftc', '-parse-as-library', *map(str, SOURCES),
                str(CORE / 'SteamWorkshopDownloadTaskProjection.swift'),
                *[str(ROOT / 'MyWallpaperX' / name) for name in (
                    'Models/WallpaperReference.swift', 'Models/WallpaperContent.swift', 'Models/DownloadTask.swift',
                    'Core/OnlineImages/OnlineImageModels.swift', 'Modules/Downloads/Core/DownloadTaskProjection.swift')],
                str(source), '-o', str(binary)], capture_output=True, text=True, timeout=120)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            result = subprocess.run([str(binary), folder], capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
