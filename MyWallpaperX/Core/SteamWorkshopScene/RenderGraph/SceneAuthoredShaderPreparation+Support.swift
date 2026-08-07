import Foundation

extension SceneAuthoredShaderPreparation {
    nonisolated static func fallbackGraph(
        for contract: SceneShaderContract
    ) -> SceneShaderSourceGraph {
        let roots = contract.stages.map {
            SceneShaderSourceGraph.RootRequest(
                label: $0.kind.rawValue,
                virtualPath: $0.relativePath
            )
        }
        let nodes = contract.stages.map {
            SceneShaderSourceGraph.Node(
                virtualPath: $0.relativePath,
                provenance: .legacyContract,
                source: $0.source,
                rawSHA256: $0.rawSHA256,
                byteCount: $0.source.utf8.count
            )
        }
        let edges = contract.stages.map {
            SceneShaderSourceGraph.Edge(
                parentVirtualPath: nil,
                line: nil,
                request: $0.relativePath,
                candidates: [.init(
                    virtualPath: $0.relativePath,
                    provenance: .legacyContract,
                    outcome: .resolved(rawSHA256: $0.rawSHA256)
                )],
                outcome: .resolved(virtualPath: $0.relativePath)
            )
        }
        return .init(
            roots: roots,
            nodes: nodes,
            edges: edges,
            diagnostics: [],
            dependencySHA256: contract.canonicalSHA256
        )
    }

    nonisolated static func failure(
        phase: SceneEffectStageCompilerFailure.Phase,
        code: SceneEffectStageCompilerFailure.Code,
        details: [String] = []
    ) -> SceneAuthoredShaderPreparationFailure {
        .init(phase: phase, code: code, details: details)
    }
}
