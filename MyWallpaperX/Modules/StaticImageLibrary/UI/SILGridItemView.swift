//
//  SILGridItemView.swift
//  MyWallpaperX — Modules/StaticImageLibrary/UI
//
import AppKit
import QuartzCore

// MARK: - SILCollectionView

final class SILCollectionView: NSCollectionView, GridCollectionViewProtocol {
    var onBackgroundLeftClick: (() -> Void)?
    var contextMenuProvider: ((IndexPath?) -> NSMenu?)?
    var cardInteractionHandler: (() -> Void)?
    /// 返回 true 时吞掉本次点击（不进入系统选择流程）。
    var primaryClickHandler: ((IndexPath) -> Bool)?
    var isBoxSelectionEnabled = false
    var boxSelectionBeginHandler: ((IndexPath?) -> Bool)?
    var boxSelectionUpdateHandler: ((NSRect) -> Void)?
    var boxSelectionEndHandler: (() -> Void)?
    private(set) var lastPrimaryClickIndexPath: IndexPath?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let indexPath = indexPathForItem(at: point)
        guard event.type == .leftMouseDown else { super.mouseDown(with: event); return }
        lastPrimaryClickIndexPath = indexPath
        if isBoxSelectionEnabled, event.clickCount == 1,
           boxSelectionBeginHandler?(indexPath) == true {
            handleBoxSelectionLoop(startPoint: point); return
        }
        if indexPath != nil {
            cardInteractionHandler?()
        }
        if let indexPath, primaryClickHandler?(indexPath) == true {
            return
        }
        super.mouseDown(with: event)
    }

    private func handleBoxSelectionLoop(startPoint: NSPoint) {
        guard let window else { boxSelectionEndHandler?(); return }
        boxSelectionUpdateHandler?(selectionRect(from: startPoint, to: startPoint))
        while true {
            guard let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else {
                boxSelectionEndHandler?(); return
            }
            let pt = convert(next.locationInWindow, from: nil)
            boxSelectionUpdateHandler?(selectionRect(from: startPoint, to: pt))
            if next.type == .leftMouseUp {
                boxSelectionEndHandler?(); lastPrimaryClickIndexPath = nil; return
            }
        }
    }

    private func selectionRect(from s: NSPoint, to e: NSPoint) -> NSRect {
        NSRect(origin: NSPoint(x: min(s.x, e.x), y: min(s.y, e.y)),
               size: NSSize(width: abs(s.x - e.x), height: abs(s.y - e.y)))
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        guard event.type == .leftMouseUp else { return }
        let point = convert(event.locationInWindow, from: nil)
        if lastPrimaryClickIndexPath == nil, indexPathForItem(at: point) == nil {
            onBackgroundLeftClick?()
        }
        lastPrimaryClickIndexPath = nil
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        contextMenuProvider?(indexPathForItem(at: convert(event.locationInWindow, from: nil)))
    }

    override func keyDown(with event: NSEvent) {
        let noMod = event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
        if noMod {
            switch event.keyCode {
            case 123, 124, 125, 126:
                SILService.shared.moveSingleSelectionByArrowKey(event.keyCode); return
            default:
                break
            }
        }
        // ⌘A：多选模式下全选
        if event.keyCode == 0,
           event.modifierFlags.intersection([.command]) == .command,
           event.modifierFlags.intersection([.control, .option, .shift]).isEmpty,
           SILService.shared.isMultiSelectMode {
            SILService.shared.selectAll(); return
        }
        super.keyDown(with: event)
    }
}

// MARK: - SILGridItem

final class SILGridItem: NSCollectionViewItem, WallpaperGridHoverItem {
    private struct LayoutInputs: Equatable {
        let size: NSSize
        let title: String
        let metadata: String
        let placeholder: String
    }
    private var lastLayoutInputs: LayoutInputs?

    static let reuseID = NSUserInterfaceItemIdentifier("SILGridItem")
    private static var hoverTrackingActivated = false
    static func resetHoverTracking() { hoverTrackingActivated = false }

    private let imageContainer   = AppearanceAwareContainerView()
    private let thumbnailView    = NSImageView()
    private let placeholderLabel = NSTextField(labelWithString: "加载中...")
    private let selectionTint    = NSView()
    private let hoverOutline     = NSView()
    private let overlayView      = NSView()
    private let gradientLayer    = CAGradientLayer()
    private let titleLabel       = NSTextField(labelWithString: "")
    private let metaLabel        = NSTextField(labelWithString: "")
    private let multiSelectBadge = NSView()
    private let multiSelectIcon  = NSImageView()

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
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = true
        view = v
        setupViews()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutSubviewsManually()
    }

    private func fontSizeForWidth(_ width: CGFloat) -> (title: CGFloat, meta: CGFloat) {
        switch width {
        case ..<160:
            return (9, 8)
        case 160..<260:
            return (11, 10)
        default:
            return (13, 11)
        }
    }

    private func layoutSubviewsManually() {
        let inputs = LayoutInputs(size: view.bounds.size, title: titleLabel.stringValue,
            metadata: metaLabel.stringValue, placeholder: placeholderLabel.stringValue)
        guard lastLayoutInputs != inputs else {
            checkInitialHoverState()
            return
        }
        lastLayoutInputs = inputs
        let b = view.bounds
        let fontSizes = fontSizeForWidth(b.width)
        titleLabel.font = .systemFont(ofSize: fontSizes.title, weight: .medium)
        metaLabel.font = .monospacedDigitSystemFont(ofSize: fontSizes.meta, weight: .regular)
        imageContainer.frame = b
        thumbnailView.frame = imageContainer.bounds
        selectionTint.frame = imageContainer.bounds
        hoverOutline.frame = imageContainer.bounds.insetBy(dx: 1, dy: 1)

        // 仅同步 overlay 与圆角容器边界，不做全屏阴影效果
        overlayView.frame = imageContainer.bounds
        gradientLayer.frame = overlayView.bounds
        
        let pad: CGFloat = 8
        metaLabel.frame = NSRect(x: pad, y: pad + 2, width: b.width - pad * 2, height: fontSizes.meta + 2)
        
        titleLabel.frame = NSRect(x: pad, y: metaLabel.frame.maxY + 2, width: b.width - pad * 2, height: fontSizes.title + 3)

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
        checkInitialHoverState()
        refreshThemeAwareAppearance()
    }

    private func checkInitialHoverState() {
        guard !view.isGridHoverSuppressed else { return }
        let isHoveringNow = view.isGridPointerInside
        if isHoveringNow && !isHovering {
            isHovering = true
            applyHoverVisibility(true, animated: false)
        }
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
        titleLabel.alphaValue = 0; metaLabel.alphaValue = 0; overlayView.alphaValue = 0
        titleLabel.stringValue = ""; metaLabel.stringValue = ""
        refreshThemeAwareAppearance()
    }

    func configure(
        wallpaper: SILWallpaper,
        isSelected: Bool,
        isMultiSelectMode: Bool,
        thumbnailVisible: Bool,
        thumbnailLoader: @escaping (ThumbnailCacheRequestCancellation, @escaping (SILThumbnailLoadResult) -> Void) -> Void
    ) {
        wallpaperID = wallpaper.id
        titleLabel.stringValue = wallpaper.title
        
        var metaLines: [String] = []
        if let size = wallpaper.fileSize {
            let mb = Double(size) / (1024 * 1024)
            metaLines.append(String(format: "%.1fMB", mb))
        }
        if let w = wallpaper.pixelWidth, let h = wallpaper.pixelHeight {
            metaLines.append("\(w) × \(h)")
        }
        metaLabel.stringValue = metaLines.joined(separator: "  ")

        applySelectionState(isSelected: isSelected, multiSelectMode: isMultiSelectMode)
        thumbnailCancellation?.cancel()
        thumbnailCancellation = nil
        self.thumbnailLoader = thumbnailLoader
        thumbnailRequestFinished = false
        isThumbnailVisible = thumbnailVisible
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
        }
    }

    func applySelectionState(isSelected: Bool, multiSelectMode: Bool) {
        isMultiSelect = multiSelectMode; isSelectedState = isSelected
        // 强制在主线程下一个 runloop 刷新，确保 frame 已经由 apply(_:) 设置完毕
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshThemeAwareAppearance()
            self.updateMultiSelectBadge(selected: isSelected)
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

    // MARK: - Hover

    func refreshGridHover(isScrolling: Bool) {
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
        guard Self.hoverTrackingActivated else { return }
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
        let alpha: CGFloat = (visible && !isMultiSelect) ? 1 : 0
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = visible ? UIInteractionAnimation.cardHoverExpandDuration : UIInteractionAnimation.cardHoverCollapseDuration
                ctx.timingFunction = visible ? UIInteractionAnimation.cardEnterTiming : UIInteractionAnimation.cardExitTiming
                titleLabel.animator().alphaValue = alpha
                metaLabel.animator().alphaValue = alpha
                overlayView.animator().alphaValue = alpha
            }
        } else {
            titleLabel.alphaValue = alpha
            metaLabel.alphaValue = alpha
            overlayView.alphaValue = alpha
        }
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
        layer.borderColor = (isSelectedState ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        layer.borderWidth = isSelectedState ? 2 : 1
        // 不显示蓝色遮罩，只用描边表示选中
        selectionTint.alphaValue = 0
        let hoverColor: NSColor = view.isDarkAppearance ? .white : .controlAccentColor
        hoverOutline.layer?.borderColor = hoverColor.cgColor
    }

    // MARK: - Setup

    private func updateMultiSelectBadge(selected: Bool) {
        multiSelectBadge.isHidden = !isMultiSelect
        guard isMultiSelect else { return }
        multiSelectBadge.layer?.backgroundColor = selected
            ? NSColor.controlAccentColor.cgColor
            : NSColor.black.withAlphaComponent(0.42).cgColor
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
        overlayView.layer?.addSublayer(gradientLayer)
        overlayView.alphaValue = 0
        // 底部信息渐变：仅在底部形成对比，提升文字可读性
        gradientLayer.colors = [
            NSColor.clear.cgColor,
            NSColor.black.withAlphaComponent(0.05).cgColor,
            NSColor.black.withAlphaComponent(0.72).cgColor
        ]
        gradientLayer.locations = [0.0, 0.62, 1.0]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 0.0)
        gradientLayer.actions = ["bounds": NSNull(), "position": NSNull()]
        gradientLayer.needsDisplayOnBoundsChange = true
        gradientLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]

        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.alignment = .center
        titleLabel.alphaValue = 0

        metaLabel.textColor = NSColor.white.withAlphaComponent(0.80)
        metaLabel.font = .monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        metaLabel.alignment = .center
        metaLabel.alphaValue = 0

        multiSelectBadge.wantsLayer = true
        multiSelectBadge.layer?.cornerRadius = 12
        multiSelectBadge.layer?.masksToBounds = true
        multiSelectBadge.isHidden = true

        multiSelectIcon.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
        multiSelectIcon.contentTintColor = .white
        multiSelectIcon.isHidden = true

        view.addSubview(imageContainer)
        imageContainer.addSubview(thumbnailView)
        imageContainer.addSubview(selectionTint)
        imageContainer.addSubview(overlayView)
        overlayView.addSubview(titleLabel)
        overlayView.addSubview(metaLabel)
        imageContainer.addSubview(hoverOutline)
        imageContainer.addSubview(placeholderLabel)
        imageContainer.addSubview(multiSelectBadge)
        multiSelectBadge.addSubview(multiSelectIcon)

        let tracking = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect],
            owner: self, userInfo: nil
        )
        imageContainer.addTrackingArea(tracking)

        imageContainer.appearanceDidChangeHandler = { [weak self] in
            self?.refreshThemeAwareAppearance()
        }
        refreshThemeAwareAppearance()
    }
}
