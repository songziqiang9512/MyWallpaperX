nonisolated enum ScenePuppetAnimationPropertyTarget {
    nonisolated static func visibility(
        layerID: Int,
        animationLayerID: Int
    ) -> SceneDynamicTarget {
        .scriptInstanceProperty(
            layerID: layerID,
            path: ["puppetAnimationLayer", String(animationLayerID), "visible"]
        )
    }
}
