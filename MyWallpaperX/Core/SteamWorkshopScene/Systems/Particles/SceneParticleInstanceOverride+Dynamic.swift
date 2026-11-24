import Foundation

nonisolated extension SceneParticleInstanceOverride {
    static func resolving(
        authored: Self?, dynamic: SceneDynamicParticleValues?, brightness: Double? = nil
    ) -> Self? {
        guard let authored else {
            guard dynamic != nil else { return nil }
            return Self(id: nil, alpha: nil, size: nil, lifetime: nil, rate: nil,
                speed: nil, count: nil, color: nil, normalizedColor: nil,
                controlPoints: [:], controlPointAngles: [:]).resolving(dynamic)
        }
        return authored.resolving(dynamic, brightness: brightness)
    }

    func resolving(_ dynamic: SceneDynamicParticleValues?, brightness currentBrightness: Double? = nil) -> Self {
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
        guard let dynamic else {
            guard currentBrightness != nil else { return self }
            var resolved = self
            resolved.brightness = scalar(currentBrightness, fallback: brightness)
            return resolved
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
            color: color,
            normalizedColor: normalizedColor,
            controlPoints: controlPoints,
            controlPointAngles: controlPointAngles,
            brightness: scalar(currentBrightness, fallback: brightness)
        )
    }
}
