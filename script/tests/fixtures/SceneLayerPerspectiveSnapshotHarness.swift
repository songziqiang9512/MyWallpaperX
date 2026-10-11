
nonisolated enum SceneDynamicLayerField: Hashable, Sendable { case perspective }
nonisolated enum SceneDynamicTarget: Hashable, Sendable {
    case layer(layerID: Int, field: SceneDynamicLayerField)
}
nonisolated enum SceneDynamicSource: Sendable { case authored, sceneScript }
nonisolated enum SceneDynamicValue: Sendable { case bool(Bool), scalar(Double) }
nonisolated struct SceneDynamicResolvedValue: Sendable {
    let value: SceneDynamicValue
    let source: SceneDynamicSource
}
nonisolated struct SceneDynamicSnapshot: Sendable {
    var values: [SceneDynamicTarget: SceneDynamicResolvedValue] = [:]
    subscript(_ target: SceneDynamicTarget) -> SceneDynamicResolvedValue? { values[target] }
}
