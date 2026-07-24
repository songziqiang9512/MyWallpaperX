import CryptoKit
import Foundation

nonisolated enum SceneShakeShaderProfile {
    case whitePhaseFallback
    case timeOffsetCombo

    private struct CanonicalShaderPayload: Encodable {
        let identity: String
        let sourceKind: SceneShaderContract.SourceKind
        let stages: [SceneShaderContract.Stage]
        let diagnostics: [SceneShaderContract.Diagnostic]
    }

    private struct Fingerprint {
        let profile: SceneShakeShaderProfile
        let canonicalSHA256: String
        let fragmentSHA256: String
    }

    static func resolve(_ contracts: [SceneShaderContract]) -> SceneShakeShaderProfile? {
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
            (.vertex, vertexPath, vertexSHA256),
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

    private static let shaderIdentity = "effects/shake"
    private static let vertexPath = "shaders/effects/shake.vert"
    private static let vertexSHA256 =
        "9b884c23ad3e38cb7fa76330bf98d8f7029653c3a73f7a732f1cfd3c3829c4bc"
    private static let fragmentPath = "shaders/effects/shake.frag"
    private static let fingerprints = [
        Fingerprint(
            profile: .whitePhaseFallback,
            canonicalSHA256: "9b94cf5844faf7b0a5a01f1d81195f9a26752e6e55057aa821a8074e6187ac76",
            fragmentSHA256: "f8734c9237d2393bab81b06db8d54cfa6afb64d1687edbf7572db3be52ee27cf"
        ),
        Fingerprint(
            profile: .timeOffsetCombo,
            canonicalSHA256: "1f6fec9dd4296d518694aeb2177b9131a9b9e9789c5cbcb636054164c75e8bf3",
            fragmentSHA256: "9f3d003499dea2870d2f49692c7d859e38499f35f82574daaebccbce0b0d57ac"
        ),
    ]
}
