/// Closed semantic facts for stock texture identities published by the shader
/// contract. This registry never infers purpose from filenames or file formats.
nonisolated enum SceneStockTextureSemanticRegistry {
    static func isNeutralColorCarrier(_ path: SceneVFSAssetPath) -> Bool {
        path.value == "util/white"
    }

    /// Stock noise paths the runtime can synthesize deterministically when
    /// the sample ships no such asset (user-directed 2026-09-26).
    static let noiseTexturePaths: [String] = [
        "pattern/voronoi",
        "pattern/voronoi_local",
        "util/clouds_256",
        "util/noise",
        "util/perlin_256",
        "util/uniform_256",
    ]

    static func purpose(
        for path: SceneVFSAssetPath
    ) -> SceneTextureLoadPurpose? {
        switch path.value {
        case "effects/waterripplenormal": .normal
        case "effects/waterflowphase": .phase
        case "gradient/gradient_fire": .preservedChannels
        case "gradient/gradient_ferro_fluid": .preservedChannels
        case "gradient/gradient_iridescent": .preservedChannels
        case "pattern/voronoi": .noise
        case "pattern/voronoi_local": .noise
        case "util/clouds_256": .noise
        case "util/noise": .noise
        case "util/perlin_256": .noise
        case "util/uniform_256": .noise
        default: nil
        }
    }
}
