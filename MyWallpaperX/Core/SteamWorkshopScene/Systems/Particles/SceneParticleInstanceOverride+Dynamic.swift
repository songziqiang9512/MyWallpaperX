import Foundation

nonisolated extension SceneParticleInstanceOverride {
    func resolving(_ dynamic: SceneDynamicParticleValues?) -> Self {
        guard let dynamic else { return self }
        func scalar(
            _ value: Double?,
            fallback: SceneParticleBoundValue?
        ) -> SceneParticleBoundValue? {
            guard let value else { return fallback }
            return .init(
                value: .scalar(value), userPropertyKey: nil,
                hasScript: false, hasAnimation: false
            )
        }
        let normalizedColor = dynamic.normalizedColor.map {
            SceneParticleBoundValue(
                value: .vector([$0.x, $0.y, $0.z]), userPropertyKey: nil,
                hasScript: false, hasAnimation: false
            )
        } ?? self.normalizedColor
        return .init(
            id: id,
            alpha: scalar(dynamic.alpha, fallback: alpha),
            size: scalar(dynamic.size, fallback: size),
            lifetime: scalar(dynamic.lifetime, fallback: lifetime),
            rate: scalar(dynamic.rate, fallback: rate),
            speed: scalar(dynamic.speed, fallback: speed),
            count: scalar(dynamic.count, fallback: count),
            brightness: scalar(dynamic.brightness, fallback: brightness),
            color: color,
            normalizedColor: normalizedColor,
            controlPoints: controlPoints,
            controlPointAngles: controlPointAngles
        )
    }
}
