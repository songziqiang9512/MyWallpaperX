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
        let texture: MTLTexture
        let blendMode: SceneParticlePipelineBlendMode
        let spriteAnimation: SceneSpriteAnimation?
        let orientation: SceneParticleOrientation
        let orientationAxis: SIMD3<Float>?
        let usesPerspective: Bool
        let layerAlpha: Float
        let instanceBuffer = SceneParticleMetalInstanceBuffer()
        var simulator: SceneParticleSimulator
    }

    private let device: MTLDevice
    private var layers: [LayerRuntime] = []
    private(set) var diagnostics: [SceneParticleRuntimeDiagnostic] = []

    var activeLayerIDs: [Int] { layers.map(\.layerID) }

    init(
        descriptor: SceneRenderDescriptor,
        cacheDirectory: URL,
        device: MTLDevice
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
                blending: $0.blending
            )
        }
        let graph = SceneParticleAssetGraphLoader().load(
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
            guard let sprite = supportedSpriteRenderer(
                in: asset.definition,
                layerID: layer.id,
                path: path
            ) else { continue }
            guard !asset.definition.flags.isWorldSpace,
                  !asset.definition.renderers.contains(where: \.isWorldSpace) else {
                addDiagnostic(kind: .worldSpaceUnsupported, layerID: layer.id, path: path)
                continue
            }
            if !asset.definition.children.isEmpty {
                addDiagnostic(kind: .childSystemsUnsupported, layerID: layer.id, path: path)
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
                texture = loadedTexture
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
            appendSimulationDiagnostics(simulator.diagnostics, layerID: layer.id, path: path)
            layers.append(LayerRuntime(
                layerID: layer.id,
                particlePath: path,
                definition: asset.definition,
                texture: texture,
                blendMode: asset.blendMode == .additive ? .additive : .translucent,
                spriteAnimation: spriteAnimation,
                orientation: SceneParticleOrientation(authoredValue: sprite.orientation),
                orientationAxis: sprite.axis.map {
                    SceneParticleSimulationMath.vector($0, fallback: SIMD3(0, 0, 1)).floatValue
                },
                usesPerspective: asset.definition.flags.usesPerspective,
                layerAlpha: Float(min(max(layer.alpha ?? 1, 0), 1)),
                simulator: simulator
            ))
        }
    }

    /// Advances every active layer by the frame delta and returns batches in scene render order.
    func advance(by frameDelta: TimeInterval) -> [SceneParticleDrawBatch] {
        var batches: [SceneParticleDrawBatch] = []
        for index in layers.indices {
            layers[index].simulator.advance(by: frameDelta)
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
            let frames = spriteFrames(
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
                currentFrame: frames.current,
                nextFrame: frames.next,
                frameMix: frames.mix
            )
        }
    }

    private func spriteFrames(
        animation: SceneSpriteAnimation?,
        definition: SceneParticleDefinition,
        particleID: UInt64,
        age: Float,
        lifetime: Float
    ) -> (current: SceneParticleFrameTransform, next: SceneParticleFrameTransform?, mix: Float) {
        guard let animation,
              let selection = SceneParticleSpriteFrameSelector.select(
                mode: SceneParticleSpriteAnimationMode(authoredValue: definition.animationMode),
                frameDurations: animation.frames.map(\.duration),
                age: age,
                lifetime: lifetime,
                sequenceMultiplier: Float(definition.sequenceMultiplier ?? 1),
                particleID: particleID,
                blendsFrames: !definition.flags.disablesFrameBlending
              ) else {
            return (.identity, nil, 0)
        }
        return (
            Self.frameTransform(animation.frames[selection.currentIndex]),
            Self.frameTransform(animation.frames[selection.nextIndex]),
            selection.mix
        )
    }

    private func supportedSpriteRenderer(
        in definition: SceneParticleDefinition,
        layerID: Int,
        path: String
    ) -> SceneParticleRenderer? {
        var sprite: SceneParticleRenderer?
        for renderer in definition.renderers {
            switch renderer.kind {
            case .sprite:
                if sprite == nil { sprite = renderer }
            case .spriteTrail:
                addDiagnostic(kind: .trailRendererUnsupported, layerID: layerID, path: path, detail: "spritetrail")
            case .rope:
                addDiagnostic(kind: .ropeRendererUnsupported, layerID: layerID, path: path, detail: "rope")
            case .ropeTrail:
                addDiagnostic(kind: .trailRendererUnsupported, layerID: layerID, path: path, detail: "ropetrail")
            case let .unsupported(name):
                addDiagnostic(kind: .missingSpriteRenderer, layerID: layerID, path: path, detail: name)
            }
        }
        if sprite == nil {
            addDiagnostic(kind: .missingSpriteRenderer, layerID: layerID, path: path)
        }
        return sprite
    }

    private func appendSimulationDiagnostics(
        _ values: [SceneParticleSimulationDiagnostic],
        layerID: Int,
        path: String
    ) {
        for value in values {
            switch value.kind {
            case .trailRendererIgnored:
                addDiagnostic(kind: .trailRendererUnsupported, layerID: layerID, path: path, detail: value.componentName)
            case .unsupportedRenderer:
                addDiagnostic(kind: .ropeRendererUnsupported, layerID: layerID, path: path, detail: value.componentName)
            case .childSystemsIgnored:
                addDiagnostic(kind: .childSystemsUnsupported, layerID: layerID, path: path, detail: value.componentName)
            default:
                let detail = [value.kind.rawValue, value.componentName].compactMap { $0 }.joined(separator: ":")
                addDiagnostic(kind: .simulationLimitation, layerID: layerID, path: path, detail: detail)
            }
        }
    }

    private func addDiagnostic(
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

    private static func orderedLayers(in descriptor: SceneRenderDescriptor) -> [SceneRenderDescriptor.Layer] {
        let byID = Dictionary(uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0) })
        var seen: Set<Int> = []
        let ordered = descriptor.renderOrderLayerIDs.compactMap { id -> SceneRenderDescriptor.Layer? in
            guard seen.insert(id).inserted else { return nil }
            return byID[id]
        }
        return ordered + descriptor.layers.filter { seen.insert($0.id).inserted }
    }

    private static func runtimeKind(
        _ value: SceneParticleAssetDiagnostic.Kind
    ) -> SceneParticleRuntimeDiagnosticKind {
        SceneParticleRuntimeDiagnosticKind(rawValue: value.rawValue) ?? .missingDefinition
    }

    private static func frameTransform(
        _ frame: SceneTexContainer.SpriteFrame
    ) -> SceneParticleFrameTransform {
        SceneParticleFrameTransform(origin: frame.origin, xAxis: frame.xAxis, yAxis: frame.yAxis)
    }

    private static func textureFailureDescription(_ outcome: SceneTextureLoadOutcome) -> String {
        switch outcome {
        case .loaded: "loaded"
        case let .unsupportedFormat(value): "unsupportedFormat:\(value)"
        case let .unsupportedTexFormat(value): "unsupportedTexFormat:\(value)"
        case .texNoEmbeddedImage: "texNoEmbeddedImage"
        case .texContainsVideoPayload: "texContainsVideoPayload"
        case let .decodeFailed(value): "decodeFailed:\(value)"
        case let .textureAllocationFailed(width, height): "textureAllocationFailed:\(width)x\(height)"
        }
    }
}

private extension SIMD3 where Scalar == Double {
    var floatValue: SIMD3<Float> { SIMD3<Float>(Float(x), Float(y), Float(z)) }
}
