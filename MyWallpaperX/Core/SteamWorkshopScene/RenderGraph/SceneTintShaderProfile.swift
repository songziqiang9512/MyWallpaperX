import CryptoKit
import Foundation

/// Tint 的逐指纹 shader profile。
///
/// 已验证的 authored variants 携带 2 种 tint shader 源，vert 完全相同，frag 两个版本：
/// - `stock2842`：2.8.42 原版；
/// - `maskOverrideV1`：历史 shader revision，
///   与 stock 逐行 diff 只有两类差异：
///   1. `g_Texture0`/`g_Texture1` 的注解元数据（mask-override-v1 多 `"material":"framebuffer"`、
///      `"material":"mask"`、mask `"default":"util/white"`），不进任何执行路径；
///   2. `#if MASK` 分支：stock 是 `mask *= tex(g_Texture1).r`（与 g_BlendAlpha 相乘），
///      mask-override-v1 是 `mask = tex(g_Texture1).r`（覆盖 g_BlendAlpha）。
///
/// `BLENDMODE` 的 `[COMBO]` 注解两版逐字符一致（default 30）；无遮罩时两版 main
/// 数学逐行相同（`mask = g_BlendAlpha` → `ApplyBlending` → `BLENDMODE == 0` 置 alpha=1，
/// 无输出 clamp）。槽位 1 绑图（编辑器在编译期自动置 `MASK=1`，语料 0 次显式声明）时
/// 两版 mask 语义分流：stock `mask = g_BlendAlpha * tex.r`，mask-override-v1 `mask = tex.r` 覆盖。
/// 另一个已验证的 authored revision 只调整了注解/排版，执行语义仍归入 stock；shader
/// identity 由 definition -> material 链推导，不用 Workshop ID 或资源名选择 profile。
nonisolated enum SceneTintShaderProfile: Equatable {
    case stock2842
    case maskOverrideV1

    /// `#if MASK` 分支语义：stock 将遮罩与 `g_BlendAlpha` 相乘，mask-override-v1 直接覆盖。
    var maskMultipliesBlendAlpha: Bool {
        self == .stock2842
    }

    /// 较早 authored package 的 effect.json 缺 `replacementkey` 字段，其余字段与
    /// stock 逐字段一致；stock 指纹保持必须携带。
    var acceptsMissingReplacementKey: Bool {
        self == .maskOverrideV1
    }

    private struct CanonicalShaderPayload: Encodable {
        let identity: String
        let sourceKind: SceneShaderContract.SourceKind
        let stages: [SceneShaderContract.Stage]
        let diagnostics: [SceneShaderContract.Diagnostic]
    }

    private struct Fingerprint {
        let profile: SceneTintShaderProfile
        let fragmentSHA256: String
    }

    static func resolve(_ contracts: [SceneShaderContract]) -> SceneTintShaderProfile? {
        resolve(contracts, shaderIdentity: stockShaderIdentity)
    }

    /// Shader identity comes from the exact definition -> material chain. The executable
    /// source bytes remain allow-listed, while a byte-identical authored copy may live below
    /// another package-relative shader directory.
    static func resolve(
        _ contracts: [SceneShaderContract],
        shaderIdentity: String
    ) -> SceneTintShaderProfile? {
        let identity = normalized(shaderIdentity)
        let matches = contracts.filter { normalized($0.identity) == identity }
        guard matches.count == 1, let contract = matches.first,
              contract.sourceKind == .authoredSource,
              contract.diagnostics.isEmpty,
              contract.stages.count == 2,
              let fingerprint = fingerprints.first(where: {
                  $0.fragmentSHA256 == contract.stages[1].rawSHA256
              }),
              canonicalHash(contract) == contract.canonicalSHA256
        else {
            return nil
        }
        let expected: [(SceneShaderContract.StageKind, String, String)] = [
            (.vertex, "shaders/\(identity).vert", vertexSHA256),
            (.fragment, "shaders/\(identity).frag", fingerprint.fragmentSHA256),
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

    private static let stockShaderIdentity = "effects/tint"
    private static let vertexSHA256 =
        "62b2f5853fc565d706c1b6c789981385254f8195e0e1579c3d737796b41ddf2a"
    private static let fingerprints = [
        Fingerprint(
            profile: .stock2842,
            fragmentSHA256: "02b9397cec32de6f0d8caa2e1af7c07510752d474bd64048c9d78f55926973f1"
        ),
        Fingerprint(
            profile: .maskOverrideV1,
            fragmentSHA256: "98f97e9e9ed0c22e2216ccdfb50012274f7e9c944a9ea014eaddc45d606ea63a"
        ),
        // Verified Workshop revision: executable mask semantics match stock (`mask *= tex.r`).
        Fingerprint(
            profile: .stock2842,
            fragmentSHA256: "887d9dbc05f5d55e4a0dc8a87820e19896bf61622faffbb212326aa23ae30b3c"
        ),
    ]
}
