import Foundation

nonisolated extension SceneParticleDefinitionParser {
    func parseInstanceOverride(_ rawValue: Any?) -> SceneParticleInstanceOverride? {
        guard let root = rawValue as? [String: Any] else { return nil }
        var controlPoints: [Int: SceneParticleBoundValue] = [:]
        var controlPointAngles: [Int: SceneParticleBoundValue] = [:]
        for index in 0..<8 {
            controlPoints[index] = Self.boundValue(root["controlpoint\(index)"])
            controlPointAngles[index] = Self.boundValue(root["controlpointangle\(index)"])
        }
        return SceneParticleInstanceOverride(
            id: Self.integer(root["id"]),
            alpha: Self.boundValue(root["alpha"]),
            size: Self.boundValue(root["size"]),
            lifetime: Self.boundValue(root["lifetime"]),
            rate: Self.boundValue(root["rate"]),
            speed: Self.boundValue(root["speed"]),
            count: Self.boundValue(root["count"]),
            brightness: Self.boundValue(root["brightness"]),
            color: Self.boundValue(root["color"]),
            normalizedColor: Self.boundValue(root["colorn"]),
            controlPoints: controlPoints,
            controlPointAngles: controlPointAngles
        )
    }
}
