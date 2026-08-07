import Foundation

extension SceneAuthoredEffectExecutionCatalog {
    var reportLines: [String] {
        let transformDiagnostics = chainsByLayerID.sorted(by: { $0.key < $1.key }).flatMap {
            entry in
            entry.value.executionStages.compactMap(\.transform).flatMap { transform in
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
        let activityCounts = countMap(
            SceneAuthoredEffectStageAdmission.Activity.allCases,
            value: \.activity
        )
        let strictAdmissionCounts = countMap(
            SceneAuthoredEffectStageAdmission.StrictAdmission.allCases,
            value: \.strictAdmission
        )
        let coverageCounts = countMap(
            SceneAuthoredEffectStageAdmission.Coverage.allCases,
            value: \.coverage
        )
        let activeCount = stageAdmissions.filter { $0.activity == .active }.count
        let inactiveActivityCount = stageAdmissions.filter {
            $0.activity != .active
        }.count
        let inactiveStrictCount = stageAdmissions.filter {
            $0.strictAdmission == .inactive
        }.count
        let activeStrictCount = stageAdmissions.filter {
            $0.strictAdmission != .inactive
        }.count
        let parsedKeys = stageAdmissions.map(\.key)
        let strictAdmissionKeys = stageAdmissions.compactMap { admission in
            switch admission.strictAdmission {
            case .admittedDedicated, .admittedGeneric:
                admission.key
            case .inactive, .notAdmitted:
                nil
            }
        }
        let chainStages = chainsByLayerID.values.flatMap(\.executionStages)
        let chainStageIdentityValid = chainStages.allSatisfy {
            $0.renderGraph.effects.count == 1
        }
        let chainStageKeys = chainStages.compactMap { stage in
            stage.renderGraph.effects.first?.key
        } + Array(resolvedMaterialStageKeys)
        let stageCompileFailures = chainAdmissionsByLayerID.values.compactMap {
            $0.rejection?.stageCompileFailure
        }
        let compileFailureCodes = countedValues(
            stageCompileFailures.map { $0.code.rawValue }
        )
        let compilerProbes = stageCompileFailures.flatMap(\.probes)
        let compilerProbeOutcomes = countedValues(compilerProbes.map { probe in
            switch probe.outcome {
            case .notApplicable:
                "not-applicable"
            case .rejected:
                "rejected"
            }
        })
        let compilerFailureCodes = countedValues(compilerProbes.compactMap { probe in
            guard case .rejected(let failure) = probe.outcome else { return nil }
            return "\(failure.backend.rawValue)/\(failure.phase.rawValue)/"
                + failure.code.rawValue
        })
        return [
            "authoredEffectGraphPlannedCount: \(chainsByLayerID.count)",
            "authoredEffectGraphMaterialNodeCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.materialNodeCount })",
            "authoredEffectGraphLogicalRTCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.logicalRenderTargetCount })",
            "authoredEffectGraphSupportLevel: \(chainsByLayerID.isEmpty ? "none" : "executed-degraded")",
            "authoredEffectGraphHiddenEligibleCount: \(hiddenEligibleLayerIDs.count)",
            "authoredEffectGraphHiddenEligibleLayerIDs: \(hiddenEligibleLayerIDs.map(String.init).joined(separator: ","))",
            "authoredEffectGraphLegacyBlurBlockedCount: \(legacyGaussianBlurBlockedLayerIDs.count)",
            "authoredEffectGraphLegacyBlurBlockedLayerIDs: \(legacyGaussianBlurBlockedLayerIDs.sorted().map(String.init).joined(separator: ","))",
            "authoredEffectGraphChainCount: \(chainsByLayerID.values.filter { $0.executionStages.count > 1 }.count)",
            "authoredEffectGraphStageCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.executionStages.count })",
            "authoredEffectStageDescriptorCount: \(descriptorEffectStageCount)",
            "authoredEffectStageParsedCount: \(stageAdmissions.count)",
            "authoredEffectStageActivityCounts: \(activityCounts)",
            "authoredEffectStageStrictAdmissionCounts: \(strictAdmissionCounts)",
            "authoredEffectStageCoverageCounts: \(coverageCounts)",
            "authoredEffectStageDescriptorIdentityConserved: \(descriptorIdentityConserved(parsedKeys))",
            "authoredEffectStageActivityConserved: \(activityCount == descriptorEffectStageCount)",
            "authoredEffectStageInactiveAdmissionConserved: \(inactiveActivityCount == inactiveStrictCount)",
            "authoredEffectStageActiveAdmissionConserved: \(activeCount == activeStrictCount)",
            "authoredEffectStageStrictIdentityConserved: \(strictIdentityConserved(admissionKeys: strictAdmissionKeys, chainKeys: chainStageKeys, chainStageIdentityValid: chainStageIdentityValid))",
            "authoredEffectStageCompileFailureCount: \(stageCompileFailures.count)",
            "authoredEffectStageCompileFailureCodes: \(compileFailureCodes)",
            "authoredEffectStageCompilerProbeOutcomeCounts: \(compilerProbeOutcomes)",
            "authoredEffectStageCompilerFailureCodes: \(compilerFailureCodes)",
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
            "authoredEffectGraphWaterCausticsCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.waterCausticsCount })",
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
            "authoredEffectGraphAuthoredShaderCount: 0",
            "authoredEffectGraphScrollCount: 0",
            "authoredEffectGraphXRayPrefixCount: \(xRayPrefixOmittedEffectPathsByLayerID.count)",
            "authoredEffectGraphXRayPrefixOmittedEffects: \(xRayPrefixOmittedEffectPathsByLayerID.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value.joined(separator: ","))" }.joined(separator: ";"))",
        ] + stageAdmissions.map(\.reportLine)
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

    private func countMap<Value: RawRepresentable & Equatable>(
        _ values: [Value],
        value: KeyPath<SceneAuthoredEffectStageAdmission, Value>
    ) -> String where Value.RawValue == String {
        values.map { candidate in
            let count = stageAdmissions.filter { $0[keyPath: value] == candidate }.count
            return "\(candidate.rawValue)=\(count)"
        }.joined(separator: ",")
    }

    private func countedValues(_ values: [String]) -> String {
        Dictionary(grouping: values, by: { $0 })
            .map { key, values in (key, values.count) }
            .sorted { $0.0 < $1.0 }
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: ",")
    }

    private var activityCount: Int {
        SceneAuthoredEffectStageAdmission.Activity.allCases.reduce(0) { total, activity in
            total + stageAdmissions.filter { $0.activity == activity }.count
        }
    }

    private func descriptorIdentityConserved(
        _ parsedKeys: [SceneAuthoredEffectRenderPlan.EffectKey]
    ) -> Bool {
        parsedKeys.count == descriptorEffectStageCount
            && Set(parsedKeys).count == parsedKeys.count
            && Set(parsedKeys) == descriptorEffectStageKeys
    }

    private func strictIdentityConserved(
        admissionKeys: [SceneAuthoredEffectRenderPlan.EffectKey],
        chainKeys: [SceneAuthoredEffectRenderPlan.EffectKey],
        chainStageIdentityValid: Bool
    ) -> Bool {
        chainStageIdentityValid
            && admissionKeys.count == Set(admissionKeys).count
            && chainKeys.count == Set(chainKeys).count
            && Set(admissionKeys) == Set(chainKeys)
    }
}
