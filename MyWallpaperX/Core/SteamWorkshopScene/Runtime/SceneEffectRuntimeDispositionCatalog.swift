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
    let resolvedMaterialOwnershipConserved: Bool
    init(
        descriptor: SceneRenderDescriptor,
        authoredCatalog: SceneAuthoredEffectExecutionCatalog,
        resourcesByLayerID: [Int: SceneLegacyEffectResourceAvailability],
        resolvedMaterialSubjects: [SceneEffectExactRuntimeSubject] = []
    ) {
        let admissionsByLayerID = Dictionary(
            grouping: authoredCatalog.stageAdmissions,
            by: \.key.layerID
        )
        let subjectsByLayerID = Dictionary(
            grouping: resolvedMaterialSubjects,
            by: \.key.layerID
        )
        var resolvedLayerIDs = Set<Int>()
        var ownershipConserved = true
        for (layerID, subjects) in subjectsByLayerID {
            let activeKeys = Set((admissionsByLayerID[layerID] ?? []).compactMap {
                $0.activity == .active ? $0.key : nil
            })
            let admissionByKey = Dictionary(
                uniqueKeysWithValues: (admissionsByLayerID[layerID] ?? []).map {
                    ($0.key, $0)
                }
            )
            let keys = subjects.map(\.key)
            guard !keys.isEmpty,
                  Set(keys).count == keys.count, Set(keys) == activeKeys,
                  subjects.allSatisfy({ subject in
                      guard subject.key.layerID == layerID,
                            let admission = admissionByKey[subject.key] else {
                          return false
                      }
                      switch admission.strictAdmission {
                      case .admittedGeneric:
                          return subject.family == "resolved-material"
                      case .admittedDedicated:
                          return admission.backendName == subject.family
                      default:
                          return false
                      }
                  }) else {
                ownershipConserved = false
                continue
            }
            resolvedLayerIDs.insert(layerID)
        }
        resolvedMaterialOwnershipConserved = ownershipConserved
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
            if resolvedLayerIDs.contains(layer.id) {
                let subjectByKey = Dictionary(uniqueKeysWithValues:
                    (subjectsByLayerID[layer.id] ?? []).map { ($0.key, $0) }
                )
                let migrated = admissions.map { admission in
                    admission.activity == .active
                        ? Self.resolvedDisposition(
                            admission,
                            family: subjectByKey[admission.key]?.family
                        )
                        : Self.inactiveDisposition(admission)
                }
                records.append(contentsOf: migrated)
                groups.append(Self.routeGroup(
                    layerID: layer.id,
                    kind: .authored,
                    dispositions: migrated,
                    reason: nil
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
            strictLayerIDs: Set(authoredCatalog.chainsByLayerID.keys),
            resolvedLayerIDs: resolvedLayerIDs
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
            "effectStageRuntimeResolvedMaterialOwnershipConserved: \(resolvedMaterialOwnershipConserved)",
        ] + routeGroups.map(\.reportLine) + dispositions.map(\.reportLine)
    }
    /// Projects only exact static owners for runtime evidence.  This is a
    /// resource-backed telemetry view; it is deliberately not an admission
    /// input and excludes aggregate, structural, omitted, and route-only
    /// records.
    var resolvedMaterialExecutionEvidenceSubjects:
        [SceneEffectExactRuntimeSubject] {
        dispositions.compactMap { disposition in
            guard disposition.attribution == .exactKey,
                  disposition.kind == .strictDedicated
                    || disposition.kind == .strictGeneric
                    || disposition.kind == .strictInlineSuffix
                    || disposition.kind == .legacyExactInline
                    || disposition.kind == .legacyExactOffscreen,
                  let family = disposition.family,
                  !family.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            return .init(key: disposition.key, family: family)
        }
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

    private nonisolated static func resolvedDisposition(
        _ admission: Admission,
        family: String?
    ) -> Disposition {
        switch admission.strictAdmission {
        case .admittedGeneric where family == "resolved-material":
            return disposition(
                admission,
                kind: .strictGeneric,
                family: family,
                role: .owner,
                reason: "resolved-material-capability-owner"
            )
        case .admittedDedicated where family == admission.backendName:
            return disposition(
                admission,
                kind: .strictDedicated,
                family: family,
                role: .owner
            )
        default:
            return unattributedDisposition(
                admission,
                reason: "resolved-material-subject-mismatch"
            )
        }
    }

    private nonisolated static func disposition(
        _ admission: Admission,
        kind: Disposition.Kind,
        family: String?,
        role: Disposition.RouteRole,
        reason: String? = nil
    ) -> Disposition {
        Disposition(
            key: admission.key,
            definitionPath: admission.definitionPath,
            kind: kind,
            attribution: .exactKey,
            family: family,
            routeGroupID: admission.key.layerID,
            routeRole: role,
            reasonCode: reason ?? admission.reasonCode
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
