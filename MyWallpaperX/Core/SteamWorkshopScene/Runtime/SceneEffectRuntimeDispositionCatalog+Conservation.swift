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
        } && dispositions.allSatisfy {
            $0.routeGroupID == nil || byID[$0.routeGroupID!] != nil
        }
    }

    nonisolated static func admissionMappingsAreConserved(
        admissions: [Admission],
        dispositions: [Disposition],
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
                switch admission.admission {
                case .admittedGeneric:
                    return disposition.kind == .program
                        && disposition.family == "resolved-material"
                        && disposition.reasonCode
                            == "resolved-material-capability-owner"
                case .admittedDedicated:
                    return disposition.kind == .dedicated
                        && disposition.family == admission.backendName
                        && disposition.reasonCode == admission.reasonCode
                case .admittedFallback:
                    return disposition.kind == .fallback
                        && disposition.family == "visual-failure-passthrough"
                        && disposition.family == admission.backendName
                        && disposition.reasonCode == "effect-local-visual-failure"
                default:
                    return false
                }
            }
            guard admission.admission == .notAdmitted else { return false }
            switch disposition.kind {
            case .inactive, .dedicated, .fallback, .program:
                return false
            default:
                return true
            }
        }
    }
}
