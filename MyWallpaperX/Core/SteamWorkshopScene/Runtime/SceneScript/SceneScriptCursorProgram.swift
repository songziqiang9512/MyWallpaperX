import Foundation

nonisolated struct SceneScriptCursorHit: Equatable, Sendable {
    let layerID: Int
    let worldPosition: SIMD3<Double>
    let localPosition: SIMD3<Double>
}

nonisolated struct SceneScriptCursorFrameResult: Equatable, Sendable {
    let failures: [Int: SceneScriptScalarRuntimeFailure]
    let materialFunctionMutations: [SceneScriptMaterialFunctionMutation]
    let animationMutations: [SceneTimelinePlaybackMutation]
    let layerMutations: [SceneScriptLayerMutation]
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
        hits: [Int: SceneScriptCursorHit],
        primaryButtonIsDown: Bool,
        frame: SceneScriptFrameInput,
        userPropertiesJSON: String,
        interruptBudget: UInt64? = nil
    ) -> SceneScriptCursorFrameResult {
        let admittedHits = hits.filter {
            ownerLayerIDs.contains($0.key) && !disabledLayerIDs.contains($0.key)
        }
        let leaving = Set(previousHits.keys).subtracting(admittedHits.keys)
        let entering = Set(admittedHits.keys).subtracting(previousHits.keys)
        let pressed = primaryButtonIsDown && !previousPrimaryButtonIsDown
        let released = !primaryButtonIsDown && previousPrimaryButtonIsDown
        var failures: [Int: SceneScriptScalarRuntimeFailure] = [:]
        var materialFunctions: [SceneScriptMaterialFunctionMutation] = []
        var animations: [SceneTimelinePlaybackMutation] = []
        var layers: [SceneScriptLayerMutation] = []
        func emit(
            _ kind: SceneScriptCursorEventKind,
            binding: SceneScriptCursorBinding,
            hit: SceneScriptCursorHit
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
                event, frame: frame, userPropertiesJSON: userPropertiesJSON,
                interruptBudget: interruptBudget
            ) {
            case let .success(mutations):
                materialFunctions.append(contentsOf: mutations.materialFunctions)
                animations.append(contentsOf: mutations.animations)
                layers.append(contentsOf: mutations.layers)
                NSLog(
                    "MWX SceneScript VM: layerID=%d event=%@ route=generic-only",
                    binding.layerID, kind.callbackName
                )
            case let .failure(failure):
                failures[binding.layerID] = failure
                disabledLayerIDs.insert(binding.layerID)
            }
        }
        for binding in bindings where !disabledLayerIDs.contains(binding.layerID) {
            if leaving.contains(binding.layerID), let hit = previousHits[binding.layerID] {
                emit(.leave, binding: binding, hit: hit)
            }
            if entering.contains(binding.layerID), let hit = admittedHits[binding.layerID] {
                emit(.enter, binding: binding, hit: hit)
            }
            if pressed, let hit = admittedHits[binding.layerID] {
                emit(.down, binding: binding, hit: hit)
                if !disabledLayerIDs.contains(binding.layerID) {
                    capturedHits[binding.layerID] = hit
                }
            }
            if released, let captured = capturedHits[binding.layerID] {
                let releaseHit = admittedHits[binding.layerID] ?? captured
                emit(.up, binding: binding, hit: releaseHit)
                if admittedHits[binding.layerID] != nil {
                    emit(.click, binding: binding, hit: releaseHit)
                }
            }
        }
        if released { capturedHits = [:] }
        previousPrimaryButtonIsDown = primaryButtonIsDown
        previousHits = admittedHits.filter {
            !disabledLayerIDs.contains($0.key)
        }
        return .init(
            failures: failures,
            materialFunctionMutations: materialFunctions,
            animationMutations: animations,
            layerMutations: layers
        )
    }

    func invalidate() {
        bindings.filter(\.ownsOwner).forEach { $0.owner.invalidate() }
        previousHits = [:]
        capturedHits = [:]
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
            (.down, "cursorDown"), (.up, "cursorUp"), (.click, "cursorClick"),
        ]
        return Set(pairs.compactMap { owner.exports($0.1) ? $0.0 : nil })
    }

    private static func validHitLayer(
        _ layer: SceneRenderDescriptor.Layer
    ) -> Bool {
        guard let origin = layer.originXYZ, origin.count == 3,
              let size = layer.sizeWH, size.count == 2,
              let scale = layer.scaleXYZ, scale.count == 3,
              (layer.anglesXYZ?.count ?? 3) == 3,
              (layer.parallaxDepthXY?.count ?? 2) == 2 else { return false }
        let angles = layer.anglesXYZ ?? [0, 0, 0]
        let parallax = layer.parallaxDepthXY ?? [0, 0]
        return origin.allSatisfy(\.isFinite)
            && size.allSatisfy { $0.isFinite && $0 > 0 }
            && scale.allSatisfy { $0.isFinite && $0 > 0 }
            && angles.allSatisfy { $0.bitPattern == Float(0).bitPattern }
            && parallax.allSatisfy { $0.bitPattern == Float(0).bitPattern }
    }
}
