import AppKit
import QuartzCore

@main struct ListThumbnailTintAnimationChecks {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        NSApp.finishLaunching()
        var checks: [String: Bool] = [:], samples: [String: [CGFloat]] = [:]
        var timingDiagnostics: [String: Any] = [:]
        func check(_ key: String, _ value: Bool) { checks[key] = value }
        let screen = NSScreen.main!.visibleFrame
        let window = NSWindow(contentRect: NSRect(x: screen.minX + 30, y: screen.minY + 30, width: 480, height: 260),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 260))
        let systemBase = NSView(frame: NSRect(x: 0, y: 0, width: 140, height: 260))
        systemBase.wantsLayer = true
        systemBase.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        let sidebar = AppKitListTintSurface(frame: systemBase.bounds)
        sidebar.ignoresHitTesting = true
        sidebar.setAccessibilityElement(false)
        systemBase.addSubview(sidebar)
        let scroll = NSScrollView(frame: systemBase.bounds)
        scroll.drawsBackground = false
        let document = NSView(frame: systemBase.bounds)
        scroll.documentView = document
        systemBase.addSubview(scroll)
        let main = AppKitListTintSurface(frame: NSRect(x: 140, y: 0, width: 340, height: 260))
        let button = NSButton(title: "系统按钮", target: nil, action: nil)
        button.frame = NSRect(x: 25, y: 60, width: 120, height: 30)
        main.addSubview(button); root.addSubview(systemBase); root.addSubview(main); window.contentView = root
        root.appearance = NSAppearance(named: .aqua)
        sidebar.wantsLayer = true; main.wantsLayer = true
        sidebar.layer!.backgroundColor = NSColor.clear.cgColor; main.layer!.backgroundColor = NSColor.clear.cgColor
        let roots: [NSView] = [sidebar, main]
        let layers = roots.map { $0.layer! }
        let children = roots.map(\.subviews), accessibility = roots.map { $0.isAccessibilityElement() }
        let frames = [sidebar.frame, main.frame, button.frame]
        func hierarchy(_ views: [NSView]) -> [[String: Any]] {
            views.map { view in
                ["type": String(describing: type(of: view)), "frame": NSStringFromRect(view.frame),
                 "layer": view.layer.map { String(describing: ObjectIdentifier($0)) } ?? "nil",
                 "children": view.subviews.map { ["type": String(describing: type(of: $0)),
                    "identity": String(describing: ObjectIdentifier($0)), "frame": NSStringFromRect($0.frame)] }]
            }
        }
        timingDiagnostics["hierarchyBeforeInstall"] = hierarchy(roots)
        let buttonTint = button.contentTintColor, accent = NSColor.controlAccentColor
        var options = AppKitListBackgroundTint.DisplayOptions(allowsTint: true, reduceMotion: false)
        var pendingSamples: [(ListThumbnailTintColor?) -> Void] = []
        let owner = AppKitListBackgroundTint(sample: { _, done in pendingSamples.append(done); return {} },
            displayOptions: { options })
        owner.install(sidebar: sidebar, main: main)
        check("installAddsNoSubviewOrLayer", roots.map(\.subviews) == children && roots.map { $0.layer! } == layers)
        // The Sidebar gate separately checks the product's opaque system draw.
        // This hierarchy isolates the unchanged real CALayer projection.
        check("onePassiveTintHostSitsBetweenPlainSystemBaseAndOriginalTransparentScroll", systemBase.subviews.filter { $0 is AppKitListTintSurface }.count == 1
            && systemBase.subviews.firstIndex(of: sidebar)! < systemBase.subviews.firstIndex(of: scroll)!
            && !scroll.drawsBackground && !(systemBase is NSVisualEffectView)
            && systemBase.layer?.backgroundColor?.alpha == 1)
        check("passiveSidebarTintCannotInterceptScrollDocumentHitOrAccessibility", sidebar.hitTest(.zero) == nil
            && !sidebar.isAccessibilityElement() && scroll.documentView === document
            && systemBase.hitTest(NSPoint(x: 50, y: 100))?.isDescendant(of: scroll) == true)
        let key = AppKitListBackgroundTint.animationKey
        func pump(_ seconds: TimeInterval) {
            CATransaction.flush()
            let deadline = Date().addingTimeInterval(seconds)
            repeat {
                window.displayIfNeeded()
                if let event = NSApp.nextEvent(matching: .any, until: Date().addingTimeInterval(0.005), inMode: .default, dequeue: true) {
                    NSApp.sendEvent(event)
                }
                NSApp.updateWindows()
            } while Date() < deadline
        }
        func rgba(_ color: CGColor?) -> [CGFloat]? {
            guard let color, let c = NSColor(cgColor: color)?.usingColorSpace(.deviceRGB) else { return nil }
            return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent]
        }
        func model(_ view: NSView) -> [CGFloat] { rgba(view.layer?.backgroundColor) ?? [-1, -1, -1, -1] }
        func presented(_ view: NSView) -> [CGFloat]? { rgba(view.layer?.presentation()?.backgroundColor) }
        func animation(_ view: NSView) -> CABasicAnimation? { view.layer?.animation(forKey: key) as? CABasicAnimation }
        func animationColor(_ value: Any?) -> [CGFloat]? {
            guard let value, CFGetTypeID(value as CFTypeRef) == CGColor.typeID else { return nil }
            return rgba((value as! CGColor))
        }
        func from(_ view: NSView) -> [CGFloat]? { animationColor(animation(view)?.fromValue) }
        func to(_ view: NSView) -> [CGFloat]? { animationColor(animation(view)?.toValue) }
        func usesSystemEase(_ view: NSView) -> Bool {
            guard let timing = animation(view)?.timingFunction else { return false }
            var first: [Float] = [0, 0], second: [Float] = [0, 0]
            timing.getControlPoint(at: 1, values: &first); timing.getControlPoint(at: 2, values: &second)
            return abs(first[0] - 0.42) < 0.001 && abs(first[1]) < 0.001
                && abs(second[0] - 0.58) < 0.001 && abs(second[1] - 1) < 0.001
        }
        func close(_ a: [CGFloat]?, _ b: [CGFloat]?, tolerance: CGFloat = 0.015) -> Bool {
            guard let a, let b, a.count == 4, b.count == 4 else { return false }
            return zip(a, b).allSatisfy { abs($0 - $1) <= tolerance }
        }
        func record(_ name: String, _ value: [CGFloat]?) { if let value { samples[name] = value } }
        func notify() {
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                object: NSWorkspace.shared)
        }
        let data = Data([UInt8(255), 0, 0, 255])
        let cg = CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: CGDataProvider(data: data as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let image = NSImage(cgImage: cg, size: NSSize(width: 1, height: 1))
        let red = ListThumbnailTintColor(red: 1, green: 0, blue: 0)
        let blue = ListThumbnailTintColor(red: 0, green: 0, blue: 1)
        let green = ListThumbnailTintColor(red: 0, green: 1, blue: 0)
        func source(_ id: String) -> ListThumbnailTintSource {
            let result = ListThumbnailTintSource()
            result.update(id: id) { done in done(image); return {} }
            return result
        }
        func complete(_ color: ListThumbnailTintColor) {
            precondition(!pendingSamples.isEmpty, "real controller must request sampling")
            pendingSamples.removeLast()(color)
        }
        window.orderFront(nil); pump(0.08)
        timingDiagnostics["hierarchyFirstVisible"] = hierarchy(roots)
        let a = source("A"); owner.bind(a); complete(red)
        check("realWindowStartsSystemBackgroundAnimation", window.isVisible && roots.allSatisfy {
            animation($0)?.keyPath == "backgroundColor" && animation($0)?.duration == 0.75
                && usesSystemEase($0)
        })
        check("animationDoesNotChangeRootOpacity", roots.allSatisfy { $0.alphaValue == 1 && $0.layer?.opacity == 1 })
        pump(0.24)
        let redMiddle = presented(main)
        record("redMiddle", redMiddle)
        check("realPresentationShowsIntermediateTint", redMiddle.map { $0[0] > 0.01 && $0[0] < 0.95 && $0[1] < 0.01 && $0[2] < 0.01 && $0[3] > 0.004 && $0[3] < 0.085 } == true
            && model(main)[3] > 0.085)
        let oldFrom = from(main), beforeSame = presented(main)
        notify(); pump(0.015)
        let afterSame = presented(main)
        record("sameTargetBefore", beforeSame); record("sameTargetAfter", afterSame)
        check("sameTargetNotificationDoesNotRestart", close(from(main), oldFrom, tolerance: 0.0001)
            && (afterSame?[3] ?? -1) >= (beforeSame?[3] ?? 1) - 0.002)

        // A new first item has not returned its image yet. The model becomes
        // clear while the actual presentation fades from its current color.
        let b = ListThumbnailTintSource()
        var lateImage: ((NSImage?) -> Void)?
        b.update(id: "B") { done in lateImage = done; return {} }
        let beforeRetarget = presented(main)
        owner.bind(b)
        record("retargetBefore", beforeRetarget); record("retargetFrom", from(main))
        check("rapidRetargetStartsAtPresentedColor", close(from(main), beforeRetarget)
            && model(main)[3] == 0 && to(main)?[3] == 0)
        pump(0.14)
        let fading = presented(main)
        record("pendingImageFade", fading)
        check("pendingImageFadesInsteadOfFlashingClear", model(main)[3] == 0
            && fading.map { $0[3] > 0.004 && $0[3] < (beforeRetarget?[3] ?? 0) } == true)
        lateImage?(image)
        check("asyncImageStartsRealSampler", pendingSamples.count == 1)
        let beforeBlue = presented(main)
        complete(blue)
        record("asyncBlueFrom", from(main)); record("asyncBlueBefore", beforeBlue)
        check("asyncNewColorContinuesFromPresentation", close(from(main), beforeBlue) && model(main)[2] > 0.98 && (to(main)?[2] ?? 0) > 0.98)
        pump(0.2)
        let blueMiddle = presented(main)
        record("blueMiddle", blueMiddle)
        check("realPresentationBlendsOldAndNewHue", blueMiddle.map { $0[0] > 0.01 && $0[2] > 0.01 && $0[3] > 0.004 } == true)
        let c = source("C"), beforeGreen = presented(main)
        let finalRetargetStarted = Date()
        owner.bind(c); complete(green)
        let finalAnimation = animation(main)
        record("rapidGreenBefore", beforeGreen); record("rapidGreenFrom", from(main))
        check("secondRapidRetargetRemainsContinuous", close(from(main), beforeGreen) && model(main)[1] > 0.98)
        pump(0.44)
        record("extendedTransitionMiddle", presented(main))
        check("extendedDurationStillBlendsAtPreviousFinish", !close(presented(main), model(main), tolerance: 0.002))
        pump(0.38)
        record("settledPresentation", presented(main)); record("settledModel", model(main))
        check("transitionSettlesAtTarget", close(presented(main), model(main), tolerance: 0.002)
            && close(model(main), [0, 1, 0, 0.09], tolerance: 0.002))
        check("settledAnimationHasFiniteNoRepeatLifetime", finalAnimation?.duration == 0.75 && finalAnimation?.repeatCount == 0
            && finalAnimation?.repeatDuration == 0 && finalAnimation?.isRemovedOnCompletion == true)
        if let layer = main.layer, let retained = animation(main) {
            let now = CACurrentMediaTime()
            timingDiagnostics.merge(["isRemovedOnCompletion": retained.isRemovedOnCompletion,
                "fillMode": retained.fillMode.rawValue, "beginTime": retained.beginTime,
                "speed": retained.speed, "timeOffset": retained.timeOffset, "duration": retained.duration,
                "repeatCount": retained.repeatCount, "repeatDuration": retained.repeatDuration,
                "layerSpeed": layer.speed, "layerTimeOffset": layer.timeOffset,
                "mediaTime": now, "layerLocalTime": layer.convertTime(now, from: nil),
                "windowVisible": window.isVisible, "windowOcclusionVisible": window.occlusionState.contains(.visible),
                "appRunning": NSApp.isRunning, "animationKeys": layer.animationKeys() ?? []], uniquingKeysWith: { _, next in next })
        }
        timingDiagnostics["terminalColorElapsed"] = Date().timeIntervalSince(finalRetargetStarted)
        // Native same-key replacements can retain a finished animation object
        // after its visible color has settled. Bound bookkeeping cleanup apart
        // from the strict presentation assertion above; the product owns no timer.
        let completionDeadline = finalRetargetStarted.addingTimeInterval(3)
        while animation(main) != nil && Date() < completionDeadline { pump(0.02) }
        timingDiagnostics["keyCleanupElapsed"] = Date().timeIntervalSince(finalRetargetStarted)
        timingDiagnostics["keyCleaned"] = animation(main) == nil
        check("settledAnimationRemoved", animation(main) == nil)

        owner.bind(nil); pump(0.07)
        let beforeHidden = presented(main)
        record("clearFadeBeforeHidden", beforeHidden)
        check("hiddenCounterexampleHasClearModelAndVisibleFade", model(main)[3] == 0
            && animation(main) != nil && (beforeHidden?[3] ?? 0) > 0.004)
        window.orderOut(nil); pump(0.02)
        check("hiddenImmediatelyRemovesOwnedAnimation", roots.allSatisfy { animation($0) == nil && model($0)[3] == 0 })
        window.orderFront(nil); pump(0.04)
        let d = source("D"); owner.bind(d); complete(red); pump(0.82)
        owner.bind(nil); pump(0.07)
        let beforeDisabled = presented(main)
        record("clearFadeBeforeDisabled", beforeDisabled)
        check("disabledCounterexampleHasClearModelAndVisibleFade", model(main)[3] == 0
            && animation(main) != nil && (beforeDisabled?[3] ?? 0) > 0.004)
        options.allowsTint = false; notify()
        check("disabledImmediatelyRemovesOwnedAnimation", roots.allSatisfy { animation($0) == nil && model($0)[3] == 0 })

        options.allowsTint = true; notify()
        let e = source("E"); owner.bind(e); complete(blue); pump(0.06)
        let unrelated = CABasicAnimation(keyPath: "opacity")
        unrelated.fromValue = 1; unrelated.toValue = 1; unrelated.duration = 10
        main.layer?.add(unrelated, forKey: "unrelated-test-animation")
        options.reduceMotion = true; notify()
        check("reduceMotionImmediatelyRemovesOwnedAnimation", roots.allSatisfy { animation($0) == nil && model($0)[2] > 0.98 })
        check("accessibilityChangePreservesUnrelatedAnimation", main.layer?.animation(forKey: "unrelated-test-animation") != nil)
        let f = source("F"); owner.bind(f); complete(red)
        check("reduceMotionNewTargetProjectsImmediately", roots.allSatisfy { animation($0) == nil && model($0)[0] > 0.98 && model($0)[3] > 0.085 })
        options.reduceMotion = false; notify()
        let g = source("G"); owner.bind(g); complete(green); pump(0.06)
        check("appearanceCounterexampleHasRunningAnimation", animation(main) != nil)
        root.appearance = NSAppearance(named: .darkAqua); pump(0.02)
        timingDiagnostics["rootDark"] = roots.map { ["rgba": model($0), "appearance": $0.effectiveAppearance.name.rawValue] as [String: Any] }
        check("appearanceReprojectsWithoutAnimation", roots.allSatisfy { animation($0) == nil && abs(model($0)[3] - 0.12) < 0.002 })
        root.appearance = NSAppearance(named: .aqua); pump(0.02)
        timingDiagnostics["rootLight"] = roots.map { ["rgba": model($0), "appearance": $0.effectiveAppearance.name.rawValue] as [String: Any] }
        timingDiagnostics["hierarchyAfterTransitions"] = hierarchy(roots)
        check("appearanceRestoresLightAlpha", roots.allSatisfy { animation($0) == nil && abs(model($0)[3] - 0.09) < 0.002 })
        check("allTransitionsPreserveChildrenLayersAndFrames", roots.map(\.subviews) == children && roots.map { $0.layer! } == layers
            && [sidebar.frame, main.frame, button.frame] == frames)
        check("allTransitionsPreserveButtonHitAndAccessibility", root.hitTest(button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: root)) === button
            && roots.map { $0.isAccessibilityElement() } == accessibility)
        check("allTransitionsPreserveOpacityAndSystemAccent", roots.allSatisfy { $0.alphaValue == 1 && $0.layer?.opacity == 1 }
            && button.contentTintColor == buttonTint && NSColor.controlAccentColor == accent)
        main.layer?.removeAnimation(forKey: "unrelated-test-animation")
        owner.bind(nil); window.contentView = nil; window.close()
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: ["checks": checks,
            "presentationSamples": samples, "timingDiagnostics": timingDiagnostics], options: [.sortedKeys]))
    }
}
