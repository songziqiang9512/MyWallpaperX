import CoreGraphics
import simd

enum SceneLayerCursorGeometry {
    static func worldPosition(
        camera: SceneRenderDescriptor.CameraDescriptor,
        mouseNormalized: SIMD2<Float>,
        viewportSize: CGSize
    ) -> SIMD2<Float> {
        let orthoWidth = camera.orthoWidth ?? Float(viewportSize.width)
        let orthoHeight = camera.orthoHeight ?? Float(viewportSize.height)
        return SIMD2(
            orthoWidth * 0.5 + mouseNormalized.x * orthoWidth * 0.5,
            orthoHeight * 0.5 - mouseNormalized.y * orthoHeight * 0.5
        )
    }

    static func layerUV(
        for layer: SceneRenderDescriptor.Layer,
        cursorWorld: SIMD2<Float>
    ) -> SIMD2<Float> {
        let origin = SIMD3<Float>(layer.originXYZ ?? [], fill: 0)
        let size = SIMD2<Float>(layer.renderSizeWH ?? [], fill: 0)
        guard size.x > 0, size.y > 0 else { return .zero }
        return SIMD2(
            (cursorWorld.x - (origin.x - size.x / 2)) / size.x,
            (cursorWorld.y - (origin.y - size.y / 2)) / size.y
        )
    }
}
