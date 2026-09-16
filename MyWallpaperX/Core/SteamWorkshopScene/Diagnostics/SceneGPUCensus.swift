import Metal

/// Frame-path GPU operation census.
///
/// The counters exist to answer one question before any composition change:
/// which encoded operations a frame's GPU work comes from. They count pass
/// creations and whole-texture copies so AS3 can name the operation it intends
/// to remove and then measure GPU time, instead of guessing from a stack sample
/// or from theoretical bytes.
///
/// Every helper here is one lock acquisition on the existing
/// `ScenePerformanceCounterHub`, the same always-on counter owner that already
/// records draws and pipeline binds. Nothing here measures GPU duration; Metal
/// exposes per-command-buffer GPU time only, so pass-level attribution must come
/// from counting what was encoded and confirming with a before/after GPU number.
enum SceneGPUCensus {
    /// The reusable main composite pass. Each creation is one pass split, so the
    /// count is the pass-merge target for AS3.
    static func recordMainPassRender(usesDepth: Bool) {
        ScenePerformanceCounterHub.shared.recordMainPassRender(usesDepth: usesDepth)
    }

    /// An offscreen render pass. The kind keeps the offscreen total partitioned
    /// so a redundant clear or capture pass stays visible as a named cost.
    static func recordOffscreenRender(_ kind: SceneOffscreenPassKind) {
        ScenePerformanceCounterHub.shared.recordOffscreenRender(kind)
    }

    static func recordFramebufferCapture(texture: MTLTexture) {
        ScenePerformanceCounterHub.shared.recordFramebufferCapture(
            byteCount: byteCost(texture)
        )
    }

    static func recordGraphOutputPublication(texture: MTLTexture) {
        ScenePerformanceCounterHub.shared.recordGraphOutputPublication(
            byteCount: byteCost(texture)
        )
    }

    static func recordTextureCopy(texture: MTLTexture) {
        ScenePerformanceCounterHub.shared.recordTextureCopy(
            byteCount: byteCost(texture)
        )
    }

    /// Bytes moved by a whole-texture copy, or `nil` when the pixel format has
    /// no known bytes-per-pixel. Unknown formats are counted as unmeasured
    /// rather than assumed to be four bytes.
    private static func byteCost(_ texture: MTLTexture) -> Int? {
        guard let bytesPerPixel = bytesPerPixel(texture.pixelFormat) else {
            return nil
        }
        let (pixels, pixelOverflow) = texture.width.multipliedReportingOverflow(
            by: texture.height
        )
        let (bytes, byteOverflow) = pixels.multipliedReportingOverflow(
            by: bytesPerPixel
        )
        return pixelOverflow || byteOverflow ? nil : bytes
    }

    /// Only formats the Scene runtime actually renders or copies into. A format
    /// that reaches a copy without an entry is reported as unmeasured so the
    /// gap is visible instead of being rounded away.
    private static func bytesPerPixel(_ format: MTLPixelFormat) -> Int? {
        switch format {
        case .r8Unorm, .r8Snorm, .r8Uint, .r8Sint:
            return 1
        case .r16Float, .r16Unorm, .r16Snorm, .r16Uint, .r16Sint, .rg8Unorm,
             .rg8Snorm, .rg8Uint, .rg8Sint, .depth16Unorm:
            return 2
        case .rgba8Unorm, .rgba8Unorm_srgb, .bgra8Unorm, .bgra8Unorm_srgb,
             .rgba8Snorm, .rgba8Uint, .rgba8Sint,
             .rg16Float, .rg16Unorm, .rg16Snorm, .rg16Uint, .rg16Sint,
             .r32Float, .r32Uint, .r32Sint, .bgr10a2Unorm, .depth32Float:
            return 4
        case .rgba16Float, .rgba16Unorm, .rgba16Snorm, .rgba16Uint,
             .rgba16Sint, .rg32Float, .rg32Uint, .rg32Sint:
            return 8
        case .rgba32Float, .rgba32Uint, .rgba32Sint:
            return 16
        default:
            return nil
        }
    }
}
