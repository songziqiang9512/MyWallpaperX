import Foundation

/// Cross-checks the bounded two-source composite proof against exact graph
/// identities and immutable unit host data before granting product authority.
nonisolated enum SceneResolvedMaterialUnitPreviousBlurredCompositeEligibility {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias Template = SceneResolvedMaterialTemplate

    struct Slots: Equatable {
        let blurred: Int
        let previous: Int
    }

    static func slots(
        fragmentSource: String,
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
        template: Template,
        implicitFramebufferIdentity: Graph.TextureIdentity?,
        activeGraphTextureIdentities: [Int: Graph.TextureIdentity]
    ) -> Slots? {
        guard let fact = SceneAuthoredShaderUnitPreviousBlurredCompositeAnalyzer
            .analyze(fragmentSource: fragmentSource),
              let previousIdentity = implicitFramebufferIdentity,
              previousIdentity.name == nil,
              previousIdentity.kind == .layerSource
                || previousIdentity.kind == .effectOutput,
              let blurredIdentity = activeGraphTextureIdentities[fact.blurredSlot],
              blurredIdentity.kind == .framebuffer,
              blurredIdentity.name != nil,
              blurredIdentity.layerID == previousIdentity.layerID,
              blurredIdentity.effect == template.effectContext?.key,
              Set(samplers.keys) == Set([fact.blurredSlot, fact.previousSlot]),
              samplers[fact.blurredSlot]?.mode == .regular,
              samplers[fact.previousSlot]?.mode == .regular,
              activeGraphTextureIdentities == [
                  fact.blurredSlot: blurredIdentity,
                  fact.previousSlot: previousIdentity,
              ], exactGraphCandidate(
                  slot: fact.blurredSlot,
                  identity: blurredIdentity,
                  template: template
              ), exactGraphCandidate(
                  slot: fact.previousSlot,
                  identity: previousIdentity,
                  template: template
              ), exactUnitColor(
                  named: fact.unitColorUniform,
                  template: template
              ) else { return nil }
        return .init(blurred: fact.blurredSlot, previous: fact.previousSlot)
    }

    private static func exactGraphCandidate(
        slot: Int, identity: Graph.TextureIdentity, template: Template
    ) -> Bool {
        guard template.textureSlots.indices.contains(slot),
              let declaration = template.textureSlots[slot],
              !declaration.candidates.isEmpty else { return false }
        return declaration.candidates.allSatisfy {
            guard case let .graph(candidate) = $0.reference else { return false }
            return candidate == identity
        }
    }

    private static func exactUnitColor(
        named name: String, template: Template
    ) -> Bool {
        let matches = template.uniformDeclarations.filter { $0.name == name }
        guard matches.count == 1, let declaration = matches.first,
              case let .staticExact(value) = declaration.value,
              value.componentBitPatterns.count == 3 else { return false }
        return value.componentBitPatterns.allSatisfy {
            Double(bitPattern: $0) == 1
        }
    }
}
