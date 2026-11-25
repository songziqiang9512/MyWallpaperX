import Foundation
import simd

extension SceneParticleRuntime {
    var playbackSimulators: [(Int, SceneParticleSimulator)] {
        layers.compactMap { layer in layer.rootRender.map { (layer.layerID, $0.simulator) } }
    }
    func playbackVisibility(layerID: Int, dynamicValues: SceneDynamicSnapshot)
        -> SceneParticlePlaybackVisibility? {
        guard let index = layers.firstIndex(where: { $0.layerID == layerID }) else { return nil }
        let visible = SceneLayerVisibility.isEffectivelyVisible(layerID: layerID, in: descriptor,
            layersByID: visibilityLayersByID, snapshot: dynamicValues)
        return .init(isVisible: visible, resetsPopulation: !visible
            || (layers[index].wasVisible != nil && layers[index].wasVisible != visible))
    }
    func emissionContext(layerID: Int, sceneTime: Double = 0, dynamicValues: SceneDynamicSnapshot,
                         pointerLocalPosition: SIMD3<Double>?, audio: SceneParticleAudioInput,
                         worldFrame: simd_float4x4?) throws -> SceneParticleSimulator.EmissionContext {
        guard let layer = layers.first(where: { $0.layerID == layerID }), let root = layer.rootRender else {
            throw SceneParticleEmissionFailure.unavailable
        }
        var points = dynamicValues.particleControlPoints(layerID: layerID)
        points.merge(root.definition.pointerControlPointValues(at: pointerLocalPosition,
            identities: root.pointerControlPointIdentities)) { _, pointer in pointer }
        let world = worldFrame.flatMap { current in
            if let plan = rootWorldTranslationPlans[layerID] {
                return plan.frame(currentWorldFrame: current)
            }
            return SceneParticleWorldSpaceFrame(worldFrame: current)
        }
        if worldSpaceRequiringLayerIDs.contains(layerID), world == nil {
            throw SceneParticleEmissionFailure.unavailable
        }
        let authoredOverride = root.simulator.instanceOverride
        return .init(sceneTime: sceneTime, controlPoints: points,
            controlPointAngles: dynamicValues.particleControlPointAngles(layerID: layerID),
            instanceOverride: SceneParticleInstanceOverride.resolving(authored: authoredOverride,
                dynamic: dynamicValues.particleInstanceValues(layerID: layerID),
                brightness: dynamicValues.particleBrightness(
                    layerID: layerID, isBound: authoredOverride?.brightness?.userPropertyKey != nil
                )),
            audio: audio, worldFrame: world,
            controlPointFrame: root.simulator.needsWorldControlPointFrame
                ? .init(worldFrame: worldFrame, sceneOrthoHeight: descriptor.camera.orthoHeight) : nil)
    }
    func playbackObservation(layerID: Int) -> SceneParticlePlaybackObservation? {
        layers.first { $0.layerID == layerID }?.rootRender?.simulator.playbackObservation
    }

    func adoptPlayback(_ states: [Int: SceneParticlePlaybackSnapshot]) {
        for (layerID, simulator) in playbackSimulators {
            simulator.adoptPlayback(states[layerID] ?? .init())
        }
    }

    /// Official particle containers parse `renderer` and `children` as
    /// independent collections. We admit only the bounded form whose root has
    /// no renderer and whose complete root-child set is static and executable;
    /// event children still require a root simulator and therefore fail closed.
    func admitsChildOnlyContainer(
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
        guard accepted else {
#if DEBUG
            addDiagnostic(
                kind: .missingSpriteRenderer,
                layerID: layerID,
                path: path,
                detail: definition.children.isEmpty
                    ? nil : "rootRendererAbsentOutsideStrictStaticChildContainer"
            )
#endif
            return false
        }
        return true
    }

    func admitsLayerImageEmitters(
        _ definition: SceneParticleDefinition,
        map: SceneParticleLayerImageEmissionMap?,
        layerID: Int,
        path: String
    ) -> Bool {
        guard definition.emitters.contains(where: { $0.kind == .layerImage }) else {
            return true
        }
        let accepted = map != nil && Self.supportsLayerImageEmitterProfile(definition)
#if DEBUG
        if !accepted && !diagnostics.contains(where: {
            $0.kind == .layerImageEmitterUnsupported && $0.layerID == layerID
        }) {
            addDiagnostic(
                kind: .layerImageEmitterUnsupported, layerID: layerID, path: path,
                detail: map == nil ? "emissionMapUnavailable" : "unsupportedEmitterProfile"
            )
        }
#endif
        return accepted
    }

    static func supportsLayerImageEmitterProfile(
        _ definition: SceneParticleDefinition
    ) -> Bool {
        definition.emitters.allSatisfy { emitter in
            guard emitter.kind == .layerImage else { return true }
            return emitter.origin == nil && emitter.directions == nil && emitter.sign == nil
                && emitter.distanceMinimum == nil && emitter.distanceMaximum == nil
                && emitter.speedMinimum == nil && emitter.speedMaximum == nil
                && emitter.controlPoint == nil && emitter.rawFlags == 0
                && !emitter.audioResponse.isEnabled
        }
    }

    static func spriteFrames(
        animation: SceneSpriteAnimation?,
        staticAspect: Float,
        definition: SceneParticleDefinition,
        particleID: UInt64,
        age: Float,
        lifetime: Float
    ) -> (
        current: SceneParticleFrameTransform,
        next: SceneParticleFrameTransform?,
        currentAspect: Float,
        nextAspect: Float,
        mix: Float
    ) {
        guard let animation,
              let selection = SceneParticleSpriteFrameSelector.select(
                mode: SceneParticleSpriteAnimationMode(authoredValue: definition.animationMode),
                frameDurations: animation.frameDurations,
                frameEndTimes: animation.frameEndTimes,
                totalDuration: animation.duration,
                age: age,
                lifetime: lifetime,
                sequenceMultiplier: Float(definition.sequenceMultiplier ?? 1),
                particleID: particleID,
                blendsFrames: !definition.flags.disablesFrameBlending
              ) else {
            return (.identity, nil, staticAspect, staticAspect, 0)
        }
        return (
            frameTransform(animation.frames[selection.currentIndex]),
            frameTransform(animation.frames[selection.nextIndex]),
            animation.aspectRatio(forFrameAt: selection.currentIndex),
            animation.aspectRatio(forFrameAt: selection.nextIndex),
            selection.mix
        )
    }

    func supportedRenderers(
        in definition: SceneParticleDefinition, layerID: Int, path: String
    ) -> [SceneParticleRendererPlan] {
        var plans: [SceneParticleRendererPlan] = []
        for (index, renderer) in definition.renderers.enumerated() {
            switch renderer.kind {
            case .sprite:
                plans.append(.init(index: index, renderer: renderer, trail: nil, rope: nil, ropeTrail: nil))
            case .spriteTrail:
                if let trail = SceneParticleTrailRenderPlan(
                    length: renderer.length, minimumLength: renderer.minimumLength,
                    maximumLength: renderer.maximumLength,
                    hasMalformedFields: renderer.hasMalformedFields
                ) {
                    plans.append(.init(index: index, renderer: renderer, trail: trail, rope: nil, ropeTrail: nil))
                } else {
#if DEBUG
                    addDiagnostic(kind: .trailRendererUnsupported, layerID: layerID,
                                  path: path, detail: "spritetrail:invalidLength")
#endif
                }
            case .rope:
                if let rope = SceneParticleRopePlan(
                    renderer: renderer, maximumParticleCount: definition.maximumCount ?? 1
                ) {
                    plans.append(.init(index: index, renderer: renderer, trail: nil, rope: rope, ropeTrail: nil))
                } else {
#if DEBUG
                    addDiagnostic(kind: .ropeRendererUnsupported, layerID: layerID,
                                  path: path, detail: "rope:unsupportedProfile")
#endif
                }
            case .ropeTrail:
                if let history = SceneParticleRopeTrailPlan(
                    renderer: renderer, maximumParticleCount: definition.maximumCount ?? 1
                ) {
                    plans.append(.init(index: index, renderer: renderer, trail: nil, rope: nil, ropeTrail: history))
                } else {
#if DEBUG
                    addDiagnostic(kind: .trailRendererUnsupported, layerID: layerID,
                                  path: path, detail: "ropetrail:unsupportedProfile")
#endif
                }
            case let .unsupported(name):
#if DEBUG
                addDiagnostic(kind: .missingSpriteRenderer, layerID: layerID, path: path, detail: name)
#endif
                break
            }
        }
        return plans
    }

#if DEBUG
    func appendSimulationDiagnostics(
        _ values: [SceneParticleSimulationDiagnostic],
        layerID: Int,
        path: String,
        handlesAllChildren: Bool = false
    ) {
        for value in values {
            switch value.kind {
            case .trailRendererIgnored:
                addDiagnostic(kind: .trailRendererUnsupported, layerID: layerID, path: path, detail: value.componentName)
            case .unsupportedRenderer:
                addDiagnostic(kind: .ropeRendererUnsupported, layerID: layerID, path: path, detail: value.componentName)
            case .childSystemsIgnored where handlesAllChildren:
                continue
            case .childSystemsIgnored:
                addDiagnostic(kind: .childSystemsUnsupported, layerID: layerID, path: path, detail: value.componentName)
            default:
                let detail = [value.kind.rawValue, value.componentName].compactMap { $0 }.joined(separator: ":")
                addDiagnostic(kind: .simulationLimitation, layerID: layerID, path: path, detail: detail)
            }
        }
    }

#endif

    static func orderedLayers(in descriptor: SceneRenderDescriptor) -> [SceneRenderDescriptor.Layer] {
        let byID = Dictionary(uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0) })
        var seen: Set<Int> = []
        let ordered = descriptor.renderOrderLayerIDs.compactMap { id -> SceneRenderDescriptor.Layer? in
            guard seen.insert(id).inserted else { return nil }
            return byID[id]
        }
        return ordered + descriptor.layers.filter { seen.insert($0.id).inserted }
    }

#if DEBUG
    static func runtimeKind(
        _ value: SceneParticleAssetDiagnostic.Kind
    ) -> SceneParticleRuntimeDiagnosticKind {
        SceneParticleRuntimeDiagnosticKind(rawValue: value.rawValue) ?? .missingDefinition
    }

#endif

    static func frameTransform(
        _ frame: SceneTexContainer.SpriteFrame
    ) -> SceneParticleFrameTransform {
        SceneParticleFrameTransform(origin: frame.origin, xAxis: frame.xAxis, yAxis: frame.yAxis)
    }
}

extension SceneParticleRopeTrailParticle {
    nonisolated init(state: SceneParticleState) {
        id = state.id
        position = SIMD3(
            Float(state.position.x),
            Float(state.position.y),
            Float(state.position.z)
        )
        size = Float(state.size)
        color = SIMD3(
            Float(state.color.x),
            Float(state.color.y),
            Float(state.color.z)
        )
        alpha = Float(state.alpha)
    }
}

extension SceneParticleRopeTrailHistory {
    mutating func advance(
        snapshots: [SceneParticleStepSnapshot],
        currentParticles: some Collection<SceneParticleState>,
        layerAlpha: Float
    ) -> [SceneParticleGPUInstance] {
        for snapshot in snapshots {
            ingest(
                by: snapshot.duration,
                particles: snapshot.particles.map(SceneParticleRopeTrailParticle.init)
            )
        }
        return advance(
            by: 0,
            particles: currentParticles.map(SceneParticleRopeTrailParticle.init(state:)),
            layerAlpha: layerAlpha
        )
    }
}

extension SceneParticleRopeTrailParticle {
    nonisolated init(_ value: SceneParticleStepParticle) {
        id = value.id
        position = value.position
        size = value.size
        color = value.color
        alpha = value.alpha
    }
}
