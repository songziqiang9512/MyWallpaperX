import Foundation
import Metal
import simd

/// Owns CPU simulation state and instance values for effectively visible particle layers.
/// Positions remain local for legacy systems, or in one immutable reference
/// for admitted root translations. The renderer applies that chosen frame once.
final class SceneParticleRuntime {
    let descriptor: SceneRenderDescriptor
    let visibilityLayersByID: [Int: SceneRenderDescriptor.Layer]

    private let device: MTLDevice
    private(set) var layers: [SceneParticleLayerRuntime] = []
#if DEBUG
    private(set) var diagnostics: [SceneParticleRuntimeDiagnostic] = []
#endif
    /// Active world-space roots and their authored transform chains.
    private var worldSpaceChains: [Int: Set<Int>]
    private(set) var rootWorldTranslationPlans: [Int: SceneParticleRootWorldTranslationPlan] = [:]
    /// Only these root/child consumers freeze on a missing world frame;
    /// local-space peers still advance because their frame matters only at draw.
    private(set) var worldSpaceRequiringLayerIDs: Set<Int> = []
    private var frozenWorldSpaceLayerIDs: Set<Int> = []
    /// Prepared root/child pointer demand retires with its owning layer.
    private(set) var pointerControlPointDemands: Set<Int> = []
    private(set) var requiredPipelineVariants: Set<SceneParticlePipelineVariant> = []
#if DEBUG
    var pendingAudioEvaluationObservations:
        [SceneParticleRuntimeAudioEvaluationObservation] = []
    var pendingComponentObservations: [SceneParticleRuntimeComponentObservation]? =
        SceneParticleDefinitionParser.componentObservationEnabled ? [] : nil
#endif

    func playbackLiveCount(charging: (UInt64) throws -> Void) throws -> Int {
        try charging(UInt64(layers.count))
        return try layers.reduce(0) { count, layer in
            try charging(UInt64(layer.childRuntime?.lifecycleSystemCount ?? 0))
            return count + (layer.rootRender?.simulator.particles.count ?? 0)
                + (layer.childRuntime?.lifecycleParticleCount ?? 0)
        }
    }
    /// The transaction has validated the complete surface/instance set. Install
    /// its simulator and visibility checkpoint together, without a second reset.
    func installPlaybackCandidate(layerID: Int, state: SceneParticleSimulator.FrameSnapshot,
                                  visibility: SceneParticlePlaybackVisibility?) {
        guard let index = layers.firstIndex(where: { $0.layerID == layerID }),
              var root = layers[index].rootRender else {
            preconditionFailure("validated particle instance disappeared during install")
        }
        root.simulator.restoreFrame(state)
        if let visibility {
            layers[index].wasVisible = visibility.isVisible
            if visibility.resetsPopulation {
                root.instances = []
                root.ropeTrailHistory?.clear(keepingCapacity: false)
            }
        }
        layers[index].rootRender = root
    }
    func clearStoppedPlaybackCaches(_ layerIDs: Set<Int>) {
        for index in layers.indices where layerIDs.contains(layers[index].layerID) {
            layers[index].rootRender?.instances.removeAll(keepingCapacity: true)
            layers[index].rootRender?.ropeTrailHistory?.clear()
        }
    }

    func validatePlaybackTransitions(_ transitions: [SceneParticlePlaybackTransition]) -> Bool {
        var revisions: [Int: UInt64] = [:]
        for transition in transitions {
            guard let observation = playbackObservation(layerID: transition.layerID) else { return false }
            let previous = revisions[transition.layerID] ?? observation.revision
            if transition.revision <= observation.revision { continue }
            guard previous < UInt64.max, transition.revision == previous + 1 else { return false }
            revisions[transition.layerID] = transition.revision
        }
        return true
    }

    /// Session validates the complete surface set before applying any command.
    func applyPlaybackTransitions(_ transitions: [SceneParticlePlaybackTransition]) {
        for transition in transitions {
            guard let index = layers.firstIndex(where: { $0.layerID == transition.layerID }),
                  var root = layers[index].rootRender,
                  transition.revision > root.simulator.playback.revision else { continue }
            root.simulator.applyPlaybackTransition(transition)
            if transition.action == .stop {
                root.instances.removeAll(keepingCapacity: true)
                root.ropeTrailHistory?.clear()
            }
            layers[index].rootRender = root
        }
    }

    var activeLayerIDs: [Int] { layers.map(\.layerID) }
    var hasAudioConsumer: Bool {
        layers.contains {
            $0.definition.hasBoundedAudioConsumer
                || $0.childRuntime?.hasAudioConsumer == true
        }
    }
    var lifecycleSnapshot: SceneParticleRuntimeLifecycleSnapshot {
        SceneParticleRuntimeLifecycleSnapshot(
            activeLayerCount: layers.count,
            rootSystemCount: layers.reduce(0) { $0 + ($1.rootRender == nil ? 0 : 1) },
            childSystemCount: layers.reduce(0) {
                $0 + ($1.childRuntime?.lifecycleSystemCount ?? 0)
            },
            rootParticleCount: layers.reduce(0) {
                $0 + ($1.rootRender?.simulator.particles.count ?? 0)
            },
            childParticleCount: layers.reduce(0) {
                $0 + ($1.childRuntime?.lifecycleParticleCount ?? 0)
            }
        )
    }

    /// Definition bytes are prepared before candidate publication. Per-surface
    /// runtimes consume this graph without reopening authored particle files.
    static func prepareAssets(
        descriptor: SceneRenderDescriptor,
        resourceView: SceneResourceView,
        preparedParticleVisibilityLayerIDs: Set<Int> = [],
        preparedDefinitions: [String: SceneParticleAssetGraphLoader.PreparedDefinition]? = nil,
        stockTextureBundleURL: URL? = SceneStockTextureResolver.defaultBundleRoot(),
        checkCancellation: (() throws -> Void)? = nil
    ) throws -> SceneParticleAssetGraph {
        try checkCancellation?()
        let visibleIDs = SceneLayerVisibility.visibleLayerIDs(in: descriptor)
        let particleLayers = Self.orderedLayers(in: descriptor).filter {
            (visibleIDs.contains($0.id) || preparedParticleVisibilityLayerIDs.contains($0.id))
                && $0.contentKind == "particle" && $0.particlePath != nil
        }
        let materialPasses = descriptor.materialPasses.map {
            SceneParticleMaterialPass(
                materialPath: $0.materialPath,
                passIndex: $0.passIndex,
                shaderPath: $0.shaderPath,
                texturePaths: $0.texturePaths,
                textureSlots: $0.textureSlots,
                blending: $0.blending,
                combos: $0.combos,
                constantValues: $0.constantShaderValues.mapValues {
                    SceneParticleMaterialConstant(
                        components: $0.components ?? [],
                        isStatic: (($0.userValueKind == nil
                            && ((["number", "string", "vector"].contains($0.valueKind)
                                && $0.bindingKeys.isEmpty)
                                || ($0.valueKind == "binding" && $0.bindingKeys == ["value"])))
                            || ($0.valueKind == "binding" && $0.bindingKeys == ["user", "value"]
                                && $0.userValueKind == .null))
                            && $0.userBinding == nil
                            && $0.scriptSource == nil
                            && $0.timeline == nil
                            && $0.timelineDiagnostics.isEmpty
                    )
                },
                hasUserTextureInputs: !$0.userTextureInputs.isEmpty,
                hasUserShaderValues: !$0.userShaderValues.isEmpty,
                depthTest: $0.depthTest,
                depthWrite: $0.depthWrite,
                cullMode: $0.cullMode,
                alphaWriting: $0.alphaWriting
            )
        }
        return try SceneParticleAssetGraphLoader(
            resourceView: resourceView,
            stockTextureBundleURL: stockTextureBundleURL
        ).load(
            rootPaths: particleLayers.compactMap(\.particlePath),
            materialPasses: materialPasses,
            preparedDefinitions: preparedDefinitions,
            checkCancellation: checkCancellation
        )
    }

    init(
        descriptor: SceneRenderDescriptor,
        preparedAssets graph: SceneParticleAssetGraph,
        device: MTLDevice,
        textureLoader: SceneTextureLoader = SceneTextureLoader(),
        layerImage: SceneParticleLayerImageEmitterCompilation = .empty,
        staticWorldSpaceFrames: [Int: SceneParticleWorldSpaceFrame]? = nil,
        staticWorldSpaceChains: [Int: Set<Int>]? = nil,
        preparedParticleVisibilityLayerIDs: Set<Int> = [],
        initialDynamicValues: SceneDynamicSnapshot = .empty(frameIndex: 0),
        initialPlayback: [Int: SceneParticlePlaybackSnapshot] = [:],
        destroyedAuthoredLayerIDs: Set<Int> = []
    ) {
        self.device = device
        self.descriptor = descriptor
        visibilityLayersByID = Dictionary(uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0) })
        let layerImageEmissionMaps = layerImage.mapsByLayerID
#if DEBUG
        diagnostics = layerImage.diagnostics
#endif
        let staticWorldSpaceFrames = staticWorldSpaceFrames
            ?? descriptor.staticParticleWorldSpaceFrames
        worldSpaceChains = (staticWorldSpaceChains
            ?? descriptor.staticParticleWorldSpaceChains).filter { !destroyedAuthoredLayerIDs.contains($0.key) }
        let preparedTranslations = descriptor.particleRootWorldTranslations(initialDynamicValues: initialDynamicValues)
        let visibleIDs = SceneLayerVisibility.visibleLayerIDs(in: descriptor)
        let particleLayers = Self.orderedLayers(in: descriptor).filter {
            !destroyedAuthoredLayerIDs.contains($0.id)
                && (visibleIDs.contains($0.id) || preparedParticleVisibilityLayerIDs.contains($0.id))
                && $0.contentKind == "particle"
                && $0.particlePath != nil
        }
        // Prewarm consumes the initial typed transform, before the first advance.
        let initialPointFrames = graph.assetsByPath.values.contains(where: {
            $0.definition.controlPoints.contains { ($0.rawFlags ?? 0) & 2 != 0 }
        }) ? SceneLayerDynamicWorldFrameResolver.resolve(
            descriptor: descriptor, byID: visibilityLayersByID,
            snapshot: initialDynamicValues,
            staticFrames: SceneLayerWorldFrameResolver.compute(
                descriptor: descriptor, byID: visibilityLayersByID)) : [:]
#if DEBUG
        let layersByPath = Dictionary(
            grouping: particleLayers,
            by: { SceneParticleAssetGraphLoader.normalizedPath($0.particlePath ?? "") }
        )
        for value in graph.diagnostics {
            let matchingLayers = layersByPath[value.assetPath] ?? []
            if matchingLayers.isEmpty {
                addDiagnostic(
                    kind: Self.runtimeKind(value.kind),
                    layerID: nil,
                    path: value.assetPath,
                    detail: value.detail
                )
            } else {
                for layer in matchingLayers {
                    addDiagnostic(
                        kind: Self.runtimeKind(value.kind),
                        layerID: layer.id,
                        path: value.assetPath,
                        detail: value.detail
                    )
                }
            }
        }

#endif

        let builtInTextureRegistry = SceneParticleBuiltInTextureRegistry(device: device)
        var pointerDemands: Set<Int> = []
        var worldSpaceDemandLayerIDs = Set<Int>()
        for layer in particleLayers {
            guard let rawPath = layer.particlePath else {
#if DEBUG
                addDiagnostic(
                    kind: .missingDefinition,
                    layerID: layer.id,
                    path: "",
                    detail: "particle layer has no definition reference"
                )
#endif
                continue
            }
            let path = SceneParticleAssetGraphLoader.normalizedPath(rawPath)
            guard let asset = graph.assetsByPath[path] else {
#if DEBUG
                addDiagnostic(
                    kind: .missingDefinition,
                    layerID: layer.id,
                    path: path,
                    detail: "definition asset missing from the loaded particle graph"
                )
#endif
                continue
            }
            let layerImageMap = layerImageEmissionMaps[layer.id]
            let render = asset.definition.renderers.isEmpty ? nil
                : supportedRenderer(in: asset.definition, layerID: layer.id, path: path)
            let forceEnvironment = descriptor.particleControlPointForceEnvironment(
                for: layer, definition: asset.definition)
            let translation = staticWorldSpaceFrames[layer.id] == nil
                && asset.definition.flags.isWorldSpace && !asset.definition.flags.usesPerspective
                ? preparedTranslations[layer.id] : nil
            let worldSpaceFrame = staticWorldSpaceFrames[layer.id] ?? translation?.frame
            guard !asset.definition.flags.isWorldSpace || worldSpaceFrame != nil else {
#if DEBUG
                addDiagnostic(
                    kind: .worldSpaceUnsupported,
                    layerID: layer.id,
                    path: path,
                    detail: "dynamicSystemTransform"
                )
#endif
                continue
            }
            guard !asset.definition.operators.contains(where: \.isWorldSpaceMovement)
                    || worldSpaceFrame != nil else {
#if DEBUG
                addDiagnostic(
                    kind: .worldSpaceMovementUnsupported,
                    layerID: layer.id,
                    path: path,
                    detail: "dynamicSystemTransform"
                )
#endif
                continue
            }
            let initialControlPointFrame = SceneParticleControlPointFrame(worldFrame: initialPointFrames[layer.id],
                                                                        sceneOrthoHeight: descriptor.camera.orthoHeight)
            let childRuntime = SceneParticleChildRuntime(
                layerID: layer.id,
                rootAsset: asset,
                graph: graph,
                textureLoader: textureLoader,
                builtInTextureRegistry: builtInTextureRegistry,
                device: device,
                worldSpaceFrame: worldSpaceFrame,
                rootInstanceOverride: layer.particleInstanceOverride,
                initialDynamicInstanceValues: initialDynamicValues.particleInstanceValues(layerID: layer.id),
                controlPointFrame: initialControlPointFrame,
                rootTranslationOffset: translation?.frame.birthPositionOffset ?? .zero,
                initialDynamicControlPoints: initialDynamicValues.particleControlPoints(layerID: layer.id),
                initialDynamicControlPointAngles: initialDynamicValues.particleControlPointAngles(layerID: layer.id)
            )
#if DEBUG
            for detail in childRuntime.unsupportedDetails {
                addDiagnostic(
                    kind: .childSystemsUnsupported,
                    layerID: layer.id,
                    path: path,
                    detail: detail
                )
            }
            for detail in childRuntime.performanceDetails {
                addDiagnostic(
                    kind: .simulationLimitation,
                    layerID: layer.id,
                    path: path,
                    detail: detail
                )
            }
#endif
            let retainedChildRuntime = childRuntime.hasTemplates ? childRuntime : nil
            if asset.definition.renderers.isEmpty {
                guard admitsChildOnlyContainer(
                    asset.definition,
                    childRuntime: childRuntime,
                    layerID: layer.id,
                    path: path
                ) else { continue }
                layers.append(SceneParticleLayerRuntime(
                    layerID: layer.id,
                    particlePath: path,
                    definition: asset.definition,
                    rootRender: nil,
                    childRuntime: retainedChildRuntime
                ))
                if let translation { rootWorldTranslationPlans[layer.id] = translation.plan }
                if childRuntime.hasPointerControlPointConsumer {
                    pointerDemands.insert(layer.id)
                }
                if asset.definition.flags.isWorldSpace
                    || asset.definition.operators.contains(where: \.isWorldSpaceMovement)
                    || childRuntime.hasWorldSpaceFrameConsumer {
                    worldSpaceDemandLayerIDs.insert(layer.id)
                }
                continue
            }

            guard asset.supportsBuiltInShaderExecution,
                  let renderState = asset.pipelineState,
                  admitsLayerImageEmitters(
                    asset.definition, map: layerImageMap, layerID: layer.id, path: path
                  ),
                  let render,
                  let rootRender = makeRootRenderRuntime(
                    asset: asset,
                    renderState: renderState,
                    render: render,
                    layer: layer,
                    path: path,
                    layerImageMap: layerImageMap,
                    worldSpaceFrame: worldSpaceFrame,
                    rootWorldTranslation: translation?.plan,
                    forceEnvironment: forceEnvironment,
                    controlPointFrame: initialControlPointFrame,
                    initialDynamicValues: initialDynamicValues,
                    initialPlayback: initialPlayback[layer.id] ?? .init(),
                    textureLoader: textureLoader,
                    builtInTextureRegistry: builtInTextureRegistry
                  ) else { continue }
#if DEBUG
            appendSimulationDiagnostics(
                rootRender.simulator.diagnostics,
                layerID: layer.id,
                path: path,
                handlesAllChildren: childRuntime.handlesAllChildren
            )
#endif
            layers.append(SceneParticleLayerRuntime(
                layerID: layer.id,
                particlePath: path,
                definition: asset.definition,
                rootRender: rootRender,
                childRuntime: retainedChildRuntime
            ))
            if let translation { rootWorldTranslationPlans[layer.id] = translation.plan }
            if !rootRender.pointerControlPointIdentities.isEmpty
                || childRuntime.hasPointerControlPointConsumer {
                pointerDemands.insert(layer.id)
            }
            if asset.definition.flags.isWorldSpace
                || asset.definition.operators.contains(where: \.isWorldSpaceMovement)
                || childRuntime.hasWorldSpaceFrameConsumer {
                worldSpaceDemandLayerIDs.insert(layer.id)
            }
        }
        pointerControlPointDemands = pointerDemands
        worldSpaceRequiringLayerIDs = worldSpaceDemandLayerIDs
        requiredPipelineVariants = layers.reduce(into: []) { variants, layer in
            var layerVariants = layer.childRuntime?.requiredPipelineVariants ?? []
            if let root = layer.rootRender {
                layerVariants.insert(.init(isRefraction: root.refraction != nil,
                    blendMode: root.renderState.blendMode,
                    usesDepthAttachment: root.renderState.depthWriteEnabled))
            }
            variants.formUnion(SceneParticlePipelineVariant.includingLayerDepth(layerVariants))
        }
    }

    /// Adopt the canonical current frame, including undeclared script writes.
    /// A missing or degenerate frame freezes only its world-space consumers;
    /// a later valid frame resumes them without replaying the frozen interval.
#if DEBUG
    private var liveWorldSpaceAdoptedLayerIDs: Set<Int> = []
#endif
    private func resolveCurrentWorldSpaceFrames(
        dynamicValues: SceneDynamicSnapshot,
        layerWorldFrames: [Int: simd_float4x4]
    ) -> [Int: SceneParticleWorldSpaceFrame] {
        var liveFrames: [Int: SceneParticleWorldSpaceFrame] = [:]
        for (layerID, plan) in rootWorldTranslationPlans {
            if let current = layerWorldFrames[layerID], let frame = plan.frame(currentWorldFrame: current) {
                liveFrames[layerID] = frame
                if frozenWorldSpaceLayerIDs.remove(layerID) != nil {
#if DEBUG
                    addDiagnostic(kind: .simulationLimitation, layerID: layerID,
                        path: layers.first { $0.layerID == layerID }?.particlePath ?? "",
                        detail: "world-space root translation resumed")
#endif
                }
            } else if frozenWorldSpaceLayerIDs.insert(layerID).inserted {
#if DEBUG
                addDiagnostic(kind: .simulationLimitation, layerID: layerID,
                    path: layers.first { $0.layerID == layerID }?.particlePath ?? "",
                    detail: "world-space root translation frozen: invalid current frame")
#endif
            }
        }
        guard !worldSpaceChains.isEmpty else { return liveFrames }
        let transformLayerIDs = dynamicValues.dynamicTransformLayerIDsForFrame
        guard !transformLayerIDs.isEmpty || !frozenWorldSpaceLayerIDs.isEmpty else { return liveFrames }
        for (layerID, chain) in worldSpaceChains
        where worldSpaceRequiringLayerIDs.contains(layerID)
            && (frozenWorldSpaceLayerIDs.contains(layerID)
                || !chain.isDisjoint(with: transformLayerIDs)) {
#if DEBUG
            let path = layers.first { $0.layerID == layerID }?.particlePath ?? ""
#endif
            if let current = layerWorldFrames[layerID],
               let frame = SceneParticleWorldSpaceFrame(worldFrame: current) {
                if frozenWorldSpaceLayerIDs.remove(layerID) != nil {
#if DEBUG
                    addDiagnostic(
                        kind: .simulationLimitation,
                        layerID: layerID,
                        path: path,
                        detail: "world-space frame resumed after transform recovered"
                    )
#endif
                }
                // A vanished write returns this chain to its prepared static
                // frame. Other chains' active lanes must not prevent recovery.
                guard !chain.isDisjoint(with: transformLayerIDs) else { continue }
#if DEBUG
                if liveWorldSpaceAdoptedLayerIDs.insert(layerID).inserted {
                    addDiagnostic(
                        kind: .simulationLimitation,
                        layerID: layerID,
                        path: path,
                        detail: "world-space frame follows current transform"
                    )
                }
#endif
                liveFrames[layerID] = frame
            } else if frozenWorldSpaceLayerIDs.insert(layerID).inserted {
#if DEBUG
                addDiagnostic(
                    kind: .simulationLimitation,
                    layerID: layerID,
                    path: path,
                    detail: "world-space frame frozen after runtime transform write"
                )
#endif
            }
        }
        return liveFrames
    }

    /// Advances every active layer by the frame delta and returns batches in scene render order.
    func advance(by frameDelta: TimeInterval, dynamicValues: SceneDynamicSnapshot = .empty(frameIndex: 0),
                 pointerLocalPositions: [Int: SIMD3<Double>] = [:], audioInput: SceneParticleAudioInput = .silent,
                 layerWorldFrames: [Int: simd_float4x4] = [:]) -> [SceneParticleDrawBatch] {
        let liveWorldSpaceFrames = resolveCurrentWorldSpaceFrames(
            dynamicValues: dynamicValues,
            layerWorldFrames: layerWorldFrames
        )
        var batches: [SceneParticleDrawBatch] = []
        for index in layers.indices {
            let layerID = layers[index].layerID
            let isVisible = SceneLayerVisibility.isEffectivelyVisible(
                layerID: layerID, in: descriptor,
                layersByID: visibilityLayersByID, snapshot: dynamicValues
            )
            // Hidden cadences discard their root births as well, so an explicit
            // hidden emission cannot survive until a later show. Children keep
            // their independent aging lifecycle below.
            if !isVisible || (layers[index].wasVisible != nil && layers[index].wasVisible != isVisible) {
                layers[index].rootRender?.simulator.restartPopulationForVisibility()
                layers[index].rootRender?.instances.removeAll(keepingCapacity: true)
                layers[index].rootRender?.ropeTrailHistory?.clear()
            }
            layers[index].wasVisible = isVisible
            let layerDelta = frozenWorldSpaceLayerIDs.contains(layerID)
                ? 0 : frameDelta
            let needsPointFrame = layers[index].rootRender?.simulator.needsWorldControlPointFrame == true
                || layers[index].childRuntime?.needsWorldControlPointFrame == true
            let pointFrame = needsPointFrame ? SceneParticleControlPointFrame(
                worldFrame: layerWorldFrames[layerID], sceneOrthoHeight: descriptor.camera.orthoHeight) : nil
            let worldSpaceFrameOverride = liveWorldSpaceFrames[layerID]
            var births: [SceneParticleState] = []
            var deaths: [SceneParticleState] = []
            var parentParticles = layers[index].rootRender?.simulator.particles ?? []
            let dynamicControlPoints = dynamicValues.particleControlPoints(
                layerID: layerID
            )
            let controlPointAngles = dynamicValues.particleControlPointAngles(
                layerID: layerID
            )
            let dynamicOverride = dynamicValues.particleInstanceValues(layerID: layerID)
            if isVisible, let root = layers[index].rootRender,
               !(rootWorldTranslationPlans[layerID] != nil && frozenWorldSpaceLayerIDs.contains(layerID)) {
                var rootControlPoints = dynamicControlPoints
                let pointerValues = root.definition.pointerControlPointValues(
                    at: pointerLocalPositions[layerID],
                    identities: root.pointerControlPointIdentities
                )
                rootControlPoints.merge(pointerValues) { _, pointer in pointer }
                let instanceOverride = SceneParticleInstanceOverride.resolving(
                    authored: root.simulator.instanceOverride, dynamic: dynamicOverride)
                root.simulator.advance(
                    by: layerDelta,
                    dynamicControlPoints: rootControlPoints,
                    dynamicControlPointAngles: controlPointAngles,
                    dynamicInstanceOverride: instanceOverride,
                    audioInput: audioInput,
                    worldSpaceFrameOverride: worldSpaceFrameOverride,
                    controlPointFrame: pointFrame
                )
#if DEBUG
                collectEvaluationObservations(layerID: layerID,
                    particlePath: layers[index].particlePath, simulator: root.simulator)
#endif
                births = root.simulator.consumeBirthEvents()
                deaths = root.simulator.consumeDeathEvents()
                parentParticles = root.simulator.particles
                layers[index].rootRender = root
            }
            if let childRuntime = layers[index].childRuntime {
                // Particle opacity comes from particle/instance alpha;
                // generic layer alpha does not modulate particle renderers.
                let result = childRuntime.advance(
                    by: layerDelta,
                    spawnEvents: births,
                    deathEvents: deaths,
                    parentParticles: parentParticles,
                    layerAlpha: 1,
                    dynamicInstanceValues: dynamicOverride,
                    pointerLocalPosition: pointerLocalPositions[layerID],
                    dynamicControlPoints: dynamicControlPoints,
                    dynamicControlPointAngles: controlPointAngles,
                    audioInput: audioInput,
                    worldSpaceFrameOverride: worldSpaceFrameOverride,
                    controlPointFrame: pointFrame,
                    rootTranslationOffset: worldSpaceFrameOverride?.birthPositionOffset
                        ?? layers[index].rootRender?.simulator.activeWorldSpaceFrame?.birthPositionOffset
                        ?? childRuntime.lastWorldSpaceFrame?.birthPositionOffset ?? .zero,
                    isFrozen: frozenWorldSpaceLayerIDs.contains(layerID),
                    isVisible: isVisible
                )
#if DEBUG
                collectEvaluationObservations(layerID: layerID, childRuntime: childRuntime)
#endif
                for var batch in result.batches {
                    batch.referenceWorldFrame = rootWorldTranslationPlans[layerID]?.referenceWorldFrame
                    batches.append(batch)
                }
#if DEBUG
                for detail in result.limitationDetails {
                    addDiagnostic(
                        kind: .simulationLimitation,
                        layerID: layers[index].layerID,
                        path: layers[index].particlePath,
                        detail: detail
                    )
                }
#endif
            }
            guard isVisible, var root = layers[index].rootRender else { continue }
            rebuildGPUInstances(root: &root)
            batches.append(SceneParticleDrawBatch(
                layerID: layerID,
                particlePath: layers[index].particlePath,
                texture: root.texture,
                colorUVScale: root.colorUVScale,
                colorSampling: root.colorSampling,
                refraction: root.refraction,
                renderState: root.renderState,
                childTemplateIndex: nil,
                instances: root.instances,
                orientation: root.orientation,
                orientationAxis: root.orientationAxis,
                usesPerspective: root.usesPerspective,
                inheritsNativeSceneCamera: root.ropeTrailHistory != nil,
                referenceWorldFrame: root.simulator.rootWorldTranslation?.referenceWorldFrame,
                sizeIsWorldSpace: root.definition.flags.isWorldSpace
            ))
#if DEBUG
            batches[batches.count - 1].debugRendererComponentIndex = root.debugRendererComponentIndex
            batches[batches.count - 1].debugRendererKind = root.debugRendererKind
#endif
            layers[index].rootRender = root
        }
        return batches
    }

    func frameSnapshot() -> FrameSnapshot {
        var snapshot = FrameSnapshot(layers: layers.map { layer in
            let root = layer.rootRender.map {
                FrameSnapshot.LayerSnapshot.RootSnapshot(
                    simulator: $0.simulator,
                    simulatorFrame: $0.simulator.frameSnapshot(),
                    instances: $0.instances,
                    ropeTrailHistory: $0.ropeTrailHistory
                )
            }
            return FrameSnapshot.LayerSnapshot(
                root: root,
                child: layer.childRuntime?.frameSnapshot(),
                wasVisible: layer.wasVisible
            )
        }, frozenWorldSpaceLayerIDs: frozenWorldSpaceLayerIDs)
#if DEBUG
        snapshot.pendingAudioEvaluationObservations = pendingAudioEvaluationObservations
        snapshot.pendingComponentObservations = pendingComponentObservations
        snapshot.adoptedWorldSpaceLayerIDs = liveWorldSpaceAdoptedLayerIDs
#endif
        return snapshot
    }

    func restoreFrame(_ snapshot: FrameSnapshot) {
        guard snapshot.layers.count == layers.count else { return }
        for index in layers.indices {
            layers[index].wasVisible = snapshot.layers[index].wasVisible
            if let rootSnapshot = snapshot.layers[index].root,
               var root = layers[index].rootRender {
                rootSnapshot.simulator.restoreFrame(rootSnapshot.simulatorFrame)
                root.instances = rootSnapshot.instances
                root.ropeTrailHistory = rootSnapshot.ropeTrailHistory
                layers[index].rootRender = root
            }
            if let childSnapshot = snapshot.layers[index].child {
                layers[index].childRuntime?.restoreFrame(childSnapshot)
            }
        }
#if DEBUG
        pendingAudioEvaluationObservations = snapshot.pendingAudioEvaluationObservations
        pendingComponentObservations = snapshot.pendingComponentObservations
#endif
        frozenWorldSpaceLayerIDs = snapshot.frozenWorldSpaceLayerIDs
#if DEBUG
        liveWorldSpaceAdoptedLayerIDs = snapshot.adoptedWorldSpaceLayerIDs
#endif
    }

#if DEBUG
    func consumeAudioEvaluationObservations()
        -> [SceneParticleRuntimeAudioEvaluationObservation] {
        defer { pendingAudioEvaluationObservations.removeAll(keepingCapacity: true) }
        return pendingAudioEvaluationObservations
    }
#endif

    func retire(layerIDs: Set<Int>) {
        layers.removeAll { layer in
            guard layerIDs.contains(layer.layerID) else { return false }
            layer.childRuntime?.teardown()
            return true
        }
        for layerID in layerIDs {
            worldSpaceChains.removeValue(forKey: layerID)
            rootWorldTranslationPlans.removeValue(forKey: layerID)
            pointerControlPointDemands.remove(layerID)
        }
        worldSpaceRequiringLayerIDs.subtract(layerIDs)
        frozenWorldSpaceLayerIDs.subtract(layerIDs)
#if DEBUG
        liveWorldSpaceAdoptedLayerIDs.subtract(layerIDs)
        pendingAudioEvaluationObservations.removeAll { layerIDs.contains($0.layerID) }
        pendingComponentObservations?.removeAll { layerIDs.contains($0.layerID) }
#endif
    }

    func teardown() {
        retire(layerIDs: Set(activeLayerIDs))
        layers.removeAll(keepingCapacity: false)
    }

    private func rebuildGPUInstances(
        root: inout SceneParticleRootRenderRuntime
    ) {
        let stepSnapshots = root.simulator.consumeStepSnapshots()
        if let rope = root.rope {
            root.instances = rope.instances(
                particles: root.simulator.particles,
                layerAlpha: 1,
                simulationTime: root.simulator.simulationTime
            )
            return
        }
        if var history = root.ropeTrailHistory {
            root.instances = history.advance(
                snapshots: stepSnapshots, currentParticles: root.simulator.particles,
                layerAlpha: 1
            )
            root.ropeTrailHistory = history
            return
        }
        let particles = root.simulator.renderParticlesForCurrentAdvance()
        root.instances.removeAll(keepingCapacity: true)
        root.instances.reserveCapacity(particles.count)
        for particle in particles {
            let frames = Self.spriteFrames(
                animation: root.spriteAnimation,
                staticAspect: root.staticSpriteAspect,
                definition: root.definition,
                particleID: particle.id,
                age: Float(particle.age),
                lifetime: Float(particle.lifetime)
            )
            root.instances.append(SceneParticleGPUInstance(
                position: particle.position.particleFloatValue,
                size: Float(particle.size),
                rotation: particle.rotation.particleFloatValue,
                color: particle.color.particleFloatValue,
                alpha: Float(particle.alpha),
                velocity: root.trail?.direction(for: particle.velocity)
                    ?? particle.velocity.particleFloatValue,
                trailStretch: root.trail?.stretch(for: particle.velocity),
                currentFrame: frames.current.orientedForTrail(root.trail != nil),
                nextFrame: frames.next?.orientedForTrail(root.trail != nil),
                currentFrameAspect: frames.currentAspect,
                nextFrameAspect: frames.nextAspect,
                frameMix: frames.mix
            ))
        }
        // Translucent particles blend as premultiplied "over", so draw order
        // decides local brightness; simulation order is not a depth order and
        // shows as uneven stacking and flicker. Sort far-to-near by the depth
        // proxy available at rebuild time — the layer-local z axis. In this
        // engine's orthographic and fallback-perspective frames the camera sits
        // on the +z side looking toward -z, so SMALLER z is farther; ascending
        // z therefore draws far first and near last, which is what "over"
        // compositing requires. The proxy is exact for unrotated layers and an
        // approximation for X/Y-rotated layers and authored perspective scenes.
        // Only large translucent systems pay for the sort: additive blending
        // is commutative (one/one) and order-invariant, opaque profiles are
        // never admitted by the pipeline compiler, and the 256-instance
        // threshold keeps small systems at zero sort cost. The index
        // tiebreak makes the sort stable: equal-depth instances keep
        // simulation order.
        if root.renderState.blendMode == .translucent, root.instances.count >= 256 {
            let order = root.instances.indices.sorted { lhs, rhs in
                let lhsZ = root.instances[lhs].positionAndSize.z
                let rhsZ = root.instances[rhs].positionAndSize.z
                return lhsZ == rhsZ ? lhs < rhs : lhsZ < rhsZ
            }
            root.instances = order.map { root.instances[$0] }
        }
    }

#if DEBUG
    var childRuntimeSummaries: [String] {
        layers.compactMap { layer in
            layer.childRuntime.map {
                "layer=\(layer.layerID): \($0.expansionSummary)"
            }
        }
    }

    func addDiagnostic(
        kind: SceneParticleRuntimeDiagnosticKind, layerID: Int?, path: String, detail: String? = nil
    ) {
        let value = SceneParticleRuntimeDiagnostic(
            kind: kind, layerID: layerID, particlePath: path, detail: detail
        )
        if !diagnostics.contains(value) { diagnostics.append(value) }
    }
#endif

    // swiftlint:disable:next function_parameter_count
    private func makeRootRenderRuntime(
        asset: SceneParticleAsset,
        renderState: SceneParticlePipelineRenderState,
        render: (
            renderer: SceneParticleRenderer,
            trail: SceneParticleTrailRenderPlan?,
            rope: SceneParticleRopePlan?,
            ropeTrail: SceneParticleRopeTrailPlan?
        ),
        layer: SceneRenderDescriptor.Layer,
        path: String,
        layerImageMap: SceneParticleLayerImageEmissionMap?,
        worldSpaceFrame: SceneParticleWorldSpaceFrame?,
        rootWorldTranslation: SceneParticleRootWorldTranslationPlan?,
        forceEnvironment: SceneParticleControlPointForceEnvironment,
        controlPointFrame: SceneParticleControlPointFrame?,
        initialDynamicValues: SceneDynamicSnapshot,
        initialPlayback: SceneParticlePlaybackSnapshot,
        textureLoader: SceneTextureLoader,
        builtInTextureRegistry: SceneParticleBuiltInTextureRegistry
    ) -> SceneParticleRootRenderRuntime? {
        guard let textureSource = asset.textureSource else { return nil }
        let texture: MTLTexture
        let spriteAnimation: SceneSpriteAnimation?
        let staticSpriteAspect: Float
        let colorUVScale: SIMD2<Float>
        let colorSampling: SceneParticleTextureSampling
        let refraction: SceneParticleRefractionBinding?
        do {
            if let declaration = asset.refraction {
                guard let loaded = try SceneParticleRefractionTextureLoader.load(
                    colorSource: textureSource,
                    declaration: declaration,
                    textureLoader: textureLoader,
                    device: device
                ) else {
#if DEBUG
                    addDiagnostic(
                        kind: .refractionUnsupported,
                        layerID: layer.id,
                        path: path,
                        detail: "textureProfileUnsupported"
                    )
#endif
                    return nil
                }
                texture = loaded.color
                spriteAnimation = loaded.colorAnimation
                staticSpriteAspect = loaded.staticSpriteAspect
                colorUVScale = loaded.colorUVScale
                colorSampling = loaded.colorSampling
                refraction = loaded.binding
            } else {
                guard let loaded = try SceneParticleChildTemplateSupport.loadTexture(
                    textureSource,
                    textureLoader: textureLoader,
                    builtInTextureRegistry: builtInTextureRegistry,
                    device: device,
                    usesWholeImage: render.rope != nil
                ) else {
#if DEBUG
                    addDiagnostic(
                        kind: .textureLoadFailed, layerID: layer.id, path: path,
                        detail: "particleColorTexturePreparationFailed"
                    )
#endif
                    return nil
                }
                texture = loaded.texture
                spriteAnimation = loaded.animation
                staticSpriteAspect = loaded.staticAspect
                colorSampling = loaded.sampling
                colorUVScale = loaded.uvScale
                refraction = nil
            }
        } catch {
#if DEBUG
            addDiagnostic(kind: .textureLoadFailed, layerID: layer.id, path: path,
                          detail: "resourceReadFailed:\(error)")
#endif
            return nil
        }
        guard supportsPathRendererTexture(
            rope: render.rope,
            ropeTrail: render.ropeTrail,
            animation: spriteAnimation,
            layerID: layer.id,
            path: path
        ) else { return nil }

        let initialInstanceOverride = SceneParticleInstanceOverride.resolving(
            authored: layer.particleInstanceOverride,
            dynamic: initialDynamicValues.particleInstanceValues(layerID: layer.id))
        let simulator = SceneParticleSimulator(
            definition: asset.definition,
            instanceOverride: layer.particleInstanceOverride,
            initialDynamicInstanceOverride: initialInstanceOverride,
            initialDynamicControlPoints: initialDynamicValues.particleControlPoints(layerID: layer.id),
            initialDynamicControlPointAngles: initialDynamicValues.particleControlPointAngles(layerID: layer.id),
            initialPlayback: initialPlayback,
            seed: UInt64(bitPattern: Int64(layer.id)),
            prewarmStepBudget: 3_600,
            layerImageEmissionMap: layerImageMap,
            worldSpaceFrame: worldSpaceFrame,
            rootWorldTranslation: rootWorldTranslation,
            controlPointForceEnvironment: forceEnvironment,
            controlPointFrame: controlPointFrame,
            stepSnapshotPolicy: render.ropeTrail?.stepSnapshotPolicy
        )
        var root = SceneParticleRootRenderRuntime(
            definition: asset.definition,
            pointerControlPointIdentities: asset.definition.pointerControlPointIdentities(environment: forceEnvironment),
            trail: render.trail,
            rope: render.rope,
            texture: texture,
            colorUVScale: colorUVScale,
            colorSampling: colorSampling,
            refraction: refraction,
            renderState: renderState,
            spriteAnimation: spriteAnimation,
            staticSpriteAspect: staticSpriteAspect,
            orientation: SceneParticleOrientation(
                authoredValue: render.renderer.orientation,
                isWorldSpace: render.renderer.isWorldSpace
            ),
            orientationAxis: render.renderer.axis.map {
                SceneParticleSimulationMath.vector(
                    $0,
                    fallback: SIMD3(0, 0, 1)
                ).particleFloatValue
            },
            usesPerspective: asset.definition.flags.usesPerspective,
            simulator: simulator,
            ropeTrailHistory: render.ropeTrail.map(
                SceneParticleRopeTrailHistory.init(plan:)
            )
        )
#if DEBUG
        if let sources = asset.definition.componentObservationSources {
            let typedIndex = asset.definition.renderers.firstIndex(of: render.renderer)
            root.debugRendererComponentIndex = typedIndex.flatMap { sources["renderer"]?[$0].componentIndex }
            root.debugRendererKind = asset.definition.rendererWasImplicit ? "sprite"
                : typedIndex.flatMap { sources["renderer"]?[$0].kind }
            simulator.observeSelectedRenderer(typedIndex: typedIndex)
        }
#endif
        return root
    }
}
