import CoreGraphics
import Metal
import simd

extension SceneMetalRenderer {
    func admitResolvedMaterialFrameTargets(
        imageTextures: SceneBaseImageTextureSnapshot,
        spriteAnimations: [Int: SceneSpriteAnimation],
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
        // Publish this frame's typed resources before target sizing or source
        // admission. Otherwise preflight reads a stale/empty registry while
        // preparation later encodes the current provider into that target.
        beginTextureFrame(
            imageTextures, userPropertyTextures, userPropertyStates,
            mediaThumbnail, frameContext
        )
        switch preflightResolvedMaterialFrameTargets(
            imageTextures: imageTextures,
            offscreenTexturePool: offscreenTexturePool,
            frameContext: frameContext,
            worldFramesByLayerID: worldFramesByLayerID,
            cameraFrame: cameraFrame,
            parallaxConfiguration: parallaxConfiguration,
            commandBuffer: commandBuffer
        ) {
        case let .ready(plans, localFallbacks):
            guard imageCompositor.installResolvedMaterialFrameLocalFallbacks(
                localFallbacks
            ) else {
                imageCompositor.recordResolvedMaterialFramePreflightFailure(
                    "frame-local-fallback-install-rejected"
                )
                _ = imageCompositor.endResolvedMaterialFrame(on: commandBuffer)
                return nil
            }
            var requestFailureReason: String?
            guard let requests = resolvedMaterialFramePreparationRequests(
                plans: plans,
                imageTextures: imageTextures,
                spriteAnimations: spriteAnimations,
                imagePipeline: imagePipeline,
                offscreenTexturePool: offscreenTexturePool,
                frameContext: frameContext,
                worldFramesByLayerID: worldFramesByLayerID,
                cameraFrame: cameraFrame,
                parallaxConfiguration: parallaxConfiguration,
                mainTarget: mainTarget,
                failureReason: &requestFailureReason
            ) else {
                imageCompositor.recordResolvedMaterialFramePreflightFailure(
                    requestFailureReason ?? "frame-preparation-request-invalid"
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
                    return nil
                }
            case .rejected:
                _ = imageCompositor.endResolvedMaterialFrame(on: commandBuffer)
                return nil
            }
            return plans
        case .deferred:
            _ = imageCompositor.deferResolvedMaterialFrame()
            _ = imageCompositor.endResolvedMaterialFrame(on: commandBuffer)
            return nil
        case .rejected(let reasonCode):
            imageCompositor.recordResolvedMaterialFramePreflightFailure(reasonCode)
            _ = imageCompositor.endResolvedMaterialFrame(on: commandBuffer)
            return nil
        }
    }

    func preflightResolvedMaterialFrameTargets(
        imageTextures: SceneBaseImageTextureSnapshot,
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
        var sourceCoverageFallbacks: [Int: String] = [:]
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
                let selection = baseMaterialTextureSelection(
                    for: layer,
                    imageTextures: imageTextures,
                    readyProviderUsesAuthoredLayerColor:
                        baseMaterialReadyProviderUsesAuthoredLayerColor(
                            for: layer,
                            dynamicValues: frameContext.dynamicValues
                        )
                )
                let selectedSource: SceneBaseMaterialTextureSource
                switch selection {
                case let .source(value):
                    selectedSource = value
                case .missing:
                    return .deferred
                case let .rejected(reasonCode):
                    return .rejected(reasonCode: reasonCode)
                }
                if layer.contentKind != "solid" {
                    desiredSize = CGSize(
                        width: selectedSource.texture.width,
                        height: selectedSource.texture.height
                    )
                    break
                }
                let model = imageModelMatrix(
                    for: layer,
                    worldFramesByLayerID: worldFramesByLayerID,
                    renderSizeOverride: imageTextures.layerSourceRenderSize(
                        for: layer.id
                    ),
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
                      case let .success(sourceRoute) =
                        SceneUtilityLayerSourceRoute.resolve(
                          layer: layer,
                          descriptor: renderDescriptor
                      ) else {
                    return .rejected(
                        reasonCode: "utility-source-shape-invalid"
                    )
                }
                if sourceRoute.capturesCompositionSubtree,
                   !hasOpaqueFullViewportUtilitySource(
                       route: sourceRoute,
                       imageTextures: imageTextures,
                       frameContext: frameContext,
                       worldFramesByLayerID: worldFramesByLayerID,
                       cameraFrame: cameraFrame,
                       parallaxConfiguration: parallaxConfiguration
                   ) {
                    sourceCoverageFallbacks[layer.id] =
                        "utility-composition-subtree-source-coverage-unavailable"
                    continue
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
            return .ready(
                plans: [:],
                localFallbacks: sourceCoverageFallbacks
            )
        }
        guard let offscreenTexturePool else {
            return .rejected(reasonCode: "frame-target-pool-unavailable")
        }
        let result = SceneResolvedMaterialGraphComposition.preflight(
            requests: requests,
            pool: offscreenTexturePool,
            commandBuffer: commandBuffer
        )
        guard case let .ready(plans, localFallbacks) = result else {
            return result
        }
        var mergedFallbacks = sourceCoverageFallbacks
        mergedFallbacks.merge(localFallbacks) { _, graphReason in graphReason }
        return .ready(plans: plans, localFallbacks: mergedFallbacks)
    }

    func resolvedMaterialFramePreparationRequests(
        plans: [Int: SceneResolvedMaterialFrameTargetPlan],
        imageTextures: SceneBaseImageTextureSnapshot,
        spriteAnimations: [Int: SceneSpriteAnimation],
        imagePipeline: SceneImageLayerPipeline?,
        offscreenTexturePool: SceneOffscreenTexturePool?,
        frameContext: SceneFrameContext,
        worldFramesByLayerID: [Int: simd_float4x4],
        cameraFrame: SceneParticleCameraFrame,
        parallaxConfiguration: SceneLayerParallax.Configuration,
        mainTarget: MTLTexture,
        failureReason: inout String?
    ) -> [SceneResolvedMaterialRuntimeBridge.FramePreparationRequest]? {
        func invalid(_ reasonCode: String) -> [
            SceneResolvedMaterialRuntimeBridge.FramePreparationRequest
        ]? {
            failureReason = "frame-preparation-request-invalid:\(reasonCode)"
            return nil
        }
        guard !plans.isEmpty else { return [] }
        guard let imagePipeline, offscreenTexturePool != nil else {
            return invalid("shared-input-unavailable")
        }
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
                return invalid("layer-\(layerID)-world-frame-missing")
            }
            let route = imageCompositor.preflightResolvedMaterialClaim(
                layerID: layerID
            )
            guard case let .claimed(claim) = route,
                  claim.token == plan.token else {
                return invalid("layer-\(layerID)-claim-token-mismatch")
            }
            let dependencyEffect: SceneDependencyEffectInput?
            switch claim.dependencyOwnership {
            case .none, .graphInternal: dependencyEffect = nil
            case .externalPrimary(let binding):
                guard binding.consumerLayerID == layerID,
                      let providerLayer = layersByID[binding.providerLayerID] else {
                    return invalid("layer-\(layerID)-dependency-binding-invalid")
                }
                let providerMVP = imageMVP(
                    providerLayer,
                    imageTextures.layerSourceRenderSize(for: providerLayer.id)
                )
                let providerSelection = baseMaterialTextureSelection(
                    for: providerLayer,
                    imageTextures: imageTextures,
                    readyProviderUsesAuthoredLayerColor:
                        baseMaterialReadyProviderUsesAuthoredLayerColor(
                            for: providerLayer,
                            dynamicValues: frameContext.dynamicValues
                        )
                )
                guard let providerSource = providerSelection.source else {
                    return invalid(
                        "layer-\(layerID)-dependency-provider-source-"
                            + (providerSelection.rejectedProviderReason
                                ?? "missing")
                    )
                }
                var dependencyFailureReason: String?
                guard let reservedInput = dependencyRuntime.reserveEffectInput(
                    for: binding,
                    providerLayer: providerLayer,
                    providerTexture: providerSource.texture,
                    providerCandidate: providerSource.candidate,
                    layerMVP: providerMVP,
                    viewportSize: frameContext.screenSize,
                    frameEpoch: textureRegistry.frameEpoch,
                    failureReason: &dependencyFailureReason
                ) else {
                    return invalid(
                        "layer-\(layerID)-dependency-input-invalid"
                            + (dependencyFailureReason.map { "-\($0)" } ?? "")
                    )
                }
                dependencyEffect = reservedInput
            }
            let sourceMVP: simd_float4x4
            let outputMVP: simd_float4x4
            let sourceTexture: MTLTexture?
            let sourceCandidate: SceneTextureCandidate?
            let sourceUsesAuthoredLayerColor: Bool
            let textureFrame: SceneTextureUVTransform
            let capturesMainTarget: Bool
            var sourceUniforms: SceneLayerFragmentUniforms? = nil
            switch claim.sourceRoute {
            case .capturedLayerTexture:
                let sourceSelection = baseMaterialTextureSelection(
                    for: layer,
                    imageTextures: imageTextures,
                    readyProviderUsesAuthoredLayerColor:
                        baseMaterialReadyProviderUsesAuthoredLayerColor(
                            for: layer,
                            dynamicValues: frameContext.dynamicValues
                        )
                )
                guard let source = sourceSelection.source else {
                    return invalid(
                        "layer-\(layerID)-source-texture-"
                            + (sourceSelection.rejectedProviderReason ?? "missing")
                    )
                }
                sourceMVP = imageMVP(
                    layer,
                    imageTextures.layerSourceRenderSize(for: layerID)
                )
                outputMVP = sourceMVP
                sourceTexture = source.texture
                sourceCandidate = source.candidate
                sourceUsesAuthoredLayerColor = source.usesAuthoredLayerColor
                textureFrame = spriteAnimations[layerID]?.transform(at: time) ?? .identity
                capturesMainTarget = false
            case .capturedMainTargetTexture:
                guard let utility = layer.utilityLayer,
                      layer.contentKind == utility.kind.rawValue,
                      case .success = SceneUtilityLayerSourceRoute.resolve(
                          layer: layer,
                          descriptor: renderDescriptor
                      ) else {
                    return invalid("layer-\(layerID)-utility-source-shape-invalid")
                }
                sourceMVP = imageMVP(layer, nil)
                guard let geometry = SceneCaptureGeometryResolver.resolve(
                    kind: utility.kind,
                    layerMVP: sourceMVP,
                    viewportSize: frameContext.screenSize
                ) else {
                    return invalid("layer-\(layerID)-utility-geometry-invalid")
                }
                outputMVP = geometry.outputMVP
                sourceTexture = mainTarget
                sourceCandidate = nil
                sourceUsesAuthoredLayerColor = false
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
                      ) else {
                    return invalid("layer-\(layerID)-direct-draw-model-invalid")
                }
                sourceMVP = cameraFrame.orthographicViewProjection * directDrawModel
                outputMVP = sourceMVP
                sourceTexture = nil
                sourceCandidate = nil
                sourceUsesAuthoredLayerColor = false
                textureFrame = .identity
                capturesMainTarget = false
            }
            guard let effectTextureProjectionMatrixInverse =
                    SceneLayerCursorGeometry.effectProjectionInverse(
                        outputMVP,
                        required: claim.requiresInvertibleEffectTextureProjection
                    ) else {
                return invalid("layer-\(layerID)-effect-projection-inverse-invalid")
            }
            let cursor = SceneLayerCursorGeometry.layerUV(
                mouseNormalized: frameContext.pointer.current,
                modelViewProjection: sourceMVP
            )
            let previousCursor = SceneLayerCursorGeometry.layerUV(
                mouseNormalized: frameContext.pointer.previous,
                modelViewProjection: sourceMVP
            )
            if let texture = sourceTexture {
                let request = SceneImageLayerDrawRequest(
                    layer: layer,
                    texture: texture,
                    baseTextureCandidate: sourceCandidate,
                    masks: .empty,
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
                        tint: capturesMainTarget || !sourceUsesAuthoredLayerColor
                            ? SIMD3(repeating: 1)
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
                ) else {
                    return invalid("layer-\(layerID)-source-uniforms-invalid")
                }
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
                        ) else {
                    return invalid("layer-\(layerID)-scene-background-invalid")
                }
                sceneBackgroundResource = resource
            } else {
                sceneBackgroundResource = nil
            }
            let frameInputs = SceneResolvedMaterialRuntimeBridge.FrameInputs(
                dynamicValues: frameContext.dynamicValues,
                cursorUV: cursor ?? .zero,
                previousCursorUV: previousCursor ?? cursor ?? .zero,
                pointerIsInside: frameContext.pointer.isInside && cursor != nil,
                previousPointerIsInside:
                    frameContext.pointer.isInside && previousCursor != nil,
                pointerMovement: simd_length(
                    frameContext.pointer.current - frameContext.pointer.previous
                ) * 0.5,
                primaryButtonIsDown: frameContext.pointer.isPrimaryButtonDown,
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
                frameInputs: frameInputs
            )
            result.append(request)
        }
        guard result.count == plans.count else {
            return invalid("plan-count-mismatch")
        }
        return result
    }
}
