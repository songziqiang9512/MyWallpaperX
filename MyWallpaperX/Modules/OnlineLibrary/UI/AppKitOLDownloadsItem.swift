//
//  AppKitOLDownloadsItem.swift
//  MyWallpaperX — Modules/OnlineLibrary/UI
//
//  已下载项网格卡片。
//  常态只显示缩略图；hover 时对齐在线浏览页的底部信息层布局，
//  并保留视频库同款播放按钮作为「设为壁纸」动作入口。
//

import AppKit
import AVFoundation
import QuartzCore

private extension NSImage {
    static func olSymbol(
        _ name: String,
        pointSize: CGFloat,
        weight: NSFont.Weight = .regular,
        scale: NSImage.SymbolScale = .medium,
        accessibilityDescription: String? = nil
    ) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: accessibilityDescription) else { return nil }
        let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight, scale: scale)
        return base.withSymbolConfiguration(cfg)
    }
}

// MARK: - 下载项缩略图共享缓存（收编共享 ThumbnailCache，替换旧内存-only 平行实现）

/// 下载项缩略图统一走共享 ThumbnailCache：in-flight 去重 + 磁盘层 + 失败负缓存
/// 都由其承担，损坏文件不再每次重配置重复 AVAsset 抽帧。
enum OLDownloadedThumbnailStore {
    static let sharedCache = ThumbnailCache(
        label: "com.mywallpaper.onlinelibrary.downloads.thumbnail",
        countLimit: 200,
        totalCostLimit: 50 * 1024 * 1024,
        namespace: "onlinelibrary-downloads",
        usesFailureCache: true
    )

    /// 键含本地路径 + mtime + size：文件被覆盖/替换后自然换新键，
    /// 旧键缓存（含失败负缓存）不会以 stale 内容复活。
    /// 模式同 steamWorkshopLocalPreviewCacheKey / SteamWorkshopDownloadThumbnailPipeline.cacheKey。
    static func cacheKey(for url: URL) -> String {
        let fileURL = url.standardizedFileURL
        let resourceValues = try? fileURL.resourceValues(forKeys: [
            .contentModificationDateKey,
            .fileSizeKey
        ])
        let modificationTime = resourceValues?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let fileSize = resourceValues?.fileSize ?? 0
        return "ol-downloaded-preview:\(fileURL.path):\(fileSize):\(modificationTime)"
    }
}

// MARK: - 数据模型

struct OLDownloadedEntry {
    let id: Int
    let localURL: URL
    let fileSize: Int
    var duration: Int?
    var resolutionString: String?

    var displayTitle: String {
        localURL.lastPathComponent
    }

    var durationString: String {
        guard let duration else { return "" }
        return AppKitOLDownloadsItem.formatDuration(duration)
    }

    var fileSizeString: String? {
        guard fileSize > 0 else { return nil }
        let mb = Double(fileSize) / (1024 * 1024)
        if mb >= 1024 {
            return String(format: "%.1fGB", mb / 1024)
        }
        if mb >= 100 {
            return String(format: "%.0fMB", mb)
        }
        if mb >= 10 {
            return String(format: "%.1fMB", mb)
        }
        return String(format: "%.2fMB", mb)
    }

    var metaLine: String {
        [fileSizeString, durationString.isEmpty ? nil : durationString, resolutionString]
            .compactMap { $0 }
            .joined(separator: "  ")
    }
}

// MARK: - 视频库同款播放按钮

private final class OLDownloadsPlayBadgeView: NSView {
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
            glyphView.heightAnchor.constraint(equalToConstant: 14),
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
        if abs((layer?.cornerRadius ?? 0) - radius) > 0.5 {
            layer?.cornerRadius = radius
            backdropView.layer?.cornerRadius = radius
            backdropView.layer?.masksToBounds = true
        }
        layer?.shadowPath = CGPath(ellipseIn: bounds.insetBy(dx: 1, dy: 1), transform: nil)
        glossLayer.frame = bounds
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

// MARK: - 卡片

final class AppKitOLDownloadsItem: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("AppKitOLDownloadsItem")
    static let hoverScale: CGFloat = 1.03
    private static let pressedScale: CGFloat = 0.98

    private static var hoverTrackingActivated = false

    static func resetHoverTrackingActivation() {
        hoverTrackingActivated = false
    }

    private let imageContainer = AppearanceAwareContainerView()
    private let thumbnailView = NSImageView()
    private let placeholderLabel = NSTextField(labelWithString: "加载中...")
    private let selectionTintView = NSView()
    private let hoverOutlineView = NSView()
    private let overlayView = NSView()
    private let gradientLayer = CAGradientLayer()
    private let titleLabel = NSTextField(labelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
    private let playActionButton = OLDownloadsPlayBadgeView()
    private let multiSelectBadge = NSView()
    private let multiSelectBadgeIcon = NSImageView()

    private var isHovering = false
    private var isPressingCard = false
    private var isMultiSelectMode = false
    private var isHoverOutlineVisible = false
    private var currentCardScale: CGFloat = 1
    private var currentEntryID = -1
    private var isSelectedState = false
    private var isPlaying = false
    private var trackingAreaRef: NSTrackingArea?

    override init(nibName: NSNib.Name?, bundle: Bundle?) {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    static func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remain = seconds % 60
        if minutes > 0, remain > 0 { return "\(minutes)m\(remain)s" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(max(0, seconds))s"
    }

    override func loadView() {
        view = NSView()
        buildViewHierarchy()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        currentEntryID = -1
        thumbnailView.image = nil
        placeholderLabel.stringValue = "加载中..."
        placeholderLabel.isHidden = false
        titleLabel.stringValue = ""
        metaLabel.stringValue = ""
        titleLabel.layer?.mask = nil
        isHovering = false
        isPressingCard = false
        isSelectedState = false
        isMultiSelectMode = false
        isPlaying = false
        imageContainer.layer?.transform = CATransform3DIdentity
        hoverOutlineView.alphaValue = 0
        isHoverOutlineVisible = false
        currentCardScale = 1
        selectionTintView.alphaValue = 0
        multiSelectBadge.isHidden = true
        multiSelectBadgeIcon.isHidden = true
        playActionButton.isPlaying = false
        applyHoverVisibility(false, animated: false)
        refreshTheme()
    }

    func configure(
        entry: OLDownloadedEntry,
        isSelected: Bool,
        isMultiSelectMode: Bool,
        isPlaying: Bool
    ) {
        applySelectionState(isSelected, multiSelectMode: isMultiSelectMode)
        applyPlayingState(isPlaying: isPlaying)
        guard entry.id != currentEntryID else { return }

        currentEntryID = entry.id
        titleLabel.stringValue = entry.displayTitle
        metaLabel.stringValue = entry.metaLine
        view.needsLayout = true

        let cacheKey = OLDownloadedThumbnailStore.cacheKey(for: entry.localURL)
        if let cached = OLDownloadedThumbnailStore.sharedCache.cachedImage(forKey: cacheKey) {
            thumbnailView.image = cached
            placeholderLabel.isHidden = true
            return
        }

        let id = entry.id
        let url = entry.localURL
        weak let item = self
        // 共享缓存自带 in-flight 去重与失败负缓存：同键并发只抽一次帧，
        // 失败（损坏/不支持的编码）记录结论后不再重复 AVAsset 重试。
        OLDownloadedThumbnailStore.sharedCache.load(forKey: cacheKey, loader: {
            Self.generateThumbnail(from: url)
        }, completion: { image in
            // ThumbnailCache 统一主线程回调；卡片已复用为其他条目时丢弃结果
            guard let item, item.currentEntryID == id else { return }
            if let image {
                item.thumbnailView.image = image
                item.placeholderLabel.isHidden = true
            } else {
                // 生成失败：结束加载态，呈现静态失败文案，
                // 避免占位符永远停留「加载中...」。
                item.showThumbnailFailureState()
            }
        })
    }

    /// 同步抽帧供 ThumbnailCache 的后台 decode 队列调用（信号量模式同
    /// SteamWorkshopDownloadThumbnailPipeline.generateCGImage）。
    private static func generateThumbnail(from url: URL) -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 520, height: 300)
        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        var result: CGImage?
        let semaphore = DispatchSemaphore(value: 0)
        generator.generateCGImageAsynchronously(for: time) { cgImage, _, _ in
            result = cgImage
            semaphore.signal()
        }
        semaphore.wait()
        guard let cgImage = result else { return nil }
        return NSImage(cgImage: cgImage, size: .zero)
    }

    /// 缩略图生成失败态：占位文案替换为失败提示并重新排版居中。
    /// 此卡片没有加载动画可停（placeholder 是静态 label），文案即失败态本体。
    private func showThumbnailFailureState() {
        placeholderLabel.stringValue = "无法生成预览"
        placeholderLabel.isHidden = false
        view.needsLayout = true
    }

    private func buildViewHierarchy() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor

        imageContainer.wantsLayer = true
        imageContainer.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        imageContainer.layer?.masksToBounds = true
        imageContainer.layer?.borderWidth = 1

        thumbnailView.imageScaling = .scaleAxesIndependently

        placeholderLabel.alignment = .center
        placeholderLabel.textColor = .secondaryLabelColor
        placeholderLabel.font = .systemFont(ofSize: 11, weight: .regular)

        selectionTintView.wantsLayer = true
        selectionTintView.alphaValue = 0

        overlayView.wantsLayer = true
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
        gradientLayer.endPoint   = CGPoint(x: 0.5, y: 0.0)
        gradientLayer.actions = ["bounds": NSNull(), "position": NSNull()]
        gradientLayer.needsDisplayOnBoundsChange = true
        gradientLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]

        hoverOutlineView.wantsLayer = true
        hoverOutlineView.layer?.borderWidth = 1
        hoverOutlineView.layer?.backgroundColor = NSColor.clear.cgColor
        hoverOutlineView.alphaValue = 0

        titleLabel.textColor = .white
        titleLabel.alignment = .left
        titleLabel.maximumNumberOfLines = 1
        titleLabel.lineBreakMode = .byClipping
        titleLabel.cell?.wraps = false
        titleLabel.cell?.isScrollable = false
        titleLabel.wantsLayer = true

        metaLabel.textColor = NSColor.white.withAlphaComponent(0.80)
        metaLabel.alignment = .left
        metaLabel.maximumNumberOfLines = 1
        metaLabel.lineBreakMode = .byClipping
        metaLabel.wantsLayer = true

        multiSelectBadge.wantsLayer = true
        multiSelectBadge.layer?.masksToBounds = true
        multiSelectBadge.isHidden = true

        multiSelectBadgeIcon.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
        multiSelectBadgeIcon.contentTintColor = .white
        multiSelectBadgeIcon.imageScaling = .scaleProportionallyDown
        multiSelectBadgeIcon.translatesAutoresizingMaskIntoConstraints = false
        multiSelectBadgeIcon.isHidden = true

        playActionButton.isHidden = true

        view.addSubview(imageContainer)
        imageContainer.addSubview(thumbnailView)
        imageContainer.addSubview(selectionTintView)
        imageContainer.addSubview(overlayView)
        overlayView.addSubview(titleLabel)
        overlayView.addSubview(metaLabel)
        overlayView.addSubview(playActionButton)
        imageContainer.addSubview(multiSelectBadge)
        multiSelectBadge.addSubview(multiSelectBadgeIcon)
        imageContainer.addSubview(hoverOutlineView)
        imageContainer.addSubview(placeholderLabel)

        let tracking = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        imageContainer.addTrackingArea(tracking)
        trackingAreaRef = tracking

        imageContainer.appearanceDidChangeHandler = { [weak self] in
            self?.refreshTheme()
        }

        applyHoverVisibility(false, animated: false)
        refreshTheme()
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

    override func viewDidLayout() {
        super.viewDidLayout()

        let width = view.bounds.width
        guard width > 0 else { return }
        let height = floor(width * 9.0 / 16.0)

        imageContainer.frame = NSRect(x: 0, y: view.bounds.height - height, width: width, height: height)

        let radius = max(6, width * 0.045)
        imageContainer.layer?.cornerRadius = radius

        hoverOutlineView.layer?.cornerRadius = max(5, radius - 1)

        thumbnailView.frame = imageContainer.bounds
        selectionTintView.frame = imageContainer.bounds
        overlayView.frame = imageContainer.bounds
        hoverOutlineView.frame = NSRect(x: 1, y: 1, width: width - 2, height: height - 2)

        let placeholderSize = placeholderLabel.stringValue.size(
            withAttributes: [.font: placeholderLabel.font ?? NSFont.systemFont(ofSize: 12)]
        )
        placeholderLabel.frame = NSRect(
            x: floor((width - placeholderSize.width) / 2),
            y: floor((height - placeholderSize.height) / 2),
            width: ceil(placeholderSize.width),
            height: ceil(placeholderSize.height)
        )

        let (titleSize, metaSize) = fontSizeForWidth(width)
        let pad = max(6, width * 0.05)
        let gap = 2.0

        if titleLabel.font?.pointSize != titleSize {
            titleLabel.font = .systemFont(ofSize: titleSize, weight: .medium)
            metaLabel.font = .monospacedDigitSystemFont(ofSize: metaSize, weight: .regular)
        }

        let buttonSize: CGFloat = max(22, min(32, width * 0.12))
        let actionTrailingInset: CGFloat = max(8, width * 0.04)
        let buttonX = width - actionTrailingInset - buttonSize
        let buttonY: CGFloat = max(8, width * 0.04)
        playActionButton.frame = NSRect(x: buttonX, y: buttonY, width: buttonSize, height: buttonSize)

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

        // 仅同步 overlay 与圆角容器边界，不做全屏阴影效果
        overlayView.frame = imageContainer.bounds
        gradientLayer.frame = overlayView.bounds

        applyTitleFadeMaskIfNeeded()

        // 检查当前鼠标是否已经在卡片范围内（解决导入新文件时不显示 meta 的问题）
        checkInitialHoverState()

        let multiSelectSize: CGFloat = 24
        multiSelectBadge.frame = NSRect(
            x: floor((imageContainer.bounds.width - multiSelectSize) / 2),
            y: floor((imageContainer.bounds.height - multiSelectSize) / 2),
            width: multiSelectSize,
            height: multiSelectSize
        )
        multiSelectBadge.layer?.cornerRadius = multiSelectSize / 2

        let multiSelectIconSize: CGFloat = 14
        multiSelectBadgeIcon.frame = NSRect(
            x: floor((multiSelectSize - multiSelectIconSize) / 2),
            y: floor((multiSelectSize - multiSelectIconSize) / 2),
            width: multiSelectIconSize,
            height: multiSelectIconSize
        )
    }

    private func checkInitialHoverState() {
        guard let window = view.window else {
            return
        }
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

    override func mouseEntered(with event: NSEvent) {
        guard Self.hoverTrackingActivated else { return }
        isHovering = true
        applyHoverState(true)
    }

    override func mouseExited(with event: NSEvent) {
        guard Self.hoverTrackingActivated else { return }
        isHovering = false
        applyHoverState(false)
    }

    override func mouseMoved(with event: NSEvent) {
        if !Self.hoverTrackingActivated {
            Self.hoverTrackingActivated = true
        }
        let point = imageContainer.convert(event.locationInWindow, from: nil)
        let hoveringNow = imageContainer.bounds.contains(point)
        guard hoveringNow != isHovering else { return }
        isHovering = hoveringNow
        applyHoverState(hoveringNow)
    }

    private func applyHoverState(_ hovered: Bool) {
        let duration = hovered ? UIInteractionAnimation.cardHoverExpandDuration : UIInteractionAnimation.cardHoverCollapseDuration
        let timing = hovered ? UIInteractionAnimation.cardEnterTiming : UIInteractionAnimation.cardExitTiming
        applyHoverOutline(hovered, duration: duration, timing: timing)

        let targetScale: CGFloat
        if hovered {
            targetScale = isPressingCard ? Self.pressedScale : Self.hoverScale
        } else {
            targetScale = 1
        }

        applyCardScale(targetScale: targetScale, duration: duration, timing: timing)
        applyHoverVisibility(hovered, animated: true)
    }

    func applyPressedState(_ pressed: Bool) {
        guard isPressingCard != pressed else { return }
        isPressingCard = pressed
        // 多选模式下不触发按下动画，保持卡片视觉干净
        guard isHovering && !isMultiSelectMode else { return }
        applyCardScale(
            targetScale: pressed ? Self.pressedScale : Self.hoverScale,
            duration: pressed ? UIInteractionAnimation.cardPressDownDuration : UIInteractionAnimation.cardPressUpDuration,
            timing: pressed ? UIInteractionAnimation.cardEnterTiming : UIInteractionAnimation.cardExitTiming
        )
    }

    func applySelectionState(_ isSelected: Bool, multiSelectMode: Bool = false) {
        isSelectedState = isSelected
        isMultiSelectMode = multiSelectMode

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageContainer.layer?.borderWidth = isSelected ? 2 : 1
        CATransaction.commit()

        selectionTintView.alphaValue = isSelected ? 0.2 : 0
        updateMultiSelectBadge(selected: isSelected)
        applyHoverVisibility(isHovering, animated: false)
        refreshTheme()
    }

    func applyPlayingState(isPlaying: Bool) {
        guard self.isPlaying != isPlaying else { return }
        self.isPlaying = isPlaying
        playActionButton.isPlaying = isPlaying
        applyHoverVisibility(isHovering, animated: false)
    }

    private func updateMultiSelectBadge(selected: Bool) {
        multiSelectBadge.isHidden = !isMultiSelectMode
        guard isMultiSelectMode else {
            multiSelectBadgeIcon.isHidden = true
            return
        }

        if selected {
            multiSelectBadge.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            multiSelectBadgeIcon.isHidden = false
        } else {
            multiSelectBadge.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.42).cgColor
            multiSelectBadgeIcon.isHidden = true
        }
    }

    func shouldTriggerPlayAction(at pointInItem: NSPoint) -> Bool {
        guard !playActionButton.isHidden else { return false }
        return playActionButton.frame.insetBy(dx: -8, dy: -8).contains(pointInItem)
    }

    private func applyCardScale(targetScale: CGFloat, duration: CFTimeInterval, timing: CAMediaTimingFunction) {
        guard let layer = imageContainer.layer else { return }
        imageContainer.ensureLayerAnchorCentered()
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
        let targetAlpha: CGFloat = hovered ? 1 : 0
        guard isHoverOutlineVisible != hovered || abs(hoverOutlineView.alphaValue - targetAlpha) > 0.0001 else { return }
        isHoverOutlineVisible = hovered
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = timing
            hoverOutlineView.animator().alphaValue = targetAlpha
        }
    }

    private func refreshTheme() {
        guard let layer = imageContainer.layer else { return }
        layer.borderColor = (isSelectedState ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        selectionTintView.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.2).cgColor
        hoverOutlineView.layer?.borderColor = view.isDarkAppearance
            ? NSColor.white.cgColor
            : NSColor.controlAccentColor.cgColor
    }
}
