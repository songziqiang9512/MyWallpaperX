import Metal
import simd

struct SceneParticleRendererPlan {
    let index: Int
    let renderer: SceneParticleRenderer
    let trail: SceneParticleTrailRenderPlan?
    let rope: SceneParticleRopePlan?
    let ropeTrail: SceneParticleRopeTrailPlan?
    let snapshotPolicy: SceneParticleStepSnapshotPolicy?

    init(index: Int, renderer: SceneParticleRenderer,
         trail: SceneParticleTrailRenderPlan?, rope: SceneParticleRopePlan?,
         ropeTrail: SceneParticleRopeTrailPlan?) {
        self.index = index
        self.renderer = renderer
        self.trail = trail
        self.rope = rope
        self.ropeTrail = ropeTrail
        snapshotPolicy = ropeTrail?.stepSnapshotPolicy
    }
}

struct SceneParticlePreparedRenderer {
    let index: Int
    let trail: SceneParticleTrailRenderPlan?
    let rope: SceneParticleRopePlan?
    let ropeTrail: SceneParticleRopeTrailPlan?
    let snapshotPolicy: SceneParticleStepSnapshotPolicy?
    let texture: MTLTexture
    let colorUVScale: SIMD2<Float>
    let colorSampling: SceneParticleTextureSampling
    let refraction: SceneParticleRefractionBinding?
    let renderState: SceneParticlePipelineRenderState
    let spriteAnimation: SceneSpriteAnimation?
    let staticSpriteAspect: Float
    let orientation: SceneParticleOrientation
    let orientationAxis: SIMD3<Float>?
    let usesPerspective: Bool
    let usesSceneCamera: Bool
#if DEBUG
    var debugRendererComponentIndex: Int? = nil
    var debugRendererKind: String? = nil
#endif

    private struct TextureView {
        let texture: MTLTexture
        let animation: SceneSpriteAnimation?
        let staticAspect: Float
        let uvScale: SIMD2<Float>
        let sampling: SceneParticleTextureSampling
        let refraction: SceneParticleRefractionBinding?
    }

    static func prepare(
        plans: [SceneParticleRendererPlan],
        asset: SceneParticleAsset,
        textureLoader: SceneTextureLoader,
        builtInTextureRegistry: SceneParticleBuiltInTextureRegistry,
        device: MTLDevice,
        onFailure: (Int, String) -> Void = { _, _ in }
    ) -> [SceneParticlePreparedRenderer] {
        guard let source = asset.textureSource, let state = asset.pipelineState else { return [] }
        var views: [Bool: TextureView] = [:]
        let modes = Set(plans.map { $0.rope != nil && asset.refraction == nil })
        for whole in [false, true] where modes.contains(whole) {
            do {
                if let declaration = asset.refraction {
                    guard let loaded = try SceneParticleRefractionTextureLoader.load(
                        colorSource: source, declaration: declaration,
                        textureLoader: textureLoader, device: device
                    ) else {
                        for plan in plans { onFailure(plan.index, "textureProfileUnsupported") }
                        continue
                    }
                    views[whole] = TextureView(
                        texture: loaded.color, animation: loaded.colorAnimation,
                        staticAspect: loaded.staticSpriteAspect, uvScale: loaded.colorUVScale,
                        sampling: loaded.colorSampling, refraction: loaded.binding
                    )
                } else if let loaded = try SceneParticleChildTemplateSupport.loadTexture(
                    source, textureLoader: textureLoader,
                    builtInTextureRegistry: builtInTextureRegistry,
                    device: device, usesWholeImage: whole
                ) {
                    views[whole] = TextureView(
                        texture: loaded.texture, animation: loaded.animation,
                        staticAspect: loaded.staticAspect, uvScale: loaded.uvScale,
                        sampling: loaded.sampling, refraction: nil
                    )
                } else {
                    for plan in plans where (plan.rope != nil) == whole {
                        onFailure(plan.index, "particleColorTexturePreparationFailed")
                    }
                }
            } catch {
                for plan in plans where (plan.rope != nil && asset.refraction == nil) == whole {
                    onFailure(plan.index, "resourceReadFailed:\(error)")
                }
            }
        }
        return plans.compactMap { plan in
            guard let view = views[plan.rope != nil && asset.refraction == nil] else { return nil }
            if view.animation != nil, plan.rope != nil || plan.ropeTrail != nil {
                onFailure(plan.index, plan.rope != nil ? "rope:animatedTexture" : "ropetrail:animatedTexture")
                return nil
            }
            var output = SceneParticlePreparedRenderer(
                index: plan.index, trail: plan.trail, rope: plan.rope,
                ropeTrail: plan.ropeTrail, snapshotPolicy: plan.snapshotPolicy,
                texture: view.texture, colorUVScale: view.uvScale,
                colorSampling: view.sampling, refraction: view.refraction,
                renderState: state, spriteAnimation: view.animation,
                staticSpriteAspect: view.staticAspect,
                orientation: SceneParticleOrientation(
                    authoredValue: plan.renderer.orientation,
                    isWorldSpace: plan.renderer.isWorldSpace
                ),
                orientationAxis: plan.renderer.axis.map {
                    SceneParticleSimulationMath.vector($0, fallback: SIMD3(0, 0, 1)).particleFloatValue
                },
                usesPerspective: asset.definition.flags.usesPerspective,
                usesSceneCamera: SceneParticlePipelineRenderStateCompiler.usesSceneCamera(
                    renderer: plan.renderer, materialPass: asset.materialPass
                )
            )
#if DEBUG
            if let sources = asset.definition.componentObservationSources {
                output.debugRendererComponentIndex = sources["renderer"]?[plan.index].componentIndex
                output.debugRendererKind = asset.definition.rendererWasImplicit ? "sprite"
                    : sources["renderer"]?[plan.index].kind
            }
#endif
            return output
        }
    }

    func drawBatch(
        layerID: Int, particlePath: String, childTemplateIndex: Int?,
        instances: [SceneParticleGPUInstance],
        referenceWorldFrame: simd_float4x4? = nil, sizeIsWorldSpace: Bool
    ) -> SceneParticleDrawBatch {
        var batch = SceneParticleDrawBatch(
            layerID: layerID, particlePath: particlePath, texture: texture,
            colorUVScale: colorUVScale, colorSampling: colorSampling,
            refraction: refraction, renderState: renderState,
            childTemplateIndex: childTemplateIndex, instances: instances,
            orientation: orientation, orientationAxis: orientationAxis,
            usesPerspective: usesPerspective, rendererIndex: index,
            usesSceneCamera: usesSceneCamera,
            usesPerspectiveTrailEye: trail != nil && usesPerspective
                && orientation == .screen && !sizeIsWorldSpace && childTemplateIndex == nil,
            inheritsNativeSceneCamera: ropeTrail != nil,
            referenceWorldFrame: referenceWorldFrame, sizeIsWorldSpace: sizeIsWorldSpace
        )
#if DEBUG
        batch.debugRendererComponentIndex = debugRendererComponentIndex
        batch.debugRendererKind = debugRendererKind
#endif
        return batch
    }
}

struct SceneParticleRootRendererOutput {
    let renderer: SceneParticlePreparedRenderer
    var instances: [SceneParticleGPUInstance] = []
    var ropeTrailHistory: SceneParticleRopeTrailHistory?
}

/// Optional root draw owned by a particle layer. A stock particle definition may
/// be a child-system container and therefore have no root renderer at all.
/// Such a container must not manufacture a sprite draw or a root simulator.
struct SceneParticleRootRenderRuntime {
    let definition: SceneParticleDefinition
    let collisionBoundsExtent: SIMD2<Float>?
    /// Prepared once with the definition graph; coordinates remain frame-varying.
    let pointerControlPointIdentities: [Int]
    var simulator: SceneParticleSimulator
    var outputs: [SceneParticleRootRendererOutput]

    mutating func clearOutputs(keepingCapacity: Bool = true) {
        for index in outputs.indices {
            outputs[index].instances.removeAll(keepingCapacity: keepingCapacity)
            outputs[index].ropeTrailHistory?.clear(keepingCapacity: keepingCapacity)
        }
    }

    mutating func rebuildInstances() {
        let streams = simulator.consumeStepSnapshots()
        var spriteParticles: [SceneParticleState]?
        for index in outputs.indices {
            let renderer = outputs[index].renderer
            if let rope = renderer.rope {
                outputs[index].instances = rope.instances(
                    particles: simulator.particles.liveArray, layerAlpha: 1,
                    simulationTime: simulator.simulationTime
                )
                continue
            }
            if var history = outputs[index].ropeTrailHistory {
                outputs[index].instances = history.advance(
                    snapshots: renderer.snapshotPolicy.flatMap { streams[$0] } ?? [],
                    currentParticles: simulator.particles.liveArray, layerAlpha: 1
                )
                outputs[index].ropeTrailHistory = history
                continue
            }
            if spriteParticles == nil { spriteParticles = simulator.renderParticlesForCurrentAdvance() }
            let particles = spriteParticles ?? []
            outputs[index].instances.removeAll(keepingCapacity: true)
            outputs[index].instances.reserveCapacity(particles.count)
            for particle in particles {
                let frames = SceneParticleRuntime.spriteFrames(
                    animation: renderer.spriteAnimation, staticAspect: renderer.staticSpriteAspect,
                    definition: definition, particleID: particle.id,
                    age: Float(particle.age), lifetime: Float(particle.lifetime)
                )
                outputs[index].instances.append(SceneParticleGPUInstance(
                    position: particle.position.particleFloatValue, size: Float(particle.size),
                    rotation: particle.rotation.particleFloatValue, color: particle.color.particleFloatValue,
                    alpha: Float(particle.alpha),
                    velocity: renderer.trail?.direction(for: particle.velocity) ?? particle.velocity.particleFloatValue,
                    trailStretch: renderer.trail?.stretch(for: particle.velocity),
                    currentFrame: frames.current.orientedForTrail(renderer.trail != nil),
                    nextFrame: frames.next?.orientedForTrail(renderer.trail != nil),
                    currentFrameAspect: frames.currentAspect,
                    nextFrameAspect: frames.nextAspect, frameMix: frames.mix
                ))
            }
            // Preserve the existing local-Z far-to-near proxy and stable ties;
            // only large translucent populations pay for sorting.
            if renderer.renderState.blendMode == .translucent, outputs[index].instances.count >= 256 {
                let instances = outputs[index].instances
                let order = instances.indices.sorted { lhs, rhs in
                    let lhsZ = instances[lhs].positionAndSize.z
                    let rhsZ = instances[rhs].positionAndSize.z
                    return lhsZ == rhsZ ? lhs < rhs : lhsZ < rhsZ
                }
                outputs[index].instances = order.map { instances[$0] }
            }
        }
    }
}

/// Per-layer mutable particle state owned by one SceneParticleRuntime launch.
/// Root draw state and child-system state are separate official lifecycles: a
/// layer may own both, or a strict child-only container may own only the latter.
struct SceneParticleLayerRuntime {
    let layerID: Int
    let particlePath: String
    let definition: SceneParticleDefinition
    var rootRender: SceneParticleRootRenderRuntime?
    var childRuntime: SceneParticleChildRuntime?
    var wasVisible: Bool? = nil
}
