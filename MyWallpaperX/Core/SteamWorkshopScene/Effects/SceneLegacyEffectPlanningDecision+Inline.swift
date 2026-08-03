import Foundation

extension SceneLegacyEffectDecisionBuilder {
    static func assignInline(
        layer: SceneRenderDescriptor.Layer,
        resources: SceneLegacyEffectResourceAvailability,
        runtimePlan: SceneEffectRuntimePlan,
        drafts: inout [Int: Draft]
    ) {
        if runtimePlan.inputs.flags.contains(.foliagesway),
           let selection = SceneFoliageSwayRuntimePlanner.selection(
               for: layer,
               hasMask: resources.hasFoliageMask
           ) {
            assignExactInline(
                selection.effectIndex,
                family: "foliage-sway",
                drafts: &drafts
            )
        }
        if runtimePlan.inputs.flags.contains(.waterwaves) {
            assignLegacyWaterContributors(
                layer: layer,
                hasWaterMask: resources.hasWaterMask,
                drafts: &drafts
            )
        }
        if runtimePlan.inputs.flags.contains(.chromaticaberration) {
            assignInlineCandidates(
                layer.effects.enumerated().filter {
                    $0.element.visible != false
                        && SceneEffectRuntimeSupport.isChromaticAberration(
                            $0.element.file
                        )
                },
                family: "chromatic-aberration",
                drafts: &drafts
            )
        }
        if runtimePlan.inputs.flags.contains(.irisMask) {
            assignHybridInlineCandidates(
                layer: layer,
                pathFragment: "iris",
                family: "iris",
                drafts: &drafts
            )
        }
        if runtimePlan.inputs.flags.contains(.opacityMask) {
            assignHybridInlineCandidates(
                layer: layer,
                pathFragment: "opacity",
                family: "opacity-mask",
                drafts: &drafts
            )
        }
    }

    private static func assignLegacyWaterContributors(
        layer: SceneRenderDescriptor.Layer,
        hasWaterMask: Bool,
        drafts: inout [Int: Draft]
    ) {
        let visible = layer.effects.enumerated().filter {
            $0.element.visible != false
        }
        let singleWaterWavesIndex = visible.count == 1
            && visible[0].element.file.localizedLowercase.contains("waterwaves")
            ? visible[0].offset
            : nil
        let contributors = visible.filter { entry in
            let path = entry.element.file.localizedLowercase
            guard path.contains("waterwaves") || path.contains("waterripple") else {
                return false
            }
            let writesParameters = entry.element.passes.first != nil
            let triggersRipple = path.contains("waterripple")
                && (!SceneEffectMaskSemantics.declaresMask(in: entry.element)
                    || hasWaterMask)
            return writesParameters || triggersRipple
                || entry.offset == singleWaterWavesIndex
        }
        if contributors.count == 1, let contributor = contributors.first {
            let family = contributor.element.file.localizedLowercase
                .contains("waterwaves") ? "water-waves" : "water-ripple"
            assignExactInline(
                contributor.offset,
                family: family,
                drafts: &drafts
            )
            return
        }
        for contributor in contributors where drafts[contributor.offset] == nil {
            drafts[contributor.offset] = Draft(
                kind: .legacyCoalescedInline,
                attribution: .layerAggregate,
                family: "water-waves-ripple",
                role: .aggregateContributor,
                reason: "layer-flag-first-resource-last-parameters"
            )
        }
    }

    private static func assignHybridInlineCandidates(
        layer: SceneRenderDescriptor.Layer,
        pathFragment: String,
        family: String,
        drafts: inout [Int: Draft]
    ) {
        assignInlineCandidates(
            layer.effects.enumerated().filter {
                $0.element.visible != false
                    && $0.element.file.localizedLowercase.contains(pathFragment)
                    && !$0.element.passes.isEmpty
            },
            family: family,
            coalescedReason: "layer-resource-first-parameters-last",
            drafts: &drafts
        )
    }

    private static func assignInlineCandidates(
        _ candidates: [(offset: Int, element: SceneRenderDescriptor.EffectDescriptor)],
        family: String,
        coalescedReason: String = "multiple-instances-coalesced-to-one-flag",
        drafts: inout [Int: Draft]
    ) {
        if candidates.count == 1, let candidate = candidates.first {
            assignExactInline(
                candidate.offset,
                family: family,
                drafts: &drafts
            )
            return
        }
        for candidate in candidates where drafts[candidate.offset] == nil {
            drafts[candidate.offset] = Draft(
                kind: .legacyCoalescedInline,
                attribution: .layerAggregate,
                family: family,
                role: .aggregateContributor,
                reason: coalescedReason
            )
        }
    }

    private static func assignExactInline(
        _ index: Int,
        family: String,
        drafts: inout [Int: Draft]
    ) {
        guard drafts[index] == nil else { return }
        drafts[index] = Draft(
            kind: .legacyExactInline,
            attribution: .exactKey,
            family: family,
            role: .owner,
            reason: nil
        )
    }
}
