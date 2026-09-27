import Foundation
import Metal

enum SceneParticleChildControlPointCopyAdmission {
    case disabled
    case ignoredUnused(count: Int)
    case supported(SceneParticleInstanceOverride, count: Int)
    case unsupported(String)
}

enum SceneParticleChildEventColorAdmission {
    case disabled
    case supported([String])
    case unsupported(String)
}

/// Project-owned bounded child transform profile. Screen-plane scale stays uniform;
/// mirroring, rotation, nested scaling, ropes, and world-space movement remain fail-closed.
struct SceneParticleChildTransform: Equatable {
    private static let minimumScale = 1.0 / 1_024.0
    private static let maximumScale = 1_024.0

    let origin: SIMD3<Double>
    let scale: SIMD3<Double>

    var hasScale: Bool { scale != SIMD3(repeating: 1) }

    init?(child: SceneParticleChild, allowsOrigin: Bool) {
        guard !child.hasMalformedTransformFields,
              let origin = Self.vector(child.origin, fallback: .zero),
              let angles = Self.vector(child.angles, fallback: .zero),
              let scale = Self.vector(child.scale, fallback: SIMD3(repeating: 1)),
              angles == .zero,
              allowsOrigin || origin == .zero,
              scale.x == scale.y,
              scale.x >= Self.minimumScale, scale.x <= Self.maximumScale,
              scale.z >= Self.minimumScale, scale.z <= Self.maximumScale
        else { return nil }
        self.origin = origin
        self.scale = scale
    }

    func position(_ value: SIMD3<Double>) -> SIMD3<Double> {
        value * scale
    }

    func inversePosition(_ value: SIMD3<Double>) -> SIMD3<Double> {
        value / scale
    }

    func velocity(_ value: SIMD3<Double>) -> SIMD3<Double> {
        value * scale
    }

    func size(_ value: Double) -> Double {
        value * scale.x
    }

    private static func vector(
        _ value: SceneParticleNumericValue?, fallback: SIMD3<Double>
    ) -> SIMD3<Double>? {
        guard let value else { return fallback }
        guard case let .vector(components) = value, components.count == 3,
              components.allSatisfy(\.isFinite) else { return nil }
        return SIMD3(components[0], components[1], components[2])
    }
}

enum SceneParticleChildTemplateSupport {
    static func eventColorAdmission(
        definition: SceneParticleDefinition,
        trigger: SceneParticleChildTrigger
    ) -> SceneParticleChildEventColorAdmission {
        let initializers = definition.initializers.compactMap { initializer -> SceneParticleEventColorDeclaration? in
            guard case let .inheritEventColor(value) = initializer.kind else { return nil }
            return value
        }
        let operators = definition.operators.compactMap { value -> SceneParticleEventColorDeclaration? in
            guard case let .inheritEventColor(declaration) = value.kind else { return nil }
            return declaration
        }
        guard !initializers.isEmpty || !operators.isEmpty else { return .disabled }
        guard initializers.allSatisfy(\.isBoundedSetColor) else {
            return .unsupported("eventColorInitializerUnsupported")
        }
        guard operators.allSatisfy(\.isBoundedSetColor) else {
            return .unsupported("eventColorOperatorUnsupported")
        }
        guard initializers.isEmpty || trigger != .staticChild else {
            return .unsupported("eventColorInitializerOutsideEventChild")
        }
        guard operators.isEmpty || trigger == .follow else {
            return .unsupported("eventColorOperatorOutsideFollowChild")
        }
        var markers: [String] = []
        if !initializers.isEmpty {
            markers.append("eventColorInitializerBounded:setcolor")
        }
        if !operators.isEmpty {
            markers.append("eventColorOperatorBounded:setcolor")
        }
        return .supported(markers)
    }

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
        let hasKnownConsumer = childDefinition.emitters.contains { $0.controlPoint != nil }
            || childDefinition.operators.contains { $0.controlPoint != nil }
        let hasUnknownConsumer = childDefinition.initializers.contains {
            if case .unsupported = $0.kind { return true }
            return false
        } || childDefinition.operators.contains {
            if case .unsupported = $0.kind { return true }
            return false
        }
        let isInertMappingShape = mappings.allSatisfy {
            $0.parentControlPoint != nil && $0.rawFlags == 0
                && isZeroVector($0.offset) && isZeroVector($0.angles)
        }
        if isInertMappingShape, !hasKnownConsumer, !hasUnknownConsumer,
           childDefinition.children.isEmpty
        {
            return .ignoredUnused(count: mappings.count)
        }
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

    static func transform(
        _ child: SceneParticleChild, allowsOrigin: Bool
    ) -> SceneParticleChildTransform? {
        SceneParticleChildTransform(child: child, allowsOrigin: allowsOrigin)
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
    ) -> (
        renderer: SceneParticleRenderer,
        trail: SceneParticleTrailRenderPlan?,
        rope: SceneParticleRopePlan?
    )? {
        for renderer in definition.renderers {
            switch renderer.kind {
            case .sprite:
                return (renderer, nil, nil)
            case .spriteTrail:
                guard let trail = SceneParticleTrailRenderPlan(
                    length: renderer.length,
                    minimumLength: renderer.minimumLength,
                    maximumLength: renderer.maximumLength,
                    hasMalformedFields: renderer.hasMalformedFields
                ) else { continue }
                return (renderer, trail, nil)
            case .rope:
                guard let rope = SceneParticleRopePlan(
                    renderer: renderer,
                    rendererCount: definition.renderers.count,
                    maximumParticleCount: definition.maximumCount ?? 1
                ) else { continue }
                return (renderer, nil, rope)
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
        sampling: SceneParticleTextureSampling,
        uvScale: SIMD2<Float>,
        staticAspect: Float
    )? {
        switch source {
        case let .file(url):
            guard let sourceIdentity = textureLoader.sourceKey(for: url) else { return nil }
            let container = textureLoader.texContainer(from: url)
            let animation = container.flatMap {
                SceneSpriteAnimation(container: $0, sourceURL: url)
            }
            var uvScale = SIMD2<Float>(repeating: 1)
            var staticAspect: Float = 1
            let texture: MTLTexture
            // Preserve the existing first-frame fallback for an unplayable
            // atlas. Static files use the loader's validated output geometry:
            // raw uploads can be cropped while embedded images retain padding.
            if container == nil || (container?.spriteFrames.isEmpty == true
                && container?.imageCount == 1 && container?.isAnimated == false) {
                guard case let .loaded(candidate) = textureLoader.loadCandidate(
                    from: url, purpose: .straightAlbedo, device: device
                ) else { return nil }
                texture = candidate.texture
                uvScale = SIMD2(
                    Float(candidate.mappedSize.width / candidate.physicalSize.width),
                    Float(candidate.mappedSize.height / candidate.physicalSize.height)
                )
                // Keep the authored ratio even if the upload was normalized to
                // the device budget and its integer dimensions were rounded.
                staticAspect = container.map {
                    Float($0.imageWidth) / Float($0.imageHeight)
                } ?? Float(candidate.mappedSize.width / candidate.mappedSize.height)
            } else {
                guard case let .loaded(value) = textureLoader.load(
                    from: url, purpose: .straightAlbedo, device: device
                )
                else { return nil }
                texture = value
            }
            guard let colorTexture = SceneParticleColorTextureAdapter.adapt(
                texture
            ), textureLoader.sourceKey(for: url) == sourceIdentity else { return nil }
            return (
                colorTexture, animation,
                container.map { SceneParticleTextureSampling(texFlags: $0.flags) }
                    ?? .directImageFallback,
                uvScale, staticAspect
            )
        case let .builtIn(key):
            guard let texture = builtInTextureRegistry.texture(for: key) else { return nil }
            return (texture, nil, .directImageFallback, SIMD2(repeating: 1),
                    Float(texture.width) / Float(texture.height))
        }
    }
}

extension SceneParticleChildTemplate {
    func eventColorContext(
        for parent: SceneParticleState
    ) -> SceneParticleEventColorContext {
        switch trigger {
        case .spawn, .death:
            .snapshot(parent.color)
        case .follow:
            .follow(parent.color)
        case .staticChild:
            .unavailable
        }
    }
}
