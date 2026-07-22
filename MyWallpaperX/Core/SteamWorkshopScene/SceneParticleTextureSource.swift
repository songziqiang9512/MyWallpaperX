import Foundation

nonisolated enum SceneParticleBuiltInTexture: String, Equatable, Sendable {
    case drop = "particle/drop"
}

nonisolated enum SceneParticleTextureSource: Equatable, Sendable {
    case file(URL)
    case builtIn(SceneParticleBuiltInTexture)

    nonisolated init?(reference rawReference: String) {
        var reference = rawReference
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
            .lowercased()
        while reference.hasPrefix("./") {
            reference.removeFirst(2)
        }
        if reference.hasPrefix("materials/") {
            reference.removeFirst("materials/".count)
        }

        switch reference {
        case "particle/drop":
            self = .builtIn(.drop)
        default:
            return nil
        }
    }
}
