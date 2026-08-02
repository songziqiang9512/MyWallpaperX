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

    /// 保真 particle instance Timeline。absolute/relative、lane 数和 Combined Animation
    /// 的执行准入留给 target compiler。
    nonisolated static func particleTimelines(
        _ rawValue: Any?
    ) -> (animations: [SceneDocument.SceneParticleTimeline], diagnostics: [String]) {
        guard let root = rawValue as? [String: Any] else {
            return ([], [])
        }
        var animations: [SceneDocument.SceneParticleTimeline] = []
        var diagnostics: [String] = []
        let scalarHosts: [(String, SceneDocument.SceneParticleTimeline.Field)] = [
            ("alpha", .alpha), ("size", .size), ("lifetime", .lifetime),
            ("rate", .rate), ("speed", .speed), ("count", .count),
            ("brightness", .brightness),
        ]
        for (host, field) in scalarHosts {
            let result = SceneTimelineAnimationParser.parse(host: root[host])
            if let animation = result.animation {
                animations.append(.init(index: nil, field: field, animation: animation))
            }
            diagnostics.append(contentsOf: result.diagnostics.map {
                "instanceoverride.\(host):\($0.token)"
            })
        }
        for index in 0 ..< 8 {
            let hosts: [(String, SceneDocument.SceneParticleTimeline.Field)] = [
                ("controlpoint\(index)", .position),
                ("controlpointangle\(index)", .angles),
            ]
            for (host, field) in hosts {
                let result = SceneTimelineAnimationParser.parse(host: root[host])
                if let animation = result.animation {
                    animations.append(.init(index: index, field: field, animation: animation))
                }
                diagnostics.append(contentsOf: result.diagnostics.map {
                    "instanceoverride.\(host):\($0.token)"
                })
            }
        }
        return (animations, diagnostics)
    }
}
