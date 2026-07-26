import Foundation
import Metal

enum SceneParticleRuntimeDiagnosticKind: String, Codable, Sendable {
    case missingDefinition
    case invalidDefinition
    case cyclicChildReference
    case missingMaterial
    case unsupportedShader
    case missingTextureReference
    case missingTextureFile
    case builtInTextureUnavailable
    case unsupportedBlendMode
    case refractionUnsupported
    case missingSpriteRenderer
    case worldSpaceUnsupported
    case trailRendererUnsupported
    case ropeRendererUnsupported
    case childSystemsUnsupported
    case textureLoadFailed
    case simulationLimitation
    case instanceBufferAllocationFailed
}

struct SceneParticleRuntimeDiagnostic: Codable, Equatable, Hashable, Sendable {
    let kind: SceneParticleRuntimeDiagnosticKind
    let layerID: Int?
    let particlePath: String
    let detail: String?
}

struct SceneParticleDrawBatch {
    let layerID: Int
    let particlePath: String
    let texture: MTLTexture
    let blendMode: SceneParticlePipelineBlendMode
    let instanceBuffer: SceneParticleMetalInstanceBuffer
    let instances: [SceneParticleGPUInstance]
    let orientation: SceneParticleOrientation
    let orientationAxis: SIMD3<Float>?
    let usesPerspective: Bool
}

/// Owns the CPU state and GPU instance buffers for effectively visible particle layers.
/// Particle positions and sizes stay in the author-defined layer-local coordinate system.
/// The renderer applies the layer world frame, Y-axis convention, and layer scale once.
final class SceneParticleRuntime {
    private struct LayerRuntime {
        let layerID: Int
        let particlePath: String
        let definition: SceneParticleDefinition
        let trail: SceneParticleTrailRenderPlan?
        let texture: MTLTexture
        let blendMode: SceneParticlePipelineBlendMode
        let spriteAnimation: SceneSpriteAnimation?
        let orientation: SceneParticleOrientation
        let orientationAxis: SIMD3<Float>?
        let usesPerspective: Bool
        let layerAlpha: Float
        let instanceBuffer = SceneParticleMetalInstanceBuffer()
        var simulator: SceneParticleSimulator
        var childRuntime: SceneParticleChildRuntime?
    }

    private let device: MTLDevice
    private var layers: [LayerRuntime] = []
    private(set) var diagnostics: [SceneParticleRuntimeDiagnostic] = []

    var activeLayerIDs: [Int] { layers.map(\.layerID) }

    init(
        descriptor: SceneRenderDescriptor,
        cacheDirectory: URL,
        device: MTLDevice,
        stockTextureBundleURL: URL? = SceneStockTextureResolver.defaultBundleRoot()
    ) {
        self.device = device
        let visibleIDs = SceneLayerVisibility.visibleLayerIDs(in: descriptor)
        let particleLayers = Self.orderedLayers(in: descriptor).filter {
            visibleIDs.contains($0.id) && $0.contentKind == "particle" && $0.particlePath != nil
        }
        let materialPasses = descriptor.materialPasses.map {
            SceneParticleMaterialPass(
                materialPath: $0.materialPath,
                shaderPath: $0.shaderPath,
                texturePaths: $0.texturePaths,
                blending: $0.blending,
                combos: $0.combos
            )
        }
        let graph = SceneParticleAssetGraphLoader(
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

        let textureLoader = SceneTextureLoader()
        let builtInTextureRegistry = SceneParticleBuiltInTextureRegistry(device: device)
        for layer in particleLayers {
            guard let rawPath = layer.particlePath else { continue }
            let path = SceneParticleAssetGraphLoader.normalizedPath(rawPath)
            guard let asset = graph.assetsByPath[path] else { continue }
            guard let render = supportedRenderer(
                in: asset.definition,
                layerID: layer.id,
                path: path
            ) else { continue }
            guard !asset.definition.flags.isWorldSpace,
                  !asset.definition.renderers.contains(where: \.isWorldSpace) else {
                addDiagnostic(kind: .worldSpaceUnsupported, layerID: layer.id, path: path)
                continue
            }
            guard let textureSource = asset.textureSource else { continue }
            let texture: MTLTexture
            let spriteAnimation: SceneSpriteAnimation?
            switch textureSource {
            case let .file(textureURL):
                let outcome = textureLoader.load(from: textureURL, device: device)
                guard case let .loaded(loadedTexture) = outcome else {
                    addDiagnostic(
                        kind: .textureLoadFailed,
                        layerID: layer.id,
                        path: path,
                        detail: Self.textureFailureDescription(outcome)
                    )
                    continue
                }
                texture = SceneParticleColorTextureAdapter.adapt(loadedTexture, device: device)
                spriteAnimation = SceneSpriteAnimation.load(from: textureURL)
            case let .builtIn(key):
                guard let loadedTexture = builtInTextureRegistry.texture(for: key) else {
                    addDiagnostic(
                        kind: .textureLoadFailed,
                        layerID: layer.id,
                        path: path,
                        detail: "builtInTextureAllocationFailed:\(key.rawValue)"
                    )
                    continue
                }
                texture = loadedTexture
                spriteAnimation = nil
            }

            let simulator = SceneParticleSimulator(
                definition: asset.definition,
                instanceOverride: layer.particleInstanceOverride,
                seed: UInt64(bitPattern: Int64(layer.id))
            )
            let childRuntime = SceneParticleChildRuntime(
                layerID: layer.id,
                rootAsset: asset,
                graph: graph,
                layerAlpha: Float(min(max(layer.alpha ?? 1, 0), 1)),
                textureLoader: textureLoader,
                builtInTextureRegistry: builtInTextureRegistry,
                device: device
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
            appendSimulationDiagnostics(
                simulator.diagnostics,
                layerID: layer.id,
                path: path,
                handlesAllChildren: childRuntime.handlesAllChildren
            )
            layers.append(LayerRuntime(
                layerID: layer.id,
                particlePath: path,
                definition: asset.definition,
                trail: render.trail,
                texture: texture,
                blendMode: asset.blendMode == .additive ? .additive : .translucent,
                spriteAnimation: spriteAnimation,
                orientation: SceneParticleOrientation(authoredValue: render.renderer.orientation),
                orientationAxis: render.renderer.axis.map {
                    SceneParticleSimulationMath.vector($0, fallback: SIMD3(0, 0, 1)).floatValue
                },
                usesPerspective: asset.definition.flags.usesPerspective,
                layerAlpha: Float(min(max(layer.alpha ?? 1, 0), 1)),
                simulator: simulator,
                childRuntime: childRuntime.hasTemplates ? childRuntime : nil
            ))
        }
    }

    /// Advances every active layer by the frame delta and returns batches in scene render order.
    func advance(by frameDelta: TimeInterval) -> [SceneParticleDrawBatch] {
        var batches: [SceneParticleDrawBatch] = []
        for index in layers.indices {
            layers[index].simulator.advance(by: frameDelta)
            let births = layers[index].simulator.consumeBirthEvents()
            let deaths = layers[index].simulator.consumeDeathEvents()
            if let childRuntime = layers[index].childRuntime {
                let result = childRuntime.advance(
                    by: frameDelta,
                    spawnEvents: births,
                    deathEvents: deaths,
                    parentParticles: layers[index].simulator.particles
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
            let instances = makeGPUInstances(for: layers[index])
            guard layers[index].instanceBuffer.update(device: device, instances: instances) else {
                addDiagnostic(
                    kind: .instanceBufferAllocationFailed,
                    layerID: layers[index].layerID,
                    path: layers[index].particlePath
                )
                continue
            }
            batches.append(SceneParticleDrawBatch(
                layerID: layers[index].layerID,
                particlePath: layers[index].particlePath,
                texture: layers[index].texture,
                blendMode: layers[index].blendMode,
                instanceBuffer: layers[index].instanceBuffer,
                instances: instances,
                orientation: layers[index].orientation,
                orientationAxis: layers[index].orientationAxis,
                usesPerspective: layers[index].usesPerspective
            ))
        }
        return batches
    }

    private func makeGPUInstances(for layer: LayerRuntime) -> [SceneParticleGPUInstance] {
        layer.simulator.particles.map { particle in
            let frames = Self.spriteFrames(
                animation: layer.spriteAnimation,
                definition: layer.definition,
                particleID: particle.id,
                age: Float(particle.age),
                lifetime: Float(particle.lifetime)
            )
            return SceneParticleGPUInstance(
                position: particle.position.floatValue,
                size: Float(particle.size),
                rotation: particle.rotation.floatValue,
                color: particle.color.floatValue,
                alpha: Float(particle.alpha) * layer.layerAlpha,
                velocity: particle.velocity.floatValue,
                trailStretch: layer.trail?.stretch(for: particle.velocity),
                currentFrame: frames.current,
                nextFrame: frames.next,
                frameMix: frames.mix
            )
        }
    }

    func addDiagnostic(
        kind: SceneParticleRuntimeDiagnosticKind,
        layerID: Int?,
        path: String,
        detail: String? = nil
    ) {
        let value = SceneParticleRuntimeDiagnostic(
            kind: kind,
            layerID: layerID,
            particlePath: path,
            detail: detail
        )
        if !diagnostics.contains(value) { diagnostics.append(value) }
    }

}

private extension SIMD3 where Scalar == Double {
    var floatValue: SIMD3<Float> { SIMD3<Float>(Float(x), Float(y), Float(z)) }
}
