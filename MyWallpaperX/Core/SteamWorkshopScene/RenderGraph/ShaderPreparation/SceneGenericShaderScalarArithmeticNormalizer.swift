/// Coordinates source-driven scalar arithmetic compatibility before the
/// declaration and stage-link contracts are lowered to Vulkan GLSL.
nonisolated enum SceneGenericShaderScalarArithmeticNormalizer {
    static func rewrite(_ source: String) -> String {
        SceneGenericShaderScalarBuiltInLiteralNormalizer.rewrite(
            SceneGenericShaderFloatingModuloNormalizer.rewrite(
                SceneGenericShaderBooleanScalarArithmeticNormalizer.rewrite(source)
            )
        )
    }
}
