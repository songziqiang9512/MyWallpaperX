import Foundation

extension SceneEffectAdmissionCatalog {
    var resolvedMaterialExecutionLayerIDs: Set<Int> {
        Set(unifiedExecutionStageKeys.map(\.layerID))
    }

    var reportLines: [String] {
        let activityCounts = countMap(
            SceneEffectStageAdmission.Activity.allCases,
            value: \.activity
        )
        let admissionCounts = countMap(
            SceneEffectStageAdmission.Admission.allCases,
            value: \.admission
        )
        let coverageCounts = countMap(
            SceneEffectStageAdmission.Coverage.allCases,
            value: \.coverage
        )
        let activeCount = stageAdmissions.filter {
            $0.activity.participatesInUnifiedRoute
        }.count
        let inactiveActivityCount = stageAdmissions.filter {
            !$0.activity.participatesInUnifiedRoute
        }.count
        let inactiveAdmissionCount = stageAdmissions.filter {
            $0.admission == .inactive
        }.count
        let activeAdmissionCount = stageAdmissions.filter {
            $0.admission != .inactive
        }.count
        let parsedKeys = stageAdmissions.map(\.key)
        let admittedKeys = stageAdmissions.compactMap { admission in
            switch admission.admission {
            case .admittedDedicated, .admittedFallback, .admittedGeneric,
                 .admittedPassthrough:
                admission.key
            case .inactive, .notAdmitted:
                nil
            }
        }
        let executionKeys = Array(unifiedExecutionStageKeys)
        return [
            "effectAdmissionSchema: 1",
            "effectStageDescriptorCount: \(descriptorEffectStageCount)",
            "effectStageParsedCount: \(stageAdmissions.count)",
            "effectStageActivityCounts: \(activityCounts)",
            "effectStageAdmissionCounts: \(admissionCounts)",
            "effectStageCoverageCounts: \(coverageCounts)",
            "effectStageDescriptorIdentityConserved: \(descriptorIdentityConserved(parsedKeys))",
            "effectStageActivityConserved: \(activeCount + inactiveActivityCount == descriptorEffectStageCount)",
            "effectStageInactiveAdmissionConserved: \(inactiveActivityCount == inactiveAdmissionCount)",
            "effectStageActiveAdmissionConserved: \(activeCount == activeAdmissionCount)",
            "effectStageExecutionIdentityConserved: \(executionIdentityConserved(admissionKeys: admittedKeys, executionKeys: executionKeys))",
        ] + stageAdmissions.map(\.reportLine)
    }

    private func countMap<Value: RawRepresentable & Equatable>(
        _ values: [Value],
        value: KeyPath<SceneEffectStageAdmission, Value>
    ) -> String where Value.RawValue == String {
        values.map { candidate in
            let count = stageAdmissions.filter { $0[keyPath: value] == candidate }.count
            return "\(candidate.rawValue)=\(count)"
        }.joined(separator: ",")
    }

    private func descriptorIdentityConserved(
        _ parsedKeys: [SceneAuthoredEffectRenderPlan.EffectKey]
    ) -> Bool {
        parsedKeys.count == descriptorEffectStageCount
            && Set(parsedKeys).count == parsedKeys.count
            && Set(parsedKeys) == descriptorEffectStageKeys
    }

    private func executionIdentityConserved(
        admissionKeys: [SceneAuthoredEffectRenderPlan.EffectKey],
        executionKeys: [SceneAuthoredEffectRenderPlan.EffectKey]
    ) -> Bool {
        admissionKeys.count == Set(admissionKeys).count
            && executionKeys.count == Set(executionKeys).count
            && Set(admissionKeys) == Set(executionKeys)
    }
}
