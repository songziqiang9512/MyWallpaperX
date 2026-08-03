import Foundation

nonisolated struct SceneLegacyEffectResourceAvailability {
    let hasIrisMask: Bool
    let hasOpacityMask: Bool
    let hasWaterMask: Bool
    let hasFoliageMask: Bool
    let hasWaterRippleNormal: Bool

    static let none = SceneLegacyEffectResourceAvailability(
        hasIrisMask: false,
        hasOpacityMask: false,
        hasWaterMask: false,
        hasFoliageMask: false,
        hasWaterRippleNormal: false
    )
}

nonisolated struct SceneEffectStageRuntimeDisposition {
    typealias EffectKey = SceneAuthoredEffectRenderPlan.EffectKey

    enum Kind: String, CaseIterable {
        case inactive
        case strictDedicated = "strict-dedicated"
        case strictGeneric = "strict-generic"
        case strictInlineSuffix = "strict-inline-suffix"
        case omittedByStrictChain = "omitted-by-strict-chain"
        case legacyExactInline = "legacy-exact-inline"
        case legacyExactOffscreen = "legacy-exact-offscreen"
        case legacyStructuralMember = "legacy-structural-member"
        case legacyCoalescedInline = "legacy-coalesced-inline"
        case legacyCoalescedOffscreen = "legacy-coalesced-offscreen"
        case legacyShadowed = "legacy-shadowed"
        case routeOnlyMember = "route-only-member"
        case compositeRefused = "composite-refused"
        case unsupported
        case unattributed
    }

    enum Attribution: String, CaseIterable {
        case exactKey = "exact-key"
        case layerAggregate = "layer-aggregate"
        case none
    }

    enum RouteRole: String, CaseIterable {
        case owner
        case aggregateContributor = "aggregate-contributor"
        case member
        case none
    }

    let key: EffectKey
    let definitionPath: String
    let kind: Kind
    let attribution: Attribution
    let family: String?
    let routeGroupID: Int?
    let routeRole: RouteRole
    let reasonCode: String?

    var reportLine: String {
        "effectStageRuntimeDisposition: layer=\(key.layerID) "
            + "effect=\(key.effectIndex) descriptor=\(reportToken(key.descriptorID)) "
            + "kind=\(kind.rawValue) attribution=\(attribution.rawValue) "
            + "family=\(family ?? "-") group=\(routeGroupID.map(String.init) ?? "-") "
            + "role=\(routeRole.rawValue) reason=\(reasonCode ?? "-") "
            + "path=\(reportToken(definitionPath))"
    }
}

nonisolated struct SceneEffectStaticRouteGroup {
    typealias EffectKey = SceneAuthoredEffectRenderPlan.EffectKey

    enum Kind: String, CaseIterable {
        case inactive
        case direct
        case authored
        case legacyOffscreen = "legacy-offscreen"
        case offscreenPassthrough = "offscreen-passthrough"
        case compositeRefused = "composite-refused"
    }

    let layerID: Int
    let kind: Kind
    let effectKeys: [EffectKey]
    let ownerKeys: [EffectKey]
    let aggregateContributorKeys: [EffectKey]
    let reasonCode: String?

    var reportLine: String {
        "effectStaticRouteGroup: layer=\(layerID) "
            + "scope=effect-induced-static kind=\(kind.rawValue) "
            + "effects=\(effectKeys.count) owners=\(ownerKeys.count) "
            + "aggregate=\(aggregateContributorKeys.count) "
            + "reason=\(reasonCode ?? "-")"
    }
}

nonisolated struct SceneLegacyEffectPlanningDecision {
    let runtimePlan: SceneEffectRuntimePlan
    let dispositions: [SceneEffectStageRuntimeDisposition]
    let routeGroup: SceneEffectStaticRouteGroup
}

private nonisolated func reportToken(_ value: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(
        CharacterSet(charactersIn: "-._~/")
    )
    return value.addingPercentEncoding(withAllowedCharacters: allowed)
        ?? "<invalid>"
}
