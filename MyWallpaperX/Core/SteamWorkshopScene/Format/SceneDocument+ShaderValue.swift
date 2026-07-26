import Foundation

extension SceneDocument {
    struct ShaderValue: Codable {
        let rawValue: String
        let valueKind: String
        let userBinding: String?
        let components: [Double]?
        /// 作者挂在该 constant 上的 Timeline。`valueKind == "binding"` 且
        /// `userBinding == nil` 的形态既可能是 `animation` 也可能是 `script`，
        /// 这里只在真的解析出 animation 时非空。
        let timeline: SceneTimelineAnimation?
        /// Timeline fail-closed 的原因。非空即表示作者声明了 animation 但被拒绝，
        /// 不能当作「作者没写」静默丢弃。
        let timelineDiagnostics: [String]

        /// 两个 Timeline 字段有默认值：官方 Timeline 挂在 scene object 的属性上，
        /// material pass 的 constant 不是它的宿主，那条通路（`SceneAssetCatalog`）
        /// 按现状继续不解析 animation。
        nonisolated init(
            rawValue: String,
            valueKind: String,
            userBinding: String?,
            components: [Double]?,
            timeline: SceneTimelineAnimation? = nil,
            timelineDiagnostics: [String] = []
        ) {
            self.rawValue = rawValue
            self.valueKind = valueKind
            self.userBinding = userBinding
            self.components = components
            self.timeline = timeline
            self.timelineDiagnostics = timelineDiagnostics
        }
    }
}
