import Foundation

/// Immutable shader/frontend/schema facts for one texture-readiness variant.
/// Concrete resources and uniform values are bound by each frame snapshot.
nonisolated struct SceneResolvedMaterialCompiledVariant {
    typealias Sampler = SceneResolvedMaterialShaderSchema.Sampler
    typealias Uniform = SceneResolvedMaterialShaderSchema.Uniform

    let readinessMask: UInt8
    let textureFormats: [SceneShaderTextureFormat?]
    let preparedAssembly: SceneResolvedMaterialProgram.PreparedAssembly
    var preparedShader: SceneShaderPreparedProgram { preparedAssembly.preparedShader }
    /// Exact active combo values after authored defaults, explicit values,
    /// texture readiness, and format macros have converged for this variant.
    /// Downstream prepared contracts consume these facts instead of guessing
    /// missing annotation defaults during a frame.
    let resolvedIntegerCombos: [String: Int]
    var frontendProgram: SceneAuthoredShaderProgram { preparedAssembly.frontendProgram }
    /// Nominal producer fact for preparing following passes. Actual frame
    /// output content always comes from the finalized resource contract.
    let preparedOutputContent: SceneTextureContent?
    let routeDecision: SceneGenericShaderRouteDecision
    var runtimeLoopBounds: SceneAuthoredShaderRuntimeLoopBounds {
        preparedAssembly.runtimeLoopBounds
    }
    let activeSamplers: [Int: Sampler]
    let graphInputSourceSlotFacts: [
        Int: SceneResolvedMaterialGraphInputSourceSlotFact
    ]
    let preservedAlphaRGBColorSlots: Set<Int>
    let sourceProvenOpaqueColorSlots: Set<Int>
    /// Exact color inputs converted from the shared premultiplied publication
    /// contract into authored straight-RGBA math by this compiled Program.
    var premultipliedColorInputSlots: Set<Int> {
        preparedAssembly.premultipliedColorInputSlots
    }
    /// External provider slots whose source dataflow is proven to consume
    /// independent scalar channels rather than compositor color.
    let preservedChannelsProviderInputSlots: Set<Int>
    /// Source-proven overlay input for associated-over/overlay-alpha math.
    /// This is immutable shader analysis and must not be rediscovered while
    /// binding every frame's resources and uniform values.
    var associatedOverOverlaySlot: Int? { preparedAssembly.associatedOverOverlaySlot }
    var conditionalGeneratedRGBInputContract:
        SceneResolvedMaterialProgramDerivation
            .ConditionalGeneratedRGBInputContract? {
        preparedAssembly.conditionalGeneratedRGBInputContract
    }
    let sameAlphaReconstructedRGBInputContract:
        SceneResolvedMaterialProgramDerivation
            .SameAlphaReconstructedRGBInputContract?
    let activeUniforms: [String: Uniform]
    let preparedUniformBindings: [
        SceneResolvedMaterialPreparedUniformBinding
    ]
    let neutralTextureResolution:
        SceneAuthoredShaderNeutralTextureResolutionFact?
    let preservesTargetPixelFootprint: Bool

    init(
        readinessMask: UInt8,
        textureFormats: [SceneShaderTextureFormat?],
        preparedAssembly: SceneResolvedMaterialProgram.PreparedAssembly,
        resolvedIntegerCombos: [String: Int],
        preparedOutputContent: SceneTextureContent? = nil,
        routeDecision: SceneGenericShaderRouteDecision,
        activeSamplers: [Int: Sampler],
        graphInputSourceSlotFacts: [
            Int: SceneResolvedMaterialGraphInputSourceSlotFact
        ],
        preservedAlphaRGBColorSlots: Set<Int>,
        sourceProvenOpaqueColorSlots: Set<Int>,
        preservedChannelsProviderInputSlots: Set<Int> = [],
        sameAlphaReconstructedRGBInputContract:
            SceneResolvedMaterialProgramDerivation
                .SameAlphaReconstructedRGBInputContract?,
        activeUniforms: [String: Uniform],
        preparedUniformBindings: [
            SceneResolvedMaterialPreparedUniformBinding
        ],
        neutralTextureResolution:
            SceneAuthoredShaderNeutralTextureResolutionFact?,
        preservesTargetPixelFootprint: Bool = false
    ) {
        self.readinessMask = readinessMask
        self.textureFormats = textureFormats
        self.preparedAssembly = preparedAssembly
        self.resolvedIntegerCombos = resolvedIntegerCombos
        self.preparedOutputContent = preparedOutputContent
        self.routeDecision = routeDecision
        self.activeSamplers = activeSamplers
        self.graphInputSourceSlotFacts = graphInputSourceSlotFacts
        self.preservedAlphaRGBColorSlots = preservedAlphaRGBColorSlots
        self.sourceProvenOpaqueColorSlots = sourceProvenOpaqueColorSlots
        self.preservedChannelsProviderInputSlots =
            preservedChannelsProviderInputSlots
        self.sameAlphaReconstructedRGBInputContract =
            sameAlphaReconstructedRGBInputContract
        self.activeUniforms = activeUniforms
        self.preparedUniformBindings = preparedUniformBindings
        self.neutralTextureResolution = neutralTextureResolution
        self.preservesTargetPixelFootprint = preservesTargetPixelFootprint
    }

    var requiresInvertibleEffectTextureProjection: Bool {
        preparedUniformBindings.contains { binding in
            guard case let .host(host) = binding.source else { return false }
            switch host {
            case .effectTextureProjectionMatrix,
                 .effectTextureProjectionMatrixInverse:
                return true
            default:
                return false
            }
        }
    }
}
