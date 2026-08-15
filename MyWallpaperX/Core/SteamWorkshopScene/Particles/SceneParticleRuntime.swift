import Foundation
import Metal

/// Owns the CPU state and GPU instance buffers for effectively visible particle layers.
/// Particle positions and sizes stay in the author-defined layer-local coordinate system.
/// The renderer applies the layer world frame, Y-axis convention, and layer scale once.
final class SceneParticleRuntime {
    private let device: MTLDevice
    private var layers: [SceneParticleLayerRuntime] = []
    private(set) var diagnostics: [SceneParticleRuntimeDiagnostic] = []

    var activeLayerIDs: [Int] { layers.map(\.layerID) }
    var hasAudioConsumer: Bool { layers.contains { $0.definition.hasBoundedAudioConsumer } }

    init(
        descriptor: SceneRenderDescriptor,
        cacheDirectory: URL,
        device: MTLDevice,
        resourceView: SceneResourceView? = nil,
        stockTextureBundleURL: URL? = SceneStockTextureResolver.defaultBundleRoot(),
        textureLoader: SceneTextureLoader = SceneTextureLoader(),
        layerImageEmissionMaps: [Int: SceneParticleLayerImageEmissionMap] = [:],
        initialDiagnostics: [SceneParticleRuntimeDiagnostic] = [],
        staticWorldSpaceFrames: [Int: SceneParticleWorldSpaceFrame]? = nil,
        initialDynamicValues: SceneDynamicSnapshot = .empty(frameIndex: 0)
    ) {
        self.device = device
        diagnostics = initialDiagnostics
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
            guard let asset = graph.assetsByPath[path] else { continue }
            let layerImageMap = layerImageEmissionMaps[layer.id]
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
            let childRuntime = SceneParticleChildRuntime(
                layerID: layer.id,
                rootAsset: asset,
                graph: graph,
                layerAlpha: Float(min(max(layer.alpha ?? 1, 0), 1)),
                textureLoader: textureLoader,
                builtInTextureRegistry: builtInTextureRegistry,
                device: device,
                worldSpaceFrame: worldSpaceFrame,
                rootInstanceOverride: layer.particleInstanceOverride
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
            let retainedChildRuntime = childRuntime.hasTemplates ? childRuntime : nil
            if asset.definition.renderers.isEmpty {
                guard admitsChildOnlyContainer(
                    asset.definition,
                    childRuntime: childRuntime,
                    layerID: layer.id,
                    path: path
                ) else { continue }
                layers.append(SceneParticleLayerRuntime(
                    layerID: layer.id,
                    particlePath: path,
                    definition: asset.definition,
                    layerAlpha: Float(min(max(layer.alpha ?? 1, 0), 1)),
                    rootRender: nil,
                    childRuntime: retainedChildRuntime
                ))
                continue
            }

            guard asset.supportsBuiltInShaderExecution,
                  let renderState = asset.pipelineState,
                  admitsLayerImageEmitters(
                    asset.definition, map: layerImageMap, layerID: layer.id, path: path
                  ),
                  let render = supportedRenderer(
                    in: asset.definition, layerID: layer.id, path: path
                  ),
                  let rootRender = makeRootRenderRuntime(
                    asset: asset,
                    renderState: renderState,
                    render: render,
                    layer: layer,
                    path: path,
                    layerImageMap: layerImageMap,
                    worldSpaceFrame: worldSpaceFrame,
                    initialDynamicValues: initialDynamicValues,
                    textureLoader: textureLoader,
                    builtInTextureRegistry: builtInTextureRegistry
                  ) else { continue }
            appendSimulationDiagnostics(
                rootRender.simulator.diagnostics,
                layerID: layer.id,
                path: path,
                handlesAllChildren: childRuntime.handlesAllChildren
            )
            layers.append(SceneParticleLayerRuntime(
                layerID: layer.id,
                particlePath: path,
                definition: asset.definition,
                layerAlpha: Float(min(max(layer.alpha ?? 1, 0), 1)),
                rootRender: rootRender,
                childRuntime: retainedChildRuntime
            ))
        }
    }

    /// Advances every active layer by the frame delta and returns batches in scene render order.
    func advance(by frameDelta: TimeInterval, dynamicValues: SceneDynamicSnapshot = .empty(frameIndex: 0),
                 pointerLocalPositions: [Int: SIMD3<Double>] = [:], audioInput: SceneParticleAudioInput = .silent) -> [SceneParticleDrawBatch] {
        var batches: [SceneParticleDrawBatch] = []
        for index in layers.indices {
            let layerID = layers[index].layerID
            var births: [SceneParticleState] = []
            var deaths: [SceneParticleState] = []
            var parentParticles: [SceneParticleState] = []
            if var root = layers[index].rootRender {
                let pointerValues = root.definition.pointerControlPointValues(
                    at: pointerLocalPositions[layerID]
                )
                let controlPoints = dynamicValues.particleControlPoints(
                    layerID: layerID
                ).merging(pointerValues) { _, pointer in pointer }
                let dynamicOverride = dynamicValues.particleInstanceValues(layerID: layerID)
                let instanceOverride = root.simulator.instanceOverride?.resolving(
                    dynamicOverride
                )
                root.simulator.advance(
                    by: frameDelta,
                    dynamicControlPoints: controlPoints,
                    dynamicInstanceOverride: instanceOverride,
                    audioInput: audioInput
                )
                births = root.simulator.consumeBirthEvents()
                deaths = root.simulator.consumeDeathEvents()
                parentParticles = root.simulator.particles
                layers[index].rootRender = root
            }
            if let childRuntime = layers[index].childRuntime {
                let result = childRuntime.advance(
                    by: frameDelta,
                    spawnEvents: births,
                    deathEvents: deaths,
                    parentParticles: parentParticles,
                    pointerLocalPosition: pointerLocalPositions[layerID]
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
            guard var root = layers[index].rootRender else { continue }
            rebuildGPUInstances(root: &root, layerAlpha: layers[index].layerAlpha)
            guard root.instanceBuffer.update(device: device, instances: root.instances) else {
                addDiagnostic(
                    kind: .instanceBufferAllocationFailed,
                    layerID: layerID,
                    path: layers[index].particlePath
                )
                continue
            }
            batches.append(SceneParticleDrawBatch(
                layerID: layerID,
                particlePath: layers[index].particlePath,
                texture: root.texture,
                colorUVScale: root.colorUVScale,
                colorSampling: root.colorSampling,
                refraction: root.refraction,
                renderState: root.renderState,
                instanceBuffer: root.instanceBuffer,
                instances: root.instances,
                orientation: root.orientation,
                orientationAxis: root.orientationAxis,
                usesPerspective: root.usesPerspective
            ))
            layers[index].rootRender = root
        }
        return batches
    }

    private func rebuildGPUInstances(
        root: inout SceneParticleRootRenderRuntime,
        layerAlpha: Float
    ) {
        let stepSnapshots = root.simulator.consumeStepSnapshots()
        let particles = root.simulator.particles
        if let rope = root.rope {
            root.instances = rope.instances(
                particles: particles,
                layerAlpha: layerAlpha,
                simulationTime: root.simulator.simulationTime
            )
            return
        }
        if var history = root.ropeTrailHistory {
            root.instances = history.advance(
                snapshots: stepSnapshots, currentParticles: particles,
                layerAlpha: layerAlpha
            )
            root.ropeTrailHistory = history
            return
        }
        root.instances.removeAll(keepingCapacity: true)
        root.instances.reserveCapacity(particles.count)
        for particle in particles {
            let frames = Self.spriteFrames(
                animation: root.spriteAnimation,
                definition: root.definition,
                particleID: particle.id,
                age: Float(particle.age),
                lifetime: Float(particle.lifetime)
            )
            root.instances.append(SceneParticleGPUInstance(
                position: particle.position.particleFloatValue,
                size: Float(particle.size),
                rotation: particle.rotation.particleFloatValue,
                color: particle.color.particleFloatValue,
                alpha: Float(particle.alpha) * layerAlpha,
                velocity: particle.velocity.particleFloatValue,
                trailStretch: root.trail?.stretch(for: particle.velocity),
                currentFrame: frames.current.orientedForTrail(root.trail != nil),
                nextFrame: frames.next?.orientedForTrail(root.trail != nil),
                currentFrameAspect: frames.currentAspect,
                nextFrameAspect: frames.nextAspect,
                frameMix: frames.mix
            ))
        }
    }

    func addDiagnostic(
        kind: SceneParticleRuntimeDiagnosticKind, layerID: Int?, path: String, detail: String? = nil
    ) {
        let value = SceneParticleRuntimeDiagnostic(
            kind: kind, layerID: layerID, particlePath: path, detail: detail
        )
        if !diagnostics.contains(value) { diagnostics.append(value) }
    }

    /// Official particle containers parse `renderer` and `children` as
    /// independent collections. We admit only the bounded form whose root has
    /// no renderer and whose complete root-child set is static and executable;
    /// event children still require a root simulator and therefore fail closed.
    private func admitsChildOnlyContainer(
        _ definition: SceneParticleDefinition,
        childRuntime: SceneParticleChildRuntime,
        layerID: Int,
        path: String
    ) -> Bool {
        let rendererMalformed = definition.diagnostics.contains {
            $0.path == "renderer" || $0.path.hasPrefix("renderer[")
        }
        let staticChildren = !definition.children.isEmpty
            && definition.children.allSatisfy {
                guard let type = $0.type?.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).localizedLowercase else { return true }
                return type.isEmpty || type == "static"
            }
        let accepted = !rendererMalformed
            && staticChildren
            && childRuntime.hasTemplates
            && childRuntime.handlesAllChildren
            && childRuntime.unsupportedDetails.isEmpty
        guard accepted else {
            addDiagnostic(
                kind: .missingSpriteRenderer,
                layerID: layerID,
                path: path,
                detail: definition.children.isEmpty
                    ? nil : "rootRendererAbsentOutsideStrictStaticChildContainer"
            )
            return false
        }
        return true
    }

    // swiftlint:disable:next function_parameter_count
    private func makeRootRenderRuntime(
        asset: SceneParticleAsset,
        renderState: SceneParticlePipelineRenderState,
        render: (
            renderer: SceneParticleRenderer,
            trail: SceneParticleTrailRenderPlan?,
            rope: SceneParticleRopePlan?,
            ropeTrail: SceneParticleRopeTrailPlan?
        ),
        layer: SceneRenderDescriptor.Layer,
        path: String,
        layerImageMap: SceneParticleLayerImageEmissionMap?,
        worldSpaceFrame: SceneParticleWorldSpaceFrame?,
        initialDynamicValues: SceneDynamicSnapshot,
        textureLoader: SceneTextureLoader,
        builtInTextureRegistry: SceneParticleBuiltInTextureRegistry
    ) -> SceneParticleRootRenderRuntime? {
        guard let textureSource = asset.textureSource else { return nil }
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
                return nil
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
                    return nil
                }
                texture = SceneParticleColorTextureAdapter.adapt(
                    loadedTexture,
                    device: device
                )
                let container = textureLoader.texContainer(from: textureURL)
                spriteAnimation = container.flatMap {
                    SceneSpriteAnimation(container: $0, sourceURL: textureURL)
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
                    return nil
                }
                texture = loadedTexture
                spriteAnimation = nil
                colorSampling = .directImageFallback
            }
            colorUVScale = SIMD2(repeating: 1)
            refraction = nil
        }
        guard supportsPathRendererTexture(
            rope: render.rope,
            ropeTrail: render.ropeTrail,
            animation: spriteAnimation,
            layerID: layer.id,
            path: path
        ) else { return nil }

        let initialInstanceOverride = layer.particleInstanceOverride?.resolving(
            initialDynamicValues.particleInstanceValues(layerID: layer.id)
        )
        let simulator = SceneParticleSimulator(
            definition: asset.definition,
            instanceOverride: layer.particleInstanceOverride,
            initialDynamicInstanceOverride: initialInstanceOverride,
            seed: UInt64(bitPattern: Int64(layer.id)),
            layerImageEmissionMap: layerImageMap,
            worldSpaceFrame: worldSpaceFrame,
            stepSnapshotPolicy: render.ropeTrail?.stepSnapshotPolicy
        )
        return SceneParticleRootRenderRuntime(
            definition: asset.definition,
            trail: render.trail,
            rope: render.rope,
            texture: texture,
            colorUVScale: colorUVScale,
            colorSampling: colorSampling,
            refraction: refraction,
            renderState: renderState,
            spriteAnimation: spriteAnimation,
            orientation: SceneParticleOrientation(
                authoredValue: render.renderer.orientation,
                isWorldSpace: render.renderer.isWorldSpace
            ),
            orientationAxis: render.renderer.axis.map {
                SceneParticleSimulationMath.vector(
                    $0,
                    fallback: SIMD3(0, 0, 1)
                ).particleFloatValue
            },
            usesPerspective: asset.definition.flags.usesPerspective,
            simulator: simulator,
            ropeTrailHistory: render.ropeTrail.map(
                SceneParticleRopeTrailHistory.init(plan:)
            )
        )
    }
}
