//
//  AppKitSteamWorkshopBrowserView.swift
//  MyWallpaperX
//

import AppKit
import Combine

final class AppKitSteamWorkshopBrowserView: NSView {
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
    private var isShowingDownloadError = false

    private lazy var gridView = AppKitSteamWorkshopBrowserContainerView(
        service: service,
        onOpen: { [weak self] item in
            self?.service.presentItemDetail(item)
        },
        onAuthor: { [weak self] item in
            self?.service.showAuthorWorkshop(for: item)
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
        if window == nil {
            InspectorHostActions.postClose(module: .steamWorkshop)
            service.dismissItemDetail()
            return
        }

        service.prepareForBrowserEntry()
        syncContent(force: true)
        presentPendingDownloadErrorIfNeeded()
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
            .sink { [weak self] item in self?.syncSelectedInspectorItem(item) }
            .store(in: &cancellables)

        service.$downloadError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.presentPendingDownloadErrorIfNeeded() }
            .store(in: &cancellables)

    }

    private func observeInspectorHost() {
        NotificationCenter.default.publisher(for: .inspectorHostDidPresent)
            .receive(on: DispatchQueue.main)
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
            if service.hasVisibleBrowserItems {
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
            return "当前搜索没有匹配到作者作品"
        }
        return service.isBrowsingAuthorWorkshop
            ? "\(service.activeAuthorWorkshopName ?? "该作者") 当前没有抓取到\(service.browserContentMode.displayName)项目"
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
        currentState = nextState

        contentHost.subviews.forEach { $0.removeFromSuperview() }

        let contentView: NSView
        let fillsHost: Bool
        switch nextState {
        case .loading:
            contentView = makeLoadingStateView(text: loadingText)
            fillsHost = false
        case .error(let message):
            contentView = makeErrorStateView(message: message)
            fillsHost = false
        case .empty(let symbolName, let message):
            contentView = makeCenteredStateView(symbolName: symbolName, message: message)
            fillsHost = false
        case .grid:
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

    private func makeLoadingStateView(text: String) -> NSView {
        let stack = makeCenteredStack(spacing: 12)
        let indicator = NSProgressIndicator()
        indicator.style = .spinning
        indicator.controlSize = .large
        indicator.startAnimation(nil)
        stack.addArrangedSubview(indicator)
        stack.addArrangedSubview(makeStateLabel(text))
        return stack
    }

    private func makeErrorStateView(message: String) -> NSView {
        let stack = makeCenteredStack(spacing: 12)
        stack.addArrangedSubview(makeSymbol("wifi.exclamationmark", pointSize: 30))
        stack.addArrangedSubview(makeStateLabel(service.isBrowsingAuthorWorkshop ? "抓取作者工坊信息失败" : "抓取创意工坊信息失败", weight: .semibold))
        let messageLabel = makeStateLabel(message)
        messageLabel.maximumNumberOfLines = 0
        stack.addArrangedSubview(messageLabel)

        let retryButton = NSButton(title: "重试", target: self, action: #selector(retryBrowserFetch))
        retryButton.bezelStyle = .rounded
        stack.addArrangedSubview(retryButton)
        return stack
    }

    private func makeCenteredStateView(symbolName: String, message: String) -> NSView {
        let stack = makeCenteredStack(spacing: 10)
        stack.addArrangedSubview(makeSymbol(symbolName, pointSize: 32))
        let label = makeStateLabel(message)
        label.maximumNumberOfLines = 0
        stack.addArrangedSubview(label)
        return stack
    }

    private func makeCenteredStack(spacing: CGFloat) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func makeStateLabel(_ text: String, weight: NSFont.Weight = .regular) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.alignment = .center
        label.font = .systemFont(ofSize: 13, weight: weight)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byWordWrapping
        label.widthAnchor.constraint(lessThanOrEqualToConstant: 420).isActive = true
        return label
    }

    private func makeSymbol(_ name: String, pointSize: CGFloat) -> NSImageView {
        let imageView = NSImageView()
        imageView.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        imageView.contentTintColor = .secondaryLabelColor
        return imageView
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
              request.token.module == .steamWorkshop else {
            return
        }

        isHandlingHostClose = true
        visibleCardID = nil
        lastRequestedCardID = nil
        removeInspectorContent()
        service.dismissItemDetail()
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
            detailView = existing
        } else {
            let created = AppKitSteamWorkshopItemDetailView(item: item)
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

    private func presentPendingDownloadErrorIfNeeded() {
        guard let message = service.downloadError, !message.isEmpty else { return }
        guard !isShowingDownloadError else { return }
        guard let window else { return }

        isShowingDownloadError = true
        let alert = NSAlert()
        alert.messageText = "下载失败"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "确定")
        alert.beginSheetModal(for: window) { [weak self] _ in
            guard let self else { return }
            self.service.downloadError = nil
            self.isShowingDownloadError = false
        }
    }

    @objc private func retryBrowserFetch() {
        service.refresh()
    }
}
