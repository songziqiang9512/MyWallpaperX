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
        removePointerEventMonitors()
        guard isVisible, isOutputActive else { return }
        guard launchContext?.sceneScriptCursorProgram.ownerCount ?? 0 > 0 else {
            return
        }
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
    }

    func removePointerEventMonitors() {
        userShortcutInput.revoke()
        if let localPointerEventMonitor {
            NSEvent.removeMonitor(localPointerEventMonitor)
            self.localPointerEventMonitor = nil
        }
        if let globalPointerEventMonitor {
            NSEvent.removeMonitor(globalPointerEventMonitor)
            self.globalPointerEventMonitor = nil
        }
    }

    private func capturePointerEvent(_ event: NSEvent) {
        guard isVisible, isOutputActive else { return }
#if DEBUG
        guard debugPointerOverride == nil else { return }
#endif
        let screenPoint = event.window?.convertPoint(
            toScreen: event.locationInWindow
        ) ?? NSEvent.mouseLocation
        let primaryButtonIsDown: Bool
        switch event.type {
        case .leftMouseDown:
            primaryButtonIsDown = true
        case .leftMouseUp:
            primaryButtonIsDown = false
        default:
            primaryButtonIsDown = NSEvent.pressedMouseButtons & 1 != 0
        }
        let hasNativeMainThreadIngress = Thread.isMainThread
        let publish = { [weak self] in
            guard let self else { return }
            guard self.isVisible, self.isOutputActive else { return }
            let timestamp = CACurrentMediaTime()
            let buttonEvent = event.type == .leftMouseDown || event.type == .leftMouseUp
            var admitsNativeAction = false
            if hasNativeMainThreadIngress, buttonEvent {
                let receiver = NSWindow.windowNumber(at: screenPoint, belowWindowWithWindowNumber: 0)
                admitsNativeAction = self.surfaces.values.contains { $0.window.windowNumber == receiver }
                    || PlaybackDesktopInputAdmission.allowsDesktopWindow(windowNumber: receiver)
            }
            let gestureID: UInt64?
            if admitsNativeAction {
                gestureID = self.userShortcutInput.receiveNativeButtonEvent(
                    down: event.type == .leftMouseDown, up: event.type == .leftMouseUp)
            } else {
                if buttonEvent { self.userShortcutInput.revoke() }
                gestureID = nil
            }
            let grant: ScenePlaybackShortcutGesture?
            if let gestureID, let requestID = self.launchRequestID, let context = self.launchContext {
                grant = .init(requestID: requestID,
                    configurationRevision: context.userShortcuts.revision, gestureID: gestureID)
            } else { grant = nil }
            for surface in surfaces.values {
                surface.metalView.recordSceneScriptPointerEvent(
                    screenPoint: screenPoint,
                    primaryButtonIsDown: primaryButtonIsDown,
                    timestamp: timestamp, nativeShortcutGesture: grant
                )
            }
        }
        if Thread.isMainThread {
            publish()
        } else {
            DispatchQueue.main.async(execute: publish)
        }
    }
}
