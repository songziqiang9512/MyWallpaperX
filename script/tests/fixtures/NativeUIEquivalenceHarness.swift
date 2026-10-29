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
        func pixels(_ view: NSView) -> Data? {
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let bytes = bitmap.bitmapData else { return nil }
            return Data(bytes: bytes, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        }
        func edgeAlpha(_ scroll: NSScrollView, top: Bool) -> CGFloat? {
            guard let mask = scroll.layer?.mask, scroll.bounds.width > 0, scroll.bounds.height > 0,
                  let bitmap = scroll.bitmapImageRepForCachingDisplay(in: scroll.bounds) else { return nil }
            // Capture the native view tree: rendering the bare mask omits its
            // flipped AppKit ancestor and reverses the physical edge mapping.
            scroll.cacheDisplay(in: scroll.bounds, to: bitmap)
            let scaleX = CGFloat(bitmap.pixelsWide) / scroll.bounds.width
            let scaleY = CGFloat(bitmap.pixelsHigh) / scroll.bounds.height
            let distanceFromTop = scroll.isFlipped ? mask.frame.minY - scroll.bounds.minY : scroll.bounds.maxY - mask.frame.maxY
            let x = Int(floor((mask.frame.midX - scroll.bounds.minX) * scaleX))
            let y = top ? Int(round(distanceFromTop * scaleY)) : Int(round((distanceFromTop + mask.frame.height) * scaleY)) - 1
            guard (0..<bitmap.pixelsWide).contains(x), (0..<bitmap.pixelsHigh).contains(y) else { return nil }
            return bitmap.colorAt(x: x, y: y)?.alphaComponent
        }
        func edges(_ scroll: NSScrollView, topFades: Bool, bottomFades: Bool) -> Bool {
            guard let top = edgeAlpha(scroll, top: true), let bottom = edgeAlpha(scroll, top: false) else { return false }
            let passed = (topFades ? top < 0.5 : top == 1) && (bottomFades ? bottom < 0.5 : bottom == 1)
            if !passed, let document = scroll.documentView, let mask = scroll.layer?.mask as? CAGradientLayer {
                let colors = (mask.colors as? [CGColor])?.map(\.alpha) ?? []
                let diagnostic: [String] = ["fade-native-edges", "expectedTop=\(topFades)", "expectedBottom=\(bottomFades)",
                    "topPixelAlpha=\(top)", "bottomPixelAlpha=\(bottom)", "colors=\(colors)",
                    "scrollFlipped=\(scroll.isFlipped)", "layerFlipped=\(scroll.layer?.isGeometryFlipped == true)",
                    "maskFlipped=\(mask.isGeometryFlipped)", "start=\(mask.startPoint)", "end=\(mask.endPoint)",
                    "maskFrame=\(mask.frame)", "maskBounds=\(mask.bounds)", "clip=\(scroll.contentView.bounds)",
                    "viewport=\(document.convert(scroll.contentView.bounds, from: scroll.contentView))", "insets=\(scroll.contentInsets)",
                    "documentFlipped=\(document.isFlipped)", "documentBounds=\(document.bounds)"]
                FileHandle.standardError.write(Data((diagnostic.joined(separator: " ") + "\n").utf8))
            }
            return passed
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
            // A known opaque canvas also makes both mask edges observable
            // when the short document leaves part of the viewport empty.
            scroll.drawsBackground = true
            scroll.backgroundColor = .systemBlue
            let document = InspectorContentDocumentView(frame: NSRect(x: 0, y: 0, width: 250, height: 1200))
            document.wantsLayer = true
            document.layer?.backgroundColor = NSColor.systemBlue.cgColor
            scroll.documentView = document
            root.addSubview(scroll)
            scroll.layoutSubtreeIfNeeded()
            for offset in [CGFloat(0), 100, 750] {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: offset))
                scroll.reflectScrolledClipView(scroll.contentView)
                checks["fade-\(ratio)-\(offset)"] = edges(scroll,
                    topFades: ratio > 0 && offset > 0, bottomFades: ratio > 0)
                image("fade-\(ratio)-\(offset)", scroll)
            }
            scroll.frame.size = NSSize(width: 300, height: 180)
            scroll.layoutSubtreeIfNeeded()
            checks["fade-resize-\(ratio)"] = scroll.layer?.mask?.frame == scroll.bounds
            image("fade-resize-\(ratio)", scroll)
            let bottomY = document.bounds.maxY - scroll.contentView.bounds.height
            scroll.contentView.scroll(to: NSPoint(x: 0, y: bottomY))
            scroll.reflectScrolledClipView(scroll.contentView)
            checks["fade-native-bottom-\(ratio)"] = edges(scroll, topFades: ratio > 0, bottomFades: false)

            scroll.automaticallyAdjustsContentInsets = false
            scroll.contentInsets = NSEdgeInsets(top: 12, left: 0, bottom: 6, right: 0)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: -12))
            scroll.reflectScrolledClipView(scroll.contentView)
            let insetTop = edges(scroll, topFades: false, bottomFades: ratio > 0)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: bottomY + 6))
            scroll.reflectScrolledClipView(scroll.contentView)
            let nativeClip = scroll.convert(scroll.contentView.bounds, from: scroll.contentView)
            let expectedMask = NSRect(x: nativeClip.minX, y: nativeClip.minY + (scroll.isFlipped ? 12 : 6),
                width: nativeClip.width, height: nativeClip.height - 18)
            checks["fade-native-insets-\(ratio)"] = insetTop && edges(scroll, topFades: ratio > 0, bottomFades: false)
                && scroll.layer?.mask?.frame == expectedMask
            scroll.contentInsets = NSEdgeInsetsZero

            let unflipped = NSView(frame: document.frame)
            unflipped.wantsLayer = true
            unflipped.layer?.backgroundColor = NSColor.systemBlue.cgColor
            scroll.documentView = unflipped
            scroll.contentView.scroll(to: NSPoint(x: 0, y: bottomY))
            scroll.reflectScrolledClipView(scroll.contentView)
            let unflippedTop = edges(scroll, topFades: false, bottomFades: ratio > 0)
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
            checks["fade-unflipped-document-\(ratio)"] = unflippedTop && edges(scroll, topFades: ratio > 0, bottomFades: false)

            scroll.documentView = InspectorContentDocumentView(frame: NSRect(x: 0, y: 0, width: 300, height: 80))
            scroll.contentView.scroll(to: .zero)
            scroll.layoutSubtreeIfNeeded()
            checks["fade-short-document-\(ratio)"] = edges(scroll, topFades: false, bottomFades: false)
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
        let anchor = NSButton(title: "原生菜单", target: nil, action: nil)
        anchor.frame = NSRect(x: 220, y: 200, width: 80, height: 32)
        root.addSubview(anchor)
        var nativeCalls = 0
        let rows: [ToolbarMenu.Row] = [.header("排序"),
            .init(title: "当前选项", kind: .action, isChecked: true, handler: { nativeCalls += 1 }),
            .init(title: "禁用选项", kind: .action, isEnabled: false, handler: { nativeCalls += 100 }),
            .separator(), .init(title: "状态", kind: .info)]
        let nativeMenu = ToolbarMenu.makeMenu(rows: rows)
        checks["native-menu-preserves-order-and-separators"] = nativeMenu.items.map(\.title) == ["排序", "当前选项", "禁用选项", "", "状态"]
            && nativeMenu.items[0].isSectionHeader && nativeMenu.items[3].isSeparatorItem
        checks["native-menu-preserves-checked-and-disabled-values"] = nativeMenu.items[1].state == .on
            && !nativeMenu.items[2].isEnabled && !nativeMenu.items[4].isEnabled
        nativeMenu.performActionForItem(at: 1)
        if let action = nativeMenu.items[2].action { NSApp.sendAction(action, to: nativeMenu.items[2].target, from: nativeMenu.items[2]) }
        checks["native-menu-dispatches-only-available-original-command"] = nativeCalls == 1
        var duplicateCalls: [String] = []
        let duplicates = ToolbarMenu.makeMenu(rows: [
            .init(title: "重复", kind: .action, handler: { duplicateCalls.append("first") }),
            .init(title: "重复", kind: .action, handler: { duplicateCalls.append("second") })
        ])
        duplicates.performActionForItem(at: 0); duplicates.performActionForItem(at: 1)
        checks["same-title-native-menu-items-retain-distinct-original-actions"] = duplicateCalls == ["first", "second"]
        var trackingMenu: NSMenu?, began = 0, ended = 0
        let begin = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { note in
            MainActor.assumeIsolated { trackingMenu = note.object as? NSMenu; began += 1 }
        }
        let end = NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ended += 1 }
        }
        let cancellation = Timer(timeInterval: 0.03, repeats: false) { _ in
            MainActor.assumeIsolated { trackingMenu?.cancelTracking() }
        }
        RunLoop.main.add(cancellation, forMode: .eventTracking)
        ToolbarMenu.popUp(anchor: anchor, rows: rows)
        cancellation.invalidate()
        checks["ordinary-menu-tracks-and-cancels-through-appkit"] = began == 1 && ended == 1
            && trackingMenu?.items[1].state == .on && nativeCalls == 1
        NotificationCenter.default.removeObserver(begin); NotificationCenter.default.removeObserver(end)
        anchor.removeFromSuperview()
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
            checks["sidebar-\(dark)-native-neutral-selection"] = !row.isEmphasized
            let selectedPixels = pixels(row)
            row.isEmphasized = true
            checks["sidebar-\(dark)-no-accent-phase"] = !row.isEmphasized
            pump()
            checks["sidebar-\(dark)-no-accent-pixel-shift"] = selectedPixels != nil && selectedPixels == pixels(row)
            let editor = NSTextField(string: "焦点回归")
            editor.frame = NSRect(x: 250, y: 200, width: 140, height: 24)
            root.addSubview(editor)
            let movedToContent = window.makeFirstResponder(editor)
            pump()
            checks["sidebar-\(dark)-content-focus-keeps-native-selection"] = movedToContent
                && window.firstResponder !== sidebar && sidebar.selectedRow == 1 && row.isSelected && !row.isEmphasized
            checks["sidebar-\(dark)-content-focus-pixel-stability"] = selectedPixels != nil && selectedPixels == pixels(row)
            let movedToSidebar = window.makeFirstResponder(sidebar)
            pump()
            checks["sidebar-\(dark)-sidebar-focus-keeps-native-selection"] = movedToSidebar
                && window.firstResponder === sidebar && sidebar.selectedRow == 1 && row.isSelected && !row.isEmphasized
            checks["sidebar-\(dark)-sidebar-focus-pixel-stability"] = selectedPixels != nil && selectedPixels == pixels(row)
            editor.removeFromSuperview()
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
            // Manual drag selection suppression has retired. Real native gap,
            // cancellation and receipt behavior live in SidebarHarness; the
            // focus/neutral-selection/pixel/geometry checks above stay here.
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
