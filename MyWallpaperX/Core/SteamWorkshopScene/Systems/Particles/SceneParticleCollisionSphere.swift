import Foundation

nonisolated struct SceneParticleCollisionSpherePlan: Equatable, Sendable {
    let origin: SIMD3<Double>
    let radius: Double
    let bounceFactor: Double

    nonisolated init?(root: [String: Any], origin: SceneParticleNumericValue?) {
        guard case let .vector(values) = origin, values.count == 3,
              values.allSatisfy(\.isFinite),
              let radius = SceneParticleDefinitionParser.number(root["radius"]),
              radius.isFinite, radius >= 0 else { return nil }

        let bounceFactor: Double
        switch root["collisionbehavior"] {
        case nil, is NSNull:
            guard let value = SceneParticleDefinitionParser.number(root["bouncefactor"]),
                  value.isFinite else { return nil }
            bounceFactor = value
        case let behavior as String where behavior.lowercased() == "slide":
            bounceFactor = 0
        default:
            return nil
        }
        self.origin = SIMD3(values[0], values[1], values[2])
        self.radius = radius
        self.bounceFactor = bounceFactor
    }
}
