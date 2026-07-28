import simd

/// Wallpaper Engine image/solid `alignment` places the authored origin on a named
/// edge or corner of the quad. The unit quad is centered at zero, so moving its
/// center by half an extent makes the named edge land on the origin.
nonisolated enum SceneImageLayerPivot {
    /// Unit-quad translation applied after `sizeScale`, inside the layer's rotation.
    nonisolated static func unitOffset(alignment: String?) -> SIMD2<Float> {
        switch alignment?.lowercased() {
        case "top":
            return SIMD2(0, -0.5)
        case "topright":
            return SIMD2(-0.5, -0.5)
        case "right":
            return SIMD2(-0.5, 0)
        case "bottomright":
            return SIMD2(-0.5, 0.5)
        case "bottom":
            return SIMD2(0, 0.5)
        case "bottomleft":
            return SIMD2(0.5, 0.5)
        case "left":
            return SIMD2(0.5, 0)
        case "topleft":
            return SIMD2(0.5, -0.5)
        default:
            return .zero
        }
    }
}
