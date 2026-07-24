import CryptoKit
import Foundation

nonisolated enum SceneWaterFlowShaderProfile {
    case legacy
    case phaseFeather

    private struct CanonicalShaderPayload: Encodable {
        let identity: String
        let sourceKind: SceneShaderContract.SourceKind
        let stages: [SceneShaderContract.Stage]
        let diagnostics: [SceneShaderContract.Diagnostic]
    }

    private struct Fingerprint {
        let profile: SceneWaterFlowShaderProfile
        let canonicalSHA256: String
        let vertexSHA256: String
        let fragmentSHA256: String
    }

    static func resolve(_ contracts: [SceneShaderContract]) -> SceneWaterFlowShaderProfile? {
        let matches = contracts.filter { normalized($0.identity) == shaderIdentity }
        guard matches.count == 1, let contract = matches.first,
              contract.sourceKind == .authoredSource,
              contract.diagnostics.isEmpty,
              contract.stages.count == 2,
              let fingerprint = fingerprints.first(where: {
                  $0.canonicalSHA256 == contract.canonicalSHA256
              }),
              canonicalHash(contract) == fingerprint.canonicalSHA256 else {
            return nil
        }
        let expected: [(SceneShaderContract.StageKind, String, String)] = [
            (.vertex, vertexPath, fingerprint.vertexSHA256),
            (.fragment, fragmentPath, fingerprint.fragmentSHA256),
        ]
        guard zip(contract.stages, expected).allSatisfy({ stage, expected in
            stage.kind == expected.0
                && normalized(stage.relativePath) == expected.1
                && stage.rawSHA256 == expected.2
                && sha256(Data(stage.source.utf8)) == expected.2
        }) else {
            return nil
        }
        return fingerprint.profile
    }

    private static func canonicalHash(_ contract: SceneShaderContract) -> String {
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

    private static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static let shaderIdentity = "effects/waterflow"
    private static let vertexPath = "shaders/effects/waterflow.vert"
    private static let fragmentPath = "shaders/effects/waterflow.frag"
    private static let fingerprints = [
        Fingerprint(
            profile: .legacy,
            canonicalSHA256: "63ef341dd11eb804ecc05196ff86e5802b950cec8d3dcf29b4bc20872595c2e3",
            vertexSHA256: "45803f340c80659ca4726cdea107eb017e7638a64a1b9ff7d30093d1938a738e",
            fragmentSHA256: "20928cfc8b69497820cd70dc98d18f32398ba473707e1c72363670707af6dc7f"
        ),
        Fingerprint(
            profile: .phaseFeather,
            canonicalSHA256: "2e6af4aa60155e94d9b8026be9a68b36eb2dee68243546256b06b5d63c94aa1d",
            vertexSHA256: "b89a287994b2553b0bcb8456f8ff8d6cbc7fe37a795f424c45ed57b0a6014f8f",
            fragmentSHA256: "702c8d882360827b856a5ea82d427faad9857e45cad8fc2b5ddb3fdc7eee92db"
        ),
    ]
}
