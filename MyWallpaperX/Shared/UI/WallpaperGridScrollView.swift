import AppKit

/// Cards keep their existing click, selection and playback owners. Only hover
/// presentation yields while the user moves the grid beneath the pointer.
protocol WallpaperGridHoverItem: NSCollectionViewItem {
    func refreshGridHover(isScrolling: Bool)
}

/// The existing grid scroll phase owns suppression. Removing the tracking area
/// also removes AppKit's hover bookkeeping, rather than only ignoring callbacks.
/// Collection selection, button hits, menus and keyboard input stay untouched.
final class WallpaperGridHoverTracking {
    private weak var trackedView: NSView?
    private var area: NSTrackingArea?

    func update(in view: NSView, owner: NSResponder, isScrolling: Bool? = nil) {
        if isScrolling ?? view.isGridHoverSuppressed {
            detach()
            return
        }
        guard trackedView !== view || area == nil else { return }
        detach()
        let next = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect],
            owner: owner, userInfo: nil)
        trackedView = view
        area = next
        view.addTrackingArea(next)
    }

    private func detach() {
        if let area { trackedView?.removeTrackingArea(area) }
        area = nil
        trackedView = nil
    }
}

final class WallpaperGridScrollView: NSScrollView {
    // The wheel override only observes phases and forwards the original event.
    // Keep AppKit's responsive scrolling, which overrides otherwise opt out of.
    override class var isCompatibleWithResponsiveScrolling: Bool { true }

    private(set) var isGridScrolling = false
    private var contextMenuPointer: NSPoint?
    var isTrackingContextMenu: Bool { contextMenuPointer != nil }
    var contextMenuPointerLocation: NSPoint? { contextMenuPointer }
    /// Sources own the request; this scroll view only owns the native control.
    var onRefresh: (() -> Void)? { didSet { updateRefreshController() } }
    /// Existing page/source facts only; this view neither counts nor queries.
    var pullCountText: String? {
        didSet {
            guard pullCountText != oldValue else { return }
            pullCountLabel.stringValue = pullCountText ?? ""
            setAccessibilityHelp(pullCountText)
            updatePullCount()
        }
    }
    var permitsPullCountInput: (() -> Bool)?
    private let pullCountLabel = WallpaperGridPullCountLabel(labelWithString: "")
    /// AppKit's overlapping toolbar owns these insets. A flipped document's
    /// true top can have a negative native clip origin.
    var gridDocumentTopY: CGFloat { -contentInsets.top }
    var isGridAtTop: Bool { contentView.bounds.minY <= gridDocumentTopY + 0.5 }
    var gridViewportRect: NSRect {
        guard let documentView else { return .zero }
        let rect = contentView.convert(contentView.bounds, to: documentView)
        let insets = contentInsets
        return NSRect(x: rect.minX + insets.left, y: rect.minY + insets.top,
            width: max(0, rect.width - insets.left - insets.right),
            height: max(0, rect.height - insets.top - insets.bottom))
    }
    /// Consumers persist the settled native viewport using this existing
    /// scroll-phase owner, rather than serializing preferences on every pixel.
    var onScrollSettled: (() -> Void)?
    private var wheelEndWork: DispatchWorkItem?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        observeLiveScroll()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        observeLiveScroll()
    }

    deinit { wheelEndWork?.cancel() }

    func beginContextMenu(at point: NSPoint) {
        guard !isTrackingContextMenu, window != nil else { return }
        contextMenuPointer = point
        wheelEndWork?.cancel()
        wheelEndWork = nil
        // A native context gesture replaces the preceding scroll gesture. Its
        // modal loop may consume the wheel end; settle the existing owner now.
        if isGridScrolling { setScrolling(false) }
        else {
            for case let item as WallpaperGridHoverItem in (documentView as? NSCollectionView)?.visibleItems() ?? [] {
                item.refreshGridHover(isScrolling: false)
            }
        }
    }

    func endContextMenu() {
        let wasTracking = isTrackingContextMenu
        contextMenuPointer = nil
        guard wasTracking, !isGridScrolling, window != nil else { return }
        for case let item as WallpaperGridHoverItem in (documentView as? NSCollectionView)?.visibleItems() ?? [] {
            item.refreshGridHover(isScrolling: false)
        }
    }

    private func updateRefreshController() {
        // The symbol is absent from the Xcode 26 SDK even on a newer runtime.
        #if compiler(>=6.4)
        if #available(macOS 27.0, *) {
            guard onRefresh != nil else {
                refreshController?.endRefreshing()
                refreshController = nil
                return
            }
            guard refreshController == nil else { return }
            let controller = NSRefreshController()
            controller.target = self
            controller.action = #selector(handleRefresh)
            refreshController = controller
        }
        #endif
    }

    /// A source's real terminal fact ends a native pull. Ordinary loading does
    /// not start a second refresh presentation or store another loading flag.
    func applyRefreshLoading(_ isLoading: Bool) {
        guard !isLoading else { return }
        #if compiler(>=6.4)
        if #available(macOS 27.0, *) { refreshController?.endRefreshing() }
        #endif
    }

    @objc private func handleRefresh() {
        guard permitsPullCountInput?() != false, let onRefresh else {
            applyRefreshLoading(false)
            return
        }
        onRefresh()
    }

    private func observeLiveScroll() {
        verticalScrollElasticity = .allowed
        pullCountLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        pullCountLabel.textColor = .secondaryLabelColor
        pullCountLabel.alignment = .center
        pullCountLabel.lineBreakMode = .byTruncatingTail
        pullCountLabel.isHidden = true
        pullCountLabel.setAccessibilityElement(false)
        addSubview(pullCountLabel)
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(updatePullCount),
            name: NSView.boundsDidChangeNotification, object: contentView)
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                     NSWindow.willBeginSheetNotification, NSWindow.didEndSheetNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(updatePullCount), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(liveScrollStarted),
            name: NSScrollView.willStartLiveScrollNotification, object: self)
        NotificationCenter.default.addObserver(self, selector: #selector(liveScrollEnded),
            name: NSScrollView.didEndLiveScrollNotification, object: self)
    }

    @objc private func liveScrollStarted() {
        wheelEndWork?.cancel()
        wheelEndWork = nil
        setScrolling(true)
    }

    @objc private func liveScrollEnded() {
        scheduleScrollEnd()
    }

    override func scrollWheel(with event: NSEvent) {
        guard permitsPullCountInput?() != false else { pullCountLabel.isHidden = true; return }
        // Also cancel the finger-end settlement when momentum starts. There
        // must be no transient hover/GIF restart between those two phases.
        wheelEndWork?.cancel()
        wheelEndWork = nil
        setScrolling(true)
        super.scrollWheel(with: event)
        if (event.phase.isEmpty && event.momentumPhase.isEmpty)
            || !event.phase.intersection([.ended, .cancelled]).isEmpty
            || !event.momentumPhase.intersection([.ended, .cancelled]).isEmpty {
            scheduleScrollEnd()
        }
    }

    private func scheduleScrollEnd() {
        wheelEndWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.wheelEndWork = nil
            self?.setScrolling(false)
        }
        wheelEndWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            endContextMenu()
            wheelEndWork?.cancel()
            wheelEndWork = nil
            setScrolling(false)
        }
        updatePullCount()
    }

    override func layout() {
        super.layout()
        updatePullCount()
    }

    @objc private func updatePullCount() {
        let gap = gridDocumentTopY - contentView.bounds.minY
        guard isGridScrolling, gap >= 24, let text = pullCountText, !text.isEmpty,
              permitsPullCountInput?() != false, window?.isVisible == true, !isHiddenOrHasHiddenAncestor else {
            pullCountLabel.isHidden = true
            return
        }
        let clip = convert(contentView.bounds, from: contentView)
        let height = pullCountLabel.intrinsicContentSize.height
        let top = isFlipped ? clip.minY + contentInsets.top : clip.maxY - contentInsets.top
        let middle = top + (isFlipped ? gap * 0.5 : -gap * 0.5)
        pullCountLabel.frame = NSRect(x: clip.minX + contentInsets.left + 8, y: middle - height * 0.5,
            width: max(0, clip.width - contentInsets.left - contentInsets.right - 16), height: height)
        pullCountLabel.isHidden = false
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        // A window can move to a Retina screen without changing card sizes.
        // Image consumers must get a chance to request the required pixel tier.
        (documentView as? NSCollectionView)?.visibleItems().forEach { $0.view.needsLayout = true }
    }

    private func setScrolling(_ scrolling: Bool) {
        guard isGridScrolling != scrolling else { return }
        isGridScrolling = scrolling
        updatePullCount()
        if let collection = documentView as? NSCollectionView {
            for case let item as WallpaperGridHoverItem in collection.visibleItems() {
                item.refreshGridHover(isScrolling: scrolling)
            }
        }
        if !scrolling { onScrollSettled?() }
    }
}

private final class WallpaperGridPullCountLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

extension NSView {
    /// A visual-only transform around the cover centre; collection layout and
    /// pointer sampling remain with their existing owners.
    func applyGridHoverScale(_ hovered: Bool, animated: Bool) {
        guard let layer else { return }
        let menuPoint = (enclosingScrollView as? WallpaperGridScrollView)?.contextMenuPointerLocation
        let keepMenuScale = menuPoint.map { bounds.intersection(gridVisibleRect).contains(convert($0, from: nil)) } == true
        let hovered = hovered || keepMenuScale
        let moving = isGridHoverSuppressed
        let reduced = hovered && NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let scale: CGFloat = hovered && !moving && !reduced ? 1.025 : 1
        let target = CATransform3DMakeAffineTransform(CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
            tx: (1 - scale) * bounds.width * (0.5 - layer.anchorPoint.x),
            ty: (1 - scale) * bounds.height * (0.5 - layer.anchorPoint.y)))
        let key = "wallpaper.card.hover.scale"
        let animate = animated && !moving && !reduced
        guard !CATransform3DEqualToTransform(layer.transform, target) else {
            if !animate, scale == 1 { layer.removeAnimation(forKey: key) }
            return
        }
        let previous = layer.presentation()?.transform ?? layer.transform
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.transform = target
        CATransaction.commit()
        if animate {
            let transition = CABasicAnimation(keyPath: "transform")
            transition.fromValue = NSValue(caTransform3D: previous)
            transition.toValue = NSValue(caTransform3D: target)
            transition.duration = hovered ? 0.18 : 0.16
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(transition, forKey: key)
        } else { layer.removeAnimation(forKey: key) }
    }

    var gridVisibleRect: NSRect {
        guard let scroll = enclosingScrollView as? WallpaperGridScrollView,
              let document = scroll.documentView else { return visibleRect }
        return visibleRect.intersection(convert(scroll.gridViewportRect, from: document))
    }

    var isGridHoverSuppressed: Bool {
        (enclosingScrollView as? WallpaperGridScrollView)?.isGridScrolling == true
    }

    var isGridPointerInside: Bool {
        guard !isGridHoverSuppressed, !isHiddenOrHasHiddenAncestor, NSApp.isActive,
              let window, window.isVisible, !window.isMiniaturized else { return false }
        let point = window.mouseLocationOutsideOfEventStream
        return bounds.intersection(gridVisibleRect).contains(convert(point, from: nil))
    }
}
