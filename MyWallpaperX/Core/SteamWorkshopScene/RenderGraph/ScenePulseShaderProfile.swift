import CryptoKit
import Foundation
import simd

/// 官方 `effects/pulse` 的逐指纹 shader profile。
///
/// 语料 12 个样本携带 5 种 pulse shader 源，其中 4 种可执行、按指纹绑定各自语义：
/// - `stock2842`：2.8.42 原版，`sin(t*speed + phase - π/2)`、noise UV 系数 (1/12, 1/36)、
///   noisespeed 默认 0.5 / range [0,1]、输出 `max(0, rgb)`；
/// - `legacyDirectPhaseSaturate`：历史版，`sin(t*speed + phase)` 无偏移、noise UV (1, 0.333)、
///   noisespeed 默认 0.1 / range [0,0.5]、输出 `saturate(rgba)`；
/// - `legacyDirectPhaseMaxClamp`：主体同上，输出改 `max(0, rgb)`（两个 fragment 写法变体，
///   `CAST3(0)` 与字面 `0`，各自独立指纹）。
/// 另一种（`3088601835` 的 `#ifndef AUDIOPROCESSING` 变体）生效公式取决于 WE combo
/// 注入行为，无证据判定 vert/frag 哪条路径生效，继续 fail closed。
nonisolated enum ScenePulseShaderProfile: Equatable {
    case stock2842
    case legacyDirectPhaseSaturate
    case legacyDirectPhaseMaxClamp

    private struct CanonicalShaderPayload: Encodable {
        let identity: String
        let sourceKind: SceneShaderContract.SourceKind
        let stages: [SceneShaderContract.Stage]
        let diagnostics: [SceneShaderContract.Diagnostic]
    }

    private struct Fingerprint {
        let profile: ScenePulseShaderProfile
        let canonicalSHA256: String
        let vertexSHA256: String
        let fragmentSHA256: String
    }

    /// frag `AUDIOPROCESSING == 0` 分支的 `sin` 相位常数项。
    var phaseOffset: Float {
        switch self {
        case .stock2842: -1.57079632679
        case .legacyDirectPhaseSaturate, .legacyDirectPhaseMaxClamp: 0
        }
    }

    /// noise UV 的时间系数：`vec2(t*x, t*y) * noiseSpeed`。
    var noiseUVScale: SIMD2<Float> {
        switch self {
        case .stock2842: SIMD2(0.08333333, 0.02777777)
        case .legacyDirectPhaseSaturate, .legacyDirectPhaseMaxClamp: SIMD2(1, 0.333)
        }
    }

    /// `noisespeed` 注解的 default 与 range（其余常量各版本注解一致）。
    var noiseSpeedDefault: Double {
        switch self {
        case .stock2842: 0.5
        case .legacyDirectPhaseSaturate, .legacyDirectPhaseMaxClamp: 0.1
        }
    }

    var noiseSpeedRange: ClosedRange<Double> {
        switch self {
        case .stock2842: 0 ... 1
        case .legacyDirectPhaseSaturate, .legacyDirectPhaseMaxClamp: 0 ... 0.5
        }
    }

    /// 输出行：`saturate(albedo)` 或 `vec4(max(0, rgb), a)`。
    var saturatesOutput: Bool {
        self == .legacyDirectPhaseSaturate
    }

    /// 旧编辑器定义省略了 `replacementkey`；只对已登记的 legacy shader 指纹兼容。
    var acceptsMissingReplacementKey: Bool {
        switch self {
        case .stock2842: false
        case .legacyDirectPhaseSaturate, .legacyDirectPhaseMaxClamp: true
        }
    }

    static func resolve(_ contracts: [SceneShaderContract]) -> ScenePulseShaderProfile? {
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

    private static let shaderIdentity = "effects/pulse"
    private static let vertexPath = "shaders/effects/pulse.vert"
    private static let fragmentPath = "shaders/effects/pulse.frag"

    private static let stockVertexSHA256 =
        "01612b2020ff6c7e22dc579dbb783d516028d14611c1f6ddae697ca7550739d8"
    private static let legacyVertexSHA256 =
        "3db10db7124931886b399661dc80e47417b27fa3b371160e1d08e00ee53be5c0"

    private static let fingerprints = [
        Fingerprint(
            profile: .stock2842,
            canonicalSHA256: "2746ccd536d5df618469a2718df92d140dfd0cdc9f947675b3aec513eb7910ae",
            vertexSHA256: stockVertexSHA256,
            fragmentSHA256: "96ff3e88180d0c3a6c2e24cd83c1c407d50b468e6130f4b2cc228ec366860f52"
        ),
        Fingerprint(
            profile: .legacyDirectPhaseSaturate,
            canonicalSHA256: "6a7ccf09278fa489567ef995f7f29bf60bf9b6fe16f9b3b009cf6687dca41416",
            vertexSHA256: legacyVertexSHA256,
            fragmentSHA256: "6854cdb0a22d6cb973dfedaae5654c5340759ee67e5c123c569e29ab11677820"
        ),
        Fingerprint(
            profile: .legacyDirectPhaseMaxClamp,
            canonicalSHA256: "a0deed377026f1e70bb215f9126bfd569394dc6f42c10f08a9020917753895df",
            vertexSHA256: legacyVertexSHA256,
            fragmentSHA256: "4a152125352c805508982c53ad17479584f12cfb7c84ddd9142a1ac9d2a9c374"
        ),
        Fingerprint(
            profile: .legacyDirectPhaseMaxClamp,
            canonicalSHA256: "049a32252a75e49dc86ec38f8f5429511ee55c44973128fcabf2b156866c51eb",
            vertexSHA256: legacyVertexSHA256,
            fragmentSHA256: "fa64321ea52b8d53286438eeba2d3a88ccad440192eb32f7b1fd2f4819e12c53"
        ),
    ]
}
