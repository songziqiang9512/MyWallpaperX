import Foundation

nonisolated enum SceneTextureLoadPurpose: Hashable {
    case premultipliedColor
    case straightAlbedo
    case preservedChannels
    case mask
    case noise
    case flow
    case phase
    case normal
    case depth
    case lookupTable
}

extension SceneResolvedMaterialShaderSchema.TextureMode {
    // Synced from SceneResolvedMaterialShaderSchema+SamplerPurpose.swift.
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

extension SceneResolvedMaterialShaderSchema.Sampler {
    // Synced from SceneResolvedMaterialShaderSchema+SamplerPurpose.swift.
    nonisolated var usesGraphInputMaterialAlias: Bool {
        switch materialKey?.lowercased() {
        case "framebuffer", "previous":
            return true
        case "ui_editor_properties_framebuffer":
            return name == "g_Texture0" && slot == 0
                && mode == .regular && isHidden
        default:
            guard name == "g_Texture0", slot == 0,
                  mode == .regular, isHidden,
                  let key = materialKey?.lowercased(),
                  ["mask", "texture"].contains(key) else {
                return false
            }
            return labelKey?.lowercased()
                == "ui_editor_properties_framebuffer"
        }
    }

    nonisolated var permitsSourceStraightColorProjection: Bool {
        guard mode == .regular,
              !isHidden,
              sourceProvenPurpose == nil,
              declaredPurpose == nil,
              !usesGraphInputMaterialAlias else { return false }
        switch defaultTexture {
        case nil:
            return true
        case .internalTarget:
            return false
        case let .asset(path):
            guard let registered = SceneStockTextureSemanticRegistry.purpose(
                for: path
            ) else { return true }
            return registered == .straightAlbedo
        }
    }

    private nonisolated var declaredPurpose: SceneTextureLoadPurpose? {
        if let purpose = mode.explicitPurpose { return purpose }
        if formatKey?.caseInsensitiveCompare("normalmap") == .orderedSame {
            return .normal
        }
        return switch materialKey?.lowercased() {
        case "albedo": .straightAlbedo
        case "noise": .noise
        case "normal": .normal
        default: nil
        }
    }
}

extension SceneResolvedMaterialShaderSchema {
    // Synced from SceneResolvedMaterialShaderSchema+SamplerPurpose.swift.
    // The blur harness compiles the schema but not the purpose grab-bag
    // file; these entry points keep product behavior here instead of
    // stubbing it out.
    nonisolated static func validateTextureFormat(
        _ value: SceneShaderAnnotationValue?,
        mode: TextureMode,
        name: String
    ) throws {
        guard let value else { return }
        guard let raw = value.stringValue,
              !raw.isEmpty,
              raw == raw.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.unicodeScalars.contains(where: {
                  $0.value < 32 || $0.value == 127
              }) else {
            throw Issue.sampler(name)
        }
        if mode == .depth,
           raw.caseInsensitiveCompare("r8") != .orderedSame {
            throw Issue.sampler(name)
        }
    }

    nonisolated static func sourceTypedColorSamplers(
        _ samplers: [Int: Sampler],
        vertexSource: String,
        fragmentSource: String
    ) -> [Int: Sampler] {
        let auxiliary = sourceTypedAuxiliarySamplers(
            samplers,
            vertexSource: vertexSource,
            fragmentSource: fragmentSource
        )
        var result = auxiliary
        for (slot, sampler) in auxiliary {
            guard sampler.permitsSourceStraightColorProjection,
                  SceneAuthoredShaderTextureChannelAnalyzer
                      .provesStraightColorUse(
                          samplerName: sampler.name,
                          vertexSource: vertexSource,
                          fragmentSource: fragmentSource
                      ) else { continue }
            result[slot] = sampler.withSourceProvenPurpose(.straightAlbedo)
        }
        return result
    }
}
