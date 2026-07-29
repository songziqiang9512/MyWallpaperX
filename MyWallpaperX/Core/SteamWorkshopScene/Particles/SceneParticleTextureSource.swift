import Foundation
import Metal

nonisolated struct SceneParticleTextureSampling: Equatable, Sendable {
    enum Filter: String, Equatable, Sendable {
        case linear
        case nearest
    }

    enum AddressMode: String, Equatable, Sendable {
        case clampToEdge
        case repeatWrap
    }

    let filter: Filter
    let addressMode: AddressMode
    let usesClampBorderFallback: Bool

    static let directImageFallback = SceneParticleTextureSampling(
        filter: .linear,
        addressMode: .clampToEdge,
        usesClampBorderFallback: false
    )

    init(texFlags: UInt32) {
        filter = texFlags & 1 == 0 ? .linear : .nearest
        usesClampBorderFallback = texFlags & 8 != 0
        addressMode = usesClampBorderFallback || texFlags & 2 != 0
            ? .clampToEdge
            : .repeatWrap
    }

    private init(
        filter: Filter,
        addressMode: AddressMode,
        usesClampBorderFallback: Bool
    ) {
        self.filter = filter
        self.addressMode = addressMode
        self.usesClampBorderFallback = usesClampBorderFallback
    }
}

/// The particle fragment shader multiplies the sampled texel straight into the
/// premultiplied blend chain, so every color texture must satisfy RGB == color * A.
/// Authored/stock TEX may arrive as R8 (grayscale mask) or RG88 (luminance +
/// alpha); sampling those natively yields (r,0,0,1)/(r,g,0,1) and floods layers
/// with red or amber. Adapt them here, at the particle consumer, so shared
/// data-texture users (flow, phase, normal maps) keep native channels.
enum SceneParticleColorTextureAdapter {
    static func adapt(_ texture: MTLTexture, device: MTLDevice) -> MTLTexture {
        switch texture.pixelFormat {
        case .r8Unorm:
            return texture.makeTextureView(
                pixelFormat: .r8Unorm,
                textureType: .type2D,
                levels: 0..<texture.mipmapLevelCount,
                slices: 0..<1,
                swizzle: MTLTextureSwizzleChannels(
                    red: .red, green: .red, blue: .red, alpha: .red
                )
            ) ?? texture
        case .rg8Unorm:
            return expandLuminanceAlpha(texture, device: device) ?? texture
        default:
            return texture
        }
    }

    private static func expandLuminanceAlpha(
        _ texture: MTLTexture,
        device: MTLDevice
    ) -> MTLTexture? {
        guard texture.storageMode == .shared else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: texture.width,
            height: texture.height,
            mipmapped: texture.mipmapLevelCount > 1
        )
        descriptor.mipmapLevelCount = texture.mipmapLevelCount
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let output = device.makeTexture(descriptor: descriptor) else { return nil }
        for level in 0..<texture.mipmapLevelCount {
            let width = max(texture.width >> level, 1)
            let height = max(texture.height >> level, 1)
            var source = [UInt8](repeating: 0, count: width * height * 2)
            texture.getBytes(
                &source,
                bytesPerRow: width * 2,
                from: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: level
            )
            var expanded = [UInt8](repeating: 0, count: width * height * 4)
            for index in 0..<(width * height) {
                let luminance = UInt16(source[index * 2])
                let alpha = UInt16(source[index * 2 + 1])
                let premultiplied = UInt8((luminance * alpha + 127) / 255)
                expanded[index * 4] = premultiplied
                expanded[index * 4 + 1] = premultiplied
                expanded[index * 4 + 2] = premultiplied
                expanded[index * 4 + 3] = UInt8(alpha)
            }
            expanded.withUnsafeBytes { buffer in
                output.replace(
                    region: MTLRegionMake2D(0, 0, width, height),
                    mipmapLevel: level,
                    withBytes: buffer.baseAddress!,
                    bytesPerRow: width * 4
                )
            }
        }
        return output
    }
}

nonisolated enum SceneParticleBuiltInTexture: String, Hashable, Sendable {
    case chromaticDot = "particle/chromaticdot"
    case beam1 = "particle/beam/beam_1"
    case drop = "particle/drop"
    case fire1 = "particle/fire/fire1"
    case fog1 = "particle/fog/fog1"
    case fog3 = "particle/fog/fog3"
    case leaves7 = "particle/nature/leaves7"
    case leaves8 = "particle/nature/leaves8"
    case snow = "particle/nature/snow"
    case lightShafts0 = "particle/light/light_shafts_0"
    case lightShafts6 = "particle/light/light_shafts_6"
    case lightning3 = "particle/lightning/lightning3"
    case halo = "particle/halo"
    case halo2 = "particle/halo_2"
    case halo3 = "particle/halo_3"
    case halo4 = "particle/halo_4"
    case halo6 = "particle/halo_6"
    case star = "particle/star"
    case flare1 = "particle/light/flare_1"
    case rippleSingle = "particle/water/ripple_single"
    case rosePetals = "particle/nature/rosepetals"
    case smoke2 = "particle/smoke/smoke2"
}

nonisolated enum SceneParticleTextureSource: Equatable, Sendable {
    case file(URL)
    case builtIn(SceneParticleBuiltInTexture)

    nonisolated init?(reference rawReference: String) {
        var reference = rawReference
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
            .lowercased()
        while reference.hasPrefix("./") {
            reference.removeFirst(2)
        }
        if reference.hasPrefix("materials/") {
            reference.removeFirst("materials/".count)
        }

        guard let builtIn = SceneParticleBuiltInTexture(rawValue: reference) else {
            return nil
        }
        self = .builtIn(builtIn)
    }
}
