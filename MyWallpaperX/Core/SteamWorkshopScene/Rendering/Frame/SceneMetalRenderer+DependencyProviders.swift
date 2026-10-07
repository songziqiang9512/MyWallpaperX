import CoreGraphics
import Metal
import simd

extension SceneMetalRenderer {
    /// Resolves the complete dependency input vector for one image draw. The
    /// aggregate path remains lossless; a missing or invalid member falls
    /// through to the same typed failure used by the legacy single input.
    func resolveDependencyEffectInputs(
        layerID: Int,
        requiresDependencyEffect: Bool,
        hasResolvedFramePlan: Bool,
        bypassReason: String?,
        dependencyRuntime: SceneDependencyFrameRuntime,
        textureRegistry: SceneFrameTextureRegistry
    ) -> (
        dependencyEffects: [SceneDependencyEffectInput],
        failure: (reasonCode: String, isOrdinaryUnavailable: Bool)?
    ) {
        if bypassReason != nil {
            return ([], nil)
        }
        if requiresDependencyEffect, hasResolvedFramePlan {
            if let aggregate = dependencyRuntime.plan
                .multiProviderAggregatesByConsumerLayerID[layerID] {
                switch dependencyRuntime.aggregateEffectInputResolution(
                    for: aggregate,
                    textureRegistry: textureRegistry
                ) {
                case let .ready(inputs):
                    return (inputs, nil)
                case let .unavailable(reasonCode):
                    return ([], (reasonCode, true))
                case let .invalid(reasonCode):
                    return ([], (reasonCode, false))
                }
            }
            switch dependencyRuntime.resolvedMaterialEffectInputResolution(
                for: layerID,
                textureRegistry: textureRegistry
            ) {
            case let .ready(input):
                return ([input], nil)
            case let .unavailable(reasonCode):
                return ([], (reasonCode, true))
            case let .invalid(reasonCode):
                return ([], (reasonCode, false))
            }
        }
        return (
            dependencyRuntime.effectInput(
                for: layerID,
                textureRegistry: textureRegistry
            ).map { [$0] } ?? [],
            nil
        )
    }

    /// Executes an effectful hidden dependency provider through the same
    /// resolved graph runtime as a visible image layer, then publishes that
    /// intermediate output to the existing named-target registry. It never
    /// composites the hidden provider directly into the main target.
    func executeDependencyGraphProviderIfRequired(
        layer: SceneRenderDescriptor.Layer,
        isVisibleExecutionRoot: Bool,
        framePlan: SceneResolvedMaterialFrameTargetPlan?,
        textureRegistry: SceneFrameTextureRegistry,
        dependencyRuntime: SceneDependencyFrameRuntime,
        mainPass: SceneMainPassEncoder,
        commandBuffer: MTLCommandBuffer,
        geometryProduct: SceneGeometryProduct? = nil,
        imagePipeline: SceneImageLayerPipeline? = nil,
        executionTrace: SceneEffectExecutionFrameTrace?
    ) -> Bool? {
        guard dependencyRuntime.requiresDemandedGraphOutputCapture(
            for: layer.id
        ) else { return nil }
        guard !isVisibleExecutionRoot else { return nil }
        // A visual frame-local fallback intentionally publishes nothing. Any
        // downstream consumer then takes the ordinary provider-miss path.
        guard framePlan != nil else { return true }

        let dependencyBypassReason = imageCompositor
            .preparedResolvedMaterialExternalDependencyBypassReason(
                layerID: layer.id
            )
        var dependencyEffects: [SceneDependencyEffectInput] = []
        if dependencyRuntime.requiresEffect(for: layer.id),
           dependencyBypassReason == nil {
            if let aggregate = dependencyRuntime.plan
                .multiProviderAggregatesByConsumerLayerID[layer.id] {
                switch dependencyRuntime.aggregateEffectInputResolution(
                    for: aggregate,
                    textureRegistry: textureRegistry
                ) {
                case let .ready(inputs):
                    dependencyEffects = inputs
                case let .unavailable(reasonCode):
                    dependencyRuntime.recordBindingFailure(for: layer.id)
                    return imageCompositor
                        .rejectResolvedMaterialDependencySubgraphLocally(
                            layerID: layer.id,
                            reasonCode: reasonCode
                        )
                case let .invalid(reasonCode):
                    dependencyRuntime.recordBindingFailure(for: layer.id)
                    imageCompositor.recordResolvedMaterialFramePreflightFailure(
                        reasonCode
                    )
                    return false
                }
            } else {
                switch dependencyRuntime.resolvedMaterialEffectInputResolution(
                    for: layer.id,
                    textureRegistry: textureRegistry
                ) {
                case let .ready(input):
                    dependencyEffects = [input]
                case let .unavailable(reasonCode):
                    dependencyRuntime.recordBindingFailure(for: layer.id)
                    return imageCompositor
                        .rejectResolvedMaterialDependencySubgraphLocally(
                            layerID: layer.id,
                            reasonCode: reasonCode
                        )
                case let .invalid(reasonCode):
                    dependencyRuntime.recordBindingFailure(for: layer.id)
                    imageCompositor.recordResolvedMaterialFramePreflightFailure(
                        reasonCode
                    )
                    return false
                }
            }
        }

        // Resolve an external provider before consuming the execution claim.
        // An ordinary missing publication can then remove this unencoded
        // transaction locally and let the same rule cascade through later
        // hidden providers without invalidating independent frame work.
        let claim: SceneResolvedMaterialRuntimeBridge.ClaimedExecution
        switch imageCompositor.resolvedMaterialClaim(layerID: layer.id) {
        case let .claimed(value):
            claim = value
        case .localFallback:
            return true
        case .unclaimed, .rejected:
            return false
        }

        guard let resolvedMaterialRuntime = imageCompositor.resolvedMaterialRuntime
        else { return false }
        let executed = imageCompositor.executeResolvedMaterialClaim(
            runtime: resolvedMaterialRuntime,
            claim: claim,
            framePlan: framePlan,
            layerID: layer.id,
            dependencyEffects: dependencyEffects,
            mainPass: mainPass,
            executionTrace: executionTrace,
            executionOrigin: .image
        )
        let texture: MTLTexture
        let ticket: SceneResolvedMaterialRuntimeBridge.ExecutionTicket
        switch executed {
        case let .encoded(value, executionTicket):
            texture = value
            ticket = executionTicket
        case .failed:
            return false
        }
        let publicationResult = dependencyRuntime.publishGraphOutputIfRequired(
            layerID: layer.id,
            texture: texture,
            publicationRole: .namedProviderPrepass,
            textureRegistry: textureRegistry,
            commandBuffer: commandBuffer,
            geometryProduct: geometryProduct,
            content: ticket.finalContent,
            imagePipeline: imagePipeline,
            retainAuxiliary: mainPass.retainAuxiliaryRelease
        ) ?? .invalid(reasonCode: "named-provider-publication-route-missing")
        dependencyRuntime.recordBindingIfRequired(
            for: layer.id,
            encoded: ticket.consumesExternalPrimaryDependency,
            on: commandBuffer
        )
        switch publicationResult {
        case .published:
            return imageCompositor.consumeResolvedMaterialNamedPublication(
                ticket,
                texture: texture,
                published: true,
                layerID: layer.id,
                executionTrace: executionTrace,
                executionOrigin: .image
            )
        case let .unavailable(reasonCode) where ticket.finalContent != .data:
            return imageCompositor
                .discardResolvedMaterialNamedPublicationLocally(
                    ticket,
                    texture: texture,
                    reasonCode: reasonCode,
                    layerID: layer.id,
                    executionTrace: executionTrace,
                    executionOrigin: .image
                )
        case let .unavailable(reasonCode), let .invalid(reasonCode):
            executionTrace?.recordRouteOperation(
                layerID: layer.id,
                origin: .image,
                operation: "named-provider-publication",
                outcome: .failed(reasonCode: reasonCode)
            )
            _ = imageCompositor.consumeResolvedMaterialNamedPublication(
                ticket,
                texture: texture,
                published: false,
                layerID: layer.id,
                executionTrace: executionTrace,
                executionOrigin: .image
            )
            return false
        }
    }

    /// Publishes the plan-proven image providers whose authored position is
    /// later than their consumer. Static providers use the existing source
    /// capture; effectful providers consume their prepared graph claim. Both
    /// remain offscreen and preserve authored final composition order.
    /// The original forward and authored calls share the exact raw source inputs.
    /// Capacity-only returns nil on success; it never reports a publication.
    func captureRawDependencyProvider(
        layer: SceneRenderDescriptor.Layer, source: SceneBaseMaterialTextureSource?,
        imageTextures: SceneBaseImageTextureSnapshot, imagePipeline: SceneImageLayerPipeline,
        frameContext: SceneFrameContext, worldFrames: [Int: simd_float4x4],
        cameraFrame: SceneParticleCameraFrame, parallax: SceneLayerParallax.Configuration,
        viewportSize: CGSize, mainPass: SceneMainPassEncoder, preparesCapacityOnly: Bool = false
    ) -> SceneGraphOutputPublicationResult? {
        let model = imageModelMatrix(for: layer, worldFramesByLayerID: worldFrames,
            renderSizeOverride: imageTextures.layerSourceRenderSize(for: layer.id),
            parallaxMouseNormalized: frameContext.cameraParallaxPosition, configuration: parallax,
            visibleHalfExtents: cameraFrame.coverHalfExtents,
            usesPerspective: cameraFrame.resolvesPerspective(for: layer))
        let mvp = cameraFrame.viewProjection(for: layer) * model
        if preparesCapacityOnly {
            return dependencyRuntime.prepareCaptureCapacity(layer: layer, sourceTexture: source?.texture,
                sourceCandidate: source?.candidate, layerMVP: mvp, viewportSize: viewportSize,
                textureRegistry: textureRegistry) ? nil : .unavailable(reasonCode: "named-provider-capacity-unavailable")
        }
        return dependencyRuntime.captureProviderIfRequired(layer: layer, sourceTexture: source?.texture,
            sourceCandidate: source?.candidate, usesAuthoredLayerColor: source?.usesAuthoredLayerColor ?? true,
            providerAlpha: Float(SceneDynamicLayerValues.alpha(layerID: layer.id,
                authoredValue: layer.alpha, snapshot: frameContext.dynamicValues)),
            providerColor: SceneDynamicLayerValues.color(layerID: layer.id,
                authoredValue: layer.colorRGB, snapshot: frameContext.dynamicValues),
            layerMVP: mvp, viewportSize: viewportSize, pipeline: imagePipeline,
            textureRegistry: textureRegistry, mainPass: mainPass,
            geometryProduct: imageTextures.geometryProducts[layer.id])
    }

    func prepareForwardDependencyProviders(
        orderedLayers: [SceneRenderDescriptor.Layer],
        layersByID: [Int: SceneRenderDescriptor.Layer],
        imageTextures: SceneBaseImageTextureSnapshot,
        imagePipeline: SceneImageLayerPipeline,
        frameContext: SceneFrameContext,
        worldFramesByLayerID: [Int: simd_float4x4],
        cameraFrame: SceneParticleCameraFrame,
        parallaxConfiguration: SceneLayerParallax.Configuration,
        viewportSize: CGSize,
        mainPass: SceneMainPassEncoder,
        framePlans: [Int: SceneResolvedMaterialFrameTargetPlan],
        activeStaticModelConsumerLayerIDs: Set<Int>,
        commandBuffer: MTLCommandBuffer,
        executionTrace: SceneEffectExecutionFrameTrace?
    ) -> Set<Int>? {
        var graphProviderLayerIDs: Set<Int> = []
        let activeExecutionLayerIDs = Set(framePlans.keys)
        guard let preparationLayerIDs = dependencyRuntime
                .forwardDependencyPreparationOrder(
                    authoredLayerIDs: orderedLayers.map(\.id),
                    activeExecutionLayerIDs: activeExecutionLayerIDs,
                    activeStaticModelConsumerLayerIDs:
                        activeStaticModelConsumerLayerIDs
                ) else { return nil }
        let preparationLayers = preparationLayerIDs.compactMap {
            layersByID[$0]
        }
        guard preparationLayers.count == preparationLayerIDs.count else {
            return nil
        }
        for provider in preparationLayers {
            if dependencyRuntime.requiresGraphOutputCapture(for: provider.id) {
                if framePlans[provider.id] == nil {
                    guard captureForwardGraphSourceFallback(
                        provider: provider,
                        imageTextures: imageTextures,
                        imagePipeline: imagePipeline,
                        frameContext: frameContext,
                        worldFramesByLayerID: worldFramesByLayerID,
                        cameraFrame: cameraFrame,
                        parallaxConfiguration: parallaxConfiguration,
                        viewportSize: viewportSize,
                        mainPass: mainPass
                    ) else { return nil }
                    continue
                }
                guard executeDependencyGraphProviderIfRequired(
                    layer: provider,
                    isVisibleExecutionRoot: false,
                    framePlan: framePlans[provider.id],
                    textureRegistry: textureRegistry,
                    dependencyRuntime: dependencyRuntime,
                    mainPass: mainPass,
                    commandBuffer: commandBuffer,
                    geometryProduct: imageTextures.geometryProducts[provider.id],
                    imagePipeline: imagePipeline,
                    executionTrace: executionTrace
                ) == true else { return nil }
                graphProviderLayerIDs.insert(provider.id)
                continue
            }
            let baseSource = baseMaterialTextureSelection(
                for: provider,
                imageTextures: imageTextures,
                readyProviderUsesAuthoredLayerColor:
                    baseMaterialReadyProviderUsesAuthoredLayerColor(
                        for: provider,
                        dynamicValues: frameContext.dynamicValues
                    )
            ).source
            let captureResult = captureRawDependencyProvider(layer: provider, source: baseSource,
                imageTextures: imageTextures, imagePipeline: imagePipeline, frameContext: frameContext,
                worldFrames: worldFramesByLayerID, cameraFrame: cameraFrame,
                parallax: parallaxConfiguration, viewportSize: viewportSize, mainPass: mainPass)

            // Same policy as the visible capture route: an ordinary miss is
            // localized by the consumer-side resolution, while a typed
            // identity rejection can only be seen here and aborts the prepass
            // so the caller stops on the claimed failure.
            if case let .invalid(reasonCode)? = captureResult {
                executionTrace?.recordRouteOperation(
                    layerID: provider.id,
                    origin: Self.effectExecutionOrigin(
                        for: provider.contentKind
                    ),
                    operation: "named-provider-capture",
                    outcome: .failed(reasonCode: reasonCode)
                )
                imageCompositor.recordResolvedMaterialFramePreflightFailure(
                    reasonCode
                )
                return nil
            }
        }
        return graphProviderLayerIDs
    }
}
