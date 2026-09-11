import Foundation
import Metal

extension SceneDependencyFrameRuntime {
    /// Verifies that every prepared provider output can be copied into its
    /// independently reserved named target. The reservation must remain a
    /// distinct texture because graph target allocation is free to reuse a
    /// provider's final texture for a later transaction in the same frame.
    func installPreparedGraphOutputs(
        _ outputsByLayerID: [Int: MTLTexture],
        frameEpoch: UInt64
    ) -> Bool {
        synchronizeReservations(to: frameEpoch)
        for providerLayerID in demandedGraphOutputProviderLayerIDs.sorted() {
            guard let output = outputsByLayerID[providerLayerID] else {
                // A frame-local visual fallback deliberately leaves the
                // provisional reservation unpublished so dependants take the
                // existing ordinary provider-miss path.
                continue
            }
            let candidateReservation = reservationsByProviderLayerID[
                providerLayerID
            ]
            guard let reservation = candidateReservation,
                  reservation.frameEpoch == frameEpoch,
                  reservation.providerLayerID == providerLayerID,
                  reservation.width == output.width,
                  reservation.height == output.height,
                  reservation.texture !== output,
                  reservation.texture.pixelFormat == output.pixelFormat,
                  output.textureType == .type2D,
                  output.sampleCount == 1,
                  output.mipmapLevelCount == 1,
                  output.usage.contains(.renderTarget),
                  output.usage.contains(.shaderRead) else {
#if DEBUG
                debugRecordPreparedOutputInstallFailure(
                    providerLayerID: providerLayerID,
                    output: output,
                    reservation: candidateReservation,
                    frameEpoch: frameEpoch
                )
#endif
                return false
            }
        }
        return true
    }

    func makeEffectInput(
        binding: SceneDependencyRenderPlan.Binding,
        frameEpoch: UInt64,
        texture: MTLTexture,
        content: SceneTextureContent = .color(.resolved(.premultipliedAlpha))
    ) -> SceneDependencyEffectInput {
        SceneDependencyEffectInput(
            consumerLayerID: binding.consumerLayerID,
            providerLayerID: binding.providerLayerID,
            variant: .primary,
            slot: binding.slot,
            blendMode: binding.blendMode,
            frameEpoch: frameEpoch,
            texture: texture,
            content: content
        )
    }

    static func isValidDependencyTexture(_ texture: MTLTexture) -> Bool {
        texture.width > 0
            && texture.height > 0
            && texture.textureType == .type2D
            && texture.sampleCount == 1
            && texture.mipmapLevelCount == 1
            && texture.usage.contains(.renderTarget)
            && texture.usage.contains(.shaderRead)
    }

    /// Validates the complete aggregate input atom in authored slot order.
    /// Every field participates in the comparison; a set of provider/slot
    /// strings is insufficient because it can hide consumer, variant, blend,
    /// epoch, order, or physical-texture drift.
    func aggregateInputVectorIsValid(
        _ inputs: [SceneDependencyEffectInput],
        aggregate: SceneDependencyRenderPlan.MultiProviderAggregate,
        frameEpoch: UInt64
    ) -> Bool {
        guard frameEpoch > 0,
              aggregate.hasStrictBindingVector,
              plan.multiProviderAggregatesByConsumerLayerID[
                  aggregate.consumerLayerID
              ] == aggregate,
              inputs.count == aggregate.bindings.count else {
            return false
        }
        var texturesByProvider: [Int: MTLTexture] = [:]
        var textureIdentities = Set<ObjectIdentifier>()
        for (input, binding) in zip(inputs, aggregate.bindings) {
            guard input.consumerLayerID == aggregate.consumerLayerID,
                  input.consumerLayerID == binding.consumerLayerID,
                  input.providerLayerID == binding.providerLayerID,
                  input.variant == .primary,
                  input.slot == binding.slot,
                  input.blendMode == binding.blendMode,
                  input.frameEpoch == frameEpoch,
                  Self.isValidDependencyTexture(input.texture) else {
                return false
            }
            if let existing = texturesByProvider[input.providerLayerID] {
                guard existing === input.texture else { return false }
            } else {
                texturesByProvider[input.providerLayerID] = input.texture
                guard textureIdentities.insert(
                    ObjectIdentifier(input.texture)
                ).inserted else {
                    return false
                }
            }
        }
        return true
    }

#if DEBUG
    /// Emits one bounded, first-failure record for the prepared graph-output
    /// install seam. The ordinary rejection path remains unchanged; this is
    /// only enough identity/descriptor data to distinguish a missing
    /// reservation from extent, usage, or texture-object drift in a run.
    func debugRecordPreparedOutputInstallFailure(
        providerLayerID: Int,
        output: MTLTexture,
        reservation: EffectTargetReservation?,
        frameEpoch: UInt64
    ) {
        guard !debugPreparedOutputInstallFailureRecorded else { return }
        debugPreparedOutputInstallFailureRecorded = true
        var reasons: [String] = []
        if let reservation {
            if reservation.frameEpoch != frameEpoch {
                reasons.append("reservation-epoch-mismatch")
            }
            if reservation.providerLayerID != providerLayerID {
                reasons.append("reservation-provider-mismatch")
            }
            if reservation.width != output.width {
                reasons.append("width-mismatch")
            }
            if reservation.height != output.height {
                reasons.append("height-mismatch")
            }
            if reservation.texture === output {
                reasons.append("texture-identity-alias")
            }
            if reservation.texture.pixelFormat != output.pixelFormat {
                reasons.append("pixel-format-mismatch")
            }
        } else {
            reasons.append("reservation-missing")
        }
        if output.textureType != .type2D {
            reasons.append("output-type-invalid")
        }
        if output.sampleCount != 1 {
            reasons.append("output-sample-count-invalid")
        }
        if output.mipmapLevelCount != 1 {
            reasons.append("output-mip-count-invalid")
        }
        if !output.usage.contains(.renderTarget) {
            reasons.append("output-render-target-usage-missing")
        }
        if !output.usage.contains(.shaderRead) {
            reasons.append("output-shader-read-usage-missing")
        }
        if reasons.isEmpty {
            reasons.append("unknown-integrity-mismatch")
        }
        let outputDescription = [
            "size=\(output.width)x\(output.height)",
            "type=\(String(describing: output.textureType))",
            "sample=\(output.sampleCount)",
            "mips=\(output.mipmapLevelCount)",
            "pixelFormat=\(output.pixelFormat.rawValue)",
            "usage=\(output.usage.rawValue)",
            "identity=\(String(describing: ObjectIdentifier(output)))",
        ].joined(separator: ",")
        let reservationDescription: String
        if let reservation {
            reservationDescription = [
                "size=\(reservation.width)x\(reservation.height)",
                "kind=\(String(describing: reservation.kind))",
                "frameEpoch=\(reservation.frameEpoch)",
                "pixelFormat=\(reservation.texture.pixelFormat.rawValue)",
                "usage=\(reservation.texture.usage.rawValue)",
                "type=\(String(describing: reservation.texture.textureType))",
                "sample=\(reservation.texture.sampleCount)",
                "mips=\(reservation.texture.mipmapLevelCount)",
                "identity=\(String(describing: ObjectIdentifier(reservation.texture)))",
            ].joined(separator: ",")
        } else {
            reservationDescription = "none"
        }
        NSLog(
            "MWX DEBUG SCENE: phase=prepared-provider-output-install-failure frameEpoch=%llu provider=%d reason=%@ output={%@} reservation={%@} reservationKeys=%@ reservationCount=%d",
            frameEpoch,
            providerLayerID,
            reasons.joined(separator: "+"),
            outputDescription,
            reservationDescription,
            reservationsByProviderLayerID.keys.sorted().map(String.init).joined(separator: ","),
            reservationsByProviderLayerID.count
        )
    }
#endif

}
