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

    func applyPointerInput(_ input: SceneSurfacePointerInput) {
        if pointerState.apply(input) {
            appendSceneScriptPointerEvent()
        }
        let parallaxTarget = input.isInside ? input.current : .zero
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
        guard let sample = SceneSurfacePointerEvent.sample(
            localPosition: local,
            bounds: bounds,
            primaryButtonIsDown: primaryButtonIsDown ?? (NSEvent.pressedMouseButtons & 1 != 0)
        ) else {
            setPointerOutside()
            return
        }
        pointerState.sceneScriptCurrent = sample.normalizedPosition
        pointerState.sceneScriptPrimaryButtonIsDown = sample.primaryButtonIsDown
        guard sample.isInside else {
            setPointerOutside(
                primaryButtonIsDown: sample.primaryButtonIsDown
            )
            return
        }
        let normalized = SIMD2(
            max(-1, min(1, sample.normalizedPosition.x)),
            max(-1, min(1, sample.normalizedPosition.y))
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

    private func setPointerOutside(primaryButtonIsDown: Bool? = nil) {
        _ = pointerState.setOutside(
            primaryButtonIsDown: primaryButtonIsDown ?? (NSEvent.pressedMouseButtons & 1 != 0)
        )
        parallaxPointerSmoother.setTarget(.zero, timestamp: CACurrentMediaTime())
    }
}
