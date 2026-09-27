import Foundation

/// An admitted scalar owner starts from its authored value until the shared VM
/// publishes a newer value. Only that exact field loses its script marker;
/// unadmitted siblings retain their authored fallback and diagnostics.
nonisolated enum SceneScriptParticleProjection {
    static func apply(
        admittedTargets: Set<SceneDynamicTarget>,
        to descriptor: SceneRenderDescriptor
    ) -> SceneRenderDescriptor {
        var result = descriptor
        result.layers = descriptor.layers.map { source in
            var layer = source
            guard layer.contentKind == "particle",
                  let value = layer.particleInstanceOverride else { return layer }
            func admitted(
                _ bound: SceneParticleBoundValue?, _ field: SceneDynamicParticleField
            ) -> SceneParticleBoundValue? {
                guard admittedTargets.contains(.particle(layerID: layer.id, field: field))
                else { return bound }
                return bound.map {
                    SceneParticleBoundValue(
                        value: $0.value, userPropertyKey: $0.userPropertyKey,
                        hasScript: false, hasAnimation: $0.hasAnimation
                    )
                }
            }
            layer.particleInstanceOverride = .init(
                id: value.id,
                alpha: admitted(value.alpha, .alpha),
                size: admitted(value.size, .size),
                lifetime: admitted(value.lifetime, .lifetime),
                rate: admitted(value.rate, .rate),
                speed: admitted(value.speed, .speed),
                count: admitted(value.count, .count),
                brightness: admitted(value.brightness, .brightness),
                color: value.color, normalizedColor: value.normalizedColor,
                controlPoints: value.controlPoints,
                controlPointAngles: value.controlPointAngles
            )
            return layer
        }
        return result
    }
}
