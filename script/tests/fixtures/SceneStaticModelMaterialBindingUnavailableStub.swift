// These standalone Timeline, Text and display fixtures exercise the real
// descriptor builder, but shader interface compilation is outside their scope.
// Preserve the production fallback contract without importing the shader stack.
struct SceneStaticModelMaterialBindingCompiler {
    init<Contract>(shaderContracts: [Contract]) {}
    func defaultAlbedoAssetPath(pass: SceneRenderDescriptor.MaterialPassDescriptor) -> String? { nil }
    mutating func compile(
        pass: SceneRenderDescriptor.MaterialPassDescriptor
    ) -> SceneStaticModelMaterialBindings {
        .init(state: .unavailable, bindings: [], rejectionReason: "fixture-shader-boundary")
    }
}
