import CoreGraphics
import Metal
import simd

extension SceneDependencyFrameRuntime {
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
                width: providerTexture.width,
                height: providerTexture.height
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
                width: providerTexture.width,
                height: providerTexture.height
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
