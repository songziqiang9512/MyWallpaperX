nonisolated extension SceneResolvedMaterialGenericShaderArtifactCache.Resolution {
    static func unavailableOrDeferred(
        code: String,
        requestKey: String,
        permitsBoundedFrontend: Bool,
        routeDecision: SceneGenericShaderRouteDecision
    ) -> Self {
        guard routeDecision.fallbackOwner
                == SceneGenericShaderFallbackOwner.programFirstIncumbent.rawValue
        else {
            return .unavailable(
                code: code,
                requestKey: requestKey,
                permitsBoundedFrontend: permitsBoundedFrontend,
                routeDecision: routeDecision
            )
        }
        return .ownerDeferred(
            code: code,
            requestKey: requestKey,
            routeDecision: routeDecision
        )
    }
}
