import AppKit

extension SceneMetalView {
    func updateDrawableSize() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        metalLayer.contentsScale = scale
        let pixelSize = CGSize(
            width: max(bounds.width, 1) * scale,
            height: max(bounds.height, 1) * scale
        )
        if metalLayer.drawableSize != pixelSize {
            metalLayer.drawableSize = pixelSize
        }
    }
}
