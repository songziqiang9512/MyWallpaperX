import Foundation

extension SceneEffectRuntimePlanner {
    static func legacyPlanningDecision(
        for layer: SceneRenderDescriptor.Layer,
        resources: SceneLegacyEffectResourceAvailability,
        blocksLegacyGaussianBlur: Bool = false
    ) -> SceneLegacyEffectPlanningDecision {
        let runtimePlan = plan(
            for: layer,
            hasIrisMask: resources.hasIrisMask,
            hasOpacityMask: resources.hasOpacityMask && !resources.hasIrisMask,
            hasWaterMask: resources.hasWaterMask,
            hasFoliageMask: resources.hasFoliageMask,
            hasWaterRippleNormal: resources.hasWaterRippleNormal,
            blocksLegacyGaussianBlur: blocksLegacyGaussianBlur
        )
        return SceneLegacyEffectDecisionBuilder.make(
            layer: layer,
            resources: resources,
            runtimePlan: runtimePlan,
            blocksLegacyGaussianBlur: blocksLegacyGaussianBlur
        )
    }
}

enum SceneLegacyEffectDecisionBuilder {
    typealias Disposition = SceneEffectStageRuntimeDisposition
    typealias EffectKey = SceneAuthoredEffectRenderPlan.EffectKey

    struct Draft {
        let kind: Disposition.Kind
        let attribution: Disposition.Attribution
        let family: String
        let role: Disposition.RouteRole
        let reason: String?
    }

    private struct OffscreenSelection {
        let owners: [Int: String]
        let aggregates: [Int: (family: String, reason: String)]
        let members: [Int: (family: String, reason: String)]
    }

    static func make(
        layer: SceneRenderDescriptor.Layer,
        resources: SceneLegacyEffectResourceAvailability,
        runtimePlan: SceneEffectRuntimePlan,
        blocksLegacyGaussianBlur: Bool
    ) -> SceneLegacyEffectPlanningDecision {
        let visible = layer.effects.enumerated().filter {
            $0.element.visible != false
        }
        if runtimePlan.skipsUnsupportedComposite {
            let dispositions = visible.map { entry in
                disposition(
                    layer: layer,
                    entry: entry,
                    kind: .compositeRefused,
                    attribution: .layerAggregate,
                    family: "unsupported-composite",
                    role: .member,
                    reason: "waterflow-waterripple-perspective-opacity"
                )
            }
            return decision(
                runtimePlan: runtimePlan,
                dispositions: dispositions,
                layerID: layer.id,
                groupKind: .compositeRefused,
                reason: "legacy-composite-refused"
            )
        }

        var drafts: [Int: Draft] = [:]
        assignInline(
            layer: layer,
            resources: resources,
            runtimePlan: runtimePlan,
            drafts: &drafts
        )
        let offscreen = offscreenSelection(
            layer: layer,
            resources: resources,
            runtimePlan: runtimePlan,
            blocksLegacyGaussianBlur: blocksLegacyGaussianBlur
        )
        for (index, family) in offscreen.owners where drafts[index] == nil {
            drafts[index] = Draft(
                kind: .legacyExactOffscreen,
                attribution: .exactKey,
                family: family,
                role: .owner,
                reason: nil
            )
        }
        for (index, aggregate) in offscreen.aggregates where drafts[index] == nil {
            drafts[index] = Draft(
                kind: .legacyCoalescedOffscreen,
                attribution: .layerAggregate,
                family: aggregate.family,
                role: .aggregateContributor,
                reason: aggregate.reason
            )
        }
        for (index, member) in offscreen.members where drafts[index] == nil {
            drafts[index] = Draft(
                kind: .legacyStructuralMember,
                attribution: .exactKey,
                family: member.family,
                role: .member,
                reason: member.reason
            )
        }

        let offscreenCandidates = Set(visible.compactMap { entry in
            SceneEffectRuntimePlanner.shouldRouteEffectOffscreen(
                path: entry.element.file.localizedLowercase,
                passCount: entry.element.passes.count
            ) ? entry.offset : nil
        })
        let groupKind: SceneEffectStaticRouteGroup.Kind
        if runtimePlan.offscreenPassCount > 0 {
            groupKind = offscreen.owners.isEmpty && offscreen.aggregates.isEmpty
                ? .offscreenPassthrough
                : .legacyOffscreen
        } else {
            groupKind = .direct
        }
        for index in offscreenCandidates where drafts[index] == nil {
            let effect = layer.effects[index]
            drafts[index] = Draft(
                kind: groupKind == .offscreenPassthrough
                    ? .routeOnlyMember
                    : .legacyShadowed,
                attribution: .exactKey,
                family: offscreenFamily(effect.file),
                role: .member,
                reason: groupKind == .offscreenPassthrough
                    ? "capture-or-neutral-copy-only"
                    : "shadowed-by-legacy-precedence"
            )
        }
        for entry in visible where drafts[entry.offset] == nil {
            drafts[entry.offset] = Draft(
                kind: .unsupported,
                attribution: .none,
                family: effectFamily(entry.element.file),
                role: .member,
                reason: "no-legacy-visual-route"
            )
        }
        let dispositions = visible.compactMap { entry -> Disposition? in
            guard let draft = drafts[entry.offset] else { return nil }
            return disposition(
                layer: layer,
                entry: entry,
                kind: draft.kind,
                attribution: draft.attribution,
                family: draft.family,
                role: draft.role,
                reason: draft.reason
            )
        }
        return decision(
            runtimePlan: runtimePlan,
            dispositions: dispositions,
            layerID: layer.id,
            groupKind: groupKind,
            reason: groupKind == .offscreenPassthrough
                ? "no-implemented-offscreen-stage"
                : nil
        )
    }

    private static func offscreenSelection(
        layer: SceneRenderDescriptor.Layer,
        resources: SceneLegacyEffectResourceAvailability,
        runtimePlan: SceneEffectRuntimePlan,
        blocksLegacyGaussianBlur: Bool
    ) -> OffscreenSelection {
        if runtimePlan.gradientColor != nil,
           let selection = SceneGradientColorRuntimePlanner.selection(for: layer),
           let owner = selection.effectIndices.first {
            let members = Dictionary(uniqueKeysWithValues:
                selection.effectIndices.dropFirst().map {
                    ($0, ("gradient-color", "shape-only-legacy-member"))
                }
            )
            return OffscreenSelection(
                owners: [owner: "gradient-color"],
                aggregates: [:],
                members: members
            )
        }
        var owners: [Int: String] = [:]
        var aggregates: [Int: (family: String, reason: String)] = [:]
        if runtimePlan.waterRippleNormal != nil,
           let ripple = SceneWaterRippleRuntimePlanner.selection(
               for: layer,
               hasNormalTexture: resources.hasWaterRippleNormal
           ) {
            let resourceCandidates = normalResourceCandidateIndices(in: layer)
            let contributors = Set(resourceCandidates + [ripple.effectIndex])
            if contributors.count == 1 {
                owners[ripple.effectIndex] = "water-ripple-normal"
            } else {
                for index in contributors {
                    aggregates[index] = (
                        "water-ripple-normal",
                        "first-parameters-first-resolvable-normal"
                    )
                }
            }
        }
        if runtimePlan.perspectiveOpacity != nil {
            let visible = layer.effects.enumerated().filter {
                $0.element.visible != false
            }
            if let perspective = visible.first(where: {
                $0.element.file.localizedLowercase.contains("perspective")
            }), let opacity = visible.first(where: {
                $0.element.file.localizedLowercase.contains("opacity")
            }) {
                let contributors = Set(
                    [perspective.offset, opacity.offset]
                        + opacityResourceCandidateIndices(in: layer)
                )
                for index in contributors {
                    aggregates[index] = (
                        "perspective-opacity",
                        "combined-stage-first-resolvable-opacity-mask"
                    )
                }
            }
        }
        if !owners.isEmpty || !aggregates.isEmpty {
            return OffscreenSelection(
                owners: owners,
                aggregates: aggregates,
                members: [:]
            )
        }
        if runtimePlan.bloom != nil,
           let bloom = layer.effects.enumerated().first(where: {
               $0.element.visible != false
                   && $0.element.file.localizedLowercase.contains("/bloom/")
                   && !$0.element.passes.isEmpty
           }) {
            return OffscreenSelection(
                owners: [bloom.offset: "bloom"],
                aggregates: [:],
                members: [:]
            )
        }
        if runtimePlan.gaussianBlur != nil,
           !blocksLegacyGaussianBlur,
           let blur = SceneGaussianBlurRuntimePlanner.selection(for: layer) {
            return OffscreenSelection(
                owners: [blur.effectIndex: blur.plan.isPrecise
                    ? "gaussian-blur-precise"
                    : "gaussian-blur"],
                aggregates: [:],
                members: [:]
            )
        }
        return OffscreenSelection(owners: [:], aggregates: [:], members: [:])
    }

    private static func normalResourceCandidateIndices(
        in layer: SceneRenderDescriptor.Layer
    ) -> [Int] {
        layer.effects.enumerated().compactMap { entry in
            guard entry.element.visible != false,
                  entry.element.file.localizedLowercase.contains("waterripple"),
                  entry.element.passes.contains(where: { pass in
                      pass.textureSlots.indices.contains(2)
                          && pass.textureSlots[2] != nil
                  }) else {
                return nil
            }
            return entry.offset
        }
    }

    private static func opacityResourceCandidateIndices(
        in layer: SceneRenderDescriptor.Layer
    ) -> [Int] {
        layer.effects.enumerated().compactMap { entry in
            guard entry.element.visible != false,
                  entry.element.file.localizedLowercase.contains("opacity"),
                  entry.element.passes.contains(where: {
                      !$0.texturePaths.isEmpty
                  }) else {
                return nil
            }
            return entry.offset
        }
    }

    private static func disposition(
        layer: SceneRenderDescriptor.Layer,
        entry: (offset: Int, element: SceneRenderDescriptor.EffectDescriptor),
        kind: Disposition.Kind,
        attribution: Disposition.Attribution,
        family: String,
        role: Disposition.RouteRole,
        reason: String?
    ) -> Disposition {
        Disposition(
            key: key(layerID: layer.id, entry: entry),
            definitionPath: entry.element.file,
            kind: kind,
            attribution: attribution,
            family: family,
            routeGroupID: layer.id,
            routeRole: role,
            reasonCode: reason
        )
    }

    private static func decision(
        runtimePlan: SceneEffectRuntimePlan,
        dispositions: [Disposition],
        layerID: Int,
        groupKind: SceneEffectStaticRouteGroup.Kind,
        reason: String?
    ) -> SceneLegacyEffectPlanningDecision {
        let sorted = dispositions.sorted { $0.key.effectIndex < $1.key.effectIndex }
        return SceneLegacyEffectPlanningDecision(
            runtimePlan: runtimePlan,
            dispositions: sorted,
            routeGroup: SceneEffectStaticRouteGroup(
                layerID: layerID,
                kind: groupKind,
                effectKeys: sorted.map(\.key),
                ownerKeys: sorted.filter { $0.routeRole == .owner }.map(\.key),
                aggregateContributorKeys: sorted.filter {
                    $0.routeRole == .aggregateContributor
                }.map(\.key),
                reasonCode: reason
            )
        )
    }

    private static func key(
        layerID: Int,
        entry: (offset: Int, element: SceneRenderDescriptor.EffectDescriptor)
    ) -> EffectKey {
        EffectKey(
            layerID: layerID,
            effectIndex: entry.offset,
            descriptorID: entry.element.id
        )
    }

    private static func offscreenFamily(_ path: String) -> String {
        let lower = path.localizedLowercase
        if lower.contains("motionblur") { return "motion-blur" }
        if lower.contains("blurprecise") { return "gaussian-blur-precise" }
        if lower.contains("/blur/") { return "gaussian-blur" }
        if lower.contains("bloom") { return "bloom" }
        if lower.contains("godrays") { return "godrays" }
        if lower.contains("glitter") { return "glitter" }
        if lower.contains("opacity") { return "opacity" }
        if lower.contains("shadow") { return "shadow" }
        if lower.contains("gradient_color") { return "gradient-color" }
        return "declared-multipass"
    }

    private static func effectFamily(_ path: String) -> String {
        let components = path.localizedLowercase.split(separator: "/")
        return components.dropLast().last.map(String.init) ?? "unknown"
    }
}
