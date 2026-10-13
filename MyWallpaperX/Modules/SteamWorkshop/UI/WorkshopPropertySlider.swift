import AppKit

final class WorkshopPropertySlider: NSSlider {
    var isTrackingMouse = false
    var onTrackingBegan: ((NSSlider) -> Void)?
    var onTrackingEnded: ((NSSlider) -> Void)?

    override func mouseDown(with event: NSEvent) {
        isTrackingMouse = true
        onTrackingBegan?(self)
        super.mouseDown(with: event)
        isTrackingMouse = false
        onTrackingEnded?(self)
    }
}

