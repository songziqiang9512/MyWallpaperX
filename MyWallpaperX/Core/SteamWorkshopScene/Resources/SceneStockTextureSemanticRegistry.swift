/// Closed semantic facts for stock texture identities published by the shader
/// contract. This registry never infers purpose from filenames or file formats.
nonisolated enum SceneStockTextureSemanticRegistry {
    static func purpose(
        for path: SceneVFSAssetPath
    ) -> SceneTextureLoadPurpose? {
        switch path.value {
        case "effects/waterripplenormal": .normal
        case "effects/waterflowphase": .phase
        case "gradient/gradient_fire": .preservedChannels
        case "gradient/gradient_ferro_fluid": .preservedChannels
        case "gradient/gradient_iridescent": .preservedChannels
        case "util/clouds_256": .noise
        case "util/noise": .noise
        case "util/perlin_256": .noise
        default: nil
        }
    }
}
