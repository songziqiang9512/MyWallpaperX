//
//  AppKitLibraryGridItemView.swift
//  MyWallpaperX
//

import AppKit
import QuartzCore

@objc(AppKitWallpaperItem)
final class AppKitWallpaperItem: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier(NSStringFromClass(AppKitWallpaperItem.self))
    static let hoverScale: CGFloat = 1.03
    private static let pressedScale: CGFloat = 0.98
    // hoverTrackingActivated 是全局开关：首次真正收到鼠标移动后再开启 hover 跟踪，避免冷启动时过早绑定轨迹事件。
    private static var hoverTrackingActivated = false

    static func resetHoverTrackingActivation() {
        hoverTrackingActivated = false
    }

    private let imageContainer = AppearanceAwareContainerView()
    private let selectionTintView = NSView()
    private let hoverOutlineView = NSView()
    private let overlayView = NSView()
    private let gradientLayer = CAGradientLayer()
    private let titleLabel = NSTextField(labelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
    private let thumbnailImageView = NSImageView()
    private let placeholderLabel = NSTextField(labelWithString: "生成中...")
    private let favoriteBadgeContainer = NSView()
    private let favoriteBadge = NSImageView()
    private let multiSelectBadge = NSView()
    private let multiSelectBadgeIcon = NSImageView()
    private let playActionButton = PlayBadgeView()
    private var currentWallpaperID: String?
    private var currentWallpaper: VideoWallpaper?
    private var imageTaskID: UUID?
    private var trackingAreaRef: NSTrackingArea?
    private var isHovering = false
    private var isPressingCard = false
    private var isPlaying = false
    private var isMultiSelectMode = false
    private var isHoverOutlineVisible = false
    private var isSelectedState = false
    private var currentCardScale: CGFloat = 1.0
    
    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func loadView() {
        view = NSView()
        setupViews()
    }


    override func prepareForReuse() {
        super.prepareForReuse()
        currentWallpaperID = nil
        currentWallpaper = nil
        imageTaskID = nil
        isHovering = false
        isPressingCard = false
        isPlaying = false
        isMultiSelectMode = false
        isSelectedState = false
        thumbnailImageView.image = nil
        placeholderLabel.stringValue = "生成中..."
        placeholderLabel.toolTip = nil
        placeholderLabel.isHidden = false
        favoriteBadge.isHidden = true
        favoriteBadgeContainer.isHidden = true
        multiSelectBadge.isHidden = true
        playActionButton.isHidden = true
        playActionButton.isPlaying = false
        imageContainer.layer?.transform = CATransform3DIdentity
        hoverOutlineView.alphaValue = 0
        isHoverOutlineVisible = false
        currentCardScale = 1.0
        selectionTintView.alphaValue = 0
        titleLabel.stringValue = ""
        metaLabel.stringValue = ""
        titleLabel.layer?.mask = nil
        metaLabel.layer?.mask = nil
        refreshThemeAwareAppearance()
    }

    func configure(
        wallpaper: VideoWallpaper,
        isSelected: Bool,
        isPlaying: Bool,
        isFavorite: Bool,
        multiSelectMode: Bool,
        wallpaperManager: WallpaperManager,
        thumbnailProvider: AppKitThumbnailProvider
    ) {
        // item 只接收外部快照，不主动改模型；否则 selection / 收藏 / 预览会出现双向写回竞争。
        currentWallpaperID = wallpaper.id
        currentWallpaper = wallpaper
        self.isPlaying = isPlaying
        self.isMultiSelectMode = multiSelectMode
        placeholderLabel.isHidden = false
        favoriteBadgeContainer.isHidden = !isFavorite
        favoriteBadge.isHidden = !isFavorite
        
        titleLabel.stringValue = wallpaper.displayTitle
        titleLabel.layer?.mask = nil
        metaLabel.layer?.mask = nil
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
        metaLabel.stringValue = metaLines.joined(separator: "  ")

        applySelectionState(isSelected: isSelected, multiSelectMode: multiSelectMode)
        updatePlayButtonVisibility()
        applyHoverVisibility(isHovering, animated: false)

        let requestID = UUID()
        imageTaskID = requestID
        thumbnailProvider.loadThumbnail(for: wallpaper) { [weak self] image in
            guard let self,
                  self.imageTaskID == requestID,
                  self.currentWallpaperID == wallpaper.id else {
                return
            }
            if let image {
                self.thumbnailImageView.image = image
                self.placeholderLabel.isHidden = true
            } else {
                self.thumbnailImageView.image = nil
                self.placeholderLabel.isHidden = false
                let normalizedPath = wallpaperManager.normalizedPath(wallpaper.path)
                if !wallpaperManager.normalizedSourcePathExists(wallpaper.path) {
                    self.placeholderLabel.stringValue = "请检查文件路径"
                    self.placeholderLabel.toolTip = wallpaper.path
                } else if wallpaperManager.isThumbnailGenerationInFlight(for: normalizedPath) {
                    self.placeholderLabel.stringValue = "生成中..."
                    self.placeholderLabel.toolTip = nil
                } else if wallpaperManager.hasRecentThumbnailGenerationFailure(for: normalizedPath) {
                    self.placeholderLabel.stringValue = "缩略图生成失败"
                    self.placeholderLabel.toolTip = "稍后将自动重试"
                } else {
                    self.placeholderLabel.stringValue = "生成中..."
                    self.placeholderLabel.toolTip = nil
                    wallpaperManager.ensurePreviewAssetsForWallpaper(wallpaper)
                }
            }
        }
    }

    private func setupViews() {
        // 卡片视觉由几层独立 overlay 组成：缩略图、选中态、hover 描边、播放按钮、收藏角标。
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

        thumbnailImageView.imageScaling = .scaleAxesIndependently
        thumbnailImageView.translatesAutoresizingMaskIntoConstraints = false

        placeholderLabel.alignment = .center
        placeholderLabel.textColor = .secondaryLabelColor
        placeholderLabel.font = .systemFont(ofSize: 11, weight: .regular)
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false

        favoriteBadgeContainer.wantsLayer = true
        favoriteBadgeContainer.layer?.cornerRadius = 10
        favoriteBadgeContainer.layer?.masksToBounds = false
        favoriteBadgeContainer.layer?.backgroundColor = NSColor.white.cgColor
        favoriteBadgeContainer.layer?.shadowColor = NSColor.black.cgColor
        favoriteBadgeContainer.layer?.shadowOpacity = 0.2
        favoriteBadgeContainer.layer?.shadowRadius = 2
        favoriteBadgeContainer.layer?.shadowOffset = CGSize(width: 0, height: 1)
        favoriteBadgeContainer.translatesAutoresizingMaskIntoConstraints = false
        favoriteBadgeContainer.isHidden = true

        favoriteBadge.image = NSImage(systemSymbolName: "heart.fill", accessibilityDescription: nil)
        favoriteBadge.contentTintColor = .systemRed
        favoriteBadge.translatesAutoresizingMaskIntoConstraints = false
        favoriteBadge.isHidden = true

        multiSelectBadge.wantsLayer = true
        multiSelectBadge.layer?.cornerRadius = 12
        multiSelectBadge.layer?.masksToBounds = true
        multiSelectBadge.translatesAutoresizingMaskIntoConstraints = false
        multiSelectBadge.isHidden = true

        multiSelectBadgeIcon.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
        multiSelectBadgeIcon.contentTintColor = .white
        multiSelectBadgeIcon.translatesAutoresizingMaskIntoConstraints = false
        multiSelectBadgeIcon.isHidden = true

        playActionButton.isHidden = true

        overlayView.wantsLayer = true
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.layer?.backgroundColor = NSColor.clear.cgColor
        overlayView.layer?.addSublayer(gradientLayer)
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
        titleLabel.alignment = .left
        titleLabel.maximumNumberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.wantsLayer = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        metaLabel.textColor = NSColor.white.withAlphaComponent(0.80)
        metaLabel.alignment = .left
        metaLabel.maximumNumberOfLines = 1
        metaLabel.lineBreakMode = .byClipping
        metaLabel.maximumNumberOfLines = 1
        metaLabel.lineBreakMode = .byTruncatingTail
        metaLabel.font = .systemFont(ofSize: 10, weight: .regular)
        metaLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(imageContainer)
        imageContainer.addSubview(thumbnailImageView)
        imageContainer.addSubview(selectionTintView)
        imageContainer.addSubview(overlayView)
        overlayView.addSubview(titleLabel)
        overlayView.addSubview(metaLabel)
        imageContainer.addSubview(hoverOutlineView)
        imageContainer.addSubview(placeholderLabel)
        imageContainer.addSubview(favoriteBadgeContainer)
        favoriteBadgeContainer.addSubview(favoriteBadge)
        imageContainer.addSubview(multiSelectBadge)
        multiSelectBadge.addSubview(multiSelectBadgeIcon)
        overlayView.addSubview(playActionButton)

        NSLayoutConstraint.activate([
            imageContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageContainer.topAnchor.constraint(equalTo: view.topAnchor),
            imageContainer.heightAnchor.constraint(equalTo: imageContainer.widthAnchor, multiplier: 9.0 / 16.0),

            thumbnailImageView.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor),
            thumbnailImageView.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor),
            thumbnailImageView.topAnchor.constraint(equalTo: imageContainer.topAnchor),
            thumbnailImageView.bottomAnchor.constraint(equalTo: imageContainer.bottomAnchor),

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

            favoriteBadgeContainer.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor, constant: -8),
            favoriteBadgeContainer.topAnchor.constraint(equalTo: imageContainer.topAnchor, constant: 8),
            favoriteBadgeContainer.widthAnchor.constraint(equalToConstant: 20),
            favoriteBadgeContainer.heightAnchor.constraint(equalToConstant: 20),

            favoriteBadge.centerXAnchor.constraint(equalTo: favoriteBadgeContainer.centerXAnchor),
            favoriteBadge.centerYAnchor.constraint(equalTo: favoriteBadgeContainer.centerYAnchor),
            favoriteBadge.widthAnchor.constraint(equalToConstant: 12),
            favoriteBadge.heightAnchor.constraint(equalToConstant: 12),

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

        if let trackingAreaRef {
            imageContainer.removeTrackingArea(trackingAreaRef)
        }
        let tracking = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        imageContainer.addTrackingArea(tracking)
        trackingAreaRef = tracking

        imageContainer.appearanceDidChangeHandler = { [weak self] in
            self?.refreshThemeAwareAppearance()
        }

        refreshThemeAwareAppearance()
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

    private func applyHoverVisibility(_ visible: Bool, animated: Bool) {
        // 多选模式下不显示底部信息层，保持卡片干净
        let infoVisible = visible && !isMultiSelectMode
        let alpha: CGFloat = infoVisible ? 1 : 0
        let gradientOpacity: Float = infoVisible ? 1 : 0
        let playAlpha: CGFloat = ((visible || isPlaying) && !isMultiSelectMode) ? 1 : 0

        if animated {
            let duration = visible ? UIInteractionAnimation.cardHoverExpandDuration : UIInteractionAnimation.cardHoverCollapseDuration
            let timing = visible ? UIInteractionAnimation.cardEnterTiming : UIInteractionAnimation.cardExitTiming
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = timing
                titleLabel.animator().alphaValue = alpha
                metaLabel.animator().alphaValue = alpha
                playActionButton.animator().alphaValue = playAlpha
                gradientLayer.opacity = gradientOpacity
            }
        } else {
            titleLabel.alphaValue = alpha
            metaLabel.alphaValue = alpha
            playActionButton.alphaValue = playAlpha
            gradientLayer.opacity = gradientOpacity
        }

        playActionButton.isHidden = (!visible && !isPlaying) || isMultiSelectMode
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        ensureCardAnchorCenteredIfNeeded()

        let width = imageContainer.bounds.width
        guard width > 0 else { return }
        
        let radius = max(6, width * 0.045)
        imageContainer.layer?.cornerRadius = radius
        hoverOutlineView.layer?.cornerRadius = max(5, radius - 1)

        let (titleSize, metaSize) = fontSizeForWidth(width)
        let pad = max(6, width * 0.05)
        let gap = 2.0

        titleLabel.font = .systemFont(ofSize: titleSize, weight: .medium)
        metaLabel.font = .systemFont(ofSize: metaSize, weight: .regular)

        let buttonSize: CGFloat = max(22, min(32, width * 0.12))
        let actionTrailingInset: CGFloat = max(8, width * 0.04)
        let buttonX = width - actionTrailingInset - buttonSize
        let buttonY: CGFloat = max(8, width * 0.04)
        playActionButton.frame = NSRect(x: buttonX, y: buttonY, width: buttonSize, height: buttonSize)
        playActionButton.needsLayout = true

        let textMaxWidth = buttonX - pad - 12

        metaLabel.frame = NSRect(
            x: pad,
            y: buttonY,
            width: textMaxWidth,
            height: metaSize + 2
        )

        titleLabel.frame = NSRect(
            x: pad,
            y: metaLabel.frame.maxY + gap,
            width: textMaxWidth,
            height: titleSize + 3
        )

        gradientLayer.frame = overlayView.bounds

        applyTitleFadeMaskIfNeeded()

        // 检查当前鼠标是否已经在卡片范围内（解决导入新文件时不显示 meta 的问题）
        checkInitialHoverState()
    }

    private func checkInitialHoverState() {
        guard let window = view.window else { return }
        let mouseLocation = window.mouseLocationOutsideOfEventStream
        let localPoint = view.convert(mouseLocation, from: nil)
        let isHoveringNow = view.bounds.contains(localPoint)
        if isHoveringNow && !isHovering {
            isHovering = true
            applyHoverVisibility(true, animated: false)
        }
    }

    private func applyTitleFadeMaskIfNeeded() {
        applyFadeMask(to: titleLabel)
        applyFadeMask(to: metaLabel)
    }

    private func applyFadeMask(to label: NSTextField) {
        let textWidth = label.attributedStringValue.size().width
        let viewWidth = label.frame.width
        guard viewWidth > 0 else {
            label.layer?.mask = nil
            return
        }
        if textWidth > viewWidth - 4 {
            let mask = CAGradientLayer()
            mask.colors = [NSColor.black.cgColor, NSColor.clear.cgColor]
            mask.startPoint = CGPoint(x: 0.85, y: 0.5)
            mask.endPoint = CGPoint(x: 1.0, y: 0.5)
            mask.frame = label.bounds
            label.layer?.mask = mask
        } else {
            label.layer?.mask = nil
        }
    }

    private func ensureCardAnchorCenteredIfNeeded() {
        imageContainer.ensureLayerAnchorCentered()
    }

    override func mouseEntered(with event: NSEvent) {
        // hover 进入只触发视觉态，不改 selection。
        guard Self.hoverTrackingActivated else { return }
        isHovering = true
        applyHoverCardScale(true)
        updatePlayButtonVisibility()
        applyHoverVisibility(true, animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        // hover 离开恢复卡片缩放和播放按钮可见性。
        guard Self.hoverTrackingActivated else { return }
        isHovering = false
        applyHoverCardScale(false)
        updatePlayButtonVisibility()
        applyHoverVisibility(false, animated: true)
    }

    override func mouseMoved(with event: NSEvent) {
        // 首次收到鼠标移动后才开启 hover tracking，避免窗口刚出现就误判 hover 状态。
        if !Self.hoverTrackingActivated {
            Self.hoverTrackingActivated = true
        }
        let localPoint = imageContainer.convert(event.locationInWindow, from: nil)
        let hoveringNow = imageContainer.bounds.contains(localPoint)
        guard hoveringNow != isHovering else { return }
        isHovering = hoveringNow
        applyHoverCardScale(hoveringNow)
        updatePlayButtonVisibility()
        applyHoverVisibility(hoveringNow, animated: true)
    }

    private func updatePlayButtonVisibility() {
        // 播放按钮仅在非多选模式下显示，避免与批量操作视觉冲突。
        guard !isMultiSelectMode else {
            playActionButton.isHidden = true
            playActionButton.isPlaying = isPlaying
            return
        }
        playActionButton.isPlaying = isPlaying
        playActionButton.isHidden = !(isHovering || isPlaying)
    }

    private func updateMultiSelectBadge(selected: Bool) {
        multiSelectBadge.isHidden = !isMultiSelectMode
        guard isMultiSelectMode else { return }
        if selected {
            multiSelectBadge.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            multiSelectBadgeIcon.isHidden = false
        } else {
            multiSelectBadge.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.42).cgColor
            multiSelectBadgeIcon.isHidden = true
        }
    }

    func shouldTriggerPlayAction(at localPoint: NSPoint) -> Bool {
        // 播放命中区只做几何判断，不单独拦截事件；事件仍由 collectionView 统一处理。
        guard !playActionButton.isHidden else { return false }
        return playActionButton.frame.insetBy(dx: -8, dy: -8).contains(localPoint)
    }

    func applySelectionState(isSelected: Bool, multiSelectMode: Bool) {
        // selection 只改边框和遮罩，不碰当前缩放态，避免 hover / press 动画互相打架。
        isMultiSelectMode = multiSelectMode
        isSelectedState = isSelected
        refreshThemeAwareAppearance()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageContainer.layer?.borderWidth = isSelected ? 2 : 1
        CATransaction.commit()
        selectionTintView.alphaValue = isSelected ? 0.2 : 0
        updateMultiSelectBadge(selected: isSelected)
        updatePlayButtonVisibility()
    }

    func applyFavoriteState(isFavorite: Bool) {
        // 收藏角标只跟收藏状态绑定，不参与 selection / hover 的其他视觉逻辑。
        favoriteBadgeContainer.isHidden = !isFavorite
        favoriteBadge.isHidden = !isFavorite
    }

    func applyPlayingState(isPlaying: Bool) {
        guard self.isPlaying != isPlaying else { return }
        self.isPlaying = isPlaying
        playActionButton.isPlaying = isPlaying
        updatePlayButtonVisibility()
    }

    func applyPressedState(_ pressed: Bool) {
        // 按压态只在 hover 基础上做二级缩放，松手后回到 hover 或原始大小。
        guard isPressingCard != pressed else { return }
        isPressingCard = pressed
        guard isHovering else { return }
        applyCardScale(
            targetScale: pressed ? Self.pressedScale : Self.hoverScale,
            duration: pressed ? UIInteractionAnimation.cardPressDownDuration : UIInteractionAnimation.cardPressUpDuration,
            timing: pressed ? UIInteractionAnimation.cardEnterTiming : UIInteractionAnimation.cardExitTiming
        )
    }

    private func applyHoverCardScale(_ hovered: Bool) {
        // hover 和 pressed 共用同一层 scale，避免双层 transform 叠加产生偏移。
        let duration = hovered ? UIInteractionAnimation.cardHoverExpandDuration : UIInteractionAnimation.cardHoverCollapseDuration
        let timing = hovered ? UIInteractionAnimation.cardEnterTiming : UIInteractionAnimation.cardExitTiming
        applyHoverOutline(hovered, duration: duration, timing: timing)
        let targetScale: CGFloat
        if hovered {
            targetScale = isPressingCard ? Self.pressedScale : Self.hoverScale
        } else {
            targetScale = 1.0
        }
        applyCardScale(targetScale: targetScale, duration: duration, timing: timing)
    }

    private func applyCardScale(targetScale: CGFloat, duration: CFTimeInterval, timing: CAMediaTimingFunction) {
        // 直接改 layer.transform，比通过 frame 反推更稳定，也更容易保持中心点缩放。
        guard let layer = imageContainer.layer else { return }
        ensureCardAnchorCenteredIfNeeded()
        guard abs(currentCardScale - targetScale) > 0.0001 else { return }

        let fromScale = (layer.presentation()?.value(forKeyPath: "transform.scale") as? CGFloat) ?? currentCardScale
        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = fromScale
        animation.toValue = targetScale
        animation.duration = duration
        animation.timingFunction = timing
        layer.add(animation, forKey: "card.hover.scale")

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = CATransform3DMakeScale(targetScale, targetScale, 1)
        CATransaction.commit()
        currentCardScale = targetScale
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

        let borderColor = isSelectedState ? NSColor.controlAccentColor : NSColor.separatorColor
        layer.borderColor = borderColor.cgColor

        selectionTintView.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.2).cgColor

        let hoverColor: NSColor
        if isDarkAppearance {
            hoverColor = .white
        } else {
            hoverColor = .controlAccentColor
        }
        hoverOutlineView.layer?.borderColor = hoverColor.cgColor
    }

    private var isDarkAppearance: Bool { view.isDarkAppearance }
}

private final class PlayBadgeView: NSView {
    var isPlaying: Bool = false {
        didSet {
            guard oldValue != isPlaying else { return }
            updateGlyphAppearance()
        }
    }

    private let backdropView = NSVisualEffectView()
    private let glyphView = NSImageView()
    private let glossLayer = CAGradientLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.16
        layer?.shadowRadius = 4
        layer?.shadowOffset = CGSize(width: 0, height: 1)

        backdropView.material = .menu
        backdropView.blendingMode = .behindWindow
        backdropView.state = .active
        backdropView.wantsLayer = true
        backdropView.translatesAutoresizingMaskIntoConstraints = false
        backdropView.isEmphasized = true
        backdropView.alphaValue = 0.90

        glyphView.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "设为壁纸")
        glyphView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12.5, weight: .semibold)
        glyphView.contentTintColor = .white
        glyphView.imageScaling = .scaleProportionallyDown
        glyphView.translatesAutoresizingMaskIntoConstraints = false
        glyphView.wantsLayer = true
        glyphView.layer?.shadowColor = NSColor.black.cgColor
        glyphView.layer?.shadowOpacity = 0.06
        glyphView.layer?.shadowRadius = 1
        glyphView.layer?.shadowOffset = .zero

        addSubview(backdropView)
        addSubview(glyphView)

        NSLayoutConstraint.activate([
            backdropView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdropView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backdropView.topAnchor.constraint(equalTo: topAnchor),
            backdropView.bottomAnchor.constraint(equalTo: bottomAnchor),

            glyphView.centerXAnchor.constraint(equalTo: centerXAnchor),
            glyphView.centerYAnchor.constraint(equalTo: centerYAnchor),
            glyphView.widthAnchor.constraint(equalToConstant: 14),
            glyphView.heightAnchor.constraint(equalToConstant: 14)
        ])

        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.50).cgColor

        glossLayer.colors = [
            NSColor.white.withAlphaComponent(0.28).cgColor,
            NSColor.white.withAlphaComponent(0.10).cgColor,
            NSColor.white.withAlphaComponent(0.02).cgColor,
            NSColor.clear.cgColor
        ]
        glossLayer.locations = [0.0, 0.22, 0.58, 1.0]
        glossLayer.startPoint = CGPoint(x: 0.18, y: 0.96)
        glossLayer.endPoint = CGPoint(x: 0.76, y: 0.06)
        layer?.addSublayer(glossLayer)

        updateGlyphAppearance()
    }

    override func layout() {
        super.layout()
        let radius = min(bounds.width, bounds.height) / 2
        // 只在 radius 真正变化时才写 layer 属性，避免每次布局都触发 NSVisualEffectView 内部重新布局。
        if abs((layer?.cornerRadius ?? 0) - radius) > 0.5 {
            layer?.cornerRadius = radius
            backdropView.layer?.cornerRadius = radius
            backdropView.layer?.masksToBounds = true
        }
        layer?.shadowPath = CGPath(ellipseIn: bounds.insetBy(dx: 1, dy: 1), transform: nil)
        glossLayer.frame = bounds
        glossLayer.cornerRadius = radius
        glossLayer.masksToBounds = true
    }

    private func updateGlyphAppearance() {
        let darkModeBoost: CGFloat = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? 0.06 : 0.0
        backdropView.alphaValue = min(1.0, isPlaying ? (1.0 + darkModeBoost) : (0.90 + darkModeBoost))
        layer?.borderColor = NSColor.white.withAlphaComponent(0.50).cgColor
        layer?.shadowOpacity = isPlaying ? 0.18 : 0.16
        glossLayer.opacity = isPlaying ? 1.0 : 0.90

        glyphView.contentTintColor = isPlaying ? .systemRed : .white
        glyphView.layer?.shadowColor = NSColor.black.cgColor
        glyphView.layer?.shadowOpacity = isPlaying ? 0.14 : 0.06
    }
}
