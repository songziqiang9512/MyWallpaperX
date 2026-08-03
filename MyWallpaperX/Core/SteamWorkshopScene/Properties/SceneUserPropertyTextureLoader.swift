import Foundation
import Metal

struct SceneUserPropertyTextureLoadResult {
    let textures: [String: MTLTexture]
    let textureCandidates: [String: SceneTextureCandidate]
    let straightAlbedoTextures: [String: MTLTexture]
    let preservedTextures: [String: MTLTexture]
    let reportLines: [String]
}

struct SceneUserPropertyTextureLoader {
    private static let supportedFileExtensions: Set<String> = ["png", "jpg", "jpeg"]

    static func supports(url: URL) -> Bool {
        supportedFileExtensions.contains(url.pathExtension.localizedLowercase)
    }

    func load(
        urlsByPropertyKey: [String: URL],
        straightAlbedoPropertyKeys: Set<String> = [],
        preservedPropertyKeys: Set<String> = [],
        device: MTLDevice
    ) -> SceneUserPropertyTextureLoadResult {
        guard !urlsByPropertyKey.isEmpty else {
            return SceneUserPropertyTextureLoadResult(
                textures: [:],
                textureCandidates: [:],
                straightAlbedoTextures: [:],
                preservedTextures: [:],
                reportLines: []
            )
        }
        let loader = SceneTextureLoader()
        var textures: [String: MTLTexture] = [:]
        var textureCandidates: [String: SceneTextureCandidate] = [:]
        var straightAlbedoTextures: [String: MTLTexture] = [:]
        var preservedTextures: [String: MTLTexture] = [:]
        var reportLines = ["sceneUserTextureRequestedCount: \(urlsByPropertyKey.count)"]

        for key in urlsByPropertyKey.keys.sorted() {
            guard let url = urlsByPropertyKey[key] else { continue }
            guard Self.supports(url: url) else {
                reportLines.append("scene user texture \(key): unsupported \(url.pathExtension.lowercased())")
                continue
            }
            switch loader.loadCandidate(
                from: url,
                purpose: .premultipliedColor,
                device: device
            ) {
            case let .loaded(candidate):
                textures[key] = candidate.texture
                textureCandidates[key] = candidate
                reportLines.append(
                    "scene user texture \(key): OK \(url.lastPathComponent) -> "
                        + "\(candidate.texture.width)x\(candidate.texture.height)"
                )
            case let .failed(outcome):
                switch outcome {
                case let .decodeFailed(message):
                    reportLines.append(
                        "scene user texture \(key): decode failed (\(message))"
                    )
                case let .textureAllocationFailed(width, height):
                    reportLines.append(
                        "scene user texture \(key): allocation failed at \(width)x\(height)"
                    )
                case .unsupportedFormat, .unsupportedTexFormat,
                     .texNoEmbeddedImage, .texContainsVideoPayload:
                    reportLines.append(
                        "scene user texture \(key): unsupported image payload"
                    )
                case .loaded:
                    reportLines.append(
                        "scene user texture \(key): typed candidate unavailable"
                    )
                }
            }
            if straightAlbedoPropertyKeys.contains(key) {
                switch loader.load(
                    from: url,
                    purpose: .straightAlbedo,
                    device: device
                ) {
                case let .loaded(texture):
                    straightAlbedoTextures[key] = texture
                    reportLines.append(
                        "scene user texture \(key) straight albedo: OK "
                            + "\(url.lastPathComponent) -> \(texture.width)x\(texture.height)"
                    )
                case let .decodeFailed(message):
                    reportLines.append(
                        "scene user texture \(key) straight albedo: decode failed (\(message))"
                    )
                case let .textureAllocationFailed(width, height):
                    reportLines.append(
                        "scene user texture \(key) straight albedo: allocation failed at "
                            + "\(width)x\(height)"
                    )
                case .unsupportedFormat, .unsupportedTexFormat,
                     .texNoEmbeddedImage, .texContainsVideoPayload:
                    reportLines.append(
                        "scene user texture \(key) straight albedo: unsupported image payload"
                    )
                }
            }
            if preservedPropertyKeys.contains(key) {
                switch loader.load(
                    from: url,
                    purpose: .preservedChannels,
                    device: device
                ) {
                case let .loaded(texture):
                    preservedTextures[key] = texture
                    reportLines.append(
                        "scene user texture \(key) preserved: OK "
                            + "\(url.lastPathComponent) -> \(texture.width)x\(texture.height)"
                    )
                case let .decodeFailed(message):
                    reportLines.append(
                        "scene user texture \(key) preserved: decode failed (\(message))"
                    )
                case let .textureAllocationFailed(width, height):
                    reportLines.append(
                        "scene user texture \(key) preserved: allocation failed at "
                            + "\(width)x\(height)"
                    )
                case .unsupportedFormat, .unsupportedTexFormat,
                     .texNoEmbeddedImage, .texContainsVideoPayload:
                    reportLines.append(
                        "scene user texture \(key) preserved: unsupported image payload"
                    )
                }
            }
        }
        reportLines.append("sceneUserTextureLoadedCount: \(textures.count)")
        reportLines.append(
            "sceneUserTextureStraightAlbedoLoadedCount: \(straightAlbedoTextures.count)"
        )
        reportLines.append(
            "sceneUserTexturePreservedLoadedCount: \(preservedTextures.count)"
        )
        return SceneUserPropertyTextureLoadResult(
            textures: textures,
            textureCandidates: textureCandidates,
            straightAlbedoTextures: straightAlbedoTextures,
            preservedTextures: preservedTextures,
            reportLines: reportLines
        )
    }
}
