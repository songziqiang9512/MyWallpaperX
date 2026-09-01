import Foundation

nonisolated extension SceneResolvedMaterialTextureResolver {
    enum LaunchAuthoredReference {
        case none
        case selected(
            Template.TextureReference,
            purpose: SceneTextureLoadPurpose?
        )
        case deferred
    }

    /// Enumerates only representation choices that can be selected by the
    /// exact mixed-provider contract. This is combined with readiness and
    /// format profiles before launch so frame finalization never compiles.
    static func launchSelectedTexturePurposeProfiles(
        template: Template,
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler]
    ) throws -> [[SceneTextureLoadPurpose?]] {
        let facts = SceneResolvedMaterialVariantCache.mixedProviderSlotFacts(
            in: template,
            samplers: samplers
        )
        var profiles = [Array<SceneTextureLoadPurpose?>(
            repeating: nil,
            count: 8
        )]
        for slot in facts.keys.sorted() {
            var expanded: [[SceneTextureLoadPurpose?]] = []
            for profile in profiles {
                for purpose in [
                    SceneTextureLoadPurpose.preservedChannels,
                    .premultipliedColor,
                ] {
                    var next = profile
                    next[slot] = purpose
                    expanded.append(next)
                    guard expanded.count <= 256 else {
                        throw launchSelectionFailure(
                            .shaderPreparationFailed,
                            slot: slot
                        )
                    }
                }
            }
            profiles = expanded
        }
        return profiles
    }

    /// Mirrors frame precedence for immutable asset candidates. Only an exact
    /// absent state may expose a lower-priority candidate; all other unready
    /// states fail launch admission instead of becoming a fallback.
    static func launchAuthoredReference(
        template: Template,
        sampler: SceneResolvedMaterialShaderSchema.Sampler?,
        slot: Int,
        assetStates: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState]
    ) throws -> LaunchAuthoredReference {
        guard template.textureSlots.indices.contains(slot),
              let textureSlot = template.textureSlots[slot] else { return .none }
        for ordinal in textureSlot.candidates.indices.reversed() {
            let candidate = textureSlot.candidates[ordinal]
            switch candidate.reference {
            case .asset:
                guard let sampler else { return .deferred }
                // Reachability is settled by the prepared Program fixed point.
                // An unproven candidate purpose cannot be loaded yet, but it
                // also cannot revoke a material before the compiler determines
                // whether this sampler is active. Active uses still fail closed
                // in launchProgramFailure and capability demand admission.
                guard let purpose = SceneResolvedMaterialTextureSlotPurpose.fact(
                    in: textureSlot,
                    candidateOrdinal: ordinal,
                    sampler: sampler
                )?.purpose else {
                    return .deferred
                }
                switch try launchAssetState(
                    candidate.reference,
                    purpose: purpose,
                    assetStates: assetStates,
                    slot: slot
                ) {
                case .ready:
                    return .selected(candidate.reference, purpose: purpose)
                case .absent: continue
                case .effectLocalUnavailable(.animatedFrameMetadataInvalid):
                    throw launchSelectionFailure(
                        .animatedFrameMetadataInvalid,
                        slot: slot
                    )
                case .pending, .unavailable:
                    throw launchSelectionFailure(.textureBindingInvalid, slot: slot)
                }
            case .userProperty:
                return .deferred
            case .provider, .graph:
                return .selected(
                    candidate.reference,
                    purpose: sampler?.purpose(for: candidate.reference)
                )
            }
        }
        return .none
    }

    static func launchAssetState(
        _ reference: Template.TextureReference,
        sampler: SceneResolvedMaterialShaderSchema.Sampler,
        assetStates: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState],
        slot: Int
    ) throws -> SceneAssetTextureLaunchState {
        guard let purpose = sampler.purpose(for: reference) else {
            throw launchSelectionFailure(.texturePurposeUnproven, slot: slot)
        }
        return try launchAssetState(
            reference,
            purpose: purpose,
            assetStates: assetStates,
            slot: slot
        )
    }

    static func launchAssetState(
        _ reference: Template.TextureReference,
        purpose: SceneTextureLoadPurpose,
        assetStates: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState],
        slot: Int
    ) throws -> SceneAssetTextureLaunchState {
        guard case let .asset(path) = reference else {
            throw launchSelectionFailure(.texturePurposeUnproven, slot: slot)
        }
        let identity = SceneAssetTextureIdentity(path: path, purpose: purpose)
        guard let state = assetStates[identity] else {
            throw launchSelectionFailure(.textureBindingInvalid, slot: slot)
        }
        return state
    }

    private static func launchSelectionFailure(
        _ code: Failure.Code,
        slot: Int
    ) -> Failure {
        .init(phase: .texture, code: code, slot: slot, details: [])
    }
}
