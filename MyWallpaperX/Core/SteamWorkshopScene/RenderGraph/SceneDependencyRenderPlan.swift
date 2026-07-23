import Foundation

nonisolated struct SceneDependencyRenderPlan {
    nonisolated struct Reference: Hashable {
        let consumerLayerID: Int
        let providerLayerID: Int
        let slot: SceneEffectPassSlot
        let variant: SceneNamedTextureReference.Variant
    }

    nonisolated struct Binding: Hashable {
        let consumerLayerID: Int
        let providerLayerID: Int
        let slot: SceneEffectPassSlot
        let blendMode: Int
    }

    nonisolated enum IssueKind: String {
        case dependencyMismatch
        case missingProvider
        case cyclicDependency
        case unsupportedConsumer
        case unsupportedVariant
        case forwardUtilityProvider
    }

    nonisolated struct Issue: Hashable {
        let kind: IssueKind
        let layerID: Int
        let providerLayerID: Int?
    }

    let references: [Reference]
    let namedReferenceConsumerLayerIDs: Set<Int>
    let requiredEffectConsumerLayerIDs: Set<Int>
    let bindingsByConsumerLayerID: [Int: Binding]
    let requiredProviderLayerIDs: Set<Int>
    let cyclicLayerIDs: Set<Int>
    let issues: [Issue]

    nonisolated init(
        descriptor: SceneRenderDescriptor,
        visibleLayerIDs: Set<Int>
    ) {
        let layersByID = Dictionary(uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0) })
        let order = Dictionary(uniqueKeysWithValues: descriptor.renderOrderLayerIDs.enumerated().map {
            ($0.element, $0.offset)
        })
        let references = Self.references(in: descriptor.layers)
        let dependencyEdges = Self.dependencyEdges(
            layers: descriptor.layers,
            references: references
        )
        let cyclicLayerIDs = Self.cyclicLayerIDs(edges: dependencyEdges)
        var issues = Self.referenceIssues(references: references, layersByID: layersByID)
        var bindings: [Int: Binding] = [:]

        for layer in descriptor.layers where visibleLayerIDs.contains(layer.id) {
            let layerReferences = references.filter { $0.consumerLayerID == layer.id }
            guard !layerReferences.isEmpty else { continue }
            guard let binding = Self.executableBinding(
                for: layer,
                references: layerReferences,
                layersByID: layersByID,
                order: order,
                cyclicLayerIDs: cyclicLayerIDs,
                issues: &issues
            ) else {
                continue
            }
            bindings[layer.id] = binding
            if !layer.dependencyLayerIDs.contains(binding.providerLayerID) {
                issues.append(Issue(
                    kind: .dependencyMismatch,
                    layerID: layer.id,
                    providerLayerID: binding.providerLayerID
                ))
            }
        }

        self.references = references
        self.namedReferenceConsumerLayerIDs = Set(references.compactMap { reference in
            visibleLayerIDs.contains(reference.consumerLayerID) ? reference.consumerLayerID : nil
        })
        self.requiredEffectConsumerLayerIDs = Set(descriptor.layers.compactMap { layer in
            guard visibleLayerIDs.contains(layer.id),
                  references.contains(where: { $0.consumerLayerID == layer.id }),
                  layer.effects.contains(where: {
                      $0.visible != false
                          && $0.file.localizedLowercase.contains("clipping_mask")
                  }) else {
                return nil
            }
            return layer.id
        })
        self.bindingsByConsumerLayerID = bindings
        self.requiredProviderLayerIDs = Set(bindings.values.map(\.providerLayerID))
        self.cyclicLayerIDs = cyclicLayerIDs
        self.issues = Array(Set(issues)).sorted {
            ($0.layerID, $0.kind.rawValue, $0.providerLayerID ?? -1)
                < ($1.layerID, $1.kind.rawValue, $1.providerLayerID ?? -1)
        }
    }

    private nonisolated static func references(
        in layers: [SceneRenderDescriptor.Layer]
    ) -> [Reference] {
        layers.flatMap { layer in
            layer.effects.filter { $0.visible != false }.flatMap { effect in
                effect.passes.flatMap { pass in
                    pass.textureSlots.enumerated().compactMap { slotIndex, path in
                        guard let reference = SceneNamedTextureReference.parse(path) else { return nil }
                        return Reference(
                            consumerLayerID: layer.id,
                            providerLayerID: reference.providerLayerID,
                            slot: SceneEffectPassSlot(
                                effectID: effect.id,
                                passIndex: pass.passIndex,
                                slotIndex: slotIndex
                            ),
                            variant: reference.variant
                        )
                    }
                }
            }
        }
    }

    private nonisolated static func dependencyEdges(
        layers: [SceneRenderDescriptor.Layer],
        references: [Reference]
    ) -> [Int: Set<Int>] {
        var edges = Dictionary(uniqueKeysWithValues: layers.map { layer in
            (layer.id, Set(layer.dependencyLayerIDs.filter { $0 != layer.id }))
        })
        for reference in references where reference.consumerLayerID != reference.providerLayerID {
            edges[reference.consumerLayerID, default: []].insert(reference.providerLayerID)
        }
        return edges
    }

    private nonisolated static func cyclicLayerIDs(
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

    private nonisolated static func referenceIssues(
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

    private nonisolated static func executableBinding(
        for layer: SceneRenderDescriptor.Layer,
        references: [Reference],
        layersByID: [Int: SceneRenderDescriptor.Layer],
        order: [Int: Int],
        cyclicLayerIDs: Set<Int>,
        issues: inout [Issue]
    ) -> Binding? {
        let visibleEffects = layer.effects.filter { $0.visible != false }
        guard let effect = supportedClippingEffect(in: visibleEffects),
              effect.passes.count == 1,
              let pass = effect.passes.first,
              references.count == 1,
              let reference = references.first,
              reference.slot.slotIndex == 1,
              supportsClippingConstants(pass.constantShaderValues),
              pass.combos.allSatisfy({ key, value in
                  key.caseInsensitiveCompare("BLENDMODE") == .orderedSame || value == 0
              }) else {
            issues.append(Issue(kind: .unsupportedConsumer, layerID: layer.id, providerLayerID: nil))
            return nil
        }
        let blendMode = combo("BLENDMODE", in: pass) ?? 0
        guard blendMode == 0 || blendMode == 5 else {
            issues.append(Issue(kind: .unsupportedConsumer, layerID: layer.id, providerLayerID: nil))
            return nil
        }
        guard reference.variant == .primary else {
            issues.append(Issue(
                kind: .unsupportedVariant,
                layerID: layer.id,
                providerLayerID: reference.providerLayerID
            ))
            return nil
        }
        guard let provider = layersByID[reference.providerLayerID] else { return nil }
        guard !cyclicLayerIDs.contains(layer.id), !cyclicLayerIDs.contains(provider.id) else {
            issues.append(Issue(
                kind: .cyclicDependency,
                layerID: layer.id,
                providerLayerID: provider.id
            ))
            return nil
        }
        guard provider.utilityLayer?.kind == .composition,
              provider.effects.allSatisfy({ $0.visible == false }),
              provider.childLayerIDs.isEmpty,
              provider.dependencyLayerIDs.isEmpty,
              (order[provider.id] ?? .max) < (order[layer.id] ?? .min) else {
            issues.append(Issue(
                kind: .forwardUtilityProvider,
                layerID: layer.id,
                providerLayerID: provider.id
            ))
            return nil
        }
        return Binding(
            consumerLayerID: layer.id,
            providerLayerID: provider.id,
            slot: reference.slot,
            blendMode: blendMode
        )
    }

    private nonisolated static func supportedClippingEffect(
        in visibleEffects: [SceneRenderDescriptor.EffectDescriptor]
    ) -> SceneRenderDescriptor.EffectDescriptor? {
        if visibleEffects.count == 1,
           visibleEffects[0].file.localizedLowercase.contains("clipping_mask") {
            return visibleEffects[0]
        }
        guard visibleEffects.count == 2,
              SceneGradientColorRuntimePlanner.plan(for: visibleEffects[0]) != nil,
              visibleEffects[1].file.localizedLowercase.contains("clipping_mask") else {
            return nil
        }
        return visibleEffects[1]
    }

    private nonisolated static func combo(
        _ name: String,
        in pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor
    ) -> Int? {
        pass.combos.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    private nonisolated static func supportsClippingConstants(
        _ values: [String: SceneDocument.ShaderValue]
    ) -> Bool {
        values.allSatisfy { key, value in
            guard key.caseInsensitiveCompare("Opacity") == .orderedSame,
                  let components = value.components,
                  components.count == 1,
                  let opacity = components.first else {
                return false
            }
            return opacity.isFinite && abs(opacity - 1) < 0.000_001
        }
    }
}
