import Foundation

/// Launch-owned animation positions. The existing SceneClock supplies cadence;
/// surfaces retain pose/physics/GPU resources and consume this one sample frame.
nonisolated final class ScenePuppetAnimationPlaybackRuntime: @unchecked Sendable {
    struct LayerFrame {
        let samples: [ScenePuppetAnimationEvaluator.FrameSample?]
        let blends: [Double]?

        init(samples: [ScenePuppetAnimationEvaluator.FrameSample?], blends: [Double]? = nil) {
            self.samples = samples
            self.blends = blends
        }
    }

    struct FrameSnapshot {
        let frameIndex: UInt64
        let sceneTime: Double
        fileprivate let layers: [Int: LayerFrame]
        let animationSnapshots: [ScenePuppetAnimationSnapshot]

        subscript(layerID: Int) -> LayerFrame? { layers[layerID] }
    }

    enum Failure: Error, Equatable {
        case conflictingDefinition(layerID: Int)
        case unmatchedAnimationLayer(layerID: Int)
        case unconsumedCadence(frameIndex: UInt64)
        case unknownIdentity(ScenePuppetAnimationIdentity)
        case invalidValue(ScenePuppetAnimationIdentity)
        case commandBudgetExceeded
        case duplicateCommand
        case staleCommand
    }

    private struct ClipDefinition: Equatable {
        let identity: ScenePuppetAnimationIdentity
        let layer: ScenePuppetAnimationLayer
        let animation: SceneMdlPuppetAnimation

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.identity == rhs.identity && lhs.layer == rhs.layer
                && lhs.animation.id == rhs.animation.id
                && lhs.animation.name == rhs.animation.name
                && lhs.animation.mode == rhs.animation.mode
                && lhs.animation.framesPerSecond == rhs.animation.framesPerSecond
                && lhs.animation.frameCount == rhs.animation.frameCount
                && lhs.animation.transformsByBone == rhs.animation.transformsByBone
                && lhs.animation.alphaByBone == rhs.animation.alphaByBone
        }

        var usesDynamicVisibility: Bool {
            layer.visibilityBinding != nil || layer.hasVisibilityScript == true
        }

        func isVisible(layerID: Int, snapshot: SceneDynamicSnapshot) -> Bool {
            guard usesDynamicVisibility else { return layer.visible == true }
            guard let id = layer.id,
                  let resolved = snapshot[ScenePuppetAnimationPropertyTarget.visibility(
                      layerID: layerID, animationLayerID: id
                  )], case let .bool(visible) = resolved.value else {
                // Script presence is not admission: unsupported candidates have
                // no published target and retain their authored visual fallback.
                return layer.visibilityBinding == nil && layer.visible == true
            }
            return visible
        }
    }

    private struct LayerDefinition: Equatable {
        let composition: String
        let clips: [ClipDefinition]
    }

    private struct ClipState {
        var playbackTime: Double?
        var phaseOffset: Double = 0
        var explicitFrame: Double?
        var isPlaying = true
        var rate: Double
        var blend: Double
        var visible: Bool
        var endedSequence: UInt64 = 0
        var endedFailure: ScenePuppetAnimationEndedFailure?

        func phase(_ clip: ClipDefinition) -> Double {
            (playbackTime ?? 0) * rate * Double(clip.animation.framesPerSecond) + phaseOffset
        }
    }

    private struct CommandKey: Hashable, Comparable {
        let epoch: UInt64
        let ordinal: UInt32
        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.epoch == rhs.epoch ? lhs.ordinal < rhs.ordinal : lhs.epoch < rhs.epoch
        }
    }

    private let lock = NSLock()
    private var definitions: [Int: LayerDefinition] = [:]
    private var states: [Int: [ClipState]] = [:]
    private var lastSceneTime: Double?
    private var latestFrame: FrameSnapshot?
    private var appliedCommands: [CommandKey: ScenePuppetAnimationCommand] = [:]
    private var lastCommandKey: CommandKey?
    static let commandBudget = 64

    /// Only preparation compares immutable tracks. Registering the same layer
    /// for a second surface or rebuild preserves the launch's consumed position.
    @discardableResult
    func register(
        layerID: Int,
        selection: ScenePuppetAnimationSelection,
        authoredLayers: [ScenePuppetAnimationLayer]
    ) -> Result<Void, Failure> {
        var clips: [ClipDefinition] = []
        var nextAuthoredPosition = 0
        for clip in selection.clips {
            guard let position = authoredLayers.indices.dropFirst(nextAuthoredPosition)
                .first(where: { authoredLayers[$0] == clip.layer }) else {
                return .failure(.unmatchedAnimationLayer(layerID: layerID))
            }
            nextAuthoredPosition = position + 1
            clips.append(.init(identity: .init(layerID: layerID, animationLayerIndex: position,
                animationLayerID: clip.layer.id), layer: clip.layer,
                animation: clip.animation))
        }
        let definition = LayerDefinition(composition: selection.composition.rawValue, clips: clips)
        lock.lock()
        defer { lock.unlock() }
        if let previous = definitions[layerID] {
            return previous == definition ? .success(())
                : .failure(.conflictingDefinition(layerID: layerID))
        }
        definitions[layerID] = definition
        states[layerID] = clips.map { clip in
            ClipState(rate: clip.layer.rate ?? 1, blend: clip.layer.blend ?? 1,
                visible: clip.layer.visible == true)
        }
        return .success(())
    }

    /// Consume cadence once, before any surface or GPU work. Hidden clips keep
    /// their position but publish nil samples so the existing bind-pose fallback
    /// remains intact. Restoring visibility adds only this cadence's increment.
    func advance(
        frameIndex: UInt64,
        sceneTime: Double,
        dynamicValues: SceneDynamicSnapshot
    ) -> FrameSnapshot {
        lock.lock()
        defer { lock.unlock() }
        if let latestFrame, frameIndex < latestFrame.frameIndex { return latestFrame }
        let sameCadence = latestFrame?.frameIndex == frameIndex
        let currentSceneTime = sameCadence ? latestFrame!.sceneTime : sceneTime
        var layers: [Int: LayerFrame] = sameCadence ? latestFrame!.layers : [:]
        if let latestFrame, sameCadence, layers.count == definitions.count { return latestFrame }
        let elapsed = sameCadence ? 0 : max(0, currentSceneTime - (lastSceneTime ?? currentSceneTime))
        if !sameCadence { appliedCommands.removeAll(keepingCapacity: true) }
        var animationSnapshots = sameCadence ? latestFrame!.animationSnapshots : []
        layers.reserveCapacity(definitions.count)
        for (layerID, definition) in definitions {
            // Paused surface rebuilding may register a newly prepared layer
            // after this cadence was consumed. Fill only that missing parent;
            // existing samples and their visibility decisions remain frozen.
            guard layers[layerID] == nil else { continue }
            var local = states[layerID]!
            var samples: [ScenePuppetAnimationEvaluator.FrameSample?] = []
            samples.reserveCapacity(definition.clips.count)
            for index in definition.clips.indices {
                let clip = definition.clips[index]
                if clip.usesDynamicVisibility {
                    local[index].visible = clip.isVisible(layerID: layerID, snapshot: dynamicValues)
                }
                if local[index].playbackTime == nil {
                    // Preserve first-visible nonzero sceneTime compatibility.
                    local[index].playbackTime = local[index].visible ? max(0, currentSceneTime) : 0
                } else if local[index].visible && local[index].isPlaying {
                    let previousPhase = local[index].explicitFrame ?? local[index].phase(clip)
                    local[index].playbackTime! += elapsed
                    if let explicit = local[index].explicitFrame, elapsed > 0, local[index].rate > 0 {
                        local[index].phaseOffset = max(0, explicit)
                            + elapsed * local[index].rate * Double(clip.animation.framesPerSecond)
                            - local[index].playbackTime! * local[index].rate * Double(clip.animation.framesPerSecond)
                        local[index].explicitFrame = nil
                    }
                    if local[index].explicitFrame == nil {
                        Self.recordEnded(clip: clip, previousPhase: previousPhase, state: &local[index])
                    }
                }
                samples.append(local[index].visible ? Self.sample(clip: clip, state: local[index]) : nil)
                animationSnapshots.append(Self.snapshot(clip: clip, state: local[index]))
            }
            states[layerID] = local
            layers[layerID] = LayerFrame(samples: samples, blends: local.map(\.blend))
        }
        let frame = FrameSnapshot(frameIndex: frameIndex, sceneTime: currentSceneTime, layers: layers,
            animationSnapshots: Self.sorted(animationSnapshots))
        latestFrame = frame
        lastSceneTime = currentSceneTime
        return frame
    }

    /// Validation is side-effect free; a rejected owner cannot partially control a clip.
    func validate(_ commands: [ScenePuppetAnimationCommand], frameIndex: UInt64) -> Result<Void, Failure> {
        lock.lock()
        defer { lock.unlock() }
        return admission(commands, frameIndex: frameIndex).map { _ in () }
    }

    /// Apply only after this SceneClock cadence was consumed. Samples already
    /// handed to surfaces stay frozen; controls affect the following advance.
    @discardableResult
    func apply(_ commands: [ScenePuppetAnimationCommand], frameIndex: UInt64) -> Result<Void, Failure> {
        lock.lock()
        defer { lock.unlock() }
        switch admission(commands, frameIndex: frameIndex) {
        case let .failure(failure): return .failure(failure)
        case let .success(ordered):
            for command in ordered {
                let key = CommandKey(epoch: command.callbackEpoch, ordinal: command.ordinal)
                if appliedCommands[key] != nil { continue }
                let clips = definitions[command.identity.layerID]!.clips
                let index = clips.firstIndex { $0.identity == command.identity }!
                let clip = clips[index]
                var state = states[command.identity.layerID]![index]
                switch command.action {
                case .play: state.isPlaying = true
                case .pause: state.isPlaying = false
                case .stop: state.isPlaying = false; state.explicitFrame = 0
                case let .setFrame(frame): state.explicitFrame = Double(Float(frame))
                case let .setRate(rate):
                    let phase = state.phase(clip)
                    state.rate = Double(Float(rate))
                    state.phaseOffset = phase - (state.playbackTime ?? 0) * state.rate
                        * Double(clip.animation.framesPerSecond)
                case let .setBlend(blend): state.blend = Double(Float(blend))
                case let .setVisible(visible): state.visible = visible
                }
                states[command.identity.layerID]![index] = state
                appliedCommands[key] = command
                lastCommandKey = key
            }
            return .success(())
        }
    }

    func snapshots() -> [ScenePuppetAnimationSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        return Self.sorted(definitions.flatMap { layerID, definition in
            definition.clips.enumerated().map { index, clip in
                Self.snapshot(clip: clip, state: states[layerID]![index])
            }
        })
    }

    private func admission(_ commands: [ScenePuppetAnimationCommand], frameIndex: UInt64)
        -> Result<[ScenePuppetAnimationCommand], Failure> {
        guard latestFrame?.frameIndex == frameIndex else {
            return .failure(.unconsumedCadence(frameIndex: frameIndex))
        }
        guard commands.count <= Self.commandBudget else { return .failure(.commandBudgetExceeded) }
        let ordered = commands.sorted {
            CommandKey(epoch: $0.callbackEpoch, ordinal: $0.ordinal)
                < CommandKey(epoch: $1.callbackEpoch, ordinal: $1.ordinal)
        }
        var keys: Set<CommandKey> = []
        var newCount = 0
        for command in ordered {
            guard definitions[command.identity.layerID]?.clips.contains(where: {
                $0.identity == command.identity
            }) == true else { return .failure(.unknownIdentity(command.identity)) }
            switch command.action {
            case let .setFrame(value):
                guard value.isFinite, Float(value).isFinite else { return .failure(.invalidValue(command.identity)) }
            case let .setRate(value), let .setBlend(value):
                guard value.isFinite, value >= 0, Float(value).isFinite else {
                    return .failure(.invalidValue(command.identity))
                }
            default: break
            }
            let key = CommandKey(epoch: command.callbackEpoch, ordinal: command.ordinal)
            guard keys.insert(key).inserted else { return .failure(.duplicateCommand) }
            if let applied = appliedCommands[key] {
                guard applied == command else { return .failure(.duplicateCommand) }
            } else {
                guard lastCommandKey == nil || key > lastCommandKey! else { return .failure(.staleCommand) }
                newCount += 1
            }
        }
        guard appliedCommands.count + newCount <= Self.commandBudget else {
            return .failure(.commandBudgetExceeded)
        }
        return .success(ordered)
    }

    private static func sample(clip: ClipDefinition, state: ClipState)
        -> ScenePuppetAnimationEvaluator.FrameSample {
        if let frame = state.explicitFrame {
            let count = clip.animation.frameCount
            guard count > 0 else { return .init(frameA: 0, frameB: 0) }
            let bounded = min(Double(count), max(0, frame))
            if bounded == Double(count) { return .init(frameA: count - 1, frameB: count, fraction: 1) }
            let a = Int(bounded.rounded(.down))
            return .init(frameA: a, frameB: a + 1, fraction: Float(bounded - Double(a)))
        }
        // Preserve the existing sampler for natural playback, including reverse
        // mirror intervals. Rate changes anchor phase instead of scaling history.
        if state.phaseOffset == 0 {
            return ScenePuppetAnimationEvaluator.frameSample(sceneTime: state.playbackTime ?? 0,
                rate: state.rate, animation: clip.animation)
        }
        return ScenePuppetAnimationEvaluator.frameSample(
            sceneTime: state.phase(clip) / Double(clip.animation.framesPerSecond),
            rate: 1, animation: clip.animation)
    }

    private static func snapshot(clip: ClipDefinition, state: ClipState) -> ScenePuppetAnimationSnapshot {
        let sample = sample(clip: clip, state: state)
        let fps = Double(clip.animation.framesPerSecond)
        return .init(identity: clip.identity, animationID: clip.animation.id,
            name: clip.layer.name ?? clip.animation.name, framesPerSecond: fps,
            frameCount: clip.animation.frameCount, duration: Double(clip.animation.frameCount) / fps,
            currentFrame: state.explicitFrame ?? (Double(sample.frameA)
                + Double(sample.frameB - sample.frameA) * Double(sample.fraction)),
            isPlaying: state.isPlaying, rate: state.rate, blend: state.blend,
            visible: state.visible, endedSequence: state.endedSequence,
            supportsEndedCallbacks: clip.animation.mode == "loop" && state.endedFailure == nil,
            endedFailure: clip.animation.mode == "loop" ? state.endedFailure : .unsupportedMode)
    }

    private static func sorted(_ snapshots: [ScenePuppetAnimationSnapshot]) -> [ScenePuppetAnimationSnapshot] {
        snapshots.sorted {
            $0.identity.layerID == $1.identity.layerID
                ? $0.identity.animationLayerIndex < $1.identity.animationLayerIndex
                : $0.identity.layerID < $1.identity.layerID
        }
    }

    private static func recordEnded(clip: ClipDefinition, previousPhase: Double, state: inout ClipState) {
        guard clip.animation.mode == "loop", state.endedFailure == nil,
              clip.animation.frameCount > 0, state.rate > 0 else { return }
        let currentPhase = state.phase(clip)
        let count = Double(clip.animation.frameCount)
        let crossings = floor(currentPhase / count) - floor(max(0, previousPhase) / count)
        guard crossings > 0 else { return }
        guard crossings == 1 else { state.endedFailure = .multipleLoopsCrossed; return }
        guard state.endedSequence < UInt64.max else { state.endedFailure = .sequenceOverflow; return }
        state.endedSequence += 1
    }
}
