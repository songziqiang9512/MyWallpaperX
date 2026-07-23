import simd

enum SceneTextureMappedUVScale {
    static func resolve(
        physicalWidth: Int,
        physicalHeight: Int,
        mappedWidth: Int,
        mappedHeight: Int
    ) -> SIMD2<Float> {
        guard physicalWidth > 0, physicalHeight > 0,
              mappedWidth > 0, mappedHeight > 0 else {
            return SIMD2(repeating: 1)
        }
        return SIMD2(
            min(Float(mappedWidth) / Float(physicalWidth), 1),
            min(Float(mappedHeight) / Float(physicalHeight), 1)
        )
    }
}
