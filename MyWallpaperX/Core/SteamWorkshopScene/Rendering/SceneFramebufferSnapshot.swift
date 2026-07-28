import Metal

/// Reusable, per-surface copy of the current main render target.
///
/// The snapshot is intentionally full resolution: consumers that sample the current
/// framebuffer must observe every layer encoded before them. Allocation fails closed
/// above the byte budget instead of silently changing resolution or format.
final class SceneFramebufferSnapshot {
    static let defaultByteBudget = 64 * 1_024 * 1_024

    private let device: MTLDevice
    private let byteBudget: Int
    private let label: String
    private var texture: MTLTexture?

    init(
        device: MTLDevice,
        byteBudget: Int = SceneFramebufferSnapshot.defaultByteBudget,
        label: String
    ) {
        self.device = device
        self.byteBudget = byteBudget
        self.label = label
    }

    func capture(
        target: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard target.textureType == .type2D,
              target.sampleCount == 1,
              target.pixelFormat == .bgra8Unorm,
              let cost = Self.byteCost(width: target.width, height: target.height),
              cost <= byteBudget,
              let destination = destination(width: target.width, height: target.height),
              let encoder = commandBuffer.makeBlitCommandEncoder() else {
            return nil
        }
        encoder.copy(
            from: target,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: .init(x: 0, y: 0, z: 0),
            sourceSize: .init(width: target.width, height: target.height, depth: 1),
            to: destination,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: .init(x: 0, y: 0, z: 0)
        )
        encoder.endEncoding()
        return destination
    }

    private func destination(width: Int, height: Int) -> MTLTexture? {
        if let texture, texture.width == width, texture.height == height {
            return texture
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.label = "\(label) \(width)x\(height)"
        self.texture = texture
        return texture
    }

    static func byteCost(width: Int, height: Int) -> Int? {
        let (pixels, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        let (bytes, byteOverflow) = pixels.multipliedReportingOverflow(by: 4)
        return pixelOverflow || byteOverflow ? nil : bytes
    }
}
