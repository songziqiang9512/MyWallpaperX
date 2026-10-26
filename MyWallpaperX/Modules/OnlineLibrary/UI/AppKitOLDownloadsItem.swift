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
    nonisolated static func cacheKey(for url: URL) -> String {
        OnlineLibraryDownloadedFileIdentity.key(for: url)
    }
}

// The object bridges cancellation and AVFoundation's callback exactly once.
nonisolated private final class OLThumbnailVideoGeneration: @unchecked Sendable {
    private let lock = NSLock()
    private let generator: AVAssetImageGenerator
    private var continuation: CheckedContinuation<NSImage?, Never>?
    private var cancelled = false

    init(url: URL) {
        generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 520, height: 300)
    }

    func image() async -> NSImage? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                lock.lock()
                if cancelled { lock.unlock(); continuation.resume(returning: nil); return }
                self.continuation = continuation
                generator.generateCGImageAsynchronously(for: CMTime(seconds: 0.5, preferredTimescale: 600)) { [self] image, _, _ in
                    finish(image.map { NSImage(cgImage: $0, size: .zero) })
                }
                lock.unlock()
            }
        } onCancel: { self.cancel() }
    }

    private func finish(_ image: NSImage?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        let result = cancelled ? nil : image
        lock.unlock()
        pending?.resume(returning: result)
    }

    private func cancel() {
        lock.lock()
        cancelled = true
        let pending = continuation
        continuation = nil
        lock.unlock()
        generator.cancelAllCGImageGeneration()
        pending?.resume(returning: nil)
    }
}

extension OLDownloadedThumbnailStore {
    nonisolated static func generateThumbnail(from url: URL) async -> NSImage? {
        await OLThumbnailVideoGeneration(url: url).image()
    }

    static func prefetch(_ entry: OLDownloadedEntry, cancellation: ThumbnailCacheRequestCancellation,
        completion: @escaping (String, NSImage?) -> Void) {
        guard !cancellation.cancelled else { return }
        // The scan fingerprint is a ready-memory hint only. A queued miss may
        // read a replacement file, so resolve its actual identity off the UI lane.
        if let preparedKey = entry.thumbnailSourceKey, let image = sharedCache.cachedImage(forKey: preparedKey) {
            completion(preparedKey, image)
            return
        }
        let url = entry.localURL
        Task {
            let key = await Task.detached(priority: .utility) {
                guard !cancellation.cancelled else { return Optional<String>.none }
                return cacheKey(for: url)
            }.value
            guard let key, !cancellation.cancelled else { return }
            sharedCache.loadImageAsync(forKey: key, priority: .prefetch, cancellation: cancellation, loader: {
                // The producer may wait behind another generation. Never publish
                // pixels from a later source revision under this request's key.
                guard cacheKey(for: url) == key else { cancellation.cancel(); return nil }
                let image = await generateThumbnail(from: url)
                guard cacheKey(for: url) == key else { cancellation.cancel(); return nil }
                return image
            }, completion: { image in completion(key, image) })
        }
    }
}

// MARK: - 视频库同款播放按钮



// MARK: - 卡片

final class AppKitOLDownloadsItem: WallpaperCardCollectionViewItem, WallpaperGridHoverItem {
    private struct LayoutInputs: Equatable {
        let size: NSSize
        let title: String
        let metadata: String
        let placeholder: String
    }
    private var lastLayoutInputs: LayoutInputs?

    static let reuseIdentifier = NSUserInterfaceItemIdentifier("AppKitOLDownloadsItem")

    private static var hoverTrackingActivated = false

    static func resetHoverTrackingActivation() {
        hoverTrackingActivated = false
    }

    private let imageContainer = AppearanceAwareContainerView()
    private let hoverTracking = WallpaperGridHoverTracking()
    private let thumbnailView = NSImageView()
    private let placeholderLabel = NSTextField(labelWithString: "加载中...")
    private let selectionTintView = NSView()
    private let hoverOutlineView = NSView()
    private let overlayView = NSView()
    private var currentTitle = ""
    private var currentMetadata = ""
    private var controlBar: WallpaperCardControlsView?
    private var controlBarFrame = NSRect.zero
    private var barVisibilityRevision: UInt64 = 0
    var onPrimaryAction: ((Int) -> Void)? {
        didSet { controlBar?.playButton.isEnabled = onPrimaryAction != nil && !isSwitching }
    }
    var onToggleFavorite: ((Int) -> Void)? {
        didSet { controlBar?.favoriteButton.isHidden = onToggleFavorite == nil }
    }
    private let multiSelectBadge = NSView()
    private let multiSelectBadgeIcon = NSImageView()

    private var isHovering = false
    private var isMultiSelectMode = false
    private var isHoverOutlineVisible = false
    private var thumbnailRequestID = UUID()
    private var thumbnailCancellation: ThumbnailCacheRequestCancellation?
    private var thumbnailLoadingWork: DispatchWorkItem?
    private var isThumbnailDemandActive = true
    private var presentedEntry: OLDownloadedEntry?
    private var currentEntryID = -1
    private var isSelectedState = false
    private var isPlaying = false
    private var isSwitching = false
    private var isFavoriteState = false
    private var primaryShowsStop = false

    override init(nibName: NSNib.Name?, bundle: Bundle?) {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }


    override func loadView() {
        view = WallpaperCardInteractionView()
        buildViewHierarchy()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        lastLayoutInputs = nil
        thumbnailRequestID = UUID()
        thumbnailCancellation?.cancel()
        thumbnailCancellation = nil
        isThumbnailDemandActive = true
        thumbnailLoadingWork?.cancel(); thumbnailLoadingWork = nil
        presentedEntry = nil
        currentEntryID = -1
        thumbnailView.image = nil
        placeholderLabel.stringValue = "加载中..."
        placeholderLabel.isHidden = false
        currentTitle = ""
        currentMetadata = ""
        isHovering = false
        isSelectedState = false
        isMultiSelectMode = false
        isPlaying = false; isSwitching = false; isFavoriteState = false; primaryShowsStop = false
        hoverOutlineView.alphaValue = 0
        isHoverOutlineVisible = false
        selectionTintView.alphaValue = 0
        multiSelectBadge.isHidden = true
        multiSelectBadgeIcon.isHidden = true
        controlBar?.playButton.contentTintColor = .labelColor
        onPrimaryAction = nil; onToggleFavorite = nil
        updateControlBarContent()
        applyHoverVisibility(false, animated: false)
        refreshTheme()
    }

    func configure(
        entry: OLDownloadedEntry,
        isSelected: Bool,
        isMultiSelectMode: Bool,
        isPlaying: Bool,
        thumbnailDemandActive: Bool? = nil
    ) {
        let wasActive = isThumbnailDemandActive
        if currentEntryID != entry.id { isSwitching = false }
        if let thumbnailDemandActive { isThumbnailDemandActive = thumbnailDemandActive }
        if !isThumbnailDemandActive { endDisplayingThumbnail() }
        applySelectionState(isSelected, multiSelectMode: isMultiSelectMode)
        applyPlayingState(isPlaying: isPlaying)
        guard presentedEntry != entry else {
            if isThumbnailDemandActive && !wasActive { beginDisplayingThumbnail() }
            return
        }
        let imageChanged = currentEntryID != entry.id || presentedEntry?.localURL != entry.localURL
            || presentedEntry?.fileSize != entry.fileSize || presentedEntry?.thumbnailSourceKey != entry.thumbnailSourceKey
        presentedEntry = entry
        currentEntryID = entry.id
        currentTitle = entry.displayTitle
        currentMetadata = entry.metaLine
        updateControlBarContent()
        view.needsLayout = true

        guard imageChanged else {
            if isThumbnailDemandActive && !wasActive { beginDisplayingThumbnail() }
            return
        }
        thumbnailCancellation?.cancel(); thumbnailCancellation = nil
        thumbnailLoadingWork?.cancel(); thumbnailLoadingWork = nil
        let requestID = UUID()
        thumbnailRequestID = requestID
        thumbnailView.image = nil
        placeholderLabel.stringValue = "加载中..."
        placeholderLabel.isHidden = true
        guard isThumbnailDemandActive else { return }
        // Visible cards preserve the live file fingerprint check: an external
        // replacement can happen before the next library scan refreshes entry.
        let cacheKey = OLDownloadedThumbnailStore.cacheKey(for: entry.localURL)
        if let cached = OLDownloadedThumbnailStore.sharedCache.cachedImage(forKey: cacheKey) {
            thumbnailView.image = cached
            layoutThumbnail()
            placeholderLabel.isHidden = true
            return
        }

        let loadingWork = DispatchWorkItem { [weak self] in
            guard let self, self.thumbnailRequestID == requestID, self.thumbnailView.image == nil else { return }
            self.placeholderLabel.isHidden = false
        }
        thumbnailLoadingWork = loadingWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: loadingWork)
        let id = entry.id
        let url = entry.localURL
        weak let item = self
        // 共享缓存自带 in-flight 去重与失败负缓存：同键并发只抽一次帧，
        // 失败（损坏/不支持的编码）记录结论后不再重复 AVAsset 重试。
        let cancellation = ThumbnailCacheRequestCancellation()
        thumbnailCancellation = cancellation
        OLDownloadedThumbnailStore.sharedCache.loadImageAsync(forKey: cacheKey, priority: .visible,
            cancellation: cancellation, loader: {
            await OLDownloadedThumbnailStore.generateThumbnail(from: url)
        }, completion: { image in
            // ThumbnailCache 统一主线程回调；卡片已复用为其他条目时丢弃结果
            guard let item, item.currentEntryID == id, item.thumbnailRequestID == requestID else { return }
            item.thumbnailCancellation = nil
            item.thumbnailLoadingWork?.cancel(); item.thumbnailLoadingWork = nil
            if let image {
                item.thumbnailView.image = image
                item.layoutThumbnail()
                item.placeholderLabel.isHidden = true
            } else {
                // 生成失败：结束加载态，呈现静态失败文案，
                // 避免占位符永远停留「加载中...」。
                item.showThumbnailFailureState()
            }
        })
    }

    func endDisplayingThumbnail() {
        isThumbnailDemandActive = false
        controlBar?.setActive(false)
        thumbnailCancellation?.cancel()
        thumbnailCancellation = nil
        thumbnailLoadingWork?.cancel(); thumbnailLoadingWork = nil
        thumbnailRequestID = UUID()
    }

    func beginDisplayingThumbnail() {
        isThumbnailDemandActive = true
        applyHoverVisibility(isHovering, animated: false)
        guard thumbnailView.image == nil, thumbnailCancellation == nil, let entry = presentedEntry else { return }
        presentedEntry = nil
        configure(entry: entry, isSelected: isSelectedState, isMultiSelectMode: isMultiSelectMode, isPlaying: isPlaying)
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

        thumbnailView.imageScaling = .scaleProportionallyUpOrDown

        placeholderLabel.alignment = .center
        placeholderLabel.textColor = .secondaryLabelColor
        placeholderLabel.font = .systemFont(ofSize: 11, weight: .regular)

        selectionTintView.wantsLayer = true
        selectionTintView.alphaValue = 0

        overlayView.wantsLayer = true
        overlayView.layer?.backgroundColor = NSColor.clear.cgColor
        hoverOutlineView.wantsLayer = true
        hoverOutlineView.layer?.borderWidth = 1
        hoverOutlineView.layer?.backgroundColor = NSColor.clear.cgColor
        hoverOutlineView.alphaValue = 0

        multiSelectBadge.wantsLayer = true
        multiSelectBadge.layer?.masksToBounds = true
        multiSelectBadge.isHidden = true

        multiSelectBadgeIcon.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
        multiSelectBadgeIcon.contentTintColor = .white
        multiSelectBadgeIcon.imageScaling = .scaleProportionallyDown
        multiSelectBadgeIcon.translatesAutoresizingMaskIntoConstraints = false
        multiSelectBadgeIcon.isHidden = true


        view.addSubview(imageContainer)
        imageContainer.addSubview(thumbnailView)
        imageView = thumbnailView
        imageContainer.addSubview(selectionTintView)
        imageContainer.addSubview(multiSelectBadge)
        multiSelectBadge.addSubview(multiSelectBadgeIcon)
        imageContainer.addSubview(hoverOutlineView)
        imageContainer.addSubview(overlayView)
        imageContainer.addSubview(placeholderLabel)

        hoverTracking.update(in: imageContainer, owner: self)

        imageContainer.appearanceDidChangeHandler = { [weak self] in
            self?.refreshTheme()
        }

        applyHoverVisibility(false, animated: false)
        refreshTheme()
    }



    override func viewDidLayout() {
        super.viewDidLayout()
        hoverTracking.update(in: imageContainer, owner: self)
        let inputs = LayoutInputs(size: view.bounds.size, title: currentTitle,
            metadata: currentMetadata, placeholder: placeholderLabel.stringValue)
        guard lastLayoutInputs != inputs else {
            refreshGridHover(isScrolling: view.isGridHoverSuppressed)
            return
        }
        lastLayoutInputs = inputs

        let width = view.bounds.width
        guard width > 0 else { return }
        let height = width

        imageContainer.frame = NSRect(x: 0, y: view.bounds.height - height, width: width, height: height)

        let radius: CGFloat = 14
        imageContainer.layer?.cornerRadius = radius

        hoverOutlineView.layer?.cornerRadius = max(5, radius - 1)

        layoutThumbnail()
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

        let metrics = WallpaperCardBarMetrics(cardWidth: width)
        controlBarFrame = NSRect(x: metrics.barHorizontalInset, y: metrics.barBottomInset,
            width: max(0, width - metrics.barHorizontalInset * 2), height: metrics.barHeight)
        controlBar?.frame = controlBarFrame
        controlBar?.apply(metrics: metrics)
        updateControlBarContent()

        // 布局改变后按当前指针位置双向同步 hover。
        refreshGridHover(isScrolling: view.isGridHoverSuppressed)

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






    /// Keep the glass-backed control out of an idle card's initial hierarchy.
    /// Native buttons own hit testing; the collection supplies current-ID actions.
    private func prepareControlBarIfNeeded() {
        guard controlBar == nil else { return }
        let bar = WallpaperCardControlsView(frame: controlBarFrame)
        bar.onPlay = { [weak self] in
            guard let self, !self.isMultiSelectMode, self.presentedEntry != nil else { return }
            self.onPrimaryAction?(self.currentEntryID)
        }
        bar.onFavorite = { [weak self] in
            guard let self, !self.isMultiSelectMode, self.presentedEntry != nil else { return }
            self.onToggleFavorite?(self.currentEntryID)
        }
        controlBar = bar
        bar.apply(metrics: WallpaperCardBarMetrics(cardWidth: imageContainer.bounds.width))
        bar.layoutSubtreeIfNeeded()
        updateControlBarContent()
    }

    private func updateControlBarContent() {
        controlBar?.apply(title: currentTitle, metadata: currentMetadata)
        controlBar?.favoriteButton.isHidden = onToggleFavorite == nil
        controlBar?.playButton.isEnabled = onPrimaryAction != nil && !isSwitching
        controlBar?.isFavorite = isFavoriteState
        controlBar?.primaryState = isSwitching ? .switching : (primaryShowsStop && isPlaying ? .playing : .apply)
        controlBar?.playButton.contentTintColor = isPlaying && !isSwitching ? .controlAccentColor : .labelColor
        view.toolTip = nil
    }

    /// Only the mixed-library adapter binds a real play/stop command owner.
    func applyOrganizationState(isFavorite: Bool, primaryShowsStop: Bool) {
        isFavoriteState = isFavorite
        self.primaryShowsStop = primaryShowsStop
        updateControlBarContent()
    }

    private func layoutThumbnail() {
        let bounds = imageContainer.bounds
        guard let size = thumbnailView.image?.size, size.width > 0, size.height > 0 else {
            thumbnailView.frame = bounds
            return
        }
        let scale = max(bounds.width / size.width, bounds.height / size.height)
        let fitted = NSSize(width: size.width * scale, height: size.height * scale)
        thumbnailView.frame = NSRect(x: (bounds.width-fitted.width)/2, y: (bounds.height-fitted.height)/2,
                                     width: fitted.width, height: fitted.height)
    }

    private func applyHoverVisibility(_ visible: Bool, animated: Bool) {
        let show = (visible || isPlaying || isSwitching) && !isMultiSelectMode
        if show { prepareControlBarIfNeeded() }
        guard let bar = controlBar else { return }
        barVisibilityRevision &+= 1
        let revision = barVisibilityRevision
        if show {
            if bar.superview == nil { overlayView.addSubview(bar) }
            bar.isHidden = false
        }
        bar.setActive(show && visible && isThumbnailDemandActive)
        let finish = { [weak self, weak bar] in
            guard let self, let bar, self.barVisibilityRevision == revision, !show else { return }
            bar.isHidden = true
            bar.removeFromSuperview()
        }
        if animated && bar.superview != nil {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = visible ? UIInteractionAnimation.cardHoverExpandDuration : UIInteractionAnimation.cardHoverCollapseDuration
                context.timingFunction = visible ? UIInteractionAnimation.cardEnterTiming : UIInteractionAnimation.cardExitTiming
                bar.animator().alphaValue = show ? 1 : 0
            } completionHandler: { DispatchQueue.main.async(execute: finish) }
        } else {
            bar.alphaValue = show ? 1 : 0
            finish()
        }
    }

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
        isHovering = true
        applyHoverState(true)
    }

    override func mouseExited(with event: NSEvent) {
        guard !view.isGridHoverSuppressed else { return }
        guard Self.hoverTrackingActivated || isHovering else { return }
        isHovering = false
        applyHoverState(false)
    }

    override func mouseMoved(with event: NSEvent) {
        guard !view.isGridHoverSuppressed else { return }
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

        applyHoverVisibility(hovered, animated: true)
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
        updateControlBarContent()
        applyHoverVisibility(isHovering, animated: false)
    }

    func applySwitchingState(isSwitching: Bool) {
        guard self.isSwitching != isSwitching else { return }
        self.isSwitching = isSwitching
        updateControlBarContent()
        applyHoverVisibility(isHovering, animated: false)
    }

    private func updateMultiSelectBadge(selected: Bool) {
        multiSelectBadge.isHidden = !isMultiSelectMode
        guard isMultiSelectMode else {
            multiSelectBadgeIcon.isHidden = true
            return
        }
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
