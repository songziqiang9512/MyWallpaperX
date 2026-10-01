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

/// Encodes the terminal display mapping over a completed composite: blit the
/// source drawable to a size-cached intermediate texture, then sample the
/// intermediate and write the mapped values back to the source (Metal forbids
/// reading and writing the same attachment in one render pass). Fixed product
/// shaders and the frozen curve live in `SceneDisplayMappingPostProcess.metal`.
/// Preparation or encoding failure skips mapping and preserves the source.
/// Pipeline preparation failures log at creation; allocation failure logs once.
final class SceneDisplayMappingPostProcess {
    private let device: MTLDevice
    private let pipeline: MTLRenderPipelineState
    private let pixelFormat: MTLPixelFormat
    private var textureFailureLogged = false
    private var cachedIntermediateBySize: [SIMD2<Int>: MTLTexture] = [:]

    /// Prepare the single pipeline state once at renderer creation. A partial
    /// set is never published and cannot trigger compiler work during encode.
    init?(device: MTLDevice, pixelFormat: MTLPixelFormat, hdrEnabled: Bool, clearEnabled: Bool) {
        // A load pass can retain already-mapped display pixels. Until a distinct
        // pre-display history target exists, accumulating scenes keep their route.
        guard hdrEnabled && clearEnabled else { return nil }
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

    /// Full-resolution intermediate, format-matched to the source, allocated
    /// through the single scene resident-allocation entry.
    private func intermediateTexture(
        on device: MTLDevice, matching source: MTLTexture
    ) -> MTLTexture? {
        let key = SIMD2(Int(source.width), Int(source.height))
        if let cached = cachedIntermediateBySize[key] {
            return cached
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: key.x,
            height: key.y,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .renderTarget]
        descriptor.storageMode = .private
        guard let texture = device.makeSceneTexture(descriptor: descriptor) else {
            if !textureFailureLogged {
                textureFailureLogged = true
                NSLog("MWX Scene display mapping: intermediate texture allocation failed")
            }
            return nil
        }
        cachedIntermediateBySize = [key: texture]
        return texture
    }

    /// Map the completed composite in place. Guards refuse mismatched format,
    /// foreign devices without logging (gated paths
    /// stay silent). Allocation failure logs once; encoder failure is silent.
    /// Both leave the pre-mapping composite intact for this frame.
    @discardableResult
    func encode(source: MTLTexture, commandBuffer: MTLCommandBuffer) -> Bool {
        guard source.pixelFormat == pixelFormat,
              source.device === device,
              let intermediate = intermediateTexture(on: device, matching: source)
        else { return false }
        // Blit only reads the drawable; a later encoder failure keeps the
        // pre-mapping composite bit-intact in the source.
        guard let blit = commandBuffer.makeBlitCommandEncoder() else { return false }
        blit.copy(
            from: source, sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: MTLOriginMake(0, 0, 0),
            sourceSize: MTLSizeMake(source.width, source.height, 1),
            to: intermediate, destinationSlice: 0, destinationLevel: 0,
            destinationOrigin: MTLOriginMake(0, 0, 0)
        )
        blit.endEncoding()
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = source
        // Full-screen coverage write; the previous contents are fully consumed
        // via the intermediate copy above.
        descriptor.colorAttachments[0].loadAction = .dontCare
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return false }
        encoder.setRenderPipelineState(pipeline)
        encoder.setTriangleFillMode(.fill)
        encoder.setFragmentTexture(intermediate, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        return true
    }
}
