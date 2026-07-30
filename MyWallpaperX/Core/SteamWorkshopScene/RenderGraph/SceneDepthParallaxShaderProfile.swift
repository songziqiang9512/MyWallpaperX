import CryptoKit
import Foundation

nonisolated enum SceneDepthParallaxShaderProfile {
    case stock2842

    static func resolve(_ contracts: [SceneShaderContract]) -> Self? {
        let matches = contracts.filter {
            normalized($0.identity) == shaderIdentity
        }
        guard matches.count == 1,
              let contract = matches.first,
              contract.sourceKind == .authoredSource,
              contract.diagnostics.isEmpty,
              contract.canonicalSHA256 == canonicalSHA256,
              canonicalHash(contract) == canonicalSHA256,
              contract.stages.count == stages.count,
              zip(contract.stages, stages).allSatisfy({ stage, expected in
                  stage.kind == expected.kind
                      && normalized(stage.relativePath) == expected.path
                      && stage.rawSHA256 == expected.rawSHA256
                      && sha256(Data(stage.source.utf8)) == expected.rawSHA256
              }) else {
            return nil
        }
        return .stock2842
    }

    private struct CanonicalShaderPayload: Encodable {
        let identity: String
        let sourceKind: SceneShaderContract.SourceKind
        let stages: [SceneShaderContract.Stage]
        let diagnostics: [SceneShaderContract.Diagnostic]
    }

    private struct StageFingerprint {
        let kind: SceneShaderContract.StageKind
        let path: String
        let rawSHA256: String
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

    private static let shaderIdentity = "effects/depthparallax"
    private static let canonicalSHA256 =
        "62adf16ec6b93cd6adf46c412b974aabad74131212fb2bba96aeda901255adef"
    private static let stages = [
        StageFingerprint(
            kind: .vertex,
            path: "shaders/effects/depthparallax.vert",
            rawSHA256:
                "4479e604f99a9355685811fe3a78ad7196e55da296c5f63411630d9eb91d7d98"
        ),
        StageFingerprint(
            kind: .fragment,
            path: "shaders/effects/depthparallax.frag",
            rawSHA256:
                "bc947d45d05887456649b025297c656f16057384cbec1114d9b83f8ae9f67585"
        ),
    ]
}
