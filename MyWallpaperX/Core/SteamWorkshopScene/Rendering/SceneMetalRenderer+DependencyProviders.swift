import CoreGraphics
import Metal
import simd

extension SceneMetalRenderer {
    /// Executes an effectful hidden dependency provider through the same
    /// resolved graph runtime as a visible image layer, then publishes that
    /// intermediate output to the existing named-target registry. It never
    /// composites the hidden provider directly into the main target.
    func executeDependencyGraphProviderIfRequired(
        layer: SceneRenderDescriptor.Layer,
        framePlan: SceneResolvedMaterialFrameTargetPlan?,
        textureRegistry: SceneFrameTextureRegistry,
        dependencyRuntime: SceneDependencyFrameRuntime,
        mainPass: SceneMainPassEncoder,
        commandBuffer: MTLCommandBuffer,
        executionTrace: SceneEffectExecutionFrameTrace
    ) -> Bool? {
        guard dependencyRuntime.requiresGraphOutputCapture(
            for: layer.id
        ) else { return nil }
        guard layer.visible == false else { return nil }
        // A visual frame-local fallback intentionally publishes nothing. Any
        // downstream consumer then takes the ordinary provider-miss path.
        guard framePlan != nil else { return true }

        let dependencyBypassReason = imageCompositor
            .preparedResolvedMaterialExternalDependencyBypassReason(
                layerID: layer.id
            )
        let dependencyEffect: SceneDependencyEffectInput?
        if dependencyRuntime.requiresEffect(for: layer.id),
           dependencyBypassReason == nil {
            switch dependencyRuntime.resolvedMaterialEffectInputResolution(
                for: layer.id,
                textureRegistry: textureRegistry
            ) {
            case let .ready(input):
                dependencyEffect = input
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
            dependencyEffect = nil
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
            dependencyEffect: dependencyEffect,
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
        let published = dependencyRuntime.publishGraphOutputIfRequired(
            layerID: layer.id,
            texture: texture,
            textureRegistry: textureRegistry,
            commandBuffer: commandBuffer
        ) == true
        dependencyRuntime.recordBindingIfRequired(
            for: layer.id,
            encoded: ticket.consumesExternalPrimaryDependency,
            on: commandBuffer
        )
        return imageCompositor.consumeResolvedMaterialNamedPublication(
            ticket,
            texture: texture,
            published: published,
            layerID: layer.id,
            executionTrace: executionTrace,
            executionOrigin: .image
        ) && published
    }

    /// Publishes the plan-proven image providers whose authored position is
    /// later than their consumer. Static providers use the existing source
    /// capture; effectful providers consume their prepared graph claim. Both
    /// remain offscreen and preserve authored final composition order.
    func prepareForwardDependencyProviders(
        orderedLayers: [SceneRenderDescriptor.Layer],
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
        executionTrace: SceneEffectExecutionFrameTrace
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
        let layersByID = Dictionary(uniqueKeysWithValues: orderedLayers.map {
            ($0.id, $0)
        })
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
                    framePlan: framePlans[provider.id],
                    textureRegistry: textureRegistry,
                    dependencyRuntime: dependencyRuntime,
                    mainPass: mainPass,
                    commandBuffer: commandBuffer,
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
            let model = imageModelMatrix(
                for: provider,
                worldFramesByLayerID: worldFramesByLayerID,
                renderSizeOverride: imageTextures.layerSourceRenderSize(
                    for: provider.id
                ),
                parallaxMouseNormalized: frameContext.cameraParallaxPosition,
                configuration: parallaxConfiguration,
                visibleHalfExtents: cameraFrame.coverHalfExtents,
                usesPerspective: cameraFrame.resolvesPerspective(
                    layerOverride: provider.usesPerspective
                )
            )
            _ = dependencyRuntime.captureProviderIfRequired(
                layer: provider,
                sourceTexture: baseSource?.texture,
                sourceCandidate: baseSource?.candidate,
                usesAuthoredLayerColor:
                    baseSource?.usesAuthoredLayerColor ?? true,
                providerAlpha: Float(SceneDynamicLayerValues.alpha(
                    layerID: provider.id,
                    authoredValue: provider.alpha,
                    snapshot: frameContext.dynamicValues
                )),
                providerColor: SceneDynamicLayerValues.color(
                    layerID: provider.id,
                    authoredValue: provider.colorRGB,
                    snapshot: frameContext.dynamicValues
                ),
                layerMVP: cameraFrame.viewProjection(for: provider) * model,
                viewportSize: viewportSize,
                pipeline: imagePipeline,
                textureRegistry: textureRegistry,
                mainPass: mainPass
            )
        }
        return graphProviderLayerIDs
    }
}
