extension SceneDesktopWallpaperHost {
    static func activeLiveConsumerTargets(
        in descriptor: SceneRenderDescriptor,
        authoredEffectCatalog: SceneAuthoredEffectExecutionCatalog
    ) -> Set<SceneDynamicTarget> {
        let utilityPlans = SceneUtilityLayerRuntimePlanner.plans(
            in: descriptor,
            authoredEffectCatalog: authoredEffectCatalog
        )
        let visibleLayerIDs = SceneLayerVisibility.visibleLayerIDs(in: descriptor)
        return descriptor.layers.reduce(
            into: authoredEffectCatalog.liveConsumerTargets
        ) { targets, layer in
            switch layer.contentKind {
            case "image":
                targets.insert(.layer(layerID: layer.id, field: .alpha))
                for animationLayer in layer.puppetAnimationLayers
                    where animationLayer.visibilityBinding != nil {
                    guard let animationLayerID = animationLayer.id else { continue }
                    targets.insert(ScenePuppetAnimationPropertyTarget.visibility(
                        layerID: layer.id,
                        animationLayerID: animationLayerID
                    ))
                }
            case "text":
                targets.insert(.layer(layerID: layer.id, field: .alpha))
                guard layer.text != nil,
                      layer.textStyle != nil,
                      visibleLayerIDs.contains(layer.id) else { return }
                targets.insert(.text(layerID: layer.id, field: .content))
                targets.insert(.text(layerID: layer.id, field: .pointSize))
                targets.insert(.text(layerID: layer.id, field: .color))
                if layer.textStyle?.limitWidth == true {
                    targets.insert(.text(layerID: layer.id, field: .maxWidth))
                }
            case "solid":
                targets.insert(.layer(layerID: layer.id, field: .alpha))
                targets.insert(.layer(layerID: layer.id, field: .color))
            case "particle":
                let fields: [SceneDynamicParticleField] = [
                    .alpha, .size, .lifetime, .rate, .speed, .count,
                    .brightness, .normalizedColor,
                ]
                targets.formUnion(fields.map {
                    .particle(layerID: layer.id, field: $0)
                })
            case "composition", "project", "fullscreen":
                if utilityPlans[layer.id]?.shouldCapture == true {
                    targets.insert(.layer(layerID: layer.id, field: .alpha))
                }
            default:
                break
            }
        }
    }
}
