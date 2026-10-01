import Foundation
import Metal
import simd

/// Project-owned SDR shoulder for the opaque, already-composited HDR route.
/// Values remain display-referred sRGB; this is not a transfer conversion.
/// The knee at 0.5 leaves dark values unchanged and reserves SDR headroom:
/// f(x) = x below the knee, otherwise 1 - 0.25 / x. The join is C1 continuous.
/// Finite precision may round extreme highlights to 1. Non-HDR scenes skip
/// this owner entirely; identity over their full range is a route contract.
nonisolated struct SceneDisplayMappingCurve: Sendable {
    nonisolated static let frozenDefault = SceneDisplayMappingCurve()

    nonisolated func evaluate(_ x: Float) -> Float {
        guard x.isFinite else { return 0 }
        if x <= 0 { return 0 }
        if x <= 0.5 { return x }
        return 1 - 0.25 / x
    }

    nonisolated func evaluate(_ rgb: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(evaluate(rgb.x), evaluate(rgb.y), evaluate(rgb.z))
    }
}

/// Encodes the terminal display transform from a completed, distinct color
/// source to the drawable. The existing target pool owns scratch residency;
/// this owner holds only its prepared pipeline and never retains history.
final class SceneDisplayMappingPostProcess {
    private let device: MTLDevice
    private let pipeline: MTLRenderPipelineState
    private let pixelFormat: MTLPixelFormat

    /// Prepare the single pipeline state once at renderer creation. A partial
    /// set is never published and cannot trigger compiler work during encode.
    init?(device: MTLDevice, pixelFormat: MTLPixelFormat, hdrEnabled: Bool) {
        // The renderer admits accumulating HDR only through the raw-history
        // target transaction. This output stage never reads its destination.
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
    }

    /// Caller has already made a readable terminal source. Reject accidental
    /// raw/display aliasing before creating an encoder; failure preserves both.
    @discardableResult
    func encode(source: MTLTexture, target: MTLTexture,
                commandBuffer: MTLCommandBuffer) -> Bool {
        guard source !== target, source.pixelFormat == pixelFormat,
              target.pixelFormat == pixelFormat,
              source.device === device, target.device === device,
              source.width == target.width, source.height == target.height
        else { return false }
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        // Full-screen coverage; the source is never modified.
        descriptor.colorAttachments[0].loadAction = .dontCare
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return false }
        encoder.setRenderPipelineState(pipeline)
        encoder.setTriangleFillMode(.fill)
        encoder.setFragmentTexture(source, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        return true
    }
}
