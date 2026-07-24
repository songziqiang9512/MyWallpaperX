import simd

extension SceneLayerEffectInputs {
    static let neutral = SceneLayerEffectInputs(
        flags: [],
        params0: .zero,
        params1: .zero,
        params2: .zero,
        params3: .zero,
        params4: .zero
    )
}

extension SceneImageLayerCompositor {
    func makeFragmentUniforms(
        values: SceneImageLayerUniformValues,
        effectInputs: SceneLayerEffectInputs,
        textureFrame: SceneTextureUVTransform,
        tint: SIMD3<Float>,
        foliageMaskUVScale: SIMD2<Float>,
        dependencyBlendMode: Int?
    ) -> SceneLayerFragmentUniforms {
        var flags = effectInputs.flags
        if dependencyBlendMode != nil {
            flags.insert(.dependencyBlend)
        }
        return SceneLayerFragmentUniforms(
            time: values.time,
            alpha: values.alpha,
            effectFlags: flags.rawValue,
            dependencyBlendMode: UInt32(dependencyBlendMode ?? 0),
            cursorUV: values.cursorUV,
            _pad1: .zero,
            tint: SIMD4(tint.x, tint.y, tint.z, 1),
            effectParams0: effectInputs.params0,
            effectParams1: effectInputs.params1,
            effectParams2: effectInputs.params2,
            effectParams3: effectInputs.params3,
            effectParams4: effectInputs.params4,
            effectParams5: SIMD4(foliageMaskUVScale.x, foliageMaskUVScale.y, 0, 0),
            textureFrame0: textureFrame.uniform0,
            textureFrame1: textureFrame.uniform1
        )
    }
}
