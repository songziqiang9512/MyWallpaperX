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
    private(set) var pipelineVariants: SceneParticlePipelineVariant.Preparation = ([], [])
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
                root.clearOutputs(keepingCapacity: false)
            }
        }
        layers[index].rootRender = root
    }
    func clearStoppedPlaybackCaches(_ layerIDs: Set<Int>) {
        for index in layers.indices where layerIDs.contains(layers[index].layerID) {
            layers[index].rootRender?.clearOutputs()
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
                root.clearOutputs()
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
        let lightClasses = descriptor.lighting?.lightClasses ?? .init()
        // Hidden lamps retain their prepared dynamic inputs and may become live.
        let hasPotentialDirectLights = descriptor.layers.contains { layer in
            if let point = layer.pointLight {
                return point.kind == "point" || lightClasses.point
            }
            return (layer.directionalLight != nil && lightClasses.directional)
                || (layer.spotLight != nil && lightClasses.spot)
        }
        let supportsAmbientLighting = !hasPotentialDirectLights
            && SceneAuthoredShaderLightingInputs.Builder(
                orthographicHeight: descriptor.camera.orthoHeight,
                ambient: descriptor.lighting?.ambientColorRGB
            ).finish().ambient != nil
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
            supportsAmbientLighting: supportsAmbientLighting,
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
        initialWorldFrames: [Int: simd_float4x4]? = nil,
        initialPlayback: [Int: SceneParticlePlaybackSnapshot] = [:],
        initialAudioInput: SceneParticleAudioInput = .silent,
        initialSceneTime: Double = 0,
        destroyedAuthoredLayerIDs: Set<Int> = [],
        shouldCancelPrewarm: (() -> Bool)? = nil
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
        let needsInitialPointFrames = graph.assetsByPath.values.contains {
            $0.definition.controlPoints.contains { $0.rawFlags & 2 != 0 }
        }
        // Production supplies the pose already used for its initial batches.
        var prewarmWorldFrames = initialWorldFrames
        func prewarmWorldFrame(for layerID: Int) -> simd_float4x4? {
            if prewarmWorldFrames == nil {
                prewarmWorldFrames = SceneLayerDynamicWorldFrameResolver.resolve(
                    descriptor: descriptor, byID: visibilityLayersByID,
                    snapshot: initialDynamicValues,
                    staticFrames: SceneLayerWorldFrameResolver.compute(
                        descriptor: descriptor, byID: visibilityLayersByID))
            }
            return prewarmWorldFrames?[layerID]
        }
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
            let renderers = supportedRenderers(in: asset.definition, layerID: layer.id, path: path)
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
            let initialControlPointFrame = needsInitialPointFrames ? SceneParticleControlPointFrame(
                worldFrame: prewarmWorldFrame(for: layer.id), sceneOrthoHeight: descriptor.camera.orthoHeight) : nil
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
                initialDynamicControlPointAngles: initialDynamicValues.particleControlPointAngles(layerID: layer.id),
                initialAudioInput: initialAudioInput, initialSceneTime: initialSceneTime
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
                  admitsLayerImageEmitters(
                    asset.definition, map: layerImageMap, layerID: layer.id, path: path
                  ),
                  !renderers.isEmpty else { continue }
            let boundsExtent = asset.definition.hasCanvasCollision ? collisionBoundsExtent : nil
            let initialBoundsFrame: SceneParticleCollisionBoundsFrame?
            if (asset.definition.startTime ?? 0) > 0, let boundsExtent,
               let worldFrame = prewarmWorldFrame(for: layer.id) {
                initialBoundsFrame = .init(extent: boundsExtent, worldFrame: worldFrame)
            } else {
                initialBoundsFrame = nil
            }
            guard let rootRender = makeRootRenderRuntime(
                asset: asset,
                plans: renderers,
                layer: layer,
                path: path,
                hasChildSystems: retainedChildRuntime != nil,
                layerImageMap: layerImageMap,
                worldSpaceFrame: worldSpaceFrame,
                rootWorldTranslation: translation?.plan,
                forceEnvironment: forceEnvironment,
                controlPointFrame: initialControlPointFrame,
                collisionBoundsExtent: boundsExtent,
                collisionBoundsFrame: initialBoundsFrame,
                initialDynamicValues: initialDynamicValues,
                initialPlayback: initialPlayback[layer.id] ?? .init(),
                initialAudioInput: initialAudioInput, initialSceneTime: initialSceneTime,
                shouldCancelPrewarm: shouldCancelPrewarm,
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
        let canUseSceneDepth = SceneParticleCameraFrame.acceptsNativePerspectiveProjection(camera: descriptor.camera)
        pipelineVariants = layers.reduce(into: ([], [])) { variants, layer in
            var layerVariants = layer.childRuntime?.requiredPipelineVariants ?? []
            if let root = layer.rootRender {
                for output in root.outputs {
                    let renderer = output.renderer
                    layerVariants.insert(.init(isRefraction: renderer.refraction != nil,
                        blendMode: renderer.renderState.blendMode,
                        usesDepthAttachment: renderer.renderState.depthWriteEnabled))
                    guard canUseSceneDepth else { continue }
                    if renderer.ignoresNativeSceneDepthWrite {
                        variants.sceneDepth.insert(.init(
                            blendMode: renderer.renderState.blendMode, usesDepthAttachment: false
                        ))
                    }
                    let readsSceneDepth = renderer.ignoresNativeSceneDepthWrite
                        ? renderer.renderState.depthTestEnabled
                        : renderer.renderState.readsSceneDepth(
                            usesSceneCamera: renderer.usesSceneCamera, isRefraction: renderer.refraction != nil
                        )
                    if readsSceneDepth {
                        variants.sceneDepth.insert(.init(
                            blendMode: renderer.renderState.blendMode, usesDepthAttachment: true
                        ))
                    }
                }
            }
            variants.required.formUnion(SceneParticlePipelineVariant.includingLayerDepth(layerVariants))
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
    func advance(by frameDelta: TimeInterval, sceneTime: Double = 0,
                 dynamicValues: SceneDynamicSnapshot = .empty(frameIndex: 0),
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
                layers[index].rootRender?.clearOutputs()
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
                let authoredOverride = root.simulator.instanceOverride
                let instanceOverride = SceneParticleInstanceOverride.resolving(
                    authored: authoredOverride, dynamic: dynamicOverride,
                    brightness: dynamicValues.particleBrightness(
                        layerID: layerID, isBound: authoredOverride?.brightness?.userPropertyKey != nil
                    ))
                let collisionFrame: SceneParticleCollisionBoundsFrame?
                if layerDelta > 0, let extent = root.collisionBoundsExtent,
                   let worldFrame = layerWorldFrames[layerID] {
                    collisionFrame = .init(extent: extent, worldFrame: worldFrame)
                } else {
                    collisionFrame = nil
                }
                root.simulator.advance(
                    by: layerDelta,
                    sceneTime: sceneTime,
                    dynamicControlPoints: rootControlPoints,
                    dynamicControlPointAngles: controlPointAngles,
                    dynamicInstanceOverride: instanceOverride,
                    audioInput: audioInput,
                    worldSpaceFrameOverride: worldSpaceFrameOverride,
                    controlPointFrame: pointFrame,
                    collisionBoundsFrame: collisionFrame
                )
#if DEBUG
                collectEvaluationObservations(layerID: layerID,
                    particlePath: layers[index].particlePath, simulator: root.simulator)
#endif
                births = root.simulator.consumeBirthEvents()
                deaths = root.simulator.consumeDeathEvents()
                layers[index].rootRender = root
            }
            if let childRuntime = layers[index].childRuntime {
                let parentParticles = layers[index].rootRender?.simulator.particles.liveParticles ?? []
                // Particle opacity comes from particle/instance alpha;
                // generic layer alpha does not modulate particle renderers.
                let result = childRuntime.advance(
                    by: layerDelta,
                    sceneTime: sceneTime,
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
            let referenceWorldFrame = root.simulator.rootWorldTranslation?.referenceWorldFrame
            root.rebuildInstances(worldFrame: referenceWorldFrame ?? layerWorldFrames[layerID])
            for output in root.outputs {
                batches.append(output.renderer.drawBatch(
                    layerID: layerID, particlePath: layers[index].particlePath,
                    childTemplateIndex: nil, instances: output.instances,
                    referenceWorldFrame: referenceWorldFrame,
                    sizeIsWorldSpace: root.definition.flags.isWorldSpace
                ))
            }
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
                    outputs: $0.outputs
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
                root.outputs = rootSnapshot.outputs
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
        asset: SceneParticleAsset, plans: [SceneParticleRendererPlan],
        layer: SceneRenderDescriptor.Layer, path: String, hasChildSystems: Bool,
        layerImageMap: SceneParticleLayerImageEmissionMap?,
        worldSpaceFrame: SceneParticleWorldSpaceFrame?,
        rootWorldTranslation: SceneParticleRootWorldTranslationPlan?,
        forceEnvironment: SceneParticleControlPointForceEnvironment,
        controlPointFrame: SceneParticleControlPointFrame?,
        collisionBoundsExtent: SIMD2<Float>?,
        collisionBoundsFrame: SceneParticleCollisionBoundsFrame?,
        initialDynamicValues: SceneDynamicSnapshot,
        initialPlayback: SceneParticlePlaybackSnapshot,
        initialAudioInput: SceneParticleAudioInput, initialSceneTime: Double,
        shouldCancelPrewarm: (() -> Bool)?, textureLoader: SceneTextureLoader,
        builtInTextureRegistry: SceneParticleBuiltInTextureRegistry
    ) -> SceneParticleRootRenderRuntime? {
        var prepared = SceneParticlePreparedRenderer.prepare(
            plans: plans, asset: asset, rootUsesWorldSpace: asset.definition.flags.isWorldSpace,
            textureLoader: textureLoader,
            builtInTextureRegistry: builtInTextureRegistry, device: device
        ) { _, reason in
#if DEBUG
            let kind: SceneParticleRuntimeDiagnosticKind
            if reason.hasPrefix("rope:") { kind = .ropeRendererUnsupported }
            else if reason.hasPrefix("ropetrail:") { kind = .trailRendererUnsupported }
            else if reason == "textureProfileUnsupported" { kind = .refractionUnsupported }
            else { kind = .textureLoadFailed }
            addDiagnostic(kind: kind, layerID: layer.id, path: path, detail: reason)
#endif
        }
        guard !prepared.isEmpty else { return nil }
        if !hasChildSystems, layer.parentID == nil, let state = asset.pipelineState,
           state.blendMode == .translucent, state.depthWriteEnabled,
           prepared.allSatisfy(\.usesSceneCamera) {
            for index in prepared.indices { prepared[index].ignoresNativeSceneDepthWrite = true }
        }
        let initialInstanceOverride = SceneParticleInstanceOverride.resolving(
            authored: layer.particleInstanceOverride,
            dynamic: initialDynamicValues.particleInstanceValues(layerID: layer.id),
            brightness: initialDynamicValues.particleBrightness(
                layerID: layer.id, isBound: layer.particleInstanceOverride?.brightness?.userPropertyKey != nil
            ))
        let simulator = SceneParticleSimulator(
            definition: asset.definition,
            instanceOverride: layer.particleInstanceOverride,
            initialDynamicInstanceOverride: initialInstanceOverride,
            initialDynamicControlPoints: initialDynamicValues.particleControlPoints(layerID: layer.id),
            initialDynamicControlPointAngles: initialDynamicValues.particleControlPointAngles(layerID: layer.id),
            initialPlayback: initialPlayback,
            initialAudioInput: initialAudioInput, initialSceneTime: initialSceneTime,
            seed: UInt64(bitPattern: Int64(layer.id)),
            prewarmStepBudget: nil,
            shouldCancelPrewarm: shouldCancelPrewarm,
            layerImageEmissionMap: layerImageMap,
            worldSpaceFrame: worldSpaceFrame,
            rootWorldTranslation: rootWorldTranslation,
            controlPointForceEnvironment: forceEnvironment,
            controlPointFrame: controlPointFrame,
            collisionBoundsFrame: collisionBoundsFrame,
            stepSnapshotPolicies: prepared.compactMap { $0.snapshotPolicy }
        )
#if DEBUG
        simulator.observeSelectedRenderers(typedIndices: prepared.map(\.index))
#endif
        return SceneParticleRootRenderRuntime(
            definition: asset.definition,
            collisionBoundsExtent: collisionBoundsExtent,
            pointerControlPointIdentities: asset.definition.pointerControlPointIdentities(environment: forceEnvironment),
            simulator: simulator,
            outputs: prepared.map {
                SceneParticleRootRendererOutput(
                    renderer: $0,
                    ropeTrailHistory: $0.ropeTrail.map(SceneParticleRopeTrailHistory.init(plan:))
                )
            }
        )
    }

    private var collisionBoundsExtent: SIMD2<Float>? {
        let camera = descriptor.camera
        guard camera.authoredOrthographicProjectionActive != false,
              let width = camera.orthoWidth, let height = camera.orthoHeight else { return nil }
        return SIMD2(width, height)
    }
}
