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
    isHovering: () -> Bool, label: String
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
    func stationary() -> Bool {
        guard let layer = cardRoot.layer, CATransform3DIsIdentity(layer.transform) else { return false }
        if let presentation = layer.presentation(), !CATransform3DIsIdentity(presentation.transform) { return false }
        return !(layer.animationKeys() ?? []).contains {
            layer.animation(forKey: $0).map(hasTransformAnimation) == true
        }
    }
    func observe(_ interval: TimeInterval) -> Bool {
        var unchanged = stationary()
        let deadline = Date().addingTimeInterval(interval)
        while Date() < deadline {
            RunLoop.main.run(until: min(deadline, Date().addingTimeInterval(0.005)))
            unchanged = stationary() && unchanged
        }
        return unchanged
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
    checks[label + ".active-hover-keeps-identity-without-transform-animation"] = observe(0.38)
    diagnose("after-hover-observation")
    checks[label + ".active-hover-shows-white-outline"] = isHovering() && whiteOutline()
    item.mouseDown(with: mouse(.leftMouseDown))
    diagnose("after-down")
    checks[label + ".card-responder-down-keeps-identity"] = observe(0.10)
    item.mouseUp(with: mouse(.leftMouseUp))
    diagnose("after-up")
    checks[label + ".card-responder-up-keeps-identity"] = observe(0.14) && isHovering() && whiteOutline()
    window.testPointer = outside
    item.mouseExited(with: tracking(.mouseExited, outside))
    diagnose("after-exited")
    checks[label + ".exit-keeps-identity-without-transform-animation"] = observe(0.38)
    checks[label + ".exit-hides-hover-outline"] = !isHovering() && outline.alphaValue < 0.01
    enter()
    checks[label + ".restored-hover-keeps-identity-without-transform-animation"] = observe(0.38)
    diagnose("after-restored-observation")
    checks[label + ".restored-hover-shows-white-outline"] = isHovering() && whiteOutline()
    return checks
}
