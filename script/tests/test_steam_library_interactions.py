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
        ui = (CORE.parent / 'UI/SteamWorkshopDownloadTasksPopover.swift').read_text()
        navigation = (CORE / 'SteamWorkshopService+BrowseNavigation.swift').read_text()
        shell = (ROOT / 'MyWallpaperX/App/WallpaperLibraryWindowComposition.swift').read_text()
        pages = (ROOT / 'MyWallpaperX/Models/WallpaperLibraryPage.swift').read_text()
        records = (CORE / 'SteamWorkshopService+LibraryRecords.swift').read_text()
        downloads = (CORE / 'SteamWorkshopService+Downloads.swift').read_text()
        harness = r'''
import AppKit
@MainActor final class Auth { var steamId: String? = "A" }
enum Source { case featured, mySubscriptions; var isPersonal: Bool { self == .mySubscriptions } }
enum Choice { case all, none }
enum SteamWorkshopBrowseSection { case personal, discovery }
enum SelectedItem {
    case steamWorkshop, steamSubscribed, steamDownloads, onlineLibrary, onlineDownloads, staticImageLibrary
    struct Context { var scrollPersistenceKey = "steam" }
    var selectionContext: Context { Context() }
    var isInSteamWorkshopContext: Bool { self == .steamWorkshop || self == .steamSubscribed }
}
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
    var browserEntryChecks = 0
    var pendingDownloadsScrollRestoreOffsetY: CGFloat?
    var isBrowsingAuthorWorkshop = true
    var suppressAutomaticBrowseNavigation = false
    var browserContentMode = Choice.all
    var facetFilters = Choice.none
    init(_ root: URL) { downloadJobStore = SteamDownloadJobStore(persistenceURL: root.appendingPathComponent("jobs.json")) }
    func returnToDiscoveryBrowse(selectOrigin: Bool = true) { isBrowsingAuthorWorkshop = false }
    func enterBrowseSection(_ section: SteamWorkshopBrowseSection) { source = section == .personal ? .mySubscriptions : .featured }
    func setBrowserQuery(_ query: String) {}
    func prepareForBrowserEntry() { browserEntryChecks += 1 }
    func removeTransientRecord(id: String) {}
    func scheduleTerminalDownloadCleanup() {}
    func downloadWorkshopItem(id: String, pageTitle: String) { retried.append(id) }
''' + method(downloads, '    func discardFailedDownload(') + '\n' + method(records, '    nonisolated static func hasLocalWorkshopContent(') + '\n' + method(navigation, '    func requestSteamWorkshopBrowserSelection(') + r'''
}
@MainActor final class Actions: NSObject {
    let service: SteamWorkshopService
    var latestAccountSteamID: String? = "A"
    let retryButton = NSButton()
    var retryHandler: (() -> Void)?
    init(_ service: SteamWorkshopService) { self.service = service }
''' + method(ui, '    @objc private func handleClearAll(') + '\n' + method(ui, '    private func configureRetry(') + r'''
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
        actions.handleClearAll()
        precondition(store.job(id: running.id) == running && store.job(id: queued.id) == queued)
        precondition(store.job(id: failed.id)?.state == .cancelled)
        precondition(store.job(id: other.id) == other)
        precondition(!store.history.contains { $0.accountSteamId == "A" })
        precondition(store.history.contains { $0.accountSteamId == "B" })
        actions.configureRetry(itemID: "3", title: "three", account: "A", failed: true)
        precondition(!actions.retryButton.isHidden)
        actions.retryHandler?()
        precondition(service.retried == ["3"])
        service.steamAuth.steamId = "B"
        actions.retryHandler?()
        actions.handleClearAll()
        precondition(service.retried == ["3"] && store.job(id: other.id) == other)
        actions.configureRetry(itemID: "3", title: "three", account: "B", failed: false)
        precondition(actions.retryButton.isHidden && actions.retryHandler == nil)

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
        shell.navigate(to: .workshop)
        precondition(!service.isBrowsingAuthorWorkshop && service.source == .featured && service.browserEntryChecks == 1,
            "reselecting the current author host must exit author mode and prepare the visible browser")
        shell.navigate(to: .workshop)
        precondition(service.browserEntryChecks == 1, "ordinary same-row clicks keep their scroll-to-top behavior")
        precondition(shell.grid.scrollToTopCalls == 0,
            "reselecting the remote browser must keep its original early-return path")
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
                str(CORE / 'SteamWorkshopDownloadTaskProjection.swift'), str(source), '-o', str(binary)], capture_output=True, text=True, timeout=120)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            result = subprocess.run([str(binary), folder], capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
