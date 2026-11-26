import Metal

extension SceneDependencyFrameRuntime {
    func selectNamedGraphHistory(
        _ schedule: SceneDependencyRenderPlan.PreparationSchedule,
        completed: [Int: SceneNamedGraphOutput],
        frameEpoch: UInt64
    ) {
        synchronizeReservations(to: frameEpoch)
        for provider in previousProviderLayerIDs.subtracting(schedule.previousProviderLayerIDs) {
            targetPool.retireHistory(for: provider, keeping: previousNamedGraphOutputs[provider]?.texture)
        }
        previousProviderLayerIDs = schedule.previousProviderLayerIDs
        previousProvidersByConsumerLayerID = schedule.previousProvidersByConsumerLayerID
        previousNamedGraphOutputs = completed
    }

    /// Reserve the writer even if its first reader has no previous image.
    func reserveHistoricalGraphOutput(
        for provider: Int, sourceExtent: (width: Int, height: Int), frameEpoch: UInt64
    ) -> (reserved: Bool, retiresPrevious: Bool) {
        guard let extent = Self.normalizedExtent(width: sourceExtent.width, height: sourceExtent.height)
        else { return (false, false) }
        let previous = previousNamedGraphOutputs[provider]
        let reusable = previous.map {
            $0.sourceWidth == sourceExtent.width && $0.sourceHeight == sourceExtent.height
        } ?? false
        func reserve(avoiding texture: MTLTexture?) -> MTLTexture? {
            var failure: String?
            return reserveProviderTarget(providerLayerID: provider, kind: .resolvedMaterial,
                extent: extent, sourceExtent: sourceExtent, avoiding: texture,
                frameEpoch: frameEpoch, failureReason: &failure)
        }
        if reusable, let previous, reserve(avoiding: previous.texture) != nil {
            return (true, false)
        }
        if let previous {
            previousNamedGraphOutputs.removeValue(forKey: provider)
            targetPool.retireHistory(for: provider, keeping: reusable ? previous.texture : nil)
        }
        return (reserve(avoiding: nil) != nil, previous != nil)
    }

    func previousEffectInput(for binding: SceneDependencyRenderPlan.Binding, frameEpoch: UInt64)
        -> SceneDependencyEffectInput? {
        guard let previous = previousNamedGraphOutputs[binding.providerLayerID],
              let writer = reservationsByProviderLayerID[binding.providerLayerID],
              writer.texture !== previous.texture else { return nil }
        return .init(consumerLayerID: binding.consumerLayerID, providerLayerID: binding.providerLayerID,
            variant: .primary, slot: binding.slot, blendMode: binding.blendMode, frameEpoch: frameEpoch,
            texture: previous.texture, content: previous.content, producerFrameEpoch: previous.frameEpoch)
    }

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
        textureRegistry: SceneFrameTextureRegistry,
        selectedSlots: Set<SceneEffectPassSlot>? = nil
    ) -> SceneResolvedMaterialAggregateInputResolution {
        let frameEpoch = textureRegistry.frameEpoch
        guard frameEpoch > 0 else {
            return .invalid(
                reasonCode: "external-primary-frame-epoch-invalid"
            )
        }
        synchronizeReservations(to: frameEpoch)
        var inputs: [SceneDependencyEffectInput] = []
        for binding in aggregate.bindings where selectedSlots?.contains(binding.slot) != false {
            if previousProvidersByConsumerLayerID[binding.consumerLayerID]?.contains(binding.providerLayerID) == true {
                if let input = previousEffectInput(for: binding, frameEpoch: frameEpoch) {
                    inputs.append(input)
                }
                continue
            }
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
        if previousProvidersByConsumerLayerID[consumerLayerID]?.contains(binding.providerLayerID) == true {
            return previousEffectInput(for: binding, frameEpoch: frameEpoch).map { .ready($0) }
                ?? .unavailable(reasonCode: "external-primary-provider-history-unavailable")
        }
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
