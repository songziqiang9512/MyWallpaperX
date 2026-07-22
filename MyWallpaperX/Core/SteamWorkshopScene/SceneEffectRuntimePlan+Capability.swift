extension SceneEffectRuntimePlan {
    var hasImplementedVisualWork: Bool {
        !skipsUnsupportedComposite && (
            !inputs.flags.isEmpty
                || gaussianBlur != nil
                || bloom != nil
                || waterRippleNormal != nil
                || perspectiveOpacity != nil
        )
    }
}
