import Foundation
import Metal

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
        let colorUVScale: SIMD2<Float>
        let colorSampling: SceneParticleTextureSampling
        let refraction: SceneParticleRefractionBinding?
        let blendMode: SceneParticlePipelineBlendMode
        let spriteAnimation: SceneSpriteAnimation?
        let orientation: SceneParticleOrientation
        let orientationAxis: SIMD3<Float>?
        let usesPerspective: Bool
        let layerAlpha: Float
        let instanceBuffer = SceneParticleMetalInstanceBuffer()
        var instances: [SceneParticleGPUInstance] = []
        var simulator: SceneParticleSimulator
        var ropeTrailHistory: SceneParticleRopeTrailHistory?
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
        resourceView: SceneResourceView? = nil,
        stockTextureBundleURL: URL? = SceneStockTextureResolver.defaultBundleRoot(),
        textureLoader: SceneTextureLoader = SceneTextureLoader(),
        staticWorldSpaceFrames: [Int: SceneParticleWorldSpaceFrame]? = nil
    ) {
        self.device = device
        let staticWorldSpaceFrames = staticWorldSpaceFrames
            ?? descriptor.staticParticleWorldSpaceFrames
        let visibleIDs = SceneLayerVisibility.visibleLayerIDs(in: descriptor)
        let particleLayers = Self.orderedLayers(in: descriptor).filter {
            visibleIDs.contains($0.id)
                && $0.contentKind == "particle"
                && $0.particlePath != nil
                && $0.particleInstanceOverride?.alpha?.isStaticZeroScalar != true
        }
        let materialPasses = descriptor.materialPasses.map {
            SceneParticleMaterialPass(
                materialPath: $0.materialPath,
                passIndex: $0.passIndex,
                shaderPath: $0.shaderPath,
                texturePaths: $0.texturePaths,
                textureSlots: $0.textureSlots,
                blending: $0.blending,
                combos: $0.combos,
                constantValues: $0.constantShaderValues.mapValues {
                    SceneParticleMaterialConstant(
                        components: $0.components ?? [],
                        isStatic: $0.userBinding == nil
                            && $0.timeline == nil
                            && $0.timelineDiagnostics.isEmpty
                    )
                },
                hasUserTextureInputs: !$0.userTextureInputs.isEmpty,
                hasUserShaderValues: !$0.userShaderValues.isEmpty,
                depthTest: $0.depthTest,
                depthWrite: $0.depthWrite,
                cullMode: $0.cullMode,
                alphaWriting: $0.alphaWriting
            )
        }
        let graph = SceneParticleAssetGraphLoader(
            resourceView: resourceView,
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

        let builtInTextureRegistry = SceneParticleBuiltInTextureRegistry(device: device)
        for layer in particleLayers {
            guard let rawPath = layer.particlePath else { continue }
            let path = SceneParticleAssetGraphLoader.normalizedPath(rawPath)
            guard let asset = graph.assetsByPath[path], asset.supportsBuiltInShaderExecution, let blendMode = asset.blendMode else { continue }
            guard let render = supportedRenderer(
                in: asset.definition,
                layerID: layer.id,
                path: path
            ) else { continue }
            let worldSpaceFrame = staticWorldSpaceFrames[layer.id]
            guard !asset.definition.flags.isWorldSpace || worldSpaceFrame != nil else {
                addDiagnostic(
                    kind: .worldSpaceUnsupported,
                    layerID: layer.id,
                    path: path,
                    detail: "dynamicSystemTransform"
                )
                continue
            }
            guard !asset.definition.operators.contains(where: \.isWorldSpaceMovement)
                    || worldSpaceFrame != nil else {
                addDiagnostic(
                    kind: .worldSpaceMovementUnsupported,
                    layerID: layer.id,
                    path: path,
                    detail: "dynamicSystemTransform"
                )
                continue
            }
            guard let textureSource = asset.textureSource else { continue }
            let texture: MTLTexture
            let spriteAnimation: SceneSpriteAnimation?
            let colorUVScale: SIMD2<Float>
            let colorSampling: SceneParticleTextureSampling
            let refraction: SceneParticleRefractionBinding?
            if let declaration = asset.refraction {
                guard let loaded = SceneParticleRefractionTextureLoader.load(
                    colorSource: textureSource,
                    declaration: declaration,
                    textureLoader: textureLoader,
                    device: device
                ) else {
                    addDiagnostic(
                        kind: .refractionUnsupported,
                        layerID: layer.id,
                        path: path,
                        detail: "textureProfileUnsupported"
                    )
                    continue
                }
                texture = loaded.color
                spriteAnimation = loaded.colorAnimation
                colorUVScale = loaded.colorUVScale
                colorSampling = loaded.colorSampling
                refraction = loaded.binding
            } else {
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
                    texture = SceneParticleColorTextureAdapter.adapt(
                        loadedTexture,
                        device: device
                    )
                    let container = textureLoader.texContainer(from: textureURL)
                    spriteAnimation = container.flatMap {
                        SceneSpriteAnimation(frames: $0.spriteFrames)
                    }
                    colorSampling = container.map {
                        SceneParticleTextureSampling(texFlags: $0.flags)
                    } ?? .directImageFallback
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
                    colorSampling = .directImageFallback
                }
                colorUVScale = SIMD2(repeating: 1)
                refraction = nil
            }
            guard supportsRopeTrailTexture(
                plan: render.ropeTrail, animation: spriteAnimation,
                layerID: layer.id, path: path
            ) else { continue }

            let simulator = SceneParticleSimulator(
                definition: asset.definition,
                instanceOverride: layer.particleInstanceOverride,
                seed: UInt64(bitPattern: Int64(layer.id)),
                worldSpaceFrame: worldSpaceFrame, stepSnapshotPolicy: render.ropeTrail?.stepSnapshotPolicy
            )
            let childRuntime = SceneParticleChildRuntime(
                layerID: layer.id,
                rootAsset: asset,
                graph: graph,
                layerAlpha: Float(min(max(layer.alpha ?? 1, 0), 1)),
                textureLoader: textureLoader,
                builtInTextureRegistry: builtInTextureRegistry,
                device: device,
                worldSpaceFrame: worldSpaceFrame
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
                colorUVScale: colorUVScale,
                colorSampling: colorSampling,
                refraction: refraction,
                blendMode: blendMode == .additive ? .additive : .translucent,
                spriteAnimation: spriteAnimation,
                orientation: SceneParticleOrientation(
                    authoredValue: render.renderer.orientation,
                    isWorldSpace: render.renderer.isWorldSpace
                ),
                orientationAxis: render.renderer.axis.map {
                    SceneParticleSimulationMath.vector($0, fallback: SIMD3(0, 0, 1)).floatValue
                },
                usesPerspective: asset.definition.flags.usesPerspective,
                layerAlpha: Float(min(max(layer.alpha ?? 1, 0), 1)),
                simulator: simulator,
                ropeTrailHistory: render.ropeTrail.map(SceneParticleRopeTrailHistory.init(plan:)),
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
            rebuildGPUInstances(forLayerAt: index)
            guard layers[index].instanceBuffer.update(
                device: device,
                instances: layers[index].instances
            ) else {
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
                colorUVScale: layers[index].colorUVScale,
                colorSampling: layers[index].colorSampling,
                refraction: layers[index].refraction,
                blendMode: layers[index].blendMode,
                instanceBuffer: layers[index].instanceBuffer,
                instances: layers[index].instances,
                orientation: layers[index].orientation,
                orientationAxis: layers[index].orientationAxis,
                usesPerspective: layers[index].usesPerspective
            ))
        }
        return batches
    }

    private func rebuildGPUInstances(forLayerAt index: Int) {
        let stepSnapshots = layers[index].simulator.consumeStepSnapshots()
        let particles = layers[index].simulator.particles
        let spriteAnimation = layers[index].spriteAnimation
        let definition = layers[index].definition
        let layerAlpha = layers[index].layerAlpha
        let trail = layers[index].trail
        if var history = layers[index].ropeTrailHistory {
            layers[index].instances = history.advance(
                snapshots: stepSnapshots, currentParticles: particles,
                layerAlpha: layerAlpha
            )
            layers[index].ropeTrailHistory = history
            return
        }
        layers[index].instances.removeAll(keepingCapacity: true)
        layers[index].instances.reserveCapacity(particles.count)
        for particle in particles {
            let frames = Self.spriteFrames(
                animation: spriteAnimation,
                definition: definition,
                particleID: particle.id,
                age: Float(particle.age),
                lifetime: Float(particle.lifetime)
            )
            layers[index].instances.append(SceneParticleGPUInstance(
                position: particle.position.floatValue,
                size: Float(particle.size),
                rotation: particle.rotation.floatValue,
                color: particle.color.floatValue,
                alpha: Float(particle.alpha) * layerAlpha,
                velocity: particle.velocity.floatValue,
                trailStretch: trail?.stretch(for: particle.velocity),
                currentFrame: frames.current.orientedForTrail(trail != nil),
                nextFrame: frames.next?.orientedForTrail(trail != nil),
                frameMix: frames.mix
            ))
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
