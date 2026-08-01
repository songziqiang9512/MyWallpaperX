import Foundation

extension SceneParticleRuntime {
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
        if !accepted && !diagnostics.contains(where: {
            $0.kind == .layerImageEmitterUnsupported && $0.layerID == layerID
        }) {
            addDiagnostic(
                kind: .layerImageEmitterUnsupported, layerID: layerID, path: path,
                detail: map == nil ? "emissionMapUnavailable" : "unsupportedEmitterProfile"
            )
        }
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
                frameDurations: animation.frames.map(\.duration),
                age: age,
                lifetime: lifetime,
                sequenceMultiplier: Float(definition.sequenceMultiplier ?? 1),
                particleID: particleID,
                blendsFrames: !definition.flags.disablesFrameBlending
              ) else {
            return (.identity, nil, 1, 1, 0)
        }
        return (
            frameTransform(animation.frames[selection.currentIndex]),
            frameTransform(animation.frames[selection.nextIndex]),
            animation.aspectRatio(forFrameAt: selection.currentIndex),
            animation.aspectRatio(forFrameAt: selection.nextIndex),
            selection.mix
        )
    }

    func supportedRenderer(
        in definition: SceneParticleDefinition,
        layerID: Int,
        path: String
    ) -> (
        renderer: SceneParticleRenderer,
        trail: SceneParticleTrailRenderPlan?,
        ropeTrail: SceneParticleRopeTrailPlan?
    )? {
        let containsRopeTrail = definition.renderers.contains {
            $0.kind == .ropeTrail
        }
        let malformedRendererCollection = definition.diagnostics.contains {
            $0.kind == .malformedComponent && $0.path.hasPrefix("renderer[")
        }
        if containsRopeTrail,
           definition.renderers.count != 1 || malformedRendererCollection {
            addDiagnostic(
                kind: .trailRendererUnsupported,
                layerID: layerID,
                path: path,
                detail: "ropetrail:unsupportedProfile"
            )
            return nil
        }
        var supported: (
            SceneParticleRenderer,
            SceneParticleTrailRenderPlan?,
            SceneParticleRopeTrailPlan?
        )?
        var sawKnownRenderer = false
        for renderer in definition.renderers {
            switch renderer.kind {
            case .sprite:
                sawKnownRenderer = true
                if supported == nil { supported = (renderer, nil, nil) }
            case .spriteTrail:
                sawKnownRenderer = true
                if let trail = SceneParticleTrailRenderPlan(
                    length: renderer.length,
                    minimumLength: renderer.minimumLength,
                    maximumLength: renderer.maximumLength
                ) {
                    if supported == nil { supported = (renderer, trail, nil) }
                } else {
                    addDiagnostic(
                        kind: .trailRendererUnsupported,
                        layerID: layerID,
                        path: path,
                        detail: "spritetrail:invalidLength"
                    )
                }
            case .rope:
                sawKnownRenderer = true
                addDiagnostic(kind: .ropeRendererUnsupported, layerID: layerID, path: path, detail: "rope")
            case .ropeTrail:
                sawKnownRenderer = true
                if let ropeTrail = SceneParticleRopeTrailPlan(
                    renderer: renderer,
                    rendererCount: definition.renderers.count,
                    maximumParticleCount: definition.maximumCount ?? 1
                ) {
                    if supported == nil { supported = (renderer, nil, ropeTrail) }
                } else {
                    addDiagnostic(
                        kind: .trailRendererUnsupported,
                        layerID: layerID,
                        path: path,
                        detail: "ropetrail:unsupportedProfile"
                    )
                }
            case let .unsupported(name):
                addDiagnostic(kind: .missingSpriteRenderer, layerID: layerID, path: path, detail: name)
            }
        }
        if supported == nil && !sawKnownRenderer {
            addDiagnostic(kind: .missingSpriteRenderer, layerID: layerID, path: path)
        }
        return supported
    }

    func supportsRopeTrailTexture(
        plan: SceneParticleRopeTrailPlan?,
        animation: SceneSpriteAnimation?,
        layerID: Int,
        path: String
    ) -> Bool {
        guard plan != nil, animation != nil else { return true }
        addDiagnostic(
            kind: .trailRendererUnsupported,
            layerID: layerID,
            path: path,
            detail: "ropetrail:animatedTexture"
        )
        return false
    }

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

    static func orderedLayers(in descriptor: SceneRenderDescriptor) -> [SceneRenderDescriptor.Layer] {
        let byID = Dictionary(uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0) })
        var seen: Set<Int> = []
        let ordered = descriptor.renderOrderLayerIDs.compactMap { id -> SceneRenderDescriptor.Layer? in
            guard seen.insert(id).inserted else { return nil }
            return byID[id]
        }
        return ordered + descriptor.layers.filter { seen.insert($0.id).inserted }
    }

    static func runtimeKind(
        _ value: SceneParticleAssetDiagnostic.Kind
    ) -> SceneParticleRuntimeDiagnosticKind {
        SceneParticleRuntimeDiagnosticKind(rawValue: value.rawValue) ?? .missingDefinition
    }

    static func frameTransform(
        _ frame: SceneTexContainer.SpriteFrame
    ) -> SceneParticleFrameTransform {
        SceneParticleFrameTransform(origin: frame.origin, xAxis: frame.xAxis, yAxis: frame.yAxis)
    }

    static func textureFailureDescription(_ outcome: SceneTextureLoadOutcome) -> String {
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
        currentParticles: [SceneParticleState],
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
