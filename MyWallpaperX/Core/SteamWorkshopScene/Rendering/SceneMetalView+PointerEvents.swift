import AppKit

extension SceneMetalView {
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        configurePointerTracking()
    }

    override func mouseMoved(with event: NSEvent) { handlePointerEvent(event) }
    override func mouseEntered(with event: NSEvent) { handlePointerEvent(event) }
    override func mouseExited(with event: NSEvent) { handlePointerExit() }
    override func mouseDown(with event: NSEvent) { handlePointerEvent(event) }
    override func mouseUp(with event: NSEvent) { handlePointerEvent(event) }
}
