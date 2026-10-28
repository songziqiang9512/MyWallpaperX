import AppKit
import QuartzCore

@MainActor private final class GridCardInteractionWindow: NSWindow {
    var testPointer = NSPoint(x: -10_000, y: -10_000)
    override var mouseLocationOutsideOfEventStream: NSPoint { testPointer }
}

/// Drives complete production cards through their responder methods in an
/// isolated window. It observes the whole-card layer, not thumbnail or badge
/// layers. Press/up are card-responder inputs; collection selection, drag and
/// button dispatch remain covered by their existing owner gates.
@MainActor func gridCardInteractionChecks(
    item: NSCollectionViewItem, cardRoot: NSView, outline: NSView,
    isHovering: () -> Bool, label: String,
    dragImageView: NSImageView? = nil, layoutDragImage: (() -> Void)? = nil
) -> [String: Bool] {
    let previousSuperview = item.view.superview
    let previousFrame = item.view.frame
    let previousAppearance = item.view.appearance
    let window = GridCardInteractionWindow(contentRect: NSRect(x: 14_000, y: 14_000, width: 300, height: 220),
        styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let host = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 220))
    window.contentView = host
    item.view.frame = NSRect(x: 20, y: 20, width: 260, height: 180)
    item.view.appearance = NSAppearance(named: .darkAqua)
    host.addSubview(item.view)
    window.orderFrontRegardless()
    NSApp.setActivationPolicy(.regular)
    NSApp.activate()
    let activationDeadline = Date().addingTimeInterval(2)
    while !NSApp.isActive, Date() < activationDeadline {
        RunLoop.main.run(until: min(activationDeadline, Date().addingTimeInterval(0.005)))
    }
    host.layoutSubtreeIfNeeded()
    item.view.layoutSubtreeIfNeeded()
    item.viewDidLayout()
    defer {
        item.view.removeFromSuperview()
        item.view.appearance = previousAppearance
        item.view.frame = previousFrame
        previousSuperview?.addSubview(item.view)
        window.orderOut(nil)
        window.close()
    }
    func hasTransformAnimation(_ animation: CAAnimation) -> Bool {
        if let property = animation as? CAPropertyAnimation,
           let key = property.keyPath, key == "transform" || key.hasPrefix("transform.") { return true }
        return (animation as? CAAnimationGroup)?.animations?.contains(where: hasTransformAnimation) == true
    }
    let nominalFrame = cardRoot.frame
    func matches(_ transform: CATransform3D, scale: CGFloat? = nil) -> Bool {
        let value = transform.m11
        let anchor = cardRoot.layer!.anchorPoint
        return value >= 0.9999 && value <= 1.0251 && abs(transform.m22 - value) < 0.0001
            && (scale.map { abs(value - $0) < 0.0001 } ?? true)
            && abs(transform.m41 - (1 - value) * cardRoot.bounds.width * (0.5 - anchor.x)) < 0.001
            && abs(transform.m42 - (1 - value) * cardRoot.bounds.height * (0.5 - anchor.y)) < 0.001
            && transform.m12 == 0 && transform.m21 == 0 && transform.m33 == 1
    }
    func observe(_ interval: TimeInterval, scale: CGFloat = 1, allowsTransition: Bool = false) -> Bool {
        func valid() -> Bool {
            guard let layer = cardRoot.layer, matches(layer.transform, scale: scale), cardRoot.frame == nominalFrame else { return false }
            if let presentation = layer.presentation(), !matches(presentation.transform, scale: allowsTransition ? nil : scale) { return false }
            return !(layer.animationKeys() ?? []).contains {
                layer.animation(forKey: $0).map(hasTransformAnimation) == true
                    && !(allowsTransition && $0 == "wallpaper.card.hover.scale")
            }
        }
        var correct = valid()
        let deadline = Date().addingTimeInterval(interval)
        while Date() < deadline {
            RunLoop.main.run(until: min(deadline, Date().addingTimeInterval(0.005)))
            correct = valid() && correct
        }
        return correct
    }
    func whiteOutline() -> Bool {
        guard let borderColor = outline.layer?.borderColor,
              let color = NSColor(cgColor: borderColor)?.usingColorSpace(.deviceRGB) else {
            fputs("\(label): hover outline has no RGB border color\n", stderr)
            return false
        }
        let visibleWhite = outline.alphaValue > 0.9 && (outline.layer?.borderWidth ?? 0) > 0
            && color.redComponent > 0.99 && color.greenComponent > 0.99
            && color.blueComponent > 0.99 && color.alphaComponent > 0
        if !visibleWhite {
            fputs("\(label): hover outline alpha=\(outline.alphaValue) width=\(outline.layer?.borderWidth ?? 0) rgba=\(color.redComponent),\(color.greenComponent),\(color.blueComponent),\(color.alphaComponent)\n", stderr)
        }
        return visibleWhite
    }
    let inside = cardRoot.convert(NSPoint(x: cardRoot.bounds.midX, y: cardRoot.bounds.midY), to: nil)
    let outside = cardRoot.convert(NSPoint(x: cardRoot.bounds.minX - 20, y: cardRoot.bounds.minY - 20), to: nil)
    func diagnose(_ phase: String) {
        fputs("grid-card[\(label)] \(phase) active=\(NSApp.isActive) running=\(NSApp.isRunning) windowVisible=\(window.isVisible) miniaturized=\(window.isMiniaturized) itemInside=\(item.view.isGridPointerInside) rootInside=\(cardRoot.isGridPointerInside) hover=\(isHovering()) bundle=\(Bundle.main.bundleIdentifier ?? "none")\n", stderr)
        fputs("grid-card[\(label)] \(phase) pointer=\(window.testPointer) itemPoint=\(item.view.convert(window.testPointer, from: nil)) itemBounds=\(item.view.bounds) itemVisible=\(item.view.visibleRect) itemHidden=\(item.view.isHiddenOrHasHiddenAncestor) rootPoint=\(cardRoot.convert(window.testPointer, from: nil)) rootBounds=\(cardRoot.bounds) rootVisible=\(cardRoot.visibleRect) rootHidden=\(cardRoot.isHiddenOrHasHiddenAncestor)\n", stderr)
    }
    func tracking(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
        NSEvent.enterExitEvent(with: type, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, trackingNumber: 0, userData: nil)!
    }
    func mouse(_ type: NSEvent.EventType) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: inside, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 2, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
    }
    func enter() {
        window.testPointer = inside
        item.mouseEntered(with: tracking(.mouseEntered, inside))
        diagnose("after-entered")
        item.mouseMoved(with: mouse(.mouseMoved))
        diagnose("after-moved")
    }
    var checks: [String: Bool] = [:]
    window.testPointer = inside
    checks[label + ".visible-dark-whole-card"] = item.view.window === window && window.isVisible
        && NSApp.isActive && item.view.isGridPointerInside && cardRoot.isGridPointerInside
        && item.view.isDarkAppearance && !cardRoot.bounds.isEmpty
        && cardRoot.bounds.contains(cardRoot.convert(inside, from: nil))
        && !cardRoot.bounds.contains(cardRoot.convert(outside, from: nil))
    if checks[label + ".visible-dark-whole-card"] != true { diagnose("invalid-environment") }
    window.testPointer = outside
    item.mouseExited(with: tracking(.mouseExited, outside))
    diagnose("after-initial-exited")
    _ = observe(0.38)
    enter()
    checks[label + ".active-hover-expands-equally-about-centre"] = observe(0.38, scale: 1.025, allowsTransition: true)
    diagnose("after-hover-observation")
    checks[label + ".active-hover-shows-white-outline"] = isHovering() && whiteOutline()
    item.mouseDown(with: mouse(.leftMouseDown))
    diagnose("after-down")
    checks[label + ".card-responder-down-keeps-hover-scale"] = observe(0.10, scale: 1.025)
    item.mouseUp(with: mouse(.leftMouseUp))
    diagnose("after-up")
    checks[label + ".card-responder-up-keeps-hover-scale"] = observe(0.14, scale: 1.025) && isHovering() && whiteOutline()
    window.testPointer = outside
    item.mouseExited(with: tracking(.mouseExited, outside))
    diagnose("after-exited")
    checks[label + ".exit-returns-to-identity-about-centre"] = observe(0.38, allowsTransition: true)
    checks[label + ".exit-hides-hover-outline"] = !isHovering() && outline.alphaValue < 0.01
    enter()
    checks[label + ".restored-hover-restores-the-same-centred-expansion"] = observe(0.38, scale: 1.025, allowsTransition: true)
    diagnose("after-restored-observation")
    checks[label + ".restored-hover-shows-white-outline"] = isHovering() && whiteOutline()
    if let dragImageView, let layoutDragImage {
        checks.merge(cardNativeDragImageChecks(item: item, thumbnail: dragImageView,
            layoutThumbnail: layoutDragImage, label: label)) { _, new in new }
    }
    return checks
}

@MainActor private final class CardNativeDragImageProbe: NSObject, NSCollectionViewDelegate {
    let owner: WallpaperLibraryGridController
    let card: NSCollectionViewItem
    let thumbnail: NSImageView
    let readyImage: NSImage
    weak var mountedParent: NSView?
    var starts = 0, ends = 0
    var components: [NSDraggingImageComponent] = []
    var firstTurnPreservesSource: Bool?
    var endedDiagnostic = "not-ended", firstTurnDiagnostic = "not-sampled"
    var firstTurnTimer: Timer?
    init(owner: WallpaperLibraryGridController, card: NSCollectionViewItem, thumbnail: NSImageView, image: NSImage) {
        self.owner = owner; self.card = card; self.thumbnail = thumbnail; readyImage = image
    }
    override func responds(to selector: Selector!) -> Bool { super.responds(to: selector) || owner.responds(to: selector) }
    override func forwardingTarget(for selector: Selector!) -> Any? { owner }
    func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession,
                        willBeginAt point: NSPoint, forItemsAt paths: Set<IndexPath>) {
        (owner as NSCollectionViewDelegate).collectionView?(collectionView, draggingSession: session,
            willBeginAt: point, forItemsAt: paths)
        starts += 1
        session.enumerateDraggingItems(options: [], for: collectionView, classes: [NSPasteboardItem.self], searchOptions: [:]) { item, _, _ in
            components += item.imageComponents ?? []
        }
    }
    func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession,
                        endedAt point: NSPoint, dragOperation operation: NSDragOperation) {
        (owner as NSCollectionViewDelegate).collectionView?(collectionView, draggingSession: session,
            endedAt: point, dragOperation: operation)
        ends += 1
        endedDiagnostic = sampleSource(in: collectionView).diagnostic
        // Observe the first later native turn, after the ended callback returns.
        // Do not force a layout, display, layer commit or thumbnail refresh.
        let timer = Timer(timeInterval: 0, repeats: false) { [weak self, weak collectionView] _ in
            MainActor.assumeIsolated {
                guard let self, let collectionView else { return }
                let sample = self.sampleSource(in: collectionView)
                self.firstTurnPreservesSource = sample.preserved
                self.firstTurnDiagnostic = sample.diagnostic
                self.firstTurnTimer = nil
            }
        }
        firstTurnTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    private func sampleSource(in collection: NSCollectionView) -> (preserved: Bool, diagnostic: String) {
        var node: NSView? = thumbnail
        var opaque = true, values: [String] = []
        while let current = node, current !== collection {
            let model = current.layer?.opacity, presentation = current.layer?.presentation()?.opacity
            opaque = opaque && !current.isHidden && current.alphaValue == 1
                && model.map({ $0 == 1 }) != false && presentation.map({ $0 == 1 }) != false
            values.append("\(type(of: current)):hidden=\(current.isHidden),alpha=\(current.alphaValue),layer=\(String(describing: model)),presentation=\(String(describing: presentation))")
            node = current.superview
        }
        let mounted = card.view.superview === mountedParent && mountedParent != nil && node === collection
        let sameImage = thumbnail.image === readyImage
        return (mounted && sameImage && opaque && card.view.layer != nil && !thumbnail.isHiddenOrHasHiddenAncestor,
                "mounted=\(mounted) sameImage=\(sameImage) " + values.joined(separator: ";"))
    }
}

/// The production Grid's real native collection asks the complete provider item
/// for its drag image and applies its actual cancellation policy.
/// Only the already-ready source pixels are controlled here; no decoder,
/// network, App selection or relationship command is replaced or invoked.
@MainActor private func cardNativeDragImageChecks(item: NSCollectionViewItem, thumbnail: NSImageView,
                                                layoutThumbnail: () -> Void, label: String) -> [String: Bool] {
    let previousParent = item.view.superview, previousFrame = item.view.frame
    let previousImage = thumbnail.image, previousSelection = item.isSelected
    let root = item.view as? WallpaperCardInteractionView
    let previousActivation = root?.onAccessibilityActivate
    let previousElement = item.view.isAccessibilityElement(), previousRole = item.view.accessibilityRole()
    let previousLabel = item.view.accessibilityLabel()
    let image = NSImage(size: NSSize(width: 400, height: 180))
    image.lockFocus()
    NSColor(deviceRed: 0.16, green: 0.73, blue: 0.46, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: 400, height: 180).fill()
    NSColor(deviceRed: 0.86, green: 0.14, blue: 0.20, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: 100, height: 180).fill()
    NSColor(deviceRed: 0.12, green: 0.26, blue: 0.86, alpha: 1).setFill()
    NSRect(x: 300, y: 0, width: 100, height: 180).fill()
    NSColor(deviceRed: 0.91, green: 0.78, blue: 0.12, alpha: 1).setFill()
    NSRect(x: 100, y: 140, width: 200, height: 40).fill()
    NSColor(deviceRed: 0.76, green: 0.18, blue: 0.81, alpha: 1).setFill()
    NSRect(x: 100, y: 0, width: 200, height: 40).fill()
    image.unlockFocus()
    thumbnail.image = image
    let owner = WallpaperLibraryGridController { _, _, _, _ in item }
    owner.loadViewIfNeeded()
    owner.onSelection = { _, _ in UUID() }
    let collection = owner.collection
    let probe = CardNativeDragImageProbe(owner: owner, card: item, thumbnail: thumbnail, image: image)
    collection.delegate = probe
    let window = NSWindow(contentRect: NSRect(x: 160, y: 160, width: 600, height: 350),
        styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentViewController = owner
    window.setContentSize(NSSize(width: 600, height: 350))
    window.makeKeyAndOrderFront(nil); NSApp.activate()
    defer {
        window.orderOut(nil)
        item.view.removeFromSuperview(); item.view.frame = previousFrame
        previousParent?.addSubview(item.view)
        item.isSelected = previousSelection; thumbnail.image = previousImage
        layoutThumbnail()
        collection.dataSource = nil; collection.delegate = nil
        probe.firstTurnTimer?.invalidate()
        window.close()
        root?.onAccessibilityActivate = previousActivation
        item.view.setAccessibilityElement(previousElement); item.view.setAccessibilityRole(previousRole)
        item.view.setAccessibilityLabel(previousLabel)
        withExtendedLifetime(probe) {}
    }
    let activation = Date().addingTimeInterval(3)
    while !NSApp.isActive || !window.isKeyWindow {
        precondition(Date() < activation, "native card drag host never became active/key")
        RunLoop.main.run(until: Date().addingTimeInterval(0.005))
    }
    window.contentView?.layoutSubtreeIfNeeded(); owner.scrollView.layoutSubtreeIfNeeded()
    let reference = WallpaperReference(provider: .videoLibrary, sourceID: "native-card-" + label)
    let value = WallpaperContentItem(reference: reference, providerReference: reference,
        locator: .init(mediaKind: .video), title: label, kind: .video,
        publishedAvailability: .available, capabilities: [.organize], metadata: .init(),
        acquisition: .idle, update: .idle, aliases: [])
    owner.update(page: .videos, items: [value], selection: .init(), preferredColumns: 3,
        permitsDragging: true, scrollAnchor: nil)
    window.contentView?.layoutSubtreeIfNeeded(); collection.layoutSubtreeIfNeeded()
    item.viewDidLayout(); layoutThumbnail()
    precondition(collection.item(at: IndexPath(item: 0, section: 0)) === item && item.view.window === window,
        "real provider card was not mounted by the native collection")
    let parent = item.view.superview, frame = item.view.frame
    probe.mountedParent = parent
    let start = item.view.convert(NSPoint(x: item.view.bounds.midX, y: item.view.bounds.midY), to: nil)
    let moved = NSPoint(x: start.x + 35, y: start.y + 15)
    let now = ProcessInfo.processInfo.systemUptime
    func mouse(_ type: NSEvent.EventType, _ point: NSPoint, _ time: TimeInterval) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: time,
            windowNumber: window.windowNumber, context: nil, eventNumber: 61, clickCount: 1,
            pressure: type == .leftMouseUp ? 0 : 1)!
    }
    NSApp.postEvent(mouse(.leftMouseUp, moved, now + 0.03), atStart: true)
    NSApp.postEvent(mouse(.leftMouseDragged, moved, now + 0.02), atStart: true)
    window.sendEvent(mouse(.leftMouseDown, start, now))
    let ending = Date().addingTimeInterval(2)
    while probe.firstTurnPreservesSource == nil, Date() < ending {
        while let event = NSApp.nextEvent(matching: .any, until: .distantPast, inMode: .default, dequeue: true) { NSApp.sendEvent(event) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.005))
    }
    let bounds = NSRect(origin: .zero, size: frame.size)
    let snapshot = NSImage(size: bounds.size)
    snapshot.lockFocus()
    for component in probe.components {
        (component.contents as? NSImage)?.draw(in: component.frame, from: .zero, operation: .sourceOver, fraction: 1)
    }
    snapshot.unlockFocus()
    func pixel(_ image: NSImage, x: Double, y: Double) -> NSColor? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.colorAt(x: min(rep.pixelsWide - 1, Int(Double(rep.pixelsWide) * x)),
            y: min(rep.pixelsHigh - 1, Int(Double(rep.pixelsHigh) * y)))?.usingColorSpace(.deviceRGB)
    }
    func matches(_ expected: NSColor?, _ color: NSColor?) -> Bool {
        guard let expected, let color else { return false }
        return zip([expected.redComponent, expected.greenComponent, expected.blueComponent, expected.alphaComponent],
                   [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent])
            .allSatisfy { pair in abs(pair.0 - pair.1) <= CGFloat(1) / 255 }
    }
    func rgba(_ color: NSColor?) -> String {
        guard let color else { return "nil" }
        return "\(color.redComponent),\(color.greenComponent),\(color.blueComponent),\(color.alphaComponent)"
    }
    let geometry = probe.components.map { "\($0.key.rawValue):\($0.frame):\(type(of: $0.contents as Any))" }.joined(separator: ",")
    FileHandle.standardError.write(Data("native-card-drag[\(label)] starts=\(probe.starts) ends=\(probe.ends) card=\(bounds) thumbnail=\(thumbnail.frame) nativeOutlet=\(item.imageView === thumbnail) components=\(geometry)\n".utf8))
    FileHandle.standardError.write(Data("native-card-drag[\(label)] ended=\(probe.endedDiagnostic)\nfirst-native-turn=\(probe.firstTurnDiagnostic)\n".utf8))
    let pixelValues = [0.15, 0.5, 0.85].map {
        "y=\($0) source=\(rgba(pixel(image, x: 0.5, y: $0))) drag=\(rgba(pixel(snapshot, x: 0.5, y: $0)))"
    }
    FileHandle.standardError.write(Data(("native-card-drag[\(label)] " + pixelValues.joined(separator: "; ") + "\n").utf8))
    return [
        label + ".native-drag-uses-the-current-ready-thumbnail-outlet": probe.starts == 1 && probe.ends == 1
            && item.imageView === thumbnail && probe.components.count == 1 && probe.components.first?.key == .icon,
        label + ".native-drag-cover-stays-inside-the-live-card": !probe.components.isEmpty
            && probe.components.allSatisfy { bounds.contains($0.frame) && !$0.frame.isEmpty },
        label + ".native-drag-preview-excludes-the-glass-bar": [0.15, 0.5, 0.85].allSatisfy {
            matches(pixel(image, x: 0.5, y: $0), pixel(snapshot, x: 0.5, y: $0))
        },
        label + ".native-drag-completion-preserves-source-pixels-and-mount": thumbnail.image === image
            && item.view.superview === parent && parent != nil && item.view.frame == frame
            && !item.view.isHidden && item.view.alphaValue == 1,
        label + ".first-native-turn-after-drag-keeps-live-source-opaque-and-ready": probe.firstTurnPreservesSource == true,
        // A square center crop of this 400x180 fixture keeps source x=110...290.
        // Neither outside 100px edge marker belongs in the resulting cover.
        label + ".native-drag-center-crops-wide-pixels-instead-of-stretching-edge-markers":
            frame.width == frame.height && frame.width > 0
            && matches(pixel(image, x: 0.5, y: 0.5), pixel(snapshot, x: 0.1, y: 0.5))
            && matches(pixel(image, x: 0.5, y: 0.5), pixel(snapshot, x: 0.9, y: 0.5)),
        label + ".nonuniform-source-has-distinct-opaque-edge-and-orientation-markers": {
            guard let left = pixel(image, x: 0.05, y: 0.5), let right = pixel(image, x: 0.95, y: 0.5),
                  let top = pixel(image, x: 0.5, y: 0.05), let bottom = pixel(image, x: 0.5, y: 0.95) else { return false }
            return left.redComponent > left.blueComponent && right.blueComponent > right.redComponent
                && top.greenComponent > top.blueComponent && bottom.blueComponent > bottom.greenComponent
                && [left, right, top, bottom].allSatisfy { $0.alphaComponent == 1 }
        }()
    ]
}
