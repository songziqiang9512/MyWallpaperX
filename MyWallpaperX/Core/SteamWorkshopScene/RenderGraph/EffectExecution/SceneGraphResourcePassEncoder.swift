import Foundation
import Metal
import simd

/// Preflights graph-resource source capture, initialization and exact-copy
/// operations before a transaction starts encoding. Capture remains a real
/// full-target render draw; exact copy deliberately does not resize, scale or
/// convert color.
final class SceneGraphResourcePassEncoder {
    typealias Plan = SceneGraphRenderTargetPlan

    struct PreparedCommand {
        enum Kind: Equatable {
            case sourceCapture
            case initialization
            case copy
        }

        let kind: Kind

        fileprivate let ownerToken: UUID
        fileprivate let resetGeneration: UInt64
        fileprivate let operation: Operation
    }

    fileprivate enum Operation {
        case sourceCapture(
            source: MTLTexture,
            target: MTLTexture,
            uniforms: SceneLayerFragmentUniforms,
            pipeline: SceneImageLayerPipeline
        )
        case initialization(target: MTLTexture, clear: Plan.ClearColor)
        case copy(source: MTLTexture, target: MTLTexture)
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let ownerToken = UUID()
    private let lock = NSLock()
    private var resetGeneration: UInt64 = 0

    init(commandQueue: MTLCommandQueue) {
        self.commandQueue = commandQueue
        self.device = commandQueue.device
    }

    /// Returns a complete immutable full-target source draw without creating
    /// an encoder or appending any command to a command buffer.
    func prepareSourceCapture(
        source: MTLTexture,
        target: MTLTexture,
        uniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline
    ) -> PreparedCommand? {
        withLock {
            guard validSourceCapture(
                source: source,
                target: target,
                pipeline: pipeline
            ) else { return nil }
            return PreparedCommand(
                kind: .sourceCapture,
                ownerToken: ownerToken,
                resetGeneration: resetGeneration,
                operation: .sourceCapture(
                    source: source,
                    target: target,
                    uniforms: uniforms,
                    pipeline: pipeline
                )
            )
        }
    }

    /// Returns a complete immutable clear operation without creating an encoder
    /// or appending any command to a command buffer.
    func prepareInitialization(
        target: MTLTexture,
        clear: Plan.ClearColor
    ) -> PreparedCommand? {
        withLock {
            guard validTarget(target), valid(clear) else { return nil }
            return PreparedCommand(
                kind: .initialization,
                ownerToken: ownerToken,
                resetGeneration: resetGeneration,
                operation: .initialization(target: target, clear: clear)
            )
        }
    }

    /// Returns a complete immutable, exact-copy operation. This clean-room
    /// implementation intentionally makes no claim about the official client's
    /// copy primitive.
    func prepareCopy(
        source: MTLTexture,
        target: MTLTexture
    ) -> PreparedCommand? {
        withLock {
            guard validCopy(source: source, target: target) else { return nil }
            return PreparedCommand(
                kind: .copy,
                ownerToken: ownerToken,
                resetGeneration: resetGeneration,
                operation: .copy(source: source, target: target)
            )
        }
    }

    /// `true` only means the command was appended. GPU completion and graph
    /// transaction commit remain the caller's responsibility.
    func encode(
        _ command: PreparedCommand,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        withLock {
            guard command.ownerToken == ownerToken,
                  command.resetGeneration == resetGeneration,
                  ObjectIdentifier(commandBuffer.commandQueue)
                    == ObjectIdentifier(commandQueue),
                  commandBuffer.commandQueue.device.registryID
                    == device.registryID,
                  commandBuffer.status == .notEnqueued else {
                return false
            }

            switch command.operation {
            case let .sourceCapture(source, target, uniforms, pipeline):
                guard validSourceCapture(
                    source: source,
                    target: target,
                    pipeline: pipeline
                ) else { return false }
                return encodeSourceCapture(
                    source: source,
                    target: target,
                    uniforms: uniforms,
                    pipeline: pipeline,
                    commandBuffer: commandBuffer
                )
            case .initialization(let target, let clear):
                guard validTarget(target), valid(clear) else { return false }
                return encodeInitialization(
                    target: target,
                    clear: clear,
                    commandBuffer: commandBuffer
                )
            case .copy(let source, let target):
                guard validCopy(source: source, target: target) else {
                    return false
                }
                return encodeCopy(
                    source: source,
                    target: target,
                    commandBuffer: commandBuffer
                )
            }
        }
    }

    private func encodeSourceCapture(
        source: MTLTexture,
        target: MTLTexture,
        uniforms: SceneLayerFragmentUniforms,
        pipeline: SceneImageLayerPipeline,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: descriptor
        ) else {
            return false
        }
        encoder.label = "Scene graph source capture"
        pipeline.bind(encoder: encoder)
        pipeline.drawLayer(
            texture: source,
            mvp: Self.fullTargetMVP,
            uniforms: uniforms,
            encoder: encoder
        )
        encoder.endEncoding()
        return true
    }

    func reset() {
        withLock { resetGeneration &+= 1 }
    }

    private func encodeInitialization(
        target: MTLTexture,
        clear: Plan.ClearColor,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(
            clear.red,
            clear.green,
            clear.blue,
            clear.alpha
        )
        guard let encoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: descriptor
        ) else {
            return false
        }
        encoder.label = "Scene graph resource initialization"
        encoder.endEncoding()
        return true
    }

    private func encodeCopy(
        source: MTLTexture,
        target: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard let encoder = commandBuffer.makeBlitCommandEncoder() else {
            return false
        }
        encoder.label = "Scene graph exact resource copy"
        encoder.copy(
            from: source,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: .init(x: 0, y: 0, z: 0),
            sourceSize: .init(
                width: source.width,
                height: source.height,
                depth: 1
            ),
            to: target,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: .init(x: 0, y: 0, z: 0)
        )
        encoder.endEncoding()
        return true
    }

    private func validTarget(_ texture: MTLTexture) -> Bool {
        let supportedFormats: Set<MTLPixelFormat> = [.bgra8Unorm, .rgba8Unorm]
        return texture.device.registryID == device.registryID
            && texture.textureType == .type2D
            && supportedFormats.contains(texture.pixelFormat)
            && texture.width > 0
            && texture.height > 0
            && texture.mipmapLevelCount == 1
            && texture.sampleCount == 1
            && texture.usage.contains(.renderTarget)
            && texture.usage.contains(.shaderRead)
    }

    private func validSourceCapture(
        source: MTLTexture,
        target: MTLTexture,
        pipeline: SceneImageLayerPipeline
    ) -> Bool {
        validTarget(target)
            && target.pixelFormat == .bgra8Unorm
            && source.device.registryID == device.registryID
            && pipeline.state.device.registryID == device.registryID
            && source.textureType == .type2D
            && source.width > 0
            && source.height > 0
            && source.sampleCount == 1
            && source.usage.contains(.shaderRead)
            && ObjectIdentifier(source) != ObjectIdentifier(target)
    }

    private func validCopy(
        source: MTLTexture,
        target: MTLTexture
    ) -> Bool {
        validTarget(target)
            && source.device.registryID == device.registryID
            && source.device.registryID == target.device.registryID
            && source.textureType == .type2D
            && source.width > 0
            && source.height > 0
            && source.mipmapLevelCount == 1
            && source.sampleCount == 1
            && source.usage.contains(.shaderRead)
            && ObjectIdentifier(source) != ObjectIdentifier(target)
            && source.width == target.width
            && source.height == target.height
            && source.pixelFormat == target.pixelFormat
    }

    private func valid(_ clear: Plan.ClearColor) -> Bool {
        clear.red.isFinite
            && clear.green.isFinite
            && clear.blue.isFinite
            && clear.alpha.isFinite
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private static let fullTargetMVP = simd_float4x4(
        diagonal: SIMD4<Float>(2, 2, 1, 1)
    )
}
