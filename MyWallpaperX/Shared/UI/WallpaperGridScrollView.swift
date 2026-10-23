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

    func update(in view: NSView, owner: AnyObject, isScrolling: Bool? = nil) {
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

    private func observeLiveScroll() {
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
            wheelEndWork?.cancel()
            wheelEndWork = nil
            setScrolling(false)
        }
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
        guard let collection = documentView as? NSCollectionView else { return }
        for case let item as WallpaperGridHoverItem in collection.visibleItems() {
            item.refreshGridHover(isScrolling: scrolling)
        }
    }
}

extension NSView {
    var isGridHoverSuppressed: Bool {
        (enclosingScrollView as? WallpaperGridScrollView)?.isGridScrolling == true
    }

    var isGridPointerInside: Bool {
        guard !isGridHoverSuppressed, !isHiddenOrHasHiddenAncestor, NSApp.isActive,
              let window, window.isVisible, !window.isMiniaturized else { return false }
        return bounds.intersection(visibleRect).contains(
            convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }
}
