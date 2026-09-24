import Foundation

/// Typed control state for authored TEX sprite playback. The runtime owns no
/// texture, provider, timer, or clock: it samples immutable frame metadata
/// against the host's existing SceneClock and returns one playback time for
/// the existing SceneSpriteAnimation consumer.
nonisolated final class SceneTextureAnimationPlaybackRuntime: @unchecked Sendable {
    nonisolated enum Failure: Error, Equatable, Sendable {
        case conflictingDefinition(layerID: Int)
        case unknownLayer(layerID: Int)
        case invalidFrame(layerID: Int)
        case invalidRate(layerID: Int)
        case commandBudgetExceeded
    }

    private struct Definition: Equatable {
        let sourceIdentity: String
        let frameDurations: [Double]
        let frameEndTimes: [Double]
        let duration: Double

        init(sourceIdentity: String, animation: SceneSpriteAnimation) {
            self.sourceIdentity = sourceIdentity
            frameDurations = animation.frameDurations.map(Double.init)
            frameEndTimes = animation.frameEndTimes.map(Double.init)
            duration = Double(animation.duration)
        }

        var frameCount: Int { frameDurations.count }

        func normalizedPlaybackTime(_ value: Double) -> Double {
            guard duration > 0 else { return 0 }
            var result = value.truncatingRemainder(dividingBy: duration)
            if result < 0 { result += duration }
            return result
        }

        func playbackTime(forFrame frame: Double) -> Double {
            guard frameCount > 0 else { return 0 }
            let index = min(max(Int(frame), 0), frameCount - 1)
            return index == 0 ? 0 : frameEndTimes[index - 1]
        }

        func samplingTime(_ value: Double) -> Float {
            // Renderer playback is Float. Quantization can advance to the
            // next frame, including rounding the last instant up to the loop end.
            let time = Float(normalizedPlaybackTime(value))
            return time < Float(duration) ? time : 0
        }

        func frame(atPlaybackTime value: Double) -> Double {
            guard frameCount > 0, duration > 0 else { return 0 }
            let time = Double(samplingTime(value))
            var lower = 0
            var upper = frameEndTimes.count
            while lower < upper {
                let middle = lower + (upper - lower) / 2
                if time < frameEndTimes[middle] {
                    upper = middle
                } else {
                    lower = middle + 1
                }
            }
            let index = min(lower, frameCount - 1)
            // The public API reports the discrete frame currently sampled by
            // the renderer.  Authored scripts commonly use strict equality
            // against `frameCount - 1` to schedule stop/restart callbacks.
            return Double(index)
        }
    }

    private struct LocalState: Equatable {
        var anchorSceneTime: Double
        var anchorPlaybackTime: Double
        var rate: Double
        var isPlaying: Bool

        func playbackTime(at sceneTime: Double, definition: Definition) -> Double {
            let elapsed = isPlaying
                ? (sceneTime - anchorSceneTime) * rate
                : 0
            return definition.normalizedPlaybackTime(anchorPlaybackTime + elapsed)
        }
    }

    private static let maximumCommandsPerFrame = 64
    private static let maximumAbsoluteRate = 16.0
    private let lock = NSLock()
    private var definitions: [Int: Definition] = [:]
    private var definitionsBySource: [String: Definition] = [:]
    private var localStates: [Int: LocalState] = [:]

    @discardableResult
    func register(
        layerID: Int,
        sourceIdentity: String,
        animation: SceneSpriteAnimation
    ) -> Result<Void, Failure> {
        let definition = Definition(
            sourceIdentity: sourceIdentity,
            animation: animation
        )
        lock.lock()
        defer { lock.unlock() }
        if let existing = definitions[layerID], existing != definition {
            return .failure(.conflictingDefinition(layerID: layerID))
        }
        if let existing = definitionsBySource[sourceIdentity],
           existing != definition {
            return .failure(.conflictingDefinition(layerID: layerID))
        }
        definitions[layerID] = definition
        definitionsBySource[sourceIdentity] = definition
        return .success(())
    }

    func snapshots(sceneTime: TimeInterval) -> [Int: SceneTextureAnimationSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        return definitions.reduce(into: [:]) { output, entry in
            let (layerID, definition) = entry
            let sharedTime = definition.normalizedPlaybackTime(sceneTime)
            let state = localStates[layerID]
            let playbackTime = state?.playbackTime(
                at: sceneTime,
                definition: definition
            ) ?? sharedTime
            output[layerID] = SceneTextureAnimationSnapshot(
                layerID: layerID,
                frameCount: definition.frameCount,
                duration: definition.duration,
                rate: state?.rate ?? 1,
                currentFrame: definition.frame(atPlaybackTime: playbackTime),
                isPlaying: state?.isPlaying ?? true,
                sharedRate: 1,
                sharedCurrentFrame: definition.frame(atPlaybackTime: sharedTime),
                sharedIsPlaying: true
            )
        }
    }

    func playbackTimes<LayerIDs: Sequence>(
        layerIDs: LayerIDs,
        sceneTime: TimeInterval
    ) -> [Int: Float] where LayerIDs.Element == Int {
        lock.lock()
        defer { lock.unlock() }
        return layerIDs.reduce(into: [:]) { output, layerID in
            guard let definition = definitions[layerID] else { return }
            let value = localStates[layerID]?.playbackTime(
                at: sceneTime,
                definition: definition
            ) ?? definition.normalizedPlaybackTime(sceneTime)
            output[layerID] = definition.samplingTime(value)
        }
    }

    func validate(
        _ commands: [SceneTextureAnimationCommand],
        sceneTime: TimeInterval
    ) -> Result<Void, Failure> {
        lock.lock()
        defer { lock.unlock() }
        return stagedStates(
            applying: commands,
            sceneTime: sceneTime,
            to: localStates
        ).map { _ in () }
    }

    @discardableResult
    func apply(
        _ commands: [SceneTextureAnimationCommand],
        sceneTime: TimeInterval
    ) -> Result<Void, Failure> {
        lock.lock()
        defer { lock.unlock() }
        switch stagedStates(
            applying: commands,
            sceneTime: sceneTime,
            to: localStates
        ) {
        case let .success(staged):
            localStates = staged
            return .success(())
        case let .failure(failure):
            return .failure(failure)
        }
    }

    private func stagedStates(
        applying commands: [SceneTextureAnimationCommand],
        sceneTime: TimeInterval,
        to initial: [Int: LocalState]
    ) -> Result<[Int: LocalState], Failure> {
        guard commands.count <= Self.maximumCommandsPerFrame else {
            return .failure(.commandBudgetExceeded)
        }
        var staged = initial
        for command in commands {
            guard let definition = definitions[command.layerID] else {
                return .failure(.unknownLayer(layerID: command.layerID))
            }
            if case .join = command.action {
                staged[command.layerID] = nil
                continue
            }
            var state = staged[command.layerID] ?? LocalState(
                anchorSceneTime: sceneTime,
                anchorPlaybackTime: definition.normalizedPlaybackTime(sceneTime),
                rate: 1,
                isPlaying: true
            )
            let currentTime = state.playbackTime(
                at: sceneTime,
                definition: definition
            )
            state.anchorSceneTime = sceneTime
            state.anchorPlaybackTime = currentTime
            switch command.action {
            case .play:
                state.isPlaying = true
            case .pause:
                state.isPlaying = false
            case .stop:
                state.anchorPlaybackTime = 0
                state.isPlaying = false
            case let .setFrame(frame):
                guard frame.isFinite, frame >= 0,
                      frame.rounded(.towardZero) == frame,
                      frame < Double(definition.frameCount) else {
                    return .failure(.invalidFrame(layerID: command.layerID))
                }
                state.anchorPlaybackTime = definition.playbackTime(forFrame: frame)
            case let .setRate(rate):
                guard rate.isFinite,
                      abs(rate) <= Self.maximumAbsoluteRate else {
                    return .failure(.invalidRate(layerID: command.layerID))
                }
                state.rate = rate
            case .join:
                break
            }
            staged[command.layerID] = state
        }
        return .success(staged)
    }
}
