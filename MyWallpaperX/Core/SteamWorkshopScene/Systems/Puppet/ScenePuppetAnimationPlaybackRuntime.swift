import Foundation

/// Launch-owned animation positions. The existing SceneClock supplies cadence;
/// surfaces retain pose/physics/GPU resources and consume this one sample frame.
nonisolated final class ScenePuppetAnimationPlaybackRuntime: @unchecked Sendable {
    struct LayerFrame {
        let samples: [ScenePuppetAnimationEvaluator.FrameSample?]
        let blends: [Double]?
        let selection: ScenePuppetAnimationSelection?
        let membershipRevision: UInt64

        init(samples: [ScenePuppetAnimationEvaluator.FrameSample?], blends: [Double]? = nil,
             selection: ScenePuppetAnimationSelection? = nil, membershipRevision: UInt64 = 0) {
            self.samples = samples
            self.blends = blends
            self.selection = selection
            self.membershipRevision = membershipRevision
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
        case unknownSingleAnimation(layerID: Int, animationID: Int)
    }

    private struct ClipDefinition: Equatable {
        let identity: ScenePuppetAnimationIdentity
        let layer: ScenePuppetAnimationLayer
        let animation: SceneMdlPuppetAnimation

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.identity == rhs.identity && lhs.layer == rhs.layer
                && ScenePuppetAnimationPlaybackRuntime.sameAnimation(lhs.animation, rhs.animation)
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
                // Scripts and newly prepared object properties retain the
                // resolved fallback without a typed value; legacy String
                // bindings still require their published Bool.
                return (layer.visibilityBinding == nil || layer.hasPreparedVisibilityProperty == true)
                    && layer.visible == true
            }
            return visible
        }
    }

    private struct LayerDefinition: Equatable {
        let composition: String
        let clips: [ClipDefinition]
        let availableSingleAnimations: [SceneMdlPuppetAnimation]

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.composition == rhs.composition && lhs.clips == rhs.clips
                && lhs.availableSingleAnimations.count == rhs.availableSingleAnimations.count
                && zip(lhs.availableSingleAnimations, rhs.availableSingleAnimations)
                    .allSatisfy { ScenePuppetAnimationPlaybackRuntime.sameAnimation($0.0, $0.1) }
        }
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

        mutating func setRate(_ value: Double, clip: ClipDefinition) {
            let next = Double(Float(value))
            guard rate != next else { return }
            let currentPhase = phase(clip)
            rate = next
            phaseOffset = currentPhase - (playbackTime ?? 0) * rate
                * Double(clip.animation.framesPerSecond)
        }
    }

    private struct EventCrossing {
        let clipIndex: Int
        let eventIndex: Int
        let fraction: Double
    }

    private struct Member {
        let clip: ClipDefinition
        var state: ClipState
    }

    private struct LayerState {
        var members: [Member]
        var selection: ScenePuppetAnimationSelection
        var membershipRevision: UInt64 = 0
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
    private var states: [Int: LayerState] = [:]
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
        authoredLayers: [ScenePuppetAnimationLayer],
        availableSingleAnimations: [SceneMdlPuppetAnimation] = []
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
        let definition = LayerDefinition(composition: selection.composition.rawValue, clips: clips,
            availableSingleAnimations: availableSingleAnimations)
        lock.lock()
        defer { lock.unlock() }
        if let previous = definitions[layerID] {
            return previous == definition ? .success(())
                : .failure(.conflictingDefinition(layerID: layerID))
        }
        definitions[layerID] = definition
        states[layerID] = LayerState(members: clips.map { clip in
            Member(clip: clip, state: ClipState(rate: clip.layer.rate ?? 1,
                blend: clip.layer.blend ?? 1, visible: clip.layer.visible == true,
                eventFailure: Self.eventDefinitionFailure(clip)))
        }, selection: selection)
        return .success(())
    }

    func singleAnimationSource(layerID: Int, name: String) -> ScenePuppetSingleAnimationSourceMetadata? {
        lock.lock()
        defer { lock.unlock() }
        return sourceMetadata(layerID: layerID) { $0.name == name }
    }

    func singleAnimationSource(layerID: Int, animationID: Int) -> ScenePuppetSingleAnimationSourceMetadata? {
        lock.lock()
        defer { lock.unlock() }
        return sourceMetadata(layerID: layerID) { $0.id == animationID }
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
        for layerID in definitions.keys {
            // Paused surface rebuilding may register a newly prepared layer
            // after this cadence was consumed. Fill only that missing parent;
            // existing samples and their visibility decisions remain frozen.
            guard layers[layerID] == nil else { continue }
            var local = states[layerID]!
            var samples: [ScenePuppetAnimationEvaluator.FrameSample?] = []
            var crossings: [EventCrossing] = []
            var eventSources: Set<Int> = []
            var eventBatchOverflowed = false
            var retired: [Int] = []
            samples.reserveCapacity(local.members.count)
            for index in local.members.indices {
                let clip = local.members[index].clip
                var state = local.members[index].state
                if clip.usesDynamicVisibility {
                    state.visible = clip.isVisible(layerID: layerID, snapshot: dynamicValues)
                }
                let startsNow = state.playbackTime == nil
                if startsNow {
                    // Preserve first-visible nonzero sceneTime compatibility.
                    state.playbackTime = state.visible ? max(0, currentSceneTime) : 0
                }
                if clip.layer.hasRateScript == true || clip.layer.rateTimeline != nil, let id = clip.layer.id,
                   let resolved = dynamicValues[ScenePuppetAnimationPropertyTarget.rate(
                       layerID: layerID, animationLayerID: id)],
                   (clip.layer.hasRateScript == true && resolved.source == .sceneScript)
                    || (clip.layer.rateTimeline != nil && resolved.source == .timeline),
                   case let .scalar(rate) = resolved.value,
                   ScenePuppetAnimationCommand.acceptsScalarControl(rate) {
                    state.setRate(rate, clip: clip)
                }
                if clip.layer.blendTimeline != nil, let id = clip.layer.id,
                   let resolved = dynamicValues[ScenePuppetAnimationPropertyTarget.blend(
                       layerID: layerID, animationLayerID: id)],
                   resolved.source == .timeline, case let .scalar(blend) = resolved.value,
                   ScenePuppetAnimationCommand.acceptsScalarControl(blend) {
                    state.blend = Double(Float(blend))
                }
                if !startsNow && state.visible && state.isPlaying {
                    let previousPhase = state.explicitFrame ?? state.phase(clip)
                    state.playbackTime! += elapsed
                    if let explicit = state.explicitFrame, elapsed > 0, state.rate > 0 {
                        state.phaseOffset = max(0, explicit)
                            + elapsed * state.rate * Double(clip.animation.framesPerSecond)
                            - state.playbackTime! * state.rate * Double(clip.animation.framesPerSecond)
                        state.explicitFrame = nil
                    }
                    if case .created = clip.identity.instance,
                       elapsed > 0, state.rate > 0, state.explicitFrame == nil,
                       state.phase(clip) >= Double(clip.animation.frameCount) {
                        retired.append(index)
                        continue
                    }
                    if case .authored = clip.identity.instance, state.explicitFrame == nil {
                        Self.recordEnded(clip: clip, previousPhase: previousPhase, state: &state)
                        switch Self.eventCrossings(clip: clip, clipIndex: index,
                            previousPhase: previousPhase, state: state) {
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
                            state.eventFailure = failure
                            if failure == .eventBudgetExceeded {
                                eventSources.insert(index)
                                eventBatchOverflowed = true
                                crossings.removeAll(keepingCapacity: true)
                            }
                        }
                    }
                }
                local.members[index].state = state
                samples.append(state.visible ? Self.sample(clip: clip, state: state) : nil)
                animationSnapshots.append(Self.snapshot(clip: clip, state: state))
            }
            if eventBatchOverflowed {
                for index in eventSources { local.members[index].state.eventFailure = .eventBudgetExceeded }
            } else {
                crossings.sort {
                    if $0.fraction != $1.fraction { return $0.fraction < $1.fraction }
                    return $0.clipIndex == $1.clipIndex
                        ? $0.eventIndex < $1.eventIndex : $0.clipIndex < $1.clipIndex
                }
                for crossing in crossings {
                    let index = crossing.clipIndex
                    let clip = local.members[index].clip
                    let event = clip.animation.events[crossing.eventIndex]
                    local.members[index].state.eventSequence += 1
                    animationEvents.append(.init(identity: clip.identity,
                        sequence: local.members[index].state.eventSequence, name: event.name, frame: event.frame))
                }
            }
            for member in local.members {
                if let failure = member.state.eventFailure {
                    eventFailures[member.clip.identity] = failure
                }
            }
            if !retired.isEmpty {
                for index in retired.reversed() { local.members.remove(at: index) }
                local.selection = Self.selection(for: local.members)
                local.membershipRevision = frameIndex
            }
            states[layerID] = local
            layers[layerID] = LayerFrame(samples: samples, blends: local.members.map(\.state.blend),
                selection: local.selection, membershipRevision: local.membershipRevision)
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
        liveLayerIDs: @autoclosure () -> Set<Int>,
        destroyedAuthoredLayerIDs: Set<Int> = []
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard dynamicTopologyRevision != topologyRevision else { return }
        let live = liveLayerIDs()
        let retired = Set(definitions.keys.filter {
            destroyedAuthoredLayerIDs.contains($0) || ($0 < 0 && !live.contains($0))
        })
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

    /// Only visibility and ended subscriptions require a prepared nested source.
    /// Playback commands target any published clip; visibility stays exact-self.
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
        case let .success(admitted):
            for (layerID, layer) in admitted.layers { states[layerID] = layer }
            for command in admitted.commands {
                let key = CommandKey(epoch: command.callbackEpoch, ordinal: command.ordinal)
                if appliedCommands[key] != nil { continue }
                appliedCommands[key] = command
                lastCommandKey = key
            }
            return .success(())
        }
    }

    func snapshots() -> [ScenePuppetAnimationSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        return Self.sorted(states.flatMap { _, layer in
            layer.members.map { member in
                Self.snapshot(clip: member.clip, state: member.state)
            }
        })
    }

    private func admission(_ commands: [ScenePuppetAnimationCommand], frameIndex: UInt64)
        -> Result<(commands: [ScenePuppetAnimationCommand], layers: [Int: LayerState]), Failure> {
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
        var candidates: [Int: LayerState] = [:]
        for command in ordered {
            let key = CommandKey(epoch: command.callbackEpoch, ordinal: command.ordinal)
            guard keys.insert(key).inserted else { return .failure(.duplicateCommand) }
            if let applied = appliedCommands[key] {
                guard applied == command else { return .failure(.duplicateCommand) }
                continue
            }
            guard lastCommandKey == nil || key > lastCommandKey! else { return .failure(.staleCommand) }
            newCount += 1
            let layerID = command.identity.layerID
            guard var layer = candidates[layerID] ?? states[layerID] else {
                return .failure(.unknownIdentity(command.identity))
            }
            if case let .createSingle(animationID) = command.action {
                guard command.identity.instance == .created(epoch: command.callbackEpoch, ordinal: command.ordinal),
                      !layer.members.contains(where: { $0.clip.identity == command.identity }) else {
                    return .failure(.invalidControlTarget(command.identity))
                }
                guard let animation = definitions[layerID]?.availableSingleAnimations.first(where: {
                    $0.id == animationID
                }) else { return .failure(.unknownSingleAnimation(layerID: layerID, animationID: animationID)) }
                let configuration = ScenePuppetAnimationLayer(id: nil, animationID: animationID,
                    name: nil, additive: false, blend: 1, blendIn: nil, blendOut: nil,
                    blendTime: nil, rate: 1, visible: true, visibilityBinding: nil)
                let clip = ClipDefinition(identity: command.identity, layer: configuration, animation: animation)
                layer.members.append(Member(clip: clip,
                    state: ClipState(playbackTime: 0, rate: 1, blend: 1, visible: true)))
                guard Self.acceptsComposition(layer.members) else {
                    return .failure(.invalidControlTarget(command.identity))
                }
                layer.selection = Self.selection(for: layer.members)
                layer.membershipRevision = frameIndex &+ 1
            } else {
                guard let index = layer.members.firstIndex(where: { $0.clip.identity == command.identity }) else {
                    return .failure(.unknownIdentity(command.identity))
                }
                let clip = layer.members[index].clip
                var state = layer.members[index].state
                switch command.action {
                case .play: state.isPlaying = true
                case .pause: state.isPlaying = false
                case .stop: state.isPlaying = false; state.explicitFrame = 0
                case let .setFrame(value):
                    guard value.isFinite, Float(value).isFinite else { return .failure(.invalidValue(command.identity)) }
                    state.explicitFrame = Double(Float(value))
                case let .setRate(value), let .setBlend(value):
                    guard ScenePuppetAnimationCommand.acceptsScalarControl(value) else {
                        return .failure(.invalidValue(command.identity))
                    }
                    if case .setRate = command.action { state.setRate(value, clip: clip) }
                    else { state.blend = Double(Float(value)) }
                case let .setVisible(visible):
                    guard case .authored = command.identity.instance else {
                        return .failure(.invalidControlTarget(command.identity))
                    }
                    state.visible = visible
                case .createSingle: break
                }
                layer.members[index].state = state
            }
            candidates[layerID] = layer
        }
        guard appliedCommands.count + newCount <= Self.commandBudget else {
            return .failure(.commandBudgetExceeded)
        }
        return .success((commands: ordered, layers: candidates))
    }

    private func sourceMetadata(layerID: Int, matching: (SceneMdlPuppetAnimation) -> Bool)
        -> ScenePuppetSingleAnimationSourceMetadata? {
        var selected: SceneMdlPuppetAnimation?
        for animation in definitions[layerID]?.availableSingleAnimations ?? [] where matching(animation) {
            guard selected == nil else { return nil }
            selected = animation
        }
        return selected.map { .init(animationID: $0.id, name: $0.name,
            framesPerSecond: Double($0.framesPerSecond), frameCount: $0.frameCount) }
    }

    private static func sameAnimation(_ lhs: SceneMdlPuppetAnimation, _ rhs: SceneMdlPuppetAnimation) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.mode == rhs.mode
            && lhs.framesPerSecond == rhs.framesPerSecond && lhs.frameCount == rhs.frameCount
            && lhs.referenceTrackPolicy == rhs.referenceTrackPolicy
            && lhs.transformsByBone == rhs.transformsByBone && lhs.transformTrackStates == rhs.transformTrackStates
            && lhs.alphaByBone == rhs.alphaByBone && lhs.events == rhs.events
    }

    private static func selection(for members: [Member]) -> ScenePuppetAnimationSelection {
        let clips = members.map { ScenePuppetAnimationSelection.Clip(layer: $0.clip.layer, animation: $0.clip.animation) }
        return .init(clips: clips, composition: clips.count == 1 && clips[0].layer.additive == false
            ? .singleAbsolute : .layered)
    }

    private static func acceptsComposition(_ members: [Member]) -> Bool {
        let alphaCount = members.reduce(0) { $0 + ($1.clip.animation.hasAlphaContribution ? 1 : 0) }
        let opaqueCount = members.reduce(0) { $0 + ($1.clip.layer.additive == false ? 1 : 0) }
        return alphaCount <= 1 && (opaqueCount <= 1 || !members.contains {
            $0.clip.animation.transformTrackStates.contains(.referenceCandidate)
        })
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
        // Stable grouping retains the runtime's member order within a parent.
        snapshots.sorted { $0.identity.layerID < $1.identity.layerID }
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
