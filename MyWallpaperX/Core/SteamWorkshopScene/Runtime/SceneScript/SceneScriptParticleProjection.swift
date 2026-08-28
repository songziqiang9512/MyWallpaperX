import Foundation

/// Keeps scripted particle fields fail-soft without authorizing unknown nested
/// targets. A structurally admitted rate owner renders its authored value until
/// the generic scalar VM publishes a newer value; all other scripted particle
/// shapes remain hidden at the smallest currently safe layer boundary.
nonisolated enum SceneScriptParticleProjection {
    static func apply(
        admittedRateLayerIDs: Set<Int>,
        to descriptor: SceneRenderDescriptor
    ) -> SceneRenderDescriptor {
        var result = descriptor
        result.layers = descriptor.layers.map { source in
            var layer = source
            guard layer.contentKind == "particle",
                  layer.particleInstanceOverride?.hasAnySceneScript == true else {
                return layer
            }
            guard admittedRateLayerIDs.contains(layer.id),
                  let override = layer.particleInstanceOverride else {
                layer.visible = false
                return layer
            }
            layer.particleInstanceOverride = override.admittingGenericRateScript()
            return layer
        }
        return result
    }
}

private nonisolated extension SceneParticleInstanceOverride {
    var hasAnySceneScript: Bool {
        let values = [
            alpha, size, lifetime, rate, speed, count, brightness,
            color, normalizedColor,
        ]
        return values.compactMap { $0 }.contains(where: \.hasScript)
            || controlPoints.values.contains(where: \.hasScript)
            || controlPointAngles.values.contains(where: \.hasScript)
    }

    func admittingGenericRateScript() -> Self {
        let admittedRate = rate.map {
            SceneParticleBoundValue(
                value: $0.value,
                userPropertyKey: $0.userPropertyKey,
                hasScript: false,
                hasAnimation: $0.hasAnimation
            )
        }
        return Self(
            id: id,
            alpha: alpha,
            size: size,
            lifetime: lifetime,
            rate: admittedRate,
            speed: speed,
            count: count,
            brightness: brightness,
            color: color,
            normalizedColor: normalizedColor,
            controlPoints: controlPoints,
            controlPointAngles: controlPointAngles
        )
    }
}
