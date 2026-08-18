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
        mainTarget: MTLTexture,
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
        case let .ready(plans, localFallbacks):
            beginTextureFrame(
                imageTextures, userPropertyTextures, userPropertyStates,
                mediaThumbnail, frameContext
            )
            guard imageCompositor.installResolvedMaterialFrameLocalFallbacks(
                localFallbacks
            ) else {
                imageCompositor.recordResolvedMaterialFramePreflightFailure(
                    "frame-local-fallback-install-rejected"
                )
                _ = imageCompositor.endResolvedMaterialFrame(on: commandBuffer)
                return nil
            }
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
                parallaxConfiguration: parallaxConfiguration,
                mainTarget: mainTarget
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
        func materialFunctionInvocations(
            for layer: SceneRenderDescriptor.Layer
        ) -> [SceneGraphMaterialFunctionInvocationRequest] {
            frameContext.materialFunctionMutations
                .filter { $0.layerID == layer.id }
                .map { mutation in
                    let descriptorID: String
                    if layer.effects.indices.contains(mutation.effectIndex) {
                        descriptorID = layer.effects[mutation.effectIndex].id
                    } else {
                        descriptorID = "invalid-effect-index-\(mutation.effectIndex)"
                    }
                    return SceneGraphMaterialFunctionInvocationRequest(
                        effect: .init(
                            layerID: layer.id,
                            effectIndex: mutation.effectIndex,
                            descriptorID: descriptorID
                        ),
                        functionName: mutation.functionName,
                        frameEpoch: textureRegistry.frameEpoch
                    )
                }
        }
        for layer in orderedLayers {
            let route = imageCompositor.preflightResolvedMaterialClaim(
                layerID: layer.id
            )
            let claim: SceneResolvedMaterialRuntimeBridge.ClaimedExecution
            switch route {
            case .unclaimed:
                continue
            case let .localFallback(reasonCode):
                return .rejected(reasonCode: reasonCode)
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
            case .capturedMainTargetTexture:
                guard let utility = layer.utilityLayer,
                      layer.contentKind == utility.kind.rawValue,
                      layer.childLayerIDs.isEmpty else {
                    return .rejected(
                        reasonCode: "utility-source-shape-invalid"
                    )
                }
                let model = imageModelMatrix(
                    for: layer,
                    worldFramesByLayerID: worldFramesByLayerID,
                    parallaxMouseNormalized: frameContext.cameraParallaxPosition,
                    configuration: parallaxConfiguration,
                    visibleHalfExtents: cameraFrame.coverHalfExtents
                )
                guard let geometry = SceneCaptureGeometryResolver.resolve(
                    kind: utility.kind,
                    layerMVP: cameraFrame.orthographicViewProjection * model,
                    viewportSize: viewportSize
                ) else {
                    return .rejected(
                        reasonCode: "utility-offscreen-size-unavailable"
                    )
                }
                desiredSize = geometry.pixelSize
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
                requestedHeight: max(1, Int(desiredSize.height.rounded(.up))),
                materialFunctionInvocations: materialFunctionInvocations(for: layer)
            ))
        }
        guard !requests.isEmpty else {
            return .ready(plans: [:], localFallbacks: [:])
        }
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
        parallaxConfiguration: SceneLayerParallax.Configuration,
        mainTarget: MTLTexture
    ) -> [SceneResolvedMaterialRuntimeBridge.FramePreparationRequest]? {
        guard !plans.isEmpty else { return [] }
        guard let imagePipeline, offscreenTexturePool != nil else { return nil }
        let time = Float(frameContext.sceneTime)
        let imageMVP: (SceneRenderDescriptor.Layer, [Float]?) -> simd_float4x4 = {
            layer, renderSizeOverride in
            cameraFrame.orthographicViewProjection * self.imageModelMatrix(
                for: layer,
                worldFramesByLayerID: worldFramesByLayerID,
                renderSizeOverride: renderSizeOverride,
                parallaxMouseNormalized: frameContext.cameraParallaxPosition,
                configuration: parallaxConfiguration,
                visibleHalfExtents: cameraFrame.coverHalfExtents
            )
        }
        var result: [SceneResolvedMaterialRuntimeBridge.FramePreparationRequest] = []
        for layerID in renderDescriptor.renderOrderLayerIDs {
            guard let plan = plans[layerID] else { continue }
            guard let layer = layersByID[layerID],
                  let layerModelMatrix = worldFramesByLayerID[layerID] else {
                return nil
            }
            let route = imageCompositor.preflightResolvedMaterialClaim(
                layerID: layerID
            )
            guard case let .claimed(claim) = route,
                  claim.token == plan.token else { return nil }
            let dependencyEffect: SceneDependencyEffectInput?
            switch claim.dependencyOwnership {
            case .none, .graphInternal: dependencyEffect = nil
            case .externalPrimary(let binding):
                guard binding.consumerLayerID == layerID,
                      let providerLayer = layersByID[binding.providerLayerID] else {
                    return nil
                }
                let providerMVP = imageMVP(
                    providerLayer,
                    dynamicTextRenderSizes[providerLayer.id]
                )
                guard let reservedInput = dependencyRuntime.reserveEffectInput(
                    for: binding,
                    providerLayer: providerLayer,
                    providerTexture: imageTextures[binding.providerLayerID],
                    providerCandidate: imageTextures[binding.providerLayerID].flatMap {
                        imageTextures.candidate(
                            for: binding.providerLayerID,
                            matching: $0
                        )
                    },
                    layerMVP: providerMVP,
                    viewportSize: frameContext.screenSize,
                    frameEpoch: textureRegistry.frameEpoch
                ) else { return nil }
                dependencyEffect = reservedInput
            }
            let sourceMVP: simd_float4x4
            let outputMVP: simd_float4x4
            let sourceTexture: MTLTexture?
            let textureFrame: SceneTextureUVTransform
            let capturesMainTarget: Bool
            var sourceUniforms: SceneLayerFragmentUniforms? = nil
            switch claim.sourceRoute {
            case .capturedLayerTexture:
                guard let texture = imageTextures[layerID] else { return nil }
                sourceMVP = imageMVP(
                    layer,
                    dynamicTextRenderSizes[layerID]
                )
                outputMVP = sourceMVP
                sourceTexture = texture
                textureFrame = spriteAnimations[layerID]?.transform(at: time) ?? .identity
                capturesMainTarget = false
            case .capturedMainTargetTexture:
                guard let utility = layer.utilityLayer,
                      layer.contentKind == utility.kind.rawValue,
                      layer.childLayerIDs.isEmpty else { return nil }
                sourceMVP = imageMVP(layer, nil)
                guard let geometry = SceneCaptureGeometryResolver.resolve(
                    kind: utility.kind,
                    layerMVP: sourceMVP,
                    viewportSize: frameContext.screenSize
                ) else { return nil }
                outputMVP = geometry.outputMVP
                sourceTexture = mainTarget
                textureFrame = geometry.sourceUV
                capturesMainTarget = true
            case .transparentDirectDraw:
                guard layer.contentKind == "quad",
                      let directDrawModel = lightShaftsModelMatrix(
                          for: layer,
                          worldFramesByLayerID: worldFramesByLayerID,
                          parallaxMouseNormalized:
                              frameContext.cameraParallaxPosition,
                          configuration: parallaxConfiguration
                      ) else { return nil }
                sourceMVP = cameraFrame.orthographicViewProjection * directDrawModel
                outputMVP = sourceMVP
                sourceTexture = nil
                textureFrame = .identity
                capturesMainTarget = false
            }
            guard let effectTextureProjectionMatrixInverse =
                    SceneLayerCursorGeometry.effectProjectionInverse(
                        outputMVP,
                        required: claim.requiresInvertibleEffectTextureProjection
                    ) else { return nil }
            let cursor = SceneLayerCursorGeometry.layerUV(
                mouseNormalized: frameContext.pointer.current,
                modelViewProjection: sourceMVP
            )
            let previousCursor = SceneLayerCursorGeometry.layerUV(
                mouseNormalized: frameContext.pointer.previous,
                modelViewProjection: sourceMVP
            )
            let masks = effectMasks(for: layerID, in: effectTextures)
            if let texture = sourceTexture {
                let request = SceneImageLayerDrawRequest(
                    layer: layer,
                    texture: texture,
                    baseTextureCandidate: capturesMainTarget ? nil
                        : imageTextures.candidate(for: layerID, matching: texture),
                    masks: masks,
                    textureFrame: textureFrame,
                    mvp: outputMVP,
                    uniforms: .init(
                        time: time,
                        alpha: capturesMainTarget ? 1 : SceneDynamicLayerValues.alpha(
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
                        tint: capturesMainTarget ? SIMD3(repeating: 1)
                            : SceneDynamicLayerValues.color(
                            layerID: layerID,
                            authoredValue: layer.colorRGB,
                            snapshot: frameContext.dynamicValues
                        )
                    ),
                    offscreenTexturePool: nil,
                    offscreenSize: nil,
                    requiresSourceCopy: false,
                    finalCompositeAlpha: nil,
                    dependencyEffect: nil
                )
                guard let uniforms = imageCompositor.sourceFragmentUniforms(
                    for: request,
                    routesOffscreen: true
                ) else { return nil }
                sourceUniforms = uniforms
            }
            let sceneBackgroundResource: SceneFrameTextureResource?
            if let requirement = claim.sceneBackgroundRequirement {
                guard requirement.layerID == layerID,
                      let resource = SceneFrameTextureResource
                        .sameFrameSceneBackground(
                            consumerLayerID: layerID,
                            frameEpoch: textureRegistry.frameEpoch,
                            texture: mainTarget
                        ) else { return nil }
                sceneBackgroundResource = resource
            } else {
                sceneBackgroundResource = nil
            }
            let dedicatedInputs =
                SceneResolvedMaterialRuntimeBridge.DedicatedFrameInputs(
                    masks: masks,
                    dynamicValues: frameContext.dynamicValues,
                    pipelines: imageCompositor.authoredEffectPipelines,
                    cursorUV: cursor ?? .zero,
                    previousCursorUV: previousCursor ?? cursor ?? .zero,
                    pointerIsInside: frameContext.pointer.isInside && cursor != nil,
                    previousPointerIsInside:
                        frameContext.pointer.isInside && previousCursor != nil,
                    pointerMovement: simd_length(
                        frameContext.pointer.current - frameContext.pointer.previous
                    ) * 0.5,
                    primaryButtonIsDown:
                        frameContext.pointer.isPrimaryButtonDown,
                    layerModelMatrix: layerModelMatrix,
                    effectTextureProjectionMatrixInverse:
                        effectTextureProjectionMatrixInverse,
                    frameTime: Float(frameContext.frameTime),
                    time: time,
                    audioSpectrum: frameContext.audioSpectrum,
                    dependencyEffect: dependencyEffect
                )
            let materialFunctionInvocations = frameContext.materialFunctionMutations
                .filter { $0.layerID == layerID }
                .map { mutation in
                    let descriptorID: String
                    if layer.effects.indices.contains(mutation.effectIndex) {
                        descriptorID = layer.effects[mutation.effectIndex].id
                    } else {
                        descriptorID = "invalid-effect-index-\(mutation.effectIndex)"
                    }
                    return SceneGraphMaterialFunctionInvocationRequest(
                        effect: .init(
                            layerID: layerID,
                            effectIndex: mutation.effectIndex,
                            descriptorID: descriptorID
                        ),
                        functionName: mutation.functionName,
                        frameEpoch: textureRegistry.frameEpoch
                    )
                }
            let request = SceneResolvedMaterialRuntimeBridge.FramePreparationRequest(
                claim: claim,
                targetPlan: plan,
                materialFunctionInvocations: materialFunctionInvocations,
                sceneBackgroundResource: sceneBackgroundResource,
                sourceTexture: sourceTexture,
                sourceUniforms: sourceUniforms,
                sourcePipeline: imagePipeline,
                dedicatedInputs: dedicatedInputs
            )
            result.append(request)
        }
        return result.count == plans.count ? result : nil
    }
}
