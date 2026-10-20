nonisolated enum ScenePuppetAnimationPropertyTarget {
    enum Field: String { case visibility = "visible", rate }

    nonisolated static func visibility(
        layerID: Int,
        animationLayerID: Int
    ) -> SceneDynamicTarget {
        .scriptInstanceProperty(
            layerID: layerID,
            path: ["puppetAnimationLayer", String(animationLayerID), "visible"]
        )
    }

    nonisolated static func rate(layerID: Int, animationLayerID: Int) -> SceneDynamicTarget {
        .scriptInstanceProperty(
            layerID: layerID,
            path: ["puppetAnimationLayer", String(animationLayerID), "rate"]
        )
    }

    nonisolated static func field(for target: SceneDynamicTarget) -> Field? {
        guard case let .scriptInstanceProperty(_, path) = target,
              path.count == 3, path[0] == "puppetAnimationLayer" else { return nil }
        return Field(rawValue: path[2])
    }

    nonisolated static func source(for target: SceneDynamicTarget)
        -> (layerID: Int, animationLayerID: Int)? {
        guard field(for: target) != nil,
              case let .scriptInstanceProperty(layerID, path) = target,
              let id = Int(path[1]), String(id) == path[1] else { return nil }
        return (layerID, id)
    }
}
