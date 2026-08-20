/// Cross-checks a source-derived color-blend fact against the active material
/// schema and exact graph-input identity before granting product authority.
nonisolated enum SceneResolvedMaterialColorBlendEligibility {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias Template = SceneResolvedMaterialTemplate

    static func sourceSlot(
        fragmentSource: String,
        colorTransfer: SceneShaderColorTransfer,
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
        template: Template,
        implicitFramebufferIdentity: Graph.TextureIdentity?
    ) -> Int? {
        guard let fact = SceneAuthoredShaderGraphInputColorBlendAnalyzer.analyze(
            fragmentSource: fragmentSource
        ), transfer(colorTransfer, matches: fact), validated(
            fact: fact,
            samplers: samplers,
            template: template,
            implicitFramebufferIdentity: implicitFramebufferIdentity
        ) else { return nil }
        return fact.sourceSlot
    }

    static func validated(
        fact: SceneAuthoredShaderGraphInputColorBlendFact,
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
              ), template.graphRole.effectInput == inputRole,
              template.graphRole.effectOutput == .effectOutput,
              template.graphRole.nodeTarget == .effectOutput,
              fact.auxiliaryRedSlots.count <= 1 else {
            return false
        }
        let factSlots = fact.auxiliaryRedSlots.union([fact.sourceSlot])
        guard Set(samplers.keys) == factSlots,
              samplers[fact.sourceSlot]?.mode == .regular,
              fact.auxiliaryRedSlots.allSatisfy({
                samplers[$0]?.mode == .opacityMask
              }), sourceSlotSelectsExactInput(
                fact.sourceSlot,
                inputIdentity: inputIdentity,
                inputRole: inputRole,
                samplers: samplers,
                template: template
              ) else { return false }
        return fact.auxiliaryRedSlots.allSatisfy {
            !slotMaySelectGraphTexture($0, samplers: samplers, template: template)
        }
    }

    private static func transfer(
        _ transfer: SceneShaderColorTransfer,
        matches fact: SceneAuthoredShaderGraphInputColorBlendFact
    ) -> Bool {
        switch (fact.alphaOutput, transfer) {
        case let (.preserved, .straightAlphaPreserving(slot)):
            slot == fact.sourceSlot
        case (.opaque, .opaque):
            true
        default:
            false
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

nonisolated extension SceneResolvedMaterialVariantCache {
    /// A finalizer hint may become an effect-local passthrough only when the
    /// complete launch envelope proves the new shared color-blend profile and
    /// the failed slot is a readiness-driven, non-graph opacity mask.
    func provesEffectLocalOptionalColorBlendTextureFailure(slot: Int) -> Bool {
        guard (0 ..< 8).contains(slot) else { return false }
        let snapshot = launchEnvelopeCapabilitySnapshot()
        let profile = SceneGenericShaderCapabilityProfile
            .sourceProvenGraphInputColorBlend.rawValue
        guard snapshot.hasCachedReachability,
              snapshot.inputIdentity != nil,
              snapshot.allEntriesReady,
              !snapshot.variants.isEmpty,
              let reachableSamplers = snapshot.reachableSamplers?[slot],
              !reachableSamplers.isEmpty,
              reachableSamplers.allSatisfy({
                  $0.mode == .opacityMask && $0.readinessCombo != nil
              }), let declaration = snapshot.template.textureSlots[slot],
              !declaration.candidates.isEmpty,
              declaration.candidates.allSatisfy({ candidate in
                  switch candidate.reference {
                  case .asset, .userProperty:
                      return true
                  case .provider, .graph:
                      return false
                  }
              }), !snapshot.template.graphRole.bindings.contains(where: {
                  $0.slot == slot
              }), snapshot.variants.allSatisfy({ variant in
                  guard variant.routeDecision.profile == profile else {
                      return false
                  }
                  let sampler = variant.activeSamplers[slot]
                  let bindings = variant.frontendProgram.textureBindings.filter {
                      $0.slot == slot
                  }
                  if let sampler {
                      return sampler.mode == .opacityMask
                          && sampler.readinessCombo != nil
                          && bindings.count == 1
                          && bindings[0].channelUse == .redOnly
                  }
                  return bindings.isEmpty
              }) else {
            return false
        }
        return snapshot.variants.contains {
            $0.activeSamplers[slot] != nil
        } && snapshot.variants.contains {
            $0.activeSamplers[slot] == nil
        }
    }
}
