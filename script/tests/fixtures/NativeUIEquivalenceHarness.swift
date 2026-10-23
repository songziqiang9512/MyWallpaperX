import AppKit
import QuartzCore

@MainActor private final class ActionTarget: NSObject {
    var senders: [AnyObject] = []
    @objc func invoke(_ sender: AnyObject) { senders.append(sender) }
}

@MainActor private final class EquivalenceWindow: NSWindow {
    var pointer = NSPoint.zero
    override var mouseLocationOutsideOfEventStream: NSPoint { pointer }
}

@MainActor private final class SidebarFixtureData: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    let rows: [NSString] = ["我的视频", "我的图片", "创意工坊"]
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { item == nil ? rows.count : 0 }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { false }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { rows[index] }
    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat { 30 }
    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? { SidebarRowView() }
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let cell = SidebarRowCellView()
        cell.configure(title: item as! String, symbolName: "photo", count: 12)
        return cell
    }
}

@main struct NativeUIEquivalenceHarness {
    @MainActor static func main() throws {
        initializeNativeAppHarness()
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let window = EquivalenceWindow(contentRect: NSRect(x: 120, y: 120, width: 640, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let root = window.contentView!
        var checks: [String: Bool] = [:]
        var facts: [String: Any] = [:]
        func pump(_ interval: TimeInterval = 0.04) {
            RunLoop.current.run(until: Date().addingTimeInterval(interval))
        }
        func image(_ name: String, _ view: NSView) {
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                checks[name + "-capture"] = false
                return
            }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try! bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
        }
        func event(_ type: NSEvent.EventType, at point: NSPoint) -> NSEvent {
            if type == .mouseEntered || type == .mouseExited {
                return NSEvent.enterExitEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
            }
            return NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                               clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
        }
        let target = ActionTarget()
        for dark in [false, true] {
            root.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            for (name, kind) in [("primary", InspectorFooterButtonKind.primary), ("secondary", .secondary), ("danger", .danger)] {
                for iconOnly in [false, true] {
                    let id = "\(dark ? "dark" : "light")-\(name)-\(iconOnly ? "icon" : "title")"
                    let title = iconOnly ? "" : "设为壁纸"
                    let button = InspectorFooterButton(title: title,
                        image: NSImage(systemSymbolName: "play.fill", accessibilityDescription: "播放"),
                        kind: kind, target: target, action: #selector(ActionTarget.invoke(_:)))
                    root.addSubview(button)
                    let buttonWidth = button.widthAnchor.constraint(equalToConstant: iconOnly ? 38 : 180)
                    NSLayoutConstraint.activate([
                        button.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
                        button.topAnchor.constraint(equalTo: root.topAnchor, constant: -80),
                        buttonWidth,
                        button.heightAnchor.constraint(equalToConstant: 38)
                    ])
                    root.layoutSubtreeIfNeeded()
                    pump()
                    checks[id + "-geometry"] = button.frame.size == NSSize(width: iconOnly ? 38 : 180, height: 38)
                    checks[id + "-intrinsic-height"] = button.intrinsicContentSize.height == 38
                    checks[id + "-action-sender"] = button.accessibilityPerformPress() && target.senders.last === button
                    image(id + "-normal", button)
                    button.mouseEntered(with: event(.mouseEntered, at: .zero))
                    image(id + "-hover", button)
                    button.mouseExited(with: event(.mouseExited, at: .zero))
                    button.isEnabled = false
                    let count = target.senders.count
                    checks[id + "-disabled"] = !button.accessibilityPerformPress() && target.senders.count == count
                    image(id + "-disabled", button)
                    button.isEnabled = true
                    button.setProgressFill(0.5)
                    pump(0.25)
                    image(id + "-progress", button)
                    button.setProgressFill(nil)
                    facts[id + "-intrinsic-width"] = button.intrinsicContentSize.width
                    if name == "primary" && !iconOnly {
                        let inside = button.convert(NSPoint(x: 20, y: 15), to: nil)
                        let outside = button.convert(NSPoint(x: -25, y: 15), to: nil)
                        for (scenario, positions) in [("click", [inside]), ("cancel", [outside]), ("reenter", [outside, inside])] {
                            let before = target.senders.count
                            var timers: [Timer] = []
                            func schedule(_ delay: Double, _ operation: @escaping () -> Void) {
                                let timer = Timer(timeInterval: delay, repeats: false) { _ in operation() }
                                RunLoop.main.add(timer, forMode: .common)
                                timers.append(timer)
                            }
                            schedule(0.03) { image(id + "-" + scenario + "-pressed", button) }
                            for (index, point) in positions.enumerated() {
                                schedule(0.06 + Double(index) * 0.06) {
                                    window.pointer = point
                                    NSApp.postEvent(event(.leftMouseDragged, at: point), atStart: false)
                                }
                            }
                            schedule(0.06 + Double(positions.count) * 0.06) {
                                window.pointer = positions.last!
                                NSApp.postEvent(event(.leftMouseUp, at: positions.last!), atStart: false)
                            }
                            window.pointer = inside
                            button.mouseDown(with: event(.leftMouseDown, at: inside))
                            timers.forEach { $0.invalidate() }
                            checks[id + "-" + scenario] = target.senders.count - before == (scenario == "cancel" ? 0 : 1)
                            image(id + "-" + scenario + "-released", button)
                        }
                        for character in [" ", "\r"] {
                            let before = target.senders.count
                            let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                windowNumber: window.windowNumber, context: nil, characters: character,
                                charactersIgnoringModifiers: character, isARepeat: false, keyCode: character == " " ? 49 : 36)!
                            button.keyDown(with: key)
                            checks[id + "-key-" + String(key.keyCode)] = target.senders.count == before + 1
                        }
                    }
                    let trackingOptions: NSTrackingArea.Options = [.activeAlways, .mouseEnteredAndExited, .inVisibleRect]
                    var trackingValid = true
                    for width in [CGFloat(iconOnly ? 76 : 260), iconOnly ? 38 : 180] {
                        buttonWidth.constant = width
                        root.layoutSubtreeIfNeeded()
                        button.updateTrackingAreas()
                        let areas = button.trackingAreas.filter { $0.owner === button && $0.options.contains(.inVisibleRect) }
                        trackingValid = trackingValid && button.frame.width == width
                            && areas.count == 1 && areas.first?.options == trackingOptions
                    }
                    checks[id + "-tracking-resize"] = trackingValid
                    window.setContentSize(NSSize(width: 48, height: 400))
                    root.layoutSubtreeIfNeeded()
                    button.updateTrackingAreas()
                    let clippedAreas = button.trackingAreas.filter { $0.owner === button && $0.options.contains(.inVisibleRect) }
                    checks[id + "-tracking-clipped"] = button.visibleRect.width < button.bounds.width
                        && clippedAreas.count == 1 && clippedAreas.first?.options == trackingOptions
                    window.setContentSize(NSSize(width: 640, height: 400))
                    root.layoutSubtreeIfNeeded()
                    button.removeFromSuperview()
                }
            }
            let settings = SettingsGroupView(title: "测试设置")
            settings.frame = NSRect(x: 0, y: 0, width: 320, height: 150)
            root.addSubview(settings)
            let settingsWidth = settings.widthAnchor.constraint(equalToConstant: 320)
            settingsWidth.isActive = true
            let rows = (0..<3).map { _ in NSView() }
            for row in rows {
                row.heightAnchor.constraint(equalToConstant: 32).isActive = true
                settings.addRow(row)
            }
            settings.layoutSubtreeIfNeeded()
            pump()
            let stack = rows[0].superview as! NSStackView
            let separators = stack.arrangedSubviews.filter { view in !rows.contains(where: { $0 === view }) }
            checks["settings-separator-geometry-\(dark)"] = separators.count == 2 && separators.allSatisfy {
                $0.frame.height == 1 && $0.subviews.first!.frame.minX == 16
                    && $0.subviews.first!.frame.width == $0.bounds.width - 32
            }
            image("\(dark ? "dark" : "light")-settings", settings)
            let rowPoint = rows[0].convert(NSPoint(x: 10, y: 10), to: settings.superview)
            checks["settings-row-hit-\(dark)"] = settings.hitTest(rowPoint) === rows[0]
            for (step, appearance) in [NSAppearance.Name.darkAqua, .aqua, .darkAqua, .aqua].enumerated() {
                root.appearance = NSAppearance(named: appearance)
                settingsWidth.constant = step.isMultiple(of: 2) ? 420 : 320
                settings.layoutSubtreeIfNeeded()
                pump()
                let background = settings.subviews.first { $0.layer?.cornerRadius == 12 }!
                checks["settings-transition-\(dark)-\(step)"] = settings.bounds.width == settingsWidth.constant
                    && background.frame.width == settings.bounds.width
                    && background.layer?.masksToBounds == true && background.layer?.cornerCurve == .continuous
                let bitmap = settings.bitmapImageRepForCachingDisplay(in: settings.bounds)!
                settings.cacheDisplay(in: settings.bounds, to: bitmap)
                let pixel = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)!
                    .usingColorSpace(.deviceRGB)!
                let expectedAlpha: CGFloat = appearance == .darkAqua ? 0.02 : 1
                checks["settings-transition-fill-\(dark)-\(step)"] = abs(pixel.alphaComponent - expectedAlpha) < 0.005
                    && pixel.redComponent > 0.9 && abs(pixel.redComponent - pixel.greenComponent) < 0.01
                facts["settings-transition-\(dark)-\(step)-frames"] = ([settings, background] + rows).map {
                    [$0.frame.minX, $0.frame.minY, $0.frame.width, $0.frame.height]
                }
                image("settings-transition-\(dark)-\(step)", settings)
            }
            root.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            settingsWidth.constant = 320
            settings.layoutSubtreeIfNeeded()
            rows[1].isHidden = true
            settings.refreshSeparators()
            settings.layoutSubtreeIfNeeded()
            checks["settings-hidden-separators-\(dark)"] = separators.allSatisfy(\.isHidden)
            image("\(dark ? "dark" : "light")-settings-hidden", settings)
            settings.removeFromSuperview()
            let untitled = SettingsGroupView(title: nil)
            let maintenanceRow = NSView()
            maintenanceRow.heightAnchor.constraint(equalToConstant: 32).isActive = true
            untitled.addRow(maintenanceRow)
            root.addSubview(untitled)
            let maintenanceWidth = untitled.widthAnchor.constraint(equalToConstant: 320)
            maintenanceWidth.isActive = true
            for width in [CGFloat(320), 420] {
                maintenanceWidth.constant = width
                untitled.layoutSubtreeIfNeeded()
                pump()
                let background = untitled.subviews.first { $0.layer?.cornerRadius == 12 }!
                checks["settings-untitled-\(dark)-\(width)"] = untitled.bounds.size == NSSize(width: width, height: 32)
                    && background.frame == untitled.bounds && maintenanceRow.frame.size.width == width
                checks["settings-background-accessibility-\(dark)"] = !background.isAccessibilityElement()
                image("settings-untitled-\(dark)-\(width)", untitled)
            }
            untitled.removeFromSuperview()
        }
        for ratio in [CGFloat(0), 0.035] {
            let scroll = InspectorFadingScrollView(fadeRatio: ratio)
            scroll.frame = NSRect(x: 0, y: 0, width: 250, height: 150)
            let document = NSView(frame: NSRect(x: 0, y: 0, width: 250, height: 1200))
            document.wantsLayer = true
            document.layer?.backgroundColor = NSColor.systemBlue.cgColor
            scroll.documentView = document
            root.addSubview(scroll)
            scroll.layoutSubtreeIfNeeded()
            let expected: [NSNumber] = [0, NSNumber(value: Double(ratio)), NSNumber(value: Double(1 - ratio)), 1]
            for offset in [CGFloat(0), 100, 750] {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: offset))
                scroll.reflectScrolledClipView(scroll.contentView)
                checks["fade-\(ratio)-\(offset)"] = (scroll.layer?.mask as? CAGradientLayer)?.locations == expected
                image("fade-\(ratio)-\(offset)", scroll)
            }
            scroll.frame.size = NSSize(width: 300, height: 180)
            scroll.layoutSubtreeIfNeeded()
            checks["fade-resize-\(ratio)"] = scroll.layer?.mask?.frame == scroll.bounds
            image("fade-resize-\(ratio)", scroll)
            scroll.removeFromSuperview()
        }
        let reference = NSButton(title: "Reference", target: target, action: #selector(ActionTarget.invoke(_:)))
        reference.frame = NSRect(x: 24, y: 200, width: 180, height: 38)
        root.addSubview(reference)
        window.pointer = reference.convert(NSPoint(x: 20, y: 15), to: nil)
        let beforeReference = target.senders.count
        let up = Timer(timeInterval: 0.08, repeats: false) { _ in
            NSApp.postEvent(event(.leftMouseUp, at: window.pointer), atStart: false)
        }
        RunLoop.main.add(up, forMode: .common)
        reference.mouseDown(with: event(.leftMouseDown, at: window.pointer))
        up.invalidate()
        checks["native-reference-click"] = target.senders.count == beforeReference + 1
        reference.removeFromSuperview()
        for dark in [false, true] {
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let anchor = NSButton(title: "菜单", target: nil, action: nil)
            anchor.frame = NSRect(x: 220, y: 200, width: 80, height: 32)
            root.addSubview(anchor)
            typealias Row = ToolbarMenuPopoverPresenter.Row
            let menus: [(String, [Row])] = [
                ("empty", []),
                ("single", [.init(title: "创建时间", kind: .check, isChecked: true)]),
                ("mixed", [.header("排序方式"), .init(title: "作品名称", kind: .check),
                    .separator(), .init(title: "灰显状态", kind: .info),
                    .init(title: "不可点击", kind: .action, isEnabled: false)]),
                ("long", [.separator(), .header("多种文字与连续分隔线"), .separator(), .separator(),
                    .init(title: "非常长的作品名称与 English 🎨 é 测试文字", kind: .check),
                    .init(title: "重复", kind: .action), .init(title: "重复", kind: .check),
                    .separator()])
            ]
            func panel(_ presenter: ToolbarMenuPopoverPresenter) -> NSPopover {
                Mirror(reflecting: presenter).children.first { $0.label == "popover" }!.value as! NSPopover
            }
            func descendants(_ view: NSView) -> [NSButton] {
                (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(descendants)
            }
            for (name, rows) in menus {
                let presenter = ToolbarMenuPopoverPresenter()
                presenter.toggle(anchor: anchor) { rows }
                pump(0.18)
                let popover = panel(presenter)
                let view = popover.contentViewController!.view
                view.layoutSubtreeIfNeeded()
                let id = "menu-\(dark)-\(name)"
                let expectedHeight = 12 + rows.reduce(CGFloat(0)) {
                    $0 + ($1.kind == .separator ? 5 : ($1.kind == .sectionHeader ? 24 : 26))
                }
                checks[id + "-height"] = popover.contentSize.height == expectedHeight
                checks[id + "-width"] = (104...280).contains(popover.contentSize.width)
                checks[id + "-shown"] = presenter.isShown
                facts[id + "-size"] = [popover.contentSize.width, popover.contentSize.height]
                let stack = view.subviews.first as! NSStackView
                facts[id + "-frames"] = stack.arrangedSubviews.map {
                    [$0.frame.minX, $0.frame.minY, $0.frame.width, $0.frame.height]
                }
                image(id, view)
                presenter.close()
                pump(0.16)
            }
            var selected = false
            var calls: [String] = []
            let presenter = ToolbarMenuPopoverPresenter()
            presenter.toggle(anchor: anchor) {
                [.header("排序"),
                 .init(title: selected ? "升序" : "降序", kind: .check, isChecked: selected,
                       handler: { selected.toggle(); calls.append("check") }),
                 .separator(),
                 .init(title: "不可点击", kind: .check, isEnabled: false, handler: { calls.append("disabled") }),
                 .init(title: "重复", kind: .check, handler: { calls.append("duplicate-first") }),
                 .init(title: "重复", kind: .action, handler: { calls.append("duplicate-second") })]
            }
            pump(0.18)
            let popover = panel(presenter)
            let oldButton = descendants(popover.contentViewController!.view).first { $0.title == "降序" }!
            oldButton.performClick(nil)
            pump(0.08)
            let buttons = descendants(popover.contentViewController!.view)
            checks["menu-\(dark)-check-stays-open"] = presenter.isShown && selected && calls == ["check"]
                && buttons.first?.title == "升序"
            oldButton.performClick(nil)
            checks["menu-\(dark)-retired-button-inert"] = calls == ["check"] && selected
            buttons.first { $0.title == "不可点击" }!.performClick(nil)
            checks["menu-\(dark)-disabled-inert"] = calls == ["check"]
            buttons.filter { $0.title == "重复" }.first!.performClick(nil)
            pump(0.08)
            checks["menu-\(dark)-duplicate-check"] = presenter.isShown && calls == ["check", "duplicate-first"]
            let refreshedButtons = descendants(popover.contentViewController!.view)
            refreshedButtons.filter { $0.title == "重复" }.last!.performClick(nil)
            let closingDeadline = Date().addingTimeInterval(1)
            while presenter.isShown && Date() < closingDeadline { pump(0.02) }
            facts["menu-\(dark)-calls"] = calls
            checks["menu-\(dark)-action-closes"] = !presenter.isShown
                && calls == ["check", "duplicate-first", "duplicate-second"]
            anchor.removeFromSuperview()
        }
        let probePopover = NSPopover()
        var probeObserver: ToolbarPopoverScrollDismissal? = ToolbarPopoverScrollDismissal(popover: probePopover)
        weak var weakObserver = probeObserver
        func hasMonitor(_ observer: ToolbarPopoverScrollDismissal) -> Bool {
            let value = Mirror(reflecting: observer).children.first { $0.label == "monitor" }!.value
            return !Mirror(reflecting: value).children.isEmpty
        }
        probeObserver!.watch(relativeTo: root)
        let watching = hasMonitor(probeObserver!)
        NotificationCenter.default.post(name: NSPopover.willCloseNotification, object: probePopover)
        checks["menu-observer-stops-on-close"] = watching && !hasMonitor(probeObserver!)
        probeObserver = nil
        checks["menu-observer-released"] = weakObserver == nil
        NotificationCenter.default.post(name: NSPopover.willCloseNotification, object: probePopover)
        facts["checks"] = checks
        for dark in [false, true] {
            root.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let data = SidebarFixtureData()
            let sidebar = SidebarOutlineView(frame: NSRect(x: 0, y: 0, width: 220, height: 140))
            let column = NSTableColumn(identifier: .init("sidebar"))
            column.width = 220
            sidebar.addTableColumn(column)
            sidebar.outlineTableColumn = column
            sidebar.headerView = nil
            sidebar.rowSizeStyle = .default
            sidebar.style = .sourceList
            sidebar.floatsGroupRows = false
            sidebar.indentationPerLevel = 10
            sidebar.intercellSpacing = NSSize(width: 0, height: 4)
            sidebar.dataSource = data
            sidebar.delegate = data
            root.addSubview(sidebar)
            sidebar.reloadData()
            sidebar.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
            window.makeFirstResponder(sidebar)
            pump()
            let row = sidebar.rowView(atRow: 1, makeIfNecessary: true) as! SidebarRowView
            checks["sidebar-\(dark)-selection"] = sidebar.selectedRow == 1 && row.isSelected
            checks["sidebar-\(dark)-geometry"] = sidebar.rect(ofRow: 1).height == 30
            facts["sidebar-\(dark)-frames"] = (0..<3).map { index in
                let rect = sidebar.rect(ofRow: index)
                return [rect.minX, rect.minY, rect.width, rect.height]
            }
            image("sidebar-\(dark)-active", sidebar)
            row.isEmphasized = false
            facts["sidebar-\(dark)-nonemphasized"] = !row.isEmphasized
            row.needsDisplay = true
            image("sidebar-\(dark)-inactive", sidebar)
            row.suppressSelectionDuringDrag = true
            row.needsDisplay = true
            image("sidebar-\(dark)-drag", sidebar)
            checks["sidebar-\(dark)-drag-keeps-selection"] = sidebar.selectedRow == 1 && row.isSelected
            row.suppressSelectionDuringDrag = false
            row.needsDisplay = true
            checks["sidebar-\(dark)-restore-keeps-selection"] = sidebar.selectedRow == 1 && row.isSelected
            image("sidebar-\(dark)-restored", sidebar)
            sidebar.removeFromSuperview()
        }
        facts["checks"] = checks
        facts["nativeButton"] = InspectorFooterButton.self is NSButton.Type
        facts["windowVisible"] = window.isVisible
        try JSONSerialization.data(withJSONObject: facts, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("report.json"))
        window.close()
    }
}
