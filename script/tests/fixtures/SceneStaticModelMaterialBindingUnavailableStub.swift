// These standalone Timeline, Text and display fixtures exercise the real
// descriptor builder, but shader interface compilation is outside their scope.
// Preserve the production fallback contract without importing the shader stack.
enum SceneStaticModelMaterialBindingCompiler {
    static func compile<Contract>(
        pass: SceneRenderDescriptor.MaterialPassDescriptor,
        shaderContracts: [Contract]
    ) -> SceneStaticModelMaterialBindings {
        .init(state: .unavailable, bindings: [], rejectionReason: "fixture-shader-boundary")
    }
}
