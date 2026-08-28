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
}

private nonisolated struct SceneScriptCursorBinding: @unchecked Sendable {
    let layerID: Int
    let authoredOrder: Int
    let owner: SceneScriptVectorOwner
}

/// Executes authored enter/leave callbacks against the shared scene VM. Hit
/// testing remains a typed host responsibility; JavaScript receives immutable
/// world/local positions and can only publish through existing mutation paths.
nonisolated final class SceneScriptCursorProgram: @unchecked Sendable {
    private let bindings: [SceneScriptCursorBinding]
    private let generation: UInt64
    private var previousHits: [Int: SceneScriptCursorHit] = [:]
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
        generation: UInt64,
        budget: SceneScriptScalarBudget = .default
    ) -> SceneScriptCursorProgram {
        guard let domain,
              (try? domain.configureLayerCatalog(descriptor)) != nil else {
            return .init(bindings: [], generation: generation)
        }
        var candidates: [SceneScriptCursorBinding] = []
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
            guard owner.exports("cursorEnter"), owner.exports("cursorLeave") else {
                continue
            }
            candidates.append(.init(
                layerID: identity.layerID,
                authoredOrder: identity.authoredOrder,
                owner: owner
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
        frame: SceneScriptFrameInput,
        userPropertiesJSON: String,
        interruptBudget: UInt64? = nil
    ) -> SceneScriptCursorFrameResult {
        let admittedHits = hits.filter {
            ownerLayerIDs.contains($0.key) && !disabledLayerIDs.contains($0.key)
        }
        let leaving = Set(previousHits.keys).subtracting(admittedHits.keys)
        let entering = Set(admittedHits.keys).subtracting(previousHits.keys)
        var failures: [Int: SceneScriptScalarRuntimeFailure] = [:]
        var materialFunctions: [SceneScriptMaterialFunctionMutation] = []
        var animations: [SceneTimelinePlaybackMutation] = []
        for binding in bindings where !disabledLayerIDs.contains(binding.layerID) {
            let event: SceneScriptCursorEventInput?
            if leaving.contains(binding.layerID),
               let hit = previousHits[binding.layerID] {
                event = .init(
                    kind: .leave,
                    layerID: binding.layerID,
                    worldPosition: hit.worldPosition,
                    localPosition: hit.localPosition
                )
            } else if entering.contains(binding.layerID),
                      let hit = admittedHits[binding.layerID] {
                event = .init(
                    kind: .enter,
                    layerID: binding.layerID,
                    worldPosition: hit.worldPosition,
                    localPosition: hit.localPosition
                )
            } else {
                event = nil
            }
            guard let event else { continue }
            switch binding.owner.dispatchCursor(
                event,
                frame: frame,
                userPropertiesJSON: userPropertiesJSON,
                interruptBudget: interruptBudget
            ) {
            case let .success(mutations):
                materialFunctions.append(contentsOf: mutations.materialFunctions)
                animations.append(contentsOf: mutations.animations)
                NSLog(
                    "MWX SceneScript VM: layerID=%d event=%@ route=generic-only",
                    binding.layerID,
                    event.kind == .enter ? "cursorEnter" : "cursorLeave"
                )
            case let .failure(failure):
                failures[binding.layerID] = failure
                disabledLayerIDs.insert(binding.layerID)
            }
        }
        previousHits = admittedHits.filter {
            !disabledLayerIDs.contains($0.key)
        }
        return .init(
            failures: failures,
            materialFunctionMutations: materialFunctions,
            animationMutations: animations
        )
    }

    func invalidate() {
        bindings.forEach { $0.owner.invalidate() }
        previousHits = [:]
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
              binding.wrapperKeys == ["script", "value"],
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
              validHitTransform(layer) else { return nil }
        return .init(layerID: layerID, authoredOrder: index)
    }

    private static func validHitTransform(
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
