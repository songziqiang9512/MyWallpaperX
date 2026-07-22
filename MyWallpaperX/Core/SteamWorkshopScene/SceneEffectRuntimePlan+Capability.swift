extension SceneEffectRuntimePlan {
    var hasImplementedVisualWork: Bool {
        !skipsUnsupportedComposite && (
            !inputs.flags.isEmpty
                || gaussianBlur != nil
                || bloom != nil
                || gradientColor != nil
                || waterRippleNormal != nil
                || perspectiveOpacity != nil
        )
    }
}
