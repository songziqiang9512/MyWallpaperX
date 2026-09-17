import Metal
import simd

/// Prepared geometry whose vertex positions remain in authored model space.
/// The encoder consumes the caller's live model-to-clip transform directly;
/// no layer-sized or coverage-sized texture is part of this product.
struct SceneGeometryProduct {
    typealias ColorBlendBinder = (
        MTLRenderCommandEncoder,
        MTLTexture,
        simd_float4x4
    ) -> Void

    let encode: (
        MTLRenderCommandEncoder,
        MTLTexture,
        MTLTexture?,
        simd_float4x4,
        SceneLayerFragmentUniforms,
        ColorBlendBinder?
    ) -> Bool
    /// Exact authored owner and atlas identity. `resourceGeneration` is
    /// assigned only when the base-image store installs the atlas and mesh as
    /// one resource atom; an uninstalled product cannot publish cross-layer.
    let ownerLayerID: Int
    let samplingTexture: MTLTexture
    let resourceGeneration: UInt64
    let isPreparedForPublication: (MTLCommandBuffer) -> Bool
    let authoredSize: SIMD2<Float>
    /// Fixed when this source product is prepared. Effects process the atlas
    /// before the mesh samples it, so changing its extent changes the product.
    let effectSourceExtentContract: SceneEffectSourceExtentContract

    init(
        ownerLayerID: Int,
        samplingTexture: MTLTexture,
        resourceGeneration: UInt64 = 0,
        isPreparedForPublication: @escaping (MTLCommandBuffer) -> Bool = { _ in true },
        encode: @escaping (
            MTLRenderCommandEncoder,
            MTLTexture,
            MTLTexture?,
            simd_float4x4,
            SceneLayerFragmentUniforms,
            ColorBlendBinder?
        ) -> Bool,
        authoredSize: SIMD2<Float>,
        effectSourceExtentContract: SceneEffectSourceExtentContract
    ) {
        self.ownerLayerID = ownerLayerID
        self.samplingTexture = samplingTexture
        self.resourceGeneration = resourceGeneration
        self.isPreparedForPublication = isPreparedForPublication
        self.encode = encode
        self.authoredSize = authoredSize
        self.effectSourceExtentContract = effectSourceExtentContract
    }

    func installing(resourceGeneration: UInt64) -> Self {
        Self(
            ownerLayerID: ownerLayerID,
            samplingTexture: samplingTexture,
            resourceGeneration: resourceGeneration,
            isPreparedForPublication: isPreparedForPublication,
            encode: encode,
            authoredSize: authoredSize,
            effectSourceExtentContract: effectSourceExtentContract
        )
    }

    func matchesInstalledSource(
        layerID: Int,
        texture: MTLTexture
    ) -> Bool {
        ownerLayerID == layerID
            && resourceGeneration > 0
            && samplingTexture === texture
            && authoredSize.x.isFinite
            && authoredSize.y.isFinite
            && authoredSize.x >= 1
            && authoredSize.y >= 1
    }

    /// The first geometry-provider profile is deliberately placement exact:
    /// the mesh is rasterized in authored-local coordinates and the consumer
    /// must place that local card exactly where the provider would have been.
    /// This prevents a consumer-specific world transform from leaking into a
    /// provider target that may later be shared.
    func supportsNamedProviderPlacement(
        providerOutputMVP: simd_float4x4,
        consumerOutputMVP: simd_float4x4
    ) -> Bool {
        for column in 0 ..< 4 {
            for row in 0 ..< 4 {
                let provider = providerOutputMVP[column][row]
                let consumer = consumerOutputMVP[column][row]
                guard provider.isFinite, consumer.isFinite else { return false }
                let scale = max(1, max(abs(provider), abs(consumer)))
                guard abs(provider - consumer) <= 0.0001 * scale else {
                    return false
                }
            }
        }
        return true
    }

}
