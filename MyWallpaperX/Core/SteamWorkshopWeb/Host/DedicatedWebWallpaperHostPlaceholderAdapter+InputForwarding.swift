//
//  DedicatedWebWallpaperHostPlaceholderAdapter+InputForwarding.swift
//  MyWallpaperX
//

import Foundation
import AppKit
import WebKit
import CoreGraphics

extension DedicatedWebWallpaperHostPlaceholderAdapter {
    func forwardPolledPointerLocationToWallpaper() {
        guard !surfaces.isEmpty else { return }

        let screenLocation = NSEvent.mouseLocation
        let buttonMask = Int(NSEvent.pressedMouseButtons)
        // Buttoned motion belongs to the admitted down/drag/up path below. Polling it would
        // let a drag that started in another app leak into the wallpaper after crossing desktop.
        guard buttonMask == 0 else {
            lastPassivePointerLocation = nil
            return
        }

        guard shouldForwardMouseEventToWallpaper(at: screenLocation),
              let destinationSurface = targetSurface(at: screenLocation) else {
            lastPassivePointerLocation = nil
            clearSyntheticHoverState()
            return
        }

        let normalizedPoint = normalizedPoint(for: screenLocation, in: destinationSurface)
        guard admitPassivePointerMove(normalizedPoint, to: destinationSurface) else { return }
        let script = String(
            format: "window.__myWallpaperSetPassiveMouseState(true, %.6f, %.6f, %d); window.__myWallpaperDispatchMouseEvent('pointermove', %.6f, %.6f, 0, %d, 1);",
            normalizedPoint.x,
            normalizedPoint.y,
            buttonMask,
            normalizedPoint.x,
            normalizedPoint.y,
            buttonMask
        )
        destinationSurface.webView.evaluateJavaScript(script, completionHandler: nil)
        lastHoveredScreenID = destinationSurface.screenID
    }

    func clearSyntheticHoverState() {
        lastPassivePointerLocation = nil
        if let lastHoveredScreenID,
           let previousSurface = surfaces[lastHoveredScreenID] {
            previousSurface.webView.evaluateJavaScript(
                "window.__myWallpaperSetPassiveMouseState(false, 0, 0, 0);",
                completionHandler: nil
            )
        }
        lastHoveredScreenID = nil
    }

    /// Both native events and the polling fallback publish passive positions.
    /// Hit testing and event preheat run before this deduplication; a stationary
    /// pointer still clears hover when another window covers the desktop.
    func admitPassivePointerMove(_ point: CGPoint, to surface: HostSurface) -> Bool {
        let frame = surface.window.screen?.frame ?? surface.window.frame
        if let previous = lastPassivePointerLocation, previous.surfaceID == surface.id,
           hypot((point.x - previous.normalizedPoint.x) * max(frame.width, 1),
                 (point.y - previous.normalizedPoint.y) * max(frame.height, 1)) < 0.5 {
            return false
        }
        lastPassivePointerLocation = (surface.id, point)
        return true
    }

    func forwardMouseEventToWallpaper(_ event: NSEvent) {
        guard !surfaces.isEmpty else { return }
        if event.type == .mouseMoved {
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastPointerMoveForwardedAt >= Self.pointerMoveThrottleInterval else { return }
            lastPointerMoveForwardedAt = now
        } else if isStartupClickEvent(event),
                  isWithinActiveClickWarmup {
            return
        }
        let screenLocation: NSPoint
        if let sourceWindow = event.window {
            let windowPoint = event.locationInWindow
            screenLocation = sourceWindow.convertPoint(toScreen: windowPoint)
        } else {
            screenLocation = event.locationInWindow
        }

        guard let destinationSurface = destinationSurfaceForMouseEvent(
            event,
            screenLocation: screenLocation
        ) else {
            clearSyntheticHoverState()
            return
        }

        if let lastHoveredScreenID,
           destinationSurface.screenID != lastHoveredScreenID,
           let previousSurface = surfaces[lastHoveredScreenID] {
            previousSurface.webView.evaluateJavaScript(
                "window.__myWallpaperSetPassiveMouseState(false, 0, 0, 0);",
                completionHandler: nil
            )
        }

        let normalizedPoint = normalizedPoint(for: screenLocation, in: destinationSurface)
        let interactionRegion = interactiveRegionHit(
            normalizedX: normalizedPoint.x,
            normalizedY: normalizedPoint.y,
            screenID: destinationSurface.screenID
        )
        let preheatedRegion = interactiveRegionPreheatHit(
            normalizedX: normalizedPoint.x,
            normalizedY: normalizedPoint.y,
            screenID: destinationSurface.screenID
        )

        if event.type == .mouseMoved {
            updateHoverPreheat(
                for: destinationSurface,
                preheatedRegion: preheatedRegion,
                normalizedPoint: normalizedPoint
            )
        }

        if shouldHandleViaTransientCapture(event, interactionRegion: interactionRegion) {
            handleTransientCaptureEvent(
                event,
                on: destinationSurface,
                normalizedPoint: normalizedPoint
            )
        } else {
            forwardPassiveMouseEvent(
                event,
                to: destinationSurface,
                normalizedPoint: normalizedPoint
            )
        }

        lastHoveredScreenID = destinationSurface.screenID

        if isDesktopGestureEnd(event),
           let buttonNumber = desktopGestureButtonNumber(for: event) {
            admittedDesktopGestureScreenByButton.removeValue(forKey: buttonNumber)
        }
    }

    func destinationSurfaceForMouseEvent(_ event: NSEvent, screenLocation: NSPoint) -> HostSurface? {
        if let buttonNumber = desktopGestureButtonNumber(for: event) {
            if isDesktopGestureStart(event) {
                admittedDesktopGestureScreenByButton.removeValue(forKey: buttonNumber)
                // Gesture ownership is decided only at mouse-down. A drag that began in another
                // app is never admitted later merely because the pointer reaches bare desktop.
                guard shouldForwardMouseEventToWallpaper(at: screenLocation),
                      let surface = targetSurface(at: screenLocation) else {
                    return nil
                }
                admittedDesktopGestureScreenByButton[buttonNumber] = surface.screenID
                return surface
            }

            if isDesktopGestureContinuation(event) {
                guard let screenID = admittedDesktopGestureScreenByButton[buttonNumber],
                      let surface = surfaces[screenID] else {
                    admittedDesktopGestureScreenByButton.removeValue(forKey: buttonNumber)
                    return nil
                }
                return surface
            }
        }

        guard shouldForwardMouseEventToWallpaper(at: screenLocation) else { return nil }
        return targetSurface(at: screenLocation)
    }

    func desktopGestureButtonNumber(for event: NSEvent) -> Int? {
        switch event.type {
        case .leftMouseDown, .leftMouseDragged, .leftMouseUp:
            return 0
        case .rightMouseDown, .rightMouseDragged, .rightMouseUp:
            return 1
        case .otherMouseDown, .otherMouseDragged, .otherMouseUp:
            return max(2, Int(event.buttonNumber))
        default:
            return nil
        }
    }

    func isDesktopGestureStart(_ event: NSEvent) -> Bool {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return true
        default:
            return false
        }
    }

    func isDesktopGestureContinuation(_ event: NSEvent) -> Bool {
        switch event.type {
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
             .leftMouseUp, .rightMouseUp, .otherMouseUp:
            return true
        default:
            return false
        }
    }

    func isDesktopGestureEnd(_ event: NSEvent) -> Bool {
        switch event.type {
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            return true
        default:
            return false
        }
    }

    func cancelAdmittedDesktopGestures(for screenID: CGDirectDisplayID? = nil) {
        let gestures = admittedDesktopGestureScreenByButton.filter { _, gestureScreenID in
            screenID == nil || gestureScreenID == screenID
        }
        guard !gestures.isEmpty else { return }

        for buttonNumber in gestures.keys {
            admittedDesktopGestureScreenByButton.removeValue(forKey: buttonNumber)
        }
        for (buttonNumber, gestureScreenID) in gestures {
            guard let surface = surfaces[gestureScreenID] else { continue }
            let normalizedPoint = normalizedPoint(for: NSEvent.mouseLocation, in: surface)
            let pointerID = buttonNumber == 0 ? 1 : buttonNumber + 1
            let domButton = buttonNumber == 1 ? 2 : buttonNumber
            let script = String(
                format: "window.__myWallpaperDispatchMouseEvent('pointercancel', %.6f, %.6f, %d, 0, %d);",
                normalizedPoint.x,
                normalizedPoint.y,
                domButton,
                pointerID
            )
            surface.webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }

    func shouldHandleViaTransientCapture(_ event: NSEvent, interactionRegion: InteractiveRegion?) -> Bool {
        guard let interactionRegion else { return false }
        switch event.type {
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
            return interactionRegion.allowsClick
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return interactionRegion.allowsDrag || transientCaptureActiveScreenID != nil
        default:
            return false
        }
    }

    var isWithinActiveClickWarmup: Bool {
        guard let activeInputForwardingStartedAt else { return false }
        return ProcessInfo.processInfo.systemUptime - activeInputForwardingStartedAt < Self.activeClickWarmupDuration
    }

    func isStartupClickEvent(_ event: NSEvent) -> Bool {
        switch event.type {
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
             .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return true
        default:
            return false
        }
    }

    func updateHoverPreheat(
        for surface: HostSurface,
        preheatedRegion: InteractiveRegion?,
        normalizedPoint: CGPoint
    ) {
        let nextRegionID = preheatedRegion?.id
        if lastPreheatedRegionIDByScreen[surface.screenID] != nextRegionID {
            lastPreheatedRegionIDByScreen[surface.screenID] = nextRegionID
        }

        guard let preheatedRegion else {
            if transientCaptureActiveScreenID == surface.screenID {
                scheduleTransientMouseCaptureRelease(for: surface.screenID, delay: Self.transientCaptureDuration)
            }
            return
        }

        if preheatedRegion.allowsClick || preheatedRegion.allowsDrag {
            beginTransientMouseCapture(for: surface)
            scheduleTransientMouseCaptureRelease(for: surface.screenID, delay: Self.transientCaptureDuration)
        }
    }

    func handleTransientCaptureEvent(
        _ event: NSEvent,
        on surface: HostSurface,
        normalizedPoint: CGPoint
    ) {
        beginTransientMouseCapture(for: surface)
        forwardPassiveMouseEvent(event, to: surface, normalizedPoint: normalizedPoint)
        let releaseDelay: TimeInterval
        switch event.type {
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            releaseDelay = Self.dragCaptureDuration
        default:
            releaseDelay = Self.transientCaptureDuration
        }
        scheduleTransientMouseCaptureRelease(for: surface.screenID, delay: releaseDelay)
    }

    func forwardPassiveMouseEvent(
        _ event: NSEvent,
        to targetSurface: HostSurface,
        normalizedPoint: CGPoint
    ) {
        let normalizedX = normalizedPoint.x
        let normalizedY = normalizedPoint.y
        let buttonMask = eventButtonMask(event)
        let eventType = domMouseEventType(for: event)
        let button = domMouseButton(for: event)
        let pointerID = pointerIdentifier(for: event)
        if event.type == .mouseMoved, buttonMask == 0,
           !admitPassivePointerMove(normalizedPoint, to: targetSurface) { return }
        let script: String
        if let eventType {
            if eventType == "wheel" {
                script = String(
                    format: "window.__myWallpaperSetPassiveMouseState(true, %.6f, %.6f, %d); window.__myWallpaperDispatchWheelEvent(%.6f, %.6f, %.6f, %.6f, %d);",
                    normalizedX,
                    normalizedY,
                    buttonMask,
                    normalizedX,
                    normalizedY,
                    event.scrollingDeltaX,
                    event.scrollingDeltaY,
                    buttonMask
                )
            } else {
                script = String(
                    format: "window.__myWallpaperSetPassiveMouseState(true, %.6f, %.6f, %d); window.__myWallpaperDispatchMouseEvent('%@', %.6f, %.6f, %d, %d, %d);",
                    normalizedX,
                    normalizedY,
                    buttonMask,
                    eventType,
                    normalizedX,
                    normalizedY,
                    button,
                    buttonMask,
                    pointerID
                )
            }
        } else {
            script = String(
                format: "window.__myWallpaperSetPassiveMouseState(true, %.6f, %.6f, %d);",
                normalizedX,
                normalizedY,
                buttonMask
            )
        }
        targetSurface.webView.evaluateJavaScript(script, completionHandler: nil)
    }

    func eventButtonMask(_ event: NSEvent) -> Int {
        let pressedButtons = Int(NSEvent.pressedMouseButtons)
        switch event.type {
        case .leftMouseDown:
            return pressedButtons | 1
        case .rightMouseDown:
            return pressedButtons | 2
        case .otherMouseDown:
            let buttonNumber = max(0, Int(event.buttonNumber))
            let buttonMask = buttonNumber < Int.bitWidth ? (1 << buttonNumber) : 0
            return pressedButtons | buttonMask
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .leftMouseUp, .rightMouseUp, .otherMouseUp, .mouseMoved, .scrollWheel:
            return pressedButtons
        default:
            return pressedButtons
        }
    }

    func domMouseEventType(for event: NSEvent) -> String? {
        switch event.type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return "pointermove"
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return "pointerdown"
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            return "pointerup"
        case .scrollWheel:
            return "wheel"
        default:
            return nil
        }
    }

    func pointerIdentifier(for event: NSEvent) -> Int {
        switch event.type {
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
            return 2
        case .otherMouseDown, .otherMouseUp, .otherMouseDragged:
            return max(1, Int(event.buttonNumber) + 1)
        default:
            return 1
        }
    }

    func domMouseButton(for event: NSEvent) -> Int {
        switch event.type {
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
            return 2
        case .otherMouseDown, .otherMouseUp, .otherMouseDragged:
            return max(1, Int(event.buttonNumber))
        default:
            return 0
        }
    }
}
