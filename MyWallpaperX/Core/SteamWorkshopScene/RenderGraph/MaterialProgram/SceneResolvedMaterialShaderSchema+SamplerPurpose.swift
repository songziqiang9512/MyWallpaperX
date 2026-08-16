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
        let declaredPurpose: SceneTextureLoadPurpose? = if let purpose = mode.explicitPurpose {
            purpose
        } else {
            switch materialKey?.lowercased() {
            case "albedo": .straightAlbedo
            case "noise": .noise
            case "normal": .normal
            default: nil
            }
        }
        if case .graph = reference {
            return mode.explicitPurpose ?? .premultipliedColor
        }
        if case .provider(.namedLayerTarget) = reference {
            return mode.explicitPurpose ?? .premultipliedColor
        }
        guard case let .asset(path) = reference,
              let registeredPurpose = SceneStockTextureSemanticRegistry.purpose(
                  for: path
              ) else {
            return declaredPurpose
        }
        guard declaredPurpose == nil || declaredPurpose == registeredPurpose else {
            return nil
        }
        return registeredPurpose
    }

    nonisolated var hasTypedAuxiliaryDefault: Bool {
        guard case let .asset(path)? = defaultTexture else { return false }
        let reference = SceneResolvedMaterialTemplate.TextureReference.asset(path)
        return purpose(for: reference) != nil
    }
}
