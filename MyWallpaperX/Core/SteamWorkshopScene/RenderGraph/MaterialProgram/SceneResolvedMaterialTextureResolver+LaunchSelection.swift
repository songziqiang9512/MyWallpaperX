import Foundation

nonisolated extension SceneResolvedMaterialTextureResolver {
    enum LaunchAuthoredReference {
        case none
        case selected(Template.TextureReference)
        case deferred
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
        for candidate in textureSlot.candidates.reversed() {
            switch candidate.reference {
            case .asset:
                guard let sampler else { return .deferred }
                switch try launchAssetState(
                    candidate.reference,
                    sampler: sampler,
                    assetStates: assetStates,
                    slot: slot
                ) {
                case .ready: return .selected(candidate.reference)
                case .absent: continue
                case .pending, .unavailable:
                    throw launchSelectionFailure(.textureBindingInvalid, slot: slot)
                }
            case .userProperty:
                return .deferred
            case .provider, .graph:
                return .selected(candidate.reference)
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
        guard case let .asset(path) = reference,
              let purpose = sampler.purpose(for: reference) else {
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
