import Foundation

extension SceneDocumentLoader {
    /// 逐个扫描 layer 级宿主属性上的 `animation`。宿主名同时是 target 身份的一部分，
    /// 所以按 `Host.allCases` 的固定顺序遍历，保证同一份 scene.json 每次得到同一顺序。
    nonisolated static func objectTimelines(
        _ root: [String: Any]
    ) -> (animations: [SceneDocument.SceneObjectTimeline], diagnostics: [String]) {
        var animations: [SceneDocument.SceneObjectTimeline] = []
        var diagnostics: [String] = []
        for host in SceneDocument.SceneObjectTimeline.Host.allCases {
            let result = SceneTimelineAnimationParser.parse(host: root[host.rawValue])
            if let animation = result.animation {
                animations.append(.init(host: host, animation: animation))
            }
            diagnostics.append(contentsOf: result.diagnostics.map { "\(host.rawValue):\($0.token)" })
        }
        return (animations, diagnostics)
    }
}
