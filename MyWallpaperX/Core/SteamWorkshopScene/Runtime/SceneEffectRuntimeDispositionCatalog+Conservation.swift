import Foundation

extension SceneEffectRuntimeDispositionCatalog {
    nonisolated static func groupsAreConserved(
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

    nonisolated static func strictMappingsAreConserved(
        admissions: [Admission],
        dispositions: [Disposition],
        strictLayerIDs: Set<Int>,
        resolvedLayerIDs: Set<Int>
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
            if resolvedLayerIDs.contains(admission.key.layerID) {
                guard disposition.attribution == .exactKey,
                      disposition.routeRole == .owner else { return false }
                switch admission.strictAdmission {
                case .admittedGeneric:
                    return disposition.kind == .strictGeneric
                        && disposition.family == "resolved-material"
                        && disposition.reasonCode
                            == "resolved-material-capability-owner"
                case .admittedDedicated:
                    return disposition.kind == .strictDedicated
                        && disposition.family == admission.backendName
                        && disposition.reasonCode == admission.reasonCode
                default:
                    return false
                }
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
}
