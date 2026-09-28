import Foundation

/// Executes authored cursor callbacks against the shared scene VM. Hit
/// testing remains a typed host responsibility; JavaScript receives immutable
/// world/local positions and can only publish through existing mutation paths.
nonisolated final class SceneScriptCursorProgram: @unchecked Sendable {
    let bindings: [SceneScriptCursorBinding]
    private let generation: UInt64
    private var previousHits: [Int: SceneScriptCursorHit] = [:]
    private var capturedHits: [Int: SceneScriptCursorHit] = [:]
    private var previousPointerPosition: SIMD2<Float>?
    private var previousPrimaryButtonIsDown = false
    private var capturedSurfaceID: UInt32?
    private var previousSurfaceID: UInt32?
    private var previousSurface: SceneScriptSurfaceInput?
    private var disabledTargets: Set<SceneDynamicTarget> = []
    private var scriptPropertiesJSONCache = SceneScriptPropertyInputJSONCache()
    private var pendingEvents: [SceneScriptCursorPendingEvent] = []
    private var candidateEvents: [SceneScriptCursorPendingEvent] = []
    private var candidateFailures: Set<SceneDynamicTarget> = []
    private var hasCandidateDispatch = false
    // A normal 512-sample input batch can expand to several callbacks per
    // owner. Leave room for that burst and bound retained retry work as well.
    private static let maximumEventsPerOwner = 4096
    private static let maximumPendingEvents = 16_384

    let ownerLayerIDs: Set<Int>
    let ownerTargets: Set<SceneDynamicTarget>
    /// Layer hit state is shared, owner state is per target: several typed
    /// owners can live on one layer, so layer lookup must not scan them all.
    private let bindingsByLayer: [Int: [SceneScriptCursorBinding]]
    private let bindingsByTarget: [SceneDynamicTarget: SceneScriptCursorBinding]
    var capturedOwnerLayerIDs: Set<Int> { Set(capturedHits.keys) }
    var ownerCount: Int { bindings.count }
    var hasAudioConsumers: Bool { bindings.contains { $0.owner.hasAudioRegistration } }

    func edgeStateSnapshot() -> SceneScriptCursorEdgeState {
        .init(
            previousHits: previousHits,
            capturedHits: capturedHits,
            previousPointerPosition: previousPointerPosition,
            previousPrimaryButtonIsDown: previousPrimaryButtonIsDown,
            pendingEvents: pendingEvents,
            capturedSurfaceID: capturedSurfaceID,
            previousSurfaceID: previousSurfaceID,
            previousSurface: previousSurface
        )
    }

    func restoreEdgeState(_ state: SceneScriptCursorEdgeState) {
        previousHits = state.previousHits
        capturedHits = state.capturedHits
        previousPointerPosition = state.previousPointerPosition
        previousPrimaryButtonIsDown = state.previousPrimaryButtonIsDown
        pendingEvents = state.pendingEvents
        capturedSurfaceID = state.capturedSurfaceID
        previousSurfaceID = state.previousSurfaceID
        previousSurface = state.previousSurface
        clearCandidateEvents()
    }

    func timerFrameStateSnapshot() -> SceneScriptProgramTimerFrameState { .init(snapshots: bindings.map { $0.owner.timerFrameSnapshot() }) }
    func restoreTimerFrameState(_ state: SceneScriptProgramTimerFrameState) { zip(bindings, state.snapshots).forEach { $0.0.owner.restoreTimerFrame($0.1) } }
    func discardTimerFrameState(_ state: SceneScriptProgramTimerFrameState) { zip(bindings, state.snapshots).forEach { $0.0.owner.discardTimerFrame($0.1) } }

    init(
        bindings: [SceneScriptCursorBinding],
        generation: UInt64
    ) {
        self.bindings = bindings
        self.ownerLayerIDs = Set(bindings.map(\.layerID))
        self.ownerTargets = Set(bindings.map(\.ownerTarget))
        self.bindingsByLayer = Dictionary(grouping: bindings, by: \.layerID)
        self.bindingsByTarget = Dictionary(uniqueKeysWithValues: bindings.map { ($0.ownerTarget, $0) })
        self.generation = generation
    }

    func dispatch(
        batch: SceneScriptCursorFrameBatch,
        frame: SceneScriptFrameInput,
        userPropertiesJSON: String,
        effectivePropertyValues: [String: SceneUserPropertyValue] = [:],
        propertyRevision: UInt64? = nil,
        audioSpectrum: SceneAudioSpectrumSnapshot = .silent,
        interruptBudget: UInt64? = nil
    ) -> SceneScriptCursorFrameResult {
        hasCandidateDispatch = true
        candidateFailures.removeAll(keepingCapacity: true)
        candidateEvents = pendingEvents.filter { !disabledTargets.contains($0.ownerTarget) }
        defer {
            bindings.forEach {
                $0.owner.clearCursorAuthoredLayerBaselines()
            }
        }
        if batch.overflowed {
            // Rebase incomplete raw input, but preserve older complete events.
            // None were attempted here, so this dispatch confirms nothing.
            clearCandidateEvents()
            if let latest = batch.samples.last {
                synchronize(
                    hits: latest.hits,
                    pointerPosition: latest.pointerPosition,
                    primaryButtonIsDown: latest.primaryButtonIsDown,
                    surfaceID: latest.surfaceID,
                    surface: latest.surface
                )
            } else {
                synchronize(
                    hits: [:], pointerPosition: nil,
                    primaryButtonIsDown: false
                )
            }
            return .init(
                failures: [:], materialFunctionMutations: [],
                animationMutations: [], layerMutations: [],
                inputBatchOverflowed: true
            )
        }
        var failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure] = [:]
        func hasActiveBinding(layerID: Int) -> Bool {
            (bindingsByLayer[layerID] ?? []).contains { binding in
                !disabledTargets.contains(binding.ownerTarget)
            }
        }
        func removeCaptureIfOrphaned(layerID: Int) {
            if !hasActiveBinding(layerID: layerID) {
                capturedHits.removeValue(forKey: layerID)
            }
        }
        for binding in bindings where binding.owner.hasAudioRegistration
            && !disabledTargets.contains(binding.ownerTarget) {
            guard case let .failure(failure) = binding.owner.refreshAudio(audioSpectrum) else { continue }
            failures[binding.ownerTarget] = failure
            binding.owner.discardLayerMutations()
            if failure.permanentlyDisablesOwner {
                disabledTargets.insert(binding.ownerTarget)
            }
            removeCaptureIfOrphaned(layerID: binding.layerID)
        }
        var materialFunctions: [(
            ownerTarget: SceneDynamicTarget,
            mutation: SceneScriptMaterialFunctionMutation
        )] = []
        var animations: [(
            ownerTarget: SceneDynamicTarget,
            mutation: SceneTimelinePlaybackMutation
        )] = []
        var puppetBones: [(
            ownerTarget: SceneDynamicTarget,
            mutation: SceneScriptPuppetBoneMutation
        )] = []
        var textureAnimations: [(
            ownerTarget: SceneDynamicTarget,
            command: SceneTextureAnimationCommand
        )] = []
        var videos: [(
            ownerTarget: SceneDynamicTarget,
            command: SceneScriptVideoCommand
        )] = []
        var layers: [(
            ownerTarget: SceneDynamicTarget,
            mutation: SceneScriptLayerMutation
        )] = []
        var authoredMutationIndices: [
            SceneScriptCursorAuthoredMutationKey: Int
        ] = [:]
        func discardCandidates(ownerTarget: SceneDynamicTarget) {
            materialFunctions.removeAll { $0.ownerTarget == ownerTarget }
            animations.removeAll { $0.ownerTarget == ownerTarget }
            layers.removeAll { $0.ownerTarget == ownerTarget }
            puppetBones.removeAll { $0.ownerTarget == ownerTarget }
            textureAnimations.removeAll { $0.ownerTarget == ownerTarget }
            videos.removeAll { $0.ownerTarget == ownerTarget }
            authoredMutationIndices = [:]
            for (index, candidate) in layers.enumerated()
                where !candidate.mutation.isDynamic
                    && candidate.mutation.kind == .upsert {
                authoredMutationIndices[.init(
                    ownerTarget: candidate.ownerTarget,
                    targetLayerID: candidate.mutation.layerID
                )] = index
            }
        }
        func appendOwnerMutations(
            ownerTarget: SceneDynamicTarget,
            materialFunctions ownerMaterialFunctions: [SceneScriptMaterialFunctionMutation],
            animations ownerAnimations: [SceneTimelinePlaybackMutation],
            layers ownerLayers: [SceneScriptLayerMutation],
            puppetBones ownerPuppetBones: [SceneScriptPuppetBoneMutation],
            videos ownerVideos: [SceneScriptVideoCommand],
            textureAnimations ownerTextureAnimations: [SceneTextureAnimationCommand]
        ) {
            videos.append(contentsOf: ownerVideos.map { (ownerTarget, $0) })
            puppetBones.append(contentsOf:
                ownerPuppetBones.map { (ownerTarget, $0) }
            )
            textureAnimations.append(contentsOf:
                ownerTextureAnimations.map { (ownerTarget, $0) }
            )
            materialFunctions.append(contentsOf:
                ownerMaterialFunctions.map { (ownerTarget, $0) }
            )
            animations.append(contentsOf:
                ownerAnimations.map { (ownerTarget, $0) }
            )
            for mutation in ownerLayers {
                guard !mutation.isDynamic, mutation.kind == .upsert else {
                    layers.append((ownerTarget, mutation))
                    continue
                }
                let key = SceneScriptCursorAuthoredMutationKey(
                    ownerTarget: ownerTarget,
                    targetLayerID: mutation.layerID
                )
                if let index = authoredMutationIndices[key] {
                    layers[index].mutation = layers[index].mutation.merging(with: mutation)
                } else {
                    authoredMutationIndices[key] = layers.count
                    layers.append((ownerTarget, mutation))
                }
            }
        }
        // Cursor events are dispatched ahead of the frame evaluation, but a
        // borrowed owner's authored `init` belongs to that evaluation. Running
        // it here keeps the authored order (init before every other callback)
        // without moving the cursor/update ordering; the later evaluation finds
        // the owner initialized and adds nothing.
        func prepareOwner(
            binding: SceneScriptCursorBinding,
            callbackFrame: SceneScriptFrameInput
        ) -> Bool {
            let ownerTarget = binding.ownerTarget
            guard failures[ownerTarget] == nil,
                  !disabledTargets.contains(ownerTarget) else { return false }
            guard binding.owner.needsInitialization else { return true }
            guard let seedValue = binding.ownerSeedValue else {
                // Only a borrowed owner carries the authored seed, and its
                // construction already refuses an owner that would need the
                // frame evaluation. Reaching this means a future admission
                // change reintroduced the ordering gap, so fail closed.
                failures[ownerTarget] = .invalidArgument(
                    "SceneScript cursor owner initialization seed unavailable"
                )
                binding.owner.discardLayerMutations()
                disabledTargets.insert(ownerTarget)
                removeCaptureIfOrphaned(layerID: binding.layerID)
                return false
            }
            guard let propertiesJSON = scriptPropertiesJSONCache.value(
                for: binding.owner.target,
                inputs: binding.scriptProperties,
                effectiveValues: effectivePropertyValues,
                revision: propertyRevision
            ) else { return true }
            switch binding.owner.initializeIfNeeded(
                input: seedValue,
                frame: callbackFrame,
                scriptPropertiesJSON: propertiesJSON,
                userPropertiesJSON: userPropertiesJSON,
                expectedGeneration: generation,
                interruptBudget: interruptBudget,
                retainsValueForNextUpdate: true
            ) {
            case let .success(initialization):
                guard let initialization else { return true }
                appendOwnerMutations(
                    ownerTarget: ownerTarget,
                    materialFunctions: initialization.materialFunctionMutations,
                    animations: initialization.animationMutations,
                    layers: initialization.layerMutations,
                    puppetBones: initialization.puppetBoneMutations,
                    videos: initialization.videoCommands,
                    textureAnimations: initialization.textureAnimationCommands
                )
                return true
            case let .failure(failure):
                discardCandidates(ownerTarget: ownerTarget)
                binding.owner.discardLayerMutations()
                failures[ownerTarget] = failure
                if failure.permanentlyDisablesOwner {
                    disabledTargets.insert(ownerTarget)
                }
                removeCaptureIfOrphaned(layerID: binding.layerID)
                return false
            }
        }
        func emit(
            _ kind: SceneScriptCursorEventKind,
            binding: SceneScriptCursorBinding,
            hit: SceneScriptCursorHit,
            callbackFrame: SceneScriptFrameInput,
            captureActive: Bool,
            currentHit: Bool
        ) {
            let ownerTarget = binding.ownerTarget
            guard failures[ownerTarget] == nil, binding.events.contains(kind),
                  !disabledTargets.contains(ownerTarget) else { return }
            guard prepareOwner(binding: binding, callbackFrame: callbackFrame)
            else { return }
            guard let propertiesJSON = scriptPropertiesJSONCache.value(
                for: binding.owner.target,
                inputs: binding.scriptProperties,
                effectiveValues: effectivePropertyValues,
                revision: propertyRevision
            ) else {
                discardCandidates(ownerTarget: ownerTarget)
                binding.owner.discardLayerMutations()
                failures[ownerTarget] = .invalidArgument(
                    "SceneScript cursor script properties unavailable"
                )
                removeCaptureIfOrphaned(layerID: binding.layerID)
                return
            }
            let event = SceneScriptCursorEventInput(
                kind: kind,
                layerID: binding.layerID,
                worldPosition: hit.worldPosition,
                localPosition: hit.localPosition
            )
            switch binding.owner.dispatchCursor(
                event, frame: callbackFrame,
                scriptPropertiesJSON: propertiesJSON,
                userPropertiesJSON: userPropertiesJSON,
                authoredLayerBaselines: layers.compactMap { candidate in
                    guard candidate.ownerTarget == ownerTarget,
                          !candidate.mutation.isDynamic,
                          candidate.mutation.kind == .upsert else { return nil }
                    return candidate.mutation
                },
                interruptBudget: interruptBudget
            ) {
            case let .success(mutations):
                appendOwnerMutations(
                    ownerTarget: ownerTarget,
                    materialFunctions: mutations.materialFunctions,
                    animations: mutations.animations,
                    layers: mutations.layers,
                    puppetBones: mutations.puppetBones,
                    videos: mutations.videoCommands,
                    textureAnimations: mutations.textureAnimationCommands
                )
                for mutation in mutations.layers
                    where mutation.fields.contains(.origin) {
                    NSLog(
                        "MWX SceneScript VM: layerID=%d event=%@ mutation=origin value=%.6f,%.6f,%.6f route=generic-only",
                        mutation.layerID, kind.callbackName,
                        mutation.origin.x, mutation.origin.y, mutation.origin.z
                    )
                }
                NSLog(
                    "MWX SceneScript VM: layerID=%d event=%@ captureActive=%d currentHit=%d local=%.6f,%.6f,%.6f route=generic-only",
                    binding.layerID, kind.callbackName,
                    captureActive ? 1 : 0, currentHit ? 1 : 0,
                    hit.localPosition.x, hit.localPosition.y,
                    hit.localPosition.z
                )
            case let .failure(failure):
                discardCandidates(ownerTarget: ownerTarget)
                // Cursor callbacks borrow the vector owner's C transaction;
                // an extraction/identity failure must not remain commit-able
                // when the vector pass runs later in the same frame.
                binding.owner.discardLayerMutations()
                failures[ownerTarget] = failure
                if failure.permanentlyDisablesOwner {
                    disabledTargets.insert(ownerTarget)
                }
                removeCaptureIfOrphaned(layerID: binding.layerID)
            }
        }
        var eventCounts = candidateEvents.reduce(into: [SceneDynamicTarget: Int]()) {
            $0[$1.ownerTarget, default: 0] += 1
        }
        func record(
            _ kind: SceneScriptCursorEventKind,
            binding: SceneScriptCursorBinding,
            hit: SceneScriptCursorHit,
            callbackFrame: SceneScriptFrameInput,
            captureActive: Bool,
            currentHit: Bool
        ) {
            let target = binding.ownerTarget
            guard binding.events.contains(kind), !disabledTargets.contains(target) else { return }
            guard eventCounts[target, default: 0] < Self.maximumEventsPerOwner,
                  candidateEvents.count < Self.maximumPendingEvents else {
                failures[target] = .mutationOverflow("SceneScript cursor pending event budget exceeded")
                disabledTargets.insert(target)
                binding.owner.invalidate()
                candidateEvents.removeAll { $0.ownerTarget == target }
                binding.owner.discardLayerMutations()
                removeCaptureIfOrphaned(layerID: binding.layerID)
                return
            }
            candidateEvents.append(.init(ownerTarget: target, kind: kind, hit: hit,
                surface: callbackFrame.surface, captureActive: captureActive, currentHit: currentHit))
            eventCounts[target, default: 0] += 1
        }
        // Recognize the entire input batch before executing callbacks. A
        // recoverable enter/down failure must not erase later up/click edges.
        for sample in batch.samples {
            if let capturedSurfaceID, sample.surfaceID != capturedSurfaceID {
                capturedHits = [:]
                self.capturedSurfaceID = nil
            }
            let callbackFrame = SceneScriptFrameInput(
                replacingSurfaceOf: frame,
                with: sample.surface
            )
            let admittedHits = sample.hits.filter {
                ownerLayerIDs.contains($0.key) && hasActiveBinding(layerID: $0.key)
            }
            let admittedProjections = sample.ownerProjections.filter {
                ownerLayerIDs.contains($0.key) && hasActiveBinding(layerID: $0.key)
            }
            let changedSurface = sample.surfaceID != previousSurfaceID
            let leaving = changedSurface ? Set(previousHits.keys)
                : Set(previousHits.keys).subtracting(admittedHits.keys)
            let entering = changedSurface ? Set(admittedHits.keys)
                : Set(admittedHits.keys).subtracting(previousHits.keys)
            let pressed = sample.primaryButtonIsDown
                && !previousPrimaryButtonIsDown
            let released = !sample.primaryButtonIsDown
                && previousPrimaryButtonIsDown
            let moved = sample.pointerPosition != nil
                && previousPointerPosition != nil
                && (sample.pointerPosition != previousPointerPosition || changedSurface)
            for binding in bindings where !disabledTargets.contains(binding.ownerTarget) {
                if leaving.contains(binding.layerID),
                   let hit = previousHits[binding.layerID] {
                    record(
                        .leave, binding: binding, hit: hit,
                        callbackFrame: changedSurface ? .init(
                            replacingSurfaceOf: frame,
                            with: sample.leavingSurface ?? previousSurface
                        ) : callbackFrame,
                        captureActive: capturedHits[binding.layerID] != nil,
                        currentHit: false
                    )
                }
                if entering.contains(binding.layerID),
                   let hit = admittedHits[binding.layerID] {
                    record(
                        .enter, binding: binding, hit: hit,
                        callbackFrame: callbackFrame,
                        captureActive: capturedHits[binding.layerID] != nil,
                        currentHit: true
                    )
                }
                if pressed, let hit = admittedHits[binding.layerID] {
                    record(
                        .down, binding: binding, hit: hit,
                        callbackFrame: callbackFrame,
                        captureActive: false, currentHit: true
                    )
                    if hasActiveBinding(layerID: binding.layerID) {
                        capturedHits[binding.layerID] = hit
                    }
                }
                let captured = capturedHits[binding.layerID] != nil
                let moveHit = captured
                    ? admittedProjections[binding.layerID]
                    : admittedHits[binding.layerID]
                if moved, let hit = moveHit {
                    record(
                        .move, binding: binding, hit: hit,
                        callbackFrame: callbackFrame,
                        captureActive: captured,
                        currentHit: admittedHits[binding.layerID] != nil
                    )
                    if captured, hasActiveBinding(layerID: binding.layerID) {
                        capturedHits[binding.layerID] = hit
                    }
                }
                if released, let captured = capturedHits[binding.layerID] {
                    let releaseHit = admittedProjections[binding.layerID]
                        ?? captured
                    record(
                        .up, binding: binding, hit: releaseHit,
                        callbackFrame: callbackFrame,
                        captureActive: true,
                        currentHit: admittedHits[binding.layerID] != nil
                    )
                    if admittedHits[binding.layerID] != nil {
                        record(
                            .click, binding: binding, hit: releaseHit,
                            callbackFrame: callbackFrame,
                            captureActive: true, currentHit: true
                        )
                    }
                }
            }
            if pressed, !capturedHits.isEmpty { capturedSurfaceID = sample.surfaceID }
            if released { capturedHits = [:] }
            if capturedHits.isEmpty { capturedSurfaceID = nil }
            previousSurfaceID = sample.surfaceID
            previousSurface = sample.surface
            previousPointerPosition = sample.pointerPosition
            previousPrimaryButtonIsDown = sample.primaryButtonIsDown
            previousHits = admittedHits.filter {
                hasActiveBinding(layerID: $0.key)
            }
        }
        for event in candidateEvents {
            guard let binding = bindingsByTarget[event.ownerTarget] else { continue }
            emit(event.kind, binding: binding, hit: event.hit,
                callbackFrame: .init(replacingSurfaceOf: frame, with: event.surface),
                captureActive: event.captureActive, currentHit: event.currentHit)
        }
        for binding in bindings where !disabledTargets.contains(binding.ownerTarget) {
            if case let .failure(failure) = binding.owner.commitStorage() {
                discardCandidates(ownerTarget: binding.ownerTarget)
                // A borrowed cursor binding shares its vector owner's C
                // layer transaction.  Cursor runs before the vector pass;
                // discard immediately so a later vector finalizer cannot
                // commit a cursor callback that failed storage publication.
                binding.owner.discardLayerMutations()
                failures[binding.ownerTarget] = failure
                if failure.permanentlyDisablesOwner {
                    disabledTargets.insert(binding.ownerTarget)
                }
                removeCaptureIfOrphaned(layerID: binding.layerID)
            }
        }
        for binding in bindings where failures[binding.ownerTarget] != nil {
            binding.owner.discardStorage()
        }
        candidateFailures = Set(failures.keys)
        let ownerEffects = bindings.compactMap { binding in
            let effects = SceneScriptOwnerEffects(
                ownerTarget: binding.owner.target,
                materialFunctionMutations: materialFunctions.compactMap {
                    $0.ownerTarget == binding.ownerTarget ? $0.mutation : nil
                },
                animationMutations: animations.compactMap {
                    $0.ownerTarget == binding.ownerTarget ? $0.mutation : nil
                },
                layerMutations: layers.compactMap {
                    $0.ownerTarget == binding.ownerTarget ? $0.mutation : nil
                },
                videoCommands: videos.compactMap {
                    $0.ownerTarget == binding.ownerTarget ? $0.command : nil
                },
                textureAnimationCommands: textureAnimations.compactMap {
                    $0.ownerTarget == binding.ownerTarget ? $0.command : nil
                },
                puppetBoneMutations: puppetBones.compactMap {
                    $0.ownerTarget == binding.ownerTarget ? $0.mutation : nil
                }
            )
            return effects.isEmpty ? nil : effects
        }
        return .init(
            failures: failures,
            materialFunctionMutations: materialFunctions.map { $0.mutation },
            animationMutations: animations.map { $0.mutation },
            layerMutations: layers.map { $0.mutation },
            inputBatchOverflowed: false,
            ownerEffects: ownerEffects
        )
    }

    private func synchronize(
        hits: [Int: SceneScriptCursorHit],
        pointerPosition: SIMD2<Float>?,
        primaryButtonIsDown: Bool,
        surfaceID: UInt32? = nil,
        surface: SceneScriptSurfaceInput? = nil
    ) {
        previousHits = hits.filter { entry in
            ownerLayerIDs.contains(entry.key)
                && (bindingsByLayer[entry.key] ?? []).contains { binding in
                    !disabledTargets.contains(binding.ownerTarget)
                }
        }
        previousPointerPosition = pointerPosition
        previousPrimaryButtonIsDown = primaryButtonIsDown
        capturedHits = [:]
        capturedSurfaceID = nil
        previousSurfaceID = surfaceID
        previousSurface = surface
    }

    func finalizeLayerMutations(
        committing: Bool,
        rejectedOwnerTargets: Set<SceneDynamicTarget> = []
    ) {
        if committing && hasCandidateDispatch {
            let rejected = rejectedOwnerTargets.union(candidateFailures)
            pendingEvents = candidateEvents.filter {
                rejected.contains($0.ownerTarget) && !disabledTargets.contains($0.ownerTarget)
            }
        } else {
            pendingEvents.removeAll { disabledTargets.contains($0.ownerTarget) }
        }
        clearCandidateEvents()
        // Event confirmation covers borrowed owners too. Their C transaction
        // is still finalized exactly once by the vector program below the Host.
        bindings.forEach { binding in
            guard binding.ownsOwner else { return }
            let target = binding.owner.target
            let rejected = rejectedOwnerTargets.contains(target)
            if committing && !rejected && !disabledTargets.contains(target) {
                binding.owner.commitLayerMutations()
            } else {
                binding.owner.discardLayerMutations()
            }
        }
    }

    private func clearCandidateEvents() {
        candidateEvents.removeAll(keepingCapacity: true)
        candidateFailures.removeAll(keepingCapacity: true)
        hasCandidateDispatch = false
    }

    func invalidate() {
        bindings.filter(\.ownsOwner).forEach { $0.owner.invalidate() }
        previousHits = [:]
        capturedHits = [:]
        capturedSurfaceID = nil
        previousSurfaceID = nil
        previousSurface = nil
        previousPointerPosition = nil
        previousPrimaryButtonIsDown = false
        pendingEvents.removeAll(keepingCapacity: true)
        clearCandidateEvents()
    }

    func teardown(
        frame: SceneScriptFrameInput,
        userPropertiesJSON: String
    ) -> [SceneScriptOwnerTeardownOutcome] {
        let outcomes = bindings.filter(\.ownsOwner).map {
            $0.owner.teardown(
                frame: frame,
                scriptPropertiesJSON: "",
                userPropertiesJSON: userPropertiesJSON
            )
        }
        previousHits = [:]
        capturedHits = [:]
        capturedSurfaceID = nil
        previousSurfaceID = nil
        previousSurface = nil
        previousPointerPosition = nil
        previousPrimaryButtonIsDown = false
        pendingEvents.removeAll(keepingCapacity: true)
        clearCandidateEvents()
        return outcomes
    }

    static func exportedEvents(
        _ owner: SceneScriptValueOwner
    ) -> Set<SceneScriptCursorEventKind> {
        owner.exportedCursorEvents
    }

}
