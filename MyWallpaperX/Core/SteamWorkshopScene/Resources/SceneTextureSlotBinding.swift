import CoreGraphics
import Metal
import simd

/// One authored `g_Texture0...g_Texture7` binding kept together with the
/// metadata produced for the same resource generation.
///
/// The binding itself preserves full UV metadata. Bounded consumers may apply
/// a stricter admission rule (for example, axis-aligned mapped UV only) before
/// splitting it into Metal arguments.
struct SceneTextureSlotBinding {
    static let authoredSlotRange = 0..<8

    let slotIndex: Int
    let candidate: SceneTextureCandidate

    /// Resolve the highest-priority ready candidate without letting an absent
    /// override suppress an authored fallback. Candidate order is low to high
    /// priority, matching material -> instance -> user/provider selection.
    static func resolveFinalCandidate(
        slotIndex: Int,
        candidates: [SceneTextureCandidate?]
    ) -> SceneTextureSlotBinding? {
        for candidate in candidates.reversed() {
            guard let candidate,
                  let binding = SceneTextureSlotBinding(
                      slotIndex: slotIndex,
                      candidate: candidate
                  ) else {
                continue
            }
            return binding
        }
        return nil
    }

    init?(
        slotIndex: Int,
        candidate: SceneTextureCandidate
    ) {
        guard Self.authoredSlotRange.contains(slotIndex),
              Self.valid(candidate) else {
            return nil
        }
        self.slotIndex = slotIndex
        self.candidate = candidate
    }

    var texture: MTLTexture { candidate.texture }
    var identity: SceneTextureResourceIdentity { candidate.identity }
    var generation: SceneTextureResourceGeneration { candidate.generation }
    var purpose: SceneTextureLoadPurpose { candidate.purpose }
    var physicalSize: CGSize { candidate.physicalSize }
    var mappedSize: CGSize { candidate.mappedSize }
    var uvTransform: SceneTextureUVTransform { candidate.uvTransform }
    var sampling: SceneTextureSampling { candidate.sampling }
    var pixelFormat: MTLPixelFormat { candidate.pixelFormat }
    var mipmapLevelCount: Int { texture.mipmapLevelCount }

    /// Project-local carrier for the documented physical `xy` and mapped
    /// `zw` dimensions. It does not claim Wallpaper Engine's private packing
    /// for any other texture built-in.
    var physicalMappedResolution: SIMD4<Float> {
        SIMD4(
            Float(physicalSize.width),
            Float(physicalSize.height),
            Float(mappedSize.width),
            Float(mappedSize.height)
        )
    }

    var physicalTexelSize: SIMD2<Float> {
        SIMD2(
            1 / Float(physicalSize.width),
            1 / Float(physicalSize.height)
        )
    }

    var mappedTexelSize: SIMD2<Float> {
        SIMD2(
            1 / Float(mappedSize.width),
            1 / Float(mappedSize.height)
        )
    }

    func axisAlignedUVScale(
        expectedSlotIndex: Int,
        expectedPurpose: SceneTextureLoadPurpose,
        allowedPixelFormats: Set<MTLPixelFormat>,
        requiresIdentityUV: Bool = false
    ) -> SIMD2<Float>? {
        guard slotIndex == expectedSlotIndex,
              purpose == expectedPurpose,
              allowedPixelFormats.contains(pixelFormat),
              !sampling.usesClampBorderFallback,
              let scale = candidate.axisAlignedMappedUVScale(
                  expectedPurpose: expectedPurpose
              ),
              !requiresIdentityUV || near(scale, SIMD2(repeating: 1)) else {
            return nil
        }
        return scale
    }

    var diagnosticSummary: String {
        "slot=\(slotIndex) \(candidate.diagnosticSummary)"
            + " mipLevels=\(mipmapLevelCount)"
    }

    private static func valid(_ candidate: SceneTextureCandidate) -> Bool {
        valid(candidate.physicalSize)
            && valid(candidate.mappedSize)
            && candidate.mappedSize.width <= candidate.physicalSize.width
            && candidate.mappedSize.height <= candidate.physicalSize.height
            && candidate.physicalSize.width == CGFloat(candidate.texture.width)
            && candidate.physicalSize.height == CGFloat(candidate.texture.height)
            && candidate.texture.textureType == .type2D
            && candidate.texture.sampleCount == 1
            && candidate.texture.mipmapLevelCount > 0
            && candidate.texture.usage.contains(.shaderRead)
            && candidate.pixelFormat != .invalid
            && valid(candidate.uvTransform)
    }

    private static func valid(_ size: CGSize) -> Bool {
        size.width.isFinite
            && size.height.isFinite
            && size.width > 0
            && size.height > 0
            && size.width.rounded() == size.width
            && size.height.rounded() == size.height
    }

    private static func finite(_ value: SIMD2<Float>) -> Bool {
        value.x.isFinite && value.y.isFinite
    }

    private static func valid(_ transform: SceneTextureUVTransform) -> Bool {
        let area = determinant(transform)
        return finite(transform.origin)
            && finite(transform.xAxis)
            && finite(transform.yAxis)
            && area.isFinite
            && abs(area) > 0.000_000_1
    }

    private static func determinant(
        _ transform: SceneTextureUVTransform
    ) -> Float {
        transform.xAxis.x * transform.yAxis.y
            - transform.xAxis.y * transform.yAxis.x
    }

    private func near(_ lhs: SIMD2<Float>, _ rhs: SIMD2<Float>) -> Bool {
        abs(lhs.x - rhs.x) <= 0.000_001
            && abs(lhs.y - rhs.y) <= 0.000_001
    }
}
