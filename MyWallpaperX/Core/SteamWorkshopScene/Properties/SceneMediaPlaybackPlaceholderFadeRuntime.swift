import Foundation

/// Scene-scoped state advanced once per host frame and broadcast to every surface.
/// A supplied playback event is applied before that call's frame update.
nonisolated struct SceneMediaPlaybackPlaceholderFadeRuntime {
    private enum Mode: Equatable {
        case stopped
        case playing
        case paused
        case unknown

        init(rawValue: Int) {
            switch rawValue {
            case 0: self = .stopped
            case 1: self = .playing
            case 2: self = .paused
            default: self = .unknown
            }
        }
    }

    private struct State {
        var counter: Double
        var mode: Mode = .stopped
    }

    private let bindings: [SceneMediaPlaybackPlaceholderFadeBinding]
    private var states: [SceneDynamicTarget: State]

    nonisolated init(program: SceneMediaPlaybackPlaceholderFadeProgram) {
        bindings = program.bindings
        states = Dictionary(uniqueKeysWithValues: program.bindings.map {
            ($0.definition.target, State(counter: $0.plan.initialCounter))
        })
    }

    nonisolated mutating func values(
        playbackEventState: Int? = nil,
        frameTime: TimeInterval
    ) -> [SceneDynamicTarget: SceneDynamicValue] {
        if let playbackEventState {
            let mode = Mode(rawValue: playbackEventState)
            for target in states.keys {
                states[target]?.mode = mode
            }
        }
        guard frameTime.isFinite, frameTime >= 0 else {
            return currentValues()
        }
        var result: [SceneDynamicTarget: SceneDynamicValue] = [:]
        for binding in bindings {
            let target = binding.definition.target
            guard var state = states[target] else { continue }
            let plan = binding.plan
            let delta = plan.frameTimeScale * frameTime
            let candidate: Double
            switch (state.mode, plan.polarity) {
            case (.stopped, .stoppedRise),
                 (.playing, .activeRise),
                 (.paused, .activeRise):
                candidate = state.counter + delta
            case (.stopped, .activeRise),
                 (.playing, .stoppedRise),
                 (.paused, .stoppedRise):
                candidate = state.counter - delta
            case (.unknown, _):
                candidate = state.counter
            }
            guard candidate.isFinite else { continue }
            state.counter = candidate
            switch state.mode {
            case .stopped where state.counter < plan.stoppedLowerReset:
                state.counter = plan.stoppedLowerReset
            case .playing where state.counter > plan.activeUpperReset,
                 .paused where state.counter > plan.activeUpperReset:
                state.counter = plan.activeUpperReset
            default:
                break
            }
            let output = state.counter * plan.outputScale
            guard output.isFinite else { continue }
            states[target] = state
            result[target] = .scalar(output)
        }
        return result
    }

    private nonisolated func currentValues(
    ) -> [SceneDynamicTarget: SceneDynamicValue] {
        bindings.reduce(into: [:]) { result, binding in
            guard let state = states[binding.definition.target] else { return }
            let output = state.counter * binding.plan.outputScale
            guard output.isFinite else { return }
            result[binding.definition.target] = .scalar(output)
        }
    }
}
