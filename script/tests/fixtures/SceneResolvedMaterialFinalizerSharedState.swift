import Foundation
import Metal
import simd

final class SceneResolvedMaterialFinalizerFixture {
    let device: MTLDevice

    lazy var preparation = SceneResolvedMaterialFinalizerPreparationCases(self)
    lazy var framebuffer = SceneResolvedMaterialFinalizerFramebufferCases(self)
    lazy var uniforms = SceneResolvedMaterialFinalizerDynamicUniformCases(self)
    lazy var providers = SceneResolvedMaterialFinalizerProviderResourceCases(self)
    lazy var failures = SceneResolvedMaterialFinalizerFailureCases(self)

    init(device: MTLDevice) { self.device = device }
    // Runs the established cases once before collecting an optional observer.
    func run(additionalResults: () throws -> [String: Any] = { [:] }) rethrows -> [String: Any] {
        let device = self.device
        let fixture = self
        // Force each original initializer and admission guard in its original order.
        _ = fixture.preparation.revisionA
        _ = fixture.preparation.revisionB
        _ = fixture.preparation.successfulPrograms
        _ = fixture.preparation.resolverInvariants
        _ = fixture.preparation.variantSelectionKeyMismatch
        _ = fixture.preparation.audioInputs
        _ = fixture.preparation.audioProgramResult
        _ = fixture.preparation.audioSpectrumEncoded
        _ = fixture.preparation.stageLocalProgram
        _ = fixture.preparation.stageLocalUniformsEncoded
        _ = fixture.preparation.sharedStageLocalProgram
        _ = fixture.preparation.sharedStageLocalDynamicUniformsEncoded
        _ = fixture.preparation.exactCrossStageUniformCases
        _ = fixture.preparation.runtimeLoopProgram
        _ = fixture.preparation.runtimeLoopStaticProducerAccepted
        _ = fixture.preparation.pointerStateProgram
        _ = fixture.preparation.pointerStateEncoded
        _ = fixture.preparation.admittedEffectIngress
        _ = fixture.framebuffer.implicitFramebufferProgram
        _ = fixture.framebuffer.caseInsensitiveFramebufferProgram
        _ = fixture.framebuffer.historicalFramebufferProgram
        _ = fixture.framebuffer.previousAliasProgram
        _ = fixture.framebuffer.explicitFramebufferProgram
        _ = fixture.framebuffer.scalarRedConsumerProgram
        _ = fixture.framebuffer.scalarRedForgedTEXFormat
        _ = fixture.framebuffer.scalarRedWrongFormat
        _ = fixture.framebuffer.scalarRedConsumerIdentity
        _ = fixture.framebuffer.rgbaDataConsumerProgram
        _ = fixture.framebuffer.rgbaDataConsumerIdentity
        _ = fixture.framebuffer.graphRoleIdentityFailure
        _ = fixture.framebuffer.programAssemblyIdentityFailure
        _ = fixture.framebuffer.implicitFramebufferTyped
        _ = fixture.framebuffer.previousAliasTyped
        _ = fixture.framebuffer.historicalFramebufferTyped
        _ = fixture.framebuffer.stockNoisePath
        _ = fixture.framebuffer.stockNoiseIdentity
        _ = fixture.framebuffer.stockDefaultProgram
        _ = fixture.framebuffer.stockDefaultProgramPreservesSnapshotAtoms
        _ = fixture.framebuffer.explicitFramebufferPreserved
        _ = fixture.framebuffer.implicitDefaultPath
        _ = fixture.framebuffer.shaderDefaultBeforeImplicit
        _ = fixture.framebuffer.shaderDefaultPreserved
        _ = fixture.uniforms.tintField
        _ = fixture.uniforms.tintRange
        _ = fixture.uniforms.tintDefaultCorrect
        _ = fixture.uniforms.timeField
        _ = fixture.uniforms.timeRange
        _ = fixture.uniforms.hostDefaultIgnored
        _ = fixture.uniforms.explicitTint
        _ = fixture.uniforms.explicitOverrideCorrect
        _ = fixture.uniforms.maskMetadata
        _ = fixture.uniforms.assetPath
        _ = fixture.uniforms.assetProgram
        _ = fixture.uniforms.maskedPath
        _ = fixture.uniforms.maskedIdentity
        _ = fixture.uniforms.maskedShader
        _ = fixture.uniforms.maskedProgram
        _ = fixture.uniforms.maskedDynamicAlphaEncoded
        _ = fixture.uniforms.directScalarWithinRange
        _ = fixture.uniforms.directScalarOutOfRange
        _ = fixture.uniforms.directScalarInvalidFallback
        _ = fixture.uniforms.directScalarTypeMismatch
        _ = fixture.uniforms.directUserPropertyScalarRangeFallback
        _ = fixture.uniforms.sceneScriptAlphaProgram
        _ = fixture.uniforms.sceneScriptDynamicAlphaEncoded
        _ = fixture.uniforms.timelineVectorA
        _ = fixture.uniforms.timelineVectorB
        _ = fixture.uniforms.timelineVectorTypeMismatch
        _ = fixture.uniforms.timelineVectorUpdatesProgramWithoutTopologyChange
        _ = fixture.uniforms.scalarSplatShader
        _ = fixture.uniforms.scalarSplatProgram
        _ = fixture.uniforms.scalarSplatAuthoredProgram
        _ = fixture.uniforms.rangedScalarSplatShader
        _ = fixture.uniforms.authoredRangeSentinelProgram
        _ = fixture.uniforms.outOfRangeLiveFallsBackToAuthoredSentinel
        _ = fixture.uniforms.mismatchedOutOfRangeAuthoredSentinel
        _ = fixture.uniforms.producerDomainScalarShader
        _ = fixture.uniforms.producerDomainZeroProgram
        _ = fixture.uniforms.producerDomainFractionProgram
        _ = fixture.uniforms.producerDomainOverflowProgram
        _ = fixture.uniforms.staticScalarSplatProgram
        _ = fixture.uniforms.userPropertyScalarFloat2SplatEncoded
        _ = fixture.uniforms.authoredOutOfRangeScalarFloat2SentinelPreserved
        _ = fixture.uniforms.directUserPropertyScalarProducerDomainPreserved
        _ = fixture.uniforms.staticScalarFloat2SplatEncoded
        _ = fixture.uniforms.unequalDefaultStaticScalarSplat
        _ = fixture.uniforms.missingDefaultStaticScalarSplat
        _ = fixture.uniforms.nonFiniteDefaultStaticScalarSplat
        _ = fixture.uniforms.wrongABIStaticScalarSplat
        _ = fixture.uniforms.arrayStaticScalarSplat
        _ = fixture.uniforms.nonFiniteStaticScalarSplat
        _ = fixture.uniforms.unprovenStaticScalarSplat
        _ = fixture.uniforms.scalarShaderDefaultOnly
        _ = fixture.uniforms.exactStaticFloat2Program
        _ = fixture.uniforms.exactStaticFloat2Preserved
        _ = fixture.uniforms.unequalScalarSplatFallback
        _ = fixture.uniforms.nonUserScalarSplatContributor
        _ = fixture.uniforms.extraKeyScalarSplat
        _ = fixture.uniforms.scriptKeyScalarSplat
        _ = fixture.providers.overlayPath
        _ = fixture.providers.overlayIdentity
        _ = fixture.providers.overlayShader
        _ = fixture.providers.overlayProgram
        _ = fixture.providers.overlayDataTyped
        _ = fixture.providers.overlayColorAuxiliary
        _ = fixture.providers.optionalDefaultPath
        _ = fixture.providers.optionalDefaultIdentity
        _ = fixture.providers.optionalDefaultEntry
        _ = fixture.providers.optionalMaskShader
        _ = fixture.providers.optionalMaskProgram
        _ = fixture.providers.optionalMaskWithoutResourceAccepted
        _ = fixture.providers.optionalMaskWithResource
        _ = fixture.providers.optionalMaskWithResourceAccepted
        _ = fixture.providers.optionalMaskPending
        _ = fixture.providers.optionalMaskWrongPurpose
        _ = fixture.providers.activeDefaultMaskShader
        _ = fixture.providers.activeDefaultUniforms
        _ = fixture.providers.activeDefaultTemplate
        _ = fixture.providers.activeDefaultMaskCache
        _ = fixture.providers.activeDefaultLaunch
        _ = fixture.providers.activeDefaultLaunchMasks
        _ = fixture.providers.activeDefaultMaskProgram
        _ = fixture.providers.activeDefaultMaskAccepted
        _ = fixture.providers.activeAuthoredMaskProgram
        _ = fixture.providers.activeDefaultMaskMissing
        _ = fixture.providers.optionalUntypedMask
        _ = fixture.providers.maskedMissing
        _ = fixture.providers.maskedPending
        _ = fixture.providers.maskedWrongPurpose
        _ = fixture.providers.maskedColorAuxiliary
        _ = fixture.providers.propertyRequest
        _ = fixture.providers.propertyIdentity
        _ = fixture.providers.propertyProgram
        _ = fixture.providers.systemMaskIdentity
        _ = fixture.providers.systemMaskRequest
        _ = fixture.providers.providerProgram
        _ = fixture.providers.providerPending
        _ = fixture.providers.fallbackAssetPath
        _ = fixture.providers.fallbackProperty
        _ = fixture.providers.fallbackPropertyIdentity
        _ = fixture.providers.providerUnavailableDoesNotFallback
        _ = fixture.providers.providerAbsentFallback
        _ = fixture.providers.providerMissingDoesNotFallback
        _ = fixture.providers.providerPendingDoesNotFallback
        _ = fixture.providers.shaderDefaultAfterUnavailableProvider
        _ = fixture.providers.shaderDefaultAfterAbsentProvider
        _ = fixture.preparation.renderSizeField
        _ = fixture.preparation.expectedRenderSize
        _ = fixture.preparation.encodedRange
        _ = fixture.preparation.uniformLayoutCorrect
        _ = fixture.preparation.effectProjectionField
        _ = fixture.preparation.effectProjectionEncoded
        _ = fixture.preparation.modelViewProjectionInverseField
        _ = fixture.preparation.modelViewProjectionInverseEncoded
        _ = fixture.preparation.layerModelField
        _ = fixture.preparation.layerModelEncoded
        _ = fixture.preparation.forwardProjectionField
        _ = fixture.preparation.effectModelViewProjectionField
        _ = fixture.preparation.expectedForwardDiagonal
        _ = fixture.preparation.forwardProjectionEncoded
        _ = fixture.preparation.effectModelViewProjectionEncoded
        _ = fixture.preparation.parallaxField
        _ = fixture.preparation.parallaxPositionEncoded
        _ = fixture.preparation.parallaxRangePreserved
        _ = fixture.preparation.invalidParallaxRejected
        _ = fixture.failures.failures

        let attenuationEligibility = attenuationEligibilityTokens()
        let colorBlendEligibility = colorBlendEligibilityTokens()
        let neutralTextureResolution = neutralTextureResolutionToken(device)
        let neutralTextureResolutionUnseen =
            neutralTextureResolutionUnseenToken(device)
        let separateNeutralTextureResolution =
            separateNeutralTextureResolutionToken(device)
        let neutralTextureResolutionAnalyzer =
            neutralTextureResolutionAnalyzerCases()
        let neutralTextureResolutionFailures =
            neutralTextureResolutionFinalizerFailures(device)
        let dormantGraphInputFacts = dormantGraphInputFactTokens(device)
        let capturedMainInternalTerminal =
            capturedMainInternalTerminalTokens()
        let mappedTextureResolution = mappedTextureResolutionTokens(device)
        let mixedSystemNamedProvider = mixedSystemNamedProviderTokens(device)
        let namedProviderRuntimePurpose = namedProviderRuntimePurposeTokens(device)
        let effectProjectionRequirements = [
            "modelOnly": effectProjectionRequirementToken(
                "g_EffectModelViewProjectionMatrix"
            ),
            "textureForward": effectProjectionRequirementToken(
                "g_EffectTextureProjectionMatrix"
            ),
            "textureInverse": effectProjectionRequirementToken(
                "g_EffectTextureProjectionMatrixInverse"
            ),
        ]

        let extra = try additionalResults()
        let result: [String: Any] = [
            "metalAvailable": true,
            "mappedTextureResolution": mappedTextureResolution,
            "mixedSystemNamedProvider": mixedSystemNamedProvider,
            "namedProviderRuntimePurpose": namedProviderRuntimePurpose,
            "effectProjectionRequirements": effectProjectionRequirements,
            "effectForwardProjectionConsumption": effectForwardProjectionConsumption(device),
            "attenuationEligibilityCases": attenuationEligibility,
            "colorBlendEligibilityCases": colorBlendEligibility,
            "exactCrossStageUniformCases": fixture.preparation.exactCrossStageUniformCases,
            "activeDefaultCache": [
                "launchMasks": fixture.providers.activeDefaultLaunchMasks?.map(Int.init) ?? [-1],
                "failure": failureToken(fixture.providers.activeDefaultMaskProgram),
                "cached": fixture.providers.activeDefaultMaskCache.counters.cachedVariantCount,
                "prepared": fixture.providers.activeDefaultMaskCache.counters.shaderPreparationCount,
                "frontend": fixture.providers.activeDefaultMaskCache.counters.frontendCompilationCount,
                "capacity": fixture.providers.activeDefaultMaskCache.counters.capacityRejectionCount,
            ],
            "positive": [
                "neutralTextureResolution": neutralTextureResolution == "success",
                "neutralTextureResolutionUnseen":
                    neutralTextureResolutionUnseen == "success",
                "separateNeutralTextureResolution":
                    separateNeutralTextureResolution == "success",
                "neutralTextureResolutionAnalyzer":
                    neutralTextureResolutionAnalyzer.values.allSatisfy { $0 },
                "attenuationEligibility": attenuationEligibility.values.allSatisfy { $0 },
                "colorBlendEligibility": colorBlendEligibility.values.allSatisfy { $0 },
                "fixedEightSlots": fixture.preparation.programA.textureSlots.count == 8
                    && fixture.preparation.programA.textureSlots[0] != nil
                    && fixture.preparation.programA.textureSlots.dropFirst().allSatisfy { $0 == nil },
                "uniformLayoutCorrect": fixture.preparation.uniformLayoutCorrect,
                "modelViewProjectionInverseEncoded":
                    fixture.preparation.modelViewProjectionInverseEncoded,
                "effectProjectionInverseEncoded": fixture.preparation.effectProjectionEncoded,
                "layerModelMatrixEncoded": fixture.preparation.layerModelEncoded,
                "effectModelViewProjectionEncoded":
                    fixture.preparation.effectModelViewProjectionEncoded,
                "effectProjectionEncoded": fixture.preparation.forwardProjectionEncoded,
                "parallaxPositionEncoded": fixture.preparation.parallaxPositionEncoded,
                "parallaxRangePreserved": fixture.preparation.parallaxRangePreserved,
                "invalidParallaxRejected": fixture.preparation.invalidParallaxRejected,
                "shaderUniformDefault": fixture.uniforms.tintDefaultCorrect,
                "hostIgnoresShaderDefault": fixture.uniforms.hostDefaultIgnored,
                "explicitUniformOverridesDefault": fixture.uniforms.explicitOverrideCorrect,
                "stageLocalUniformsEncoded": fixture.preparation.stageLocalUniformsEncoded,
                "sharedStageLocalDynamicUniformsEncoded":
                    fixture.preparation.sharedStageLocalDynamicUniformsEncoded,
                "exactCrossStageUniformSchema":
                    fixture.preparation.exactCrossStageUniformCases.values.allSatisfy { $0 },
                "assetReferenceTyped": failureToken(fixture.uniforms.assetProgram) == "success",
                "userReferenceTyped": failureToken(fixture.providers.propertyProgram) == "success",
                "providerReferenceTyped": failureToken(fixture.providers.providerProgram) == "success",
                "maskedDynamicAlphaEncoded": fixture.uniforms.maskedDynamicAlphaEncoded,
                "directUserPropertyScalarRangeFallback":
                    fixture.uniforms.directUserPropertyScalarRangeFallback,
                "sceneScriptDynamicAlphaEncoded": fixture.uniforms.sceneScriptDynamicAlphaEncoded,
                "timelineVectorUpdatesProgramWithoutTopologyChange":
                    fixture.uniforms.timelineVectorUpdatesProgramWithoutTopologyChange,
                "userPropertyScalarFloat2SplatEncoded":
                    fixture.uniforms.userPropertyScalarFloat2SplatEncoded,
                "authoredOutOfRangeScalarFloat2SentinelPreserved":
                    fixture.uniforms.authoredOutOfRangeScalarFloat2SentinelPreserved,
                "directUserPropertyScalarProducerDomainPreserved":
                    fixture.uniforms.directUserPropertyScalarProducerDomainPreserved,
                "staticScalarFloat2SplatEncoded":
                    fixture.uniforms.staticScalarFloat2SplatEncoded,
                "exactStaticFloat2Preserved": fixture.uniforms.exactStaticFloat2Preserved,
                "overlayDataTyped": fixture.providers.overlayDataTyped,
                "optionalMaskWithoutResourceAccepted":
                    fixture.providers.optionalMaskWithoutResourceAccepted,
                "optionalMaskWithResourceAccepted":
                    fixture.providers.optionalMaskWithResourceAccepted,
                "activeDefaultMaskAccepted": fixture.providers.activeDefaultMaskAccepted,
                "activeAuthoredPresenceMaskAccepted":
                    failureToken(fixture.providers.activeAuthoredMaskProgram) == "success",
                "implicitFramebufferTyped": fixture.framebuffer.implicitFramebufferTyped,
                "previousMaterialAliasTyped": fixture.framebuffer.previousAliasTyped,
                "historicalFramebufferMaterialAliasTyped":
                    fixture.framebuffer.historicalFramebufferTyped,
                "stockDefaultProgramPreservesSnapshotAtoms":
                    fixture.framebuffer.stockDefaultProgramPreservesSnapshotAtoms,
                "implicitFramebufferMaterialKeyCaseInsensitive":
                    failureToken(fixture.framebuffer.caseInsensitiveFramebufferProgram) == "success",
                "explicitFramebufferCandidatePreserved":
                    fixture.framebuffer.explicitFramebufferPreserved,
                "shaderDefaultPreservedBeforeImplicitFramebuffer":
                    fixture.framebuffer.shaderDefaultPreserved,
                "realPreparationObserved": !fixture.preparation.programA.preparedShader.cacheKey.isEmpty
                    && !fixture.preparation.programA.preparedShader.vertex.dependencies.isEmpty
                    && !fixture.preparation.programA.preparedShader.fragment.dependencies.isEmpty,
                "frontendObserved": fixture.preparation.programA.frontendProgram.textureBindings.map(\.slot) == [0],
                "audioSpectrumArraysEncoded": fixture.preparation.audioSpectrumEncoded,
                "runtimeLoopStaticProducerAccepted":
                    fixture.preparation.runtimeLoopStaticProducerAccepted,
                "pointerStatePrimaryButtonEncoded": fixture.preparation.pointerStateEncoded,
            ],
            "identity": [
                "semanticStable": fixture.preparation.programA.semanticIdentity == fixture.preparation.programB.semanticIdentity,
                "exactRevisionSensitive": fixture.preparation.programA.exactIdentity != fixture.preparation.programB.exactIdentity,
                "scalarFramebufferDirectRedConsumer": fixture.framebuffer.scalarRedConsumerIdentity,
                "rgbaFramebufferDataConsumer": fixture.framebuffer.rgbaDataConsumerIdentity,
            ],
            "samplerSchema": [
                "regularGraph": samplerPurposeToken(nil),
                "regularAsset": samplerPurposeToken(nil, assetReference: true),
                "albedoAsset": samplerPurposeToken(
                    #"{"material":"albedo"}"#,
                    assetReference: true
                ),
                "noiseAsset": samplerPurposeToken(
                    #"{"material":"noise"}"#,
                    assetReference: true
                ),
                "normalAsset": samplerPurposeToken(
                    #"{"material":"normal"}"#,
                    assetReference: true
                ),
                "normalAssetCaseInsensitive": samplerPurposeToken(
                    #"{"material":"Normal"}"#,
                    assetReference: true
                ),
                "registeredStockNoise": samplerPurposeToken(
                    nil,
                    assetReference: true,
                    assetPath: "util/noise"
                ),
                "registeredStockWaterFlowPhase": samplerPurposeToken(
                    nil,
                    assetReference: true,
                    assetPath: "effects/waterflowphase"
                ),
                "registeredStockWaterRippleNormal": samplerPurposeToken(
                    nil,
                    assetReference: true,
                    assetPath: "effects/waterripplenormal"
                ),
                "registeredStockWaterRippleNormalConflict": samplerPurposeToken(
                    #"{"mode":"opacitymask"}"#,
                    assetReference: true,
                    assetPath: "effects/waterripplenormal"
                ),
                "neighboringWaterRippleNormalUnproven": samplerPurposeToken(
                    nil,
                    assetReference: true,
                    assetPath: "effects/waterripplenormal_extra"
                ),
                "customWaterRippleNormalUnproven": samplerPurposeToken(
                    nil,
                    assetReference: true,
                    assetPath: "custom/waterripplenormal"
                ),
                "registeredStockShimmerGradient": samplerPurposeToken(
                    nil,
                    assetReference: true,
                    assetPath: "gradient/gradient_ferro_fluid"
                ),
                "registeredStockLightShaftsGradient": samplerPurposeToken(
                    nil,
                    assetReference: true,
                    assetPath: "gradient/gradient_iridescent"
                ),
                "registeredStockFireGradient": samplerPurposeToken(
                    nil,
                    assetReference: true,
                    assetPath: "gradient/gradient_fire"
                ),
                "registeredStockFireGradientConflict": samplerPurposeToken(
                    #"{"mode":"opacitymask"}"#,
                    assetReference: true,
                    assetPath: "gradient/gradient_fire"
                ),
                "unregisteredGradient": samplerPurposeToken(
                    nil,
                    assetReference: true,
                    assetPath: "gradient/unknown"
                ),
                "registeredStockCloudNoise": samplerPurposeToken(
                    nil,
                    assetReference: true,
                    assetPath: "util/clouds_256"
                ),
                "registeredStockPerlinNoise": samplerPurposeToken(
                    nil,
                    assetReference: true,
                    assetPath: "util/perlin_256"
                ),
                "registeredStockVoronoiNoise": samplerPurposeToken(
                    nil,
                    assetReference: true,
                    assetPath: "pattern/voronoi"
                ),
                "registeredStockLocalVoronoiNoise": samplerPurposeToken(
                    nil,
                    assetReference: true,
                    assetPath: "pattern/voronoi_local"
                ),
                "registeredStockUniformNoise": samplerPurposeToken(
                    nil,
                    assetReference: true,
                    assetPath: "util/uniform_256"
                ),
                "registeredStockPerlinPurposeConflict": samplerPurposeToken(
                    #"{"mode":"opacitymask"}"#,
                    assetReference: true,
                    assetPath: "util/perlin_256"
                ),
                "registeredStockVoronoiPurposeConflict": samplerPurposeToken(
                    #"{"mode":"opacitymask"}"#,
                    assetReference: true,
                    assetPath: "pattern/voronoi"
                ),
                "neighboringCustomPerlinUnproven": samplerPurposeToken(
                    nil,
                    assetReference: true,
                    assetPath: "custom/perlin_256"
                ),
                "neighboringPerlin512Unproven": samplerPurposeToken(
                    nil,
                    assetReference: true,
                    assetPath: "util/perlin_512"
                ),
                "neighboringPerlinSuffixUnproven": samplerPurposeToken(
                    nil,
                    assetReference: true,
                    assetPath: "util/perlin_256_extra"
                ),
                "neighboringVoronoiSuffixUnproven": samplerPurposeToken(
                    nil,
                    assetReference: true,
                    assetPath: "pattern/voronoi_extra"
                ),
                "neighboringLocalVoronoiSuffixUnproven": samplerPurposeToken(
                    nil,
                    assetReference: true,
                    assetPath: "pattern/voronoi_local_extra"
                ),
                "neighboringUniformSuffixUnproven": samplerPurposeToken(
                    nil,
                    assetReference: true,
                    assetPath: "util/uniform_256_extra"
                ),
                "registeredStockPurposeConflict": samplerPurposeToken(
                    #"{"mode":"opacitymask"}"#,
                    assetReference: true,
                    assetPath: "util/noise"
                ),
                "unknownMaterialAsset": samplerPurposeToken(
                    #"{"material":"unknown"}"#,
                    assetReference: true
                ),
                "conflictingMaterial": samplerPurposeToken(
                    #"{"material":"normal"}"#,
                    vertexMetadata: #"{"material":"noise"}"#,
                    assetReference: true
                ),
                "reachableConditionalAlbedo": reachableConditionalPurposeToken(),
                "customPurposeIgnored": samplerPurposeToken(#"{"purpose":"mask"}"#),
                "opacityMask": samplerPurposeToken(#"{"mode":"opacitymask"}"#),
                "rgbMask": samplerPurposeToken(#"{"mode":"rgbmask"}"#),
                "rgbMaskNamedTarget": samplerPurposeToken(
                    #"{"mode":"rgbmask"}"#,
                    namedTargetReference: true
                ),
                "flowMask": samplerPurposeToken(#"{"mode":"flowmask"}"#),
                "normal": samplerPurposeToken(#"{"mode":"normal"}"#),
                "depth": samplerPurposeToken(#"{"mode":"depth"}"#),
                "depthR8": samplerPurposeToken(
                    #"{"mode":"depth","format":"r8"}"#
                ),
                "depthWrongFormat": samplerPurposeToken(
                    #"{"mode":"depth","format":"rgba8"}"#
                ),
                "normalFormat": samplerPurposeToken(#"{"format":"normalmap"}"#),
                "genericFormat": samplerPurposeToken(#"{"format":"rgba8"}"#),
                "unknownMode": samplerPurposeToken(#"{"mode":"mystery"}"#),
            ],
            "samplerSchemaOrigin": [
                "unmarkedReadiness": samplerReadinessSchemaToken(
                    #"{"mode":"opacitymask","combo":"MASK","default":"textures/mask.tex"}"#
                ),
                "authoredMarker": samplerReadinessSchemaToken(
                    #"[COMBO] {"combo":"AUTHORED","default":1}"#
                ),
            ],
            "implicitFramebufferSchema": [
                "registeredStockDefault": implicitFramebufferProjectionToken(
                    defaultAssetPath: "util/noise"
                ),
                "registeredAuthoredCandidate":
                    implicitFramebufferCandidateProjectionToken(
                        assetPath: "effects/waterflowphase"
                    ),
                "unprovenAuthoredCandidate":
                    implicitFramebufferCandidateProjectionToken(
                        assetPath: "custom/unproven-auxiliary"
                    ),
                "graphAuthoredCandidate":
                    implicitFramebufferGraphCandidateProjectionToken(),
                "unknownDefault": implicitFramebufferProjectionToken(
                    defaultAssetPath: "textures/unknown-default.tex"
                ),
            ],
            "shaderPreparationBoundary": [
                "missingSourceGraph": missingSourceGraphDiagnostic(),
                "selfGatedReadiness": selfGatedReadinessSeedTokens(),
            ],
            "compatibilityTargetTextureCandidate":
                compatibilityTargetTextureCandidateTokens(),
            "neutralTextureResolution": neutralTextureResolution,
            "neutralTextureResolutionUnseen": neutralTextureResolutionUnseen,
            "separateNeutralTextureResolution": separateNeutralTextureResolution,
            "neutralTextureResolutionAnalyzer": neutralTextureResolutionAnalyzer,
            "neutralTextureResolutionFailures": neutralTextureResolutionFailures,
            "dormantGraphInputFacts": dormantGraphInputFacts,
            "rtDefaultAdmission": rtDefaultAdmissionTokens(device),
            "capturedMainInternalTerminal": capturedMainInternalTerminal,
            "admittedEffectIngress": fixture.preparation.admittedEffectIngress,
            "failures": fixture.failures.failures,
            "arithmeticColorBoundary": fixture.failures.arithmeticColorBoundary,
            "materialCrossTemplateCache": crossTemplateMaterialCacheTokens(device),
            "preparedVariantFrames": scenePreparedVariantFrameCases(device),
        ]
        return result.merging(extra) { _, additional in additional }
    }
}
