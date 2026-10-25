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
        for (index, symbol, label) in [(0, "minus.magnifyingglass", "缩小卡片"), (1, "plus.magnifyingglass", "放大卡片")] {
            setImage(NSImage(systemSymbolName: symbol, accessibilityDescription: label), forSegment: index)
            setToolTip(label, forSegment: index)
            setWidth(28, forSegment: index)
            setEnabled(false, forSegment: index)
        }
        toolTip = "调整卡片大小"
        setAccessibilityLabel("调整卡片大小")
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    func update(preferredColumns: Int, clipWidth: CGFloat, canDispatch: Bool) {
        let ready = canDispatch && clipWidth.isFinite && clipWidth > 0
        let availability = WallpaperLibraryGridMetrics.zoomAvailability(preferredColumns: preferredColumns, clipWidth: clipWidth)
        isEnabled = ready
        setEnabled(ready && availability.canZoomOut, forSegment: 0)
        setEnabled(ready && availability.canZoomIn, forSegment: 1)
        let columns = WallpaperLibraryGridMetrics(clipWidth: clipWidth, preferredColumns: preferredColumns).columns
        let description = !ready ? "内容区域尚未就绪" : (columns == preferredColumns ? "当前每行 \(columns) 张卡片"
            : "当前窗口每行可显示 \(columns) 张卡片，保留每行 \(preferredColumns) 张的偏好")
        toolTip = "调整卡片大小：\(description)"
        setAccessibilityHelp(description)
    }

    func menuRepresentation() -> NSMenuItem {
        let entry = NSMenuItem(title: "缩放", action: nil, keyEquivalent: "")
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (segment, delta, title, symbol) in [(0, -1, "缩小卡片", "minus.magnifyingglass"), (1, 1, "放大卡片", "plus.magnifyingglass")] {
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
