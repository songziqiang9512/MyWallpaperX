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
    let triggerLayerID: Int

    var shouldCapture: Bool {
        disposition == .capture
    }
}

enum SceneUtilityLayerRuntimePlanner {
    static func plans(
        in descriptor: SceneRenderDescriptor,
        authoredEffectCatalog: SceneAuthoredEffectExecutionCatalog,
        resolvedMaterialLayerIDs: Set<Int> = []
    ) -> [Int: SceneUtilityLayerRuntimePlan] {
        plans(
            in: descriptor,
            authoredEffectCatalog: authoredEffectCatalog,
            executableUtilityConsumerLayerIDs: executableUtilityConsumerLayerIDs(
                in: descriptor,
                authoredEffectCatalog: authoredEffectCatalog,
                resolvedMaterialLayerIDs: resolvedMaterialLayerIDs
            ),
            resolvedMaterialLayerIDs: resolvedMaterialLayerIDs
        )
    }

    static func plans(
        in descriptor: SceneRenderDescriptor,
        authoredEffectCatalog: SceneAuthoredEffectExecutionCatalog,
        executableUtilityConsumerLayerIDs: Set<Int>,
        resolvedMaterialLayerIDs: Set<Int> = []
    ) -> [Int: SceneUtilityLayerRuntimePlan] {
        let visibleLayerIDs = SceneLayerVisibility.visibleLayerIDs(in: descriptor)
        let suppressedConsumerLayerIDs = authoredEffectCatalog
            .legacyEffectFallbackSuppressedLayerIDs
        let dependencyPlan = SceneDependencyRenderPlan(
            descriptor: descriptor,
            visibleLayerIDs: visibleLayerIDs,
            executableUtilityConsumerLayerIDs: executableUtilityConsumerLayerIDs
        )
        let namedTargetLayerIDs = Set(
            descriptor.layers.flatMap(\.dependencyLayerIDs)
        )
        return Dictionary(uniqueKeysWithValues: descriptor.layers.compactMap { layer in
            guard let utility = layer.utilityLayer else { return nil }
            let disposition: SceneUtilityLayerRuntimePlan.Disposition
            if !visibleLayerIDs.contains(layer.id) {
                disposition = .skippedHidden
            } else if suppressedConsumerLayerIDs.contains(layer.id) {
                disposition = .unsupportedEffects
            } else if !layer.dependencyLayerIDs.isEmpty {
                if utility.kind == .composition,
                   layer.childLayerIDs.isEmpty,
                   executableUtilityConsumerLayerIDs.contains(layer.id),
                   dependencyPlan.bindingsByConsumerLayerID[layer.id] != nil,
                   supportsCompleteAuthoredCapture(
                       layer: layer,
                       catalog: authoredEffectCatalog,
                       resolvedMaterialLayerIDs: resolvedMaterialLayerIDs
                   ) {
                    disposition = .capture
                } else {
                    disposition = .unsupportedDependencies
                }
            } else if !layer.effects.contains(where: { $0.visible != false }) {
                disposition = .skippedNoEffect
            } else if !layer.childLayerIDs.isEmpty {
                disposition = .unsupportedChildren
            } else if supportsCompleteAuthoredCapture(
                layer: layer,
                catalog: authoredEffectCatalog,
                resolvedMaterialLayerIDs: resolvedMaterialLayerIDs
            ) {
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
                    triggerLayerID: layer.id
                )
            )
        })
    }

    static func executableUtilityConsumerLayerIDs(
        in descriptor: SceneRenderDescriptor,
        authoredEffectCatalog: SceneAuthoredEffectExecutionCatalog,
        resolvedMaterialLayerIDs: Set<Int> = []
    ) -> Set<Int> {
        let visibleLayerIDs = SceneLayerVisibility.visibleLayerIDs(in: descriptor)
        return Set(descriptor.layers.compactMap { layer in
            guard visibleLayerIDs.contains(layer.id),
                  layer.utilityLayer?.kind == .composition,
                  layer.contentKind == "composition",
                  layer.childLayerIDs.isEmpty,
                  layer.dependencyLayerIDs.count == 1,
                  supportsCompleteAuthoredCapture(
                      layer: layer,
                      catalog: authoredEffectCatalog,
                      resolvedMaterialLayerIDs: resolvedMaterialLayerIDs
                  ) else {
                return nil
            }
            return layer.id
        })
    }

    static func reportLines(
        descriptor: SceneRenderDescriptor,
        authoredEffectCatalog: SceneAuthoredEffectExecutionCatalog,
        resolvedMaterialLayerIDs: Set<Int> = []
    ) -> [String] {
        let executableUtilityConsumerLayerIDs = executableUtilityConsumerLayerIDs(
            in: descriptor,
            authoredEffectCatalog: authoredEffectCatalog,
            resolvedMaterialLayerIDs: resolvedMaterialLayerIDs
        )
        let plans = plans(
            in: descriptor,
            authoredEffectCatalog: authoredEffectCatalog,
            executableUtilityConsumerLayerIDs: executableUtilityConsumerLayerIDs,
            resolvedMaterialLayerIDs: resolvedMaterialLayerIDs
        )
        let ordered = descriptor.layers.compactMap { plans[$0.id] }
        let dependencyEdges = descriptor.layers.flatMap(\.dependencyLayerIDs).count
        let dependencyPlan = SceneDependencyRenderPlan(
            descriptor: descriptor,
            visibleLayerIDs: SceneLayerVisibility.visibleLayerIDs(in: descriptor),
            executableUtilityConsumerLayerIDs: executableUtilityConsumerLayerIDs
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
            lines.append(
                "utility layer \(plan.layerID): \(plan.disposition.rawValue) "
                    + "kind=\(plan.kind.rawValue)\(trigger)\(namedTarget)"
            )
        }
        return lines
    }

    private static func visibleEffects(
        in layer: SceneRenderDescriptor.Layer
    ) -> [SceneRenderDescriptor.EffectDescriptor] {
        layer.effects.filter { $0.visible != false }
    }

    private static func supportsCompleteAuthoredCapture(
        layer: SceneRenderDescriptor.Layer,
        catalog: SceneAuthoredEffectExecutionCatalog,
        resolvedMaterialLayerIDs: Set<Int>
    ) -> Bool {
        let visible = visibleEffects(in: layer)
        guard !visible.isEmpty else { return false }
        if resolvedMaterialLayerIDs.contains(layer.id) {
            return true
        }
        guard
              let chain = catalog.chainsByLayerID[layer.id],
              chain.executionStages.count == visible.count,
              chain.executionStages.count == chain.renderGraph.effects.count else {
            return false
        }
        return chain.executionStages.allSatisfy(\.supportsUtilityCapture)
    }
}

extension SceneRenderDescriptor {
    func requiresReadableFramebuffer(
        authoredEffectCatalog: SceneAuthoredEffectExecutionCatalog,
        resolvedMaterialLayerIDs: Set<Int> = []
    ) -> Bool {
        if materialPasses.contains(where: { $0.combos["REFRACT"] == 1 }) {
            return true
        }
        let executableUtilityConsumerLayerIDs = SceneUtilityLayerRuntimePlanner
            .executableUtilityConsumerLayerIDs(
                in: self,
                authoredEffectCatalog: authoredEffectCatalog,
                resolvedMaterialLayerIDs: resolvedMaterialLayerIDs
            )
        if SceneUtilityLayerRuntimePlanner.plans(
            in: self,
            authoredEffectCatalog: authoredEffectCatalog,
            executableUtilityConsumerLayerIDs: executableUtilityConsumerLayerIDs,
            resolvedMaterialLayerIDs: resolvedMaterialLayerIDs
        ).values.contains(where: { $0.shouldCapture }) {
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
            executableUtilityConsumerLayerIDs: executableUtilityConsumerLayerIDs
        ).requiredProviderLayerIDs.isEmpty
    }
}
