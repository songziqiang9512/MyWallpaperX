import Foundation
import Metal

enum SceneParticleChildTrigger: Equatable {
    case staticChild
    case spawn
    case death
    case follow
}

struct SceneParticleChildTemplate {
    let index: Int
    let path: String
    let definition: SceneParticleDefinition
    let trigger: SceneParticleChildTrigger
    let trail: SceneParticleTrailRenderPlan?
    let texture: MTLTexture
    let colorUVScale: SIMD2<Float>
    let colorSampling: SceneParticleTextureSampling
    let refraction: SceneParticleRefractionBinding?
    let renderState: SceneParticlePipelineRenderState
    let spriteAnimation: SceneSpriteAnimation?
    let orientation: SceneParticleOrientation
    let orientationAxis: SIMD3<Float>?
    let usesPerspective: Bool
    let worldSpaceFrame: SceneParticleWorldSpaceFrame?
    let probability: Double
    let staticOrigin: SIMD3<Double>
    let maximumSystemCount: Int
    let particleBudget: Int
    let depth: Int
    let parentAssetPath: String?
    let instanceBuffer = SceneParticleMetalInstanceBuffer()
}

/// Expands authored child declarations into strict templates. Depth-one declarations keep
/// per-declaration templates; nested declarations expand once per parent asset path and stay
/// limited to event triggers at depth two. Anything deeper or outside the strict shapes fails
/// closed with a diagnostic.
enum SceneParticleChildGraphExpansion {
    static let maximumDepth = 2

    struct Expansion {
        let templates: [SceneParticleChildTemplate]
        let unsupportedDetails: [String]
        let performanceDetails: [String]
        let handledRootChildren: Int
    }

    private enum Evaluation {
        case accepted(SceneParticleChildTemplate, SceneParticleAsset)
        case skipped
        case rejected(String)
    }

    static func expand(
        rootAsset: SceneParticleAsset,
        graph: SceneParticleAssetGraph,
        textureLoader: SceneTextureLoader,
        builtInTextureRegistry: SceneParticleBuiltInTextureRegistry,
        device: MTLDevice,
        worldSpaceFrame: SceneParticleWorldSpaceFrame?
    ) -> Expansion {
        var templates: [SceneParticleChildTemplate] = []
        var unsupported: [String] = []
        var performance: [String] = []
        var handledRootChildren = 0
        var expandedParentPaths: Set<String> = []
        var nextTemplateIndex = 0

        for (index, child) in rootAsset.definition.children.enumerated() {
            let evaluation = evaluate(
                child: child,
                declarationIndex: index,
                depth: 1,
                parentAssetPath: nil,
                templateIndex: nextTemplateIndex,
                graph: graph,
                textureLoader: textureLoader,
                builtInTextureRegistry: builtInTextureRegistry,
                device: device,
                worldSpaceFrame: worldSpaceFrame,
                performance: &performance
            )
            switch evaluation {
            case .skipped:
                handledRootChildren += 1
            case let .rejected(detail):
                unsupported.append(detail)
            case let .accepted(template, asset):
                nextTemplateIndex += 1
                if !asset.definition.children.isEmpty,
                   expandedParentPaths.insert(template.path).inserted
                {
                    for (nestedIndex, nested) in asset.definition.children.enumerated() {
                        let nestedEvaluation = evaluate(
                            child: nested,
                            declarationIndex: nestedIndex,
                            depth: 2,
                            parentAssetPath: template.path,
                            templateIndex: nextTemplateIndex,
                            graph: graph,
                            textureLoader: textureLoader,
                            builtInTextureRegistry: builtInTextureRegistry,
                            device: device,
                            worldSpaceFrame: worldSpaceFrame,
                            performance: &performance
                        )
                        switch nestedEvaluation {
                        case .skipped:
                            continue
                        case let .rejected(detail):
                            unsupported.append(detail)
                        case let .accepted(nestedTemplate, _):
                            nextTemplateIndex += 1
                            templates.append(nestedTemplate)
                        }
                    }
                }
                templates.append(template)
                handledRootChildren += 1
            }
        }
        return Expansion(
            templates: templates,
            unsupportedDetails: unsupported,
            performanceDetails: performance,
            handledRootChildren: handledRootChildren
        )
    }

    // swiftlint:disable:next function_parameter_count
    private static func evaluate(
        child: SceneParticleChild,
        declarationIndex: Int,
        depth: Int,
        parentAssetPath: String?,
        templateIndex: Int,
        graph: SceneParticleAssetGraph,
        textureLoader: SceneTextureLoader,
        builtInTextureRegistry: SceneParticleBuiltInTextureRegistry,
        device: MTLDevice,
        worldSpaceFrame: SceneParticleWorldSpaceFrame?,
        performance: inout [String]
    ) -> Evaluation {
        let label = child.path ?? "child#\(declarationIndex)"
        let trigger: SceneParticleChildTrigger
        switch child.type?.lowercased() {
        case nil, "static": trigger = .staticChild
        case "eventspawn": trigger = .spawn
        case "eventdeath": trigger = .death
        case "eventfollow": trigger = .follow
        default:
            return .rejected("\(label):unsupportedType:\(child.type ?? "missing")")
        }
        if depth > 1, trigger == .staticChild {
            return .rejected("\(label):nestedStaticChildUnsupported")
        }
        let staticOrigin = trigger == .staticChild
            ? SceneParticleChildTemplateSupport.staticOriginTranslation(child) : .zero
        let supportsTransform = trigger == .staticChild
            ? staticOrigin != nil : SceneParticleChildTemplateSupport.hasIdentityTransform(child)
        guard supportsTransform,
              child.controlPointStartIndex == nil,
              child.rawFlags == 0
        else {
            return .rejected("\(label):unsupportedTransformOrControlPoint")
        }
        let probability = child.probability ?? 1
        guard probability.isFinite, (0 ... 1).contains(probability) else {
            return .rejected("\(label):invalidProbability")
        }
        guard trigger != .staticChild || probability == 1 else {
            return .rejected("\(label):unsupportedStaticProbability")
        }
        if probability == 0 { return .skipped }
        guard let rawPath = child.path else {
            return .rejected("child#\(declarationIndex):missingPath")
        }
        let path = SceneParticleAssetGraphLoader.normalizedPath(rawPath)
        guard let asset = graph.assetsByPath[path] else {
            return .rejected("\(path):missingAsset")
        }
        guard asset.supportsBuiltInShaderExecution else {
            return .rejected("\(path):unsupportedShader")
        }
        guard let renderState = asset.pipelineState else {
            return .rejected("\(path):unsupportedRenderState")
        }
        if depth >= maximumDepth, !asset.definition.children.isEmpty {
            return .rejected("\(path):nestedDepthUnsupported")
        }
        guard SceneParticleChildLifecycle.supportsEmitterProfile(asset.definition),
              let render = SceneParticleChildTemplateSupport.supportedRenderer(
                  in: asset.definition
              )
        else {
            let profile = trigger == .staticChild
                ? "outsideStrictStaticProfile" : "outsideStrictEventProfile"
            return .rejected("\(path):\(profile)")
        }
        let needsStaticFrame = asset.definition.flags.isWorldSpace
            || asset.definition.operators.contains(where: \.isWorldSpaceMovement)
        guard !needsStaticFrame || worldSpaceFrame != nil else {
            return .rejected("\(path):dynamicWorldSpaceTransform")
        }
        guard let source = asset.textureSource else {
            return .rejected("\(path):textureLoadFailed")
        }
        let texture: MTLTexture
        let animation: SceneSpriteAnimation?
        let colorUVScale: SIMD2<Float>
        let colorSampling: SceneParticleTextureSampling
        let refraction: SceneParticleRefractionBinding?
        if let declaration = asset.refraction {
            guard let loaded = SceneParticleRefractionTextureLoader.load(
                colorSource: source,
                declaration: declaration,
                textureLoader: textureLoader,
                device: device
            ) else {
                return .rejected("\(path):refractionTextureProfileUnsupported")
            }
            texture = loaded.color
            animation = loaded.colorAnimation
            colorUVScale = loaded.colorUVScale
            colorSampling = loaded.colorSampling
            refraction = loaded.binding
        } else {
            guard let loaded = SceneParticleChildTemplateSupport.loadTexture(
                source,
                textureLoader: textureLoader,
                builtInTextureRegistry: builtInTextureRegistry,
                device: device
            ) else {
                return .rejected("\(path):textureLoadFailed")
            }
            texture = loaded.texture
            animation = loaded.animation
            colorSampling = loaded.sampling
            colorUVScale = SIMD2(repeating: 1)
            refraction = nil
        }
        let maximum = child.maximumCount ?? 512
        guard maximum > 0, maximum <= 512 else {
            return .rejected("\(path):invalidSystemLimit")
        }
        let authoredMaximum = min(max(asset.definition.maximumCount ?? 1, 0), 20000)
        let particleBudget = min(authoredMaximum, SceneParticleChildRuntime.maximumParticlesPerSystem)
        if particleBudget < authoredMaximum {
            let instantaneous = asset.definition.emitters.map { $0.instantaneousCount ?? 0 }.max() ?? 0
            performance.append(
                "\(path):particleBudget:max=\(authoredMaximum):instantaneous=\(instantaneous):effective=\(particleBudget)"
            )
        }
        return .accepted(
            SceneParticleChildTemplate(
                index: templateIndex,
                path: path,
                definition: asset.definition,
                trigger: trigger,
                trail: render.trail,
                texture: texture,
                colorUVScale: colorUVScale,
                colorSampling: colorSampling,
                refraction: refraction,
                renderState: renderState,
                spriteAnimation: animation,
                orientation: SceneParticleOrientation(
                    authoredValue: render.renderer.orientation,
                    isWorldSpace: render.renderer.isWorldSpace
                ),
                orientationAxis: render.renderer.axis.map {
                    SceneParticleSimulationMath.vector($0, fallback: SIMD3(0, 0, 1)).particleFloatValue
                },
                usesPerspective: asset.definition.flags.usesPerspective,
                worldSpaceFrame: worldSpaceFrame,
                probability: probability,
                staticOrigin: staticOrigin ?? .zero,
                maximumSystemCount: maximum,
                particleBudget: particleBudget,
                depth: depth,
                parentAssetPath: parentAssetPath
            ),
            asset
        )
    }
}

extension SceneParticleChildTemplate {
    func simulator(
        seed: UInt64,
        emissionDeadline: Double? = nil
    ) -> SceneParticleSimulator {
        SceneParticleSimulator(
            definition: definition,
            seed: seed,
            particleBudget: particleBudget,
            emissionDeadline: emissionDeadline,
            worldSpaceFrame: worldSpaceFrame
        )
    }

    func instance(
        origin: SIMD3<Double>,
        particle: SceneParticleState,
        layerAlpha: Float
    ) -> SceneParticleGPUInstance {
        let frames = SceneParticleRuntime.spriteFrames(
            animation: spriteAnimation,
            definition: definition,
            particleID: particle.id,
            age: Float(particle.age),
            lifetime: Float(particle.lifetime)
        )
        return SceneParticleGPUInstance(
            position: (origin + particle.position).particleFloatValue,
            size: Float(particle.size),
            rotation: particle.rotation.particleFloatValue,
            color: particle.color.particleFloatValue,
            alpha: Float(particle.alpha) * layerAlpha,
            velocity: particle.velocity.particleFloatValue,
            trailStretch: trail?.stretch(for: particle.velocity),
            currentFrame: frames.current.orientedForTrail(trail != nil),
            nextFrame: frames.next?.orientedForTrail(trail != nil),
            frameMix: frames.mix
        )
    }
}

extension SIMD3 where Scalar == Double {
    var particleFloatValue: SIMD3<Float> {
        SIMD3<Float>(Float(x), Float(y), Float(z))
    }
}
