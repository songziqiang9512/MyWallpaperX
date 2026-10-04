import Metal

struct SceneStaticModelNamedAlbedoInput {
    let texture: MTLTexture
    let frameEpoch: UInt64
    let textureFrame: SceneTextureUVTransform
    let sampling: SceneTextureSampling
    let isPremultiplied: Bool
}

extension SceneDependencyFrameRuntime {
    static func staticModelProviderSource(
        layer: SceneRenderDescriptor.Layer,
        texture: MTLTexture,
        candidate: SceneTextureCandidate?
    ) -> (
        textureFrame: SceneTextureUVTransform,
        sampling: SceneTextureSampling
    )? {
        if layer.contentKind == "solid" {
            return (.identity, .linearClamp)
        }
        guard let candidate,
              isExactImageProviderCandidate(candidate, matching: texture) else {
            return nil
        }
        return (candidate.uvTransform, candidate.sampling)
    }

    func requiresForwardCapture(for providerLayerID: Int) -> Bool {
        forwardCaptureProviderLayerIDs.contains(providerLayerID)
    }

    static func staticModelCaptureExtent(
        providerLayer: SceneRenderDescriptor.Layer,
        providerTexture: MTLTexture?,
        providerCandidate: SceneTextureCandidate?,
        failureReason: inout String?
    ) -> (width: Int, height: Int)? {
        guard let providerTexture else {
            failureReason = "static-model-provider-invalid"
            return nil
        }
        if providerLayer.contentKind == "solid" {
            return normalizedExtent(
                width: providerTexture.width,
                height: providerTexture.height
            )
        }
        guard let providerCandidate,
              isExactImageProviderCandidate(
                  providerCandidate,
                  matching: providerTexture
              ) else {
            failureReason = "static-model-provider-invalid"
            return nil
        }
        return normalizedExtent(
            width: providerTexture.width,
            height: providerTexture.height
        )
    }

    func requiresCapture(
        for providerLayerID: Int,
        activeStaticModelConsumerLayerIDs: Set<Int>
    ) -> Bool {
        if nonStaticModelProviderLayerIDs.contains(providerLayerID) {
            return true
        }
        guard let consumerIDs = staticModelConsumerLayerIDsByProviderLayerID[
            providerLayerID
        ] else {
            return false
        }
        return !consumerIDs.isDisjoint(with: activeStaticModelConsumerLayerIDs)
    }

    func isStaticModelSourceProvider(_ layerID: Int) -> Bool {
        staticModelProviderLayerIDs.contains(layerID) && !nonStaticModelProviderLayerIDs.contains(layerID)
    }

    /// A model has no effect-pass slot. Reserve its provider's prepared graph
    /// output directly in the same provider ledger used by effect consumers.
    func reserveStaticModelGraphOutput(
        providerLayer: SceneRenderDescriptor.Layer,
        preparedOutputExtent: (width: Int, height: Int),
        frameEpoch: UInt64,
        failureReason: inout String?
    ) -> Bool {
        guard frameEpoch > 0,
              staticModelProviderLayerIDs.contains(providerLayer.id),
              plan.requiredGraphOutputProviderLayerIDs.contains(providerLayer.id),
              let extent = Self.normalizedExtent(
                  width: preparedOutputExtent.width,
                  height: preparedOutputExtent.height
              ) else {
            failureReason = "static-model-graph-output-plan-invalid"
            return false
        }
        return reserveProviderTarget(
            providerLayerID: providerLayer.id,
            kind: providerLayer.contentKind == "solid" ? .solidLayer : .image,
            extent: extent,
            sourceExtent: preparedOutputExtent,
            frameEpoch: frameEpoch,
            failureReason: &failureReason
        ) != nil
    }

    func staticModelNamedAlbedo(
        for consumerLayerID: Int,
        materialPath: String,
        expectedReference: SceneNamedTextureReference,
        textureRegistry: SceneFrameTextureRegistry
    ) -> SceneStaticModelNamedAlbedoInput? {
        guard textureRegistry.frameEpoch > 0,
              let binding = plan.staticModelBindingsByConsumerLayerID[
                  consumerLayerID
              ],
              binding.passIndex == 0,
              binding.slotIndex == 0,
              binding.providerLayerID == expectedReference.providerLayerID,
              binding.variant == expectedReference.variant,
              normalized(binding.materialPath) == normalized(materialPath) else {
            return nil
        }
        guard let texture = textureRegistry.completeNamedLayerTargetTexture(
                  reference: expectedReference,
                  frameEpoch: textureRegistry.frameEpoch
              ),
              texture.textureType == .type2D,
              texture.sampleCount == 1,
              texture.usage.contains(.shaderRead) else { return nil }
        return .init(
            texture: texture,
            frameEpoch: textureRegistry.frameEpoch,
            textureFrame: .identity,
            sampling: .linearClamp,
            isPremultiplied: true
        )
    }

    func recordStaticModelBindingIfRequired(
        for consumerLayerID: Int,
        encoded: Bool,
        on commandBuffer: MTLCommandBuffer
    ) {
        guard plan.staticModelBindingsByConsumerLayerID[consumerLayerID] != nil
        else { return }
        bindingTelemetry.record(
            layerID: consumerLayerID,
            encoded: encoded,
            on: commandBuffer
        )
    }

    func recordStaticModelBindingFailure(for consumerLayerID: Int) {
        guard plan.staticModelBindingsByConsumerLayerID[consumerLayerID] != nil
        else { return }
        bindingTelemetry.recordFailure(layerID: consumerLayerID)
    }

    private func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/")
            .localizedLowercase
    }
}
