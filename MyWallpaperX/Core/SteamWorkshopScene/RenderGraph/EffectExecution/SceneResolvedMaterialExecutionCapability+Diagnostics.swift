import Foundation

nonisolated enum SceneResolvedMaterialExecutionCapabilityDiagnostics {
    static func frontendFailure(
        template: SceneResolvedMaterialTemplate,
        output: SceneAuthoredShaderFrontendOutput
    ) -> [String] {
        let diagnosticCodes = output.diagnostics.map { $0.code.rawValue }
#if DEBUG
        let codes = diagnosticCodes.isEmpty ? "invariant" : diagnosticCodes.joined(separator: ",")
        print(
            "MWX resolved material frontend rejection:"
                + " shader=\(template.diagnosticProvenance.authoredShaderPath)"
                + " node=\(template.diagnosticProvenance.nodeIndex) codes=\(codes)"
        )
#endif
        return diagnosticCodes
    }

}
