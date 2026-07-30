extension SceneCursorRippleExecutionPlan.RenderStates {
    static let supported = Self(
        applyForce: supportedState("enabled"),
        simulateForce: supportedState("enabled"),
        combine: supportedState(nil)
    )

    var matchesSupportedTuple: Bool {
        applyForce.matchesFullscreenOverwrite(alphaWriting: .enabled)
            && simulateForce.matchesFullscreenOverwrite(alphaWriting: .enabled)
            && combine.matchesFullscreenOverwrite(alphaWriting: .unspecified)
    }

    private static func supportedState(_ alphaWriting: String?) -> SceneMaterialRenderState {
        SceneMaterialRenderState.compile(
            blending: "normal", depthTest: "disabled", depthWrite: "disabled",
            cullMode: "nocull", alphaWriting: alphaWriting
        )!
    }
}
