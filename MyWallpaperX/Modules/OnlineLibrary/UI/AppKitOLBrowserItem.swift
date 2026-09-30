//
//  AppKitOLBrowserItem.swift
//  MyWallpaperX — Modules/OnlineLibrary/UI
//
//  在线库搜索结果网格卡片。内部元素全部用相对卡片宽度的手动 frame 布局。
//

import AppKit
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

final class OLCircularProgressView: NSView {
    private let backgroundLayer = CAShapeLayer()
    private let trackLayer = CAShapeLayer()
    private let progressLayer = CAShapeLayer()
    private let textLayer = CATextLayer()
    private var progressValue: Double = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        backgroundLayer.fillColor = NSColor.black.withAlphaComponent(0.46).cgColor
        backgroundLayer.strokeColor = NSColor.clear.cgColor
        backgroundLayer.lineWidth = 0
        layer?.addSublayer(backgroundLayer)

        trackLayer.fillColor = NSColor.clear.cgColor
        trackLayer.strokeColor = NSColor.white.withAlphaComponent(0.18).cgColor
        trackLayer.lineWidth = 3.6
        layer?.addSublayer(trackLayer)

        progressLayer.fillColor = NSColor.clear.cgColor
        progressLayer.strokeColor = NSColor.white.cgColor
        progressLayer.lineWidth = 4.2
        progressLayer.lineCap = .round
        progressLayer.strokeEnd = 0
        layer?.addSublayer(progressLayer)

        textLayer.alignmentMode = .center
        textLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        textLayer.foregroundColor = NSColor.white.cgColor
        layer?.addSublayer(textLayer)
    }

    override func layout() {
        super.layout()
        let rect = bounds.insetBy(dx: 1.5, dy: 1.5)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = max(7, min(rect.width, rect.height) / 2 - 3.2)
        let ringPath = CGMutablePath()
        ringPath.addArc(
            center: center,
            radius: radius,
            startAngle: -.pi / 2,
            endAngle: .pi * 3 / 2,
            clockwise: false
        )
        let circlePath = CGPath(
            ellipseIn: CGRect(
                x: center.x - radius - 4.4,
                y: center.y - radius - 4.4,
                width: (radius + 4.4) * 2,
                height: (radius + 4.4) * 2
            ),
            transform: nil
        )
        backgroundLayer.frame = bounds
        backgroundLayer.path = circlePath
        trackLayer.frame = bounds
        trackLayer.path = ringPath
        trackLayer.strokeEnd = 1
        progressLayer.frame = bounds
        progressLayer.path = ringPath
        progressLayer.strokeEnd = CGFloat(progressValue)
        progressLayer.strokeColor = NSColor.white.cgColor

        let fontSize = max(8, bounds.width * 0.23)
        textLayer.font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold)
        textLayer.fontSize = fontSize
        textLayer.foregroundColor = NSColor.white.cgColor
        let textHeight = fontSize + 4
        textLayer.frame = CGRect(x: 0, y: floor((bounds.height - textHeight) / 2.0), width: bounds.width, height: textHeight)
    }

    func setProgress(_ progress: Double) {
        progressValue = min(1, max(0, progress))
        textLayer.string = "\(Int((progressValue * 100).rounded()))"
        needsLayout = true
    }
}

final class AppKitOLBrowserItem: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("AppKitOLBrowserItem")
    private static var hoverTrackingActivated = false
    static func resetHoverTrackingActivation() { hoverTrackingActivated = false }

    private let shadowView = NSView()
    private let imageContainer     = AppearanceAwareContainerView()
    private let thumbnailView      = NSImageView()
    private let placeholderView    = NSView()
    private let spinner            = NSProgressIndicator()
    private let overlayView        = NSView()
    private let hoverOutlineView   = NSView()
    private let durationBadgeView  = NSView()
    private let durationBadgeTextLayer = CATextLayer()
    private let gradientLayer      = CAGradientLayer()
    private let titleLabel         = NSTextField(labelWithString: "")
    private let metaLabel          = NSTextField(labelWithString: "")
    private let downloadBtn        = NSButton()
    private let setWallpaperBtn    = NSButton()
    private let downloadingSpinner = NSProgressIndicator()
    private let downloadProgressView = OLCircularProgressView(frame: .zero)
    private let downloadedBadge    = NSImageView()
    private let completionBadgeView = NSView()
    private let completionBadgeIcon = NSImageView()

    private var isHovering        = false
    private var isPressingCard    = false
    private var isHoverOutlineVis = false
    private var isDownloadingState = false
    private var isDownloadedState = false
    private var currentCardScale  = CGFloat(1)
    private var currentItemID     = -1
    private var currentPageURL:   String? = nil
    private var trackingAreaRef:  NSTrackingArea?
    private var thumbnailTask:    Task<Void, Never>?
    private var completionHideWorkItem: DispatchWorkItem?
    private var completionRevealWorkItem: DispatchWorkItem?
    private var isCompletionAnimating = false
    private var lastSymbolPointSize: CGFloat = 0
    private var onDownload:       (() -> Void)?
    private var onSetAsWallpaper: (() -> Void)?
    private var hoverVisible      = false

    override init(nibName: NSNib.Name?, bundle: Bundle?) { super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    override func loadView() { view = NSView(); buildViewHierarchy() }

    // MARK: - 复用
    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailTask?.cancel(); thumbnailTask = nil
        completionHideWorkItem?.cancel()
        completionHideWorkItem = nil
        completionRevealWorkItem?.cancel()
        completionRevealWorkItem = nil
        isCompletionAnimating = false
        currentItemID = -1
        currentPageURL = nil
        thumbnailView.image = nil
        completionHideWorkItem?.cancel()
        completionHideWorkItem = nil
        placeholderView.isHidden = false
        spinner.startAnimation(nil)
        titleLabel.stringValue = ""
        durationBadgeTextLayer.string = nil
        metaLabel.stringValue = ""
        setDownloadState(isDownloading: false, isDownloaded: false, downloadProgress: nil)
        isHovering = false; isPressingCard = false; hoverVisible = false
        isDownloadedState = false
        imageContainer.layer?.transform = CATransform3DIdentity
        hoverOutlineView.alphaValue = 0
        isHoverOutlineVis = false; currentCardScale = 1
        completionBadgeView.alphaValue = 0
        completionBadgeView.isHidden = true
        completionBadgeView.layer?.transform = CATransform3DIdentity
        onDownload = nil; onSetAsWallpaper = nil
        applyHoverVisibility(false, animated: false)
        refreshTheme()
    }

    // MARK: - 配置
    func configure(
        item: OnlineLibraryVideoItem,
        isDownloading: Bool, isDownloaded: Bool, downloadProgress: Double?,
        onDownload: @escaping () -> Void,
        onSetAsWallpaper: @escaping () -> Void
    ) {
        self.onDownload = onDownload
        self.onSetAsWallpaper = onSetAsWallpaper
        if item.id != currentItemID {
            currentItemID = item.id
            currentPageURL = item.pageURL
            titleLabel.stringValue = item.displayTitle
            let durationText = Self.formatDuration(item.duration)
            durationBadgeTextLayer.string = durationText
            var metaParts: [String] = []
            if let size = item.fileSizeString {
                metaParts.append(size)
            }
            metaParts.append(durationText)
            if let res = item.resolutionString {
                metaParts.append(res)
            }
            metaLabel.stringValue = metaParts.joined(separator: "  ")
            loadThumbnail(url: item.previewThumbnailURL)
        }
        setDownloadState(
            isDownloading: isDownloading,
            isDownloaded: isDownloaded,
            downloadProgress: downloadProgress
        )
    }

    private static func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remain = seconds % 60
        if minutes > 0, remain > 0 { return "\(minutes)m\(remain)s" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(max(0, seconds))s"
    }

    private func setDownloadState(isDownloading: Bool, isDownloaded: Bool, downloadProgress: Double?) {
        let wasDownloading = isDownloadingState
        isDownloadingState = isDownloading
        isDownloadedState = isDownloaded
        let progress = downloadProgress ?? 0
        downloadProgressView.isHidden = !isDownloading
        downloadProgressView.setProgress(progress)
        downloadProgressView.alphaValue = isDownloading ? 1 : (hoverVisible ? 1 : 0)
        downloadingSpinner.isHidden = true
        downloadingSpinner.stopAnimation(nil)
        if isDownloaded && isCompletionAnimating {
            downloadBtn.isHidden = true
            setWallpaperBtn.isHidden = true
            downloadedBadge.isHidden = true
        } else {
            downloadedBadge.isHidden = !isDownloaded
            downloadBtn.isHidden     = isDownloading || isDownloaded
            setWallpaperBtn.isHidden = isDownloading
        }
        durationBadgeView.layer?.backgroundColor = (
            isDownloaded
                ? NSColor.systemGreen.blended(withFraction: 0.38, of: .black)?.withAlphaComponent(0.82)
                    ?? NSColor.systemGreen.withAlphaComponent(0.82)
                : NSColor.black.withAlphaComponent(0.55)
        ).cgColor
        if isDownloaded && wasDownloading {
            showCompletionBadge()
        }
        view.needsLayout = true
    }

    private func showCompletionBadge() {
        completionHideWorkItem?.cancel()
        completionRevealWorkItem?.cancel()
        isCompletionAnimating = true
        downloadBtn.isHidden = true
        setWallpaperBtn.isHidden = true
        downloadedBadge.isHidden = true
        completionBadgeView.isHidden = false
        completionBadgeView.alphaValue = 1
        completionBadgeView.frame.origin = setWallpaperBtn.frame.origin
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        completionBadgeView.layer?.transform = CATransform3DMakeScale(0.72, 0.72, 1)
        CATransaction.commit()

        let bounce = CAKeyframeAnimation(keyPath: "transform.scale")
        bounce.values = [0.72, 1.16, 0.94, 1.0]
        bounce.keyTimes = [0, 0.45, 0.78, 1]
        bounce.duration = 0.34
        bounce.timingFunctions = [
            UIInteractionAnimation.cardEnterTiming,
            UIInteractionAnimation.cardExitTiming,
            UIInteractionAnimation.cardExitTiming
        ]
        completionBadgeView.layer?.add(bounce, forKey: "completion.badge.bounce")

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        completionBadgeView.layer?.transform = CATransform3DIdentity
        CATransaction.commit()

        let bounceDuration: TimeInterval = 0.34
        let moveDuration: TimeInterval = 0.26
        let revealLead: TimeInterval = 0.08
        let revealWork = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.isCompletionAnimating = false
            self.downloadedBadge.isHidden = false
            self.setWallpaperBtn.isHidden = false
        }
        completionRevealWorkItem = revealWork
        DispatchQueue.main.asyncAfter(deadline: .now() + bounceDuration + max(0, moveDuration - revealLead), execute: revealWork)

        DispatchQueue.main.asyncAfter(deadline: .now() + bounceDuration) { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = moveDuration
                ctx.timingFunction = UIInteractionAnimation.cardExitTiming
                self.completionBadgeView.animator().frame.origin = self.downloadedBadge.frame.origin
            } completionHandler: {
                NSAnimationContext.runAnimationGroup { fadeCtx in
                    fadeCtx.duration = 0.14
                    fadeCtx.timingFunction = UIInteractionAnimation.cardExitTiming
                    self.completionBadgeView.animator().alphaValue = 0
                } completionHandler: {
                    self.completionBadgeView.isHidden = true
                }
            }
        }

        let hideWork = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.isCompletionAnimating = false
            self.completionBadgeView.isHidden = true
            self.completionBadgeView.alphaValue = 1
            self.downloadedBadge.isHidden = false
            self.setWallpaperBtn.isHidden = false
        }
        completionHideWorkItem = hideWork
        DispatchQueue.main.asyncAfter(deadline: .now() + bounceDuration + moveDuration + 0.18, execute: hideWork)
    }

    private func loadThumbnail(url: URL?) {
        thumbnailView.image = nil; placeholderView.isHidden = false; spinner.startAnimation(nil)
        guard let url else { return }
        let id = currentItemID
        thumbnailTask = Task { [weak self] in
            // 命中/未命中两路径统一走缓存的后台解码，避免在主线程重复解码同一份 JPEG
            if let img = await OLThumbnailCache.shared.cachedImage(for: url) {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.currentItemID == id else { return }
                    self.thumbnailView.image = img
                    self.placeholderView.isHidden = true
                    self.spinner.stopAnimation(nil)
                }
                return
            }
            guard !Task.isCancelled else { return }
            guard let data = await OLThumbnailRequestCoordinator.shared.loadData(from: url, priority: .visible),
                  let img = await OLThumbnailCache.shared.storeAndDecode(data: data, for: url) else {
                await MainActor.run {
                    guard let self, self.currentItemID == id else { return }
                    self.spinner.stopAnimation(nil)
                }
                return
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.currentItemID == id else { return }
                self.thumbnailView.image = img
                self.placeholderView.isHidden = true
                self.spinner.stopAnimation(nil)
            }
        }
    }

    @objc private func handleDownload()     { onDownload?() }
    @objc private func handleSetWallpaper() { onSetAsWallpaper?() }

    // MARK: - 右键菜单（UI-4）

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = buildContextMenu() else { super.rightMouseDown(with: event); return }
        NSMenu.popUpContextMenu(menu, with: event, for: imageContainer)
    }

    private func buildContextMenu() -> NSMenu? {
        guard currentItemID != -1 else { return nil }
        let menu = NSMenu()

        // 下载 / 已下载状态
        menu.addItem(
            makeContextMenuItem(
                title: "下载到本地",
                symbolName: "arrow.down.circle",
                action: #selector(handleDownload),
                isEnabled: onDownload != nil
            )
        )

        // 设为壁纸
        menu.addItem(
            makeContextMenuItem(
                title: "设为壁纸",
                symbolName: "display",
                action: #selector(handleSetWallpaper),
                isEnabled: onSetAsWallpaper != nil
            )
        )

        menu.addItem(.separator())

        // 在 Pixabay 上查看
        menu.addItem(
            makeContextMenuItem(
                title: "在 Pixabay 上查看",
                symbolName: "arrow.up.right.square",
                action: #selector(handleOpenInPixabay),
                isEnabled: true
            )
        )

        return menu
    }

    private func makeContextMenuItem(
        title: String,
        symbolName: String,
        action: Selector,
        isEnabled: Bool
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = NSImage.olSymbol(symbolName, pointSize: 14, weight: .regular)
        item.isEnabled = isEnabled
        return item
    }

    @objc private func handleOpenInPixabay() {
        // pageURL 通过 configure 时暂存
        guard let urlString = currentPageURL, let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - 构建层级（只设固定属性，尺寸全在 layout 里算）
    private func buildViewHierarchy() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor

        imageContainer.wantsLayer = true
        imageContainer.layer?.masksToBounds = true
        imageContainer.layer?.borderWidth = 1

        thumbnailView.imageScaling = .scaleAxesIndependently

        placeholderView.wantsLayer = true
        placeholderView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isIndeterminate = true
        placeholderView.addSubview(spinner)

        overlayView.wantsLayer = true
        overlayView.layer?.backgroundColor = NSColor.clear.cgColor

        hoverOutlineView.wantsLayer = true
        hoverOutlineView.layer?.borderWidth = 1
        hoverOutlineView.layer?.backgroundColor = NSColor.clear.cgColor
        hoverOutlineView.alphaValue = 0

        durationBadgeView.wantsLayer = true
        durationBadgeView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor

        durationBadgeTextLayer.alignmentMode = .center
        durationBadgeTextLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        durationBadgeTextLayer.truncationMode = .none
        durationBadgeTextLayer.isWrapped = false
        durationBadgeView.layer?.addSublayer(durationBadgeTextLayer)

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

        titleLabel.textColor = .white; titleLabel.alignment = .left
        titleLabel.maximumNumberOfLines = 1; titleLabel.lineBreakMode = .byClipping
        titleLabel.cell?.wraps = false; titleLabel.cell?.isScrollable = false
        titleLabel.wantsLayer = true  // 提前启用，确保 layer 在 viewDidLayout 时已存在

        metaLabel.textColor = NSColor.white.withAlphaComponent(0.80); metaLabel.alignment = .left
        metaLabel.maximumNumberOfLines = 1; metaLabel.lineBreakMode = .byClipping
        metaLabel.cell?.wraps = false; metaLabel.cell?.isScrollable = false
        metaLabel.wantsLayer = true

        downloadBtn.image = NSImage.olSymbol("arrow.down.circle.fill", pointSize: 16, weight: .regular, accessibilityDescription: "下载")
        downloadBtn.imageScaling = .scaleProportionallyUpOrDown
        downloadBtn.isBordered = false; downloadBtn.contentTintColor = .white
        downloadBtn.target = self; downloadBtn.action = #selector(handleDownload); downloadBtn.toolTip = "下载到本地"

        setWallpaperBtn.image = NSImage.olSymbol("display", pointSize: 16, weight: .regular, accessibilityDescription: "设为壁纸")
        setWallpaperBtn.imageScaling = .scaleProportionallyUpOrDown
        setWallpaperBtn.isBordered = false; setWallpaperBtn.contentTintColor = .white
        setWallpaperBtn.target = self; setWallpaperBtn.action = #selector(handleSetWallpaper); setWallpaperBtn.toolTip = "设为壁纸"

        downloadingSpinner.style = .spinning; downloadingSpinner.controlSize = .small
        downloadingSpinner.isIndeterminate = true; downloadingSpinner.isHidden = true

        downloadProgressView.isHidden = true
        completionBadgeView.wantsLayer = true
        completionBadgeView.layer?.backgroundColor = NSColor.systemGreen.cgColor
        completionBadgeView.layer?.shadowColor = NSColor.black.cgColor
        completionBadgeView.layer?.shadowOpacity = 0.16
        completionBadgeView.layer?.shadowRadius = 6
        completionBadgeView.layer?.shadowOffset = CGSize(width: 0, height: 2)
        completionBadgeView.isHidden = true
        completionBadgeView.alphaValue = 0

        completionBadgeIcon.image = NSImage.olSymbol("checkmark", pointSize: 18, weight: .black, accessibilityDescription: "下载完成")
        completionBadgeIcon.contentTintColor = .systemGreen.blended(withFraction: 0.55, of: .black) ?? .black
        completionBadgeIcon.imageScaling = .scaleProportionallyUpOrDown

        downloadedBadge.image = NSImage.olSymbol("checkmark.circle.fill", pointSize: 15, weight: .semibold, accessibilityDescription: "已下载")
        downloadedBadge.imageScaling = .scaleProportionallyUpOrDown
        downloadedBadge.contentTintColor = .systemGreen; downloadedBadge.isHidden = true

        view.addSubview(imageContainer)
        imageContainer.addSubview(thumbnailView)
        imageContainer.addSubview(placeholderView)
        imageContainer.addSubview(overlayView)
        overlayView.layer?.addSublayer(gradientLayer)
        overlayView.addSubview(durationBadgeView)
        overlayView.addSubview(titleLabel)
        overlayView.addSubview(metaLabel)
        overlayView.addSubview(downloadBtn)
        overlayView.addSubview(setWallpaperBtn)
        overlayView.addSubview(downloadProgressView)
        overlayView.addSubview(downloadingSpinner)
        overlayView.addSubview(downloadedBadge)
        overlayView.addSubview(completionBadgeView)
        completionBadgeView.addSubview(completionBadgeIcon)
        imageContainer.addSubview(hoverOutlineView)

        let tracking = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect],
            owner: self, userInfo: nil
        )
        imageContainer.addTrackingArea(tracking)
        trackingAreaRef = tracking
        imageContainer.appearanceDidChangeHandler = { [weak self] in self?.refreshTheme() }
        applyHoverVisibility(false, animated: false)
        refreshTheme()
    }

    // MARK: - 手动 Frame 布局
    // 所有元素尺寸均相对卡片宽度，彻底解决列数变化时布局混乱

    private func fontSizeForWidth(_ w: CGFloat) -> (title: CGFloat, meta: CGFloat, badge: CGFloat) {
        // 三档字号：小卡(w<160) / 中卡(160-260) / 大卡(>260)
        switch w {
        case ..<160:      return (9,  8,  9)
        case 160..<260:  return (11, 10, 11)
        default:          return (13, 11, 12)
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let w = view.bounds.width
        guard w > 0 else { return }
        let h = floor(w * 9.0 / 16.0)

        // imageContainer: 16:9，顶部对齐
        imageContainer.frame = NSRect(x: 0, y: view.bounds.height - h, width: w, height: h)

        let radius = max(6, w * 0.045)
        imageContainer.layer?.cornerRadius = radius

        hoverOutlineView.layer?.cornerRadius = max(5, radius - 1)

        thumbnailView.frame = imageContainer.bounds
        placeholderView.frame = imageContainer.bounds
        overlayView.frame = imageContainer.bounds
        let spinSz: CGFloat = min(20, w * 0.12)
        spinner.frame = NSRect(x: (w-spinSz)/2, y: (h-spinSz)/2, width: spinSz, height: spinSz)
        hoverOutlineView.frame = NSRect(x: 1, y: 1, width: w-2, height: h-2)

        let (titleSz, metaSz, badgeSz) = fontSizeForWidth(w)
        let pad = max(6, w * 0.05)   // 内边距，随卡片等比缩放
        let btnBaseSz = max(18, w * 0.13) // 按钮基础边长（实际会与文本区高度对齐）
        let gap   = max(4, w * 0.03)  // 按钮间距
        let textBlockYOffset = max(2, w * 0.012)

        // 字体（只在档位变化时重设，避免每帧重建）
        if titleLabel.font?.pointSize != titleSz {
            titleLabel.font    = .systemFont(ofSize: titleSz, weight: .medium)
            metaLabel.font     = .monospacedDigitSystemFont(ofSize: metaSz, weight: .regular)
        }

        // 时长角标（左上角，非 hover）
        let badgeHPad = max(7, w * 0.040)
        let badgeVPad = max(4, w * 0.020)
        let badgeFont = NSFont.monospacedDigitSystemFont(ofSize: badgeSz, weight: .semibold)
        let badgeText = (durationBadgeTextLayer.string as? String) ?? ""
        let badgeAttrs: [NSAttributedString.Key: Any] = [
            .font: badgeFont,
            .foregroundColor: NSColor.white
        ]
        let badgeTextSz = (badgeText as NSString).size(withAttributes: badgeAttrs)
        let bw = ceil(badgeTextSz.width + badgeHPad * 2)
        let bh = ceil(badgeTextSz.height + badgeVPad * 2)
        durationBadgeView.frame = NSRect(x: pad, y: h - pad - bh, width: bw, height: bh)
        durationBadgeView.layer?.cornerRadius = bh * 0.35
        durationBadgeTextLayer.font = badgeFont
        durationBadgeTextLayer.fontSize = badgeFont.pointSize
        durationBadgeTextLayer.foregroundColor = NSColor.white.cgColor
        durationBadgeTextLayer.frame = CGRect(
            x: badgeHPad,
            y: floor((bh - badgeTextSz.height) / 2.0) - 1,
            width: max(0, bw - badgeHPad * 2),
            height: ceil(badgeTextSz.height) + 2
        )

        // 标题行（上）/ 元数据行（下）
        let titleH = titleSz + 3
        let provisionalDlX = w - pad - btnBaseSz - pad - btnBaseSz
        let textMaxW = provisionalDlX - pad - gap  // 先用基础按钮宽度估算
        titleLabel.frame = NSRect(
            x: pad,
            y: pad + titleSz + gap - textBlockYOffset,
            width: max(10, textMaxW),
            height: titleH
        )

        // meta 行（标题下方）
        let metaH = metaSz + 2
        let metaY = pad - textBlockYOffset
        metaLabel.frame = NSRect(x: pad, y: metaY, width: max(10, textMaxW), height: metaH)

        // 按钮区：顶部对齐标题行顶部，底部对齐元数据行底部；右边距与两按钮间距一致
        let actionTop = titleLabel.frame.maxY
        let actionBottom = metaLabel.frame.minY
        let btnSz = max(btnBaseSz, actionTop - actionBottom)
        let actionGap = pad
        let setWpX = w - actionGap - btnSz
        let setWpY = actionBottom
        let dlX = setWpX - actionGap - btnSz

        setWallpaperBtn.frame = NSRect(x: setWpX, y: setWpY, width: btnSz, height: btnSz)
        downloadBtn.frame = NSRect(x: dlX, y: setWpY, width: btnSz, height: btnSz)
        downloadingSpinner.frame = NSRect(x: setWpX, y: setWpY, width: btnSz, height: btnSz)
        downloadProgressView.frame = NSRect(x: setWpX, y: setWpY, width: btnSz, height: btnSz)
        downloadedBadge.frame = NSRect(x: dlX, y: setWpY, width: btnSz, height: btnSz)

        completionBadgeView.frame = NSRect(x: setWpX, y: setWpY, width: btnSz, height: btnSz)
        completionBadgeView.layer?.cornerRadius = btnSz / 2
        let iconSize = btnSz * 0.52
        completionBadgeIcon.frame = NSRect(
            x: floor((btnSz - iconSize) / 2),
            y: floor((btnSz - iconSize) / 2),
            width: iconSize,
            height: iconSize
        )
        if abs(lastSymbolPointSize - btnSz) > 0.5 {
            let symbolPt = max(12, btnSz * 0.82)
            downloadBtn.image = NSImage.olSymbol("arrow.down.circle.fill", pointSize: symbolPt, weight: .regular, accessibilityDescription: "下载")
            setWallpaperBtn.image = NSImage.olSymbol("display", pointSize: symbolPt * 0.9, weight: .regular, accessibilityDescription: "设为壁纸")
            downloadedBadge.image = NSImage.olSymbol("checkmark.circle.fill", pointSize: symbolPt * 0.88, weight: .semibold, accessibilityDescription: "已下载")
            completionBadgeIcon.image = NSImage.olSymbol("checkmark", pointSize: max(11, iconSize * 0.88), weight: .black, accessibilityDescription: "下载完成")
            lastSymbolPointSize = btnSz
        }

        // 按钮尺寸变化后，回写两行文本可用宽度
        let finalTextWidth = max(10, dlX - pad - gap)
        titleLabel.frame.size.width = finalTextWidth
        metaLabel.frame.size.width = finalTextWidth

        // 仅同步 overlay 与圆角容器边界，不做全屏阴影效果
        overlayView.frame = imageContainer.bounds
        gradientLayer.frame = overlayView.bounds

        applyTextFadeMasksIfNeeded()

        // 检查当前鼠标是否已经在卡片范围内（解决导入新文件时不显示 meta 的问题）
        checkInitialHoverState()

        imageContainer.ensureLayerAnchorCentered()
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

    private func applyTextFadeMasksIfNeeded() {
        applyFadeMaskIfNeeded(to: titleLabel)
        applyFadeMaskIfNeeded(to: metaLabel)
    }

    private func applyFadeMaskIfNeeded(to label: NSTextField) {
        let textW = label.attributedStringValue.size().width
        let viewW = label.frame.width
        guard viewW > 0 else {
            label.layer?.mask = nil
            return
        }
        if textW > viewW - 6 {
            let fadeW = min(32, viewW * 0.25)
            let start = 1.0 - fadeW / viewW
            let mask = CAGradientLayer()
            mask.colors = [NSColor.black.cgColor, NSColor.clear.cgColor]
            mask.startPoint = CGPoint(x: start, y: 0.5)
            mask.endPoint = CGPoint(x: 1.0, y: 0.5)
            mask.frame = CGRect(origin: .zero, size: CGSize(width: viewW, height: label.frame.height))
            label.wantsLayer = true
            label.layer?.mask = mask
        } else {
            label.layer?.mask = nil
        }
    }

    private func applyHoverVisibility(_ visible: Bool, animated: Bool) {
        hoverVisible = visible
        let alpha: CGFloat = visible ? 1 : 0
        let badgeAlpha: CGFloat = visible ? 0 : 1
        let gradientOpacity: Float = visible ? 1.0 : 0.0
        if animated {
            let dur = visible ? UIInteractionAnimation.cardHoverExpandDuration : UIInteractionAnimation.cardHoverCollapseDuration
            let tim = visible ? UIInteractionAnimation.cardEnterTiming : UIInteractionAnimation.cardExitTiming
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = dur; ctx.timingFunction = tim
                titleLabel.animator().alphaValue  = alpha
                metaLabel.animator().alphaValue   = alpha
                downloadBtn.animator().alphaValue  = alpha
                setWallpaperBtn.animator().alphaValue = alpha
                downloadProgressView.animator().alphaValue = isDownloadingState ? 1 : alpha
                downloadingSpinner.animator().alphaValue = 0
                downloadedBadge.animator().alphaValue = alpha
                durationBadgeView.animator().alphaValue = badgeAlpha
                gradientLayer.opacity = gradientOpacity
            }
        } else {
            titleLabel.alphaValue  = alpha
            metaLabel.alphaValue   = alpha
            downloadBtn.alphaValue  = alpha
            setWallpaperBtn.alphaValue = alpha
            downloadProgressView.alphaValue = isDownloadingState ? 1 : alpha
            downloadingSpinner.alphaValue = 0
            downloadedBadge.alphaValue = alpha
            durationBadgeView.alphaValue = badgeAlpha
            gradientLayer.opacity = gradientOpacity
        }
    }

    // MARK: - Hover
    override func mouseEntered(with event: NSEvent) {
        guard Self.hoverTrackingActivated else { return }
        isHovering = true; applyHoverState(true)
    }
    override func mouseExited(with event: NSEvent) {
        guard Self.hoverTrackingActivated else { return }
        isHovering = false; applyHoverState(false)
    }
    override func mouseMoved(with event: NSEvent) {
        if !Self.hoverTrackingActivated { Self.hoverTrackingActivated = true }
        let p = imageContainer.convert(event.locationInWindow, from: nil)
        let now = imageContainer.bounds.contains(p)
        guard now != isHovering else { return }
        isHovering = now; applyHoverState(now)
    }

    private func applyHoverState(_ hovered: Bool) {
        let dur = hovered ? UIInteractionAnimation.cardHoverExpandDuration : UIInteractionAnimation.cardHoverCollapseDuration
        let tim = hovered ? UIInteractionAnimation.cardEnterTiming : UIInteractionAnimation.cardExitTiming
        applyHoverOutline(hovered, duration: dur, timing: tim)
        let targetScale: CGFloat
        if hovered {
            targetScale = isPressingCard ? UIInteractionAnimation.cardPressedScale : UIInteractionAnimation.cardHoverScale
        } else {
            targetScale = 1.0
        }
        applyCardScale(targetScale: targetScale, duration: dur, timing: tim)
        applyHoverVisibility(hovered, animated: true)
    }

    func applyPressedState(_ pressed: Bool) {
        guard isPressingCard != pressed else { return }
        isPressingCard = pressed
        guard isHovering else { return }
        applyCardScale(
            targetScale: pressed ? UIInteractionAnimation.cardPressedScale : UIInteractionAnimation.cardHoverScale,
            duration: pressed ? UIInteractionAnimation.cardPressDownDuration : UIInteractionAnimation.cardPressUpDuration,
            timing: pressed ? UIInteractionAnimation.cardEnterTiming : UIInteractionAnimation.cardExitTiming
        )
    }

    private func applyCardScale(targetScale: CGFloat, duration: CFTimeInterval, timing: CAMediaTimingFunction) {
        guard let layer = imageContainer.layer else { return }
        imageContainer.ensureLayerAnchorCentered()
        guard abs(currentCardScale - targetScale) > 0.0001 else { return }
        let from = (layer.presentation()?.value(forKeyPath: "transform.scale") as? CGFloat) ?? currentCardScale
        let anim = CABasicAnimation(keyPath: "transform.scale")
        anim.fromValue = from; anim.toValue = targetScale
        anim.duration = duration; anim.timingFunction = timing
        layer.add(anim, forKey: "card.hover.scale")
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.transform = CATransform3DMakeScale(targetScale, targetScale, 1)
        CATransaction.commit()
        currentCardScale = targetScale
    }

    private func applyHoverOutline(_ hovered: Bool, duration: CFTimeInterval, timing: CAMediaTimingFunction) {
        let target: CGFloat = hovered ? 1 : 0
        guard isHoverOutlineVis != hovered || abs(hoverOutlineView.alphaValue - target) > 0.0001 else { return }
        isHoverOutlineVis = hovered
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration; ctx.timingFunction = timing
            hoverOutlineView.animator().alphaValue = target
        }
    }

    // MARK: - 主题
    private func refreshTheme() {
        guard let layer = imageContainer.layer else { return }
        layer.borderColor = NSColor.separatorColor.cgColor
        hoverOutlineView.layer?.borderColor = view.isDarkAppearance
            ? NSColor.white.cgColor : NSColor.controlAccentColor.cgColor
    }
}
