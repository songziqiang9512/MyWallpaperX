import Foundation

extension SceneAuthoredEffectExecutionCatalog {
    var reportLines: [String] {
        let transformDiagnostics = chainsByLayerID.sorted(by: { $0.key < $1.key }).flatMap {
            entry in
            entry.value.stages.compactMap(\.transform).flatMap { transform in
                transform.staticFallbackDiagnostics.map {
                    "layer=\(entry.key),\($0.reportValue)"
                }
            }
        }
        let isolatedCursorRippleDiagnostics = isolatedDiagnostics {
            $0.isolatedCursorRippleOmittedEffectPaths
        }
        let isolatedShineDiagnostics = isolatedDiagnostics {
            $0.isolatedShineOmittedEffectPaths
        }
        return [
            "authoredEffectGraphPlannedCount: \(chainsByLayerID.count)",
            "authoredEffectGraphMaterialNodeCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.materialNodeCount })",
            "authoredEffectGraphLogicalRTCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.logicalRenderTargetCount })",
            "authoredEffectGraphSupportLevel: \(chainsByLayerID.isEmpty ? "none" : "executed-degraded")",
            "authoredEffectGraphHiddenEligibleCount: \(hiddenEligibleLayerIDs.count)",
            "authoredEffectGraphHiddenEligibleLayerIDs: \(hiddenEligibleLayerIDs.map(String.init).joined(separator: ","))",
            "authoredEffectGraphLegacyBlurBlockedCount: \(legacyGaussianBlurBlockedLayerIDs.count)",
            "authoredEffectGraphLegacyBlurBlockedLayerIDs: \(legacyGaussianBlurBlockedLayerIDs.sorted().map(String.init).joined(separator: ","))",
            "authoredEffectGraphChainCount: \(chainsByLayerID.values.filter { $0.stages.count > 1 }.count)",
            "authoredEffectGraphStageCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.stages.count })",
            "authoredEffectGraphLocalContrastCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.localContrastCount })",
            "authoredEffectGraphOpacityCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.opacityCount })",
            "authoredEffectGraphColorKeyCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.colorKeyCount })",
            "authoredEffectGraphColorGradingCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.colorGradingCount })",
            "authoredEffectGraphWorkshopShiftHueCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.workshopShiftHueCount })",
            "authoredEffectGraphWorkshopAudioBarsCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.workshopAudioBarsCount })",
            "authoredEffectGraphWorkshopGradientCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.workshopGradientCount })",
            "authoredEffectGraphWorkshopAudioHueShiftCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.workshopAudioHueShiftCount })",
            "authoredEffectGraphWorkshopShadowCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.workshopShadowCount })",
            "authoredEffectGraphSpinCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.spinCount })",
            "authoredEffectGraphProceduralNoiseCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.proceduralNoiseCount })",
            "authoredEffectGraphFilmGrainCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.filmGrainCount })",
            "authoredEffectGraphLightShaftsCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.lightShaftsCount })",
            "authoredEffectGraphShakeCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.shakeCount })",
            "authoredEffectGraphWaterFlowCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.waterFlowCount })",
            "authoredEffectGraphWaterWavesCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.waterWavesCount })",
            "authoredEffectGraphCursorRippleCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.cursorRippleCount })",
            "authoredEffectGraphCursorRippleIsolatedCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.isolatedCursorRippleCount })",
            "authoredEffectGraphCursorRippleOmittedEffects: \(isolatedCursorRippleDiagnostics.joined(separator: ";"))",
            "authoredEffectGraphFoliageSwayCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.foliageSwayCount })",
            "authoredEffectGraphWaterRippleCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.waterRippleCount })",
            "authoredEffectGraphDepthParallaxCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.depthParallaxCount })",
            "authoredEffectGraphIrisInlineSuffixCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.irisInlineSuffixCount })",
            "authoredEffectGraphXRayCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.xRayCount })",
            "authoredEffectGraphClippingMaskCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.clippingMaskCount })",
            "authoredEffectGraphBlendCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.blendCount })",
            "authoredEffectGraphTintCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.tintCount })",
            "authoredEffectGraphTransformCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.transformCount })",
            "authoredEffectGraphFisheyeZeroDistortionCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.fisheyeZeroDistortionCount })",
            "authoredEffectGraphTransformStaticFallbackCount: \(transformDiagnostics.count)",
            "authoredEffectGraphTransformStaticFallbackDiagnostics: \(transformDiagnostics.joined(separator: ";"))",
            "authoredEffectGraphPulseCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.pulseCount })",
            "authoredEffectGraphGodraysCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.godraysCount })",
            "authoredEffectGraphShineCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.shineCount })",
            "authoredEffectGraphShineIsolatedCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.isolatedShineCount })",
            "authoredEffectGraphShineOmittedEffects: \(isolatedShineDiagnostics.joined(separator: ";"))",
            "authoredEffectGraphAuthoredShaderCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.authoredShaderCount })",
            "authoredEffectGraphScrollCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.scrollCount })",
            "authoredEffectGraphXRayPrefixCount: \(xRayPrefixOmittedEffectPathsByLayerID.count)",
            "authoredEffectGraphXRayPrefixOmittedEffects: \(xRayPrefixOmittedEffectPathsByLayerID.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value.joined(separator: ","))" }.joined(separator: ";"))",
        ]
    }

    private func isolatedDiagnostics(
        omittedPaths: (SceneAuthoredEffectExecutionChain) -> [String]
    ) -> [String] {
        chainsByLayerID.sorted { $0.key < $1.key }.compactMap { entry in
            let omitted = omittedPaths(entry.value)
            guard !omitted.isEmpty else { return nil }
            return "layer=\(entry.key),omitted=\(omitted.joined(separator: ","))"
        }
    }
}
