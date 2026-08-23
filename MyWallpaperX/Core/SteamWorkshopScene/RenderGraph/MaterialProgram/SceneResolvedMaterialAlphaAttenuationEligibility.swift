/// Cross-checks the source-derived attenuation fact against active material
/// schema and graph-input identity before it can grant route authority.
nonisolated enum SceneResolvedMaterialAlphaAttenuationEligibility {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias Template = SceneResolvedMaterialTemplate

    static func sourceSlot(
        fragmentSource: String,
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
        template: Template,
        implicitFramebufferIdentity: Graph.TextureIdentity?,
        graphInputSourceSlotFacts: [
            Int: SceneResolvedMaterialGraphInputSourceSlotFact
        ] = [:]
    ) -> Int? {
        guard let fact = SceneAuthoredShaderAlphaAttenuationAnalyzer.analyze(
            fragmentSource: fragmentSource
        ) else { return nil }
        let graphFacts = graphInputSourceSlotFacts.isEmpty
            ? SceneResolvedMaterialShaderSchema.graphInputSourceSlotFacts(
                template: template,
                samplers: samplers,
                inputIdentity: implicitFramebufferIdentity,
                sourceColorTransfer:
                    SceneAuthoredShaderColorTransferAnalyzer.analyze(
                        fragmentSource: fragmentSource
                    )
            ) : graphInputSourceSlotFacts
        guard validated(
            fact: fact,
            samplers: samplers,
            template: template,
            implicitFramebufferIdentity: implicitFramebufferIdentity,
            graphInputSourceSlotFacts: graphFacts
        ) else { return nil }
        return fact.sourceSlot
    }

    static func validated(
        fact: SceneAuthoredShaderAlphaAttenuationFact,
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
        template: Template,
        implicitFramebufferIdentity: Graph.TextureIdentity?,
        graphInputSourceSlotFacts: [
            Int: SceneResolvedMaterialGraphInputSourceSlotFact
        ] = [:]
    ) -> Bool {
        let graphFacts = graphInputSourceSlotFacts.isEmpty
            ? SceneResolvedMaterialShaderSchema.graphInputSourceSlotFacts(
                template: template,
                samplers: samplers,
                inputIdentity: implicitFramebufferIdentity
            ) : graphInputSourceSlotFacts
        guard let inputIdentity = implicitFramebufferIdentity,
              inputIdentity.name == nil,
              inputIdentity.kind == .layerSource
                || inputIdentity.kind == .effectOutput,
              let inputRole = Template.GraphTextureRole(
                  rawValue: inputIdentity.kind.rawValue
              ),
              template.graphRole.effectInput == inputRole,
              template.graphRole.effectOutput == .effectOutput,
              template.graphRole.nodeTarget == .effectOutput else {
            return false
        }
        let factSlots = fact.auxiliaryRedSlots.union([fact.sourceSlot])
        guard Set(samplers.keys) == factSlots,
              samplers[fact.sourceSlot]?.mode == .regular,
              fact.auxiliaryRedSlots.allSatisfy({
                  samplers[$0]?.mode == .opacityMask
              }) else { return false }

        guard sourceSlotSelectsExactInput(
            fact.sourceSlot,
            inputIdentity: inputIdentity,
            inputRole: inputRole,
            samplers: samplers,
            template: template,
            graphInputSourceSlotFacts: graphFacts
        ) else { return false }
        return fact.auxiliaryRedSlots.allSatisfy {
            !slotMaySelectGraphTexture(
                $0,
                samplers: samplers,
                template: template,
                graphInputSourceSlotFacts: graphFacts
            )
        }
    }

    private static func sourceSlotSelectsExactInput(
        _ slot: Int,
        inputIdentity: Graph.TextureIdentity,
        inputRole: Template.GraphTextureRole,
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
        template: Template,
        graphInputSourceSlotFacts: [
            Int: SceneResolvedMaterialGraphInputSourceSlotFact
        ]
    ) -> Bool {
        if template.textureSlots.indices.contains(slot),
           let declaration = template.textureSlots[slot] {
            return !declaration.candidates.isEmpty
                && declaration.candidates.allSatisfy {
                    guard case let .graph(identity) = $0.reference else {
                        return false
                    }
                    return identity == inputIdentity
                }
        }
        if template.graphRole.bindings.contains(where: {
            $0.slot == slot && $0.texture == inputRole
        }) {
            return true
        }
        return graphInputSourceSlotFacts[slot]?.inputIdentity == inputIdentity
    }

    private static func slotMaySelectGraphTexture(
        _ slot: Int,
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
        template: Template,
        graphInputSourceSlotFacts: [
            Int: SceneResolvedMaterialGraphInputSourceSlotFact
        ]
    ) -> Bool {
        if template.graphRole.bindings.contains(where: { $0.slot == slot }) {
            return true
        }
        if template.textureSlots.indices.contains(slot),
           template.textureSlots[slot]?.candidates.contains(where: {
               if case .graph = $0.reference { return true }
               return false
           }) == true {
            return true
        }
        return graphInputSourceSlotFacts[slot] != nil
    }
}
