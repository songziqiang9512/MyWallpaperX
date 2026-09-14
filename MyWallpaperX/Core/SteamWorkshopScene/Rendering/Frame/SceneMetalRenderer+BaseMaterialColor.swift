extension SceneMetalRenderer {
    func baseMaterialReadyProviderUsesAuthoredLayerColor(
        for layer: SceneRenderDescriptor.Layer,
        dynamicValues: SceneDynamicSnapshot
    ) -> Bool {
        guard layer.contentKind == "solid" else { return true }
        return dynamicValues[
            .layer(layerID: layer.id, field: .color)
        ] != nil
    }
}
