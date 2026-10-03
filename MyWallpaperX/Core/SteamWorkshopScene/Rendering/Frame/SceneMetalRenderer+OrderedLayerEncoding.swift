import Foundation
import Metal
import QuartzCore
import simd

extension SceneMetalRenderer {
    /// Owns authored order and each layer's utility defer. Closing group
    /// encoders and finishing the main pass are part of the same stage.
    func encodeOrderedLayers(
        orderedLayers: [SceneRenderDescriptor.Layer],
        initiallyStopped: Bool,
        forwardGraphProviderLayerIDs: Set<Int>,
        frameVisibleLayerIDs: Set<Int>,
        activeStaticModelNamedAlbedoLayerIDs: Set<Int>,
        imageTextures: SceneBaseImageTextureSnapshot,
        imagePipeline: SceneImageLayerPipeline?,
        specializedBaseTextureSamplings: [Int: SceneTextureSampling],
        spriteAnimations: [Int: SceneSpriteAnimation],
        spriteAnimationPlaybackTimes: [Int: Float],
        resolvedMaterialFrameTargetPlans: [Int: SceneResolvedMaterialFrameTargetPlan],
        frameContext: SceneFrameContext,
        frameWorldFrames: [Int: simd_float4x4],
        cameraFrame: SceneParticleCameraFrame,
        parallaxMouseNormalized: SIMD2<Float>,
        parallaxConfiguration: SceneLayerParallax.Configuration,
        viewportSize: CGSize,
        time: Float,
        offscreenTexturePool: SceneOffscreenTexturePool?,
        frameLightSnapshot: SceneLightSnapshot,
        reflection: ReflectionFrame,
        environmentSource: @escaping (MTLCommandBuffer) -> SceneFrameTextureResource?,
        modelFrame: StaticModelFrame,
        mainPass: SceneMainPassEncoder,
        compositionGroupRuntime: SceneCompositionGroupFrameRuntime?,
        commandBuffer: MTLCommandBuffer,
        effectExecutionTrace: SceneEffectExecutionFrameTrace?,
        particleBatchesByID: [Int: [SceneParticleDrawBatch]],
        particlePipeline: SceneParticleMetalPipeline?,
        frameDepthLeases: inout [SceneParticleDepthTargetLease],
        particlePerformanceObservations: inout [SceneParticlePerformanceObservation]?,
        performanceTelemetry: SceneFramePerformanceTelemetry?,
        sceneColor: SceneResolvedMaterialSubmissionCoordinator.SceneColorReservation?,
        frameProjection: SceneMetalRendererFrameWorldProjection,
        layerTopology: SceneScriptLayerTopologySnapshot?
    ) -> FrameOutcome? {
#if DEBUG
        let collectsPointLightExecutionEvidence =
            SceneDesktopWallpaperHost.usesDebugEvidenceWindow
            && frameContext.frameIndex <= 2
            && !frameLightSnapshot.point.isEmpty
        var dynamicEncodedLayerCount = 0
        var dynamicPassthroughLayerCount = 0
        var pointLitStaticModelLayerIDs: [Int] = []
#endif
        var stopsAfterClaimedFailure = initiallyStopped
        var lastLayerPass: SceneMainPassEncoder?
        performanceTelemetry?.beginStage("layer-loop")
        let hubLayerLoopStart = ProcessInfo.processInfo.systemUptime
        frameLayers: for layer in orderedLayers {
            if stopsAfterClaimedFailure { break frameLayers }
            defer {
                if !stopsAfterClaimedFailure,
                   !renderUtilityPlans(triggeredBy: layer.id,
                    imagePipeline: imagePipeline,
                    offscreenTexturePool: offscreenTexturePool, frameContext: frameContext,
                    worldFramesByLayerID: frameWorldFrames, cameraFrame: cameraFrame,
                    parallaxConfiguration: parallaxConfiguration, viewportSize: viewportSize,
                    time: time, mainPass: mainPass, commandBuffer: commandBuffer,
                    effectExecutionTrace: effectExecutionTrace,
                    resolvedMaterialFrameTargetPlans:
                        resolvedMaterialFrameTargetPlans,
                    compositionGroupRuntime: compositionGroupRuntime,
                    utilityExecution: frameProjection.utilityExecution,
                    layersByID: frameProjection.layersByID) {
                    // A utility plan that hit typed identity drift already
                    // sealed the frame as failed, so stop the layer loop like
                    // every other `.invalid` consumer instead of encoding
                    // work that can never be presented.
                    stopsAfterClaimedFailure = true
                }
            }
            // D1: a composition-group member encodes into its group's
            // isolated target. A degraded group skips the member entirely —
            // uncomposited member content must never reach the parent
            // target. The utility defer above stays registered so an
            // enclosing group whose trigger lands on this layer still
            // composites. Only one render encoder may be open per command
            // buffer, so switching passes closes the previous layer's pass.
            let layerMainPass: SceneMainPassEncoder
            if let compositionGroupRuntime,
               let groupPass = compositionGroupRuntime.renderPass(
                   forLayerID: layer.id, beginsRendering: true
               ), groupPass !== mainPass {
                layerMainPass = groupPass
            } else if compositionGroupRuntime != nil,
                      frameProjection.utilityExecution.memberRootsByLayerID[layer.id] != nil {
                continue
            } else {
                layerMainPass = mainPass
            }
            if layerMainPass !== lastLayerPass {
                lastLayerPass?.closeForOffscreen()
            }
            lastLayerPass = layerMainPass
            // Its graph was already executed and published before an earlier
            // consumer. Keep authored trigger order, but never consume the
            // same launch/frame claim twice.
            if forwardGraphProviderLayerIDs.contains(layer.id) { continue }
            let baseSelection: SceneBaseMaterialTextureSelection
            switch layer.contentKind {
            case "image", "solid", "text":
                baseSelection = baseMaterialTextureSelection(
                    for: layer,
                    imageTextures: imageTextures,
                    readyProviderUsesAuthoredLayerColor:
                        baseMaterialReadyProviderUsesAuthoredLayerColor(
                            for: layer,
                            dynamicValues: frameContext.dynamicValues
                        )
                )
            default:
                baseSelection = .missing
            }
            let baseSource = baseSelection.source
            if let reasonCode = baseSelection.rejectedProviderReason {
                effectExecutionTrace?.recordRouteOperation(
                    layerID: layer.id,
                    origin: Self.effectExecutionOrigin(for: layer.contentKind),
                    operation: "base-material-provider-rejected",
                    outcome: .failed(reasonCode: reasonCode)
                )
            } else if baseSource?.usesSystemProvider == true {
                effectExecutionTrace?.recordRouteOperation(
                    layerID: layer.id,
                    origin: Self.effectExecutionOrigin(for: layer.contentKind),
                    operation: "base-material-system-provider",
                    outcome: .encoded
                )
            } else if baseSource?.usesUserPropertyProvider == true {
                effectExecutionTrace?.recordRouteOperation(
                    layerID: layer.id,
                    origin: Self.effectExecutionOrigin(for: layer.contentKind),
                    operation: "base-material-user-property-provider",
                    outcome: .encoded
                )
            }
            if let providerGraphEncoded = executeDependencyGraphProviderIfRequired(
                layer: layer,
                isVisibleExecutionRoot: frameVisibleLayerIDs.contains(layer.id),
                framePlan: resolvedMaterialFrameTargetPlans[layer.id],
                textureRegistry: textureRegistry,
                dependencyRuntime: dependencyRuntime,
                mainPass: layerMainPass,
                commandBuffer: commandBuffer,
                geometryProduct: imageTextures.geometryProducts[layer.id],
                imagePipeline: imagePipeline,
                executionTrace: effectExecutionTrace
            ) {
                if !providerGraphEncoded {
                    stopsAfterClaimedFailure = true
                    break frameLayers
                }
                continue
            }
            if let imagePipeline, dependencyRuntime.requiresCapture(
                for: layer.id,
                activeStaticModelConsumerLayerIDs:
                    activeStaticModelNamedAlbedoLayerIDs
            ) {
                let captureResult = captureRawDependencyProvider(layer: layer, source: baseSource,
                    imageTextures: imageTextures, imagePipeline: imagePipeline, frameContext: frameContext,
                    worldFrames: frameWorldFrames, cameraFrame: cameraFrame,
                    parallax: parallaxConfiguration, viewportSize: viewportSize, mainPass: layerMainPass)

                // This route owns no publication of its own: an ordinary
                // miss keeps previous-current and the consumer-side
                // resolution localises it. A typed identity rejection is only
                // visible here, so it must fail closed instead of being
                // downgraded to that ordinary miss.
                if case let .invalid(reasonCode)? = captureResult {
                    effectExecutionTrace?.recordRouteOperation(
                        layerID: layer.id,
                        origin: Self.effectExecutionOrigin(
                            for: layer.contentKind
                        ),
                        operation: "named-provider-capture",
                        outcome: .failed(reasonCode: reasonCode)
                    )
                    imageCompositor.recordResolvedMaterialFramePreflightFailure(
                        reasonCode
                    )
                    stopsAfterClaimedFailure = true
                    break frameLayers
                }
            }
            guard frameVisibleLayerIDs.contains(layer.id) else { continue }
            switch layer.contentKind {
            case "image", "solid", "text":
                guard let imagePipeline, let baseSource else { continue }
                let imageResult = encodeImageLayer(
                    layer: layer,
                    baseSource: baseSource,
                    imageTextures: imageTextures,
                    imagePipeline: imagePipeline,
                    specializedBaseTextureSamplings: specializedBaseTextureSamplings,
                    spriteAnimations: spriteAnimations,
                    spriteAnimationPlaybackTimes: spriteAnimationPlaybackTimes,
                    resolvedMaterialFrameTargetPlans: resolvedMaterialFrameTargetPlans,
                    frameContext: frameContext,
                    frameWorldFrames: frameWorldFrames,
                    cameraFrame: cameraFrame,
                    parallaxMouseNormalized: parallaxMouseNormalized,
                    parallaxConfiguration: parallaxConfiguration,
                    viewportSize: viewportSize,
                    time: time,
                    offscreenTexturePool: offscreenTexturePool,
                    frameLightSnapshot: frameLightSnapshot,
                    reflection: reflection,
                    environmentSource: environmentSource,
                    modelFrame: modelFrame,
                    layerMainPass: layerMainPass,
                    commandBuffer: commandBuffer,
                    effectExecutionTrace: effectExecutionTrace
                )
                if imageResult.stop {
                    stopsAfterClaimedFailure = true
                    break frameLayers
                }
                guard let drawOutcome = imageResult.outcome else { continue }
#if DEBUG
                if frameProjection.dynamicLayerIDs.contains(layer.id) {
                    if drawOutcome.encoded {
                        dynamicEncodedLayerCount += 1
                    }
                    if case .layerSourcePassthrough = drawOutcome {
                        dynamicPassthroughLayerCount += 1
                    }
                }
#endif
                dependencyRuntime.recordBindingIfRequired(
                    for: layer.id,
                    encoded: drawOutcome.consumedDependency,
                    on: commandBuffer
                )
                if !drawOutcome.encoded,
                   resolvedMaterialFrameTargetPlans[layer.id] != nil {
                    stopsAfterClaimedFailure = true
                    break frameLayers
                }
            case "composition":
                // D1: an isolated-group root without an admitted frame plan
                // must keep previous-current. Its members encoded only into
                // the group target, so the flat composition fallback would
                // draw parent content that never contained them.
                if resolvedMaterialFrameTargetPlans[layer.id] == nil,
                   frameProjection.utilityExecution.membersByRootID[layer.id] == nil,
                   let imagePipeline {
                    _ = drawCompositionSourceFallback(
                        layer: layer,
                        imageTextures: imageTextures,
                        imagePipeline: imagePipeline,
                        frameContext: frameContext,
                        worldFramesByLayerID: frameWorldFrames,
                        cameraFrame: cameraFrame,
                        parallaxConfiguration: parallaxConfiguration,
                        time: time,
                        mainPass: layerMainPass,
                        executionTrace: effectExecutionTrace
                    )
                }
            case "project", "fullscreen":
                break
            case "model":
                let lit = drawStaticModel(layer: layer, state: modelFrame,
                    worldFrames: frameWorldFrames, frameContext: frameContext,
                    cameraFrame: cameraFrame, lighting: frameLightSnapshot,
                    pass: layerMainPass, commandBuffer: commandBuffer, leases: &frameDepthLeases)
#if DEBUG
                if collectsPointLightExecutionEvidence, lit { pointLitStaticModelLayerIDs.append(layer.id) }
#endif
            case "quad":
                if !drawQuadLayer(
                    layer: layer,
                    resolvedFramePlan: resolvedMaterialFrameTargetPlans[layer.id],
                    frameContext: frameContext,
                    mainPass: layerMainPass,
                    executionTrace: effectExecutionTrace
                ) {
                    stopsAfterClaimedFailure = true
                    break frameLayers
                }
            case "spotLight":
                guard frameVisibleLayerIDs.contains(layer.id) else { continue }
                spotLightRuntime.render(
                    layerID: layer.id, worldFrame: frameWorldFrames[layer.id],
                    frame: .init(
                        frameContext: frameContext, cameraFrame: cameraFrame,
                        mainPass: layerMainPass, commandBuffer: commandBuffer
                    )
                )
            case "particle":
                guard let particlePipeline,
                      let layerBatches = particleBatchesByID[layer.id] else { continue }
                let model = particleModelMatrix(
                    for: layer, worldFramesByLayerID: frameWorldFrames,
                    parallaxMouseNormalized: parallaxMouseNormalized,
                    configuration: parallaxConfiguration
                )
                if let depthLease = renderParticleBatches(
                    layerBatches,
                    pipeline: particlePipeline,
                    model: model,
                    cameraFrame: cameraFrame,
                    viewportSize: SIMD2(
                        Float(viewportSize.width),
                        Float(viewportSize.height)
                    ),
                    mainPass: layerMainPass,
                    commandBuffer: commandBuffer,
                    preparedDepth: modelFrame.particleDepth[layer.id],
                    performanceObservations: &particlePerformanceObservations
                ) {
                    if modelFrame.particleDepth[layer.id] == nil { frameDepthLeases.append(depthLease) }
                }
            default:
                continue
            }
        }
        performanceTelemetry?.endStage("layer-loop")
        hubStage(.layerLoopMicros, hubLayerLoopStart)
        // D1: no group encoder may outlive the layer loop — the compositor
        // seal re-opens the main pass and Metal permits only one active
        // render encoder per command buffer.
        compositionGroupRuntime?.closeAllGroupEncoders()

        let mainEncoded = mainPass.finishEnsuringClear()
        reflection.mainSourceCompleted = mainEncoded
        if sceneColor != nil && !mainEncoded {
            return .dropped(reasonCode: "scene-color-main-encoder-unavailable")
        }
#if DEBUG
        if collectsPointLightExecutionEvidence {
            logStaticModelLightExecutionEvidence(
                frameContext: frameContext,
                frameLightSnapshot: frameLightSnapshot,
                encodedLayerIDs: pointLitStaticModelLayerIDs,
                commandBuffer: commandBuffer
            )
        }
        reportDynamicLayerRenderEvidence(
            projection: frameProjection,
            imageTextures: imageTextures,
            dynamicValues: frameContext.dynamicValues,
            encodedLayerCount: dynamicEncodedLayerCount,
            passthroughLayerCount: dynamicPassthroughLayerCount,
            frameIndex: frameContext.frameIndex,
            topologyRevision: layerTopology?.topologyRevision ?? 0,
            commandBuffer: commandBuffer
        )
#endif
        return nil
    }
}
