import Foundation

nonisolated extension SceneResolvedMaterialTextureResolver {
    static func selectionPurpose(
        _ reference: Template.TextureReference,
        activeSampler: SceneResolvedMaterialShaderSchema.Sampler?,
        reachableSamplers: Set<SceneResolvedMaterialShaderSchema.Sampler>,
        channelUse: ChannelUse?,
        input: SceneResolvedMaterialFinalizationInput
    ) -> SceneTextureLoadPurpose? {
        let declared: SceneTextureLoadPurpose?
        if let activeSampler {
            declared = activeSampler.purpose(for: reference)
        } else {
            let purposes = reachableSamplers.compactMap { $0.purpose(for: reference) }
            guard purposes.count == reachableSamplers.count,
                  Set(purposes).count == 1 else { return nil }
            declared = purposes.first
        }
        guard case let .graph(identity) = reference,
              identity.kind == .framebuffer else { return declared }
        guard case let .ready(resource)? = input.textureSnapshot.lookup(.graph(identity))
        else { return declared }
        switch resource.publication.candidate.content {
        case .scalarRedUnorm:
            guard let channelUse,
                  channelUse == .redOnly,
                  activeSampler?.mode == .regular else { return nil }
            return .preservedChannels
        case .color, .data:
            return declared
        }
    }

    static func runtimeIdentity(
        _ reference: Template.TextureReference,
        purpose: SceneTextureLoadPurpose
    ) throws -> SceneFrameTextureIdentity {
        switch reference {
        case let .asset(path):
            return .asset(.init(path: path, purpose: purpose))
        case let .userProperty(request):
            guard let identity = SceneUserPropertyTextureIdentity(
                propertyKey: request.key,
                purpose: purpose
            ) else {
                throw Failure(phase: .invariant, code: .identityInvariant)
            }
            return .materialUserProperty(identity)
        case let .provider(.system(name)):
            return .system(name)
        case let .graph(graph):
            return .graph(graph)
        }
    }
}
