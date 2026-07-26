import Foundation
import Metal

/// Executes strict children up to depth two. Unsupported declarations stay diagnostic.
final class SceneParticleChildRuntime {
    struct AdvanceResult {
        let batches: [SceneParticleDrawBatch]
        let bufferFailurePaths: [String]
        let limitationDetails: [String]
    }

    private struct System {
        let id: UInt64
        let templateIndex: Int
        let depth: Int
        let spawnScopeID: UInt64?
        let parentParticleID: UInt64?
        let emissionCompletionTime: Double?
        var origin: SIMD3<Double>
        var simulator: SceneParticleSimulator
    }

    private struct ParentFrame {
        let systemID: UInt64
        let path: String
        let origin: SIMD3<Double>
        let births: [SceneParticleState]
        let deaths: [SceneParticleState]
        let particles: [SceneParticleState]
    }

    // Child systems run on the CPU fallback; cap burst spikes while retaining authored
    // distribution. Each depth keeps its own aggregate budget so nested trails cannot
    // starve depth-one children and vice versa.
    static let maximumParticlesPerSystem = 1024
    private static let maximumSystemsPerDepth = 64

    let unsupportedDetails: [String]
    let performanceDetails: [String]
    let handlesAllChildren: Bool
    var hasTemplates: Bool {
        !templates.isEmpty
    }

    private let layerID: Int
    private let layerAlpha: Float
    private let device: MTLDevice
    private let templates: [SceneParticleChildTemplate]
    private let nestedParentPaths: Set<String>
    private var systems: [System] = []
    private var nextSeed: UInt64 = 0
    private var nextSystemID: UInt64 = 1

    init(
        layerID: Int,
        rootAsset: SceneParticleAsset,
        graph: SceneParticleAssetGraph,
        layerAlpha: Float,
        textureLoader: SceneTextureLoader,
        builtInTextureRegistry: SceneParticleBuiltInTextureRegistry,
        device: MTLDevice
    ) {
        self.layerID = layerID
        self.layerAlpha = layerAlpha
        self.device = device
        let expansion = SceneParticleChildGraphExpansion.expand(
            rootAsset: rootAsset,
            graph: graph,
            textureLoader: textureLoader,
            builtInTextureRegistry: builtInTextureRegistry,
            device: device
        )
        templates = expansion.templates
        unsupportedDetails = expansion.unsupportedDetails
        handlesAllChildren = expansion.handledRootChildren == rootAsset.definition.children.count
        nestedParentPaths = Set(templates.compactMap(\.parentAssetPath))
        var performance = expansion.performanceDetails
        let staticTemplates = templates.filter { $0.trigger == .staticChild }
        if staticTemplates.count > Self.maximumSystemsPerDepth {
            performance.append(Self.budgetDetail(depth: 1))
        }
        for (offset, template) in staticTemplates.prefix(Self.maximumSystemsPerDepth).enumerated() {
            systems.append(System(
                id: nextSystemID,
                templateIndex: template.index,
                depth: template.depth,
                spawnScopeID: nil,
                parentParticleID: nil,
                emissionCompletionTime: SceneParticleChildLifecycle.emissionCompletionTime(
                    template.definition
                ),
                origin: template.staticOrigin,
                simulator: SceneParticleSimulator(
                    definition: template.definition,
                    seed: UInt64(bitPattern: Int64(layerID))
                        ^ UInt64(template.index &+ 1) &* 0xBF58_476D_1CE4_E5B9
                        ^ UInt64(offset),
                    particleBudget: template.particleBudget
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
        parentParticles: [SceneParticleState]
    ) -> AdvanceResult {
        var limitations: Set<String> = []
        let parentFrames = advanceDepthOne(by: frameDelta, rootParticles: parentParticles)
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
        advanceDepthTwo(by: frameDelta, parentFrames: parentFrames, limitations: &limitations)

        var batches: [SceneParticleDrawBatch] = []
        var failures: [String] = []
        for template in templates {
            let instances = makeInstances(for: template)
            guard !instances.isEmpty else { continue }
            guard template.instanceBuffer.update(device: device, instances: instances) else {
                failures.append(template.path)
                continue
            }
            batches.append(SceneParticleDrawBatch(
                layerID: layerID,
                particlePath: template.path,
                texture: template.texture,
                blendMode: template.blendMode,
                instanceBuffer: template.instanceBuffer,
                instances: instances,
                orientation: template.orientation,
                orientationAxis: template.orientationAxis,
                usesPerspective: template.usesPerspective
            ))
        }
        return AdvanceResult(
            batches: batches,
            bufferFailurePaths: failures,
            limitationDetails: limitations.sorted()
        )
    }

    /// Advances depth-one systems against the root simulator and collects the per-system
    /// event frames that feed nested children, before completed systems are recycled.
    private func advanceDepthOne(
        by frameDelta: TimeInterval,
        rootParticles: [SceneParticleState]
    ) -> [ParentFrame] {
        let parentsByID: [UInt64: SceneParticleState] = templates.contains {
            $0.depth == 1 && $0.trigger == .follow
        } ? Dictionary(uniqueKeysWithValues: rootParticles.map { ($0.id, $0) }) : [:]
        systems.removeAll { system in
            guard system.depth == 1, let parentID = system.parentParticleID else { return false }
            return parentsByID[parentID] == nil
        }
        var frames: [ParentFrame] = []
        for index in systems.indices where systems[index].depth == 1 {
            if let parentID = systems[index].parentParticleID,
               let parent = parentsByID[parentID]
            {
                systems[index].origin = parent.position
            }
            systems[index].simulator.advance(by: frameDelta)
            let births = systems[index].simulator.consumeBirthEvents()
            let deaths = systems[index].simulator.consumeDeathEvents()
            guard let path = templatePath(at: systems[index].templateIndex),
                  nestedParentPaths.contains(path) else { continue }
            frames.append(ParentFrame(
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
        parentFrames: [ParentFrame],
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
            }
            systems[index].simulator.advance(by: frameDelta)
            _ = systems[index].simulator.consumeBirthEvents()
            _ = systems[index].simulator.consumeDeathEvents()
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
        for event in events {
            for template in templates
                where template.trigger == trigger && template.depth == depth
                && template.parentAssetPath == parentPath
            {
                let activeCount = systems.lazy.filter {
                    $0.templateIndex == template.index && $0.spawnScopeID == scopeID
                }.count
                guard activeCount < template.maximumSystemCount,
                      Self.accepts(event: event, template: template, scopeID: scopeID)
                else { continue }
                guard depthSystemCount(depth) < Self.maximumSystemsPerDepth else {
                    limitations.insert(Self.budgetDetail(depth: depth))
                    continue
                }
                appendSystem(
                    template: template,
                    scopeID: scopeID,
                    parentParticleID: nil,
                    origin: parentOrigin + event.position,
                    eventID: event.id
                )
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
        for template in templates
            where template.trigger == .follow && template.depth == depth
            && template.parentAssetPath == parentPath
        {
            var followedIDs = Set(systems.lazy.compactMap { system in
                system.templateIndex == template.index && system.spawnScopeID == scopeID
                    ? system.parentParticleID : nil
            })
            for parent in parents {
                guard !followedIDs.contains(parent.id),
                      followedIDs.count < template.maximumSystemCount,
                      Self.accepts(event: parent, template: template, scopeID: scopeID)
                else { continue }
                guard depthSystemCount(depth) < Self.maximumSystemsPerDepth else {
                    limitations.insert(Self.budgetDetail(depth: depth))
                    continue
                }
                followedIDs.insert(parent.id)
                appendSystem(
                    template: template,
                    scopeID: scopeID,
                    parentParticleID: parent.id,
                    origin: parentOrigin + parent.position,
                    eventID: parent.id
                )
            }
        }
    }

    private func appendSystem(
        template: SceneParticleChildTemplate,
        scopeID: UInt64?,
        parentParticleID: UInt64?,
        origin: SIMD3<Double>,
        eventID: UInt64
    ) {
        let seed = UInt64(bitPattern: Int64(layerID))
            ^ eventID &* 0x9E37_79B9_7F4A_7C15
            ^ UInt64(template.index &+ 1) &* 0xBF58_476D_1CE4_E5B9
            ^ (scopeID ?? 0) &* 0x94D0_49BB_1331_11EB
            ^ nextSeed
        nextSeed &+= 1
        systems.append(System(
            id: nextSystemID,
            templateIndex: template.index,
            depth: template.depth,
            spawnScopeID: scopeID,
            parentParticleID: parentParticleID,
            emissionCompletionTime: SceneParticleChildLifecycle.emissionCompletionTime(
                template.definition
            ),
            origin: origin,
            simulator: SceneParticleSimulator(
                definition: template.definition,
                seed: seed,
                particleBudget: template.particleBudget
            )
        ))
        nextSystemID &+= 1
    }

    private func makeInstances(for template: SceneParticleChildTemplate) -> [SceneParticleGPUInstance] {
        systems.lazy.filter { $0.templateIndex == template.index }.flatMap { system in
            system.simulator.particles.map { particle in
                template.instance(origin: system.origin, particle: particle, layerAlpha: layerAlpha)
            }
        }
    }

    private func depthSystemCount(_ depth: Int) -> Int {
        systems.lazy.filter { $0.depth == depth }.count
    }

    private func templatePath(at index: Int) -> String? {
        templates.first { $0.index == index }?.path
    }

    private static func accepts(
        event: SceneParticleState,
        template: SceneParticleChildTemplate,
        scopeID: UInt64?
    ) -> Bool {
        guard template.probability < 1 else { return true }
        var random = SceneParticleRandomGenerator(
            state: event.id ^ UInt64(template.index &+ 1) &* 0x94D0_49BB_1331_11EB
                ^ (scopeID ?? 0) &* 0xBF58_476D_1CE4_E5B9
        )
        return random.unit() < template.probability
    }

    private static func budgetDetail(depth: Int) -> String {
        depth <= 1
            ? "aggregateSystemBudget:systems=\(maximumSystemsPerDepth):particleCapacity="
            + "\(maximumSystemsPerDepth * maximumParticlesPerSystem)"
            : "nestedAggregateSystemBudget:depth=2:systems=\(maximumSystemsPerDepth)"
            + ":particleCapacity=\(maximumSystemsPerDepth * maximumParticlesPerSystem)"
    }
}
