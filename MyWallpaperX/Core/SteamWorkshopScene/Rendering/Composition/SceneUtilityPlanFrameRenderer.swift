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
        frameVisibleLayerIDs: Set<Int>,
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
        modelFrame: SceneMetalRenderer.StaticModelFrame,
        effectExecutionTrace: SceneEffectExecutionFrameTrace?,
        resolvedMaterialFrameTargetPlans: [
            Int: SceneResolvedMaterialFrameTargetPlan
        ] = [:],
        compositionGroupRuntime: SceneCompositionGroupFrameRuntime? = nil,
        layersByID: [Int: SceneRenderDescriptor.Layer]
    ) -> Bool {
        for plan in plans {
            guard let layer = layersByID[plan.layerID] else { continue }
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
            let framePlan = resolvedMaterialFrameTargetPlans[layer.id]
            let dependencyBypassReason = framePlan == nil ? nil : imageCompositor
                .preparedResolvedMaterialExternalDependencyBypassReason(layerID: layer.id)
            let requiresDependencyEffect = (framePlan?.consumesExternalPrimaryDependency
                ?? dependencyRuntime.requiresEffect(for: layer.id)) && dependencyBypassReason == nil
            let dependencyResolution = renderer.resolveDependencyEffectInputs(
                layerID: layer.id,
                requiresDependencyEffect: requiresDependencyEffect,
                hasResolvedFramePlan: framePlan != nil,
                bypassReason: dependencyBypassReason,
                dependencyRuntime: dependencyRuntime,
                textureRegistry: renderer.textureRegistry
            )
            let dependencyEffects = dependencyResolution.dependencyEffects
            if let reasonCode = dependencyResolution.failure {
                dependencyRuntime.recordBindingFailure(for: layer.id)
                imageCompositor.recordResolvedMaterialFramePreflightFailure(
                    reasonCode
                )
                return false
            }
            let captured: Bool
            if requiresDependencyEffect,
               dependencyEffects.isEmpty, framePlan == nil {
                dependencyRuntime.recordBindingFailure(for: layer.id)
                captured = false
            } else {
                // Every capture writes to its enclosing pass. An isolated
                // root reads its own source; a childless capture uses the
                // same enclosing pass for read/clear and final composition.
                let compositePass: SceneMainPassEncoder?
                if let compositionGroupRuntime {
                    compositePass = compositionGroupRuntime
                        .compositeTargetPass(forRootID: plan.layerID, beginsRendering: true)
                } else {
                    compositePass = mainPass
                }
                let isolatedGroupSource: MTLTexture?
                if plan.usesIsolatedGroupTarget {
                    isolatedGroupSource = compositionGroupRuntime?
                        .groupTexture(forRootID: plan.layerID)
                } else {
                    isolatedGroupSource = nil
                }
                guard let compositePass,
                      !plan.usesIsolatedGroupTarget || isolatedGroupSource != nil else {
                    if frameVisibleLayerIDs.contains(layer.id) || plan.requiresNamedTarget {
                        utilityCaptureTelemetry.record(
                            layerID: layer.id, encoded: false, on: commandBuffer)
                        dependencyRuntime.recordBindingIfRequired(
                            for: layer.id, encoded: false, on: commandBuffer)
                    }
                    continue
                }
                let compositeOutput = frameVisibleLayerIDs.contains(layer.id)
                let publisher: ((MTLTexture, SceneTextureContent) -> SceneGraphOutputPublicationResult)?
                if dependencyRuntime.requiresDemandedGraphOutputCapture(for: layer.id) {
                    publisher = { texture, content in
                        dependencyRuntime.publishGraphOutputIfRequired(
                            layerID: layer.id,
                            texture: texture,
                            publicationRole: compositeOutput ? .visibleMainLoop : .namedProviderPrepass,
                            textureRegistry: renderer.textureRegistry,
                            commandBuffer: commandBuffer,
                            content: content,
                            imagePipeline: imagePipeline,
                            retainAuxiliary: compositePass.retainAuxiliaryRelease
                        ) ?? .invalid(reasonCode: "named-provider-publication-route-missing")
                    }
                } else {
                    publisher = nil
                }
                let terminalDepth: SceneImageLayerTerminalDepthBinding?
                let terminalMVP: simd_float4x4?
                if layer.utilityLayer?.framebufferSource != nil {
                    guard compositePass === mainPass, isolatedGroupSource == nil,
                          resolvedMaterialFrameTargetPlans[layer.id] != nil else { continue }
                    guard let binding = modelFrame.terminalDepthBinding(
                        pass: compositePass, commandBuffer: commandBuffer) else {
                        imageCompositor.recordResolvedMaterialFramePreflightFailure(
                            "framebuffer-source-depth-binding-invalid")
                        return false
                    }
                    terminalDepth = binding
                    terminalMVP = cameraFrame.reverseDepthViewProjection(
                        usesPerspective: cameraFrame.resolvesPerspective(for: layer)) * model
                } else {
                    terminalDepth = nil
                    terminalMVP = nil
                }
                captured = SceneUtilityLayerRenderer.draw(
                    layer: layer,
                    plan: plan,
                    layerMVP: mvp,
                    viewportSize: compositionGroupRuntime?
                        .enclosingTargetSize(forLayerID: layer.id) ?? viewportSize,
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
                    resolvedMaterialGraphOutputPublisher: publisher,
                    compositeOutput: compositeOutput,
                    pipeline: imagePipeline,
                    compositor: imageCompositor,
                    offscreenTexturePool: offscreenTexturePool,
                    mainPass: compositePass,
                    resolvedMaterialFrameTargetPlan:
                        resolvedMaterialFrameTargetPlans[layer.id],
                    terminalMVP: terminalMVP,
                    terminalDepth: terminalDepth,
                    isolatedGroupSource: isolatedGroupSource,
                    captureMVP: compositionGroupRuntime?.rasterModelViewProjection(
                        forLayerID: layer.id,
                        worldMVP: cameraFrame.captureViewProjection(for: layer) * model
                    ) ?? (cameraFrame.captureViewProjection(for: layer) * model),
                    localCompositionSourceExtent: compositionGroupRuntime?
                        .localSourceExtent(forRootID: layer.id),
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
