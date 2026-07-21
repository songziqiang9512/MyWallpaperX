import Metal

final class SceneOffscreenTexturePool {
    struct Pair {
        let primary: MTLTexture
        let secondary: MTLTexture
        let tertiary: MTLTexture
    }

    private let device: MTLDevice
    private let pixelFormat: MTLPixelFormat
    private let maxDimension: Int
    private var cachedPairs: [String: Pair] = [:]

    init(
        device: MTLDevice,
        pixelFormat: MTLPixelFormat = .bgra8Unorm,
        maxDimension: Int = 2048
    ) {
        self.device = device
        self.pixelFormat = pixelFormat
        self.maxDimension = maxDimension
    }

    func textures(for sourceTexture: MTLTexture) -> Pair? {
        let sourceWidth = max(1, sourceTexture.width)
        let sourceHeight = max(1, sourceTexture.height)
        let longestEdge = max(sourceWidth, sourceHeight)
        let scale = longestEdge > maxDimension ? Double(maxDimension) / Double(longestEdge) : 1
        let width = max(1, Int((Double(sourceWidth) * scale).rounded()))
        let height = max(1, Int((Double(sourceHeight) * scale).rounded()))
        let key = "\(width)x\(height)"
        if let cached = cachedPairs[key] {
            return cached
        }

        guard let primary = makeTexture(width: width, height: height, label: "SceneOffscreenA \(key)"),
              let secondary = makeTexture(width: width, height: height, label: "SceneOffscreenB \(key)"),
              let tertiary = makeTexture(width: width, height: height, label: "SceneOffscreenC \(key)") else {
            return nil
        }

        let pair = Pair(primary: primary, secondary: secondary, tertiary: tertiary)
        cachedPairs[key] = pair
        return pair
    }

    private func makeTexture(width: Int, height: Int, label: String) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        let texture = device.makeTexture(descriptor: descriptor)
        texture?.label = label
        return texture
    }
}
