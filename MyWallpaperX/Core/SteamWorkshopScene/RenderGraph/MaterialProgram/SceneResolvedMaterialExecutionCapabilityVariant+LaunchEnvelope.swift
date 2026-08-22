import Foundation

nonisolated struct SceneResolvedMaterialVariantKey: Hashable {
    let readinessMask: UInt8
    let textureFormats: [SceneShaderTextureFormat?]

    init?(readinessMask: UInt8, textureFormats: [SceneShaderTextureFormat?]) {
        guard textureFormats.count == 8 else { return nil }
        self.readinessMask = readinessMask
        self.textureFormats = textureFormats
    }

    var resolvedTextureFormats: [Int: SceneShaderTextureFormat] {
        Dictionary(uniqueKeysWithValues: textureFormats.enumerated().compactMap {
            index, format in format.map { (index, $0) }
        })
    }
}

extension SceneResolvedMaterialVariantCache {
    typealias ChannelUse = SceneAuthoredShaderProgram.TextureBinding.ChannelUse

    /// A singular effect projection is usable only when no compiled launch
    /// variant can observe either projection-matrix host uniform.
    var requiresInvertibleEffectTextureProjection: Bool {
        let snapshot = launchEnvelopeCapabilitySnapshot()
        guard snapshot.allEntriesReady, !snapshot.variants.isEmpty else {
            return true
        }
        return snapshot.variants.contains { variant in
            let activeSlots = Set(
                variant.frontendProgram.textureBindings.map(\.slot)
            )
            return variant.frontendProgram.uniformLayout.fields.contains { field in
                guard let host = SceneResolvedMaterialUniformEncoder.hostUniform(
                    field,
                    activeTextureSlots: activeSlots
                ) else { return false }
                switch host {
                case .effectTextureProjectionMatrix,
                     .effectTextureProjectionMatrixInverse:
                    return true
                default:
                    return false
                }
            }
        }
    }

    func resolve(
        _ input: SceneResolvedMaterialFinalizationInput
    ) -> Result<Variant, Failure> {
        resolveSelection(input).map(\.variant)
    }

    /// At least one launch-envelope variant must consume the slot, and every
    /// consuming variant must observe only the stored red scalar.
    func provesRedOnlyConsumer(slot: Int) -> Bool {
        guard let uses = compiledChannelUses(for: slot) else { return false }
        return Self.channelEnvelopeIsRedOnly(uses)
    }

    /// At least one launch-envelope variant must consume the slot, and every
    /// consuming variant must either observe a nonempty subset of stored R/G
    /// or the complete vector supplied by a typed Metal R/G texture.
    func provesRedGreenConsumer(slot: Int) -> Bool {
        guard let uses = compiledChannelUses(for: slot) else { return false }
        return Self.channelEnvelopeIsRedGreenCompatible(uses)
    }

    static func channelEnvelopeIsRedOnly(_ uses: [ChannelUse]) -> Bool {
        !uses.isEmpty && uses.allSatisfy { $0 == .redOnly }
    }

    static func channelEnvelopeIsRedGreenCompatible(_ uses: [ChannelUse]) -> Bool {
        !uses.isEmpty && uses.allSatisfy {
            [.redOnly, .greenOnly, .redGreenOnly, .wholeVector].contains($0)
        }
    }

    struct Counters: Equatable {
        let cachedVariantCount: Int
        let shaderPreparationCount: Int
        /// Bounded Swift frontend invocations; generic artifact hits do not increment.
        let frontendCompilationCount: Int
        let capacityRejectionCount: Int
    }

    enum LaunchEnvelopeFailure: Error {
        enum Kind: String {
            case capacity
            case shaderPreparation = "shader-preparation"
            case frontend
            case samplerSchema = "sampler-schema"
            case uniformSchema = "uniform-schema"
            case texturePurpose = "texture-purpose"
            case textureBinding = "texture-binding"
            case animatedFrameMetadata = "animated-frame-metadata"
            case colorContract = "color-contract"
            case invariant
        }

        case capacity
        case material(Failure)

        var kind: Kind {
            switch self {
            case .capacity: .capacity
            case let .material(failure): switch failure.code {
                case .shaderPreparationFailed: .shaderPreparation
                case .shaderFrontendFailed: .frontend
                case .authoredSamplerSchemaInvalid: .samplerSchema
                case .uniformBindingInvalid: .uniformSchema
                case .texturePurposeUnproven: .texturePurpose
                case .animatedFrameMetadataInvalid: .animatedFrameMetadata
                case .textureBindingInvalid, .textureReferenceInvalid:
                    .textureBinding
                case .colorContractUnproven: .colorContract
                default: .invariant
                }
            }
        }
    }

}
