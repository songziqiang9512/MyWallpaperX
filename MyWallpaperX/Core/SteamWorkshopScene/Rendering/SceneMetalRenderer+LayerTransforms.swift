import simd

extension SceneMetalRenderer {
    func imageModelMatrix(
        for layer: SceneRenderDescriptor.Layer,
        renderSizeOverride: [Float]? = nil,
        parallaxMouseNormalized: SIMD2<Float>,
        configuration: SceneLayerParallax.Configuration,
        visibleHalfExtents: SIMD2<Float>
    ) -> simd_float4x4 {
        let size = SIMD2(renderSizeOverride ?? layer.renderSizeWH ?? [], fill: 0)
        let sizeScale = SceneMatrix.scale(SIMD3(size.x, -size.y, 1))
        let world = worldFramesByLayerID[layer.id] ?? SceneMatrix.identity()
        let parallax = parallaxOffset(
            for: layer,
            worldFrame: world,
            mouseNormalized: parallaxMouseNormalized,
            configuration: configuration
        )
        // 作者 `anchor` 只出现在 text layer 上，所以从 textStyle 取。
        let screenAnchor = SceneLayerScreenAnchor.offset(
            anchor: layer.textStyle?.screenAnchor,
            orthoSize: configuration.orthoSize,
            visibleHalfExtents: visibleHalfExtents
        )
        // image/solid 的 `alignment` 与 text 的 horizontal/vertical alignment 都会定义
        // origin 落在哪条 quad 边上，但它们来自两套作者字段，不能互相代替。
        let pivot = layer.contentKind == "text"
            ? SceneTextLayerPivot.unitOffset(
                horizontal: layer.textStyle?.horizontalAlignment,
                vertical: layer.textStyle?.verticalAlignment
            )
            : SceneImageLayerPivot.unitOffset(alignment: layer.imageAlignment)
        let shift = parallax + screenAnchor
        return SceneMatrix.translation(SIMD3(shift.x, shift.y, 0))
            * world
            * sizeScale
            * SceneMatrix.translation(SIMD3(pivot.x, pivot.y, 0))
    }

    func particleModelMatrix(
        for layer: SceneRenderDescriptor.Layer,
        parallaxMouseNormalized: SIMD2<Float>,
        configuration: SceneLayerParallax.Configuration
    ) -> simd_float4x4 {
        let world = worldFramesByLayerID[layer.id] ?? SceneMatrix.identity()
        let parallax = parallaxOffset(
            for: layer,
            worldFrame: world,
            mouseNormalized: parallaxMouseNormalized,
            configuration: configuration
        )
        return SceneParticleCameraFrame.particleLayerModel(
            worldFrame: world,
            parallaxOffset: parallax
        )
    }

    func lightShaftsModelMatrix(
        for layer: SceneRenderDescriptor.Layer,
        parallaxMouseNormalized: SIMD2<Float>,
        configuration: SceneLayerParallax.Configuration
    ) -> simd_float4x4? {
        let world = worldFramesByLayerID[layer.id] ?? SceneMatrix.identity()
        let parallax = parallaxOffset(
            for: layer,
            worldFrame: world,
            mouseNormalized: parallaxMouseNormalized,
            configuration: configuration
        )
        return SceneLightShaftsQuadGeometry.modelMatrix(
            worldFrame: world,
            parallaxOffset: parallax,
            canvasSize: configuration.orthoSize
        )
    }

    private func parallaxOffset(
        for layer: SceneRenderDescriptor.Layer,
        worldFrame: simd_float4x4,
        mouseNormalized: SIMD2<Float>,
        configuration: SceneLayerParallax.Configuration
    ) -> SIMD2<Float> {
        SceneLayerParallax.offset(
            resolution: parallaxByLayerID[layer.id],
            configuration: configuration,
            layerPosition: SIMD2(worldFrame.columns.3.x, worldFrame.columns.3.y),
            mouseNormalized: mouseNormalized
        )
    }

    func particleBasis(
        for batch: SceneParticleDrawBatch,
        layerModel: simd_float4x4,
        cameraFrame: SceneParticleCameraFrame
    ) -> SceneParticleOrientationBasis {
        guard batch.orientation.isFixed else {
            return cameraFrame.basis(for: batch.orientation)
        }
        let vectors = batch.orientation.fixedBasisVectors(
            axis: batch.orientationAxis ?? SIMD3<Float>(0, 0, 1),
            layerModel: layerModel
        )
        return cameraFrame.basis(
            for: batch.orientation,
            fixedRight: vectors.right,
            fixedUp: vectors.up
        )
    }
}
