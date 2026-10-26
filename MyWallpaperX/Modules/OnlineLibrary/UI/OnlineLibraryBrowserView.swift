//
//  OnlineLibraryBrowserView.swift
//  MyWallpaperX — Modules/OnlineLibrary/UI
//

import AppKit
import Combine

final class OnlineLibraryBrowserView: NSView, ListThumbnailTintProviding {
    let listThumbnailTintSource = ListThumbnailTintSource()
    var preferredColumns = 5 {
        didSet { currentGrid?.preferredColumns = preferredColumns }
    }
    var clipWidth: CGFloat { currentGrid?.window == nil ? 0 : currentGrid?.clipWidth ?? 0 }
    var onClipWidthChange: ((CGFloat) -> Void)? {
        didSet { onClipWidthChange?(clipWidth) }
    }
    var makeOrganization: ((OnlineLibraryVideoItem) -> WallpaperInspectorActions?)? {
        didSet { currentGrid?.makeOrganization = makeOrganization }
    }
    func refreshOrganization() { currentGrid?.refreshOrganization() }
    private let service = OnlineLibraryService.shared
    private let contentHost = NSView()
    private var currentState: OnlineLibraryBrowserContentState?
    private var gridStack: NSStackView?
    private weak var currentGrid: AppKitOLBrowserContainerView?
    private var gridBannerView: NSView?
    private var toastView: OnlineLibraryDownloadToastView?
    private var toastDismissTask: Task<Void, Never>?
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

    deinit {
        toastDismissTask?.cancel()
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

        NotificationCenter.default.publisher(for: .olShowAPIKeySettings)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.presentAPIKeyEdit() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .olClearAPIKey)
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

    private func contentState() -> OnlineLibraryBrowserContentState {
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
            updateGridBannerIfNeeded()
            return
        }

        listThumbnailTintSource.forward(from: nil)
        currentState = nextState
        currentGrid = nil
        onClipWidthChange?(0)
        gridStack = nil
        gridBannerView = nil
        contentHost.subviews.forEach { $0.removeFromSuperview() }

        let contentView: NSView
        let fillsHost: Bool
        switch nextState {
        case .apiKeyPrompt:
            contentView = makeAPIKeyPromptView()
            fillsHost = false
        case .loadingInitial:
            contentView = OnlineLibraryBrowserViews.makeLoadingState(title: "加载中...")
            fillsHost = false
        case .initialError(let message):
            contentView = makeErrorStateView(message: message)
            fillsHost = false
        case .emptyLoaded:
            contentView = OnlineLibraryBrowserViews.makeCenteredStateView(
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
        let stack = OnlineLibraryBrowserViews.makeCenteredStack(spacing: 20)
        stack.edgeInsets = NSEdgeInsets(top: 40, left: 40, bottom: 40, right: 40)

        stack.addArrangedSubview(OnlineLibraryBrowserViews.makeSymbol("key.fill", pointSize: 44, color: .controlAccentColor))
        stack.addArrangedSubview(OnlineLibraryBrowserViews.makeLabel("需要 API Key", font: .systemFont(ofSize: 16, weight: .semibold), color: .labelColor))

        let message = OnlineLibraryBrowserViews.makeLabel(
            "请前往 Pixabay 获取免费 API Key，即可开始浏览 Pixabay 视频。",
            font: .systemFont(ofSize: 13),
            color: .secondaryLabelColor
        )
        message.alignment = .center
        message.maximumNumberOfLines = 0
        stack.addArrangedSubview(message)
        message.widthAnchor.constraint(lessThanOrEqualToConstant: 360).isActive = true

        let button = OnlineLibraryBrowserViews.makeButton(title: "填写 API Key", target: self, action: #selector(presentAPIKeyEdit))
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        stack.addArrangedSubview(button)
        return stack
    }

    private func makeErrorStateView(message: String) -> NSView {
        let stack = OnlineLibraryBrowserViews.makeCenteredStateView(
            symbolName: "wifi.exclamationmark",
            title: message,
            message: nil
        )

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 12
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.addArrangedSubview(OnlineLibraryBrowserViews.makeButton(title: "重试", target: self, action: #selector(retrySearch)))
        if message.contains("API Key") {
            buttonRow.addArrangedSubview(OnlineLibraryBrowserViews.makeButton(title: "更改 API Key", target: self, action: #selector(presentAPIKeyEditFromAction)))
        }
        stack.addArrangedSubview(buttonRow)
        return stack
    }

    private func makeStartPromptView() -> NSView {
        let stack = OnlineLibraryBrowserViews.makeCenteredStateView(
            symbolName: "play.rectangle.on.rectangle",
            title: "探索 Pixabay 海量免费视频",
            message: nil
        )
        stack.addArrangedSubview(
            OnlineLibraryBrowserViews.makeButton(title: "开始浏览", target: self, action: #selector(startBrowsing))
        )
        return stack
    }

    private func makeGridContentView() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        gridStack = stack

        updateGridBannerIfNeeded()

        let grid = AppKitOLBrowserContainerView(
            service: service,
            onDownload: { [weak self] item in self?.service.download(item: item) },
            onSetAsWallpaper: { [weak self] item in self?.service.downloadAndSet(item: item) }
        )
        grid.makeOrganization = makeOrganization
        grid.preferredColumns = preferredColumns
        grid.onClipWidthChange = { [weak self, weak grid] width in
            guard let self, self.currentGrid === grid else { return }
            self.onClipWidthChange?(width)
        }
        currentGrid = grid
        listThumbnailTintSource.forward(from: grid.listThumbnailTintSource)
        grid.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(grid)
        grid.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    private func updateGridBannerIfNeeded() {
        guard let gridStack else { return }
        if let message = service.errorMessage, !service.items.isEmpty {
            if let gridBannerView {
                (gridBannerView.viewWithTag(11) as? NSTextField)?.stringValue = message
                return
            }
            let banner = OnlineLibraryBrowserViews.makeErrorBanner(message: message, target: self, action: #selector(retrySearch))
            gridBannerView = banner
            gridStack.insertArrangedSubview(banner, at: 0)
            banner.widthAnchor.constraint(equalTo: gridStack.widthAnchor).isActive = true
        } else if let gridBannerView {
            gridStack.removeArrangedSubview(gridBannerView)
            gridBannerView.removeFromSuperview()
            self.gridBannerView = nil
        }
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
                        service.apiKey = key
                        service.resetLoadedState()
                        triggerInitialSearchIfNeeded()
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
        let alert = makeAppAlert(title: "下载失败", message: message)
        presentAppAlert(alert, in: window ?? appModalHostWindow()) { [weak self] _ in
            self?.service.downloadError = nil
        }
    }

    private func presentDownloadToast(message: String) {
        dismissToastNow(clearServiceState: false)
        let toast = OnlineLibraryDownloadToastView(
            message: message,
            onSetAsWallpaper: { [weak self] in
                guard let self else { return }
                if let id = self.service.lastDownloadedItemID {
                    self.service.setLocalFileAsWallpaper(id: id)
                }
                self.dismissToastNow(clearServiceState: true)
            },
            onDismiss: { [weak self] in
                self?.dismissToastNow(clearServiceState: true)
            },
            onHoverChange: { [weak self] hovering in
                if hovering {
                    self?.toastDismissTask?.cancel()
                    self?.toastDismissTask = nil
                } else {
                    self?.scheduleToastDismiss(after: 1.5)
                }
            }
        )
        toastView = toast
        addSubview(toast)
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            toast.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            toast.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
            toast.widthAnchor.constraint(lessThanOrEqualToConstant: 430)
        ])
        scheduleToastDismiss(after: 4)
    }

    private func scheduleToastDismiss(after seconds: TimeInterval) {
        toastDismissTask?.cancel()
        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            dismissToastNow(clearServiceState: true)
        }
    }

    private func dismissToastNow(clearServiceState: Bool) {
        toastDismissTask?.cancel()
        toastDismissTask = nil
        toastView?.removeFromSuperview()
        toastView = nil
        guard clearServiceState else { return }
        service.downloadSuccessMessage = nil
        service.lastDownloadedItemID = nil
    }
}
