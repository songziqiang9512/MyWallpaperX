import Foundation

/// Immutable shader/frontend/schema facts for one texture-readiness variant.
/// Concrete resources and uniform values are bound by each frame snapshot.
nonisolated struct SceneResolvedMaterialCompiledVariant {
    typealias Sampler = SceneResolvedMaterialShaderSchema.Sampler
    typealias Uniform = SceneResolvedMaterialShaderSchema.Uniform

    let readinessMask: UInt8
    let textureFormats: [SceneShaderTextureFormat?]
    let preparedShader: SceneShaderPreparedProgram
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
    let neutralTextureResolution:
        SceneAuthoredShaderNeutralTextureResolutionFact?
    let sameSlotMappedCoordinateFacts:
        Set<SceneAuthoredShaderSameSlotMappedCoordinateFact>

    init(
        readinessMask: UInt8,
        textureFormats: [SceneShaderTextureFormat?],
        preparedShader: SceneShaderPreparedProgram,
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
        associatedOverOverlaySlot: Int?,
        conditionalGeneratedRGBInputContract:
            SceneResolvedMaterialProgramDerivation
                .ConditionalGeneratedRGBInputContract?,
        sameAlphaReconstructedRGBInputContract:
            SceneResolvedMaterialProgramDerivation
                .SameAlphaReconstructedRGBInputContract?,
        activeUniforms: [String: Uniform],
        neutralTextureResolution:
            SceneAuthoredShaderNeutralTextureResolutionFact?,
        sameSlotMappedCoordinateFacts:
            Set<SceneAuthoredShaderSameSlotMappedCoordinateFact>
    ) {
        self.readinessMask = readinessMask
        self.textureFormats = textureFormats
        self.preparedShader = preparedShader
        self.frontendProgram = frontendProgram
        self.routeDecision = routeDecision
        self.runtimeLoopBounds = runtimeLoopBounds
        self.activeSamplers = activeSamplers
        self.graphInputSourceSlotFacts = graphInputSourceSlotFacts
        self.preservedAlphaRGBColorSlots = preservedAlphaRGBColorSlots
        self.sourceProvenOpaqueColorSlots = sourceProvenOpaqueColorSlots
        self.premultipliedColorInputSlots = premultipliedColorInputSlots
        self.associatedOverOverlaySlot = associatedOverOverlaySlot
        self.conditionalGeneratedRGBInputContract =
            conditionalGeneratedRGBInputContract
        self.sameAlphaReconstructedRGBInputContract =
            sameAlphaReconstructedRGBInputContract
        self.activeUniforms = activeUniforms
        self.neutralTextureResolution = neutralTextureResolution
        self.sameSlotMappedCoordinateFacts = sameSlotMappedCoordinateFacts
    }
}
