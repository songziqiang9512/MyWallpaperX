import Metal

final class SceneNamedRenderTargetPool {
    static let maximumDimension = 2_048
    static let defaultByteBudget = 64 * 1_024 * 1_024

    private struct Entry {
        let texture: MTLTexture
        let width: Int
        let height: Int
        let byteCost: Int
    }

    private let device: MTLDevice
    private let maxDimension: Int
    private let byteBudget: Int
    private var entriesByProviderLayerID: [Int: Entry] = [:]

    private(set) var residentByteCost = 0

    var residentTextureCount: Int {
        entriesByProviderLayerID.count
    }

    init(
        device: MTLDevice,
        maxDimension: Int = SceneNamedRenderTargetPool.maximumDimension,
        byteBudget: Int = SceneNamedRenderTargetPool.defaultByteBudget
    ) {
        self.device = device
        self.maxDimension = min(max(maxDimension, 1), Self.maximumDimension)
        self.byteBudget = min(max(byteBudget, 0), Self.defaultByteBudget)
    }

    func texture(
        for providerLayerID: Int,
        width requestedWidth: Int,
        height requestedHeight: Int
    ) -> MTLTexture? {
        guard providerLayerID >= 0,
              let extent = normalizedExtent(
            width: requestedWidth,
            height: requestedHeight
        ) else {
            return nil
        }

        let existing = entriesByProviderLayerID[providerLayerID]
        if existing?.width == extent.width, existing?.height == extent.height {
            return existing?.texture
        }

        let byteCost = extent.width * extent.height * 4
        let costWithoutExisting = residentByteCost - (existing?.byteCost ?? 0)
        guard costWithoutExisting <= byteBudget,
              byteCost <= byteBudget - costWithoutExisting,
              let texture = makeTexture(
                  providerLayerID: providerLayerID,
                  width: extent.width,
                  height: extent.height
              ) else {
            return nil
        }

        entriesByProviderLayerID[providerLayerID] = Entry(
            texture: texture,
            width: extent.width,
            height: extent.height,
            byteCost: byteCost
        )
        residentByteCost = costWithoutExisting + byteCost
        return texture
    }

    private func normalizedExtent(width: Int, height: Int) -> (width: Int, height: Int)? {
        guard width > 0, height > 0 else { return nil }
        let longestEdge = max(width, height)
        guard longestEdge > maxDimension else { return (width, height) }

        let scale = Double(maxDimension) / Double(longestEdge)
        let scaledWidth = max(1, Int((Double(width) * scale).rounded()))
        let scaledHeight = max(1, Int((Double(height) * scale).rounded()))
        return (scaledWidth, scaledHeight)
    }

    private func makeTexture(
        providerLayerID: Int,
        width: Int,
        height: Int
    ) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        let texture = device.makeTexture(descriptor: descriptor)
        texture?.label = "SceneNamedTarget layer=\(providerLayerID) \(width)x\(height)"
        return texture
    }
}
