import Foundation

/// Product authority, rollback and shared-backend fallback policy for the
/// structural capability profiles derived by the generic shader route owner.
nonisolated extension SceneGenericShaderCapabilityProfile {
    var defaultRouteState: SceneGenericShaderRouteState {
        switch self {
        case .ordinaryShader,
             .providerBackedScalarColorInterpolation,
             .sourceProvenGraphInputStraightAlpha,
             .sourceProvenGraphInputStraightAlphaPreserving,
             .sourceProvenScalarColorInterpolation,
             .sourceProvenOpaqueScalarOutput,
             .sourceProvenStraightAlphaR8Signal,
             .sourceProvenRedGreenUnormScalarSplat,
             .sourceProvenPreservedRGBAStateTransform,
             .sourceProvenIndependentPremultipliedOutput,
             .sourceProvenGraphInputIndependentSignalProducer,
             .sourceProvenGraphTargetIndependentSignalAccumulator,
             .sourceProvenGraphTargetIndependentSignalUNormAccumulator,
             .sourceProvenGraphInputIndependentSignalCompositing,
             .providerBackedGraphInputIndependentSignalUnderlayCompositing,
             .sourceProvenGraphTargetPassthrough,
             .sourceProvenGraphInputSameSlotColorReplacement,
             .sourceProvenNormalizedSampleSum,
             .sourceProvenGraphTargetOpaqueLoopSampleAverage,
             .sourceProvenGraphTargetOpaqueStaticSampleAverage,
             .sourceProvenGraphTargetOpaqueAlphaWeightedLoopAverage,
             .sourceProvenGraphInputConditionalOpaqueAlphaWeightedRGB,
             .sourceProvenGraphInputAlphaWeightedSampleAverage,
             .sourceProvenGraphInputPreservedAlphaRGBFilter,
             .sourceProvenGraphInputTypedDataRGBFilter,
             .sourceProvenGraphInputSameAlphaReconstructedRGBDataFilter,
             .sourceProvenGraphInputSampledAlphaReconstructedRGBADataFilter,
             .sourceProvenUnitPreviousBlurredComposite,
             .sourceProvenGraphInputAlphaAttenuation,
             .sourceProvenGraphInputColorBlend,
             .sourceProvenGraphInputSpatialWeightedColorBlend,
             .providerBackedGraphInputSpatialWeightedColorBlend,
             .sourceProvenGraphInputOverlayAlphaBlend,
             .sourceProvenGraphInputOverlayColorBlendAlphaPreserving,
             .sourceProvenGraphInputConditionalStraightUnion,
             .sourceProvenGraphInputConditionalGeneratedRGBPreservedAlpha,
             .sourceProvenGraphInputSingleSamplerAlphaMutation,
             .sourceProvenGraphInputStraightRGBScalarAlpha,
             .sourceProvenGraphInputRGBBlendScalarAlpha,
             .sourceProvenGraphInputSameSlotChannelReconstruction,
             .sourceProvenGraphInputAuxiliaryRGBBlendAlphaPreserving,
             .sourceProvenGraphInputAudioStageUniformStraightAlphaNoAuxiliary,
             .sourceProvenGraphInputStageUniformStraightAlphaPreserving,
             .sourceProvenGraphInputStageUniformStraightAlphaPreservingStaticAuxiliary,
             .sourceProvenGraphInputStageUniformStraightAlphaPreservingNoAuxiliary,
             .sourceProvenGraphInputStageUniformPassthrough:
            .genericOnly
        case .sourceProvenGraphInputAssociatedOverBlend:
            .preferGeneric
        case .sourceProvenUnitPreviousBlurredCompositeUnowned:
            .observeOnly
        }
    }

    /// New owner migrations are controlled only by the exact profile map;
    /// the legacy process-wide switch must not revoke their product owner.
    var ignoresLegacyProcessRoute: Bool {
        self == .ordinaryShader
            || self == .providerBackedScalarColorInterpolation
            || self == .sourceProvenGraphInputStraightAlpha
            || self == .sourceProvenGraphInputStraightAlphaPreserving
            || self
                == .sourceProvenGraphInputConditionalGeneratedRGBPreservedAlpha
            || self == .sourceProvenGraphTargetOpaqueLoopSampleAverage
            || self == .sourceProvenGraphTargetOpaqueStaticSampleAverage
            || self == .sourceProvenGraphTargetOpaqueAlphaWeightedLoopAverage
            || self == .sourceProvenGraphInputSameSlotColorReplacement
            || self == .providerBackedGraphInputSpatialWeightedColorBlend
            || self
                == .providerBackedGraphInputIndependentSignalUnderlayCompositing
            || self
                == .sourceProvenGraphInputConditionalOpaqueAlphaWeightedRGB
    }

    /// Shared profiles normally roll back through the bounded frontend. The
    /// preserved-alpha RGB filters and the unit previous/blurred composite
    /// have no complete, visually safe secondary owner: disabling their
    /// generic owner must reject that effect back to the safe previous-current
    /// boundary. A source-proven composite that lacks the surrounding graph
    /// owner token remains quarantined behind the verified incumbent.
    var validatedRollbackOwner: SceneGenericShaderFallbackOwner {
        switch self {
        case .sourceProvenGraphInputPreservedAlphaRGBFilter,
             .sourceProvenGraphInputTypedDataRGBFilter,
             .sourceProvenGraphInputSampledAlphaReconstructedRGBADataFilter,
             .sourceProvenGraphInputStraightRGBScalarAlpha,
             .sourceProvenGraphInputRGBBlendScalarAlpha,
             .sourceProvenUnitPreviousBlurredComposite:
            .none
        case .sourceProvenUnitPreviousBlurredCompositeUnowned:
            .programFirstIncumbent
        default:
            .boundedFrontend
        }
    }

    /// This exact source-derived profile has a complete shared Swift frontend
    /// owner. Falling back between shared compiler backends never revives a
    /// retained dedicated product renderer.
    func permitsBoundedFrontendAfterArtifactFailure(
        routeState: SceneGenericShaderRouteState
    ) -> Bool {
        guard validatedRollbackOwner == .boundedFrontend else { return false }
        return self == .ordinaryShader
            || self == .providerBackedScalarColorInterpolation
            || self == .sourceProvenGraphInputStraightAlpha
            || self == .sourceProvenGraphInputStraightAlphaPreserving
            || routeState != .genericOnly
            || self
                == .sourceProvenGraphInputStageUniformStraightAlphaPreservingNoAuxiliary
            || self == .sourceProvenGraphInputOverlayAlphaBlend
            || self
                == .sourceProvenGraphInputOverlayColorBlendAlphaPreserving
            || self == .sourceProvenGraphInputAssociatedOverBlend
            || self
                == .sourceProvenGraphInputConditionalOpaqueAlphaWeightedRGB
            || self
                == .providerBackedGraphInputIndependentSignalUnderlayCompositing
    }

    func artifactFallbackOutcome(
        routeState: SceneGenericShaderRouteState
    ) -> String {
        guard routeState == .genericOnly else { return "fallback" }
        return permitsBoundedFrontendAfterArtifactFailure(routeState: routeState)
            ? "shared-backend-fallback" : "rejected"
    }
}
