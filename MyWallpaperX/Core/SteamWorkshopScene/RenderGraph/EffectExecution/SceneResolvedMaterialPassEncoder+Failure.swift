import Foundation

extension SceneResolvedMaterialPassEncoder {
    enum PreparationFailure: Error, Equatable {
        case fragmentOutputRejected
        case targetRejected
        case uniformsRejected
        case bindingsRejected
        case compileStateKeyRejected
        case renderStateRejected
        case libraryCompilationRejected(diagnostic: String)
        case vertexFunctionRejected
        case fragmentFunctionRejected
        case pipelineCompilationRejected(diagnostic: String)

        var code: String {
            switch self {
            case .fragmentOutputRejected: "fragment-output"
            case .targetRejected: "target"
            case .uniformsRejected: "uniforms"
            case .bindingsRejected: "bindings"
            case .compileStateKeyRejected: "compile-state-key"
            case .renderStateRejected: "render-state"
            case .libraryCompilationRejected: "library-compilation"
            case .vertexFunctionRejected: "vertex-function"
            case .fragmentFunctionRejected: "fragment-function"
            case .pipelineCompilationRejected: "pipeline-compilation"
            }
        }
    }
}
