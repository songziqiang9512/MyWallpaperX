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

    /// Keeps available publications in authored slot order. Missing supply
    /// stays local to its operation; existing resource identity drift is invalid.
    func aggregateEffectInputResolution(
        for aggregate: SceneDependencyRenderPlan.MultiProviderAggregate,
        textureRegistry: SceneFrameTextureRegistry
    ) -> SceneResolvedMaterialAggregateInputResolution {
        let frameEpoch = textureRegistry.frameEpoch
        guard frameEpoch > 0 else {
            return .invalid(
                reasonCode: "external-primary-frame-epoch-invalid"
            )
        }
        synchronizeReservations(to: frameEpoch)
        var inputs: [SceneDependencyEffectInput] = []
        for binding in aggregate.bindings {
            let reference = SceneNamedTextureReference(
                providerLayerID: binding.providerLayerID,
                variant: .primary
            )
            guard let reservation = reservationsByProviderLayerID[
                binding.providerLayerID
            ] else { continue }
            guard reservation.frameEpoch == frameEpoch,
                  reservation.providerLayerID == binding.providerLayerID,
                  reservation.kind == .init(binding.kind) else {
                return .invalid(
                    reasonCode: "external-primary-aggregate-reservation-mismatch"
                )
            }
            guard let resource = textureRegistry.completeNamedLayerTargetResource(
                reference: reference,
                frameEpoch: frameEpoch
            ) else { continue }
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
        guard !plan.cyclicLayerIDs.contains(binding.providerLayerID) else {
            return .unavailable(reasonCode: "external-primary-provider-capture-unavailable")
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
