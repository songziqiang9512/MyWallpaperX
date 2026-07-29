import Foundation
import Metal

enum SceneParticleChildTemplateSupport {
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
                    SceneSpriteAnimation(frames: $0.spriteFrames)
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
