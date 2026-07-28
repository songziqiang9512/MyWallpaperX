import CryptoKit
import Foundation

/// Strict fingerprint set for the stock three-pass Cursor Ripple shaders.
///
/// The renderer below is a clean-room implementation. These fingerprints only
/// admit the declaration shape that the implementation was validated against.
nonisolated enum SceneCursorRippleShaderProfile {
    private struct CanonicalShaderPayload: Encodable {
        let identity: String
        let sourceKind: SceneShaderContract.SourceKind
        let stages: [SceneShaderContract.Stage]
        let diagnostics: [SceneShaderContract.Diagnostic]
    }

    private struct Fingerprint {
        let identity: String
        let vertexPath: String
        let fragmentPath: String
        let variants: [Variant]
    }

    private struct Variant {
        let canonicalSHA256: String
        let vertexSHA256: String
        let fragmentSHA256: String
    }

    static func matches(_ contracts: [SceneShaderContract]) -> Bool {
        let relevant = contracts.filter {
            fingerprints.map(\.identity).contains(normalized($0.identity))
        }
        guard relevant.count == fingerprints.count else { return false }
        guard fingerprints.allSatisfy({ fingerprint in
            let matches = relevant.filter {
                normalized($0.identity) == fingerprint.identity
            }
            guard matches.count == 1, let contract = matches.first,
                  contract.sourceKind == .authoredSource,
                  contract.diagnostics.isEmpty,
                  contract.stages.count == 2 else {
                return false
            }
            let expected: [(SceneShaderContract.StageKind, String)] = [
                (.vertex, fingerprint.vertexPath),
                (.fragment, fingerprint.fragmentPath),
            ]
            guard zip(contract.stages, expected).allSatisfy({ stage, value in
                stage.kind == value.0
                    && normalized(stage.relativePath) == value.1
            }) else {
                return false
            }
            let canonical = canonicalHash(contract)
            return fingerprint.variants.contains { variant in
                contract.canonicalSHA256 == variant.canonicalSHA256
                    && canonical == variant.canonicalSHA256
                    && contract.stages[0].rawSHA256 == variant.vertexSHA256
                    && sha256(Data(contract.stages[0].source.utf8))
                        == variant.vertexSHA256
                    && contract.stages[1].rawSHA256 == variant.fragmentSHA256
                    && sha256(Data(contract.stages[1].source.utf8))
                        == variant.fragmentSHA256
            }
        }) else {
            return false
        }
        let canonicalByIdentity = Dictionary(uniqueKeysWithValues: relevant.map {
            (normalized($0.identity), $0.canonicalSHA256)
        })
        return acceptedProfiles.contains { profile in
            profile.allSatisfy { canonicalByIdentity[$0.key] == $0.value }
        }
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

    private static let fingerprints = [
        Fingerprint(
            identity: "effects/cursorripple_apply_force",
            vertexPath: "shaders/effects/cursorripple_apply_force.vert",
            fragmentPath: "shaders/effects/cursorripple_apply_force.frag",
            variants: [
                Variant(
                    canonicalSHA256: "eaa7aa5c9d8692e4cdd120bacd4a3c7ae30769a07d5c43b6f4b26d05e03d0250",
                    vertexSHA256: "a08e7647493ad1229d659b814d95462d2d2e157560f17d8e62599e4561f33bc7",
                    fragmentSHA256: "1d5809d0457c58dc88738118fb0b17475af33c32c2e7204b46fef8f8776323a8"
                ),
                Variant(
                    canonicalSHA256: "a5a87216dacbf6a66508a222c2cebd116f4518eb62dd87522b28fe93aa85eaa3",
                    vertexSHA256: "a08e7647493ad1229d659b814d95462d2d2e157560f17d8e62599e4561f33bc7",
                    fragmentSHA256: "1c7f5bc1046e4dd3240fcedb73272f2aad845e9c5fe7ed6b921671b48255b16e"
                ),
            ]
        ),
        Fingerprint(
            identity: "effects/cursorripple_simulate_force",
            vertexPath: "shaders/effects/cursorripple_simulate_force.vert",
            fragmentPath: "shaders/effects/cursorripple_simulate_force.frag",
            variants: [
                Variant(
                    canonicalSHA256: "22b259ac7e208087befa7ac09bd87b1a3d74daff230b3cdde8371eb15cb314cf",
                    vertexSHA256: "f859ae16e4ef489ecf7b67ae8495287696127eaf28b092bb1354f9657074a8c6",
                    fragmentSHA256: "e36af11201fa65d7a51069d4d0252457c173e58fa18dce682550c92a36e3db3e"
                ),
                Variant(
                    canonicalSHA256: "6b194db9c013d7f6cc7a63fe30885f8e037b56607b0ba43d69a9d162d16e0037",
                    vertexSHA256: "f859ae16e4ef489ecf7b67ae8495287696127eaf28b092bb1354f9657074a8c6",
                    fragmentSHA256: "bfd7293d3e8a46e2b18e4538f47b4547855ca702ab7c729f7b033aadf17559b6"
                ),
            ]
        ),
        Fingerprint(
            identity: "effects/cursorripple_combine",
            vertexPath: "shaders/effects/cursorripple_combine.vert",
            fragmentPath: "shaders/effects/cursorripple_combine.frag",
            variants: [
                Variant(
                    canonicalSHA256: "27b77f811b74f2754bedf8b9f8d4ed66ded84695154c3432438459a94dcf01c6",
                    vertexSHA256: "46b9bade0e6be4e3942a3848894053370dc9c8801b6ae4419c5617adb503d974",
                    fragmentSHA256: "5da561c2de6bcf8e6e7b8614509febac7d9ae8655ded7349069fa046387f4744"
                ),
            ]
        ),
    ]

    private static let acceptedProfiles = [
        [
            "effects/cursorripple_apply_force":
                "eaa7aa5c9d8692e4cdd120bacd4a3c7ae30769a07d5c43b6f4b26d05e03d0250",
            "effects/cursorripple_simulate_force":
                "22b259ac7e208087befa7ac09bd87b1a3d74daff230b3cdde8371eb15cb314cf",
            "effects/cursorripple_combine":
                "27b77f811b74f2754bedf8b9f8d4ed66ded84695154c3432438459a94dcf01c6",
        ],
        [
            "effects/cursorripple_apply_force":
                "a5a87216dacbf6a66508a222c2cebd116f4518eb62dd87522b28fe93aa85eaa3",
            "effects/cursorripple_simulate_force":
                "6b194db9c013d7f6cc7a63fe30885f8e037b56607b0ba43d69a9d162d16e0037",
            "effects/cursorripple_combine":
                "27b77f811b74f2754bedf8b9f8d4ed66ded84695154c3432438459a94dcf01c6",
        ],
    ]
}
