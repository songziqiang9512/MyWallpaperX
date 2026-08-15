import Foundation

nonisolated struct SceneEffectStageRuntimeDisposition {
    typealias EffectKey = SceneAuthoredEffectRenderPlan.EffectKey

    enum Kind: String, CaseIterable {
        case inactive
        case dedicated
        case fallback
        case program
        case unsupported
        case unattributed
    }

    enum Attribution: String, CaseIterable {
        case exactKey = "exact-key"
        case none
    }

    enum RouteRole: String, CaseIterable {
        case owner
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

/// Stable exact-effect identity and family projected from static runtime
/// disposition. Render backends consume this value but do not derive it.
nonisolated struct SceneEffectExactRuntimeSubject: Hashable {
    typealias EffectKey = SceneAuthoredEffectRenderPlan.EffectKey

    let key: EffectKey
    let family: String
}

nonisolated struct SceneEffectStaticRouteGroup {
    typealias EffectKey = SceneAuthoredEffectRenderPlan.EffectKey

    enum Kind: String, CaseIterable {
        case inactive
        case direct
        case resolved
    }

    let layerID: Int
    let kind: Kind
    let effectKeys: [EffectKey]
    let ownerKeys: [EffectKey]
    let reasonCode: String?

    var reportLine: String {
        "effectStaticRouteGroup: layer=\(layerID) "
            + "scope=unified-effect-graph kind=\(kind.rawValue) "
            + "effects=\(effectKeys.count) owners=\(ownerKeys.count) "
            + "reason=\(reasonCode ?? "-")"
    }
}

private nonisolated func reportToken(_ value: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(
        CharacterSet(charactersIn: "-._~/")
    )
    return value.addingPercentEncoding(withAllowedCharacters: allowed)
        ?? "<invalid>"
}
