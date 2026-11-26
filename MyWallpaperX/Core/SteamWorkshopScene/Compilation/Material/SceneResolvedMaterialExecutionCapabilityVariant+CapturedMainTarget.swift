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

        var dynamicUniforms: Set<Template.DynamicUniform> {
            var values: Set<Template.DynamicUniform> = []
            for variant in variants {
                for binding in variant.preparedUniformBindings {
                    if case let .dynamic(prepared) = binding.source {
                        values.insert(prepared.declaration)
                    }
                }
            }
            return values
        }
    }

    /// Launch-envelope compilation is the authority for host audio demand.
    /// Raw source declarations are insufficient because inactive variants and
    /// rejected array shapes must not keep system audio capture alive.
    var hasAudioSpectrumConsumer: Bool {
        launchEnvelopeCapabilitySnapshot().variants.contains { variant in
            variant.preparedAssembly.preparedUniformBindings.contains { binding in
                switch binding.source {
                case .host(.audioSpectrumLeft), .host(.audioSpectrumRight):
                    return true
                default:
                    return false
                }
            }
        }
    }
}
