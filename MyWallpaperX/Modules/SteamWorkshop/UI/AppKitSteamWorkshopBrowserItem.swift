//
//  AppKitSteamWorkshopBrowserItem.swift
//  MyWallpaperX
//

import AppKit
import Combine
import QuartzCore

final class AppKitSteamWorkshopBrowserItem: NSCollectionViewItem {
    static let hoverScale: CGFloat = 1.03
    static let pressedScale: CGFloat = 0.98
    private var cancellables = Set<AnyCancellable>()

    let cardView = AppearanceAwareContainerView()
    let hoverOutlineView = NSView()
    let previewContainer = NSView()
    let previewImageView = NSImageView()
    let previewPlaceholderView = SteamWorkshopPreviewPlaceholderView()
    let multiSelectBadgeView = NSView()
    let multiSelectBadgeIcon = NSImageView()
    let overlayBarShadowView = NSView()
    let overlayBar = SteamWorkshopGlassBarView()
    let detailButton = SteamWorkshopOverlayIconButton()
    let titleMarqueeView = SteamWorkshopMarqueeTextView()
    let statusBadgeButton = SteamWorkshopOverlayIconButton()

    var previewLoadCancellation: SteamWorkshopPreviewLoadCancellation?
    var previewRetryTask: Task<Void, Never>?
    var currentPreviewURL: URL?
    var isPreviewLoadInFlight = false
    private var currentPreviewSourceURL: URL?
    private var currentDownloadVideoURL: URL?
    private var isPlayingRecord = false
    private var currentTitleText = ""
    private var onOpen: (() -> Void)?
    private var onDownload: (() -> Void)?
    private var onSetAsWallpaper: (() -> Void)?
    private var onCancelDownload: (() -> Void)?
    private var currentActionKind: ActionKind = .download
    var prefersCircularPlayBadge = false
    /// M0.5：本卡片"设为壁纸"是否处于 pending（渲染加载态图标）。
    private var isLaunchPendingBadge = false
    var trackingAreaRef: NSTrackingArea?
    var isHovering = false
    var isPressingCard = false
    var currentCardScale: CGFloat = 1.0
    var currentBarVisibility = false
    var isHoverOutlineVisible = false
    var isSelectionHighlighted = false
    var isMultiSelectMode = false
    var currentDisplayContext: DisplayContext = .browser
    var currentBarState: BarState = .idle
    var shouldPersistBarVisibility = false
    private var currentDebugID = ""
    var isPreviewVisible = false
    private weak var downloadProgressStore: SteamWorkshopDownloadProgressStore?
    private var downloadProgressObserverID: UUID?
    private var boundProgressItemID: String?
    var currentProgressSnapshot: SteamWorkshopDownloadProgressSnapshot?
    private var currentItem: SteamWorkshopBrowserItem?
    private var currentDownloadRecord: SteamWorkshopDownloadRecord?
    private var currentIsDownloading = false
    private var currentIsDownloaded = false
    private var currentIsKeyboardFocused = false
    private var progressAccessibilityBucket: Int?
    private var progressAccessibilityPhase: SteamWorkshopDownloadProgressSnapshot.Phase?

    private enum ActionKind {
        case download
        case cancel
        case setAsWallpaper
        case retry
        case saving
        case stop
    }

    enum DisplayContext {
        case browser
        case downloads
    }

    enum BarState {
        case idle
        case queued
        case connecting
        case preparing
        case transferring
        case validating
        case saving
        case waiting
        case ready
        case failed
    }

    enum Layout {
        static let cardCornerRadius: CGFloat = 14
        static let referenceCardWidth: CGFloat = 250
        static let cardInset: CGFloat = 2
        static let barHorizontalInset: CGFloat = 8
        static let barBottomInset: CGFloat = 11
        static let hoverLift: CGFloat = 2
        static let barHeight: CGFloat = 34
        static let iconButtonSize: CGFloat = 30
        static let statusBadgeSize: CGFloat = 30
        static let barEdgeInset: CGFloat = 8
        static let barSpacing: CGFloat = 8
        static let marqueeSideInset: CGFloat = 2
        static let minBarCornerInset: CGFloat = 4
    }

    struct Metrics {
        let scale: CGFloat
        let barHorizontalInset: CGFloat
        let barBottomInset: CGFloat
        let barHeight: CGFloat
        let iconButtonSize: CGFloat
        let badgeSize: CGFloat
        let barEdgeInset: CGFloat
        let barSpacing: CGFloat
        let marqueeSideInset: CGFloat
        let titleFont: NSFont
        let buttonCornerRadius: CGFloat
    }

    override init(nibName: NSNib.Name?, bundle: Bundle?) {
        super.init(nibName: nibName, bundle: bundle)
        // 订阅状态变化（含其他入口触发的订阅）实时刷新卡片 bar 心形。
        SteamWorkshopService.shared.steamSubscriptions.$states
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshSubscribeHeart() }
            .store(in: &cancellables)
        SteamWorkshopService.shared.$source
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshSubscribeHeart() }
            .store(in: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        let root = SteamWorkshopCardAccessibilityView()
        root.onPress = { [weak self] in self?.onOpen?() }
        view = root
        buildHierarchy()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        unbindDownloadProgress()
        previewLoadCancellation?.cancel()
        previewLoadCancellation = nil
        currentPreviewURL = nil
        isPreviewLoadInFlight = false
        currentDownloadVideoURL = nil
        currentTitleText = ""
        titleMarqueeView.text = ""
        previewImageView.image = nil
        onOpen = nil
        onDownload = nil
        onSetAsWallpaper = nil
        onCancelDownload = nil
        currentActionKind = .download
        prefersCircularPlayBadge = false
        isHovering = false
        isPressingCard = false
        currentCardScale = 1.0
        currentBarVisibility = false
        isHoverOutlineVisible = false
        isSelectionHighlighted = false
        isMultiSelectMode = false
        currentDisplayContext = .browser
        currentBarState = .idle
        shouldPersistBarVisibility = false
        currentDebugID = ""
        isPreviewVisible = false
        currentItem = nil
        currentDownloadRecord = nil
        currentIsDownloading = false
        currentIsDownloaded = false
        currentIsKeyboardFocused = false
        currentProgressSnapshot = nil
        progressAccessibilityBucket = nil
        progressAccessibilityPhase = nil
        cardView.layer?.transform = CATransform3DIdentity
        overlayBar.alphaValue = 0
        hoverOutlineView.alphaValue = 0
        titleMarqueeView.setActive(false)
        overlayBar.setProgressAnimationVisible(false)
        overlayBar.applyProgress(style: .neutral, fraction: nil, indeterminate: false, animated: false)
        statusBadgeButton.layer?.removeAnimation(forKey: "steam.status.spin")
        previewRetryTask?.cancel()
        refreshThemeAwareAppearance()
    }

    func configure(
        displayContext: DisplayContext = .browser,
        isPlaying: Bool = false,
        item: SteamWorkshopBrowserItem,
        downloadRecord: SteamWorkshopDownloadRecord?,
        downloadProgressStore: SteamWorkshopDownloadProgressStore,
        isDownloading: Bool,
        isDownloaded: Bool,
        isMultiSelectMode: Bool = false,
        isKeyboardFocused: Bool,
        onOpen: @escaping () -> Void,
        onDownload: @escaping () -> Void,
        onSetAsWallpaper: @escaping () -> Void,
        onCancelDownload: @escaping () -> Void
    ) {
        self.onOpen = onOpen
        self.onDownload = onDownload
        self.onSetAsWallpaper = onSetAsWallpaper
        self.onCancelDownload = onCancelDownload
        currentDisplayContext = displayContext
        isPlayingRecord = isPlaying && displayContext == .downloads
        currentDownloadVideoURL = downloadRecord?.videoURL
        currentPreviewSourceURL = item.previewImageURL
        currentDebugID = item.id
        currentItem = item
        (view as? SteamWorkshopCardAccessibilityView)?.onMenu = { [weak self] in
            guard let self, let item = self.currentItem, self.currentDisplayContext == .browser else { return nil }
            return SteamWorkshopItemMenu.make(item: item, service: SteamWorkshopService.shared)
        }
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        view.setAccessibilityLabel(item.title)
        view.setAccessibilityCustomActions([
            NSAccessibilityCustomAction(name: "查看详情", handler: { [weak self] in
                self?.onOpen?()
                return self != nil
            })
        ] + (displayContext == .browser ? [
            NSAccessibilityCustomAction(name: "作品操作菜单", handler: { [weak self] in
                guard let self, self.currentDisplayContext == .browser,
                      let item = self.currentItem else { return false }
                SteamWorkshopItemMenu.make(item: item, service: SteamWorkshopService.shared)
                    .popUp(positioning: nil, at: NSPoint(x: self.view.bounds.midX, y: self.view.bounds.midY), in: self.view)
                return true
            })
        ] : []))
        currentDownloadRecord = downloadRecord
        currentIsDownloading = isDownloading
        currentIsDownloaded = isDownloaded
        self.isMultiSelectMode = isMultiSelectMode
        currentIsKeyboardFocused = isKeyboardFocused
        prefersCircularPlayBadge = false
        syncPreviewAnimationState()
        bindDownloadProgress(to: downloadProgressStore, itemID: item.id)
        loadPreview(from: item.previewImageURL, fallbackVideoURL: currentDownloadVideoURL)
    }

    func configureMetadataOnly(
        displayContext: DisplayContext = .browser,
        isPlaying: Bool = false,
        item: SteamWorkshopBrowserItem,
        downloadRecord: SteamWorkshopDownloadRecord?,
        downloadProgressStore: SteamWorkshopDownloadProgressStore,
        isDownloading: Bool,
        isDownloaded: Bool,
        isMultiSelectMode: Bool = false,
        isKeyboardFocused: Bool,
        onOpen: @escaping () -> Void,
        onDownload: @escaping () -> Void,
        onSetAsWallpaper: @escaping () -> Void,
        onCancelDownload: @escaping () -> Void
    ) {
        self.onOpen = onOpen
        self.onDownload = onDownload
        self.onSetAsWallpaper = onSetAsWallpaper
        self.onCancelDownload = onCancelDownload
        currentDisplayContext = displayContext
        isPlayingRecord = isPlaying && displayContext == .downloads
        currentDownloadVideoURL = downloadRecord?.videoURL
        currentPreviewSourceURL = item.previewImageURL
        currentDebugID = item.id
        currentItem = item
        (view as? SteamWorkshopCardAccessibilityView)?.onMenu = { [weak self] in
            guard let self, let item = self.currentItem, self.currentDisplayContext == .browser else { return nil }
            return SteamWorkshopItemMenu.make(item: item, service: SteamWorkshopService.shared)
        }
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        view.setAccessibilityLabel(item.title)
        view.setAccessibilityCustomActions([
            NSAccessibilityCustomAction(name: "查看详情", handler: { [weak self] in
                self?.onOpen?()
                return self != nil
            })
        ] + (displayContext == .browser ? [
            NSAccessibilityCustomAction(name: "作品操作菜单", handler: { [weak self] in
                guard let self, self.currentDisplayContext == .browser,
                      let item = self.currentItem else { return false }
                SteamWorkshopItemMenu.make(item: item, service: SteamWorkshopService.shared)
                    .popUp(positioning: nil, at: NSPoint(x: self.view.bounds.midX, y: self.view.bounds.midY), in: self.view)
                return true
            })
        ] : []))
        currentDownloadRecord = downloadRecord
        currentIsDownloading = isDownloading
        currentIsDownloaded = isDownloaded
        self.isMultiSelectMode = isMultiSelectMode
        currentIsKeyboardFocused = isKeyboardFocused
        prefersCircularPlayBadge = false
        syncPreviewAnimationState()
        bindDownloadProgress(to: downloadProgressStore, itemID: item.id)
        loadPreview(from: item.previewImageURL, fallbackVideoURL: currentDownloadVideoURL)
    }

    override func viewDidLayout() {
        super.viewDidLayout()

        let bounds = view.bounds
        guard bounds.width.isFinite, bounds.height.isFinite else { return }
        cardView.frame = bounds.insetBy(dx: Layout.cardInset, dy: Layout.cardInset)
        ensureCardAnchorCenteredIfNeeded()

        let metrics = metrics(for: cardView.bounds.size)
        applyMetrics(metrics)

        previewContainer.frame = cardView.bounds
        hoverOutlineView.frame = cardView.bounds
        updatePreviewImageFrame()

        let barWidth = max(0, cardView.bounds.width - metrics.barHorizontalInset * 2)
        let barFrame = CGRect(
            x: metrics.barHorizontalInset,
            y: metrics.barBottomInset,
            width: barWidth,
            height: metrics.barHeight
        )
        overlayBarShadowView.frame = barFrame
        overlayBar.frame = barFrame

        let iconSize = metrics.iconButtonSize
        let barMidY = floor((overlayBar.bounds.height - iconSize) * 0.5)
        let statusBadgeX = overlayBar.bounds.width - iconSize - metrics.barEdgeInset
        statusBadgeButton.frame = CGRect(
            x: statusBadgeX,
            y: barMidY,
            width: iconSize,
            height: iconSize
        )
        let detailButtonX = metrics.barEdgeInset
        detailButton.frame = CGRect(
            x: detailButtonX,
            y: barMidY,
            width: iconSize,
            height: iconSize
        )
        let marqueeX = detailButton.frame.maxX + metrics.barSpacing
        let marqueeWidth = max(24, statusBadgeButton.frame.minX - metrics.barSpacing - marqueeX)
        titleMarqueeView.frame = CGRect(
            x: marqueeX + metrics.marqueeSideInset,
            y: 0,
            width: max(24, marqueeWidth - metrics.marqueeSideInset * 2),
            height: overlayBar.bounds.height
        )
        statusBadgeButton.ensureLayerAnchorCentered()

        let badgeSize = max(22, min(28, cardView.bounds.width * 0.12))
        let badgeOrigin: CGPoint
        if currentDisplayContext == .downloads && isMultiSelectMode {
            badgeOrigin = CGPoint(
                x: floor((cardView.bounds.width - badgeSize) * 0.5),
                y: floor((cardView.bounds.height - badgeSize) * 0.5)
            )
        } else {
            badgeOrigin = CGPoint(x: 10, y: cardView.bounds.height - badgeSize - 10)
        }
        multiSelectBadgeView.frame = CGRect(origin: badgeOrigin, size: CGSize(width: badgeSize, height: badgeSize))
        multiSelectBadgeIcon.frame = multiSelectBadgeView.bounds.insetBy(dx: 5, dy: 5)

        applyHoverStyle(animated: false)
        refreshTrackingArea()
        syncHoverStateFromWindow(animated: false)
    }

    func forceReloadPreview() {
        previewRetryTask?.cancel()
        previewLoadCancellation?.cancel()
        previewLoadCancellation = nil

        if let currentPreviewSourceURL, !currentPreviewSourceURL.isFileURL {
            let cacheKey = steamWorkshopPreviewCacheKey(for: currentPreviewSourceURL)
            SteamWorkshopPreviewImageCache.shared.remove(forKey: cacheKey)
            SteamWorkshopPreviewRequestCoordinator.shared.resetFailureState(for: currentPreviewSourceURL)
        }

        currentPreviewURL = nil
        previewImageView.image = nil
        loadPreview(from: currentPreviewSourceURL, fallbackVideoURL: currentDownloadVideoURL)
    }

    func setKeyboardFocus(_ focused: Bool) {
        currentIsKeyboardFocused = focused
        isSelectionHighlighted = focused
        refreshThemeAwareAppearance()
        if view.window != nil {
            applyHoverStyle(animated: false)
        }
        if focused {
            syncHoverStateFromWindow(animated: false)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        syncHoverState(with: event, animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        syncHoverState(with: event, animated: true)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        syncHoverState(with: event, animated: true)
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
    }

    private func bindDownloadProgress(to store: SteamWorkshopDownloadProgressStore, itemID: String) {
        if downloadProgressStore === store, boundProgressItemID == itemID {
            receiveDownloadProgress(store.snapshot(for: itemID))
            return
        }
        unbindDownloadProgress()
        downloadProgressStore = store
        boundProgressItemID = itemID
        currentProgressSnapshot = nil
        progressAccessibilityBucket = nil
        progressAccessibilityPhase = nil
        downloadProgressObserverID = store.addObserver(for: itemID, owner: self) { [weak self] snapshot in
            self?.receiveDownloadProgress(snapshot)
        }
    }

    private func unbindDownloadProgress() {
        if let downloadProgressObserverID {
            downloadProgressStore?.removeObserver(downloadProgressObserverID)
        }
        downloadProgressObserverID = nil
        downloadProgressStore = nil
        boundProgressItemID = nil
    }

    private func receiveDownloadProgress(_ snapshot: SteamWorkshopDownloadProgressSnapshot?) {
        guard snapshot?.itemID == boundProgressItemID || snapshot == nil else { return }
        let previous = currentProgressSnapshot
        currentProgressSnapshot = snapshot
        applyCurrentContent()
        updateProgressAccessibility(previous: previous, current: snapshot)
    }

    private func applyCurrentContent() {
        guard let currentItem else { return }
        applyContent(
            item: currentItem,
            downloadRecord: currentDownloadRecord,
            isDownloading: currentIsDownloading,
            isDownloaded: currentIsDownloaded,
            isMultiSelectMode: isMultiSelectMode,
            isKeyboardFocused: currentIsKeyboardFocused
        )
    }

    private func updateProgressAccessibility(
        previous: SteamWorkshopDownloadProgressSnapshot?,
        current: SteamWorkshopDownloadProgressSnapshot?
    ) {
        let value = current?.statusText() ?? currentTitleText
        overlayBar.setAccessibilityValue(value)
        let bucket = current?.percent.map { $0 / 10 }
        let phase = current?.phase
        let shouldAnnounce = previous != nil
            && (phase != progressAccessibilityPhase || bucket != progressAccessibilityBucket)
        progressAccessibilityPhase = phase
        progressAccessibilityBucket = bucket
        if shouldAnnounce, view.window != nil {
            NSAccessibility.post(element: overlayBar, notification: .valueChanged)
        }
    }

    private func applyContent(
        item: SteamWorkshopBrowserItem,
        downloadRecord: SteamWorkshopDownloadRecord?,
        isDownloading: Bool,
        isDownloaded: Bool,
        isMultiSelectMode: Bool,
        isKeyboardFocused: Bool
    ) {
        let barState = resolvedBarState(
            downloadRecord: downloadRecord,
            isDownloading: isDownloading,
            isDownloaded: isDownloaded
        )
        currentBarState = barState
        shouldPersistBarVisibility = shouldPersistBar(for: barState)
        isSelectionHighlighted = isKeyboardFocused
        self.isMultiSelectMode = isMultiSelectMode
        let displayTitle = resolvedDisplayTitle(item: item, downloadRecord: downloadRecord, barState: barState)
        currentTitleText = item.title
        titleMarqueeView.text = displayTitle
        detailButton.setAccessibilityLabel("订阅：\(item.title)")
        statusBadgeButton.toolTip = currentProgressSnapshot?.failureMessage ?? downloadRecord?.failureMessage

        currentActionKind = resolvedActionKind(
            downloadRecord: downloadRecord,
            isDownloading: isDownloading,
            isDownloaded: isDownloaded
        )
        if isPlayingRecord {
            // 正在播放：bar 常显、淡红底、按钮切换为停止。
            currentActionKind = .stop
            shouldPersistBarVisibility = true
            overlayBar.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.2).cgColor
        } else if overlayBar.layer?.backgroundColor != NSColor.clear.cgColor {
            overlayBar.layer?.backgroundColor = NSColor.clear.cgColor
        }
        isLaunchPendingBadge = downloadRecord.map {
            SteamWorkshopService.shared.isLaunchPending($0.id)
        } ?? false
        applyStatusBadgeAppearance(
            actionKind: currentActionKind,
            itemTitle: item.title,
            isLaunchPending: isLaunchPendingBadge
        )

        refreshThemeAwareAppearance()
        refreshSubscribeHeart()
        if view.window != nil {
            applyHoverStyle(animated: false)
        } else {
            updateContinuousAnimationState()
        }
    }

    private func resolvedBarState(
        downloadRecord: SteamWorkshopDownloadRecord?,
        isDownloading: Bool,
        isDownloaded: Bool
    ) -> BarState {
        if let phase = currentProgressSnapshot?.phase {
            switch phase {
            case .connecting: return .connecting
            case .preparing: return .preparing
            case .transferring: return .transferring
            case .validating: return .validating
            case .saving: return .saving
            case .waiting: return .waiting
            case .failed: return .failed
            }
        }
        if isDownloading || downloadRecord?.status == .downloading {
            return .connecting
        }
        if downloadRecord?.status == .queued {
            return .queued
        }
        if isDownloaded || downloadRecord?.status == .ready {
            return .ready
        }
        if downloadRecord?.failureMessage != nil {
            return .failed
        }
        return .idle
    }

    private func resolvedDisplayTitle(
        item: SteamWorkshopBrowserItem,
        downloadRecord: SteamWorkshopDownloadRecord?,
        barState: BarState
    ) -> String {
        let trimmedRecordSize = downloadRecord?.sizeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let sizeText = (trimmedRecordSize?.isEmpty == false ? trimmedRecordSize : nil)
            ?? item.fileSizeText
            ?? "未知大小"

        switch barState {
        case .connecting, .preparing, .transferring, .validating, .saving, .waiting:
            let compact = view.bounds.width > 0 && view.bounds.width < 230
            return currentProgressSnapshot?.statusText(compact: compact) ?? "下载中  ·  \(sizeText)"
        case .queued:
            return "等待下载  ·  \(sizeText)"
        case .failed:
            return currentProgressSnapshot?.statusText() ?? "下载失败 · 重试"
        case .idle, .ready:
            return item.title
        }
    }

    private func shouldPersistBar(for state: BarState) -> Bool {
        if currentDisplayContext == .downloads && isMultiSelectMode {
            return false
        }
        switch state {
        case .queued, .connecting, .preparing, .transferring, .validating, .saving, .waiting, .failed:
            return true
        case .ready:
            return currentDisplayContext == .browser
        case .idle:
            return false
        }
    }

    private func resolvedActionKind(
        downloadRecord: SteamWorkshopDownloadRecord?,
        isDownloading: Bool,
        isDownloaded: Bool
    ) -> ActionKind {
        if let phase = currentProgressSnapshot?.phase {
            switch phase {
            case .saving:
                return .saving
            case .failed:
                return .retry
            case .connecting, .preparing, .transferring, .validating, .waiting:
                return .cancel
            }
        }
        if isDownloading || downloadRecord?.status == .queued {
            return .cancel
        }
        if let downloadRecord,
           downloadRecord.status == .ready,
           case .missing = downloadRecord.dependencyStatus {
            return .setAsWallpaper
        }
        if isDownloaded {
            return .setAsWallpaper
        }
        if downloadRecord?.failureMessage != nil {
            return .retry
        }
        return .download
    }

    private func applyStatusBadgeAppearance(
        actionKind: ActionKind,
        itemTitle: String,
        isLaunchPending: Bool = false
    ) {
        let symbolName: String
        let tintColor: NSColor
        let accessibilityLabel: String

        switch actionKind {
        case .download:
            symbolName = "square.and.arrow.down"
            tintColor = .white
            accessibilityLabel = "下载：\(itemTitle)"
        case .cancel:
            symbolName = "xmark"
            tintColor = .white
            accessibilityLabel = "取消下载：\(itemTitle)"
        case .setAsWallpaper:
            if isLaunchPending {
                symbolName = "hourglass"
                accessibilityLabel = "正在切换壁纸：\(itemTitle)"
            } else {
                symbolName = "play.fill"
                accessibilityLabel = "设为壁纸：\(itemTitle)"
            }
            tintColor = .white
        case .retry:
            symbolName = "square.and.arrow.down"
            tintColor = .white
            accessibilityLabel = "重新下载：\(itemTitle)"
        case .saving:
            symbolName = "checkmark.circle"
            tintColor = .white
            accessibilityLabel = "正在保存：\(itemTitle)"
        case .stop:
            symbolName = "stop.fill"
            tintColor = .white
            accessibilityLabel = "停止播放：\(itemTitle)"
        }

        statusBadgeButton.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: accessibilityLabel
        )
        statusBadgeButton.iconTintColor = tintColor
        statusBadgeButton.setAccessibilityLabel(accessibilityLabel)
        statusBadgeButton.isEnabled = actionKind != .saving
        updateContinuousAnimationState()
    }

    func ensureCardAnchorCenteredIfNeeded() {
        cardView.ensureLayerAnchorCentered()
    }

    private func syncHoverState(with event: NSEvent, animated: Bool) {
        let localPoint = view.convert(event.locationInWindow, from: nil)
        let hoveringNow = view.bounds.contains(localPoint)
        guard hoveringNow != isHovering else { return }
        isHovering = hoveringNow
        applyHoverStyle(animated: animated)
    }

    private func syncHoverStateFromWindow(animated: Bool) {
        guard let window = view.window else { return }
        let localPoint = view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let hoveringNow = view.bounds.contains(localPoint)
        guard hoveringNow != isHovering else { return }
        isHovering = hoveringNow
        applyHoverStyle(animated: animated)
    }

    @objc private func handleOpen() {
        onOpen?()
    }

    /// 心形订阅：unknown 先拉取订阅状态，已知状态直接切换。
    @objc func handleSubscribeToggle() {
        guard let item = currentItem else { return }
        if currentDisplayContext == .downloads { onOpen?(); return }
        guard SteamWorkshopService.shared.steamAuth.isOnline else {
            SteamWorkshopService.shared.presentSteamLoginForUserAction(context: "订阅")
            return
        }
        let store = SteamWorkshopService.shared.steamSubscriptions
        switch store.state(for: item.id) {
        case .known:
            store.toggle(item.id)
        default:
            store.refresh(item.id)
        }
    }

    /// Subscription membership comes only from the account-scoped store.
    func refreshSubscribeHeart() {
        guard let item = currentItem else { return }
        guard currentDisplayContext == .browser else {
            detailButton.isEnabled = true
            detailButton.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "详细信息")
            detailButton.iconTintColor = .labelColor
            detailButton.setAccessibilityLabel("详细信息：\(item.title)")
            return
        }
        let store = SteamWorkshopService.shared.steamSubscriptions
        let state = store.state(for: item.id)
        let subscribed: Bool
        switch state {
        case .known(let value):
            subscribed = value
        default:
            subscribed = false
        }
        let busy = state == .loading || state == .writing || state == .reconciling
        detailButton.isEnabled = !busy
        detailButton.toolTip = nil
        detailButton.iconTintColor = subscribed ? .systemRed : .labelColor
        detailButton.image = NSImage(
            systemSymbolName: subscribed ? "heart.fill" : "heart",
            accessibilityDescription: subscribed ? "取消订阅" : "订阅"
        )
        detailButton.setAccessibilityLabel(busy ? "正在核对订阅：\(item.title)" : (subscribed ? "取消订阅：\(item.title)" : "订阅：\(item.title)"))
    }

    @objc func handleStatusAction() {
        switch currentActionKind {
        case .download, .retry:
            onDownload?()
        case .cancel:
            onCancelDownload?()
        case .setAsWallpaper:
            onSetAsWallpaper?()
        case .saving:
            break
        case .stop:
            if let record = currentDownloadRecord,
               SteamWorkshopService.shared.isRecordCurrentlyPlaying(record) {
                PlaybackCommandMultiplexer.shared.dispatch(
                    .stop,
                    to: record.contentType == .scene ? .scene : .video
                )
            }
        }
    }

    func setPrefersCircularPlayBadge(_ prefersCircularPlayBadge: Bool) {
        guard self.prefersCircularPlayBadge != prefersCircularPlayBadge else { return }
        self.prefersCircularPlayBadge = prefersCircularPlayBadge
        applyStatusBadgeAppearance(
            actionKind: currentActionKind,
            itemTitle: currentTitleText,
            isLaunchPending: isLaunchPendingBadge
        )
        if view.window != nil {
            refreshThemeAwareAppearance()
            view.needsLayout = true
        }
    }
}

/// The card itself opens details; secondary operations remain in its context menu.
private final class SteamWorkshopCardAccessibilityView: NSView {
    var onPress: (() -> Void)?
    var onMenu: (() -> NSMenu?)?
    override func menu(for event: NSEvent) -> NSMenu? { onMenu?() ?? super.menu(for: event) }
    override func accessibilityPerformPress() -> Bool {
        guard let onPress else { return false }
        onPress()
        return true
    }
}
