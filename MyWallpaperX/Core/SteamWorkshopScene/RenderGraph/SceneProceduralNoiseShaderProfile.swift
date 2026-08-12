import CryptoKit
import Foundation

enum SceneProceduralNoiseShaderProfile {
    nonisolated enum Profile: CaseIterable, Sendable {
        case modern
        case worleyColorV1

        var shaderIdentity: String {
            switch self {
            case .modern: "workshop/2906937488/effects/procedural_noise"
            case .worleyColorV1: "workshop/2924967132/effects/procedural_noise"
            }
        }

        var definitionPath: String {
            switch self {
            case .modern: "effects/workshop/2906937488/procedural_noise/effect.json"
            case .worleyColorV1:
                "effects/workshop/2924967132/procedural_noise/effect.json"
            }
        }

        var materialPath: String {
            "materials/\(shaderIdentity).json"
        }

        var materialSHA256: String {
            switch self {
            case .modern:
                "4f48c4c321b1c9058986f253a3e7dfb28febf894f6b6ddb589aa7132cb006d8a"
            case .worleyColorV1:
                "01608b45e4ce2065c1f6cfdf61532771e6408fb8166d1251e905ca64caca1828"
            }
        }

        fileprivate var canonicalSHA256: String {
            switch self {
            case .modern:
                "1c551685d5b7a17a24e1e4d5c85bdd9d93072f621dfc0470b5e624e6b88d0342"
            case .worleyColorV1:
                "6739631a2be09fd772b6cb2b70b2789865153af1eefceea2710600ecb8420b14"
            }
        }

        fileprivate var stageSHA256: (vertex: String, fragment: String) {
            switch self {
            case .modern:
                (
                    "ebe97469efc7c80a6c9501af0a9e9fe3d98c8d6fdc45f112547eaad63a702a84",
                    "915b525ed18ab865191d437f0e3bd6154ea4e41831761148d32a0c1a67e7c767"
                )
            case .worleyColorV1:
                (
                    "32443038eb517a8c16f56ea69e7c731cfa9cf8cdcf5633518095db83ae5a6108",
                    "17747e7bb09b92369a5925b658d94db56b55e1832740097bd16552f045674bf2"
                )
            }
        }
    }

    private nonisolated struct CanonicalPayload: Encodable {
        let identity: String
        let sourceKind: SceneShaderContract.SourceKind
        let stages: [SceneShaderContract.Stage]
        let diagnostics: [SceneShaderContract.Diagnostic]
    }

    nonisolated static func matches(_ contracts: [SceneShaderContract]) -> Bool {
        matchingProfile(contracts) != nil
    }

    nonisolated static func matchingProfile(
        _ contracts: [SceneShaderContract]
    ) -> Profile? {
        let profiles = Profile.allCases.filter { matches(contracts, profile: $0) }
        return profiles.count == 1 ? profiles[0] : nil
    }

    private nonisolated static func matches(
        _ contracts: [SceneShaderContract],
        profile: Profile
    ) -> Bool {
        let matches = contracts.filter {
            normalized($0.identity) == profile.shaderIdentity
        }
        guard matches.count == 1,
              let contract = matches.first,
              contract.sourceKind == .authoredSource,
              contract.diagnostics == expectedDiagnostics(profile),
              contract.canonicalSHA256 == profile.canonicalSHA256,
              canonicalHash(contract) == profile.canonicalSHA256,
              contract.stages.count == 2 else {
            return false
        }
        let hashes = profile.stageSHA256
        let expected: [(SceneShaderContract.StageKind, String, String)] = [
            (.vertex, vertexPath(profile), hashes.vertex),
            (.fragment, fragmentPath(profile), hashes.fragment),
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

    private nonisolated static func vertexPath(_ profile: Profile) -> String {
        "shaders/\(profile.shaderIdentity).vert"
    }

    private nonisolated static func fragmentPath(_ profile: Profile) -> String {
        "shaders/\(profile.shaderIdentity).frag"
    }

    private nonisolated static func expectedDiagnostics(
        _ profile: Profile
    ) -> [SceneShaderContract.Diagnostic] {
        [1, 8].map {
            SceneShaderContract.Diagnostic(
                code: .malformedAnnotation,
                message: "Shader annotation contains malformed JSON.",
                relativePath: fragmentPath(profile),
                line: $0
            )
        }
    }
}
