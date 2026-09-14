/// Coordinates source-driven scalar arithmetic compatibility before the
/// declaration and stage-link contracts are lowered to Vulkan GLSL.
nonisolated enum SceneGenericShaderScalarArithmeticNormalizer {
    static func rewrite(
        _ source: String,
        stage: SceneShaderContract.StageKind = .fragment
    ) -> String {
        SceneGenericShaderScalarVectorBroadcastNormalizer.rewrite(
            SceneGenericShaderScalarBuiltInLiteralNormalizer.rewrite(
                SceneGenericShaderFloatingModuloNormalizer.rewrite(
                    SceneGenericShaderBooleanScalarArithmeticNormalizer.rewrite(source)
                )
            ),
            stage: stage
        )
    }
}
