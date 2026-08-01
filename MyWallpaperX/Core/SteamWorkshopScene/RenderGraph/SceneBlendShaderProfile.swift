import CryptoKit
import Foundation

/// Exact shader contract for the legacy single-texture `effects/blend` variant.
nonisolated enum SceneBlendShaderProfile: Equatable {
    case legacySingleTexture
    case transformRepeatRequirementSingleTexture

    private struct Fingerprint {
        let profile: SceneBlendShaderProfile
        let canonicalSHA256: String
        let fragmentSHA256: String
    }

    private struct CanonicalShaderPayload: Encodable {
        let identity: String
        let sourceKind: SceneShaderContract.SourceKind
        let stages: [SceneShaderContract.Stage]
        let diagnostics: [SceneShaderContract.Diagnostic]
    }

    nonisolated static func resolve(
        _ contracts: [SceneShaderContract]
    ) -> SceneBlendShaderProfile? {
        let matches = contracts.filter { normalized($0.identity) == shaderIdentity }
        guard matches.count == 1,
              let contract = matches.first,
              contract.sourceKind == .authoredSource,
              contract.diagnostics.isEmpty,
              let fingerprint = fingerprints.first(where: {
                  $0.canonicalSHA256 == contract.canonicalSHA256
              }),
              canonicalHash(contract) == fingerprint.canonicalSHA256,
              contract.stages.count == 2 else {
            return nil
        }
        let expected: [(SceneShaderContract.StageKind, String, String)] = [
            (.vertex, vertexPath, vertexSHA256),
            (.fragment, fragmentPath, fingerprint.fragmentSHA256),
        ]
        guard zip(contract.stages, expected).allSatisfy({ stage, fingerprint in
            stage.kind == fingerprint.0
                && normalized(stage.relativePath) == fingerprint.1
                && stage.rawSHA256 == fingerprint.2
                && sha256(Data(stage.source.utf8)) == fingerprint.2
        }) else {
            return nil
        }
        return fingerprint.profile
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

    private nonisolated static let shaderIdentity = "effects/blend"
    private nonisolated static let vertexPath = "shaders/effects/blend.vert"
    private nonisolated static let vertexSHA256 =
        "1f62202885dbbd8e010aea73c050c965a0780da56604cd74d1e42720ebed937b"
    private nonisolated static let fragmentPath = "shaders/effects/blend.frag"
    private nonisolated static let fingerprints = [
        Fingerprint(
            profile: .legacySingleTexture,
            canonicalSHA256:
                "302ccce9589534ff111de2125e10bbc55a9c2a4034388b43645491033bd1b5a4",
            fragmentSHA256:
                "b66d0515e57113ce960c0c1e5f4bea9100bd18590c4ab1435350be7e06980354"
        ),
        Fingerprint(
            profile: .transformRepeatRequirementSingleTexture,
            canonicalSHA256:
                "135688c4405e7fe9f25577ce391c40d48ed40a465843300b2326839952c111ad",
            fragmentSHA256:
                "0f23200fca3cdb1170b5b16e9d0581003bbf4e8edb34f193df4f083e6ca5fe1b"
        ),
    ]
}
