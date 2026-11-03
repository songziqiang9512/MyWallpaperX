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
        guard reference.variant != .unspecified else { return false }
        if input.kind == .layerSource {
            return reference.variant == .primary && input.effect == nil
        }
        guard input.kind == .effectOutput,
              let producer = input.effect else { return false }
        return producer.layerID == consumer.layerID
            && producer.effectIndex + 1 == consumer.effectIndex
    }
}

/// Shared selected-input identity checks for dependency and captured-main
/// ingress. Shader mathematics remain owned by the compiled Program.
nonisolated enum SceneResolvedMaterialPreviousBlurredCompositeEligibility {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias Template = SceneResolvedMaterialTemplate

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
    /// or identity cannot stand in for the selected graph ingress.
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
}
