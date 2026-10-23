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
                    NSLayoutConstraint.activate([
                        button.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
                        button.topAnchor.constraint(equalTo: root.topAnchor, constant: -80),
                        button.widthAnchor.constraint(equalToConstant: iconOnly ? 38 : 180),
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
                    button.removeFromSuperview()
                }
            }
            let settings = SettingsGroupView(title: "测试设置")
            settings.frame = NSRect(x: 0, y: 0, width: 320, height: 150)
            root.addSubview(settings)
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
            rows[1].isHidden = true
            settings.refreshSeparators()
            settings.layoutSubtreeIfNeeded()
            checks["settings-hidden-separators-\(dark)"] = separators.allSatisfy(\.isHidden)
            image("\(dark ? "dark" : "light")-settings-hidden", settings)
            settings.removeFromSuperview()
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
        facts["checks"] = checks
        facts["nativeButton"] = InspectorFooterButton.self is NSButton.Type
        facts["windowVisible"] = window.isVisible
        try JSONSerialization.data(withJSONObject: facts, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("report.json"))
        window.close()
    }
}
