import AppKit

/// A native pair presents the current page's density. It owns neither a
/// preference nor a page identity; the App supplies each fixed command.
@MainActor final class WallpaperLibraryZoomControl: NSSegmentedControl {
    var makeAction: ((Int) -> (() -> Void)?)?

    init() {
        super.init(frame: .zero)
        segmentCount = 2
        trackingMode = .momentary
        segmentStyle = .capsule
        target = self
        action = #selector(activate(_:))
        for (index, symbol, label) in [(0, "minus.magnifyingglass", String(localized: "Make Cards Smaller")), (1, "plus.magnifyingglass", String(localized: "Enlarge Card"))] {
            setImage(NSImage(systemSymbolName: symbol, accessibilityDescription: label), forSegment: index)
            setToolTip(label, forSegment: index)
            setWidth(28, forSegment: index)
            setEnabled(false, forSegment: index)
        }
        toolTip = String(localized: "Adjust Card Size")
        setAccessibilityLabel(String(localized: "Adjust Card Size"))
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    func update(preferredColumns: Int, clipWidth: CGFloat, canDispatch: Bool) {
        let ready = canDispatch && clipWidth.isFinite && clipWidth > 0
        let availability = WallpaperLibraryGridMetrics.zoomAvailability(preferredColumns: preferredColumns, clipWidth: clipWidth)
        isEnabled = ready
        setEnabled(ready && availability.canZoomOut, forSegment: 0)
        setEnabled(ready && availability.canZoomIn, forSegment: 1)
        let columns = WallpaperLibraryGridMetrics(clipWidth: clipWidth, preferredColumns: preferredColumns).columns
        let description = !ready ? String(localized: "The content area isn’t ready yet.") : (columns == preferredColumns ? String(localized: "\(columns) cards per row")
            : String(localized: "This window can show \(columns) cards per row; your preference of \(preferredColumns) per row is kept."))
        toolTip = String(localized: "Adjust Card Size: \(description)")
        setAccessibilityHelp(description)
    }

    func menuRepresentation() -> NSMenuItem {
        let entry = NSMenuItem(title: String(localized: "Zoom"), action: nil, keyEquivalent: "")
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (segment, delta, title, symbol) in [(0, -1, String(localized: "Make Cards Smaller"), "minus.magnifyingglass"), (1, 1, String(localized: "Enlarge Card"), "plus.magnifyingglass")] {
            let command = isEnabled && isEnabled(forSegment: segment) ? makeAction?(delta) : nil
            let item = ActionMenuItem(title: title, symbol: symbol) { command?() }
            item.isEnabled = command != nil
            menu.addItem(item)
        }
        entry.toolTip = toolTip
        entry.submenu = menu
        return entry
    }

    @objc private func activate(_ sender: NSSegmentedControl) {
        let segment = sender.selectedSegment
        guard (0...1).contains(segment), isEnabled, isEnabled(forSegment: segment) else { return }
        makeAction?(segment == 0 ? -1 : 1)?()
    }
}
