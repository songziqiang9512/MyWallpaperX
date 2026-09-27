import Foundation
import Metal

enum SceneParticleRefractionTextureLoader {
    struct Loaded {
        let color: MTLTexture
        let colorAnimation: SceneSpriteAnimation?
        let staticSpriteAspect: Float
        let colorUVScale: SIMD2<Float>
        let colorSampling: SceneParticleTextureSampling
        let binding: SceneParticleRefractionBinding
    }

    static func load(
        colorSource: SceneParticleTextureSource,
        declaration: SceneParticleRefractionDeclaration,
        textureLoader: SceneTextureLoader,
        device: MTLDevice
    ) -> Loaded? {
        guard case let .file(colorURL) = colorSource,
              let colorIdentity = textureLoader.sourceKey(for: colorURL),
              let colorContainer = textureLoader.texContainer(from: colorURL),
              [UInt32(0), 4, 8].contains(colorContainer.format),
              case let .loaded(color) = textureLoader.load(
                  from: colorURL,
                  purpose: .straightAlbedo,
                  device: device
              ) else {
            return nil
        }

        let normalCandidate: SceneTextureCandidate?
        let normal: MTLTexture
        let normalUsesParticleFrames: Bool
        let normalUVScale: SIMD2<Float>
        let normalSampling: SceneParticleTextureSampling
        let normalFormat: SceneShaderTextureFormat?
        var normalIdentity: (url: URL, key: SceneTextureLoader.SourceKey)?
        switch declaration.normalTextureSource {
        case nil:
            // No authored normal means exactly zero displacement. Reuse the
            // albedo as an unobserved binding; the shader skips normal sampling.
            normal = color
            normalFormat = nil
            normalCandidate = nil
            normalUsesParticleFrames = false
            normalUVScale = SIMD2(repeating: 1)
            normalSampling = .linearClamp
        case .some(.builtIn):
            return nil
        case let .some(.file(normalURL)):
            guard let sourceIdentity = textureLoader.sourceKey(for: normalURL),
                  let normalContainer = textureLoader.texContainer(from: normalURL),
                  let format = SceneShaderTextureFormat(rawValue: normalContainer.format),
                  format == .rgba8888 || format == .dxt5 else {
                return nil
            }
            normalIdentity = (normalURL, sourceIdentity)
            normalFormat = format
            normalSampling = SceneParticleTextureSampling(
                texFlags: normalContainer.flags
            )
            // Normal data keeps its own load purpose even for a shared file:
            // straight color may normalize bit depth or gray channels.
            if normalContainer.imageCount == 1,
                      !normalContainer.isAnimated,
                      normalContainer.spriteFrames.isEmpty,
                      !normalSampling.usesClampBorderFallback {
                guard case let .loaded(candidate) = textureLoader.loadCandidate(
                    from: normalURL,
                    purpose: .normal,
                    device: device
                ) else { return nil }
                normal = candidate.texture
                normalCandidate = candidate
            } else {
                guard case let .loaded(value) = textureLoader.load(
                    from: normalURL,
                    purpose: .normal,
                    device: device
                ) else { return nil }
                normal = value
                normalCandidate = nil
            }

            let normalFrames = normalContainer.spriteFrames
            if normalFrames.isEmpty {
                normalUsesParticleFrames = false
            } else {
                guard compatible(colorContainer.spriteFrames, normalFrames) else {
                    return nil
                }
                normalUsesParticleFrames = true
            }
            normalUVScale = uvScale(
                for: normalContainer,
                usesFrames: normalUsesParticleFrames
            )
        }

        let colorFrames = colorContainer.spriteFrames
        let colorEncoding: SceneParticleRefractionBinding.ColorEncoding =
            colorContainer.format == 8 ? .luminanceAlpha : .rgba
        let binding: SceneParticleRefractionBinding
        if let normalCandidate {
            guard let candidateBinding = SceneParticleRefractionBinding(
                normalCandidate: normalCandidate,
                amount: declaration.amount,
                overbright: declaration.overbright,
                colorEncoding: colorEncoding
            ) else { return nil }
            binding = candidateBinding
        } else {
            binding = SceneParticleRefractionBinding(
                normalTexture: normal,
                amount: declaration.amount,
                overbright: declaration.overbright,
                colorEncoding: colorEncoding,
                normalUsesParticleFrames: normalUsesParticleFrames,
                normalUVScale: normalUVScale,
                normalSampling: normalSampling,
                normalFormat: normalFormat
            )
        }
        guard textureLoader.sourceKey(for: colorURL) == colorIdentity else { return nil }
        if let normalIdentity {
            guard textureLoader.sourceKey(for: normalIdentity.url) == normalIdentity.key else {
                return nil
            }
        }
        return Loaded(
            color: color,
            colorAnimation: colorFrames.isEmpty
                ? nil : SceneSpriteAnimation(container: colorContainer, sourceURL: colorURL),
            staticSpriteAspect: colorFrames.isEmpty
                && colorContainer.imageWidth > 0 && colorContainer.imageHeight > 0
                ? Float(colorContainer.imageWidth) / Float(colorContainer.imageHeight) : 1,
            colorUVScale: uvScale(for: colorContainer, usesFrames: !colorFrames.isEmpty),
            colorSampling: SceneParticleTextureSampling(texFlags: colorContainer.flags),
            binding: binding
        )
    }

    private static func compatible(
        _ color: [SceneTexContainer.SpriteFrame],
        _ normal: [SceneTexContainer.SpriteFrame]
    ) -> Bool {
        guard color.count == normal.count, !color.isEmpty else { return false }
        return zip(color, normal).allSatisfy { lhs, rhs in
            lhs.imageIndex == rhs.imageIndex
                && abs(lhs.duration - rhs.duration) < 0.000_01
                && near(lhs.origin, rhs.origin)
                && near(lhs.xAxis, rhs.xAxis)
                && near(lhs.yAxis, rhs.yAxis)
        }
    }

    private static func near(_ lhs: SIMD2<Float>, _ rhs: SIMD2<Float>) -> Bool {
        abs(lhs.x - rhs.x) < 0.000_01 && abs(lhs.y - rhs.y) < 0.000_01
    }

    private static func uvScale(
        for container: SceneTexContainer,
        usesFrames: Bool
    ) -> SIMD2<Float> {
        guard !usesFrames,
              container.textureWidth > 0,
              container.textureHeight > 0 else {
            return SIMD2(repeating: 1)
        }
        return SIMD2(
            min(max(Float(container.imageWidth) / Float(container.textureWidth), 0), 1),
            min(max(Float(container.imageHeight) / Float(container.textureHeight), 0), 1)
        )
    }
}
