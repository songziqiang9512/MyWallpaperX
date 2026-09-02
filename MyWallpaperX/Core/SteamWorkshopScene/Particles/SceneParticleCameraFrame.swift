import CoreGraphics
import simd

struct SceneParticleCameraFrame: Sendable {
    static let perspectiveEyeDistance: Float = 1_000

    struct NativePerspectiveOverride: Sendable {
        let eye: SIMD3<Float>
        let center: SIMD3<Float>
        let up: SIMD3<Float>
        let fovDegrees: Float

        init?(
            worldFrame: simd_float4x4,
            fovDegrees: Float
        ) {
            let eye = SIMD3(
                worldFrame.columns.3.x,
                worldFrame.columns.3.y,
                worldFrame.columns.3.z
            )
            let localForward = -SIMD3(
                worldFrame.columns.2.x,
                worldFrame.columns.2.y,
                worldFrame.columns.2.z
            )
            let localUp = SIMD3(
                worldFrame.columns.1.x,
                worldFrame.columns.1.y,
                worldFrame.columns.1.z
            )
            guard eye.x.isFinite, eye.y.isFinite, eye.z.isFinite,
                  fovDegrees.isFinite, fovDegrees > 0, fovDegrees < 180 else {
                return nil
            }
            let forward = SceneParticleCameraFrame.normalized(
                localForward,
                fallback: .zero
            )
            let up = SceneParticleCameraFrame.normalized(
                localUp,
                fallback: .zero
            )
            guard simd_length_squared(forward) > 0,
                  simd_length_squared(up) > 0 else { return nil }
            self.eye = eye
            self.center = eye + forward
            self.up = up
            self.fovDegrees = fovDegrees
        }
    }

    let orthographicViewProjection: simd_float4x4
    let perspectiveViewProjection: simd_float4x4
    let reverseDepthOrthographicViewProjection: simd_float4x4
    let reverseDepthPerspectiveViewProjection: simd_float4x4
    let coverHalfExtents: SIMD2<Float>
    let cameraRight: SIMD3<Float>
    let cameraUp: SIMD3<Float>
    let cameraForward: SIMD3<Float>
    let cameraOrigin: SIMD3<Float>
    let perspectiveEyePosition: SIMD3<Float>
    let defaultsToPerspective: Bool

    init(
        camera: SceneRenderDescriptor.CameraDescriptor,
        viewportSize: CGSize,
        cameraOrigin: SIMD3<Float> = .zero,
        cameraZoom: Float = 1,
        nativePerspectiveOverride: NativePerspectiveOverride? = nil
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

        let hasValidViewport = viewportSize.width > 0 && viewportSize.height > 0
        if hasValidViewport,
           let native = Self.nativePerspectiveCamera(
               camera,
               override: nativePerspectiveOverride
           ) {
            let origin = safeOrigin
            let eye = native.eye + origin
            let center = native.center + origin
            let safeZoom = cameraZoom.isFinite && cameraZoom > 0
                ? cameraZoom : 1
            let fovY = 2 * atan(tan(native.fovY * 0.5) / safeZoom)
            let aspect = Float(viewportSize.width / viewportSize.height)
            let view = SceneMatrix.lookAt(
                eye: eye,
                center: center,
                up: native.up
            )
            let projection = SceneMatrix.perspectiveRHMetal(
                fovYRadians: fovY,
                aspect: aspect,
                near: camera.nearZ,
                far: camera.farZ
            )
            // Native perspective scenes are authored in a Y-up world. Metal's
            // viewport already maps positive clip Y to the visual top, so an
            // additional clip-space reflection would mirror every world-space
            // layer around the camera center.
            perspectiveViewProjection = projection * view
            reverseDepthPerspectiveViewProjection = SceneMatrix.reversingDepth(
                perspectiveViewProjection
            )
            let focusDistance = simd_distance(eye, center)
            let halfHeight = focusDistance * tan(fovY * 0.5)
            coverHalfExtents = SIMD2(halfHeight * aspect, halfHeight)
            cameraForward = native.forward
            cameraRight = native.right
            cameraUp = native.cameraUp
            perspectiveEyePosition = eye
            defaultsToPerspective = true
            return
        }

        let orthoWidth = camera.orthoWidth ?? Float(viewportSize.width)
        let orthoHeight = camera.orthoHeight ?? Float(viewportSize.height)
        let hasValidScene = orthoWidth.isFinite && orthoHeight.isFinite
            && orthoWidth > 0 && orthoHeight > 0

        guard hasValidViewport, hasValidScene else {
            perspectiveViewProjection = SceneMatrix.identity()
            reverseDepthPerspectiveViewProjection = SceneMatrix.identity()
            coverHalfExtents = .zero
            cameraRight = SIMD3(1, 0, 0)
            cameraUp = SIMD3(0, 1, 0)
            cameraForward = SIMD3(0, 0, -1)
            perspectiveEyePosition = safeOrigin
            defaultsToPerspective = false
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
        perspectiveEyePosition = eye
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
        defaultsToPerspective = false
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

    func resolvesPerspective(layerOverride: Bool?) -> Bool {
        layerOverride ?? defaultsToPerspective
    }

    func viewProjection(for layer: SceneRenderDescriptor.Layer) -> simd_float4x4 {
        guard layer.utilityLayer == nil else {
            return orthographicViewProjection
        }
        return viewProjection(
            usesPerspective: resolvesPerspective(
                layerOverride: layer.usesPerspective
            )
        )
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

    private struct NativePerspectiveCamera {
        let eye: SIMD3<Float>
        let center: SIMD3<Float>
        let up: SIMD3<Float>
        let forward: SIMD3<Float>
        let right: SIMD3<Float>
        let cameraUp: SIMD3<Float>
        let fovY: Float
    }

    private static func nativePerspectiveCamera(
        _ camera: SceneRenderDescriptor.CameraDescriptor,
        override: NativePerspectiveOverride?
    ) -> NativePerspectiveCamera? {
        guard camera.orthoWidth == nil, camera.orthoHeight == nil,
              camera.nearZ.isFinite, camera.nearZ > 0,
              camera.farZ.isFinite, camera.farZ > camera.nearZ else {
            return nil
        }
        let eye: SIMD3<Float>
        let center: SIMD3<Float>
        let authoredUp: SIMD3<Float>
        let fovDegrees: Float?
        if let override {
            eye = override.eye
            center = override.center
            authoredUp = override.up
            fovDegrees = override.fovDegrees
        } else {
            guard let fallbackEye = vector3(camera.eye),
                  let fallbackCenter = vector3(camera.center),
                  let fallbackUp = vector3(camera.up) else { return nil }
            eye = fallbackEye
            center = fallbackCenter
            authoredUp = fallbackUp
            fovDegrees = camera.fovDegrees
        }
        guard let fovY = authoredFOVRadians(fovDegrees) else { return nil }
        let forward = normalized(center - eye, fallback: .zero)
        let right = normalized(
            simd_cross(forward, authoredUp),
            fallback: .zero
        )
        guard simd_length_squared(forward) > 0,
              simd_length_squared(right) > 0 else {
            return nil
        }
        let cameraUp = normalized(
            simd_cross(right, forward),
            fallback: .zero
        )
        guard simd_length_squared(cameraUp) > 0 else { return nil }
        return NativePerspectiveCamera(
            eye: eye,
            center: center,
            up: cameraUp,
            forward: forward,
            right: right,
            cameraUp: cameraUp,
            fovY: fovY
        )
    }

    private static func vector3(_ values: [Float]) -> SIMD3<Float>? {
        guard values.count >= 3,
              values[0].isFinite, values[1].isFinite,
              values[2].isFinite else { return nil }
        return SIMD3(values[0], values[1], values[2])
    }
}
