extension SceneResolvedMaterialShaderSchema.Sampler {
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
