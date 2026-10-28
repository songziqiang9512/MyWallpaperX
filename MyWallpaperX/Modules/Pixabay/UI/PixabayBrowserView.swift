//
//  PixabayBrowserView.swift
//  MyWallpaperX — Modules/Pixabay/UI
//

import AppKit
import Combine

final class PixabayBrowserView: NSView, ListThumbnailTintProviding {
    let listThumbnailTintSource = ListThumbnailTintSource()
    var preferredColumns = 5 {
        didSet { currentGrid?.preferredColumns = preferredColumns }
    }
    var clipWidth: CGFloat { currentGrid?.window == nil ? 0 : currentGrid?.clipWidth ?? 0 }
    var onClipWidthChange: ((CGFloat) -> Void)? {
        didSet { onClipWidthChange?(clipWidth) }
    }
    var makeOrganization: ((PixabayVideoItem) -> WallpaperInspectorActions?)? {
        didSet { currentGrid?.makeOrganization = makeOrganization }
    }
    var onInspect: ((PixabayVideoItem) -> Void)? {
        didSet { currentGrid?.onInspect = onInspect }
    }
    var onSelectionChange: ((PixabayVideoItem?) -> Void)? {
        didSet { currentGrid?.onSelectionChange = onSelectionChange }
    }
    var selectedItem: PixabayVideoItem? { currentGrid?.selectedItem }
    var selectedPrimaryAction: (() -> Void)? { currentGrid?.selectedPrimaryAction }
    @discardableResult func inspectSelectedItem() -> Bool { currentGrid?.inspectSelectedItem() == true }
    var opensDetailsOnSingleClick: () -> Bool = { false } {
        didSet { currentGrid?.opensDetailsOnSingleClick = opensDetailsOnSingleClick }
    }
    func refreshOrganization() { currentGrid?.refreshOrganization() }
    private let service = PixabayService.shared
    private let contentHost = NSView()
    private var currentState: PixabayBrowserContentState?
    private weak var currentGrid: AppKitPixabayBrowserContainerView?
    private let notice = WallpaperGridNoticeView()
    private var lastGridError: String?
    private var cancellables = Set<AnyCancellable>()
    private var keyPanel: WallpaperAPIKeyPanelController?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
        observeService()
        triggerInitialSearchIfNeeded()
        syncContent(force: true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onClipWidthChange?(clipWidth)
        guard window != nil else { return }
        triggerInitialSearchIfNeeded()
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
        notice.attach(to: self)
    }

    private func observeService() {
        service.$items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncContent() }
            .store(in: &cancellables)

        service.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncContent() }
            .store(in: &cancellables)

        service.$errorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncContent() }
            .store(in: &cancellables)

        service.$downloadError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                guard let message, !message.isEmpty else { return }
                self?.presentDownloadError(message)
            }
            .store(in: &cancellables)

        service.$downloadSuccessMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                guard let self, let message, !message.isEmpty else { return }
                self.presentDownloadToast(message: message)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .pixabayShowAPIKeySettings)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.presentAPIKeyEdit() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .pixabayClearAPIKey)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.service.clearAPIKeyAndReset()
                self?.syncContent(force: true)
            }
            .store(in: &cancellables)
    }

    private func triggerInitialSearchIfNeeded() {
        guard service.hasValidAPIKey, !service.hasLoadedOnce, !service.isLoading else { return }
        service.searchWithCurrentContext(order: .popular)
    }

    private func contentState() -> PixabayBrowserContentState {
        if !service.hasValidAPIKey {
            return .apiKeyPrompt
        }
        if service.isLoading && service.items.isEmpty {
            return .loadingInitial
        }
        if let error = service.errorMessage, service.items.isEmpty {
            return .initialError(error)
        }
        if service.items.isEmpty {
            return service.hasLoadedOnce ? .emptyLoaded : .startPrompt
        }
        return .grid
    }

    private func syncContent(force: Bool = false) {
        let nextState = contentState()
        if !force, nextState == currentState {
            updateGridNoticeIfNeeded()
            return
        }

        listThumbnailTintSource.forward(from: nil)
        currentState = nextState
        if currentGrid != nil { onSelectionChange?(nil) }
        currentGrid = nil
        onClipWidthChange?(0)
        contentHost.subviews.forEach { $0.removeFromSuperview() }

        let contentView: NSView
        let fillsHost: Bool
        switch nextState {
        case .apiKeyPrompt:
            contentView = makeAPIKeyPromptView()
            fillsHost = false
        case .loadingInitial:
            contentView = PixabayBrowserViews.makeLoadingState(title: "加载中...")
            fillsHost = false
        case .initialError(let message):
            contentView = makeErrorStateView(message: message)
            fillsHost = false
        case .emptyLoaded:
            contentView = PixabayBrowserViews.makeCenteredStateView(
                symbolName: "video.slash",
                title: "没有找到相关视频",
                message: "试试其他关键词或分类"
            )
            fillsHost = false
        case .startPrompt:
            contentView = makeStartPromptView()
            fillsHost = false
        case .grid:
            contentView = makeGridContentView()
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

    private func makeAPIKeyPromptView() -> NSView {
        let stack = PixabayBrowserViews.makeCenteredStack(spacing: 20)
        stack.edgeInsets = NSEdgeInsets(top: 40, left: 40, bottom: 40, right: 40)

        stack.addArrangedSubview(PixabayBrowserViews.makeSymbol("key.fill", pointSize: 44, color: .controlAccentColor))
        stack.addArrangedSubview(PixabayBrowserViews.makeLabel("需要 API Key", font: .systemFont(ofSize: 16, weight: .semibold), color: .labelColor))

        let message = PixabayBrowserViews.makeLabel(
            "请前往 Pixabay 获取免费 API Key，即可开始浏览 Pixabay 视频。",
            font: .systemFont(ofSize: 13),
            color: .secondaryLabelColor
        )
        message.alignment = .center
        message.maximumNumberOfLines = 0
        stack.addArrangedSubview(message)
        message.widthAnchor.constraint(lessThanOrEqualToConstant: 360).isActive = true

        let button = PixabayBrowserViews.makeButton(title: "填写 API Key", target: self, action: #selector(presentAPIKeyEdit))
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        stack.addArrangedSubview(button)
        return stack
    }

    private func makeErrorStateView(message: String) -> NSView {
        let stack = PixabayBrowserViews.makeCenteredStateView(
            symbolName: "wifi.exclamationmark",
            title: message,
            message: nil
        )

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 12
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.addArrangedSubview(PixabayBrowserViews.makeButton(title: "重试", target: self, action: #selector(retrySearch)))
        if message.contains("API Key") {
            buttonRow.addArrangedSubview(PixabayBrowserViews.makeButton(title: "更改 API Key", target: self, action: #selector(presentAPIKeyEditFromAction)))
        }
        stack.addArrangedSubview(buttonRow)
        return stack
    }

    private func makeStartPromptView() -> NSView {
        let stack = PixabayBrowserViews.makeCenteredStateView(
            symbolName: "play.rectangle.on.rectangle",
            title: "探索 Pixabay 海量免费视频",
            message: nil
        )
        stack.addArrangedSubview(
            PixabayBrowserViews.makeButton(title: "开始浏览", target: self, action: #selector(startBrowsing))
        )
        return stack
    }

    private func makeGridContentView() -> NSView {
        updateGridNoticeIfNeeded()

        let grid = AppKitPixabayBrowserContainerView(
            service: service,
            onDownload: { [weak self] item in self?.service.download(item: item) },
            onSetAsWallpaper: { [weak self] item in self?.service.downloadAndSet(item: item) }
        )
        grid.makeOrganization = makeOrganization
        grid.onInspect = onInspect
        grid.onSelectionChange = onSelectionChange
        grid.opensDetailsOnSingleClick = opensDetailsOnSingleClick
        grid.preferredColumns = preferredColumns
        grid.onClipWidthChange = { [weak self, weak grid] width in
            guard let self, self.currentGrid === grid else { return }
            self.onClipWidthChange?(width)
        }
        currentGrid = grid
        listThumbnailTintSource.forward(from: grid.listThumbnailTintSource)
        grid.translatesAutoresizingMaskIntoConstraints = false
        return grid
    }

    private func updateGridNoticeIfNeeded() {
        let message = service.items.isEmpty ? nil : service.errorMessage
        guard message != lastGridError else { return }
        let previous = lastGridError
        lastGridError = message
        if let message {
            notice.update(messages: [message], actions: [("重试", { [weak self] in self?.service.searchWithCurrentContext() })])
        } else if let previous { notice.clear(message: previous) }
    }

    @objc private func retrySearch() {
        service.searchWithCurrentContext()
    }

    @objc private func startBrowsing() {
        service.searchWithCurrentContext(order: .popular)
    }

    @objc private func presentAPIKeyEditFromAction() {
        presentAPIKeyEdit()
    }

    @objc private func presentAPIKeyEdit() {
        guard let host = window ?? appModalHostWindow() else { return }
        if keyPanel == nil {
            keyPanel = WallpaperAPIKeyPanelController(title: "Pixabay API Key",
                message: "填写 Pixabay 账号的 API Key 后即可浏览和下载视频。保存后会刷新当前列表。",
                helpURL: URL(string: "https://pixabay.com/api/docs/")!, hasStoredKey: service.hasValidAPIKey) { [weak self] key in
                    guard let self else { return }
                    if let key {
                        service.setAPIKeyAndSearch(key)
                    } else { service.clearAPIKeyAndReset() }
                    syncContent(force: true)
                }
        }
        guard let controller = keyPanel else { return }
        controller.present(in: host) { [weak self, weak controller] in
            guard let self, let controller, keyPanel === controller else { return }
            keyPanel = nil
        }
    }

    private func presentDownloadError(_ message: String) {
        notice.update(messages: [])
        notice.update(messages: [message], showsClose: true) { [weak self] in self?.service.downloadError = nil }
    }

    private func presentDownloadToast(message: String) {
        notice.update(messages: [])
        notice.update(messages: [message], actions: [("设为壁纸", { [weak self] in
            guard let self else { return }
            if let id = service.lastDownloadedItemID { service.setLocalFileAsWallpaper(id: id) }
            notice.clear(message: message)
            service.downloadSuccessMessage = nil
            service.lastDownloadedItemID = nil
        })], showsClose: true) { [weak self] in
            self?.service.downloadSuccessMessage = nil
            self?.service.lastDownloadedItemID = nil
        }
    }
}
