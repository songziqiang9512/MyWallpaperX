import Foundation

/// Scene-scoped evaluator for the admitted media-color profile. Media events
/// are applied once per host frame before update, then one result is broadcast
/// to every surface.
nonisolated struct SceneMediaColorTransitionRuntime {
    private enum PlaybackMode {
        case stopped
        case playing
        case paused

        init?(_ value: Int) {
            switch value {
            case 0: self = .stopped
            case 1: self = .playing
            case 2: self = .paused
            default: return nil
            }
        }
    }

    private struct State {
        var oldColor: SIMD3<Double>
        var newColor: SIMD3<Double>
        var timer: TimeInterval
    }

    private let bindings: [SceneMediaColorTransitionBinding]
    private var states: [SceneDynamicTarget: State] = [:]
    private var playbackMode = PlaybackMode.stopped
    private var consumedThumbnailGeneration: UInt64 = 0
    private var consumedPlaybackGeneration: UInt64 = 0
#if DEBUG
    private var reportedThumbnailCompletionGenerations: [SceneDynamicTarget: UInt64] = [:]
#endif

    nonisolated init(program: SceneMediaColorTransitionProgram) {
        bindings = program.bindings
    }

    nonisolated mutating func values(
        effectivePropertyValues: [String: SceneUserPropertyValue],
        mediaInput: SceneMediaThumbnailInbox.Snapshot,
        frameTime: TimeInterval
    ) -> [SceneDynamicTarget: SceneDynamicValue] {
        let topColors = resolvedTopColors(from: effectivePropertyValues)
        initializeStates(topColors: topColors)
        applyMediaEvents(mediaInput)

        let advances = frameTime.isFinite && frameTime >= 0
        var result: [SceneDynamicTarget: SceneDynamicValue] = [:]
        for binding in bindings {
            let target = binding.definition.target
            guard let topColor = topColors[target], var state = states[target] else {
                continue
            }
            let plan = binding.plan
            var output = state.newColor
            if state.timer < plan.duration {
                let progress = state.timer / plan.duration
                output = state.oldColor + (state.newColor - state.oldColor) * progress
                if advances {
                    state.timer += frameTime
                }
            }
            if state.newColor == .zero || playbackMode == .stopped {
                output = topColor
            }
            guard Self.isNormalizedColor(output) else { continue }
            states[target] = state
            result[target] = .vector3(output.x, output.y, output.z)
#if DEBUG
            reportThumbnailCompletionIfNeeded(
                binding: binding,
                state: state,
                output: output
            )
#endif
        }
        return result
    }

#if DEBUG
    private mutating func reportThumbnailCompletionIfNeeded(
        binding: SceneMediaColorTransitionBinding,
        state: State,
        output: SIMD3<Double>
    ) {
        let generation = consumedThumbnailGeneration
        guard generation > 0,
              state.timer >= binding.plan.duration,
              reportedThumbnailCompletionGenerations[binding.definition.target]
                != generation else { return }
        let fallback: String
        if state.newColor == .zero {
            fallback = "missing-color"
        } else if playbackMode == .stopped {
            fallback = "playback-stopped"
        } else {
            guard output == state.newColor else { return }
            fallback = "none"
        }
        let channel = switch binding.plan.thumbnailColorChannel {
        case .primary: "primary"
        case .secondary: "secondary"
        }
        reportedThumbnailCompletionGenerations[binding.definition.target] = generation
        NSLog(
            "MWX Scene media color: event=thumbnail-color-completed target=%@ generation=%llu channel=%@ output=%.9g,%.9g,%.9g fallback=%@ route=disable-generic",
            String(describing: binding.definition.target),
            generation,
            channel,
            output.x,
            output.y,
            output.z,
            fallback
        )
    }
#endif

    private mutating func initializeStates(
        topColors: [SceneDynamicTarget: SIMD3<Double>]
    ) {
        for binding in bindings where states[binding.definition.target] == nil {
            guard let topColor = topColors[binding.definition.target] else { continue }
            states[binding.definition.target] = State(
                oldColor: topColor,
                newColor: topColor,
                timer: binding.plan.duration
            )
        }
    }

    private mutating func applyMediaEvents(
        _ input: SceneMediaThumbnailInbox.Snapshot
    ) {
        if input.generation != consumedThumbnailGeneration {
            consumedThumbnailGeneration = input.generation
            for binding in bindings {
                let target = binding.definition.target
                guard var state = states[target] else { continue }
                let eventColor: SIMD3<Double>?
                switch binding.plan.thumbnailColorChannel {
                case .primary:
                    eventColor = input.primaryColor
                case .secondary:
                    eventColor = input.secondaryColor
                }
                let color = eventColor.flatMap {
                    Self.isNormalizedColor($0) ? $0 : nil
                } ?? .zero
                state.oldColor = state.newColor
                state.newColor = color
                state.timer = 0
                states[target] = state
            }
        }
        if input.playbackGeneration != consumedPlaybackGeneration {
            consumedPlaybackGeneration = input.playbackGeneration
            if let rawState = input.playbackState,
               let mode = PlaybackMode(rawState) {
                playbackMode = mode
            }
        }
    }

    private func resolvedTopColors(
        from values: [String: SceneUserPropertyValue]
    ) -> [SceneDynamicTarget: SIMD3<Double>] {
        bindings.reduce(into: [:]) { result, binding in
            let plan = binding.plan
            let color = values[plan.userPropertyKey]
                .flatMap(Self.color(from:)) ?? plan.authoredTopColor
            guard Self.isNormalizedColor(color) else { return }
            result[binding.definition.target] = color
        }
    }

    private static func color(
        from value: SceneUserPropertyValue
    ) -> SIMD3<Double>? {
        guard case let .string(source) = value else { return nil }
        let components = source.split(whereSeparator: \Character.isWhitespace)
        guard components.count == 3,
              let red = Double(components[0]),
              let green = Double(components[1]),
              let blue = Double(components[2]) else { return nil }
        let result = SIMD3(red, green, blue)
        return isNormalizedColor(result) ? result : nil
    }

    private static func isNormalizedColor(_ value: SIMD3<Double>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite
            && (0...1).contains(value.x)
            && (0...1).contains(value.y)
            && (0...1).contains(value.z)
    }
}
