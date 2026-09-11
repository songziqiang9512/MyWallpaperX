import Foundation

nonisolated extension SceneResolvedMaterialTextureResolver {
    static func selectionPurpose(
        in slot: Template.TextureSlot,
        candidateOrdinal: Int,
        activeSampler: SceneResolvedMaterialShaderSchema.Sampler?,
        reachableSamplers: Set<SceneResolvedMaterialShaderSchema.Sampler>,
        channelUse: ChannelUse?,
        input: SceneResolvedMaterialFinalizationInput
    ) -> SceneTextureLoadPurpose? {
        let reference = slot.candidates[candidateOrdinal].reference
        let declared: SceneTextureLoadPurpose?
        if let activeSampler {
            declared = SceneResolvedMaterialTextureSlotPurpose.fact(
                in: slot,
                candidateOrdinal: candidateOrdinal,
                sampler: activeSampler
            )?.purpose
        } else {
            let purposes = reachableSamplers.compactMap {
                SceneResolvedMaterialTextureSlotPurpose.fact(
                    in: slot,
                    candidateOrdinal: candidateOrdinal,
                    sampler: $0
                )?.purpose
            }
            guard purposes.count == reachableSamplers.count,
                  Set(purposes).count == 1 else { return nil }
            declared = purposes.first
        }
        let resource: SceneFrameTextureResource
        switch reference {
        case let .provider(.namedLayerTarget(namedReference)):
            guard case let .ready(namedResource)? = input.textureSnapshot.lookup(
                .namedLayerTarget(namedReference)
            ) else { return declared }
            resource = namedResource
        case let .graph(identity) where identity.kind == .framebuffer:
            guard case let .ready(graphResource)? = input.textureSnapshot.lookup(
                .graph(identity)
            ) else { return declared }
            resource = graphResource
        default:
            return declared
        }
        switch resource.publication.candidate.content {
        case .scalarRedUnorm, .scalarRedFloat16:
            guard let channelUse,
                  [.redOnly, .wholeVector].contains(channelUse),
                  activeSampler?.mode == .regular else { return nil }
            return .preservedChannels
        case .redGreenUnorm, .redGreenFloat16:
            guard let channelUse,
                  [.redOnly, .greenOnly, .redGreenOnly, .wholeVector]
                    .contains(channelUse),
                  activeSampler?.mode == .regular else { return nil }
            return .preservedChannels
        case .data:
            // A named provider may carry packed RGBA state into an exact
            // material dependency. Its publication is the frame-time purpose
            // authority; treating that state as compositor color would change
            // channel values before the authored shader reads them.
            guard activeSampler?.mode == .regular else { return nil }
            return .preservedChannels
        case .color:
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
        case let .provider(request):
            switch request {
            case let .system(name):
                return .system(.init(name: name, purpose: purpose))
            case let .namedLayerTarget(reference):
                return .namedLayerTarget(reference)
            case let .sceneBackground(consumerLayerID):
                return .sceneBackground(consumerLayerID)
            }
        case let .graph(graph):
            return .graph(graph)
        }
    }
}
