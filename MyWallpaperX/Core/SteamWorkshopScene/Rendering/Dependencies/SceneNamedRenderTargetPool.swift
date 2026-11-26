import Metal

final class SceneNamedRenderTargetPool {
    static let maximumDimension = 2_048
    static let defaultByteBudget = 64 * 1_024 * 1_024

    private struct Entry {
        var primary: MTLTexture
        var alternate: MTLTexture?
        let width: Int
        let height: Int
        let byteCost: Int

        var activeByteCost: Int { alternate == nil ? byteCost : 2 * byteCost }
        var members: [MTLTexture] { alternate.map { [primary, $0] } ?? [primary] }
    }

    private struct RetiredEntry {
        weak var texture: MTLTexture?
        let byteCost: Int
    }

    private let device: MTLDevice
    private let pixelFormat: MTLPixelFormat
    private let maxDimension: Int
    private let byteBudget: Int
    private var entriesByProviderLayerID: [Int: Entry] = [:]
    // Metal's retaining command buffers and publication receipts own retired
    // textures until release. Keep their charges without extending that life.
    private var retiredEntries: [RetiredEntry] = []
    private var activeByteCost = 0

    var residentByteCost: Int {
        activeByteCost + retiredEntries.reduce(0) { $1.texture == nil ? $0 : $0 + $1.byteCost }
    }

    var residentTextureCount: Int {
        entriesByProviderLayerID.values.reduce(0) { $0 + ($1.alternate == nil ? 1 : 2) }
            + retiredEntries.reduce(0) { $1.texture == nil ? $0 : $0 + 1 }
    }

    init(
        device: MTLDevice,
        pixelFormat: MTLPixelFormat = .bgra8Unorm,
        maxDimension: Int = SceneNamedRenderTargetPool.maximumDimension,
        byteBudget: Int = SceneNamedRenderTargetPool.defaultByteBudget
    ) {
        self.device = device
        self.pixelFormat = pixelFormat
        self.maxDimension = min(max(maxDimension, 1), Self.maximumDimension)
        self.byteBudget = min(max(byteBudget, 0), Self.defaultByteBudget)
    }

    func texture(
        for providerLayerID: Int,
        width requestedWidth: Int,
        height requestedHeight: Int,
        avoiding previous: MTLTexture? = nil
    ) -> MTLTexture? {
        guard providerLayerID >= 0,
              let extent = normalizedExtent(
            width: requestedWidth,
            height: requestedHeight
        ) else {
            return nil
        }

        let existing = entriesByProviderLayerID[providerLayerID]
        if var entry = existing, entry.width == extent.width, entry.height == extent.height {
            if entry.primary !== previous { return entry.primary }
            if let alternate = entry.alternate { return alternate }
            guard let alternate = allocateTexture(
                providerLayerID: providerLayerID, width: extent.width,
                height: extent.height, byteCost: entry.byteCost
            ) else { return nil }
            entry.alternate = alternate
            entriesByProviderLayerID[providerLayerID] = entry
            activeByteCost += entry.byteCost
            return alternate
        }

        let byteCost = extent.width * extent.height * (pixelFormat == .rgba16Float ? 8 : 4)
        let preservesRetiringCost = previous != nil || existing?.alternate != nil
        let oldCost = existing?.activeByteCost ?? 0
        guard let texture = allocateTexture(
            providerLayerID: providerLayerID, width: extent.width, height: extent.height,
            byteCost: byteCost, reclaiming: preservesRetiringCost ? 0 : oldCost
        ) else { return nil }
        if preservesRetiringCost, let existing {
            for member in existing.members {
                retiredEntries.append(.init(texture: member, byteCost: existing.byteCost))
            }
        }

        entriesByProviderLayerID[providerLayerID] = Entry(
            primary: texture,
            width: extent.width,
            height: extent.height,
            byteCost: byteCost
        )
        activeByteCost += byteCost - oldCost
        return texture
    }

    func retireHistory(for providerLayerID: Int, keeping survivor: MTLTexture?) {
        guard var entry = entriesByProviderLayerID.removeValue(forKey: providerLayerID) else { return }
        retiredEntries.removeAll { $0.texture == nil }
        activeByteCost -= entry.activeByteCost
        for member in entry.members {
            if member === survivor {
                entry.primary = member
                entry.alternate = nil
                entriesByProviderLayerID[providerLayerID] = entry
                activeByteCost += entry.byteCost
            } else {
                retiredEntries.append(.init(texture: member, byteCost: entry.byteCost))
            }
        }
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

    private func allocateTexture(
        providerLayerID: Int,
        width: Int,
        height: Int,
        byteCost: Int,
        reclaiming: Int = 0
    ) -> MTLTexture? {
        retiredEntries.removeAll { $0.texture == nil }
        guard byteCost <= byteBudget - residentByteCost + reclaiming else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        let texture = device.makeSceneTexture(descriptor: descriptor)
        texture?.label = "SceneNamedTarget layer=\(providerLayerID) \(width)x\(height)"
        return texture
    }
}
