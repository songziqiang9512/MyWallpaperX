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
    let authoredSize: SIMD2<Float>
}
