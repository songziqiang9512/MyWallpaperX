import Foundation

nonisolated enum SceneParticleBuiltInTexture: String, Hashable, Sendable {
    case chromaticDot = "particle/chromaticdot"
    case beam1 = "particle/beam/beam_1"
    case drop = "particle/drop"
    case fire1 = "particle/fire/fire1"
    case fog1 = "particle/fog/fog1"
    case fog3 = "particle/fog/fog3"
    case leaves7 = "particle/nature/leaves7"
    case leaves8 = "particle/nature/leaves8"
    case snow = "particle/nature/snow"
    case lightShafts0 = "particle/light/light_shafts_0"
    case lightShafts6 = "particle/light/light_shafts_6"
    case lightning3 = "particle/lightning/lightning3"
    case halo = "particle/halo"
    case halo2 = "particle/halo_2"
    case halo3 = "particle/halo_3"
    case halo4 = "particle/halo_4"
    case flare1 = "particle/light/flare_1"
    case rippleSingle = "particle/water/ripple_single"
    case rosePetals = "particle/nature/rosepetals"
    case smoke2 = "particle/smoke/smoke2"
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

        guard let builtIn = SceneParticleBuiltInTexture(rawValue: reference) else {
            return nil
        }
        self = .builtIn(builtIn)
    }
}
