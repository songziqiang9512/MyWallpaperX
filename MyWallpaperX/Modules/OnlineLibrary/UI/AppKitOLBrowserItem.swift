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



final class AppKitOLBrowserItem: NSCollectionViewItem, WallpaperGridHoverItem {
    private struct LayoutInputs: Equatable {
        let size: NSSize
        let title: String
        let metadata: String
        let duration: String
        let backingScale: CGFloat
    }
    private var lastLayoutInputs: LayoutInputs?

    static let reuseIdentifier = NSUserInterfaceItemIdentifier("AppKitOLBrowserItem")
    private static var hoverTrackingActivated = false
    static func resetHoverTrackingActivation() { hoverTrackingActivated = false }

    private let imageContainer     = AppearanceAwareContainerView()
    private let hoverTracking = WallpaperGridHoverTracking()
    private let thumbnailView      = NSImageView()
    private let placeholderView    = NSView()
    private let spinner            = NSProgressIndicator()
    private let overlayView        = NSView()
    private let hoverOutlineView   = NSView()
    private let durationBadgeView  = NSView()
    private let durationBadgeTextLayer = CATextLayer()
    private var currentTitle = ""
    private var currentMetadata = ""
    private let controlBar = WallpaperCardControlsView()
    private var setWallpaperBtn: NSButton { controlBar.playButton }
    private var currentDownloadProgress: Double?
    private var barVisibilityRevision: UInt64 = 0
    private var organization: WallpaperInspectorActions?
    // A UI binding survives same-item status/metadata echoes, but never native
    // reuse or display retirement. It is independent of thumbnail requests.
    private var contextMenuBindingID = UUID()
    private var primaryActionFrame: NSRect {
        setWallpaperBtn.convert(setWallpaperBtn.bounds, to: overlayView)
    }
    private let downloadedBadge    = NSImageView()
    private let completionBadgeView = NSView()
    private let completionBadgeIcon = NSImageView()

    private var isHovering        = false
    private var isHoverOutlineVis = false
    private var isDownloadingState = false
    private var isDownloadedState = false
    private var presentedItem: OnlineLibraryVideoItem?
    private var currentItemID     = -1
    private var currentPageURL:   String? = nil
    private var currentThumbnailURL: URL?
    private var requestedPixelLimit = 0
    private var thumbnailRequestID = UUID()
    private var completionAnimationID = UUID()
    private var thumbnailTask:    Task<Void, Never>?
    private var thumbnailLoadingWork: DispatchWorkItem?
    private var terminalThumbnailFailureGeneration: Int?
    private var isThumbnailDemandActive = true
    private var completionHideWorkItem: DispatchWorkItem?
    private var completionRevealWorkItem: DispatchWorkItem?
    private var isCompletionAnimating = false
    private var onDownload:       (() -> Void)?
    private var onSetAsWallpaper: (() -> Void)?
    private var hoverVisible      = false

    override init(nibName: NSNib.Name?, bundle: Bundle?) { super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    override func loadView() { view = WallpaperCardInteractionView(); buildViewHierarchy() }

    // MARK: - 复用
    override func prepareForReuse() {
        super.prepareForReuse()
        contextMenuBindingID = UUID()
        lastLayoutInputs = nil
        thumbnailRequestID = UUID()
        completionAnimationID = UUID()
        completionBadgeView.layer?.removeAllAnimations()
        thumbnailTask?.cancel(); thumbnailTask = nil
        terminalThumbnailFailureGeneration = nil
        isThumbnailDemandActive = true
        thumbnailLoadingWork?.cancel(); thumbnailLoadingWork = nil
        completionHideWorkItem?.cancel()
        completionHideWorkItem = nil
        completionRevealWorkItem?.cancel()
        completionRevealWorkItem = nil
        isCompletionAnimating = false
        presentedItem = nil
        currentItemID = -1
        currentThumbnailURL = nil
        requestedPixelLimit = 0
        currentPageURL = nil
        thumbnailView.image = nil
        completionHideWorkItem?.cancel()
        completionHideWorkItem = nil
        placeholderView.isHidden = true
        spinner.stopAnimation(nil)
        currentTitle = ""
        durationBadgeTextLayer.string = nil
        currentMetadata = ""
        setDownloadState(isDownloading: false, isDownloaded: false, downloadProgress: nil)
        isHovering = false; hoverVisible = false
        isDownloadedState = false
        hoverOutlineView.alphaValue = 0
        isHoverOutlineVis = false
        completionBadgeView.alphaValue = 0
        completionBadgeView.isHidden = true
        completionBadgeView.layer?.transform = CATransform3DIdentity
        onDownload = nil; onSetAsWallpaper = nil
        organization = nil
        updateControlBarContent()
        applyHoverVisibility(false, animated: false)
        refreshTheme()
    }

    // MARK: - 配置
    func configure(
        item: OnlineLibraryVideoItem,
        isDownloading: Bool, isDownloaded: Bool, downloadProgress: Double?,
        thumbnailDemandActive: Bool? = nil,
        organization: WallpaperInspectorActions? = nil,
        onDownload: @escaping () -> Void,
        onSetAsWallpaper: @escaping () -> Void
    ) {
        let wasActive = isThumbnailDemandActive
        if let thumbnailDemandActive { isThumbnailDemandActive = thumbnailDemandActive }
        if !isThumbnailDemandActive { endDisplayingThumbnail() }
        self.onDownload = onDownload
        self.onSetAsWallpaper = onSetAsWallpaper
        self.organization = organization
        if item.id != currentItemID { contextMenuBindingID = UUID() }
        let imageChanged = item.id != currentItemID || currentThumbnailURL != item.previewThumbnailURL
        currentItemID = item.id
        if presentedItem != item {
            presentedItem = item
            currentPageURL = item.pageURL
            currentTitle = item.displayTitle
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
            currentMetadata = metaParts.joined(separator: "  ")
            view.needsLayout = true
        }
        if imageChanged {
            thumbnailTask?.cancel(); thumbnailTask = nil
            thumbnailLoadingWork?.cancel(); thumbnailLoadingWork = nil
            terminalThumbnailFailureGeneration = nil
            thumbnailRequestID = UUID()
            currentThumbnailURL = item.previewThumbnailURL
            requestedPixelLimit = 0
            thumbnailView.image = nil
            placeholderView.isHidden = true
            spinner.stopAnimation(nil)
            if isThumbnailDemandActive { loadThumbnail(url: item.previewThumbnailURL) }
        } else if isThumbnailDemandActive && !wasActive { beginDisplayingThumbnail() }
        setDownloadState(
            isDownloading: isDownloading,
            isDownloaded: isDownloaded,
            downloadProgress: downloadProgress
        )
    }

    func updateOrganization(_ actions: WallpaperInspectorActions?, for itemID: Int) {
        // A relationship echo may arrive while a diffable source update still
        // displays the old item at this path. Never attach B's actions to A.
        guard currentItemID == itemID else { return }
        organization = actions
        updateControlBarContent()
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
        currentDownloadProgress = downloadProgress
        durationBadgeView.layer?.backgroundColor = (
            isDownloaded
                ? NSColor.systemGreen.blended(withFraction: 0.38, of: .black)?.withAlphaComponent(0.82)
                    ?? NSColor.systemGreen.withAlphaComponent(0.82)
                : NSColor.black.withAlphaComponent(0.55)
        ).cgColor
        if isDownloaded && wasDownloading { showCompletionBadge() }
        updateControlBarContent()
        applyHoverVisibility(hoverVisible, animated: false)
        view.needsLayout = true
    }

    private func updateControlBarContent() {
        controlBar.apply(title: currentTitle, metadata: currentMetadata)
        controlBar.isFavorite = organization?.state.isFavorite ?? false
        controlBar.favoriteButton.isHidden = organization == nil
        controlBar.favoriteButton.isEnabled = organization?.state.canFavorite == true
        setWallpaperBtn.isHidden = isCompletionAnimating
        setWallpaperBtn.isEnabled = !isDownloadingState
        let title = isDownloadingState ? "下载中" : (isDownloadedState ? "设为壁纸" : "下载到本地")
        if isDownloadingState {
            setWallpaperBtn.imagePosition = .noImage
            setWallpaperBtn.title = currentDownloadProgress.map { "\(Int((min(1,max(0,$0))*100).rounded()))%" } ?? "…"
            setWallpaperBtn.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        } else {
            setWallpaperBtn.imagePosition = .imageOnly
            setWallpaperBtn.title = ""
            setWallpaperBtn.image = NSImage(systemSymbolName: isDownloadedState ? "play.fill" : "arrow.down",
                                            accessibilityDescription: title)
        }
        setWallpaperBtn.toolTip = title
        setWallpaperBtn.setAccessibilityLabel(title)
        downloadedBadge.isHidden = !isDownloadedState || isCompletionAnimating || organization != nil
        controlBar.glass.applyProgress(style: isDownloadingState ? .downloading : .neutral,
            fraction: isDownloadingState ? currentDownloadProgress : nil,
            indeterminate: isDownloadingState && currentDownloadProgress == nil, animated: false)
        view.toolTip = nil
    }

    private func showCompletionBadge() {
        let animationID = UUID()
        completionAnimationID = animationID
        completionHideWorkItem?.cancel()
        completionRevealWorkItem?.cancel()
        isCompletionAnimating = true
        setWallpaperBtn.isHidden = true
        downloadedBadge.isHidden = true
        completionBadgeView.isHidden = false
        completionBadgeView.alphaValue = 1
        completionBadgeView.frame.origin = primaryActionFrame.origin
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
            guard let self, self.completionAnimationID == animationID else { return }
            self.isCompletionAnimating = false
            self.downloadedBadge.isHidden = false
            self.setWallpaperBtn.isHidden = false
            self.updateControlBarContent()
            self.applyHoverVisibility(self.hoverVisible, animated: false)
        }
        completionRevealWorkItem = revealWork
        DispatchQueue.main.asyncAfter(deadline: .now() + bounceDuration + max(0, moveDuration - revealLead), execute: revealWork)

        DispatchQueue.main.asyncAfter(deadline: .now() + bounceDuration) { [weak self] in
            guard let self, self.completionAnimationID == animationID else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = moveDuration
                ctx.timingFunction = UIInteractionAnimation.cardExitTiming
                self.completionBadgeView.animator().frame.origin = self.downloadedBadge.frame.origin
            } completionHandler: { [weak self] in
                guard let self, self.completionAnimationID == animationID else { return }
                NSAnimationContext.runAnimationGroup { fadeCtx in
                    fadeCtx.duration = 0.14
                    fadeCtx.timingFunction = UIInteractionAnimation.cardExitTiming
                    self.completionBadgeView.animator().alphaValue = 0
                } completionHandler: { [weak self] in
                    guard let self, self.completionAnimationID == animationID else { return }
                    self.completionBadgeView.isHidden = true
                }
            }
        }

        let hideWork = DispatchWorkItem { [weak self] in
            guard let self, self.completionAnimationID == animationID else { return }
            self.isCompletionAnimating = false
            self.completionBadgeView.isHidden = true
            self.completionBadgeView.alphaValue = 1
            self.downloadedBadge.isHidden = false
            self.setWallpaperBtn.isHidden = false
            self.updateControlBarContent()
            self.applyHoverVisibility(self.hoverVisible, animated: false)
        }
        completionHideWorkItem = hideWork
        DispatchQueue.main.asyncAfter(deadline: .now() + bounceDuration + moveDuration + 0.18, execute: hideWork)
    }

    private func loadThumbnail(url: URL?) {
        guard isThumbnailDemandActive else { return }
        thumbnailTask?.cancel()
        terminalThumbnailFailureGeneration = nil
        thumbnailLoadingWork?.cancel(); thumbnailLoadingWork = nil
        let requestID = UUID()
        thumbnailRequestID = requestID
        if requestedPixelLimit == 0 {
            thumbnailView.image = nil; placeholderView.isHidden = true; spinner.stopAnimation(nil)
        }
        let pixelLimit = GridThumbnailDecoder.pixelLimit(width: view.bounds.width, scale: view.window?.backingScaleFactor ?? 2)
        requestedPixelLimit = pixelLimit
        guard let url else {
            placeholderView.isHidden = false; spinner.stopAnimation(nil)
            return
        }
        if let ready = OLThumbnailCache.shared.readyImage(for: url, maxPixelSize: pixelLimit) {
            thumbnailView.image = ready
            layoutThumbnail()
            placeholderView.isHidden = true
            spinner.stopAnimation(nil)
            return
        }
        if thumbnailView.image == nil {
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.thumbnailRequestID == requestID, self.thumbnailView.image == nil else { return }
                self.placeholderView.isHidden = false
                self.spinner.startAnimation(nil)
            }
            thumbnailLoadingWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
        }
        let id = currentItemID
        thumbnailTask = Task { [weak self] in
            let generation = await OLThumbnailCache.shared.publicationGeneration()
            guard !Task.isCancelled else { return }
            guard let img = await OLThumbnailCache.shared.image(for: url, maxPixelSize: pixelLimit, priority: .visible) else {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.currentItemID == id, self.thumbnailRequestID == requestID else { return }
                    self.terminalThumbnailFailureGeneration = generation
                    self.thumbnailLoadingWork?.cancel(); self.thumbnailLoadingWork = nil
                    if self.thumbnailView.image == nil { self.placeholderView.isHidden = false }
                    self.spinner.stopAnimation(nil)
                }
                return
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.currentItemID == id, self.thumbnailRequestID == requestID else { return }
                self.thumbnailLoadingWork?.cancel(); self.thumbnailLoadingWork = nil
                self.thumbnailView.image = img
                self.layoutThumbnail()
                self.placeholderView.isHidden = true
                self.spinner.stopAnimation(nil)
            }
        }
    }

    func endDisplayingThumbnail() {
        // Called by the original Grid's didEndDisplaying/hide/detach paths.
        contextMenuBindingID = UUID()
        isThumbnailDemandActive = false
        controlBar.setActive(false)
        controlBar.glass.setProgressAnimationVisible(false)
        thumbnailTask?.cancel()
        thumbnailTask = nil
        thumbnailLoadingWork?.cancel(); thumbnailLoadingWork = nil
        spinner.stopAnimation(nil)
        thumbnailRequestID = UUID()
    }

    func beginDisplayingThumbnail() {
        isThumbnailDemandActive = true
        applyHoverVisibility(hoverVisible, animated: false)
        guard thumbnailView.image == nil, thumbnailTask == nil, let url = currentThumbnailURL else { return }
        if let failedGeneration = terminalThumbnailFailureGeneration {
            let requestID = thumbnailRequestID
            thumbnailTask = Task { [weak self] in
                let generation = await OLThumbnailCache.shared.publicationGeneration()
                guard !Task.isCancelled, let self, self.thumbnailRequestID == requestID else { return }
                if generation != failedGeneration { self.loadThumbnail(url: url) }
            }
        } else { loadThumbnail(url: url) }
    }

    // MARK: - 右键菜单（UI-4）

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = buildContextMenu() else { super.rightMouseDown(with: event); return }
        NSMenu.popUpContextMenu(menu, with: event, for: imageContainer)
    }

    private func buildContextMenu() -> NSMenu? {
        guard currentItemID != -1 else { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false

        // 下载 / 已下载状态
        menu.addItem(
            makeContextMenuItem(
                title: "下载到本地",
                symbolName: "arrow.down.circle",
                action: onDownload
            )
        )

        // 设为壁纸
        menu.addItem(
            makeContextMenuItem(
                title: "设为壁纸",
                symbolName: "display",
                action: onSetAsWallpaper
            )
        )

        menu.addItem(.separator())

        // 在 Pixabay 上查看
        let openPage: (() -> Void)? = currentPageURL.flatMap { URL(string: $0) }.map { url in
            { _ = NSWorkspace.shared.open(url) }
        }
        menu.addItem(
            makeContextMenuItem(
                title: "在 Pixabay 上查看",
                symbolName: "arrow.up.right.square",
                action: openPage
            )
        )

        if let organization {
            let id = currentItemID, bindingID = contextMenuBindingID
            menu.addItem(.separator())
            let favorite = ActionMenuItem(title: organization.state.isFavorite ? "取消特别喜爱" : "加入特别喜爱",
                symbol: organization.state.isFavorite ? "heart.fill" : "heart") { [weak self] in
                    guard let self, self.currentItemID == id, self.contextMenuBindingID == bindingID,
                          self.organization?.state.canFavorite == true, organization.state.canFavorite else { return }
                    organization.onToggleFavorite()
                }
            favorite.isEnabled = organization.state.canFavorite
            menu.addItem(favorite)
            let playlist = NSMenuItem(title: "添加到播放列表", action: nil, keyEquivalent: "")
            playlist.image = NSImage(systemSymbolName: WallpaperLibrarySymbols.playlist, accessibilityDescription: nil)
            playlist.submenu = organization.makePlaylistMenu?({ [weak self] in
                guard let self else { return false }
                return self.currentItemID == id && self.contextMenuBindingID == bindingID &&
                    self.organization?.state.canOrganize == true && organization.state.canOrganize
            })
            playlist.isEnabled = organization.state.canOrganize && playlist.submenu != nil
            menu.addItem(playlist)
            if let restore = organization.onRestoreLibrary {
                menu.addItem(makeContextMenuItem(title: "重新加入我的下载", symbolName: "arrow.down.to.line", action: restore))
            }
        }

        return menu
    }

    private func makeContextMenuItem(
        title: String,
        symbolName: String,
        action: (() -> Void)?
    ) -> NSMenuItem {
        let id = currentItemID, bindingID = contextMenuBindingID
        let item = ActionMenuItem(title: title, symbol: symbolName) { [weak self] in
            guard let self, self.currentItemID == id, self.contextMenuBindingID == bindingID else { return }
            action?()
        }
        item.image = item.image?.withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        item.isEnabled = action != nil
        return item
    }

    // MARK: - 构建层级（只设固定属性，尺寸全在 layout 里算）
    private func buildViewHierarchy() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor

        imageContainer.wantsLayer = true
        imageContainer.layer?.masksToBounds = true
        imageContainer.layer?.borderWidth = 1

        thumbnailView.imageScaling = .scaleProportionallyUpOrDown

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

        controlBar.onPlay = { [weak self] in
            guard let self, !self.isDownloadingState, self.currentItemID >= 0 else { return }
            if self.isDownloadedState { self.onSetAsWallpaper?() } else { self.onDownload?() }
        }
        controlBar.onFavorite = { [weak self] in
            guard let self, self.currentItemID >= 0, let actions = self.organization, actions.state.canFavorite else { return }
            actions.onToggleFavorite()
        }
        controlBar.favoriteButton.isHidden = true

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
        imageContainer.addSubview(hoverOutlineView)
        imageContainer.addSubview(overlayView)
        overlayView.addSubview(controlBar)
        overlayView.addSubview(durationBadgeView)
        overlayView.addSubview(downloadedBadge)
        overlayView.addSubview(completionBadgeView)
        completionBadgeView.addSubview(completionBadgeIcon)

        hoverTracking.update(in: imageContainer, owner: self)
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
        hoverTracking.update(in: imageContainer, owner: self)
        let inputs = LayoutInputs(size: view.bounds.size, title: currentTitle,
            metadata: currentMetadata, duration: (durationBadgeTextLayer.string as? String) ?? "", backingScale: view.window?.backingScaleFactor ?? 2)
        guard lastLayoutInputs != inputs else {
            checkInitialHoverState()
            return
        }
        lastLayoutInputs = inputs
        let w = view.bounds.width
        guard w > 0 else { return }
        if let url = currentThumbnailURL,
           GridThumbnailDecoder.pixelLimit(width: w, scale: view.window?.backingScaleFactor ?? 2) > requestedPixelLimit {
            loadThumbnail(url: url)
        }
        let h = w

        // Square preview; the original image stays unchanged for other consumers.
        imageContainer.frame = NSRect(x: 0, y: view.bounds.height - h, width: w, height: h)

        let radius: CGFloat = 14
        imageContainer.layer?.cornerRadius = radius

        hoverOutlineView.layer?.cornerRadius = max(5, radius - 1)

        layoutThumbnail()
        placeholderView.frame = imageContainer.bounds
        overlayView.frame = imageContainer.bounds
        let spinSz: CGFloat = min(20, w * 0.12)
        spinner.frame = NSRect(x: (w-spinSz)/2, y: (h-spinSz)/2, width: spinSz, height: spinSz)
        hoverOutlineView.frame = NSRect(x: 1, y: 1, width: w-2, height: h-2)

        let (_, _, badgeSz) = fontSizeForWidth(w)
        let pad = max(6, w * 0.05)
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

        let metrics = WallpaperCardBarMetrics(cardWidth: w)
        controlBar.frame = NSRect(x: metrics.barHorizontalInset, y: metrics.barBottomInset,
            width: max(0,w-metrics.barHorizontalInset*2), height: metrics.barHeight)
        controlBar.apply(metrics: metrics)
        controlBar.layoutSubtreeIfNeeded()
        let actionFrame = primaryActionFrame
        downloadedBadge.frame = controlBar.favoriteButton.convert(controlBar.favoriteButton.bounds, to: overlayView)
        if !isCompletionAnimating { completionBadgeView.frame = actionFrame }
        completionBadgeView.layer?.cornerRadius = actionFrame.height/2
        let iconSize = actionFrame.height*0.52
        completionBadgeIcon.frame = NSRect(x: (actionFrame.width-iconSize)/2, y: (actionFrame.height-iconSize)/2,
                                           width: iconSize, height: iconSize)
        updateControlBarContent()

        // 检查当前鼠标是否已经在卡片范围内（解决导入新文件时不显示 meta 的问题）
        checkInitialHoverState()
    }

    private func checkInitialHoverState() {
        guard !view.isGridHoverSuppressed else { return }
        let isHoveringNow = view.isGridPointerInside
        if isHoveringNow && !isHovering {
            isHovering = true
            applyHoverVisibility(true, animated: false)
        }
    }





    private func applyHoverVisibility(_ visible: Bool, animated: Bool) {
        hoverVisible = visible
        let show = visible || isDownloadingState || isCompletionAnimating
        barVisibilityRevision &+= 1
        let revision = barVisibilityRevision
        if show {
            if controlBar.superview == nil { overlayView.addSubview(controlBar, positioned: .below, relativeTo: downloadedBadge) }
            controlBar.isHidden = false
        }
        controlBar.setActive(show && visible && isThumbnailDemandActive)
        controlBar.glass.setProgressAnimationVisible(show && isThumbnailDemandActive)
        let finish = { [weak self] in
            guard let self, self.barVisibilityRevision == revision, !show else { return }
            self.controlBar.isHidden = true
            self.controlBar.removeFromSuperview()
        }
        if animated && controlBar.superview != nil {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = visible ? UIInteractionAnimation.cardHoverExpandDuration : UIInteractionAnimation.cardHoverCollapseDuration
                context.timingFunction = visible ? UIInteractionAnimation.cardEnterTiming : UIInteractionAnimation.cardExitTiming
                controlBar.animator().alphaValue = show ? 1 : 0
                downloadedBadge.animator().alphaValue = visible ? 1 : 0
                durationBadgeView.animator().alphaValue = visible ? 0 : 1
            } completionHandler: { DispatchQueue.main.async(execute: finish) }
        } else {
            controlBar.alphaValue = show ? 1 : 0
            downloadedBadge.alphaValue = visible ? 1 : 0
            durationBadgeView.alphaValue = visible ? 0 : 1
            finish()
        }
    }

    private func layoutThumbnail() {
        let bounds = imageContainer.bounds
        guard let size = thumbnailView.image?.size, size.width > 0, size.height > 0 else {
            thumbnailView.frame = bounds
            return
        }
        let scale = max(bounds.width/size.width, bounds.height/size.height)
        let fitted = NSSize(width: size.width*scale, height: size.height*scale)
        thumbnailView.frame = NSRect(x: (bounds.width-fitted.width)/2, y: (bounds.height-fitted.height)/2,
                                     width: fitted.width, height: fitted.height)
    }

    // MARK: - Hover
    func refreshGridHover(isScrolling: Bool) {
        hoverTracking.update(in: imageContainer, owner: self, isScrolling: isScrolling)
        let hovered = !isScrolling && view.isGridPointerInside
        guard hovered != isHovering else { return }
        isHovering = hovered
        applyHoverState(hovered)
    }

    override func mouseEntered(with event: NSEvent) {
        guard !view.isGridHoverSuppressed else { return }
        guard Self.hoverTrackingActivated else { return }
        isHovering = true; applyHoverState(true)
    }
    override func mouseExited(with event: NSEvent) {
        guard !view.isGridHoverSuppressed else { return }
        guard Self.hoverTrackingActivated else { return }
        isHovering = false; applyHoverState(false)
    }
    override func mouseMoved(with event: NSEvent) {
        guard !view.isGridHoverSuppressed else { return }
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
        applyHoverVisibility(hovered, animated: true)
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
        hoverOutlineView.layer?.borderColor = NSColor.white.cgColor
    }
}
