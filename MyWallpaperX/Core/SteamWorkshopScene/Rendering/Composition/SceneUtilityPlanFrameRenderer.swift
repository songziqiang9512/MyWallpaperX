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
        ] = [:],
        compositionGroupRuntime: SceneCompositionGroupFrameRuntime? = nil
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
            // A composition utility resolves the complete dependency vector
            // before entering the shared compositor: its aggregate slot
            // order when the plan owns one, otherwise the single-provider
            // input.
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
                dependencyEffects = dependencyRuntime.effectInput(
                    for: layer.id,
                    textureRegistry: renderer.textureRegistry
                ).map { [$0] } ?? []
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
               dependencyEffects.isEmpty {
                dependencyRuntime.recordBindingFailure(for: layer.id)
                captured = false
            } else {
                // D1: an isolated-group composite reads the group's own
                // target as its effect-chain source and encodes once into
                // the enclosing pass. A degraded group (allocation failure,
                // or a degraded enclosing group) keeps previous-current and
                // never publishes uncomposited member content.
                let isolatedGroupSource: (
                    texture: MTLTexture,
                    pixelSize: CGSize,
                    compositePass: SceneMainPassEncoder
                )?
                if plan.usesIsolatedGroupTarget {
                    // The members encoded only into the group target, so a
                    // missing group runtime or degraded target must keep
                    // previous-current; the legacy main-target capture can
                    // never substitute for group content.
                    guard let compositionGroupRuntime,
                          let texture = compositionGroupRuntime
                            .groupTexture(forRootID: plan.layerID),
                          let compositePass = compositionGroupRuntime
                            .compositeTargetPass(forRootID: plan.layerID) else {
                        captured = false
                        utilityCaptureTelemetry.record(
                            layerID: layer.id,
                            encoded: false,
                            on: commandBuffer
                        )
                        dependencyRuntime.recordBindingIfRequired(
                            for: layer.id,
                            encoded: false,
                            on: commandBuffer
                        )
                        continue
                    }
                    isolatedGroupSource = (
                        texture,
                        viewportSize,
                        compositePass
                    )
                } else {
                    isolatedGroupSource = nil
                }
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
                    dependencyEffects: dependencyEffects,
                    requiresDependencyEffect: requiresDependencyEffect,
                    pipeline: imagePipeline,
                    compositor: imageCompositor,
                    offscreenTexturePool: offscreenTexturePool,
                    mainPass: isolatedGroupSource?.compositePass ?? mainPass,
                    resolvedMaterialFrameTargetPlan:
                        resolvedMaterialFrameTargetPlans[layer.id],
                    isolatedGroupSource: isolatedGroupSource.map {
                        (texture: $0.texture, pixelSize: $0.pixelSize)
                    },
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
