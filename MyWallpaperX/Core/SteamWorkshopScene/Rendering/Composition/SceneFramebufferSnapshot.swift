import Metal

/// Reusable, per-surface copy of the current main render target.
///
/// The snapshot is intentionally full resolution: consumers that sample the current
/// framebuffer must observe every layer encoded before them. Allocation fails closed
/// above the byte budget instead of silently changing resolution or format.
final class SceneFramebufferSnapshot {
    static let defaultByteBudget = 64 * 1_024 * 1_024

    private let device: MTLDevice
    private let byteBudget: Int?
    private let label: String
    private var texture: MTLTexture?
    private(set) var residentByteCost = 0

    init(
        device: MTLDevice,
        byteBudget: Int? = nil,
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
              target.pixelFormat == .bgra8Unorm || target.pixelFormat == .rgba16Float,
              let cost = Self.byteCost(width: target.width, height: target.height, pixelFormat: target.pixelFormat),
              cost <= (byteBudget ?? Self.defaultByteBudget * (target.pixelFormat == .rgba16Float ? 2 : 1)),
              let destination = destination(width: target.width, height: target.height, pixelFormat: target.pixelFormat),
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
        SceneGPUCensus.recordFramebufferCapture(texture: target)
        encoder.endEncoding()
        return destination
    }

    private func destination(width: Int, height: Int, pixelFormat: MTLPixelFormat) -> MTLTexture? {
        if let texture, texture.width == width, texture.height == height,
           texture.pixelFormat == pixelFormat {
            return texture
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = .shaderRead
        guard let texture = device.makeSceneTexture(descriptor: descriptor) else { return nil }
        texture.label = "\(label) \(width)x\(height)"
        self.texture = texture
        residentByteCost = Self.byteCost(width: width, height: height, pixelFormat: pixelFormat) ?? 0
        return texture
    }

    static func byteCost(width: Int, height: Int, pixelFormat: MTLPixelFormat = .bgra8Unorm) -> Int? {
        let (pixels, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        let (bytes, byteOverflow) = pixels.multipliedReportingOverflow(by: pixelFormat == .rgba16Float ? 8 : 4)
        return pixelOverflow || byteOverflow ? nil : bytes
    }
}
