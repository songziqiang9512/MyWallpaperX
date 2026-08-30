import Foundation

/// Proves that a lower-precedence named-layer candidate is only authored
/// provenance for an exact `previous -> effect.input` graph binding. The
/// selected graph identity remains the sole runtime owner; this predicate does
/// not publish or consume either named target variant.
nonisolated enum SceneResolvedMaterialExactPreviousInputShadow {
    typealias Graph = SceneAuthoredEffectRenderPlan

    static func accepts(
        _ reference: SceneNamedTextureReference,
        input: Graph.TextureIdentity,
        consumer: Graph.EffectKey
    ) -> Bool {
        guard reference.providerLayerID == input.layerID,
              input.layerID == consumer.layerID,
              input.name == nil else { return false }
        switch reference.variant {
        case .unspecified:
            return false
        case .primary:
            return input.kind == .layerSource && input.effect == nil
        case .secondary:
            guard input.kind == .effectOutput,
                  let producer = input.effect else { return false }
            return producer.layerID == consumer.layerID
                && producer.effectIndex + 1 == consumer.effectIndex
        }
    }
}

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
              ], exactGraphOverride(
                  slot: fact.blurredSlot,
                  identity: blurredIdentity,
                  template: template,
                  allowsNamedInputProvenance: false
              ), exactGraphOverride(
                  slot: fact.previousSlot,
                  identity: previousIdentity,
                  template: template,
                  allowsNamedInputProvenance: true
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

    /// An explicit graph binding is the immutable high-precedence selection.
    /// The previous-input slot may retain one exact named-target candidate
    /// below it as provenance; internal blurred slots stay graph-only.
    static func exactGraphOverride(
        slot: Int,
        identity: Graph.TextureIdentity,
        template: Template,
        allowsNamedInputProvenance: Bool
    ) -> Bool {
        guard template.textureSlots.indices.contains(slot),
              let declaration = template.textureSlots[slot],
              let selected = declaration.candidates.last,
              selected.provenance == .explicitBinding,
              case let .graph(candidate) = selected.reference,
              candidate == identity else { return false }
        let provenance = declaration.candidates.dropLast()
        guard provenance.isEmpty || allowsNamedInputProvenance else {
            return false
        }
        guard provenance.count <= 1 else { return false }
        return provenance.allSatisfy {
            guard $0.provenance == .instance,
                  case let .provider(.namedLayerTarget(reference)) = $0.reference,
                  let context = template.effectContext
            else { return false }
            return SceneResolvedMaterialExactPreviousInputShadow.accepts(
                reference,
                input: identity,
                consumer: context.key
            )
        }
    }

    /// The graph binding that shadows named input provenance is intentionally
    /// identical to the dependency-owner predicate. A different alias, slot,
    /// or identity must keep the incumbent instead of opening an owner gap.
    static func exactPreviousInputBinding(
        bindings: [Graph.Binding],
        slot: Int,
        identity: Graph.TextureIdentity
    ) -> Bool {
        let matches = bindings.filter { $0.slot == slot }
        return matches.count == 1
            && matches[0].authoredName == "previous"
            && matches[0].texture == identity
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
