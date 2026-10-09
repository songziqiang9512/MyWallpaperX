import simd

extension SceneMetalRenderer {
    func imageModelMatrix(
        for layer: SceneRenderDescriptor.Layer,
        worldFramesByLayerID: [Int: simd_float4x4],
        renderSizeOverride: [Float]? = nil,
        textCenterOffsetY: Float = 0,
        parallaxMouseNormalized: SIMD2<Float>,
        configuration: SceneLayerParallax.Configuration,
        visibleHalfExtents: SIMD2<Float>,
        usesPerspective: Bool
    ) -> simd_float4x4 {
        let size = SIMD2(renderSizeOverride ?? layer.renderSizeWH ?? [], fill: 0)
        // Orthographic scene coordinates are Y-down, while native perspective
        // layers are authored in a Y-up world. Keep the shared quad/UV layout
        // unchanged and select only the world-space card orientation here.
        let sizeScale = SceneMatrix.scale(SIMD3(
            size.x,
            size.y * SceneCameraProjection.imageCardYDirection(
                usesPerspective: usesPerspective,
                sceneOrthoHeight: renderDescriptor.camera.orthoHeight
            ),
            1
        ))
        let world = worldFramesByLayerID[layer.id] ?? SceneMatrix.identity()
        let parallax = parallaxOffset(
            for: layer,
            worldFramesByLayerID: worldFramesByLayerID,
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
        // Only a published text raster carries the decoration border. Queries
        // using authored geometry (including content hit boxes) keep its pivot.
        let textBorder = renderSizeOverride == nil ? 0 : (layer.textStyle?.decorationInset ?? 0)
        let pivot = layer.contentKind == "text"
            ? SceneTextLayerPivot.unitOffset(
                horizontal: layer.textStyle?.horizontalAlignment,
                vertical: layer.textStyle?.verticalAlignment,
                renderSize: size,
                padding: (layer.textStyle?.padding ?? 0) + textBorder,
                centerOffsetY: textCenterOffsetY
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
        worldFramesByLayerID: [Int: simd_float4x4],
        parallaxMouseNormalized: SIMD2<Float>,
        configuration: SceneLayerParallax.Configuration
    ) -> simd_float4x4 {
        let world = worldFramesByLayerID[layer.id] ?? SceneMatrix.identity()
        let parallax = parallaxOffset(
            for: layer,
            worldFramesByLayerID: worldFramesByLayerID,
            mouseNormalized: parallaxMouseNormalized,
            configuration: configuration
        )
        return SceneParticleCameraFrame.particleLayerModel(
            worldFrame: world,
            parallaxOffset: parallax
        )
    }

    /// Puppet vertices are already expressed in authored model pixels. Apply
    /// the layer/world transform and coordinate-system orientation exactly
    /// once; unlike image quads, no render-size scale belongs in this matrix.
    func geometryModelMatrix(
        for layer: SceneRenderDescriptor.Layer,
        worldFramesByLayerID: [Int: simd_float4x4],
        authoredSize: SIMD2<Float>,
        parallaxMouseNormalized: SIMD2<Float>,
        configuration: SceneLayerParallax.Configuration,
        visibleHalfExtents: SIMD2<Float>,
        usesPerspective: Bool
    ) -> simd_float4x4 {
        let world = worldFramesByLayerID[layer.id] ?? SceneMatrix.identity()
        let parallax = parallaxOffset(
            for: layer,
            worldFramesByLayerID: worldFramesByLayerID,
            mouseNormalized: parallaxMouseNormalized,
            configuration: configuration
        )
        let screenAnchor = SceneLayerScreenAnchor.offset(
            anchor: layer.textStyle?.screenAnchor,
            orthoSize: configuration.orthoSize,
            visibleHalfExtents: visibleHalfExtents
        )
        let unitPivot = SceneImageLayerPivot.unitOffset(
            alignment: layer.imageAlignment
        )
        let localPivot = SIMD3(
            authoredSize.x * unitPivot.x,
            authoredSize.y * unitPivot.y,
            0
        )
        let yDirection = SceneCameraProjection.imageCardYDirection(
            usesPerspective: usesPerspective,
            sceneOrthoHeight: renderDescriptor.camera.orthoHeight
        )
        let shift = parallax + screenAnchor
        return SceneMatrix.translation(SIMD3(shift.x, shift.y, 0))
            * world
            * SceneMatrix.scale(SIMD3(1, yDirection, 1))
            * SceneMatrix.translation(localPivot)
    }

    func directDrawOutputModelMatrix(
        for layer: SceneRenderDescriptor.Layer,
        worldFramesByLayerID: [Int: simd_float4x4],
        parallaxMouseNormalized: SIMD2<Float>,
        configuration: SceneLayerParallax.Configuration
    ) -> simd_float4x4? {
        let world = worldFramesByLayerID[layer.id] ?? SceneMatrix.identity()
        let parallax = parallaxOffset(
            for: layer,
            worldFramesByLayerID: worldFramesByLayerID,
            mouseNormalized: parallaxMouseNormalized,
            configuration: configuration
        )
        return SceneDirectDrawOutputGeometry.modelMatrix(
            worldFrame: world,
            parallaxOffset: parallax,
            canvasSize: configuration.orthoSize
        )
    }

    private func parallaxOffset(
        for layer: SceneRenderDescriptor.Layer,
        worldFramesByLayerID: [Int: simd_float4x4],
        mouseNormalized: SIMD2<Float>,
        configuration: SceneLayerParallax.Configuration
    ) -> SIMD2<Float> {
        guard let resolution = parallaxByLayerID[layer.id],
              let sourceFrame = worldFramesByLayerID[resolution.sourceLayerID]
        else { return .zero }
        // Depth and camera-relative position belong to the same inherited
        // source. Using each child's position separates authored pieces even
        // when every member inherits one parent's parallax.
        return SceneLayerParallax.offset(
            resolution: resolution,
            configuration: configuration,
            layerPosition: SIMD2(sourceFrame.columns.3.x, sourceFrame.columns.3.y),
            mouseNormalized: mouseNormalized
        )
    }

}
