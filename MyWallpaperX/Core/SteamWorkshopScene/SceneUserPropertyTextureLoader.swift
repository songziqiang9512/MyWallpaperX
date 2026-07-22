import Foundation
import Metal

struct SceneUserPropertyTextureLoadResult {
    let textures: [String: MTLTexture]
    let reportLines: [String]
}

struct SceneUserPropertyTextureLoader {
    private static let supportedFileExtensions: Set<String> = ["png", "jpg", "jpeg"]

    static func supports(url: URL) -> Bool {
        supportedFileExtensions.contains(url.pathExtension.localizedLowercase)
    }

    func load(
        urlsByPropertyKey: [String: URL],
        device: MTLDevice
    ) -> SceneUserPropertyTextureLoadResult {
        guard !urlsByPropertyKey.isEmpty else {
            return SceneUserPropertyTextureLoadResult(textures: [:], reportLines: [])
        }
        let loader = SceneTextureLoader()
        var textures: [String: MTLTexture] = [:]
        var reportLines = ["sceneUserTextureRequestedCount: \(urlsByPropertyKey.count)"]

        for key in urlsByPropertyKey.keys.sorted() {
            guard let url = urlsByPropertyKey[key] else { continue }
            guard Self.supports(url: url) else {
                reportLines.append("scene user texture \(key): unsupported \(url.pathExtension.lowercased())")
                continue
            }
            switch loader.load(from: url, device: device) {
            case let .loaded(texture):
                textures[key] = texture
                reportLines.append(
                    "scene user texture \(key): OK \(url.lastPathComponent) -> \(texture.width)x\(texture.height)"
                )
            case let .decodeFailed(message):
                reportLines.append("scene user texture \(key): decode failed (\(message))")
            case let .textureAllocationFailed(width, height):
                reportLines.append("scene user texture \(key): allocation failed at \(width)x\(height)")
            case .unsupportedFormat, .unsupportedTexFormat, .texNoEmbeddedImage, .texContainsVideoPayload:
                reportLines.append("scene user texture \(key): unsupported image payload")
            }
        }
        reportLines.append("sceneUserTextureLoadedCount: \(textures.count)")
        return SceneUserPropertyTextureLoadResult(textures: textures, reportLines: reportLines)
    }
}
