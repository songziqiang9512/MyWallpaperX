import CoreGraphics
import Metal
import simd

/// Prepares one utility's source geometry and optional ordered material input.
/// Allocation, publication and encoding remain with the original frame/graph.
struct SceneResolvedMaterialUtilitySource {
    let geometry: SceneCaptureGeometry
    let material: SceneResolvedMaterialRuntimeBridge.FramebufferSourceMaterial?

    /// The captured source and this pass must name the same current pixels.
    /// A utility can otherwise use a flat capture with a perspective output.
    func permitsAttachmentRead(
        layer: SceneRenderDescriptor.Layer,
        alpha: Float,
        cameraFrame: SceneParticleCameraFrame,
        viewportSize: CGSize,
        groups: SceneCompositionGroupFrameRuntime?,
        memberLayerIDs: [Int]?
    ) -> Bool {
        guard let utility = layer.utilityLayer, utility.kind == .composition,
              utility.copyBackground, utility.framebufferSource == nil,
              memberLayerIDs == nil, layer.childLayerIDs.isEmpty,
              material == nil, alpha == 1, !cameraFrame.resolvesPerspective(for: layer),
              (layer.colorBlendMode ?? 0) == 0 else { return false }
        return geometry.sourceMatchesOutputPixels(
            rasterOutputMVP: groups?.rasterModelViewProjection(
                forLayerID: layer.id, worldMVP: geometry.outputMVP) ?? geometry.outputMVP,
            viewportSize: groups?.enclosingTargetSize(forLayerID: layer.id) ?? viewportSize)
    }

    static func prepare(
        layer: SceneRenderDescriptor.Layer,
        unitModelMatrix: simd_float4x4,
        cameraFrame: SceneParticleCameraFrame,
        viewportSize: CGSize,
        groups: SceneCompositionGroupFrameRuntime?,
        memberLayerIDs: [Int]?,
        sourceTexture: MTLTexture,
        frameEpoch: UInt64,
        preparedMaterial: SceneResolvedMaterialRuntimeBridge.PreparedSourceMaterial?
    ) -> Self? {
        guard let utility = layer.utilityLayer,
              let geometry = SceneCaptureGeometryResolver.resolve(
                kind: utility.kind,
                layerMVP: cameraFrame.viewProjection(for: layer) * unitModelMatrix,
                viewportSize: groups?.enclosingTargetSize(forLayerID: layer.id) ?? viewportSize,
                captureMVP: groups?.rasterModelViewProjection(
                    forLayerID: layer.id,
                    worldMVP: cameraFrame.captureViewProjection(for: layer) * unitModelMatrix
                ) ?? (cameraFrame.captureViewProjection(for: layer) * unitModelMatrix),
                compositionSourceMemberLayerIDs: memberLayerIDs,
                authoredRenderSizeWH: layer.renderSizeWH,
                localCompositionSourceExtent: groups?.localSourceExtent(forRootID: layer.id),
                usesMaterialSource: utility.framebufferSource != nil
              ) else { return nil }
        guard utility.framebufferSource != nil else {
            return .init(geometry: geometry, material: nil)
        }
        guard case .capturedMain? = preparedMaterial?.outputDomain,
              let preparedMaterial,
              let source = SceneFrameTextureResource.sameFrameSceneBackground(
                consumerLayerID: layer.id, frameEpoch: frameEpoch, texture: sourceTexture
              ) else { return nil }
        return .init(geometry: geometry, material: .init(
            material: preparedMaterial, source: source, unitModelMatrix: unitModelMatrix
        ))
    }
}
