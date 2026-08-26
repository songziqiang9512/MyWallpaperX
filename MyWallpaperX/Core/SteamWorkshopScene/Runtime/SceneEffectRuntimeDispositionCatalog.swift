import Foundation

struct SceneEffectRuntimeDispositionCatalog {
    typealias Admission = SceneEffectStageAdmission
    typealias Disposition = SceneEffectStageRuntimeDisposition
    typealias EffectKey = SceneAuthoredEffectRenderPlan.EffectKey
    let dispositions: [Disposition]
    let routeGroups: [SceneEffectStaticRouteGroup]
    let descriptorIdentityConserved: Bool
    let groupIdentityConserved: Bool
    let admissionIdentityConserved: Bool
    let resolvedMaterialOwnershipConserved: Bool
    init(
        descriptor: SceneRenderDescriptor,
        admissionCatalog: SceneEffectAdmissionCatalog,
        resolvedMaterialSubjects: [SceneEffectExactRuntimeSubject] = []
    ) {
        let admissionsByLayerID = Dictionary(
            grouping: admissionCatalog.stageAdmissions,
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
                $0.activity.participatesInUnifiedRoute ? $0.key : nil
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
                      switch admission.admission {
                      case .admittedGeneric:
                          return subject.family == "resolved-material"
                      case .admittedDedicated:
                          return admission.backendName == subject.family
                      case .admittedFallback:
                          return admission.backendName == subject.family
                              && subject.family == "visual-failure-passthrough"
                      case .admittedPassthrough:
                          return admission.backendName == subject.family
                              && subject.family == "initially-inactive-passthrough"
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
            let activeAdmissions = admissions.filter {
                $0.activity.participatesInUnifiedRoute
            }
            if activeAdmissions.isEmpty {
                records.append(contentsOf: admissions.map(Self.inactiveDisposition))
                groups.append(SceneEffectStaticRouteGroup(
                    layerID: layer.id,
                    kind: .inactive,
                    effectKeys: [],
                    ownerKeys: [],
                    reasonCode: "no-active-effect"
                ))
                continue
            }
            if resolvedLayerIDs.contains(layer.id) {
                let subjectByKey = Dictionary(uniqueKeysWithValues:
                    (subjectsByLayerID[layer.id] ?? []).map { ($0.key, $0) }
                )
                let migrated = admissions.map { admission in
                    admission.activity.participatesInUnifiedRoute
                        ? Self.resolvedDisposition(
                            admission,
                            family: subjectByKey[admission.key]?.family
                        )
                        : Self.inactiveDisposition(admission)
                }
                records.append(contentsOf: migrated)
                groups.append(Self.routeGroup(
                    layerID: layer.id,
                    kind: .resolved,
                    dispositions: migrated,
                    reason: nil
                ))
                continue
            }
            let unsupported = admissions.map { admission in
                admission.activity.participatesInUnifiedRoute
                    ? Self.rejectedDisposition(
                        admission,
                        reason: "r5-no-runtime-owner"
                    )
                    : Self.inactiveDisposition(admission)
            }
            records.append(contentsOf: unsupported)
            groups.append(Self.routeGroup(
                layerID: layer.id,
                kind: .direct,
                dispositions: unsupported,
                reason: "r5-no-runtime-owner"
            ))
        }

        dispositions = records.sorted(by: Self.less)
        routeGroups = groups.sorted { $0.layerID < $1.layerID }
        let dispositionKeys = dispositions.map(\.key)
        descriptorIdentityConserved = dispositionKeys.count
                == admissionCatalog.descriptorEffectStageCount
            && Set(dispositionKeys).count == dispositionKeys.count
            && Set(dispositionKeys) == admissionCatalog.descriptorEffectStageKeys
        groupIdentityConserved = Self.groupsAreConserved(
            dispositions: dispositions,
            groups: routeGroups
        )
        admissionIdentityConserved = Self.admissionMappingsAreConserved(
            admissions: admissionCatalog.stageAdmissions,
            dispositions: dispositions,
            resolvedLayerIDs: resolvedLayerIDs
        )
    }

    var reportLines: [String] {
        [
            "effectStageRuntimeDispositionSchema: 1",
            "effectStageRuntimeRouteScope: unified-effect-graph",
            "effectStageRuntimeDispositionCount: \(dispositions.count)",
            "effectStageRuntimeDispositionKindCounts: \(countMap(Disposition.Kind.allCases, keyPath: \.kind))",
            "effectStageRuntimeDispositionAttributionCounts: \(countMap(Disposition.Attribution.allCases, keyPath: \.attribution))",
            "effectStageRuntimeDispositionRoleCounts: \(countMap(Disposition.RouteRole.allCases, keyPath: \.routeRole))",
            "effectStaticRouteGroupCount: \(routeGroups.count)",
            "effectStaticRouteGroupKindCounts: \(groupCountMap())",
            "effectStageRuntimeDescriptorIdentityConserved: \(descriptorIdentityConserved)",
            "effectStageRuntimeGroupIdentityConserved: \(groupIdentityConserved)",
            "effectStageRuntimeAdmissionIdentityConserved: \(admissionIdentityConserved)",
            "effectStageRuntimeResolvedMaterialOwnershipConserved: \(resolvedMaterialOwnershipConserved)",
        ] + routeGroups.map(\.reportLine) + dispositions.map(\.reportLine)
    }
    /// Projects only exact static owners for runtime evidence.  This is an
    /// admission-derived telemetry view; it is deliberately not an admission
    /// input and excludes omitted records.
    var resolvedMaterialExecutionEvidenceSubjects:
        [SceneEffectExactRuntimeSubject] {
        dispositions.compactMap { disposition in
            guard disposition.attribution == .exactKey,
                  disposition.kind == .dedicated
                    || disposition.kind == .fallback
                    || disposition.kind == .program,
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
    private nonisolated static func resolvedDisposition(
        _ admission: Admission,
        family: String?
    ) -> Disposition {
        switch admission.admission {
        case .admittedGeneric where family == "resolved-material":
            return disposition(
                admission,
                kind: .program,
                family: family,
                role: .owner,
                reason: "resolved-material-capability-owner"
            )
        case .admittedDedicated where family == admission.backendName:
            return disposition(
                admission,
                kind: .dedicated,
                family: family,
                role: .owner
            )
        case .admittedFallback
            where family == "visual-failure-passthrough"
                && family == admission.backendName:
            return disposition(
                admission,
                kind: .fallback,
                family: family,
                role: .owner,
                reason: "effect-local-visual-failure"
            )
        case .admittedPassthrough
            where family == "initially-inactive-passthrough"
                && family == admission.backendName:
            return disposition(
                admission,
                kind: .passthrough,
                family: family,
                role: .member,
                reason: "initially-inactive-property-stage-passthrough"
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
            routeGroupID: admission.activity.participatesInUnifiedRoute
                ? admission.key.layerID
                : nil,
            routeRole: admission.activity.participatesInUnifiedRoute
                ? .member : .none,
            reasonCode: reason
        )
    }
    private nonisolated static func rejectedDisposition(
        _ admission: Admission,
        reason: String
    ) -> Disposition {
        Disposition(
            key: admission.key,
            definitionPath: admission.definitionPath,
            kind: .unsupported,
            attribution: .none,
            family: nil,
            routeGroupID: admission.key.layerID,
            routeRole: .member,
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
