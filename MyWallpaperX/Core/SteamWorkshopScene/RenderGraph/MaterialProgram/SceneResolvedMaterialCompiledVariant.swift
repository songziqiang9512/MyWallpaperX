import Foundation

/// Immutable execution route for one active authored uniform. Preparation
/// resolves ownership and structural projection once; a frame only supplies
/// the value carried by that route and revalidates live resource identity.
nonisolated struct SceneResolvedMaterialPreparedUniformBinding: Hashable {
    typealias Program = SceneResolvedMaterialProgram
    typealias Template = SceneResolvedMaterialTemplate
    typealias Uniform = SceneResolvedMaterialShaderSchema.Uniform

    struct Dynamic: Hashable {
        let declaration: Template.DynamicUniform
        let contributor: Template.DynamicUniformSource
        let fallback: Template.StaticUniformValue?
        let schema: Uniform
    }

    enum Source: Hashable {
        case host(Program.HostUniform)
        case staticValue(Data)
        case dynamic(Dynamic)
        case neutralMissingTextureResolution(
            SceneAuthoredShaderNeutralTextureResolutionFact
        )
        case selfCompositeTextureResolution(
            slot: Int,
            providerLayerID: Int
        )
    }

    let field: SceneAuthoredShaderUniformLayout.Field
    let source: Source
}

/// Immutable shader/frontend/schema facts for one texture-readiness variant.
/// Concrete resources and uniform values are bound by each frame snapshot.
nonisolated struct SceneResolvedMaterialCompiledVariant {
    typealias Sampler = SceneResolvedMaterialShaderSchema.Sampler
    typealias Uniform = SceneResolvedMaterialShaderSchema.Uniform

    let readinessMask: UInt8
    let textureFormats: [SceneShaderTextureFormat?]
    let preparedShader: SceneShaderPreparedProgram
    /// Exact active combo values after authored defaults, explicit values,
    /// texture readiness, and format macros have converged for this variant.
    /// Downstream prepared contracts consume these facts instead of guessing
    /// missing annotation defaults during a frame.
    let resolvedIntegerCombos: [String: Int]
    let frontendProgram: SceneAuthoredShaderProgram
    let routeDecision: SceneGenericShaderRouteDecision
    let runtimeLoopBounds: SceneAuthoredShaderRuntimeLoopBounds
    let activeSamplers: [Int: Sampler]
    let graphInputSourceSlotFacts: [
        Int: SceneResolvedMaterialGraphInputSourceSlotFact
    ]
    let preservedAlphaRGBColorSlots: Set<Int>
    let sourceProvenOpaqueColorSlots: Set<Int>
    /// Exact color inputs converted from the shared premultiplied publication
    /// contract into authored straight-RGBA math by this compiled Program.
    let premultipliedColorInputSlots: Set<Int>
    /// External provider slots whose source dataflow is proven to consume
    /// independent scalar channels rather than compositor color.
    let preservedChannelsProviderInputSlots: Set<Int>
    /// Source-proven overlay input for associated-over/overlay-alpha math.
    /// This is immutable shader analysis and must not be rediscovered while
    /// binding every frame's resources and uniform values.
    let associatedOverOverlaySlot: Int?
    let conditionalGeneratedRGBInputContract:
        SceneResolvedMaterialProgramDerivation
            .ConditionalGeneratedRGBInputContract?
    let sameAlphaReconstructedRGBInputContract:
        SceneResolvedMaterialProgramDerivation
            .SameAlphaReconstructedRGBInputContract?
    let activeUniforms: [String: Uniform]
    let preparedUniformBindings: [
        SceneResolvedMaterialPreparedUniformBinding
    ]
    let neutralTextureResolution:
        SceneAuthoredShaderNeutralTextureResolutionFact?
    let sameSlotMappedCoordinateFacts:
        Set<SceneAuthoredShaderSameSlotMappedCoordinateFact>

    init(
        readinessMask: UInt8,
        textureFormats: [SceneShaderTextureFormat?],
        preparedShader: SceneShaderPreparedProgram,
        resolvedIntegerCombos: [String: Int],
        frontendProgram: SceneAuthoredShaderProgram,
        routeDecision: SceneGenericShaderRouteDecision,
        runtimeLoopBounds: SceneAuthoredShaderRuntimeLoopBounds,
        activeSamplers: [Int: Sampler],
        graphInputSourceSlotFacts: [
            Int: SceneResolvedMaterialGraphInputSourceSlotFact
        ],
        preservedAlphaRGBColorSlots: Set<Int>,
        sourceProvenOpaqueColorSlots: Set<Int>,
        premultipliedColorInputSlots: Set<Int> = [],
        preservedChannelsProviderInputSlots: Set<Int> = [],
        associatedOverOverlaySlot: Int?,
        conditionalGeneratedRGBInputContract:
            SceneResolvedMaterialProgramDerivation
                .ConditionalGeneratedRGBInputContract?,
        sameAlphaReconstructedRGBInputContract:
            SceneResolvedMaterialProgramDerivation
                .SameAlphaReconstructedRGBInputContract?,
        activeUniforms: [String: Uniform],
        preparedUniformBindings: [
            SceneResolvedMaterialPreparedUniformBinding
        ],
        neutralTextureResolution:
            SceneAuthoredShaderNeutralTextureResolutionFact?,
        sameSlotMappedCoordinateFacts:
            Set<SceneAuthoredShaderSameSlotMappedCoordinateFact>
    ) {
        self.readinessMask = readinessMask
        self.textureFormats = textureFormats
        self.preparedShader = preparedShader
        self.resolvedIntegerCombos = resolvedIntegerCombos
        self.frontendProgram = frontendProgram
        self.routeDecision = routeDecision
        self.runtimeLoopBounds = runtimeLoopBounds
        self.activeSamplers = activeSamplers
        self.graphInputSourceSlotFacts = graphInputSourceSlotFacts
        self.preservedAlphaRGBColorSlots = preservedAlphaRGBColorSlots
        self.sourceProvenOpaqueColorSlots = sourceProvenOpaqueColorSlots
        self.premultipliedColorInputSlots = premultipliedColorInputSlots
        self.preservedChannelsProviderInputSlots =
            preservedChannelsProviderInputSlots
        self.associatedOverOverlaySlot = associatedOverOverlaySlot
        self.conditionalGeneratedRGBInputContract =
            conditionalGeneratedRGBInputContract
        self.sameAlphaReconstructedRGBInputContract =
            sameAlphaReconstructedRGBInputContract
        self.activeUniforms = activeUniforms
        self.preparedUniformBindings = preparedUniformBindings
        self.neutralTextureResolution = neutralTextureResolution
        self.sameSlotMappedCoordinateFacts = sameSlotMappedCoordinateFacts
    }

    var requiresInvertibleEffectTextureProjection: Bool {
        preparedUniformBindings.contains { binding in
            guard case let .host(host) = binding.source else { return false }
            switch host {
            case .effectModelViewProjection,
                 .effectTextureProjectionMatrix,
                 .effectTextureProjectionMatrixInverse:
                return true
            default:
                return false
            }
        }
    }
}
