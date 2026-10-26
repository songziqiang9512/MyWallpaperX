import AppKit
import Foundation

@MainActor final class TintProviderView: NSView, ListThumbnailTintProviding {
    let listThumbnailTintSource = ListThumbnailTintSource()
}

@main struct ListThumbnailTintChecks {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        var checks: [String: Bool] = [:]
        func check(_ name: String, _ value: Bool) { checks[name] = value }
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.025)) }
        func image(_ rgba: [UInt8]) -> NSImage {
            let data = Data(rgba)
            let provider = CGDataProvider(data: data as CFData)!
            let pixels = CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
            return NSImage(cgImage: pixels, size: NSSize(width: 1, height: 1))
        }
        let redImage = image([255, 0, 0, 255])
        let transparent = image([0, 0, 0, 0]).cgImage(forProposedRect: nil, context: nil, hints: nil)!
        check("transparentPixelsHaveNoTint", ListThumbnailTintSampler.average(transparent) == nil)
        let sampled = ListThumbnailTintSampler.average(redImage.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
        check("realSamplerRed", sampled.map { $0.red > 0.98 && $0.green < 0.02 && $0.blue < 0.02 } == true)
        let halfRed = ListThumbnailTintSampler.average(image([255, 0, 0, 128]).cgImage(forProposedRect: nil, context: nil, hints: nil)!)
        check("partialAlphaDoesNotDarkenHue", halfRed.map { $0.red > 0.98 && $0.green < 0.02 && $0.blue < 0.02 } == true)

        let source = ListThumbnailTintSource()
        var notifications = 0
        let stop = source.observe { notifications += 1 }
        source.update(id: "A", assets: ["one"]) { complete in complete(redImage); return {} }
        let first = source.request!.revision
        source.update(id: "A", assets: ["one"]) { _ in fatalError("unchanged identity must retain its loader") }
        check("sameIdentityDoesNotRepublish", notifications == 1 && source.request?.revision == first)
        source.update(id: "A", assets: ["two"]) { complete in complete(redImage); return {} }
        check("sameIDNewAssetRepublishes", notifications == 2 && source.request?.revision != first)
        let assetRevision = source.request!.revision
        source.invalidate()
        check("explicitInvalidateChangesRevision", source.request?.revision != assetRevision && notifications == 3)
        stop(); source.update(id: nil)
        check("observerDetachesAndEmptyClears", notifications == 3 && source.request == nil)

        let wrapper = TintProviderView(), old = ListThumbnailTintSource(), next = ListThumbnailTintSource()
        old.update(id: "old") { complete in complete(redImage); return {} }
        wrapper.listThumbnailTintSource.forward(from: old)
        check("forwardAlreadyPublishedRequest", wrapper.listThumbnailTintSource.request?.identity.itemID == "old")
        wrapper.listThumbnailTintSource.forward(from: next)
        old.invalidate()
        check("forwardReplacementRejectsOld", wrapper.listThumbnailTintSource.request == nil)
        next.update(id: "new") { complete in complete(redImage); return {} }
        check("forwardTracksCurrent", wrapper.listThumbnailTintSource.request?.revision == next.request?.revision)
        wrapper.listThumbnailTintSource.forward(from: nil); next.invalidate()
        check("forwardDetachClears", wrapper.listThumbnailTintSource.request == nil)
        let outer = NSView(); outer.addSubview(wrapper)
        check("mountedFindsActualNestedProvider", ListThumbnailTintSource.mounted(in: outer) === wrapper.listThumbnailTintSource)
        outer.addSubview(TintProviderView())
        check("mountedKeepsFirstMountedProvider", ListThumbnailTintSource.mounted(in: outer) === wrapper.listThumbnailTintSource)

        let window = NSWindow(contentRect: NSRect(x: 14000, y: 14000, width: 440, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 300))
        let sidebar = AppKitListTintSurface(frame: NSRect(x: 0, y: 0, width: 120, height: 300))
        sidebar.ignoresHitTesting = true
        let main = AppKitListTintSurface(frame: NSRect(x: 120, y: 0, width: 320, height: 300))
        let button = NSButton(title: "系统按钮", target: nil, action: nil)
        button.bezelStyle = .rounded; button.frame = NSRect(x: 30, y: 40, width: 110, height: 30)
        main.addSubview(button); root.addSubview(sidebar); root.addSubview(main); window.contentView = root
        sidebar.wantsLayer = true; main.wantsLayer = true
        sidebar.layer?.backgroundColor = NSColor.clear.cgColor; main.layer?.backgroundColor = NSColor.clear.cgColor
        let originalChildren = [sidebar.subviews, main.subviews]
        let originalAccessibility = [sidebar.isAccessibilityElement(), main.isAccessibilityElement()]
        let originalFrames = [sidebar.frame, main.frame, button.frame]
        let originalTint = button.contentTintColor
        let originalAccent = NSColor.controlAccentColor
        var sampleCalls = 0, loadCalls = 0, loadCancels = 0, sampleCancels = 0
        var deferredSamples: [(ListThumbnailTintColor?) -> Void] = []
        var deferSampling = false
        let red = ListThumbnailTintColor(red: 1, green: 0, blue: 0)
        let blue = ListThumbnailTintColor(red: 0, green: 0, blue: 1)
        let controller = AppKitListBackgroundTint(sample: { _, done in
            sampleCalls += 1
            if deferSampling { deferredSamples.append(done) } else { done(red) }
            return { sampleCancels += 1 }
        }, displayOptions: { .init(allowsTint: true, reduceMotion: true) })
        controller.install(sidebar: sidebar, main: main)
        let roots: [NSView] = [sidebar, main]
        var appearanceDiagnostics: [String: Any] = [:]
        func components(_ view: NSView) -> [CGFloat] {
            guard let color = view.layer?.backgroundColor, let c = NSColor(cgColor: color)?.usingColorSpace(.deviceRGB) else { return [-1, -1, -1, -1] }
            return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent]
        }
        func recordAppearance(_ stage: String) {
            appearanceDiagnostics[stage] = roots.map { view in
                ["type": String(describing: type(of: view)), "rgba": components(view),
                 "appearance": view.effectiveAppearance.name.rawValue,
                 "layer": view.layer.map { String(describing: ObjectIdentifier($0)) } ?? "nil",
                 "frame": NSStringFromRect(view.frame)] as [String: Any]
            }
        }
        func isClear() -> Bool { roots.allSatisfy { components($0).last == 0 } }
        func freshHosts() -> (AppKitListTintSurface, AppKitListTintSurface) {
            let side = AppKitListTintSurface(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
            side.ignoresHitTesting = true
            let main = AppKitListTintSurface(frame: NSRect(x: 10, y: 0, width: 10, height: 10))
            side.wantsLayer = true; main.wantsLayer = true
            root.addSubview(side); root.addSubview(main)
            return (side, main)
        }
        let active = ListThumbnailTintSource()
        active.update(id: "sync") { done in loadCalls += 1; done(redImage); return { loadCancels += 1 } }
        controller.bind(active)
        check("hiddenWindowDoesNotLoad", sampleCalls == 0 && isClear())
        window.orderFront(nil); settle(); root.layoutSubtreeIfNeeded()
        recordAppearance("firstVisible")
        check("syncLoadAndSamplerComplete", sampleCalls == 1 && roots.allSatisfy { components($0)[0] > 0.98 && components($0)[3] > 0 })
        let beforeCached = sampleCalls
        controller.bind(active)
        check("sameRevisionUsesBoundedCache", sampleCalls == beforeCached)
        for index in 0..<25 {
            let additional = ListThumbnailTintSource()
            additional.update(id: "cache-\(index)") { done in done(redImage); return {} }
            controller.bind(additional)
        }
        let beforeEvicted = sampleCalls
        controller.bind(active)
        check("oldestRevisionIsEvictedFromBoundedCache", sampleCalls == beforeEvicted + 1)
        root.appearance = NSAppearance(named: .aqua); settle()
        recordAppearance("rootLight")
        let light = components(roots[0])
        root.appearance = NSAppearance(named: .darkAqua); settle()
        recordAppearance("rootDark")
        let dark = components(roots[0])
        root.appearance = NSAppearance(named: .aqua); settle()
        recordAppearance("rootLightRestored")
        check("nativeAppearanceAlphaAndRestore", abs(light[3] - 0.09) < 0.01 && abs(dark[3] - 0.12) < 0.01 && components(roots[0]) == light)
        let appearanceCounts = [loadCalls, sampleCalls, loadCancels, sampleCancels]
        let appearanceRevision = active.request?.revision
        sidebar.appearance = NSAppearance(named: .darkAqua); settle()
        recordAppearance("sidebarDark")
        check("sidebarOwnAppearanceReprojectsWithoutChangingMainAppearance", abs(components(sidebar)[3] - 0.12) < 0.01
            && abs(components(main)[3] - 0.09) < 0.01)
        sidebar.appearance = NSAppearance(named: .aqua)
        main.appearance = NSAppearance(named: .darkAqua); settle()
        recordAppearance("mainDark")
        check("mainOwnAppearanceReprojectsWithoutChangingSidebarAppearance", abs(components(main)[3] - 0.12) < 0.01
            && abs(components(sidebar)[3] - 0.09) < 0.01)
        sidebar.appearance = nil; main.appearance = nil; settle()
        recordAppearance("ownOverridesCleared")
        check("independentAppearanceChangesNeverReloadResampleOrRevokeCurrentSource", appearanceCounts == [loadCalls, sampleCalls, loadCancels, sampleCancels]
            && active.request?.revision == appearanceRevision && components(sidebar) == light && components(main) == light)
        check("passiveLayerPreservesLayout", [sidebar.frame, main.frame, button.frame] == originalFrames)
        check("passiveLayerPreservesHitAndAccessibility", root.hitTest(button.convert(button.bounds.center, to: root)) === button
            && [sidebar.subviews, main.subviews] == originalChildren
            && [sidebar.isAccessibilityElement(), main.isAccessibilityElement()] == originalAccessibility)
        check("noAddedSubviewsAndRootOpacityPreserved", [sidebar.subviews, main.subviews] == originalChildren
            && roots.allSatisfy { $0.alphaValue == 1 && $0.layer?.opacity == 1 })
        check("controlsRetainSystemAccent", button.contentTintColor == originalTint && NSColor.controlAccentColor == originalAccent)

        let beforeNativeMode = [loadCalls, sampleCalls]
        controller.setUsesThumbnailTint(false)
        active.invalidate()
        let nativeModeSource = ListThumbnailTintSource()
        nativeModeSource.update(id: "new-page-during-native") { done in
            loadCalls += 1; done(redImage); return { loadCancels += 1 }
        }
        controller.bind(nativeModeSource)
        check("nativeModeClearsTintAndDoesNotLoadOrSampleCurrentOrNewPage", isClear() && [loadCalls, sampleCalls] == beforeNativeMode)
        controller.setUsesThumbnailTint(true)
        check("returningToTintLoadsCurrentPageInsteadOfPreviousPage", [loadCalls, sampleCalls] == beforeNativeMode.map { $0 + 1 }
            && components(main)[0] > 0.98 && components(main)[3] > 0)
        let resumedWork = [loadCalls, sampleCalls, loadCancels, sampleCancels]
        controller.setUsesThumbnailTint(true)
        check("unchangedBackgroundStyleDoesNotRepeatWork", resumedWork == [loadCalls, sampleCalls, loadCancels, sampleCancels])
        controller.setUsesThumbnailTint(false); controller.setUsesThumbnailTint(true)
        check("returningToSameRevisionUsesExistingColorCache", resumedWork[0] == loadCalls && resumedWork[1] == sampleCalls && !isClear())
        deferSampling = true
        nativeModeSource.invalidate()
        let retiredModeSample = deferredSamples.removeLast(), cancelsBeforeNative = sampleCancels
        controller.setUsesThumbnailTint(false)
        retiredModeSample(blue)
        check("nativeModeCancelsAndRejectsLateColorReply", sampleCancels == cancelsBeforeNative + 1 && isClear())
        controller.setUsesThumbnailTint(true)
        let resumedModeSample = deferredSamples.removeLast()
        resumedModeSample(red)
        check("returningToTintAcceptsOnlyCurrentSample", components(main)[0] > 0.98 && components(main)[2] < 0.02)

        deferSampling = true
        let a = ListThumbnailTintSource(), b = ListThumbnailTintSource()
        var lateLoad: ((NSImage?) -> Void)?
        a.update(id: "A") { done in lateLoad = done; return { loadCancels += 1 } }
        b.update(id: "B") { done in done(redImage); return { loadCancels += 1 } }
        controller.bind(a); controller.bind(b)
        let bSample = deferredSamples.removeLast()
        let samplesBeforeLate = sampleCalls
        lateLoad?(redImage)
        check("lateLoaderCannotStartSampleAfterSourceSwitch", sampleCalls == samplesBeforeLate && isClear())
        bSample(blue)
        check("currentBPublishes", components(roots[1])[2] > 0.98)
        a.update(id: "A", assets: ["replacement"]) { done in done(redImage); return { loadCancels += 1 } }
        controller.bind(a)
        let oldSample = deferredSamples.removeLast()
        a.update(id: "A", assets: ["newer"]) { done in done(redImage); return { loadCancels += 1 } }
        let currentSample = deferredSamples.removeLast()
        oldSample(blue)
        check("sameIDAssetChangeRejectsLateSample", isClear())
        currentSample(red)
        let beforeInvalidate = sampleCalls
        a.invalidate()
        check("invalidateReopensImageAndSample", sampleCalls == beforeInvalidate + 1 && isClear())
        let invalidatedSample = deferredSamples.removeLast()
        window.orderOut(nil); settle()
        invalidatedSample(blue)
        check("hiddenWindowRejectsLateSampling", isClear())
        window.orderFront(nil); settle()
        check("visibleWindowResumesCurrentRevision", !deferredSamples.isEmpty)
        deferredSamples.removeLast()(nil)
        check("samplingFailureRemainsNeutral", isClear())
        a.update(id: "missing") { done in done(nil); return { loadCancels += 1 } }
        check("missingImageRemainsNeutral", isClear())
        a.update(id: nil)
        check("emptyListClearsTint", isClear())
        controller.bind(nil)
        check("replacementsCancelPreviousWork", loadCancels >= 5 && sampleCancels >= 3)
        let pending = ListThumbnailTintSource()
        var pendingLoadCancelled = 0, pendingSampleCancelled = 0
        pending.update(id: "pending-load") { _ in return { pendingLoadCancelled += 1 } }
        var loadOwner: AppKitListBackgroundTint? = AppKitListBackgroundTint(displayOptions: { .init(allowsTint: true, reduceMotion: true) })
        weak var weakLoadOwner = loadOwner
        let loadHosts = freshHosts()
        loadOwner?.install(sidebar: loadHosts.0, main: loadHosts.1); loadOwner?.bind(pending)
        loadOwner = nil
        check("ownerReleaseCancelsPendingLoad", weakLoadOwner == nil && pendingLoadCancelled == 1)
        pending.update(id: "pending-sample") { done in done(redImage); return {} }
        var sampleOwner: AppKitListBackgroundTint? = AppKitListBackgroundTint(sample: { _, _ in
            return { pendingSampleCancelled += 1 }
        }, displayOptions: { .init(allowsTint: true, reduceMotion: true) })
        weak var weakSampleOwner = sampleOwner
        let sampleHosts = freshHosts()
        sampleOwner?.install(sidebar: sampleHosts.0, main: sampleHosts.1); sampleOwner?.bind(pending)
        sampleOwner = nil
        check("ownerReleaseCancelsPendingSample", weakSampleOwner == nil && pendingSampleCancelled == 1)

        // Exercise the production workspace notification subscription with a
        // deterministic policy leaf, without changing the user's OS settings.
        var policyAllowsTint = false
        var policyLoads = 0, policyLoadCancels = 0, policySamples = 0, policySampleCancels = 0
        var policyLoad: ((NSImage?) -> Void)?
        var policyCompletions: [(ListThumbnailTintColor?) -> Void] = []
        let policySource = ListThumbnailTintSource()
        let policyOwner = AppKitListBackgroundTint(sample: { _, done in
            policySamples += 1; policyCompletions.append(done)
            return { policySampleCancels += 1 }
        }, displayOptions: { .init(allowsTint: policyAllowsTint, reduceMotion: true) })
        let policyHosts = freshHosts()
        policyOwner.install(sidebar: policyHosts.0, main: policyHosts.1)
        let policyRoots: [NSView] = [policyHosts.0, policyHosts.1]
        func policyIsClear() -> Bool { policyRoots.allSatisfy { components($0)[3] == 0 } }
        func notifyPolicyChange() {
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                object: NSWorkspace.shared)
            settle()
        }
        policySource.update(id: "policy-A") { done in
            policyLoads += 1; policyLoad = done
            return { policyLoadCancels += 1 }
        }
        policyOwner.bind(policySource)
        check("disabledPolicyDoesNotLoad", policyLoads == 0 && policySamples == 0 && policyIsClear())
        policyAllowsTint = true; notifyPolicyChange()
        check("workspaceNotificationStartsCurrentSource", policyLoads == 1 && policySamples == 0 && policyLoad != nil)
        policyAllowsTint = false; notifyPolicyChange()
        check("workspaceDisableCancelsPendingLoad", policyLoadCancels == 1 && policySamples == 0 && policyIsClear())
        policyLoad?(redImage)
        check("disabledPolicyRejectsLateLoad", policySamples == 0 && policyIsClear())
        policySource.update(id: "policy-B") { done in
            policyLoads += 1; done(redImage)
            return { policyLoadCancels += 1 }
        }
        check("disabledSourceChangeDoesNotLoad", policyLoads == 1 && policySamples == 0)
        policyAllowsTint = true; notifyPolicyChange()
        check("workspaceRestoreLoadsLatestSource", policyLoads == 2 && policySamples == 1)
        let policyLateSample = policyCompletions.removeLast()
        policyAllowsTint = false; notifyPolicyChange()
        check("workspaceDisableCancelsPendingSample", policyLoadCancels == 2 && policySampleCancels == 1 && policyIsClear())
        policyLateSample(blue)
        check("disabledPolicyRejectsLateSample", policyIsClear())
        policySource.update(id: "policy-C") { done in
            policyLoads += 1; done(redImage)
            return { policyLoadCancels += 1 }
        }
        check("disabledNewFirstItemStaysNeutral", policyLoads == 2 && policySamples == 1 && policyIsClear())
        policyAllowsTint = true; notifyPolicyChange()
        check("workspaceRestoreSamplesCurrentFirstItem", policyLoads == 3 && policySamples == 2)
        policyCompletions.removeLast()(red)
        check("restoredPolicyPublishesNativeFill", policyRoots.allSatisfy { components($0)[0] > 0.98 && components($0)[3] > 0 })
        policyAllowsTint = false; notifyPolicyChange()
        check("workspaceDisableClearsPublishedFill", policyIsClear())
        let samplesBeforePolicyCache = policySamples
        policyAllowsTint = true; notifyPolicyChange()
        check("workspaceRestoreProjectsCurrentCachedRevision", policySamples == samplesBeforePolicyCache
            && policyRoots.allSatisfy { components($0)[0] > 0.98 && components($0)[3] > 0 })
        policyOwner.bind(nil)

        let sheet = NSWindow(contentRect: NSRect(x: 14000, y: 14000, width: 220, height: 180),
            styleMask: [.titled], backing: .buffered, defer: false)
        sheet.isReleasedWhenClosed = false
        let sheetSurface = AppKitListTintSurface(frame: NSRect(x: 0, y: 0, width: 220, height: 180))
        sheetSurface.appearance = NSAppearance(named: .aqua)
        let sheetButton = NSButton(title: "原生控件", target: nil, action: nil)
        sheetButton.frame = NSRect(x: 20, y: 30, width: 100, height: 30)
        let secondRoot = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 180))
        let secondSidebar = AppKitListTintSurface(frame: NSRect(x: 0, y: 0, width: 80, height: 180))
        secondSidebar.appearance = NSAppearance(named: .aqua)
        sheetSurface.frame.origin.x = 80
        secondRoot.addSubview(secondSidebar); secondRoot.addSubview(sheetSurface)
        sheetSurface.addSubview(sheetButton); sheet.contentView = secondRoot
        let sheetChildren = sheetSurface.subviews, sheetButtonFrame = sheetButton.frame
        var sheetLoads = 0, sheetSampleCancels = 0
        var sheetSamples: [(ListThumbnailTintColor?) -> Void] = []
        let sheetOwner = AppKitListBackgroundTint(sample: { _, done in
            sheetSamples.append(done); return { sheetSampleCancels += 1 }
        }, displayOptions: { .init(allowsTint: true, reduceMotion: true) })
        sheetOwner.install(sidebar: secondSidebar, main: sheetSurface)
        let sheetSource = ListThumbnailTintSource()
        sheetSource.update(id: "second-window") { done in sheetLoads += 1; done(redImage); return {} }
        let sheetRevision = sheetSource.request?.revision
        sheetOwner.bind(sheetSource)
        check("secondWindowInstallCreatesNoPhantomSidebarOrContent", sheetSurface.subviews == sheetChildren
            && sheetButton.frame == sheetButtonFrame && sheetLoads == 0 && components(sheetSurface)[3] == 0)
        sheet.orderFront(nil); settle()
        check("secondWindowVisibilityLoadsTheOriginalBoundSource", sheetLoads == 1 && sheetSamples.count == 1
            && sheetSource.request?.revision == sheetRevision)
        sheetSamples.removeLast()(red)
        check("secondWindowProjectsSameLightTintWithoutChangingHitOrLayout", components(sheetSurface)[0] > 0.98
            && abs(components(sheetSurface)[3] - 0.09) < 0.01 && components(secondSidebar) == components(sheetSurface) && sheetSurface.subviews == sheetChildren
            && sheetButton.frame == sheetButtonFrame && secondRoot.hitTest(sheetButton.convert(sheetButton.bounds.center, to: secondRoot)) === sheetButton)
        window.orderOut(nil); settle()
        check("secondWindowLeaseDoesNotFollowAnotherWindowVisibility", components(sheetSurface)[0] > 0.98
            && sheetLoads == 1 && sheetSource.request?.revision == sheetRevision)
        sheetSource.invalidate()
        let sheetLateSample = sheetSamples.removeLast()
        let cancelsBeforeSheetHide = sheetSampleCancels
        sheet.orderOut(nil); settle(); sheetLateSample(blue)
        check("secondWindowHiddenWindowCancelsAndRejectsLateSample", sheetSampleCancels == cancelsBeforeSheetHide + 1
            && components(sheetSurface)[3] == 0 && components(secondSidebar)[3] == 0 && sheetSource.request?.revision != sheetRevision)
        sheetOwner.bind(nil); sheet.contentView = nil; sheet.close()
        window.orderFront(nil); settle()

        // The unmodified default policy must agree with this machine's current
        // NSWorkspace values; only the sampling leaf is recorded here.
        let workspace = NSWorkspace.shared
        let accessibilitySuppressesTint = workspace.accessibilityDisplayShouldReduceTransparency || workspace.accessibilityDisplayShouldIncreaseContrast
        var defaultLoads = 0, defaultSamples = 0
        let defaultSource = ListThumbnailTintSource()
        defaultSource.update(id: "default-policy") { done in defaultLoads += 1; done(redImage); return {} }
        let defaultOwner = AppKitListBackgroundTint(sample: { _, done in defaultSamples += 1; done(red); return {} })
        let defaultHosts = freshHosts()
        defaultOwner.install(sidebar: defaultHosts.0, main: defaultHosts.1); defaultOwner.bind(defaultSource)
        let defaultRoots: [NSView] = [defaultHosts.0, defaultHosts.1]
        check("defaultPolicyMatchesCurrentWorkspace", accessibilitySuppressesTint
            ? defaultLoads == 0 && defaultSamples == 0 && defaultRoots.allSatisfy { components($0)[3] == 0 }
            : defaultLoads == 1 && defaultSamples == 1 && defaultRoots.allSatisfy { components($0)[0] > 0.98 && components($0)[3] > 0 })
        let systemReducesMotion = workspace.accessibilityDisplayShouldReduceMotion
        check("defaultPolicyMatchesSystemReduceMotion", defaultRoots.allSatisfy {
            let animation = $0.layer?.animation(forKey: AppKitListBackgroundTint.animationKey)
            return accessibilitySuppressesTint || systemReducesMotion ? animation == nil : animation?.duration == 0.75
        })
        notifyPolicyChange()
        check("defaultPolicyNotificationPreservesCurrentSystemDecision", accessibilitySuppressesTint
            ? defaultLoads == 0 && defaultSamples == 0 && defaultRoots.allSatisfy { components($0)[3] == 0 }
            : defaultLoads == 1 && defaultSamples == 1 && defaultRoots.allSatisfy { components($0)[3] > 0 })
        defaultOwner.bind(nil)
        window.contentView = nil; window.close()
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: ["checks": checks,
            "accessibilitySuppressed": accessibilitySuppressesTint, "systemReducesMotion": systemReducesMotion,
            "appearanceDiagnostics": appearanceDiagnostics], options: [.sortedKeys]))
    }
}

private extension NSRect { var center: NSPoint { NSPoint(x: midX, y: midY) } }
