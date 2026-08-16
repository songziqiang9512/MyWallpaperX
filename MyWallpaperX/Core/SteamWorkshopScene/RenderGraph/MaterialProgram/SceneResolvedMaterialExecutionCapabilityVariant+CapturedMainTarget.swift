import Foundation

extension SceneResolvedMaterialVariantCache {
    private enum AuthoredCapturedSource {
        case implicit
        case explicit(slot: Int)
    }

    struct LaunchEnvelopeCapabilitySnapshot {
        let template: Template
        let variants: [Variant]
        let allEntriesReady: Bool
        let reachableSamplers: [
            Int: Set<SceneResolvedMaterialShaderSchema.Sampler>
        ]?
        let inputIdentity: Graph.TextureIdentity?
        let hasCachedReachability: Bool
    }

    /// Launch-envelope compilation is the authority for host audio demand.
    /// Raw source declarations are insufficient because inactive variants and
    /// rejected array shapes must not keep system audio capture alive.
    var hasAudioSpectrumConsumer: Bool {
        launchEnvelopeCapabilitySnapshot().variants.contains { variant in
            let activeTextureSlots = Set(
                variant.frontendProgram.textureBindings.map(\.slot)
            )
            return variant.frontendProgram.uniformLayout.fields.contains { field in
                switch SceneResolvedMaterialUniformEncoder.hostUniform(
                    field,
                    activeTextureSlots: activeTextureSlots
                ) {
                case .audioSpectrumLeft, .audioSpectrumRight:
                    return true
                default:
                    return false
                }
            }
        }
    }

    /// A renderer-owned main-target capture is executable only when every
    /// prepared launch variant consumes one exact layer-source color slot.
    var supportsCapturedMainTargetTexture: Bool {
        let snapshot = launchEnvelopeCapabilitySnapshot()
        guard snapshot.hasCachedReachability,
              let inputIdentity = snapshot.inputIdentity,
              inputIdentity.kind == .layerSource,
              inputIdentity.effect == nil,
              inputIdentity.name == nil,
              snapshot.allEntriesReady,
              !snapshot.variants.isEmpty,
              let reachable = snapshot.reachableSamplers,
              exactCapturedInputRole(snapshot.template.graphRole) else {
            return false
        }
        guard reachable.allSatisfy({ _, samplers in
            samplers.filter(\.usesGraphInputMaterialAlias).allSatisfy {
                $0.mode == .regular && $0.defaultTexture == nil
            }
        }) else { return false }
        let reachableSlots = snapshot.variants.compactMap {
            capturedSourceSlot(
                snapshot.template,
                samplers: $0.activeSamplers
            )
        }
        guard reachableSlots.count == snapshot.variants.count,
              Set(reachableSlots).count == 1,
              let reachableSlot = reachableSlots.first,
              let authoredSource = authoredSource(
                  snapshot.template,
                  inputIdentity: inputIdentity,
                  sourceSlot: reachableSlot
              ) else {
            return false
        }
        if case let .explicit(slot) = authoredSource,
           slot != reachableSlot { return false }

        return snapshot.variants.allSatisfy { variant in
            guard capturedSourceSlot(
                    snapshot.template,
                    samplers: variant.activeSamplers
                  ) == reachableSlot,
                  variant.frontendProgram.textureBindings.filter({
                      $0.slot == reachableSlot
                  }).count == 1,
                  colorSourceSlot(variant.frontendProgram.colorTransfer)
                    == reachableSlot else {
                return false
            }
            return true
        }
    }

    private func capturedSourceSlot(
        _ template: Template,
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler]
    ) -> Int? {
        guard samplers.values.filter(\.usesGraphInputMaterialAlias).allSatisfy({
            $0.mode == .regular && $0.defaultTexture == nil
        }) else { return nil }
        let aliases = samplers.compactMap { slot, sampler -> Int? in
            guard sampler.usesGraphInputMaterialAlias else { return nil }
            return slot
        }
        let implicit = SceneResolvedMaterialShaderSchema.implicitFramebufferSlots(
            template: template,
            samplers: samplers
        )
        let slots = Set(aliases).union(implicit)
        return slots.count == 1 ? slots.first : nil
    }

    /// Distinguishes one explicit authored source slot from the historical
    /// implicit framebuffer form while keeping every other shape closed.
    private func authoredSource(
        _ template: Template,
        inputIdentity: Graph.TextureIdentity,
        sourceSlot: Int
    ) -> AuthoredCapturedSource? {
        let source: AuthoredCapturedSource
        switch template.graphRole.bindings.count {
        case 0:
            source = .implicit
        case 1:
            guard let binding = template.graphRole.bindings.first,
                  binding.texture == .layerSource else { return nil }
            source = .explicit(slot: binding.slot)
        default:
            return nil
        }

        var graphSlots: [Int] = []
        for (slot, declaration) in template.textureSlots.enumerated() {
            guard let declaration else { continue }
            if case .implicit = source, slot == sourceSlot,
               !declaration.candidates.isEmpty { return nil }
            for candidate in declaration.candidates {
                switch candidate.reference {
                case let .graph(identity):
                    guard identity == inputIdentity else { return nil }
                    graphSlots.append(slot)
                case .provider:
                    return nil
                case .asset, .userProperty:
                    break
                }
            }
        }
        if case let .explicit(bindingSlot) = source {
            guard graphSlots == [bindingSlot],
                  template.textureSlots[bindingSlot]?.candidates.count == 1
            else { return nil }
        } else {
            guard graphSlots.isEmpty else { return nil }
        }
        return source
    }

    private func exactCapturedInputRole(_ role: Template.GraphRole) -> Bool {
        role.effectInput == .layerSource
            && role.effectOutput == .effectOutput
            && role.nodeTarget == .effectOutput
    }

    private func colorSourceSlot(_ transfer: SceneShaderColorTransfer) -> Int? {
        switch transfer {
        case let .passthrough(slot),
             let .straightAlphaPreserving(slot),
             let .straightAlpha(slot),
             let .straightAlphaUNorm(slot):
            return slot
        case let .independentAlphaSignalCompositing(_, colorSlot):
            return colorSlot
        case .interpolatedColor,
             .independentAlphaSignal, .independentAlphaSignalPreserving,
             .premultipliedAlpha, .opaque, .unresolved:
            return nil
        }
    }
}
