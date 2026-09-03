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
        plan.bindingsByConsumerLayerID.values.contains {
            $0.providerLayerID == providerLayerID && $0.requiresForwardCapture
        } || plan.staticModelBindingsByConsumerLayerID.values.contains {
            $0.providerLayerID == providerLayerID && $0.requiresForwardCapture
        }
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
        if plan.bindingsByConsumerLayerID.values.contains(where: {
            $0.providerLayerID == providerLayerID
        }) {
            return true
        }
        return plan.staticModelBindingsByConsumerLayerID.values.contains {
            $0.providerLayerID == providerLayerID
                && activeStaticModelConsumerLayerIDs.contains($0.consumerLayerID)
        }
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
        let identity = SceneFrameTextureIdentity.namedLayerTarget(
            expectedReference
        )
        guard let texture = textureRegistry.texture(for: identity),
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
