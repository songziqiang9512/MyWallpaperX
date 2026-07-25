import Foundation
import Metal

/// Executes strict depth-one event-triggered children. Unsupported declarations stay diagnostic.
final class SceneParticleChildRuntime {
    private enum Trigger: Equatable {
        case spawn
        case death
        case follow
    }

    struct AdvanceResult {
        let batches: [SceneParticleDrawBatch]
        let bufferFailurePaths: [String]
        let limitationDetails: [String]
    }

    private struct Template {
        let index: Int
        let path: String
        let definition: SceneParticleDefinition
        let trigger: Trigger
        let trail: SceneParticleTrailRenderPlan?
        let texture: MTLTexture
        let blendMode: SceneParticlePipelineBlendMode
        let spriteAnimation: SceneSpriteAnimation?
        let orientation: SceneParticleOrientation
        let orientationAxis: SIMD3<Float>?
        let usesPerspective: Bool
        let probability: Double
        let maximumSystemCount: Int
        let particleBudget: Int
        let instanceBuffer = SceneParticleMetalInstanceBuffer()
    }

    private struct System {
        let templateIndex: Int
        let parentParticleID: UInt64?
        let emissionCompletionTime: Double?
        var origin: SIMD3<Double>
        var simulator: SceneParticleSimulator
    }

    let unsupportedDetails: [String]
    let performanceDetails: [String]
    let handlesAllChildren: Bool
    var hasTemplates: Bool { !templates.isEmpty }

    private let layerID: Int
    private let layerAlpha: Float
    private let device: MTLDevice
    private let templates: [Template]
    private var systems: [System] = []
    private var nextSeed: UInt64 = 0

    // Child systems run on the CPU fallback; cap burst spikes while retaining authored distribution.
    private static let maximumParticlesPerSystem = 1_024
    private static let maximumChildSystems = 64

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
        var accepted: [Template] = []
        var unsupported: [String] = []
        var performance: [String] = []
        var handledChildren = 0

        for (index, child) in rootAsset.definition.children.enumerated() {
            let label = child.path ?? "child#\(index)"
            let trigger: Trigger
            switch child.type?.lowercased() {
            case "eventspawn": trigger = .spawn
            case "eventdeath": trigger = .death
            case "eventfollow": trigger = .follow
            default:
                unsupported.append("\(label):unsupportedType:\(child.type ?? "missing")")
                continue
            }
            guard Self.hasIdentityTransform(child),
                  child.controlPointStartIndex == nil,
                  child.rawFlags == 0 else {
                unsupported.append("\(label):unsupportedTransformOrControlPoint")
                continue
            }
            let probability = child.probability ?? 1
            guard probability.isFinite, (0...1).contains(probability) else {
                unsupported.append("\(label):invalidProbability")
                continue
            }
            if probability == 0 {
                handledChildren += 1
                continue
            }
            guard let rawPath = child.path else {
                unsupported.append("child#\(index):missingPath")
                continue
            }
            let path = SceneParticleAssetGraphLoader.normalizedPath(rawPath)
            guard let asset = graph.assetsByPath[path] else {
                unsupported.append("\(path):missingAsset")
                continue
            }
            guard asset.definition.children.isEmpty,
                  SceneParticleChildLifecycle.supportsEmitterProfile(asset.definition),
                  let render = Self.supportedRenderer(in: asset.definition) else {
                unsupported.append("\(path):outsideStrictEventProfile")
                continue
            }
            guard let source = asset.textureSource,
                  let loaded = Self.loadTexture(
                    source,
                    textureLoader: textureLoader,
                    builtInTextureRegistry: builtInTextureRegistry,
                    device: device
                  ) else {
                unsupported.append("\(path):textureLoadFailed")
                continue
            }
            let maximum = child.maximumCount ?? 512
            guard maximum > 0, maximum <= 512 else {
                unsupported.append("\(path):invalidSystemLimit")
                continue
            }
            let authoredMaximum = min(max(asset.definition.maximumCount ?? 1, 0), 20_000)
            let particleBudget = min(authoredMaximum, Self.maximumParticlesPerSystem)
            if particleBudget < authoredMaximum {
                let instantaneous = asset.definition.emitters.map { $0.instantaneousCount ?? 0 }.max() ?? 0
                performance.append(
                    "\(path):particleBudget:max=\(authoredMaximum):instantaneous=\(instantaneous):effective=\(particleBudget)"
                )
            }
            accepted.append(Template(
                index: index,
                path: path,
                definition: asset.definition,
                trigger: trigger,
                trail: render.trail,
                texture: loaded.texture,
                blendMode: asset.blendMode == .additive ? .additive : .translucent,
                spriteAnimation: loaded.animation,
                orientation: SceneParticleOrientation(authoredValue: render.renderer.orientation),
                orientationAxis: render.renderer.axis.map {
                    SceneParticleSimulationMath.vector($0, fallback: SIMD3(0, 0, 1)).childFloatValue
                },
                usesPerspective: asset.definition.flags.usesPerspective,
                probability: probability,
                maximumSystemCount: maximum,
                particleBudget: particleBudget
            ))
            handledChildren += 1
        }
        templates = accepted
        unsupportedDetails = unsupported
        performanceDetails = performance
        handlesAllChildren = handledChildren == rootAsset.definition.children.count
    }

    func advance(
        by frameDelta: TimeInterval,
        spawnEvents: [SceneParticleState],
        deathEvents: [SceneParticleState],
        parentParticles: [SceneParticleState]
    ) -> AdvanceResult {
        var limitations: Set<String> = []
        let parentsByID: [UInt64: SceneParticleState] = templates.contains { $0.trigger == .follow }
            ? Dictionary(uniqueKeysWithValues: parentParticles.map { ($0.id, $0) })
            : [:]
        systems.removeAll { system in
            guard let parentID = system.parentParticleID else { return false }
            return parentsByID[parentID] == nil
        }
        for index in systems.indices {
            if let parentID = systems[index].parentParticleID,
               let parent = parentsByID[parentID] {
                systems[index].origin = parent.position
            }
            systems[index].simulator.advance(by: frameDelta)
            _ = systems[index].simulator.consumeBirthEvents()
            _ = systems[index].simulator.consumeDeathEvents()
        }
        systems.removeAll {
            $0.parentParticleID == nil
                && $0.simulator.simulationTime > 0
                && $0.emissionCompletionTime != nil
                && $0.simulator.simulationTime + 1e-12 >= ($0.emissionCompletionTime ?? .infinity)
                && $0.simulator.particles.isEmpty
        }
        spawn(from: spawnEvents, trigger: .spawn, limitations: &limitations)
        spawn(from: deathEvents, trigger: .death, limitations: &limitations)
        reconcileFollowers(parentParticles, limitations: &limitations)

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

    private func spawn(
        from events: [SceneParticleState],
        trigger: Trigger,
        limitations: inout Set<String>
    ) {
        guard !events.isEmpty else { return }
        for event in events {
            for template in templates {
                guard template.trigger == trigger else { continue }
                let activeCount = systems.lazy.filter { $0.templateIndex == template.index }.count
                guard activeCount < template.maximumSystemCount,
                      Self.accepts(event: event, template: template) else { continue }
                guard systems.count < Self.maximumChildSystems else {
                    limitations.insert(Self.aggregateBudgetDetail)
                    continue
                }
                let seed = UInt64(bitPattern: Int64(layerID))
                    ^ event.id &* 0x9E3779B97F4A7C15
                    ^ UInt64(template.index &+ 1) &* 0xBF58476D1CE4E5B9
                    ^ nextSeed
                nextSeed &+= 1
                systems.append(System(
                    templateIndex: template.index,
                    parentParticleID: nil,
                    emissionCompletionTime: SceneParticleChildLifecycle.emissionCompletionTime(
                        template.definition
                    ),
                    origin: event.position,
                    simulator: SceneParticleSimulator(
                        definition: template.definition,
                        seed: seed,
                        particleBudget: template.particleBudget
                    )
                ))
            }
        }
    }

    private func reconcileFollowers(
        _ parents: [SceneParticleState],
        limitations: inout Set<String>
    ) {
        guard !parents.isEmpty else { return }
        for template in templates where template.trigger == .follow {
            var followedIDs = Set(systems.lazy.compactMap { system in
                system.templateIndex == template.index ? system.parentParticleID : nil
            })
            for parent in parents {
                guard !followedIDs.contains(parent.id),
                      followedIDs.count < template.maximumSystemCount,
                      Self.accepts(event: parent, template: template) else { continue }
                guard systems.count < Self.maximumChildSystems else {
                    limitations.insert(Self.aggregateBudgetDetail)
                    continue
                }
                followedIDs.insert(parent.id)
                let seed = UInt64(bitPattern: Int64(layerID))
                    ^ parent.id &* 0x9E3779B97F4A7C15
                    ^ UInt64(template.index &+ 1) &* 0xBF58476D1CE4E5B9
                    ^ nextSeed
                nextSeed &+= 1
                systems.append(System(
                    templateIndex: template.index,
                    parentParticleID: parent.id,
                    emissionCompletionTime: SceneParticleChildLifecycle.emissionCompletionTime(
                        template.definition
                    ),
                    origin: parent.position,
                    simulator: SceneParticleSimulator(
                        definition: template.definition,
                        seed: seed,
                        particleBudget: template.particleBudget
                    )
                ))
            }
        }
    }

    private func makeInstances(for template: Template) -> [SceneParticleGPUInstance] {
        systems.lazy.filter { $0.templateIndex == template.index }.flatMap { system in
            system.simulator.particles.map { particle in
                let frames = SceneParticleRuntime.spriteFrames(
                    animation: template.spriteAnimation,
                    definition: template.definition,
                    particleID: particle.id,
                    age: Float(particle.age),
                    lifetime: Float(particle.lifetime)
                )
                return SceneParticleGPUInstance(
                    position: (system.origin + particle.position).childFloatValue,
                    size: Float(particle.size),
                    rotation: particle.rotation.childFloatValue,
                    color: particle.color.childFloatValue,
                    alpha: Float(particle.alpha) * layerAlpha,
                    velocity: particle.velocity.childFloatValue,
                    trailStretch: template.trail?.stretch(for: particle.velocity),
                    currentFrame: frames.current,
                    nextFrame: frames.next,
                    frameMix: frames.mix
                )
            }
        }
    }

    private static func accepts(event: SceneParticleState, template: Template) -> Bool {
        guard template.probability < 1 else { return true }
        var random = SceneParticleRandomGenerator(
            state: event.id ^ UInt64(template.index &+ 1) &* 0x94D049BB133111EB
        )
        return random.unit() < template.probability
    }

    private static func hasIdentityTransform(_ child: SceneParticleChild) -> Bool {
        let origin = SceneParticleSimulationMath.vector(child.origin, fallback: .zero)
        let angles = SceneParticleSimulationMath.vector(child.angles, fallback: .zero)
        let scale = SceneParticleSimulationMath.vector(child.scale, fallback: SIMD3(repeating: 1))
        return origin == .zero && angles == .zero && scale == SIMD3(repeating: 1)
    }

    private static var aggregateBudgetDetail: String {
        "aggregateSystemBudget:systems=\(maximumChildSystems):particleCapacity="
            + "\(maximumChildSystems * maximumParticlesPerSystem)"
    }

    private static func supportedRenderer(
        in definition: SceneParticleDefinition
    ) -> (renderer: SceneParticleRenderer, trail: SceneParticleTrailRenderPlan?)? {
        for renderer in definition.renderers {
            switch renderer.kind {
            case .sprite:
                return (renderer, nil)
            case .spriteTrail:
                guard let trail = SceneParticleTrailRenderPlan(
                    length: renderer.length,
                    minimumLength: renderer.minimumLength,
                    maximumLength: renderer.maximumLength
                ) else { continue }
                return (renderer, trail)
            default:
                continue
            }
        }
        return nil
    }

    private static func loadTexture(
        _ source: SceneParticleTextureSource,
        textureLoader: SceneTextureLoader,
        builtInTextureRegistry: SceneParticleBuiltInTextureRegistry,
        device: MTLDevice
    ) -> (texture: MTLTexture, animation: SceneSpriteAnimation?)? {
        switch source {
        case let .file(url):
            guard case let .loaded(texture) = textureLoader.load(from: url, device: device) else {
                return nil
            }
            return (texture, SceneSpriteAnimation.load(from: url))
        case let .builtIn(key):
            guard let texture = builtInTextureRegistry.texture(for: key) else { return nil }
            return (texture, nil)
        }
    }
}

private extension SIMD3 where Scalar == Double {
    var childFloatValue: SIMD3<Float> { SIMD3<Float>(Float(x), Float(y), Float(z)) }
}
