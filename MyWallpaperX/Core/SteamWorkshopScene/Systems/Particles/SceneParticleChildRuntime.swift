import Foundation
import Metal

/// Executes strict children up to depth two. Unsupported declarations stay diagnostic.
final class SceneParticleChildRuntime {
    struct FrameSnapshot {
        struct SystemSnapshot {
            let id: UInt64
            let templateIndex: Int
            let depth: Int
            let spawnScopeID: UInt64?
            let parentParticleID: UInt64?
            let isWorldSpace: Bool
            let origin: SIMD3<Double>
            let particleOrigins: [UInt64: SIMD3<Double>]
            let simulator: SceneParticleSimulator
            let simulatorFrame: SceneParticleSimulator.FrameSnapshot
        }

        let systems: [SystemSnapshot]
        let nextSeed: UInt64
        let nextSystemID: UInt64
#if DEBUG
        var observedAudioComponentsByTemplate:
            [Int: Set<SceneParticleAudioComponentIdentity>] = [:]
        var pendingAudioEvaluationObservations:
            [SceneParticleChildAudioEvaluationObservation] = []
        var pendingComponentObservations: [SceneParticleRuntimeComponentObservation]? = nil
#endif
    }

    private struct TemplateSelectionKey: Hashable {
        let trigger: SceneParticleChildTrigger
        let depth: Int
        let parentAssetPath: String?
    }

    // Reserve each admitted system's authored capacity in full. Each depth keeps
    // the previous total envelope without truncating every burst to 1024 particles.
    // The systems themselves own reservations, including frame rollback and retirement.
    private static let maximumParticlesPerDepth = 65_536
    private static let maximumSystemsPerDepth = 64

    let unsupportedDetails: [String]
#if DEBUG
    let performanceDetails: [String]
#endif
    let handlesAllChildren: Bool
    /// Launch-stable demand used by the host to avoid projecting the pointer
    /// for particle layers whose prepared child graph cannot consume it.
    let hasPointerControlPointConsumer: Bool
    let needsWorldControlPointFrame: Bool
    /// Includes dormant/event templates before their first particle exists.
    let requiredPipelineVariants: Set<SceneParticlePipelineVariant>
#if DEBUG
    /// One-line launch summary for the DEBUG evidence path: how many child
    /// systems the expansion produced versus how many declarations it saw.
    var expansionSummary: String {
        "templates=\(templates.count) unsupported=\(unsupportedDetails.count) "
            + "systems=\(systems.count) handlesAllChildren=\(handlesAllChildren)"
    }
#endif

    var hasTemplates: Bool {
        !templates.isEmpty
    }

    /// Child templates use the same simulator audio plans as root systems. Keep
    /// the demand bit on the graph owner so an audio-enabled child can start
    /// the shared producer even when its root container has no audio fields.
    var hasAudioConsumer: Bool {
        templates.contains { $0.definition.hasBoundedAudioConsumer }
    }

    /// Whether any admitted child template's simulation converts through the
    /// layer world-space frame. The runtime's freeze/re-adopt transaction
    /// applies only to layers whose root or children need that frame; a fully
    /// local-space layer keeps simulating under a scripted ancestor chain.
    var hasWorldSpaceFrameConsumer: Bool {
        templates.contains {
            $0.definition.flags.isWorldSpace
                || $0.definition.operators.contains(where: \.isWorldSpaceMovement)
        }
    }

    var lifecycleSystemCount: Int { systems.count }
    var lifecycleParticleCount: Int {
        systems.reduce(0) { $0 + $1.simulator.particles.count }
    }

    private let layerID: Int
#if DEBUG
    private var didLogInstanceCensus = false
    private var censusTimeAccumulator: TimeInterval = 0
    private var frameLimitations: Set<String> = []
#endif
    private let templates: [SceneParticleChildTemplate]
    private let templatesByIndex: [Int: SceneParticleChildTemplate]
    private let templatesBySelection: [TemplateSelectionKey: [SceneParticleChildTemplate]]
    private let nestedParentPaths: Set<String>
    private var systems: [SceneParticleChildSystem] = []
    private var instanceScratch: [Int: [SceneParticleGPUInstance]] = [:]
    private var nextSeed: UInt64 = 0
    private var nextSystemID: UInt64 = 1
#if DEBUG
    private var observedAudioComponentsByTemplate:
        [Int: Set<SceneParticleAudioComponentIdentity>] = [:]
    private var pendingAudioEvaluationObservations:
        [SceneParticleChildAudioEvaluationObservation] = []
    private var pendingComponentObservations: [SceneParticleRuntimeComponentObservation]? =
        SceneParticleDefinitionParser.componentObservationEnabled ? [] : nil
#endif

    init(
        layerID: Int,
        rootAsset: SceneParticleAsset,
        graph: SceneParticleAssetGraph,
        textureLoader: SceneTextureLoader,
        builtInTextureRegistry: SceneParticleBuiltInTextureRegistry,
        device: MTLDevice,
        worldSpaceFrame: SceneParticleWorldSpaceFrame?,
        rootInstanceOverride: SceneParticleInstanceOverride?,
        initialDynamicInstanceValues: SceneDynamicParticleValues? = nil,
        controlPointFrame: SceneParticleControlPointFrame? = nil,
        initialDynamicControlPoints: [Int: SIMD3<Double>] = [:],
        initialDynamicControlPointAngles: [Int: SIMD3<Double>] = [:]
    ) {
        self.layerID = layerID
        let expansion = SceneParticleChildGraphExpansion.expand(
            rootAsset: rootAsset,
            graph: graph,
            textureLoader: textureLoader,
            builtInTextureRegistry: builtInTextureRegistry,
            device: device,
            worldSpaceFrame: worldSpaceFrame,
            rootInstanceOverride: rootInstanceOverride
        )
        templates = expansion.templates
        requiredPipelineVariants = Set(expansion.templates.map {
            .init(isRefraction: $0.refraction != nil, blendMode: $0.renderState.blendMode,
                  usesDepthAttachment: $0.renderState.depthWriteEnabled)
        })
        templatesByIndex = Dictionary(
            expansion.templates.map { ($0.index, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        templatesBySelection = Dictionary(
            grouping: expansion.templates,
            by: {
                TemplateSelectionKey(
                    trigger: $0.trigger,
                    depth: $0.depth,
                    parentAssetPath: $0.parentAssetPath
                )
            }
        )
        // Allocate the reusable per-template output map once. The map itself
        // is topology, while each value is only cleared/refilled per frame.
        for template in expansion.templates {
            instanceScratch[template.index] = []
#if DEBUG
            if let parentPath = template.debugParentParticlePath,
               let componentIndex = template.debugParentComponentIndex {
                pendingComponentObservations?.append(.init(layerID: layerID,
                    particlePath: parentPath,
                    evaluation: .init(category: "children", componentIndex: componentIndex,
                        kind: "child-template", stage: "prepared-executable", reason: "accepted-child-template",
                        origin: "prepared", simulationTime: 0, particleID: nil),
                    childTemplateIndex: template.index, childParticlePath: template.path))
            }
#endif
        }
        unsupportedDetails = expansion.unsupportedDetails
        handlesAllChildren = expansion.handledRootChildren == rootAsset.definition.children.count
        hasPointerControlPointConsumer = expansion.templates.contains {
            !$0.pointerControlPointIdentities.isEmpty
        }
        needsWorldControlPointFrame = expansion.templates.contains(where: \.needsWorldControlPointFrame)
        nestedParentPaths = Set(templates.compactMap(\.parentAssetPath))
#if DEBUG
        var performance = expansion.performanceDetails
#endif
        let staticTemplates = templates.filter { $0.trigger == .staticChild }
        var staticCapacity = Self.maximumParticlesPerDepth
        var staticRopeExpansionCapacity =
            SceneParticleChildTemplateSupport.maximumStaticRopeExpansionSegments
        for (offset, template) in staticTemplates.enumerated() {
            guard systems.count < Self.maximumSystemsPerDepth,
                  template.particleBudget <= staticCapacity else {
#if DEBUG
                let detail = Self.budgetDetail(depth: template.depth)
                if !performance.contains(detail) { performance.append(detail) }
#endif
                continue
            }
            let ropeExpansion = template.rope.map {
                max($0.maximumGeneratedSegments
                    - SceneParticleChildTemplateSupport.maximumRopeSegmentsPerTemplate, 0)
            } ?? 0
            guard ropeExpansion <= staticRopeExpansionCapacity else {
#if DEBUG
                let detail = "staticRopeExpansionBudget:segments="
                    + "\(SceneParticleChildTemplateSupport.maximumStaticRopeExpansionSegments)"
                if !performance.contains(detail) { performance.append(detail) }
#endif
                continue
            }
            staticCapacity -= template.particleBudget
            staticRopeExpansionCapacity -= ropeExpansion
            let simulator = template.simulator(
                seed: UInt64(bitPattern: Int64(layerID))
                    ^ UInt64(template.index &+ 1) &* 0xBF58_476D_1CE4_E5B9
                    ^ UInt64(offset),
                dynamicInstanceValues: initialDynamicInstanceValues,
                origin: template.transform.origin,
                controlPointFrame: controlPointFrame,
                initialDynamicControlPoints: Self.controlPointValues(
                    for: template, origin: template.transform.origin,
                    pointerLocalPosition: nil, dynamicControlPoints: initialDynamicControlPoints
                ),
                initialDynamicControlPointAngles: initialDynamicControlPointAngles
            )
            systems.append(SceneParticleChildSystem(
                id: nextSystemID,
                templateIndex: template.index,
                depth: template.depth,
                spawnScopeID: nil,
                parentParticleID: nil,
                isWorldSpace: template.definition.flags.isWorldSpace,
                origin: template.transform.origin,
                particleOrigins: template.definition.flags.isWorldSpace
                    ? Dictionary(uniqueKeysWithValues: simulator.particles.map { ($0.id, template.transform.origin) }) : [:],
                simulator: simulator
            ))
            nextSystemID &+= 1
        }
#if DEBUG
        performanceDetails = performance
#endif
    }

    func advance(
        by frameDelta: TimeInterval,
        spawnEvents: [SceneParticleState],
        deathEvents: [SceneParticleState],
        parentParticles: [SceneParticleState],
        layerAlpha: Float,
        dynamicInstanceValues: SceneDynamicParticleValues? = nil,
        pointerLocalPosition: SIMD3<Double>? = nil,
        dynamicControlPoints: [Int: SIMD3<Double>] = [:],
        dynamicControlPointAngles: [Int: SIMD3<Double>] = [:],
        audioInput: SceneParticleAudioInput = .silent,
        worldSpaceFrameOverride: SceneParticleWorldSpaceFrame? = nil,
        controlPointFrame: SceneParticleControlPointFrame? = nil,
        isVisible: Bool = true
    ) -> SceneParticleChildAdvanceResult {
#if DEBUG
        frameLimitations.removeAll(keepingCapacity: true)
#endif
        var retiredRenderSystems: [SceneParticleChildSystem] = []
        let parentFrames = advanceDepthOne(
            by: frameDelta,
            rootParticles: parentParticles,
            dynamicInstanceValues: dynamicInstanceValues,
            pointerLocalPosition: pointerLocalPosition,
            dynamicControlPoints: dynamicControlPoints,
            dynamicControlPointAngles: dynamicControlPointAngles,
            audioInput: audioInput,
            worldSpaceFrameOverride: worldSpaceFrameOverride,
            controlPointFrame: controlPointFrame,
            allowsEmission: isVisible
        )
        retireCompletedSystems(depth: 1, into: &retiredRenderSystems)
        spawn(
            from: spawnEvents, trigger: .spawn, depth: 1, parentPath: nil,
            scopeID: nil, parentOrigin: .zero, dynamicInstanceValues: dynamicInstanceValues,
            pointerLocalPosition: pointerLocalPosition, dynamicControlPoints: dynamicControlPoints,
            dynamicControlPointAngles: dynamicControlPointAngles, controlPointFrame: controlPointFrame
        )
        spawn(
            from: deathEvents, trigger: .death, depth: 1, parentPath: nil,
            scopeID: nil, parentOrigin: .zero, dynamicInstanceValues: dynamicInstanceValues,
            pointerLocalPosition: pointerLocalPosition, dynamicControlPoints: dynamicControlPoints,
            dynamicControlPointAngles: dynamicControlPointAngles, controlPointFrame: controlPointFrame
        )
        reconcileFollowers(
            parentParticles, depth: 1, parentPath: nil,
            scopeID: nil, parentOrigin: .zero, dynamicInstanceValues: dynamicInstanceValues,
            pointerLocalPosition: pointerLocalPosition, dynamicControlPoints: dynamicControlPoints,
            dynamicControlPointAngles: dynamicControlPointAngles, controlPointFrame: controlPointFrame
        )
        advanceDepthTwo(
            by: frameDelta,
            parentFrames: parentFrames,
            dynamicInstanceValues: dynamicInstanceValues,
            pointerLocalPosition: pointerLocalPosition,
            dynamicControlPoints: dynamicControlPoints,
            dynamicControlPointAngles: dynamicControlPointAngles,
            audioInput: audioInput,
            worldSpaceFrameOverride: worldSpaceFrameOverride,
            controlPointFrame: controlPointFrame,
            retiredRenderSystems: &retiredRenderSystems,
            allowsEmission: isVisible
        )

        guard isVisible else {
            for key in instanceScratch.keys { instanceScratch[key]?.removeAll(keepingCapacity: true) }
#if DEBUG
            return SceneParticleChildAdvanceResult(
                batches: [], limitationDetails: frameLimitations.sorted()
            )
#else
            return SceneParticleChildAdvanceResult(batches: [])
#endif
        }

        // Retirement is collected by depth, while system IDs preserve authored
        // creation order across depths. Sort only on the exceptional retirement
        // path so instance assembly can merge live and render-only systems in the
        // same order as the former all-live array.
        if retiredRenderSystems.count > 1 {
            retiredRenderSystems.sort { $0.id < $1.id }
        }

        SceneParticleChildInstanceBuilder.rebuildAll(
            templates: templates,
            templatesByIndex: templatesByIndex,
            systems: systems,
            renderOnlySystems: retiredRenderSystems,
            layerAlpha: layerAlpha,
            into: &instanceScratch
        )
        var batches: [SceneParticleDrawBatch] = []
        batches.reserveCapacity(templates.count)
        for template in templates {
            guard let instances = instanceScratch[template.index], !instances.isEmpty else {
                continue
            }
            batches.append(SceneParticleDrawBatch(
                layerID: layerID,
                particlePath: template.path,
                texture: template.texture,
                colorUVScale: template.colorUVScale,
                colorSampling: template.colorSampling,
                refraction: template.refraction,
                renderState: template.renderState,
                childTemplateIndex: template.index,
                instances: instances,
                orientation: template.orientation,
                orientationAxis: template.orientationAxis,
                usesPerspective: template.usesPerspective,
                sizeIsWorldSpace: template.definition.flags.isWorldSpace
            ))
#if DEBUG
            batches[batches.count - 1].debugRendererComponentIndex = template.debugRendererComponentIndex
            batches[batches.count - 1].debugRendererKind = template.debugRendererKind
#endif
        }
#if DEBUG
        // Throttled spawn/instance census (~1s of sim time) distinguishes
        // bursty lifecycle windows from batch-creation gaps at snapshot time.
        censusTimeAccumulator += frameDelta
        let censusDue = !didLogInstanceCensus || censusTimeAccumulator >= 1
        if censusDue {
            didLogInstanceCensus = true
            censusTimeAccumulator = 0
            let spawned = templates.compactMap { instanceScratch[$0.index]?.count }
            let systemParticleCounts = systems.map { $0.simulator.particles.count }
            let systemParticleTotal = systemParticleCounts.reduce(0, +)
            NSLog(
                "MWX DEBUG SCENE: phase=particle-child-census layer=%d templates=%d systems=%d systemParticles=%d spawnedTotal=%d emptyTemplates=%d nonEmptySystems=%d batches=%d",
                layerID, templates.count, systems.count,
                systemParticleTotal, spawned.reduce(0, +), spawned.count,
                systemParticleCounts.filter { $0 > 0 }.count,
                batches.count
            )
        }
        return SceneParticleChildAdvanceResult(
            batches: batches,
            limitationDetails: frameLimitations.sorted()
        )
#else
        return SceneParticleChildAdvanceResult(batches: batches)
#endif
    }

    func frameSnapshot() -> FrameSnapshot {
        var snapshot = FrameSnapshot(
            systems: systems.map {
                .init(
                    id: $0.id,
                    templateIndex: $0.templateIndex,
                    depth: $0.depth,
                    spawnScopeID: $0.spawnScopeID,
                    parentParticleID: $0.parentParticleID,
                    isWorldSpace: $0.isWorldSpace,
                    origin: $0.origin,
                    particleOrigins: $0.particleOrigins,
                    simulator: $0.simulator,
                    simulatorFrame: $0.simulator.frameSnapshot()
                )
            },
            nextSeed: nextSeed,
            nextSystemID: nextSystemID
        )
#if DEBUG
        snapshot.observedAudioComponentsByTemplate = observedAudioComponentsByTemplate
        snapshot.pendingAudioEvaluationObservations = pendingAudioEvaluationObservations
        snapshot.pendingComponentObservations = pendingComponentObservations
#endif
        return snapshot
    }

    func restoreFrame(_ snapshot: FrameSnapshot) {
        systems = snapshot.systems.map {
            $0.simulator.restoreFrame($0.simulatorFrame)
            return SceneParticleChildSystem(
                id: $0.id,
                templateIndex: $0.templateIndex,
                depth: $0.depth,
                spawnScopeID: $0.spawnScopeID,
                parentParticleID: $0.parentParticleID,
                isWorldSpace: $0.isWorldSpace,
                origin: $0.origin,
                particleOrigins: $0.particleOrigins,
                simulator: $0.simulator
            )
        }
        nextSeed = snapshot.nextSeed
        nextSystemID = snapshot.nextSystemID
#if DEBUG
        observedAudioComponentsByTemplate = snapshot.observedAudioComponentsByTemplate
        pendingAudioEvaluationObservations = snapshot.pendingAudioEvaluationObservations
        pendingComponentObservations = snapshot.pendingComponentObservations
#endif
        instanceScratch.removeAll(keepingCapacity: true)
    }

#if DEBUG
    func appendComponentObservations(to destination: inout [SceneParticleRuntimeComponentObservation]?) {
        guard let pendingComponentObservations else { return }
        destination?.append(contentsOf: pendingComponentObservations)
        self.pendingComponentObservations?.removeAll(keepingCapacity: true)
    }

    func consumeAudioEvaluationObservations()
        -> [SceneParticleChildAudioEvaluationObservation] {
        defer { pendingAudioEvaluationObservations.removeAll(keepingCapacity: true) }
        return pendingAudioEvaluationObservations
    }
#endif

    func teardown() {
        systems.removeAll(keepingCapacity: false)
        instanceScratch.removeAll(keepingCapacity: false)
#if DEBUG
        frameLimitations.removeAll(keepingCapacity: false)
        observedAudioComponentsByTemplate.removeAll(keepingCapacity: false)
        pendingAudioEvaluationObservations.removeAll(keepingCapacity: false)
        pendingComponentObservations?.removeAll(keepingCapacity: false)
#endif
    }

    /// Advances depth-one systems against the root simulator and collects the per-system
    /// event frames that feed nested children, before completed systems are recycled.
    private func advanceDepthOne(
        by frameDelta: TimeInterval,
        rootParticles: [SceneParticleState],
        dynamicInstanceValues: SceneDynamicParticleValues?,
        pointerLocalPosition: SIMD3<Double>?,
        dynamicControlPoints: [Int: SIMD3<Double>],
        dynamicControlPointAngles: [Int: SIMD3<Double>],
        audioInput: SceneParticleAudioInput,
        worldSpaceFrameOverride: SceneParticleWorldSpaceFrame? = nil,
        controlPointFrame: SceneParticleControlPointFrame?,
        allowsEmission: Bool
    ) -> [SceneParticleChildParentFrame] {
        let parentsByID: [UInt64: SceneParticleState] = templates.contains {
            $0.depth == 1 && $0.trigger == .follow
        } ? Dictionary(uniqueKeysWithValues: rootParticles.map { ($0.id, $0) }) : [:]
        systems.removeAll { system in
            guard system.depth == 1, let parentID = system.parentParticleID else { return false }
            return parentsByID[parentID] == nil
        }
        var frames: [SceneParticleChildParentFrame] = []
        for index in systems.indices where systems[index].depth == 1 {
#if DEBUG
            suppressObservedAudioComponents(systemAt: index)
#endif
            if let parentID = systems[index].parentParticleID,
               let parent = parentsByID[parentID]
            {
                systems[index].origin = parent.position
                systems[index].simulator.updateFollowEventColor(parent.color)
            }
            guard let template = templatesByIndex[systems[index].templateIndex] else { continue }
            systems[index].simulator.advance(
                by: frameDelta,
                dynamicControlPoints: Self.controlPointValues(
                    for: template, origin: systems[index].origin,
                    pointerLocalPosition: pointerLocalPosition,
                    dynamicControlPoints: dynamicControlPoints
                ),
                dynamicControlPointAngles: dynamicControlPointAngles,
                dynamicInstanceOverride: systems[index].simulator.instanceOverride?.resolving(
                    dynamicInstanceValues
                ),
                audioInput: audioInput,
                worldSpaceFrameOverride: worldSpaceFrameOverride,
                controlPointFrame: systems[index].simulator.needsWorldControlPointFrame
                    ? controlPointFrame?.childFrame(origin: systems[index].origin, scale: template.transform.scale) : nil,
                controlPointParticleSpace: systems[index].isWorldSpace
                    && !systems[index].simulator.controlPointDistanceHistory.isEmpty
                    ? .init(currentOrigin: systems[index].origin, scale: template.transform.scale,
                            birthOrigins: systems[index].particleOrigins) : nil,
                allowsEmission: allowsEmission
            )
#if DEBUG
            collectAudioEvaluationObservations(systemAt: index)
#endif
            let births = systems[index].simulator.consumeBirthEvents()
            let deaths = systems[index].simulator.consumeDeathEvents()
            updateWorldSpaceOrigins(systemAt: index, births: births, deaths: deaths)
            guard let path = templatesByIndex[systems[index].templateIndex]?.path,
                  nestedParentPaths.contains(path) else { continue }
            frames.append(SceneParticleChildParentFrame(
                systemID: systems[index].id,
                path: path,
                origin: systems[index].origin,
                births: births,
                deaths: deaths,
                particles: systems[index].simulator.particles
            ))
        }
        return frames
    }

    private func advanceDepthTwo(
        by frameDelta: TimeInterval,
        parentFrames: [SceneParticleChildParentFrame],
        dynamicInstanceValues: SceneDynamicParticleValues?,
        pointerLocalPosition: SIMD3<Double>?,
        dynamicControlPoints: [Int: SIMD3<Double>],
        dynamicControlPointAngles: [Int: SIMD3<Double>],
        audioInput: SceneParticleAudioInput,
        worldSpaceFrameOverride: SceneParticleWorldSpaceFrame? = nil,
        controlPointFrame: SceneParticleControlPointFrame?,
        retiredRenderSystems: inout [SceneParticleChildSystem],
        allowsEmission: Bool
    ) {
        guard !nestedParentPaths.isEmpty else { return }
        var liveParents: [UInt64: (origin: SIMD3<Double>, particles: [UInt64: SceneParticleState])]
            = [:]
        if templates.contains(where: { $0.depth == 2 && $0.trigger == .follow }) {
            for frame in parentFrames {
                liveParents[frame.systemID] = (
                    frame.origin,
                    Dictionary(uniqueKeysWithValues: frame.particles.map { ($0.id, $0) })
                )
            }
        }
        systems.removeAll { system in
            guard system.depth == 2, let parentID = system.parentParticleID else { return false }
            guard let scope = system.spawnScopeID,
                  let parent = liveParents[scope] else { return true }
            return parent.particles[parentID] == nil
        }
        for index in systems.indices where systems[index].depth == 2 {
#if DEBUG
            suppressObservedAudioComponents(systemAt: index)
#endif
            if let scope = systems[index].spawnScopeID,
               let parentID = systems[index].parentParticleID,
               let parent = liveParents[scope],
               let particle = parent.particles[parentID]
            {
                systems[index].origin = parent.origin + particle.position
                systems[index].simulator.updateFollowEventColor(particle.color)
            }
            guard let template = templatesByIndex[systems[index].templateIndex] else { continue }
            systems[index].simulator.advance(
                by: frameDelta,
                dynamicControlPoints: Self.controlPointValues(
                    for: template, origin: systems[index].origin,
                    pointerLocalPosition: pointerLocalPosition,
                    dynamicControlPoints: dynamicControlPoints
                ),
                dynamicControlPointAngles: dynamicControlPointAngles,
                dynamicInstanceOverride: systems[index].simulator.instanceOverride?.resolving(
                    dynamicInstanceValues
                ),
                audioInput: audioInput,
                worldSpaceFrameOverride: worldSpaceFrameOverride,
                controlPointFrame: systems[index].simulator.needsWorldControlPointFrame
                    ? controlPointFrame?.childFrame(origin: systems[index].origin, scale: template.transform.scale) : nil,
                controlPointParticleSpace: systems[index].isWorldSpace
                    && !systems[index].simulator.controlPointDistanceHistory.isEmpty
                    ? .init(currentOrigin: systems[index].origin, scale: template.transform.scale,
                            birthOrigins: systems[index].particleOrigins) : nil,
                allowsEmission: allowsEmission
            )
#if DEBUG
            collectAudioEvaluationObservations(systemAt: index)
#endif
            let births = systems[index].simulator.consumeBirthEvents()
            let deaths = systems[index].simulator.consumeDeathEvents()
            updateWorldSpaceOrigins(systemAt: index, births: births, deaths: deaths)
        }
        // A completed depth-two owner must leave admission budgets before this
        // callback's parent events are reconciled. Its final render sample stays
        // in the local render-only list until instance assembly.
        retireCompletedSystems(depth: 2, into: &retiredRenderSystems)
        for frame in parentFrames {
            spawn(
                from: frame.births, trigger: .spawn, depth: 2, parentPath: frame.path,
                scopeID: frame.systemID, parentOrigin: frame.origin,
                dynamicInstanceValues: dynamicInstanceValues,
                pointerLocalPosition: pointerLocalPosition, dynamicControlPoints: dynamicControlPoints,
                dynamicControlPointAngles: dynamicControlPointAngles, controlPointFrame: controlPointFrame
            )
            spawn(
                from: frame.deaths, trigger: .death, depth: 2, parentPath: frame.path,
                scopeID: frame.systemID, parentOrigin: frame.origin,
                dynamicInstanceValues: dynamicInstanceValues,
                pointerLocalPosition: pointerLocalPosition, dynamicControlPoints: dynamicControlPoints,
                dynamicControlPointAngles: dynamicControlPointAngles, controlPointFrame: controlPointFrame
            )
            reconcileFollowers(
                frame.particles, depth: 2, parentPath: frame.path,
                scopeID: frame.systemID, parentOrigin: frame.origin,
                dynamicInstanceValues: dynamicInstanceValues,
                pointerLocalPosition: pointerLocalPosition, dynamicControlPoints: dynamicControlPoints,
                dynamicControlPointAngles: dynamicControlPointAngles, controlPointFrame: controlPointFrame
            )
        }
    }

    private func retireCompletedSystems(
        depth: Int,
        into retiredRenderSystems: inout [SceneParticleChildSystem]
    ) {
        systems.removeAll { system in
            guard isCompleted(system, atDepth: depth) else { return false }
            retiredRenderSystems.append(system)
            return true
        }
    }

#if DEBUG
    private func collectAudioEvaluationObservations(systemAt index: Int) {
        guard let template = templatesByIndex[systems[index].templateIndex] else {
            return
        }
        if pendingComponentObservations != nil {
            pendingComponentObservations?.append(contentsOf:
                systems[index].simulator.consumeComponentObservations().map {
                    .init(layerID: layerID, particlePath: template.path, evaluation: $0,
                          childTemplateIndex: template.index, childSystemID: systems[index].id)
                })
        }
        let observations = systems[index].simulator.consumeAudioEvaluationObservations()
        guard !observations.isEmpty else { return }
        for observation in observations {
            observedAudioComponentsByTemplate[template.index, default: []].insert(.init(
                kind: observation.componentKind,
                index: observation.componentIndex
            ))
            pendingAudioEvaluationObservations.append(.init(
                particlePath: template.path,
                evaluation: observation
            ))
        }
    }

    private func suppressObservedAudioComponents(systemAt index: Int) {
        let templateIndex = systems[index].templateIndex
        guard let observed = observedAudioComponentsByTemplate[templateIndex] else {
            return
        }
        systems[index].simulator.suppressAudioEvaluationObservations(for: observed)
    }
#endif

    private func isCompleted(_ system: SceneParticleChildSystem, atDepth depth: Int) -> Bool {
        system.depth == depth
            && system.parentParticleID == nil
            && system.simulator.simulationTime > 0
            && system.simulator.hasFinishedEmission
            && system.simulator.particles.isEmpty
    }

    /// World values stay in their source space for the point frame. Root-local
    /// values and the pointer use the same origin/scale as instance assembly.
    private static func controlPointValues(
        for template: SceneParticleChildTemplate,
        origin: SIMD3<Double>,
        pointerLocalPosition: SIMD3<Double>?,
        dynamicControlPoints: [Int: SIMD3<Double>]
    ) -> [Int: SIMD3<Double>] {
        var values: [Int: SIMD3<Double>] = [:]
        if !dynamicControlPoints.isEmpty {
            values.reserveCapacity(dynamicControlPoints.count)
            for (identity, value) in dynamicControlPoints {
                let isWorld = template.definition.controlPoints.contains {
                    $0.id == identity && $0.isWorldSpace
                }
                let childLocal = isWorld ? value : template.transform.inversePosition(value - origin)
                guard childLocal.x.isFinite, childLocal.y.isFinite, childLocal.z.isFinite else {
                    continue
                }
                values[identity] = childLocal
            }
        }
        if !template.pointerControlPointIdentities.isEmpty {
            let childLocalPosition = pointerLocalPosition.map {
                template.transform.inversePosition($0 - origin)
            }
            let pointerValues = template.definition.pointerControlPointValues(
                at: childLocalPosition,
                identities: template.pointerControlPointIdentities
            )
            values.merge(pointerValues) { _, pointer in pointer }
        }
        return values
    }

    private func spawn(
        from events: [SceneParticleState],
        trigger: SceneParticleChildTrigger,
        depth: Int,
        parentPath: String?,
        scopeID: UInt64?,
        parentOrigin: SIMD3<Double>,
        dynamicInstanceValues: SceneDynamicParticleValues?,
        pointerLocalPosition: SIMD3<Double>?,
        dynamicControlPoints: [Int: SIMD3<Double>],
        dynamicControlPointAngles: [Int: SIMD3<Double>],
        controlPointFrame: SceneParticleControlPointFrame?
    ) {
        guard !events.isEmpty else { return }
        let selectionKey = TemplateSelectionKey(
            trigger: trigger, depth: depth, parentAssetPath: parentPath
        )
        guard let selectedTemplates = templatesBySelection[selectionKey] else { return }
        // This dispatch only appends systems. Keep its budget counts local so
        // each event sees preceding appends without rescanning live systems.
        var activeCounts: [Int: Int] = [:]
        for system in systems where system.spawnScopeID == scopeID {
            activeCounts[system.templateIndex, default: 0] += 1
        }
        var allocation = depthAllocation(depth)
        for event in events {
            for template in selectedTemplates {
                let activeCount = activeCounts[template.index, default: 0]
                guard activeCount < template.maximumSystemCount,
                      SceneParticleChildLifecycle.accepts(event: event, template: template, scopeID: scopeID)
                else { continue }
                guard allocation.systems < Self.maximumSystemsPerDepth,
                      template.particleBudget <= Self.maximumParticlesPerDepth - allocation.particles else {
#if DEBUG
                    frameLimitations.insert(Self.budgetDetail(depth: depth))
#endif
                    continue
                }
                appendSystem(
                    template: template,
                    scopeID: scopeID,
                    parentParticleID: nil,
                    origin: parentOrigin + event.position,
                    parentParticle: event,
                    dynamicInstanceValues: dynamicInstanceValues,
                    pointerLocalPosition: pointerLocalPosition, dynamicControlPoints: dynamicControlPoints,
                    dynamicControlPointAngles: dynamicControlPointAngles, controlPointFrame: controlPointFrame
                )
                activeCounts[template.index] = activeCount + 1
                allocation.systems += 1
                allocation.particles += template.particleBudget
            }
        }
    }

    private func reconcileFollowers(
        _ parents: [SceneParticleState],
        depth: Int,
        parentPath: String?,
        scopeID: UInt64?,
        parentOrigin: SIMD3<Double>,
        dynamicInstanceValues: SceneDynamicParticleValues?,
        pointerLocalPosition: SIMD3<Double>?,
        dynamicControlPoints: [Int: SIMD3<Double>],
        dynamicControlPointAngles: [Int: SIMD3<Double>],
        controlPointFrame: SceneParticleControlPointFrame?
    ) {
        guard !parents.isEmpty else { return }
        let selectionKey = TemplateSelectionKey(
            trigger: .follow, depth: depth, parentAssetPath: parentPath
        )
        guard let selectedTemplates = templatesBySelection[selectionKey] else { return }
        var allocation = depthAllocation(depth)
        for template in selectedTemplates {
            var followedIDs = Set(systems.lazy.compactMap { system in
                system.templateIndex == template.index && system.spawnScopeID == scopeID
                    ? system.parentParticleID : nil
            })
            for parent in parents {
                guard !followedIDs.contains(parent.id),
                      followedIDs.count < template.maximumSystemCount,
                      SceneParticleChildLifecycle.accepts(event: parent, template: template, scopeID: scopeID)
                else { continue }
                guard allocation.systems < Self.maximumSystemsPerDepth,
                      template.particleBudget <= Self.maximumParticlesPerDepth - allocation.particles else {
#if DEBUG
                    frameLimitations.insert(Self.budgetDetail(depth: depth))
#endif
                    continue
                }
                followedIDs.insert(parent.id)
                appendSystem(
                    template: template,
                    scopeID: scopeID,
                    parentParticleID: parent.id,
                    origin: parentOrigin + parent.position,
                    parentParticle: parent,
                    dynamicInstanceValues: dynamicInstanceValues,
                    pointerLocalPosition: pointerLocalPosition, dynamicControlPoints: dynamicControlPoints,
                    dynamicControlPointAngles: dynamicControlPointAngles, controlPointFrame: controlPointFrame
                )
                allocation.systems += 1
                allocation.particles += template.particleBudget
            }
        }
    }

    private func appendSystem(
        template: SceneParticleChildTemplate,
        scopeID: UInt64?,
        parentParticleID: UInt64?,
        origin: SIMD3<Double>,
        parentParticle: SceneParticleState,
        dynamicInstanceValues: SceneDynamicParticleValues?,
        pointerLocalPosition: SIMD3<Double>?,
        dynamicControlPoints: [Int: SIMD3<Double>],
        dynamicControlPointAngles: [Int: SIMD3<Double>],
        controlPointFrame: SceneParticleControlPointFrame?
    ) {
        let seed = UInt64(bitPattern: Int64(layerID))
            ^ parentParticle.id &* 0x9E37_79B9_7F4A_7C15
            ^ UInt64(template.index &+ 1) &* 0xBF58_476D_1CE4_E5B9
            ^ (scopeID ?? 0) &* 0x94D0_49BB_1331_11EB
            ^ nextSeed
        nextSeed &+= 1
        let simulator = template.simulator(
            seed: seed,
            dynamicInstanceValues: dynamicInstanceValues,
            origin: origin,
            controlPointFrame: controlPointFrame,
            initialDynamicControlPoints: Self.controlPointValues(
                for: template, origin: origin,
                pointerLocalPosition: pointerLocalPosition, dynamicControlPoints: dynamicControlPoints
            ),
            initialDynamicControlPointAngles: dynamicControlPointAngles,
            maximumEmissionDuration: template.trigger == .follow ? nil
                : SceneParticleChildLifecycle.maximumParticleLifetime(template.definition),
            eventColorContext: template.eventColorContext(for: parentParticle)
        )
        systems.append(SceneParticleChildSystem(
            id: nextSystemID,
            templateIndex: template.index,
            depth: template.depth,
            spawnScopeID: scopeID,
            parentParticleID: parentParticleID,
            isWorldSpace: template.definition.flags.isWorldSpace,
            origin: origin,
            particleOrigins: template.definition.flags.isWorldSpace
                ? Dictionary(uniqueKeysWithValues: simulator.particles.map { ($0.id, origin) }) : [:],
            simulator: simulator
        ))
        nextSystemID &+= 1
    }

    private func updateWorldSpaceOrigins(
        systemAt index: Int,
        births: [SceneParticleState],
        deaths: [SceneParticleState]
    ) {
        guard systems[index].isWorldSpace else { return }
        for particle in births {
            systems[index].particleOrigins[particle.id] = systems[index].origin
        }
        for particle in deaths {
            systems[index].particleOrigins.removeValue(forKey: particle.id)
        }
    }

    private func depthAllocation(_ depth: Int) -> (systems: Int, particles: Int) {
        var allocation = (systems: 0, particles: 0)
        for system in systems where system.depth == depth {
            allocation.systems += 1
            allocation.particles += system.simulator.maximumParticleCount
        }
        return allocation
    }

#if DEBUG
    private static func budgetDetail(depth: Int) -> String {
        depth <= 1
            ? "aggregateSystemBudget:systems=\(maximumSystemsPerDepth):particleCapacity="
            + "\(maximumParticlesPerDepth)"
            : "nestedAggregateSystemBudget:depth=2:systems=\(maximumSystemsPerDepth)"
            + ":particleCapacity=\(maximumParticlesPerDepth)"
    }
#endif
}
