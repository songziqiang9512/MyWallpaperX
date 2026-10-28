import Foundation

nonisolated enum SceneTimelinePlaybackCommand: Equatable, Sendable {
    case play
    case pause
    case stop
    case setFrame(Double)
}

nonisolated struct SceneTimelinePlaybackMutation: Equatable, Sendable {
    let target: SceneDynamicTarget
    let command: SceneTimelinePlaybackCommand
    let callbackEpoch: UInt64
    let ordinal: UInt32

    init(target: SceneDynamicTarget, command: SceneTimelinePlaybackCommand,
         callbackEpoch: UInt64 = 0, ordinal: UInt32 = 0) {
        self.target = target
        self.command = command
        self.callbackEpoch = callbackEpoch
        self.ordinal = ordinal
    }
}

nonisolated enum SceneTimelinePlaybackFailure: Error, Equatable, Sendable {
    case invalidSceneTime
    case unknownTarget(SceneDynamicTarget)
    case invalidFrame(SceneDynamicTarget)
}

/// 唯一的 Timeline 播放状态。每个已编译 playback owner 只保一份本地播放位置，并消费
/// 现有 SceneClock 的绝对时间；不创建第二套 clock、property registry 或 animation IR。
nonisolated final class SceneTimelinePlaybackRuntime: @unchecked Sendable {
    private enum State: Equatable {
        case playing(anchorSceneTime: Double, anchorElapsedFrames: Double)
        case paused(elapsedFrames: Double)
    }

    /// Keep binding/handle ordinals independent of shared playback state.
    private let orderedBindings: [SceneTimelineBinding]
    /// Prepared once: commands resolve any member to one state, while normal
    /// projection follows integer member indices without finding groups again.
    private let stateIndices: [SceneDynamicTarget: Int]
    private let stateMembers: [[Int]]
    private let ownerAnimations: [SceneTimelineAnimation]
    private var orderedStates: [State]
    private var pendingNextFrameObservations: Set<SceneDynamicTarget> = []

    /// Observation rollback is explicit and separate from accepted playback
    /// state. A caller may snapshot/restore these diagnostics; the current host
    /// does not wire that optional protocol to surface submission.
    nonisolated struct ObservationState: Equatable, Sendable {
        fileprivate let pendingNextFrameObservations: Set<SceneDynamicTarget>

        fileprivate init(pendingNextFrameObservations: Set<SceneDynamicTarget>) {
            self.pendingNextFrameObservations = pendingNextFrameObservations
        }
    }

    init(program: SceneTimelineProgram) {
        let bindings = Dictionary(
            uniqueKeysWithValues: program.bindings.map { ($0.target, $0) }
        )
        orderedBindings = program.bindings
        var indices: [SceneDynamicTarget: Int] = [:]
        var ownerIndices: [SceneDynamicTarget: Int] = [:]
        var members: [[Int]] = []
        var animations: [SceneTimelineAnimation] = []
        var states: [State] = []
        for (bindingIndex, binding) in program.bindings.enumerated() {
            let ownerTarget = binding.playbackOwnerTarget
            // Resolve the compiler's prepared owner without inventing a fallback.
            guard let owner = bindings[ownerTarget] else { continue }
            let stateIndex: Int
            if let existing = ownerIndices[ownerTarget] {
                stateIndex = existing
            } else {
                stateIndex = states.count
                ownerIndices[ownerTarget] = stateIndex
                members.append([])
                animations.append(owner.animation)
                states.append(owner.animation.options.startsPaused
                    ? .paused(elapsedFrames: 0)
                    : .playing(anchorSceneTime: 0, anchorElapsedFrames: 0))
            }
            indices[binding.target] = stateIndex
            members[stateIndex].append(bindingIndex)
        }
        stateIndices = indices
        stateMembers = members
        ownerAnimations = animations
        orderedStates = states
    }

    nonisolated func observationSnapshot() -> ObservationState {
        ObservationState(
            pendingNextFrameObservations: pendingNextFrameObservations
        )
    }

    nonisolated func restoreObservationState(_ state: ObservationState) {
        pendingNextFrameObservations = state.pendingNextFrameObservations
    }

    func values(sceneTime: Double) -> [SceneDynamicTarget: SceneDynamicValue] {
        guard sceneTime.isFinite, sceneTime >= 0 else { return [:] }
        var values: [SceneDynamicTarget: SceneDynamicValue] = [:]
        values.reserveCapacity(orderedBindings.count)
        for index in orderedStates.indices {
            project(stateIndex: index, state: orderedStates[index], sceneTime: sceneTime,
                into: &values, observe: true)
        }
        return values
    }

    /// 一帧产生的命令先在副本上完整校验，全部合法才提交，避免同帧局部 mutation。
    func validate(
        _ mutations: [SceneTimelinePlaybackMutation],
        sceneTime: Double
    ) -> Result<Void, SceneTimelinePlaybackFailure> {
        switch candidateStates(for: mutations, sceneTime: sceneTime) {
        case .success: .success(())
        case let .failure(failure): .failure(failure)
        }
    }

    /// Projects this frame's admitted commands without consuming playback or
    /// observation state. All members of a changed owner are evaluated; the ordinary
    /// frame's complete Timeline projection remains the caller's base.
    func preview(
        _ mutations: [SceneTimelinePlaybackMutation],
        sceneTime: Double
    ) -> Result<[SceneDynamicTarget: SceneDynamicValue], SceneTimelinePlaybackFailure> {
        guard !mutations.isEmpty else { return .success([:]) }
        let candidate: [State]
        switch candidateStates(for: mutations, sceneTime: sceneTime) {
        case let .success(states): candidate = states
        case let .failure(failure): return .failure(failure)
        }
        var values: [SceneDynamicTarget: SceneDynamicValue] = [:]
        var projected: Set<Int> = []
        for mutation in mutations {
            guard let index = stateIndices[mutation.target] else {
                return .failure(.unknownTarget(mutation.target))
            }
            guard projected.insert(index).inserted else { continue }
            project(stateIndex: index, state: candidate[index], sceneTime: sceneTime,
                into: &values, observe: false)
        }
        return .success(values)
    }

    func apply(
        _ mutations: [SceneTimelinePlaybackMutation],
        sceneTime: Double
    ) -> Result<Void, SceneTimelinePlaybackFailure> {
        switch candidateStates(for: mutations, sceneTime: sceneTime) {
        case let .success(candidate):
            orderedStates = candidate
            for mutation in mutations {
                if let index = stateIndices[mutation.target] {
                    pendingNextFrameObservations.formUnion(
                        stateMembers[index].map { orderedBindings[$0].target }
                    )
                }
            }
            return .success(())
        case let .failure(failure):
            return .failure(failure)
        }
    }

    private func candidateStates(
        for mutations: [SceneTimelinePlaybackMutation],
        sceneTime: Double
    ) -> Result<[State], SceneTimelinePlaybackFailure> {
        guard sceneTime.isFinite, sceneTime >= 0 else {
            return .failure(.invalidSceneTime)
        }
        var candidate = orderedStates
        for mutation in mutations {
            guard let stateIndex = stateIndices[mutation.target] else {
                return .failure(.unknownTarget(mutation.target))
            }
            let animation = ownerAnimations[stateIndex]
            let state = candidate[stateIndex]
            let elapsed = elapsedFrames(
                state: state,
                animation: animation,
                sceneTime: sceneTime
            )
            switch mutation.command {
            case .play:
                // A completed single animation starts a new run. Playing or
                // paused positions before its end still resume in place.
                let completed = animation.options.mode == .single
                    && elapsed >= animation.options.length
                candidate[stateIndex] = .playing(
                    anchorSceneTime: sceneTime,
                    anchorElapsedFrames: completed ? 0 : elapsed
                )
            case .pause:
                candidate[stateIndex] = .paused(elapsedFrames: elapsed)
            case .stop:
                candidate[stateIndex] = .paused(elapsedFrames: 0)
            case let .setFrame(frame):
                guard frame.isFinite else { return .failure(.invalidFrame(mutation.target)) }
                switch state {
                case .playing:
                    candidate[stateIndex] = .playing(
                        anchorSceneTime: sceneTime, anchorElapsedFrames: frame)
                case .paused:
                    candidate[stateIndex] = .paused(elapsedFrames: frame)
                }
            }
        }
        return .success(candidate)
    }

    private func project(
        stateIndex: Int,
        state: State,
        sceneTime: Double,
        into values: inout [SceneDynamicTarget: SceneDynamicValue],
        observe: Bool
    ) {
        let elapsed = elapsedFrames(state: state, animation: ownerAnimations[stateIndex],
            sceneTime: sceneTime)
        let members = stateMembers[stateIndex]
        for index in members {
            let binding = orderedBindings[index]
            guard let value = SceneTimelineRuntime.value(of: binding, elapsedFrames: elapsed) else {
                // A bad lane may not leave a partially published group behind.
                for member in members { values.removeValue(forKey: orderedBindings[member].target) }
                return
            }
            values[binding.target] = value
        }
        guard observe, !pendingNextFrameObservations.isEmpty else { return }
        for index in members {
            let target = orderedBindings[index].target
            guard pendingNextFrameObservations.remove(target) != nil,
                  let value = values[target] else { continue }
#if DEBUG
            NSLog(
                "MWX SceneScript VM: animationTarget=%@ state=next-frame elapsedFrames=%.9g value=%@ route=generic-only",
                String(describing: target), elapsed, String(describing: value)
            )
#endif
        }
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
