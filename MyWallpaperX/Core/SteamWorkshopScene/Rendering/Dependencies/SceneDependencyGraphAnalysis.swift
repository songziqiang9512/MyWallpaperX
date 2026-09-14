import Foundation

/// Stateless graph interpretation shared by dependency-plan assembly and
/// passthrough safety admission.
nonisolated enum SceneDependencyGraphAnalysis {
    typealias Reference = SceneDependencyRenderPlan.Reference
    typealias Issue = SceneDependencyRenderPlan.Issue

    nonisolated static func references(
        in layers: [SceneRenderDescriptor.Layer]
    ) -> [Reference] {
        SceneNamedTextureDependencyReferenceAnalysis.references(in: layers).map {
            Reference(
                consumerLayerID: $0.consumerLayerID,
                providerLayerID: $0.providerLayerID,
                slot: $0.slot,
                variant: $0.variant
            )
        }
    }

    nonisolated static func potentialOptionalNamedFallbackReferences(
        in layers: [SceneRenderDescriptor.Layer]
    ) -> [Reference] {
        SceneNamedTextureDependencyReferenceAnalysis
            .potentialOptionalNamedFallbackReferences(in: layers).map {
                Reference(
                    consumerLayerID: $0.consumerLayerID,
                    providerLayerID: $0.providerLayerID,
                    slot: $0.slot,
                    variant: $0.variant
                )
            }
    }

    nonisolated static func dependencyEdges(
        layers: [SceneRenderDescriptor.Layer],
        references: [Reference]
    ) -> [Int: Set<Int>] {
        var edges = Dictionary(uniqueKeysWithValues: layers.map { layer in
            (layer.id, Set(layer.dependencyLayerIDs.filter { $0 != layer.id }))
        })
        for reference in references
        where reference.consumerLayerID != reference.providerLayerID {
            edges[reference.consumerLayerID, default: []].insert(
                reference.providerLayerID
            )
        }
        return edges
    }

    /// A strictly verified stock X-Ray stage may skip its effect-local provider
    /// when alpha-affecting combos are disabled. The provider stays blocked.
    nonisolated static func xRayEffectLocalProviderContract(
        for layer: SceneRenderDescriptor.Layer,
        verifiedStageKeys: Set<SceneAuthoredEffectRenderPlan.EffectKey>,
        availableLayerIDs: Set<Int>
    ) -> Reference? {
        guard layer.contentKind == "image",
              layer.visible != false,
              layer.dependencyLayerIDs.count == 1,
              let providerLayerID = layer.dependencyLayerIDs.first,
              providerLayerID != layer.id,
              availableLayerIDs.contains(providerLayerID) else {
            return nil
        }
        let verifiedKeys = verifiedStageKeys.filter { $0.layerID == layer.id }
        guard verifiedKeys.count == 1,
              let verifiedKey = verifiedKeys.first,
              layer.effects.indices.contains(verifiedKey.effectIndex) else {
            return nil
        }
        let effect = layer.effects[verifiedKey.effectIndex]
        guard effect.visible != false,
              effect.id == verifiedKey.descriptorID,
              effect.passes.count == 1,
              let pass = effect.passes.first,
              pass.passIndex == 0,
              pass.userTextureInputs.isEmpty,
              Set(pass.combos.keys.map { $0.uppercased() }).count
                == pass.combos.count,
              pass.combos.allSatisfy({
                  ["BLENDMODE", "OPACITYMASK"].contains($0.key.uppercased())
                      && $0.value == 0
              }),
              pass.textureSlots.count == 3,
              pass.textureSlots[0] == nil,
              let blendPath = pass.textureSlots[1],
              let blendReference = SceneNamedTextureReference.parse(blendPath),
              blendReference.variant == .primary,
              blendReference.providerLayerID == providerLayerID,
              pass.textureSlots[2].flatMap(SceneNamedTextureReference.parse) == nil,
              pass.texturePaths.map(normalized)
                == pass.textureSlots.compactMap({ $0 }).map(normalized) else {
            return nil
        }
        let layerReferences = references(in: [layer])
        guard layerReferences.count == 1,
              let onlyReference = layerReferences.first,
              onlyReference.consumerLayerID == layer.id,
              onlyReference.providerLayerID == providerLayerID,
              onlyReference.slot.effectID == effect.id,
              onlyReference.slot.passIndex == 0,
              onlyReference.slot.slotIndex == 1,
              onlyReference.variant == .primary else {
            return nil
        }
        return onlyReference
    }

    nonisolated static func cyclicLayerIDs(
        edges: [Int: Set<Int>]
    ) -> Set<Int> {
        enum VisitState { case visiting, visited }
        var states: [Int: VisitState] = [:]
        var stack: [Int] = []
        var cyclic: Set<Int> = []

        func visit(_ layerID: Int) {
            if states[layerID] == .visited { return }
            if states[layerID] == .visiting {
                if let start = stack.firstIndex(of: layerID) {
                    cyclic.formUnion(stack[start...])
                }
                return
            }
            states[layerID] = .visiting
            stack.append(layerID)
            for providerID in edges[layerID] ?? [] where edges[providerID] != nil {
                visit(providerID)
            }
            _ = stack.popLast()
            states[layerID] = .visited
        }

        for layerID in edges.keys { visit(layerID) }
        return cyclic
    }

    nonisolated static func referenceIssues(
        references: [Reference],
        layersByID: [Int: SceneRenderDescriptor.Layer]
    ) -> [Issue] {
        references.compactMap { reference in
            guard layersByID[reference.providerLayerID] == nil else { return nil }
            return Issue(
                kind: .missingProvider,
                layerID: reference.consumerLayerID,
                providerLayerID: reference.providerLayerID
            )
        }
    }

    private nonisolated static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}
