import Foundation

extension ScenePuppetAnimationEvaluator {
    /// Converts scene time into an interval between authored poses. Keeping
    /// the interpolation fraction here gives all playback callers one shared
    /// rule for single, loop, and mirror clips.
    static func frameSample(
        sceneTime: Double,
        rate: Double,
        animation: SceneMdlPuppetAnimation
    ) -> FrameSample {
        guard sceneTime.isFinite, rate.isFinite, rate > 0,
              animation.framesPerSecond.isFinite,
              animation.framesPerSecond > 0,
              animation.frameCount > 0 else {
            return FrameSample(frameA: 0, frameB: 0)
        }
        let count = animation.frameCount
        let phase = max(0, sceneTime) * rate * Double(animation.framesPerSecond)
        guard phase.isFinite else {
            return FrameSample(frameA: 0, frameB: 0)
        }

        func linearSample(_ q: Double) -> FrameSample {
            let bounded = min(Double(count), max(0, q))
            if bounded >= Double(count) {
                return FrameSample(frameA: count - 1, frameB: count, fraction: 1)
            }
            let a = min(count - 1, max(0, Int(bounded.rounded(.down))))
            let fraction = Float(min(1, max(0, bounded - Double(a))))
            return FrameSample(frameA: a, frameB: a + 1, fraction: fraction)
        }

        func positiveRemainder(_ value: Double, _ period: Double) -> Double {
            let remainder = value.truncatingRemainder(dividingBy: period)
            return remainder >= 0 ? remainder : remainder + period
        }

        switch animation.mode {
        case "single":
            return linearSample(phase)
        case "mirror":
            let period = Double(count) * 2
            let q = positiveRemainder(phase, period)
            let aRaw = min(count * 2 - 1, max(0, Int(q.rounded(.down))))
            let fraction = Float(min(1, max(0, q - Double(aRaw))))
            func mirrorIndex(_ index: Int) -> Int {
                index <= count ? index : count * 2 - index
            }
            return FrameSample(
                frameA: mirrorIndex(aRaw),
                frameB: mirrorIndex(aRaw + 1),
                fraction: fraction
            )
        default:
            let q = positiveRemainder(phase, Double(count))
            return linearSample(q)
        }
    }

    static func frameIndex(
        sceneTime: Double,
        rate: Double,
        animation: SceneMdlPuppetAnimation
    ) -> Int {
        frameSample(sceneTime: sceneTime, rate: rate, animation: animation).frameA
    }
}
