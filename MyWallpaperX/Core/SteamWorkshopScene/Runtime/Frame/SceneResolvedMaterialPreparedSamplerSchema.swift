import Foundation

/// Immutable sampler facts shared by preparation and current-frame binding.
nonisolated struct SceneResolvedMaterialPreparedSamplerSchema: Hashable {
    typealias ChannelUse = SceneAuthoredShaderProgram.TextureBinding.ChannelUse

    enum TextureMode: Hashable {
        case regular
        case opacityMask
        case rgbMask
        case flowMask
        case depth
    }

    enum DefaultTexture: Hashable {
        case asset(SceneVFSAssetPath)
        case internalTarget(RenderTargetDefault)
    }

    struct RenderTargetDefault: Hashable {
        let authoredName: String
        let admission: SceneRenderTargetReferenceKind
    }

    let name: String
    let slot: Int
    let mode: TextureMode
    let materialKey: String?
    /// Authored annotation `label`. Wallpaper Engine editors express the
    /// slot-0 framebuffer input either through `material: framebuffer` or
    /// through the framebuffer label; the label lane must survive schema
    /// parsing for that alias to be recognized.
    let labelKey: String?
    /// Authored annotation `format` (e.g. `normalmap`). It declares the
    /// asset's data role for samplers that carry no mode/material fact.
    let formatKey: String?
    let isHidden: Bool
    let defaultTexture: DefaultTexture?
    /// An unmarked sampler combo describes whether an authored texture is
    /// actually bound. Its annotation default must not manufacture that
    /// presence fact, although an active combo-off sampler may consume the
    /// typed default as a separate resource fallback.
    let readinessCombo: String?
    /// Source-derived use for one prepared variant. Bootstrap schemas have
    /// no active syntax proof and therefore retain the conservative default.
    let channelUse: ChannelUse
    /// A role proven from complete active shader dataflow. This may type an
    /// otherwise ambiguous authored asset/property slot, but it may never
    /// override a conflicting explicit or registered resource contract.
    let sourceProvenPurpose: SceneTextureLoadPurpose?

    init(
        name: String,
        slot: Int,
        mode: TextureMode,
        materialKey: String?,
        labelKey: String? = nil,
        formatKey: String? = nil,
        isHidden: Bool,
        defaultTexture: DefaultTexture?,
        readinessCombo: String?,
        channelUse: ChannelUse = .unproven,
        sourceProvenPurpose: SceneTextureLoadPurpose? = nil
    ) {
        self.name = name
        self.slot = slot
        self.mode = mode
        self.materialKey = materialKey
        self.labelKey = labelKey
        self.formatKey = formatKey
        self.isHidden = isHidden
        self.defaultTexture = defaultTexture
        self.readinessCombo = readinessCombo
        self.channelUse = channelUse
        self.sourceProvenPurpose = sourceProvenPurpose
    }

    func withChannelUse(_ value: ChannelUse) -> Self {
        .init(
            name: name,
            slot: slot,
            mode: mode,
            materialKey: materialKey,
            labelKey: labelKey,
            formatKey: formatKey,
            isHidden: isHidden,
            defaultTexture: defaultTexture,
            readinessCombo: readinessCombo,
            channelUse: value,
            sourceProvenPurpose: sourceProvenPurpose
        )
    }

    func withSourceProvenPurpose(
        _ value: SceneTextureLoadPurpose
    ) -> Self {
        .init(
            name: name,
            slot: slot,
            mode: mode,
            materialKey: materialKey,
            labelKey: labelKey,
            formatKey: formatKey,
            isHidden: isHidden,
            defaultTexture: defaultTexture,
            readinessCombo: readinessCombo,
            channelUse: channelUse,
            sourceProvenPurpose: value
        )
    }
}
