import AppKit
import Combine

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
    func clearHistory(forAccount account: String) { clearedAccounts.append(account) }
}
@MainActor final class SteamWorkshopService {
    static let shared = SteamWorkshopService()
    let steamAuth = ToolbarAuth(), downloadJobStore = ToolbarJobs()
    @Published var statusMessage = ""
    @Published var source = SteamWorkshopSource.featured
    @Published var browserContentMode = SteamWorkshopBrowserContentMode.all
    @Published var trendingWindow = SteamWorkshopTrendingWindow.week
    @Published var browserSectionTitle = "创意工坊"
    @Published var isBrowsingAuthorWorkshop = false
    @Published var facetFilters = 0
    var personalSort = SteamWorkshopPersonalSort.name
    var browserQuery = "" { didSet { queries.append(browserQuery) } }
    var navigationVersion = 0
    var queries: [String] = []
    var activeFilterSummary = "全部"
    var authorWorkshopReturnDestination: (title: String, marker: Int)? = ("返回创意工坊", 0)
    var loginCalls = 0, logoutCalls = 0, backCalls = 0, subscriptionsCalls = 0
    var canReturnFromBrowse: Bool { isBrowsingAuthorWorkshop || source.isPersonal }
    var retryRequests: [String] = [], discardedJobs: [String] = []
    func showLoginPanel() { loginCalls += 1 }
    func signOutEverywhere() { logoutCalls += 1 }
    func returnFromBrowseSubpage() { backCalls += 1; isBrowsingAuthorWorkshop = false }
    func showMySubscriptions() { subscriptionsCalls += 1 }
    func downloadWorkshopItem(id: String, pageTitle: String) { retryRequests.append(id) }
    func discardFailedDownload(jobID: String) { discardedJobs.append(jobID) }
}
@MainActor final class SteamWorkshopFilterPanelController: NSViewController {
    static let panelWidth: CGFloat = 300
    let preferredPanelHeight: CGFloat = 100
    init(service: SteamWorkshopService) { super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { nil }
    override func loadView() { view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 100)) }
}
@MainActor final class SteamWorkshopDownloadRowView: NSView {
    var unbinds = 0
    init(service: SteamWorkshopService, onCleared: @escaping () -> Void) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 76).isActive = true
    }
    required init?(coder: NSCoder) { nil }
    func configure(job: SteamDownloadJob) { setAccessibilityLabel(job.title) }
    func configure(summary: SteamWorkshopDownloadHistorySummary) { setAccessibilityLabel(summary.title) }
    func unbind() { unbinds += 1 }
}
// ACTUAL_TASK_CONTROLLERS
@MainActor final class OnlineLibraryService: ObservableObject {
    static let shared = OnlineLibraryService()
    @Published var toolbarCategory = OnlineLibraryCategory.all
    @Published var toolbarQuery = ""
    @Published var currentParams = OnlineLibrarySearchParams()
    var apiKey = "fixture-key"
    var hasLoadedOnce = false
    var searches: [OnlineLibrarySearchParams] = []
    var refreshes = 0
    func searchWithCurrentContext(query: String? = nil, category: OnlineLibraryCategory? = nil, order: OnlineLibraryOrder? = nil) {
        currentParams.query = query ?? toolbarQuery
        if let category { currentParams.category = category }
        if let order { currentParams.order = order }
        hasLoadedOnce = true
        searches.append(currentParams)
    }
    func refresh() { refreshes += 1 }
}
extension Notification.Name {
    static let steamWorkshopModeDidChange = Self("fixture-steam-mode")
    static let steamWorkshopBrowseContextDidChange = Self("fixture-steam-context")
    static let onlineLibraryModeDidChange = Self("fixture-online-mode")
}
@MainActor final class RemoteToolbarDelegate: NSObject, NSToolbarDelegate {
    var identifiers: [NSToolbarItem.Identifier] = []
    var makeItem: ((NSToolbarItem.Identifier) -> NSToolbarItem?)?
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { identifiers }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { identifiers }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar: Bool) -> NSToolbarItem? {
        if id.rawValue == "ToolbarTitle" {
            let item = NSToolbarItem(itemIdentifier: id)
            item.view = NSTextField(labelWithString: "来源标题")
            return item
        }
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
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let toolbar = NSToolbar(identifier: .init("remote-fixture")), delegate = RemoteToolbarDelegate()
        toolbar.delegate = delegate; toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        let steam = SteamWorkshopToolbarController(toolbar: toolbar, window: window)
        let online = OnlineLibraryToolbarController(window: window)
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
                       value.contentViewController is SteamWorkshopDownloadTasksContentController { taskPopover = value }
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
            for item in [steam.filterToolbarItem, steam.downloadTasksToolbarItem] {
                diagnostic("\(label) item \(item.itemIdentifier.rawValue): toolbarMatches=\(item.toolbar === toolbar), enabled=\(item.isEnabled), nativeVisible=\(toolbar.visibleItems?.contains { $0 === item } == true), view={\(viewFacts(item.view))}")
            }
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
        checks["steam-discovery-has-five-native-role-groups-without-empty-spaces"] = groups() == [[.steamAccount, .steamDownloadTasks],
            [.steamTrendingWindow], [.steamSort, .steamFilter], [.steamZoom], [.steamSearch]]
        checks["steam-search-is-the-original-field-in-a-native-search-toolbar-item"] = steam.searchToolbarItem.searchField === steam.searchField
            && steam.searchField.delegate === steam && steam.searchToolbarItem.preferredWidthForSearchField == 240
        let publicMenu = menu(steam.sortToolbarItem)
        publicMenu.performActionForItem(at: SteamWorkshopSource.publicSources.firstIndex(of: .recent)!)
        checks["steam-native-overflow-chooses-the-original-public-source-enum"] = service.source == .recent
            && menu(steam.sortToolbarItem).items[1].state == .on
        service.source = .featured; steam.syncTrendingWindowPopup()
        menu(steam.trendingWindowToolbarItem).performActionForItem(at: SteamWorkshopTrendingWindow.allCases.firstIndex(of: .month)!)
        checks["steam-native-overflow-chooses-the-original-time-window-enum"] = service.trendingWindow == .month
        service.source = .mySubscriptions; steam.syncPersonalListPopup(); steam.syncSortPopup()
        await install(steam.browserIdentifiers, factory: steam.makeItem(for:))
        checks["steam-personal-subpage-keeps-return-and-all-original-controls"] = groups() == [[.steamAccount, .steamDownloadTasks],
            [.steamAuthorBack], [.steamPersonalList], [.steamSort, .steamFilter], [.steamZoom], [.steamSearch]] && steam.authorBackToolbarItem.isEnabled
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
        checks["steam-author-subroute-has-return-without-unsupported-sort-filter-groups"] = groups() == [[.steamAccount, .steamDownloadTasks],
            [.steamAuthorBack], [.steamZoom], [.steamSearch]]
        let back = steam.authorBackToolbarItem.menuFormRepresentation!
        NSApp.sendAction(back.action!, to: back.target, from: back)
        checks["steam-native-overflow-returns-through-the-original-author-route"] = service.backCalls == 1
        steam.configureDownloadTasksItem()
        let tasks = steam.downloadTasksToolbarItem.menuFormRepresentation!
        popoverPhase = "first-task-show"
        let firstTaskDidShow = await afterPopoverEvent(NSPopover.didShowNotification,
            matching: { $0.contentViewController is SteamWorkshopDownloadTasksContentController }) {
            NSApp.sendAction(tasks.action!, to: tasks.target, from: tasks)
        }
        diagnostic("First task: controllerShown=\(steam.downloadTasksPopoverController.isShown), popover={\(popoverFacts(taskPopover))}")
        toolbarFacts("First task toolbar")
        checks["steam-native-task-overflow-keeps-the-original-task-owner-and-real-anchor"] = firstTaskDidShow
            && steam.downloadTasksPopoverController.isShown
            && taskPopover?.contentViewController?.view.window?.isVisible == true
            && taskPopover.map { didShowCounts[ObjectIdentifier($0), default: 0] > 0 } == true
        popoverPhase = "first-task-close"
        let firstTaskDidClose = await afterPopoverEvent(NSPopover.didCloseNotification, matching: { $0 === taskPopover }) {
            steam.downloadTasksPopoverController.close()
        }
        checks["native-task-close-completes-before-the-next-toolbar-action"] = firstTaskDidClose
            && !steam.downloadTasksPopoverController.isShown
        diagnostic("First task close: controllerShown=\(steam.downloadTasksPopoverController.isShown), popover={\(popoverFacts(taskPopover))}")
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
        NotificationCenter.default.post(name: .steamWorkshopModeDidChange, object: nil, userInfo: ["enabled": true, "isDownloads": true])
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
        service.source = .featured
        await install(steam.browserIdentifiers, factory: steam.makeItem(for:))
        window.setContentSize(NSSize(width: 600, height: 500)); await settle()
        checks["steam-narrow-native-toolbar-overflows-with-equivalent-source-actions"] = (toolbar.visibleItems?.count ?? 0) < toolbar.items.count
            && [.steamAccount, .steamDownloadTasks, .steamTrendingWindow, .steamSort, .steamFilter].allSatisfy { id in steam.makeItem(for: id)?.menuFormRepresentation != nil }
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
        let detachedTasks: Bool = isDetachedActionItem(steam.downloadTasksToolbarItem)
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
        if !steam.filterPanelPopover.isShown {
            diagnostic("Steam filter: active=\(app.isActive), key=\(window.isKeyWindow), sourceActive=\(steam.isSteamWorkshopMode), downloads=\(steam.isDownloadsMode), author=\(service.isBrowsingAuthorWorkshop), enabled=\(filter.isEnabled), buttonWindow=\(String(describing: steam.filterButton.window)), hostVisible=\(window.isVisible)")
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
            accountSteamId: account, attempt: 1, outcome: .completed, failureMessage: nil, recordID: nil, terminalAt: Date(timeIntervalSince1970: 2))]
        let priorTaskShows = taskPopover.map { didShowCounts[ObjectIdentifier($0), default: 0] } ?? 0
        popoverPhase = "overflow-task-show"
        let overflowTaskDidShow = await afterPopoverEvent(NSPopover.didShowNotification, matching: { $0 === taskPopover }) {
            NSApp.sendAction(tasks.action!, to: tasks.target, from: tasks)
        }
        diagnostic("Overflow task display: controllerShown=\(steam.downloadTasksPopoverController.isShown), priorDidShow=\(priorTaskShows), popover={\(popoverFacts(taskPopover))}")
        let taskRoot = taskPopover?.contentViewController?.view
        let retries = taskRoot.flatMap { descendants($0, NSButton.self).first { $0.title == "重试全部失败" } }
        let clears = taskRoot.flatMap { descendants($0, NSButton.self).first { $0.title == "全部清除" } }
        checks["real-native-task-popover-opens-from-a-detached-overflow-item"] = overflowTaskDidShow && steam.downloadTasksPopoverController.isShown
            && taskRoot?.window?.isVisible == true
            && taskPopover.map { didShowCounts[ObjectIdentifier($0), default: 0] > priorTaskShows } == true
        checks["real-task-content-displays-current-account-jobs-and-history"] = taskRoot.map {
            descendants($0, NSTextField.self).contains { $0.stringValue == "下载任务 · 3 项" }
        } == true && retries?.isEnabled == true && clears?.isEnabled == true
        service.steamAuth.steamId = "other-account"
        retries?.performClick(nil); clears?.performClick(nil)
        checks["held-task-content-cannot-retry-or-clear-another-account"] = service.retryRequests.isEmpty
            && service.discardedJobs.isEmpty && service.downloadJobStore.clearedAccounts.isEmpty
        service.steamAuth.steamId = account; await settle()
        retries?.performClick(nil); clears?.performClick(nil)
        checks["real-task-buttons-route-only-current-failed-work-and-account-history"] = service.retryRequests == ["123457"]
            && service.discardedJobs == ["failed"] && service.downloadJobStore.clearedAccounts == [account]
            && service.downloadJobStore.jobs.first { $0.id == "active" }?.state == .running
            && service.downloadJobStore.jobs.first { $0.id == "foreign" }?.accountSteamId == "other-account"
        let rows = taskRoot.map { descendants($0, SteamWorkshopDownloadRowView.self) } ?? []
        diagnostic("Task close precondition: root={\(viewFacts(taskRoot))}, rows=\(rows.map { "\(ObjectIdentifier($0)):\($0.unbinds)" }), controllerShown=\(steam.downloadTasksPopoverController.isShown)")
        popoverPhase = "overflow-task-close"
        let overflowTaskDidClose = await afterPopoverEvent(NSPopover.didCloseNotification, matching: { $0 === taskPopover }) {
            steam.downloadTasksPopoverController.close()
        }
        diagnostic("Task close result: controllerShown=\(steam.downloadTasksPopoverController.isShown), rows=\(rows.map { "\(ObjectIdentifier($0)):\($0.unbinds)" }), remainingRows=\(taskRoot.map { descendants($0, SteamWorkshopDownloadRowView.self).count } ?? -1), popover={\(popoverFacts(taskPopover))}")
        checks["closing-the-real-task-popover-revokes-row-observation"] = overflowTaskDidClose && !steam.downloadTasksPopoverController.isShown
            && !rows.isEmpty && rows.allSatisfy { $0.unbinds > 0 }
            && taskRoot.map { descendants($0, SteamWorkshopDownloadRowView.self).isEmpty } == true
        window.setContentSize(NSSize(width: 600, height: 500)); await settle()
        NotificationCenter.default.post(name: .steamWorkshopModeDidChange, object: nil, userInfo: ["enabled": false])
        NotificationCenter.default.post(name: .onlineLibraryModeDidChange, object: nil, userInfo: ["enabled": true])
        await install(online.onlineIdentifiers, factory: online.makeItem(for:))
        checks["pixabay-has-five-native-groups-and-one-settings-refresh-source-group"] = groups() == [[.olSettings, .olRefresh],
            [.olCategory], [.olOrder], [.olZoom], [.olSearch]]
        let onlineService = OnlineLibraryService.shared
        checks["pixabay-search-is-the-original-field-in-a-native-search-toolbar-item"] = online.searchToolbarItem.searchField === online.searchField
            && online.searchField.delegate === online && online.searchToolbarItem.preferredWidthForSearchField == 240
        menu(online.categoryToolbarItem).performActionForItem(at: OnlineLibraryCategory.allCases.firstIndex(of: .nature)!)
        menu(online.orderToolbarItem).performActionForItem(at: OnlineLibraryOrder.allCases.firstIndex(of: .latest)!)
        checks["pixabay-native-overflow-uses-original-category-and-order-enums"] = onlineService.toolbarCategory == .nature
            && onlineService.currentParams.category == .nature && onlineService.currentParams.order == .latest
            && online.categoryControl.selectedSegment == OnlineLibraryCategory.allCases.firstIndex(of: .nature)
        var apiChanges = 0, apiClears = 0
        let change = NotificationCenter.default.addObserver(forName: .olShowAPIKeySettings, object: nil, queue: .main) { _ in MainActor.assumeIsolated { apiChanges += 1 } }
        let clear = NotificationCenter.default.addObserver(forName: .olClearAPIKey, object: nil, queue: .main) { _ in MainActor.assumeIsolated { apiClears += 1 } }
        let apiMenu = menu(online.settingsToolbarItem)
        apiMenu.performActionForItem(at: 0); apiMenu.performActionForItem(at: 2)
        checks["pixabay-native-overflow-retains-both-original-api-settings-notifications"] = apiChanges == 1 && apiClears == 1
        let refresh = online.refreshToolbarItem
        NSApp.sendAction(refresh.action!, to: refresh.target, from: refresh)
        checks["pixabay-refresh-still-invokes-the-original-source-owner"] = onlineService.refreshes == 1
        online.searchField.stringValue = "first"; online.controlTextDidChange(.init(name: NSControl.textDidChangeNotification, object: online.searchField))
        online.searchField.stringValue = "last"; online.controlTextDidChange(.init(name: NSControl.textDidChangeNotification, object: online.searchField))
        let priorSearchCount = onlineService.searches.count
        await settle(0.45)
        checks["pixabay-original-search-debounce-merges-to-the-latest-query"] = onlineService.toolbarQuery == "last"
            && onlineService.searches.count == priorSearchCount + 1 && onlineService.searches.last?.query == "last"
        if checks["pixabay-original-search-debounce-merges-to-the-latest-query"] != true {
            diagnostic("Pixabay debounce: prior=\(priorSearchCount), count=\(onlineService.searches.count), queries=\(onlineService.searches.map(\.query)), field=\(online.searchField.stringValue), context=\(onlineService.toolbarQuery)")
        }
        let beforeImmediateCategory = onlineService.searches.count
        online.searchField.stringValue = "draft with category"
        online.controlTextDidChange(.init(name: NSControl.textDidChangeNotification, object: online.searchField))
        menu(online.categoryToolbarItem).performActionForItem(at: OnlineLibraryCategory.allCases.firstIndex(of: .all)!)
        await settle(0.45)
        checks["pixabay-immediate-category-consumes-the-current-draft-without-a-second-debounce-request"] =
            onlineService.searches.count == beforeImmediateCategory + 1 && onlineService.searches.last?.query == "draft with category"
            && onlineService.searches.last?.category == .all
        let beforeImmediateOrder = onlineService.searches.count
        online.searchField.stringValue = "draft with order"
        online.controlTextDidChange(.init(name: NSControl.textDidChangeNotification, object: online.searchField))
        menu(online.orderToolbarItem).performActionForItem(at: OnlineLibraryOrder.allCases.firstIndex(of: .popular)!)
        await settle(0.45)
        checks["pixabay-immediate-order-consumes-the-current-draft-without-a-second-debounce-request"] =
            onlineService.searches.count == beforeImmediateOrder + 1 && onlineService.searches.last?.query == "draft with order"
            && onlineService.searches.last?.order == .popular
        let countBeforeSourceEcho = onlineService.searches.count
        onlineService.toolbarCategory = .all
        onlineService.currentParams.order = .popular
        onlineService.toolbarQuery = "external context"
        await settle()
        checks["pixabay-source-echo-updates-category-order-search-and-overflow-without-requesting"] = onlineService.searches.count == countBeforeSourceEcho
            && online.categoryControl.selectedSegment == OnlineLibraryCategory.allCases.firstIndex(of: .all)
            && online.orderControl.selectedSegment == OnlineLibraryOrder.allCases.firstIndex(of: .popular)
            && online.searchField.stringValue == "external context"
            && menu(online.categoryToolbarItem).items[0].state == .on
            && menu(online.orderToolbarItem).items[0].state == .on
        online.searchField.stringValue = "two "
        online.controlTextDidChange(.init(name: NSControl.textDidChangeNotification, object: online.searchField))
        await settle()
        checks["pixabay-own-query-echo-preserves-the-space-between-typed-words"] = online.searchField.stringValue == "two "
            && onlineService.toolbarQuery == "two" && onlineService.searches.count == countBeforeSourceEcho
        onlineService.toolbarQuery = ""
        onlineService.apiKey = ""
        await settle(0.45)
        checks["pixabay-clearing-the-key-revokes-a-pending-query-and-refreshes-the-field"] = onlineService.searches.count == countBeforeSourceEcho
            && online.searchField.stringValue.isEmpty && onlineService.toolbarQuery.isEmpty
        onlineService.apiKey = "fixture-key-a"
        online.searchField.stringValue = "old key query"
        online.controlTextDidChange(.init(name: NSControl.textDidChangeNotification, object: online.searchField))
        onlineService.apiKey = "fixture-key-b"
        await settle(0.45)
        checks["pixabay-replacing-the-key-revokes-only-the-old-pending-query"] = onlineService.searches.count == countBeforeSourceEcho
        online.searchField.stringValue = "new key query"
        online.controlTextDidChange(.init(name: NSControl.textDidChangeNotification, object: online.searchField))
        await settle(0.45)
        checks["pixabay-input-under-the-new-key-keeps-the-original-debounce-route"] = onlineService.searches.count == countBeforeSourceEcho + 1
            && onlineService.searches.last?.query == "new key query"
        checks["pixabay-narrow-native-toolbar-retains-category-order-api-overflow"] = (toolbar.visibleItems?.count ?? 0) < toolbar.items.count
            && [online.categoryToolbarItem, online.orderToolbarItem, online.settingsToolbarItem].allSatisfy { $0.menuFormRepresentation?.submenu?.items.contains { $0.isEnabled } == true }
        checks["pixabay-collapsed-search-expands-the-original-native-field"] = await searchInteraction(online.searchToolbarItem, label: "Pixabay", begin: online.focusSearch)
        let heldCategory = menu(online.categoryToolbarItem).items[0]
        let submittedQuery = onlineService.currentParams.query
        online.searchField.stringValue = "draft retained for return"
        online.controlTextDidChange(.init(name: NSControl.textDidChangeNotification, object: online.searchField))
        NotificationCenter.default.post(name: .onlineLibraryModeDidChange, object: nil, userInfo: ["enabled": false])
        let countBeforeLeaving = onlineService.searches.count
        NSApp.sendAction(heldCategory.action!, to: heldCategory.target, from: heldCategory)
        apiMenu.performActionForItem(at: 2)
        checks["leaving-pixabay-revokes-held-source-menu-actions"] = onlineService.searches.count == countBeforeLeaving && apiClears == 1
        await settle(0.45)
        checks["pixabay-leaving-retires-pending-network-work-without-dropping-the-draft"] = onlineService.searches.count == countBeforeLeaving
            && onlineService.toolbarQuery == "draft retained for return" && onlineService.currentParams.query == submittedQuery
        NotificationCenter.default.post(name: .onlineLibraryModeDidChange, object: nil, userInfo: ["enabled": true])
        await settle(0.45)
        checks["pixabay-return-submits-the-unfulfilled-draft-once-through-the-original-owner"] = onlineService.searches.count == countBeforeLeaving + 1
            && onlineService.searches.last?.query == "draft retained for return"
        NotificationCenter.default.post(name: .onlineLibraryModeDidChange, object: nil, userInfo: ["enabled": false])
        NotificationCenter.default.post(name: .onlineLibraryModeDidChange, object: nil, userInfo: ["enabled": true])
        await settle(0.45)
        checks["pixabay-fulfilled-query-does-not-request-again-on-a-page-roundtrip"] = onlineService.searches.count == countBeforeLeaving + 1
        NotificationCenter.default.post(name: .onlineLibraryModeDidChange, object: nil, userInfo: ["enabled": false])
        onlineService.hasLoadedOnce = false
        onlineService.toolbarQuery = "initial draft"
        NotificationCenter.default.post(name: .onlineLibraryModeDidChange, object: nil, userInfo: ["enabled": true])
        await settle()
        checks["pixabay-first-load-stays-with-the-original-browser-initialization-owner"] = onlineService.searches.count == countBeforeLeaving + 1
        let stock = NSSearchToolbarItem(itemIdentifier: .init("native-stock-search"))
        stock.preferredWidthForSearchField = 240; stock.visibilityPriority = .high
        await install(online.onlineIdentifiers.map { $0 == .olSearch ? stock.itemIdentifier : $0 }) { id in
            if id == stock.itemIdentifier { return stock }
            return online.makeItem(for: id)
        }
        window.makeKeyAndOrderFront(nil)
        checks["stock-search-under-the-same-narrow-toolbar-gains-a-field-editor"] = await searchInteraction(stock, label: "Stock", begin: stock.beginSearchInteraction)
        NotificationCenter.default.removeObserver(change); NotificationCenter.default.removeObserver(clear)
        online.menuPopover.close(); steam.menuPopover.close(); steam.filterPanelPopover.close()
        window.close()
        print(String(data: try! JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
