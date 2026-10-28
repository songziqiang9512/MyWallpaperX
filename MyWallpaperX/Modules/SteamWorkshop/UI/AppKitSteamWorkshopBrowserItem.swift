//
//  AppKitSteamWorkshopBrowserItem.swift
//  MyWallpaperX
//

import AppKit
import QuartzCore

final class AppKitSteamWorkshopBrowserItem: WallpaperCardCollectionViewItem, WallpaperGridHoverItem {
    private struct LayoutInputs: Equatable {
        let size: NSSize
        let scale: CGFloat
        let downloads: Bool
        let multiSelect: Bool
    }
    private var lastLayoutInputs: LayoutInputs?

    static let reuseIdentifier = NSUserInterfaceItemIdentifier("AppKitSteamWorkshopBrowserItem")

    let cardView = AppearanceAwareContainerView()
    let hoverOutlineView = NSView()
    let previewContainer = NSView()
    let previewImageView = NSImageView()
    let previewPlaceholderView = SteamWorkshopPreviewPlaceholderView()
    let multiSelectBadgeView = NSView()
    let multiSelectBadgeIcon = NSImageView()
    let controlBar = WallpaperCardControlsView()

    lazy var previewState: SteamWorkshopPreviewState = {
        let state = SteamWorkshopPreviewState()
        state.onChange = { [weak self] in self?.applyPreviewState() }
        return state
    }()
    private var currentDownloadVideoURL: URL?
    private var isPlayingRecord = false
    private var currentTitleText = ""
    private var onOpen: (() -> Void)?
    private var onDownload: (() -> Void)?
    private var onSetAsWallpaper: (() -> Void)?
    private var onCancelDownload: (() -> Void)?
    private var makeMenu: (() -> NSMenu?)?
    var organizationPresentation: OrganizationPresentation?
    private var currentActionKind: ActionKind = .download
    /// M0.5：本卡片"设为壁纸"是否处于 pending（渲染加载态图标）。
    private var isLaunchPendingBadge = false
    let hoverTracking = WallpaperGridHoverTracking()
    var isHovering = false
    var currentBarVisibility = false
    var barPresentationGeneration: UInt64 = 0
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
    private var lastAccessibilityValue: String?
    /// Memo for `refreshThemeAwareAppearance` (see +Presentation). Internal:
    /// the themed pass lives in the presentation extension.
    var lastThemedChromeInputs: AppKitSteamWorkshopBrowserItem.ThemedChromeInputs?

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
        static let cardInset: CGFloat = 2
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
        root.onPress = { [weak self] in
            guard let action = self?.onOpen else { return false }
            action()
            return true
        }
        view = root
        buildHierarchy()
        controlBar.detailButton.isEnabled = onOpen != nil
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        lastLayoutInputs = nil
        unbindDownloadProgress()
        previewState.reset()
        currentDownloadVideoURL = nil
        currentTitleText = ""
        controlBar.apply(title: "", metadata: "")
        previewImageView.image = nil
        onOpen = nil
        controlBar.onInspect = nil; controlBar.onPlay = nil
        view.setAccessibilityCustomActions([])
        onDownload = nil
        onSetAsWallpaper = nil
        onCancelDownload = nil
        makeMenu = nil
        (view as? WallpaperCardInteractionView)?.onAccessibilityActivate = { false }
        organizationPresentation = nil
        isLaunchPendingBadge = false
        controlBar.detailButton.isEnabled = false
        currentActionKind = .download
        isHovering = false
        currentBarVisibility = false
        barPresentationGeneration &+= 1
        controlBar.removeFromSuperview()
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
        lastAccessibilityValue = nil
        lastThemedChromeInputs = nil
        controlBar.alphaValue = 0
        hoverOutlineView.alphaValue = 0
        controlBar.setActive(false)
        controlBar.glass.setProgressAnimationVisible(false)
        controlBar.glass.applyProgress(style: .neutral, fraction: nil, indeterminate: false, animated: false)
        controlBar.primaryActionTitle = nil
        controlBar.primaryState = .download
        controlBar.playButton.isEnabled = false
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
        organization: OrganizationPresentation? = nil,
        makeMenu: (() -> NSMenu?)? = nil,
        onOpen: (() -> Void)?,
        onDownload: @escaping () -> Void,
        onSetAsWallpaper: @escaping () -> Void,
        onCancelDownload: @escaping () -> Void
    ) {
        organizationPresentation = organization
        self.onOpen = onOpen
        controlBar.detailButton.isEnabled = onOpen != nil
        self.onDownload = onDownload
        self.onSetAsWallpaper = onSetAsWallpaper
        self.onCancelDownload = onCancelDownload
        self.makeMenu = makeMenu
        currentDisplayContext = displayContext
        if displayContext == .browser { (view as? WallpaperCardInteractionView)?.onAccessibilityActivate = nil }
        isPlayingRecord = isPlaying && (displayContext == .downloads || organization != nil)
        currentDownloadVideoURL = downloadRecord?.videoURL
        currentDebugID = item.id
        currentItem = item
        (view as? SteamWorkshopCardAccessibilityView)?.onMenu = { [weak self] in
            self?.currentContextMenu()
        }
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        view.setAccessibilityLabel(item.title)
        view.setAccessibilityCustomActions((onOpen.map { action in [
            NSAccessibilityCustomAction(name: "查看详情", handler: { [weak self] in
                guard let self, self.onOpen != nil, self.currentDisplayContext == displayContext,
                      self.currentItem?.id.utf8.elementsEqual(item.id.utf8) == true else { return false }
                action()
                return true
            })
        ] } ?? []) + (displayContext == .browser ? [
            NSAccessibilityCustomAction(name: "作品操作菜单", handler: { [weak self] in
                guard let self, self.currentDisplayContext == displayContext,
                      self.currentItem?.id.utf8.elementsEqual(item.id.utf8) == true,
                      let menu = self.currentContextMenu() else { return false }
                let scroll = self.view.enclosingScrollView as? WallpaperGridScrollView
                scroll?.beginContextMenu(at: self.view.convert(NSPoint(x: self.view.bounds.midX, y: self.view.bounds.midY), to: nil))
                defer { scroll?.endContextMenu() }
                menu.popUp(positioning: nil, at: NSPoint(x: self.view.bounds.midX, y: self.view.bounds.midY), in: self.view)
                return true
            })
        ] : []))
        currentDownloadRecord = downloadRecord
        currentIsDownloading = isDownloading
        currentIsDownloaded = isDownloaded
        self.isMultiSelectMode = isMultiSelectMode
        currentIsKeyboardFocused = isKeyboardFocused
        syncPreviewAnimationState()
        bindDownloadProgress(to: downloadProgressStore, itemID: item.id)
        // 绑定回放（store 立即回调当前快照，浏览/已下载场景为 nil）被
        // receiveDownloadProgress 的 tick-diff 早退拦截，初始内容应用改为
        // 显式执行——否则标题、状态徽章与操作按钮在首次配置时全部缺位。
        applyCurrentContent()
        loadCurrentPreview()
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
        organization: OrganizationPresentation? = nil,
        makeMenu: (() -> NSMenu?)? = nil,
        onOpen: (() -> Void)?,
        onDownload: @escaping () -> Void,
        onSetAsWallpaper: @escaping () -> Void,
        onCancelDownload: @escaping () -> Void
    ) {
        organizationPresentation = organization
        self.onOpen = onOpen
        controlBar.detailButton.isEnabled = onOpen != nil
        self.onDownload = onDownload
        self.onSetAsWallpaper = onSetAsWallpaper
        self.onCancelDownload = onCancelDownload
        self.makeMenu = makeMenu
        currentDisplayContext = displayContext
        if displayContext == .browser { (view as? WallpaperCardInteractionView)?.onAccessibilityActivate = nil }
        isPlayingRecord = isPlaying && (displayContext == .downloads || organization != nil)
        currentDownloadVideoURL = downloadRecord?.videoURL
        currentDebugID = item.id
        currentItem = item
        (view as? SteamWorkshopCardAccessibilityView)?.onMenu = { [weak self] in
            self?.currentContextMenu()
        }
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        view.setAccessibilityLabel(item.title)
        view.setAccessibilityCustomActions((onOpen.map { action in [
            NSAccessibilityCustomAction(name: "查看详情", handler: { [weak self] in
                guard let self, self.onOpen != nil, self.currentDisplayContext == displayContext,
                      self.currentItem?.id.utf8.elementsEqual(item.id.utf8) == true else { return false }
                action()
                return true
            })
        ] } ?? []) + (displayContext == .browser ? [
            NSAccessibilityCustomAction(name: "作品操作菜单", handler: { [weak self] in
                guard let self, self.currentDisplayContext == displayContext,
                      self.currentItem?.id.utf8.elementsEqual(item.id.utf8) == true,
                      let menu = self.currentContextMenu() else { return false }
                let scroll = self.view.enclosingScrollView as? WallpaperGridScrollView
                scroll?.beginContextMenu(at: self.view.convert(NSPoint(x: self.view.bounds.midX, y: self.view.bounds.midY), to: nil))
                defer { scroll?.endContextMenu() }
                menu.popUp(positioning: nil, at: NSPoint(x: self.view.bounds.midX, y: self.view.bounds.midY), in: self.view)
                return true
            })
        ] : []))
        currentDownloadRecord = downloadRecord
        currentIsDownloading = isDownloading
        currentIsDownloaded = isDownloaded
        self.isMultiSelectMode = isMultiSelectMode
        currentIsKeyboardFocused = isKeyboardFocused
        syncPreviewAnimationState()
        bindDownloadProgress(to: downloadProgressStore, itemID: item.id)
        // 与 configure 相同：绑定回放的 nil 快照被 tick-diff 早退拦截，
        // 初始内容应用显式执行。
        applyCurrentContent()
        loadCurrentPreview()
    }

    /// Selection/relations/playback do not rebind progress or revalidate pixels.
    func applyOrganizationState(_ presentation: OrganizationPresentation, isPlaying: Bool,
                                isMultiSelectMode: Bool, isKeyboardFocused: Bool) {
        organizationPresentation = presentation
        isPlayingRecord = isPlaying
        if self.isMultiSelectMode != isMultiSelectMode { view.needsLayout = true }
        self.isMultiSelectMode = isMultiSelectMode
        currentIsKeyboardFocused = isKeyboardFocused
        applyCurrentContent()
    }

    private func loadCurrentPreview() {
        guard let currentItem else { return }
        let sources = steamWorkshopPreviewSources(item: currentItem, record: currentDownloadRecord)
        let pixels = min(800, GridThumbnailDecoder.pixelLimit(width: view.bounds.width,
            scale: view.window?.backingScaleFactor ?? 2))
        previewState.configure(previewURL: sources.primary, fallbackImageURL: sources.fallback,
            fallbackVideoURL: currentDownloadVideoURL, maxPixelSize: pixels)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        refreshTrackingArea()
        let inputs = LayoutInputs(size: view.bounds.size, scale: view.window?.backingScaleFactor ?? 2, downloads: currentDisplayContext == .downloads,
            multiSelect: isMultiSelectMode)
        guard lastLayoutInputs != inputs else {
            syncHoverStateFromWindow(animated: false)
            return
        }
        lastLayoutInputs = inputs
        // Model configuration still validates the full source identity. A
        // geometry/chrome-only pass must not repeat local file fingerprints
        // unless it actually changes the thumbnail's pixel tier.
        let pixels = min(800, GridThumbnailDecoder.pixelLimit(width: view.bounds.width,
            scale: view.window?.backingScaleFactor ?? 2))
        if previewState.requestedPixelSize != pixels { loadCurrentPreview() }

        let bounds = view.bounds
        guard bounds.width.isFinite, bounds.height.isFinite else { return }
        cardView.frame = bounds.insetBy(dx: Layout.cardInset, dy: Layout.cardInset)

        let metrics = WallpaperCardBarMetrics(cardWidth: cardView.bounds.width)
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
        controlBar.frame = barFrame
        controlBar.apply(metrics: metrics)
        controlBar.layoutSubtreeIfNeeded()

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
        previewState.reload()
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

    func refreshGridHover(isScrolling: Bool) {
        hoverTracking.update(in: view, owner: self, isScrolling: isScrolling)
        let hovered = !isScrolling && view.isGridPointerInside
        guard hovered != isHovering else {
            cardView.applyGridHoverScale(hovered, animated: false)
            return
        }
        isHovering = hovered
        syncPreviewAnimationState()
        applyHoverStyle(animated: false)
    }

    override func mouseEntered(with event: NSEvent) {
        guard !view.isGridHoverSuppressed else { return }
        super.mouseEntered(with: event)
        syncHoverState(with: event, animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        guard !view.isGridHoverSuppressed else { return }
        super.mouseExited(with: event)
        syncHoverState(with: event, animated: true)
    }

    override func mouseMoved(with event: NSEvent) {
        guard !view.isGridHoverSuppressed else { return }
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
        lastAccessibilityValue = nil
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
        // Progress ticks arrive several times a second; an unchanged snapshot
        // (same phase/bytes, duplicate replay) must not re-run the full card
        // content pass.
        guard snapshot != currentProgressSnapshot else { return }
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
        if value != lastAccessibilityValue {
            lastAccessibilityValue = value
            controlBar.glass.setAccessibilityValue(value)
        }
        let bucket = current?.percent.map { $0 / 10 }
        let phase = current?.phase
        let shouldAnnounce = previous != nil
            && (phase != progressAccessibilityPhase || bucket != progressAccessibilityBucket)
        progressAccessibilityPhase = phase
        progressAccessibilityBucket = bucket
        if shouldAnnounce, view.window != nil {
            NSAccessibility.post(element: controlBar.glass, notification: .valueChanged)
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
        controlBar.apply(title: displayTitle, metadata: "")
        currentActionKind = resolvedActionKind(
            downloadRecord: downloadRecord,
            isDownloading: isDownloading,
            isDownloaded: isDownloaded
        )
        if isPlayingRecord {
            // 正在播放：bar 常显、淡红底、按钮切换为停止。
            currentActionKind = .stop
            shouldPersistBarVisibility = true
            controlBar.glass.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.2).cgColor
        } else if controlBar.glass.layer?.backgroundColor != NSColor.clear.cgColor {
            controlBar.glass.layer?.backgroundColor = NSColor.clear.cgColor
        }
        isLaunchPendingBadge = organizationPresentation?.isSwitching ?? downloadRecord.map {
            SteamWorkshopService.shared.isLaunchPending($0.id)
        } ?? false
        if isLaunchPendingBadge {
            currentActionKind = .setAsWallpaper
            shouldPersistBarVisibility = true
        }
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
            // D7：已存在 ready 产物又发生更新失败时保留 ready 卡，仅附加
            // 「更新失败」状态；播放动作仍走旧有效文件。
            if resolvedUpdateFailedMessage(downloadRecord: downloadRecord) != nil {
                return "已下载 · 更新失败"
            }
            return item.title
        }
    }

    /// ready 卡的「更新失败」附加状态摘要：仅当记录已就绪且现役账号存在该
    /// item 的持久失败意图时非 nil（D7：失败不覆盖已验证产物）。
    private func resolvedUpdateFailedMessage(downloadRecord: SteamWorkshopDownloadRecord?) -> String? {
        guard downloadRecord?.status == .ready, let record = downloadRecord else { return nil }
        return SteamWorkshopService.shared.failedDownloadIntentMessage(for: record.id)
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
        let title: String
        switch actionKind {
        case .download:
            controlBar.primaryState = .download
            title = "下载：\(itemTitle)"
        case .retry:
            controlBar.primaryState = .download
            title = "重新下载：\(itemTitle)"
        case .cancel:
            controlBar.primaryState = .switching
            title = "取消下载：\(itemTitle)"
        case .setAsWallpaper:
            controlBar.primaryState = isLaunchPending ? .switching : .apply
            title = isLaunchPending ? "正在切换壁纸：\(itemTitle)" : "设为壁纸：\(itemTitle)"
        case .saving:
            controlBar.primaryState = .switching
            title = "正在保存：\(itemTitle)"
        case .stop:
            controlBar.primaryState = .playing
            title = "停止播放：\(itemTitle)"
        }
        let failure = currentProgressSnapshot?.failureMessage ?? currentDownloadRecord?.failureMessage
            ?? resolvedUpdateFailedMessage(downloadRecord: currentDownloadRecord)
        controlBar.primaryActionTitle = [title, failure].compactMap { $0 }.joined(separator: "\n")
        let allowed: Bool
        if let organizationPresentation {
            switch actionKind {
            case .setAsWallpaper, .stop: allowed = organizationPresentation.canPlay
            case .download, .retry: allowed = organizationPresentation.canDownload
            case .cancel: allowed = organizationPresentation.canCancel
            case .saving: allowed = false
            }
        } else { allowed = actionKind != .saving }
        controlBar.playButton.isEnabled = allowed && !isLaunchPending
        let id = currentItem?.id, context = currentDisplayContext
        let primary: (() -> Void)?
        switch actionKind {
        case .download, .retry: primary = onDownload
        case .cancel: primary = onCancelDownload
        case .setAsWallpaper: primary = onSetAsWallpaper
        case .saving: primary = nil
        case .stop:
            if let organizationPresentation { primary = organizationPresentation.onPrimary }
            else if let record = currentDownloadRecord {
                primary = {
                    guard SteamWorkshopService.shared.isRecordCurrentlyPlaying(record) else { return }
                    PlaybackCommandMultiplexer.shared.dispatch(.stop, to: record.contentType == .scene ? .scene : .video)
                }
            } else { primary = nil }
        }
        controlBar.onPlay = primary.map { action in { [weak self] in
            guard let self, let id, !self.isMultiSelectMode, self.controlBar.playButton.isEnabled,
                  self.currentDisplayContext == context, self.currentActionKind == actionKind,
                  self.currentItem?.id.utf8.elementsEqual(id.utf8) == true else { return }
            action()
        } }
        controlBar.onInspect = onOpen.map { action in { [weak self] in
            guard let self, let id, !self.isMultiSelectMode, self.controlBar.detailButton.isEnabled,
                  self.currentDisplayContext == context,
                  self.currentItem?.id.utf8.elementsEqual(id.utf8) == true else { return }
            action()
        } }
        updateContinuousAnimationState()
    }

    private func syncHoverState(with event: NSEvent, animated: Bool) {
        guard !view.isGridHoverSuppressed else { return }
        let localPoint = view.convert(event.locationInWindow, from: nil)
        let hoveringNow = view.bounds.contains(localPoint)
        guard hoveringNow != isHovering else { return }
        isHovering = hoveringNow
        syncPreviewAnimationState()
        applyHoverStyle(animated: animated)
    }

    private func syncHoverStateFromWindow(animated: Bool) {
        guard !view.isGridHoverSuppressed else { return }
        let hoveringNow = view.isGridPointerInside
        guard hoveringNow != isHovering else { return }
        isHovering = hoveringNow
        syncPreviewAnimationState()
        applyHoverStyle(animated: animated)
    }

    private func currentContextMenu() -> NSMenu? {
        guard currentDisplayContext == .browser, let item = currentItem else { return nil }
        if let makeMenu { return makeMenu() }
        return SteamWorkshopItemMenu.make(item: item, service: SteamWorkshopService.shared,
            navigationVersion: SteamWorkshopService.shared.navigationVersion)
    }


}

/// The card itself opens details; secondary operations remain in its context menu.
private final class SteamWorkshopCardAccessibilityView: WallpaperCardInteractionView {
    var onPress: (() -> Bool)?
    var onMenu: (() -> NSMenu?)?
    override func menu(for event: NSEvent) -> NSMenu? { onMenu?() ?? super.menu(for: event) }
    override func accessibilityPerformPress() -> Bool {
        if let onAccessibilityActivate { return onAccessibilityActivate() }
        guard let onPress else { return false }
        return onPress()
    }
}
