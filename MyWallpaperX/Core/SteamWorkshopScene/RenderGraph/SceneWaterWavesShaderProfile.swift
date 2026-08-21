import CryptoKit
import Foundation

/// 官方 `effects/waterwaves` 的逐语义指纹 shader profile。
///
/// 已验证的 authored variants 携带 6 种 waterwaves shader 语义，其中 5 种可执行：
/// - `stock2842`：2.8.42 原版（exponent/DUALWAVES/PERSPECTIVE/TIMEOFFSET combo 全量）；
/// - `reversedDirectionV1`：v1 结构，方向基向量 `(0,-1)`（stock 为
///   `(0,1)`，同一 authored direction 波向相反，执行时按 +π 归一）、无 `g_Exponent`
///   （等价 exponent=1）、标量 `g_Perspective` 修正项、mask 无条件采样（default `util/white`）；
/// - `directV1`：同 v1 数学但基向量已是 `(0,1)`，两个 fragment 指纹（无 MASK combo
///   的无条件采样版与 `#if MASK` 包裹版，语料 combos 均为空，执行等价）；
/// - `reducedV2`：stock 减 DUALWAVES 段、保留标量 `g_Perspective`，combos 全空时与
///   stock exponent=1 同语义。
/// 第六种 label-as-key variant 使用编辑器 label 作常量键，
/// 无可执行实例，不纳入白名单。语义指纹只归一换行和 shader 注解 JSON 的字段顺序；
/// shader 代码、声明、注解值及其他注释仍逐字节参与哈希。这样作者把同一 effect 搬入
/// 新资源命名空间或 JSON writer 改变字段顺序时可复用，而代码变化仍失败关闭。语料全部
/// `perspective` 常量为 0，planner 只接受 0，因此执行端无需 perspective 修正项。
nonisolated enum SceneWaterWavesShaderProfile: Equatable {
    case stock2842
    case reversedDirectionV1
    case directV1
    case reducedV2

    private struct CanonicalShaderPayload: Encodable {
        let identity: String
        let sourceKind: SceneShaderContract.SourceKind
        let stages: [SceneShaderContract.Stage]
        let diagnostics: [SceneShaderContract.Diagnostic]
    }

    private struct Fingerprint {
        let profile: SceneWaterWavesShaderProfile
        let semanticVertexSHA256: String
        let semanticFragmentSHA256: String
    }

    /// v1 基向量 `(0,-1)` 等价于 stock 基向量下 direction + π。
    var directionOffset: Float {
        self == .reversedDirectionV1 ? .pi : 0
    }

    /// stock 常量必须五键全齐（exact 语料形态）；v1 语料按编辑器旧行为省略未改动键。
    var allowsOmittedConstants: Bool {
        self != .stock2842
    }

    /// v1 shader 无 `g_Exponent`，执行按 1（`pow(|sin|,1)*sign == sin`）。
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
        self != .reversedDirectionV1 && self != .directV1
    }

    /// The stock, reversed-direction v1 and both direct-v1 source profiles are
    /// now owned by MaterialProgram/GraphExecutor. The dedicated renderer
    /// remains only for reduced-v2, whose current authored instances still
    /// include user/SceneScript value producers outside this owner cohort.
    var retainsDedicatedFallback: Bool {
        self == .reducedV2
    }

    static func resolve(_ contracts: [SceneShaderContract]) -> SceneWaterWavesShaderProfile? {
        resolve(
            contracts,
            shaderIdentity: stockShaderIdentity,
            vertexPath: stockVertexPath,
            fragmentPath: stockFragmentPath
        )
    }

    static func resolve(
        _ contracts: [SceneShaderContract],
        shaderIdentity: String,
        vertexPath: String,
        fragmentPath: String
    ) -> SceneWaterWavesShaderProfile? {
        let expectedIdentity = normalized(shaderIdentity)
        let matches = contracts.filter { normalized($0.identity) == expectedIdentity }
        guard matches.count == 1, let contract = matches.first,
              contract.sourceKind == .authoredSource,
              contract.diagnostics.isEmpty,
              contract.stages.count == 2,
              canonicalHash(contract) == contract.canonicalSHA256,
              let vertex = contract.stages.first(where: { $0.kind == .vertex }),
              let fragment = contract.stages.first(where: { $0.kind == .fragment }),
              normalized(vertex.relativePath) == normalized(vertexPath),
              normalized(fragment.relativePath) == normalized(fragmentPath),
              vertex.rawSHA256 == sha256(Data(vertex.source.utf8)),
              fragment.rawSHA256 == sha256(Data(fragment.source.utf8)),
              let fingerprint = fingerprints.first(where: {
                  semanticSourceSHA256(vertex.source) == $0.semanticVertexSHA256
                      && semanticSourceSHA256(fragment.source)
                          == $0.semanticFragmentSHA256
              })
        else {
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

    private static func semanticSourceSHA256(_ source: String) -> String {
        let normalizedNewlines = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let canonical = normalizedNewlines
            .components(separatedBy: "\n")
            .map(canonicalizingAnnotationJSON)
            .joined(separator: "\n")
        return sha256(Data(canonical.utf8))
    }

    private static func canonicalizingAnnotationJSON(_ line: String) -> String {
        guard let comment = line.range(of: "//"),
              let brace = line[comment.upperBound...].firstIndex(of: "{") else {
            return line
        }
        let candidate = line[brace...].trimmingCharacters(in: .whitespaces)
        guard let data = candidate.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let canonicalData = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.sortedKeys, .withoutEscapingSlashes]
              ),
              let canonical = String(data: canonicalData, encoding: .utf8) else {
            return line
        }
        return String(line[..<brace]) + canonical
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static let stockShaderIdentity = "effects/waterwaves"
    private static let stockVertexPath = "shaders/effects/waterwaves.vert"
    private static let stockFragmentPath = "shaders/effects/waterwaves.frag"

    private static let directionalV1VertexSemanticSHA256 =
        "26a9575aa3571c0bc0ac37d201a557c7cdb29ed5d89cc5c533b5515e5a5fb1c1"
    private static let directionalV1FragmentSemanticSHA256 =
        "49e425b8757696807e9eb887e6afeee5f0eecdec94082709443dcf9034d4d47b"

    private static let fingerprints = [
        Fingerprint(
            profile: .stock2842,
            semanticVertexSHA256:
                "b452cc7e255eb3259a6c479c4c30729190774f1cfa3d0609eeb4268ed48f13f8",
            semanticFragmentSHA256:
                "abab624859fcb41a87e46cd5b20b2d12982133407939b555f4f87204f6d63d04"
        ),
        Fingerprint(
            profile: .reversedDirectionV1,
            semanticVertexSHA256:
                "fa1df7ac0f197e8f7dc9cb2337b0b4fbd8fcbe7ccfb63e44c7445f6acd5f367b",
            semanticFragmentSHA256: directionalV1FragmentSemanticSHA256
        ),
        Fingerprint(
            profile: .directV1,
            semanticVertexSHA256: directionalV1VertexSemanticSHA256,
            semanticFragmentSHA256: directionalV1FragmentSemanticSHA256
        ),
        Fingerprint(
            profile: .directV1,
            semanticVertexSHA256: directionalV1VertexSemanticSHA256,
            semanticFragmentSHA256:
                "ea5bd087ca039e7f80ef86ab4b9891fc6aba87959b7a083d24d6f98c3dc525cf"
        ),
        Fingerprint(
            profile: .reducedV2,
            semanticVertexSHA256:
                "0f344bd3efa959f9f404d961cb1e26b18765ef0954dd5a8ee374c46967720894",
            semanticFragmentSHA256:
                "b15e105051e8df3b6d7520b7860532d66f221556fd1b90f781ef3f58b50b7bb3"
        ),
    ]
}
