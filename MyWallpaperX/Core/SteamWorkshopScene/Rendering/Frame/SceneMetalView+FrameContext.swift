import CoreGraphics
import QuartzCore

extension SceneMetalView {
    var shouldDeferResolvedMaterialFrame: Bool {
        renderer.imageCompositor.shouldDeferResolvedMaterialFrame
    }

    func invalidateResolvedMaterialRuntime(
        reason: SceneGraphExecutionResetReason, notifyRender: Bool = true
    ) {
        renderer.imageCompositor.invalidateResolvedMaterialRuntime(reason: reason)
        offscreenTexturePool.reset()
        if notifyRender { onRenderInvalidated?() }
    }

    func makeFrameContext(
        timing: SceneFrameTiming,
        dynamicValues: SceneDynamicSnapshot,
        materialFunctionMutations: [SceneScriptMaterialFunctionMutation] = [],
        parallax: SIMD2<Float>,
        audioSpectrum: SceneAudioSpectrumSnapshot
    ) -> SceneFrameContext {
        let screenSize = metalLayer.drawableSize
        let camera = renderer.renderDescriptor.camera
        let property = dynamicValues.cameraPropertyProjection()
        let parallaxEnabled = property.parallaxEnabled ?? camera.parallaxEnabled
        return SceneFrameContext(
            timing: timing,
            dynamicValues: dynamicValues,
            canvasSize: CGSize(
                width: CGFloat(camera.orthoWidth ?? Float(screenSize.width)),
                height: CGFloat(camera.orthoHeight ?? Float(screenSize.height))
            ),
            screenSize: screenSize,
            pointer: pointerState,
            cameraParallaxPosition: parallaxEnabled ? parallax : .zero,
            cameraParallaxMouseInfluence:
                property.parallaxMouseInfluence ?? camera.parallaxMouseInfluence,
            allowsMouseParallax: allowsMouseParallax,
            materialFunctionMutations: materialFunctionMutations,
            audioSpectrum: audioSpectrum
        )
    }
}
