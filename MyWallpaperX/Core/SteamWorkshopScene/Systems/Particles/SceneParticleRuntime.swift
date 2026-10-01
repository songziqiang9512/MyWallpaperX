import Foundation
import Metal
import simd

/// Owns the CPU state and GPU instance buffers for effectively visible particle layers.
/// Particle positions and sizes stay in the author-defined layer-local coordinate system.
/// The renderer applies the layer world frame, Y-axis convention, and layer scale once.
final class SceneParticleRuntime {
    struct FrameSnapshot {
        struct LayerSnapshot {
            struct RootSnapshot {
                let simulator: SceneParticleSimulator
                let simulatorFrame: SceneParticleSimulator.FrameSnapshot
                let instances: [SceneParticleGPUInstance]
                let ropeTrailHistory: SceneParticleRopeTrailHistory?
            }

            let root: RootSnapshot?
            let child: SceneParticleChildRuntime.FrameSnapshot?
        }

        let layers: [LayerSnapshot]
        let pendingAudioEvaluationObservations:
            [SceneParticleRuntimeAudioEvaluationObservation]
        /// World-space freeze/adopt bookkeeping enters the same
        /// transaction as the simulation values: a discarded frame rolls
        /// the freeze back with the particles, and a replayed frame
        /// re-derives it from the same inputs.
        let frozenWorldSpaceLayerIDs: Set<Int>
        let adoptedWorldSpaceLayerIDs: Set<Int>
    }

    private let device: MTLDevice
    private var layers: [SceneParticleLayerRuntime] = []
    private(set) var diagnostics: [SceneParticleRuntimeDiagnostic] = []
    /// Eligible world-space layer -> ancestor-chain members. A dynamic-snapshot
    /// transform write into any member invalidates that system's launch-static
    /// world frame; the system then simulates with a zero delta so its last
    /// committed particle state keeps rendering (previous-current).
    private let worldSpaceChains: [Int: Set<Int>]
    /// Particle layers whose simulation actually converts through the world
    /// frame: root world-space flags/movement or any admitted child
    /// template with them. The freeze/re-adopt transaction applies only to
    /// these; a local-space system under the same scripted chain keeps
    /// simulating because the layer world frame only matters at draw time.
    /// Assigned once at the end of init and never mutated afterwards.
    private var worldSpaceRequiringLayerIDs: Set<Int> = []
    private var frozenWorldSpaceLayerIDs: Set<Int> = []
    /// Launch-stable layer demand for pointer projection. Root and child
    /// template identities are prepared with the particle graph; frame-varying
    /// coordinates are still supplied by the host each advance.
    private(set) var pointerControlPointLayerIDs: Set<Int> = []
    private var pendingAudioEvaluationObservations:
        [SceneParticleRuntimeAudioEvaluationObservation] = []

    func playbackObservation(layerID: Int) -> SceneParticlePlaybackObservation? {
        layers.first { $0.layerID == layerID }?.rootRender?.simulator.playbackObservation
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

    init(
        descriptor: SceneRenderDescriptor,
        cacheDirectory: URL,
        device: MTLDevice,
        resourceView: SceneResourceView? = nil,
        stockTextureBundleURL: URL? = SceneStockTextureResolver.defaultBundleRoot(),
        textureLoader: SceneTextureLoader = SceneTextureLoader(),
        layerImageEmissionMaps: [Int: SceneParticleLayerImageEmissionMap] = [:],
        initialDiagnostics: [SceneParticleRuntimeDiagnostic] = [],
        staticWorldSpaceFrames: [Int: SceneParticleWorldSpaceFrame]? = nil,
        staticWorldSpaceChains: [Int: Set<Int>]? = nil,
        initialDynamicValues: SceneDynamicSnapshot = .empty(frameIndex: 0),
        initialPlayback: [Int: SceneParticlePlaybackSnapshot] = [:]
    ) {
        self.device = device
        diagnostics = initialDiagnostics
        let staticWorldSpaceFrames = staticWorldSpaceFrames
            ?? descriptor.staticParticleWorldSpaceFrames
        worldSpaceChains = staticWorldSpaceChains
            ?? descriptor.staticParticleWorldSpaceChains
        let visibleIDs = SceneLayerVisibility.visibleLayerIDs(in: descriptor)
        let particleLayers = Self.orderedLayers(in: descriptor).filter {
            visibleIDs.contains($0.id)
                && $0.contentKind == "particle"
                && $0.particlePath != nil
                && $0.particleInstanceOverride?.alpha?.isStaticZeroScalar != true
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
                        isStatic: $0.userBinding == nil
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
        let graph = SceneParticleAssetGraphLoader(
            resourceView: resourceView,
            stockTextureBundleURL: stockTextureBundleURL
        ).load(
            rootPaths: particleLayers.compactMap(\.particlePath),
            materialPasses: materialPasses,
            cacheDirectory: cacheDirectory
        )
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

        let builtInTextureRegistry = SceneParticleBuiltInTextureRegistry(device: device)
        var pointerDemandLayerIDs = Set<Int>()
        var worldSpaceDemandLayerIDs = Set<Int>()
        for layer in particleLayers {
            guard let rawPath = layer.particlePath else {
                addDiagnostic(
                    kind: .missingDefinition,
                    layerID: layer.id,
                    path: "",
                    detail: "particle layer has no definition reference"
                )
                continue
            }
            let path = SceneParticleAssetGraphLoader.normalizedPath(rawPath)
            guard let asset = graph.assetsByPath[path] else {
                addDiagnostic(
                    kind: .missingDefinition,
                    layerID: layer.id,
                    path: path,
                    detail: "definition asset missing from the loaded particle graph"
                )
                continue
            }
            let layerImageMap = layerImageEmissionMaps[layer.id]
            let worldSpaceFrame = staticWorldSpaceFrames[layer.id]
            guard !asset.definition.flags.isWorldSpace || worldSpaceFrame != nil else {
                addDiagnostic(
                    kind: .worldSpaceUnsupported,
                    layerID: layer.id,
                    path: path,
                    detail: "dynamicSystemTransform"
                )
                continue
            }
            guard !asset.definition.operators.contains(where: \.isWorldSpaceMovement)
                    || worldSpaceFrame != nil else {
                addDiagnostic(
                    kind: .worldSpaceMovementUnsupported,
                    layerID: layer.id,
                    path: path,
                    detail: "dynamicSystemTransform"
                )
                continue
            }
            let childRuntime = SceneParticleChildRuntime(
                layerID: layer.id,
                rootAsset: asset,
                graph: graph,
                textureLoader: textureLoader,
                builtInTextureRegistry: builtInTextureRegistry,
                device: device,
                worldSpaceFrame: worldSpaceFrame,
                rootInstanceOverride: layer.particleInstanceOverride,
                initialDynamicInstanceValues: initialDynamicValues.particleInstanceValues(layerID: layer.id)
            )
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
                    layerAlpha: Float(min(max(layer.alpha ?? 1, 0), 1)),
                    rootRender: nil,
                    childRuntime: retainedChildRuntime
                ))
                if childRuntime.hasPointerControlPointConsumer {
                    pointerDemandLayerIDs.insert(layer.id)
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
                  let render = supportedRenderer(
                    in: asset.definition, layerID: layer.id, path: path
                  ),
                  let rootRender = makeRootRenderRuntime(
                    asset: asset,
                    renderState: renderState,
                    render: render,
                    layer: layer,
                    path: path,
                    layerImageMap: layerImageMap,
                    worldSpaceFrame: worldSpaceFrame,
                    initialDynamicValues: initialDynamicValues,
                    initialPlayback: initialPlayback[layer.id] ?? .init(),
                    textureLoader: textureLoader,
                    builtInTextureRegistry: builtInTextureRegistry
                  ) else { continue }
            appendSimulationDiagnostics(
                rootRender.simulator.diagnostics,
                layerID: layer.id,
                path: path,
                handlesAllChildren: childRuntime.handlesAllChildren
            )
            layers.append(SceneParticleLayerRuntime(
                layerID: layer.id,
                particlePath: path,
                definition: asset.definition,
                layerAlpha: Float(min(max(layer.alpha ?? 1, 0), 1)),
                rootRender: rootRender,
                childRuntime: retainedChildRuntime
            ))
            if !rootRender.pointerControlPointIdentities.isEmpty
                || childRuntime.hasPointerControlPointConsumer {
                pointerDemandLayerIDs.insert(layer.id)
            }
            if asset.definition.flags.isWorldSpace
                || asset.definition.operators.contains(where: \.isWorldSpaceMovement)
                || childRuntime.hasWorldSpaceFrameConsumer {
                worldSpaceDemandLayerIDs.insert(layer.id)
            }
        }
        pointerControlPointLayerIDs = pointerDemandLayerIDs
        worldSpaceRequiringLayerIDs = worldSpaceDemandLayerIDs
    }

    /// A script anywhere in the scene may write a chain layer's transform
    /// through the dynamic snapshot without a declared binding. The runtime
    /// then adopts the renderer's current world frame for that system; only
    /// when no current frame is available (or it is degenerate) does the
    /// system freeze for that frame and keep its last committed particles.
    /// The freeze lasts exactly as long as the degenerate state: a later
    /// frame that can construct a valid frame for the chain — whether that
    /// frame carries a fresh transform write or the write has already
    /// vanished (one-shot undeclared script write, finished timeline) and
    /// the snapshot fell back to the authored transform — resumes
    /// simulation. Lane-less frames that still cannot construct a frame
    /// keep the previous-current freeze.
    private var liveWorldSpaceAdoptedLayerIDs: Set<Int> = []
    private func resolveCurrentWorldSpaceFrames(
        dynamicValues: SceneDynamicSnapshot,
        layerWorldFrames: [Int: simd_float4x4]
    ) -> [Int: SceneParticleWorldSpaceFrame] {
        guard !worldSpaceChains.isEmpty else { return [:] }
        let transformLayerIDs = dynamicValues.dynamicTransformLayerIDsForFrame
        guard !transformLayerIDs.isEmpty || !frozenWorldSpaceLayerIDs.isEmpty else { return [:] }
        var liveFrames: [Int: SceneParticleWorldSpaceFrame] = [:]
        for (layerID, chain) in worldSpaceChains
        where worldSpaceRequiringLayerIDs.contains(layerID)
            && (frozenWorldSpaceLayerIDs.contains(layerID)
                || !chain.isDisjoint(with: transformLayerIDs)) {
            let path = layers.first { $0.layerID == layerID }?.particlePath ?? ""
            if let current = layerWorldFrames[layerID],
               let frame = SceneParticleWorldSpaceFrame(worldFrame: current) {
                if frozenWorldSpaceLayerIDs.remove(layerID) != nil {
                    addDiagnostic(
                        kind: .simulationLimitation,
                        layerID: layerID,
                        path: path,
                        detail: "world-space frame resumed after transform recovered"
                    )
                }
                // A vanished write returns this chain to its prepared static
                // frame. Other chains' active lanes must not prevent recovery.
                guard !chain.isDisjoint(with: transformLayerIDs) else { continue }
                if liveWorldSpaceAdoptedLayerIDs.insert(layerID).inserted {
                    addDiagnostic(
                        kind: .simulationLimitation,
                        layerID: layerID,
                        path: path,
                        detail: "world-space frame follows current transform"
                    )
                }
                liveFrames[layerID] = frame
            } else if frozenWorldSpaceLayerIDs.insert(layerID).inserted {
                addDiagnostic(
                    kind: .simulationLimitation,
                    layerID: layerID,
                    path: path,
                    detail: "world-space frame frozen after runtime transform write"
                )
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
            let layerDelta = frozenWorldSpaceLayerIDs.contains(layerID)
                ? 0 : frameDelta
            let worldSpaceFrameOverride = liveWorldSpaceFrames[layerID]
            let layerAlpha = SceneDynamicLayerValues.alpha(
                layerID: layerID,
                authoredValue: Double(layers[index].layerAlpha),
                snapshot: dynamicValues
            )
            var births: [SceneParticleState] = []
            var deaths: [SceneParticleState] = []
            var parentParticles: [SceneParticleState] = []
            let dynamicControlPoints = dynamicValues.particleControlPoints(
                layerID: layerID
            )
            let controlPointAngles = dynamicValues.particleControlPointAngles(
                layerID: layerID
            )
            let dynamicOverride = dynamicValues.particleInstanceValues(layerID: layerID)
            if let root = layers[index].rootRender {
                var rootControlPoints = dynamicControlPoints
                let pointerValues = root.definition.pointerControlPointValues(
                    at: pointerLocalPositions[layerID],
                    identities: root.pointerControlPointIdentities
                )
                rootControlPoints.merge(pointerValues) { _, pointer in pointer }
                let instanceOverride = root.simulator.instanceOverride?.resolving(
                    dynamicOverride
                )
                root.simulator.advance(
                    by: layerDelta,
                    dynamicControlPoints: rootControlPoints,
                    dynamicControlPointAngles: controlPointAngles,
                    dynamicInstanceOverride: instanceOverride,
                    audioInput: audioInput,
                    worldSpaceFrameOverride: worldSpaceFrameOverride
                )
                pendingAudioEvaluationObservations.append(contentsOf:
                    root.simulator.consumeAudioEvaluationObservations().map {
                        SceneParticleRuntimeAudioEvaluationObservation(
                            layerID: layerID,
                            particlePath: layers[index].particlePath,
                            evaluation: $0
                        )
                    }
                )
                births = root.simulator.consumeBirthEvents()
                deaths = root.simulator.consumeDeathEvents()
                parentParticles = root.simulator.particles
                layers[index].rootRender = root
            }
            if let childRuntime = layers[index].childRuntime {
                let result = childRuntime.advance(
                    by: layerDelta,
                    spawnEvents: births,
                    deathEvents: deaths,
                    parentParticles: parentParticles,
                    layerAlpha: layerAlpha,
                    dynamicInstanceValues: dynamicOverride,
                    pointerLocalPosition: pointerLocalPositions[layerID],
                    dynamicControlPoints: dynamicControlPoints,
                    dynamicControlPointAngles: controlPointAngles,
                    audioInput: audioInput,
                    worldSpaceFrameOverride: worldSpaceFrameOverride
                )
                pendingAudioEvaluationObservations.append(contentsOf:
                    childRuntime.consumeAudioEvaluationObservations().map {
                        SceneParticleRuntimeAudioEvaluationObservation(
                            layerID: layerID,
                            particlePath: $0.particlePath,
                            evaluation: $0.evaluation
                        )
                    }
                )
                batches.append(contentsOf: result.batches)
                for path in result.bufferFailurePaths {
                    addDiagnostic(
                        kind: .instanceBufferAllocationFailed,
                        layerID: layers[index].layerID,
                        path: path
                    )
                }
                for detail in result.limitationDetails {
                    addDiagnostic(
                        kind: .simulationLimitation,
                        layerID: layers[index].layerID,
                        path: layers[index].particlePath,
                        detail: detail
                    )
                }
            }
            guard var root = layers[index].rootRender else { continue }
            rebuildGPUInstances(root: &root, layerAlpha: layerAlpha)
            batches.append(SceneParticleDrawBatch(
                layerID: layerID,
                particlePath: layers[index].particlePath,
                texture: root.texture,
                colorUVScale: root.colorUVScale,
                colorSampling: root.colorSampling,
                refraction: root.refraction,
                renderState: root.renderState,
                instanceBuffer: root.instanceBuffer,
                instances: root.instances,
                orientation: root.orientation,
                orientationAxis: root.orientationAxis,
                usesPerspective: root.usesPerspective,
                sizeIsWorldSpace: root.definition.flags.isWorldSpace
            ))
            layers[index].rootRender = root
        }
        return batches
    }

    func frameSnapshot() -> FrameSnapshot {
        FrameSnapshot(layers: layers.map { layer in
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
                child: layer.childRuntime?.frameSnapshot()
            )
        }, pendingAudioEvaluationObservations: pendingAudioEvaluationObservations,
           frozenWorldSpaceLayerIDs: frozenWorldSpaceLayerIDs,
           adoptedWorldSpaceLayerIDs: liveWorldSpaceAdoptedLayerIDs)
    }

    func restoreFrame(_ snapshot: FrameSnapshot) {
        guard snapshot.layers.count == layers.count else { return }
        for index in layers.indices {
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
        pendingAudioEvaluationObservations = snapshot.pendingAudioEvaluationObservations
        frozenWorldSpaceLayerIDs = snapshot.frozenWorldSpaceLayerIDs
        liveWorldSpaceAdoptedLayerIDs = snapshot.adoptedWorldSpaceLayerIDs
    }

    func consumeAudioEvaluationObservations()
        -> [SceneParticleRuntimeAudioEvaluationObservation] {
        defer { pendingAudioEvaluationObservations.removeAll(keepingCapacity: true) }
        return pendingAudioEvaluationObservations
    }

    /// Ends this launch-scoped runtime atomically. Root and child systems are
    /// never transplanted into a replacement Scene/surface generation.
    func teardown() {
        for index in layers.indices {
            layers[index].childRuntime?.teardown()
            layers[index].rootRender = nil
        }
        layers.removeAll(keepingCapacity: false)
    }

    private func rebuildGPUInstances(
        root: inout SceneParticleRootRenderRuntime,
        layerAlpha: Float
    ) {
        let stepSnapshots = root.simulator.consumeStepSnapshots()
        if let rope = root.rope {
            root.instances = rope.instances(
                particles: root.simulator.particles,
                layerAlpha: layerAlpha,
                simulationTime: root.simulator.simulationTime
            )
            return
        }
        if var history = root.ropeTrailHistory {
            root.instances = history.advance(
                snapshots: stepSnapshots, currentParticles: root.simulator.particles,
                layerAlpha: layerAlpha
            )
            root.ropeTrailHistory = history
            return
        }
        let particles = root.simulator.renderParticlesForCurrentAdvance()
        // Sprite Trail orientation follows the particle's recent path chord
        // instead of its instantaneous velocity. Samples are id-ascending and
        // the render set is id-sorted, so one forward walk aligns them without
        // per-particle lookups; particles without a sample (fresh births,
        // degenerate chords, history-less child systems) keep the velocity
        // direction. The stretch magnitude below stays velocity-based.
        let trailDirections = root.trail != nil
            ? root.simulator.trailDirectionSamples() : nil
        var trailDirectionIndex = 0
        root.instances.removeAll(keepingCapacity: true)
        root.instances.reserveCapacity(particles.count)
        for particle in particles {
            if let directions = trailDirections {
                while trailDirectionIndex < directions.count,
                      directions[trailDirectionIndex].id < particle.id {
                    trailDirectionIndex += 1
                }
            }
            let trailVelocity: SIMD3<Double>
            if let directions = trailDirections,
               trailDirectionIndex < directions.count,
               directions[trailDirectionIndex].id == particle.id {
                trailVelocity = directions[trailDirectionIndex].direction
            } else {
                trailVelocity = particle.velocity
            }
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
                alpha: Float(particle.alpha) * layerAlpha,
                velocity: trailVelocity.particleFloatValue,
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

    /// Official particle containers parse `renderer` and `children` as
    /// independent collections. We admit only the bounded form whose root has
    /// no renderer and whose complete root-child set is static and executable;
    /// event children still require a root simulator and therefore fail closed.
    private func admitsChildOnlyContainer(
        _ definition: SceneParticleDefinition,
        childRuntime: SceneParticleChildRuntime,
        layerID: Int,
        path: String
    ) -> Bool {
        let rendererMalformed = definition.diagnostics.contains {
            $0.path == "renderer" || $0.path.hasPrefix("renderer[")
        }
        let staticChildren = !definition.children.isEmpty
            && definition.children.allSatisfy {
                guard let type = $0.type?.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).localizedLowercase else { return true }
                return type.isEmpty || type == "static"
            }
        let accepted = !rendererMalformed
            && staticChildren
            && childRuntime.hasTemplates
            && childRuntime.handlesAllChildren
            && childRuntime.unsupportedDetails.isEmpty
        guard accepted else {
            addDiagnostic(
                kind: .missingSpriteRenderer,
                layerID: layerID,
                path: path,
                detail: definition.children.isEmpty
                    ? nil : "rootRendererAbsentOutsideStrictStaticChildContainer"
            )
            return false
        }
        return true
    }

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
        if let declaration = asset.refraction {
            guard let loaded = SceneParticleRefractionTextureLoader.load(
                colorSource: textureSource,
                declaration: declaration,
                textureLoader: textureLoader,
                device: device
            ) else {
                addDiagnostic(
                    kind: .refractionUnsupported,
                    layerID: layer.id,
                    path: path,
                    detail: "textureProfileUnsupported"
                )
                return nil
            }
            texture = loaded.color
            spriteAnimation = loaded.colorAnimation
            staticSpriteAspect = loaded.staticSpriteAspect
            colorUVScale = loaded.colorUVScale
            colorSampling = loaded.colorSampling
            refraction = loaded.binding
        } else {
            guard let loaded = SceneParticleChildTemplateSupport.loadTexture(
                textureSource,
                textureLoader: textureLoader,
                builtInTextureRegistry: builtInTextureRegistry,
                device: device
            ) else {
                addDiagnostic(
                    kind: .textureLoadFailed, layerID: layer.id, path: path,
                    detail: "particleColorTexturePreparationFailed"
                )
                return nil
            }
            texture = loaded.texture
            spriteAnimation = loaded.animation
            staticSpriteAspect = loaded.staticAspect
            colorSampling = loaded.sampling
            colorUVScale = loaded.uvScale
            refraction = nil
        }
        guard supportsPathRendererTexture(
            rope: render.rope,
            ropeTrail: render.ropeTrail,
            animation: spriteAnimation,
            layerID: layer.id,
            path: path
        ) else { return nil }

        let initialInstanceOverride = layer.particleInstanceOverride?.resolving(
            initialDynamicValues.particleInstanceValues(layerID: layer.id)
        )
        let simulator = SceneParticleSimulator(
            definition: asset.definition,
            instanceOverride: layer.particleInstanceOverride,
            initialDynamicInstanceOverride: initialInstanceOverride,
            initialPlayback: initialPlayback,
            seed: UInt64(bitPattern: Int64(layer.id)),
            prewarmStepBudget: 3_600,
            layerImageEmissionMap: layerImageMap,
            worldSpaceFrame: worldSpaceFrame,
            stepSnapshotPolicy: render.ropeTrail?.stepSnapshotPolicy,
            trailHistoryCapacity: render.trail != nil
                ? SceneParticleTrailRenderPlan.historySampleCapacity
                : 0
        )
        return SceneParticleRootRenderRuntime(
            definition: asset.definition,
            pointerControlPointIdentities: asset.definition.pointerControlPointIdentities,
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
    }
}
