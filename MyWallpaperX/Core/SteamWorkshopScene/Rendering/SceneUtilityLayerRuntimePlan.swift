import Foundation

struct SceneUtilityLayerRuntimePlan {
    enum Disposition: String {
        case capture
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

    var shouldCapture: Bool { disposition == .capture }
}

enum SceneUtilityLayerRuntimePlanner {
    static func plans(
        in descriptor: SceneRenderDescriptor
    ) -> [Int: SceneUtilityLayerRuntimePlan] {
        let visibleLayerIDs = SceneLayerVisibility.visibleLayerIDs(in: descriptor)
        let namedTargetLayerIDs = Set(descriptor.layers.flatMap(\.dependencyLayerIDs))
        return Dictionary(uniqueKeysWithValues: descriptor.layers.compactMap { layer in
            guard let utility = layer.utilityLayer else { return nil }
            let disposition: SceneUtilityLayerRuntimePlan.Disposition
            if !visibleLayerIDs.contains(layer.id) {
                disposition = .skippedHidden
            } else if !layer.childLayerIDs.isEmpty {
                disposition = .unsupportedChildren
            } else if !layer.dependencyLayerIDs.isEmpty {
                disposition = .unsupportedDependencies
            } else if !layer.effects.contains(where: { $0.visible != false }) {
                disposition = .skippedNoEffect
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
                    requiresNamedTarget: namedTargetLayerIDs.contains(layer.id)
                )
            )
        })
    }

    static func reportLines(
        descriptor: SceneRenderDescriptor
    ) -> [String] {
        let plans = plans(in: descriptor)
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
            lines.append(
                "utility layer \(plan.layerID): \(plan.disposition.rawValue) kind=\(plan.kind.rawValue)\(namedTarget)"
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
    var requiresReadableFramebuffer: Bool {
        if SceneUtilityLayerRuntimePlanner.plans(in: self).values.contains(where: { $0.shouldCapture }) {
            return true
        }
        let visibleLayerIDs = SceneLayerVisibility.visibleLayerIDs(in: self)
        return !SceneDependencyRenderPlan(
            descriptor: self,
            visibleLayerIDs: visibleLayerIDs
        ).requiredProviderLayerIDs.isEmpty
    }
}
