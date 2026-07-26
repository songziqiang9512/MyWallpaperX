import Foundation

/// 按**绝对 scene time** 求值作者 Timeline。
///
/// 官方要求动画按绝对时间定位，而不是每帧在上一次结果上累加推进，否则掉帧会让动画整体
/// 变慢、多 surface 之间还会漂移。这里只做纯函数映射：给定同一个 `sceneTime` 必然得到
/// 同一个结果，不持有任何播放状态。
///
/// 本版**不消费 tangent**。`SceneTimelineTangent` 的 `x`/`y` 单位尚无官方定义，且
/// 「帧偏移」与「归一化段长比例」两种解释给出的曲线明显不同（见 `SceneTimelineTangent`
/// 的说明），在取得视觉定标前一律走线性插值，不冒充 Bézier parity。
///
/// `isRelative` 与 `wrapsLoop` 同样不在这里处理：前者是「动画值怎样与作者基值合成」的
/// 写回语义，后者是首尾平滑整形，都属于消费方而不是求值器。
nonisolated enum SceneTimelineEvaluator {
    /// 把绝对 scene time 映射到动画本地帧位置（单位是帧，不是秒）。
    ///
    /// `startsPaused` 的动画停在首帧：没有 SceneScript VM 时不存在能调用 `play()` 的
    /// 主体，自动播放会偏离作者意图，停住才是 fail-safe 的那一侧。
    nonisolated static func framePosition(
        of animation: SceneTimelineAnimation,
        sceneTime: Double
    ) -> Double {
        let options = animation.options
        guard !options.startsPaused else { return 0 }
        guard sceneTime.isFinite, options.fps > 0, options.length > 0 else { return 0 }
        let elapsed = max(0, sceneTime) * options.fps
        switch options.mode {
        case .single:
            return min(elapsed, options.length)
        case .loop:
            return elapsed.truncatingRemainder(dividingBy: options.length)
        case .mirror:
            // 三角波：到末帧后按同速反向。端点不重复采样，官方未定义该边界，
            // 见开发计划 §1.4-6。
            let period = options.length * 2
            let phase = elapsed.truncatingRemainder(dividingBy: period)
            return phase <= options.length ? phase : period - phase
        }
    }

    /// 求单个 component 在给定 scene time 的动画值。component 越界返回 `nil`。
    nonisolated static func value(
        of animation: SceneTimelineAnimation,
        component: Int,
        sceneTime: Double
    ) -> Double? {
        guard animation.lanes.indices.contains(component) else { return nil }
        return value(
            in: animation.lanes[component],
            atFrame: framePosition(of: animation, sceneTime: sceneTime)
        )
    }

    /// 求全部 component，顺序与 `lanes` 一致。
    nonisolated static func values(
        of animation: SceneTimelineAnimation,
        sceneTime: Double
    ) -> [Double] {
        let frame = framePosition(of: animation, sceneTime: sceneTime)
        return animation.lanes.map { value(in: $0, atFrame: frame) }
    }

    /// 关键帧区间定位 + 线性插值。
    ///
    /// 关键帧的帧范围不一定覆盖 `[0, length]`，落在首帧之前或末帧之后时保持端点值，
    /// 不外推。
    private nonisolated static func value(
        in lane: [SceneTimelineKeyframe],
        atFrame frame: Double
    ) -> Double {
        guard let first = lane.first, let last = lane.last else { return 0 }
        if frame <= first.frame { return first.value }
        if frame >= last.frame { return last.value }
        guard let upperIndex = lane.firstIndex(where: { $0.frame > frame }),
              upperIndex > 0
        else {
            return last.value
        }
        let start = lane[upperIndex - 1]
        let end = lane[upperIndex]
        let span = end.frame - start.frame
        // IR 已保证帧号严格递增，这里只兜底除零。
        guard span > 0 else { return end.value }
        let progress = (frame - start.frame) / span
        return start.value + (end.value - start.value) * progress
    }
}
