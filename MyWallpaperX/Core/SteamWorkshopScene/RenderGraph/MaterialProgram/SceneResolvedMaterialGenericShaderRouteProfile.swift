/// Product authority for one source-proven shader capability. These profiles
/// are structural host facts; they never contain effect, sample, path, or hash
/// identities.
nonisolated enum SceneGenericShaderRouteState: String {
    case preferGeneric = "prefer-generic"
    case genericOnly = "generic-only"
    case observeOnly = "observe-only"
    case disableGeneric = "disable-generic"

    static func resolve(
        _ rawValue: String?,
        defaultState: SceneGenericShaderRouteState
    ) -> SceneGenericShaderRouteState? {
        guard let rawValue else { return defaultState }
        guard let requested = Self(rawValue: rawValue) else { return nil }
        switch requested {
        case .preferGeneric:
            // A migrated profile cannot silently regain a second product
            // owner. `disable-generic` is its explicit rollback switch.
            return defaultState == .genericOnly ? .genericOnly : .preferGeneric
        case .genericOnly:
            // Do not let an environment toggle broaden generic-only
            // authority to profiles that have not passed their owner gate.
            return defaultState == .genericOnly ? .genericOnly : nil
        case .observeOnly, .disableGeneric:
            return requested
        }
    }
}

nonisolated enum SceneGenericShaderFallbackOwner: String {
    case boundedFrontend = "bounded-frontend"
    case none
}

nonisolated enum SceneGenericShaderCapabilityProfile: String {
    case ordinaryShader = "ordinary-shader"
    case providerBackedScalarColorInterpolation =
        "provider-backed-scalar-color-interpolation"
    case sourceProvenScalarColorInterpolation =
        "source-proven-scalar-color-interpolation"
    case sourceProvenOpaqueScalarOutput =
        "source-proven-opaque-scalar-output"
    case sourceProvenStraightAlphaR8Signal =
        "source-proven-straight-alpha-r8-signal"
    case sourceProvenIndependentPremultipliedOutput =
        "source-proven-independent-premultiplied-output"
    case sourceProvenGraphTargetPassthrough =
        "source-proven-graph-target-passthrough"
    case sourceProvenGraphInputAlphaAttenuation =
        "source-proven-graph-input-alpha-attenuation"
    case sourceProvenGraphInputColorBlend =
        "source-proven-graph-input-color-blend"
    case sourceProvenGraphInputConditionalStraightUnion =
        "source-proven-graph-input-conditional-straight-union"
    case sourceProvenGraphInputStraightAlpha =
        "source-proven-graph-input-straight-alpha"
    case sourceProvenGraphInputStraightAlphaPreserving =
        "source-proven-graph-input-straight-alpha-preserving"
    case sourceProvenGraphInputStageUniformStraightAlphaPreserving =
        "source-proven-graph-input-stage-uniform-straight-alpha-preserving"
    case sourceProvenGraphInputStageUniformPassthrough =
        "source-proven-graph-input-stage-uniform-passthrough"

    init(
        colorTransfer: SceneShaderColorTransfer,
        alphaAttenuationSourceSlot: Int?,
        colorBlendSourceSlot: Int?,
        conditionalStraightUnionSourceSlot: Int?,
        hasExternalProviderTexture: Bool,
        producesScalarRedOutput: Bool,
        isSourceIndependentPremultipliedOutput: Bool,
        graphTextureSlots: Set<Int>,
        graphInputTextureSlots: Set<Int>,
        r8TextureSlots: Set<Int>,
        hasDefaultedOpacityMaskSampler: Bool,
        hasStageScopedUniformBindings: Bool
    ) {
        if colorTransfer == .premultipliedAlpha,
           isSourceIndependentPremultipliedOutput,
           !hasExternalProviderTexture,
           !producesScalarRedOutput,
           graphTextureSlots.isEmpty,
           graphInputTextureSlots.isEmpty {
            self = .sourceProvenIndependentPremultipliedOutput
        } else if let colorBlendSourceSlot,
           !hasExternalProviderTexture,
           !producesScalarRedOutput,
           graphInputTextureSlots.contains(colorBlendSourceSlot) {
            self = .sourceProvenGraphInputColorBlend
        } else if case let .straightAlpha(sourceSlot) = colorTransfer,
                  conditionalStraightUnionSourceSlot == sourceSlot,
                  !hasExternalProviderTexture,
                  !producesScalarRedOutput,
                  graphTextureSlots.isEmpty,
                  graphInputTextureSlots == Set([sourceSlot]) {
            self = .sourceProvenGraphInputConditionalStraightUnion
        } else if colorTransfer == .opaque, producesScalarRedOutput {
            self = .sourceProvenOpaqueScalarOutput
        } else if case let .straightAlphaPreserving(sourceSlot) = colorTransfer,
                  !producesScalarRedOutput,
                  r8TextureSlots.contains(where: { $0 != sourceSlot }) {
            self = .sourceProvenStraightAlphaR8Signal
        } else if case let .passthrough(sourceSlot) = colorTransfer,
                  !hasExternalProviderTexture,
                  !producesScalarRedOutput,
                  graphTextureSlots.contains(sourceSlot) {
            self = .sourceProvenGraphTargetPassthrough
        } else if case let .passthrough(sourceSlot) = colorTransfer,
                  !hasExternalProviderTexture,
                  !producesScalarRedOutput,
                  graphInputTextureSlots.contains(sourceSlot),
                  hasStageScopedUniformBindings {
            self = .sourceProvenGraphInputStageUniformPassthrough
        } else if case let .straightAlpha(sourceSlot) = colorTransfer,
                  alphaAttenuationSourceSlot == sourceSlot,
                  !hasExternalProviderTexture,
                  !producesScalarRedOutput,
                  graphInputTextureSlots.contains(sourceSlot) {
            self = .sourceProvenGraphInputAlphaAttenuation
        } else if case let .straightAlpha(sourceSlot) = colorTransfer,
                  !hasExternalProviderTexture,
                  !producesScalarRedOutput,
                  graphInputTextureSlots.contains(sourceSlot) {
            self = .sourceProvenGraphInputStraightAlpha
        } else if case let .straightAlphaPreserving(sourceSlot) = colorTransfer,
                  !hasExternalProviderTexture,
                  !producesScalarRedOutput,
                  graphTextureSlots.isEmpty,
                  graphInputTextureSlots == Set([sourceSlot]),
                  hasDefaultedOpacityMaskSampler,
                  hasStageScopedUniformBindings {
            self = .sourceProvenGraphInputStageUniformStraightAlphaPreserving
        } else if case let .straightAlphaPreserving(sourceSlot) = colorTransfer,
                  !hasExternalProviderTexture,
                  !producesScalarRedOutput,
                  graphInputTextureSlots.contains(sourceSlot) {
            self = .sourceProvenGraphInputStraightAlphaPreserving
        } else if case .interpolatedColor = colorTransfer,
                  hasExternalProviderTexture {
            self = .providerBackedScalarColorInterpolation
        } else if case .interpolatedColor = colorTransfer {
            self = .sourceProvenScalarColorInterpolation
        } else {
            self = .ordinaryShader
        }
    }

    var defaultRouteState: SceneGenericShaderRouteState {
        switch self {
        case .ordinaryShader,
             .providerBackedScalarColorInterpolation,
             .sourceProvenGraphInputStraightAlpha,
             .sourceProvenGraphInputStraightAlphaPreserving:
            .preferGeneric
        case .sourceProvenScalarColorInterpolation,
             .sourceProvenOpaqueScalarOutput,
             .sourceProvenStraightAlphaR8Signal,
             .sourceProvenIndependentPremultipliedOutput,
             .sourceProvenGraphTargetPassthrough,
             .sourceProvenGraphInputAlphaAttenuation,
             .sourceProvenGraphInputColorBlend,
             .sourceProvenGraphInputConditionalStraightUnion,
             .sourceProvenGraphInputStageUniformStraightAlphaPreserving,
             .sourceProvenGraphInputStageUniformPassthrough:
            .genericOnly
        }
    }

    /// Every migrated profile keeps only the shared bounded frontend as its
    /// explicit rollback path; no retired dedicated renderer can re-enter.
    var validatedRollbackOwner: SceneGenericShaderFallbackOwner {
        .boundedFrontend
    }
}
