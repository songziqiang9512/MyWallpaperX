import Foundation

/// Codable mirror of one material shader schema sampler, shared by the
/// persistent tiers that persist sampler facts. Rebuild validates every
/// stringified enum against its known case set and returns nil on any
/// unknown value so stale or foreign records degrade to a safe miss.
nonisolated struct ScenePersistentSamplerRecord: Codable, Equatable {
    let name: String
    let slot: Int
    let mode: String
    let materialKey: String?
    let labelKey: String?
    let formatKey: String?
    let isHidden: Bool
    let defaultTextureKind: Int?
    let defaultTextureValue: String?
    let readinessCombo: String?
    let channelUse: String
    let sourceProvenPurpose: String?

    init(sampler: SceneResolvedMaterialShaderSchema.Sampler) {
        name = sampler.name
        slot = sampler.slot
        mode = ScenePersistentSamplerRecord.modeName(sampler.mode)
        materialKey = sampler.materialKey
        labelKey = sampler.labelKey
        formatKey = sampler.formatKey
        isHidden = sampler.isHidden
        switch sampler.defaultTexture {
        case nil:
            defaultTextureKind = nil
            defaultTextureValue = nil
        case let .asset(path):
            defaultTextureKind = 0
            defaultTextureValue = path.value
        case let .internalTarget(name):
            defaultTextureKind = 1
            defaultTextureValue = name.authoredName
        }
        readinessCombo = sampler.readinessCombo
        channelUse = sampler.channelUse.rawValue
        sourceProvenPurpose = sampler.sourceProvenPurpose
            .map(Self.purposeName)
    }

    /// Deterministic order key so payloads stay byte-stable across
    /// processes despite Set iteration order.
    var canonicalSortKey: String {
        [
            name, String(slot), mode,
            materialKey ?? "-", labelKey ?? "-",
            formatKey ?? "-", isHidden ? "1" : "0",
            defaultTextureKind.map(String.init) ?? "-",
            defaultTextureValue ?? "-",
            readinessCombo ?? "-", channelUse,
            sourceProvenPurpose ?? "-",
        ].joined(separator: "|")
    }

    func rebuild()
    -> SceneResolvedMaterialShaderSchema.Sampler? {
        let rebuiltMode: SceneResolvedMaterialShaderSchema.TextureMode
        switch mode {
        case "regular": rebuiltMode = .regular
        case "opacity-mask": rebuiltMode = .opacityMask
        case "rgb-mask": rebuiltMode = .rgbMask
        case "flow-mask": rebuiltMode = .flowMask
        case "depth": rebuiltMode = .depth
        default: return nil
        }
        let defaultTexture: SceneResolvedMaterialShaderSchema.DefaultTexture?
        switch defaultTextureKind {
        case nil: defaultTexture = nil
        case 0:
            guard let value = defaultTextureValue,
                  let path = SceneVFSAssetPath(value) else { return nil }
            defaultTexture = .asset(path)
        case 1:
            guard let value = defaultTextureValue,
                  !value.isEmpty else { return nil }
            defaultTexture = .internalTarget(.init(authoredName: value))
        default: return nil
        }
        let purpose: SceneTextureLoadPurpose?
        switch sourceProvenPurpose {
        case nil: purpose = nil
        case "premultiplied-color": purpose = .premultipliedColor
        case "straight-albedo": purpose = .straightAlbedo
        case "preserved-channels": purpose = .preservedChannels
        case "mask": purpose = .mask
        case "noise": purpose = .noise
        case "flow": purpose = .flow
        case "phase": purpose = .phase
        case "normal": purpose = .normal
        case "depth": purpose = .depth
        case "lookup-table": purpose = .lookupTable
        default: return nil
        }
        guard let channelUse = SceneAuthoredShaderProgram
            .TextureBinding.ChannelUse(rawValue: channelUse)
        else { return nil }
        return SceneResolvedMaterialShaderSchema.Sampler(
            name: name,
            slot: slot,
            mode: rebuiltMode,
            materialKey: materialKey,
            labelKey: labelKey,
            formatKey: formatKey,
            isHidden: isHidden,
            defaultTexture: defaultTexture,
            readinessCombo: readinessCombo,
            channelUse: channelUse,
            sourceProvenPurpose: purpose
        )
    }

    private static func modeName(
        _ mode: SceneResolvedMaterialShaderSchema.TextureMode
    ) -> String {
        switch mode {
        case .regular: return "regular"
        case .opacityMask: return "opacity-mask"
        case .rgbMask: return "rgb-mask"
        case .flowMask: return "flow-mask"
        case .depth: return "depth"
        }
    }

    private static func purposeName(
        _ purpose: SceneTextureLoadPurpose
    ) -> String {
        switch purpose {
        case .premultipliedColor: return "premultiplied-color"
        case .straightAlbedo: return "straight-albedo"
        case .preservedChannels: return "preserved-channels"
        case .mask: return "mask"
        case .noise: return "noise"
        case .flow: return "flow"
        case .phase: return "phase"
        case .normal: return "normal"
        case .depth: return "depth"
        case .lookupTable: return "lookup-table"
        }
    }
}
