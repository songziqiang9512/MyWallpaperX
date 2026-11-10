import AppKit
import QuartzCore

extension SceneDesktopWallpaperSession {
    func updateMouseLocations() {
#if DEBUG
        if let debugPointerOverride {
            let timestamp = CACurrentMediaTime()
            surfaces.values.forEach {
                $0.metalView.applyPointerInput(debugPointerOverride, timestamp: timestamp)
            }
            return
        }
#endif
        let mouseLocation = NSEvent.mouseLocation
        surfaces.values.forEach {
            $0.metalView.updateMouseLocationInScreen(mouseLocation)
        }
    }

    func installPointerEventMonitorsIfNeeded() {
        let needsMonitors = isVisible && isOutputActive && launchContext.map { context in
            context.sceneScriptCursorProgram.hasActiveOwners(excludingTargets:
                context.propertyVectorScriptProgram.disabledTargets
                    .union(context.sceneScriptScalarProgram.disabledTargets)
                    .union(context.sceneScriptStringProgram.disabledTargets))
        } == true
        guard needsMonitors else {
            if localPointerEventMonitor != nil || globalPointerEventMonitor != nil { removePointerEventMonitors() }
            return
        }
        guard localPointerEventMonitor == nil && globalPointerEventMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp,
        ]
        localPointerEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: mask
        ) { [weak self] event in
            self?.capturePointerEvent(event)
            return event
        }
        globalPointerEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: mask
        ) { [weak self] event in
            self?.capturePointerEvent(event)
        }
#if DEBUG
        if SceneDesktopWallpaperHost.usesDebugEvidenceWindow {
            NSLog("MWX DEBUG SCENE: phase=pointer-monitors request=%@ session=%@ installed=%d",
                  launchRequestID?.uuidString ?? "none", lifecycleID.uuidString,
                  (localPointerEventMonitor == nil ? 0 : 1) + (globalPointerEventMonitor == nil ? 0 : 1))
        }
        guard debugPointerOverride == nil else { return }
#endif
        if localPointerEventMonitor != nil || globalPointerEventMonitor != nil {
            launchContext?.sceneScriptCursorProgram.retirePrimaryButtonStream()
        }
    }

    func removePointerEventMonitors() {
        userShortcutInput.revoke()
        guard localPointerEventMonitor != nil || globalPointerEventMonitor != nil else { return }
        if let localPointerEventMonitor {
            NSEvent.removeMonitor(localPointerEventMonitor)
            self.localPointerEventMonitor = nil
        }
        if let globalPointerEventMonitor {
            NSEvent.removeMonitor(globalPointerEventMonitor)
            self.globalPointerEventMonitor = nil
        }
        for surface in surfaces.values {
            _ = surface.metalView.drainSceneScriptPointerEvents()
        }
        launchContext?.sceneScriptCursorProgram.retirePrimaryButtonStream()
#if DEBUG
        if SceneDesktopWallpaperHost.usesDebugEvidenceWindow {
            NSLog("MWX DEBUG SCENE: phase=pointer-monitors request=%@ session=%@ installed=0",
                  launchRequestID?.uuidString ?? "none", lifecycleID.uuidString)
        }
#endif
    }

    private func capturePointerEvent(_ event: NSEvent) {
        guard isVisible, isOutputActive else { return }
#if DEBUG
        guard debugPointerOverride == nil else { return }
#endif
        let eventPoint = event.locationInWindow
        let screenPoint = event.window?.convertPoint(toScreen: eventPoint) ?? eventPoint
        let type = event.type
        let buttonEvent = type == .leftMouseDown || type == .leftMouseUp
        let timestamp = CACurrentMediaTime()
        var grant: ScenePlaybackShortcutGesture?
        if buttonEvent {
            let receiver = NSWindow.windowNumber(at: screenPoint, belowWindowWithWindowNumber: 0)
            if surfaces.values.contains(where: { $0.window.windowNumber == receiver })
                || PlaybackDesktopInputAdmission.allowsDesktopWindow(windowNumber: receiver) {
                if let gestureID = userShortcutInput.receiveNativeButtonEvent(
                    down: type == .leftMouseDown, up: type == .leftMouseUp),
                   let requestID = launchRequestID, let context = launchContext {
                    grant = .init(requestID: requestID,
                        configurationRevision: context.userShortcuts.revision, gestureID: gestureID)
                }
            } else {
                userShortcutInput.revoke()
            }
        }
        for surface in surfaces.values {
            surface.metalView.recordSceneScriptPointerEvent(
                screenPoint: screenPoint,
                primaryButtonIsDown: type == .leftMouseDown || type == .leftMouseDragged,
                hasPrimaryButtonEdge: buttonEvent,
                timestamp: timestamp, nativeShortcutGesture: grant
            )
        }
    }
}
