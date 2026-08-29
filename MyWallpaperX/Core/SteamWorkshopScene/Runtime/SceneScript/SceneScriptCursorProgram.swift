import Foundation

nonisolated struct SceneScriptCursorHit: Equatable, Sendable {
    let layerID: Int
    let worldPosition: SIMD3<Double>
    let localPosition: SIMD3<Double>
}

nonisolated struct SceneScriptCursorFrameSample: Equatable, Sendable {
    let hits: [Int: SceneScriptCursorHit]
    let pointerPosition: SIMD2<Float>?
    let primaryButtonIsDown: Bool
    let surface: SceneScriptSurfaceInput?

    init(
        hits: [Int: SceneScriptCursorHit],
        pointerPosition: SIMD2<Float>? = nil,
        primaryButtonIsDown: Bool,
        surface: SceneScriptSurfaceInput? = nil
    ) {
        self.hits = hits
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

private nonisolated struct SceneScriptCursorBinding: @unchecked Sendable {
    let layerID: Int
    let authoredOrder: Int
    let owner: SceneScriptVectorOwner
    let events: Set<SceneScriptCursorEventKind>
    let ownsOwner: Bool
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
        guard let domain,
              (try? domain.configureLayerCatalog(descriptor)) != nil else {
            return .init(bindings: [], generation: generation)
        }
        var candidates = borrowedOwners.compactMap { registration -> SceneScriptCursorBinding? in
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
        for binding in scriptBindings {
            guard let identity = ownerIdentity(
                binding,
                descriptor: descriptor
            ), let owner = try? SceneScriptVectorOwner(
                domain: domain,
                source: binding.source,
                target: .layer(layerID: identity.layerID, field: .visibility),
                effectNames: [],
                generation: generation,
                budget: budget
            ) else { continue }
            let events = exportedEvents(owner)
            guard !events.isEmpty else { continue }
            candidates.append(.init(
                layerID: identity.layerID,
                authoredOrder: identity.authoredOrder,
                owner: owner,
                events: events,
                ownsOwner: true
            ))
        }
        let counts = Dictionary(grouping: candidates, by: \.layerID)
            .mapValues(\.count)
        let admitted = candidates.filter { counts[$0.layerID] == 1 }
            .sorted { $0.authoredOrder < $1.authoredOrder }
        return .init(bindings: admitted, generation: generation)
    }

    func dispatch(
        batch: SceneScriptCursorFrameBatch,
        frame: SceneScriptFrameInput,
        userPropertiesJSON: String,
        interruptBudget: UInt64? = nil
    ) -> SceneScriptCursorFrameResult {
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
        var materialFunctions: [SceneScriptMaterialFunctionMutation] = []
        var animations: [SceneTimelinePlaybackMutation] = []
        var layers: [SceneScriptLayerMutation] = []
        func emit(
            _ kind: SceneScriptCursorEventKind,
            binding: SceneScriptCursorBinding,
            hit: SceneScriptCursorHit,
            callbackFrame: SceneScriptFrameInput
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
                interruptBudget: interruptBudget
            ) {
            case let .success(mutations):
                materialFunctions.append(contentsOf: mutations.materialFunctions)
                animations.append(contentsOf: mutations.animations)
                layers.append(contentsOf: mutations.layers)
                for mutation in mutations.layers
                    where mutation.fields.contains(.origin) {
                    NSLog(
                        "MWX SceneScript VM: layerID=%d event=%@ mutation=origin value=%.6f,%.6f,%.6f route=generic-only",
                        mutation.layerID, kind.callbackName,
                        mutation.origin.x, mutation.origin.y, mutation.origin.z
                    )
                }
                NSLog(
                    "MWX SceneScript VM: layerID=%d event=%@ route=generic-only",
                    binding.layerID, kind.callbackName
                )
            case let .failure(failure):
                failures[binding.layerID] = failure
                disabledLayerIDs.insert(binding.layerID)
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
                        callbackFrame: callbackFrame
                    )
                }
                if entering.contains(binding.layerID),
                   let hit = admittedHits[binding.layerID] {
                    emit(
                        .enter, binding: binding, hit: hit,
                        callbackFrame: callbackFrame
                    )
                }
                if pressed, let hit = admittedHits[binding.layerID] {
                    emit(
                        .down, binding: binding, hit: hit,
                        callbackFrame: callbackFrame
                    )
                    if !disabledLayerIDs.contains(binding.layerID) {
                        capturedHits[binding.layerID] = hit
                    }
                }
                if moved, let hit = admittedHits[binding.layerID] {
                    emit(
                        .move, binding: binding, hit: hit,
                        callbackFrame: callbackFrame
                    )
                }
                if released, let captured = capturedHits[binding.layerID] {
                    let releaseHit = admittedHits[binding.layerID] ?? captured
                    emit(
                        .up, binding: binding, hit: releaseHit,
                        callbackFrame: callbackFrame
                    )
                    if admittedHits[binding.layerID] != nil {
                        emit(
                            .click, binding: binding, hit: releaseHit,
                            callbackFrame: callbackFrame
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
        return .init(
            failures: failures,
            materialFunctionMutations: materialFunctions,
            animationMutations: animations,
            layerMutations: layers,
            inputBatchOverflowed: false
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
        let pairs: [(SceneScriptCursorEventKind, String)] = [
            (.enter, "cursorEnter"), (.leave, "cursorLeave"),
            (.down, "cursorDown"), (.move, "cursorMove"),
            (.up, "cursorUp"), (.click, "cursorClick"),
        ]
        return Set(pairs.compactMap { owner.exports($0.1) ? $0.0 : nil })
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
