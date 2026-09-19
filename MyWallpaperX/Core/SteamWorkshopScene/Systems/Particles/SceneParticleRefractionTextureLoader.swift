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
        switch declaration.normalTextureSource {
        case nil:
            guard let flatNormal = makeFlatNormalTexture(device: device) else {
                return nil
            }
            normal = flatNormal
            normalCandidate = nil
            normalUsesParticleFrames = false
            normalUVScale = SIMD2(repeating: 1)
            normalSampling = .linearClamp
        case .some(.builtIn):
            return nil
        case let .some(.file(normalURL)):
            guard let normalContainer = textureLoader.texContainer(from: normalURL),
                  [UInt32(0), 4].contains(normalContainer.format) else {
                return nil
            }
            normalSampling = SceneParticleTextureSampling(
                texFlags: normalContainer.flags
            )
            let sameSource = colorURL.standardizedFileURL
                == normalURL.standardizedFileURL
            if sameSource {
                // Both semantic roles preserve the source channels, so an authored
                // same-file binding can reuse only an exact physical upload. An
                // opaque color may be safely rasterized or downscaled for albedo,
                // but that transformed texture must never stand in for normal data.
                guard let firstMip = colorContainer.mips.first,
                      color.width == firstMip.width,
                      color.height == firstMip.height,
                      color.mipmapLevelCount == colorContainer.mips.count else {
                    return nil
                }
                normal = color
                normalCandidate = nil
            } else if normalContainer.imageCount == 1,
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
                normalSampling: normalSampling
            )
        }
        return Loaded(
            color: color,
            colorAnimation: colorFrames.isEmpty
                ? nil : SceneSpriteAnimation(container: colorContainer, sourceURL: colorURL),
            colorUVScale: uvScale(for: colorContainer, usesFrames: !colorFrames.isEmpty),
            colorSampling: SceneParticleTextureSampling(texFlags: colorContainer.flags),
            binding: binding
        )
    }

    /// The author contract permits REFRACT without a normal map. The flat
    /// tangent-space normal keeps displacement neutral while the existing
    /// albedo/coverage and framebuffer composition path remains authoritative.
    private static func makeFlatNormalTexture(device: MTLDevice) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 1,
            height: 1,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return nil
        }
        let flatNormal: [UInt8] = [255, 128, 255, 128]
        flatNormal.withUnsafeBytes { bytes in
            guard let address = bytes.baseAddress else { return }
            texture.replace(
                region: MTLRegionMake2D(0, 0, 1, 1),
                mipmapLevel: 0,
                withBytes: address,
                bytesPerRow: 4
            )
        }
        return texture
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
