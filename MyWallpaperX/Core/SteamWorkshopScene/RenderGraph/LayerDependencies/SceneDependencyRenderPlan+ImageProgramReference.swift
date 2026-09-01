import Foundation

extension SceneDependencyRenderPlan {
    /// Builds descriptor-only carriers one exact slot at a time. They never
    /// enter product edges or targets here; Program finalization may promote
    /// one carrier after proving the selected mixed-provider envelope.
    nonisolated static func potentialOptionalNamedFallbackBindings(
        descriptor: SceneRenderDescriptor,
        visibleLayerIDs: Set<Int>,
        executableUtilityConsumerLayerIDs: Set<Int> = []
    ) -> [Int: [Binding]] {
        let layersByID = Dictionary(uniqueKeysWithValues: descriptor.layers.map {
            ($0.id, $0)
        })
        let order = Dictionary(uniqueKeysWithValues:
            descriptor.renderOrderLayerIDs.enumerated().map {
                ($0.element, $0.offset)
            }
        )
        let productReferences = SceneDependencyGraphAnalysis.references(
            in: descriptor.layers
        )
        let potentialReferences = Set(SceneDependencyGraphAnalysis
            .potentialOptionalNamedFallbackReferences(in: descriptor.layers)
        )
        let allPotentialReferences = Array(potentialReferences)
        let routeDisabled = ProcessInfo.processInfo.environment[
            "MWX_SCENE_NAMED_PROVIDER_ROUTE"
        ] == "disable-generic"
        var result: [Int: [Binding]] = [:]
        for reference in allPotentialReferences {
            let admittedPotentialReferences: Set<Reference> = [reference]
            let references = productReferences + [reference]
            let cyclicLayerIDs = SceneDependencyGraphAnalysis.cyclicLayerIDs(
                edges: productDependencyEdges(
                    layers: descriptor.layers,
                    references: references,
                    productReferences: productReferences,
                    potentialReferences: potentialReferences,
                    admittedPotentialReferences: admittedPotentialReferences
                )
            )
            guard let layer = layersByID[reference.consumerLayerID] else {
                continue
            }
            var ignoredIssues: [Issue] = []
            guard let binding = executableBinding(
                for: layer,
                references: [reference],
                layersByID: layersByID,
                order: order,
                visibleLayerIDs: visibleLayerIDs,
                cyclicLayerIDs: cyclicLayerIDs,
                executableUtilityConsumerLayerIDs:
                    executableUtilityConsumerLayerIDs,
                admittedResolvedMaterialReferences: [reference],
                namedProviderRouteDisabled: routeDisabled,
                issues: &ignoredIssues
            ), binding.requiresResolvedMaterialProgram else { continue }
            result[layer.id, default: []].append(binding)
        }
        return result.mapValues { bindings in
            Array(Set(bindings)).sorted {
                (
                    $0.consumerLayerID,
                    $0.providerLayerID,
                    $0.slot.effectID,
                    $0.slot.passIndex,
                    $0.slot.slotIndex
                ) < (
                    $1.consumerLayerID,
                    $1.providerLayerID,
                    $1.slot.effectID,
                    $1.slot.passIndex,
                    $1.slot.slotIndex
                )
            }
        }
    }

    /// Removes descriptor-only fallback metadata from the product dependency
    /// graph until the exact Program slot has been admitted. Candidate cycle
    /// checks call this with one admitted potential reference, so an unrelated
    /// fallback slot cannot revoke an otherwise safe carrier.
    nonisolated static func productDependencyEdges(
        layers: [SceneRenderDescriptor.Layer],
        references: [Reference],
        productReferences: [Reference],
        potentialReferences: Set<Reference>,
        admittedPotentialReferences: Set<Reference>
    ) -> [Int: Set<Int>] {
        var edges = SceneDependencyGraphAnalysis.dependencyEdges(
            layers: layers,
            references: references
        )
        for layer in layers {
            let declaredProviderIDs = Set(
                layer.dependencyLayerIDs.filter { $0 != layer.id }
            )
            let productProviderIDs = Set(productReferences.filter {
                $0.consumerLayerID == layer.id
            }.map(\.providerLayerID))
            let potentialProviderIDs = Set(potentialReferences.filter {
                $0.consumerLayerID == layer.id
            }.map(\.providerLayerID))
            let admittedPotentialProviderIDs = Set(
                admittedPotentialReferences.filter {
                $0.consumerLayerID == layer.id
                }.map(\.providerLayerID)
            )
            if !potentialProviderIDs.isEmpty,
               layer.authoredDependencies.isEmpty,
               declaredProviderIDs
                == productProviderIDs.union(potentialProviderIDs) {
                edges[layer.id] = productProviderIDs.union(
                    admittedPotentialProviderIDs
                )
            }
        }
        return edges
    }

    /// Generic carrier for one source-proven Program sampler backed by an
    /// earlier visible image layer's graph-final publication. Shader identity,
    /// effect name and scalar values deliberately do not participate here;
    /// MaterialProgram admission owns those contracts after this compiler has
    /// conserved the exact authored primary reference.
    nonisolated static func visibleImageGraphOutputReference(
        layer: SceneRenderDescriptor.Layer,
        visibleEffects: [SceneRenderDescriptor.EffectDescriptor],
        references: [Reference],
        layersByID: [Int: SceneRenderDescriptor.Layer],
        visibleLayerIDs: Set<Int>
    ) -> Reference? {
        guard layer.contentKind == "image",
              hasNoUtilityLayer(layer),
              layer.visible != false,
              visibleLayerIDs.contains(layer.id),
              layer.childLayerIDs.isEmpty,
              layer.authoredDependencies.isEmpty,
              references.count == 1,
              let reference = references.first,
              reference.variant == .primary,
              reference.slot.passIndex == 0,
              reference.slot.slotIndex == 1,
              layer.dependencyLayerIDs == [reference.providerLayerID],
              let provider = layersByID[reference.providerLayerID],
              provider.contentKind == "image",
              hasNoUtilityLayer(provider),
              provider.visible != false,
              visibleLayerIDs.contains(provider.id),
              provider.childLayerIDs.isEmpty,
              provider.authoredDependencies.isEmpty,
              provider.dependencyLayerIDs.isEmpty,
              provider.effects.contains(where: { $0.visible != false }) else {
            return nil
        }
        let effects = visibleEffects.filter { $0.id == reference.slot.effectID }
        guard effects.count == 1, let effect = effects.first,
              effect.passes.count == 1 else { return nil }
        let passes = effect.passes.filter {
            $0.passIndex == reference.slot.passIndex
        }
        guard passes.count == 1, let pass = passes.first,
              pass.textureSlots.indices.contains(reference.slot.slotIndex),
              let path = pass.textureSlots[reference.slot.slotIndex],
              SceneNamedTextureReference.parse(path) == .init(
                  providerLayerID: reference.providerLayerID,
                  variant: .primary
              ), SceneNamedTextureDependencyReferenceAnalysis
                .userTextureAllowsNamedFallback(
                    slotIndex: reference.slot.slotIndex,
                    pass: pass
                ) else {
            return nil
        }
        return reference
    }

    nonisolated static func supportedImageLayerBlendDeclaration(
        in visibleEffects: [SceneRenderDescriptor.EffectDescriptor]
    ) -> SceneImageLayerBlendDependencyDeclaration? {
        let declarations = visibleEffects.compactMap(
            SceneImageLayerBlendDependencyContract.declaration
        )
        return declarations.count == 1 ? declarations[0] : nil
    }

    /// Generic external-primary carrier for one hidden image source consumed
    /// by a single admitted Program sampler. Effect identity and authored
    /// scalar values deliberately do not select this resource route.
    nonisolated static func materialProgramImageLayerReference(
        layer: SceneRenderDescriptor.Layer,
        visibleEffects: [SceneRenderDescriptor.EffectDescriptor],
        references: [Reference],
        layersByID: [Int: SceneRenderDescriptor.Layer]
    ) -> Reference? {
        guard layer.contentKind == "image",
              hasNoUtilityLayer(layer),
              layer.childLayerIDs.isEmpty,
              layer.authoredDependencies.isEmpty,
              references.count == 1,
              let reference = references.first,
              reference.variant == .primary,
              reference.slot.passIndex == 0,
              reference.slot.slotIndex == 1,
              layer.dependencyLayerIDs == [reference.providerLayerID],
              let provider = layersByID[reference.providerLayerID],
              provider.contentKind == "image",
              hasNoUtilityLayer(provider),
              provider.visible == false,
              provider.childLayerIDs.isEmpty,
              provider.dependencyLayerIDs.isEmpty,
              !provider.effects.contains(where: { $0.visible != false }) else {
            return nil
        }
        let effects = visibleEffects.filter { $0.id == reference.slot.effectID }
        guard effects.count == 1, let effect = effects.first,
              effect.passes.count == 1,
              let pass = effect.passes.first,
              pass.passIndex == reference.slot.passIndex,
              pass.textureSlots.indices.contains(reference.slot.slotIndex),
              let path = pass.textureSlots[reference.slot.slotIndex],
              SceneNamedTextureReference.parse(path) == .init(
                  providerLayerID: reference.providerLayerID,
                  variant: .primary
              ), SceneNamedTextureDependencyReferenceAnalysis
                .userTextureAllowsNamedFallback(
                    slotIndex: reference.slot.slotIndex,
                    pass: pass
                )
        else { return nil }
        return reference
    }

    nonisolated static func hasNoUtilityLayer(
        _ layer: SceneRenderDescriptor.Layer
    ) -> Bool {
        if case nil = layer.utilityLayer { return true }
        return false
    }
}
