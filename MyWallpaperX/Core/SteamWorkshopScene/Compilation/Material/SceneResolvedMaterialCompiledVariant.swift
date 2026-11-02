import Foundation

/// Immutable shader/frontend/schema facts for one texture-readiness variant.
/// Concrete resources and uniform values are bound by each frame snapshot.
nonisolated struct SceneResolvedMaterialCompiledVariant {
    typealias Sampler = SceneResolvedMaterialShaderSchema.Sampler
    typealias Uniform = SceneResolvedMaterialShaderSchema.Uniform

    struct MixedProviderSlot: Hashable {
        enum OptionalInput: Hashable {
            case system(String)
            case userProperty(String)

            init?(_ reference: SceneResolvedMaterialTemplate.TextureReference) {
                switch reference {
                case let .provider(.system(name)) where !name.isEmpty: self = .system(name)
                case let .userProperty(request) where !request.key.isEmpty:
                    self = .userProperty(request.key)
                default: return nil
                }
            }

            func matches(_ reference: SceneResolvedMaterialTemplate.TextureReference) -> Bool {
                switch (self, reference) {
                case let (.system(expected), .provider(.system(actual))): expected == actual
                case let (.userProperty(expected), .userProperty(actual)): expected == actual.key
                default: false
                }
            }
        }

        let slot: Int
        let lowerNamedReference: SceneNamedTextureReference
        let optionalInput: OptionalInput

        func purpose(
            for reference: SceneResolvedMaterialTemplate.TextureReference
        ) -> SceneTextureLoadPurpose? {
            switch reference {
            case let .provider(.namedLayerTarget(reference)) where reference == lowerNamedReference:
                .premultipliedColor
            case let reference where optionalInput.matches(reference): .preservedChannels
            default: nil
            }
        }
    }

    struct TextureSelectionFacts {
        struct Candidate {
            let graphInputSourceFact: SceneResolvedMaterialGraphInputSourceSlotFact?
            let preservesAbsentOverride: Bool
            let defersUnreadyOptionalPromotion: Bool
        }

        struct DefaultReference {
            let reference: SceneResolvedMaterialTemplate.TextureReference
            let purpose: SceneTextureLoadPurpose?
            let graphInputSourceFact: SceneResolvedMaterialGraphInputSourceSlotFact?
            let noiseFallback: SceneResolvedMaterialTemplate.TextureReference?
            let requiresPresenceIndependentAllowance: Bool
        }

        enum DefaultSource {
            case reference(DefaultReference)
            case internalTarget(String)
        }

        /// Candidate ordinals follow the immutable Template; nil remains an
        /// unproven purpose rather than an absent texture or a color default.
        let candidatePurposes: [Int: [SceneTextureLoadPurpose?]]
        let candidates: [Int: [Candidate]]
        let defaults: [Int: DefaultSource]
        let graphInputPurposes: [Int: SceneTextureLoadPurpose]
        let mixedProviderSlots: [Int: MixedProviderSlot]
        let regularNamedProviderPurposeSlots: Set<Int>

        func restricting(to activeSlots: Set<Int>) -> Self {
            var candidates = self.candidates
            for (slot, values) in candidates where !activeSlots.contains(slot) {
                candidates[slot] = values.map {
                    Candidate(
                        graphInputSourceFact: nil,
                        preservesAbsentOverride: $0.preservesAbsentOverride,
                        defersUnreadyOptionalPromotion: false
                    )
                }
            }
            return .init(
                candidatePurposes: candidatePurposes.filter { activeSlots.contains($0.key) },
                candidates: candidates,
                defaults: defaults.filter { activeSlots.contains($0.key) },
                graphInputPurposes: graphInputPurposes.filter { activeSlots.contains($0.key) },
                mixedProviderSlots: mixedProviderSlots.filter { activeSlots.contains($0.key) },
                regularNamedProviderPurposeSlots: regularNamedProviderPurposeSlots.intersection(activeSlots)
            )
        }

        static func consensusPurposes(
            _ profiles: [[Int: [SceneTextureLoadPurpose?]]]
        ) -> [Int: [SceneTextureLoadPurpose?]] {
            var result: [Int: [SceneTextureLoadPurpose?]] = [:]
            for profile in profiles {
                for (slot, purposes) in profile {
                    if let prior = result[slot] {
                        // One unproven or conflicting reachable variant keeps
                        // this candidate unproven for an inactive sampler.
                        result[slot] = zip(prior, purposes).map { $0.0 == $0.1 ? $0.0 : nil }
                    } else {
                        result[slot] = purposes
                    }
                }
            }
            return result
        }
    }

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
    let textureSelectionFacts: TextureSelectionFacts
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
        textureSelectionFacts: TextureSelectionFacts,
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
        self.textureSelectionFacts = textureSelectionFacts
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
