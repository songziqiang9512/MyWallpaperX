import Foundation

/// Cross-checks the bounded two-source composite proof against exact graph
/// identities and immutable unit host data before granting product authority.
nonisolated enum SceneResolvedMaterialUnitPreviousBlurredCompositeEligibility {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias Template = SceneResolvedMaterialTemplate

    struct Slots: Equatable {
        let blurred: Int
        let previous: Int
        let mask: Int?
    }

    static func slots(
        fragmentSource: String,
        prepared: SceneShaderPreparedProgram,
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
        template: Template,
        implicitFramebufferIdentity: Graph.TextureIdentity?,
        activeGraphTextureIdentities: [Int: Graph.TextureIdentity]
    ) -> Slots? {
        guard template.unitPreviousBlurredCompositeGenericOwnerEligible,
              let fact = SceneAuthoredShaderUnitPreviousBlurredCompositeAnalyzer
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
              Set(samplers.keys) == Set(
                  [fact.blurredSlot, fact.previousSlot]
                    + (fact.maskSlot.map { [$0] } ?? [])
              ),
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
              ), exactMaskCandidate(
                  slot: fact.maskSlot,
                  samplers: samplers,
                  template: template
              ), exactUnitColor(
                  named: fact.unitColorUniform,
                  template: template,
                  prepared: prepared
              ) else { return nil }
        return .init(
            blurred: fact.blurredSlot,
            previous: fact.previousSlot,
            mask: fact.maskSlot
        )
    }

    private static func exactMaskCandidate(
        slot: Int?,
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
        template: Template
    ) -> Bool {
        guard let slot else { return true }
        guard template.textureSlots.indices.contains(slot),
              let declaration = template.textureSlots[slot],
              !declaration.candidates.isEmpty,
              samplers[slot]?.mode == .opacityMask else { return false }
        return declaration.candidates.allSatisfy {
            if case .asset = $0.reference { return true }
            return false
        }
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
        named name: String,
        template: Template,
        prepared: SceneShaderPreparedProgram
    ) -> Bool {
        guard let schema = SceneResolvedMaterialShaderSchema.uniqueActiveUniform(
            named: name,
            type: .float3,
            stage: .fragment,
            prepared: prepared
        ) else { return false }
        let keys = Set(schema.materialKeys)
        let declarations = template.uniformDeclarations.filter {
            keys.contains($0.name)
        }
        let value: Template.StaticUniformValue
        if declarations.isEmpty {
            guard let fallback = schema.defaultValue else { return false }
            value = fallback
        } else {
            guard declarations.count == 1,
                  case let .staticExact(authored) = declarations[0].value else {
                return false
            }
            value = authored
        }
        guard value.componentBitPatterns.count == 3 else { return false }
        return value.componentBitPatterns.allSatisfy {
            Double(bitPattern: $0) == 1
        }
    }
}
