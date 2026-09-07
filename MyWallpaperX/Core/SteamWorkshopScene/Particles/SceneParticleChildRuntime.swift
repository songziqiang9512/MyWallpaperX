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
        audioInput: SceneParticleAudioInput = .silent
    ) -> SceneParticleChildAdvanceResult {
        var limitations: Set<String> = []
        let parentFrames = advanceDepthOne(
            by: frameDelta,
            rootParticles: parentParticles,
            pointerLocalPosition: pointerLocalPosition,
            dynamicControlPoints: dynamicControlPoints,
            audioInput: audioInput
        )
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
            audioInput: audioInput,
            limitations: &limitations
        )

        SceneParticleChildInstanceBuilder.rebuildAll(
            templates: templates,
            templatesByIndex: templatesByIndex,
            systems: systems,
            layerAlpha: layerAlpha,
            into: &instanceScratch
        )
        var batches: [SceneParticleDrawBatch] = []
        batches.reserveCapacity(templates.count)
        var failures: [String] = []
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
            nextSystemID: nextSystemID
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
        instanceScratch.removeAll(keepingCapacity: true)
    }

    func teardown() {
        systems.removeAll(keepingCapacity: false)
        instanceScratch.removeAll(keepingCapacity: false)
    }

    /// Advances depth-one systems against the root simulator and collects the per-system
    /// event frames that feed nested children, before completed systems are recycled.
    private func advanceDepthOne(
        by frameDelta: TimeInterval,
        rootParticles: [SceneParticleState],
        pointerLocalPosition: SIMD3<Double>?,
        dynamicControlPoints: [Int: SIMD3<Double>],
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
                audioInput: audioInput
            )
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
        removeCompletedSystems(depth: 1)
        return frames
    }

    private func advanceDepthTwo(
        by frameDelta: TimeInterval,
        parentFrames: [SceneParticleChildParentFrame],
        pointerLocalPosition: SIMD3<Double>?,
        dynamicControlPoints: [Int: SIMD3<Double>],
        audioInput: SceneParticleAudioInput,
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
                audioInput: audioInput
            )
            let births = systems[index].simulator.consumeBirthEvents()
            let deaths = systems[index].simulator.consumeDeathEvents()
            updateWorldSpaceOrigins(systemAt: index, births: births, deaths: deaths)
        }
        removeCompletedSystems(depth: 2)
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

    private func removeCompletedSystems(depth: Int) {
        systems.removeAll {
            $0.depth == depth
                && $0.parentParticleID == nil
                && $0.simulator.simulationTime > 0
                && $0.emissionCompletionTime != nil
                && $0.simulator.simulationTime + 1e-12 >= ($0.emissionCompletionTime ?? .infinity)
                && $0.simulator.particles.isEmpty
        }
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
        if !template.pointerControlPointIdentities.isEmpty,
           let pointerLocalPosition {
            let childLocalPosition = template.transform.inversePosition(
                pointerLocalPosition - system.origin
            )
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
