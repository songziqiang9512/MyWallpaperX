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
                  slot == 0 || hasTypedAuxiliarySource(
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

    private nonisolated static func hasTypedAuxiliarySource(
        sampler: Sampler,
        slot: Template.TextureSlot?
    ) -> Bool {
        if sampler.mode.explicitPurpose != nil || sampler.hasTypedAuxiliaryDefault {
            return true
        }
        guard let slot, !slot.candidates.isEmpty else { return false }
        return slot.candidates.allSatisfy { candidate in
            guard case .graph = candidate.reference else {
                return sampler.purpose(for: candidate.reference) != nil
            }
            return false
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
}
