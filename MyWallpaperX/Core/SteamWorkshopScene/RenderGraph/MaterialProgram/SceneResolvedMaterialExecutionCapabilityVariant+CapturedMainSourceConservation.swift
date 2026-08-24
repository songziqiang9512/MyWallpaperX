import Foundation

extension SceneResolvedMaterialVariantCache {
    private enum CapturedMainTargetProgramRole: Hashable {
        case sourceConsumer(slot: Int)
        case internalFramebufferOnly
    }

    /// Classifies one material in a captured-main stage without projecting the
    /// stage source requirement onto internal framebuffer-only Programs.
    func capturedMainTargetSourceSlot(
        node: Graph.Node,
        effect: Graph.Effect
    ) -> Int? {
        guard case let .sourceConsumer(slot) = capturedMainTargetProgramRole(
            node: node,
            effect: effect
        ) else { return nil }
        return slot
    }

    func supportsCapturedMainTargetInternalProgram(
        node: Graph.Node,
        effect: Graph.Effect
    ) -> Bool {
        capturedMainTargetProgramRole(node: node, effect: effect)
            == .internalFramebufferOnly
    }

    private func capturedMainTargetProgramRole(
        node: Graph.Node,
        effect: Graph.Effect
    ) -> CapturedMainTargetProgramRole? {
        let snapshot = launchEnvelopeCapabilitySnapshot()
        guard node.kind == .material,
              node.effect == effect.key,
              exactLayerSource(effect.input, layerID: effect.key.layerID),
              exactEffectOutput(effect.output, effect: effect.key),
              snapshot.hasCachedReachability,
              snapshot.inputIdentity == effect.input,
              snapshot.allEntriesReady,
              !snapshot.variants.isEmpty,
              snapshot.reachableSamplers != nil,
              exactGraphReferences(
                  snapshot.template,
                  node: node,
                  effect: effect
              ) else { return nil }

        let sourceBindings = node.bindings.filter {
            $0.texture.kind == .layerSource
        }
        guard sourceBindings.count <= 1,
              node.bindings.allSatisfy({ binding in
                  guard binding.slot != nil else { return false }
                  return binding.texture == effect.input
                      || exactEffectFramebuffer(
                          binding.texture,
                          effect: effect.key
                      )
              }) else { return nil }

        let roles = snapshot.variants.compactMap { variant in
            variantRole(
                variant,
                template: snapshot.template,
                node: node,
                effect: effect,
                sourceBinding: sourceBindings.first
            )
        }
        guard roles.count == snapshot.variants.count,
              Set(roles).count == 1,
              let role = roles.first,
              let target = node.target else { return nil }
        switch role {
        case .sourceConsumer:
            guard target == effect.output
                    || exactEffectFramebuffer(target, effect: effect.key)
            else { return nil }
        case .internalFramebufferOnly:
            guard sourceBindings.allSatisfy({ binding in
                      guard let slot = binding.slot else { return false }
                      return snapshot.variants.allSatisfy { variant in
                          !variant.frontendProgram.textureBindings.contains {
                              $0.slot == slot
                          }
                      }
                  }),
                  exactEffectFramebuffer(target, effect: effect.key)
            else { return nil }
        }
        return role
    }

    private func variantRole(
        _ variant: Variant,
        template: Template,
        node: Graph.Node,
        effect: Graph.Effect,
        sourceBinding: Graph.Binding?
    ) -> CapturedMainTargetProgramRole? {
        let activeSlots = Set(
            variant.frontendProgram.textureBindings.map(\.slot)
        )
        guard activeSlots.count
                == variant.frontendProgram.textureBindings.count,
              activeSlots == Set(variant.activeSamplers.keys),
              variant.graphInputSourceSlotFacts.allSatisfy({ slot, fact in
                  guard fact.slot == slot,
                        fact.inputIdentity == effect.input,
                        let sampler = variant.activeSamplers[slot] else {
                      return false
                  }
                  return sampler.mode == .regular
                      && sampler.defaultTexture == nil
              }) else { return nil }
        let activeBindings = node.bindings.filter { binding in
            guard let slot = binding.slot else { return false }
            return activeSlots.contains(slot)
        }
        let boundSlots = Set(activeBindings.compactMap(\.slot))
        let activeSourceBinding: Graph.Binding? = sourceBinding.flatMap { binding in
            guard let slot = binding.slot, activeSlots.contains(slot) else {
                return nil
            }
            return binding
        }
        let unboundSourceSlots = Set(
            variant.graphInputSourceSlotFacts.keys
        ).subtracting(boundSlots)
        let sourceSlots: Set<Int>
        if let activeSourceBinding, let slot = activeSourceBinding.slot {
            sourceSlots = unboundSourceSlots.union([slot])
        } else {
            sourceSlots = unboundSourceSlots
        }
        guard sourceSlots.count <= 1 else { return nil }

        for slot in activeSlots {
            guard template.textureSlots.indices.contains(slot) else { return nil }
            let graphReferences = template.textureSlots[slot]?.candidates.compactMap {
                candidate -> Graph.TextureIdentity? in
                guard case let .graph(identity) = candidate.reference else {
                    return nil
                }
                return identity
            } ?? []
            guard graphReferences.allSatisfy({ identity in
                identity == effect.input
                    || exactEffectFramebuffer(identity, effect: effect.key)
            }) else { return nil }
        }

        guard let sourceSlot = sourceSlots.first else {
            return activeSourceBinding == nil ? .internalFramebufferOnly : nil
        }
        guard let sourceSampler = variant.activeSamplers[sourceSlot],
              sourceSampler.mode == .regular,
              sourceSampler.defaultTexture == nil else { return nil }
        if let activeSourceBinding {
            guard activeSourceBinding.slot == sourceSlot,
                  activeSourceBinding.texture == effect.input,
                  template.textureSlots.indices.contains(sourceSlot),
                  let declaration = template.textureSlots[sourceSlot],
                  declaration.candidates.count == 1,
                  declaration.candidates.contains(where: {
                      if case let .graph(identity) = $0.reference {
                          return identity == effect.input
                      }
                      return false
                  }) else { return nil }
        } else {
            guard node.bindings.isEmpty,
                  template.textureSlots.indices.contains(sourceSlot),
                  template.textureSlots[sourceSlot] == nil else { return nil }
        }
        guard variant.frontendProgram.textureBindings.filter({
                  $0.slot == sourceSlot
              }).count == 1,
              capturedMainColorSourceSlot(
                  variant.frontendProgram.colorTransfer
              )
                == sourceSlot else { return nil }
        return .sourceConsumer(slot: sourceSlot)
    }

    private func exactGraphReferences(
        _ template: Template,
        node: Graph.Node,
        effect: Graph.Effect
    ) -> Bool {
        var expectedBySlot: [Int: Graph.TextureIdentity] = [:]
        for binding in node.bindings {
            guard let slot = binding.slot,
                  template.textureSlots.indices.contains(slot),
                  expectedBySlot.updateValue(binding.texture, forKey: slot) == nil
            else { return false }
        }
        for slot in template.textureSlots.indices {
            var references: [Graph.TextureIdentity] = []
            for candidate in template.textureSlots[slot]?.candidates ?? [] {
                switch candidate.reference {
                case let .graph(identity):
                    references.append(identity)
                case .asset:
                    break
                case .userProperty:
                    break
                case .provider:
                    // Provider candidates are auxiliary resource provenance,
                    // not another graph ingress. Their reservation,
                    // publication, epoch and active-sampler readiness remain
                    // owned by dependency admission and texture finalization.
                    break
                }
            }
            let expected = expectedBySlot[slot].map { [$0] } ?? []
            guard references == expected,
                  references.allSatisfy({ identity in
                      identity == effect.input
                          || exactEffectFramebuffer(identity, effect: effect.key)
                  }) else { return false }
        }
        return true
    }

    private func exactLayerSource(
        _ identity: Graph.TextureIdentity,
        layerID: Int
    ) -> Bool {
        identity.kind == .layerSource
            && identity.layerID == layerID
            && identity.effect == nil
            && identity.name == nil
    }

    private func exactEffectOutput(
        _ identity: Graph.TextureIdentity,
        effect: Graph.EffectKey
    ) -> Bool {
        identity.kind == .effectOutput
            && identity.layerID == effect.layerID
            && identity.effect == effect
            && identity.name == nil
    }

    private func exactEffectFramebuffer(
        _ identity: Graph.TextureIdentity,
        effect: Graph.EffectKey
    ) -> Bool {
        identity.kind == .framebuffer
            && identity.layerID == effect.layerID
            && identity.effect == effect
            && identity.name?.isEmpty == false
    }

    private func capturedMainColorSourceSlot(
        _ transfer: SceneShaderColorTransfer
    ) -> Int? {
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
