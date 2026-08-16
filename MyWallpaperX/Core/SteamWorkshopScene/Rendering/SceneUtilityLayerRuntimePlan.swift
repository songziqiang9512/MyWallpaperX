import Foundation

struct SceneUtilityLayerRuntimePlan {
    enum Disposition: String {
        case capture
        case skippedHidden
        case skippedNoEffect
        case unsupportedDependencies
        case unsupportedChildren
        case unsupportedEffects
    }

    let layerID: Int
    let kind: SceneUtilityLayer.Kind
    let disposition: Disposition
    let requiresNamedTarget: Bool
    let triggerLayerID: Int

    var shouldCapture: Bool { disposition == .capture }
}

enum SceneUtilityLayerRuntimePlanner {
    static func plans(
        in descriptor: SceneRenderDescriptor,
        resolvedMaterialLayerIDs: Set<Int> = []
    ) -> [Int: SceneUtilityLayerRuntimePlan] {
        plans(
            in: descriptor,
            executableUtilityConsumerLayerIDs: executableUtilityConsumerLayerIDs(
                in: descriptor,
                resolvedMaterialLayerIDs: resolvedMaterialLayerIDs
            ),
            resolvedMaterialLayerIDs: resolvedMaterialLayerIDs
        )
    }

    static func plans(
        in descriptor: SceneRenderDescriptor,
        executableUtilityConsumerLayerIDs: Set<Int>,
        resolvedMaterialLayerIDs: Set<Int> = []
    ) -> [Int: SceneUtilityLayerRuntimePlan] {
        let visibleLayerIDs = SceneLayerVisibility.visibleLayerIDs(in: descriptor)
        let dependencyPlan = SceneDependencyRenderPlan(
            descriptor: descriptor,
            visibleLayerIDs: visibleLayerIDs,
            executableUtilityConsumerLayerIDs: executableUtilityConsumerLayerIDs
        )
        let namedTargetLayerIDs = Set(descriptor.layers.flatMap(\.dependencyLayerIDs))
        return Dictionary(uniqueKeysWithValues: descriptor.layers.compactMap { layer in
            guard let utility = layer.utilityLayer else { return nil }
            let hasVisibleEffects = layer.effects.contains { $0.visible != false }
            let disposition: SceneUtilityLayerRuntimePlan.Disposition
            if !visibleLayerIDs.contains(layer.id) {
                disposition = .skippedHidden
            } else if !layer.dependencyLayerIDs.isEmpty {
                if utility.kind == .composition,
                   layer.childLayerIDs.isEmpty,
                   executableUtilityConsumerLayerIDs.contains(layer.id),
                   dependencyPlan.bindingsByConsumerLayerID[layer.id] != nil,
                   resolvedMaterialLayerIDs.contains(layer.id) {
                    disposition = .capture
                } else {
                    disposition = .unsupportedDependencies
                }
            } else if !hasVisibleEffects {
                disposition = .skippedNoEffect
            } else if !layer.childLayerIDs.isEmpty {
                disposition = .unsupportedChildren
            } else if resolvedMaterialLayerIDs.contains(layer.id) {
                disposition = .capture
            } else {
                disposition = .unsupportedEffects
            }
            return (
                layer.id,
                SceneUtilityLayerRuntimePlan(
                    layerID: layer.id,
                    kind: utility.kind,
                    disposition: disposition,
                    requiresNamedTarget: namedTargetLayerIDs.contains(layer.id),
                    triggerLayerID: layer.id
                )
            )
        })
    }

    static func executableUtilityConsumerLayerIDs(
        in descriptor: SceneRenderDescriptor,
        resolvedMaterialLayerIDs: Set<Int> = []
    ) -> Set<Int> {
        let visibleLayerIDs = SceneLayerVisibility.visibleLayerIDs(in: descriptor)
        return Set(descriptor.layers.compactMap { layer in
            guard visibleLayerIDs.contains(layer.id),
                  resolvedMaterialLayerIDs.contains(layer.id),
                  layer.utilityLayer?.kind == .composition,
                  layer.contentKind == "composition",
                  layer.childLayerIDs.isEmpty,
                  layer.dependencyLayerIDs.count == 1,
                  layer.effects.contains(where: { $0.visible != false }) else {
                return nil
            }
            return layer.id
        })
    }

    static func reportLines(
        descriptor: SceneRenderDescriptor,
        resolvedMaterialLayerIDs: Set<Int> = []
    ) -> [String] {
        let executableConsumers = executableUtilityConsumerLayerIDs(
            in: descriptor,
            resolvedMaterialLayerIDs: resolvedMaterialLayerIDs
        )
        let plans = plans(
            in: descriptor,
            executableUtilityConsumerLayerIDs: executableConsumers,
            resolvedMaterialLayerIDs: resolvedMaterialLayerIDs
        )
        let ordered = descriptor.layers.compactMap { plans[$0.id] }
        let dependencyEdges = descriptor.layers.flatMap(\.dependencyLayerIDs).count
        let dependencyPlan = SceneDependencyRenderPlan(
            descriptor: descriptor,
            visibleLayerIDs: SceneLayerVisibility.visibleLayerIDs(in: descriptor),
            executableUtilityConsumerLayerIDs: executableConsumers
        )
        let namedTargetProviderIDs = dependencyPlan.requiredProviderLayerIDs
        let namedTargetGaps = ordered.filter {
            $0.requiresNamedTarget && !namedTargetProviderIDs.contains($0.layerID)
        }
        var lines = [
            "utilityLayerCount: \(ordered.count)",
            "utilityCapturePlannedCount: \(ordered.filter(\.shouldCapture).count)",
            "utilityDependencyEdgeCount: \(dependencyEdges)",
            "utilityNamedConsumerCount: \(dependencyPlan.namedReferenceConsumerLayerIDs.count)",
            "utilityNamedTargetPlannedCount: \(namedTargetProviderIDs.count)",
            "utilityNamedBindingPlannedCount: \(dependencyPlan.bindingsByConsumerLayerID.count)",
            "utilityNamedTargetGapCount: \(namedTargetGaps.count)",
            "utilityDependencyIssueCount: \(dependencyPlan.issues.count)",
        ]
        for issue in dependencyPlan.issues {
            let provider = issue.providerLayerID.map(String.init) ?? "-"
            lines.append(
                "utilityDependencyIssue: kind=\(issue.kind.rawValue) "
                    + "layer=\(issue.layerID) provider=\(provider)"
            )
        }
        for plan in ordered {
            let namedTarget: String
            if namedTargetProviderIDs.contains(plan.layerID) {
                namedTarget = "; named target planned"
            } else if plan.requiresNamedTarget {
                namedTarget = "; named target unsupported"
            } else {
                namedTarget = ""
            }
            lines.append(
                "utility layer \(plan.layerID): \(plan.disposition.rawValue) "
                    + "kind=\(plan.kind.rawValue)\(namedTarget)"
            )
        }
        return lines
    }
}

extension SceneRenderDescriptor {
    func requiresReadableFramebuffer(
        resolvedMaterialLayerIDs: Set<Int> = []
    ) -> Bool {
        if materialPasses.contains(where: { $0.combos["REFRACT"] == 1 }) {
            return true
        }
        let executableConsumers = SceneUtilityLayerRuntimePlanner
            .executableUtilityConsumerLayerIDs(
                in: self,
                resolvedMaterialLayerIDs: resolvedMaterialLayerIDs
            )
        if SceneUtilityLayerRuntimePlanner.plans(
            in: self,
            executableUtilityConsumerLayerIDs: executableConsumers,
            resolvedMaterialLayerIDs: resolvedMaterialLayerIDs
        ).values.contains(where: \.shouldCapture) {
            return true
        }
        let visibleLayerIDs = SceneLayerVisibility.visibleLayerIDs(in: self)
        if layers.contains(where: { layer in
            visibleLayerIDs.contains(layer.id)
                && ["image", "solid", "text"].contains(layer.contentKind)
                && (1 ... SceneBlendModeShaderSource.maximumMode).contains(
                    layer.colorBlendMode ?? 0
                )
        }) {
            return true
        }
        return !SceneDependencyRenderPlan(
            descriptor: self,
            visibleLayerIDs: visibleLayerIDs,
            executableUtilityConsumerLayerIDs: executableConsumers
        ).requiredProviderLayerIDs.isEmpty
    }
}
