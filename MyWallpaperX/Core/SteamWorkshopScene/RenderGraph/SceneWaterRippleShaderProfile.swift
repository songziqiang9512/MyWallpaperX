import CryptoKit
import Foundation

/// 官方 `effects/waterripple` 的逐指纹 shader profile。
///
/// 语料 45 样本携带 3 种 waterripple shader 源（4 个可见实例），核心数学
/// （ripple UV 累积、双法线采样、`strength²` 扰动、framebuffer 采样）逐字一致，
/// 按指纹绑定各自语义：
/// - `stock2842`：2.8.42 原版，PERSPECTIVE/MASK combo 齐备，effect.json 带
///   PERSPECTIVE gizmos，scroll 基向量 `rotateVec2(vec2(0,1), dir)`；
/// - `legacyInvertedScroll`（1937925563、2131872317）：无 PERSPECTIVE/MASK
///   combo，mask 无条件采样（槽默认 util/white；planner 仍要求实例显式绑定
///   mask，缺省槽继续 fail closed），scroll 基向量 `vec2(0,-1)`。rotateVec2
///   是线性旋转，`rotateVec2(vec2(0,-1), r) == rotateVec2(vec2(0,1), r + π)`，
///   故对现有 pipeline 精确折算为 `scrolldirection + π`；1937925563 的
///   effect.json 变体没有 replacementkey；
/// - `legacyMaskCombo`（2470144420）：MASK combo 与 scroll 基向量已回到 stock
///   形态，仅缺 PERSPECTIVE 分支；mask UV 取 slot1 自身 resolution，与宿主
///   Metal 复刻的 maskUVScale 语义一致，无需运行时分支。
///
/// legacy 两族的 effect.json 均无 gizmos，实例常量只写非默认键
/// （2131872317 的两实例是 4 键子集），准入按 profile 分流、stock 面保持不变。
nonisolated enum SceneWaterRippleShaderProfile: Equatable {
    case stock2842
    case legacyInvertedScroll
    case legacyMaskCombo

    private struct CanonicalShaderPayload: Encodable {
        let identity: String
        let sourceKind: SceneShaderContract.SourceKind
        let stages: [SceneShaderContract.Stage]
        let diagnostics: [SceneShaderContract.Diagnostic]
    }

    private struct Fingerprint {
        let profile: SceneWaterRippleShaderProfile
        let canonicalSHA256: String
        let vertexSHA256: String
        let fragmentSHA256: String
    }

    /// vert scroll 基向量差异折算到 `scrolldirection` 的偏移（弧度）。
    var scrollDirectionOffset: Float {
        self == .legacyInvertedScroll ? .pi : 0
    }

    /// effect.json 是否要求 stock 的 PERSPECTIVE gizmos 声明（legacy 均无）。
    var expectsPerspectiveGizmos: Bool {
        self == .stock2842
    }

    /// 1937925563 的更早 effect.json 变体没有 replacementkey。
    var acceptsMissingReplacementKey: Bool {
        self == .legacyInvertedScroll
    }

    /// legacy 语料实例只写非默认常量键，准入放宽为白名单键的子集。
    var allowsSparseConstants: Bool {
        self != .stock2842
    }

    static func resolve(
        _ contracts: [SceneShaderContract]
    ) -> SceneWaterRippleShaderProfile? {
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

    private static let shaderIdentity = "effects/waterripple"
    private static let vertexPath = "shaders/effects/waterripple.vert"
    private static let fragmentPath = "shaders/effects/waterripple.frag"

    private static let fingerprints = [
        Fingerprint(
            profile: .stock2842,
            canonicalSHA256: "cff8420a7f1103b6123906feff9db9f3233039d9cd1d9da2e02352700048c7ce",
            vertexSHA256: "e1347f6f4dbec03106514592f652e9f63e6a75dc6e6c3cd8c76138c34dc2e7a4",
            fragmentSHA256: "21bcc2216765fd09804331dec96b9aa94aa4b15e4b5957c6b001371e1e82e38a"
        ),
        Fingerprint(
            profile: .legacyInvertedScroll,
            canonicalSHA256: "cc5e0055ea1015f27d900c47ec56c1b0f4824d5c9189e7dbf765a5da01a51de3",
            vertexSHA256: "274a3349c945f230350a23fdb1baf6e973ba10306d13822338822fc0ca989cdf",
            fragmentSHA256: "795cda51fe98cd21cea8d95594e003aff4746546a7d828d0b4b9bbef326cff6b"
        ),
        Fingerprint(
            profile: .legacyMaskCombo,
            canonicalSHA256: "53bde3dd6b88b1929fb2929843428c3848e94878fd0ee8973159f42de92d55a1",
            vertexSHA256: "3745865023a909b697917183c2aca2ef1fb789854129f9676daaa1c41c8920c8",
            fragmentSHA256: "84716ced71b6a46cb354ac6135f3d38514cebd991c81f372dab1000d46f21b07"
        ),
    ]
}
