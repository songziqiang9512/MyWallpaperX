import CryptoKit
import Foundation

/// Compiles the bounded text-update AST accepted by the native text runtime.
///
/// Unsupported scripts keep their authored fallback text and are fingerprinted only
/// for diagnostics; source identity never selects product execution.
nonisolated enum SceneTextScriptCompiler {
    nonisolated static func compile(descriptor: SceneRenderDescriptor) -> SceneTextScriptProgram {
        let visibleLayerIDs = SceneLayerVisibility.visibleLayerIDs(in: descriptor)
        var bindings: [SceneTextScriptProgram.Binding] = []
        var diagnostics: [SceneTextScriptProgram.Diagnostic] = []

        for layer in descriptor.layers where
            layer.contentKind == "text" && visibleLayerIDs.contains(layer.id) {
            guard let script = layer.textScript else { continue }
            guard let program = SceneTextScriptSubsetCompiler.compile(script.source) else {
                diagnostics.append(.init(
                    layerID: layer.id,
                    code: .unknownProfile,
                    sourceSHA256: sha256(script.source)
                ))
                continue
            }
            bindings.append(.init(
                layerID: layer.id,
                profile: .ecmaTextUpdateSubset,
                configuration: .scriptSubset(
                    program: program,
                    properties: script.properties
                ),
                definition: .init(
                    target: .text(layerID: layer.id, field: .content),
                    valueType: .string,
                    authoredValue: .string(layer.text ?? "")
                )
            ))
        }
        return SceneTextScriptProgram(bindings: bindings, diagnostics: diagnostics)
    }

    private nonisolated static func sha256(_ source: String) -> String {
        SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
