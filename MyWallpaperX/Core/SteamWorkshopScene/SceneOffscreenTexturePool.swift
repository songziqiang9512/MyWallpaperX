import Metal

final class SceneOffscreenTexturePool {
    struct Pair {
        let primary: MTLTexture
        let secondary: MTLTexture
        let tertiary: MTLTexture
    }

    private let device: MTLDevice
    private let pixelFormat: MTLPixelFormat
    private struct Entry {
        let pair: Pair
        let byteCost: Int
        var lastAccess: UInt64
    }

    private let maxDimension: Int
    private let byteBudget: Int
    private var cachedPairs: [String: Entry] = [:]
    private var cachedByteCost = 0
    private var accessCounter: UInt64 = 0

    init(
        device: MTLDevice,
        pixelFormat: MTLPixelFormat = .bgra8Unorm,
        maxDimension: Int = 2048,
        byteBudget: Int = 96 * 1_024 * 1_024
    ) {
        self.device = device
        self.pixelFormat = pixelFormat
        self.maxDimension = maxDimension
        self.byteBudget = max(byteBudget, 1)
    }

    func textures(for sourceTexture: MTLTexture) -> Pair? {
        textures(width: sourceTexture.width, height: sourceTexture.height)
    }

    func textures(width requestedWidth: Int, height requestedHeight: Int) -> Pair? {
        let sourceWidth = max(1, requestedWidth)
        let sourceHeight = max(1, requestedHeight)
        let longestEdge = max(sourceWidth, sourceHeight)
        let scale = longestEdge > maxDimension ? Double(maxDimension) / Double(longestEdge) : 1
        let width = max(1, Int((Double(sourceWidth) * scale).rounded()))
        let height = max(1, Int((Double(sourceHeight) * scale).rounded()))
        let key = "\(width)x\(height)"
        accessCounter &+= 1
        if var cached = cachedPairs[key] {
            cached.lastAccess = accessCounter
            cachedPairs[key] = cached
            return cached.pair
        }

        let byteCost = width * height * 4 * 3
        evictUntilAffordable(byteCost)

        guard let primary = makeTexture(width: width, height: height, label: "SceneOffscreenA \(key)"),
              let secondary = makeTexture(width: width, height: height, label: "SceneOffscreenB \(key)"),
              let tertiary = makeTexture(width: width, height: height, label: "SceneOffscreenC \(key)") else {
            return nil
        }

        let pair = Pair(primary: primary, secondary: secondary, tertiary: tertiary)
        cachedPairs[key] = Entry(pair: pair, byteCost: byteCost, lastAccess: accessCounter)
        cachedByteCost += byteCost
        return pair
    }

    private func evictUntilAffordable(_ incomingByteCost: Int) {
        while !cachedPairs.isEmpty,
              cachedByteCost + incomingByteCost > byteBudget,
              let oldest = cachedPairs.min(by: { $0.value.lastAccess < $1.value.lastAccess }) {
            cachedByteCost -= oldest.value.byteCost
            cachedPairs.removeValue(forKey: oldest.key)
        }
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
