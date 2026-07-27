import CryptoKit
import Foundation

enum SceneProceduralNoiseShaderProfile {
    private nonisolated struct CanonicalPayload: Encodable {
        let identity: String
        let sourceKind: SceneShaderContract.SourceKind
        let stages: [SceneShaderContract.Stage]
        let diagnostics: [SceneShaderContract.Diagnostic]
    }

    nonisolated static func matches(_ contracts: [SceneShaderContract]) -> Bool {
        let matches = contracts.filter { normalized($0.identity) == shaderIdentity }
        guard matches.count == 1,
              let contract = matches.first,
              contract.sourceKind == .authoredSource,
              contract.diagnostics == expectedDiagnostics,
              contract.canonicalSHA256 == canonicalSHA256,
              canonicalHash(contract) == canonicalSHA256,
              contract.stages.count == 2 else {
            return false
        }
        let expected: [(SceneShaderContract.StageKind, String, String)] = [
            (.vertex, vertexPath, vertexSHA256),
            (.fragment, fragmentPath, fragmentSHA256),
        ]
        return zip(contract.stages, expected).allSatisfy { stage, fingerprint in
            stage.kind == fingerprint.0
                && normalized(stage.relativePath) == fingerprint.1
                && stage.rawSHA256 == fingerprint.2
                && sha256(Data(stage.source.utf8)) == fingerprint.2
        }
    }

    private nonisolated static func canonicalHash(_ contract: SceneShaderContract) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let payload = CanonicalPayload(
            identity: contract.identity,
            sourceKind: contract.sourceKind,
            stages: contract.stages,
            diagnostics: contract.diagnostics
        )
        guard let data = try? encoder.encode(payload) else { return "" }
        return sha256(data)
    }

    private nonisolated static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private nonisolated static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static let shaderIdentity =
        "workshop/2906937488/effects/procedural_noise"
    private nonisolated static let canonicalSHA256 =
        "1c551685d5b7a17a24e1e4d5c85bdd9d93072f621dfc0470b5e624e6b88d0342"
    private nonisolated static let vertexPath =
        "shaders/workshop/2906937488/effects/procedural_noise.vert"
    private nonisolated static let vertexSHA256 =
        "ebe97469efc7c80a6c9501af0a9e9fe3d98c8d6fdc45f112547eaad63a702a84"
    private nonisolated static let fragmentPath =
        "shaders/workshop/2906937488/effects/procedural_noise.frag"
    private nonisolated static let fragmentSHA256 =
        "915b525ed18ab865191d437f0e3bd6154ea4e41831761148d32a0c1a67e7c767"
    private nonisolated static let expectedDiagnostics = [
        SceneShaderContract.Diagnostic(
            code: .malformedAnnotation,
            message: "Shader annotation contains malformed JSON.",
            relativePath: fragmentPath,
            line: 1
        ),
        SceneShaderContract.Diagnostic(
            code: .malformedAnnotation,
            message: "Shader annotation contains malformed JSON.",
            relativePath: fragmentPath,
            line: 8
        ),
    ]
}
