import Foundation

enum SceneBaseMaterialProviderBindingCompiler {
    nonisolated static func compile(
        descriptor: SceneRenderDescriptor,
        materialInstancesByLayerID: [
            Int: SceneDocument.SceneLayerMaterialInstance
        ],
        scriptBindings: [SceneScriptBindingIR]
    ) -> SceneBaseMaterialProviderBindingProgram {
        _ = scriptBindings
        let texturePropertyKeys = Set(descriptor.texturePropertyKeys)
        let materialPathByModelPath = descriptor.modelMaterialLinks.reduce(
            into: [String: String]()
        ) { result, link in
            guard let materialPath = link.materialPath else { return }
            result[normalized(link.modelPath)] = normalized(materialPath)
        }
        let materialPassesByPath = Dictionary(
            grouping: descriptor.materialPasses,
            by: { normalized($0.materialPath) }
        )
        var accepted: [Int: SceneBaseMaterialProviderBindingProgram.BaseMaterialBinding] = [:]
        var rejected: [Int: String] = [:]

        for layer in descriptor.layers where layer.isImageRenderable {
            let materialPasses: [SceneRenderDescriptor.MaterialPassDescriptor]
            if let imagePath = layer.imagePath,
               let materialPath = materialPathByModelPath[normalized(imagePath)] {
                materialPasses = materialPassesByPath[materialPath] ?? []
            } else {
                materialPasses = []
            }
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
            rejectedBaseMaterialReasons: rejected
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
