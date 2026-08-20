/// Cross-checks the source-derived attenuation fact against active material
/// schema and graph-input identity before it can grant route authority.
nonisolated enum SceneResolvedMaterialAlphaAttenuationEligibility {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias Template = SceneResolvedMaterialTemplate

    static func sourceSlot(
        fragmentSource: String,
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
        template: Template,
        implicitFramebufferIdentity: Graph.TextureIdentity?
    ) -> Int? {
        guard let fact = SceneAuthoredShaderAlphaAttenuationAnalyzer.analyze(
            fragmentSource: fragmentSource
        ), validated(
            fact: fact,
            samplers: samplers,
            template: template,
            implicitFramebufferIdentity: implicitFramebufferIdentity
        ) else { return nil }
        return fact.sourceSlot
    }

    static func validated(
        fact: SceneAuthoredShaderAlphaAttenuationFact,
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
        template: Template,
        implicitFramebufferIdentity: Graph.TextureIdentity?
    ) -> Bool {
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
            template: template
        ) else { return false }
        return fact.auxiliaryRedSlots.allSatisfy {
            !slotMaySelectGraphTexture(
                $0,
                samplers: samplers,
                template: template
            )
        }
    }

    private static func sourceSlotSelectsExactInput(
        _ slot: Int,
        inputIdentity: Graph.TextureIdentity,
        inputRole: Template.GraphTextureRole,
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
        template: Template
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
        return SceneResolvedMaterialShaderSchema.implicitFramebufferSlots(
            template: template,
            samplers: samplers
        ).contains(slot) || samplers[slot]?.usesGraphInputMaterialAlias == true
    }

    private static func slotMaySelectGraphTexture(
        _ slot: Int,
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
        template: Template
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
        return SceneResolvedMaterialShaderSchema.implicitFramebufferSlots(
            template: template,
            samplers: samplers
        ).contains(slot) || samplers[slot]?.usesGraphInputMaterialAlias == true
    }
}
