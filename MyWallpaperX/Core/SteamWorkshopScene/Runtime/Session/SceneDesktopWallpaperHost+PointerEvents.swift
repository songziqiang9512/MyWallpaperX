import AppKit
import QuartzCore

extension SceneDesktopWallpaperHost {
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
        let publish = { [weak self] in
            guard let self else { return }
            let timestamp = CACurrentMediaTime()
            for surface in surfaces.values {
                surface.metalView.recordSceneScriptPointerEvent(
                    screenPoint: screenPoint,
                    primaryButtonIsDown: primaryButtonIsDown,
                    timestamp: timestamp
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
