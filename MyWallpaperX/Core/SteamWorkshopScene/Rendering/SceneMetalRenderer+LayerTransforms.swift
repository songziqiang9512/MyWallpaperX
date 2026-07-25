import simd

extension SceneMetalRenderer {
    func imageModelMatrix(
        for layer: SceneRenderDescriptor.Layer,
        parallaxMouseNormalized: SIMD2<Float>,
        configuration: SceneLayerParallax.Configuration,
        visibleHalfExtents: SIMD2<Float>
    ) -> simd_float4x4 {
        let size = SIMD2(layer.renderSizeWH ?? [], fill: 0)
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
            cameraEyeOffset: configuration.cameraEyeOffset,
            visibleHalfExtents: visibleHalfExtents
        )
        let shift = parallax + screenAnchor
        // 作者 text layer 的对齐同时是 quad pivot：origin 落在对齐命名的那条边上，
        // 放在 sizeScale 之后才能跟着作者 size、layer scale 缩放并留在旋转内部。
        let pivot = SceneTextLayerPivot.unitOffset(
            horizontal: layer.textStyle?.horizontalAlignment,
            vertical: layer.textStyle?.verticalAlignment
        )
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
        guard batch.orientation == .fixed else {
            return cameraFrame.basis(for: batch.orientation)
        }
        let rawAxis = batch.orientationAxis ?? SIMD3<Float>(0, 0, 1)
        let axisLength = simd_length_squared(rawAxis)
        let normal = axisLength.isFinite && axisLength > 1e-8
            ? rawAxis / sqrt(axisLength)
            : SIMD3<Float>(0, 0, 1)
        let reference = abs(normal.y) < 0.999 ? SIMD3<Float>(0, 1, 0) : SIMD3(1, 0, 0)
        let localRight = simd_normalize(simd_cross(reference, normal))
        let localUp = simd_normalize(simd_cross(normal, localRight))
        let transformedRight = layerModel * SIMD4(localRight.x, localRight.y, localRight.z, 0)
        let transformedUp = layerModel * SIMD4(localUp.x, localUp.y, localUp.z, 0)
        return cameraFrame.basis(
            for: batch.orientation,
            fixedRight: SIMD3(transformedRight.x, transformedRight.y, transformedRight.z),
            fixedUp: SIMD3(transformedUp.x, transformedUp.y, transformedUp.z)
        )
    }
}
