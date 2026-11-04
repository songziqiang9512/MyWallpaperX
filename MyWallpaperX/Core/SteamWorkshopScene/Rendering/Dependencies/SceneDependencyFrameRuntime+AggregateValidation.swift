import Foundation
import Metal

extension SceneDependencyFrameRuntime {
    /// Verifies that every prepared provider output can feed its independently
    /// reserved named target. Flat providers copy the output; geometry
    /// providers sample it while rasterizing their mesh into a local target.
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
                  reservation.sourceWidth == output.width,
                  reservation.sourceHeight == output.height,
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
            if reservation.sourceWidth != output.width {
                reasons.append("width-mismatch")
            }
            if reservation.sourceHeight != output.height {
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
                "sourceSize=\(reservation.sourceWidth)x\(reservation.sourceHeight)",
                "targetSize=\(reservation.width)x\(reservation.height)",
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
