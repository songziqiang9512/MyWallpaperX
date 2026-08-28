import Foundation

/// 按**绝对 scene time** 求值作者 Timeline。
///
/// 官方要求动画按绝对时间定位，而不是每帧在上一次结果上累加推进，否则掉帧会让动画整体
/// 变慢、多 surface 之间还会漂移。这里只做纯函数映射：给定同一个 `sceneTime` 必然得到
/// 同一个结果，不持有任何播放状态。
///
/// 每段按作者 front/back handle 构造 cubic Bézier。X 是 segment-span 比例，Y 是 value
/// offset；按 frame progress 反求唯一 curve parameter 后再求 value。禁用或缺失的 handle
/// 退化到对应 keyframe anchor；两侧都关闭时几何曲线严格为直线。
///
/// `isRelative` 不在这里处理：它是「动画值怎样与作者基值合成」的写回语义。
/// `wrapsLoop` 则属于时间曲线本身：末关键帧到下一周期首关键帧使用同一个 Bézier 段
/// 求值，其中末帧 `front` 与首帧 `back` 是该段的两个 control handles。
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
        return framePosition(
            of: animation,
            elapsedFrames: max(0, sceneTime) * options.fps
        )
    }

    /// 把已由播放状态机累计的本地帧映射到作者 mode。播放、暂停和 stop 只改变
    /// `elapsedFrames`；关键帧插值仍由同一纯函数执行。
    nonisolated static func framePosition(
        of animation: SceneTimelineAnimation,
        elapsedFrames: Double
    ) -> Double {
        let options = animation.options
        guard elapsedFrames.isFinite, options.length > 0 else { return 0 }
        let elapsed = max(0, elapsedFrames)
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
            atFrame: framePosition(of: animation, sceneTime: sceneTime),
            wrappingLength: wrappingLength(of: animation)
        )
    }

    /// 求全部 component，顺序与 `lanes` 一致。
    nonisolated static func values(
        of animation: SceneTimelineAnimation,
        sceneTime: Double
    ) -> [Double] {
        let frame = framePosition(of: animation, sceneTime: sceneTime)
        let wrappingLength = wrappingLength(of: animation)
        return animation.lanes.map {
            value(in: $0, atFrame: frame, wrappingLength: wrappingLength)
        }
    }

    /// 用显式本地播放帧求全部 component，供唯一 Timeline playback state 消费。
    nonisolated static func values(
        of animation: SceneTimelineAnimation,
        elapsedFrames: Double
    ) -> [Double] {
        let frame = framePosition(of: animation, elapsedFrames: elapsedFrames)
        let wrappingLength = wrappingLength(of: animation)
        return animation.lanes.map {
            value(in: $0, atFrame: frame, wrappingLength: wrappingLength)
        }
    }

    /// 关键帧区间定位 + 作者 Bézier 插值。
    ///
    /// 关键帧的帧范围不一定覆盖 `[0, length]`，落在首帧之前或末帧之后时保持端点值，
    /// 不外推。
    private nonisolated static func value(
        in lane: [SceneTimelineKeyframe],
        atFrame frame: Double,
        wrappingLength: Double?
    ) -> Double {
        guard let first = lane.first, let last = lane.last else { return 0 }
        if frame < first.frame {
            guard let wrappingLength else { return first.value }
            let virtualStart = last.frame - wrappingLength
            let span = first.frame - virtualStart
            guard span > 0 else { return first.value }
            return interpolatedValue(
                from: last, to: first,
                progress: (frame - virtualStart) / span
            )
        }
        if frame == first.frame { return first.value }
        if frame > last.frame {
            guard let wrappingLength else { return last.value }
            let virtualEnd = first.frame + wrappingLength
            let span = virtualEnd - last.frame
            guard span > 0 else { return last.value }
            return interpolatedValue(
                from: last, to: first,
                progress: (frame - last.frame) / span
            )
        }
        if frame == last.frame { return last.value }
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
        return interpolatedValue(from: start, to: end, progress: progress)
    }

    private nonisolated static func wrappingLength(
        of animation: SceneTimelineAnimation
    ) -> Double? {
        guard animation.options.wrapsLoop,
              animation.hasExecutableWrapLoop else { return nil }
        return animation.options.length
    }

    private nonisolated static func interpolatedValue(
        from start: SceneTimelineKeyframe,
        to end: SceneTimelineKeyframe,
        progress: Double
    ) -> Double {
        let front = start.front.flatMap { $0.isEnabled ? $0 : nil }
        let back = end.back.flatMap { $0.isEnabled ? $0 : nil }
        guard front != nil || back != nil else {
            return start.value + (end.value - start.value) * progress
        }
        let x1 = front?.x ?? 0
        let x2 = 1 + (back?.x ?? 0)
        let y1 = start.value + (front?.y ?? 0)
        let y2 = end.value + (back?.y ?? 0)

        // Parser 把 enabled X 限在当前 segment 内，因此 x(t) 单调且可二分。固定轮数让
        // realtime/offline 与不同 surface 对同一 frame 得到完全相同的求值路径。
        var lower = 0.0
        var upper = 1.0
        for _ in 0 ..< 48 {
            let parameter = (lower + upper) * 0.5
            let curveProgress = cubic(0, x1, x2, 1, at: parameter)
            if curveProgress == progress {
                return cubic(start.value, y1, y2, end.value, at: parameter)
            } else if curveProgress < progress {
                lower = parameter
            } else {
                upper = parameter
            }
        }
        return cubic(
            start.value, y1, y2, end.value,
            at: (lower + upper) * 0.5
        )
    }

    private nonisolated static func cubic(
        _ p0: Double,
        _ p1: Double,
        _ p2: Double,
        _ p3: Double,
        at t: Double
    ) -> Double {
        let oneMinusT = 1 - t
        return oneMinusT * oneMinusT * oneMinusT * p0
            + 3 * oneMinusT * oneMinusT * t * p1
            + 3 * oneMinusT * t * t * p2
            + t * t * t * p3
    }
}
