import Foundation
import Metal

/// Executes the strict, depth-one eventspawn profile. Unsupported child declarations stay diagnostic.
final class SceneParticleChildRuntime {
    struct AdvanceResult {
        let batches: [SceneParticleDrawBatch]
        let bufferFailurePaths: [String]
    }

    private struct Template {
        let index: Int
        let path: String
        let definition: SceneParticleDefinition
        let texture: MTLTexture
        let blendMode: SceneParticlePipelineBlendMode
        let spriteAnimation: SceneSpriteAnimation?
        let orientation: SceneParticleOrientation
        let orientationAxis: SIMD3<Float>?
        let usesPerspective: Bool
        let probability: Double
        let maximumSystemCount: Int
        let instanceBuffer = SceneParticleMetalInstanceBuffer()
    }

    private struct System {
        let templateIndex: Int
        let origin: SIMD3<Double>
        var simulator: SceneParticleSimulator
    }

    let unsupportedDetails: [String]
    let handlesAllChildren: Bool
    var hasTemplates: Bool { !templates.isEmpty }

    private let layerID: Int
    private let layerAlpha: Float
    private let device: MTLDevice
    private let templates: [Template]
    private var systems: [System] = []
    private var nextSeed: UInt64 = 0

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

        for (index, child) in rootAsset.definition.children.enumerated() {
            let label = child.path ?? "child#\(index)"
            guard child.type?.lowercased() == "eventspawn" else {
                unsupported.append("\(label):unsupportedType:\(child.type ?? "missing")")
                continue
            }
            guard Self.hasIdentityTransform(child),
                  child.controlPointStartIndex == nil,
                  child.rawFlags == 0 else {
                unsupported.append("\(label):unsupportedTransformOrControlPoint")
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
                  Self.hasStrictInstantaneousEmitter(asset.definition),
                  !asset.definition.flags.isWorldSpace,
                  !asset.definition.renderers.contains(where: \.isWorldSpace),
                  let renderer = Self.spriteRenderer(in: asset.definition) else {
                unsupported.append("\(path):outsideStrictEventspawnProfile")
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
            let probability = child.probability ?? 1
            guard probability.isFinite, (0...1).contains(probability) else {
                unsupported.append("\(path):invalidProbability")
                continue
            }
            guard let maximum = child.maximumCount, maximum > 0, maximum <= 512 else {
                unsupported.append("\(path):invalidSystemLimit")
                continue
            }
            accepted.append(Template(
                index: index,
                path: path,
                definition: asset.definition,
                texture: loaded.texture,
                blendMode: asset.blendMode == .additive ? .additive : .translucent,
                spriteAnimation: loaded.animation,
                orientation: SceneParticleOrientation(authoredValue: renderer.orientation),
                orientationAxis: renderer.axis.map {
                    SceneParticleSimulationMath.vector($0, fallback: SIMD3(0, 0, 1)).childFloatValue
                },
                usesPerspective: asset.definition.flags.usesPerspective,
                probability: probability,
                maximumSystemCount: maximum
            ))
        }
        templates = accepted
        unsupportedDetails = unsupported
        handlesAllChildren = accepted.count == rootAsset.definition.children.count
    }

    func advance(by frameDelta: TimeInterval, spawnEvents: [SceneParticleState]) -> AdvanceResult {
        for index in systems.indices { systems[index].simulator.advance(by: frameDelta) }
        systems.removeAll { $0.simulator.simulationTime > 0 && $0.simulator.particles.isEmpty }
        spawn(from: spawnEvents)

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
        return AdvanceResult(batches: batches, bufferFailurePaths: failures)
    }

    private func spawn(from events: [SceneParticleState]) {
        guard !events.isEmpty else { return }
        for event in events {
            for template in templates {
                let activeCount = systems.lazy.filter { $0.templateIndex == template.index }.count
                guard activeCount < template.maximumSystemCount,
                      Self.accepts(event: event, template: template) else { continue }
                let seed = UInt64(bitPattern: Int64(layerID))
                    ^ event.id &* 0x9E3779B97F4A7C15
                    ^ UInt64(template.index &+ 1) &* 0xBF58476D1CE4E5B9
                    ^ nextSeed
                nextSeed &+= 1
                systems.append(System(
                    templateIndex: template.index,
                    origin: event.position,
                    simulator: SceneParticleSimulator(definition: template.definition, seed: seed)
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

    private static func hasStrictInstantaneousEmitter(_ definition: SceneParticleDefinition) -> Bool {
        !definition.emitters.isEmpty && definition.emitters.allSatisfy {
            ($0.instantaneousCount ?? 0) > 0 && ($0.rate ?? 0) == 0
        }
    }

    private static func spriteRenderer(in definition: SceneParticleDefinition) -> SceneParticleRenderer? {
        definition.renderers.first {
            if case .sprite = $0.kind { return true }
            return false
        }
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
