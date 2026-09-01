import Foundation

nonisolated struct SceneScriptCursorHit: Equatable, Sendable {
    let layerID: Int
    let worldPosition: SIMD3<Double>
    let localPosition: SIMD3<Double>
}

nonisolated struct SceneScriptCursorFrameSample: Equatable, Sendable {
    let hits: [Int: SceneScriptCursorHit]
    let ownerProjections: [Int: SceneScriptCursorHit]
    let pointerPosition: SIMD2<Float>?
    let primaryButtonIsDown: Bool
    let surface: SceneScriptSurfaceInput?

    init(
        hits: [Int: SceneScriptCursorHit],
        ownerProjections: [Int: SceneScriptCursorHit]? = nil,
        pointerPosition: SIMD2<Float>? = nil,
        primaryButtonIsDown: Bool,
        surface: SceneScriptSurfaceInput? = nil
    ) {
        self.hits = hits
        self.ownerProjections = ownerProjections ?? hits
        self.pointerPosition = pointerPosition
        self.primaryButtonIsDown = primaryButtonIsDown
        self.surface = surface
    }
}

nonisolated struct SceneScriptCursorFrameBatch: Equatable, Sendable {
    let samples: [SceneScriptCursorFrameSample]
    let overflowed: Bool
}

nonisolated struct SceneScriptCursorFrameResult: Equatable, Sendable {
    let failures: [Int: SceneScriptScalarRuntimeFailure]
    let materialFunctionMutations: [SceneScriptMaterialFunctionMutation]
    let animationMutations: [SceneTimelinePlaybackMutation]
    let layerMutations: [SceneScriptLayerMutation]
    let inputBatchOverflowed: Bool
}

nonisolated struct SceneScriptCursorProgramConstruction: @unchecked Sendable {
    let program: SceneScriptCursorProgram
    let requestedLayerIDs: Set<Int>
    let instantiatedLayerIDs: Set<Int>
    let failures: [Int: SceneScriptScalarRuntimeFailure]

    var deferredLayerIDs: Set<Int> {
        requestedLayerIDs.subtracting(instantiatedLayerIDs).subtracting(failures.keys)
    }
}

private nonisolated struct SceneScriptCursorBinding: @unchecked Sendable {
    let layerID: Int
    let authoredOrder: Int
    let owner: SceneScriptVectorOwner
    let events: Set<SceneScriptCursorEventKind>
    let ownsOwner: Bool
}

private nonisolated struct SceneScriptCursorAuthoredMutationKey: Hashable {
    let ownerLayerID: Int
    let targetLayerID: Int
}

/// Executes authored cursor callbacks against the shared scene VM. Hit
/// testing remains a typed host responsibility; JavaScript receives immutable
/// world/local positions and can only publish through existing mutation paths.
nonisolated final class SceneScriptCursorProgram: @unchecked Sendable {
    private let bindings: [SceneScriptCursorBinding]
    private let generation: UInt64
    private var previousHits: [Int: SceneScriptCursorHit] = [:]
    private var capturedHits: [Int: SceneScriptCursorHit] = [:]
    private var previousPointerPosition: SIMD2<Float>?
    private var previousPrimaryButtonIsDown = false
    private var disabledLayerIDs: Set<Int> = []

    var ownerLayerIDs: Set<Int> { Set(bindings.map(\.layerID)) }
    var capturedOwnerLayerIDs: Set<Int> { Set(capturedHits.keys) }
    var ownerCount: Int { bindings.count }

    private init(
        bindings: [SceneScriptCursorBinding],
        generation: UInt64
    ) {
        self.bindings = bindings
        self.generation = generation
    }

    static func compile(
        domain: SceneScriptQuickJSDomain?,
        descriptor: SceneRenderDescriptor,
        scriptBindings: [SceneScriptBindingIR],
        borrowedOwners: [SceneScriptCursorOwnerRegistration] = [],
        generation: UInt64,
        budget: SceneScriptScalarBudget = .default
    ) -> SceneScriptCursorProgram {
        compileCandidate(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: scriptBindings,
            borrowedOwners: borrowedOwners,
            rejectedLayerIDs: [],
            generation: generation,
            budget: budget
        ).program
    }

    static func compileCandidate(
        domain: SceneScriptQuickJSDomain?,
        descriptor: SceneRenderDescriptor,
        scriptBindings: [SceneScriptBindingIR],
        borrowedOwners: [SceneScriptCursorOwnerRegistration] = [],
        rejectedLayerIDs: Set<Int>,
        generation: UInt64,
        budget: SceneScriptScalarBudget = .default
    ) -> SceneScriptCursorProgramConstruction {
        let standaloneCandidates = projectedStandaloneCandidates(
            descriptor: descriptor,
            scriptBindings: scriptBindings
        ).filter { !rejectedLayerIDs.contains($0.identity.layerID) }
        let borrowedBindings = projectedBorrowedBindings(
            descriptor: descriptor,
            borrowedOwners: borrowedOwners
        ).filter { !rejectedLayerIDs.contains($0.layerID) }
        let borrowedCounts = Dictionary(
            grouping: borrowedBindings,
            by: \.layerID
        ).mapValues(\.count)
        var candidateCounts = Dictionary(
            grouping: standaloneCandidates,
            by: { $0.identity.layerID }
        ).mapValues(\.count)
        for binding in borrowedBindings {
            candidateCounts[binding.layerID, default: 0] += 1
        }
        let collisionLayerIDs: Set<Int> = Set(candidateCounts.compactMap {
            layerID, count -> Int? in
            guard count > 1, borrowedCounts[layerID] != nil else { return nil }
            return layerID
        })
        let requestedCandidates = standaloneCandidates.filter {
            candidateCounts[$0.identity.layerID] == 1
        }.sorted { $0.identity.authoredOrder < $1.identity.authoredOrder }
        let requestedLayerIDs = Set(
            requestedCandidates.map { $0.identity.layerID }
        ).union(collisionLayerIDs)
        guard let domain else {
            return failedConstruction(
                requestedLayerIDs: requestedLayerIDs,
                generation: generation,
                failure: .invalidArgument("QuickJS domain unavailable")
            )
        }
        do {
            try domain.configureLayerCatalog(descriptor)
        } catch {
            return failedConstruction(
                requestedLayerIDs: requestedLayerIDs,
                generation: generation,
                failure: (error as? SceneScriptScalarRuntimeFailure)
                    ?? .invalidArgument(String(describing: error))
            )
        }

        var bindings = borrowedBindings.filter {
            candidateCounts[$0.layerID] == 1
        }
        var instantiatedLayerIDs: Set<Int> = []
        let collisionFailure = SceneScriptScalarRuntimeFailure.invalidArgument(
            "SceneScript cursor owner collision"
        )
        var failures: [Int: SceneScriptScalarRuntimeFailure] = Dictionary(
            uniqueKeysWithValues:
            collisionLayerIDs.map { ($0, collisionFailure) }
        )
        for candidate in requestedCandidates {
            let layerID = candidate.identity.layerID
            let owner: SceneScriptVectorOwner
            do {
                owner = try SceneScriptVectorOwner(
                    domain: domain,
                    source: candidate.source,
                    target: .layer(layerID: layerID, field: .visibility),
                    effectNames: [],
                    generation: generation,
                    budget: budget
                )
            } catch let failure as SceneScriptScalarRuntimeFailure {
                failures[layerID] = failure
                break
            } catch {
                failures[layerID] = .invalidArgument(String(describing: error))
                break
            }
            let events = exportedEvents(owner)
            guard !events.isEmpty else {
                failures[layerID] = .invalidSource
                break
            }
            bindings.append(.init(
                layerID: layerID,
                authoredOrder: candidate.identity.authoredOrder,
                owner: owner,
                events: events,
                ownsOwner: true
            ))
            instantiatedLayerIDs.insert(layerID)
        }
        bindings.sort { $0.authoredOrder < $1.authoredOrder }
        return .init(
            program: .init(bindings: bindings, generation: generation),
            requestedLayerIDs: requestedLayerIDs,
            instantiatedLayerIDs: instantiatedLayerIDs,
            failures: failures
        )
    }

    static func projectedStandaloneLayerIDs(
        descriptor: SceneRenderDescriptor,
        scriptBindings: [SceneScriptBindingIR]
    ) -> Set<Int> {
        let candidates = projectedStandaloneCandidates(
            descriptor: descriptor,
            scriptBindings: scriptBindings
        )
        let counts = Dictionary(
            grouping: candidates,
            by: { $0.identity.layerID }
        ).mapValues(\.count)
        return Set(candidates.compactMap { candidate in
            counts[candidate.identity.layerID] == 1
                ? candidate.identity.layerID : nil
        })
    }

    static func projectedStandaloneOwnerSources(
        descriptor: SceneRenderDescriptor,
        scriptBindings: [SceneScriptBindingIR]
    ) -> [String] {
        let candidates = projectedStandaloneCandidates(
            descriptor: descriptor,
            scriptBindings: scriptBindings
        )
        let counts = Dictionary(
            grouping: candidates,
            by: { $0.identity.layerID }
        ).mapValues(\.count)
        return candidates.compactMap { candidate in
            counts[candidate.identity.layerID] == 1 ? candidate.source : nil
        }
    }

    func dispatch(
        batch: SceneScriptCursorFrameBatch,
        frame: SceneScriptFrameInput,
        userPropertiesJSON: String,
        interruptBudget: UInt64? = nil
    ) -> SceneScriptCursorFrameResult {
        defer {
            bindings.forEach {
                $0.owner.clearCursorAuthoredTransformBaseline()
            }
        }
        if batch.overflowed {
            if let latest = batch.samples.last {
                synchronize(
                    hits: latest.hits,
                    pointerPosition: latest.pointerPosition,
                    primaryButtonIsDown: latest.primaryButtonIsDown
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
        var failures: [Int: SceneScriptScalarRuntimeFailure] = [:]
        var materialFunctions: [(
            ownerLayerID: Int,
            mutation: SceneScriptMaterialFunctionMutation
        )] = []
        var animations: [(
            ownerLayerID: Int,
            mutation: SceneTimelinePlaybackMutation
        )] = []
        var layers: [(
            ownerLayerID: Int,
            mutation: SceneScriptLayerMutation
        )] = []
        var authoredBaselines: [Int: SceneScriptLayerMutation] = [:]
        var authoredMutationIndices: [
            SceneScriptCursorAuthoredMutationKey: Int
        ] = [:]
        func discardCandidates(ownerLayerID: Int) {
            materialFunctions.removeAll { $0.ownerLayerID == ownerLayerID }
            animations.removeAll { $0.ownerLayerID == ownerLayerID }
            layers.removeAll { $0.ownerLayerID == ownerLayerID }
            authoredBaselines.removeValue(forKey: ownerLayerID)
            authoredMutationIndices = [:]
            for (index, candidate) in layers.enumerated()
                where !candidate.mutation.isDynamic
                    && candidate.mutation.kind == .upsert {
                authoredMutationIndices[.init(
                    ownerLayerID: candidate.ownerLayerID,
                    targetLayerID: candidate.mutation.layerID
                )] = index
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
            guard binding.events.contains(kind),
                  !disabledLayerIDs.contains(binding.layerID) else { return }
            let event = SceneScriptCursorEventInput(
                kind: kind,
                layerID: binding.layerID,
                worldPosition: hit.worldPosition,
                localPosition: hit.localPosition
            )
            switch binding.owner.dispatchCursor(
                event, frame: callbackFrame,
                userPropertiesJSON: userPropertiesJSON,
                authoredTransformBaseline: authoredBaselines[binding.layerID],
                interruptBudget: interruptBudget
            ) {
            case let .success(mutations):
                materialFunctions.append(contentsOf: mutations.materialFunctions.map {
                    (binding.layerID, $0)
                })
                animations.append(contentsOf: mutations.animations.map {
                    (binding.layerID, $0)
                })
                for mutation in mutations.layers {
                    guard !mutation.isDynamic, mutation.kind == .upsert else {
                        layers.append((binding.layerID, mutation))
                        continue
                    }
                    let key = SceneScriptCursorAuthoredMutationKey(
                        ownerLayerID: binding.layerID,
                        targetLayerID: mutation.layerID
                    )
                    if let index = authoredMutationIndices[key] {
                        layers[index].mutation = Self.mergingAuthoredMutation(
                            layers[index].mutation, with: mutation
                        )
                    } else {
                        authoredMutationIndices[key] = layers.count
                        layers.append((binding.layerID, mutation))
                    }
                    authoredBaselines[binding.layerID] = authoredBaselines[
                        binding.layerID
                    ].map {
                        Self.mergingAuthoredMutation($0, with: mutation)
                    } ?? mutation
                }
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
                discardCandidates(ownerLayerID: binding.layerID)
                failures[binding.layerID] = failure
                disabledLayerIDs.insert(binding.layerID)
                capturedHits.removeValue(forKey: binding.layerID)
            }
        }
        for sample in batch.samples {
            let callbackFrame = SceneScriptFrameInput(
                replacingSurfaceOf: frame,
                with: sample.surface
            )
            let admittedHits = sample.hits.filter {
                ownerLayerIDs.contains($0.key)
                    && !disabledLayerIDs.contains($0.key)
            }
            let admittedProjections = sample.ownerProjections.filter {
                ownerLayerIDs.contains($0.key)
                    && !disabledLayerIDs.contains($0.key)
            }
            let leaving = Set(previousHits.keys).subtracting(admittedHits.keys)
            let entering = Set(admittedHits.keys).subtracting(previousHits.keys)
            let pressed = sample.primaryButtonIsDown
                && !previousPrimaryButtonIsDown
            let released = !sample.primaryButtonIsDown
                && previousPrimaryButtonIsDown
            let moved = sample.pointerPosition != nil
                && previousPointerPosition != nil
                && sample.pointerPosition != previousPointerPosition
            for binding in bindings where !disabledLayerIDs.contains(binding.layerID) {
                if leaving.contains(binding.layerID),
                   let hit = previousHits[binding.layerID] {
                    emit(
                        .leave, binding: binding, hit: hit,
                        callbackFrame: callbackFrame,
                        captureActive: capturedHits[binding.layerID] != nil,
                        currentHit: false
                    )
                }
                if entering.contains(binding.layerID),
                   let hit = admittedHits[binding.layerID] {
                    emit(
                        .enter, binding: binding, hit: hit,
                        callbackFrame: callbackFrame,
                        captureActive: capturedHits[binding.layerID] != nil,
                        currentHit: true
                    )
                }
                if pressed, let hit = admittedHits[binding.layerID] {
                    emit(
                        .down, binding: binding, hit: hit,
                        callbackFrame: callbackFrame,
                        captureActive: false, currentHit: true
                    )
                    if !disabledLayerIDs.contains(binding.layerID) {
                        capturedHits[binding.layerID] = hit
                    }
                }
                let captured = capturedHits[binding.layerID] != nil
                let moveHit = captured
                    ? admittedProjections[binding.layerID]
                    : admittedHits[binding.layerID]
                if moved, let hit = moveHit {
                    emit(
                        .move, binding: binding, hit: hit,
                        callbackFrame: callbackFrame,
                        captureActive: captured,
                        currentHit: admittedHits[binding.layerID] != nil
                    )
                    if captured, !disabledLayerIDs.contains(binding.layerID) {
                        capturedHits[binding.layerID] = hit
                    }
                }
                if released, let captured = capturedHits[binding.layerID] {
                    let releaseHit = admittedProjections[binding.layerID]
                        ?? captured
                    emit(
                        .up, binding: binding, hit: releaseHit,
                        callbackFrame: callbackFrame,
                        captureActive: true,
                        currentHit: admittedHits[binding.layerID] != nil
                    )
                    if admittedHits[binding.layerID] != nil {
                        emit(
                            .click, binding: binding, hit: releaseHit,
                            callbackFrame: callbackFrame,
                            captureActive: true, currentHit: true
                        )
                    }
                }
            }
            if released { capturedHits = [:] }
            previousPointerPosition = sample.pointerPosition
            previousPrimaryButtonIsDown = sample.primaryButtonIsDown
            previousHits = admittedHits.filter {
                !disabledLayerIDs.contains($0.key)
            }
        }
        for binding in bindings where !disabledLayerIDs.contains(binding.layerID) {
            if case let .failure(failure) = binding.owner.commitStorage() {
                discardCandidates(ownerLayerID: binding.layerID)
                failures[binding.layerID] = failure
                disabledLayerIDs.insert(binding.layerID)
                capturedHits.removeValue(forKey: binding.layerID)
            }
        }
        for binding in bindings where failures[binding.layerID] != nil {
            binding.owner.discardStorage()
        }
        return .init(
            failures: failures,
            materialFunctionMutations: materialFunctions.map { $0.mutation },
            animationMutations: animations.map { $0.mutation },
            layerMutations: layers.map { $0.mutation },
            inputBatchOverflowed: false
        )
    }

    private static func mergingAuthoredMutation(
        _ previous: SceneScriptLayerMutation,
        with current: SceneScriptLayerMutation
    ) -> SceneScriptLayerMutation {
        .init(
            kind: current.kind,
            isDynamic: false,
            fields: previous.fields.union(current.fields),
            layerID: current.layerID,
            orderIndex: current.orderIndex,
            visible: current.visible,
            alpha: current.alpha,
            origin: current.fields.contains(.origin)
                ? current.origin : previous.origin,
            scale: current.fields.contains(.scale)
                ? current.scale : previous.scale,
            angles: current.fields.contains(.angles)
                ? current.angles : previous.angles,
            color: current.color,
            pointSize: current.pointSize,
            text: current.text,
            font: current.font,
            assetPath: current.assetPath
        )
    }

    private func synchronize(
        hits: [Int: SceneScriptCursorHit],
        pointerPosition: SIMD2<Float>?,
        primaryButtonIsDown: Bool
    ) {
        previousHits = hits.filter {
            ownerLayerIDs.contains($0.key) && !disabledLayerIDs.contains($0.key)
        }
        previousPointerPosition = pointerPosition
        previousPrimaryButtonIsDown = primaryButtonIsDown
        capturedHits = [:]
    }

    func invalidate() {
        bindings.filter(\.ownsOwner).forEach { $0.owner.invalidate() }
        previousHits = [:]
        capturedHits = [:]
        previousPointerPosition = nil
        previousPrimaryButtonIsDown = false
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
        previousPointerPosition = nil
        previousPrimaryButtonIsDown = false
        return outcomes
    }

    private struct OwnerIdentity {
        let layerID: Int
        let authoredOrder: Int
    }

    private struct StandaloneCandidate {
        let source: String
        let identity: OwnerIdentity
    }

    private static func projectedStandaloneCandidates(
        descriptor: SceneRenderDescriptor,
        scriptBindings: [SceneScriptBindingIR]
    ) -> [StandaloneCandidate] {
        scriptBindings.compactMap { binding in
            ownerIdentity(binding, descriptor: descriptor).map {
                .init(source: binding.source, identity: $0)
            }
        }
    }

    private static func projectedBorrowedBindings(
        descriptor: SceneRenderDescriptor,
        borrowedOwners: [SceneScriptCursorOwnerRegistration]
    ) -> [SceneScriptCursorBinding] {
        borrowedOwners.compactMap { registration in
            guard let layer = descriptor.layers.first(where: {
                $0.id == registration.layerID
            }), validHitLayer(layer) else { return nil }
            let events = exportedEvents(registration.owner)
            guard !events.isEmpty else { return nil }
            return .init(
                layerID: registration.layerID,
                authoredOrder: registration.authoredOrder,
                owner: registration.owner,
                events: events,
                ownsOwner: false
            )
        }
    }

    private static func failedConstruction(
        requestedLayerIDs: Set<Int>,
        generation: UInt64,
        failure: SceneScriptScalarRuntimeFailure
    ) -> SceneScriptCursorProgramConstruction {
        .init(
            program: .init(bindings: [], generation: generation),
            requestedLayerIDs: requestedLayerIDs,
            instantiatedLayerIDs: [],
            failures: Dictionary(uniqueKeysWithValues:
                requestedLayerIDs.map { ($0, failure) }
            )
        )
    }

    private static func ownerIdentity(
        _ binding: SceneScriptBindingIR,
        descriptor: SceneRenderDescriptor
    ) -> OwnerIdentity? {
        guard binding.owner.kind == .object,
              binding.targetKey == "visible",
              binding.wrapperKeys == ["script", "value"]
                || binding.wrapperKeys == ["script", "user", "value"],
              binding.valueType == .boolean,
              binding.properties.isEmpty,
              let authored = binding.authoredValue?.boolValue,
              let index = binding.owner.objectIndex,
              let layerID = binding.owner.objectID,
              descriptor.layers.indices.contains(index) else { return nil }
        let layer = descriptor.layers[index]
        guard layer.id == layerID,
              layer.layerIndex == index,
              layer.visible == authored,
              binding.targetPath == [
                  .key("objects"), .index(index), .key("visible"),
              ],
              layer.contentKind == "composition",
              layer.utilityLayer?.kind == .composition,
              layer.utilityLayer?.copyBackground == false,
              layer.utilityLayer?.passthrough == false,
              layer.parentID == nil,
              layer.childLayerIDs.isEmpty,
              layer.effects.isEmpty,
              layer.effectFiles.isEmpty,
              validHitLayer(layer) else { return nil }
        return .init(layerID: layerID, authoredOrder: index)
    }

    private static func exportedEvents(
        _ owner: SceneScriptVectorOwner
    ) -> Set<SceneScriptCursorEventKind> {
        owner.exportedCursorEvents
    }

    private static func validHitLayer(
        _ layer: SceneRenderDescriptor.Layer
    ) -> Bool {
        guard let origin = layer.originXYZ, origin.count == 3,
              let size = layer.sizeWH, size.count == 2,
              (layer.scaleXYZ?.count ?? 3) == 3,
              (layer.anglesXYZ?.count ?? 3) == 3,
              (layer.parallaxDepthXY?.count ?? 2) == 2 else { return false }
        let scale = layer.scaleXYZ ?? [1, 1, 1]
        let angles = layer.anglesXYZ ?? [0, 0, 0]
        let parallax = layer.parallaxDepthXY ?? [0, 0]
        return origin.allSatisfy(\.isFinite)
            && size.allSatisfy { $0.isFinite && $0 > 0 }
            && scale.allSatisfy { $0.isFinite && $0 > 0 }
            && angles.allSatisfy { $0.bitPattern == Float(0).bitPattern }
            && parallax.allSatisfy { $0.bitPattern == Float(0).bitPattern }
    }
}
