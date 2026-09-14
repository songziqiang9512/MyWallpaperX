import Foundation

extension SceneResolvedMaterialVariantCache {
    struct LaunchEnvelopeCapabilitySnapshot {
        let template: Template
        let variants: [Variant]
        let allEntriesReady: Bool
        let reachableSamplers: [
            Int: Set<SceneResolvedMaterialShaderSchema.Sampler>
        ]?
        let inputIdentity: Graph.TextureIdentity?
        let hasCachedReachability: Bool
    }

    /// Launch-envelope compilation is the authority for host audio demand.
    /// Raw source declarations are insufficient because inactive variants and
    /// rejected array shapes must not keep system audio capture alive.
    var hasAudioSpectrumConsumer: Bool {
        launchEnvelopeCapabilitySnapshot().variants.contains { variant in
            let activeTextureSlots = Set(
                variant.frontendProgram.textureBindings.map(\.slot)
            )
            return variant.frontendProgram.uniformLayout.fields.contains { field in
                switch SceneResolvedMaterialUniformEncoder.hostUniform(
                    field,
                    activeTextureSlots: activeTextureSlots
                ) {
                case .audioSpectrumLeft, .audioSpectrumRight:
                    return true
                default:
                    return false
                }
            }
        }
    }
}
