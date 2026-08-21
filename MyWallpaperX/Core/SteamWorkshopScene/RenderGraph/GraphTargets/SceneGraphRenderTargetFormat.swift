import Metal

extension SceneGraphRenderTargetPlan.TextureFormat {
    /// Deterministic texel payload used by graph admission and cache accounting.
    /// This is not the device-specific physical allocation footprint; Metal may
    /// add row, page, or heap alignment around the texture.
    nonisolated var logicalBytesPerPixel: Int {
        switch self {
        case .r8:
            1
        case .rg88:
            2
        case .rgbaBackbuffer, .rgba8888:
            4
        }
    }

    nonisolated var metalPixelFormat: MTLPixelFormat {
        switch self {
        case .r8:
            .r8Unorm
        case .rg88:
            .rg8Unorm
        case .rgbaBackbuffer:
            .bgra8Unorm
        case .rgba8888:
            .rgba8Unorm
        }
    }
}
