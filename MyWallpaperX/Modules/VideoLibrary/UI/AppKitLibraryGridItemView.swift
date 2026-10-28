//
//  AppKitLibraryGridItemView.swift
//  MyWallpaperX
//

import AppKit
import QuartzCore

@objc(AppKitWallpaperItem)
final class AppKitWallpaperItem: WallpaperCardCollectionViewItem, WallpaperGridHoverItem {
    private struct LayoutInputs: Equatable {
        let size: NSSize
    }
    private var lastLayoutInputs: LayoutInputs?

    static let reuseIdentifier = NSUserInterfaceItemIdentifier(NSStringFromClass(AppKitWallpaperItem.self))
    // hoverTrackingActivated 是全局开关：首次真正收到鼠标移动后再开启 hover 跟踪，避免冷启动时过早绑定轨迹事件。
    private static var hoverTrackingActivated = false

    static func resetHoverTrackingActivation() {
        hoverTrackingActivated = false
    }

    private let imageContainer = AppearanceAwareContainerView()
    private let hoverTracking = WallpaperGridHoverTracking()
    private let selectionTintView = NSView()
    private let hoverOutlineView = NSView()
    private let overlayView = NSView()
    private var currentTitle = ""
    private var currentMetadata = ""
    private let thumbnailImageView = NSImageView()
    private let placeholderLabel = NSTextField(labelWithString: "生成中...")
    private let multiSelectBadge = NSView()
    private let multiSelectBadgeIcon = NSImageView()
    private var controlBar: WallpaperCardControlsView?
    private var controlBarFrame = NSRect.zero
    private var barVisibilityRevision = 0
    var onPlayRequested: ((String) -> Void)? {
        didSet { if controlBar != nil { updateControlBarContent() } }
    }
    var onInspectRequested: ((String) -> Void)? {
        didSet { if controlBar != nil { updateControlBarContent() } }
    }
    private var currentWallpaperID: String?
    private var currentWallpaper: VideoWallpaper?
    private var imageTaskID: UUID?
    private var imageCancellation: ThumbnailCacheRequestCancellation?
    private var loadingPlaceholderWorkItem: DispatchWorkItem?
    private weak var thumbnailWallpaperManager: WallpaperManager?
    private weak var currentThumbnailProvider: AppKitThumbnailProvider?
    private var isThumbnailDemandPaused = false
    private var thumbnailRequestIsPending = false
    private var isHovering = false
    private var isPlaying = false
    private var isSwitching = false
    private var isMultiSelectMode = false
    private var isHoverOutlineVisible = false
    private var isSelectedState = false
    
    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    deinit { imageCancellation?.cancel(); loadingPlaceholderWorkItem?.cancel() }

    override func loadView() {
        view = WallpaperCardInteractionView()
        view.clipsToBounds = false
        setupViews()
    }


    override func prepareForReuse() {
        super.prepareForReuse()
        lastLayoutInputs = nil
        currentWallpaperID = nil
        currentWallpaper = nil
        imageTaskID = nil
        imageCancellation?.cancel()
        imageCancellation = nil
        loadingPlaceholderWorkItem?.cancel()
        loadingPlaceholderWorkItem = nil
        thumbnailWallpaperManager = nil
        currentThumbnailProvider = nil
        isThumbnailDemandPaused = false
        thumbnailRequestIsPending = false
        isHovering = false
        isPlaying = false
        isSwitching = false
        isMultiSelectMode = false
        isSelectedState = false
        thumbnailImageView.image = nil
        placeholderLabel.stringValue = "生成中..."
        placeholderLabel.toolTip = nil
        placeholderLabel.isHidden = true
        multiSelectBadge.isHidden = true
        barVisibilityRevision += 1
        controlBar?.setActive(false)
        controlBar?.removeFromSuperview()
        controlBar?.isHidden = true
        controlBar?.primaryState = .apply
        controlBar?.apply(title: "", metadata: "")
        onPlayRequested = nil
        onInspectRequested = nil
        hoverOutlineView.alphaValue = 0
        isHoverOutlineVisible = false
        selectionTintView.alphaValue = 0
        currentTitle = ""
        currentMetadata = ""
        view.toolTip = nil
        refreshThemeAwareAppearance()
    }

    func configure(
        wallpaper: VideoWallpaper,
        isSelected: Bool,
        isPlaying: Bool,
        multiSelectMode: Bool,
        wallpaperManager: WallpaperManager,
        thumbnailProvider: AppKitThumbnailProvider
    ) {
        // item 只接收外部快照，不主动改模型；否则 selection / 收藏 / 预览会出现双向写回竞争。
        let unchangedResource = currentWallpaper?.id == wallpaper.id
            && currentWallpaper?.path == wallpaper.path && currentWallpaper?.thumbnailPath == wallpaper.thumbnailPath
        if !unchangedResource { thumbnailImageView.image = nil }
        if currentWallpaperID != wallpaper.id { isSwitching = false }
        currentWallpaperID = wallpaper.id
        currentWallpaper = wallpaper
        self.isPlaying = isPlaying
        self.isMultiSelectMode = multiSelectMode
        loadingPlaceholderWorkItem?.cancel()
        placeholderLabel.isHidden = true
        
        currentTitle = wallpaper.displayTitle
        var metaLines: [String] = []
        if let size = wallpaper.fileSize {
            let mb = Double(size) / (1024 * 1024)
            metaLines.append(String(format: "%.1fMB", mb))
        }
        if let duration = wallpaper.duration {
            let mins = duration / 60
            let secs = duration % 60
            if mins > 0 {
                metaLines.append("\(mins)m\(secs)s")
            } else {
                metaLines.append("\(secs)s")
            }
        }
        if let res = wallpaper.resolution {
            metaLines.append(res)
        }
        currentMetadata = metaLines.joined(separator: "  ")
        view.toolTip = nil
        updateControlBarContent()

        applySelectionState(isSelected: isSelected, multiSelectMode: multiSelectMode)

        thumbnailWallpaperManager = wallpaperManager
        currentThumbnailProvider = thumbnailProvider
        thumbnailRequestIsPending = true
        if !isThumbnailDemandPaused {
            requestThumbnail(for: wallpaper, wallpaperManager: wallpaperManager, thumbnailProvider: thumbnailProvider)
        }
    }

    func setThumbnailVisible(_ visible: Bool) {
        if !visible {
            isThumbnailDemandPaused = true
            applyHoverVisibility(isHovering, animated: false)
            imageTaskID = nil
            imageCancellation?.cancel()
            imageCancellation = nil
            loadingPlaceholderWorkItem?.cancel()
            loadingPlaceholderWorkItem = nil
        } else if isThumbnailDemandPaused {
            isThumbnailDemandPaused = false
            applyHoverVisibility(isHovering, animated: false)
            guard thumbnailRequestIsPending, let wallpaper = currentWallpaper,
                  let manager = thumbnailWallpaperManager, let provider = currentThumbnailProvider else { return }
            requestThumbnail(for: wallpaper, wallpaperManager: manager, thumbnailProvider: provider)
        }
    }

    private func requestThumbnail(for wallpaper: VideoWallpaper, wallpaperManager: WallpaperManager,
                                  thumbnailProvider: AppKitThumbnailProvider) {
        let requestID = UUID()
        imageTaskID = requestID
        let loading = DispatchWorkItem { [weak self] in
            guard let self, self.imageTaskID == requestID, self.thumbnailImageView.image == nil else { return }
            self.placeholderLabel.stringValue = "生成中..."
            self.placeholderLabel.isHidden = false
        }
        loadingPlaceholderWorkItem = loading
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: loading)
        imageCancellation?.cancel()
        imageCancellation = thumbnailProvider.loadThumbnail(for: wallpaper) { [weak self] image in
            guard let self,
                  self.imageTaskID == requestID,
                  self.currentWallpaperID == wallpaper.id else {
                return
            }
            self.thumbnailRequestIsPending = false
            self.loadingPlaceholderWorkItem?.cancel()
            self.loadingPlaceholderWorkItem = nil
            if let image {
                self.thumbnailImageView.image = image
                self.layoutThumbnail()
                self.placeholderLabel.isHidden = true
            } else {
                self.thumbnailImageView.image = nil
                self.placeholderLabel.isHidden = false
                let normalizedPath = wallpaperManager.normalizedPath(wallpaper.path)
                if !wallpaperManager.normalizedSourcePathExists(wallpaper.path) {
                    self.placeholderLabel.stringValue = "请检查文件路径"
                    self.placeholderLabel.toolTip = nil
                } else if wallpaperManager.isThumbnailGenerationInFlight(for: normalizedPath) {
                    self.placeholderLabel.stringValue = "生成中..."
                    self.placeholderLabel.toolTip = nil
                } else if wallpaperManager.hasRecentThumbnailGenerationFailure(for: normalizedPath) {
                    self.placeholderLabel.stringValue = "缩略图生成失败"
                    self.placeholderLabel.toolTip = nil
                } else {
                    self.placeholderLabel.stringValue = "生成中..."
                    self.placeholderLabel.toolTip = nil
                    wallpaperManager.ensurePreviewAssetsForWallpaper(wallpaper)
                }
            }
        }
    }

    private func setupViews() {
        // 卡片视觉由几层独立 overlay 组成：缩略图、选中态、hover 描边、播放按钮与多选标记。
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor

        imageContainer.wantsLayer = true
        imageContainer.layer?.cornerRadius = 12
        imageContainer.layer?.masksToBounds = true
        imageContainer.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        imageContainer.layer?.borderWidth = 1
        imageContainer.translatesAutoresizingMaskIntoConstraints = false

        selectionTintView.wantsLayer = true
        selectionTintView.translatesAutoresizingMaskIntoConstraints = false
        selectionTintView.alphaValue = 0

        hoverOutlineView.wantsLayer = true
        hoverOutlineView.layer?.cornerRadius = 11
        hoverOutlineView.layer?.borderWidth = 1
        hoverOutlineView.layer?.backgroundColor = NSColor.clear.cgColor
        hoverOutlineView.translatesAutoresizingMaskIntoConstraints = false
        hoverOutlineView.alphaValue = 0

        thumbnailImageView.imageScaling = .scaleProportionallyUpOrDown

        placeholderLabel.alignment = .center
        placeholderLabel.textColor = .secondaryLabelColor
        placeholderLabel.font = .systemFont(ofSize: 11, weight: .regular)
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false

        multiSelectBadge.wantsLayer = true
        multiSelectBadge.layer?.cornerRadius = 12
        multiSelectBadge.layer?.masksToBounds = true
        multiSelectBadge.translatesAutoresizingMaskIntoConstraints = false
        multiSelectBadge.isHidden = true

        multiSelectBadgeIcon.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
        multiSelectBadgeIcon.contentTintColor = .white
        multiSelectBadgeIcon.translatesAutoresizingMaskIntoConstraints = false
        multiSelectBadgeIcon.isHidden = true

        overlayView.wantsLayer = true
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.layer?.backgroundColor = NSColor.clear.cgColor

        view.addSubview(imageContainer)
        imageContainer.addSubview(thumbnailImageView)
        imageView = thumbnailImageView
        imageContainer.addSubview(selectionTintView)
        imageContainer.addSubview(hoverOutlineView)
        imageContainer.addSubview(overlayView)
        imageContainer.addSubview(placeholderLabel)
        imageContainer.addSubview(multiSelectBadge)
        multiSelectBadge.addSubview(multiSelectBadgeIcon)

        NSLayoutConstraint.activate([
            imageContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageContainer.topAnchor.constraint(equalTo: view.topAnchor),
            imageContainer.heightAnchor.constraint(equalTo: imageContainer.widthAnchor),

            selectionTintView.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor),
            selectionTintView.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor),
            selectionTintView.topAnchor.constraint(equalTo: imageContainer.topAnchor),
            selectionTintView.bottomAnchor.constraint(equalTo: imageContainer.bottomAnchor),

            hoverOutlineView.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor, constant: 1),
            hoverOutlineView.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor, constant: -1),
            hoverOutlineView.topAnchor.constraint(equalTo: imageContainer.topAnchor, constant: 1),
            hoverOutlineView.bottomAnchor.constraint(equalTo: imageContainer.bottomAnchor, constant: -1),

            placeholderLabel.centerXAnchor.constraint(equalTo: imageContainer.centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: imageContainer.centerYAnchor),

            multiSelectBadge.centerXAnchor.constraint(equalTo: imageContainer.centerXAnchor),
            multiSelectBadge.centerYAnchor.constraint(equalTo: imageContainer.centerYAnchor),
            multiSelectBadge.widthAnchor.constraint(equalToConstant: 24),
            multiSelectBadge.heightAnchor.constraint(equalToConstant: 24),

            multiSelectBadgeIcon.centerXAnchor.constraint(equalTo: multiSelectBadge.centerXAnchor),
            multiSelectBadgeIcon.centerYAnchor.constraint(equalTo: multiSelectBadge.centerYAnchor),
            multiSelectBadgeIcon.widthAnchor.constraint(equalToConstant: 14),
            multiSelectBadgeIcon.heightAnchor.constraint(equalToConstant: 14),


            overlayView.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: imageContainer.topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: imageContainer.bottomAnchor),

        ])

        hoverTracking.update(in: imageContainer, owner: self)

        imageContainer.appearanceDidChangeHandler = { [weak self] in
            self?.refreshThemeAwareAppearance()
        }

        refreshThemeAwareAppearance()
    }

    /// The glass hierarchy is created only on first hover/current playback.
    private func prepareControlBarIfNeeded() {
        guard controlBar == nil else { return }
        let bar = WallpaperCardControlsView(frame: controlBarFrame)
        bar.alphaValue = 0
        controlBar = bar
        bar.apply(metrics: WallpaperCardBarMetrics(cardWidth: imageContainer.bounds.width))
        updateControlBarContent()
    }

    private func updateControlBarContent() {
        let id = currentWallpaperID
        controlBar?.onPlay = id.flatMap { id in onPlayRequested.map { action in { [weak self] in
            guard let self, !self.isMultiSelectMode,
                  self.controlBar?.playButton.isEnabled == true else { return }
            action(id)
        } } }
        controlBar?.onInspect = id.flatMap { id in onInspectRequested.map { action in { [weak self] in
            guard let self, !self.isMultiSelectMode,
                  self.controlBar?.detailButton.isEnabled == true else { return }
            action(id)
        } } }
        controlBar?.playButton.isEnabled = onPlayRequested != nil && !isSwitching
        controlBar?.detailButton.isEnabled = onInspectRequested != nil
        controlBar?.primaryState = isSwitching ? .switching : (isPlaying ? .playing : .apply)
        controlBar?.apply(title: currentTitle, metadata: currentMetadata)
    }

    private func applyHoverVisibility(_ visible: Bool, animated: Bool) {
        imageContainer.applyGridHoverScale(isHovering, animated: animated)
        let showBar = (visible || isPlaying || isSwitching) && !isMultiSelectMode
        if showBar { prepareControlBarIfNeeded() }
        guard let bar = controlBar else { return }
        barVisibilityRevision += 1
        let revision = barVisibilityRevision
        if showBar {
            if bar.superview == nil { overlayView.addSubview(bar) }
            bar.isHidden = false
        }
        bar.setActive(showBar && visible && !isThumbnailDemandPaused)
        let finish = { [weak self, weak bar] in
            guard let self, let bar, self.barVisibilityRevision == revision, !showBar else { return }
            bar.isHidden = true
            bar.removeFromSuperview()
        }
        if animated && bar.superview != nil {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = visible ? UIInteractionAnimation.cardHoverExpandDuration : UIInteractionAnimation.cardHoverCollapseDuration
                context.timingFunction = visible ? UIInteractionAnimation.cardEnterTiming : UIInteractionAnimation.cardExitTiming
                bar.animator().alphaValue = showBar ? 1 : 0
            } completionHandler: {
                DispatchQueue.main.async(execute: finish)
            }
        } else {
            bar.alphaValue = showBar ? 1 : 0
            finish()
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        hoverTracking.update(in: imageContainer, owner: self)
        let inputs = LayoutInputs(size: imageContainer.bounds.size)
        guard lastLayoutInputs != inputs else {
            refreshGridHover(isScrolling: view.isGridHoverSuppressed)
            return
        }
        lastLayoutInputs = inputs
        let width = imageContainer.bounds.width
        guard width > 0 else { return }
        imageContainer.layer?.cornerRadius = 14
        hoverOutlineView.layer?.cornerRadius = 13
        let metrics = WallpaperCardBarMetrics(cardWidth: width)
        controlBarFrame = NSRect(x: metrics.barHorizontalInset, y: metrics.barBottomInset,
            width: max(0, width - metrics.barHorizontalInset * 2), height: metrics.barHeight)
        controlBar?.frame = controlBarFrame
        controlBar?.apply(metrics: metrics)
        layoutThumbnail()
        refreshGridHover(isScrolling: view.isGridHoverSuppressed)
    }

    private func layoutThumbnail() {
        let bounds = imageContainer.bounds
        guard let image = thumbnailImageView.image, image.size.width > 0, image.size.height > 0 else {
            thumbnailImageView.frame = bounds
            return
        }
        // Aspect-fill crops only the thumbnail; wallpaper playback scaling stays unchanged.
        let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        thumbnailImageView.frame = NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
            width: size.width, height: size.height)
    }


    func refreshGridHover(isScrolling: Bool) {
        hoverTracking.update(in: imageContainer, owner: self, isScrolling: isScrolling)
        let hovered = !isScrolling && view.isGridPointerInside
        guard hovered != isHovering else {
            imageContainer.applyGridHoverScale(hovered, animated: false)
            return
        }
        isHovering = hovered
        updateHoverOutline(hovered)
        applyHoverVisibility(hovered, animated: false)
    }

    override func mouseEntered(with event: NSEvent) {
        guard !view.isGridHoverSuppressed else { return }
        // hover 进入只触发视觉态，不改 selection。
        guard Self.hoverTrackingActivated else { return }
        isHovering = true
        updateHoverOutline(true)
        applyHoverVisibility(true, animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        guard !view.isGridHoverSuppressed else { return }
        // hover 离开恢复描边和播放按钮可见性。
        guard Self.hoverTrackingActivated || isHovering else { return }
        isHovering = false
        updateHoverOutline(false)
        applyHoverVisibility(false, animated: true)
    }

    override func mouseMoved(with event: NSEvent) {
        guard !view.isGridHoverSuppressed else { return }
        // 首次收到鼠标移动后才开启 hover tracking，避免窗口刚出现就误判 hover 状态。
        if !Self.hoverTrackingActivated {
            Self.hoverTrackingActivated = true
        }
        let localPoint = imageContainer.convert(event.locationInWindow, from: nil)
        let hoveringNow = imageContainer.bounds.contains(localPoint)
        guard hoveringNow != isHovering else { return }
        isHovering = hoveringNow
        updateHoverOutline(hoveringNow)
        applyHoverVisibility(hoveringNow, animated: true)
    }

    private func updateMultiSelectBadge(selected: Bool) {
        multiSelectBadge.isHidden = !isMultiSelectMode
        guard isMultiSelectMode else { return }
        imageContainer.effectiveAppearance.performAsCurrentDrawingAppearance {
            multiSelectBadge.layer?.backgroundColor = (selected
                ? NSColor.controlAccentColor : NSColor.black.withAlphaComponent(0.42)).cgColor
        }
        if selected {
            multiSelectBadgeIcon.isHidden = false
        } else {
            multiSelectBadgeIcon.isHidden = true
        }
    }

    func applySelectionState(isSelected: Bool, multiSelectMode: Bool) {
        // selection 只改边框和遮罩，hover 描边独立更新。
        isMultiSelectMode = multiSelectMode
        isSelectedState = isSelected
        refreshThemeAwareAppearance()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageContainer.layer?.borderWidth = isSelected ? 2 : 1
        CATransaction.commit()
        selectionTintView.alphaValue = isSelected ? 0.2 : 0
        updateMultiSelectBadge(selected: isSelected)
        applyHoverVisibility(isHovering, animated: false)
    }

    func applyPlayingState(isPlaying: Bool) {
        guard self.isPlaying != isPlaying else { return }
        self.isPlaying = isPlaying
        updateControlBarContent()
        applyHoverVisibility(isHovering, animated: false)
    }

    func applySwitchingState(isSwitching: Bool) {
        guard self.isSwitching != isSwitching else { return }
        self.isSwitching = isSwitching
        updateControlBarContent()
        applyHoverVisibility(isHovering, animated: false)
    }

    private func updateHoverOutline(_ hovered: Bool) {
        let duration = hovered ? UIInteractionAnimation.cardHoverExpandDuration : UIInteractionAnimation.cardHoverCollapseDuration
        let timing = hovered ? UIInteractionAnimation.cardEnterTiming : UIInteractionAnimation.cardExitTiming
        applyHoverOutline(hovered, duration: duration, timing: timing)
    }

    private func applyHoverOutline(_ hovered: Bool, duration: CFTimeInterval, timing: CAMediaTimingFunction) {
        // 描边渐显/渐隐只跟 hover 绑定，不跟 selection 绑定。
        let targetAlpha: CGFloat = hovered ? 1.0 : 0.0
        guard isHoverOutlineVisible != hovered || abs(hoverOutlineView.alphaValue - targetAlpha) > 0.0001 else {
            return
        }
        isHoverOutlineVisible = hovered
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = timing
            hoverOutlineView.animator().alphaValue = targetAlpha
        }
    }

    private func refreshThemeAwareAppearance() {
        guard let layer = imageContainer.layer else { return }
        imageContainer.effectiveAppearance.performAsCurrentDrawingAppearance {
            layer.backgroundColor = NSColor.windowBackgroundColor.cgColor
            layer.borderColor = (isSelectedState ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
            selectionTintView.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.2).cgColor
            multiSelectBadge.layer?.backgroundColor = (isSelectedState
                ? NSColor.controlAccentColor : NSColor.black.withAlphaComponent(0.42)).cgColor
            hoverOutlineView.layer?.borderColor = NSColor.white.cgColor
        }
    }

}
