import Foundation
import Metal

enum SceneParticleChildControlPointCopyAdmission {
    case disabled
    case supported(SceneParticleInstanceOverride, count: Int)
    case unsupported(String)
}

enum SceneParticleChildTemplateSupport {
    static func rawParentControlPointOverride(
        childDefinition: SceneParticleDefinition,
        rootDefinition: SceneParticleDefinition,
        rootOverride: SceneParticleInstanceOverride?,
        allowsCopy: Bool
    ) -> SceneParticleChildControlPointCopyAdmission {
        let mappings = childDefinition.controlPoints.filter {
            $0.parentControlPoint != nil || $0.copiesRawParentValue
        }
        guard !mappings.isEmpty else { return .disabled }
        guard mappings.allSatisfy({ $0.parentControlPoint != nil }) else {
            return .unsupported("rawParentControlPointCopyMalformed")
        }
        guard allowsCopy else { return .unsupported("rawParentControlPointCopyOutsideStaticDepthOne") }
        var values: [Int: SceneParticleBoundValue] = [:]
        for mapping in mappings {
            guard let childID = mapping.id, (0 ... 7).contains(childID),
                  let parentID = mapping.parentControlPoint, (0 ... 7).contains(parentID),
                  mapping.rawFlags == 4, values[childID] == nil,
                  isZeroVector(mapping.offset), isZeroVector(mapping.angles)
            else { return .unsupported("rawParentControlPointCopyMalformed") }
            let sources = rootDefinition.controlPoints.filter { $0.id == parentID }
            guard sources.count == 1,
                  var value = finiteVector(sources[0].offset, fallback: .zero)
            else { return .unsupported("rawParentControlPointSourceUnavailable") }
            if let authored = rootOverride?.controlPoints[parentID] {
                guard authored.userPropertyKey == nil, !authored.hasScript, !authored.hasAnimation,
                      let override = finiteVector(authored.value, fallback: nil)
                else { return .unsupported("rawParentControlPointSourceDynamic") }
                value += override
            }
            values[childID] = SceneParticleBoundValue(
                value: .vector([value.x, value.y, value.z]),
                userPropertyKey: nil, hasScript: false, hasAnimation: false
            )
        }
        return .supported(SceneParticleInstanceOverride(
            id: nil, alpha: nil, size: nil, lifetime: nil, rate: nil, speed: nil,
            count: nil, brightness: nil, color: nil, normalizedColor: nil,
            controlPoints: values, controlPointAngles: [:]
        ), count: values.count)
    }

    static func staticOriginTranslation(_ child: SceneParticleChild) -> SIMD3<Double>? {
        let origin = SceneParticleSimulationMath.vector(child.origin, fallback: .zero)
        let angles = SceneParticleSimulationMath.vector(child.angles, fallback: .zero)
        let scale = SceneParticleSimulationMath.vector(child.scale, fallback: SIMD3(repeating: 1))
        guard origin.x.isFinite, origin.y.isFinite, origin.z.isFinite,
              angles == .zero, scale == SIMD3(repeating: 1) else { return nil }
        return origin
    }

    static func hasIdentityTransform(_ child: SceneParticleChild) -> Bool {
        staticOriginTranslation(child) == .zero
    }

    private static func finiteVector(
        _ value: SceneParticleNumericValue?, fallback: SIMD3<Double>?
    ) -> SIMD3<Double>? {
        guard let value else { return fallback }
        guard case let .vector(components) = value, components.count == 3,
              components.allSatisfy(\.isFinite) else { return nil }
        return SIMD3(components[0], components[1], components[2])
    }

    private static func isZeroVector(_ value: SceneParticleNumericValue?) -> Bool {
        guard let resolved = finiteVector(value, fallback: .zero) else { return false }
        return resolved == .zero
    }

    static func supportedRenderer(
        in definition: SceneParticleDefinition
    ) -> (renderer: SceneParticleRenderer, trail: SceneParticleTrailRenderPlan?)? {
        for renderer in definition.renderers {
            switch renderer.kind {
            case .sprite:
                return (renderer, nil)
            case .spriteTrail:
                guard let trail = SceneParticleTrailRenderPlan(
                    length: renderer.length,
                    minimumLength: renderer.minimumLength,
                    maximumLength: renderer.maximumLength
                ) else { continue }
                return (renderer, trail)
            default:
                continue
            }
        }
        return nil
    }

    static func loadTexture(
        _ source: SceneParticleTextureSource,
        textureLoader: SceneTextureLoader,
        builtInTextureRegistry: SceneParticleBuiltInTextureRegistry,
        device: MTLDevice
    ) -> (
        texture: MTLTexture,
        animation: SceneSpriteAnimation?,
        sampling: SceneParticleTextureSampling
    )? {
        switch source {
        case let .file(url):
            guard case let .loaded(texture) = textureLoader.load(from: url, device: device) else {
                return nil
            }
            let container = textureLoader.texContainer(from: url)
            return (
                SceneParticleColorTextureAdapter.adapt(texture, device: device),
                container.flatMap {
                    SceneSpriteAnimation(container: $0, sourceURL: url)
                },
                container.map { SceneParticleTextureSampling(texFlags: $0.flags) }
                    ?? .directImageFallback
            )
        case let .builtIn(key):
            guard let texture = builtInTextureRegistry.texture(for: key) else { return nil }
            return (texture, nil, .directImageFallback)
        }
    }
}
