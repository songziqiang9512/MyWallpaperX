import CoreGraphics
import Metal
import simd

extension SceneMetalRenderer {
    func admitResolvedMaterialFrameTargets(
        imageTextures: SceneBaseImageTextureSnapshot,
        dynamicTextRenderSizes: [Int: [Float]],
        spriteAnimations: [Int: SceneSpriteAnimation],
        effectTextures: SceneLayerEffectTextureStore,
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
        commandBuffer: MTLCommandBuffer
    ) -> [Int: SceneResolvedMaterialFrameTargetPlan]? {
        switch preflightResolvedMaterialFrameTargets(
            imageTextures: imageTextures,
            dynamicTextRenderSizes: dynamicTextRenderSizes,
            offscreenTexturePool: offscreenTexturePool,
            frameContext: frameContext,
            worldFramesByLayerID: worldFramesByLayerID,
            cameraFrame: cameraFrame,
            parallaxConfiguration: parallaxConfiguration,
            commandBuffer: commandBuffer
        ) {
        case .ready(let plans):
            beginTextureFrame(
                imageTextures, userPropertyTextures, userPropertyStates,
                mediaThumbnail, frameContext
            )
            guard let requests = resolvedMaterialFramePreparationRequests(
                plans: plans,
                imageTextures: imageTextures,
                dynamicTextRenderSizes: dynamicTextRenderSizes,
                spriteAnimations: spriteAnimations,
                effectTextures: effectTextures,
                imagePipeline: imagePipeline,
                offscreenTexturePool: offscreenTexturePool,
                frameContext: frameContext,
                worldFramesByLayerID: worldFramesByLayerID,
                cameraFrame: cameraFrame,
                parallaxConfiguration: parallaxConfiguration
            ) else {
                imageCompositor.recordResolvedMaterialFramePreflightFailure(
                    "frame-preparation-request-invalid"
                )
                _ = imageCompositor.endResolvedMaterialFrame(on: commandBuffer)
                return nil
            }
            switch imageCompositor.prepareResolvedMaterialFrame(
                requests,
                pool: offscreenTexturePool,
                commandBuffer: commandBuffer
            ) {
            case .ready:
                break
            case .rejected:
                _ = imageCompositor.endResolvedMaterialFrame(on: commandBuffer)
                return nil
            }
            return plans
        case .deferred:
            return nil
        case .rejected(let reasonCode):
            beginTextureFrame(
                imageTextures, userPropertyTextures, userPropertyStates,
                mediaThumbnail, frameContext
            )
            imageCompositor.recordResolvedMaterialFramePreflightFailure(reasonCode)
            _ = imageCompositor.endResolvedMaterialFrame(on: commandBuffer)
            return nil
        }
    }

    func preflightResolvedMaterialFrameTargets(
        imageTextures: SceneBaseImageTextureSnapshot,
        dynamicTextRenderSizes: [Int: [Float]],
        offscreenTexturePool: SceneOffscreenTexturePool?,
        frameContext: SceneFrameContext,
        worldFramesByLayerID: [Int: simd_float4x4],
        cameraFrame: SceneParticleCameraFrame,
        parallaxConfiguration: SceneLayerParallax.Configuration,
        commandBuffer: MTLCommandBuffer
    ) -> SceneResolvedMaterialGraphComposition.FramePreflightResult {
        let viewportSize = frameContext.screenSize
        let orderedLayers = renderDescriptor.renderOrderLayerIDs.compactMap {
            layersByID[$0]
        }
        var requests: [
            SceneResolvedMaterialGraphComposition.FrameTargetRequest
        ] = []
        for layer in orderedLayers {
            let route = imageCompositor.preflightResolvedMaterialClaim(
                layerID: layer.id
            )
            let claim: SceneResolvedMaterialRuntimeBridge.ClaimedExecution
            switch route {
            case .legacy:
                continue
            case let .rejected(reasonCode):
                return .rejected(reasonCode: reasonCode)
            case let .claimed(value):
                claim = value
            }
            guard let texture = imageTextures[layer.id] else {
                return .deferred
            }
            let desiredSize: CGSize
            if layer.contentKind == "solid" {
                let model = imageModelMatrix(
                    for: layer,
                    worldFramesByLayerID: worldFramesByLayerID,
                    renderSizeOverride: dynamicTextRenderSizes[layer.id],
                    parallaxMouseNormalized: frameContext.cameraParallaxPosition,
                    configuration: parallaxConfiguration,
                    visibleHalfExtents: cameraFrame.coverHalfExtents
                )
                guard let projectedSize =
                    SceneCaptureGeometryResolver.projectedPixelSize(
                    layerMVP: cameraFrame.orthographicViewProjection * model,
                    viewportSize: viewportSize
                    ) else {
                    return .rejected(
                        reasonCode: "solid-offscreen-size-unavailable"
                    )
                }
                desiredSize = projectedSize
            } else {
                desiredSize = CGSize(width: texture.width, height: texture.height)
            }
            requests.append(.init(
                claim: claim,
                fullFrameExtentPolicy: claim.fullFrameExtentPolicy,
                requestedWidth: max(1, Int(desiredSize.width.rounded(.up))),
                requestedHeight: max(1, Int(desiredSize.height.rounded(.up)))
            ))
        }
        guard !requests.isEmpty else { return .ready([:]) }
        guard let offscreenTexturePool else {
            return .rejected(reasonCode: "frame-target-pool-unavailable")
        }
        return SceneResolvedMaterialGraphComposition.preflight(
            requests: requests,
            pool: offscreenTexturePool,
            commandBuffer: commandBuffer
        )
    }

    func resolvedMaterialFramePreparationRequests(
        plans: [Int: SceneResolvedMaterialFrameTargetPlan],
        imageTextures: SceneBaseImageTextureSnapshot,
        dynamicTextRenderSizes: [Int: [Float]],
        spriteAnimations: [Int: SceneSpriteAnimation],
        effectTextures: SceneLayerEffectTextureStore,
        imagePipeline: SceneImageLayerPipeline?,
        offscreenTexturePool: SceneOffscreenTexturePool?,
        frameContext: SceneFrameContext,
        worldFramesByLayerID: [Int: simd_float4x4],
        cameraFrame: SceneParticleCameraFrame,
        parallaxConfiguration: SceneLayerParallax.Configuration
    ) -> [SceneResolvedMaterialRuntimeBridge.FramePreparationRequest]? {
        guard !plans.isEmpty else { return [] }
        guard let imagePipeline, let offscreenTexturePool else { return nil }
        let time = Float(frameContext.sceneTime)
        var result: [SceneResolvedMaterialRuntimeBridge.FramePreparationRequest] = []
        for layerID in renderDescriptor.renderOrderLayerIDs {
            guard let plan = plans[layerID] else { continue }
            guard let layer = layersByID[layerID],
                  let texture = imageTextures[layerID] else { return nil }
            let route = imageCompositor.preflightResolvedMaterialClaim(
                layerID: layerID
            )
            guard case let .claimed(claim) = route,
                  claim.token == plan.token else { return nil }
            let model = imageModelMatrix(
                for: layer,
                worldFramesByLayerID: worldFramesByLayerID,
                renderSizeOverride: dynamicTextRenderSizes[layerID],
                parallaxMouseNormalized: frameContext.cameraParallaxPosition,
                configuration: parallaxConfiguration,
                visibleHalfExtents: cameraFrame.coverHalfExtents
            )
            let mvp = cameraFrame.orthographicViewProjection * model
            let cursor = SceneLayerCursorGeometry.layerUV(
                mouseNormalized: frameContext.pointer.current,
                modelViewProjection: mvp
            )
            let previousCursor = SceneLayerCursorGeometry.layerUV(
                mouseNormalized: frameContext.pointer.previous,
                modelViewProjection: mvp
            )
            let masks = effectMasks(for: layerID, in: effectTextures)
            let request = SceneImageLayerDrawRequest(
                layer: layer,
                texture: texture,
                baseTextureCandidate: imageTextures.candidate(
                    for: layerID, matching: texture
                ),
                masks: masks,
                textureFrame: spriteAnimations[layerID]?.transform(
                    at: time, wallDate: frameContext.wallDate
                ) ?? .identity,
                mvp: mvp,
                uniforms: .init(
                    time: time,
                    alpha: SceneDynamicLayerValues.alpha(
                        layerID: layerID,
                        authoredValue: layer.alpha,
                        snapshot: frameContext.dynamicValues
                    ),
                    cursorUV: cursor ?? .zero,
                    previousCursorUV: previousCursor ?? cursor ?? .zero,
                    cursorIsInside: frameContext.pointer.isInside && cursor != nil,
                    previousCursorIsInside:
                        frameContext.pointer.isInside && previousCursor != nil,
                    primaryButtonIsDown:
                        frameContext.pointer.isPrimaryButtonDown,
                    frameTime: Float(frameContext.frameTime),
                    tint: SceneDynamicLayerValues.color(
                        layerID: layerID,
                        authoredValue: layer.colorRGB,
                        snapshot: frameContext.dynamicValues
                    )
                ),
                offscreenTexturePool: offscreenTexturePool,
                resolvedMaterialFrameTargetPlan: plan,
                offscreenSize: layer.contentKind == "solid"
                    ? SceneCaptureGeometryResolver.projectedPixelSize(
                        layerMVP: mvp,
                        viewportSize: frameContext.screenSize
                    ) : nil,
                requiresSourceCopy: false,
                finalCompositeAlpha: nil,
                dependencyEffect: nil,
                authoredEffectPlan: nil,
                blocksLegacyGaussianBlur: false,
                authoredEffectChain: nil,
                dynamicValues: frameContext.dynamicValues,
                audioSpectrum: frameContext.audioSpectrum,
                authoredShaderFrameInputs: .init(frameContext: frameContext)
            )
            guard let sourceUniforms = imageCompositor.sourceFragmentUniforms(
                for: request,
                effectInputs: .neutral,
                routesOffscreen: true
            ) else { return nil }
            result.append(.init(
                claim: claim,
                targetPlan: plan,
                sourceTexture: texture,
                sourceUniforms: sourceUniforms,
                sourcePipeline: imagePipeline,
                dedicatedInputs: .init(
                    masks: masks.authoredEffectResourcesOnly,
                    dynamicValues: frameContext.dynamicValues,
                    pipelines: imageCompositor.authoredEffectPipelines,
                    cursorUV: cursor ?? .zero,
                    previousCursorUV: previousCursor ?? cursor ?? .zero,
                    pointerIsInside: frameContext.pointer.isInside && cursor != nil,
                    previousPointerIsInside:
                        frameContext.pointer.isInside && previousCursor != nil,
                    frameTime: Float(frameContext.frameTime),
                    time: time,
                    audioSpectrum: frameContext.audioSpectrum,
                    dependencyEffect: nil
                )
            ))
        }
        return result.count == plans.count ? result : nil
    }
}
