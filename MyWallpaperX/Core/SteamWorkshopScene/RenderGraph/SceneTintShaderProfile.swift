import CryptoKit
import Foundation

/// 官方 `effects/tint` 的逐指纹 shader profile。
///
/// 语料 45 样本携带 2 种 tint shader 源，vert 完全相同（`62b2f585…`），frag 两个版本：
/// - `stock2842`：2.8.42 原版；
/// - `legacyMaskOverride`：历史版（样本 `1937925563` / `2131872317`，25 个可见实例），
///   与 stock 逐行 diff 只有两类差异：
///   1. `g_Texture0`/`g_Texture1` 的注解元数据（legacy 多 `"material":"framebuffer"`、
///      `"material":"mask"`、mask `"default":"util/white"`），不进任何执行路径；
///   2. `#if MASK` 分支：stock 是 `mask *= tex(g_Texture1).r`（与 g_BlendAlpha 相乘），
///      legacy 是 `mask = tex(g_Texture1).r`（覆盖 g_BlendAlpha）。
///
/// `BLENDMODE` 的 `[COMBO]` 注解两版逐字符一致（default 30）；无遮罩时两版 main
/// 数学逐行相同（`mask = g_BlendAlpha` → `ApplyBlending` → `BLENDMODE == 0` 置 alpha=1，
/// 无输出 clamp）。槽位 1 绑图（编辑器在编译期自动置 `MASK=1`，语料 0 次显式声明）时
/// 两版 mask 语义分流：stock `mask = g_BlendAlpha * tex.r`，legacy `mask = tex.r` 覆盖。
nonisolated enum SceneTintShaderProfile: Equatable {
    case stock2842
    case legacyMaskOverride

    /// `#if MASK` 分支语义：stock 将遮罩与 `g_BlendAlpha` 相乘，legacy 直接覆盖。
    var maskMultipliesBlendAlpha: Bool {
        self == .stock2842
    }

    private struct CanonicalShaderPayload: Encodable {
        let identity: String
        let sourceKind: SceneShaderContract.SourceKind
        let stages: [SceneShaderContract.Stage]
        let diagnostics: [SceneShaderContract.Diagnostic]
    }

    private struct Fingerprint {
        let profile: SceneTintShaderProfile
        let canonicalSHA256: String
        let fragmentSHA256: String
    }

    static func resolve(_ contracts: [SceneShaderContract]) -> SceneTintShaderProfile? {
        let matches = contracts.filter { normalized($0.identity) == shaderIdentity }
        guard matches.count == 1, let contract = matches.first,
              contract.sourceKind == .authoredSource,
              contract.diagnostics.isEmpty,
              contract.stages.count == 2,
              let fingerprint = fingerprints.first(where: {
                  $0.canonicalSHA256 == contract.canonicalSHA256
              }),
              canonicalHash(contract) == fingerprint.canonicalSHA256
        else {
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

    private static let shaderIdentity = "effects/tint"
    private static let vertexPath = "shaders/effects/tint.vert"
    private static let vertexSHA256 =
        "62b2f5853fc565d706c1b6c789981385254f8195e0e1579c3d737796b41ddf2a"
    private static let fragmentPath = "shaders/effects/tint.frag"
    private static let fingerprints = [
        Fingerprint(
            profile: .stock2842,
            canonicalSHA256: "606ea00aef226fc0d7d1360f9bb4750af3c323831bc94399c64327084c9f5b36",
            fragmentSHA256: "02b9397cec32de6f0d8caa2e1af7c07510752d474bd64048c9d78f55926973f1"
        ),
        Fingerprint(
            profile: .legacyMaskOverride,
            canonicalSHA256: "3c418471e512703771cdf2bd3ffbfeda024113fa6edd426ddd37267605e087ee",
            fragmentSHA256: "98f97e9e9ed0c22e2216ccdfb50012274f7e9c944a9ea014eaddc45d606ea63a"
        ),
    ]
}
