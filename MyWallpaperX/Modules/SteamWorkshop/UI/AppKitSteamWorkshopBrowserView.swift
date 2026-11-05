//
//  AppKitSteamWorkshopBrowserView.swift
//  MyWallpaperX
//

import AppKit
import Combine

final class AppKitSteamWorkshopBrowserView: NSView, ListThumbnailTintProviding {
    let listThumbnailTintSource = ListThumbnailTintSource()
    var preferredColumns = 5 {
        didSet { if currentState == .grid { gridView.preferredColumns = preferredColumns } }
    }
    var clipWidth: CGFloat { currentState == .grid && gridView.window != nil ? gridView.clipWidth : 0 }
    var selectedItem: SteamWorkshopBrowserItem? { gridView.selectedItem }
    var selectedPrimaryAction: (() -> Void)? { gridView.selectedPrimaryAction }
    @discardableResult func inspectSelectedItem() -> Bool { gridView.inspectSelectedItem() }
    var onClipWidthChange: ((CGFloat) -> Void)? {
        didSet { onClipWidthChange?(clipWidth) }
    }
    var makeOrganization: ((SteamWorkshopBrowserItem) -> AppKitSteamWorkshopBrowserItem.OrganizationPresentation?)? {
        didSet { gridView.makeOrganization = makeOrganization }
    }
    var makeInspectorActions: ((SteamWorkshopBrowserItem) -> WallpaperInspectorActions?)? {
        didSet { refreshInspectorActions() }
    }
    var makeOrganizationMenu: ((SteamWorkshopBrowserItem) -> NSMenu?)? {
        didSet { gridView.makeOrganizationMenu = makeOrganizationMenu }
    }

    func refreshLibraryActions() {
        gridView.refreshLibraryActions()
        refreshInspectorActions()
    }

    private func refreshInspectorActions() {
        guard let item = latestInspectorItem else { return }
        inspectorDetailView?.updateLibraryActions(makeInspectorActions?(item))
    }
    private enum ContentState: Equatable {
        case loading
        case error(String)
        case empty(symbolName: String, message: String)
        case grid
    }

    private let service = SteamWorkshopService.shared
    private let contentHost = NSView()
    private var cancellables = Set<AnyCancellable>()
    private var currentState: ContentState?
    private var inspectorDetailView: AppKitSteamWorkshopItemDetailView?
    private var lastRequestedCardID: String?
    private var visibleCardID: String?
    private var latestInspectorItem: SteamWorkshopBrowserItem?
    private var isHandlingHostClose = false
    /// One visible demand per view, balanced across hiding, minimization and detachment.
    private var isBrowsePanelActive = false
    private var visibilitySubscription: AnyCancellable?

    var opensDetailsOnSingleClick: () -> Bool = { false }
    private lazy var gridView = AppKitSteamWorkshopBrowserContainerView(
        service: service,
        onOpen: { [weak self] item in
            self?.service.presentItemDetail(item)
        },
        onDownload: { [weak self] item in
            self?.service.requestDownloadForBrowserItem(item)
        },
        onSetAsWallpaper: { [weak self] record in
            self?.service.setAsWallpaper(record)
        },
        onCancelDownload: { [weak self] item in
            self?.service.cancelDownload(itemID: item.id)
        }
    )

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
        observeService()
        observeInspectorHost()
        syncContent(force: true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let wasAttached = visibilitySubscription != nil
        visibilitySubscription = nil
        guard let window else {
            updateBrowsePanelVisibility()
            if wasAttached {
                InspectorHostActions.postClose(module: .steamWorkshop)
                service.dismissItemDetail()
            }
            return
        }
        let changes = [window.publisher(for: \.isVisible, options: [.new]).map { _ in () }.eraseToAnyPublisher()]
            + [NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification].map {
                NotificationCenter.default.publisher(for: $0, object: window).map { _ in () }.eraseToAnyPublisher()
            } + [NSApplication.didHideNotification, NSApplication.didUnhideNotification].map {
                NotificationCenter.default.publisher(for: $0, object: NSApp).map { _ in () }.eraseToAnyPublisher()
            }
        visibilitySubscription = Publishers.MergeMany(changes).sink { [weak self] in
            MainActor.assumeIsolated { self?.updateBrowsePanelVisibility() }
        }
        updateBrowsePanelVisibility(isEntry: true)
    }

    override func viewDidHide() { super.viewDidHide(); updateBrowsePanelVisibility() }
    override func viewDidUnhide() { super.viewDidUnhide(); updateBrowsePanelVisibility() }

    private func updateBrowsePanelVisibility(isEntry: Bool = false) {
        let active = window?.isVisible == true && window?.isMiniaturized == false
            && !NSApp.isHidden && !isHiddenOrHasHiddenAncestor
        guard active != isBrowsePanelActive else { return }
        isBrowsePanelActive = active
        guard active else { service.noteBrowsePanelDetached(); return }
        service.noteBrowsePanelAttached()
        gridView.opensDetailsOnSingleClick = { [weak self] in self?.opensDetailsOnSingleClick() == true }
        if isEntry || service.browserState == .idle || service.browserState == .loading { service.prepareForBrowserEntry() }
        syncContent(force: true)
        syncSelectedInspectorItem(service.selectedBrowserItem)
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        translatesAutoresizingMaskIntoConstraints = false

        contentHost.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentHost)
        NSLayoutConstraint.activate([
            contentHost.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentHost.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentHost.topAnchor.constraint(equalTo: topAnchor),
            contentHost.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

    }

    private func observeService() {
        let syncPublishers: [AnyPublisher<Void, Never>] = [
            service.$displayedBrowserItems.map { _ in () }.eraseToAnyPublisher(),
            service.$isRefreshingBrowserFeed.map { _ in () }.eraseToAnyPublisher(),
            service.$isLoadingMoreBrowserItems.map { _ in () }.eraseToAnyPublisher(),
            service.$hasMoreBrowserItems.map { _ in () }.eraseToAnyPublisher(),
            service.$browserContentMode.map { _ in () }.eraseToAnyPublisher(),
            service.$browserQuery.map { _ in () }.eraseToAnyPublisher(),
            service.$source.map { _ in () }.eraseToAnyPublisher(),
            service.$currentPageTitle.map { _ in () }.eraseToAnyPublisher(),
            service.$isBrowsingAuthorWorkshop.map { _ in () }.eraseToAnyPublisher(),
            service.$activeAuthorWorkshopName.map { _ in () }.eraseToAnyPublisher(),
            service.steamAuth.$steamId.map { _ in () }.eraseToAnyPublisher()
        ]

        syncPublishers.forEach { publisher in
            publisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in self?.syncContent() }
                .store(in: &cancellables)
        }

        service.$selectedBrowserItem
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.syncSelectedInspectorItem(self.service.selectedBrowserItem)
            }
            .store(in: &cancellables)
    }

    private func observeInspectorHost() {
        NotificationCenter.default.publisher(for: .inspectorHostDidPresent)
            .sink { [weak self] notification in self?.handleInspectorDidPresent(notification) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .inspectorHostDidClose)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in self?.handleInspectorDidClose(notification) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .inspectorHostCloseRequested)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in self?.handleInspectorCloseRequested(notification) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .moduleDidBecomeActive)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in self?.handleModuleActivation(notification) }
            .store(in: &cancellables)
    }

    private func contentState() -> ContentState {
        switch service.browserState {
        case .idle, .loading:
            return .loading
        case .failed(let message):
            return .error(message)
        case .loaded:
            // A locally filtered page does not exhaust the remote collection.
            if service.hasVisibleBrowserItems || service.hasMoreBrowserItems {
                return .grid
            }
            if let message = personalLoginGuidance {
                return .empty(symbolName: "person.crop.circle", message: message)
            }
            return .empty(symbolName: "square.grid.2x2", message: emptyStateMessage)
        }
    }

    private var loadingText: String {
        service.isBrowsingAuthorWorkshop
            ? "正在抓取 \(service.activeAuthorWorkshopName ?? "作者") 的工坊列表..."
            : "正在抓取创意工坊\(service.browserContentMode.displayName)列表..."
    }

    private var emptyStateMessage: String {
        let trimmedQuery = service.browserQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if service.isBrowsingAuthorWorkshop,
           !trimmedQuery.isEmpty,
           !service.browserItems.isEmpty {
            return "已加载的作者作品中没有匹配项"
        }
        return service.isBrowsingAuthorWorkshop
            ? "\(service.activeAuthorWorkshopName ?? "该作者") 当前没有可访问的作品"
            : "当前条件下没有抓取到\(service.browserContentMode.displayName)项目"
    }

    /// The account route remains the sole authentication authority. This view
    /// only derives the personal-feed presentation from that live identity;
    /// it neither stores a second login flag nor starts authentication.
    private var personalLoginGuidance: String? {
        guard service.shouldUseSteamKitPersonal,
              !service.steamAuth.isOnline else {
            return nil
        }
        return "登录 Steam 后可查看当前账号的「\(service.source.displayName)」。请使用工具栏的「登录 Steam」。"
    }

    private func syncContent(force: Bool = false) {
        let nextState = contentState()
        guard force || nextState != currentState else { return }
        listThumbnailTintSource.forward(from: nextState == .grid ? gridView.listThumbnailTintSource : nil)
        currentState = nextState
        if nextState != .grid { onClipWidthChange?(0) }

        contentHost.subviews.forEach { $0.removeFromSuperview() }

        let contentView: NSView
        let fillsHost: Bool
        switch nextState {
        case .loading:
            contentView = WallpaperLibraryControlStyle.gridState(label: NSTextField(labelWithString: loadingText))
            fillsHost = false
        case .error(let message):
            contentView = makeErrorStateView(message: message)
            fillsHost = false
        case .empty(let symbolName, let message):
            contentView = WallpaperLibraryControlStyle.gridState(symbol: symbolName, label: NSTextField(wrappingLabelWithString: message))
            fillsHost = false
        case .grid:
            gridView.preferredColumns = preferredColumns
            gridView.onClipWidthChange = { [weak self] width in
                guard let self, self.currentState == .grid else { return }
                self.onClipWidthChange?(width)
            }
            contentView = gridView
            fillsHost = true
        }

        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentHost.addSubview(contentView)
        if fillsHost {
            NSLayoutConstraint.activate([
                contentView.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
                contentView.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
                contentView.topAnchor.constraint(equalTo: contentHost.topAnchor),
                contentView.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor)
            ])
        } else {
            NSLayoutConstraint.activate([
                contentView.centerXAnchor.constraint(equalTo: contentHost.centerXAnchor),
                contentView.centerYAnchor.constraint(equalTo: contentHost.centerYAnchor),
                contentView.leadingAnchor.constraint(greaterThanOrEqualTo: contentHost.leadingAnchor, constant: 32),
                contentView.trailingAnchor.constraint(lessThanOrEqualTo: contentHost.trailingAnchor, constant: -32),
                contentView.topAnchor.constraint(greaterThanOrEqualTo: contentHost.topAnchor, constant: 32),
                contentView.bottomAnchor.constraint(lessThanOrEqualTo: contentHost.bottomAnchor, constant: -32)
            ])
        }
    }


    private func makeErrorStateView(message: String) -> NSView {
        let stack = WallpaperLibraryControlStyle.gridState(symbol: "wifi.exclamationmark",
            label: NSTextField(labelWithString: service.isBrowsingAuthorWorkshop ? "抓取作者工坊信息失败" : "抓取创意工坊信息失败"), message: message)
        let retryButton = NSButton(title: "重试", target: self, action: #selector(retryBrowserFetch))
        retryButton.bezelStyle = .rounded
        stack.addArrangedSubview(retryButton)
        return stack
    }





    private func syncSelectedInspectorItem(_ item: SteamWorkshopBrowserItem?) {
        latestInspectorItem = item
        guard !isHandlingHostClose else { return }

        guard let item else {
            if let cardID = visibleCardID ?? lastRequestedCardID {
                InspectorHostActions.postClose(module: .steamWorkshop, cardID: cardID)
            } else {
                removeInspectorContent()
            }
            return
        }

        let presentation = makePresentation(for: item)
        lastRequestedCardID = presentation.cardID
        if visibleCardID == presentation.cardID {
            installInspectorContent(for: item)
            return
        }
        InspectorHostActions.postOpen(module: .steamWorkshop, presentation: presentation)
    }

    private func makePresentation(for item: SteamWorkshopBrowserItem) -> InspectorHostPresentation {
        .infoPanel(
            cardID: item.id,
            title: item.title,
            subtitle: item.author.isEmpty ? service.currentPageTitle : item.author,
            preferredWidth: 356,
            focusPolicy: .preserveCurrentResponder
        )
    }

    private func handleInspectorDidPresent(_ notification: Notification) {
        guard let request = InspectorHostRequest(userInfo: notification.userInfo),
              request.token.module == .steamWorkshop,
              let item = latestInspectorItem,
              request.token.cardID == makePresentation(for: item).cardID else {
            return
        }

        visibleCardID = request.token.cardID
        installInspectorContent(for: item)
    }

    private func handleInspectorCloseRequested(_ notification: Notification) {
        let dismissRequest = InspectorHostDismissRequest(userInfo: notification.userInfo)
        if let requestedModule = dismissRequest?.module, requestedModule != .steamWorkshop {
            return
        }
        if let visibleCardID,
           dismissRequest?.cardID == nil || dismissRequest?.cardID == visibleCardID {
            self.visibleCardID = nil
        }
    }

    private func handleInspectorDidClose(_ notification: Notification) {
        guard let request = InspectorHostRequest(userInfo: notification.userInfo),
              request.token.module == .steamWorkshop,
              request.token.cardID == (lastRequestedCardID ?? visibleCardID) else {
            return
        }

        isHandlingHostClose = true
        visibleCardID = nil
        lastRequestedCardID = nil
        removeInspectorContent()
        if service.selectedBrowserItem?.id == request.token.cardID { service.dismissItemDetail() }
        isHandlingHostClose = false
    }

    private func handleModuleActivation(_ notification: Notification) {
        guard let moduleRawValue = notification.userInfo?["module"] as? String,
              moduleRawValue != ModuleIdentifier.steamWorkshop.rawValue,
              latestInspectorItem != nil else {
            return
        }

        InspectorHostActions.postClose(module: .steamWorkshop, cardID: visibleCardID ?? lastRequestedCardID)
        visibleCardID = nil
        lastRequestedCardID = nil
        removeInspectorContent()
        service.dismissItemDetail()
    }

    private func installInspectorContent(for item: SteamWorkshopBrowserItem) {
        let detailView: AppKitSteamWorkshopItemDetailView
        if let existing = inspectorDetailView {
            existing.configure(item: item)
            existing.updateLibraryActions(makeInspectorActions?(item))
            detailView = existing
        } else {
            let created = AppKitSteamWorkshopItemDetailView(item: item, service: service, libraryActions: makeInspectorActions?(item))
            inspectorDetailView = created
            detailView = created
        }

        InspectorHostActions.postMount(
            module: .steamWorkshop,
            cardID: makePresentation(for: item).cardID,
            hostedView: detailView
        )
    }

    private func removeInspectorContent() {
        inspectorDetailView?.removeFromSuperview()
        inspectorDetailView = nil
    }

    @objc private func retryBrowserFetch() {
        service.refresh()
    }
}
