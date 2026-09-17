import Metal

extension SceneDependencyFrameRuntime {
    func effectInput(
        for consumerLayerID: Int,
        textureRegistry: SceneFrameTextureRegistry
    ) -> SceneDependencyEffectInput? {
        guard let binding = plan.bindingsByConsumerLayerID[consumerLayerID] else {
            return nil
        }
        let frameEpoch = textureRegistry.frameEpoch
        synchronizeReservations(to: frameEpoch)
        let reference = SceneNamedTextureReference(
            providerLayerID: binding.providerLayerID,
            variant: .primary
        )
        guard let resource = textureRegistry.completeNamedLayerTargetResource(
            reference: reference,
            frameEpoch: frameEpoch
        ) else { return nil }
        let texture = resource.publication.texture
        if let reservation = reservationsByProviderLayerID[binding.providerLayerID] {
            guard reservation.frameEpoch == frameEpoch,
                  texture === reservation.texture else { return nil }
        }
        return makeEffectInput(
            binding: binding,
            frameEpoch: frameEpoch,
            texture: texture,
            content: resource.publication.candidate.content
        )
    }

    /// Resolves every publication in a multi-provider aggregate in authored
    /// slot order. A member that is merely unpublished this frame is an
    /// ordinary `unavailable`; a missing reservation, a mismatched slot
    /// vector or a publication identity drift rejects the whole aggregate as
    /// `invalid`, so execution cannot silently consume a partial provider set
    /// and callers cannot downgrade integrity drift into a local miss.
    func aggregateEffectInputResolution(
        for aggregate: SceneDependencyRenderPlan.MultiProviderAggregate,
        textureRegistry: SceneFrameTextureRegistry
    ) -> SceneResolvedMaterialAggregateInputResolution {
        let frameEpoch = textureRegistry.frameEpoch
        guard frameEpoch > 0,
              aggregate.hasStrictBindingVector,
              plan.multiProviderAggregatesByConsumerLayerID[
                  aggregate.consumerLayerID
              ] == aggregate else {
            return .invalid(
                reasonCode: "external-primary-aggregate-contract-invalid"
            )
        }
        synchronizeReservations(to: frameEpoch)
        // `hasStrictBindingVector` proves this is already canonical. Do not
        // sort here: silently reordering a corrupted aggregate would hide an
        // authored slot/order mismatch from the execution ledger.
        let orderedBindings = aggregate.bindings
        var inputs: [SceneDependencyEffectInput] = []
        for binding in orderedBindings {
            let reference = SceneNamedTextureReference(
                providerLayerID: binding.providerLayerID,
                variant: .primary
            )
            guard let reservation = reservationsByProviderLayerID[
                binding.providerLayerID
            ], reservation.frameEpoch == frameEpoch,
                  reservation.providerLayerID == binding.providerLayerID,
                  reservation.kind == .init(binding.kind) else {
                return .invalid(
                    reasonCode: "external-primary-aggregate-reservation-mismatch"
                )
            }
            guard let resource = textureRegistry.completeNamedLayerTargetResource(
                reference: reference,
                frameEpoch: frameEpoch
            ) else {
                return .unavailable(
                    reasonCode: "external-primary-provider-capture-unavailable"
                )
            }
            guard resource.publication.texture === reservation.texture else {
                return .invalid(
                    reasonCode: "external-primary-aggregate-publication-mismatch"
                )
            }
            let texture = resource.publication.texture
            inputs.append(makeEffectInput(
                binding: binding,
                frameEpoch: frameEpoch,
                texture: texture,
                content: resource.publication.candidate.content
            ))
        }
        guard aggregateInputVectorIsValid(
            inputs,
            aggregate: aggregate,
            frameEpoch: frameEpoch
        ) else {
            return .invalid(
                reasonCode: "external-primary-aggregate-input-invalid"
            )
        }
        return .ready(inputs)
    }

    /// Resolves a dependency already reserved by unified frame preparation.
    /// A valid reservation without a same-frame publication is an ordinary
    /// provider visual failure; reservation/epoch/object drift remains an
    /// integrity rejection and must not enter the local passthrough path.
    func resolvedMaterialEffectInputResolution(
        for consumerLayerID: Int,
        textureRegistry: SceneFrameTextureRegistry
    ) -> SceneResolvedMaterialDependencyInputResolution {
        guard let binding = plan.bindingsByConsumerLayerID[consumerLayerID] else {
            return .invalid(reasonCode: "external-primary-binding-missing")
        }
        let frameEpoch = textureRegistry.frameEpoch
        guard frameEpoch > 0 else {
            return .invalid(reasonCode: "external-primary-frame-epoch-invalid")
        }
        synchronizeReservations(to: frameEpoch)
        guard let reservation = reservationsByProviderLayerID[
            binding.providerLayerID
        ] else {
            return .invalid(reasonCode: "external-primary-reservation-missing")
        }
        guard reservation.frameEpoch == frameEpoch,
              reservation.providerLayerID == binding.providerLayerID,
              reservation.kind == .init(binding.kind) else {
            return .invalid(reasonCode: "external-primary-reservation-mismatch")
        }
        let reference = SceneNamedTextureReference(
            providerLayerID: binding.providerLayerID,
            variant: .primary
        )
        guard let resource = textureRegistry.completeNamedLayerTargetResource(
            reference: reference,
            frameEpoch: frameEpoch
        ) else {
            return .unavailable(
                reasonCode: "external-primary-provider-capture-unavailable"
            )
        }
        let texture = resource.publication.texture
        guard texture === reservation.texture else {
            return .invalid(reasonCode: "external-primary-publication-mismatch")
        }
        return .ready(makeEffectInput(
            binding: binding,
            frameEpoch: frameEpoch,
            texture: texture,
            content: resource.publication.candidate.content
        ))
    }

    func recordBindingIfRequired(
        for consumerLayerID: Int,
        encoded: Bool,
        on commandBuffer: MTLCommandBuffer
    ) {
        guard plan.bindingsByConsumerLayerID[consumerLayerID] != nil
            || plan.multiProviderAggregatesByConsumerLayerID[
                consumerLayerID
            ] != nil else { return }
        bindingTelemetry.record(layerID: consumerLayerID, encoded: encoded, on: commandBuffer)
    }

    func recordBindingFailure(for consumerLayerID: Int) {
        guard plan.requiredEffectConsumerLayerIDs.contains(consumerLayerID) else { return }
        bindingTelemetry.recordFailure(layerID: consumerLayerID)
    }
}
