import Foundation

nonisolated enum SceneResolvedMaterialExecutionCapabilityDiagnostics {
    static func frontendFailure(
        template: SceneResolvedMaterialTemplate,
        output: SceneAuthoredShaderFrontendOutput
    ) -> [String] {
        let diagnosticCodes = output.diagnostics.map { $0.code.rawValue }
#if DEBUG
        let codes = diagnosticCodes.isEmpty ? "invariant" : diagnosticCodes.joined(separator: ",")
        let details = output.diagnostics.prefix(8).map { diagnostic in
            let stage = diagnostic.stage?.rawValue ?? "program"
            let location = [diagnostic.line, diagnostic.column]
                .compactMap { $0.map(String.init) }
                .joined(separator: ":")
            let message = diagnostic.message
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
            return "\(stage)@\(location.isEmpty ? "unknown" : location):\(message)"
        }.joined(separator: "|")
        print(
            "MWX resolved material frontend rejection:"
                + " shader=\(template.diagnosticProvenance.authoredShaderPath)"
                + " node=\(template.diagnosticProvenance.nodeIndex) codes=\(codes)"
                + " details=\(details)"
        )
#endif
        return diagnosticCodes
    }

}
