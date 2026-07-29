import Foundation
import Metal

enum SceneParticleRefractionTextureLoader {
    struct Loaded {
        let color: MTLTexture
        let colorAnimation: SceneSpriteAnimation?
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
              case let .file(normalURL) = declaration.normalTextureSource,
              let colorContainer = textureLoader.texContainer(from: colorURL),
              let normalContainer = textureLoader.texContainer(from: normalURL),
              [UInt32(0), 4, 8].contains(colorContainer.format),
              [UInt32(0), 4].contains(normalContainer.format),
              case let .loaded(color) = textureLoader.loadDataTexture(
                  from: colorURL,
                  device: device
              ) else {
            return nil
        }

        let normal: MTLTexture
        if colorURL.standardizedFileURL == normalURL.standardizedFileURL {
            normal = color
        } else {
            guard case let .loaded(value) = textureLoader.loadDataTexture(
                from: normalURL,
                device: device
            ) else { return nil }
            normal = value
        }

        let colorFrames = colorContainer.spriteFrames
        let normalFrames = normalContainer.spriteFrames
        let normalUsesParticleFrames: Bool
        if normalFrames.isEmpty {
            normalUsesParticleFrames = false
        } else {
            guard compatible(colorFrames, normalFrames) else { return nil }
            normalUsesParticleFrames = true
        }

        return Loaded(
            color: color,
            colorAnimation: colorFrames.isEmpty
                ? nil : SceneSpriteAnimation(frames: colorFrames),
            colorUVScale: uvScale(for: colorContainer, usesFrames: !colorFrames.isEmpty),
            colorSampling: SceneParticleTextureSampling(texFlags: colorContainer.flags),
            binding: SceneParticleRefractionBinding(
                normalTexture: normal,
                amount: declaration.amount,
                overbright: declaration.overbright,
                colorEncoding: colorContainer.format == 8 ? .luminanceAlpha : .rgba,
                normalUsesParticleFrames: normalUsesParticleFrames,
                normalUVScale: uvScale(
                    for: normalContainer,
                    usesFrames: normalUsesParticleFrames
                ),
                normalSampling: SceneParticleTextureSampling(
                    texFlags: normalContainer.flags
                )
            )
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
