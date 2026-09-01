import Foundation

nonisolated struct SceneResolvedMaterialVariantKey: Hashable {
    let readinessMask: UInt8
    let textureFormats: [SceneShaderTextureFormat?]
    /// Only slots whose authored candidate chain can select more than one
    /// proven texture representation participate here. Static slots retain
    /// their existing launch contract, while a mixed provider slot cannot
    /// accidentally reuse the ABI compiled for another selected candidate.
    let selectedTexturePurposes: [SceneTextureLoadPurpose?]

    init?(
        readinessMask: UInt8,
        textureFormats: [SceneShaderTextureFormat?],
        selectedTexturePurposes: [SceneTextureLoadPurpose?] = Array(
            repeating: nil,
            count: 8
        )
    ) {
        guard textureFormats.count == 8,
              selectedTexturePurposes.count == 8 else { return nil }
        self.readinessMask = readinessMask
        self.textureFormats = textureFormats
        self.selectedTexturePurposes = selectedTexturePurposes
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
    /// consuming variant must either observe the stored red scalar directly or
    /// consume the complete vector supplied by a typed Metal R texture.
    func provesScalarRedConsumer(slot: Int) -> Bool {
        guard let uses = compiledChannelUses(for: slot) else { return false }
        return Self.channelEnvelopeIsScalarRedCompatible(uses)
    }

    /// At least one launch-envelope variant must consume the slot, and every
    /// consuming variant must either observe a nonempty subset of stored R/G
    /// or the complete vector supplied by a typed Metal R/G texture.
    func provesRedGreenConsumer(slot: Int) -> Bool {
        guard let uses = compiledChannelUses(for: slot) else { return false }
        return Self.channelEnvelopeIsRedGreenCompatible(uses)
    }

    /// Every precompiled launch variant must preserve one exact independent
    /// RGBA signal slot. A single matching variant cannot type a feedback
    /// target whose other launch variants observe a different color contract.
    func provesIndependentAlphaSignalPreserving(slot: Int) -> Bool {
        launchEnvelopeProvesColorTransfer(
            .independentAlphaSignalPreserving(textureSlot: slot),
            requiredSlots: [slot]
        )
    }

    /// Every precompiled launch variant must consume the same independent
    /// signal and compositable color slots. The graph classifier separately
    /// binds those slots to exact authored identities.
    func provesIndependentAlphaSignalCompositing(
        signalSlot: Int,
        colorSlot: Int
    ) -> Bool {
        guard signalSlot != colorSlot else { return false }
        return launchEnvelopeProvesColorTransfer(
            .independentAlphaSignalCompositing(
                signalSlot: signalSlot,
                colorSlot: colorSlot
            ),
            requiredSlots: [signalSlot, colorSlot]
        )
    }

    private func launchEnvelopeProvesColorTransfer(
        _ transfer: SceneShaderColorTransfer,
        requiredSlots: Set<Int>
    ) -> Bool {
        guard requiredSlots.allSatisfy({ (0 ..< 8).contains($0) }) else {
            return false
        }
        let snapshot = launchEnvelopeCapabilitySnapshot()
        guard snapshot.allEntriesReady, !snapshot.variants.isEmpty else {
            return false
        }
        return snapshot.variants.allSatisfy { variant in
            let bindings = variant.frontendProgram.textureBindings
            let activeSlots = Set(bindings.map(\.slot))
            return variant.frontendProgram.colorTransfer == transfer
                && activeSlots.count == bindings.count
                && requiredSlots.isSubset(of: activeSlots)
                && requiredSlots.allSatisfy { slot in
                    bindings.filter { $0.slot == slot }.count == 1
                        && variant.activeSamplers[slot] != nil
                }
        }
    }

    static func channelEnvelopeIsScalarRedCompatible(
        _ uses: [ChannelUse]
    ) -> Bool {
        !uses.isEmpty && uses.allSatisfy {
            [.redOnly, .wholeVector].contains($0)
        }
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
