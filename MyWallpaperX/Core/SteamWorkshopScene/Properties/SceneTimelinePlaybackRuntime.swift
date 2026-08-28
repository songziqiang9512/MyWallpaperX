import Foundation

nonisolated enum SceneTimelinePlaybackCommand: String, Equatable, Sendable {
    case play
    case pause
    case stop
}

nonisolated struct SceneTimelinePlaybackMutation: Equatable, Sendable {
    let target: SceneDynamicTarget
    let command: SceneTimelinePlaybackCommand
}

nonisolated enum SceneTimelinePlaybackFailure: Error, Equatable, Sendable {
    case invalidSceneTime
    case unknownTarget(SceneDynamicTarget)
}

/// 唯一的 Timeline 播放状态。它只保存每条已编译 Timeline 的本地播放位置，并消费
/// 现有 SceneClock 的绝对时间；不创建第二套 clock、property registry 或 animation IR。
nonisolated final class SceneTimelinePlaybackRuntime: @unchecked Sendable {
    private enum State: Equatable {
        case playing(anchorSceneTime: Double, anchorElapsedFrames: Double)
        case paused(elapsedFrames: Double)
    }

    private let bindings: [SceneDynamicTarget: SceneTimelineBinding]
    private var states: [SceneDynamicTarget: State]
    private var pendingNextFrameObservations: Set<SceneDynamicTarget> = []

    init(program: SceneTimelineProgram) {
        bindings = Dictionary(
            uniqueKeysWithValues: program.bindings.map { ($0.target, $0) }
        )
        states = Dictionary(uniqueKeysWithValues: program.bindings.map { binding in
            let state: State = binding.animation.options.startsPaused
                ? .paused(elapsedFrames: 0)
                : .playing(anchorSceneTime: 0, anchorElapsedFrames: 0)
            return (binding.target, state)
        })
    }

    func values(sceneTime: Double) -> [SceneDynamicTarget: SceneDynamicValue] {
        guard sceneTime.isFinite, sceneTime >= 0 else { return [:] }
        var values: [SceneDynamicTarget: SceneDynamicValue] = [:]
        for (target, binding) in bindings {
            guard let state = states[target],
                  let value = SceneTimelineRuntime.value(
                      of: binding,
                      elapsedFrames: elapsedFrames(
                          state: state,
                          animation: binding.animation,
                          sceneTime: sceneTime
                      )
                  ) else { continue }
            values[target] = value
            if pendingNextFrameObservations.remove(target) != nil {
                NSLog(
                    "MWX SceneScript VM: animationTarget=%@ state=next-frame elapsedFrames=%.9g value=%@ route=generic-only",
                    String(describing: target),
                    elapsedFrames(
                        state: state,
                        animation: binding.animation,
                        sceneTime: sceneTime
                    ),
                    String(describing: value)
                )
            }
        }
        return values
    }

    /// 一帧产生的命令先在副本上完整校验，全部合法才提交，避免同帧局部 mutation。
    func apply(
        _ mutations: [SceneTimelinePlaybackMutation],
        sceneTime: Double
    ) -> Result<Void, SceneTimelinePlaybackFailure> {
        guard sceneTime.isFinite, sceneTime >= 0 else {
            return .failure(.invalidSceneTime)
        }
        var candidate = states
        for mutation in mutations {
            guard let binding = bindings[mutation.target],
                  let state = candidate[mutation.target] else {
                return .failure(.unknownTarget(mutation.target))
            }
            let elapsed = elapsedFrames(
                state: state,
                animation: binding.animation,
                sceneTime: sceneTime
            )
            switch mutation.command {
            case .play:
                candidate[mutation.target] = .playing(
                    anchorSceneTime: sceneTime,
                    anchorElapsedFrames: elapsed
                )
            case .pause:
                candidate[mutation.target] = .paused(elapsedFrames: elapsed)
            case .stop:
                candidate[mutation.target] = .paused(elapsedFrames: 0)
            }
        }
        states = candidate
        pendingNextFrameObservations.formUnion(mutations.map(\.target))
        return .success(())
    }

    private func elapsedFrames(
        state: State,
        animation: SceneTimelineAnimation,
        sceneTime: Double
    ) -> Double {
        switch state {
        case let .playing(anchorSceneTime, anchorElapsedFrames):
            return anchorElapsedFrames
                + max(0, sceneTime - anchorSceneTime) * animation.options.fps
        case let .paused(elapsedFrames):
            return elapsedFrames
        }
    }
}
