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
            let desiredSize: CGSize
            switch claim.sourceRoute {
            case .capturedLayerTexture:
                guard let texture = imageTextures[layer.id] else {
                    return .deferred
                }
                if layer.contentKind != "solid" {
                    desiredSize = CGSize(
                        width: texture.width,
                        height: texture.height
                    )
                    break
                }
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
            case .transparentDirectDraw:
                guard layer.contentKind == "quad",
                      let model = lightShaftsModelMatrix(
                          for: layer,
                          worldFramesByLayerID: worldFramesByLayerID,
                          parallaxMouseNormalized:
                              frameContext.cameraParallaxPosition,
                          configuration: parallaxConfiguration
                      ), let projectedSize =
                        SceneCaptureGeometryResolver.projectedPixelSize(
                            layerMVP: cameraFrame.orthographicViewProjection * model,
                            viewportSize: viewportSize
                        ) else {
                    return .rejected(
                        reasonCode: "direct-draw-offscreen-size-unavailable"
                    )
                }
                desiredSize = projectedSize
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
        guard let imagePipeline, offscreenTexturePool != nil else { return nil }
        let time = Float(frameContext.sceneTime)
        var result: [SceneResolvedMaterialRuntimeBridge.FramePreparationRequest] = []
        for layerID in renderDescriptor.renderOrderLayerIDs {
            guard let plan = plans[layerID] else { continue }
            guard let layer = layersByID[layerID] else { return nil }
            let route = imageCompositor.preflightResolvedMaterialClaim(
                layerID: layerID
            )
            guard case let .claimed(claim) = route,
                  claim.token == plan.token else { return nil }
            let model: simd_float4x4
            let sourceTexture: MTLTexture?
            var sourceUniforms: SceneLayerFragmentUniforms?
            switch claim.sourceRoute {
            case .capturedLayerTexture:
                guard let texture = imageTextures[layerID] else { return nil }
                model = imageModelMatrix(
                    for: layer,
                    worldFramesByLayerID: worldFramesByLayerID,
                    renderSizeOverride: dynamicTextRenderSizes[layerID],
                    parallaxMouseNormalized: frameContext.cameraParallaxPosition,
                    configuration: parallaxConfiguration,
                    visibleHalfExtents: cameraFrame.coverHalfExtents
                )
                sourceTexture = texture
                sourceUniforms = nil
            case .transparentDirectDraw:
                guard layer.contentKind == "quad",
                      let directDrawModel = lightShaftsModelMatrix(
                          for: layer,
                          worldFramesByLayerID: worldFramesByLayerID,
                          parallaxMouseNormalized:
                              frameContext.cameraParallaxPosition,
                          configuration: parallaxConfiguration
                      ) else { return nil }
                model = directDrawModel
                sourceTexture = nil
                sourceUniforms = nil
            }
            let mvp = cameraFrame.orthographicViewProjection * model
            guard let effectTextureProjectionMatrixInverse =
                    SceneLayerCursorGeometry.inverseModelViewProjection(mvp) else {
                return nil
            }
            let cursor = SceneLayerCursorGeometry.layerUV(
                mouseNormalized: frameContext.pointer.current,
                modelViewProjection: mvp
            )
            let previousCursor = SceneLayerCursorGeometry.layerUV(
                mouseNormalized: frameContext.pointer.previous,
                modelViewProjection: mvp
            )
            let masks = effectMasks(for: layerID, in: effectTextures)
            if claim.sourceRoute == .capturedLayerTexture {
                guard let texture = sourceTexture else { return nil }
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
                        cursorIsInside:
                            frameContext.pointer.isInside && cursor != nil,
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
                    offscreenTexturePool: nil,
                    offscreenSize: nil,
                    requiresSourceCopy: false,
                    finalCompositeAlpha: nil,
                    dependencyEffect: nil,
                    authoredEffectPlan: nil,
                    blocksLegacyGaussianBlur: false
                )
                guard let uniforms = imageCompositor.sourceFragmentUniforms(
                    for: request,
                    effectInputs: .neutral,
                    routesOffscreen: true
                ) else { return nil }
                sourceUniforms = uniforms
            }
            result.append(.init(
                claim: claim,
                targetPlan: plan,
                sourceTexture: sourceTexture,
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
                    effectTextureProjectionMatrixInverse:
                        effectTextureProjectionMatrixInverse,
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
