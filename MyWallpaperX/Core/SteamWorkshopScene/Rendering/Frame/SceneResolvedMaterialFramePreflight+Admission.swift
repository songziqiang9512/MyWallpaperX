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
        environmentSource: ((MTLCommandBuffer) -> SceneFrameTextureResource?)?,
        frameLightSnapshot: SceneLightSnapshot? = nil,
        compositionGroupRuntime: SceneCompositionGroupFrameRuntime? = nil
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
            environmentSource: environmentSource,
            frameLightSnapshot: frameLightSnapshot,
            compositionGroupRuntime: compositionGroupRuntime
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
    /// A single original plain consumer, shared by the F5 batch and the
    /// author-ordered mandatory preparation. Empty means no scratch consumer.
    func compositionScratchDimensions(
        for layer: SceneRenderDescriptor.Layer, pool: SceneOffscreenTexturePool,
        imageTextures: SceneBaseImageTextureSnapshot, frameContext: SceneFrameContext,
        worldFrames: [Int: simd_float4x4], cameraFrame: SceneParticleCameraFrame,
        parallax: SceneLayerParallax.Configuration,
        lightingResolution: SceneLitCapturePayloadResolution? = nil
    ) -> [(width: Int, height: Int)]? {
        // Only these authored kinds enter the plain image compositor. Model,
        // particle and light draws do not consume its colorBlend/profile fields.
        guard ["image", "solid", "text"].contains(layer.contentKind) else { return [] }
        let blendMode = layer.colorBlendMode ?? 0
        // The document preserves arbitrary authored integers. The compositor
        // rejects unsupported modes before both blend and lighting captures.
        guard SceneLayerColorBlendRenderer.supports(blendMode) else { return [] }
        let profile = baseMaterialProviderBindings.lightingProfileByLayerID[layer.id]
        let lightingNeedsCapture: Bool
        switch lightingResolution {
        case .payload(_)?: lightingNeedsCapture = true
        case .miss(_)?: lightingNeedsCapture = false
        case nil:
            // The original F5 batch precedes reflection admission. Its existing
            // capacity policy is unchanged; the ordered path supplies the actual
            // post-admission producer result, including a plain/direct miss.
            lightingNeedsCapture = profile?.surfaceEnabled == true && imageTextures.geometryProducts[layer.id] == nil
        }
        let needsCapture = lightingNeedsCapture || blendMode > 0
        guard needsCapture,
              let source = baseMaterialTextureSelection(for: layer, imageTextures: imageTextures,
                readyProviderUsesAuthoredLayerColor: baseMaterialReadyProviderUsesAuthoredLayerColor(
                for: layer, dynamicValues: frameContext.dynamicValues)).source else { return [] }
        let extent: SceneLayerEffectSourceExtent?
        if layer.contentKind == "solid" {
            let model = imageModelMatrix(for: layer, worldFramesByLayerID: worldFrames,
                renderSizeOverride: imageTextures.layerSourceRenderSize(for: layer.id),
                parallaxMouseNormalized: frameContext.cameraParallaxPosition, configuration: parallax,
                visibleHalfExtents: cameraFrame.coverHalfExtents,
                usesPerspective: cameraFrame.resolvesPerspective(for: layer))
            extent = SceneCaptureGeometryResolver.projectedPixelSize(
                layerMVP: cameraFrame.viewProjection(for: layer) * model,
                viewportSize: frameContext.screenSize).flatMap(SceneLayerEffectSourceExtent.init(pixelSize:))
        } else {
            extent = SceneLayerEffectSourceExtent.resolve(
                publishedRenderSizeWH: imageTextures.layerSourceRenderSize(for: layer.id),
                authoredRenderSizeWH: layer.renderSizeWH, candidateMappedSize: source.candidate?.mappedSize)
        }
        guard let size = extent?.pixelSize,
              let resolved = SceneOffscreenResolutionPolicy.resolvedDimensions(
                width: max(1, Int(size.width.rounded(.up))), height: max(1, Int(size.height.rounded(.up))),
                hardLimit: pool.maxDimension, policy: .standard) else { return nil }
        return [resolved]
    }

    func hasReflectionConsumers(
        imageTextures: SceneBaseImageTextureSnapshot,
        framePlans: [Int: SceneResolvedMaterialFrameTargetPlan],
        visibleLayerIDs: Set<Int>, orderedLayers: [SceneRenderDescriptor.Layer]
    ) -> Bool {
        orderedLayers.contains { layer in
            guard visibleLayerIDs.contains(layer.id) || framePlans[layer.id] != nil,
                  imageTextures.geometryProducts[layer.id] == nil,
                  let profile = baseMaterialProviderBindings.lightingProfileByLayerID[layer.id],
                  profile.reflection != nil, let asset = profile.normalAsset,
                  case .ready = SceneBaseMaterialLitCapturePayload.TextureInput.resolve(
                    textureRegistry.lookup(.asset(asset))) else { return false }
            return true
        }
    }

    func reserveOptionalEffectScratch(
        requiresShadow: Bool, pool: SceneOffscreenTexturePool, imageTextures: SceneBaseImageTextureSnapshot,
        frameContext: SceneFrameContext, framePlans: [Int: SceneResolvedMaterialFrameTargetPlan],
        visibleLayerIDs: Set<Int>, orderedLayers: [SceneRenderDescriptor.Layer],
        worldFrames: [Int: simd_float4x4], cameraFrame: SceneParticleCameraFrame,
        parallax: SceneLayerParallax.Configuration, terminalExtent: (width: Int, height: Int)?,
        commandBuffer: MTLCommandBuffer
    ) -> [SceneOffscreenTexturePool.PinnedTexture]? {
        guard requiresShadow || hasReflectionConsumers(imageTextures: imageTextures,
            framePlans: framePlans, visibleLayerIDs: visibleLayerIDs,
            orderedLayers: orderedLayers) else { return nil }
        var dimensions: [(width: Int, height: Int)] = []
        if let terminalExtent { dimensions.append(terminalExtent) }
        for layer in orderedLayers where visibleLayerIDs.contains(layer.id) && framePlans[layer.id] == nil {
            guard let required = compositionScratchDimensions(for: layer, pool: pool,
                imageTextures: imageTextures, frameContext: frameContext, worldFrames: worldFrames,
                cameraFrame: cameraFrame, parallax: parallax) else { return nil }
            dimensions.append(contentsOf: required)
        }
        return pool.reserveCompositionTargets(dimensions: dimensions, commandBuffer: commandBuffer)
    }

}
