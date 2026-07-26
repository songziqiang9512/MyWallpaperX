import CoreGraphics
import QuartzCore

extension SceneMetalView {
    func makeFrameContext(
        timing: SceneFrameTiming,
        dynamicValues: SceneDynamicSnapshot,
        parallax: SIMD2<Float>,
        audioSpectrum: SceneAudioSpectrumSnapshot
    ) -> SceneFrameContext {
        let screenSize = metalLayer.drawableSize
        let camera = renderer.renderDescriptor.camera
        return SceneFrameContext(
            timing: timing,
            dynamicValues: dynamicValues,
            canvasSize: CGSize(
                width: CGFloat(camera.orthoWidth ?? Float(screenSize.width)),
                height: CGFloat(camera.orthoHeight ?? Float(screenSize.height))
            ),
            screenSize: screenSize,
            pointer: pointerState,
            cameraParallaxPosition: parallax,
            audioSpectrum: audioSpectrum
        )
    }
}
