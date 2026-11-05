import Foundation
import Metal

enum SceneParticleChildTrigger: Hashable {
    case staticChild
    case spawn
    case death
    case follow
}

struct SceneParticleChildTemplate {
    let index: Int
    let path: String
    let definition: SceneParticleDefinition
    /// Prepared once per child template; do not rediscover operator topology per frame.
    let pointerControlPointIdentities: [Int]
    let needsWorldControlPointFrame: Bool
    let trigger: SceneParticleChildTrigger
    let trail: SceneParticleTrailRenderPlan?
    let rope: SceneParticleRopePlan?
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
    let worldSpaceFrame: SceneParticleWorldSpaceFrame?
    let probability: Double
    let transform: SceneParticleChildTransform
    let maximumSystemCount: Int
    let particleBudget: Int
    let depth: Int
    let parentAssetPath: String?
    let instanceOverride: SceneParticleInstanceOverride?
#if DEBUG
    var debugParentParticlePath: String? = nil
    var debugParentComponentIndex: Int? = nil
    var debugRendererTypedIndex: Int? = nil
    var debugRendererComponentIndex: Int? = nil
    var debugRendererKind: String? = nil
#endif
}

/// Expands authored child declarations into strict templates. Depth-one declarations keep
/// per-declaration templates; nested declarations expand once per parent asset path and stay
/// limited to event triggers at depth two. Anything deeper or outside the strict shapes fails
/// closed with a diagnostic.
enum SceneParticleChildGraphExpansion {
    static let maximumDepth = 2

    struct Expansion {
        var templates: [SceneParticleChildTemplate] = []
        var unsupportedDetails: [String] = []
#if DEBUG
        var performanceDetails: [String] = []
#endif
        var handledRootChildren = 0
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
        worldSpaceFrame: SceneParticleWorldSpaceFrame?,
        rootInstanceOverride: SceneParticleInstanceOverride?
    ) -> Expansion {
        var result = Expansion()
        var expandedParentPaths: Set<String> = []
        var nextTemplateIndex = 0

        for (index, child) in rootAsset.definition.children.enumerated() {
            let evaluation = evaluate(
                child: child,
                declarationIndex: index,
                depth: 1,
                parentAssetPath: nil,
                rootDefinition: rootAsset.definition,
                rootInstanceOverride: rootInstanceOverride,
                templateIndex: nextTemplateIndex,
                graph: graph,
                textureLoader: textureLoader,
                builtInTextureRegistry: builtInTextureRegistry,
                device: device,
                worldSpaceFrame: worldSpaceFrame,
                result: &result
            )
            switch evaluation {
            case .skipped:
                result.handledRootChildren += 1
            case let .rejected(detail):
                result.unsupportedDetails.append(detail)
            case let .accepted(acceptedTemplate, asset):
                var template = acceptedTemplate
#if DEBUG
                template.debugParentParticlePath = rootAsset.relativePath
                template.debugParentComponentIndex = rootAsset.definition.componentObservationSources?["children"]?[index].componentIndex
#endif
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
                            rootDefinition: rootAsset.definition,
                            rootInstanceOverride: rootInstanceOverride,
                            templateIndex: nextTemplateIndex,
                            graph: graph,
                            textureLoader: textureLoader,
                            builtInTextureRegistry: builtInTextureRegistry,
                            device: device,
                            worldSpaceFrame: worldSpaceFrame,
                            result: &result
                        )
                        switch nestedEvaluation {
                        case .skipped:
                            continue
                        case let .rejected(detail):
                            result.unsupportedDetails.append(detail)
                        case let .accepted(acceptedNestedTemplate, _):
                            var nestedTemplate = acceptedNestedTemplate
#if DEBUG
                            nestedTemplate.debugParentParticlePath = template.path
                            nestedTemplate.debugParentComponentIndex = asset.definition.componentObservationSources?["children"]?[nestedIndex].componentIndex
#endif
                            nextTemplateIndex += 1
                            result.templates.append(nestedTemplate)
                        }
                    }
                }
                result.templates.append(template)
                result.handledRootChildren += 1
            }
        }
        return result
    }

    // swiftlint:disable:next function_parameter_count
    private static func evaluate(
        child: SceneParticleChild,
        declarationIndex: Int,
        depth: Int,
        parentAssetPath: String?,
        rootDefinition: SceneParticleDefinition,
        rootInstanceOverride: SceneParticleInstanceOverride?,
        templateIndex: Int,
        graph: SceneParticleAssetGraph,
        textureLoader: SceneTextureLoader,
        builtInTextureRegistry: SceneParticleBuiltInTextureRegistry,
        device: MTLDevice,
        worldSpaceFrame: SceneParticleWorldSpaceFrame?,
        result: inout Expansion
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
        guard let transform = SceneParticleChildTemplateSupport.transform(
            child, allowsOrigin: trigger == .staticChild
        ),
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
        switch SceneParticleChildTemplateSupport.eventColorAdmission(
            definition: asset.definition, trigger: trigger
        ) {
        case .disabled:
            break
#if DEBUG
        case let .supported(markers):
            result.performanceDetails.append(contentsOf: markers.map { "\(path):\($0)" })
#else
        case .supported:
            break
#endif
        case let .unsupported(detail):
            return .rejected("\(path):\(detail)")
        }
        let permitsStaticRope = render.rope != nil && depth == 1
            && trigger == .staticChild && asset.definition.children.isEmpty
            && !asset.definition.operators.contains(where: \.isWorldSpaceMovement)
        if transform.hasScale {
            guard render.rope == nil || permitsStaticRope,
                  asset.definition.children.isEmpty,
                  !asset.definition.operators.contains(where: \.isWorldSpaceMovement)
            else { return .rejected("\(path):childScaleOutsideBoundedProfile") }
#if DEBUG
            result.performanceDetails.append(
                "\(path):childScaleBounded:scale=\(transform.scale.x),\(transform.scale.y),\(transform.scale.z)"
            )
#endif
        }
        let controlPointOverride: SceneParticleInstanceOverride?
        switch SceneParticleChildTemplateSupport.rawParentControlPointOverride(
            childDefinition: asset.definition,
            rootDefinition: rootDefinition,
            rootOverride: rootInstanceOverride,
            allowsCopy: depth == 1 && trigger == .staticChild
        ) {
        case .disabled:
            controlPointOverride = nil
#if DEBUG
        case let .ignoredUnused(count):
            controlPointOverride = nil
            result.performanceDetails.append("\(path):unusedParentControlPointMappings:mappings=\(count)")
        case let .supported(value, count):
            controlPointOverride = value
            result.performanceDetails.append("\(path):rawParentControlPointCopyBounded:mappings=\(count)")
#else
        case .ignoredUnused:
            controlPointOverride = nil
        case let .supported(value, _):
            controlPointOverride = value
#endif
        case let .unsupported(detail):
            return .rejected("\(path):\(detail)")
        }
        // Layer modifiers belong to the whole child tree. Control points retain
        // their separate, explicitly admitted parent-to-child mapping.
        let instanceOverride = SceneParticleInstanceOverride(
            id: rootInstanceOverride?.id,
            alpha: rootInstanceOverride?.alpha,
            size: rootInstanceOverride?.size,
            lifetime: rootInstanceOverride?.lifetime,
            rate: rootInstanceOverride?.rate,
            speed: rootInstanceOverride?.speed,
            count: rootInstanceOverride?.count,
            brightness: rootInstanceOverride?.brightness,
            color: rootInstanceOverride?.color,
            normalizedColor: rootInstanceOverride?.normalizedColor,
            controlPoints: controlPointOverride?.controlPoints ?? [:],
            controlPointAngles: controlPointOverride?.controlPointAngles ?? [:]
        )
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
        let staticSpriteAspect: Float
        let colorUVScale: SIMD2<Float>
        let colorSampling: SceneParticleTextureSampling
        let refraction: SceneParticleRefractionBinding?
        do {
            if let declaration = asset.refraction {
                guard let loaded = try SceneParticleRefractionTextureLoader.load(
                    colorSource: source,
                    declaration: declaration,
                    textureLoader: textureLoader,
                    device: device
                ) else {
                    return .rejected("\(path):refractionTextureProfileUnsupported")
                }
                texture = loaded.color
                animation = loaded.colorAnimation
                staticSpriteAspect = loaded.staticSpriteAspect
                colorUVScale = loaded.colorUVScale
                colorSampling = loaded.colorSampling
                refraction = loaded.binding
            } else {
                guard let loaded = try SceneParticleChildTemplateSupport.loadTexture(
                    source,
                    textureLoader: textureLoader,
                    builtInTextureRegistry: builtInTextureRegistry,
                    device: device,
                    usesWholeImage: render.rope != nil
                ) else {
                    return .rejected("\(path):textureLoadFailed")
                }
                texture = loaded.texture
                animation = loaded.animation
                staticSpriteAspect = loaded.staticAspect
                colorSampling = loaded.sampling
                colorUVScale = loaded.uvScale
                refraction = nil
            }
        } catch {
            return .rejected("\(path):resourceReadFailed:\(error)")
        }
        let maximum = child.maximumCount ?? 512
        guard maximum > 0, maximum <= 512 else {
            return .rejected("\(path):invalidSystemLimit")
        }
        let authoredMaximum = min(max(asset.definition.maximumCount ?? 1, 0), 20000)
        let particleBudget = authoredMaximum
        if animation != nil, render.rope != nil {
            return .rejected("\(path):ropeAnimatedTextureUnsupported")
        }
        let systemBudget = trigger == .staticChild ? 1 : maximum
        if let rope = render.rope, !permitsStaticRope,
           systemBudget > SceneParticleChildTemplateSupport.maximumRopeSegmentsPerTemplate
                / max(rope.maximumGeneratedSegments, 1)
        {
            return .rejected("\(path):ropeAggregateSegmentBudget")
        }
        let worldPoints = Set(asset.definition.controlPoints.filter(\.isWorldSpace).compactMap(\.id))
        let needsWorldPointFrame = asset.definition.emitters.contains {
            asset.definition.emitterControlPointSource(for: $0).map(worldPoints.contains) == true
        } || asset.definition.initializers.contains {
            guard let plan = $0.positionBetweenControlPointsPlan else { return false }
            return worldPoints.contains(plan.controlPointStart) || worldPoints.contains(plan.controlPointEnd)
        } || asset.definition.operators.contains {
            switch $0.kind {
            case let .maintainControlPointDistance(plan?):
                return worldPoints.contains(plan.start) || worldPoints.contains(plan.end)
            case let .controlPointRadius(plan?):
                return worldPoints.contains(plan.controlPoint)
            default: return false
            }
        }
        var template = SceneParticleChildTemplate(
                index: templateIndex,
                path: path,
                definition: asset.definition,
                pointerControlPointIdentities: asset.definition.pointerControlPointIdentities,
                needsWorldControlPointFrame: needsWorldPointFrame,
                trigger: trigger,
                trail: render.trail,
                rope: render.rope,
                texture: texture,
                colorUVScale: colorUVScale,
                colorSampling: colorSampling,
                refraction: refraction,
                renderState: renderState,
                spriteAnimation: animation,
                staticSpriteAspect: staticSpriteAspect,
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
                transform: transform,
                maximumSystemCount: maximum,
                particleBudget: particleBudget,
                depth: depth,
                parentAssetPath: parentAssetPath,
                instanceOverride: instanceOverride
            )
#if DEBUG
        if let sources = asset.definition.componentObservationSources {
            let typedIndex = asset.definition.renderers.firstIndex(of: render.renderer)
            template.debugRendererTypedIndex = typedIndex
            template.debugRendererComponentIndex = typedIndex.flatMap { sources["renderer"]?[$0].componentIndex }
            template.debugRendererKind = asset.definition.rendererWasImplicit ? "sprite"
                : typedIndex.flatMap { sources["renderer"]?[$0].kind }
        }
#endif
        return .accepted(template, asset)
    }
}

extension SceneParticleChildTemplate {
    func simulator(
        seed: UInt64,
        dynamicInstanceValues: SceneDynamicParticleValues? = nil,
        origin: SIMD3<Double> = .zero,
        controlPointFrame: SceneParticleControlPointFrame? = nil,
        worldSpaceFrameOverride: SceneParticleWorldSpaceFrame? = nil,
        rootTranslationOffset: SIMD3<Double> = .zero,
        initialDynamicControlPoints: [Int: SIMD3<Double>] = [:],
        initialDynamicControlPointAngles: [Int: SIMD3<Double>] = [:],
        maximumEmissionDuration: Double? = nil,
        eventColorContext: SceneParticleEventColorContext = .unavailable
    ) -> SceneParticleSimulator {
        let simulator = SceneParticleSimulator(
            definition: definition,
            instanceOverride: instanceOverride,
            initialDynamicInstanceOverride: instanceOverride?.resolving(dynamicInstanceValues),
            initialDynamicControlPoints: initialDynamicControlPoints,
            initialDynamicControlPointAngles: initialDynamicControlPointAngles,
            seed: seed,
            particleBudget: particleBudget,
            maximumEmissionDuration: maximumEmissionDuration,
            worldSpaceFrame: worldSpaceFrameOverride ?? worldSpaceFrame,
            controlPointFrame: needsWorldControlPointFrame
                ? controlPointFrame?.childFrame(origin: origin - (definition.flags.isWorldSpace ? rootTranslationOffset : .zero), scale: transform.scale) : nil,
            initialControlPointParticleSpace: definition.flags.isWorldSpace
                ? .init(currentOrigin: origin, scale: transform.scale, birthOrigins: [:]) : nil,
            eventColorContext: eventColorContext
        )
#if DEBUG
        simulator.observeSelectedRenderer(typedIndex: debugRendererTypedIndex)
#endif
        return simulator
    }

    func instance(
        origin: SIMD3<Double>,
        particle: SceneParticleState,
        layerAlpha: Float
    ) -> SceneParticleGPUInstance {
        let frames = SceneParticleRuntime.spriteFrames(
            animation: spriteAnimation,
            staticAspect: staticSpriteAspect,
            definition: definition,
            particleID: particle.id,
            age: Float(particle.age),
            lifetime: Float(particle.lifetime)
        )
        let velocity = transform.velocity(particle.velocity)
        return SceneParticleGPUInstance(
            position: (origin + transform.position(particle.position)).particleFloatValue,
            size: Float(transform.size(particle.size)),
            rotation: particle.rotation.particleFloatValue,
            color: particle.color.particleFloatValue,
            alpha: Float(particle.alpha) * layerAlpha,
            velocity: trail?.direction(for: velocity) ?? velocity.particleFloatValue,
            trailStretch: trail?.stretch(for: velocity),
            currentFrame: frames.current.orientedForTrail(trail != nil),
            nextFrame: frames.next?.orientedForTrail(trail != nil),
            currentFrameAspect: frames.currentAspect,
            nextFrameAspect: frames.nextAspect,
            frameMix: frames.mix
        )
    }
}
