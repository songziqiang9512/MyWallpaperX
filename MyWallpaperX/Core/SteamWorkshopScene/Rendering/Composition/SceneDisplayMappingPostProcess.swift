import Foundation
import Metal

/// Owns the terminal display transform and its prepared input modes. History
/// always uses a distinct source; eligible cleared frames read the attachment.
/// The existing target pool owns residency; this owner never retains history.
final class SceneDisplayMappingPostProcess {
    enum Input: Equatable {
        case textureSource
        case colorAttachment
    }
    /// Surface transfer is fixed for its lifetime; only available headroom changes.
    enum Output: Equatable {
        case sRGB
        case extendedLinearSRGB(headroom: Float)

        var isLinear: Bool {
            if case .extendedLinearSRGB = self { return true }
            return false
        }
        var uniform: Float {
            guard case let .extendedLinearSRGB(headroom) = self else { return 0 }
            return headroom.isFinite ? min(65_504, max(1, headroom)) : 1
        }
    }
    private let device: MTLDevice
    private let pipeline: MTLRenderPipelineState
    private let attachmentPipeline: MTLRenderPipelineState?
    private let pixelFormat: MTLPixelFormat

    /// Prepare at renderer creation. The texture pipeline is required; the
    /// attachment pipeline is optional. Encode never invokes the compiler.
    init?(device: MTLDevice, pixelFormat: MTLPixelFormat, hdrEnabled: Bool) {
        // Accumulating HDR keeps the raw-history transaction. Preparing an
        // optional attachment input cannot remove the required texture route.
        guard hdrEnabled else { return nil }
        self.device = device
        self.pixelFormat = pixelFormat
        guard let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "sceneDisplayMappingVertex"),
              let fragment = library.makeFunction(name: "sceneDisplayMappingFragment")
        else {
            NSLog("MWX Scene display mapping: default library functions unavailable")
            return nil
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        do {
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            NSLog(
                "MWX Scene display mapping: pipeline state rejected: %@",
                String(describing: error)
            )
            return nil
        }
        var preparedAttachment: MTLRenderPipelineState?
        if pixelFormat == .rgba16Float, device.supportsFamily(.apple2),
           let fragment = library.makeFunction(name: "sceneDisplayMappingAttachmentFragment") {
            descriptor.fragmentFunction = fragment
            descriptor.colorAttachments[0].isBlendingEnabled = false
            do {
                preparedAttachment = try device.makeRenderPipelineState(descriptor: descriptor)
            } catch {
                NSLog("MWX Scene display mapping: optional attachment input unavailable: %@",
                    String(describing: error))
            }
        }
        attachmentPipeline = preparedAttachment
    }

    /// Freeze after graph admission and before optional capacity. Any upstream
    /// terminal-budget coupling keeps its original input and resource order.
    /// Reflection demand is lazy so unsupported/coupled frames keep short cuts.
    func input(for target: MTLTexture, clearEnabled: Bool,
               hasPersistentSceneColor: Bool, hasShadowReceiver: Bool,
               hasSourceMaterials: Bool, requiresReflection: () -> Bool) -> Input {
        guard attachmentPipeline != nil, acceptsAttachment(target), clearEnabled,
              !hasPersistentSceneColor, !hasShadowReceiver, !hasSourceMaterials,
              !requiresReflection() else { return .textureSource }
        return .colorAttachment
    }

    private func acceptsAttachment(_ target: MTLTexture) -> Bool {
        target.device === device && target.pixelFormat == .rgba16Float
            && target.pixelFormat == pixelFormat && target.textureType == .type2D
            && target.sampleCount == 1 && target.usage.contains(.renderTarget)
    }

    /// Caller has already made a readable terminal source. Reject accidental
    /// raw/display aliasing before creating an encoder; failure preserves both.
    @discardableResult
    func encode(source: MTLTexture, target: MTLTexture,
                commandBuffer: MTLCommandBuffer, output: Output = .sRGB) -> Bool {
        guard source !== target, source.pixelFormat == pixelFormat,
              target.pixelFormat == pixelFormat,
              source.device === device, target.device === device,
              source.width == target.width, source.height == target.height
        else { return false }
        return encodePass(source: source, target: target, pipeline: pipeline,
            commandBuffer: commandBuffer, output: output)
    }

    /// Reads color(0), never binds the target as a sampled texture. Encoder
    /// failure precedes all writes; the caller preserves the output contract.
    @discardableResult
    func encodeAttachment(target: MTLTexture, commandBuffer: MTLCommandBuffer,
                          output: Output = .sRGB) -> Bool {
        guard let attachmentPipeline, acceptsAttachment(target) else { return false }
        return encodePass(source: nil, target: target, pipeline: attachmentPipeline,
            commandBuffer: commandBuffer, output: output)
    }

    private func encodePass(source: MTLTexture?, target: MTLTexture,
                            pipeline: MTLRenderPipelineState,
                            commandBuffer: MTLCommandBuffer, output: Output) -> Bool {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = source == nil ? .load : .dontCare
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return false }
        encoder.setRenderPipelineState(pipeline)
        encoder.setTriangleFillMode(.fill)
        if let source { encoder.setFragmentTexture(source, index: 0) }
        var headroom = output.uniform
        encoder.setFragmentBytes(&headroom, length: MemoryLayout<Float>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        return true
    }
}
