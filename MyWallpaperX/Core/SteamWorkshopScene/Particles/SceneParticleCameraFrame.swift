import CoreGraphics
import simd

struct SceneParticleCameraFrame: Sendable {
    static let perspectiveEyeDistance: Float = 1_000

    let orthographicViewProjection: simd_float4x4
    let perspectiveViewProjection: simd_float4x4
    let coverHalfExtents: SIMD2<Float>
    let cameraRight: SIMD3<Float>
    let cameraUp: SIMD3<Float>
    let cameraForward: SIMD3<Float>

    init(
        camera: SceneRenderDescriptor.CameraDescriptor,
        viewportSize: CGSize,
        cameraOrigin: SIMD3<Float> = .zero,
        cameraZoom: Float = 1
    ) {
        orthographicViewProjection = SceneCameraProjection.viewProjection(
            camera: camera,
            viewportSize: viewportSize,
            cameraOrigin: cameraOrigin,
            cameraZoom: cameraZoom
        )

        let orthoWidth = camera.orthoWidth ?? Float(viewportSize.width)
        let orthoHeight = camera.orthoHeight ?? Float(viewportSize.height)
        let hasValidViewport = viewportSize.width > 0 && viewportSize.height > 0
        let hasValidScene = orthoWidth.isFinite && orthoHeight.isFinite
            && orthoWidth > 0 && orthoHeight > 0

        guard hasValidViewport, hasValidScene else {
            perspectiveViewProjection = SceneMatrix.identity()
            coverHalfExtents = .zero
            cameraRight = SIMD3(1, 0, 0)
            cameraUp = SIMD3(0, 1, 0)
            cameraForward = SIMD3(0, 0, -1)
            return
        }

        coverHalfExtents = SceneCameraProjection.coverHalfExtents(
            orthoWidth: orthoWidth,
            orthoHeight: orthoHeight,
            viewportSize: viewportSize,
            zoom: cameraZoom
        )

        let safeOrigin = cameraOrigin.x.isFinite && cameraOrigin.y.isFinite
            && cameraOrigin.z.isFinite ? cameraOrigin : .zero
        let sceneCenter = SIMD3<Float>(
            orthoWidth * 0.5 + safeOrigin.x,
            orthoHeight * 0.5 + safeOrigin.y,
            0
        )
        let eyeDistance = safeOrigin.z > camera.nearZ
            ? safeOrigin.z : Self.perspectiveEyeDistance
        let eye = sceneCenter + SIMD3<Float>(0, 0, eyeDistance)
        cameraForward = Self.normalized(sceneCenter - eye, fallback: SIMD3(0, 0, -1))
        cameraRight = Self.normalized(
            simd_cross(cameraForward, SIMD3(0, 1, 0)),
            fallback: SIMD3(1, 0, 0)
        )
        cameraUp = Self.normalized(
            simd_cross(cameraRight, cameraForward),
            fallback: SIMD3(0, 1, 0)
        )

        let visibleHeight = coverHalfExtents.y * 2
        let fovY = 2 * atan(visibleHeight / (2 * eyeDistance))
        let aspect = Float(viewportSize.width / viewportSize.height)
        let nearZ = max(camera.nearZ, 0.001)
        let farZ = max(camera.farZ, nearZ + 0.001)
        let view = SceneMatrix.lookAt(eye: eye, center: sceneCenter, up: cameraUp)
        let projection = SceneMatrix.perspectiveRHMetal(
            fovYRadians: fovY,
            aspect: aspect,
            near: nearZ,
            far: farZ
        )
        // Scene particle coordinates use the same top-left screen convention as
        // the orthographic renderer, while SceneMatrix.perspectiveRHMetal is Y-up.
        perspectiveViewProjection = SceneMatrix.scale(SIMD3(1, -1, 1))
            * projection * view
    }

    func viewProjection(usesPerspective: Bool) -> simd_float4x4 {
        usesPerspective ? perspectiveViewProjection : orthographicViewProjection
    }

    func basis(
        for orientation: SceneParticleOrientation,
        fixedRight: SIMD3<Float> = SIMD3(1, 0, 0),
        fixedUp: SIMD3<Float> = SIMD3(0, -1, 0)
    ) -> SceneParticleOrientationBasis {
        let visualUp = -cameraUp
        return orientation.basis(
            cameraRight: cameraRight,
            cameraUp: visualUp,
            cameraForward: cameraForward,
            worldUp: visualUp,
            fixedRight: fixedRight,
            fixedUp: fixedUp
        )
    }

    static func particleLayerModel(
        worldFrame: simd_float4x4,
        parallaxOffset: SIMD2<Float>
    ) -> simd_float4x4 {
        SceneMatrix.translation(SIMD3(parallaxOffset.x, parallaxOffset.y, 0))
            * worldFrame
            * SceneMatrix.scale(SIMD3(1, -1, 1))
    }

    static func billboardScale(
        inheritedFrom layerModel: simd_float4x4
    ) -> SIMD2<Float> {
        SIMD2(
            axisLength(layerModel.columns.0),
            axisLength(layerModel.columns.1)
        )
    }

    private static func axisLength(_ column: SIMD4<Float>) -> Float {
        let length = simd_length(SIMD3(column.x, column.y, column.z))
        return length.isFinite ? length : 0
    }

    private static func normalized(
        _ value: SIMD3<Float>,
        fallback: SIMD3<Float>
    ) -> SIMD3<Float> {
        let lengthSquared = simd_length_squared(value)
        return lengthSquared.isFinite && lengthSquared > 1e-8
            ? value / sqrt(lengthSquared)
            : fallback
    }
}
