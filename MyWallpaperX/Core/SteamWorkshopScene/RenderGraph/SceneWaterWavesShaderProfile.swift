import CryptoKit
import Foundation

/// 官方 `effects/waterwaves` 的逐指纹 shader profile。
///
/// 语料 45 样本携带 6 种 waterwaves shader 源，其中 5 种可执行：
/// - `stock2842`：2.8.42 原版（exponent/DUALWAVES/PERSPECTIVE/TIMEOFFSET combo 全量）；
/// - `legacyReversedDirection`（仅 `2131872317`）：v1 结构，方向基向量 `(0,-1)`（stock 为
///   `(0,1)`，同一 authored direction 波向相反，执行时按 +π 归一）、无 `g_Exponent`
///   （等价 exponent=1）、标量 `g_Perspective` 修正项、mask 无条件采样（default `util/white`）；
/// - `legacyDirectV1`：同 v1 数学但基向量已是 `(0,1)`，两个 fragment 指纹（无 MASK combo
///   的无条件采样版与 `#if MASK` 包裹版，语料 combos 均为空，执行等价）；
/// - `legacyV2`：stock 减 DUALWAVES 段、保留标量 `g_Perspective`，combos 全空时与
///   stock exponent=1 同语义。
/// 第六种（`1553008362`/`1636394814`，label-as-key 语料）实例全部使用编辑器 label 作常量键，
/// 无可执行实例，不纳入白名单。语料全部 `perspective` 常量为 0，planner 只接受 0，
/// 因此执行端无需 perspective 修正项。
nonisolated enum SceneWaterWavesShaderProfile: Equatable {
    case stock2842
    case legacyReversedDirection
    case legacyDirectV1
    case legacyV2

    private struct CanonicalShaderPayload: Encodable {
        let identity: String
        let sourceKind: SceneShaderContract.SourceKind
        let stages: [SceneShaderContract.Stage]
        let diagnostics: [SceneShaderContract.Diagnostic]
    }

    private struct Fingerprint {
        let profile: SceneWaterWavesShaderProfile
        let canonicalSHA256: String
        let vertexSHA256: String
        let fragmentSHA256: String
    }

    /// v1 基向量 `(0,-1)` 等价于 stock 基向量下 direction + π。
    var directionOffset: Float {
        self == .legacyReversedDirection ? .pi : 0
    }

    /// stock 常量必须五键全齐（exact 语料形态）；legacy 语料按编辑器旧行为省略未改动键。
    var allowsOmittedConstants: Bool {
        self != .stock2842
    }

    /// legacy shader 无 `g_Exponent`，执行按 1（`pow(|sin|,1)*sign == sin`）。
    var supportsExponent: Bool {
        self == .stock2842
    }

    /// v1/v2 语料存在未绑 mask 的实例：v1 无条件采样 default `util/white`（=1），
    /// v2 的 MASK combo 未启用，均等价无遮罩。stock 语料实例全部绑图，保持必选。
    var requiresMaskTexture: Bool {
        self == .stock2842
    }

    /// v1 族 definition JSON 无 `gizmos` 字段；stock 与 v2 携带 PERSPECTIVE gizmo。
    var expectsGizmos: Bool {
        self != .legacyReversedDirection && self != .legacyDirectV1
    }

    static func resolve(_ contracts: [SceneShaderContract]) -> SceneWaterWavesShaderProfile? {
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

    private static let shaderIdentity = "effects/waterwaves"
    private static let vertexPath = "shaders/effects/waterwaves.vert"
    private static let fragmentPath = "shaders/effects/waterwaves.frag"

    private static let legacyV1VertexSHA256 =
        "ee89723a81ddc4e9f3f229b265abbfaa0bca2ec314d5eb65b3fd2e4ab78434bf"
    private static let legacyV1FragmentSHA256 =
        "e14c75b9d406fb32c9d46ddcfcb69b2ccef38e4986a4a208556f3cfd516419f4"

    private static let fingerprints = [
        Fingerprint(
            profile: .stock2842,
            canonicalSHA256: "0aa56eeed43aa54d09ced6993f742c07a5dc0cfd1dcd89873f1fb22142e68831",
            vertexSHA256: "188d1e33de160e86708329ed1401cdc546426293e1f0b66b041d5cd556fe388f",
            fragmentSHA256: "18df156687addc31957922f782ec5da44a126619b0ffd60c1b69557d2512d50e"
        ),
        Fingerprint(
            profile: .legacyReversedDirection,
            canonicalSHA256: "df6fb6941d3ded5d2c5a9b53320251a9c710eeb9a75d8aeff5004bd2b1865961",
            vertexSHA256: "89424bfb56ca911fcfd422495ee5aecc9c4b19384f936413979b1a1e036a1a8d",
            fragmentSHA256: legacyV1FragmentSHA256
        ),
        Fingerprint(
            profile: .legacyDirectV1,
            canonicalSHA256: "42275943a4de898cafbb03c1b99b965fcb88b5884b8a9c07e88cc9212318bf82",
            vertexSHA256: legacyV1VertexSHA256,
            fragmentSHA256: legacyV1FragmentSHA256
        ),
        Fingerprint(
            profile: .legacyDirectV1,
            canonicalSHA256: "a1509d2f25023875f3cb5b0d549c79e4385b14001242f5b9f517f47f0c8b813b",
            vertexSHA256: legacyV1VertexSHA256,
            fragmentSHA256: "08a948f94e3c1c1e073a7eb91a0f58b6d0f813462813d945d33d41cbf3e9b0c3"
        ),
        Fingerprint(
            profile: .legacyV2,
            canonicalSHA256: "3d25007f0c6b6b96c1c174c716ee24a82245848d915da9d3c492d5b9e3ba029b",
            vertexSHA256: "a2ca9476e99f64406ccd2750704e1ca86906670a124e636b2bec533cb73bc24a",
            fragmentSHA256: "efa1f32c3a33734c99689f7e4ccd992f71b6827eb5d1ba5572e163853ac3b45b"
        ),
    ]
}
