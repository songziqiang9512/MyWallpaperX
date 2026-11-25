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
#if DEBUG
            NSLog("MWX Scene display mapping: default library functions unavailable")
#endif
            return nil
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        do {
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
#if DEBUG
            NSLog(
                "MWX Scene display mapping: pipeline state rejected: %@",
                String(describing: error)
            )
#endif
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
#if DEBUG
                NSLog("MWX Scene display mapping: optional attachment input unavailable: %@",
                    String(describing: error))
#endif
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
        return Draw(pipeline: pipeline, output: output).encodePass(
            source: source, target: target, commandBuffer: commandBuffer)
    }

    /// Reads color(0) without binding the target as a sampled texture.
    func attachmentDraw(for target: MTLTexture, output: Output) -> Draw? {
        guard let attachmentPipeline, acceptsAttachment(target) else { return nil }
        return Draw(pipeline: attachmentPipeline, output: output)
    }

    struct Draw {
        fileprivate let pipeline: MTLRenderPipelineState
        fileprivate let output: Output

        func encodePass(source: MTLTexture? = nil, target: MTLTexture,
                        commandBuffer: MTLCommandBuffer) -> Bool {
            let descriptor = MTLRenderPassDescriptor()
            descriptor.colorAttachments[0].texture = target
            descriptor.colorAttachments[0].loadAction = source == nil ? .load : .dontCare
            descriptor.colorAttachments[0].storeAction = .store
#if DEBUG
            let timestampEncoder = SceneGPUStageTimestampHook.render(commandBuffer, descriptor, role: "display-mapping")
#else
            let timestampEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
#endif
            guard let encoder = timestampEncoder else { return false }
            encode(on: encoder, source: source)
#if DEBUG
            SceneGPUStageTimestampHook.drew(encoder)
#endif
            encoder.endEncoding()
            return true
        }

        func encode(on encoder: MTLRenderCommandEncoder, source: MTLTexture? = nil) {
            encoder.setRenderPipelineState(pipeline)
            encoder.setTriangleFillMode(.fill)
            if let source { encoder.setFragmentTexture(source, index: 0) }
            var headroom = output.uniform
            encoder.setFragmentBytes(&headroom, length: MemoryLayout<Float>.stride, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
    }
}
