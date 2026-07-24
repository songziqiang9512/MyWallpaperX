import Foundation

extension SceneParticleRuntime {
    static func spriteFrames(
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
            frameTransform(animation.frames[selection.currentIndex]),
            frameTransform(animation.frames[selection.nextIndex]),
            selection.mix
        )
    }

    func supportedRenderer(
        in definition: SceneParticleDefinition,
        layerID: Int,
        path: String
    ) -> (renderer: SceneParticleRenderer, trail: SceneParticleTrailRenderPlan?)? {
        var supported: (SceneParticleRenderer, SceneParticleTrailRenderPlan?)?
        var sawSpriteRenderer = false
        for renderer in definition.renderers {
            switch renderer.kind {
            case .sprite:
                sawSpriteRenderer = true
                if supported == nil { supported = (renderer, nil) }
            case .spriteTrail:
                sawSpriteRenderer = true
                if let trail = SceneParticleTrailRenderPlan(
                    length: renderer.length,
                    minimumLength: renderer.minimumLength,
                    maximumLength: renderer.maximumLength
                ) {
                    if supported == nil { supported = (renderer, trail) }
                } else {
                    addDiagnostic(
                        kind: .trailRendererUnsupported,
                        layerID: layerID,
                        path: path,
                        detail: "spritetrail:invalidLength"
                    )
                }
            case .rope:
                addDiagnostic(kind: .ropeRendererUnsupported, layerID: layerID, path: path, detail: "rope")
            case .ropeTrail:
                addDiagnostic(kind: .trailRendererUnsupported, layerID: layerID, path: path, detail: "ropetrail")
            case let .unsupported(name):
                addDiagnostic(kind: .missingSpriteRenderer, layerID: layerID, path: path, detail: name)
            }
        }
        if supported == nil && !sawSpriteRenderer {
            addDiagnostic(kind: .missingSpriteRenderer, layerID: layerID, path: path)
        }
        return supported
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
