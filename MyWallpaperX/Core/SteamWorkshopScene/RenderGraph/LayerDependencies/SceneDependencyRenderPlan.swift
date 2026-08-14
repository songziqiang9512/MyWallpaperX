import Foundation

nonisolated struct SceneDependencyRenderPlan {
    nonisolated struct Reference: Hashable {
        let consumerLayerID: Int
        let providerLayerID: Int
        let slot: SceneEffectPassSlot
        let variant: SceneNamedTextureReference.Variant
    }

    nonisolated struct Binding: Hashable {
        enum Kind: Hashable {
            case clippingMask
            case proceduralNoiseLayer
        }

        let consumerLayerID: Int
        let providerLayerID: Int
        let slot: SceneEffectPassSlot
        let blendMode: Int
        let kind: Kind
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
    let executableUtilityConsumerLayerIDs: Set<Int>
    let requiredEffectConsumerLayerIDs: Set<Int>
    let bindingsByConsumerLayerID: [Int: Binding]
    let requiredProviderLayerIDs: Set<Int>
    let staticLayerSourcePassthroughBlockedLayerIDs: Set<Int>
    let cyclicLayerIDs: Set<Int>
    let issues: [Issue]

    nonisolated func blocksStaticLayerSourcePassthrough(for layerID: Int) -> Bool {
        staticLayerSourcePassthroughBlockedLayerIDs.contains(layerID)
    }

    nonisolated init(
        descriptor: SceneRenderDescriptor,
        visibleLayerIDs: Set<Int>,
        executableUtilityConsumerLayerIDs: Set<Int> = []
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
        let xRayExemptConsumerLayerIDs = Set(visibleLayerIDs.compactMap { layerID -> Int? in
            guard let layer = layersByID[layerID],
                  Self.xRayEffectLocalProviderContract(for: layer) != nil else {
                return nil
            }
            return layerID
        })
        var passthroughBlockedLayerIDs: Set<Int> = []
        for consumerLayerID in visibleLayerIDs {
            for providerLayerID in dependencyEdges[consumerLayerID] ?? [] {
                if !xRayExemptConsumerLayerIDs.contains(consumerLayerID) {
                    passthroughBlockedLayerIDs.insert(consumerLayerID)
                }
                if layersByID[providerLayerID] != nil {
                    passthroughBlockedLayerIDs.insert(providerLayerID)
                }
            }
        }
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
                executableUtilityConsumerLayerIDs: executableUtilityConsumerLayerIDs,
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
        self.executableUtilityConsumerLayerIDs = executableUtilityConsumerLayerIDs
        self.requiredEffectConsumerLayerIDs = Set(descriptor.layers.compactMap { layer in
            guard visibleLayerIDs.contains(layer.id),
                  Self.supportsEffectConsumer(
                      layer,
                      executableUtilityConsumerLayerIDs: executableUtilityConsumerLayerIDs
                  ),
                  references.contains(where: { $0.consumerLayerID == layer.id }),
                  Self.requiresNamedEffect(
                      layer,
                      executableUtilityConsumerLayerIDs: executableUtilityConsumerLayerIDs
                  ) else {
                return nil
            }
            return layer.id
        })
        self.bindingsByConsumerLayerID = bindings
        self.requiredProviderLayerIDs = Set(bindings.values.map(\.providerLayerID))
        self.staticLayerSourcePassthroughBlockedLayerIDs = passthroughBlockedLayerIDs
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

    /// Typed consumer-side passthrough exemption: the only cross-layer input of a
    /// visible image layer is the exact stock X-Ray effect's slot-1 blend texture
    /// referencing one authored dependency's primary composite. The stock
    /// `xray.frag` keeps `gl_FragColor.a` equal to the consumer's own composite
    /// alpha and only blends the provider RGB inside the pointer halo, so the
    /// provider input is effect-local to the skipped effect and cannot change the
    /// consumer's own source coverage. The provider side stays blocked.
    private nonisolated static func xRayEffectLocalProviderContract(
        for layer: SceneRenderDescriptor.Layer
    ) -> Reference? {
        guard layer.contentKind == "image",
              layer.visible != false,
              layer.dependencyLayerIDs.count == 1,
              let providerLayerID = layer.dependencyLayerIDs.first,
              providerLayerID != layer.id else {
            return nil
        }
        let visibleEffects = layer.effects.filter { $0.visible != false }
        let xRayEffects = visibleEffects.filter {
            normalized($0.file) == stockXRayEffectPath
        }
        guard xRayEffects.count == 1,
              let effect = xRayEffects.first,
              effect.passes.count == 1,
              let pass = effect.passes.first,
              pass.passIndex == 0,
              pass.userTextureInputs.isEmpty,
              normalizedXRayCombos(pass.combos) != nil,
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

    private nonisolated static func normalizedXRayCombos(
        _ authored: [String: Int]
    ) -> [String: Int]? {
        var result: [String: Int] = [:]
        let allowed = Set(["BLENDMODE", "OPACITYMASK"])
        for (key, value) in authored {
            let normalizedKey = key.uppercased()
            guard allowed.contains(normalizedKey),
                  result[normalizedKey] == nil,
                  value == 0 else {
                return nil
            }
            result[normalizedKey] = value
        }
        return result
    }

    private nonisolated static let stockXRayEffectPath = "effects/xray/effect.json"

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
        executableUtilityConsumerLayerIDs: Set<Int>,
        issues: inout [Issue]
    ) -> Binding? {
        let visibleEffects = layer.effects.filter { $0.visible != false }
        let contract: (
            reference: Reference,
            blendMode: Int,
            kind: Binding.Kind
        )?
        if let clipping = supportedClippingEffect(in: visibleEffects),
           references.count == 1,
           let reference = references.first,
           reference.slot.effectID == clipping.declaration.effectID,
           reference.slot.passIndex == clipping.declaration.passIndex,
           reference.slot.slotIndex == 1,
           reference.providerLayerID == clipping.declaration.providerLayerID {
            contract = (reference, clipping.declaration.blendMode, .clippingMask)
        } else if let reference = supportedProceduralNoiseReference(
            layer: layer,
            visibleEffects: visibleEffects,
            references: references,
            executableUtilityConsumerLayerIDs: executableUtilityConsumerLayerIDs
        ) {
            contract = (reference, 0, .proceduralNoiseLayer)
        } else {
            contract = nil
        }
        guard supportsEffectConsumer(
                  layer,
                  executableUtilityConsumerLayerIDs: executableUtilityConsumerLayerIDs
              ),
              let contract else {
            issues.append(Issue(kind: .unsupportedConsumer, layerID: layer.id, providerLayerID: nil))
            return nil
        }
        let reference = contract.reference
        if case .some = layer.utilityLayer,
           layer.dependencyLayerIDs != [reference.providerLayerID] {
            issues.append(Issue(
                kind: .dependencyMismatch,
                layerID: layer.id,
                providerLayerID: reference.providerLayerID
            ))
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
        let providerKindIsSupported = contract.kind == .clippingMask
            ? provider.utilityLayer?.kind == .composition
            : provider.contentKind == "solid"
                && hasNoUtilityLayer(provider)
                && provider.visible == false
        guard providerKindIsSupported,
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
            blendMode: contract.blendMode,
            kind: contract.kind
        )
    }

    private nonisolated static func supportsEffectConsumer(
        _ layer: SceneRenderDescriptor.Layer,
        executableUtilityConsumerLayerIDs: Set<Int>
    ) -> Bool {
        guard let utility = layer.utilityLayer else { return true }
        return executableUtilityConsumerLayerIDs.contains(layer.id)
            && utility.kind == .composition
            && layer.contentKind == "composition"
            && layer.childLayerIDs.isEmpty
            && layer.dependencyLayerIDs.count == 1
    }

    private nonisolated static func supportedClippingEffect(
        in visibleEffects: [SceneRenderDescriptor.EffectDescriptor]
    ) -> (
        effect: SceneRenderDescriptor.EffectDescriptor,
        declaration: SceneClippingMaskDeclaration
    )? {
        let matches = visibleEffects.compactMap { effect in
            SceneClippingMaskContract.declaration(for: effect).map {
                (effect: effect, declaration: $0)
            }
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private nonisolated static func requiresNamedEffect(
        _ layer: SceneRenderDescriptor.Layer,
        executableUtilityConsumerLayerIDs: Set<Int>
    ) -> Bool {
        let visibleEffects = layer.effects.filter { $0.visible != false }
        if visibleEffects.compactMap(SceneClippingMaskContract.declaration).count == 1 {
            return true
        }
        return supportedProceduralNoiseReference(
            layer: layer,
            visibleEffects: visibleEffects,
            references: references(in: [layer]),
            executableUtilityConsumerLayerIDs: executableUtilityConsumerLayerIDs
        ) != nil
    }

    private nonisolated static func supportedProceduralNoiseReference(
        layer: SceneRenderDescriptor.Layer,
        visibleEffects: [SceneRenderDescriptor.EffectDescriptor],
        references: [Reference],
        executableUtilityConsumerLayerIDs: Set<Int>
    ) -> Reference? {
        guard executableUtilityConsumerLayerIDs.contains(layer.id),
              visibleEffects.count == 1,
              let effect = visibleEffects.first,
              normalized(effect.file) == proceduralNoiseV1Path,
              effect.passes.count == 1,
              let pass = effect.passes.first,
              pass.passIndex == 0,
              pass.combos == [
                  "AB_TYPECOLOR": 3,
                  "PERSPSWITCH": 1,
                  "WRITEALPHA": 1,
              ],
              pass.textureSlots.count == 4,
              pass.textureSlots[0...2].allSatisfy({ $0 == nil }),
              let path = pass.textureSlots[3],
              pass.texturePaths == [path],
              references.count == 1,
              let reference = references.first,
              reference.slot.effectID == effect.id,
              reference.slot.passIndex == 0,
              reference.slot.slotIndex == 3,
              layer.dependencyLayerIDs == [reference.providerLayerID] else {
            return nil
        }
        return reference
    }

    private nonisolated static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private nonisolated static func hasNoUtilityLayer(
        _ layer: SceneRenderDescriptor.Layer
    ) -> Bool {
        if case nil = layer.utilityLayer { return true }
        return false
    }

    private nonisolated static let proceduralNoiseV1Path =
        "effects/workshop/2924967132/procedural_noise/effect.json"
}
