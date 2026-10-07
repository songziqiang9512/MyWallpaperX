import Foundation

enum SceneBaseMaterialProviderBindingCompiler {
    /// Share the complete prepared proof only where its actual property producer
    /// and source consumer agree. Unsupported inputs cannot lower color alone.
    nonisolated static func admittedSourceMaterials(
        _ bindings: [SceneBaseMaterialColorModulationCompiler.Binding],
        descriptor: SceneRenderDescriptor,
        materialInstancesByLayerID: [Int: SceneDocument.SceneLayerMaterialInstance],
        propertyProgram: ScenePropertyBindingProgram,
        namedLayerIDs: Set<Int>
    ) -> [SceneBaseMaterialColorModulationCompiler.Binding] {
        let targets = Set(propertyProgram.instructions.map(\.target))
        return bindings.filter { fact in
            if let target = fact.alphaPropertyTarget {
                guard targets.contains(target),
                      let range = propertyProgram.definitions.first(where: { $0.target == target })?
                        .userPropertyNumericRange,
                      range.lowerBound >= 0, range.upperBound <= 1 else { return false }
            }
            return descriptor.layers.filter {
                $0.imagePath.map { normalized($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    == fact.modelPath
            }.allSatisfy {
                materialInstancesByLayerID[$0.id] == nil && !namedLayerIDs.contains($0.id)
            }
        }
    }

    nonisolated static func compile(
        descriptor: SceneRenderDescriptor,
        materialInstancesByLayerID: [
            Int: SceneDocument.SceneLayerMaterialInstance
        ],
        scriptBindings: [SceneScriptBindingIR],
        materialPropertyTargets: Set<SceneDynamicTarget>,
        materialColorTargets: [String: SceneDynamicTarget] = [:],
        provenBindings: [SceneBaseMaterialColorModulationCompiler.Binding] = []
    ) -> SceneBaseMaterialProviderBindingProgram {
        _ = scriptBindings
        let provenModels = Set(provenBindings.map(\.modelPath))
        let texturePropertyKeys = Set(descriptor.texturePropertyKeys)
        let passesByLayer = SceneMaterialPropertyBindingCompiler.imageMaterialPasses(descriptor: descriptor)
        var accepted: [Int: SceneBaseMaterialProviderBindingProgram.BaseMaterialBinding] = [:]
        var rejected: [Int: String] = [:]

        for layer in descriptor.layers where layer.isImageRenderable {
            let materialPasses = passesByLayer[layer.id] ?? []
            let candidate: (
                source: SceneBaseMaterialProviderBindingProgram.BaseMaterialBinding.Source,
                textureSlots: [String?],
                userTextureInputs: [SceneEffectTextureInput?]
            )?
            if let instance = materialInstancesByLayerID[layer.id],
               instance.hasUserTextureOverride {
                let instanceProviders = Set(claimedProviders(
                    instance.userTextureInputs,
                    texturePropertyKeys: texturePropertyKeys
                ))
                guard !instance.isMalformed, instance.unknownKeys.isEmpty else {
                    rejected[layer.id] = rejectionReason(
                        providers: instanceProviders,
                        suffix: "instance-shape-invalid"
                    )
                    continue
                }
                guard !instanceProviders.isEmpty else { continue }
                guard instance.textureSlots.indices.contains(0),
                      let instanceFallback = instance.textureSlots[0],
                      instanceFallbackMatchesLoadedBase(
                        instanceFallback,
                        layer: layer,
                        materialPasses: materialPasses
                      ) else {
                    rejected[layer.id] = rejectionReason(
                        providers: instanceProviders,
                        suffix: "instance-fallback-mismatch"
                    )
                    continue
                }
                candidate = (
                    .layerInstance,
                    instance.textureSlots,
                    instance.userTextureInputs
                )
            } else {
                let claimedPasses = materialPasses.filter {
                    containsClaimedProvider(
                        $0.userTextureInputs,
                        texturePropertyKeys: texturePropertyKeys
                    )
                }
                guard claimedPasses.count <= 1 else {
                    let providers = Set(claimedPasses.flatMap {
                        claimedProviders(
                            $0.userTextureInputs,
                            texturePropertyKeys: texturePropertyKeys
                        )
                    })
                    rejected[layer.id] = providers.count == 1
                        ? "\(providers.first!.diagnosticPrefix)-multi-pass-unsupported"
                        : "base-material-provider-multi-pass-unsupported"
                    continue
                }
                guard let pass = claimedPasses.first else { continue }
                guard materialPasses.count == 1 else {
                    let provider = claimedProviders(
                        pass.userTextureInputs,
                        texturePropertyKeys: texturePropertyKeys
                    ).first
                    rejected[layer.id] = provider.map {
                        "\($0.diagnosticPrefix)-multi-pass-unsupported"
                    } ?? "base-material-provider-multi-pass-unsupported"
                    continue
                }
                candidate = (
                    .materialPass,
                    pass.textureSlots,
                    pass.userTextureInputs
                )
            }

            guard let candidate,
                  containsClaimedProvider(
                    candidate.userTextureInputs,
                    texturePropertyKeys: texturePropertyKeys
                  ) else {
                continue
            }
            let providers = Set(claimedProviders(
                candidate.userTextureInputs,
                texturePropertyKeys: texturePropertyKeys
            ))
            guard providers.count == 1, let provider = providers.first else {
                rejected[layer.id] = "base-material-provider-identity-conflict"
                continue
            }
            let occupied = candidate.userTextureInputs.indices.filter {
                candidate.userTextureInputs[$0] != nil
            }
            guard occupied == [0],
                  candidate.userTextureInputs[0]?.kind == provider.authoredKind,
                  candidate.userTextureInputs[0]?.value == provider.authoredName,
                  candidate.textureSlots.indices.contains(0),
                  candidate.textureSlots[0] != nil else {
                rejected[layer.id] =
                    "\(provider.diagnosticPrefix)-slot-shape-unsupported"
                continue
            }
            accepted[layer.id] = .init(
                layerID: layer.id,
                source: candidate.source,
                slotIndex: 0,
                provider: provider
            )
        }
        return .init(
            baseMaterialBindings: accepted,
            rejectedBaseMaterialReasons: rejected,
            lightingProfileByLayerID: SceneBaseMaterialLightingProfileCompiler
                .profiles(
                    descriptor: descriptor,
                    materialInstancesByLayerID: materialInstancesByLayerID,
                    materialPropertyTargets: materialPropertyTargets
                ),
            sourceMaterialAlphaByLayerID: descriptor.layers.reduce(into: [:]) {
                result, layer in
                if let path = layer.imagePath,
                   provenModels.contains(normalized(path).trimmingCharacters(in: .whitespacesAndNewlines)) {
                    return
                }
                result[layer.id] = SceneMaterialPropertyBindingCompiler
                    .sourceMaterialAlpha(
                        layer: layer,
                        instance: materialInstancesByLayerID[layer.id],
                        passes: passesByLayer[layer.id] ?? [],
                        materialPropertyTargets: materialPropertyTargets
                    )
            },
            authoredMaterialColors: Dictionary(uniqueKeysWithValues: provenBindings.map {
                ($0.modelPath, SIMD3<Float>($0.authoredColor))
            }),
            materialColorTargets: materialColorTargets,
            sourceMaterialAlphaByModel: Dictionary(uniqueKeysWithValues: provenBindings.map { fact in
                let alpha: SceneBaseMaterialProviderBindingProgram.SourceMaterialAlpha
                if let target = fact.alphaPropertyTarget {
                    alpha = .property(target: target, fallback: fact.authoredAlpha)
                } else {
                    alpha = .constant(fact.authoredAlpha)
                }
                return (fact.modelPath, alpha)
            })
        )
    }

    private nonisolated static func containsClaimedProvider(
        _ inputs: [SceneEffectTextureInput?],
        texturePropertyKeys: Set<String>
    ) -> Bool {
        !claimedProviders(
            inputs,
            texturePropertyKeys: texturePropertyKeys
        ).isEmpty
    }

    private nonisolated static func claimedProviders(
        _ inputs: [SceneEffectTextureInput?],
        texturePropertyKeys: Set<String>
    ) -> [SceneBaseMaterialProviderBindingProgram.BaseMaterialBinding.Provider] {
        inputs.compactMap { input in
            switch input?.value {
            case SceneBaseMaterialProviderBindingProgram.currentIdentity:
                .current
            case SceneBaseMaterialProviderBindingProgram.previousIdentity:
                .previous
            case let value? where texturePropertyKeys.contains(value):
                SceneUserPropertyTextureIdentity(
                    propertyKey: value,
                    purpose: .premultipliedColor
                ).map {
                    SceneBaseMaterialProviderBindingProgram.BaseMaterialBinding
                        .Provider.userProperty($0)
                }
            default:
                nil
            }
        }
    }

    private nonisolated static func instanceFallbackMatchesLoadedBase(
        _ instanceFallback: String,
        layer: SceneRenderDescriptor.Layer,
        materialPasses: [SceneRenderDescriptor.MaterialPassDescriptor]
    ) -> Bool {
        if materialPasses.count == 1,
           let pass = materialPasses.first,
           pass.textureSlots.indices.contains(0),
           let loadedFallback = pass.textureSlots[0] {
            return normalized(instanceFallback) == normalized(loadedFallback)
        }
        // Solid layers intentionally use the shared procedural white carrier;
        // their stock material is not duplicated into the descriptor catalog.
        guard materialPasses.isEmpty,
              layer.contentKind == "solid",
              let path = SceneVFSAssetPath(instanceFallback) else { return false }
        return SceneStockTextureSemanticRegistry.isNeutralColorCarrier(path)
    }

    private nonisolated static func rejectionReason(
        providers: Set<
            SceneBaseMaterialProviderBindingProgram.BaseMaterialBinding.Provider
        >,
        suffix: String
    ) -> String {
        guard providers.count == 1, let provider = providers.first else {
            return "base-material-provider-\(suffix)"
        }
        return "\(provider.diagnosticPrefix)-\(suffix)"
    }

    private nonisolated static func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").localizedLowercase
    }
}
