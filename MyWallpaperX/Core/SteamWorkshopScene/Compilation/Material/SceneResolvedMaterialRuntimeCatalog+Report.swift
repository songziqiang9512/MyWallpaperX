import Foundation

extension SceneResolvedMaterialRuntimeCatalog {
    var reportLines: [String] {
        let failures = entries.values.compactMap { entry -> Failure? in
            guard case let .failure(failure) = entry else { return nil }
            return failure
        }
        let accepted = entries.count - failures.count
        var lines = [
            "resolved material catalog: schema=executable-material-v1"
                + " nodes=\(entries.count) templates=\(accepted) failures=\(failures.count)",
            demandSummary("asset", count: assetDemands.count),
            demandSummary("user-property", count: userPropertyDemands.count),
            demandSummary("system", count: systemProviderDemands.count),
        ]
        let grouped = Dictionary(grouping: failures) {
            "\($0.phase.rawValue):\($0.code.rawValue)"
        }
        lines += grouped.keys.sorted().map {
            "resolved material template failure: \($0) count=\(grouped[$0]?.count ?? 0)"
        }
        let demandGroups = Dictionary(grouping: resourceDemandIssues) {
            "\($0.reference.kind):\($0.code.rawValue)"
        }
        lines += demandGroups.keys.sorted().map {
            "resolved material resource demand failure: \($0)"
                + " count=\(demandGroups[$0]?.count ?? 0)"
        }
        return lines
    }

    private func demandSummary(_ kind: String, count: Int) -> String {
        let failures = resourceDemandIssues.filter { $0.reference.kind == kind }.count
        return "resolved material \(kind) textures: demands=\(count)"
            + " demandFailures=\(failures)"
    }
}
