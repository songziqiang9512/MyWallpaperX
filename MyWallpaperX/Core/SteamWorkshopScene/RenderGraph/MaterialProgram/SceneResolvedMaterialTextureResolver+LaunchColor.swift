import Foundation

nonisolated extension SceneResolvedMaterialTextureResolver {
    typealias LaunchColorFact = SceneResolvedMaterialProgramDerivation.ColorTextureFact

    /// Runs frame color derivation for a material fed by the renderer-owned
    /// premultiplied layer capture. Later effectOutput stages, internal graph
    /// targets and dynamic providers retain the frame-time fail-closed gate.
    static func launchProgramFailure(
        template: Template,
        variants: [SceneResolvedMaterialCompiledVariant],
        readinessMask: UInt8,
        formatSlots: Set<Int>,
        outputStorage: SceneResolvedMaterialProgram.OutputStorage,
        implicitFramebufferIdentity: Graph.TextureIdentity?,
        assetStates: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState]
    ) -> Failure? {
        for variant in variants {
            for binding in variant.frontendProgram.textureBindings
            where readinessMask & (1 << UInt8(binding.slot)) == 0 {
                guard !formatSlots.contains(binding.slot),
                      let sampler = variant.activeSamplers[binding.slot],
                      presenceIndependentDefault(
                          template: template,
                          sampler: sampler,
                          slot: binding.slot
                      ) != nil else {
                    return failure(.textureBindingInvalid, slot: binding.slot)
                }
            }
            let preservedChannelOutput = outputStorage != .color
            if preservedChannelOutput {
                guard variant.frontendProgram.fragmentOutputChannelUse == .redDefined else {
                    return failure(
                        .colorContractUnproven,
                        phase: .color,
                        details: ["scalar-output-channel-unproven"]
                    )
                }
            } else if variant.frontendProgram.colorTransfer == .unresolved {
                return failure(
                    .colorContractUnproven,
                    phase: .color,
                    details: ["shader-color-transfer-unresolved"]
                )
            }
            if !preservedChannelOutput, case let .straightAlphaUNorm(slot) =
                variant.frontendProgram.colorTransfer {
                guard implicitFramebufferIdentity?.kind == .layerSource,
                      template.graphRole.effectInput == .layerSource,
                      template.graphRole.effectOutput == .effectOutput,
                      template.graphRole.nodeTarget == .effectOutput,
                      (0 ..< 8).contains(slot) else {
                    return failure(
                        .colorContractUnproven,
                        phase: .color,
                        details: ["straight-alpha-unorm-topology"]
                    )
                }
            }
            guard implicitFramebufferIdentity?.kind == .layerSource else {
                continue
            }
            let profiles: [[LaunchColorFact?]]
            switch launchColorProfiles(
                template: template,
                variant: variant,
                readinessMask: readinessMask,
                implicitFramebufferIdentity: implicitFramebufferIdentity,
                assetStates: assetStates
            ) {
            case .unknownInternalGraph:
                if !preservedChannelOutput, case .straightAlphaUNorm =
                    variant.frontendProgram.colorTransfer {
                    return failure(
                        .colorContractUnproven,
                        phase: .color,
                        details: ["straight-alpha-unorm-internal-graph"]
                    )
                }
                continue
            case .invalid:
                return failure(.textureBindingInvalid)
            case .profiles(let value):
                profiles = value
            }
            if preservedChannelOutput { continue }
            if case let .straightAlphaUNorm(slot) =
                variant.frontendProgram.colorTransfer {
                guard profiles.allSatisfy({ profile in
                    guard profile.indices.contains(slot),
                          let fact = profile[slot],
                          fact.isGraphReference else { return false }
                    return template.graphRole.bindings.isEmpty
                        || (template.graphRole.bindings.count == 1
                            && template.graphRole.bindings.contains {
                                $0.slot == slot && $0.texture == .layerSource
                            })
                }) else {
                    return failure(
                        .colorContractUnproven,
                        phase: .color,
                        details: ["straight-alpha-unorm-binding"]
                    )
                }
            }
            guard profiles.allSatisfy({
                SceneResolvedMaterialProgramDerivation.resolveColor(
                    transfer: variant.frontendProgram.colorTransfer,
                    textureFacts: $0
                ) != nil
            }) else {
                return failure(
                    .colorContractUnproven,
                    phase: .color,
                    details: ["launch-color-projection-unresolved"]
                )
            }
        }
        return nil
    }

    private enum LaunchColorProfiles {
        case profiles([[LaunchColorFact?]])
        case unknownInternalGraph
        case invalid
    }

    private static func launchColorProfiles(
        template: Template,
        variant: SceneResolvedMaterialCompiledVariant,
        readinessMask: UInt8,
        implicitFramebufferIdentity: Graph.TextureIdentity?,
        assetStates: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState]
    ) -> LaunchColorProfiles {
        var profiles = [Array<LaunchColorFact?>(repeating: nil, count: 8)]
        let implicitSlots = SceneResolvedMaterialShaderSchema
            .implicitFramebufferSlots(
                template: template,
                samplers: variant.activeSamplers
            )
        for binding in variant.frontendProgram.textureBindings {
            guard profiles.indices.contains(0), (0 ..< 8).contains(binding.slot),
                  let sampler = variant.activeSamplers[binding.slot] else {
                return .invalid
            }
            let reference: Template.TextureReference
            switch launchReference(
                template: template,
                sampler: sampler,
                slot: binding.slot,
                readinessMask: readinessMask,
                implicitFramebufferIdentity: implicitFramebufferIdentity,
                implicitSlots: implicitSlots,
                assetStates: assetStates
            ) {
            case let .selected(value): reference = value
            case .deferred: return .unknownInternalGraph
            case .invalid, .none: return .invalid
            }
            if case let .provider(provider) = reference {
                switch provider {
                case .system:
                    return .unknownInternalGraph
                case .namedLayerTarget, .sceneBackground:
                    break
                }
            }
            if case .userProperty = reference {
                return .unknownInternalGraph
            }
            if case let .graph(identity) = reference,
               identity != implicitFramebufferIdentity {
                return .unknownInternalGraph
            }
            guard let fact = launchFact(
                for: reference,
                sampler: sampler,
                implicitFramebufferIdentity: implicitFramebufferIdentity,
                assetStates: assetStates
            ) else { return .invalid }
            for profile in profiles {
                guard profile[binding.slot] == nil else { return .invalid }
            }
            profiles[0][binding.slot] = fact
        }
        return .profiles(profiles)
    }

    private enum LaunchReference {
        case selected(Template.TextureReference)
        case deferred
        case invalid
        case none
    }

    private static func launchReference(
        template: Template,
        sampler: SceneResolvedMaterialShaderSchema.Sampler,
        slot: Int,
        readinessMask: UInt8,
        implicitFramebufferIdentity: Graph.TextureIdentity?,
        implicitSlots: Set<Int>,
        assetStates: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState]
    ) -> LaunchReference {
        let ready = readinessMask & (UInt8(1) << UInt8(slot)) != 0
        if ready {
            do {
                switch try launchAuthoredReference(
                    template: template,
                    sampler: sampler,
                    slot: slot,
                    assetStates: assetStates
                ) {
                case let .selected(reference): return .selected(reference)
                case .deferred: return .deferred
                case .none: break
                }
            } catch {
                return .invalid
            }
        }
        let defaultAllowed = sampler.readinessCombo == nil
            || presenceIndependentDefault(
                template: template,
                sampler: sampler,
                slot: slot
            ) != nil
        if defaultAllowed, case let .asset(path)? = sampler.defaultTexture {
            let reference = Template.TextureReference.asset(path)
            do {
                switch try launchAssetState(
                    reference,
                    sampler: sampler,
                    assetStates: assetStates,
                    slot: slot
                ) {
                case .ready: return .selected(reference)
                case .absent: break
                case .pending, .unavailable: return .invalid
                }
            } catch {
                return .invalid
            }
        }
        if (sampler.usesGraphInputMaterialAlias || implicitSlots.contains(slot)),
           let identity = implicitFramebufferIdentity {
            return .selected(.graph(identity))
        }
        return .none
    }

    private static func launchFact(
        for reference: Template.TextureReference,
        sampler: SceneResolvedMaterialShaderSchema.Sampler,
        implicitFramebufferIdentity: Graph.TextureIdentity?,
        assetStates: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState]
    ) -> LaunchColorFact? {
        if case let .graph(identity) = reference {
            guard identity == implicitFramebufferIdentity else { return nil }
            return .init(
                isGraphReference: true,
                isFramebufferInput: true,
                content: .color(.resolved(.premultipliedAlpha))
            )
        }
        if case let .provider(provider) = reference {
            switch provider {
            case .namedLayerTarget:
                return .init(
                    isGraphReference: false,
                    isFramebufferInput: false,
                    content: .color(.resolved(.premultipliedAlpha))
                )
            case .sceneBackground:
                return .init(
                    isGraphReference: false,
                    isFramebufferInput: true,
                    content: .color(.resolved(.premultipliedAlpha))
                )
            case .system:
                return nil
            }
        }
        guard let purpose = sampler.purpose(for: reference) else { return nil }
        if case let .asset(path) = reference {
            let identity = SceneAssetTextureIdentity(path: path, purpose: purpose)
            guard case let .ready(content)? = assetStates[identity] else {
                return nil
            }
            return .init(
                isGraphReference: false,
                isFramebufferInput: false,
                content: content
            )
        }
        return nil
    }

    private static func failure(
        _ code: Failure.Code,
        phase: Failure.Phase = .texture,
        slot: Int? = nil,
        details: [String] = []
    ) -> Failure {
        .init(phase: phase, code: code, slot: slot, details: details)
    }
}
