import Foundation

/// Exact content identity for the bounded stock Water Caustics executor.
nonisolated enum SceneWaterCausticsAssetProfile {
    static let definitionPath = "effects/watercaustics/effect.json"
    static let definitionSHA256 =
        "0665351905c34c9f240c9ed7be583ef585a0ac947e6e1d56b6e60e2cbe6fe44e"
    static let materialPath = "materials/effects/caustics.json"
    static let materialPassID = "materials/effects/caustics.json#0"
    static let materialSHA256 =
        "95f860e435d1e7f0eaca4a820713d449f251c5f4ad0dea061e6850b22b6dfa88"
    static let shaderIdentity = "effects/caustics"
    static let vertexSHA256 =
        "32cc146321b03ce8c398a73c5450a9067505d2f0d0d323ebd0c849349e423038"
    static let fragmentSHA256 =
        "e1b1c23def0461cb0febdf043b84a3855823ea970e807dd73678d8d59e0315c3"
    static let dependencies = [
        materialPath,
        "shaders/effects/caustics.frag",
        "shaders/effects/caustics.vert",
    ]

    static func accepts(_ contracts: [SceneShaderContract]) -> Bool {
        let matches = contracts.filter { normalized($0.identity) == shaderIdentity }
        guard matches.count == 1, let contract = matches.first,
              contract.sourceKind == .authoredSource,
              contract.diagnostics.isEmpty,
              contract.stages.count == 2 else {
            return false
        }
        return stage(
            contract.stages[0], kind: .vertex,
            path: "shaders/effects/caustics.vert", sha256: vertexSHA256
        ) && stage(
            contract.stages[1], kind: .fragment,
            path: "shaders/effects/caustics.frag", sha256: fragmentSHA256
        )
    }

    private static func stage(
        _ stage: SceneShaderContract.Stage,
        kind: SceneShaderContract.StageKind,
        path: String,
        sha256: String
    ) -> Bool {
        stage.kind == kind
            && normalized(stage.relativePath) == path
            && stage.rawSHA256 == sha256
    }

    static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}
