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
        let animationEvents: [ScenePuppetAnimationEventOccurrence]
        let eventFailures: [ScenePuppetAnimationIdentity: ScenePuppetAnimationEventFailure]

        subscript(layerID: Int) -> LayerFrame? { layers[layerID] }
    }

    enum Failure: Error, Equatable {
        case conflictingDefinition(layerID: Int)
        case unmatchedAnimationLayer(layerID: Int)
        case unconsumedCadence(frameIndex: UInt64)
        case unknownIdentity(ScenePuppetAnimationIdentity)
        case invalidValue(ScenePuppetAnimationIdentity)
        case invalidControlSource(layerID: Int, animationLayerID: Int)
        case invalidControlTarget(ScenePuppetAnimationIdentity)
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
                && lhs.animation.transformTrackStates == rhs.animation.transformTrackStates
                && lhs.animation.alphaByBone == rhs.animation.alphaByBone
                && lhs.animation.events == rhs.animation.events
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
        var eventSequence: UInt64 = 0
        var eventFailure: ScenePuppetAnimationEventFailure?

        func phase(_ clip: ClipDefinition) -> Double {
            (playbackTime ?? 0) * rate * Double(clip.animation.framesPerSecond) + phaseOffset
        }
    }

    private struct EventCrossing {
        let clipIndex: Int
        let eventIndex: Int
        let fraction: Double
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
    private var dynamicTopologyRevision: UInt64?
    private var states: [Int: [ClipState]] = [:]
    private var lastSceneTime: Double?
    private var latestFrame: FrameSnapshot?
    private var appliedCommands: [CommandKey: ScenePuppetAnimationCommand] = [:]
    private var lastCommandKey: CommandKey?
    static let commandBudget = 64
    /// One parent's event batch is atomic; overflow never publishes a prefix.
    static let eventBudget = 64

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
                visible: clip.layer.visible == true,
                eventFailure: Self.eventDefinitionFailure(clip))
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
        var animationEvents = sameCadence ? latestFrame!.animationEvents : []
        var eventFailures = sameCadence ? latestFrame!.eventFailures : [:]
        layers.reserveCapacity(definitions.count)
        for (layerID, definition) in definitions {
            // Paused surface rebuilding may register a newly prepared layer
            // after this cadence was consumed. Fill only that missing parent;
            // existing samples and their visibility decisions remain frozen.
            guard layers[layerID] == nil else { continue }
            var local = states[layerID]!
            var samples: [ScenePuppetAnimationEvaluator.FrameSample?] = []
            var crossings: [EventCrossing] = []
            var eventSources: Set<Int> = []
            var eventBatchOverflowed = false
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
                        switch Self.eventCrossings(clip: clip, clipIndex: index,
                            previousPhase: previousPhase, state: local[index]) {
                        case let .success(events):
                            if !events.isEmpty {
                                eventSources.insert(index)
                                if events.count > Self.eventBudget - crossings.count {
                                    eventBatchOverflowed = true
                                    crossings.removeAll(keepingCapacity: true)
                                } else if !eventBatchOverflowed {
                                    crossings.append(contentsOf: events)
                                }
                            }
                        case let .failure(failure):
                            local[index].eventFailure = failure
                            if failure == .eventBudgetExceeded {
                                eventSources.insert(index)
                                eventBatchOverflowed = true
                                crossings.removeAll(keepingCapacity: true)
                            }
                        }
                    }
                }
                samples.append(local[index].visible ? Self.sample(clip: clip, state: local[index]) : nil)
                animationSnapshots.append(Self.snapshot(clip: clip, state: local[index]))
            }
            if eventBatchOverflowed {
                for index in eventSources { local[index].eventFailure = .eventBudgetExceeded }
            } else {
                crossings.sort {
                    if $0.fraction != $1.fraction { return $0.fraction < $1.fraction }
                    return $0.clipIndex == $1.clipIndex
                        ? $0.eventIndex < $1.eventIndex : $0.clipIndex < $1.clipIndex
                }
                for crossing in crossings {
                    let index = crossing.clipIndex
                    let clip = definition.clips[index]
                    let event = clip.animation.events[crossing.eventIndex]
                    local[index].eventSequence += 1
                    animationEvents.append(.init(identity: clip.identity,
                        sequence: local[index].eventSequence, name: event.name, frame: event.frame))
                }
            }
            for index in definition.clips.indices {
                if let failure = local[index].eventFailure {
                    eventFailures[definition.clips[index].identity] = failure
                }
            }
            states[layerID] = local
            layers[layerID] = LayerFrame(samples: samples, blends: local.map(\.blend))
        }
        let frame = FrameSnapshot(frameIndex: frameIndex, sceneTime: currentSceneTime, layers: layers,
            animationSnapshots: Self.sorted(animationSnapshots),
            animationEvents: animationEvents, eventFailures: eventFailures)
        latestFrame = frame
        lastSceneTime = currentSceneTime
        return frame
    }

    /// Committed membership belongs to this launch owner, independently of
    /// surface reconstruction. The lazy set is built only at a topology change.
    func synchronizeDynamicLayers(
        topologyRevision: UInt64,
        liveLayerIDs: @autoclosure () -> Set<Int>
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard dynamicTopologyRevision != topologyRevision else { return }
        let live = liveLayerIDs()
        let retired = Set(definitions.keys.filter { $0 < 0 && !live.contains($0) })
        for layerID in retired {
            definitions.removeValue(forKey: layerID)
            states.removeValue(forKey: layerID)
        }
        appliedCommands = appliedCommands.filter { !retired.contains($0.value.identity.layerID) }
        if let frame = latestFrame {
            latestFrame = .init(frameIndex: frame.frameIndex, sceneTime: frame.sceneTime,
                layers: frame.layers.filter { !retired.contains($0.key) },
                animationSnapshots: frame.animationSnapshots.filter { !retired.contains($0.identity.layerID) },
                animationEvents: frame.animationEvents.filter { !retired.contains($0.identity.layerID) },
                eventFailures: frame.eventFailures.filter { !retired.contains($0.key.layerID) })
        }
        dynamicTopologyRevision = topologyRevision
    }

    /// Validation is side-effect free; a rejected owner cannot partially control a clip.
    func validate(_ commands: [ScenePuppetAnimationCommand], frameIndex: UInt64) -> Result<Void, Failure> {
        lock.lock()
        defer { lock.unlock() }
        return admission(commands, frameIndex: frameIndex).map { _ in () }
    }

    /// Prepared nested owners may control playback of sibling clips, while a
    /// visibility write remains owned by its exact typed property target.
    /// Validation does not change playback or publish a second native state.
    func validate(
        _ commands: [ScenePuppetAnimationCommand],
        sourceLayerID: Int,
        sourceAnimationLayerID: Int,
        frameIndex: UInt64
    ) -> Result<Void, Failure> {
        lock.lock()
        defer { lock.unlock() }
        var source: ScenePuppetAnimationIdentity?
        for clip in definitions[sourceLayerID]?.clips ?? []
            where clip.identity.animationLayerID == sourceAnimationLayerID {
            guard source == nil else {
                return .failure(.invalidControlSource(
                    layerID: sourceLayerID, animationLayerID: sourceAnimationLayerID
                ))
            }
            source = clip.identity
        }
        guard let source else {
            return .failure(.invalidControlSource(
                layerID: sourceLayerID, animationLayerID: sourceAnimationLayerID
            ))
        }
        for command in commands {
            guard command.identity.layerID == source.layerID else {
                return .failure(.invalidControlTarget(command.identity))
            }
            if case .setVisible = command.action, command.identity != source {
                return .failure(.invalidControlTarget(command.identity))
            }
        }
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

    private static func eventDefinitionFailure(_ clip: ClipDefinition) -> ScenePuppetAnimationEventFailure? {
        guard !clip.animation.events.isEmpty else { return nil }
        guard clip.animation.mode == "loop" else { return .unsupportedMode }
        guard clip.animation.frameCount > 0, clip.animation.framesPerSecond.isFinite,
              clip.animation.framesPerSecond > 0,
              clip.animation.events.allSatisfy({
                  !$0.name.isEmpty && !$0.name.contains("\0") && $0.recordedTime.isFinite
                      && $0.frame > 0 && $0.frame < clip.animation.frameCount
              }) else { return .invalidEvent }
        return nil
    }

    private static func eventCrossings(
        clip: ClipDefinition, clipIndex: Int, previousPhase: Double, state: ClipState
    ) -> Result<[EventCrossing], ScenePuppetAnimationEventFailure> {
        guard !clip.animation.events.isEmpty else { return .success([]) }
        if let failure = state.eventFailure { return .failure(failure) }
        let current = state.phase(clip)
        guard previousPhase.isFinite, current.isFinite else { return .failure(.nonFinitePhase) }
        let previous = max(0, previousPhase)
        guard state.rate > 0, current > previous else { return .success([]) }
        let count = Double(clip.animation.frameCount)
        let firstLoop = floor(previous / count)
        let lastLoop = floor(current / count)
        guard lastLoop - firstLoop <= 1 else { return .failure(.multipleLoopsCrossed) }
        var crossings: [EventCrossing] = []
        for (index, event) in clip.animation.events.enumerated() {
            for loop in firstLoop == lastLoop ? [firstLoop] : [firstLoop, lastLoop] {
                let phase = loop * count + Double(event.frame)
                guard phase > previous, phase <= current else { continue }
                guard crossings.count < eventBudget else { return .failure(.eventBudgetExceeded) }
                crossings.append(.init(clipIndex: clipIndex, eventIndex: index,
                    fraction: (phase - previous) / (current - previous)))
            }
        }
        guard UInt64(crossings.count) <= UInt64.max - state.eventSequence else {
            return .failure(.sequenceOverflow)
        }
        return .success(crossings)
    }
}
