import CoreGraphics
import Metal
import simd

enum SceneUtilityPlanFrameRenderer {
    /// Returns `false` when a typed identity rejection claimed the frame, so
    /// the caller stops the layer loop exactly like the other `.invalid`
    /// consumers instead of encoding layers whose frame is already sealed as
    /// failed.
    @discardableResult
    static func render(
        renderer: SceneMetalRenderer,
        plans: [SceneUtilityLayerRuntimePlan],
        dependencyRuntime: SceneDependencyFrameRuntime,
        imageCompositor: SceneImageLayerCompositor,
        utilityCaptureTelemetry: SceneGPUCompletionTelemetry,
        imagePipeline: SceneImageLayerPipeline,
        offscreenTexturePool: SceneOffscreenTexturePool,
        frameContext: SceneFrameContext,
        worldFramesByLayerID: [Int: simd_float4x4],
        cameraFrame: SceneParticleCameraFrame,
        parallaxConfiguration: SceneLayerParallax.Configuration,
        viewportSize: CGSize,
        time: Float,
        mainPass: SceneMainPassEncoder,
        commandBuffer: MTLCommandBuffer,
        effectExecutionTrace: SceneEffectExecutionFrameTrace?,
        resolvedMaterialFrameTargetPlans: [
            Int: SceneResolvedMaterialFrameTargetPlan
        ] = [:]
    ) -> Bool {
        for plan in plans {
            guard let layer = renderer.layersByID[plan.layerID] else { continue }
            let model = renderer.imageModelMatrix(
                for: layer,
                worldFramesByLayerID: worldFramesByLayerID,
                parallaxMouseNormalized: frameContext.cameraParallaxPosition,
                configuration: parallaxConfiguration,
                visibleHalfExtents: cameraFrame.coverHalfExtents,
                usesPerspective: cameraFrame.resolvesPerspective(for: layer)
            )
            let mvp = cameraFrame.viewProjection(for: layer) * model
            let cursorUV = SceneLayerCursorGeometry.layerUV(
                mouseNormalized: frameContext.pointer.current,
                modelViewProjection: mvp
            )
            let requiresDependencyEffect = dependencyRuntime.requiresEffect(
                for: layer.id
            )
            let dependencyEffect = dependencyRuntime.effectInput(
                for: layer.id,
                textureRegistry: renderer.textureRegistry
            )
            // A composition utility may own a lossless multi-provider
            // aggregate. Resolve the complete authored slot vector before
            // entering the shared compositor; projecting it onto the legacy
            // singular input would silently drop every provider after the
            // first one.
            let dependencyEffects: [SceneDependencyEffectInput]
            var dependencyAggregateInvalidReason: String?
            if let aggregate = dependencyRuntime.plan
                .multiProviderAggregatesByConsumerLayerID[layer.id] {
                switch dependencyRuntime.aggregateEffectInputResolution(
                    for: aggregate,
                    textureRegistry: renderer.textureRegistry
                ) {
                case let .ready(inputs):
                    dependencyEffects = inputs
                case .unavailable(reasonCode: _):
                    // Ordinary provider miss: this utility layer keeps its
                    // previous-current output and the shared binding
                    // telemetry records the local fallback below.
                    dependencyEffects = []
                case let .invalid(reasonCode):
                    dependencyEffects = []
                    dependencyAggregateInvalidReason = reasonCode
                }
            } else {
                dependencyEffects = []
            }
            if let reasonCode = dependencyAggregateInvalidReason {
                // Reservation, epoch, slot-vector or publication identity
                // drift is only visible here. It must fail closed instead of
                // being localised as an ordinary provider miss, and it must
                // stop the whole layer loop like every other `.invalid`
                // consumer: the frame is sealed as failed, so continuing only
                // encodes work that can never be presented.
                dependencyRuntime.recordBindingFailure(for: layer.id)
                imageCompositor.recordResolvedMaterialFramePreflightFailure(
                    reasonCode
                )
                return false
            }
            let captured: Bool
            if requiresDependencyEffect,
               dependencyEffect == nil,
               dependencyEffects.isEmpty {
                dependencyRuntime.recordBindingFailure(for: layer.id)
                captured = false
            } else {
                captured = SceneUtilityLayerRenderer.draw(
                    layer: layer,
                    plan: plan,
                    layerMVP: mvp,
                    viewportSize: viewportSize,
                    time: time,
                    finalCompositeAlpha: SceneDynamicLayerValues.alpha(
                        layerID: layer.id,
                        authoredValue: layer.alpha,
                        snapshot: frameContext.dynamicValues
                    ),
                    masks: .empty,
                    cursorUV: cursorUV ?? .zero,
                    pointerIsInside: frameContext.pointer.isInside && cursorUV != nil,
                    dynamicValues: frameContext.dynamicValues,
                    audioSpectrum: frameContext.audioSpectrum,
                    dependencyEffect: dependencyEffect,
                    dependencyEffects: dependencyEffects,
                    requiresDependencyEffect: requiresDependencyEffect,
                    pipeline: imagePipeline,
                    compositor: imageCompositor,
                    offscreenTexturePool: offscreenTexturePool,
                    mainPass: mainPass,
                    resolvedMaterialFrameTargetPlan:
                        resolvedMaterialFrameTargetPlans[layer.id],
                    executionTrace: effectExecutionTrace
                )
            }
            utilityCaptureTelemetry.record(
                layerID: layer.id,
                encoded: captured,
                on: commandBuffer
            )
            dependencyRuntime.recordBindingIfRequired(
                for: layer.id,
                encoded: captured,
                on: commandBuffer
            )
        }
        return true
    }
}
