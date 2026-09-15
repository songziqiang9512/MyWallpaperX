//
//  AppKitSteamWorkshopBrowserItem.swift
//  MyWallpaperX
//

import AppKit
import QuartzCore

final class AppKitSteamWorkshopBrowserItem: NSCollectionViewItem {
    static let hoverScale: CGFloat = 1.03
    private static let pressedScale: CGFloat = 0.98

    private let cardView = AppearanceAwareContainerView()
    private let hoverOutlineView = NSView()
    private let previewContainer = NSView()
    private let previewImageView = NSImageView()
    private let previewPlaceholderView = SteamWorkshopPreviewPlaceholderView()
    private let multiSelectBadgeView = NSView()
    private let multiSelectBadgeIcon = NSImageView()
    private let overlayBarShadowView = NSView()
    private let overlayBar = SteamWorkshopGlassBarView()
    private let detailButton = SteamWorkshopOverlayIconButton()
    private let titleMarqueeView = SteamWorkshopMarqueeTextView()
    private let statusBadgeButton = SteamWorkshopOverlayIconButton()

    private var previewLoadCancellation: SteamWorkshopPreviewLoadCancellation?
    private var previewRetryTask: Task<Void, Never>?
    private var currentPreviewURL: URL?
    private var isPreviewLoadInFlight = false
    private var currentPreviewSourceURL: URL?
    private var currentDownloadVideoURL: URL?
    private var currentTitleText = ""
    private var onOpen: (() -> Void)?
    private var onDownload: (() -> Void)?
    private var onSetAsWallpaper: (() -> Void)?
    private var onCancelDownload: (() -> Void)?
    private var currentActionKind: ActionKind = .download
    private var prefersCircularPlayBadge = false
    /// M0.5：本卡片"设为壁纸"是否处于 pending（渲染加载态图标）。
    private var isLaunchPendingBadge = false
    private var trackingAreaRef: NSTrackingArea?
    private var isHovering = false
    private var isPressingCard = false
    private var currentCardScale: CGFloat = 1.0
    private var currentBarVisibility = false
    private var isHoverOutlineVisible = false
    private var isSelectionHighlighted = false
    private var isMultiSelectMode = false
    private var currentDisplayContext: DisplayContext = .browser
    private var currentBarState: BarState = .idle
    private var shouldPersistBarVisibility = false
    private var currentDebugID = ""
    private var isPreviewVisible = false
    private weak var downloadProgressStore: SteamWorkshopDownloadProgressStore?
    private var downloadProgressObserverID: UUID?
    private var boundProgressItemID: String?
    private var currentProgressSnapshot: SteamWorkshopDownloadProgressSnapshot?
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
    }

    enum DisplayContext {
        case browser
        case downloads
    }

    private enum BarState {
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

    private enum Layout {
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

    private struct Metrics {
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
        detailButton.setAccessibilityLabel("详细信息：\(item.title)")
        statusBadgeButton.toolTip = currentProgressSnapshot?.failureMessage ?? downloadRecord?.failureMessage

        currentActionKind = resolvedActionKind(
            downloadRecord: downloadRecord,
            isDownloading: isDownloading,
            isDownloaded: isDownloaded
        )
        isLaunchPendingBadge = downloadRecord.map {
            SteamWorkshopService.shared.isLaunchPending($0.id)
        } ?? false
        applyStatusBadgeAppearance(
            actionKind: currentActionKind,
            itemTitle: item.title,
            isLaunchPending: isLaunchPendingBadge
        )

        refreshThemeAwareAppearance()
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

    private func metrics(for cardSize: CGSize) -> Metrics {
        let scale = max(0.68, min(1.18, cardSize.width / Layout.referenceCardWidth))
        return Metrics(
            scale: scale,
            barHorizontalInset: round(Layout.barHorizontalInset * scale),
            barBottomInset: round(Layout.barBottomInset * scale),
            barHeight: round(Layout.barHeight * scale),
            iconButtonSize: round(Layout.iconButtonSize * scale),
            badgeSize: round(Layout.statusBadgeSize * scale),
            barEdgeInset: round(Layout.barEdgeInset * scale),
            barSpacing: round(Layout.barSpacing * scale),
            marqueeSideInset: round(Layout.marqueeSideInset * scale),
            titleFont: .systemFont(ofSize: 12.5 * scale, weight: .medium),
            buttonCornerRadius: max(8, min(12, 11 * scale))
        )
    }

    private func applyMetrics(_ metrics: Metrics) {
        let targetBarRadius = max(
            8,
            min(Layout.cardCornerRadius, floor((metrics.barHeight - Layout.minBarCornerInset) * 0.5))
        )
        if abs((overlayBar.layer?.cornerRadius ?? 0) - targetBarRadius) > 0.001 {
            overlayBar.layer?.cornerRadius = targetBarRadius
        }
        overlayBarShadowView.layer?.cornerRadius = targetBarRadius
        overlayBarShadowView.layer?.shadowPath = CGPath(
            roundedRect: overlayBarShadowView.bounds,
            cornerWidth: targetBarRadius,
            cornerHeight: targetBarRadius,
            transform: nil
        )
        let targetButtonRadius = max(8, min(12, Layout.cardCornerRadius - 1))
        if abs(detailButton.cornerRadius - targetButtonRadius) > 0.001 {
            detailButton.cornerRadius = targetButtonRadius
        }
        let targetBadgeRadius = prefersCircularPlayBadge
            ? floor(metrics.badgeSize * 0.5)
            : targetButtonRadius
        if abs(statusBadgeButton.cornerRadius - targetBadgeRadius) > 0.001 {
            statusBadgeButton.cornerRadius = targetBadgeRadius
        }
        if abs(titleMarqueeView.font.pointSize - metrics.titleFont.pointSize) > 0.001 {
            titleMarqueeView.font = metrics.titleFont
        }
        let overlaySymbolConfig = NSImage.SymbolConfiguration(pointSize: max(11, metrics.iconButtonSize * 0.56), weight: .medium)
        detailButton.contentTintColor = detailButton.iconTintColor
        detailButton.image = detailButton.image?.withSymbolConfiguration(overlaySymbolConfig)
        statusBadgeButton.image = statusBadgeButton.image?.withSymbolConfiguration(overlaySymbolConfig)
    }

    private func refreshTrackingArea() {
        if let trackingAreaRef {
            view.removeTrackingArea(trackingAreaRef)
        }
        let trackingArea = NSTrackingArea(
            rect: view.bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        view.addTrackingArea(trackingArea)
        trackingAreaRef = trackingArea
    }

    private func buildHierarchy() {
        view.wantsLayer = true

        cardView.wantsLayer = true
        cardView.layer?.cornerRadius = Layout.cardCornerRadius
        cardView.layer?.masksToBounds = false
        cardView.layer?.borderWidth = 0.8
        cardView.layer?.shadowColor = NSColor.black.cgColor
        cardView.layer?.shadowOpacity = 0.03
        cardView.layer?.shadowRadius = 7
        cardView.layer?.shadowOffset = CGSize(width: 0, height: -1)
        cardView.appearanceDidChangeHandler = { [weak self] in
            self?.refreshThemeAwareAppearance()
            self?.applyHoverStyle(animated: false)
        }
        view.addSubview(cardView)

        previewContainer.wantsLayer = true
        previewContainer.layer?.cornerRadius = Layout.cardCornerRadius
        previewContainer.layer?.masksToBounds = true
        cardView.addSubview(previewContainer)

        hoverOutlineView.wantsLayer = true
        hoverOutlineView.layer?.cornerRadius = Layout.cardCornerRadius
        hoverOutlineView.layer?.borderWidth = 1
        hoverOutlineView.layer?.backgroundColor = NSColor.clear.cgColor
        hoverOutlineView.layer?.masksToBounds = true
        hoverOutlineView.alphaValue = 0
        cardView.addSubview(hoverOutlineView)

        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewImageView.imageAlignment = .alignCenter
        syncPreviewAnimationState()
        previewContainer.addSubview(previewImageView)
        previewContainer.addSubview(previewPlaceholderView)

        multiSelectBadgeView.wantsLayer = true
        multiSelectBadgeView.layer?.cornerRadius = 12
        multiSelectBadgeView.layer?.masksToBounds = true
        multiSelectBadgeView.isHidden = true
        cardView.addSubview(multiSelectBadgeView)

        multiSelectBadgeIcon.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
        multiSelectBadgeIcon.contentTintColor = .white
        multiSelectBadgeIcon.imageScaling = .scaleProportionallyDown
        multiSelectBadgeIcon.isHidden = true
        multiSelectBadgeView.addSubview(multiSelectBadgeIcon)

        overlayBarShadowView.wantsLayer = true
        overlayBarShadowView.layer?.backgroundColor = NSColor.clear.cgColor
        overlayBarShadowView.layer?.shadowColor = NSColor.black.cgColor
        overlayBarShadowView.layer?.shadowOpacity = 0.16
        overlayBarShadowView.layer?.shadowRadius = 20
        overlayBarShadowView.layer?.shadowOffset = CGSize(width: 0, height: -1)
        cardView.addSubview(overlayBarShadowView)

        overlayBar.alphaValue = 0
        overlayBar.wantsLayer = true
        overlayBar.setAccessibilityElement(true)
        overlayBar.setAccessibilityRole(.progressIndicator)
        overlayBar.setAccessibilityLabel("下载进度")
        cardView.addSubview(overlayBar)

        detailButton.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "详细信息")
        detailButton.target = self
        detailButton.action = #selector(handleOpen)
        overlayBar.addSubview(detailButton)

        overlayBar.addSubview(titleMarqueeView)

        statusBadgeButton.target = self
        statusBadgeButton.action = #selector(handleStatusAction)
        overlayBar.addSubview(statusBadgeButton)


        refreshThemeAwareAppearance()
    }

    private func refreshThemeAwareAppearance() {
        guard let layer = cardView.layer else { return }
        let isDarkMode = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let fixedForeground = isDarkMode
            ? NSColor(calibratedWhite: 1.0, alpha: 0.98)
            : NSColor(calibratedWhite: 0.08, alpha: 0.92)
        let hoverOutlineColor = NSColor.white.withAlphaComponent(isDarkMode ? 0.56 : 0.72)
        let selectedOutlineColor = NSColor.controlAccentColor.withAlphaComponent(isDarkMode ? 0.92 : 0.84)

        layer.backgroundColor = NSColor.clear.cgColor
        let ringColor: NSColor
        if isHovering {
            ringColor = NSColor.white.withAlphaComponent(0.12)
        } else {
            ringColor = NSColor.white.withAlphaComponent(0.028)
        }
        layer.borderColor = ringColor.cgColor
        layer.shadowOpacity = isHovering ? 0.05 : 0.025
        layer.shadowRadius = isHovering ? 7 : 6
        layer.shadowOffset = CGSize(width: 0, height: -1)
        hoverOutlineView.layer?.borderColor = (isSelectionHighlighted ? selectedOutlineColor : hoverOutlineColor).cgColor
        hoverOutlineView.layer?.borderWidth = isSelectionHighlighted ? 1.6 : 1

        previewContainer.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.14).cgColor

        let showsSelectionBadge = currentDisplayContext == .downloads && isMultiSelectMode
        multiSelectBadgeView.isHidden = !showsSelectionBadge
        if showsSelectionBadge {
            multiSelectBadgeView.layer?.backgroundColor = isSelectionHighlighted
                ? NSColor.controlAccentColor.cgColor
                : NSColor.black.withAlphaComponent(0.42).cgColor
            multiSelectBadgeView.layer?.borderColor = NSColor.white.withAlphaComponent(0.28).cgColor
            multiSelectBadgeView.layer?.borderWidth = isSelectionHighlighted ? 0 : 1
            multiSelectBadgeIcon.isHidden = !isSelectionHighlighted
        } else {
            multiSelectBadgeIcon.isHidden = true
        }

        overlayBar.appearance = NSAppearance(named: isDarkMode ? .darkAqua : .aqua)
        overlayBar.alphaValue = currentBarVisibility ? (isHovering ? 0.92 : 0.84) : 0
        overlayBar.layer?.borderWidth = 0.8
        overlayBar.layer?.shadowOpacity = 0
        overlayBarShadowView.layer?.shadowOpacity = currentBarVisibility ? 0.11 : 0.08
        overlayBarShadowView.layer?.shadowRadius = 18
        overlayBarShadowView.layer?.shadowOffset = CGSize(width: 0, height: -1)
        let progressFraction = currentProgressSnapshot?.fraction
        let indeterminate = progressFraction == nil && {
            switch currentBarState {
            case .connecting, .preparing, .transferring, .validating:
                return true
            case .idle, .queued, .saving, .waiting, .ready, .failed:
                return false
            }
        }()
        overlayBar.applyProgress(
            style: barAccentStyle(for: currentBarState),
            fraction: progressFraction,
            indeterminate: indeterminate,
            animated: false
        )

        detailButton.normalBackgroundColor = .clear
        detailButton.hoverBackgroundColor = .clear
        detailButton.pressedBackgroundColor = .clear
        detailButton.iconTintColor = fixedForeground
        detailButton.borderColor = .clear
        detailButton.borderWidth = 0
        detailButton.appearance = overlayBar.appearance

        titleMarqueeView.textColor = fixedForeground
        titleMarqueeView.appearance = overlayBar.appearance

        statusBadgeButton.normalBackgroundColor = .clear
        statusBadgeButton.hoverBackgroundColor = .clear
        statusBadgeButton.pressedBackgroundColor = .clear
        statusBadgeButton.borderColor = .clear
        statusBadgeButton.borderWidth = 0
        statusBadgeButton.iconTintColor = fixedForeground
        statusBadgeButton.appearance = overlayBar.appearance
        updateContinuousAnimationState()
    }

    private func updateContinuousAnimationState(barVisible: Bool? = nil) {
        let isBarVisible = barVisible ?? currentBarVisibility
        titleMarqueeView.setActive(isBarVisible)
        overlayBar.setProgressAnimationVisible(isBarVisible)
    }

    func setPreviewVisible(_ visible: Bool) {
        guard isPreviewVisible != visible else { return }
        isPreviewVisible = visible
        syncPreviewAnimationState()
    }

    private func syncPreviewAnimationState() {
        previewImageView.animates = isPreviewVisible
    }

    private func applyHoverStyle(animated: Bool) {
        let suppressDownloadsBar = currentDisplayContext == .downloads && isMultiSelectMode
        let shouldRevealBar = !suppressDownloadsBar && (isHovering || shouldPersistBarVisibility)
        let shouldShowOutline = isHovering || isSelectionHighlighted
        let targetScale: CGFloat
        if isHovering {
            targetScale = isPressingCard ? Self.pressedScale : Self.hoverScale
        } else {
            targetScale = 1.0
        }

        refreshThemeAwareAppearance()
        let cardDuration = isHovering
            ? UIInteractionAnimation.cardHoverExpandDuration
            : UIInteractionAnimation.cardHoverCollapseDuration
        let cardTiming = isHovering
            ? UIInteractionAnimation.cardEnterTiming
            : UIInteractionAnimation.cardExitTiming
        let barDuration = shouldRevealBar
            ? UIInteractionAnimation.cardHoverExpandDuration
            : UIInteractionAnimation.cardHoverCollapseDuration
        let barTiming = shouldRevealBar
            ? UIInteractionAnimation.cardEnterTiming
            : UIInteractionAnimation.cardExitTiming

        guard animated else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            cardView.layer?.transform = CATransform3DMakeScale(targetScale, targetScale, 1)
            overlayBar.alphaValue = shouldRevealBar ? (isHovering ? 0.92 : 0.84) : 0
            overlayBar.layer?.transform = CATransform3DMakeTranslation(0, shouldRevealBar ? 0 : 4, 0)
            CATransaction.commit()
            hoverOutlineView.alphaValue = shouldShowOutline ? 1 : 0
            currentCardScale = targetScale
            currentBarVisibility = shouldRevealBar
            isHoverOutlineVisible = shouldShowOutline
            updateContinuousAnimationState(barVisible: shouldRevealBar)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = barDuration
            context.timingFunction = barTiming
            self.cardView.animator().alphaValue = 1
            self.overlayBar.animator().alphaValue = shouldRevealBar ? (self.isHovering ? 0.92 : 0.84) : 0
            self.hoverOutlineView.animator().alphaValue = shouldShowOutline ? 1 : 0
        }

        applyCardTransform(targetScale: targetScale, duration: cardDuration, timing: cardTiming)
        applyBarTransform(isVisible: shouldRevealBar, duration: barDuration, timing: barTiming)
        currentBarVisibility = shouldRevealBar
        isHoverOutlineVisible = shouldShowOutline
        updateContinuousAnimationState(barVisible: shouldRevealBar)
    }

    private func barAccentStyle(for state: BarState) -> SteamWorkshopGlassBarView.AccentStyle {
        switch state {
        case .connecting, .preparing, .transferring, .validating, .saving:
            return .downloading
        case .queued:
            return .queued
        case .waiting:
            return .waiting
        case .failed:
            return .failed
        case .ready:
            return currentDisplayContext == .downloads ? .ready : .neutral
        case .idle:
            return .neutral
        }
    }

    func applyPressedState(_ pressed: Bool) {
        guard isPressingCard != pressed else { return }
        isPressingCard = pressed
        guard isHovering else { return }
        guard !(currentDisplayContext == .downloads && isMultiSelectMode) else { return }
        applyCardTransform(
            targetScale: pressed ? Self.pressedScale : Self.hoverScale,
            duration: pressed ? UIInteractionAnimation.cardPressDownDuration : UIInteractionAnimation.cardPressUpDuration,
            timing: pressed ? UIInteractionAnimation.cardEnterTiming : UIInteractionAnimation.cardExitTiming
        )
    }

    private func applyCardTransform(targetScale: CGFloat, duration: CFTimeInterval, timing: CAMediaTimingFunction) {
        guard let layer = cardView.layer else { return }
        ensureCardAnchorCenteredIfNeeded()
        guard abs(currentCardScale - targetScale) > 0.001 else { return }
        let fromScale = (layer.presentation()?.value(forKeyPath: "transform.scale") as? CGFloat) ?? currentCardScale
        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = fromScale
        animation.toValue = targetScale
        animation.duration = duration
        animation.timingFunction = timing
        layer.add(animation, forKey: "steam.card.hover.scale")

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = CATransform3DMakeScale(targetScale, targetScale, 1)
        CATransaction.commit()
        currentCardScale = targetScale
    }

    private func applyBarTransform(isVisible: Bool, duration: CFTimeInterval, timing: CAMediaTimingFunction) {
        guard let layer = overlayBar.layer else { return }
        let targetTransform = CATransform3DMakeTranslation(0, isVisible ? 0 : 4, 0)
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = layer.transform
        animation.toValue = targetTransform
        animation.duration = duration
        animation.timingFunction = timing
        layer.add(animation, forKey: "steam.card.bar.transform")

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = targetTransform
        CATransaction.commit()
    }

    private func loadPreview(from url: URL?, fallbackVideoURL: URL?) {
        let requestURL = url ?? fallbackVideoURL
        if currentPreviewURL == requestURL {
            if previewImageView.image != nil || isPreviewLoadInFlight {
                return
            }
        }
        currentPreviewURL = requestURL
        isPreviewLoadInFlight = false
        previewLoadCancellation?.cancel()
        previewLoadCancellation = nil
        previewRetryTask?.cancel()

        if let url, url.isFileURL {
            loadLocalPreview(from: url, fallbackVideoURL: fallbackVideoURL)
            return
        }

        guard let url else {
            if let fallbackVideoURL {
                loadGeneratedDownloadPreview(from: fallbackVideoURL)
                return
            }
            previewImageView.image = nil
            previewPlaceholderView.setState(.unavailable)
            updatePreviewImageFrame()
            return
        }

        let cacheKey = steamWorkshopPreviewCacheKey(for: url)
        let bypassesCachedImage = SteamWorkshopPreviewRequestCoordinator.shared.shouldBypassCachedImage(forKey: cacheKey)
        if !bypassesCachedImage,
           let cached = SteamWorkshopPreviewImageCache.shared.cachedImage(forKey: cacheKey),
           steamWorkshopPreviewImageIsUsable(cached) {
            previewImageView.image = cached
            syncPreviewAnimationState()
            previewPlaceholderView.setState(.hidden)
            SteamWorkshopPreviewRequestCoordinator.shared.clearCachedImageSuspicion(forKey: cacheKey)
            updatePreviewImageFrame()
            return
        }
        if let cached = SteamWorkshopPreviewImageCache.shared.cachedImage(forKey: cacheKey),
           !steamWorkshopPreviewImageIsUsable(cached) {
            SteamWorkshopPreviewRequestCoordinator.shared.markCachedImageSuspicious(forKey: cacheKey)
        }

        previewImageView.image = nil
        previewPlaceholderView.setState(.loading)
        updatePreviewImageFrame()
        loadPreviewImage(url: url, cacheKey: cacheKey, bypassingCache: bypassesCachedImage)
    }

    private func loadLocalPreview(from localURL: URL, fallbackVideoURL: URL?) {
        let cacheKey = steamWorkshopLocalPreviewCacheKey(for: localURL)
        if let image = SteamWorkshopPreviewImageCache.shared.cachedImage(forKey: cacheKey) {
            previewImageView.image = image
            syncPreviewAnimationState()
            previewPlaceholderView.setState(.hidden)
            updatePreviewImageFrame()
            return
        }

        previewImageView.image = nil
        previewPlaceholderView.setState(.loading)
        updatePreviewImageFrame()
        isPreviewLoadInFlight = true
        steamWorkshopLoadLocalPreviewImage(from: localURL) { [weak self] image in
            guard let self, self.currentPreviewURL == localURL else { return }
            self.isPreviewLoadInFlight = false
            if let image {
                self.previewImageView.image = image
                self.syncPreviewAnimationState()
                self.previewPlaceholderView.setState(.hidden)
            } else if let fallbackVideoURL {
                self.loadGeneratedDownloadPreview(from: fallbackVideoURL)
                return
            } else {
                self.previewImageView.image = nil
                self.previewPlaceholderView.setState(.unavailable)
            }
            self.updatePreviewImageFrame()
        }
    }

    private func loadGeneratedDownloadPreview(from videoURL: URL) {
        let expectedPreviewURL = currentPreviewURL
        if let cached = SteamWorkshopDownloadThumbnailPipeline.shared.cachedThumbnail(for: videoURL) {
            previewImageView.image = cached
            previewPlaceholderView.setState(.hidden)
            updatePreviewImageFrame()
            return
        }

        previewImageView.image = nil
        previewPlaceholderView.setState(.loading)
        updatePreviewImageFrame()

        SteamWorkshopDownloadThumbnailPipeline.shared.generateThumbnail(for: videoURL) { [weak self] image in
            guard let self, self.currentPreviewURL == expectedPreviewURL else { return }
            if let image {
                self.previewImageView.image = image
                self.syncPreviewAnimationState()
                self.previewPlaceholderView.setState(.hidden)
            } else {
                self.previewImageView.image = nil
                self.previewPlaceholderView.setState(.unavailable)
            }
            self.updatePreviewImageFrame()
        }
    }

    private func loadPreviewImage(url: URL, cacheKey: String, bypassingCache: Bool) {
        if bypassingCache {
            SteamWorkshopPreviewImageCache.shared.remove(forKey: cacheKey)
        }
        let cancellation = SteamWorkshopPreviewLoadCancellation()
        previewLoadCancellation?.cancel()
        previewLoadCancellation = cancellation
        isPreviewLoadInFlight = true
        SteamWorkshopPreviewImageCache.shared.loadImageDataAsync(forKey: cacheKey, loader: {
            guard !cancellation.cancelled else { return nil }
            return await SteamWorkshopPreviewRequestCoordinator.shared.loadData(
                from: url,
                priority: .visible,
                ignoringBackoff: bypassingCache,
                cancellation: cancellation
            )
        }, decoder: steamWorkshopPreviewImage(from:)) { [weak self] image in
            guard let self,
                  self.currentPreviewURL == url,
                  self.previewLoadCancellation === cancellation else { return }
            self.previewLoadCancellation = nil
            self.isPreviewLoadInFlight = false
            self.applyResolvedPreviewImage(image, url: url, cacheKey: cacheKey)
        }
    }

    private func applyResolvedPreviewImage(_ image: NSImage?, url: URL, cacheKey: String) {
        if let image, steamWorkshopPreviewImageIsUsable(image) {
            previewImageView.image = image
            syncPreviewAnimationState()
            previewPlaceholderView.setState(.hidden)
            SteamWorkshopPreviewRequestCoordinator.shared.clearCachedImageSuspicion(forKey: cacheKey)
            updatePreviewImageFrame()
            return
        }

        previewImageView.image = nil
        if image != nil {
            SteamWorkshopPreviewRequestCoordinator.shared.markCachedImageSuspicious(forKey: cacheKey)
        }
        schedulePreviewRetry(url: url, cacheKey: cacheKey)
        updatePreviewImageFrame()
    }

    private func schedulePreviewRetry(url: URL, cacheKey: String) {
        previewRetryTask?.cancel()
        guard let retryDelay = SteamWorkshopPreviewRequestCoordinator.shared.nextRetryDelay(for: url, priority: .visible) else {
            previewPlaceholderView.setState(.unavailable)
            return
        }
        previewPlaceholderView.setState(.retrying)
        previewRetryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0.5, retryDelay + 0.25) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.currentPreviewURL == url else { return }
                self.previewPlaceholderView.setState(.loading)
                self.loadPreviewImage(
                    url: url,
                    cacheKey: cacheKey,
                    bypassingCache: SteamWorkshopPreviewRequestCoordinator.shared.shouldBypassCachedImage(forKey: cacheKey)
                )
            }
        }
    }

    private func updatePreviewImageFrame() {
        let containerBounds = previewContainer.bounds
        guard
            containerBounds.width.isFinite,
            containerBounds.height.isFinite,
            containerBounds.width > 0,
            containerBounds.height > 0
        else {
            previewImageView.frame = .zero
            previewPlaceholderView.frame = .zero
            return
        }
        previewPlaceholderView.frame = containerBounds
        guard
            let image = previewImageView.image,
            image.size.width.isFinite,
            image.size.height.isFinite,
            image.size.width > 0,
            image.size.height > 0
        else {
            previewImageView.frame = containerBounds
            return
        }

        let widthScale = containerBounds.width / image.size.width
        let heightScale = containerBounds.height / image.size.height
        let fillScale = max(widthScale, heightScale)
        let fittedWidth = image.size.width * fillScale
        let fittedHeight = image.size.height * fillScale
        guard fittedWidth.isFinite, fittedHeight.isFinite else {
            previewImageView.frame = containerBounds
            return
        }
        previewImageView.frame = CGRect(
            x: floor((containerBounds.width - fittedWidth) * 0.5),
            y: floor((containerBounds.height - fittedHeight) * 0.5),
            width: ceil(fittedWidth),
            height: ceil(fittedHeight)
        )
    }

    private func ensureCardAnchorCenteredIfNeeded() {
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

    @objc private func handleStatusAction() {
        switch currentActionKind {
        case .download, .retry:
            onDownload?()
        case .cancel:
            onCancelDownload?()
        case .setAsWallpaper:
            onSetAsWallpaper?()
        case .saving:
            break
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
