import Foundation

struct SceneUtilityLayerRuntimePlan {
    enum Disposition: String {
        case capture
        case captureAfterChildrenXRayPrefix
        case skippedHidden
        case skippedNoEffect
        case unsupportedDependencies
        case unsupportedChildren
        case unsupportedEffects
        case partialEffects
    }

    let layerID: Int
    let kind: SceneUtilityLayer.Kind
    let disposition: Disposition
    let requiresNamedTarget: Bool
    let triggerLayerID: Int
    let omittedEffectCount: Int

    var shouldCapture: Bool {
        disposition == .capture || disposition == .captureAfterChildrenXRayPrefix
    }
}

enum SceneUtilityLayerRuntimePlanner {
    static func plans(
        in descriptor: SceneRenderDescriptor,
        authoredEffectCatalog: SceneAuthoredEffectExecutionCatalog
    ) -> [Int: SceneUtilityLayerRuntimePlan] {
        let visibleLayerIDs = SceneLayerVisibility.visibleLayerIDs(in: descriptor)
        let namedTargetLayerIDs = Set(descriptor.layers.flatMap(\.dependencyLayerIDs))
        return Dictionary(uniqueKeysWithValues: descriptor.layers.compactMap { layer in
            guard let utility = layer.utilityLayer else { return nil }
            let disposition: SceneUtilityLayerRuntimePlan.Disposition
            var triggerLayerID = layer.id
            var omittedEffectCount = 0
            if !visibleLayerIDs.contains(layer.id) {
                disposition = .skippedHidden
            } else if !layer.dependencyLayerIDs.isEmpty {
                disposition = .unsupportedDependencies
            } else if !layer.effects.contains(where: { $0.visible != false }) {
                disposition = .skippedNoEffect
            } else if !layer.childLayerIDs.isEmpty {
                let omitted = authoredEffectCatalog
                    .xRayPrefixOmittedEffectPathsByLayerID[layer.id]
                if let omitted,
                   let trigger = SceneUtilitySubtreeTriggerResolver.triggerLayerID(
                       rootLayerID: layer.id,
                       descriptor: descriptor
                   ) {
                    disposition = .captureAfterChildrenXRayPrefix
                    triggerLayerID = trigger
                    omittedEffectCount = omitted.count
                } else {
                    disposition = .unsupportedChildren
                }
            } else if visibleEffects(in: layer).allSatisfy(SceneEffectRuntimeSupport.supportsUtilityCapture)
                && implementedEffectPlan(for: layer).hasImplementedVisualWork {
                disposition = .capture
            } else if visibleEffects(in: layer).contains(where: SceneEffectRuntimeSupport.supportsUtilityCapture) {
                disposition = .partialEffects
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
                    triggerLayerID: triggerLayerID,
                    omittedEffectCount: omittedEffectCount
                )
            )
        })
    }

    static func reportLines(
        descriptor: SceneRenderDescriptor,
        authoredEffectCatalog: SceneAuthoredEffectExecutionCatalog
    ) -> [String] {
        let plans = plans(
            in: descriptor,
            authoredEffectCatalog: authoredEffectCatalog
        )
        let ordered = descriptor.layers.compactMap { plans[$0.id] }
        let dependencyEdges = descriptor.layers.flatMap(\.dependencyLayerIDs).count
        let dependencyPlan = SceneDependencyRenderPlan(
            descriptor: descriptor,
            visibleLayerIDs: SceneLayerVisibility.visibleLayerIDs(in: descriptor)
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
            "utilityNamedTargetGapCount: \(namedTargetGaps.count)"
        ]
        for plan in ordered {
            let namedTarget: String
            if namedTargetProviderIDs.contains(plan.layerID) {
                namedTarget = "; named target planned"
            } else if plan.requiresNamedTarget {
                namedTarget = "; named target unsupported"
            } else {
                namedTarget = ""
            }
            let trigger = plan.triggerLayerID == plan.layerID
                ? ""
                : "; trigger after \(plan.triggerLayerID)"
            let omitted = plan.omittedEffectCount == 0
                ? ""
                : "; omitted effects \(plan.omittedEffectCount)"
            lines.append(
                "utility layer \(plan.layerID): \(plan.disposition.rawValue) "
                    + "kind=\(plan.kind.rawValue)\(trigger)\(omitted)\(namedTarget)"
            )
        }
        return lines
    }

    private static func implementedEffectPlan(
        for layer: SceneRenderDescriptor.Layer
    ) -> SceneEffectRuntimePlan {
        SceneEffectRuntimePlanner.plan(
            for: layer,
            hasIrisMask: false,
            hasOpacityMask: false,
            hasWaterMask: false,
            hasFoliageMask: false,
            hasWaterRippleNormal: false
        )
    }

    private static func visibleEffects(
        in layer: SceneRenderDescriptor.Layer
    ) -> [SceneRenderDescriptor.EffectDescriptor] {
        layer.effects.filter { $0.visible != false }
    }
}

extension SceneRenderDescriptor {
    func requiresReadableFramebuffer(
        authoredEffectCatalog: SceneAuthoredEffectExecutionCatalog
    ) -> Bool {
        if SceneUtilityLayerRuntimePlanner.plans(
            in: self,
            authoredEffectCatalog: authoredEffectCatalog
        ).values.contains(where: { $0.shouldCapture }) {
            return true
        }
        let visibleLayerIDs = SceneLayerVisibility.visibleLayerIDs(in: self)
        return !SceneDependencyRenderPlan(
            descriptor: self,
            visibleLayerIDs: visibleLayerIDs
        ).requiredProviderLayerIDs.isEmpty
    }
}

enum SceneUtilitySubtreeTriggerResolver {
    static func triggerLayerID(
        rootLayerID: Int,
        descriptor: SceneRenderDescriptor
    ) -> Int? {
        let grouped = Dictionary(grouping: descriptor.layers, by: \.id)
        guard grouped.values.allSatisfy({ $0.count == 1 }) else { return nil }
        let layersByID = grouped.compactMapValues(\.first)
        guard let root = layersByID[rootLayerID],
              root.parentID == nil,
              descriptor.renderOrderLayerIDs.first == rootLayerID else {
            return nil
        }

        var descendants = Set<Int>()
        var pending = root.childLayerIDs.map { (layerID: $0, parentID: rootLayerID) }
        while let candidate = pending.popLast() {
            guard descendants.insert(candidate.layerID).inserted,
                  let layer = layersByID[candidate.layerID],
                  layer.parentID == candidate.parentID,
                  layer.dependencyLayerIDs.isEmpty,
                  layer.utilityLayer == nil
                    || !layer.effects.contains(where: { $0.visible != false }) else {
                return nil
            }
            pending.append(contentsOf: layer.childLayerIDs.map {
                (layerID: $0, parentID: candidate.layerID)
            })
        }
        guard !descendants.isEmpty else { return nil }

        let orderedSubtree = Array(
            descriptor.renderOrderLayerIDs.prefix(descendants.count + 1)
        )
        guard orderedSubtree.first == rootLayerID,
              Set(orderedSubtree.dropFirst()) == descendants else {
            return nil
        }
        return orderedSubtree.last
    }
}
