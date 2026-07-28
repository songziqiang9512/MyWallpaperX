import CryptoKit
import Foundation

nonisolated enum SceneFoliageSwayShaderProfile {
    case stock
    case legacyExplicitNoise

    var acceptsSparseConstants: Bool {
        self == .legacyExplicitNoise
    }

    var expectsExplicitNoise: Bool {
        self == .legacyExplicitNoise
    }

    static func resolve(_ contracts: [SceneShaderContract]) -> Self? {
        let matches = contracts.filter {
            normalized($0.identity) == shaderIdentity
        }
        guard matches.count == 1, let contract = matches.first,
              contract.sourceKind == .authoredSource,
              contract.diagnostics.isEmpty,
              contract.stages.count == 2,
              canonicalHash(contract) == contract.canonicalSHA256
        else {
            return nil
        }

        let profile: Self
        switch contract.canonicalSHA256 {
        case stockCanonicalSHA256:
            profile = .stock
        case legacyCanonicalSHA256:
            profile = .legacyExplicitNoise
        default:
            return nil
        }
        let expected = profile == .stock ? stockStages : legacyStages
        guard zip(contract.stages, expected).allSatisfy({ stage, fingerprint in
            stage.kind == fingerprint.kind
                && normalized(stage.relativePath) == fingerprint.path
                && stage.rawSHA256 == fingerprint.sha256
                && sha256(Data(stage.source.utf8)) == fingerprint.sha256
        }) else {
            return nil
        }
        return profile
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
        let sha256: String
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

    private static let shaderIdentity = "effects/foliagesway"
    private static let vertexPath = "shaders/effects/foliagesway.vert"
    private static let fragmentPath = "shaders/effects/foliagesway.frag"
    private static let stockCanonicalSHA256 =
        "1f5c11c92bb715d86fd0b57f59c4fb5b263596a2bbeb158276336b7cc86544d6"
    private static let legacyCanonicalSHA256 =
        "d66f4e9c99b4a6801682e55064fba1692c1a4f1a7f931c34a91215375aca651a"
    private static let stockStages = [
        StageFingerprint(
            kind: .vertex,
            path: vertexPath,
            sha256: "4ee7daa1e00a02feed697b59950218444c82f9b82cc7418f72fcdee6f4545c49"
        ),
        StageFingerprint(
            kind: .fragment,
            path: fragmentPath,
            sha256: "02954542ab458f828eeb0d9da8201f02bf9c180effecacb81e86402704040f4c"
        ),
    ]
    private static let legacyStages = [
        StageFingerprint(
            kind: .vertex,
            path: vertexPath,
            sha256: "7c68e415c544b7e1764ffa0f9486d550df050fa2624c4ad45aaa2543d519b134"
        ),
        StageFingerprint(
            kind: .fragment,
            path: fragmentPath,
            sha256: "87bd90b1363ee00663ad851e95ae6491afd5fdcd8ae3a64d2f4ba65d20cb0922"
        ),
    ]
}
