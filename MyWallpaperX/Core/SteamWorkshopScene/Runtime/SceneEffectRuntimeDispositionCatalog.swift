import Foundation

struct SceneEffectRuntimeDispositionCatalog {
    typealias Admission = SceneAuthoredEffectStageAdmission
    typealias Disposition = SceneEffectStageRuntimeDisposition
    typealias EffectKey = SceneAuthoredEffectRenderPlan.EffectKey

    let dispositions: [Disposition]
    let routeGroups: [SceneEffectStaticRouteGroup]
    let descriptorIdentityConserved: Bool
    let groupIdentityConserved: Bool
    let strictIdentityConserved: Bool

    init(
        descriptor: SceneRenderDescriptor,
        authoredCatalog: SceneAuthoredEffectExecutionCatalog,
        resourcesByLayerID: [Int: SceneLegacyEffectResourceAvailability]
    ) {
        let admissionsByLayerID = Dictionary(
            grouping: authoredCatalog.stageAdmissions,
            by: \.key.layerID
        )
        var records: [Disposition] = []
        var groups: [SceneEffectStaticRouteGroup] = []
        for layer in descriptor.layers where !layer.effects.isEmpty {
            let admissions = admissionsByLayerID[layer.id] ?? []
            let activeAdmissions = admissions.filter { $0.activity == .active }
            if activeAdmissions.isEmpty {
                records.append(contentsOf: admissions.map(Self.inactiveDisposition))
                groups.append(SceneEffectStaticRouteGroup(
                    layerID: layer.id,
                    kind: .inactive,
                    effectKeys: [],
                    ownerKeys: [],
                    aggregateContributorKeys: [],
                    reasonCode: "no-active-effect"
                ))
                continue
            }
            if authoredCatalog.chainsByLayerID[layer.id] != nil {
                let strict = admissions.map(Self.strictDisposition)
                records.append(contentsOf: strict)
                groups.append(Self.routeGroup(
                    layerID: layer.id,
                    kind: .authored,
                    dispositions: strict,
                    reason: nil
                ))
                continue
            }
            let legacy = SceneEffectRuntimePlanner.legacyPlanningDecision(
                for: layer,
                resources: resourcesByLayerID[layer.id] ?? .none,
                blocksLegacyGaussianBlur: authoredCatalog
                    .legacyGaussianBlurBlockedLayerIDs.contains(layer.id)
            )
            let legacyByKey = Dictionary(
                uniqueKeysWithValues: legacy.dispositions.map { ($0.key, $0) }
            )
            let merged = admissions.map { admission in
                admission.activity == .active
                    ? legacyByKey[admission.key] ?? Self.unattributedDisposition(
                        admission,
                        reason: "legacy-decision-key-missing"
                    )
                    : Self.inactiveDisposition(admission)
            }
            records.append(contentsOf: merged)
            groups.append(Self.routeGroup(
                layerID: layer.id,
                kind: legacy.routeGroup.kind,
                dispositions: merged,
                reason: legacy.routeGroup.reasonCode
            ))
        }

        dispositions = records.sorted(by: Self.less)
        routeGroups = groups.sorted { $0.layerID < $1.layerID }
        let dispositionKeys = dispositions.map(\.key)
        descriptorIdentityConserved = dispositionKeys.count
                == authoredCatalog.descriptorEffectStageCount
            && Set(dispositionKeys).count == dispositionKeys.count
            && Set(dispositionKeys) == authoredCatalog.descriptorEffectStageKeys
        groupIdentityConserved = Self.groupsAreConserved(
            dispositions: dispositions,
            groups: routeGroups
        )
        strictIdentityConserved = Self.strictMappingsAreConserved(
            admissions: authoredCatalog.stageAdmissions,
            dispositions: dispositions,
            strictLayerIDs: Set(authoredCatalog.chainsByLayerID.keys)
        )
    }

    var reportLines: [String] {
        [
            "effectStageRuntimeDispositionSchema: 1",
            "effectStageRuntimeRouteScope: effect-induced-static",
            "effectStageRuntimeDispositionCount: \(dispositions.count)",
            "effectStageRuntimeDispositionKindCounts: \(countMap(Disposition.Kind.allCases, keyPath: \.kind))",
            "effectStageRuntimeDispositionAttributionCounts: \(countMap(Disposition.Attribution.allCases, keyPath: \.attribution))",
            "effectStageRuntimeDispositionRoleCounts: \(countMap(Disposition.RouteRole.allCases, keyPath: \.routeRole))",
            "effectStaticRouteGroupCount: \(routeGroups.count)",
            "effectStaticRouteGroupKindCounts: \(groupCountMap())",
            "effectStageRuntimeDescriptorIdentityConserved: \(descriptorIdentityConserved)",
            "effectStageRuntimeGroupIdentityConserved: \(groupIdentityConserved)",
            "effectStageRuntimeStrictIdentityConserved: \(strictIdentityConserved)",
        ] + routeGroups.map(\.reportLine) + dispositions.map(\.reportLine)
    }

    private nonisolated static func inactiveDisposition(
        _ admission: Admission
    ) -> Disposition {
        Disposition(
            key: admission.key,
            definitionPath: admission.definitionPath,
            kind: .inactive,
            attribution: .none,
            family: nil,
            routeGroupID: nil,
            routeRole: .none,
            reasonCode: admission.activity.rawValue
        )
    }

    private nonisolated static func strictDisposition(
        _ admission: Admission
    ) -> Disposition {
        guard admission.activity == .active else {
            return inactiveDisposition(admission)
        }
        switch admission.strictAdmission {
        case .admittedDedicated:
            return disposition(
                admission,
                kind: .strictDedicated,
                family: admission.backendName,
                role: .owner
            )
        case .admittedGeneric:
            return disposition(
                admission,
                kind: .strictGeneric,
                family: admission.profileName ?? admission.backendName,
                role: .owner
            )
        case .notAdmitted where admission.coverage == .terminalInlineSuffix:
            return disposition(
                admission,
                kind: .strictInlineSuffix,
                family: "iris-inline",
                role: .owner
            )
        case .notAdmitted:
            return disposition(
                admission,
                kind: .omittedByStrictChain,
                family: nil,
                role: .member
            )
        case .inactive:
            return unattributedDisposition(
                admission,
                reason: "active-strict-inactive"
            )
        }
    }

    private nonisolated static func disposition(
        _ admission: Admission,
        kind: Disposition.Kind,
        family: String?,
        role: Disposition.RouteRole
    ) -> Disposition {
        Disposition(
            key: admission.key,
            definitionPath: admission.definitionPath,
            kind: kind,
            attribution: .exactKey,
            family: family,
            routeGroupID: admission.key.layerID,
            routeRole: role,
            reasonCode: admission.reasonCode
        )
    }

    private nonisolated static func unattributedDisposition(
        _ admission: Admission,
        reason: String
    ) -> Disposition {
        Disposition(
            key: admission.key,
            definitionPath: admission.definitionPath,
            kind: .unattributed,
            attribution: .none,
            family: nil,
            routeGroupID: admission.activity == .active
                ? admission.key.layerID
                : nil,
            routeRole: admission.activity == .active ? .member : .none,
            reasonCode: reason
        )
    }

    private nonisolated static func routeGroup(
        layerID: Int,
        kind: SceneEffectStaticRouteGroup.Kind,
        dispositions: [Disposition],
        reason: String?
    ) -> SceneEffectStaticRouteGroup {
        let active = dispositions.filter { $0.routeGroupID == layerID }
        return SceneEffectStaticRouteGroup(
            layerID: layerID,
            kind: kind,
            effectKeys: active.map(\.key),
            ownerKeys: active.filter { $0.routeRole == .owner }.map(\.key),
            aggregateContributorKeys: active.filter {
                $0.routeRole == .aggregateContributor
            }.map(\.key),
            reasonCode: reason
        )
    }

    private nonisolated static func groupsAreConserved(
        dispositions: [Disposition],
        groups: [SceneEffectStaticRouteGroup]
    ) -> Bool {
        guard Set(groups.map(\.layerID)).count == groups.count else { return false }
        let byID = Dictionary(uniqueKeysWithValues: groups.map { ($0.layerID, $0) })
        return groups.allSatisfy { group in
            let records = dispositions.filter { $0.routeGroupID == group.layerID }
            return Set(records.map(\.key)) == Set(group.effectKeys)
                && Set(records.filter { $0.routeRole == .owner }.map(\.key))
                    == Set(group.ownerKeys)
                && Set(records.filter {
                    $0.routeRole == .aggregateContributor
                }.map(\.key)) == Set(group.aggregateContributorKeys)
        } && dispositions.allSatisfy {
            $0.routeGroupID == nil || byID[$0.routeGroupID!] != nil
        }
    }

    private nonisolated static func strictMappingsAreConserved(
        admissions: [Admission],
        dispositions: [Disposition],
        strictLayerIDs: Set<Int>
    ) -> Bool {
        let keys = dispositions.map(\.key)
        guard dispositions.count == admissions.count,
              Set(keys).count == keys.count else {
            return false
        }
        let byKey = Dictionary(uniqueKeysWithValues: dispositions.map {
            ($0.key, $0)
        })
        return admissions.allSatisfy { admission in
            guard let disposition = byKey[admission.key],
                  disposition.definitionPath == admission.definitionPath else {
                return false
            }
            guard admission.activity == .active else {
                return disposition.kind == .inactive
                    && disposition.routeGroupID == nil
                    && disposition.routeRole == .none
            }
            if strictLayerIDs.contains(admission.key.layerID) {
                switch admission.strictAdmission {
                case .admittedDedicated:
                    return disposition.kind == .strictDedicated
                        && disposition.routeRole == .owner
                case .admittedGeneric:
                    return disposition.kind == .strictGeneric
                        && disposition.routeRole == .owner
                case .notAdmitted where admission.coverage == .terminalInlineSuffix:
                    return disposition.kind == .strictInlineSuffix
                        && disposition.routeRole == .owner
                case .notAdmitted:
                    return disposition.kind == .omittedByStrictChain
                        && disposition.routeRole == .member
                case .inactive:
                    return false
                }
            }
            guard admission.strictAdmission == .notAdmitted else { return false }
            switch disposition.kind {
            case .inactive, .strictDedicated, .strictGeneric,
                 .strictInlineSuffix, .omittedByStrictChain:
                return false
            default:
                return true
            }
        }
    }

    private func countMap<Value: RawRepresentable & Equatable>(
        _ values: [Value],
        keyPath: KeyPath<Disposition, Value>
    ) -> String where Value.RawValue == String {
        values.map { value in
            "\(value.rawValue)=\(dispositions.filter { $0[keyPath: keyPath] == value }.count)"
        }.joined(separator: ",")
    }

    private func groupCountMap() -> String {
        SceneEffectStaticRouteGroup.Kind.allCases.map { kind in
            "\(kind.rawValue)=\(routeGroups.filter { $0.kind == kind }.count)"
        }.joined(separator: ",")
    }

    private nonisolated static func less(
        _ lhs: Disposition,
        _ rhs: Disposition
    ) -> Bool {
        if lhs.key.layerID != rhs.key.layerID {
            return lhs.key.layerID < rhs.key.layerID
        }
        if lhs.key.effectIndex != rhs.key.effectIndex {
            return lhs.key.effectIndex < rhs.key.effectIndex
        }
        return lhs.key.descriptorID < rhs.key.descriptorID
    }
}
