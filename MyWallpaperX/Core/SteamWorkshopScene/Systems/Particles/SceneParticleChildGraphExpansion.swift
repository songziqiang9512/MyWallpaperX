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
    var renderers: [SceneParticlePreparedRenderer]
    let worldSpaceFrame: SceneParticleWorldSpaceFrame?
    let probability: Double
    let transform: SceneParticleChildTransform
    let maximumSystemCount: Int
    let particleBudget: Int
    let depth: Int
    let parentAssetPath: String?
    let instanceOverride: SceneParticleInstanceOverride?
    var particleControlPointStart: Int? = nil
    var particleControlPointMask: UInt8 = 0
    var usesLocalParentControlPointFallback = false
#if DEBUG
    var debugParentParticlePath: String? = nil
    var debugParentComponentIndex: Int? = nil
#endif
}

/// Expands authored child declarations into strict templates. Depth-one declarations keep
/// per-declaration templates; nested declarations expand once per parent asset path.
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
        var parentsWithExecutableChildren: [String: Bool] = [:]
        var nextTemplateIndex = 0

        for (index, child) in rootAsset.definition.children.enumerated() {
            let evaluation = evaluate(
                child: child,
                declarationIndex: index,
                depth: 1,
                parentAssetPath: nil,
                parentDefinition: rootAsset.definition,
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
                if !asset.definition.children.isEmpty, parentsWithExecutableChildren[template.path] == nil {
                    let firstNestedIndex = nextTemplateIndex
                    for (nestedIndex, nested) in asset.definition.children.enumerated() {
                        let nestedEvaluation = evaluate(
                            child: nested,
                            declarationIndex: nestedIndex,
                            depth: 2,
                            parentAssetPath: template.path,
                            parentDefinition: asset.definition,
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
                    parentsWithExecutableChildren[template.path] = nextTemplateIndex > firstNestedIndex
                }
                if template.renderers.isEmpty, parentsWithExecutableChildren[template.path] != true {
                    nextTemplateIndex -= 1
                    result.unsupportedDetails.append("\(template.path):simulationOnlyChildHasNoExecutableDescendant")
                    continue
                }
                result.templates.append(template)
                result.handledRootChildren += 1
            }
        }
        return result
    }

    private static func trigger(for child: SceneParticleChild) -> SceneParticleChildTrigger? {
        switch child.type?.lowercased() {
        case nil, "static": .staticChild
        case "eventspawn": .spawn
        case "eventdeath": .death
        case "eventfollow": .follow
        default: nil
        }
    }

    // swiftlint:disable:next function_parameter_count
    private static func evaluate(
        child: SceneParticleChild,
        declarationIndex: Int,
        depth: Int,
        parentAssetPath: String?,
        parentDefinition: SceneParticleDefinition,
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
        guard let trigger = trigger(for: child) else {
            return .rejected("\(label):unsupportedType:\(child.type ?? "missing")")
        }
        guard let transform = SceneParticleChildTemplateSupport.transform(
            child, allowsOrigin: trigger == .staticChild
        ) else {
            return .rejected("\(label):unsupportedTransform")
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
        let needsStaticFrame = asset.definition.flags.isWorldSpace
            || asset.definition.operators.contains(where: \.isWorldSpaceMovement)
        let hasLocalPoints = !needsStaticFrame && !transform.hasScale
            && !parentDefinition.flags.isWorldSpace
            && !parentDefinition.operators.contains(where: \.isWorldSpaceMovement)
        if depth > 1, trigger == .staticChild, !hasLocalPoints {
            return .rejected("\(path):nestedStaticChildOutsideLocalSpace")
        }
        let pointStart = child.controlPointStartIndex ?? 0
        let particleControlPointStart = child.rawFlags == 1 && hasLocalPoints
            && (trigger == .follow || trigger == .staticChild) && (0 ... 7).contains(pointStart)
            ? pointStart : nil
        if child.rawFlags != 0, particleControlPointStart == nil {
            guard asset.definition.children.isEmpty,
                  !SceneParticleChildTemplateSupport.consumesControlPointValues(asset.definition)
            else { return .rejected("\(path):childControlPointBindingUnavailable") }
        }
#if DEBUG
        if particleControlPointStart == nil, child.rawFlags != 0 || child.controlPointStartIndex != nil {
            result.performanceDetails.append(
                "\(path):unconsumedChildOptions:flags=\(child.rawFlags):startIndex=\(child.controlPointStartIndex?.description ?? "-")"
            )
        }
#endif
        let simulationOnly = trigger != .staticChild && asset.definition.renderers.isEmpty
            && !asset.definition.rendererWasImplicit && !asset.definition.children.isEmpty
            && !asset.definition.diagnostics.contains {
                $0.path == "renderer" || $0.path.hasPrefix("renderer[")
            }
        guard simulationOnly || asset.supportsBuiltInShaderExecution else {
            return .rejected("\(path):unsupportedShader")
        }
        if depth >= maximumDepth, !asset.definition.children.isEmpty {
            return .rejected("\(path):nestedDepthUnsupported")
        }
        let supportsEmitters = SceneParticleChildLifecycle.supportsEmitterProfile(asset.definition)
        var plans = supportsEmitters && !simulationOnly
            ? SceneParticleChildTemplateSupport.supportedRenderers(in: asset.definition) : []
        guard !plans.isEmpty || (simulationOnly && supportsEmitters) else {
            let profile = trigger == .staticChild
                ? "outsideStrictStaticProfile" : "outsideStrictEventProfile"
            return .rejected("\(path):\(profile)")
        }
        for (index, renderer) in asset.definition.renderers.enumerated() where renderer.kind == .ropeTrail {
            result.unsupportedDetails.append("\(path):renderer[\(index)]:ropetrail:childHistoryUnavailable")
        }
        let permitsStaticRope = depth == 1
            && trigger == .staticChild && asset.definition.children.isEmpty
            && !asset.definition.operators.contains(where: \.isWorldSpaceMovement)
        if transform.hasScale {
            guard asset.definition.children.isEmpty,
                  !asset.definition.operators.contains(where: \.isWorldSpaceMovement)
            else { return .rejected("\(path):childScaleOutsideBoundedProfile") }
            if transform.scale.x != transform.scale.y {
                plans.removeAll { plan in
                    let orientation = SceneParticleOrientation(
                        authoredValue: plan.renderer.orientation,
                        isWorldSpace: plan.renderer.isWorldSpace
                    )
                    guard plan.renderer.kind == .sprite, orientation == .screen,
                          !asset.definition.flags.isWorldSpace else {
                        result.unsupportedDetails.append(
                            "\(path):renderer[\(plan.index)]:childPlaneScaleUnavailable"
                        )
                        return true
                    }
                    return false
                }
            }
            let rendererCount = plans.count
            if !permitsStaticRope { plans.removeAll { $0.rope != nil } }
            guard !plans.isEmpty else { return .rejected("\(path):childScaleOutsideBoundedProfile") }
            if plans.count != rendererCount {
                result.unsupportedDetails.append("\(path):childScaleOutsideBoundedProfile")
            }
#if DEBUG
            result.performanceDetails.append(
                "\(path):childScaleBounded:scale=\(transform.scale.x),\(transform.scale.y),\(transform.scale.z)"
            )
#endif
        }
        let controlPointOverride: SceneParticleInstanceOverride?
        var usesLocalParentControlPointFallback = false
        switch SceneParticleChildTemplateSupport.rawParentControlPointOverride(
            childDefinition: asset.definition,
            parentDefinition: parentDefinition,
            parentOverride: depth == 1 ? rootInstanceOverride : nil,
            allowsCopy: depth == 1 && trigger == .staticChild,
            allowsAuthoredFallback: trigger == .follow && hasLocalPoints
        ) {
        case .disabled:
            controlPointOverride = nil
#if DEBUG
        case let .ignoredUnused(count):
            controlPointOverride = nil
            result.performanceDetails.append("\(path):unusedParentControlPointMappings:mappings=\(count)")
        case let .authoredFallback(count):
            controlPointOverride = nil
            usesLocalParentControlPointFallback = true
            result.performanceDetails.append("\(path):rawParentControlPointAuthoredFallback:mappings=\(count)")
        case let .supported(value, count):
            controlPointOverride = value
            result.performanceDetails.append("\(path):rawParentControlPointCopyBounded:mappings=\(count)")
#else
        case .ignoredUnused:
            controlPointOverride = nil
        case .authoredFallback:
            controlPointOverride = nil
            usesLocalParentControlPointFallback = true
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
            color: rootInstanceOverride?.color,
            normalizedColor: rootInstanceOverride?.normalizedColor,
            controlPoints: controlPointOverride?.controlPoints ?? [:],
            controlPointAngles: controlPointOverride?.controlPointAngles ?? [:],
            usesLegacyColorTransfer: rootInstanceOverride?.usesLegacyColorTransfer
        )
        guard !needsStaticFrame || worldSpaceFrame != nil else {
            return .rejected("\(path):dynamicWorldSpaceTransform")
        }
        let maximum = child.maximumCount ?? 512
        guard maximum > 0, maximum <= 512 else {
            return .rejected("\(path):invalidSystemLimit")
        }
        let authoredMaximum = min(max(asset.definition.maximumCount ?? 1, 0), 20000)
        let particleBudget = authoredMaximum
        // Detached leaves can overlap new parent scopes until their particles drain.
        let systemBudget = trigger == .staticChild && depth == 2
            ? SceneParticleChildLifecycle.maximumSystemsPerDepth : maximum
        if !simulationOnly, !permitsStaticRope {
            var remainingSegments = SceneParticleChildTemplateSupport.maximumRopeSegmentsPerTemplate
            let rendererCount = plans.count
            plans.removeAll { plan in
                guard let rope = plan.rope else { return false }
                let segments = rope.maximumGeneratedSegments * systemBudget
                guard segments <= remainingSegments else { return true }
                remainingSegments -= segments
                return false
            }
            guard !plans.isEmpty else { return .rejected("\(path):ropeAggregateSegmentBudget") }
            if plans.count != rendererCount {
                result.unsupportedDetails.append("\(path):ropeAggregateSegmentBudget")
            }
        }
        var preparationFailures: [String] = []
        let renderers = simulationOnly ? [] : SceneParticlePreparedRenderer.prepare(
            plans: plans, asset: asset, rootUsesWorldSpace: false, textureLoader: textureLoader,
            builtInTextureRegistry: builtInTextureRegistry, device: device,
            onFailure: { index, detail in
                preparationFailures.append("\(path):renderer[\(index)]:\(detail)")
            }
        )
        guard !renderers.isEmpty || simulationOnly else {
            return .rejected(preparationFailures.first ?? "\(path):rendererPreparationUnavailable")
        }
        result.unsupportedDetails.append(contentsOf: preparationFailures)
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
        var particleControlPointMask: UInt8 = 0
        if let start = particleControlPointStart {
            particleControlPointMask = UInt8.max << start
            for point in asset.definition.controlPoints
                where point.copiesRawParentValue || point.isWorldSpace || point.followsPointer {
                if let id = point.id, (0 ... 7).contains(id) {
                    particleControlPointMask &= ~(UInt8(1) << id)
                }
            }
        }
        let template = SceneParticleChildTemplate(
            index: templateIndex,
            path: path,
            definition: asset.definition,
            pointerControlPointIdentities: asset.definition.pointerControlPointIdentities,
            needsWorldControlPointFrame: needsWorldPointFrame,
            trigger: trigger,
            renderers: renderers,
            worldSpaceFrame: worldSpaceFrame,
            probability: probability,
            transform: transform,
            maximumSystemCount: maximum,
            particleBudget: particleBudget,
            depth: depth,
            parentAssetPath: parentAssetPath,
            instanceOverride: instanceOverride,
            particleControlPointStart: particleControlPointStart,
            particleControlPointMask: particleControlPointMask,
            usesLocalParentControlPointFallback: usesLocalParentControlPointFallback
        )
        return .accepted(template, asset)
    }
}

extension SceneParticleChildTemplate {
    func simulator(
        seed: UInt64, timing: SceneParticleFrameTiming, sceneIsOrthographic: Bool,
        dynamicInstanceValues: SceneDynamicParticleValues? = nil,
        origin: SIMD3<Double> = .zero,
        controlPointFrame: SceneParticleControlPointFrame? = nil,
        worldSpaceFrameOverride: SceneParticleWorldSpaceFrame? = nil,
        rootTranslationOffset: SIMD3<Double> = .zero,
        initialDynamicControlPoints: [Int: SIMD3<Double>] = [:],
        initialDynamicControlPointAngles: [Int: SIMD3<Double>] = [:],
        initialAudioInput: SceneParticleAudioInput = .silent,
        hasChildStreamOrigin: Bool = false,
        maximumEmissionDuration: Double? = nil,
        eventValueContext: SceneParticleEventValueContext = .unavailable
    ) -> SceneParticleSimulator {
        let simulator = SceneParticleSimulator(
            definition: definition,
            instanceOverride: instanceOverride,
            initialDynamicInstanceOverride: instanceOverride?.resolving(dynamicInstanceValues),
            initialDynamicControlPoints: initialDynamicControlPoints,
            initialDynamicControlPointAngles: initialDynamicControlPointAngles,
            initialAudioInput: initialAudioInput,
            initialTiming: timing, sceneIsOrthographic: sceneIsOrthographic,
            seed: seed,
            particleBudget: particleBudget,
            maximumEmissionDuration: maximumEmissionDuration,
            worldSpaceFrame: worldSpaceFrameOverride ?? worldSpaceFrame,
            controlPointForceEnvironment: .init(allowsLocalParentFallback: usesLocalParentControlPointFallback),
            controlPointFrame: needsWorldControlPointFrame
                ? controlPointFrame?.childFrame(origin: origin - (definition.flags.isWorldSpace ? rootTranslationOffset : .zero), scale: transform.scale) : nil,
            initialControlPointParticleSpace: definition.flags.isWorldSpace
                ? .init(currentOrigin: origin, scale: transform.scale, birthOrigins: [:]) : nil,
            hasChildStreamOrigin: hasChildStreamOrigin,
            eventValueContext: eventValueContext
        )
#if DEBUG
        simulator.observeSelectedRenderers(typedIndices: renderers.map(\.index))
#endif
        return simulator
    }

    func instance(
        renderer: SceneParticlePreparedRenderer,
        origin: SIMD3<Double>,
        particle: SceneParticleState,
        layerAlpha: Float
    ) -> SceneParticleGPUInstance {
        let frames = SceneParticleRuntime.spriteFrames(
            animation: renderer.spriteAnimation,
            staticAspect: renderer.staticSpriteAspect,
            definition: definition,
            particleID: particle.id,
            age: Float(particle.age),
            lifetime: Float(particle.lifetime)
        )
        let velocity = transform.velocity(particle.velocity)
        let trail = renderer.trail?.geometry(for: velocity)
        return SceneParticleGPUInstance(
            position: (origin + transform.position(particle.position)).particleFloatValue,
            size: Float(transform.size(particle.size)),
            rotation: particle.rotation.particleFloatValue,
            color: particle.color.particleFloatValue,
            alpha: Float(particle.alpha) * layerAlpha,
            velocity: trail?.direction ?? velocity.particleFloatValue,
            trailStretch: trail?.stretch,
            currentFrame: frames.current.orientedForTrail(trail != nil),
            nextFrame: frames.next?.orientedForTrail(trail != nil),
            currentFrameAspect: frames.currentAspect,
            nextFrameAspect: frames.nextAspect,
            frameMix: frames.mix
        )
    }
}
