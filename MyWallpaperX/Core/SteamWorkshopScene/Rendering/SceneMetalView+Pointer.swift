import AppKit
import QuartzCore

extension SceneMetalView {
    func configurePointerTracking() {
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInActiveApp, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    func handlePointerEvent(_ event: NSEvent) {
        updatePointer(event.locationInWindow)
    }

    func handlePointerExit() {
        setPointerOutside()
    }

    func updateMouseLocationInScreen(_ screenPoint: CGPoint) {
        guard let window else {
            setPointerOutside()
            return
        }
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        updatePointer(windowPoint)
    }

    func applyPointerState(_ state: SceneSurfacePointerState) {
        let previousState = pointerState
        pointerState = state
        pointerState.sceneScriptCurrent = state.current
        pointerState.sceneScriptPrimaryButtonIsDown = state.isPrimaryButtonDown
        if previousState.sceneScriptCurrent != state.current
            || previousState.isInside != state.isInside
            || previousState.sceneScriptPrimaryButtonIsDown != state.isPrimaryButtonDown {
            appendSceneScriptPointerEvent()
        }
        let parallaxTarget = state.isInside ? state.current : .zero
        parallaxPointerSmoother.setTarget(
            parallaxTarget,
            timestamp: CACurrentMediaTime()
        )
    }

    func recordSceneScriptPointerEvent(
        screenPoint: CGPoint,
        primaryButtonIsDown: Bool
    ) {
        guard let window else { return }
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        updatePointer(
            windowPoint,
            primaryButtonIsDown: primaryButtonIsDown
        )
        appendSceneScriptPointerEvent()
    }

    func drainSceneScriptPointerEvents() -> SceneSurfacePointerEventBatch {
        sceneScriptPointerEvents.drain()
    }

    private func updatePointer(
        _ windowPoint: CGPoint,
        primaryButtonIsDown: Bool? = nil
    ) {
        let local = convert(windowPoint, from: nil)
        guard bounds.width > 0, bounds.height > 0 else {
            setPointerOutside()
            return
        }
        let nx = Float((local.x / bounds.width) * 2 - 1)
        let ny = Float((local.y / bounds.height) * 2 - 1)
        pointerState.sceneScriptCurrent = SIMD2(nx, ny)
        pointerState.sceneScriptPrimaryButtonIsDown =
            primaryButtonIsDown ?? (NSEvent.pressedMouseButtons & 1 != 0)
        guard bounds.contains(local) else {
            setPointerOutside()
            pointerState.sceneScriptPrimaryButtonIsDown =
                primaryButtonIsDown ?? (NSEvent.pressedMouseButtons & 1 != 0)
            return
        }
        let normalized = SIMD2(
            max(-1, min(1, nx)),
            max(-1, min(1, ny))
        )
        pointerState.current = normalized
        pointerState.isInside = true
        pointerState.isPrimaryButtonDown =
            primaryButtonIsDown ?? (NSEvent.pressedMouseButtons & 1 != 0)
        parallaxPointerSmoother.setTarget(normalized, timestamp: CACurrentMediaTime())
    }

    private func appendSceneScriptPointerEvent() {
        sceneScriptPointerEvents.append(.init(
            normalizedPosition: pointerState.sceneScriptCurrent,
            isInside: pointerState.isInside,
            primaryButtonIsDown: pointerState.sceneScriptPrimaryButtonIsDown
        ))
    }

    private func setPointerOutside() {
        pointerState.isInside = false
        pointerState.isPrimaryButtonDown = false
        parallaxPointerSmoother.setTarget(.zero, timestamp: CACurrentMediaTime())
    }
}
