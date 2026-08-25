import Foundation

/// Preserves the authored JSON kind of a shader wrapper's `user` member.
/// It is encoded as a string so `.null` remains distinguishable from an
/// absent field across runtime-input serialization.
nonisolated enum SceneShaderUserValueKind: String, Codable, Sendable {
    case null
    case boolean
    case number
    case string
    case array
    case object

    nonisolated init?(jsonObject value: Any) {
        guard let parsed = SceneJSONValue(jsonObject: value) else { return nil }
        self = switch parsed {
        case .null: .null
        case .bool: .boolean
        case .number: .number
        case .string: .string
        case .array: .array
        case .object: .object
        }
    }
}

extension SceneDocument {
    struct ShaderValue: Codable {
        let rawValue: String
        let valueKind: String
        let userBinding: String?
        /// `nil` means the authored wrapper omitted `user` (or predates this
        /// provenance field); `.null` is an explicit JSON null.
        let userValueKind: SceneShaderUserValueKind?
        let components: [Double]?
        /// 作者挂在该 constant 上的 Timeline。`valueKind == "binding"` 且
        /// `userBinding == nil` 的形态既可能是 `animation` 也可能是 `script`，
        /// 这里只在真的解析出 animation 时非空。
        let timeline: SceneTimelineAnimation?
        /// Timeline fail-closed 的原因。非空即表示作者声明了 animation 但被拒绝，
        /// 不能当作「作者没写」静默丢弃。
        let timelineDiagnostics: [String]
        /// Property-bound SceneScript source. Execution remains gated by a bounded compiler.
        let scriptSource: String?
        /// Full wrapper shape used to reject omitted or additional binding fields.
        let bindingKeys: [String]

        /// 两个 Timeline 字段有默认值：官方 Timeline 挂在 scene object 的属性上，
        /// material pass 的 constant 不是它的宿主，那条通路（`SceneAssetCatalog`）
        /// 按现状继续不解析 animation。
        nonisolated init(
            rawValue: String,
            valueKind: String,
            userBinding: String?,
            userValueKind: SceneShaderUserValueKind? = nil,
            components: [Double]?,
            timeline: SceneTimelineAnimation? = nil,
            timelineDiagnostics: [String] = [],
            scriptSource: String? = nil,
            bindingKeys: [String] = []
        ) {
            self.rawValue = rawValue
            self.valueKind = valueKind
            self.userBinding = userBinding
            self.userValueKind = userValueKind ?? userBinding.map { _ in .string }
            self.components = components
            self.timeline = timeline
            self.timelineDiagnostics = timelineDiagnostics
            self.scriptSource = scriptSource
            self.bindingKeys = bindingKeys
        }
    }
}
