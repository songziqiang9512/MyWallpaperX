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
            let emissionCompletionTime: Double?
            let isWorldSpace: Bool
            let origin: SIMD3<Double>
            let particleOrigins: [UInt64: SIMD3<Double>]
            let simulator: SceneParticleSimulator
            let simulatorFrame: SceneParticleSimulator.FrameSnapshot
        }

        let systems: [SystemSnapshot]
        let nextSeed: UInt64
        let nextSystemID: UInt64
        let observedAudioComponentsByTemplate:
            [Int: Set<SceneParticleAudioComponentIdentity>]
        let pendingAudioEvaluationObservations:
            [SceneParticleChildAudioEvaluationObservation]
    }

    private struct TemplateSelectionKey: Hashable {
        let trigger: SceneParticleChildTrigger
        let depth: Int
        let parentAssetPath: String?
    }

    // Child systems run on the CPU fallback; cap burst spikes while retaining authored
    // distribution. Each depth keeps its own aggregate budget so nested trails cannot
    // starve depth-one children and vice versa.
    static let maximumParticlesPerSystem = 1024
    private static let maximumSystemsPerDepth = 64

    let unsupportedDetails: [String]
    let performanceDetails: [String]
    let handlesAllChildren: Bool
    /// Launch-stable demand used by the host to avoid projecting the pointer
    /// for particle layers whose prepared child graph cannot consume it.
    let hasPointerControlPointConsumer: Bool
    /// One-line launch summary for the DEBUG evidence path: how many child
    /// systems the expansion produced versus how many declarations it saw.
    var expansionSummary: String {
        "templates=\(templates.count) unsupported=\(unsupportedDetails.count) "
            + "systems=\(systems.count) handlesAllChildren=\(handlesAllChildren)"
    }

    var hasTemplates: Bool {
        !templates.isEmpty
    }

    /// Child templates use the same simulator audio plans as root systems. Keep
    /// the demand bit on the graph owner so an audio-enabled child can start
    /// the shared producer even when its root container has no audio fields.
    var hasAudioConsumer: Bool {
        templates.contains { $0.definition.hasBoundedAudioConsumer }
    }

    var lifecycleSystemCount: Int { systems.count }
    var lifecycleParticleCount: Int {
        systems.reduce(0) { $0 + $1.simulator.particles.count }
    }

    private let layerID: Int
    private var didLogInstanceCensus = false
    private var censusTimeAccumulator: TimeInterval = 0
    private let layerAlpha: Float
    private let device: MTLDevice
    private let templates: [SceneParticleChildTemplate]
    private let templatesByIndex: [Int: SceneParticleChildTemplate]
    private let templatesBySelection: [TemplateSelectionKey: [SceneParticleChildTemplate]]
    private let nestedParentPaths: Set<String>
    private var systems: [SceneParticleChildSystem] = []
    private var instanceScratch: [Int: [SceneParticleGPUInstance]] = [:]
    private var nextSeed: UInt64 = 0
    private var nextSystemID: UInt64 = 1
    private var observedAudioComponentsByTemplate:
        [Int: Set<SceneParticleAudioComponentIdentity>] = [:]
    private var pendingAudioEvaluationObservations:
        [SceneParticleChildAudioEvaluationObservation] = []

    init(
        layerID: Int,
        rootAsset: SceneParticleAsset,
        graph: SceneParticleAssetGraph,
        layerAlpha: Float,
        textureLoader: SceneTextureLoader,
        builtInTextureRegistry: SceneParticleBuiltInTextureRegistry,
        device: MTLDevice,
        worldSpaceFrame: SceneParticleWorldSpaceFrame?,
        rootInstanceOverride: SceneParticleInstanceOverride?
    ) {
        self.layerID = layerID
        self.layerAlpha = layerAlpha
        self.device = device
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
        }
        unsupportedDetails = expansion.unsupportedDetails
        handlesAllChildren = expansion.handledRootChildren == rootAsset.definition.children.count
        hasPointerControlPointConsumer = expansion.templates.contains {
            !$0.pointerControlPointIdentities.isEmpty
        }
        nestedParentPaths = Set(templates.compactMap(\.parentAssetPath))
        var performance = expansion.performanceDetails
        let staticTemplates = templates.filter { $0.trigger == .staticChild }
        if staticTemplates.count > Self.maximumSystemsPerDepth {
            performance.append(Self.budgetDetail(depth: 1))
        }
        for (offset, template) in staticTemplates.prefix(Self.maximumSystemsPerDepth).enumerated() {
            systems.append(SceneParticleChildSystem(
                id: nextSystemID,
                templateIndex: template.index,
                depth: template.depth,
                spawnScopeID: nil,
                parentParticleID: nil,
                emissionCompletionTime: SceneParticleChildLifecycle.emissionCompletionTime(
                    template.definition
                ),
                isWorldSpace: template.definition.flags.isWorldSpace,
                origin: template.transform.origin,
                particleOrigins: [:],
                simulator: template.simulator(
                    seed: UInt64(bitPattern: Int64(layerID))
                        ^ UInt64(template.index &+ 1) &* 0xBF58_476D_1CE4_E5B9
                        ^ UInt64(offset)
                )
            ))
            nextSystemID &+= 1
        }
        performanceDetails = performance
    }

    func advance(
        by frameDelta: TimeInterval,
        spawnEvents: [SceneParticleState],
        deathEvents: [SceneParticleState],
        parentParticles: [SceneParticleState],
        pointerLocalPosition: SIMD3<Double>? = nil,
        dynamicControlPoints: [Int: SIMD3<Double>] = [:],
        dynamicControlPointAngles: [Int: SIMD3<Double>] = [:],
        audioInput: SceneParticleAudioInput = .silent
    ) -> SceneParticleChildAdvanceResult {
        var limitations: Set<String> = []
        var retiredRenderSystems: [SceneParticleChildSystem] = []
        let parentFrames = advanceDepthOne(
            by: frameDelta,
            rootParticles: parentParticles,
            pointerLocalPosition: pointerLocalPosition,
            dynamicControlPoints: dynamicControlPoints,
            dynamicControlPointAngles: dynamicControlPointAngles,
            audioInput: audioInput
        )
        retireCompletedSystems(depth: 1, into: &retiredRenderSystems)
        spawn(
            from: spawnEvents, trigger: .spawn, depth: 1, parentPath: nil,
            scopeID: nil, parentOrigin: .zero, limitations: &limitations
        )
        spawn(
            from: deathEvents, trigger: .death, depth: 1, parentPath: nil,
            scopeID: nil, parentOrigin: .zero, limitations: &limitations
        )
        reconcileFollowers(
            parentParticles, depth: 1, parentPath: nil,
            scopeID: nil, parentOrigin: .zero, limitations: &limitations
        )
        advanceDepthTwo(
            by: frameDelta,
            parentFrames: parentFrames,
            pointerLocalPosition: pointerLocalPosition,
            dynamicControlPoints: dynamicControlPoints,
            dynamicControlPointAngles: dynamicControlPointAngles,
            audioInput: audioInput,
            retiredRenderSystems: &retiredRenderSystems,
            limitations: &limitations
        )

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
        var failures: [String] = []
        // DEBUG probe: throttled spawn/instance census (~1s of sim time) with
        // the built batch count, to distinguish bursty lifecycle windows from
        // batch-creation gaps at snapshot time.
        censusTimeAccumulator += frameDelta
        let censusDue = !didLogInstanceCensus || censusTimeAccumulator >= 1
        for template in templates {
            guard let instances = instanceScratch[template.index], !instances.isEmpty else {
                continue
            }
            guard template.instanceBuffer.update(device: device, instances: instances) else {
                failures.append(template.path)
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
                instanceBuffer: template.instanceBuffer,
                instances: instances,
                orientation: template.orientation,
                orientationAxis: template.orientationAxis,
                usesPerspective: template.usesPerspective
            ))
        }
        if censusDue {
            didLogInstanceCensus = true
            censusTimeAccumulator = 0
            let spawned = templates.compactMap { instanceScratch[$0.index]?.count }
            let systemParticleCounts = systems.map { $0.simulator.particles.count }
            let systemParticleTotal = systemParticleCounts.reduce(0, +)
            NSLog(
                "MWX DEBUG SCENE: phase=particle-child-census layer=%d templates=%d systems=%d systemParticles=%d spawnedTotal=%d emptyTemplates=%d nonEmptySystems=%d batches=%d bufferFailures=%d",
                layerID, templates.count, systems.count,
                systemParticleTotal, spawned.reduce(0, +), spawned.count,
                systemParticleCounts.filter { $0 > 0 }.count,
                batches.count, failures.count
            )
        }
        return SceneParticleChildAdvanceResult(
            batches: batches,
            bufferFailurePaths: failures,
            limitationDetails: limitations.sorted()
        )
    }

    func frameSnapshot() -> FrameSnapshot {
        FrameSnapshot(
            systems: systems.map {
                .init(
                    id: $0.id,
                    templateIndex: $0.templateIndex,
                    depth: $0.depth,
                    spawnScopeID: $0.spawnScopeID,
                    parentParticleID: $0.parentParticleID,
                    emissionCompletionTime: $0.emissionCompletionTime,
                    isWorldSpace: $0.isWorldSpace,
                    origin: $0.origin,
                    particleOrigins: $0.particleOrigins,
                    simulator: $0.simulator,
                    simulatorFrame: $0.simulator.frameSnapshot()
                )
            },
            nextSeed: nextSeed,
            nextSystemID: nextSystemID,
            observedAudioComponentsByTemplate: observedAudioComponentsByTemplate,
            pendingAudioEvaluationObservations: pendingAudioEvaluationObservations
        )
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
                emissionCompletionTime: $0.emissionCompletionTime,
                isWorldSpace: $0.isWorldSpace,
                origin: $0.origin,
                particleOrigins: $0.particleOrigins,
                simulator: $0.simulator
            )
        }
        nextSeed = snapshot.nextSeed
        nextSystemID = snapshot.nextSystemID
        observedAudioComponentsByTemplate = snapshot.observedAudioComponentsByTemplate
        pendingAudioEvaluationObservations = snapshot.pendingAudioEvaluationObservations
        instanceScratch.removeAll(keepingCapacity: true)
    }

    func consumeAudioEvaluationObservations()
        -> [SceneParticleChildAudioEvaluationObservation] {
        defer { pendingAudioEvaluationObservations.removeAll(keepingCapacity: true) }
        return pendingAudioEvaluationObservations
    }

    func teardown() {
        systems.removeAll(keepingCapacity: false)
        instanceScratch.removeAll(keepingCapacity: false)
        observedAudioComponentsByTemplate.removeAll(keepingCapacity: false)
        pendingAudioEvaluationObservations.removeAll(keepingCapacity: false)
    }

    /// Advances depth-one systems against the root simulator and collects the per-system
    /// event frames that feed nested children, before completed systems are recycled.
    private func advanceDepthOne(
        by frameDelta: TimeInterval,
        rootParticles: [SceneParticleState],
        pointerLocalPosition: SIMD3<Double>?,
        dynamicControlPoints: [Int: SIMD3<Double>],
        dynamicControlPointAngles: [Int: SIMD3<Double>],
        audioInput: SceneParticleAudioInput
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
            suppressObservedAudioComponents(systemAt: index)
            if let parentID = systems[index].parentParticleID,
               let parent = parentsByID[parentID]
            {
                systems[index].origin = parent.position
                systems[index].simulator.updateFollowEventColor(parent.color)
            }
            systems[index].simulator.advance(
                by: frameDelta,
                dynamicControlPoints: controlPointValues(
                    for: systems[index],
                    pointerLocalPosition: pointerLocalPosition,
                    dynamicControlPoints: dynamicControlPoints
                ),
                dynamicControlPointAngles: dynamicControlPointAngles,
                audioInput: audioInput
            )
            collectAudioEvaluationObservations(systemAt: index)
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
        pointerLocalPosition: SIMD3<Double>?,
        dynamicControlPoints: [Int: SIMD3<Double>],
        dynamicControlPointAngles: [Int: SIMD3<Double>],
        audioInput: SceneParticleAudioInput,
        retiredRenderSystems: inout [SceneParticleChildSystem],
        limitations: inout Set<String>
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
            suppressObservedAudioComponents(systemAt: index)
            if let scope = systems[index].spawnScopeID,
               let parentID = systems[index].parentParticleID,
               let parent = liveParents[scope],
               let particle = parent.particles[parentID]
            {
                systems[index].origin = parent.origin + particle.position
                systems[index].simulator.updateFollowEventColor(particle.color)
            }
            systems[index].simulator.advance(
                by: frameDelta,
                dynamicControlPoints: controlPointValues(
                    for: systems[index],
                    pointerLocalPosition: pointerLocalPosition,
                    dynamicControlPoints: dynamicControlPoints
                ),
                dynamicControlPointAngles: dynamicControlPointAngles,
                audioInput: audioInput
            )
            collectAudioEvaluationObservations(systemAt: index)
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
                scopeID: frame.systemID, parentOrigin: frame.origin, limitations: &limitations
            )
            spawn(
                from: frame.deaths, trigger: .death, depth: 2, parentPath: frame.path,
                scopeID: frame.systemID, parentOrigin: frame.origin, limitations: &limitations
            )
            reconcileFollowers(
                frame.particles, depth: 2, parentPath: frame.path,
                scopeID: frame.systemID, parentOrigin: frame.origin, limitations: &limitations
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

    private func collectAudioEvaluationObservations(systemAt index: Int) {
        guard let template = templatesByIndex[systems[index].templateIndex] else {
            return
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

    private func isCompleted(_ system: SceneParticleChildSystem, atDepth depth: Int) -> Bool {
        system.depth == depth
            && system.parentParticleID == nil
            && system.simulator.simulationTime > 0
            && system.emissionCompletionTime != nil
            && system.simulator.simulationTime + 1e-12
                >= (system.emissionCompletionTime ?? .infinity)
            && system.simulator.particles.isEmpty
    }

    /// The frame producer supplies root-local dynamic values and an optional pointer.
    /// Child particles simulate before their authored scale is applied at instance
    /// assembly, so convert both through the same child origin/scale frame.
    private func controlPointValues(
        for system: SceneParticleChildSystem,
        pointerLocalPosition: SIMD3<Double>?,
        dynamicControlPoints: [Int: SIMD3<Double>]
    ) -> [Int: SIMD3<Double>] {
        guard let template = templatesByIndex[system.templateIndex] else {
            return [:]
        }
        var values: [Int: SIMD3<Double>] = [:]
        if !dynamicControlPoints.isEmpty {
            values.reserveCapacity(dynamicControlPoints.count)
            for (identity, value) in dynamicControlPoints {
                let childLocal = template.transform.inversePosition(value - system.origin)
                guard childLocal.x.isFinite, childLocal.y.isFinite, childLocal.z.isFinite else {
                    continue
                }
                values[identity] = childLocal
            }
        }
        if !template.pointerControlPointIdentities.isEmpty {
            let childLocalPosition = pointerLocalPosition.map {
                template.transform.inversePosition($0 - system.origin)
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
        limitations: inout Set<String>
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
        var activeDepthCount = depthSystemCount(depth)
        for event in events {
            for template in selectedTemplates {
                let activeCount = activeCounts[template.index, default: 0]
                guard activeCount < template.maximumSystemCount,
                      SceneParticleChildLifecycle.accepts(event: event, template: template, scopeID: scopeID)
                else { continue }
                guard activeDepthCount < Self.maximumSystemsPerDepth else {
                    limitations.insert(Self.budgetDetail(depth: depth))
                    continue
                }
                appendSystem(
                    template: template,
                    scopeID: scopeID,
                    parentParticleID: nil,
                    origin: parentOrigin + event.position,
                    parentParticle: event
                )
                activeCounts[template.index] = activeCount + 1
                activeDepthCount += 1
            }
        }
    }

    private func reconcileFollowers(
        _ parents: [SceneParticleState],
        depth: Int,
        parentPath: String?,
        scopeID: UInt64?,
        parentOrigin: SIMD3<Double>,
        limitations: inout Set<String>
    ) {
        guard !parents.isEmpty else { return }
        let selectionKey = TemplateSelectionKey(
            trigger: .follow, depth: depth, parentAssetPath: parentPath
        )
        guard let selectedTemplates = templatesBySelection[selectionKey] else { return }
        var activeDepthCount = depthSystemCount(depth)
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
                guard activeDepthCount < Self.maximumSystemsPerDepth else {
                    limitations.insert(Self.budgetDetail(depth: depth))
                    continue
                }
                followedIDs.insert(parent.id)
                appendSystem(
                    template: template,
                    scopeID: scopeID,
                    parentParticleID: parent.id,
                    origin: parentOrigin + parent.position,
                    parentParticle: parent
                )
                activeDepthCount += 1
            }
        }
    }

    private func appendSystem(
        template: SceneParticleChildTemplate,
        scopeID: UInt64?,
        parentParticleID: UInt64?,
        origin: SIMD3<Double>,
        parentParticle: SceneParticleState
    ) {
        let seed = UInt64(bitPattern: Int64(layerID))
            ^ parentParticle.id &* 0x9E37_79B9_7F4A_7C15
            ^ UInt64(template.index &+ 1) &* 0xBF58_476D_1CE4_E5B9
            ^ (scopeID ?? 0) &* 0x94D0_49BB_1331_11EB
            ^ nextSeed
        nextSeed &+= 1
        let completion = template.trigger == .follow
            ? SceneParticleChildLifecycle.emissionCompletionTime(template.definition)
            : SceneParticleChildLifecycle.eventEmissionWindow(template.definition)
        systems.append(SceneParticleChildSystem(
            id: nextSystemID,
            templateIndex: template.index,
            depth: template.depth,
            spawnScopeID: scopeID,
            parentParticleID: parentParticleID,
            emissionCompletionTime: completion,
            isWorldSpace: template.definition.flags.isWorldSpace,
            origin: origin,
            particleOrigins: [:],
            simulator: template.simulator(
                seed: seed,
                emissionDeadline: template.trigger == .follow ? nil : completion,
                eventColorContext: template.eventColorContext(for: parentParticle)
            )
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

    private func depthSystemCount(_ depth: Int) -> Int { systems.lazy.filter { $0.depth == depth }.count }

    private static func budgetDetail(depth: Int) -> String {
        depth <= 1
            ? "aggregateSystemBudget:systems=\(maximumSystemsPerDepth):particleCapacity="
            + "\(maximumSystemsPerDepth * maximumParticlesPerSystem)"
            : "nestedAggregateSystemBudget:depth=2:systems=\(maximumSystemsPerDepth)"
            + ":particleCapacity=\(maximumSystemsPerDepth * maximumParticlesPerSystem)"
    }
}
