import AppKit
import QuartzCore

// Actual shared grid + actual downloaded card. Only App actions are recording
// leaves; native selection, click recognition, hit testing and controls run whole.
@MainActor final class PixabayDownloadsClickOwner {
    let reference = WallpaperReference(provider: .pixabay, sourceID: "901")
    var selection = WallpaperLibrarySelectionState()
    var played: [Int] = [], inspected: [WallpaperReference] = []
    var selectionEvents = 0
    var isPlaying = true
    lazy var controller: WallpaperLibraryGridController = {
        let result = WallpaperLibraryGridController { [weak self] collection, path, _, state in
            let card = collection.makeItem(withIdentifier: AppKitPixabayDownloadsItem.reuseIdentifier, for: path) as! AppKitPixabayDownloadsItem
            card.onPrimaryAction = { [weak self] in self?.played.append($0) }
            card.configure(entry: downloadModel(901), isSelected: state.isSelected, isMultiSelectMode: state.isSelecting, isPlaying: self?.isPlaying ?? false)
            return card
        }
        result.loadViewIfNeeded()
        result.collection.register(AppKitPixabayDownloadsItem.self, forItemWithIdentifier: AppKitPixabayDownloadsItem.reuseIdentifier)
        result.onSelection = { [weak self] refs, focus in
            guard let self else { return nil }
            if self.selection.references != refs || self.selection.focusedReference != focus { self.selection.sessionID = UUID() }
            self.selection.references = refs; self.selection.focusedReference = focus; self.selectionEvents += 1
            return self.selection.sessionID
        }
        result.onInspect = { [weak self] in self?.inspected.append($0.reference) }
        result.opensDetailsOnSingleClick = { true }
        result.updateCell = { cell, _, state in
            (cell as? AppKitPixabayDownloadsItem)?.applySelectionState(state.isSelected, multiSelectMode: state.isSelecting)
        }
        return result
    }()
    func update(selecting: Bool = false) {
        selection.isSelecting = selecting
        let value = WallpaperContentItem(reference: reference, providerReference: reference,
            locator: .init(mediaKind: .video), title: "download 901", kind: .video,
            publishedAvailability: .available, capabilities: [.play, .organize, .inspect], metadata: .init(),
            acquisition: .idle, update: .idle, aliases: [])
        controller.update(page: .downloads, items: [value], selection: selection, preferredColumns: 5, permitsDragging: false, scrollAnchor: nil)
    }
}

@MainActor func pixabayNativeClickOwner(_ facts: Facts) {
    let owner = PixabayDownloadsClickOwner()
    let controller = owner.controller
    let window = CardWindow(contentViewController: controller)
    window.testBackingScale = (NSScreen.main ?? NSScreen.screens.first)?.backingScaleFactor ?? 1
    window.setFrame(NSRect(x: 14000, y: 14000, width: 320, height: 360), display: false)
    window.isReleasedWhenClosed = false
    owner.update()
    window.orderFrontRegardless(); window.makeKey()
    controller.view.layoutSubtreeIfNeeded(); pump(0.04)
    defer { window.orderOut(nil); window.close() }
    guard let card = controller.collection.item(at: IndexPath(item: 0, section: 0)) as? AppKitPixabayDownloadsItem else {
        facts.expect("real-click-card-is-registered", false); return
    }
    layout(card)
    guard let bar = card.controlBar else { facts.expect("click-bar-is-mounted", false); return }
    bar.layoutSubtreeIfNeeded()
    func mouse(_ type: NSEvent.EventType, at point: NSPoint, count: Int = 1) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime + (type == .leftMouseUp ? 0.01 : 0),
            windowNumber: window.windowNumber, context: nil, eventNumber: type == .leftMouseUp ? 3 : 2,
            clickCount: count, pressure: type == .leftMouseUp ? 0 : 1)!
    }
    func click(_ point: NSPoint, count: Int = 1) {
        let down = mouse(.leftMouseDown, at: point, count: count)
        let up = mouse(.leftMouseUp, at: point, count: count)
        NSApp.postEvent(up, atStart: true); window.sendEvent(down); pump(0.02)
    }
    let button = bar.playButton
    let center = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
    let hitCenter = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: card.view.superview)
    facts.expect("real-window-primary-hit-is-native-button", card.view.hitTest(hitCenter) === button)
    click(center)
    facts.expect("native-button-click-plays-exactly-once-without-selecting-or-inspector", owner.played == [901]
        && owner.selection.references.isEmpty && owner.selectionEvents == 0 && owner.inspected.isEmpty)
    let beside = button.convert(NSPoint(x: button.bounds.minX - 4, y: button.bounds.midY), to: nil)
    let hitBeside = button.convert(NSPoint(x: button.bounds.minX - 4, y: button.bounds.midY), to: card.view.superview)
    facts.expect("old-expanded-button-neighbor-is-not-button", card.view.hitTest(hitBeside) !== button)
    click(beside)
    facts.expect("button-neighbor-only-selects-and-opens-details", owner.played == [901]
        && owner.selection.references == [owner.reference] && owner.selection.focusedReference == owner.reference
        && owner.inspected == [owner.reference])
    let cover = card.imageContainer.convert(NSPoint(x: 100, y: 140), to: nil)
    click(cover)
    facts.expect("cover-only-reopens-details-without-playing", owner.played == [901]
        && owner.inspected == [owner.reference, owner.reference])
    owner.update(selecting: true)
    click(cover)
    facts.expect("multi-selection-cover-toggles-without-playing-or-details", owner.selection.references.isEmpty
        && owner.played == [901] && owner.inspected == [owner.reference, owner.reference])
    owner.update(selecting: false)
    card.onInspectRequested = { _ in owner.inspected.append(owner.reference) }
    layout(card); bar.layoutSubtreeIfNeeded()
    let hoverPoint = card.imageContainer.convert(NSPoint(x: card.imageContainer.bounds.midX,
        y: card.imageContainer.bounds.midY), to: nil)
    window.testPointer = hoverPoint
    for (name, target, edge, count) in [
        ("play-center-first", bar.playButton, false, 1),
        ("play-center-double", bar.playButton, false, 2),
        ("detail-center-first", bar.detailButton, false, 1),
        ("detail-center-double", bar.detailButton, false, 2),
        ("play-visual-outer-edge", bar.playButton, true, 1),
        ("play-visual-outer-edge-double", bar.playButton, true, 2),
        ("detail-visual-outer-edge", bar.detailButton, true, 1),
        ("detail-visual-outer-edge-double", bar.detailButton, true, 2)
    ] {
        card.mouseMoved(with: NSEvent.mouseEvent(with: .mouseMoved, location: hoverPoint, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 10, clickCount: 0, pressure: 0)!)
        pump(0.22)
        guard let layer = card.imageContainer.layer else {
            facts.expect(name + "-has-native-layer", false); continue
        }
        guard let shown = layer.presentation(), let shownBar = bar.layer?.presentation(),
              let shownCard = card.view.layer?.presentation() else {
            facts.expect(name + "-has-presentation-layers", false); continue
        }
        facts.expect(name + "-steady-hover-is-actually-expanded", card.isHovering
            && abs(layer.transform.m11 - 1.025) < 0.0001 && abs(shown.transform.m11 - 1.025) < 0.0001)
        let local = NSPoint(x: edge ? (target === bar.playButton ? target.bounds.maxX - 0.25 : target.bounds.minX + 0.25)
            : target.bounds.midX, y: target.bounds.midY)
        let inBar = bar.convert(local, from: target)
        let inCard = card.view.convertFromLayer(shownBar.convert(bar.convertToLayer(inBar), to: shownCard))
        let point = card.view.convert(inCard, to: nil)
        let content = window.contentView!
        let hit = content.hitTest(content.superview!.convert(point, from: nil))
        let before = (owner.played.count, owner.inspected.count, owner.selectionEvents)
        click(point, count: count)
        let after = (owner.played.count, owner.inspected.count, owner.selectionEvents)
        let detail = "active=\(NSApp.isActive) key=\(window.isKeyWindow) visible=\(window.isVisible) scale=\(shown.transform.m11) nativeHit=\(String(describing: hit)) point=\(point) callbackDelta=\(after.0-before.0),\(after.1-before.1),\(after.2-before.2)"
        facts.expect(name + "-enters-native-button", hit === target, detail)
        facts.expect(name + "-dispatches-once-without-cover-selection",
            after.0 - before.0 == (target === bar.playButton ? 1 : 0)
            && after.1 - before.1 == (target === bar.detailButton ? 1 : 0) && after.2 == before.2, detail)
        FileHandle.standardError.write(Data((name + " " + detail + "\n").utf8))
    }

    owner.isPlaying = false
    card.applyPlayingState(isPlaying: false)
    let originalPlay = bar.onPlay, originalInspect = bar.onInspect
    var playEntries = 0, inspectEntries = 0
    bar.onPlay = { playEntries += 1; originalPlay?() }
    bar.onInspect = { inspectEntries += 1; originalInspect?() }
    func nativeHit(_ point: NSPoint) -> NSView? {
        let content = window.contentView!
        return content.hitTest(content.superview!.convert(point, from: nil))
    }
    func controlState(_ target: NSButton, point: NSPoint) -> [String: Any] {
        let hit = nativeHit(point)
        return ["active": NSApp.isActive, "key": window.isKeyWindow, "windowVisible": window.isVisible,
         "sheetAttached": window.attachedSheet != nil, "modalWindow": NSApp.modalWindow != nil,
         "pointer": NSStringFromPoint(window.testPointer), "pointerInsideCard": card.view.isGridPointerInside,
         "hovering": card.isHovering, "playing": card.isPlaying, "switching": card.isSwitching,
         "barMounted": bar.superview != nil, "barHidden": bar.isHidden, "barAlpha": bar.alphaValue,
         "buttonEnabled": target.isEnabled, "buttonHighlighted": target.cell?.isHighlighted == true,
         "buttonWindowRect": NSStringFromRect(target.convert(target.bounds, to: nil)),
         "nativeHit": String(describing: hit), "nativeHitIsTarget": hit === target]
    }
    for (name, target, updatesLayout) in [
        ("unplayed-play-center", bar.playButton, false),
        ("unplayed-detail-center", bar.detailButton, false),
        ("unplayed-play-center-during-stable-layout", bar.playButton, true),
        ("unplayed-detail-center-during-stable-layout", bar.detailButton, true)
    ] {
        let point = target.convert(NSPoint(x: target.bounds.midX, y: target.bounds.midY), to: nil)
        window.testPointer = point
        card.mouseMoved(with: NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 10, clickCount: 0, pressure: 0)!)
        pump(0.02)
        let before = controlState(target, point: point), frame = target.convert(target.bounds, to: nil)
        let entryBefore = (playEntries, inspectEntries)
        let businessBefore = (owner.played.count, owner.inspected.count, owner.selectionEvents)
        var returned = false, timerFired = false, insideDown = false, upPosted = false, upObservedByApp = false
        var releaseHost: Double?, observedUpHost: Double?
        var tracked: [String: Any] = [:]
        let upMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { event in
            MainActor.assumeIsolated {
                if event.windowNumber == window.windowNumber, event.eventNumber == 3, event.locationInWindow == point {
                    upObservedByApp = true; observedUpHost = ProcessInfo.processInfo.systemUptime
                }
                return event
            }
        }
        let downHost = ProcessInfo.processInfo.systemUptime
        let release = Timer(timeInterval: 0.04, repeats: false) { _ in
            MainActor.assumeIsolated {
                timerFired = true; insideDown = !returned
                releaseHost = ProcessInfo.processInfo.systemUptime
                tracked["beforeUpdate"] = controlState(target, point: point)
                tracked["runLoopMode"] = RunLoop.current.currentMode?.rawValue ?? "nil"
                if updatesLayout {
                    card.view.needsLayout = true
                    owner.update(selecting: false)
                    card.view.layoutSubtreeIfNeeded()
                }
                tracked["afterUpdate"] = controlState(target, point: point)
                NSApp.postEvent(mouse(.leftMouseUp, at: point), atStart: false)
                upPosted = true
            }
        }
        RunLoop.main.add(release, forMode: .default)
        RunLoop.main.add(release, forMode: .eventTracking)
        window.sendEvent(mouse(.leftMouseDown, at: point))
        returned = true; pump(0.09); release.invalidate()
        if let upMonitor { NSEvent.removeMonitor(upMonitor) }
        let entries = [playEntries - entryBefore.0, inspectEntries - entryBefore.1]
        let business = [owner.played.count - businessBefore.0, owner.inspected.count - businessBefore.1,
                        owner.selectionEvents - businessBefore.2]
        let after = controlState(target, point: point)
        let receipt: [String: Any] = ["case": name, "updatesLayout": updatesLayout,
            "point": NSStringFromPoint(point), "before": before, "tracking": tracked, "after": after,
            "timerFired": timerFired, "timerInsideMouseDown": insideDown,
            "downHost": downHost, "releaseHost": releaseHost as Any? ?? NSNull(),
            "observedUpHost": observedUpHost as Any? ?? NSNull(),
            "heldSeconds": releaseHost.map { $0 - downHost } as Any? ?? NSNull(),
            "mouseUpPosted": upPosted, "mouseUpObservedByApp": upObservedByApp,
            "controlEntryDeltaPlayDetail": entries, "businessDeltaPlayDetailSelection": business,
            "inputScope": "controlled window pointer and synthetic NSEvent down/up; no physical HID or forced pointer exit/disable/removal"]
        let encoded = try! JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys])
        let detail = String(decoding: encoded, as: UTF8.self)
        facts.expect(name + "-starts-as-an-enabled-hover-only-native-button", before["active"] as? Bool == true
            && before["key"] as? Bool == true && before["playing"] as? Bool == false
            && before["switching"] as? Bool == false && before["hovering"] as? Bool == true
            && before["barMounted"] as? Bool == true && before["barHidden"] as? Bool == false
            && before["nativeHitIsTarget"] as? Bool == true && before["buttonEnabled"] as? Bool == true, detail)
        let heldState = tracked["beforeUpdate"] as? [String: Any]
        facts.expect(name + "-held-release-is-posted-and-observed-by-the-app", timerFired && upPosted && upObservedByApp
            && heldState?["buttonHighlighted"] as? Bool == true
            && heldState?["buttonWindowRect"] as? String == NSStringFromRect(frame)
            && heldState?["nativeHitIsTarget"] as? Bool == true
            && (releaseHost.map { $0 - downHost } ?? 0) >= 0.04, detail)
        facts.expect(name + "-same-control-keeps-current-geometry-and-admission", card.controlBar === bar
            && frame == target.convert(target.bounds, to: nil) && target.isEnabled
            && bar.superview != nil && !bar.isHidden && nativeHit(point) === target, detail)
        facts.expect(name + "-enters-only-the-expected-control-callback", entries == (target === bar.playButton ? [1, 0] : [0, 1]), detail)
        facts.expect(name + "-delivers-only-the-current-business-action", business == (target === bar.playButton ? [1, 0, 0] : [0, 1, 0]), detail)
        FileHandle.standardError.write(encoded + Data("\n".utf8))
    }
}
