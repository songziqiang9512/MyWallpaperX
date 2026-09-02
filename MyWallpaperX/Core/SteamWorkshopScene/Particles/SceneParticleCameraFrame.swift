import CoreGraphics
import simd

struct SceneParticleCameraFrame: Sendable {
    static let perspectiveEyeDistance: Float = 1_000

    let orthographicViewProjection: simd_float4x4
    let perspectiveViewProjection: simd_float4x4
    let reverseDepthOrthographicViewProjection: simd_float4x4
    let reverseDepthPerspectiveViewProjection: simd_float4x4
    let coverHalfExtents: SIMD2<Float>
    let cameraRight: SIMD3<Float>
    let cameraUp: SIMD3<Float>
    let cameraForward: SIMD3<Float>
    let cameraOrigin: SIMD3<Float>

    init(
        camera: SceneRenderDescriptor.CameraDescriptor,
        viewportSize: CGSize,
        cameraOrigin: SIMD3<Float> = .zero,
        cameraZoom: Float = 1
    ) {
        let safeOrigin = cameraOrigin.x.isFinite && cameraOrigin.y.isFinite
            && cameraOrigin.z.isFinite ? cameraOrigin : .zero
        self.cameraOrigin = safeOrigin
        orthographicViewProjection = SceneCameraProjection.viewProjection(
            camera: camera,
            viewportSize: viewportSize,
            cameraOrigin: safeOrigin,
            cameraZoom: cameraZoom
        )
        reverseDepthOrthographicViewProjection = SceneMatrix.reversingDepth(
            orthographicViewProjection
        )

        let orthoWidth = camera.orthoWidth ?? Float(viewportSize.width)
        let orthoHeight = camera.orthoHeight ?? Float(viewportSize.height)
        let hasValidViewport = viewportSize.width > 0 && viewportSize.height > 0
        let hasValidScene = orthoWidth.isFinite && orthoHeight.isFinite
            && orthoWidth > 0 && orthoHeight > 0

        guard hasValidViewport, hasValidScene else {
            perspectiveViewProjection = SceneMatrix.identity()
            reverseDepthPerspectiveViewProjection = SceneMatrix.identity()
            coverHalfExtents = .zero
            cameraRight = SIMD3(1, 0, 0)
            cameraUp = SIMD3(0, 1, 0)
            cameraForward = SIMD3(0, 0, -1)
            return
        }

        let fittedHalfExtents = SceneCameraProjection.coverHalfExtents(
            orthoWidth: orthoWidth,
            orthoHeight: orthoHeight,
            viewportSize: viewportSize,
            zoom: cameraZoom
        )
        coverHalfExtents = fittedHalfExtents

        let sceneCenter = SIMD3<Float>(
            orthoWidth * 0.5 + safeOrigin.x,
            orthoHeight * 0.5 + safeOrigin.y,
            0
        )
        let authoredFOV = Self.authoredFOVRadians(
            camera.perspectiveOverrideFOVDegrees
        )
        let fittedEyeDistance = authoredFOV.map {
            fittedHalfExtents.y / tan($0 * 0.5)
        }
        let usesFittedAuthoredFOV = safeOrigin.z <= camera.nearZ
            && fittedEyeDistance != nil
        let eyeDistance = safeOrigin.z > camera.nearZ
            ? safeOrigin.z
            : fittedEyeDistance ?? Self.perspectiveEyeDistance
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

        let visibleHeight = fittedHalfExtents.y * 2
        let fovY = usesFittedAuthoredFOV
            ? authoredFOV!
            : 2 * atan(visibleHeight / (2 * eyeDistance))
        let aspect = Float(viewportSize.width / viewportSize.height)
        let nearZ = max(camera.nearZ, 0.001)
        // With an orthographic canvas and an authored perspective override,
        // the eye is fitted away from the z=0 canvas plane. Preserve the
        // authored world-depth reach instead of letting that eye translation
        // consume the far range and clip valid geometry behind the canvas.
        let farZ = max(
            camera.farZ + (usesFittedAuthoredFOV ? eyeDistance : 0),
            nearZ + 0.001
        )
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
        reverseDepthPerspectiveViewProjection = SceneMatrix.reversingDepth(
            perspectiveViewProjection
        )
    }

    func viewProjection(usesPerspective: Bool) -> simd_float4x4 {
        usesPerspective ? perspectiveViewProjection : orthographicViewProjection
    }

    func reverseDepthViewProjection(
        usesPerspective: Bool
    ) -> simd_float4x4 {
        usesPerspective
            ? reverseDepthPerspectiveViewProjection
            : reverseDepthOrthographicViewProjection
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

    private static func authoredFOVRadians(_ degrees: Float?) -> Float? {
        guard let degrees, degrees.isFinite,
              degrees > 0, degrees < 180 else { return nil }
        return degrees * .pi / 180
    }
}
