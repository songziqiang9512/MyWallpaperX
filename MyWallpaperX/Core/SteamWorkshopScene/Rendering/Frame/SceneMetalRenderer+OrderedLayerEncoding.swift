import Foundation
import Metal
import QuartzCore
import simd

extension SceneMetalRenderer {
    func hasWorldOrderDependency(_ id: Int, utility: SceneUtilityLayerRuntimePlanner.Execution) -> Bool {
        utility.memberRootsByLayerID[id] != nil || utility.plansByTriggerLayerID[id] != nil
            || utility.captureLayerIDs.contains(id) || hasWorldOrderTextureDependency(id)
    }

    func hasWorldOrderTextureDependency(_ id: Int) -> Bool {
        dependencyRuntime.requiresCapture(for: id)
            || dependencyRuntime.requiresGraphOutputCapture(for: id)
            || dependencyRuntime.plan.namedReferenceConsumerLayerIDs.contains(id)
            || staticModelResources.namedAlbedoLayerIDs.contains(id)
    }

    func worldTransparencyDepth(
        _ layer: SceneRenderDescriptor.Layer, state: SceneMaterialRenderState,
        cameraFrame: SceneParticleCameraFrame, worldFrame: simd_float4x4?,
        utility: SceneUtilityLayerRuntimePlanner.Execution, allowsPlainLayerSource: Bool = false
    ) -> Float? {
        guard state.blending == .translucent, state.depthTest == .enabled,
              !hasWorldOrderDependency(layer.id, utility: utility),
              let origin = worldFrame?.columns.3 else { return nil }
        if layer.contentKind != "text" || !layer.effects.isEmpty {
            let route = imageCompositor.preflightResolvedMaterialClaim(layerID: layer.id)
            let plainSource = allowsPlainLayerSource && layer.effects.isEmpty
                && route.allowsLayerSourcePassthrough
            if !plainSource {
                guard let claim = route.execution,
                      claim.sourceRoute == .capturedLayerTexture, claim.dependencyOwnership == .none,
                      claim.sceneBackgroundRequirement == nil,
                      imageCompositor.resolvedMaterialRuntime?.requiresSceneEnvironment(layerID: layer.id) != true
                else { return nil }
            }
        }
        let depth = simd_dot(SIMD3(origin.x, origin.y, origin.z), cameraFrame.cameraForward)
        return depth.isFinite ? depth : nil
    }

    func worldTransparencyOrder(
        _ authored: [SceneRenderDescriptor.Layer], layerDepths: [Int: Float],
        sorting: Bool, mayOrderText: Bool, modelFrame: StaticModelFrame,
        visible: Set<Int>, cameraFrame: SceneParticleCameraFrame, snapshot: SceneDynamicSnapshot,
        worldFrames: [Int: simd_float4x4],
        utility: SceneUtilityLayerRuntimePlanner.Execution, backgroundCuts: Set<Int>,
        particleBatches: [Int: [SceneParticleMetalPipeline.PreparedBatch]]
    ) -> [SceneRenderDescriptor.Layer]? {
        func drawsOpaqueModel(_ layer: SceneRenderDescriptor.Layer) -> Bool {
            layer.contentKind == "model" && cameraFrame.resolvesPerspective(for: layer)
                && SceneDynamicLayerValues.alpha(layerID: layer.id,
                    authoredValue: layer.alpha, snapshot: snapshot) == 1
                && staticModelResources[layer.id]?.allSatisfy {
                    $0.testsDepth && $0.writesDepth && $0.materialBlending == .normal
                } == true
        }

        func isBarrier(_ layer: SceneRenderDescriptor.Layer) -> Bool {
            if layer.utilityLayer != nil || hasWorldOrderDependency(layer.id, utility: utility) { return true }
            switch layer.contentKind {
            case "container", "sound", "pointLight", "directionalLight", "tubeLight": return false
            case "spotLight" where spotLightRuntime?.plansByLayerID[layer.id] == nil:
                return false
            default: break
            }
            if !visible.contains(layer.id) { return false }
            return !drawsOpaqueModel(layer)
        }

        func endsOpaquePrefix(_ layer: SceneRenderDescriptor.Layer) -> Bool {
            if layer.utilityLayer != nil { return true }
            switch layer.contentKind {
            case "container", "sound", "pointLight", "directionalLight", "tubeLight": return false
            case "spotLight": return spotLightRuntime?.plansByLayerID[layer.id] != nil
            case "particle":
                return particleBatches[layer.id]?.contains {
                    $0.draw.refraction != nil || $0.draw.renderState.depthWriteEnabled
                        || $0.draw.renderState.blendMode != .additive
                } ?? false
            case "image", "solid", "text":
                guard (layer.colorBlendMode ?? 0) == 0,
                      cameraFrame.resolvesPerspective(for: layer) else { return true }
                let state = modelFrame.imageMaterialStates[layer.id]
                if state?.supportsImageNormalDepth == true { return true }
                let testsDepth = state.map {
                    $0.depthTest == .enabled && (layer.contentKind != "text" || $0.rawValues.depthTest != nil)
                } ?? false
                guard layer.effects.contains(where: { $0.visible != false }) else { return !testsDepth }
                guard let claim = imageCompositor.preflightResolvedMaterialClaim(layerID: layer.id).execution,
                      claim.sourceRoute == .capturedLayerTexture, claim.dependencyOwnership == .none,
                      claim.sceneBackgroundRequirement == nil else { return true }
                return !(testsDepth || (layer.contentKind == "solid" && claim.supportsTerminalMaterialReplay))
            default: return true
            }
        }

        var depths = layerDepths
        if mayOrderText {
            // A flush before a later draw or prefix reader still needs the
            // earlier glyph's depth to protect its original contribution.
            for layer in authored.reversed() {
                if depths[layer.id] != nil { continue }
                let isText = layer.contentKind == "text"
                if isText || (!sorting && layer.contentKind == "image"),
                   let state = modelFrame.imageMaterialStates[layer.id],
                   let depth = worldTransparencyDepth(layer, state: state, cameraFrame: cameraFrame,
                       worldFrame: worldFrames[layer.id], utility: utility) {
                    if isText {
                        modelFrame.imageMaterialStates[layer.id] = state.withoutDepthWrite
                        if sorting { depths[layer.id] = depth }
                    }
                } else if isBarrier(layer) { break }
            }
        }
        let hasBackgroundCuts = !backgroundCuts.isEmpty
        guard !depths.isEmpty || hasBackgroundCuts else { return nil }

        var ordered: [SceneRenderDescriptor.Layer] = []
        ordered.reserveCapacity(authored.count)
        var transparent: [(layer: SceneRenderDescriptor.Layer, depth: Float)] = []
        var firstBackgroundCut: Int?
        var lateOpaque: [SceneRenderDescriptor.Layer] = []
        var movedOpaque = false

        func finishOpaquePrefix() {
            if let firstBackgroundCut, !lateOpaque.isEmpty {
                ordered.insert(contentsOf: lateOpaque, at: firstBackgroundCut)
                lateOpaque.removeAll(keepingCapacity: true)
                movedOpaque = true
            }
            firstBackgroundCut = nil
        }

        func finishRange() {
            if transparent.count > 1 {
                // Swift sort is stable. Equal-depth cards keep their input order.
                transparent.sort { $0.depth > $1.depth }
            }
            for entry in transparent { ordered.append(entry.layer) }
            transparent.removeAll(keepingCapacity: true)
        }
        for layer in authored {
            let isBackgroundCut = hasBackgroundCuts && backgroundCuts.contains(layer.id)
            if firstBackgroundCut != nil, !isBackgroundCut {
                if hasWorldOrderDependency(layer.id, utility: utility) {
                    finishOpaquePrefix()
                } else if visible.contains(layer.id) {
                    if drawsOpaqueModel(layer) {
                        lateOpaque.append(layer)
                        continue
                    }
                    if endsOpaquePrefix(layer) { finishOpaquePrefix() }
                }
            }
            if let depth = depths[layer.id] {
                transparent.append((layer, depth))
                continue
            }
            if !transparent.isEmpty, isBarrier(layer) { finishRange() }
            if isBackgroundCut && firstBackgroundCut == nil {
                firstBackgroundCut = ordered.count
            }
            ordered.append(layer)
        }
        finishRange()
        finishOpaquePrefix()
        return movedOpaque || !depths.isEmpty ? ordered : nil
    }

    /// Owns prepared frame order and each layer's utility defer. Closing group
    /// encoders and finishing the main pass are part of the same stage.
    func encodeOrderedLayers(
        orderedLayers: [SceneRenderDescriptor.Layer],
        initiallyStopped: Bool,
        needsTerminalScratch: Bool,
        forwardGraphProviderLayerIDs: Set<Int>,
        preparationSchedule: SceneDependencyRenderPlan.PreparationSchedule,
        frameVisibleLayerIDs: Set<Int>,
        omittedPrivateLayerIDs: Set<Int>,
        imageTextures: SceneBaseImageTextureSnapshot,
        imagePipeline: SceneImageLayerPipeline?,
        specializedBaseTextureSamplings: [Int: SceneTextureSampling],
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
        seededMultisample: (layerID: Int, targets: MainMultisampleTargets)?,
        compositionGroupRuntime: SceneCompositionGroupFrameRuntime?,
        commandBuffer: MTLCommandBuffer,
        effectExecutionTrace: SceneEffectExecutionFrameTrace?,
        particleBatchesByID: [Int: [SceneParticleMetalPipeline.PreparedBatch]],
        particlePipeline: SceneParticleMetalPipeline?,
        frameDepthLeases: inout [SceneParticleDepthTargetLease],
        particlePerformanceObservations: inout [SceneParticlePerformanceObservation]?,
        performanceTelemetry: SceneFramePerformanceTelemetry?,
        sceneColor: SceneResolvedMaterialSubmissionCoordinator.SceneColorReservation?,
        frameProjection: SceneMetalRendererFrameWorldProjection,
        layerTopology: SceneScriptLayerTopologySnapshot?,
        initialVideoPresentation: inout InitialVideoPresentation?
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
        var graphProviderLayerIDs = forwardGraphProviderLayerIDs
        var stopsAfterClaimedFailure = initiallyStopped
        var lastLayerPass: SceneMainPassEncoder?
#if DEBUG
        performanceTelemetry?.beginStage("layer-loop")
#endif

#if DEBUG
        let hubLayerLoopStart = ProcessInfo.processInfo.systemUptime
#endif
        frameLayers: for layer in orderedLayers {
            if stopsAfterClaimedFailure || modelFrame.depthDeferralReason != nil
                || modelFrame.sceneDepthFailureReason != nil { break frameLayers }
            defer {
                if !stopsAfterClaimedFailure,
                   !renderUtilityPlans(triggeredBy: layer.id,
                    frameVisibleLayerIDs: frameVisibleLayerIDs,
                    imagePipeline: imagePipeline,
                    offscreenTexturePool: offscreenTexturePool, frameContext: frameContext,
                    worldFramesByLayerID: frameWorldFrames, cameraFrame: cameraFrame,
                    parallaxConfiguration: parallaxConfiguration, viewportSize: viewportSize,
                    time: time, mainPass: mainPass, commandBuffer: commandBuffer,
                    modelFrame: modelFrame,
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
            let skipsGroupMember: Bool
            if let compositionGroupRuntime,
               let groupPass = compositionGroupRuntime.renderPass(
                   forLayerID: layer.id, beginsRendering: true
               ), groupPass !== mainPass {
                layerMainPass = groupPass
                skipsGroupMember = false
            } else {
                layerMainPass = mainPass
                skipsGroupMember = compositionGroupRuntime != nil
                    && frameProjection.utilityExecution.memberRootsByLayerID[layer.id] != nil
            }
            let providerIDs = preparationSchedule.providersBeforeLayerID[layer.id]
            if skipsGroupMember && providerIDs == nil { continue }
            if layerMainPass !== lastLayerPass {
                lastLayerPass?.closeForOffscreen()
            }
            lastLayerPass = layerMainPass
            if let imagePipeline, let providerIDs {
                guard let prepared = prepareDependencyProviders(
                    providerLayerIDs: providerIDs, layersByID: frameProjection.layersByID,
                    frameVisibleLayerIDs: frameVisibleLayerIDs, imageTextures: imageTextures,
                    imagePipeline: imagePipeline, frameContext: frameContext,
                    worldFramesByLayerID: frameWorldFrames, cameraFrame: cameraFrame,
                    parallaxConfiguration: parallaxConfiguration, viewportSize: viewportSize,
                    mainPass: layerMainPass, framePlans: resolvedMaterialFrameTargetPlans,
                    commandBuffer: commandBuffer, executionTrace: effectExecutionTrace
                ) else {
                    stopsAfterClaimedFailure = true
                    break frameLayers
                }
                graphProviderLayerIDs.formUnion(prepared)
            }
            if skipsGroupMember || omittedPrivateLayerIDs.contains(layer.id) { continue }
            let reusesForwardOutput = graphProviderLayerIDs.contains(layer.id)
            if !reusesForwardOutput, !frameVisibleLayerIDs.contains(layer.id),
               preparationSchedule.scheduledGraphProviderLayerIDs.contains(layer.id) { continue }
            if reusesForwardOutput && !frameVisibleLayerIDs.contains(layer.id) { continue }
            let baseSelection: SceneBaseMaterialTextureSelection
            switch layer.contentKind {
            case "image", "solid", "text":
                baseSelection = reusesForwardOutput ? .missing : baseMaterialTextureSelection(
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
#if DEBUG
                effectExecutionTrace?.recordRouteOperation(
                    layerID: layer.id,
                    origin: Self.effectExecutionOrigin(for: layer.contentKind),
                    operation: "base-material-provider-rejected",
                    outcome: .failed(reasonCode: reasonCode)
                )
#endif

            } else if baseSource?.usesSystemProvider == true {
#if DEBUG
                effectExecutionTrace?.recordRouteOperation(
                    layerID: layer.id,
                    origin: Self.effectExecutionOrigin(for: layer.contentKind),
                    operation: "base-material-system-provider",
                    outcome: .encoded
                )
#endif

            } else if baseSource?.usesUserPropertyProvider == true {
#if DEBUG
                effectExecutionTrace?.recordRouteOperation(
                    layerID: layer.id,
                    origin: Self.effectExecutionOrigin(for: layer.contentKind),
                    operation: "base-material-user-property-provider",
                    outcome: .encoded
                )
#endif

            }
            if !reusesForwardOutput,
               let providerGraphEncoded = executeDependencyGraphProviderIfRequired(
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
            if let imagePipeline, preparationSchedule.authoredRawProviderLayerIDs.contains(layer.id) {
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
#if DEBUG
                    effectExecutionTrace?.recordRouteOperation(
                        layerID: layer.id,
                        origin: Self.effectExecutionOrigin(
                            for: layer.contentKind
                        ),
                        operation: "named-provider-capture",
                        outcome: .failed(reasonCode: reasonCode)
                    )
#endif

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
                guard let imagePipeline,
                      !modelFrame.unavailableImageMaterialLayerIDs.contains(layer.id) else { continue }
                if baseSelection.hasPendingAuthoredVideo {
                    initialVideoPresentation?.pendingLayerIDs.insert(layer.id)
                }
                let observesOrdinaryVideo: Bool
                if reusesForwardOutput || layerMainPass !== mainPass {
                    observesOrdinaryVideo = false
                } else if case .provider(.video)? = baseSource?.candidate?.identity {
                    observesOrdinaryVideo = true
                } else if baseSelection.hasPendingAuthoredVideo {
                    observesOrdinaryVideo = true
                } else if case .missing = baseSelection {
                    observesOrdinaryVideo = imageTextures.initialVideoReadiness?[layer.id] == .unavailable
                } else {
                    observesOrdinaryVideo = false
                }
                guard baseSource != nil || observesOrdinaryVideo || reusesForwardOutput else { continue }
                let layerAlpha = reusesForwardOutput ? 1 : SceneDynamicLayerValues.alpha(
                    layerID: layer.id, authoredValue: layer.alpha,
                    snapshot: frameContext.dynamicValues
                )
                let sourceMaterialAlpha: Float = reusesForwardOutput ? 1 : baseMaterialProviderBindings.sourceMaterialAlpha(
                    layer: layer, snapshot: frameContext.dynamicValues
                )
                let usesPerspective = cameraFrame.resolvesPerspective(for: layer)
                let model = imageTextures.geometryProducts[layer.id].map {
                    geometryModelMatrix(
                        for: layer, worldFramesByLayerID: frameWorldFrames,
                        authoredSize: $0.authoredSize,
                        parallaxMouseNormalized: parallaxMouseNormalized,
                        configuration: parallaxConfiguration,
                        visibleHalfExtents: cameraFrame.coverHalfExtents,
                        usesPerspective: usesPerspective
                    )
                } ?? imageModelMatrix(
                    for: layer, worldFramesByLayerID: frameWorldFrames,
                    renderSizeOverride: imageTextures.layerSourceRenderSize(for: layer.id),
                    textPlacement: imageTextures.layerSourceTextPlacement(for: layer.id),
                    parallaxMouseNormalized: parallaxMouseNormalized,
                    configuration: parallaxConfiguration,
                    visibleHalfExtents: cameraFrame.coverHalfExtents,
                    usesPerspective: usesPerspective
                )
                let mvp = cameraFrame.viewProjection(for: layer) * model
                let isVisibleOrdinaryVideo = observesOrdinaryVideo && layerAlpha > 0
                    && sourceMaterialAlpha > 0
                    && SceneLayerSourcePassthroughPlan.projectedGeometry(for: mvp) != nil
                if isVisibleOrdinaryVideo {
                    if baseSelection.hasPendingAuthoredVideo {
                        initialVideoPresentation?.pendingSurfaceLayerIDs.insert(layer.id)
                    } else if imageTextures.initialVideoReadiness?[layer.id] == .unavailable {
                        initialVideoPresentation?.hasUnavailableVideo = true
                    }
                }
                let imageResult: (stop: Bool, outcome: SceneImageLayerCompositor.DrawOutcome?)
                if reusesForwardOutput {
                    imageResult = encodePreparedImageLayerOutput(layer: layer,
                        geometryProduct: imageTextures.geometryProducts[layer.id], imagePipeline: imagePipeline,
                        model: model, mvp: mvp, cameraFrame: cameraFrame, usesPerspective: usesPerspective,
                        time: time, frameLightSnapshot: frameLightSnapshot, modelFrame: modelFrame,
                        layerMainPass: layerMainPass, commandBuffer: commandBuffer,
                        effectExecutionTrace: effectExecutionTrace)
                } else {
                    guard let baseSource else { continue }
                    imageResult = encodeImageLayer(
                        layer: layer,
                        baseSource: baseSource,
                        imageTextures: imageTextures,
                        imagePipeline: imagePipeline,
                        specializedBaseTextureSamplings: specializedBaseTextureSamplings,
                        resolvedMaterialFrameTargetPlans: resolvedMaterialFrameTargetPlans,
                        frameContext: frameContext,
                        frameWorldFrames: frameWorldFrames,
                        cameraFrame: cameraFrame,
                        model: model,
                        mvp: mvp,
                        usesPerspective: usesPerspective,
                        layerAlpha: layerAlpha,
                        sourceMaterialAlpha: sourceMaterialAlpha,
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
                }
                if imageResult.stop {
                    stopsAfterClaimedFailure = true
                    break frameLayers
                }
                guard let drawOutcome = imageResult.outcome else { continue }
                if isVisibleOrdinaryVideo && drawOutcome.encoded {
                    initialVideoPresentation?.readyLayerIDs.insert(layer.id)
                }
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
                if !reusesForwardOutput {
                    dependencyRuntime.recordBindingIfRequired(
                        for: layer.id,
                        encoded: drawOutcome.consumedDependency,
                        on: commandBuffer
                    )
                }
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
                   layer.utilityLayer?.framebufferSource == nil,
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
                if initialVideoPresentation != nil,
                   let videoAlbedos = staticModelResources.videoAlbedoAssetsByLayerID[layer.id],
                   SceneDynamicLayerValues.alpha(layerID: layer.id,
                    authoredValue: layer.alpha, snapshot: frameContext.dynamicValues) > 0 {
                    for identity in videoAlbedos where staticModelResources[layer.id]?.contains(where: {
                        $0.albedoSource == .asset(identity) && staticModelUsesAlbedoFallback($0)
                    }) == true {
                        if case .pending = textureRegistry.lookup(.asset(identity)) {
                            initialVideoPresentation?.pendingLayerIDs.insert(layer.id)
                            if layerMainPass === mainPass {
                                initialVideoPresentation?.pendingSurfaceLayerIDs.insert(layer.id)
                            }
                        }
                    }
                }
                if let seededMultisample, seededMultisample.layerID == layer.id,
                   let imagePipeline, let offscreenTexturePool {
                    _ = mainPass.beginMultisamplingAfterColorPrefix(
                        attachmentsForTarget: seededMultisample.targets.forTarget
                    ) { target, buffer in
                        guard let snapshot = offscreenTexturePool.reserveDisplayScratch(width: target.width,
                            height: target.height, commandBuffer: buffer),
                              copySceneColor(target, to: snapshot.texture, commandBuffer: buffer) else { return nil }
                        mainPass.retainCompositionPin(snapshot.pin)
#if DEBUG
                        if let trace = mainPass.compositionTrace, trace.isCompositionSelected {
                            trace.recordComposition(.init(kind: "msaa-prefix-snapshot", layerID: layer.id,
                                source: mainPass.compositionTarget, target: .init(snapshot.texture, role: "msaa-prefix"),
                                access: "color-copy", outcome: "encoded"))
                        }
#endif
                        return { imagePipeline.seedMultisampleColor(from: snapshot.texture, encoder: $0) }
                    }
                }
                let lit = drawStaticModel(layer: layer, state: modelFrame,
                    worldFrames: frameWorldFrames, frameContext: frameContext,
                    cameraFrame: cameraFrame, lighting: frameLightSnapshot,
                    reflection: layerMainPass === mainPass ? reflection.preparedEnvironment : nil,
                    pass: layerMainPass, commandBuffer: commandBuffer, leases: &frameDepthLeases)
                if let reason = modelFrame.depthDeferralReason {
                    compositionGroupRuntime?.closeAllGroupEncoders()
                    mainPass.closeForOffscreen()
                    return .deferred(reasonCode: reason)
                }
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
                guard let spotLightRuntime, layer.spotLight?.castsVolumetrics == true else { continue }
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
                    configuration: parallaxConfiguration,
                    referenceWorldFrame: layerBatches.first?.draw.referenceWorldFrame
                )
                let usesPerspective = cameraFrame.resolvesPerspective(for: layer)
                if let depthLease = particlePipeline.drawBatches(
                    layerBatches,
                    model: model,
                    cameraFrame: cameraFrame,
                    layerUsesPerspective: usesPerspective,
                    viewportSize: SIMD2(
                        Float(viewportSize.width),
                        Float(viewportSize.height)
                    ),
                    ambient: frameLightSnapshot.authoredShaderLighting.ambient,
                    hdrEnabled: frameProjection.descriptor.hdrEnabled,
                    mainPass: layerMainPass,
                    commandBuffer: commandBuffer,
                    preparedDepth: modelFrame.particleDepth[layer.id]?.acquisition,
                    readOnlySceneDepth: {
                        guard layerMainPass === mainPass, cameraFrame.defaultsToPerspective,
                              usesPerspective else { return nil }
                        return modelFrame.particleReadOnlyDepth(pass: mainPass, commandBuffer: commandBuffer)
                    },
                    performanceObservations: &particlePerformanceObservations
                ) {
                    if modelFrame.particleDepth[layer.id] == nil { frameDepthLeases.append(depthLease) }
                }
            default:
                continue
            }
        }
#if DEBUG
        performanceTelemetry?.endStage("layer-loop")
#endif

#if DEBUG
        hubStage(.layerLoopMicros, hubLayerLoopStart)
#endif
        // The main pass may still owe its first attachment operation. End
        // group encoders before finishing it on the shared command buffer.
        compositionGroupRuntime?.closeAllGroupEncoders()

        if let reason = modelFrame.sceneDepthFailureReason {
            mainPass.closeForOffscreen()
            return .dropped(reasonCode: reason)
        }

        if let reason = modelFrame.depthDeferralReason {
            mainPass.closeForOffscreen()
            return .deferred(reasonCode: reason)
        }

        if !stopsAfterClaimedFailure, let pointVolumePipeline, let farPlane = cameraFrame.nativeFarPlane,
           !modelFrame.volumeOccluders.isEmpty,
           let volume = pointVolumePipeline.prepare(
                lights: frameLightSnapshot.point,
                camera: .init(
                    origin: cameraFrame.perspectiveEyePosition,
                    near: frameProjection.descriptor.camera.nearZ,
                    forward: cameraFrame.cameraForward, far: farPlane.z,
                    horizontal: cameraFrame.cameraRight * (farPlane.x / farPlane.z),
                    vertical: cameraFrame.cameraUp * (farPlane.y / farPlane.z)
                ), viewport: mainPass.targetExtent),
           let depth = encodeVolumeOccluderDepth(state: modelFrame, pass: mainPass,
                pool: offscreenTexturePool, groups: compositionGroupRuntime,
                needsTerminalScratch: needsTerminalScratch),
           let encoder = mainPass.encoder(required: false) {
            pointVolumePipeline.draw(volume, depth: depth, encoder: encoder)
#if DEBUG
            if let trace = mainPass.compositionTrace, trace.isCompositionSelected {
                let coverage = volume.scissor.map { "\($0.x),\($0.y),\($0.width),\($0.height)" } ?? "full"
                trace.recordComposition(.init(kind: "point-volume",
                    source: .init(depth, role: "model-camera-depth"),
                    target: mainPass.compositionTarget, access: "texture-bind", outcome: "draw-encoded",
                    details: ["screenCoverage": coverage,
                              "quadrature": String(pointVolumePipeline.quadraturePointCount),
                              "layerIDs": frameLightSnapshot.point.compactMap {
                        $0.volume == nil ? nil : $0.layerID.map(String.init)
                    }.joined(separator: ",")]))
            }
#endif
        }

        let mainEncoded = mainPass.finishEnsuringClear()
        reflection.mainSourceCompleted = mainEncoded
        if !mainEncoded && (sceneColor != nil || mainPass.rasterSampleCount > 1) {
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
