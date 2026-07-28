import CryptoKit
import Foundation

/// Exact shader contract for the identity-only `effects/transform` backend.
nonisolated enum SceneTransformShaderProfile: Equatable {
    case stock2842

    private struct CanonicalShaderPayload: Encodable {
        let identity: String
        let sourceKind: SceneShaderContract.SourceKind
        let stages: [SceneShaderContract.Stage]
        let diagnostics: [SceneShaderContract.Diagnostic]
    }

    nonisolated static func resolve(
        _ contracts: [SceneShaderContract]
    ) -> SceneTransformShaderProfile? {
        let matches = contracts.filter { normalized($0.identity) == shaderIdentity }
        guard matches.count == 1,
              let contract = matches.first,
              contract.sourceKind == .authoredSource,
              contract.diagnostics.isEmpty,
              contract.canonicalSHA256 == canonicalSHA256,
              canonicalHash(contract) == canonicalSHA256,
              contract.stages.count == 2 else {
            return nil
        }
        let expected: [(SceneShaderContract.StageKind, String, String)] = [
            (.vertex, vertexPath, vertexSHA256),
            (.fragment, fragmentPath, fragmentSHA256),
        ]
        guard zip(contract.stages, expected).allSatisfy({ stage, fingerprint in
            stage.kind == fingerprint.0
                && normalized(stage.relativePath) == fingerprint.1
                && stage.rawSHA256 == fingerprint.2
                && sha256(Data(stage.source.utf8)) == fingerprint.2
        }) else {
            return nil
        }
        return .stock2842
    }

    private nonisolated static func canonicalHash(_ contract: SceneShaderContract) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let payload = CanonicalShaderPayload(
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

    private nonisolated static let shaderIdentity = "effects/transform"
    private nonisolated static let canonicalSHA256 =
        "4d17f8fde4946dd237a05daeef62755f32b69c6e530556cdc7ad532d26a809c1"
    private nonisolated static let vertexPath = "shaders/effects/transform.vert"
    private nonisolated static let vertexSHA256 =
        "be9ac1692d3a51a1690e79e098a6e3e10ab33604756448e40586ddf62b1b6dd3"
    private nonisolated static let fragmentPath = "shaders/effects/transform.frag"
    private nonisolated static let fragmentSHA256 =
        "d8a60fd26e6b9707971297dd25311b4f0dcff3aa108b8d08c28a2a5f828e6d01"
}
