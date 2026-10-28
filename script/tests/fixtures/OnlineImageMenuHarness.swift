import AppKit

// The real online menu, shared Commands.contextMenu and complete Recovery run with the
// real model/projection and ActionMenuItem. Transfers and unrelated business
// services are controlled leaves; no network, Finder or user files are used.
@MainActor private enum WallpaperLibrarySheetPresentation {
    static var allowsInput = true
    static func permitsInput(in window: NSWindow?) -> Bool { allowsInput }
}
private typealias MenuPage = WallpaperLibraryPage
private typealias PlaybackSwitchTicket = UUID
private enum WallpaperPlaybackSequence { typealias Snapshot = UUID }
@MainActor private final class MenuCollections { var isResetting = false }
@MainActor private final class MenuWorkspace {
    struct Relationships {
        struct Relation { let reference: WallpaperReference }
        var resetEpoch = UUID()
        var members: [Relation] = [], favorites: [Relation] = [], recent: [Relation] = []
    }
    struct Presentation {
        struct Selection { var sessionID = UUID() }
        var page = MenuPage.wallhaven
        var selectionState = Selection()
        var canEditCollections = true
        var errors: [String] = []
        mutating func report(_ error: Error) { errors.append(error.localizedDescription) }
    }
    var collections: MenuCollections? = MenuCollections()
    var relationships = Relationships()
    var presentation = Presentation()
    var contents: [WallpaperReference: WallpaperContentItem] = [:]
    var playing: WallpaperReference?, plays: [WallpaperReference] = []
    func content(for reference: WallpaperReference) throws -> WallpaperContentItem {
        guard let content = contents[reference] else { throw CocoaError(.fileNoSuchFile) }
        return content
    }
    func isPlaying(_ reference: WallpaperReference) -> Bool { playing == reference }
    func isFavorite(_ reference: WallpaperReference) -> Bool { false }
    func capturePlaybackSnapshot(for reference: WallpaperReference) throws -> UUID { UUID() }
    func play(_ reference: WallpaperReference, from source: UUID?) { plays.append(reference) }
}
@MainActor private final class MenuSession {
    struct State { var items: [OnlineImageArtwork] = [] }
    var state = State()
}
@MainActor private final class OnlineImageLibrary {
    static let shared = OnlineImageLibrary()
    var progress: [OnlineImageAssetID: Double] = [:]
    var downloads: [(id: OnlineImageAssetID, apply: Bool)] = []
    var cancellations: [OnlineImageAssetID] = []
    var records: [WallpaperReference: OnlineImageLocalRecord] = [:]
    var retries: [WallpaperReference] = []
    func record(for reference: WallpaperReference) -> OnlineImageLocalRecord? { records[reference] }
    func retry(_ reference: WallpaperReference) { retries.append(reference) }
    func downloadArtwork(_ artwork: OnlineImageArtwork, apply: Bool = false) {
        downloads.append((artwork.firstAssetID, apply))
    }
    func cancel(_ id: OnlineImageAssetID) {
        cancellations.append(id); progress.removeValue(forKey: id)
    }
}

// ACTUAL_LIBRARY_FAVORITE_STATE

@MainActor private final class MenuManager {
    struct Commit { let ticket: UUID }
    struct PlaybackSwitch { var committed: Commit? }
    var playbackSwitch = PlaybackSwitch()
}
@MainActor private final class MenuImports { func chooseReplacement(for reference: WallpaperReference) {} }
private enum WallpaperLibraryImportCoordinator {
    static func canRelocate(_ item: WallpaperContentItem, relationships: MenuWorkspace.Relationships) -> Bool { false }
}
private struct SteamWorkshopDownloadRecord {
    let id: String, title: String
    var displayItemForToolbar: Int { 0 }
}
@MainActor private final class MenuSteam {
    struct Client { var accountEpoch = 1 }
    let steamServiceClient = Client()
    func latestDownloadRecord(for id: String) -> SteamWorkshopDownloadRecord? { nil }
    func downloadWorkshopItem(id: String, pageTitle: String) {}
    func recoveryWorkshopDetailURL(itemID: String) -> URL? { nil }
    func openWorkshopDetailPage(itemID: String) {}
}
@MainActor private final class MenuOnline {
    var retriedIDs: [Int] = []
    func retryDownload(id: Int) { retriedIDs.append(id) }
    func openVideoSourcePage(id: Int) {}
}
@MainActor private enum SteamWorkshopItemMenu {
    static func make(item: Int, service: MenuSteam, includePrimary: Bool, includeReveal: Bool) -> NSMenu { NSMenu() }
}
private enum SteamWorkshopDownloadGridSupport {
    static func isRetryEligible(_ record: SteamWorkshopDownloadRecord) -> Bool { false }
}
private typealias WallpaperLibraryWorkspace = MenuWorkspace
private typealias SteamWorkshopService = MenuSteam
private typealias PixabayService = MenuOnline
@MainActor private enum WallpaperLibraryQuery {
    static func canonicalReferences<S: Sequence>(_ references: S, relationships: MenuWorkspace.Relationships) throws
        -> [WallpaperReference: WallpaperReference] where S.Element == WallpaperReference {
        Dictionary(references.map { ($0, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
@MainActor private enum MenuBrowser {
    static var opened: [URL] = []
    static func open(_ url: URL) { opened.append(url) }
}
// ACTUAL_LIBRARY_DOWNLOAD_RECOVERY
@MainActor private final class MenuCommands {
    let workspace: MenuWorkspace
    let manager = MenuManager(), imports = MenuImports(), steam = MenuSteam()
    let pixabay = MenuOnline()
    var canOrganize = true
    var stops = 0
    var onInspect: ((WallpaperContentItem) -> Void)?
    var onPreview: ((WallpaperContentItem) -> Void)?
    init(workspace: MenuWorkspace) { self.workspace = workspace }
    func favoriteActionState(for items: [WallpaperContentItem]) -> WallpaperLibraryFavoriteActionState {
        .init(canEdit: canOrganize, hasItems: !items.isEmpty, allFavorite: false,
              allOrganizable: items.allSatisfy { $0.capabilities.contains(.organize) })
    }
    func makeFavoriteAction(resolved: (items: [WallpaperContentItem], state: WallpaperLibraryFavoriteActionState)) -> (() -> Void)? { nil }
    func stop(_ reference: WallpaperReference, expectedTicket: UUID) {
        guard workspace.playing == reference, manager.playbackSwitch.committed?.ticket == expectedTicket else { return }
        stops += 1; workspace.playing = nil
    }
    func makeFavoriteAction(_ references: [WallpaperReference]) -> (() -> Void)? { nil }
    func choosePlaylist(_ references: [WallpaperReference], anchor: NSView?) {}
    func makePlaylistMenu(_ references: [WallpaperReference]) -> NSMenu? { nil }
    func reveal(_ items: [WallpaperContentItem]) {}
    func removalTitle(for page: MenuPage) -> String { "移除" }
    func remove(_ items: [WallpaperContentItem], from page: MenuPage) {}
    // ACTUAL_LIBRARY_CONTEXT_MENU
    // ACTUAL_LIBRARY_PRIMARY
}
@MainActor private final class MenuInspector {
    var previews: [WallpaperContentItem] = []
    func preview(content: WallpaperContentItem) -> Bool { previews.append(content); return true }
}
@MainActor private final class WallpaperLibraryOnlineImages {
    final class Selection { var selectedContent: WallpaperContentItem? }
    let selection = Selection()
    let wallhaven = MenuSession(), pixiv = MenuSession()
    let library = OnlineImageLibrary.shared, workspace = MenuWorkspace()
    let inspector = MenuInspector()
    lazy var commands = MenuCommands(workspace: workspace)
    var isDisplayed = true
    var window: NSWindow?
    var isPlaying: ((WallpaperReference) -> Bool)?
    var isSwitching: ((WallpaperReference) -> Bool)?
    var selectedContent: WallpaperContentItem? { browser(for: workspace.presentation.page)?.selectedContent }
    func browser(for page: MenuPage) -> Selection? { page == .wallhaven || page == .pixiv ? selection : nil }
    func session(for page: MenuPage) -> MenuSession? { page == .wallhaven ? wallhaven : page == .pixiv ? pixiv : nil }
    var authors: [OnlineImageAuthor] = []
    var authorOrigins: [WallpaperLibraryPage] = []
    func openAuthor(_ author: OnlineImageAuthor, from page: WallpaperLibraryPage) {
        authors.append(author); authorOrigins.append(page)
    }
    // ACTUAL_IMAGE_MENU
}

@main private struct OnlineImageMenuHarness {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        var checks: [String: Bool] = [:]
        func entry(_ menu: NSMenu, _ title: String) -> NSMenuItem {
            precondition(menu.items.filter { $0.title == title }.count == 1, title)
            return menu.items.first { $0.title == title }!
        }
        func perform(_ menu: NSMenu, _ title: String) {
            let item = entry(menu, title)
            precondition(item.isEnabled)
            precondition(NSApp.sendAction(item.action!, to: item.target, from: item))
        }
        for source in OnlineImageSource.allCases {
            let value = WallpaperLibraryOnlineImages()
            value.library.progress.removeAll(); value.library.downloads.removeAll(); value.library.cancellations.removeAll()
            value.library.records.removeAll(); value.library.retries.removeAll(); MenuBrowser.opened.removeAll()
            value.workspace.presentation.page = source == .wallhaven ? .wallhaven : .pixiv
            let artwork = OnlineImageArtwork(source: source, artworkID: source == .wallhaven ? "abc123" : "12345",
                title: "Fixture", sourceURL: URL(string: "https://example.invalid/work")!,
                author: "Author", authorID: "77", kind: .image)
            if source == .wallhaven { value.wallhaven.state.items = [artwork] }
            else { value.pixiv.state.items = [artwork] }
            let content = OnlineImageContentProjection.remote(artwork)
            let idle = value.menu(content, source: source)!
            checks["\(source)-idle-menu-starts-both-original-download-intents"] = entry(idle, "下载原图").isEnabled
                && entry(idle, "下载并设为壁纸").isEnabled && !idle.items.contains { $0.title == "取消下载" }
            perform(idle, "下载原图"); perform(idle, "下载并设为壁纸")
            checks["\(source)-idle-actions-keep-the-clicked-artwork-and-apply-meaning"] = value.library.downloads.count == 2
                && value.library.downloads.map(\.id) == [artwork.firstAssetID, artwork.firstAssetID]
                && !value.library.downloads[0].apply && value.library.downloads[1].apply
            checks["\(source)-remote-idle-has-one-source-page"] = idle.items.filter {
                ["打开原网页", "查看原网页"].contains($0.title)
            }.count == 1
            perform(idle, "临时预览")
            checks["\(source)-remote-preview-delegates-the-exact-content-without-admitting-another-download"] = value.inspector.previews == [content]
                && value.library.downloads.count == 2 && value.library.records.isEmpty

            value.library.progress[artwork.firstAssetID] = 0.25
            let busy = value.menu(content, source: source)!
            checks["\(source)-busy-menu-disables-start-actions-and-keeps-cancel-source-author"] = !entry(busy, "下载原图").isEnabled
                && !entry(busy, "下载并设为壁纸").isEnabled && entry(busy, "取消下载").isEnabled
                && !busy.autoenablesItems
                && entry(busy, "打开原网页").isEnabled
                && (source == .wallhaven || entry(busy, "查看作者作品").isEnabled)
            checks["\(source)-remote-busy-has-one-source-page"] = busy.items.filter {
                ["打开原网页", "查看原网页"].contains($0.title)
            }.count == 1
            perform(busy, "取消下载")
            checks["\(source)-cancel-dispatches-to-the-existing-transfer-and-restores-starts"] = value.library.cancellations == [artwork.firstAssetID]
                && value.library.progress[artwork.firstAssetID] == nil
                && entry(value.menu(content, source: source)!, "下载原图").isEnabled
            perform(idle, "查看作者作品")
            checks["\(source)-author-command-keeps-typed-source-id-name-and-origin"] = value.authors == [.init(source: source, id: "77", name: "Author")]
                && value.authorOrigins == [source == .wallhaven ? .wallhaven : .pixiv]
            if source == .pixiv { checks["pixiv-author-command-remains-available"] = value.authors.map(\.id) == ["77"] }
            value.workspace.presentation.page = .videos
            perform(idle, "下载原图")
            checks["\(source)-held-menu-cannot-start-on-a-different-page"] = value.library.downloads.count == 2
            value.workspace.presentation.page = source == .wallhaven ? .wallhaven : .pixiv
            WallpaperLibrarySheetPresentation.allowsInput = false
            perform(idle, "下载原图")
            checks["\(source)-owned-modal-input-domain-revokes-held-download"] = value.library.downloads.count == 2
            WallpaperLibrarySheetPresentation.allowsInput = true

            let record = OnlineImageLocalRecord(assetID: artwork.firstAssetID, title: artwork.title,
                sourceURL: artwork.sourceURL, author: artwork.author, authorID: artwork.authorID, tags: [],
                relativePath: "fixture.jpg", pixelWidth: 100, pixelHeight: 100, fileSizeBytes: 100,
                firstDownloadedAt: Date(), revision: UUID())
            let local = OnlineImageContentProjection.local(record, url: URL(fileURLWithPath: "/unused/fixture.jpg"), available: true)
            value.library.records[local.reference] = record
            value.workspace.contents[local.reference] = local
            let localMenu = value.menu(local, source: source)!
            var inspected: [WallpaperReference] = []
            value.commands.onInspect = { inspected.append($0.reference) }
            perform(localMenu, "查看信息")
            checks["\(source)-published-content-keeps-native-library-actions-without-download-duplicates"] = inspected == [local.reference]
                && !localMenu.items.contains { ["下载原图", "下载并设为壁纸", "取消下载"].contains($0.title) }
                && entry(localMenu, "打开原网页").isEnabled
            for available in [true, false] {
                let state = available ? "available" : "unavailable"
                let localContent = OnlineImageContentProjection.local(record,
                    url: URL(fileURLWithPath: "/unused/fixture.jpg"), available: available)
                value.workspace.contents[localContent.reference] = localContent
                let localIdle = value.menu(localContent, source: source)!
                checks["\(source)-local-\(state)-idle-retains-shared-actions-without-transfer-duplicates"] =
                    entry(localIdle, "查看信息").isEnabled && entry(localIdle, "设为壁纸").isEnabled == available
                    && !localIdle.items.contains { ["下载原图", "下载并设为壁纸", "取消下载"].contains($0.title) }
                    && entry(localIdle, "打开原网页").isEnabled
                checks["\(source)-local-\(state)-idle-has-one-source-page-and-preserves-retry"] =
                    localIdle.items.filter { ["打开原网页", "查看原网页"].contains($0.title) }.count == 1
                    && localIdle.items.contains { $0.title == "重新下载" } == !available

                let other = OnlineImageArtwork(source: source, artworkID: source == .wallhaven ? "def456" : "67890",
                    title: "Other", sourceURL: URL(string: "https://example.invalid/other")!, kind: .image)
                let before = value.library.cancellations.count
                value.library.progress[artwork.firstAssetID] = 0.25
                value.library.progress[other.firstAssetID] = 0.75
                let localBusy = value.menu(localContent, source: source)!
                checks["\(source)-local-\(state)-busy-has-one-shared-cancel-and-keeps-original-actions"] =
                    entry(localBusy, "取消下载").isEnabled && !localBusy.autoenablesItems
                    && entry(localBusy, "查看信息").isEnabled
                    && !localBusy.items.contains { ["下载原图", "下载并设为壁纸"].contains($0.title) }
                    && entry(localBusy, "打开原网页").isEnabled
                checks["\(source)-local-\(state)-busy-has-one-source-page-and-preserves-retry"] =
                    localBusy.items.filter { ["打开原网页", "查看原网页"].contains($0.title) }.count == 1
                    && localBusy.items.contains { $0.title == "重新下载" } == !available
                if source == .wallhaven { value.wallhaven.state.items = [other] }
                else { value.pixiv.state.items = [other] }
                let webpagesBefore = MenuBrowser.opened.count
                perform(localBusy, "打开原网页")
                checks["\(source)-local-\(state)-source-page-keeps-clicked-artwork"] =
                    Array(MenuBrowser.opened.dropFirst(webpagesBefore)) == [artwork.sourceURL]
                perform(localBusy, "取消下载")
                checks["\(source)-local-\(state)-cancel-dispatches-once-to-the-fixed-asset"] =
                    Array(value.library.cancellations.dropFirst(before)) == [artwork.firstAssetID]
                    && value.library.progress[artwork.firstAssetID] == nil
                    && value.library.progress[other.firstAssetID] == 0.75
                if source == .wallhaven { value.wallhaven.state.items = [artwork] }
                else { value.pixiv.state.items = [artwork] }

                value.library.progress[artwork.firstAssetID] = 0.5
                let heldPage = value.menu(localContent, source: source)!
                value.workspace.presentation.page = .videos
                perform(heldPage, "取消下载")
                checks["\(source)-local-\(state)-held-page-revokes-shared-cancel"] =
                    value.library.cancellations.count == before + 1 && value.library.progress[artwork.firstAssetID] == 0.5
                value.workspace.presentation.page = source == .wallhaven ? .wallhaven : .pixiv
                let heldModal = value.menu(localContent, source: source)!
                WallpaperLibrarySheetPresentation.allowsInput = false
                perform(heldModal, "取消下载")
                checks["\(source)-local-\(state)-modal-domain-revokes-shared-cancel"] =
                    value.library.cancellations.count == before + 1 && value.library.progress[artwork.firstAssetID] == 0.5
                WallpaperLibrarySheetPresentation.allowsInput = true
                let heldSelection = value.menu(localContent, source: source)!
                value.workspace.presentation.selectionState.sessionID = UUID()
                perform(heldSelection, "取消下载")
                checks["\(source)-local-\(state)-selection-session-revokes-shared-cancel"] =
                    value.library.cancellations.count == before + 1 && value.library.progress[artwork.firstAssetID] == 0.5
                let heldReset = value.menu(localContent, source: source)!
                value.workspace.relationships.resetEpoch = UUID()
                perform(heldReset, "取消下载")
                checks["\(source)-local-\(state)-reset-revokes-shared-cancel"] =
                    value.library.cancellations.count == before + 1 && value.library.progress[artwork.firstAssetID] == 0.5
                perform(value.menu(localContent, source: source)!, "取消下载")
                checks["\(source)-local-\(state)-next-menu-retains-one-cancel"] =
                    Array(value.library.cancellations.dropFirst(before)) == [artwork.firstAssetID, artwork.firstAssetID]
                    && value.library.progress[artwork.firstAssetID] == nil
                    && value.library.progress[other.firstAssetID] == 0.75
                value.library.progress.removeValue(forKey: other.firstAssetID)
            }
            let missing = OnlineImageContentProjection.local(record,
                url: URL(fileURLWithPath: "/unused/fixture.jpg"), available: false)
            value.workspace.contents[missing.reference] = missing
            let beforeRetry = value.library.retries.count
            let recoveryMenu = value.menu(missing, source: source)!
            if source == .wallhaven { value.wallhaven.state.items = [] }
            else { value.pixiv.state.items = [] }
            perform(recoveryMenu, "重新下载")
            checks["\(source)-composed-recovery-retries-the-fixed-reference"] =
                Array(value.library.retries.dropFirst(beforeRetry)) == [missing.reference]
            if source == .wallhaven { value.wallhaven.state.items = [artwork] }
            else { value.pixiv.state.items = [artwork] }
            let heldRecoveryPage = value.menu(missing, source: source)!
            let webpagesBeforePage = MenuBrowser.opened.count
            value.workspace.presentation.page = .downloads
            perform(heldRecoveryPage, "重新下载"); perform(heldRecoveryPage, "打开原网页")
            let webpagesBeforeReset = MenuBrowser.opened.count
            checks["\(source)-held-page-revokes-recovery-and-source-page"] = value.library.retries.count == beforeRetry + 1
                && MenuBrowser.opened.count == webpagesBeforePage
            value.workspace.presentation.page = source == .wallhaven ? .wallhaven : .pixiv
            let heldRecoveryEpoch = value.menu(missing, source: source)!
            value.workspace.relationships.resetEpoch = UUID()
            perform(heldRecoveryEpoch, "重新下载")
            WallpaperLibrarySheetPresentation.allowsInput = false
            perform(value.menu(missing, source: source)!, "重新下载")
            perform(value.menu(missing, source: source)!, "打开原网页")
            checks["\(source)-epoch-and-modal-revoke-recovery-without-losing-webpage"] =
                value.library.retries.count == beforeRetry + 1 && MenuBrowser.opened.count == webpagesBeforeReset
            WallpaperLibrarySheetPresentation.allowsInput = true
            value.workspace.presentation.canEditCollections = false
            value.commands.canOrganize = false
            value.library.progress[artwork.firstAssetID] = 0.4
            let readOnly = value.menu(missing, source: source)!
            checks["\(source)-read-only-recovery-fallback-retains-one-online-source-page"] =
                readOnly.items.filter { ["打开原网页", "查看原网页"].contains($0.title) }.count == 1
                && !readOnly.items.contains { $0.title == "重新下载" } && entry(readOnly, "取消下载").isEnabled
            perform(readOnly, "打开原网页")
            checks["\(source)-read-only-source-page-remains-usable"] = MenuBrowser.opened.last == artwork.sourceURL
            let beforeReadOnlyCancel = value.library.cancellations.count
            perform(readOnly, "取消下载")
            checks["\(source)-read-only-busy-keeps-one-cancel"] =
                Array(value.library.cancellations.dropFirst(beforeReadOnlyCancel)) == [artwork.firstAssetID]
                && value.library.progress[artwork.firstAssetID] == nil
            value.workspace.presentation.canEditCollections = true
            value.commands.canOrganize = true
            value.workspace.presentation.page = .downloads
            let libraryMenu = value.commands.contextMenu(for: [missing])!
            checks["\(source)-ordinary-library-keeps-original-recovery-page-and-retry"] =
                libraryMenu.items.filter { ["打开原网页", "查看原网页"].contains($0.title) }.count == 1
                && entry(libraryMenu, "查看原网页").isEnabled && entry(libraryMenu, "重新下载").isEnabled
            let libraryPageBefore = MenuBrowser.opened.count
            perform(libraryMenu, "查看原网页")
            checks["\(source)-ordinary-library-recovery-page-keeps-reference"] =
                Array(MenuBrowser.opened.dropFirst(libraryPageBefore)) == [record.sourceURL]
            value.workspace.presentation.page = source == .wallhaven ? .wallhaven : .pixiv
            value.selection.selectedContent = missing
            let retry = value.selectedPrimaryAction()!
            let retriesBeforePrimary = value.library.retries.count
            retry.action()
            checks["\(source)-selected-missing-image-primary-keeps-retry-title-and-original-owner"] = retry.title == "重新下载"
                && value.library.retries.count == retriesBeforePrimary + 1 && value.library.retries.last == missing.reference
                && value.workspace.plays.isEmpty
            value.selection.selectedContent = local
            value.workspace.contents[local.reference] = local
            value.workspace.playing = local.reference
            value.commands.manager.playbackSwitch.committed = .init(ticket: UUID())
            value.isPlaying = { value.workspace.isPlaying($0) }
            let stop = value.selectedPrimaryAction()!, organizationStop = value.selectedOrganizationActions()!
            stop.action()
            organizationStop.onPrimary()
            checks["\(source)-selected-primary-and-organization-retain-fixed-stop-without-replay"] = stop.title == "停止播放"
                && organizationStop.state.isPlaying && value.commands.stops == 1 && value.workspace.plays.isEmpty
            value.workspace.playing = local.reference
            let staleStop = value.selectedPrimaryAction()!
            value.commands.manager.playbackSwitch.committed = .init(ticket: UUID())
            staleStop.action()
            checks["\(source)-held-online-image-stop-cannot-borrow-new-ticket-for-the-same-item"] = value.commands.stops == 1
                && value.workspace.plays.isEmpty
        }
        precondition(checks.values.allSatisfy { $0 })
        let data = try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys])
        print(String(data: data, encoding: .utf8)!)
    }
}
