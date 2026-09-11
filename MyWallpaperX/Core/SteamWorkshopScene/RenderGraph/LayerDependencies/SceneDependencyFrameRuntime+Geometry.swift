import CoreGraphics
import Metal
import simd

extension SceneDependencyFrameRuntime {
    func captureExtentForProvider(
        layer: SceneRenderDescriptor.Layer,
        providerBindings: [SceneDependencyRenderPlan.Binding],
        hasStaticModelBinding: Bool,
        reservation: EffectTargetReservation?,
        frameEpoch: UInt64,
        sourceTexture: MTLTexture?,
        sourceCandidate: SceneTextureCandidate?,
        layerMVP: simd_float4x4,
        viewportSize: CGSize,
        failureReason: inout String?
    ) -> (width: Int, height: Int)? {
        if plan.requiredGraphOutputProviderLayerIDs.contains(layer.id),
           let reservation,
           reservation.frameEpoch == frameEpoch {
            // A graph provider may carry a lower-resolution source texture.
            // Its named target follows the prepared graph allocation extent.
            return (reservation.width, reservation.height)
        }
        if let binding = providerBindings.first {
            return Self.captureExtent(
                binding: binding,
                providerLayer: layer,
                providerTexture: sourceTexture,
                providerCandidate: sourceCandidate,
                layerMVP: layerMVP,
                viewportSize: viewportSize,
                failureReason: &failureReason
            )
        }
        guard hasStaticModelBinding else { return nil }
        return Self.staticModelCaptureExtent(
            providerLayer: layer,
            providerTexture: sourceTexture,
            providerCandidate: sourceCandidate,
            failureReason: &failureReason
        )
    }

    static func normalizedExtent(
        width: Int,
        height: Int
    ) -> (width: Int, height: Int)? {
        guard width > 0, height > 0 else { return nil }
        let longestEdge = max(width, height)
        guard longestEdge > SceneNamedRenderTargetPool.maximumDimension else {
            return (width, height)
        }
        let scale = Double(SceneNamedRenderTargetPool.maximumDimension)
            / Double(longestEdge)
        return (
            max(1, Int((Double(width) * scale).rounded())),
            max(1, Int((Double(height) * scale).rounded()))
        )
    }

    static func captureExtent(
        binding: SceneDependencyRenderPlan.Binding,
        providerLayer: SceneRenderDescriptor.Layer,
        providerTexture: MTLTexture?,
        providerCandidate: SceneTextureCandidate?,
        layerMVP: simd_float4x4,
        viewportSize: CGSize,
        preparedOutputExtent: (width: Int, height: Int)? = nil,
        failureReason: inout String?
    ) -> (width: Int, height: Int)? {
        switch binding.kind {
        case .imageLayerBlend, .visibleImageGraphOutput:
            guard binding.providerLayerID == providerLayer.id,
                  let providerTexture,
                  let providerCandidate,
                  isExactImageProviderCandidate(
                      providerCandidate,
                      matching: providerTexture
                  ) else {
                failureReason = "image-provider-invalid"
                return nil
            }
            return normalizedExtent(
                width: preparedOutputExtent?.width ?? providerTexture.width,
                height: preparedOutputExtent?.height ?? providerTexture.height
            )
        case .resolvedMaterial:
            guard let utility = providerLayer.utilityLayer,
                  let geometry = SceneCaptureGeometryResolver.resolve(
                      kind: utility.kind,
                      layerMVP: layerMVP,
                      viewportSize: viewportSize
                  ) else {
                failureReason = "resolved-material-geometry-invalid"
                return nil
            }
            return normalizedExtent(
                width: Int(geometry.pixelSize.width.rounded(.up)),
                height: Int(geometry.pixelSize.height.rounded(.up))
            )
        case .solidLayer:
            guard binding.providerLayerID == providerLayer.id else {
                failureReason = "provider-layer-mismatch"
                return nil
            }
            guard let providerTexture else {
                failureReason = "solid-provider-texture-missing"
                return nil
            }
            return normalizedExtent(
                width: preparedOutputExtent?.width ?? providerTexture.width,
                height: preparedOutputExtent?.height ?? providerTexture.height
            )
        }
    }

    static func isExactImageProviderCandidate(
        _ candidate: SceneTextureCandidate,
        matching texture: MTLTexture
    ) -> Bool {
        guard candidate.texture === texture,
              candidate.purpose == .premultipliedColor,
              candidate.content.isResolved,
              candidate.sampling.isResolvedForMaterialProgram,
              !candidate.sampling.usesClampBorderFallback,
              candidate.axisAlignedMappedUVScale(
                  expectedPurpose: .premultipliedColor
              ) != nil,
              texture.textureType == .type2D,
              texture.sampleCount == 1,
              texture.usage.contains(.shaderRead) else {
            return false
        }
        return true
    }
}
