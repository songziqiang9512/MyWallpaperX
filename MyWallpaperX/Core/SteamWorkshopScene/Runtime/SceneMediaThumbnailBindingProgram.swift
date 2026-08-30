import Foundation

/// Launch-immutable projection of authored base-material system texture slots.
/// The binding selects a resource in the existing frame registry; it never
/// publishes that resource as a layer source or owns compositor output.
nonisolated struct SceneMediaThumbnailBindingProgram {
    struct BaseMaterialBinding: Hashable {
        enum Source: String, Hashable {
            case layerInstance = "layer-instance"
            case materialPass = "material-pass"
        }

        enum Provider: String, Hashable {
            case current
            case previous

            var authoredName: String {
                switch self {
                case .current:
                    SceneMediaThumbnailBindingProgram.currentIdentity
                case .previous:
                    SceneMediaThumbnailBindingProgram.previousIdentity
                }
            }

            var textureIdentity: SceneTextureProviderIdentity {
                switch self {
                case .current: .mediaThumbnailCurrent
                case .previous: .mediaThumbnailPrevious
                }
            }

            var diagnosticPrefix: String {
                "base-material-\(rawValue)"
            }
        }

        let layerID: Int
        let source: Source
        let slotIndex: Int
        let provider: Provider

        init(
            layerID: Int,
            source: Source,
            slotIndex: Int,
            provider: Provider = .current
        ) {
            self.layerID = layerID
            self.source = source
            self.slotIndex = slotIndex
            self.provider = provider
        }

        var providerIdentity: SceneSystemProviderTextureIdentity {
            .init(name: provider.authoredName,
                  purpose: .premultipliedColor)
        }
    }

    static let currentIdentity = "$mediaThumbnail"
    static let previousIdentity = "$mediaPreviousThumbnail"

    let baseMaterialBindings: [Int: BaseMaterialBinding]
    let rejectedBaseMaterialReasons: [Int: String]

    nonisolated init(
        baseMaterialBindings: [Int: BaseMaterialBinding],
        rejectedBaseMaterialReasons: [Int: String] = [:]
    ) {
        self.baseMaterialBindings = baseMaterialBindings
        self.rejectedBaseMaterialReasons = rejectedBaseMaterialReasons
    }

    static let empty = SceneMediaThumbnailBindingProgram(
        baseMaterialBindings: [:]
    )

    var currentLayerIDs: Set<Int> {
        layerIDs(for: .current)
    }

    var previousLayerIDs: Set<Int> {
        layerIDs(for: .previous)
    }

    var hasConsumers: Bool {
        !baseMaterialBindings.isEmpty
    }

    var systemProviderDemands: Set<SceneSystemProviderTextureIdentity> {
        Set(baseMaterialBindings.values.map(\.providerIdentity))
    }

    func reportLines() -> [String] {
        let previousRejectedCount = rejectedBaseMaterialReasons.values.filter {
            $0.hasPrefix("base-material-previous-")
        }.count
        let currentRejectedCount = rejectedBaseMaterialReasons.count
            - previousRejectedCount
        return [
            "mediaThumbnailCurrentBindingCount: \(currentLayerIDs.count)",
            "mediaThumbnailCurrentBindingLayerIDs: "
                + currentLayerIDs.sorted().map(String.init).joined(separator: ","),
            "mediaThumbnailCurrentBaseMaterialBindingCount: "
                + "\(currentLayerIDs.count)",
            "mediaThumbnailPreviousBindingCount: \(previousLayerIDs.count)",
            "mediaThumbnailPreviousBindingLayerIDs: "
                + previousLayerIDs.sorted().map(String.init).joined(separator: ","),
            "mediaThumbnailPreviousBaseMaterialBindingCount: "
                + "\(previousLayerIDs.count)",
            "mediaThumbnailCurrentBaseMaterialRejectedCount: "
                + "\(currentRejectedCount)",
            "mediaThumbnailPreviousBaseMaterialRejectedCount: "
                + "\(previousRejectedCount)",
            "mediaThumbnailBaseMaterialRejectedCount: "
                + "\(rejectedBaseMaterialReasons.count)",
        ]
    }

    private func layerIDs(for provider: BaseMaterialBinding.Provider) -> Set<Int> {
        Set(baseMaterialBindings.compactMap { layerID, binding in
            binding.provider == provider ? layerID : nil
        })
    }
}

enum SceneMediaThumbnailBindingCompiler {
    nonisolated static func compile(
        descriptor: SceneRenderDescriptor,
        materialInstancesByLayerID: [
            Int: SceneDocument.SceneLayerMaterialInstance
        ],
        scriptBindings: [SceneScriptBindingIR]
    ) -> SceneMediaThumbnailBindingProgram {
        _ = scriptBindings
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
        var accepted: [Int: SceneMediaThumbnailBindingProgram.BaseMaterialBinding] = [:]
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
                source: SceneMediaThumbnailBindingProgram.BaseMaterialBinding.Source,
                textureSlots: [String?],
                userTextureInputs: [SceneEffectTextureInput?]
            )?
            if let instance = materialInstancesByLayerID[layer.id],
               instance.hasUserTextureOverride {
                guard !instance.isMalformed, instance.unknownKeys.isEmpty else {
                    rejected[layer.id] = "base-material-instance-shape-invalid"
                    continue
                }
                guard containsClaimedProvider(instance.userTextureInputs) else {
                    continue
                }
                guard instance.textureSlots.indices.contains(0),
                      let instanceFallback = instance.textureSlots[0],
                      instanceFallbackMatchesLoadedBase(
                        instanceFallback,
                        layer: layer,
                        materialPasses: materialPasses
                      ) else {
                    rejected[layer.id] = "base-material-instance-fallback-mismatch"
                    continue
                }
                candidate = (
                    .layerInstance,
                    instance.textureSlots,
                    instance.userTextureInputs
                )
            } else {
                let claimedPasses = materialPasses.filter {
                    containsClaimedProvider($0.userTextureInputs)
                }
                guard claimedPasses.count <= 1 else {
                    let providers = Set(claimedPasses.flatMap {
                        claimedProviders($0.userTextureInputs)
                    })
                    rejected[layer.id] = providers.count == 1
                        ? "\(providers.first!.diagnosticPrefix)-multi-pass-unsupported"
                        : "base-material-system-provider-multi-pass-unsupported"
                    continue
                }
                guard let pass = claimedPasses.first else { continue }
                guard materialPasses.count == 1 else {
                    let provider = claimedProviders(pass.userTextureInputs).first
                    rejected[layer.id] = provider.map {
                        "\($0.diagnosticPrefix)-multi-pass-unsupported"
                    } ?? "base-material-system-provider-multi-pass-unsupported"
                    continue
                }
                candidate = (
                    .materialPass,
                    pass.textureSlots,
                    pass.userTextureInputs
                )
            }

            guard let candidate,
                  containsClaimedProvider(candidate.userTextureInputs) else {
                continue
            }
            let providers = Set(claimedProviders(candidate.userTextureInputs))
            guard providers.count == 1, let provider = providers.first else {
                rejected[layer.id] = "base-material-system-provider-identity-conflict"
                continue
            }
            let occupied = candidate.userTextureInputs.indices.filter {
                candidate.userTextureInputs[$0] != nil
            }
            guard occupied == [0],
                  candidate.userTextureInputs[0]?.kind == .system,
                  candidate.userTextureInputs[0]?.value ==
                    provider.authoredName,
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
        _ inputs: [SceneEffectTextureInput?]
    ) -> Bool {
        !claimedProviders(inputs).isEmpty
    }

    private nonisolated static func claimedProviders(
        _ inputs: [SceneEffectTextureInput?]
    ) -> [SceneMediaThumbnailBindingProgram.BaseMaterialBinding.Provider] {
        inputs.compactMap { input in
            switch input?.value {
            case SceneMediaThumbnailBindingProgram.currentIdentity:
                .current
            case SceneMediaThumbnailBindingProgram.previousIdentity:
                .previous
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

    private nonisolated static func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").localizedLowercase
    }
}

/// Exact initial-state projection for the two stock album-cover visibility
/// scripts observed in legal Workshop assets. The system starts without a
/// published thumbnail, so these effects are inactive until a future unified
/// dynamic-topology owner supports their event lifecycle.
nonisolated enum SceneInitialMediaEffectVisibilityProjection {
    struct EffectOwner: Hashable {
        let layerID: Int
        let effectIndex: Int
    }

    static func initiallyInactiveOwners(
        scriptBindings: [SceneScriptBindingIR],
        sourceEvidence: [SceneScriptSourceEvidenceIR] = []
    ) -> Set<EffectOwner> {
        var owners = Set<EffectOwner>(scriptBindings.compactMap { binding -> EffectOwner? in
            guard binding.owner.kind == .effect,
                  binding.targetKey == "visible",
                  binding.valueType == .boolean,
                  isSupportedVisibilitySource(binding.source),
                  let layerID = binding.owner.objectID,
                  let effectIndex = binding.owner.effectIndex else {
                return nil
            }
            return EffectOwner(layerID: layerID, effectIndex: effectIndex)
        })
        owners.formUnion(sourceEvidence.compactMap { evidence -> EffectOwner? in
            guard evidence.owner.kind == .effect,
                  evidence.targetKey == "visible",
                  evidence.wrapperKeys == ["script", "user", "value"],
                  isSupportedVisibilitySource(evidence.source),
                  let layerID = evidence.owner.objectID,
                  let effectIndex = evidence.owner.effectIndex else {
                return nil
            }
            return EffectOwner(layerID: layerID, effectIndex: effectIndex)
        })
        return owners
    }

    static func apply(
        to descriptor: SceneRenderDescriptor,
        scriptBindings: [SceneScriptBindingIR],
        sourceEvidence: [SceneScriptSourceEvidenceIR] = []
    ) -> SceneRenderDescriptor {
        let owners = initiallyInactiveOwners(
            scriptBindings: scriptBindings,
            sourceEvidence: sourceEvidence
        )
        guard !owners.isEmpty else { return descriptor }
        var projected = descriptor
        for layerIndex in projected.layers.indices {
            let layerID = projected.layers[layerIndex].id
            for effectIndex in projected.layers[layerIndex].effects.indices
                where owners.contains(.init(layerID: layerID, effectIndex: effectIndex)) {
                projected.layers[layerIndex].effects[effectIndex].visible = false
            }
        }
        return projected
    }

    private static func isSupportedVisibilitySource(_ source: String) -> Bool {
        let compact = source.replacingOccurrences(
            of: #"/\*[\s\S]*?\*/"#,
            with: "",
            options: .regularExpression
        ).replacingOccurrences(
            of: #"//[^\n\r]*"#,
            with: "",
            options: .regularExpression
        ).replacingOccurrences(
            of: #"\s+"#,
            with: "",
            options: .regularExpression
        )
        let body = compact.replacingOccurrences(
            of: #"^['\"]usestrict['\"];?"#,
            with: "",
            options: .regularExpression
        )
        let direct = #"^exportfunctionmediaThumbnailChanged\(([A-Za-z_$][A-Za-z0-9_$]*)\)\{thisObject\.visible=\1\.hasThumbnail;?\}$"#
        let timed = #"^varlastHideEvent;?exportfunctionmediaThumbnailChanged\(([A-Za-z_$][A-Za-z0-9_$]*)\)\{if\(lastHideEvent\)\{lastHideEvent\(\);lastHideEvent=undefined;?\}thisObject\.visible=\1\.hasThumbnail;if\(\1\.hasThumbnail\)\{lastHideEvent=engine\.setTimeout\(\(\)=>\{thisObject\.visible=false;?\},1000\);?\}\}$"#
        return body.range(of: direct, options: .regularExpression) != nil
            || body.range(of: timed, options: .regularExpression) != nil
    }
}
