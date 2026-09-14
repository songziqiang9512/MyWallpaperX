import simd

enum SceneTextureMappedUVScale {
    static func resolve(
        physicalWidth: Int,
        physicalHeight: Int,
        mappedWidth: Int,
        mappedHeight: Int,
        sampledWidth: Int? = nil,
        sampledHeight: Int? = nil
    ) -> SIMD2<Float> {
        guard physicalWidth > 0, physicalHeight > 0,
              mappedWidth > 0, mappedHeight > 0 else {
            return SIMD2(repeating: 1)
        }
        let textureWidth = sampledWidth ?? physicalWidth
        let textureHeight = sampledHeight ?? physicalHeight
        guard textureWidth > 0, textureHeight > 0 else {
            return SIMD2(repeating: 1)
        }
        return SIMD2(
            min(Float(mappedWidth) / Float(textureWidth), 1),
            min(Float(mappedHeight) / Float(textureHeight), 1)
        )
    }
}
