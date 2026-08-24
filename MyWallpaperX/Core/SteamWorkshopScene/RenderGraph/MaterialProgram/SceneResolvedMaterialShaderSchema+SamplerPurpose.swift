extension SceneResolvedMaterialShaderSchema.TextureMode {
    nonisolated var explicitPurpose: SceneTextureLoadPurpose? {
        switch self {
        case .regular: nil
        case .opacityMask: .mask
        case .rgbMask: .preservedChannels
        case .flowMask: .flow
        case .depth: .depth
        }
    }
}

extension SceneResolvedMaterialShaderSchema {
    nonisolated static func hasOnlyScalarDataInputs(
        _ samplers: [Int: Sampler],
        activeSlots: Set<Int>,
        resolvedFormats: [Int: SceneShaderTextureFormat]
    ) -> Bool {
        activeSlots.allSatisfy { slot in
            if let format = resolvedFormats[slot] {
                return format == .r8 || format == .r16f
            }
            guard let sampler = samplers[slot] else { return false }
            return sampler.mode == .opacityMask || sampler.mode == .depth
        }
    }

    nonisolated static func hasOnlyDefaultedOpacityMaskAuxiliary(
        _ samplers: [Int: Sampler],
        graphInputSlots: Set<Int>
    ) -> Bool {
        guard graphInputSlots.count == 1,
              graphInputSlots.allSatisfy({ slot in
                guard let sampler = samplers[slot] else { return false }
                return sampler.mode == .regular && sampler.defaultTexture == nil
              }) else { return false }
        let auxiliaries = samplers.filter { !graphInputSlots.contains($0.key) }
        guard auxiliaries.count == 1,
              let auxiliary = auxiliaries.values.first else { return false }
        return auxiliary.mode == .opacityMask && auxiliary.defaultTexture != nil
    }

    nonisolated static func hasOnlyTypedOpacityMaskAuxiliary(
        _ samplers: [Int: Sampler],
        graphInputSlots: Set<Int>
    ) -> Bool {
        guard graphInputSlots.count == 1,
              graphInputSlots.allSatisfy({ slot in
                guard let sampler = samplers[slot] else { return false }
                return sampler.mode == .regular && sampler.defaultTexture == nil
              }) else { return false }
        let auxiliaries = samplers.filter { !graphInputSlots.contains($0.key) }
        guard auxiliaries.count == 1,
              let auxiliary = auxiliaries.values.first else { return false }
        return auxiliary.mode == .opacityMask
    }

    /// A structural compatibility normalization for historical authored
    /// materials that omitted the explicit framebuffer annotation.
    nonisolated static func implicitFramebufferSlots(
        template: Template,
        samplers: [Int: Sampler]
    ) -> Set<Int> {
        guard template.textureSlots.count == 8,
              template.graphRole.bindings.isEmpty,
              template.textureSlots[0] == nil,
              let sampler = samplers[0],
              sampler.name == "g_Texture0",
              sampler.mode == .regular,
              sampler.materialKey == nil,
              sampler.defaultTexture == nil,
              samplers.allSatisfy({ slot, auxiliary in
                  slot == 0 || hasAuthoredAuxiliarySource(
                      sampler: auxiliary,
                      slot: template.textureSlots[slot]
                  )
              }),
              template.textureSlots.enumerated().allSatisfy({ index, slot in
                  guard index != 0, let slot else { return true }
                  return slot.candidates.allSatisfy { candidate in
                      if case .graph = candidate.reference { return false }
                      return true
                  }
              }) else { return [] }
        return [0]
    }

    /// An explicit non-graph authored candidate proves only that this sampler
    /// is an auxiliary rather than a competing implicit graph input. Its load
    /// purpose remains a separate Program admission contract and may still
    /// fail closed without erasing the valid slot-zero previous/current role.
    private nonisolated static func hasAuthoredAuxiliarySource(
        sampler: Sampler,
        slot: Template.TextureSlot?
    ) -> Bool {
        if sampler.mode.explicitPurpose != nil || sampler.hasTypedAuxiliaryDefault {
            return true
        }
        guard let slot, !slot.candidates.isEmpty else { return false }
        return slot.candidates.allSatisfy { candidate in
            if case .graph = candidate.reference { return false }
            return true
        }
    }
}

extension SceneResolvedMaterialShaderSchema.Sampler {
    nonisolated var usesGraphInputMaterialAlias: Bool {
        switch materialKey?.lowercased() {
        case "framebuffer", "previous": true
        case "ui_editor_properties_framebuffer":
            name == "g_Texture0" && slot == 0 && mode == .regular && isHidden
        default: false
        }
    }

    nonisolated func purpose(
        for reference: SceneResolvedMaterialTemplate.TextureReference
    ) -> SceneTextureLoadPurpose? {
        if case .graph = reference {
            return mode.explicitPurpose ?? .premultipliedColor
        }
        if case let .provider(provider) = reference {
            switch provider {
            case .namedLayerTarget:
                // A named layer target is always a same-frame compositor
                // color publication. Author metadata such as `rgbmask`
                // describes ordinary asset decoding and must not relabel the
                // provider atom as data after dependency admission proved the
                // exact named reference.
                return .premultipliedColor
            case .sceneBackground:
                return mode.explicitPurpose ?? .premultipliedColor
            case .system:
                break
            }
        }
        guard case let .asset(path) = reference else {
            return declaredPurpose
        }
        let registeredPurpose = SceneStockTextureSemanticRegistry.purpose(for: path)
        guard declaredPurpose == nil || registeredPurpose == nil
                || declaredPurpose == registeredPurpose else {
            return nil
        }
        let candidatePurpose = registeredPurpose ?? declaredPurpose

        // A regular sampler's typed asset default is a slot-level author
        // contract. An authored asset override may inherit only that proven
        // role; a candidate with its own conflicting registry role is rejected.
        // The default remains source metadata, never a runtime texture fallback.
        guard mode == .regular,
              declaredPurpose == nil,
              case let .asset(defaultPath)? = defaultTexture,
              let defaultPurpose = SceneStockTextureSemanticRegistry.purpose(
                  for: defaultPath
              ) else {
            return candidatePurpose
        }
        guard candidatePurpose == nil || candidatePurpose == defaultPurpose else {
            return nil
        }
        return candidatePurpose ?? defaultPurpose
    }

    private nonisolated var declaredPurpose: SceneTextureLoadPurpose? {
        if let purpose = mode.explicitPurpose { return purpose }
        return switch materialKey?.lowercased() {
        case "albedo": .straightAlbedo
        case "noise": .noise
        case "normal": .normal
        default: nil
        }
    }

    nonisolated var hasTypedAuxiliaryDefault: Bool {
        guard case let .asset(path)? = defaultTexture else { return false }
        let reference = SceneResolvedMaterialTemplate.TextureReference.asset(path)
        return purpose(for: reference) != nil
    }

    nonisolated var hasExplicitNonColorPurpose: Bool {
        if mode.explicitPurpose != nil { return true }
        return switch materialKey?.lowercased() {
        case "noise", "normal": true
        default: false
        }
    }
}

extension SceneResolvedMaterialShaderSchema {
    typealias GraphInputFact = SceneResolvedMaterialGraphInputSourceSlotFact

    /// Canonical classification for explicit aliases, the historical missing
    /// alias, and a strictly bounded dormant authored alias. The dormant case
    /// is source-led: arbitrary editor key/label text never grants execution.
    nonisolated static func graphInputSourceSlotFacts(
        template: Template,
        samplers: [Int: Sampler],
        inputIdentity: Graph.TextureIdentity?,
        sourceColorTransfer: SceneShaderColorTransfer? = nil,
        frontendBindings: [SceneAuthoredShaderProgram.TextureBinding]? = nil
    ) -> [Int: GraphInputFact] {
        guard let inputIdentity,
              exactEffectInput(inputIdentity, template: template) else {
            return [:]
        }
        var facts: [Int: GraphInputFact] = [:]
        let implicit = implicitFramebufferSlots(
            template: template,
            samplers: samplers
        )
        for (slot, sampler) in samplers {
            let provenance: GraphInputFact.Provenance?
            if sampler.usesGraphInputMaterialAlias {
                provenance = .explicitMaterialAlias
            } else if implicit.contains(slot) {
                provenance = .implicitMissingAlias
            } else {
                provenance = nil
            }
            if let provenance {
                let selectionProvenance:
                    SceneResolvedMaterialProgram.TextureSelectionProvenance
                switch provenance {
                case .explicitMaterialAlias:
                    selectionProvenance = sampler.materialKey?.lowercased()
                        == "previous"
                        ? .materialGraphInputAlias : .implicitFramebuffer
                case .implicitMissingAlias:
                    selectionProvenance = .implicitFramebuffer
                case .dormantUnresolvedMaterialAlias:
                    selectionProvenance =
                        .dormantUnresolvedMaterialGraphInput
                }
                facts[slot] = .init(
                    slot: slot,
                    inputIdentity: inputIdentity,
                    provenance: provenance,
                    selectionProvenance: selectionProvenance
                )
            }
        }
        guard facts.isEmpty,
              template.effectContext != nil,
              let transferSlot = graphInputColorCarrierSlot(sourceColorTransfer),
              samplers.count == 1,
              let sampler = samplers[transferSlot],
              sampler.slot == transferSlot,
              sampler.mode == .regular,
              sampler.isHidden,
              sampler.materialKey?.contains(where: { !$0.isWhitespace }) == true,
              !sampler.usesGraphInputMaterialAlias,
              !sampler.hasExplicitNonColorPurpose,
              sampler.defaultTexture == nil,
              sampler.readinessCombo == nil,
              template.graphRole.bindings.isEmpty,
              template.textureSlots.allSatisfy({ $0 == nil }) else {
            return facts
        }
        if let frontendBindings {
            guard frontendBindings.count == 1,
                  let binding = frontendBindings.first,
                  binding.slot == transferSlot,
                  binding.name == sampler.name else {
                return [:]
            }
        }
        facts[transferSlot] = GraphInputFact(
            slot: transferSlot,
            inputIdentity: inputIdentity,
            provenance: GraphInputFact.Provenance
                .dormantUnresolvedMaterialAlias,
            selectionProvenance:
                SceneResolvedMaterialProgram.TextureSelectionProvenance
                    .dormantUnresolvedMaterialGraphInput
        )
        return facts
    }

    private nonisolated static func graphInputColorCarrierSlot(
        _ transfer: SceneShaderColorTransfer?
    ) -> Int? {
        switch transfer {
        case let .passthrough(slot),
             let .straightAlphaPreserving(slot):
            slot
        case .interpolatedColor, .straightAlpha, .straightAlphaUNorm,
             .independentAlphaSignal, .independentAlphaSignalPreserving,
             .independentAlphaSignalCompositing, .premultipliedAlpha,
             .opaque, .unresolved, nil:
            nil
        }
    }

    private nonisolated static func exactEffectInput(
        _ input: Graph.TextureIdentity,
        template: Template
    ) -> Bool {
        guard input.name == nil,
              input.kind == .layerSource || input.kind == .effectOutput else {
            return false
        }
        guard let context = template.effectContext else {
            return true
        }
        guard input == context.input,
              input.layerID == context.key.layerID else { return false }
        if context.key.effectIndex == 0 {
            return input.kind == .layerSource && input.effect == nil
        }
        guard input.kind == .effectOutput,
              let producer = input.effect else { return false }
        return producer.layerID == context.key.layerID
            && producer.effectIndex == context.key.effectIndex - 1
    }
}
