import Foundation
import Metal

/// Executes strict children up to depth two. Unsupported declarations stay diagnostic.
final class SceneParticleChildRuntime {
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
        worldSpaceFrame: SceneParticleWorldSpaceFrame?
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
            worldSpaceFrame: worldSpaceFrame
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
                origin: template.staticOrigin,
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
        parentParticles: [SceneParticleState]
    ) -> SceneParticleChildAdvanceResult {
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
            var instances = instanceScratch.removeValue(forKey: template.index) ?? []
            rebuildInstances(for: template, into: &instances)
            instanceScratch[template.index] = instances
            guard !instances.isEmpty else { continue }
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
                blendMode: template.blendMode,
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

    /// Advances depth-one systems against the root simulator and collects the per-system
    /// event frames that feed nested children, before completed systems are recycled.
    private func advanceDepthOne(
        by frameDelta: TimeInterval,
        rootParticles: [SceneParticleState]
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
            }
            systems[index].simulator.advance(by: frameDelta)
            let births = systems[index].simulator.consumeBirthEvents()
            let deaths = systems[index].simulator.consumeDeathEvents()
            updateWorldSpaceOrigins(systemAt: index, births: births, deaths: deaths)
            guard let path = templates.first(where: {
                $0.index == systems[index].templateIndex
            })?.path,
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
                      SceneParticleChildLifecycle.accepts(event: event, template: template, scopeID: scopeID)
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
                      SceneParticleChildLifecycle.accepts(event: parent, template: template, scopeID: scopeID)
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
                emissionDeadline: template.trigger == .follow ? nil : completion
            )
        ))
        nextSystemID &+= 1
    }

    private func rebuildInstances(
        for template: SceneParticleChildTemplate,
        into instances: inout [SceneParticleGPUInstance]
    ) {
        instances.removeAll(keepingCapacity: true)
        let matchingSystems = systems.lazy.filter { $0.templateIndex == template.index }
        instances.reserveCapacity(matchingSystems.reduce(0) {
            $0 + $1.simulator.particles.count
        })
        for system in matchingSystems {
            for particle in system.simulator.particles {
                instances.append(template.instance(
                    origin: template.definition.flags.isWorldSpace
                        ? system.particleOrigins[particle.id] ?? system.origin
                        : system.origin,
                    particle: particle,
                    layerAlpha: layerAlpha
                ))
            }
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

    private func depthSystemCount(_ depth: Int) -> Int { systems.lazy.filter { $0.depth == depth }.count }

    private static func budgetDetail(depth: Int) -> String {
        depth <= 1
            ? "aggregateSystemBudget:systems=\(maximumSystemsPerDepth):particleCapacity="
            + "\(maximumSystemsPerDepth * maximumParticlesPerSystem)"
            : "nestedAggregateSystemBudget:depth=2:systems=\(maximumSystemsPerDepth)"
            + ":particleCapacity=\(maximumSystemsPerDepth * maximumParticlesPerSystem)"
    }
}
