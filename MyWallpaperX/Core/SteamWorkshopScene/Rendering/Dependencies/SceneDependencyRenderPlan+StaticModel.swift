import Foundation

/// Authored identity for a direct model material input backed by the existing
/// same-frame named provider registry. It carries no effect identity because
/// model pass slots are not effect pass slots.
nonisolated struct SceneStaticModelNamedTextureBinding: Hashable {
    let consumerLayerID: Int
    let providerLayerID: Int
    let materialPath: String
    let passIndex: Int
    let slotIndex: Int
    let variant: SceneNamedTextureReference.Variant
    let requiresForwardCapture: Bool
}

extension SceneDependencyRenderPlan {
    nonisolated struct StaticModelBindingCompilation {
        let bindings: [Int: SceneStaticModelNamedTextureBinding]
        let issues: [Issue]
    }

    nonisolated static func staticModelNamedTextureProviderLayerIDs(
        in descriptor: SceneRenderDescriptor
    ) -> Set<Int> {
        let layersByID = Dictionary(uniqueKeysWithValues: descriptor.layers.map {
            ($0.id, $0)
        })
        let order = Dictionary(uniqueKeysWithValues:
            descriptor.renderOrderLayerIDs.enumerated().map {
                ($0.element, $0.offset)
            }
        )
        let routeDisabled = ProcessInfo.processInfo.environment[
            "MWX_SCENE_NAMED_PROVIDER_ROUTE"
        ] == "disable-generic"
        return Set(staticModelNamedTextureBindings(
            descriptor: descriptor,
            layersByID: layersByID,
            order: order,
            routeDisabled: routeDisabled
        ).bindings.values.map(\.providerLayerID))
    }

    nonisolated static func staticModelBindingsPreservingEffectProviders(
        _ compilation: StaticModelBindingCompilation,
        effectBindings: [Int: Binding]
    ) -> StaticModelBindingCompilation {
        let effectProviderLayerIDs = Set(
            effectBindings.values.map(\.providerLayerID)
        )
        var bindings = compilation.bindings
        var issues = compilation.issues
        for (consumerLayerID, binding) in compilation.bindings
        where effectProviderLayerIDs.contains(binding.providerLayerID) {
            bindings.removeValue(forKey: consumerLayerID)
            issues.append(Issue(
                kind: .dependencyMismatch,
                layerID: consumerLayerID,
                providerLayerID: binding.providerLayerID
            ))
        }
        return .init(bindings: bindings, issues: issues)
    }

    /// Compiles only the shared direct-model contract: one exact model link,
    /// material pass zero/slot zero, a primary named target, and one hidden
    /// static image/solid provider declared by the consumer. Shader/material values
    /// remain owned by the existing static-model pipeline.
    nonisolated static func staticModelNamedTextureBindings(
        descriptor: SceneRenderDescriptor,
        layersByID: [Int: SceneRenderDescriptor.Layer],
        order: [Int: Int],
        routeDisabled: Bool
    ) -> StaticModelBindingCompilation {
        let linksByModel = Dictionary(grouping: descriptor.modelMaterialLinks) {
            normalizedStaticModelAssetPath($0.modelPath)
        }
        let passesByMaterial = Dictionary(grouping: descriptor.materialPasses.filter {
            $0.passIndex == 0
        }) {
            normalizedStaticModelAssetPath($0.materialPath)
        }
        var bindings: [Int: SceneStaticModelNamedTextureBinding] = [:]
        var issues: [Issue] = []

        for consumer in descriptor.layers where consumer.staticModelPath != nil {
            guard let modelPath = consumer.staticModelPath,
                  let modelIdentity = normalizedStaticModelAssetPath(modelPath),
                  let links = linksByModel[modelIdentity],
                  links.count == 1,
                  let materialPath = links[0].materialPath,
                  let materialIdentity = normalizedStaticModelAssetPath(materialPath),
                  let passes = passesByMaterial[materialIdentity],
                  passes.count == 1,
                  let pass = passes.first,
                  pass.textureSlots.indices.contains(0),
                  let authoredPath = pass.textureSlots[0],
                  let reference = SceneNamedTextureReference.parse(authoredPath)
            else { continue }

            let providerID = reference.providerLayerID
            guard pass.texturePaths == pass.textureSlots.compactMap({ $0 }),
                  (!pass.userTextureInputs.indices.contains(0)
                      || pass.userTextureInputs[0] == nil),
                  consumer.contentKind == "model",
                  consumer.dependencyLayerIDs == [providerID] else {
                issues.append(.init(
                    kind: .dependencyMismatch,
                    layerID: consumer.id,
                    providerLayerID: providerID
                ))
                continue
            }
            guard let provider = layersByID[providerID] else {
                issues.append(.init(
                    kind: .missingProvider,
                    layerID: consumer.id,
                    providerLayerID: providerID
                ))
                continue
            }
            guard reference.variant == .primary else {
                issues.append(.init(
                    kind: .unsupportedVariant,
                    layerID: consumer.id,
                    providerLayerID: providerID
                ))
                continue
            }
            guard consumer.id != providerID,
                  ["image", "solid"].contains(provider.contentKind),
                  provider.utilityLayer.map({ _ in false }) ?? true,
                  provider.visible == false,
                  provider.effects.isEmpty,
                  provider.dependencyLayerIDs.isEmpty,
                  provider.childLayerIDs.isEmpty,
                  let consumerOrder = order[consumer.id],
                  let providerOrder = order[providerID],
                  consumerOrder != providerOrder else {
                issues.append(.init(
                    kind: consumer.id == providerID
                        ? .cyclicDependency : .forwardUtilityProvider,
                    layerID: consumer.id,
                    providerLayerID: providerID
                ))
                continue
            }
            guard !routeDisabled else {
                issues.append(.init(
                    kind: .namedProviderRouteDisabled,
                    layerID: consumer.id,
                    providerLayerID: providerID
                ))
                continue
            }
            bindings[consumer.id] = .init(
                consumerLayerID: consumer.id,
                providerLayerID: providerID,
                materialPath: pass.materialPath,
                passIndex: pass.passIndex,
                slotIndex: 0,
                variant: reference.variant,
                requiresForwardCapture: providerOrder > consumerOrder
            )
        }
        return .init(bindings: bindings, issues: issues)
    }

    private nonisolated static func normalizedStaticModelAssetPath(
        _ value: String
    ) -> String? {
        let normalized = value.replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let components = normalized.split(
            separator: "/", omittingEmptySubsequences: false
        )
        guard !normalized.isEmpty,
              !normalized.hasPrefix("/"),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else { return nil }
        return normalized.localizedLowercase
    }
}
