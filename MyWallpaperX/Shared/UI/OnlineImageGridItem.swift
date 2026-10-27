import AppKit

/// Both image sources use the existing card metrics, bar, hover tracking and thumbnail owners.
final class OnlineImageGridItem: WallpaperCardCollectionViewItem, WallpaperGridHoverItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("OnlineImageGridItem")
    private let surface = AppearanceAwareContainerView()
    private let thumbnail = NSImageView()
    private let placeholder = NSTextField(labelWithString: "")
    private let outline = NSView()
    private var bar: WallpaperCardControlsView?
    private let badge = NSTextField(labelWithString: "")
    private let hover = WallpaperGridHoverTracking()
    private let localThumbnails = SILThumbnailProvider()
    private var content: WallpaperContentItem?
    private var request: OLThumbnailRequest?
    private var visible = false, hovering = false, selecting = false, playing = false, busy = false
    private var cardSelected = false, switching = false, favorite = false
    private var fraction: Double?
    private var onPrimary: (() -> Void)?
    private var onFavorite: (() -> Void)?
    private var onPreview: (() -> Void)?
    private var barVisibilityRevision: UInt64 = 0
    private var lastLayoutSize: NSSize?
    private var lastChrome: Chrome?
    private struct Chrome: Equatable {
        let dark: Bool
        let hovered: Bool
        let selected: Bool
        let selecting: Bool
    }
    private var task: Task<Void, Never>?
    private var cancellation: ThumbnailCacheRequestCancellation?
    private var requestID = UUID()
    private var pixelLimit = 0
    private var hasFailed = false
    private var refreshToken: UUID?
    var reference: WallpaperReference? { content?.providerReference }

    deinit { task?.cancel(); cancellation?.cancel() }

    override func loadView() {
        view = WallpaperCardInteractionView()
        surface.wantsLayer = true
        surface.layer?.cornerRadius = 14; surface.layer?.masksToBounds = true
        surface.layer?.borderWidth = 0.8
        outline.wantsLayer = true
        outline.layer?.cornerRadius = 14; outline.layer?.masksToBounds = true
        outline.layer?.backgroundColor = NSColor.clear.cgColor
        outline.alphaValue = 0
        thumbnail.imageScaling = .scaleProportionallyUpOrDown
        imageView = thumbnail
        placeholder.font = .systemFont(ofSize: 11); placeholder.textColor = .secondaryLabelColor
        placeholder.alignment = .center
        badge.font = .systemFont(ofSize: 12, weight: .semibold)
        badge.alignment = .center; badge.textColor = .white
        badge.wantsLayer = true; badge.layer?.cornerRadius = 12
        view.addSubview(surface)
        [thumbnail, placeholder, outline, badge].forEach(surface.addSubview)
        surface.appearanceDidChangeHandler = { [weak self] in
            self?.lastChrome = nil; self?.updateAppearance()
        }
        updateAppearance()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        retireRequest(); content = nil; request = nil; pixelLimit = 0; hasFailed = false
        thumbnail.image = nil; visible = false; hovering = false
        cardSelected = false; selecting = false; switching = false; playing = false; busy = false
        onPrimary = nil; onFavorite = nil; onPreview = nil; bar?.onPreview = nil
        fraction = nil; lastLayoutSize = nil; lastChrome = nil
        barVisibilityRevision &+= 1
        bar?.setActive(false)
        bar?.glass.setProgressAnimationVisible(false); bar?.removeFromSuperview()
        updateAppearance()
    }

    func configure(content: WallpaperContentItem, request: OLThumbnailRequest?, selected: Bool, selecting: Bool,
                   favorite: Bool, playing: Bool, switching: Bool = false, busy: Bool = false, fraction: Double? = nil, refreshToken: UUID? = nil,
                   onPrimary: (() -> Void)?, onFavorite: (() -> Void)?, onPreview: (() -> Void)? = nil) {
        loadViewIfNeeded()
        let changed = self.content?.providerReference != content.providerReference
            || self.content?.metadata.resourceRevision != content.metadata.resourceRevision
            || self.content?.locator.path != content.locator.path || self.request?.cacheURL != request?.cacheURL
        let mustClear = self.content?.providerReference != content.providerReference
            || self.request?.cacheURL != request?.cacheURL && self.request?.scopeID != request?.scopeID
        let explicitRefresh = self.refreshToken != refreshToken
        self.refreshToken = refreshToken
        self.content = content; self.request = request
        self.selecting = selecting; self.playing = playing; self.switching = switching
        self.cardSelected = selected; self.favorite = favorite
        self.onPrimary = onPrimary; self.onFavorite = onFavorite
        self.onPreview = onPreview
        view.setAccessibilityElement(true); view.setAccessibilityRole(.group)
        view.setAccessibilityLabel(content.title)
        updateControls()
        applyTransfer(busy: busy, fraction: fraction)
        badge.stringValue = selected ? "✓" : ""
        updateAppearance()
        if changed {
            retireRequest(); if mustClear { thumbnail.image = nil }; pixelLimit = 0; hasFailed = false
            placeholder.stringValue = ""; loadThumbnail()
        } else if explicitRefresh, hasFailed {
            hasFailed = false; pixelLimit = 0; loadThumbnail()
        }
        updateVisibility(); view.needsLayout = true
    }

    func applyTransfer(busy: Bool, fraction: Double?) {
        guard self.busy != busy || self.fraction != fraction else { return }
        self.busy = busy; self.fraction = fraction
        bar?.playButton.isEnabled = onPrimary != nil && !busy && !switching
        bar?.glass.applyProgress(style: busy ? .downloading : .neutral, fraction: busy ? fraction : nil,
            indeterminate: busy && fraction == nil, animated: false)
        updateVisibility()
    }

    func setThumbnailVisible(_ value: Bool) {
        guard visible != value else { return }
        visible = value
        if value { loadThumbnail() }
        else { retireRequest(); hovering = false; updateAppearance() }
        updateVisibility()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        if lastLayoutSize != view.bounds.size {
            lastLayoutSize = view.bounds.size
            surface.frame = view.bounds.insetBy(dx: 2, dy: 2)
            outline.frame = surface.bounds
            layoutControls()
            placeholder.frame = .init(x: 8, y: surface.bounds.midY - 10, width: max(0, surface.bounds.width - 16), height: 20)
            badge.frame = .init(x: surface.bounds.midX - 12, y: surface.bounds.midY - 12, width: 24, height: 24)
            layoutImage()
        }
        refreshGridHover(isScrolling: view.isGridHoverSuppressed)
        if visible, task == nil, cancellation == nil, !hasFailed { loadThumbnail() }
    }

    private func layoutImage() {
        guard let size = thumbnail.image?.size, size.width > 0, size.height > 0 else { thumbnail.frame = surface.bounds; return }
        let scale = max(surface.bounds.width / size.width, surface.bounds.height / size.height)
        let fitted = NSSize(width: size.width * scale, height: size.height * scale)
        thumbnail.frame = .init(x: (surface.bounds.width - fitted.width) / 2,
            y: (surface.bounds.height - fitted.height) / 2, width: fitted.width, height: fitted.height)
    }

    private func loadThumbnail() {
        guard visible, task == nil, cancellation == nil, !hasFailed, let content else { return }
        let id = UUID(); requestID = id
        if content.publishedAvailability.isAvailable, let path = content.locator.path {
            guard thumbnail.image == nil || pixelLimit == 0 else { return }
            pixelLimit = 800
            let cancellation = ThumbnailCacheRequestCancellation(); self.cancellation = cancellation
            localThumbnails.load(path: path, cancellation: cancellation) { [weak self] result in
                guard let self, requestID == id, !cancellation.cancelled else { return }
                self.cancellation = nil
                if case .image(let image) = result { receive(image) } else { receive(nil) }
            }
        } else if let request {
            let wanted = GridThumbnailDecoder.pixelLimit(width: view.bounds.width, scale: view.window?.backingScaleFactor ?? 2)
            guard thumbnail.image == nil || wanted > pixelLimit else { return }
            pixelLimit = wanted
            if let image = OLThumbnailCache.shared.readyImage(for: request, maxPixelSize: pixelLimit) { receive(image); return }
            let pixels = pixelLimit
            task = Task { [weak self] in
                let image = await OLThumbnailCache.shared.image(for: request, maxPixelSize: pixels, priority: .visible)
                guard let self, !Task.isCancelled, requestID == id else { return }
                task = nil; receive(image)
            }
        } else { receive(nil) }
    }

    private func receive(_ image: NSImage?) {
        if let image { thumbnail.image = image }
        hasFailed = image == nil
        placeholder.stringValue = thumbnail.image == nil ? "缩略图暂不可用" : ""
        layoutImage()
    }

    private func retireRequest() {
        requestID = UUID(); task?.cancel(); task = nil; cancellation?.cancel(); cancellation = nil
    }

    func refreshGridHover(isScrolling: Bool) {
        hover.update(in: surface, owner: self, isScrolling: isScrolling)
        let value = !isScrolling && view.isGridPointerInside
        guard hovering != value else { return }
        hovering = value; updateAppearance(); updateVisibility()
    }
    override func mouseEntered(with event: NSEvent) {
        guard !view.isGridHoverSuppressed else { return }
        hovering = true; updateAppearance(animated: true); updateVisibility(animated: true)
    }
    override func mouseExited(with event: NSEvent) {
        guard !view.isGridHoverSuppressed else { return }
        hovering = false; updateAppearance(animated: true); updateVisibility(animated: true)
    }
    override func mouseMoved(with event: NSEvent) { refreshGridHover(isScrolling: view.isGridHoverSuppressed) }

    private func updateVisibility(animated: Bool = false) {
        let show = visible && !selecting && (hovering || playing || switching || busy)
        if show { prepareControls() }
        badge.isHidden = !selecting
        guard let bar else { return }
        barVisibilityRevision &+= 1
        let revision = barVisibilityRevision
        if show, bar.superview == nil { surface.addSubview(bar) }
        bar.setActive(show && hovering)
        bar.glass.setProgressAnimationVisible(show)
        let finish = { [weak self, weak bar] in
            guard let self, barVisibilityRevision == revision, !show else { return }
            bar?.removeFromSuperview()
        }
        let alpha: CGFloat = show ? (hovering ? 0.92 : 0.84) : 0
        if animated, bar.superview != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = show ? UIInteractionAnimation.cardHoverExpandDuration : UIInteractionAnimation.cardHoverCollapseDuration
                context.timingFunction = show ? UIInteractionAnimation.cardEnterTiming : UIInteractionAnimation.cardExitTiming
                bar.animator().alphaValue = alpha
            } completionHandler: { DispatchQueue.main.async(execute: finish) }
        } else { bar.alphaValue = alpha; finish() }
    }

    private func prepareControls() {
        guard bar == nil else { return }
        let bar = WallpaperCardControlsView()
        self.bar = bar
        bar.onPlay = { [weak self] in
            guard let self, visible, !selecting, !busy, !switching,
                  WallpaperLibrarySheetPresentation.permitsInput(in: view.window) else { return }
            onPrimary?()
        }
        bar.onFavorite = { [weak self] in
            guard let self, visible, !selecting,
                  WallpaperLibrarySheetPresentation.permitsInput(in: view.window) else { return }
            onFavorite?()
        }
        layoutControls(); updateControls()
    }

    private func layoutControls() {
        guard let bar else { return }
        let metrics = WallpaperCardBarMetrics(cardWidth: surface.bounds.width)
        bar.frame = .init(x: metrics.barHorizontalInset, y: metrics.barBottomInset,
            width: max(0, surface.bounds.width - 2 * metrics.barHorizontalInset), height: metrics.barHeight)
        bar.apply(metrics: metrics)
    }

    private func updateControls() {
        guard let bar, let content else { return }
        bar.apply(title: content.title, metadata: [content.metadata.author, content.metadata.resolutionText].compactMap { $0 }.joined(separator: "  "))
        bar.isFavorite = favorite
        bar.primaryState = switching ? .switching : content.publishedAvailability.isAvailable ? (playing ? .applied : .apply) : .download
        bar.playButton.isEnabled = onPrimary != nil && !busy && !switching
        bar.favoriteButton.isHidden = onFavorite == nil
        bar.onPreview = onPreview == nil ? nil : { [weak self] in
            guard let self, visible, !selecting,
                  WallpaperLibrarySheetPresentation.permitsInput(in: view.window) else { return }
            onPreview?()
        }
        bar.glass.applyProgress(style: busy ? .downloading : .neutral, fraction: busy ? fraction : nil,
            indeterminate: busy && fraction == nil, animated: false)
    }

    private func updateAppearance(animated: Bool = false) {
        let dark = surface.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let chrome = Chrome(dark: dark, hovered: hovering, selected: cardSelected, selecting: selecting)
        guard chrome != lastChrome else { return }
        lastChrome = chrome
        surface.effectiveAppearance.performAsCurrentDrawingAppearance {
            surface.layer?.backgroundColor = NSColor.clear.cgColor
            surface.layer?.borderColor = NSColor.white.withAlphaComponent(hovering ? 0.12 : 0.028).cgColor
            outline.layer?.borderColor = (cardSelected ? NSColor.controlAccentColor.withAlphaComponent(dark ? 0.92 : 0.84)
                : NSColor.white.withAlphaComponent(dark ? 0.56 : 0.72)).cgColor
            badge.layer?.backgroundColor = (cardSelected ? NSColor.controlAccentColor : NSColor.black.withAlphaComponent(0.42)).cgColor
            badge.layer?.borderColor = NSColor.white.withAlphaComponent(0.28).cgColor
        }
        outline.layer?.borderWidth = cardSelected ? 1.6 : 1
        badge.layer?.borderWidth = cardSelected ? 0 : 1
        let alpha: CGFloat = hovering || cardSelected ? 1 : 0
        if animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = hovering ? UIInteractionAnimation.cardHoverExpandDuration : UIInteractionAnimation.cardHoverCollapseDuration
                context.timingFunction = hovering ? UIInteractionAnimation.cardEnterTiming : UIInteractionAnimation.cardExitTiming
                outline.animator().alphaValue = alpha
            }
        } else { outline.alphaValue = alpha }
    }
}
