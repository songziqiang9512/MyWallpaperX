import AppKit

/// A native drag contains the already displayed cover, clipped by its existing
/// container. Glass controls stay on the live card rather than entering the
/// bitmap drag image; no image request or visibility lease is changed here.
class WallpaperCardCollectionViewItem: NSCollectionViewItem {
    // This stateless base preserves NSCollectionViewItem's nonisolated
    // teardown so provider cancellation can finish synchronously in deinit.
    nonisolated deinit {}

    override var draggingImageComponents: [NSDraggingImageComponent] {
        guard let imageView, imageView.image != nil, let container = imageView.superview else {
            return super.draggingImageComponents
        }
        let clip = view.convert(container.bounds, from: container).intersection(view.bounds)
        let imageRect = imageView.convert(clip, from: view).intersection(imageView.bounds)
        guard !clip.isEmpty, !imageRect.isEmpty,
              let pixels = imageView.bitmapImageRepForCachingDisplay(in: imageRect) else {
            return super.draggingImageComponents
        }
        imageView.cacheDisplay(in: imageRect, to: pixels)
        let source = NSImage(size: clip.size)
        source.addRepresentation(pixels)
        let cover = NSImage(size: clip.size)
        cover.lockFocus()
        let radius = container.layer?.masksToBounds == true ? container.layer?.cornerRadius ?? 0 : 0
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: clip.size), xRadius: radius, yRadius: radius).addClip()
        source.draw(in: NSRect(origin: .zero, size: clip.size), from: .zero, operation: .sourceOver, fraction: 1)
        cover.unlockFocus()
        let component = NSDraggingImageComponent(key: .icon)
        component.contents = cover
        component.frame = NSRect(x: clip.minX - view.bounds.minX,
            y: view.isFlipped ? view.bounds.maxY - clip.maxY : clip.minY - view.bounds.minY,
            width: clip.width, height: clip.height)
        return [component]
    }
}

/// Passive artwork belongs to the collection item's native selection/drag
/// responder. Embedded buttons and editable content keep their own tracking.
class WallpaperCardInteractionView: NSView {
    /// A mounted local grid owns selection. Returning false must not fall
    /// through to a provider action after that view receipt has been revoked.
    var onAccessibilityActivate: (() -> Bool)?

    override func accessibilityPerformPress() -> Bool {
        if let onAccessibilityActivate { return onAccessibilityActivate() }
        return super.accessibilityPerformPress()
    }

    static func isInteractiveControl(_ view: NSView) -> Bool {
        if let image = view as? NSImageView { return image.isEditable }
        if let text = view as? NSTextField { return text.isEditable || text.isSelectable }
        return view is NSControl || view is NSTextView
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        var ancestor: NSView? = hit
        while let current = ancestor, current !== self {
            if Self.isInteractiveControl(current) { return hit }
            ancestor = current.superview
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        nextResponder?.mouseDown(with: event)
    }
}
