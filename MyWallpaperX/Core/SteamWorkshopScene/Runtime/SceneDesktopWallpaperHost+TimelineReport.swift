import Foundation

extension SceneDesktopWallpaperHost {
    /// 把 Timeline 的编译结果追加到 preview 日志。
    ///
    /// 画面 motion 无法把 Timeline 与粒子/effect 的既有动画区分开，所以这里输出确定性的
    /// 求值样本：同一份 scene.json 每次得到同样的几行，benchmark 可以直接断言，不依赖像素。
    nonisolated static func timelineReportLines(
        program: SceneTimelineProgram
    ) -> [String] {
        var lines = [
            "timelineBindingCount: \(program.bindings.count)",
            "timelineDiagnosticCount: \(program.diagnostics.count)",
        ]
        for binding in program.bindings.sorted(by: {
            describe($0.target) < describe($1.target)
        }) {
            let options = binding.animation.options
            // 首帧与半程各取一次：单调动画在这两点必然不同值，是「Timeline 真的会随时间
            // 变化」的最小证据；startPaused 的则两点同值。
            let half = options.durationSeconds / 2
            lines.append(String(
                format: "timeline %@: mode=%@ duration=%.3fs startPaused=%@ lanes=%d"
                    + " value@0=%@ value@half=%@",
                describe(binding.target),
                options.mode.rawValue,
                options.durationSeconds,
                options.startsPaused ? "true" : "false",
                binding.animation.componentCount,
                format(binding, sceneTime: 0),
                format(binding, sceneTime: half)
            ))
        }
        for diagnostic in program.diagnostics {
            lines.append("timeline diagnostic: \(diagnostic)")
        }
        return lines
    }

    /// Timeline 报告要接在 metalView 写完 preview 日志之后：那边是覆盖写。
    nonisolated static func appendTimelineReport(
        to logURL: URL?,
        program: SceneTimelineProgram
    ) {
        guard let logURL,
              let existing = try? String(contentsOf: logURL, encoding: .utf8) else { return }
        // metalView 的报告末尾没有换行，直接拼接会把最后一行（`loaded: N / M`）粘住，
        // 让按行匹配的 benchmark 解析不到它。
        let separator = existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n"
        let lines = timelineReportLines(program: program)
        try? (existing + separator + lines.joined(separator: "\n") + "\n")
            .write(to: logURL, atomically: true, encoding: .utf8)
    }

    private nonisolated static func format(
        _ binding: SceneTimelineBinding,
        sceneTime: Double
    ) -> String {
        SceneTimelineEvaluator.values(of: binding.animation, sceneTime: sceneTime)
            .map { String(format: "%.5f", $0) }
            .joined(separator: ",")
    }

    private nonisolated static func describe(_ target: SceneDynamicTarget) -> String {
        switch target {
        case let .layer(layerID, field):
            "layer \(layerID) \(field.rawValue)"
        case let .effectConstant(layerID, effectIndex, passIndex, name):
            "layer \(layerID) effect \(effectIndex) pass \(passIndex) \(name)"
        default:
            "other"
        }
    }
}
