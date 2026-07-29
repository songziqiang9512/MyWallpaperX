import CryptoKit
import Foundation
import simd

/// Iris 仍使用现有的受限 inline 视觉实现，但可以作为 strict authored chain 的末端，
/// 避免前面的精确 WaterRipple / WaterWaves / Foliage stages 被整链降级。
nonisolated struct SceneIrisInlineSuffixPlan {
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let maskTexturePath: String
    let scale: SIMD2<Float>
    let speed: Float
    let rough: Float
    let noiseAmount: Float
    let phase: Float

    @MainActor var inputs: SceneLayerEffectInputs {
        SceneLayerEffectInputs(
            flags: [.irisMask],
            params0: SIMD4(scale.x, scale.y, speed, phase),
            params1: SIMD4(rough, noiseAmount, 0, 0),
            params2: .zero,
            params3: .zero,
            params4: .zero
        )
    }
}

nonisolated enum SceneIrisShaderProfile: Equatable {
    case legacyExtendedPhase
    case stock

    private struct CanonicalShaderPayload: Encodable {
        let identity: String
        let sourceKind: SceneShaderContract.SourceKind
        let stages: [SceneShaderContract.Stage]
        let diagnostics: [SceneShaderContract.Diagnostic]
    }

    private struct Fingerprint {
        let profile: SceneIrisShaderProfile
        let canonical: String
        let vertex: String
        let fragment: String
    }

    var phaseRange: ClosedRange<Double> {
        switch self {
        case .legacyExtendedPhase: -5 ... 5
        case .stock: -1 ... 1
        }
    }

    static func resolve(_ contracts: [SceneShaderContract]) -> SceneIrisShaderProfile? {
        let matches = contracts.filter { normalized($0.identity) == shaderIdentity }
        guard matches.count == 1, let contract = matches.first,
              contract.sourceKind == .authoredSource,
              contract.diagnostics.isEmpty,
              contract.stages.count == 2,
              let fingerprint = fingerprints.first(where: {
                  $0.canonical == contract.canonicalSHA256
              }),
              canonicalHash(contract) == fingerprint.canonical else {
            return nil
        }
        let expected: [(SceneShaderContract.StageKind, String, String)] = [
            (.vertex, vertexPath, fingerprint.vertex),
            (.fragment, fragmentPath, fingerprint.fragment),
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

    private static let shaderIdentity = "effects/iris"
    private static let vertexPath = "shaders/effects/iris.vert"
    private static let fragmentPath = "shaders/effects/iris.frag"
    private static let fingerprints = [
        Fingerprint(
            profile: .legacyExtendedPhase,
            canonical: "1b0dd8794faa3c479ecdf88aa0d92f6e182e87f302f02db16b11cfa655d66401",
            vertex: "ab91dde18dd7bfc43d06e685ba0337ce0a9bdef5207f70c7b253b93e731b0782",
            fragment: "03f94fa0bd7410107c4ac7a0447229737c1c08c70823f1c2b5bc2fa55c45ddc9"
        ),
        Fingerprint(
            profile: .stock,
            canonical: "41618dd2e8c5ff66efdb8d51291717fb5778d6df01dee42854b21fc8559e099d",
            vertex: "369a7485ca3211761120fbf84de55e9592c2bb7e0b4e1f7d866a9fcaaf32d5ed",
            fragment: "f768ff800f6fccaf1e5d2e0fd032932a9e5ff41863e4114989e8351e14074651"
        ),
    ]
}
