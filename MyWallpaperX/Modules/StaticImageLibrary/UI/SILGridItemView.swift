//
//  SILGridItemView.swift
//  MyWallpaperX — Modules/StaticImageLibrary/UI
//
import AppKit
import QuartzCore

// Shared square image card used by the App library adapter.
final class SILGridItem: WallpaperCardCollectionViewItem, WallpaperGridHoverItem {
    private struct LayoutInputs: Equatable {
        let size: NSSize
        let placeholder: String
    }
    private var lastLayoutInputs: LayoutInputs?

    static let reuseID = NSUserInterfaceItemIdentifier("SILGridItem")
    private static var hoverTrackingActivated = false
    static func resetHoverTracking() { hoverTrackingActivated = false }

    private let imageContainer   = AppearanceAwareContainerView()
    private let hoverTracking = WallpaperGridHoverTracking()
    private let thumbnailView    = NSImageView()
    private let placeholderLabel = NSTextField(labelWithString: "加载中...")
    private let selectionTint    = NSView()
    private let hoverOutline     = NSView()
    private let overlayView      = NSView()
    private var currentTitle = ""
    private var currentMetadata = ""
    private var controlBar: WallpaperCardControlsView?
    private var controlBarFrame = NSRect.zero
    private var barVisibilityRevision: UInt64 = 0
    private let multiSelectBadge = NSView()
    private let multiSelectIcon  = NSImageView()

    var onApplyRequested: ((String) -> Void)? {
        didSet { controlBar?.playButton.isEnabled = onApplyRequested != nil && !isSwitching }
    }
    /// Nil until the relation owner is connected; no decorative, inert heart.
    var onToggleFavorite: ((String) -> Void)? {
        didSet { controlBar?.favoriteButton.isHidden = onToggleFavorite == nil }
    }
    private var isFavoriteState = false
    private var isPlayingState = false
    private var isSwitching = false

    var wallpaperID: String?
    private var imageTaskID: UUID?
    private var thumbnailCancellation: ThumbnailCacheRequestCancellation?
    private var thumbnailLoader: ((ThumbnailCacheRequestCancellation, @escaping (SILThumbnailLoadResult) -> Void) -> Void)?
    private var isThumbnailVisible = false
    private var thumbnailRequestFinished = false
    private var loadingPlaceholderWork: DispatchWorkItem?
    private var isHovering      = false
    private var isSelectedState = false
    private var isMultiSelect   = false
    private var isHoverOutlineVisible = false

    override init(nibName: NSNib.Name?, bundle: Bundle?) { super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { super.init(coder: coder) }

    deinit {
        thumbnailCancellation?.cancel()
        loadingPlaceholderWork?.cancel()
    }

    override func apply(_ layoutAttributes: NSCollectionViewLayoutAttributes) {
        super.apply(layoutAttributes)
        view.frame = layoutAttributes.frame
        // 先同步 frame，再让状态刷新在正确尺寸上渲染
        layoutSubviewsManually()
    }

    override func loadView() {
        let v = WallpaperCardInteractionView()
        v.translatesAutoresizingMaskIntoConstraints = true
        view = v
        setupViews()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        hoverTracking.update(in: imageContainer, owner: self)
        layoutSubviewsManually()
    }

    private func layoutSubviewsManually() {
        let inputs = LayoutInputs(size: view.bounds.size, placeholder: placeholderLabel.stringValue)
        guard lastLayoutInputs != inputs else {
            refreshGridHover(isScrolling: view.isGridHoverSuppressed)
            return
        }
        lastLayoutInputs = inputs
        let b = view.bounds
        imageContainer.frame = b
        updateThumbnailFrame()
        selectionTint.frame = imageContainer.bounds
        hoverOutline.frame = imageContainer.bounds.insetBy(dx: 1, dy: 1)
        overlayView.frame = imageContainer.bounds
        imageContainer.layer?.cornerRadius = 14
        hoverOutline.layer?.cornerRadius = 13
        let metrics = WallpaperCardBarMetrics(cardWidth: b.width)
        controlBarFrame = NSRect(x: metrics.barHorizontalInset, y: metrics.barBottomInset,
                                width: max(0, b.width - metrics.barHorizontalInset * 2), height: metrics.barHeight)
        controlBar?.frame = controlBarFrame
        controlBar?.apply(metrics: metrics)

        let labelSize = placeholderLabel.stringValue.size(
            withAttributes: [.font: placeholderLabel.font ?? NSFont.systemFont(ofSize: 12)]
        )
        placeholderLabel.frame = NSRect(
            x: (imageContainer.bounds.width - labelSize.width) / 2,
            y: (imageContainer.bounds.height - labelSize.height) / 2,
            width: ceil(labelSize.width), height: ceil(labelSize.height))
        let badgeSize: CGFloat = 24
        multiSelectBadge.frame = NSRect(
            x: (imageContainer.bounds.width - badgeSize) / 2,
            y: (imageContainer.bounds.height - badgeSize) / 2,
            width: badgeSize, height: badgeSize)
        let iconSize: CGFloat = 14
        multiSelectIcon.frame = NSRect(
            x: (badgeSize - iconSize) / 2,
            y: (badgeSize - iconSize) / 2,
            width: iconSize, height: iconSize)
        // 确保 layer 在正确尺寸上刷新
        refreshGridHover(isScrolling: view.isGridHoverSuppressed)
        refreshThemeAwareAppearance()
    }

    private func updateThumbnailFrame() {
        let bounds = imageContainer.bounds
        guard let size = thumbnailView.image?.size, size.width > 0, size.height > 0 else {
            thumbnailView.frame = bounds
            return
        }
        let scale = max(bounds.width / size.width, bounds.height / size.height)
        let fitted = NSSize(width: size.width * scale, height: size.height * scale)
        thumbnailView.frame = NSRect(x: (bounds.width - fitted.width) / 2,
                                     y: (bounds.height - fitted.height) / 2,
                                     width: fitted.width, height: fitted.height)
    }


    override func prepareForReuse() {
        super.prepareForReuse()
        lastLayoutInputs = nil
        thumbnailCancellation?.cancel()
        thumbnailCancellation = nil
        thumbnailLoader = nil
        thumbnailRequestFinished = false
        loadingPlaceholderWork?.cancel()
        loadingPlaceholderWork = nil
        wallpaperID = nil; imageTaskID = nil
        isHovering = false
        isSelectedState = false; isMultiSelect = false
        thumbnailView.image = nil
        placeholderLabel.stringValue = "加载中..."
        placeholderLabel.isHidden = true
        multiSelectBadge.isHidden = true; multiSelectIcon.isHidden = true
        hoverOutline.alphaValue = 0; isHoverOutlineVisible = false
        selectionTint.alphaValue = 0
        barVisibilityRevision &+= 1
        controlBar?.setActive(false)
        controlBar?.isHidden = true
        controlBar?.removeFromSuperview()
        currentTitle = ""; currentMetadata = ""
        onApplyRequested = nil; onToggleFavorite = nil
        isFavoriteState = false; isPlayingState = false; isSwitching = false
        controlBar?.primaryState = .apply
        view.toolTip = nil
        refreshThemeAwareAppearance()
    }

    func configure(
        wallpaper: SILWallpaper,
        isSelected: Bool,
        isMultiSelectMode: Bool,
        thumbnailVisible: Bool,
        isFavorite: Bool = false,
        isPlaying: Bool = false,
        thumbnailLoader: @escaping (ThumbnailCacheRequestCancellation, @escaping (SILThumbnailLoadResult) -> Void) -> Void
    ) {
        if wallpaperID != wallpaper.id { isSwitching = false }
        wallpaperID = wallpaper.id
        isThumbnailVisible = thumbnailVisible
        currentTitle = wallpaper.title
        
        var metaLines: [String] = []
        if let size = wallpaper.fileSize {
            let mb = Double(size) / (1024 * 1024)
            metaLines.append(String(format: "%.1fMB", mb))
        }
        if let w = wallpaper.pixelWidth, let h = wallpaper.pixelHeight {
            metaLines.append("\(w) × \(h)")
        }
        currentMetadata = metaLines.joined(separator: "  ")
        isFavoriteState = isFavorite
        isPlayingState = isPlaying
        view.toolTip = nil
        updateControlBarContent()

        applySelectionState(isSelected: isSelected, multiSelectMode: isMultiSelectMode)
        thumbnailCancellation?.cancel()
        thumbnailCancellation = nil
        self.thumbnailLoader = thumbnailLoader
        thumbnailRequestFinished = false
        loadingPlaceholderWork?.cancel()
        loadingPlaceholderWork = nil
        applyHoverVisibility(isHovering, animated: false)
        thumbnailView.image = nil
        placeholderLabel.stringValue = "加载中..."
        placeholderLabel.isHidden = true
        beginThumbnailLoad()
    }

    func setThumbnailVisible(_ visible: Bool) {
        isThumbnailVisible = visible
        applyHoverVisibility(isHovering, animated: false)
        if !visible {
            thumbnailCancellation?.cancel()
            thumbnailCancellation = nil
            imageTaskID = nil
            loadingPlaceholderWork?.cancel()
            loadingPlaceholderWork = nil
        } else if !thumbnailRequestFinished, thumbnailCancellation == nil {
            beginThumbnailLoad()
        }
    }

    private func beginThumbnailLoad() {
        guard isThumbnailVisible, let wallpaperID, let thumbnailLoader else { return }
        placeholderLabel.stringValue = "加载中..."
        placeholderLabel.isHidden = true
        let cancellation = ThumbnailCacheRequestCancellation()
        thumbnailCancellation = cancellation
        let taskID = UUID(); imageTaskID = taskID
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.imageTaskID == taskID, self.thumbnailView.image == nil else { return }
            self.placeholderLabel.isHidden = false
        }
        loadingPlaceholderWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
        thumbnailLoader(cancellation) { [weak self] result in
            guard let self, self.imageTaskID == taskID, self.wallpaperID == wallpaperID else { return }
            self.thumbnailRequestFinished = true
            self.thumbnailCancellation = nil
            self.loadingPlaceholderWork?.cancel()
            self.loadingPlaceholderWork = nil
            switch result {
            case .image(let image):
                self.thumbnailView.image = image
                self.placeholderLabel.isHidden = true
            case .missingFile:
                self.thumbnailView.image = nil
                self.placeholderLabel.stringValue = "原文件不存在"
                self.placeholderLabel.isHidden = false
            case .unavailable:
                self.thumbnailView.image = nil
                self.placeholderLabel.stringValue = "缩略图不可用"
                self.placeholderLabel.isHidden = false
            }
            self.lastLayoutInputs = nil
            self.layoutSubviewsManually()
        }
    }

    func applySelectionState(isSelected: Bool, multiSelectMode: Bool) {
        isMultiSelect = multiSelectMode; isSelectedState = isSelected
        applyHoverVisibility(isHovering, animated: false)
        // 强制在主线程下一个 runloop 刷新，确保 frame 已经由 apply(_:) 设置完毕
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshThemeAwareAppearance()
            self.updateMultiSelectBadge(selected: self.isSelectedState)
            if self.imageContainer.bounds.width > 0 {
                let badgeSize: CGFloat = 24
                self.multiSelectBadge.frame = NSRect(
                    x: (self.imageContainer.bounds.width - badgeSize) / 2,
                    y: (self.imageContainer.bounds.height - badgeSize) / 2,
                    width: badgeSize, height: badgeSize)
                let iconSize: CGFloat = 14
                self.multiSelectIcon.frame = NSRect(
                    x: (badgeSize - iconSize) / 2,
                    y: (badgeSize - iconSize) / 2,
                    width: iconSize, height: iconSize)
            }
        }
    }

    /// Relationship/playback refreshes never acquire a new thumbnail lease.
    func applyFavoriteState(isFavorite: Bool) {
        isFavoriteState = isFavorite
        updateControlBarContent()
    }

    func applyPlayingState(isPlaying: Bool) {
        isPlayingState = isPlaying
        updateControlBarContent()
        applyHoverVisibility(isHovering, animated: false)
    }

    func applySwitchingState(isSwitching: Bool) {
        guard self.isSwitching != isSwitching else { return }
        self.isSwitching = isSwitching
        updateControlBarContent()
        applyHoverVisibility(isHovering, animated: false)
    }

    // MARK: - Hover

    func refreshGridHover(isScrolling: Bool) {
        hoverTracking.update(in: imageContainer, owner: self, isScrolling: isScrolling)
        let hovered = !isScrolling && view.isGridPointerInside
        guard hovered != isHovering else { return }
        isHovering = hovered
        applyHoverPresentation(hovered)
    }

    override func mouseEntered(with event: NSEvent) {
        guard !view.isGridHoverSuppressed else { return }
        guard Self.hoverTrackingActivated else { return }
        isHovering = true; applyHoverPresentation(true)
    }
    override func mouseExited(with event: NSEvent) {
        guard !view.isGridHoverSuppressed else { return }
        guard Self.hoverTrackingActivated || isHovering else { return }
        isHovering = false; applyHoverPresentation(false)
    }
    override func mouseMoved(with event: NSEvent) {
        guard !view.isGridHoverSuppressed else { return }
        if !Self.hoverTrackingActivated { Self.hoverTrackingActivated = true }
        let local = imageContainer.convert(event.locationInWindow, from: nil)
        let now = imageContainer.bounds.contains(local)
        guard now != isHovering else { return }
        isHovering = now; applyHoverPresentation(now)
    }

    // MARK: - Animation

    private func applyHoverPresentation(_ hovered: Bool) {
        let dur    = hovered ? UIInteractionAnimation.cardHoverExpandDuration   : UIInteractionAnimation.cardHoverCollapseDuration
        let timing = hovered ? UIInteractionAnimation.cardEnterTiming           : UIInteractionAnimation.cardExitTiming
        applyHoverOutline(hovered, duration: dur, timing: timing)
        applyHoverVisibility(hovered, animated: true)
    }

    private func applyHoverVisibility(_ visible: Bool, animated: Bool) {
        let showBar = (visible || isPlayingState || isSwitching) && !isMultiSelect
        if showBar { prepareControlBarIfNeeded() }
        guard let bar = controlBar else { return }
        barVisibilityRevision &+= 1
        let revision = barVisibilityRevision
        if showBar {
            if bar.superview == nil { overlayView.addSubview(bar) }
            bar.isHidden = false
        }
        bar.setActive(showBar && visible && isThumbnailVisible)
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
            } completionHandler: { DispatchQueue.main.async(execute: finish) }
        } else {
            bar.alphaValue = showBar ? 1 : 0
            finish()
        }
    }

    private func prepareControlBarIfNeeded() {
        guard controlBar == nil else { return }
        let bar = WallpaperCardControlsView(frame: controlBarFrame)
        bar.onPlay = { [weak self] in
            guard let self, !self.isMultiSelect, let id = self.wallpaperID else { return }
            self.onApplyRequested?(id)
        }
        bar.onFavorite = { [weak self] in
            guard let self, !self.isMultiSelect, let id = self.wallpaperID else { return }
            self.onToggleFavorite?(id)
        }
        controlBar = bar
        bar.apply(metrics: WallpaperCardBarMetrics(cardWidth: imageContainer.bounds.width))
        updateControlBarContent()
    }

    private func updateControlBarContent() {
        controlBar?.apply(title: currentTitle, metadata: currentMetadata)
        controlBar?.isFavorite = isFavoriteState
        controlBar?.primaryState = isSwitching ? .switching : (isPlayingState ? .playing : .apply)
        controlBar?.playButton.isEnabled = onApplyRequested != nil && !isSwitching
        controlBar?.favoriteButton.isHidden = onToggleFavorite == nil
    }

    private func applyHoverOutline(_ hovered: Bool, duration: CFTimeInterval, timing: CAMediaTimingFunction) {
        let target: CGFloat = hovered ? 1.0 : 0.0
        guard isHoverOutlineVisible != hovered || abs(hoverOutline.alphaValue - target) > 0.0001 else { return }
        isHoverOutlineVisible = hovered
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration; ctx.timingFunction = timing
            hoverOutline.animator().alphaValue = target
        }
    }

    // MARK: - Theme

    private func refreshThemeAwareAppearance() {
        guard let layer = imageContainer.layer else { return }
        imageContainer.effectiveAppearance.performAsCurrentDrawingAppearance {
            layer.backgroundColor = NSColor.windowBackgroundColor.cgColor
            layer.borderColor = (isSelectedState ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
            multiSelectBadge.layer?.backgroundColor = (isSelectedState
                ? NSColor.controlAccentColor : NSColor.black.withAlphaComponent(0.42)).cgColor
            hoverOutline.layer?.borderColor = NSColor.white.cgColor
        }
        layer.borderWidth = isSelectedState ? 2 : 1
        // 不显示蓝色遮罩，只用描边表示选中
        selectionTint.alphaValue = 0
    }

    // MARK: - Setup

    private func updateMultiSelectBadge(selected: Bool) {
        multiSelectBadge.isHidden = !isMultiSelect
        guard isMultiSelect else { return }
        imageContainer.effectiveAppearance.performAsCurrentDrawingAppearance {
            multiSelectBadge.layer?.backgroundColor = (selected
                ? NSColor.controlAccentColor : NSColor.black.withAlphaComponent(0.42)).cgColor
        }
        multiSelectIcon.isHidden = !selected
    }

    private func setupViews() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor

        imageContainer.wantsLayer = true
        imageContainer.layer?.cornerRadius = 12
        imageContainer.layer?.masksToBounds = true
        imageContainer.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        imageContainer.layer?.borderWidth = 1

        thumbnailView.imageScaling = .scaleProportionallyUpOrDown

        placeholderLabel.alignment = .center
        placeholderLabel.textColor = .secondaryLabelColor
        placeholderLabel.font = .systemFont(ofSize: 11, weight: .regular)

        selectionTint.wantsLayer = true
        selectionTint.alphaValue = 0

        hoverOutline.wantsLayer = true
        hoverOutline.layer?.cornerRadius = 11
        hoverOutline.layer?.borderWidth = 1
        hoverOutline.layer?.backgroundColor = NSColor.clear.cgColor
        hoverOutline.alphaValue = 0

        overlayView.wantsLayer = true
        overlayView.layer?.backgroundColor = NSColor.clear.cgColor

        multiSelectBadge.wantsLayer = true
        multiSelectBadge.layer?.cornerRadius = 12
        multiSelectBadge.layer?.masksToBounds = true
        multiSelectBadge.isHidden = true

        multiSelectIcon.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
        multiSelectIcon.contentTintColor = .white
        multiSelectIcon.isHidden = true

        view.addSubview(imageContainer)
        imageContainer.addSubview(thumbnailView)
        imageView = thumbnailView
        imageContainer.addSubview(selectionTint)
        imageContainer.addSubview(hoverOutline)
        imageContainer.addSubview(overlayView)
        imageContainer.addSubview(placeholderLabel)
        imageContainer.addSubview(multiSelectBadge)
        multiSelectBadge.addSubview(multiSelectIcon)

        hoverTracking.update(in: imageContainer, owner: self)

        imageContainer.appearanceDidChangeHandler = { [weak self] in
            self?.refreshThemeAwareAppearance()
        }
        refreshThemeAwareAppearance()
    }
}
