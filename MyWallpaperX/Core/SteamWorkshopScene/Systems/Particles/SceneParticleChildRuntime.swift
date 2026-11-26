import Foundation
import Metal

/// Executes prepared child systems in their original scopes up to depth two.
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
            let receivedControlPoints: UInt8
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

    private let sceneIsOrthographic: Bool

    private struct FrameInputs {
        let delta: TimeInterval
        let timing: SceneParticleFrameTiming
        let dynamicInstanceValues: SceneDynamicParticleValues?
        let pointerLocalPosition: SIMD3<Double>?
        let dynamicControlPoints: [Int: SIMD3<Double>]
        let dynamicControlPointAngles: [Int: SIMD3<Double>]
        let audioInput: SceneParticleAudioInput
        let worldSpaceFrame: SceneParticleWorldSpaceFrame?
        let controlPointFrame: SceneParticleControlPointFrame?
        let rootTranslationOffset: SIMD3<Double>
        let allowsEmission: Bool
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
    private let streamsRootParticles: Bool
    private let streamsNestedParticles: Bool
    private let followsRootParticles: Bool
    private let followsNestedParticles: Bool
    private var systems: [SceneParticleChildSystem] = []
    private var instanceScratch: [SceneParticleChildRendererKey: [SceneParticleGPUInstance]] = [:]
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
        sceneIsOrthographic: Bool,
        worldSpaceFrame: SceneParticleWorldSpaceFrame?,
        rootInstanceOverride: SceneParticleInstanceOverride?,
        initialDynamicInstanceValues: SceneDynamicParticleValues? = nil,
        controlPointFrame: SceneParticleControlPointFrame? = nil,
        rootTranslationOffset: SIMD3<Double> = .zero,
        initialDynamicControlPoints: [Int: SIMD3<Double>] = [:],
        initialDynamicControlPointAngles: [Int: SIMD3<Double>] = [:],
        initialAudioInput: SceneParticleAudioInput = .silent,
        initialSceneTime: Double = 0
    ) {
        self.layerID = layerID
        self.sceneIsOrthographic = sceneIsOrthographic
        let expansion = SceneParticleChildGraphExpansion.expand(
            rootAsset: rootAsset,
            graph: graph,
            textureLoader: textureLoader,
            builtInTextureRegistry: builtInTextureRegistry,
            device: device,
            worldSpaceFrame: worldSpaceFrame,
            rootInstanceOverride: rootInstanceOverride
        )
        var preparedTemplates = expansion.templates
        var initialSystems: [SceneParticleChildSystem] = []
        var initialNextSystemID: UInt64 = 1
#if DEBUG
        var performance = expansion.performanceDetails
#endif
        let staticTemplateIndices = preparedTemplates.indices.filter {
            preparedTemplates[$0].depth == 1 && preparedTemplates[$0].trigger == .staticChild
        }
        var staticCapacity = Self.maximumParticlesPerDepth
        var staticRopeExpansionCapacity =
            SceneParticleChildTemplateSupport.maximumStaticRopeExpansionSegments
        for (offset, index) in staticTemplateIndices.enumerated() {
            var template = preparedTemplates[index]
            guard initialSystems.count < SceneParticleChildLifecycle.maximumSystemsPerDepth,
                  template.particleBudget <= staticCapacity else {
#if DEBUG
                let detail = Self.budgetDetail(depth: template.depth)
                if !performance.contains(detail) { performance.append(detail) }
#endif
                continue
            }
#if DEBUG
            let rendererCount = template.renderers.count
#endif
            var remainingSegments = SceneParticleChildTemplateSupport.maximumRopeSegmentsPerTemplate
                + staticRopeExpansionCapacity
            var ropeSegments = 0
            template.renderers.removeAll { renderer in
                guard let rope = renderer.rope else { return false }
                guard rope.maximumGeneratedSegments <= remainingSegments else { return true }
                remainingSegments -= rope.maximumGeneratedSegments
                ropeSegments += rope.maximumGeneratedSegments
                return false
            }
            preparedTemplates[index] = template
#if DEBUG
            if template.renderers.count != rendererCount {
                let detail = "staticRopeExpansionBudget:segments="
                    + "\(SceneParticleChildTemplateSupport.maximumStaticRopeExpansionSegments)"
                if !performance.contains(detail) { performance.append(detail) }
            }
#endif
            guard !template.renderers.isEmpty else { continue }
            staticCapacity -= template.particleBudget
            staticRopeExpansionCapacity -= max(ropeSegments
                - SceneParticleChildTemplateSupport.maximumRopeSegmentsPerTemplate, 0)
            let origin = template.transform.origin
                + (template.definition.flags.isWorldSpace ? rootTranslationOffset : .zero)
            let simulator = template.simulator(
                seed: UInt64(bitPattern: Int64(layerID))
                    ^ UInt64(template.index &+ 1) &* 0xBF58_476D_1CE4_E5B9
                    ^ UInt64(offset), timing: .init(sceneTime: initialSceneTime),
                sceneIsOrthographic: sceneIsOrthographic,
                dynamicInstanceValues: initialDynamicInstanceValues,
                origin: origin,
                controlPointFrame: controlPointFrame,
                worldSpaceFrameOverride: worldSpaceFrame,
                rootTranslationOffset: rootTranslationOffset,
                initialDynamicControlPoints: Self.controlPointValues(
                    for: template, origin: origin,
                    pointerLocalPosition: nil, dynamicControlPoints: initialDynamicControlPoints,
                    rootTranslationOffset: rootTranslationOffset
                ),
                initialDynamicControlPointAngles: initialDynamicControlPointAngles,
                initialAudioInput: initialAudioInput
            )
            initialSystems.append(SceneParticleChildSystem(
                id: initialNextSystemID,
                templateIndex: template.index,
                depth: template.depth,
                spawnScopeID: nil,
                parentParticleID: nil,
                isWorldSpace: template.definition.flags.isWorldSpace,
                origin: origin,
                particleOrigins: template.definition.flags.isWorldSpace
                    ? Dictionary(uniqueKeysWithValues: simulator.particles.map { ($0.id, origin) }) : [:],
                simulator: simulator
            ))
            initialNextSystemID &+= 1
        }
        templates = preparedTemplates
        requiredPipelineVariants = Set(preparedTemplates.flatMap { $0.renderers }.map {
            .init(isRefraction: $0.refraction != nil, blendMode: $0.renderState.blendMode,
                  usesDepthAttachment: $0.renderState.depthWriteEnabled)
        })
        templatesByIndex = Dictionary(
            preparedTemplates.map { ($0.index, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        templatesBySelection = Dictionary(
            grouping: preparedTemplates,
            by: {
                TemplateSelectionKey(
                    trigger: $0.trigger,
                    depth: $0.depth,
                    parentAssetPath: $0.parentAssetPath
                )
            }
        )
        // Output keys are launch topology; only their instance arrays change per frame.
        for template in preparedTemplates {
            for renderer in template.renderers {
                instanceScratch[.init(templateIndex: template.index, rendererIndex: renderer.index)] = []
            }
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
        hasPointerControlPointConsumer = preparedTemplates.contains {
            !$0.pointerControlPointIdentities.isEmpty
        }
        needsWorldControlPointFrame = preparedTemplates.contains(where: \.needsWorldControlPointFrame)
        nestedParentPaths = Set(preparedTemplates.compactMap(\.parentAssetPath))
        streamsRootParticles = preparedTemplates.contains { $0.depth == 1 && $0.particleControlPointMask != 0 }
        streamsNestedParticles = preparedTemplates.contains { $0.depth == 2 && $0.particleControlPointMask != 0 }
        followsRootParticles = preparedTemplates.contains { $0.depth == 1 && $0.trigger == .follow }
        followsNestedParticles = preparedTemplates.contains { $0.depth == 2 && $0.trigger == .follow }
        systems = initialSystems
        nextSystemID = initialNextSystemID
#if DEBUG
        performanceDetails = performance
#endif
        if !nestedParentPaths.isEmpty {
            let input = FrameInputs(delta: 0, timing: .init(sceneTime: initialSceneTime),
                dynamicInstanceValues: initialDynamicInstanceValues, pointerLocalPosition: nil,
                dynamicControlPoints: initialDynamicControlPoints, dynamicControlPointAngles: initialDynamicControlPointAngles,
                audioInput: initialAudioInput, worldSpaceFrame: worldSpaceFrame, controlPointFrame: controlPointFrame,
                rootTranslationOffset: rootTranslationOffset, allowsEmission: true)
            for system in initialSystems {
                appendStaticChildren(of: templatesByIndex[system.templateIndex]!, scope: system.id,
                    origin: system.origin + (system.isWorldSpace ? .zero : rootTranslationOffset),
                    particles: system.simulator.particles.liveParticles, input: input)
            }
        }
    }

    var lastWorldSpaceFrame: SceneParticleWorldSpaceFrame? {
        systems.first?.simulator.activeWorldSpaceFrame
    }

    func advance(
        by frameDelta: TimeInterval, timing: SceneParticleFrameTiming = .init(),
        spawnEvents: [SceneParticleState],
        deathEvents: [SceneParticleState],
        parentParticles: some Collection<SceneParticleState>,
        layerAlpha: Float,
        dynamicInstanceValues: SceneDynamicParticleValues? = nil,
        pointerLocalPosition: SIMD3<Double>? = nil,
        dynamicControlPoints: [Int: SIMD3<Double>] = [:],
        dynamicControlPointAngles: [Int: SIMD3<Double>] = [:],
        audioInput: SceneParticleAudioInput = .silent,
        worldSpaceFrameOverride: SceneParticleWorldSpaceFrame? = nil,
        controlPointFrame: SceneParticleControlPointFrame? = nil,
        rootTranslationOffset: SIMD3<Double> = .zero,
        isFrozen: Bool = false,
        isVisible: Bool = true
    ) -> SceneParticleChildAdvanceResult {
#if DEBUG
        frameLimitations.removeAll(keepingCapacity: true)
#endif
        var retiredRenderSystems: [SceneParticleChildSystem] = []
        if !isFrozen {
            let input = FrameInputs(delta: frameDelta, timing: timing, dynamicInstanceValues: dynamicInstanceValues,
                pointerLocalPosition: pointerLocalPosition, dynamicControlPoints: dynamicControlPoints,
                dynamicControlPointAngles: dynamicControlPointAngles, audioInput: audioInput,
                worldSpaceFrame: worldSpaceFrameOverride, controlPointFrame: controlPointFrame,
                rootTranslationOffset: rootTranslationOffset, allowsEmission: isVisible)
            let rootPoints = streamsRootParticles ? parentParticles.prefix(8).map(\.position) : []
            let parentFrames = advanceDepthOne(parentParticles, points: rootPoints, input: input)
            retireCompletedSystems(depth: 1, into: &retiredRenderSystems)
            let firstNewSystemID = nextSystemID
            spawn(from: spawnEvents, trigger: .spawn, points: rootPoints, input: input)
            spawn(from: deathEvents, trigger: .death, points: rootPoints, input: input)
            reconcileFollowers(parentParticles, points: rootPoints, input: input)
            advanceDepthTwo(parentFrames, before: firstNewSystemID, input: input,
                            retiredRenderSystems: &retiredRenderSystems)
        }

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
            rootTranslationOffset: rootTranslationOffset,
            into: &instanceScratch
        )
        let batches = SceneParticleChildInstanceBuilder.batches(
            templates: templates, layerID: layerID, scratch: instanceScratch
        )
#if DEBUG
        // Throttled spawn/instance census (~1s of sim time) distinguishes
        // bursty lifecycle windows from batch-creation gaps at snapshot time.
        censusTimeAccumulator += frameDelta
        let censusDue = !didLogInstanceCensus || censusTimeAccumulator >= 1
        if censusDue {
            didLogInstanceCensus = true
            censusTimeAccumulator = 0
            let spawned = templates.map { template in
                template.renderers.reduce(0) { count, renderer in
                    count + (instanceScratch[.init(templateIndex: template.index,
                        rendererIndex: renderer.index)]?.count ?? 0)
                }
            }
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
                    receivedControlPoints: $0.receivedControlPoints,
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
                simulator: $0.simulator, receivedControlPoints: $0.receivedControlPoints
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

    private func advanceDepthOne(
        _ rootParticles: some Collection<SceneParticleState>,
        points: [SIMD3<Double>], input: FrameInputs
    ) -> [SceneParticleChildParentFrame] {
        let parentsByID = followsRootParticles
            ? Dictionary(uniqueKeysWithValues: rootParticles.map { ($0.id, $0) }) : [:]
        var frames: [SceneParticleChildParentFrame] = []
        for index in systems.indices where systems[index].depth == 1 {
            let template = templatesByIndex[systems[index].templateIndex]!
            if let parentID = systems[index].parentParticleID {
                if let parent = parentsByID[parentID] {
                    refreshFollower(at: index, parent: parent, position: parent.position, input: input)
                } else {
                    systems[index].parentParticleID = nil
                }
            }
            if template.trigger == .staticChild && systems[index].isWorldSpace {
                systems[index].origin = template.transform.origin + input.rootTranslationOffset
            }
            let origins = nestedParentPaths.contains(template.path) ? systems[index].particleOrigins : [:]
            let (births, deaths) = advanceSystem(at: index, template: template, points: points, input: input)
            guard nestedParentPaths.contains(template.path) else { continue }
            frames.append(SceneParticleChildParentFrame(
                systemID: systems[index].id, path: template.path,
                origin: systems[index].origin + (systems[index].isWorldSpace ? .zero : input.rootTranslationOffset),
                scale: template.transform.scale, particleOrigins: origins, births: births, deaths: deaths,
                particles: systems[index].simulator.particles.liveParticles,
                streamPoints: streamsNestedParticles ? systems[index].simulator.particles.prefix(8).map(\.position) : []
            ))
        }
        return frames
    }

    private func advanceDepthTwo(
        _ parentFrames: [SceneParticleChildParentFrame], before firstNewSystemID: UInt64, input: FrameInputs,
        retiredRenderSystems: inout [SceneParticleChildSystem]
    ) {
        guard !nestedParentPaths.isEmpty else { return }
        let framesByID = Dictionary(uniqueKeysWithValues: parentFrames.map { ($0.systemID, $0) })
        let parentsByScope = followsNestedParticles ? framesByID.mapValues {
            Dictionary(uniqueKeysWithValues: $0.particles.map { ($0.id, $0) })
        } : [:]
        for index in systems.indices where systems[index].depth == 2 && systems[index].id < firstNewSystemID {
            let template = templatesByIndex[systems[index].templateIndex]!
            let scope = systems[index].spawnScopeID!
            let frame = framesByID[scope]
            if let parentID = systems[index].parentParticleID {
                if let frame, let particle = parentsByScope[scope]?[parentID] {
                    refreshFollower(at: index, parent: particle, position: frame.position(for: particle), input: input)
                } else {
                    systems[index].parentParticleID = nil
                }
            }
            if template.trigger == .staticChild, let frame {
                systems[index].origin = frame.origin + frame.scale * template.transform.origin
                    - (systems[index].isWorldSpace ? .zero : input.rootTranslationOffset)
            }
            _ = advanceSystem(at: index, template: template, points: frame?.streamPoints ?? [], input: input,
                              parentScopeEnded: template.trigger == .staticChild && frame == nil)
        }
        retireCompletedSystems(depth: 2, into: &retiredRenderSystems) { system in
            system.id < firstNewSystemID && templatesByIndex[system.templateIndex]!.trigger == .staticChild
                && framesByID[system.spawnScopeID!] == nil
        }
        for frame in parentFrames {
            spawn(from: frame.births, trigger: .spawn, frame: frame, points: frame.streamPoints, input: input)
            spawn(from: frame.deaths, trigger: .death, frame: frame, points: frame.streamPoints, input: input)
            reconcileFollowers(frame.particles, frame: frame, points: frame.streamPoints, input: input)
        }
    }

    private func refreshFollower(
        at index: Int, parent: SceneParticleState, position: SIMD3<Double>, input: FrameInputs
    ) {
        systems[index].origin = position - (systems[index].isWorldSpace ? .zero : input.rootTranslationOffset)
        systems[index].simulator.updateFollowEventValues(.init(color: parent.color, size: parent.size, alpha: parent.alpha))
    }

    private func advanceSystem(
        at index: Int, template: SceneParticleChildTemplate, points: [SIMD3<Double>], input: FrameInputs,
        parentScopeEnded: Bool = false
    ) -> (births: [SceneParticleState], deaths: [SceneParticleState]) {
#if DEBUG
        suppressObservedAudioComponents(systemAt: index)
#endif
        let simulator = systems[index].simulator
        let origin = systems[index].origin
        var controlPoints = Self.controlPointValues(
            for: template, origin: origin, pointerLocalPosition: input.pointerLocalPosition,
            dynamicControlPoints: input.dynamicControlPoints, rootTranslationOffset: input.rootTranslationOffset)
        Self.supplyParentPoints(points, to: template, previous: simulator.dynamicControlPoints,
                                received: &systems[index].receivedControlPoints, values: &controlPoints)
        let isWorld = systems[index].isWorldSpace
        simulator.advance(
            by: input.delta, timing: input.timing,
            dynamicControlPoints: controlPoints,
            dynamicControlPointAngles: input.dynamicControlPointAngles,
            dynamicInstanceOverride: simulator.instanceOverride?.resolving(input.dynamicInstanceValues),
            audioInput: input.audioInput, worldSpaceFrameOverride: input.worldSpaceFrame,
            controlPointFrame: simulator.needsWorldControlPointFrame
                ? input.controlPointFrame?.childFrame(
                    origin: origin - (isWorld ? input.rootTranslationOffset : .zero), scale: template.transform.scale) : nil,
            controlPointParticleSpace: isWorld
                ? .init(currentOrigin: origin, scale: template.transform.scale,
                        birthOrigins: systems[index].particleOrigins) : nil,
            hasChildStreamOrigin: systems[index].receivedControlPoints & 1 != 0,
            allowsEmission: input.allowsEmission && !parentScopeEnded
                && (template.trigger != .follow || systems[index].parentParticleID != nil)
        )
#if DEBUG
        collectAudioEvaluationObservations(systemAt: index)
#endif
        let births = simulator.consumeBirthEvents()
        let deaths = simulator.consumeDeathEvents()
        updateWorldSpaceOrigins(systemAt: index, births: births, deaths: deaths)
        return (births, deaths)
    }

    private static func supplyParentPoints(
        _ points: [SIMD3<Double>], to template: SceneParticleChildTemplate,
        previous: [Int: SIMD3<Double>], received: inout UInt8, values: inout [Int: SIMD3<Double>]
    ) {
        guard template.particleControlPointMask != 0, let start = template.particleControlPointStart else { return }
        for slot in start..<8 {
            let bit = UInt8(1) << slot
            guard template.particleControlPointMask & bit != 0 else { continue }
            let index = slot - start
            if index < points.count {
                values[slot] = points[index]
                received |= bit
            } else if received & bit != 0 {
                values[slot] = previous[slot]
            }
        }
    }

    private func retireCompletedSystems(
        depth: Int,
        into retiredRenderSystems: inout [SceneParticleChildSystem],
        scopeEnded: (SceneParticleChildSystem) -> Bool = { _ in false }
    ) {
        systems.removeAll { system in
            guard system.depth == depth, system.parentParticleID == nil,
                  system.simulator.simulationTime > 0, system.simulator.particles.isEmpty,
                  system.simulator.hasFinishedEmission
                    || templatesByIndex[system.templateIndex]!.trigger == .follow || scopeEnded(system)
            else { return false }
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

    /// World values stay in their source space for the point frame. Root-local
    /// values and the pointer use the same origin/scale as instance assembly.
    private static func controlPointValues(
        for template: SceneParticleChildTemplate,
        origin: SIMD3<Double>,
        pointerLocalPosition: SIMD3<Double>?,
        dynamicControlPoints: [Int: SIMD3<Double>],
        rootTranslationOffset: SIMD3<Double>
    ) -> [Int: SIMD3<Double>] {
        let origin = origin - (template.definition.flags.isWorldSpace ? rootTranslationOffset : .zero)
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
        from events: [SceneParticleState], trigger: SceneParticleChildTrigger,
        frame: SceneParticleChildParentFrame? = nil, points: [SIMD3<Double>], input: FrameInputs
    ) {
        guard !events.isEmpty else { return }
        let depth = frame == nil ? 1 : 2
        let scopeID = frame?.systemID
        let key = TemplateSelectionKey(trigger: trigger, depth: depth, parentAssetPath: frame?.path)
        guard let selectedTemplates = templatesBySelection[key] else { return }
        var activeCounts: [Int: Int] = [:]
        for system in systems where system.spawnScopeID == scopeID {
            activeCounts[system.templateIndex, default: 0] += 1
        }
        var allocation = depthAllocation(depth)
        for event in events {
            for template in selectedTemplates {
                let count = activeCounts[template.index, default: 0]
                guard count < template.maximumSystemCount,
                      SceneParticleChildLifecycle.accepts(event: event, template: template, scopeID: scopeID),
                      reserve(template, allocation: &allocation) else { continue }
                appendSystem(template: template, scopeID: scopeID, parentParticleID: nil,
                    origin: frame?.position(for: event) ?? event.position, parentParticle: event,
                    points: points, input: input)
                activeCounts[template.index] = count + 1
            }
        }
    }

    private func reconcileFollowers(
        _ parents: some Collection<SceneParticleState>, frame: SceneParticleChildParentFrame? = nil,
        points: [SIMD3<Double>], input: FrameInputs
    ) {
        guard !parents.isEmpty else { return }
        let depth = frame == nil ? 1 : 2
        let scopeID = frame?.systemID
        let key = TemplateSelectionKey(trigger: .follow, depth: depth, parentAssetPath: frame?.path)
        guard let selectedTemplates = templatesBySelection[key] else { return }
        var allocation = depthAllocation(depth)
        for template in selectedTemplates {
            var followedIDs: Set<UInt64> = []
            var count = 0
            for system in systems where system.templateIndex == template.index && system.spawnScopeID == scopeID {
                count += 1
                if let parentID = system.parentParticleID { followedIDs.insert(parentID) }
            }
            for parent in parents {
                guard count < template.maximumSystemCount else { break }
                guard !followedIDs.contains(parent.id),
                      SceneParticleChildLifecycle.accepts(event: parent, template: template, scopeID: scopeID),
                      reserve(template, allocation: &allocation) else { continue }
                appendSystem(template: template, scopeID: scopeID, parentParticleID: parent.id,
                    origin: frame?.position(for: parent) ?? parent.position, parentParticle: parent,
                    points: points, input: input)
                followedIDs.insert(parent.id)
                count += 1
            }
        }
    }

    private func reserve(_ template: SceneParticleChildTemplate, allocation: inout (systems: Int, particles: Int)) -> Bool {
        guard allocation.systems < SceneParticleChildLifecycle.maximumSystemsPerDepth,
              template.particleBudget <= Self.maximumParticlesPerDepth - allocation.particles else {
#if DEBUG
            frameLimitations.insert(Self.budgetDetail(depth: template.depth))
#endif
            return false
        }
        allocation.systems += 1
        allocation.particles += template.particleBudget
        return true
    }

    private func appendSystem(
        template: SceneParticleChildTemplate, scopeID: UInt64?, parentParticleID: UInt64?,
        origin parentSpaceOrigin: SIMD3<Double>, parentParticle: SceneParticleState?,
        points: [SIMD3<Double>], input: FrameInputs
    ) {
        let seed = UInt64(bitPattern: Int64(layerID))
            ^ (parentParticle?.id ?? 0) &* 0x9E37_79B9_7F4A_7C15
            ^ UInt64(template.index &+ 1) &* 0xBF58_476D_1CE4_E5B9
            ^ (scopeID ?? 0) &* 0x94D0_49BB_1331_11EB
            ^ nextSeed
        nextSeed &+= 1
        let isWorld = template.definition.flags.isWorldSpace
        let origin = parentSpaceOrigin - (isWorld ? .zero : input.rootTranslationOffset)
        var controlPoints = Self.controlPointValues(
            for: template, origin: origin, pointerLocalPosition: input.pointerLocalPosition,
            dynamicControlPoints: input.dynamicControlPoints, rootTranslationOffset: input.rootTranslationOffset)
        var received: UInt8 = 0
        Self.supplyParentPoints(points, to: template, previous: [:], received: &received, values: &controlPoints)
        let simulator = template.simulator(
            seed: seed, timing: input.timing, sceneIsOrthographic: sceneIsOrthographic,
            dynamicInstanceValues: input.dynamicInstanceValues, origin: origin,
            controlPointFrame: input.controlPointFrame, worldSpaceFrameOverride: input.worldSpaceFrame,
            rootTranslationOffset: input.rootTranslationOffset,
            initialDynamicControlPoints: controlPoints, initialDynamicControlPointAngles: input.dynamicControlPointAngles,
            initialAudioInput: input.audioInput,
            hasChildStreamOrigin: received & 1 != 0,
            maximumEmissionDuration: parentParticle != nil && template.trigger != .follow
                ? SceneParticleChildLifecycle.maximumParticleLifetime(template.definition) : nil,
            eventValueContext: parentParticle.map { template.eventValueContext(for: $0) } ?? .unavailable
        )
        let id = nextSystemID
        nextSystemID &+= 1
        systems.append(SceneParticleChildSystem(
            id: id, templateIndex: template.index, depth: template.depth, spawnScopeID: scopeID,
            parentParticleID: parentParticleID, isWorldSpace: isWorld, origin: origin,
            particleOrigins: isWorld ? Dictionary(uniqueKeysWithValues: simulator.particles.map { ($0.id, origin) }) : [:],
            simulator: simulator, receivedControlPoints: received
        ))
        if template.depth == 1 {
            appendStaticChildren(of: template, scope: id, origin: parentSpaceOrigin,
                                 particles: simulator.particles.liveParticles, input: input)
        }
    }

    private func appendStaticChildren(
        of parent: SceneParticleChildTemplate, scope: UInt64, origin: SIMD3<Double>,
        particles: ArraySlice<SceneParticleState>, input: FrameInputs
    ) {
        let key = TemplateSelectionKey(trigger: .staticChild, depth: 2, parentAssetPath: parent.path)
        guard let selectedTemplates = templatesBySelection[key] else { return }
        let points = streamsNestedParticles ? particles.prefix(8).map(\.position) : []
        var allocation = depthAllocation(2)
        for template in selectedTemplates where reserve(template, allocation: &allocation) {
            appendSystem(template: template, scopeID: scope, parentParticleID: nil,
                origin: origin + parent.transform.scale * template.transform.origin,
                parentParticle: nil, points: points, input: input)
        }
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
            ? "aggregateSystemBudget:systems=\(SceneParticleChildLifecycle.maximumSystemsPerDepth):particleCapacity="
            + "\(maximumParticlesPerDepth)"
            : "nestedAggregateSystemBudget:depth=2:systems=\(SceneParticleChildLifecycle.maximumSystemsPerDepth)"
            + ":particleCapacity=\(maximumParticlesPerDepth)"
    }
#endif
}
