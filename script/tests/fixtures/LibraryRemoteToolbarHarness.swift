import AppKit
import Combine

@MainActor final class FinderRevealCoordinator {
    static let shared = FinderRevealCoordinator()
    private(set) var requests: [[URL]] = []
    func reveal(_ urls: [URL]) { requests.append(urls) }
}

// Network/authentication and row thumbnail IO are leaves. Toolbar, native
// popovers, task content/commands, projections and source choices are real.
// The task values below never carry staging/receipt data in these UI cases.
struct SteamWorkshopStagingLeaseIdentity: Codable, Equatable {}
struct SteamWorkshopStagedReceipt: Codable, Equatable {}
struct SteamWorkshopLibraryCommit: Codable, Equatable {}
// ACTUAL_TASK_MODELS
enum AuthDisplayState { case online, connecting, awaitingInput, expired, failed, signedOut }
@MainActor final class ToolbarAuth {
    @Published var phase = AuthDisplayState.signedOut
    @Published var steamId: String? = "123456789"
    @Published var expired = false
    var accountName: String? = "Fixture account"
    var displayState: AuthDisplayState { phase }
    var isOnline: Bool { phase == .online }
}
@MainActor final class ToolbarJobs {
    @Published var jobs: [SteamDownloadJob] = []
    @Published var history: [SteamDownloadHistoryEntry] = []
    var prunes = 0
    var clearedAccounts: [String] = []
    func pruneExpiredHistory() { prunes += 1 }
    func clearHistory(forAccount account: String? = nil) {
        clearedAccounts.append(account ?? "all-local")
        history = account.map { account in history.filter { $0.accountSteamId != account } } ?? []
    }
    func removeHistory(forJobID id: String, accountSteamId: String?) {
        history.removeAll { $0.jobID == id && $0.accountSteamId == accountSteamId }
    }
}
struct ToolbarDownloadRecord { let id: String; var status: Status; var previewURL: URL? = nil
    enum Status: Equatable { case ready }
}
struct ToolbarPreviewItem { var previewImageURL: URL? = nil }
@MainActor final class SteamWorkshopService {
    static let shared = SteamWorkshopService()
    let steamAuth = ToolbarAuth(), downloadJobStore = ToolbarJobs()
    @Published var statusMessage = ""
    // ACTUAL_STEAM_QUERY_FIELDS
    @Published var browserSectionTitle = "创意工坊"
    @Published var isBrowsingAuthorWorkshop = false
    var navigationVersion = 0
    var queries: [String] = []
    var requestQueries: [String] = []
    var displayedQueryUpdates: [String] = []
    var suppressAutomaticBrowseNavigation = false
    var isUpdatingBrowserQueryProgrammatically = false
    struct BrowseContext { var isAuthorWorkshop = false }
    var browseContext = BrowseContext()
    var currentPageTitle = "创意工坊"
    func navigateToBrowse() { navigationVersion += 1; requestQueries.append(browserQuery) }
    func handleBrowserQueryChanged() { if !suppressAutomaticBrowseNavigation { navigateToBrowse() } }
    // The actual query setter still invokes its local-projection consumer.
    // This toolbar gate records that boundary without inventing a browser feed.
    func updateDisplayedBrowserItems() { displayedQueryUpdates.append(browserQuery) }
    // ACTUAL_STEAM_QUERY_ACTIONS
    var activeFilterSummary = "全部"
    var authorWorkshopReturnDestination: (title: String, marker: Int)? = ("返回创意工坊", 0)
    var loginCalls = 0, logoutCalls = 0, backCalls = 0, subscriptionsCalls = 0
    var canReturnFromBrowse: Bool { isBrowsingAuthorWorkshop || source.isPersonal }
    var retryRequests: [String] = [], discardedJobs: [String] = []
    var downloads: [ToolbarDownloadRecord] = []
    var previewReloadToken = 0
    func latestDownloadRecord(for id: String) -> ToolbarDownloadRecord? { downloads.first { $0.id == id } }
    func downloadRecord(for id: String) -> ToolbarDownloadRecord? { latestDownloadRecord(for: id) }
    func browserItemForDownload(id: String) -> ToolbarPreviewItem? { nil }
    func revealItem(_ record: ToolbarDownloadRecord) {}
    func isDownloadPaused(itemID: String) -> Bool { false }
    func cancelDownloadImmediately(itemID: String, showFeedback: Bool) {}
    func pauseDownload(itemID: String) {}
    func resumeDownload(itemID: String) {}
    func promoteQueuedDownload(itemID: String) {}
    func showLoginPanel() { loginCalls += 1 }
    func signOutEverywhere() { logoutCalls += 1 }
    func returnFromBrowseSubpage() { backCalls += 1; isBrowsingAuthorWorkshop = false }
    func showMySubscriptions() { subscriptionsCalls += 1 }
    func downloadWorkshopItem(id: String, pageTitle: String) { retryRequests.append(id) }
    func discardFailedDownload(jobID: String) { discardedJobs.append(jobID) }
}
struct ToolbarActivity {
    let itemID: Int
    let assetID: OnlineImageAssetID
    let attemptID: UUID
    let title: String
    let phase: DownloadTaskPhase
    let createdAt: Date
    let previewURL: URL?
}
@MainActor final class PixabayService: ObservableObject {
    static let shared = PixabayService()
    @Published var toolbarCategory = PixabayCategory.all
    @Published var toolbarQuery = ""
    @Published var currentParams = PixabaySearchParams()
    var apiKey = "fixture-key"
    var hasLoadedOnce = false
    var searches: [PixabaySearchParams] = []
    var refreshes = 0
    struct Record { let id: Int; let isAvailable: Bool; let thumbnailSourceKey: String?; let localURL: URL }
    struct Content { var entries: [Record] = [] }
    var downloadedContent = Content()
    var downloadActivities: [ToolbarActivity] = []
    var downloadProgressByID: [Int: Double] = [:]
    func retryDownload(id: Int) {}
    func cancelDownload(id: Int, attemptID: UUID) {}
    func search(params: PixabaySearchParams) { currentParams = params; hasLoadedOnce = true; searches.append(params) }
    func searchWithCurrentContext(query: String? = nil, category: PixabayCategory? = nil, order: PixabayOrder? = nil) {
        currentParams.query = query ?? toolbarQuery
        if let category { currentParams.category = category }
        if let order { currentParams.order = order }
        hasLoadedOnce = true
        searches.append(currentParams)
    }
    func refresh() { refreshes += 1 }
}
@MainActor final class ToolbarImages {
    var snapshot = OnlineImageLocalSnapshot()
    var downloadActivities: [ToolbarActivity] = []
    var progress: [OnlineImageAssetID: Double] = [:]
    func requestScope(_ source: OnlineImageSource) -> String { "fixture" }
    func retryDownload(_ reference: WallpaperReference, title: String) {}
    func cancel(_ id: OnlineImageAssetID, attemptID: UUID) {}
    func record(for reference: WallpaperReference) -> OnlineImageLocalRecord? { nil }
    func localURL(for record: OnlineImageLocalRecord) -> URL? { nil }
}
/// Source publishers and IO are leaves; these are the complete production
/// aggregate projection, native-panel factory and captured-target dispatcher.
@MainActor final class ToolbarTaskCommands {
    let steam = SteamWorkshopService.shared
    let pixabay = PixabayService.shared
    let images = ToolbarImages()
    let history: DownloadHistoryStore?
    var historyError: String?
    let changed = PassthroughSubject<Void, Never>()
    var changes: AnyPublisher<Void, Never> { changed.eraseToAnyPublisher() }
    private var subscriptions = Set<AnyCancellable>()
    private(set) var progressLeases = 0
    private(set) var endedProgressLeases = 0
    init() throws {
        history = try DownloadHistoryStore(persistenceURL: URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent().appendingPathComponent("download-history/history.json"))
        let publishers = [steam.downloadJobStore.$jobs.map { _ in () }.eraseToAnyPublisher(),
            steam.downloadJobStore.$history.map { _ in () }.eraseToAnyPublisher(),
            steam.steamAuth.$steamId.map { _ in () }.eraseToAnyPublisher()]
        Publishers.MergeMany(publishers).receive(on: RunLoop.main).sink { [weak self] in self?.changed.send() }.store(in: &subscriptions)
    }
    func steamProgress(id: String, attempt: String) -> DownloadTaskProgress? { nil }
    func loadThumbnail(_ row: DownloadTaskRow, receive: @escaping (NSImage?) -> Void) -> (() -> Void)? { nil }
    func observeProgress(_ row: DownloadTaskRow, receive: @escaping (DownloadTaskProgress) -> Void) -> (() -> Void)? {
        progressLeases += 1
        return { [weak self] in self?.progressLeases -= 1; self?.endedProgressLeases += 1 }
    }
    // ACTUAL_TASK_COMMANDS
}
extension Notification.Name {
    static let steamWorkshopModeDidChange = Self("fixture-steam-mode")
    static let steamWorkshopBrowseContextDidChange = Self("fixture-steam-context")
    static let pixabayModeDidChange = Self("fixture-online-mode")
}
extension NSToolbarItem.Identifier { static let downloadTasks = Self("downloadTasks") }
@MainActor final class RemoteToolbarDelegate: NSObject, NSToolbarDelegate {
    var identifiers: [NSToolbarItem.Identifier] = []
    var makeItem: ((NSToolbarItem.Identifier) -> NSToolbarItem?)?
    var downloadItem: NSToolbarItem?
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { identifiers }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { identifiers }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar: Bool) -> NSToolbarItem? {
        if id.rawValue == "ToolbarTitle" {
            let item = NSToolbarItem(itemIdentifier: id)
            item.view = NSTextField(labelWithString: "来源标题")
            return item
        }
        if id.rawValue == "downloadTasks" { return downloadItem }
        return makeItem?(id)
    }
}

/// Test-only lifetime for one native notification and its bounded deadline.
/// Mutable observation handles stay on this actor instead of being captured
/// by an escaping Sendable closure and assigned after that capture.
@MainActor private final class NativePopoverEventReceipt {
    private var observer: NSObjectProtocol?
    private var deadline: Task<Void, Never>?
    private var continuation: CheckedContinuation<Bool, Never>?

    func receive(_ name: Notification.Name, matching: @escaping @MainActor (NSPopover) -> Bool,
                 deadlineDescription: String, perform action: @MainActor () -> Void) async -> Bool {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            observer = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    if let value = note.object as? NSPopover, matching(value) { self?.finish(true) }
                }
            }
            deadline = Task { @MainActor [weak self] in
                do { try await Task.sleep(nanoseconds: 2_000_000_000) }
                catch { return }
                FileHandle.standardError.write(Data(("Native lifecycle deadline: " + deadlineDescription + "\n").utf8))
                self?.finish(false)
            }
            action()
        }
    }

    private func finish(_ received: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        deadline?.cancel()
        deadline = nil
        continuation.resume(returning: received)
    }
}

@main enum LibraryRemoteToolbarChecks {
    @MainActor static func main() {
        initializeNativeAppHarness()
        let app = NSApplication.shared
        Task { @MainActor in
            do { try await run() }
            catch { fatalError("Remote toolbar fixture: \(error)") }
            app.stop(nil)
            if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) { app.postEvent(event, atStart: false) }
        }
        app.run()
    }

    @MainActor static func run() async throws {
        let app = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let toolbar = NSToolbar(identifier: .init("remote-fixture")), delegate = RemoteToolbarDelegate()
        toolbar.delegate = delegate; toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        let steam = SteamWorkshopToolbarController(toolbar: toolbar, window: window)
        let pixabay = PixabayToolbarController(window: window)
        let taskCommands = try ToolbarTaskCommands()
        let downloadController = taskCommands.makePopoverController()
        let downloadItem = NSToolbarItem(itemIdentifier: .downloadTasks)
        let taskAction = ActionMenuItem(title: "下载任务", symbol: "arrow.down.to.line") { [weak downloadItem, weak window] in
            guard let downloadItem, let window else { return }
            downloadController.toggle(relativeTo: downloadItem, in: window)
        }
        let downloadButton = NSButton(title: "", target: taskAction, action: taskAction.action)
        downloadButton.image = NSImage(systemSymbolName: "arrow.down.to.line", accessibilityDescription: "下载任务")
        downloadButton.frame = NSRect(x: 0, y: 0, width: 32, height: 32)
        WallpaperLibraryControlStyle.capsule(downloadButton)
        downloadItem.label = "下载任务"; downloadItem.autovalidates = false
        downloadItem.view = downloadButton; downloadItem.menuFormRepresentation = taskAction
        delegate.downloadItem = downloadItem
        var checks: [String: Bool] = [:]
        var taskPopover: NSPopover?
        var didShowCounts: [ObjectIdentifier: Int] = [:]
        var popoverPhase = "setup"
        let popoverStarted = Date()
        var popoverEventCount = 0
        let popoverObservers = [NSPopover.willShowNotification, NSPopover.didShowNotification,
            NSPopover.willCloseNotification, NSPopover.didCloseNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
                MainActor.assumeIsolated {
                    guard let value = note.object as? NSPopover else { return }
                    if name == NSPopover.willShowNotification,
                       value.contentViewController is DownloadTasksContentController { taskPopover = value }
                    if name == NSPopover.didShowNotification { didShowCounts[ObjectIdentifier(value), default: 0] += 1 }
                    // Bounded lifecycle evidence; these observations never
                    // invoke another native action or decide an assertion.
                    if popoverEventCount < 48 {
                        popoverEventCount += 1
                        let text = "Popover event: phase=\(popoverPhase), t=\(Date().timeIntervalSince(popoverStarted)), name=\(name.rawValue), id=\(ObjectIdentifier(value)), shown=\(value.isShown), content=\(String(describing: value.contentViewController)), window=\(String(describing: value.contentViewController?.view.window))\n"
                        FileHandle.standardError.write(Data(text.utf8))
                    }
                }
            }
        }
        defer { popoverObservers.forEach { NotificationCenter.default.removeObserver($0) } }
        func settle(_ seconds: TimeInterval = 0.03) async {
            window.contentView?.layoutSubtreeIfNeeded()
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            window.contentView?.layoutSubtreeIfNeeded()
        }
        func diagnostic(_ text: String) { FileHandle.standardError.write(Data((text + "\n").utf8)) }
        func afterPopoverEvent(_ name: Notification.Name, matching: @escaping @MainActor (NSPopover) -> Bool,
                               perform action: @MainActor () -> Void) async -> Bool {
            // Subscribe before the single native action. The deadline bounds
            // only an AppKit lifecycle event, never a desired field value.
            let receipt = NativePopoverEventReceipt()
            return await receipt.receive(name, matching: matching,
                deadlineDescription: "phase=\(popoverPhase), event=\(name.rawValue)", perform: action)
        }
        func descendants<T: NSView>(_ root: NSView, _ type: T.Type) -> [T] {
            ((root as? T).map { [$0] } ?? []) + root.subviews.flatMap { descendants($0, type) }
        }
        func viewFacts(_ view: NSView?) -> String {
            guard let view else { return "nil" }
            let host = view.window
            return "id=\(ObjectIdentifier(view)), frame=\(view.frame), bounds=\(view.bounds), visibleRect=\(view.visibleRect), hidden=\(view.isHidden), ancestorHidden=\(view.isHiddenOrHasHiddenAncestor), super=\(String(describing: view.superview.map { type(of: $0) })), window=\(String(describing: host?.windowNumber)), windowVisible=\(String(describing: host?.isVisible)), windowFrame=\(String(describing: host?.frame)), screen=\(String(describing: host?.screen?.frame))"
        }
        func popoverFacts(_ value: NSPopover?) -> String {
            guard let value else { return "nil" }
            return "id=\(ObjectIdentifier(value)), shown=\(value.isShown), didShow=\(didShowCounts[ObjectIdentifier(value), default: 0]), positioningRect=\(value.positioningRect), content={\(viewFacts(value.contentViewController?.view))}"
        }
        func toolbarFacts(_ label: String) {
            let visible = toolbar.visibleItems?.map { $0.itemIdentifier.rawValue } ?? []
            diagnostic("\(label): windowFrame=\(window.frame), contentFrame=\(String(describing: window.contentView?.frame)), layout=\(window.contentLayoutRect), visibleIDs=\(visible), allIDs=\(toolbar.items.map { $0.itemIdentifier.rawValue })")
            for item in [steam.filterToolbarItem, downloadItem] {
                diagnostic("\(label) item \(item.itemIdentifier.rawValue): toolbarMatches=\(item.toolbar === toolbar), enabled=\(item.isEnabled), nativeVisible=\(toolbar.visibleItems?.contains { $0 === item } == true), view={\(viewFacts(item.view))}")
            }
        }
        func hasSharedSearchWidth(_ field: NSSearchField) -> Bool {
            let expected = NSRect(x: field.bounds.minX, y: field.bounds.minY, width: 220, height: field.bounds.height)
            return field.backingAlignedRect(field.bounds, options: .alignAllEdgesNearest).width
                == field.backingAlignedRect(expected, options: .alignAllEdgesNearest).width
        }
        func searchInteraction(_ item: NSSearchToolbarItem, label: String, begin: () -> Void) async -> Bool {
            let field = item.searchField
            var beganAfter: TimeInterval?
            let started = Date()
            let observation = NotificationCenter.default.addObserver(forName: NSControl.textDidBeginEditingNotification, object: field, queue: .main) { _ in
                MainActor.assumeIsolated { beganAfter = Date().timeIntervalSince(started) }
            }
            begin()
            let immediateEditor = field.currentEditor() != nil
            // One presentation budget, never repeated begin/focus calls or
            // polling for a desired result. Debounce waits remain separate.
            await settle(0.35)
            NotificationCenter.default.removeObserver(observation)
            let accepted = field.currentEditor() != nil && window.firstResponder === field.currentEditor()
            if label != "Stock" {
                checks["\(label)-collapsed-native-search-keeps-shared-actual-width-after-focus"] = accepted && hasSharedSearchWidth(field)
            }
            diagnostic("\(label) native search: immediate=\(immediateEditor), beginNotification=\(String(describing: beganAfter)), final=\(accepted), itemEnabled=\(item.isEnabled), fieldEnabled=\(field.isEnabled), editable=\(field.isEditable), frame=\(field.frame), itemToolbarMatches=\(item.toolbar === toolbar), fieldWindow=\(String(describing: field.window)), active=\(app.isActive), key=\(window.isKeyWindow), responder=\(String(describing: window.firstResponder))")
            return accepted
        }
        func install(_ ids: [NSToolbarItem.Identifier], factory: @escaping (NSToolbarItem.Identifier) -> NSToolbarItem?) async {
            delegate.identifiers = ids; delegate.makeItem = factory
            for index in toolbar.items.indices.reversed() { toolbar.removeItem(at: index) }
            for (index, id) in ids.enumerated() { toolbar.insertItem(withItemIdentifier: id, at: index) }
            await settle()
        }
        func menu(_ item: NSToolbarItem) -> NSMenu { item.menuFormRepresentation!.submenu! }
        func groups() -> [[NSToolbarItem.Identifier]] {
            guard let start = toolbar.items.firstIndex(where: { $0.itemIdentifier == .flexibleSpace }) else { return [] }
            var result: [[NSToolbarItem.Identifier]] = [[]]
            for item in toolbar.items.dropFirst(start + 1) {
                if item.itemIdentifier == .space { result.append([]) }
                else { result[result.count - 1].append(item.itemIdentifier) }
            }
            return result
        }
        let service = SteamWorkshopService.shared
        let initialAccountButtons: [NSButton] = [steam.accountButton, pixabay.settingsButton]
        checks["unmounted-online-account-controls-start-with-shared-native-geometry"] = initialAccountButtons.allSatisfy { button in
            let geometry = button.window == nil && button.frame.size == NSSize(width: 32, height: 32)
                && button.bounds.size == NSSize(width: 32, height: 32)
            let imageStyle = button.imagePosition == .imageOnly && button.alignment == .center
                && button.imageScaling == .scaleProportionallyDown && button.symbolConfiguration == nil
            return geometry && imageStyle && button.controlSize == .regular
                && button.bezelStyle == .texturedRounded && button.isBordered
        }
        NotificationCenter.default.post(name: .steamWorkshopModeDidChange, object: nil, userInfo: ["enabled": true, "isDownloads": false])
        await install(steam.browserIdentifiers, factory: steam.makeItem(for:))
        window.center(); window.makeKeyAndOrderFront(nil); app.activate()
        let activationDeadline = Date().addingTimeInterval(2)
        while (!app.isActive || app.keyWindow !== window || app.mainWindow !== window), Date() < activationDeadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        let nativeInputReady = app.activationPolicy() == .regular && app.isActive
            && app.keyWindow === window && app.mainWindow === window && window.isKeyWindow && window.isMainWindow
        checks["remote-toolbar-has-a-real-regular-active-main-key-window"] = nativeInputReady
        guard nativeInputReady else {
            throw CocoaError(.coderInvalidValue, userInfo: [NSLocalizedDescriptionKey:
                "Remote toolbar activation failed: active=\(app.isActive), key=\(window.isKeyWindow), main=\(window.isMainWindow), frame=\(window.frame)"])
        }
        await settle()
        checks["steam-discovery-has-five-native-role-groups-without-empty-spaces"] = groups() == [[.steamAccount, .downloadTasks],
            [.steamTrendingWindow], [.steamSort, .steamFilter], [.steamZoom], [.steamSearch]]
        checks["steam-search-is-the-original-field-in-a-native-search-toolbar-item"] = steam.searchToolbarItem.searchField === steam.searchField
            && steam.searchField.delegate === steam && steam.searchToolbarItem.preferredWidthForSearchField == 220
        checks["expanded-steam-search-renders-the-same-220-point-width-as-online-image-search"] = hasSharedSearchWidth(steam.searchField)
            && steam.searchField.window === window && !steam.searchField.isHiddenOrHasHiddenAncestor
        checks["steam-sort-uses-the-shared-three-line-icon-with-current-value-in-tooltip"] = steam.sortButton.image?.tiffRepresentation == NSImage(systemSymbolName: "line.3.horizontal.decrease", accessibilityDescription: nil)?.tiffRepresentation
            && steam.sortButton.title.isEmpty && steam.sortToolbarItem.toolTip?.contains(service.source.displayName) == true
        let publicMenu = menu(steam.sortToolbarItem)
        publicMenu.performActionForItem(at: SteamWorkshopSource.publicSources.firstIndex(of: .recent)!)
        checks["steam-native-overflow-chooses-the-original-public-source-enum"] = service.source == .recent
            && menu(steam.sortToolbarItem).items[1].state == .on
        service.source = .featured; steam.syncTrendingWindowPopup()
        menu(steam.trendingWindowToolbarItem).performActionForItem(at: SteamWorkshopTrendingWindow.allCases.firstIndex(of: .month)!)
        checks["steam-native-overflow-chooses-the-original-time-window-enum"] = service.trendingWindow == .month
        service.source = .mySubscriptions; steam.syncPersonalListPopup(); steam.syncSortPopup()
        await install(steam.browserIdentifiers, factory: steam.makeItem(for:))
        checks["steam-personal-subpage-keeps-return-and-all-original-controls"] = groups() == [[.steamAuthorBack], [.steamAccount, .downloadTasks],
            [.steamPersonalList], [.steamSort, .steamFilter], [.steamZoom], [.steamSearch]] && steam.authorBackToolbarItem.isEnabled
            && steam.authorBackButton.toolTip == "返回创意工坊"
        menu(steam.personalListToolbarItem).performActionForItem(at: SteamWorkshopSource.personalSources.firstIndex(of: .myFavorites)!)
        menu(steam.sortToolbarItem).performActionForItem(at: SteamWorkshopPersonalSort.allCases.firstIndex(of: .fileSize)!)
        checks["steam-personal-overflow-retains-steam-favorites-and-personal-sort"] = service.source == .myFavorites && service.personalSort == .fileSize
            && steam.personalListButton.title == "Steam 收藏" && menu(steam.personalListToolbarItem).items[1].title == "Steam 收藏"
        service.steamAuth.phase = .signedOut; steam.configureAuthItems()
        checks["signed-out-avatar-does-not-expose-personal-subscriptions"] = !menu(steam.accountToolbarItem).items.contains { $0.title == "我的订阅" }
        let heldLogin = menu(steam.accountToolbarItem).items[0]
        service.steamAuth.phase = .connecting; steam.configureAuthItems()
        if let action = heldLogin.action { NSApp.sendAction(action, to: heldLogin.target, from: heldLogin) }
        checks["steam-auth-busy-disables-button-item-overflow-and-held-login"] = !steam.accountButton.isEnabled
            && !steam.accountToolbarItem.isEnabled && steam.accountToolbarItem.menuFormRepresentation?.isEnabled == false && service.loginCalls == 0
        service.steamAuth.phase = .online; steam.configureAuthItems()
        if let action = heldLogin.action { NSApp.sendAction(action, to: heldLogin.target, from: heldLogin) }
        checks["held-signed-out-login-cannot-become-switch-account-after-signin"] = service.loginCalls == 0
        service.steamAuth.phase = .signedOut; steam.configureAuthItems()
        menu(steam.accountToolbarItem).performActionForItem(at: 0)
        checks["steam-native-overflow-retains-the-original-login-entry"] = service.loginCalls == 1
        service.steamAuth.phase = .online; steam.configureAuthItems()
        let signedInMenu = menu(steam.accountToolbarItem)
        func perform(_ menu: NSMenu, _ title: String) {
            precondition(menu.items.contains { $0.title == title }, "Missing original account command: \(title)")
            menu.performActionForItem(at: menu.items.firstIndex { $0.title == title }!)
        }
        perform(signedInMenu, "我的订阅")
        checks["signed-in-avatar-enters-the-existing-personal-browser-owner"] = service.subscriptionsCalls == 1
        service.steamAuth.phase = .connecting; steam.configureAuthItems()
        perform(signedInMenu, "退出登录")
        checks["held-current-account-logout-is-temporarily-revoked-during-auth-busy"] = service.logoutCalls == 0
        service.steamAuth.phase = .online; service.steamAuth.accountName = "Updated same account"
        steam.configureAuthItems()
        perform(signedInMenu, "切换账号"); perform(signedInMenu, "退出登录")
        checks["steam-native-overflow-retains-switch-account-and-signout"] = service.loginCalls == 2 && service.logoutCalls == 1
        checks["same-account-auth-and-metadata-echo-preserve-held-switch-and-signout"] = service.loginCalls == 2 && service.logoutCalls == 1
        service.steamAuth.steamId = "987654321"; steam.configureAuthItems()
        perform(signedInMenu, "切换账号"); perform(signedInMenu, "退出登录")
        checks["held-account-a-menu-cannot-switch-or-sign-out-account-b"] = service.loginCalls == 2 && service.logoutCalls == 1
        perform(signedInMenu, "我的订阅")
        checks["held-personal-entry-cannot-open-another-account"] = service.subscriptionsCalls == 1
        let currentAccountMenu = menu(steam.accountToolbarItem)
        perform(currentAccountMenu, "切换账号"); perform(currentAccountMenu, "退出登录")
        checks["fresh-account-b-menu-retains-original-switch-and-signout-commands"] = service.loginCalls == 3 && service.logoutCalls == 2
        service.steamAuth.phase = .signedOut
        perform(currentAccountMenu, "我的订阅")
        checks["held-personal-entry-is-revoked-after-signout"] = service.subscriptionsCalls == 1
        service.steamAuth.phase = .online
        perform(currentAccountMenu, "我的订阅")
        checks["same-account-current-personal-entry-remains-usable"] = service.subscriptionsCalls == 2
        service.isBrowsingAuthorWorkshop = true; steam.configureAuthorBackItem()
        await install(steam.browserIdentifiers, factory: steam.makeItem(for:))
        checks["steam-author-subroute-has-return-without-unsupported-sort-filter-groups"] = groups() == [[.steamAuthorBack], [.steamAccount, .downloadTasks],
            [.steamZoom], [.steamSearch]]
        let back = steam.authorBackToolbarItem.menuFormRepresentation!
        NSApp.sendAction(back.action!, to: back.target, from: back)
        checks["steam-native-overflow-returns-through-the-original-author-route"] = service.backCalls == 1
        let tasks = downloadItem.menuFormRepresentation!
        popoverPhase = "first-task-show"
        let firstTaskDidShow = await afterPopoverEvent(NSPopover.didShowNotification,
            matching: { $0.contentViewController is DownloadTasksContentController }) {
            NSApp.sendAction(tasks.action!, to: tasks.target, from: tasks)
        }
        diagnostic("First task: controllerShown=\(downloadController.isShown), popover={\(popoverFacts(taskPopover))}")
        toolbarFacts("First task toolbar")
        checks["steam-native-task-overflow-keeps-the-original-task-owner-and-real-anchor"] = firstTaskDidShow
            && downloadController.isShown
            && taskPopover?.contentViewController?.view.window?.isVisible == true
            && taskPopover.map { didShowCounts[ObjectIdentifier($0), default: 0] > 0 } == true
        popoverPhase = "first-task-close"
        let firstTaskDidClose = await afterPopoverEvent(NSPopover.didCloseNotification, matching: { $0 === taskPopover }) {
            downloadController.close()
        }
        checks["native-task-close-completes-before-the-next-toolbar-action"] = firstTaskDidClose
            && !downloadController.isShown
        diagnostic("First task close: controllerShown=\(downloadController.isShown), popover={\(popoverFacts(taskPopover))}")
        steam.searchField.stringValue = "first"; steam.controlTextDidChange(.init(name: NSControl.textDidChangeNotification, object: steam.searchField))
        steam.searchField.stringValue = "last"; steam.controlTextDidChange(.init(name: NSControl.textDidChangeNotification, object: steam.searchField))
        await settle(0.30)
        checks["steam-original-search-debounce-merges-to-the-latest-query"] = service.queries == ["last"]
        if checks["steam-original-search-debounce-merges-to-the-latest-query"] != true {
            diagnostic("Steam debounce: queries=\(service.queries), pending=\(steam.searchDebounceWorkItem != nil), field=\(steam.searchField.stringValue)")
        }
        let beforeNavigation = service.queries.count
        steam.searchField.stringValue = "old discovery draft"
        steam.controlTextDidChange(.init(name: NSControl.textDidChangeNotification, object: steam.searchField))
        service.navigationVersion += 1
        service.browserQuery = "new author context"
        await settle(0.30)
        checks["steam-pending-discovery-query-cannot-filter-a-new-author-or-feed"] = service.queries.count == beforeNavigation + 1
            && service.browserQuery == "new author context" && steam.searchDebounceWorkItem == nil
        steam.searchField.stringValue = "fresh author draft"
        steam.controlTextDidChange(.init(name: NSControl.textDidChangeNotification, object: steam.searchField))
        await settle(0.30)
        checks["steam-current-navigation-keeps-the-original-search-consumer"] = service.queries.count == beforeNavigation + 2
            && service.browserQuery == "fresh author draft"
        let beforeLeavingSteam = service.queries.count
        steam.searchField.stringValue = "retired page draft"
        steam.controlTextDidChange(.init(name: NSControl.textDidChangeNotification, object: steam.searchField))
        NotificationCenter.default.post(name: .steamWorkshopModeDidChange, object: nil, userInfo: ["enabled": false])
        await settle(0.30)
        checks["steam-leaving-retires-the-deadline-without-dropping-the-unsubmitted-draft"] = service.queries.count == beforeLeavingSteam
            && steam.searchDebounceWorkItem == nil && steam.pendingSearchInput?.text == "retired page draft"
        NotificationCenter.default.post(name: .steamWorkshopModeDidChange, object: nil, userInfo: ["enabled": true, "isDownloads": false])
        await settle(0.30)
        checks["steam-return-to-the-same-navigation-consumes-the-draft-once"] = service.queries.count == beforeLeavingSteam + 1
            && service.browserQuery == "retired page draft" && steam.searchField.stringValue == "retired page draft"
            && steam.searchDebounceWorkItem == nil && steam.pendingSearchInput == nil
        let beforeDownloads = service.queries.count
        steam.searchField.stringValue = "draft before downloads"
        steam.controlTextDidChange(.init(name: NSControl.textDidChangeNotification, object: steam.searchField))
        NotificationCenter.default.post(name: .steamWorkshopModeDidChange, object: nil, userInfo: ["enabled": false])
        await settle(0.30)
        checks["steam-downloads-does-not-submit-the-previous-browser-draft"] = service.queries.count == beforeDownloads
        NotificationCenter.default.post(name: .steamWorkshopModeDidChange, object: nil, userInfo: ["enabled": true, "isDownloads": false])
        checks["steam-return-from-downloads-keeps-the-same-browser-draft"] = service.queries.count == beforeDownloads + 1
            && service.browserQuery == "draft before downloads" && steam.pendingSearchInput == nil
        let beforeChangedNavigation = service.queries.count
        steam.searchField.stringValue = "obsolete navigation draft"
        steam.controlTextDidChange(.init(name: NSControl.textDidChangeNotification, object: steam.searchField))
        NotificationCenter.default.post(name: .steamWorkshopModeDidChange, object: nil, userInfo: ["enabled": false])
        service.navigationVersion += 1
        service.browserQuery = "new feed query"
        NotificationCenter.default.post(name: .steamWorkshopModeDidChange, object: nil, userInfo: ["enabled": true, "isDownloads": false])
        await settle(0.30)
        checks["steam-return-after-real-navigation-retires-the-previous-draft"] = service.queries.count == beforeChangedNavigation + 1
            && service.browserQuery == "new feed query" && steam.searchField.stringValue == "new feed query"
            && steam.pendingSearchInput == nil
        let beforeSamePage = service.requestQueries.count
        let beforeSamePageProjection = service.displayedQueryUpdates.count
        steam.searchField.stringValue = "draft with personal order"
        steam.controlTextDidChange(.init(name: NSControl.textDidChangeNotification, object: steam.searchField))
        menu(steam.sortToolbarItem).performActionForItem(at: SteamWorkshopPersonalSort.allCases.firstIndex(of: .name)!)
        await settle(0.30)
        checks["steam-same-page-sort-consumes-draft-with-one-final-query"] = service.requestQueries.count == beforeSamePage + 1
            && service.requestQueries.last == "draft with personal order" && service.personalSort == .name
            && service.displayedQueryUpdates.count == beforeSamePageProjection + 1
            && service.displayedQueryUpdates.last == "draft with personal order"
        let beforeHiddenSteam = service.requestQueries.count
        steam.searchField.stringValue = "steam hidden draft"
        steam.controlTextDidChange(.init(name: NSControl.textDidChangeNotification, object: steam.searchField))
        window.orderOut(nil); await settle(0.30)
        checks["steam-hidden-window-retains-draft-without-starting-a-query"] = service.requestQueries.count == beforeHiddenSteam
            && steam.pendingSearchInput?.text == "steam hidden draft"
        window.makeKeyAndOrderFront(nil); await settle(0.30)
        checks["steam-window-restoration-submits-the-draft-once"] = service.requestQueries.count == beforeHiddenSteam + 1
            && service.browserQuery == "steam hidden draft" && steam.pendingSearchInput == nil
        let beforeMiniSteam = service.requestQueries.count
        steam.searchField.stringValue = "steam minimized draft"
        steam.controlTextDidChange(.init(name: NSControl.textDidChangeNotification, object: steam.searchField))
        window.miniaturize(nil); await settle(0.30)
        checks["steam-minimized-window-keeps-the-deferred-query-unsubmitted"] = window.isMiniaturized
            && service.requestQueries.count == beforeMiniSteam && steam.pendingSearchInput?.text == "steam minimized draft"
        window.deminiaturize(nil); await settle(0.30)
        checks["steam-deminiaturizing-submits-the-draft-once"] = service.requestQueries.count == beforeMiniSteam + 1
            && service.browserQuery == "steam minimized draft"
        steam.searchField.stringValue = "account a draft"
        steam.controlTextDidChange(.init(name: NSControl.textDidChangeNotification, object: steam.searchField))
        service.steamAuth.steamId = "account-after-draft"
        let beforeAccountChange = service.requestQueries.count
        await settle(0.30)
        checks["steam-account-change-revokes-a-draft-even-without-page-navigation"] = service.requestQueries.count == beforeAccountChange
            && steam.pendingSearchInput == nil
        service.source = .featured
        await install(steam.browserIdentifiers, factory: steam.makeItem(for:))
        window.setContentSize(NSSize(width: 600, height: 500)); await settle()
        checks["steam-narrow-native-toolbar-overflows-with-equivalent-source-actions"] = (toolbar.visibleItems?.count ?? 0) < toolbar.items.count
            && [steam.accountToolbarItem, downloadItem, steam.trendingWindowToolbarItem, steam.sortToolbarItem, steam.filterToolbarItem].allSatisfy { $0.menuFormRepresentation != nil }
        window.makeKeyAndOrderFront(nil)
        checks["steam-collapsed-search-expands-the-original-native-field"] = await searchInteraction(steam.searchToolbarItem, label: "Steam", begin: steam.focusSearch)
        // Deliberately force both items into native overflow. This is an API
        // placement regression, not a claim about the product minimum width.
        window.setContentSize(NSSize(width: 160, height: 500)); await settle()
        toolbarFacts("Forced overflow")
        func isDetachedActionItem(_ item: NSToolbarItem) -> Bool {
            let belongsToToolbar: Bool = item.toolbar === toolbar && toolbar.items.contains { $0 === item }
            let detached: Bool = item.view?.window == nil
            let hasPositiveFrame: Bool
            if let view = item.view { hasPositiveFrame = view.frame.width > 0 && view.frame.height > 0 }
            else { hasPositiveFrame = false }
            let menuEnabled: Bool = item.menuFormRepresentation?.isEnabled == true
            let hasAction: Bool = item.menuFormRepresentation?.action != nil
            return belongsToToolbar && detached && hasPositiveFrame && menuEnabled && hasAction
        }
        let actualOverflow: Bool = (toolbar.visibleItems?.count ?? 0) < toolbar.items.count
        let detachedFilter: Bool = isDetachedActionItem(steam.filterToolbarItem)
        let detachedTasks: Bool = isDetachedActionItem(downloadItem)
        checks["forced-native-overflow-really-detaches-filter-and-task-views"] = actualOverflow && detachedFilter && detachedTasks
        if let content = window.contentView {
            let stockPopover = NSPopover(), contentController = NSViewController()
            contentController.view = NSView(frame: NSRect(x: 0, y: 0, width: 80, height: 40))
            stockPopover.contentViewController = contentController
            let oldEdge = NSRect(x: max(0, content.bounds.maxX - 32), y: content.bounds.maxY, width: 1, height: 1)
            popoverPhase = "old-edge-rect"
            let oldEdgeDidShow = await afterPopoverEvent(NSPopover.didShowNotification, matching: { $0 === stockPopover }) {
                stockPopover.show(relativeTo: oldEdge, of: content, preferredEdge: .maxY)
            }
            // bounds.maxY is not necessarily outside native visibleRect in a
            // unified toolbar window. This is observed geometry, not a claim
            // that the former product anchor must fail on every macOS layout.
            diagnostic("Old edge rect: rect=\(oldEdge), visibleRect=\(content.visibleRect), intersects=\(oldEdge.intersects(content.visibleRect)), didShow=\(oldEdgeDidShow), content={\(viewFacts(content))}, popover={\(popoverFacts(stockPopover))}")
            if stockPopover.isShown {
                popoverPhase = "old-edge-close"
                checks["old-edge-stock-popover-closes-if-native-presentation-was-accepted"] = await afterPopoverEvent(
                    NSPopover.didCloseNotification, matching: { $0 === stockPopover }, perform: stockPopover.close)
            }
            let inside = NSRect(x: content.bounds.midX, y: content.bounds.midY, width: 1, height: 1)
            popoverPhase = "stock-inside-show"
            let insideDidShow = await afterPopoverEvent(NSPopover.didShowNotification, matching: { $0 === stockPopover }) {
                stockPopover.show(relativeTo: inside, of: content, preferredEdge: .maxY)
            }
            checks["stock-content-view-anchor-displays-at-a-real-inside-rectangle"] = inside.intersects(content.visibleRect)
                && insideDidShow && stockPopover.isShown && stockPopover.contentViewController?.view.window?.isVisible == true
                && didShowCounts[ObjectIdentifier(stockPopover), default: 0] > 0
            diagnostic("Stock inside rect: rect=\(inside), didShow=\(insideDidShow), popover={\(popoverFacts(stockPopover))}")
            popoverPhase = "stock-inside-close"
            let insideDidClose = await afterPopoverEvent(NSPopover.didCloseNotification,
                matching: { $0 === stockPopover }, perform: stockPopover.close)
            checks["stock-content-view-anchor-closes-after-its-native-lifecycle-completes"] = insideDidClose && !stockPopover.isShown
        } else { checks["stock-content-view-anchor-displays-at-a-real-inside-rectangle"] = false }
        let filter = steam.filterToolbarItem.menuFormRepresentation!
        popoverPhase = "filter-show"
        let filterDidShow = await afterPopoverEvent(NSPopover.didShowNotification, matching: { $0 === steam.filterPanelPopover }) {
            NSApp.sendAction(filter.action!, to: filter.target, from: filter)
        }
        diagnostic("Filter display: popover={\(popoverFacts(steam.filterPanelPopover))}")
        checks["steam-overflow-opens-the-original-filter-panel-with-a-real-window-anchor"] = filterDidShow && steam.filterPanelPopover.isShown
            && steam.filterPanelPopover.contentViewController?.view.window?.isVisible == true
            && didShowCounts[ObjectIdentifier(steam.filterPanelPopover), default: 0] > 0
        if let filterView = steam.filterPanelPopover.contentViewController?.view {
            let buttons = descendants(filterView, NSButton.self)
            let beforeDraftFilter = service.requestQueries.count
            let beforeDraftFilterProjection = service.displayedQueryUpdates.count
            steam.searchField.stringValue = "draft with facets"
            steam.controlTextDidChange(.init(name: NSControl.textDidChangeNotification, object: steam.searchField))
            buttons.first { $0.title == "动漫" }!.performClick(nil)
            await settle(0.30)
            checks["steam-native-facet-merges-the-pending-draft-with-one-query"] = service.requestQueries.count == beforeDraftFilter + 1
                && service.browserQuery == "draft with facets" && service.facetFilters.themes == [.anime]
                && service.displayedQueryUpdates.count == beforeDraftFilterProjection + 1
                && service.displayedQueryUpdates.last == "draft with facets"
            buttons.first { $0.title == "风景" }!.performClick(nil)
            checks["steam-shared-native-checkboxes-preserve-multiselect-source-owner-and-open-panel"] = service.facetFilters.themes == [.anime, .landscape]
                && steam.filterPanelPopover.isShown && steam.filterPanelPopover.contentSize.width == 400
                && descendants(filterView, NSGridView.self).map(\.numberOfColumns) == [4, 4, 2, 3]
            let beforeDraftClear = service.requestQueries.count
            let beforeDraftClearProjection = service.displayedQueryUpdates.count
            steam.searchField.stringValue = "draft with clear"
            steam.controlTextDidChange(.init(name: NSControl.textDidChangeNotification, object: steam.searchField))
            buttons.first { $0.title == "清空筛选" }!.performClick(nil)
            await settle(0.30)
            checks["steam-native-clear-merges-draft-with-one-final-query"] = service.requestQueries.count == beforeDraftClear + 1
                && service.browserQuery == "draft with clear"
                && service.displayedQueryUpdates.count == beforeDraftClearProjection + 1
                && service.displayedQueryUpdates.last == "draft with clear"
            checks["steam-shared-clear-keeps-original-service-and-native-checkboxes"] = service.facetFilters.isEmpty && service.browserContentMode.isAll
                && !buttons.first { $0.title == "清空筛选" }!.isEnabled && steam.filterPanelPopover.isShown
        }
        if !steam.filterPanelPopover.isShown {
            diagnostic("Steam filter: active=\(app.isActive), key=\(window.isKeyWindow), sourceActive=\(steam.isSteamWorkshopMode), author=\(service.isBrowsingAuthorWorkshop), enabled=\(filter.isEnabled), buttonWindow=\(String(describing: steam.filterButton.window)), hostVisible=\(window.isVisible)")
        }
        popoverPhase = "filter-close"
        let filterDidClose = await afterPopoverEvent(NSPopover.didCloseNotification, matching: { $0 === steam.filterPanelPopover },
            perform: steam.filterPanelPopover.close)
        checks["native-filter-close-completes-before-the-next-toolbar-action"] = filterDidClose && !steam.filterPanelPopover.isShown
        diagnostic("Filter close: popover={\(popoverFacts(steam.filterPanelPopover))}")
        let account = service.steamAuth.steamId!
        func job(_ id: String, item: String, state: SteamDownloadJobState, account: String, ordinal: Int) -> SteamDownloadJob {
            SteamDownloadJob(id: id, workshopItemId: item, title: id, state: state, attempt: 1, queueOrdinal: ordinal,
                accountSteamId: account, stagingPath: nil, failureMessage: nil, createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 1))
        }
        service.downloadJobStore.jobs = [job("active", item: "123456", state: .running, account: account, ordinal: 0),
            job("failed", item: "123457", state: .failed, account: account, ordinal: 1),
            job("foreign", item: "123458", state: .failed, account: "other-account", ordinal: 0)]
        service.downloadJobStore.history = [.init(jobID: "history", workshopItemId: "123459", title: "Completed history",
            accountSteamId: account, attempt: 1, outcome: .completed, failureMessage: nil, recordID: nil, terminalAt: Date(timeIntervalSince1970: 2)),
            .init(jobID: "failed", workshopItemId: "123457", title: "Failed history", accountSteamId: account,
                attempt: 1, outcome: .failed, failureMessage: "controlled failure", recordID: nil, terminalAt: Date(timeIntervalSince1970: 3)),
            .init(jobID: "foreign", workshopItemId: "123458", title: "Other account history", accountSteamId: "other-account",
                attempt: 1, outcome: .failed, failureMessage: "other failure", recordID: nil, terminalAt: Date(timeIntervalSince1970: 4))]
        let priorTaskShows = taskPopover.map { didShowCounts[ObjectIdentifier($0), default: 0] } ?? 0
        popoverPhase = "overflow-task-show"
        let overflowTaskDidShow = await afterPopoverEvent(NSPopover.didShowNotification, matching: { $0 === taskPopover }) {
            NSApp.sendAction(tasks.action!, to: tasks.target, from: tasks)
        }
        diagnostic("Overflow task display: controllerShown=\(downloadController.isShown), priorDidShow=\(priorTaskShows), popover={\(popoverFacts(taskPopover))}")
        let taskRoot = taskPopover?.contentViewController?.view
        let retries = taskRoot.flatMap { descendants($0, NSButton.self).first { $0.title == "重试全部失败" } }
        let clears = taskRoot.flatMap { descendants($0, NSButton.self).first { $0.title == "清空历史" } }
        checks["real-native-task-popover-opens-from-a-detached-overflow-item"] = overflowTaskDidShow && downloadController.isShown
            && taskRoot?.window?.isVisible == true
            && taskPopover.map { didShowCounts[ObjectIdentifier($0), default: 0] > priorTaskShows } == true
        checks["real-task-content-displays-local-jobs-and-all-account-history"] = taskRoot.map {
            descendants($0, NSTextField.self).contains { $0.stringValue == "下载任务 · 4 项" }
        } == true && retries?.isEnabled == true && clears?.isEnabled == true
        service.steamAuth.steamId = nil; service.steamAuth.phase = .signedOut; await settle()
        checks["signed-out-task-panel-keeps-local-history-without-login"] = taskRoot.map {
            descendants($0, NSTextField.self).contains { $0.stringValue == "下载任务 · 4 项" }
        } == true && retries?.isEnabled == false && service.loginCalls == 3
        service.steamAuth.steamId = account; service.steamAuth.phase = .online; await settle()
        service.steamAuth.steamId = "other-account"
        retries?.performClick(nil)
        checks["held-task-content-cannot-retry-a-new-account-before-its-ui-echo"] = service.retryRequests.isEmpty
            && service.discardedJobs.isEmpty && service.downloadJobStore.clearedAccounts.isEmpty
        service.steamAuth.steamId = account; await settle()
        retries?.performClick(nil)
        let failedRow = taskRoot.flatMap { descendants($0, DownloadTaskRowView.self).first { $0.displayedTask?.id.reference.sourceID == "123457" } }
        let abandon = failedRow.flatMap { descendants($0, NSButton.self).first { $0.toolTip == "放弃任务" } }
        abandon?.performClick(nil)
        clears?.performClick(nil)
        checks["real-task-buttons-route-fixed-failed-work-and-clear-only-local-history"] = service.retryRequests == ["123457"]
            && service.discardedJobs == ["failed"] && service.downloadJobStore.clearedAccounts == ["all-local"]
            && service.downloadJobStore.jobs.first { $0.id == "active" }?.state == .running
            && service.downloadJobStore.jobs.first { $0.id == "foreign" }?.accountSteamId == "other-account"
        let rows = taskRoot.map { descendants($0, DownloadTaskRowView.self) } ?? []
        let leasesBeforeClose = taskCommands.progressLeases, endedBeforeClose = taskCommands.endedProgressLeases
        diagnostic("Task close precondition: root={\(viewFacts(taskRoot))}, rows=\(rows.count), progressLeases=\(leasesBeforeClose), controllerShown=\(downloadController.isShown)")
        popoverPhase = "overflow-task-close"
        let overflowTaskDidClose = await afterPopoverEvent(NSPopover.didCloseNotification, matching: { $0 === taskPopover }) {
            downloadController.close()
        }
        diagnostic("Task close result: controllerShown=\(downloadController.isShown), remainingRows=\(taskRoot.map { descendants($0, DownloadTaskRowView.self).count } ?? -1), progressLeases=\(taskCommands.progressLeases), popover={\(popoverFacts(taskPopover))}")
        checks["closing-the-real-task-popover-revokes-row-observation"] = overflowTaskDidClose && !downloadController.isShown
            && !rows.isEmpty && rows.allSatisfy { $0.displayedTask == nil } && leasesBeforeClose > 0
            && taskCommands.progressLeases == 0 && taskCommands.endedProgressLeases > endedBeforeClose
            && taskRoot.map { descendants($0, DownloadTaskRowView.self).isEmpty } == true
        window.setContentSize(NSSize(width: 600, height: 500)); await settle()
        NotificationCenter.default.post(name: .steamWorkshopModeDidChange, object: nil, userInfo: ["enabled": false])
        NotificationCenter.default.post(name: .pixabayModeDidChange, object: nil, userInfo: ["enabled": true])
        await install(pixabay.pixabayIdentifiers, factory: pixabay.makeItem(for:))
        checks["pixabay-has-five-native-groups-and-one-settings-download-source-group"] = groups() == [[.pixabaySettings, .downloadTasks],
            [.pixabayFilter], [.pixabayOrder], [.pixabayZoom], [.pixabaySearch]]
        window.setContentSize(NSSize(width: 1200, height: 500)); await settle()
        let accountImage = NSImage(systemSymbolName: "person.crop.circle", accessibilityDescription: "API Key")
        let accountButton = pixabay.settingsToolbarItem.view as? NSButton
        checks["pixabay-account-symbol-matches-other-online-account-controls-with-the-original-key-entry"] = accountButton?.image != nil && accountImage != nil
            && accountButton?.image?.tiffRepresentation == accountImage?.tiffRepresentation
            && pixabay.settingsToolbarItem.toolTip == "更改 Pixabay API Key"
        for (source, button) in [("Pixabay", accountButton), ("Steam", steam.accountButton as NSButton?)] {
            guard let button else { diagnostic("Mounted account \(source): missing NSButton"); continue }
            diagnostic("Mounted account \(source): frame=\(button.frame), bounds=\(button.bounds), intrinsic=\(button.intrinsicContentSize), fitting=\(button.fittingSize), controlSize=\(button.controlSize.rawValue), imagePosition=\(button.imagePosition.rawValue), alignment=\(button.alignment.rawValue), imageScaling=\(button.imageScaling.rawValue), imageSize=\(String(describing: button.image?.size)), symbolConfig=\(String(describing: button.symbolConfiguration)), bezel=\(button.bezelStyle.rawValue), bordered=\(button.isBordered), mounted=\(button.window === window), hidden=\(button.isHiddenOrHasHiddenAncestor), superview=\(String(describing: button.superview)), autoresizingMask=\(button.autoresizingMask.rawValue), translatesMask=\(button.translatesAutoresizingMaskIntoConstraints)")
            diagnostic("Mounted account \(source) layout: horizontal=\(button.constraintsAffectingLayout(for: .horizontal)), vertical=\(button.constraintsAffectingLayout(for: .vertical))")
        }
        checks["mounted-pixabay-account-keeps-the-steam-account-hitbox-and-native-alignment"] = accountButton.map { button in
            button.window === window && button.bounds.width > 0 && button.bounds.size == steam.accountButton.bounds.size
                && button.controlSize == steam.accountButton.controlSize
                && button.imagePosition == .imageOnly && button.imagePosition == steam.accountButton.imagePosition
                && button.alignment == .center && button.alignment == steam.accountButton.alignment
                && button.imageScaling == steam.accountButton.imageScaling && button.symbolConfiguration == nil && steam.accountButton.symbolConfiguration == nil
                && button.bezelStyle == .texturedRounded && steam.accountButton.bezelStyle == .texturedRounded
                && button.isBordered && steam.accountButton.isBordered
        } == true
        let pixabayService = PixabayService.shared
        checks["pixabay-search-is-the-original-field-in-a-native-search-toolbar-item"] = pixabay.searchToolbarItem.searchField === pixabay.searchField
            && pixabay.searchField.delegate === pixabay && pixabay.searchToolbarItem.preferredWidthForSearchField == 220
        checks["expanded-pixabay-search-renders-the-same-220-point-width-as-online-image-search"] = hasSharedSearchWidth(pixabay.searchField)
            && pixabay.searchField.window === window && !pixabay.searchField.isHiddenOrHasHiddenAncestor
        var pixabayPopup: NSPopover?
        let pixabayShown = await afterPopoverEvent(NSPopover.didShowNotification, matching: {
            guard $0.contentViewController is WallpaperFilterPanelController else { return false }
            pixabayPopup = $0; return true
        }) { (pixabay.filterToolbarItem.view as! NSButton).performClick(nil) }
        if let popup = pixabayPopup, let panel = popup.contentViewController?.view {
            let buttons = descendants(panel, NSButton.self)
            buttons.first { $0.title == "自然" }!.performClick(nil)
            buttons.first { $0.title == "动画" }!.performClick(nil)
            checks["pixabay-native-filter-applies-real-source-fields-with-open-shared-geometry"] = pixabayShown && popup.isShown
                && popup.contentSize.width == 400 && pixabayService.currentParams.category == .nature
                && pixabayService.currentParams.videoType == .animation
                && descendants(panel, NSGridView.self).map(\.numberOfColumns) == [3, 3, 2, 2]
                && PixabayCategory.allCases.count == 21 && buttons.contains { $0.title == "背景" } && buttons.contains { $0.title == "时尚" }
            buttons.first { $0.title == "清空筛选" }!.performClick(nil)
            checks["pixabay-native-clear-resets-only-source-filters-without-closing-panel"] = !pixabayService.currentParams.hasFilters
                && pixabayService.currentParams.safeSearch && popup.isShown && !buttons.first { $0.title == "清空筛选" }!.isEnabled
            _ = await afterPopoverEvent(NSPopover.didCloseNotification, matching: { $0 === popup }, perform: popup.close)
        } else { checks["pixabay-native-filter-applies-real-source-fields-with-open-shared-geometry"] = false }
        window.setContentSize(NSSize(width: 600, height: 500)); await settle()
        checks["pixabay-sort-is-native-icon-menu-without-retired-segmented-control"] = pixabay.orderToolbarItem.view == nil
            && pixabay.orderToolbarItem.image?.tiffRepresentation == NSImage(systemSymbolName: "line.3.horizontal.decrease", accessibilityDescription: nil)?.tiffRepresentation
            && pixabay.orderToolbarItem.menu.items.map(\.title) == PixabayOrder.allCases.map(\.displayName)
        perform(menu(pixabay.filterToolbarItem), "自然")
        menu(pixabay.orderToolbarItem).performActionForItem(at: PixabayOrder.allCases.firstIndex(of: .latest)!)
        checks["pixabay-native-overflow-uses-original-category-and-order-enums"] = pixabayService.toolbarCategory == .nature
            && pixabayService.currentParams.category == .nature && pixabayService.currentParams.order == .latest
            && menu(pixabay.filterToolbarItem).items.first { $0.title == "自然" }?.state == .on
            && pixabay.filterToolbarItem.view is NSButton
        var apiChanges = 0, apiClears = 0
        let change = NotificationCenter.default.addObserver(forName: .pixabayShowAPIKeySettings, object: nil, queue: .main) { _ in MainActor.assumeIsolated { apiChanges += 1 } }
        let clear = NotificationCenter.default.addObserver(forName: .pixabayClearAPIKey, object: nil, queue: .main) { _ in MainActor.assumeIsolated { apiClears += 1 } }
        let apiMenu = menu(pixabay.settingsToolbarItem)
        apiMenu.performActionForItem(at: 0); apiMenu.performActionForItem(at: 2)
        checks["pixabay-native-overflow-retains-both-original-api-settings-notifications"] = apiChanges == 1 && apiClears == 1
        checks["pixabay-toolbar-retires-manual-refresh-and-keeps-shared-download-entry"] =
            !toolbar.items.contains { $0.itemIdentifier.rawValue.lowercased().contains("refresh") }
            && toolbar.items.contains { $0 === downloadItem } && pixabayService.refreshes == 0
        await settle()
        let filterBeforeTyping = pixabay.filterToolbarItem.menuFormRepresentation
        let orderBeforeTyping = pixabay.orderToolbarItem.menu
        pixabay.searchField.stringValue = "first"; pixabay.controlTextDidChange(.init(name: NSControl.textDidChangeNotification, object: pixabay.searchField))
        pixabay.searchField.stringValue = "last"; pixabay.controlTextDidChange(.init(name: NSControl.textDidChangeNotification, object: pixabay.searchField))
        let priorSearchCount = pixabayService.searches.count
        await settle(0.05)
        checks["pixabay-draft-typing-only-syncs-search-without-rebuilding-filter-or-sort-menus"] = pixabay.searchField.stringValue == "last"
            && pixabay.filterToolbarItem.menuFormRepresentation === filterBeforeTyping && pixabay.orderToolbarItem.menu === orderBeforeTyping
            && pixabayService.searches.count == priorSearchCount
        await settle(0.45)
        checks["pixabay-original-search-debounce-merges-to-the-latest-query"] = pixabayService.toolbarQuery == "last"
            && pixabayService.searches.count == priorSearchCount + 1 && pixabayService.searches.last?.query == "last"
        if checks["pixabay-original-search-debounce-merges-to-the-latest-query"] != true {
            diagnostic("Pixabay debounce: prior=\(priorSearchCount), count=\(pixabayService.searches.count), queries=\(pixabayService.searches.map(\.query)), field=\(pixabay.searchField.stringValue), context=\(pixabayService.toolbarQuery)")
        }
        let beforeImmediateCategory = pixabayService.searches.count
        let beforeCategoryMenu = pixabay.filterToolbarItem.menuFormRepresentation
        pixabay.searchField.stringValue = "draft with category"
        pixabay.controlTextDidChange(.init(name: NSControl.textDidChangeNotification, object: pixabay.searchField))
        perform(menu(pixabay.filterToolbarItem), "全部")
        await settle(0.45)
        checks["pixabay-immediate-category-consumes-the-current-draft-without-a-second-debounce-request"] =
            pixabayService.searches.count == beforeImmediateCategory + 1 && pixabayService.searches.last?.query == "draft with category"
            && pixabayService.searches.last?.category == .all
            && pixabay.filterToolbarItem.menuFormRepresentation !== beforeCategoryMenu
            && menu(pixabay.filterToolbarItem).items.first { $0.title == "全部" }?.state == .on
        let beforeImmediateOrder = pixabayService.searches.count
        pixabay.searchField.stringValue = "draft with order"
        pixabay.controlTextDidChange(.init(name: NSControl.textDidChangeNotification, object: pixabay.searchField))
        menu(pixabay.orderToolbarItem).performActionForItem(at: PixabayOrder.allCases.firstIndex(of: .popular)!)
        await settle(0.45)
        checks["pixabay-immediate-order-consumes-the-current-draft-without-a-second-debounce-request"] =
            pixabayService.searches.count == beforeImmediateOrder + 1 && pixabayService.searches.last?.query == "draft with order"
            && pixabayService.searches.last?.order == .popular
        let countBeforeSourceEcho = pixabayService.searches.count
        pixabayService.toolbarCategory = .all
        pixabayService.currentParams.order = .popular
        pixabayService.toolbarQuery = "external context"
        await settle()
        checks["pixabay-source-echo-updates-category-order-search-and-overflow-without-requesting"] = pixabayService.searches.count == countBeforeSourceEcho
            && menu(pixabay.filterToolbarItem).items.first { $0.title == "全部" }?.state == .on
            && pixabay.orderToolbarItem.menu.items.first { $0.state == .on }?.title == PixabayOrder.popular.displayName
            && pixabay.searchField.stringValue == "external context"
            && menu(pixabay.filterToolbarItem).items.first { $0.title == "全部" }?.state == .on
            && menu(pixabay.orderToolbarItem).items[0].state == .on
        pixabay.searchField.stringValue = "two "
        pixabay.controlTextDidChange(.init(name: NSControl.textDidChangeNotification, object: pixabay.searchField))
        await settle()
        checks["pixabay-own-query-echo-preserves-the-space-between-typed-words"] = pixabay.searchField.stringValue == "two "
            && pixabayService.toolbarQuery == "two" && pixabayService.searches.count == countBeforeSourceEcho
        pixabayService.toolbarQuery = ""
        pixabayService.apiKey = ""
        await settle(0.45)
        checks["pixabay-clearing-the-key-revokes-a-pending-query-and-refreshes-the-field"] = pixabayService.searches.count == countBeforeSourceEcho
            && pixabay.searchField.stringValue.isEmpty && pixabayService.toolbarQuery.isEmpty
        pixabayService.apiKey = "fixture-key-a"
        pixabay.searchField.stringValue = "old key query"
        pixabay.controlTextDidChange(.init(name: NSControl.textDidChangeNotification, object: pixabay.searchField))
        pixabayService.apiKey = "fixture-key-b"
        await settle(0.45)
        checks["pixabay-replacing-the-key-revokes-only-the-old-pending-query"] = pixabayService.searches.count == countBeforeSourceEcho
        pixabay.searchField.stringValue = "new key query"
        pixabay.controlTextDidChange(.init(name: NSControl.textDidChangeNotification, object: pixabay.searchField))
        await settle(0.45)
        checks["pixabay-input-under-the-new-key-keeps-the-original-debounce-route"] = pixabayService.searches.count == countBeforeSourceEcho + 1
            && pixabayService.searches.last?.query == "new key query"
        checks["pixabay-narrow-native-toolbar-retains-category-order-api-overflow"] = (toolbar.visibleItems?.count ?? 0) < toolbar.items.count
            && [pixabay.filterToolbarItem, pixabay.orderToolbarItem, pixabay.settingsToolbarItem].allSatisfy { $0.menuFormRepresentation?.submenu?.items.contains { $0.isEnabled } == true }
        checks["pixabay-collapsed-search-expands-the-original-native-field"] = await searchInteraction(pixabay.searchToolbarItem, label: "Pixabay", begin: pixabay.focusSearch)
        let heldCategory = menu(pixabay.filterToolbarItem).items.first { $0.title == "全部" }!
        let submittedQuery = pixabayService.currentParams.query
        pixabay.searchField.stringValue = "draft retained for return"
        pixabay.controlTextDidChange(.init(name: NSControl.textDidChangeNotification, object: pixabay.searchField))
        NotificationCenter.default.post(name: .pixabayModeDidChange, object: nil, userInfo: ["enabled": false])
        let countBeforeLeaving = pixabayService.searches.count
        NSApp.sendAction(heldCategory.action!, to: heldCategory.target, from: heldCategory)
        apiMenu.performActionForItem(at: 2)
        checks["leaving-pixabay-revokes-held-source-menu-actions"] = pixabayService.searches.count == countBeforeLeaving && apiClears == 1
        await settle(0.45)
        checks["pixabay-leaving-retires-pending-network-work-without-dropping-the-draft"] = pixabayService.searches.count == countBeforeLeaving
            && pixabayService.toolbarQuery == "draft retained for return" && pixabayService.currentParams.query == submittedQuery
        NotificationCenter.default.post(name: .pixabayModeDidChange, object: nil, userInfo: ["enabled": true])
        await settle(0.45)
        checks["pixabay-return-submits-the-unfulfilled-draft-once-through-the-original-owner"] = pixabayService.searches.count == countBeforeLeaving + 1
            && pixabayService.searches.last?.query == "draft retained for return"
        NotificationCenter.default.post(name: .pixabayModeDidChange, object: nil, userInfo: ["enabled": false])
        NotificationCenter.default.post(name: .pixabayModeDidChange, object: nil, userInfo: ["enabled": true])
        await settle(0.45)
        checks["pixabay-fulfilled-query-does-not-request-again-on-a-page-roundtrip"] = pixabayService.searches.count == countBeforeLeaving + 1
        let beforeHiddenPixabay = pixabayService.searches.count
        pixabay.searchField.stringValue = "pixabay hidden draft"
        pixabay.controlTextDidChange(.init(name: NSControl.textDidChangeNotification, object: pixabay.searchField))
        window.orderOut(nil); await settle(0.45)
        checks["pixabay-hidden-window-keeps-the-service-draft-without-http"] = pixabayService.searches.count == beforeHiddenPixabay
            && pixabayService.toolbarQuery == "pixabay hidden draft"
        window.makeKeyAndOrderFront(nil); await settle(0.45)
        checks["pixabay-window-restoration-submits-the-service-draft-once"] = pixabayService.searches.count == beforeHiddenPixabay + 1
            && pixabayService.currentParams.query == "pixabay hidden draft"
        let beforeMiniPixabay = pixabayService.searches.count
        pixabay.searchField.stringValue = "pixabay minimized draft"
        pixabay.controlTextDidChange(.init(name: NSControl.textDidChangeNotification, object: pixabay.searchField))
        window.miniaturize(nil); await settle(0.45)
        checks["pixabay-minimized-window-does-not-start-the-pending-query"] = window.isMiniaturized
            && pixabayService.searches.count == beforeMiniPixabay
        window.deminiaturize(nil); await settle(0.45)
        checks["pixabay-deminiaturizing-submits-the-draft-once"] = pixabayService.searches.count == beforeMiniPixabay + 1
            && pixabayService.currentParams.query == "pixabay minimized draft"
        NotificationCenter.default.post(name: .pixabayModeDidChange, object: nil, userInfo: ["enabled": false])
        pixabayService.hasLoadedOnce = false
        pixabayService.toolbarQuery = "initial draft"
        NotificationCenter.default.post(name: .pixabayModeDidChange, object: nil, userInfo: ["enabled": true])
        await settle()
        checks["pixabay-first-load-stays-with-the-original-browser-initialization-owner"] = pixabayService.searches.count == beforeMiniPixabay + 1
        let stock = NSSearchToolbarItem(itemIdentifier: .init("native-stock-search"))
        stock.preferredWidthForSearchField = 220; stock.visibilityPriority = .high
        await install(pixabay.pixabayIdentifiers.map { $0 == .pixabaySearch ? stock.itemIdentifier : $0 }) { id in
            if id == stock.itemIdentifier { return stock }
            return pixabay.makeItem(for: id)
        }
        window.makeKeyAndOrderFront(nil)
        checks["stock-search-under-the-same-narrow-toolbar-gains-a-field-editor"] = await searchInteraction(stock, label: "Stock", begin: stock.beginSearchInteraction)
        NotificationCenter.default.removeObserver(change); NotificationCenter.default.removeObserver(clear)
        pixabay.menuPopover.close(); steam.menuPopover.close(); steam.filterPanelPopover.close()
        window.close()
        print(String(data: try! JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
