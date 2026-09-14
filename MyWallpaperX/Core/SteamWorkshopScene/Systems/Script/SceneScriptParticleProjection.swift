import Foundation

/// Keeps scripted particle fields fail-soft without authorizing unknown nested
/// targets. A structurally admitted rate owner renders its authored value until
/// the generic scalar VM publishes a newer value. Other scripted fields retain
/// that authored value instead of suppressing the whole particle layer.
nonisolated enum SceneScriptParticleProjection {
    static func apply(
        admittedRateLayerIDs: Set<Int>,
        to descriptor: SceneRenderDescriptor
    ) -> SceneRenderDescriptor {
        var result = descriptor
        result.layers = descriptor.layers.map { source in
            var layer = source
            guard layer.contentKind == "particle",
                  admittedRateLayerIDs.contains(layer.id),
                  let override = layer.particleInstanceOverride else {
                return layer
            }
            layer.particleInstanceOverride = override.admittingGenericRateScript()
            return layer
        }
        return result
    }
}

private nonisolated extension SceneParticleInstanceOverride {
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
