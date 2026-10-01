import Metal
import simd

extension SceneMetalRenderer {
    func admitResolvedMaterialFrameTargets(
        imageTextures: SceneBaseImageTextureSnapshot,
        spriteAnimations: [Int: SceneSpriteAnimation],
        spriteAnimationPlaybackTimes: [Int: Float],
        frameVisibleLayerIDs: Set<Int>,
        performanceTelemetry: SceneFramePerformanceTelemetry? = nil,
        specializedBaseTextureSamplings: [Int: SceneTextureSampling] = [:],
        imagePipeline: SceneImageLayerPipeline?,
        userPropertyTextures: [String: MTLTexture],
        userPropertyStates: [
            SceneUserPropertyTextureIdentity: SceneTextureProviderState
        ],
        mediaThumbnail: SceneMediaThumbnailTextureStore.Snapshot,
        offscreenTexturePool: SceneOffscreenTexturePool?,
        frameContext: SceneFrameContext,
        worldFramesByLayerID: [Int: simd_float4x4],
        cameraFrame: SceneParticleCameraFrame,
        parallaxConfiguration: SceneLayerParallax.Configuration,
        mainTarget: MTLTexture,
        commandBuffer: MTLCommandBuffer,
        frameLightSnapshot: SceneLightSnapshot? = nil
    ) -> SceneMetalRenderer.ResolvedMaterialFrameAdmission {
        // Source selection is frame-scoped: provider readiness and authored
        // fallback state are refreshed above, then shared by the single
        // preflight walk that also builds the preparation requests below.
        var baseMaterialSelections: [Int: SceneBaseMaterialTextureSelection] = [:]
        switch preflightResolvedMaterialFrameTargets(
            imageTextures: imageTextures,
            spriteAnimations: spriteAnimations,
            spriteAnimationPlaybackTimes: spriteAnimationPlaybackTimes,
            performanceTelemetry: performanceTelemetry,
            specializedBaseTextureSamplings: specializedBaseTextureSamplings,
            imagePipeline: imagePipeline,
            offscreenTexturePool: offscreenTexturePool,
            frameVisibleLayerIDs: frameVisibleLayerIDs,
            frameContext: frameContext,
            worldFramesByLayerID: worldFramesByLayerID,
            cameraFrame: cameraFrame,
            parallaxConfiguration: parallaxConfiguration,
            mainTarget: mainTarget,
            commandBuffer: commandBuffer,
            baseMaterialSelections: &baseMaterialSelections,
            frameLightSnapshot: frameLightSnapshot
        ) {
        case let .ready(plans, localFallbacks, preparationRequests):
            guard imageCompositor.installResolvedMaterialFrameLocalFallbacks(
                localFallbacks
            ) else {
                imageCompositor.recordResolvedMaterialFramePreflightFailure(
                    "frame-local-fallback-install-rejected"
                )
                _ = imageCompositor.endResolvedMaterialFrame(on: commandBuffer)
                return .rejected(
                    reasonCode: "frame-local-fallback-install-rejected"
                )
            }
            performanceTelemetry?.beginStage("admit-prepare-frame")
            defer { performanceTelemetry?.endStage("admit-prepare-frame") }
            switch imageCompositor.prepareResolvedMaterialFrame(
                preparationRequests,
                pool: offscreenTexturePool,
                commandBuffer: commandBuffer,
                performanceTelemetry: performanceTelemetry
            ) {
            case .ready:
                // Observation only: splits admit-prepare-frame into the
                // coordinator's preparation and the provider-output install so
                // the remaining unattributed share can be located.
                performanceTelemetry?.beginStage("admit-install-graph-outputs")
                defer {
                    performanceTelemetry?.endStage("admit-install-graph-outputs")
                }
                guard let preparedOutputs = imageCompositor
                        .preparedResolvedMaterialOutputTexturesByLayerID(),
                      dependencyRuntime.installPreparedGraphOutputs(
                        preparedOutputs,
                        frameEpoch: textureRegistry.frameEpoch
                      ) else {
                    imageCompositor.recordResolvedMaterialFramePreflightFailure(
                        "prepared-provider-output-install-rejected"
                    )
                    _ = imageCompositor.endResolvedMaterialFrame(on: commandBuffer)
                    return .rejected(
                        reasonCode: "prepared-provider-output-install-rejected"
                    )
                }
            case .rejected:
                _ = imageCompositor.endResolvedMaterialFrame(on: commandBuffer)
                return .rejected(
                    reasonCode: "resolved-material-frame-preparation-rejected"
                )
            }
            return .ready(plans: plans)
        case .deferred:
            _ = imageCompositor.deferResolvedMaterialFrame()
            _ = imageCompositor.endResolvedMaterialFrame(on: commandBuffer)
            return .deferred(
                reasonCode: "resolved-material-preflight-deferred"
            )
        case .rejected(let reasonCode):
            imageCompositor.recordResolvedMaterialFramePreflightFailure(reasonCode)
            _ = imageCompositor.endResolvedMaterialFrame(on: commandBuffer)
            return .rejected(reasonCode: reasonCode)
        }
    }
}
