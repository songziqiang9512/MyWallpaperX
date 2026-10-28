import CoreGraphics
import simd

nonisolated struct SceneParticleCameraFrame: Sendable {
    static let perspectiveEyeDistance: Float = 1_000
    static let orthographicCanvasDefaultFOVDegrees: Float = 95

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
    private let orthographicViewBasis: SceneParticleOrientationBasis
    let perspectiveEyePosition: SIMD3<Float>
    let defaultsToPerspective: Bool
    // Shares the immutable frame value payload; no per-camera dictionary copy.
    private let dynamicValues: SceneDynamicSnapshot?
    /// Native SceneScript polling uses the far-plane point, not a layer hit.
    /// Keep its extent with the camera that owns the render projection.
    private let nativeFarPlane: SIMD3<Float>?

    init(
        camera: SceneRenderDescriptor.CameraDescriptor,
        viewportSize: CGSize,
        cameraOrigin: SIMD3<Float> = .zero,
        cameraZoom: Float = 1,
        staticEye: SIMD3<Float>? = nil,
        staticCenter: SIMD3<Float>? = nil,
        staticUp: SIMD3<Float>? = nil,
        nativePerspectiveOverride: NativePerspectiveOverride? = nil,
        dynamicValues: SceneDynamicSnapshot? = nil
    ) {
        self.dynamicValues = dynamicValues
        let safeOrigin = cameraOrigin.x.isFinite && cameraOrigin.y.isFinite
            && cameraOrigin.z.isFinite ? cameraOrigin : .zero
        let isCanvas = camera.orthoWidth != nil || camera.orthoHeight != nil
        let baseEye = staticEye ?? .zero
        let baseCenter = staticCenter ?? SIMD3(0, 0, -1)
        let baseUp = staticUp ?? SIMD3(0, 1, 0)
        let staticView: simd_float4x4?
        if isCanvas && (baseEye != .zero || baseCenter != SIMD3(0, 0, -1)
            || baseUp != SIMD3(0, 1, 0)) {
            let forward = Self.normalized(baseCenter - baseEye, fallback: .zero)
            let right = Self.normalized(simd_cross(forward, baseUp), fallback: .zero)
            staticView = simd_length_squared(forward) > 0 && simd_length_squared(right) > 0
                ? SceneMatrix.lookAt(eye: baseEye, center: baseCenter, up: baseUp) : nil
        } else { staticView = nil }
        let staticWorld = staticView.map(simd_inverse)
        if let staticView, let staticWorld {
            let canvasCenter = SIMD3<Float>(
                (camera.orthoWidth ?? Float(viewportSize.width)) * 0.5,
                (camera.orthoHeight ?? Float(viewportSize.height)) * 0.5, 0)
            let worldCenter = staticWorld * SIMD4(canvasCenter + safeOrigin, 1)
            self.cameraOrigin = SIMD3(worldCenter.x, worldCenter.y, worldCenter.z) - canvasCenter
            orthographicViewBasis = SceneParticleOrientationBasis(
                right: SIMD3(staticView.columns.0.x, staticView.columns.1.x, staticView.columns.2.x),
                up: -SIMD3(staticView.columns.0.y, staticView.columns.1.y, staticView.columns.2.y))
        } else {
            self.cameraOrigin = safeOrigin
            orthographicViewBasis = SceneParticleOrientationBasis(
                right: SIMD3(1, 0, 0), up: SIMD3(0, -1, 0))
        }
        orthographicViewProjection = SceneCameraProjection.viewProjection(
            camera: camera,
            viewportSize: viewportSize,
            cameraOrigin: safeOrigin,
            cameraZoom: cameraZoom,
            staticView: staticView
        )
        reverseDepthOrthographicViewProjection = SceneMatrix.reversingDepth(
            orthographicViewProjection
        )

        let hasValidViewport = viewportSize.width > 0 && viewportSize.height > 0
        if hasValidViewport,
           let native = Self.nativePerspectiveCamera(
               camera,
               override: nativePerspectiveOverride,
               staticEye: staticEye, staticCenter: staticCenter, staticUp: staticUp
           ) {
            let origin = safeOrigin
            let eye = native.eye + origin
            let center = native.center + origin
            let safeZoom = cameraZoom.isFinite && cameraZoom > 0
                ? cameraZoom : 1
            let fovY = 2 * atan(tan(native.fovY * 0.5) / safeZoom)
            let aspect = Float(viewportSize.width / viewportSize.height)
            let farHalfHeight = camera.farZ * tan(fovY * 0.5)
            nativeFarPlane = camera.nearZ.isFinite && camera.nearZ > 0
                && camera.farZ.isFinite && camera.farZ > camera.nearZ
                ? SIMD3(farHalfHeight * aspect, farHalfHeight, camera.farZ)
                : nil
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

        nativeFarPlane = nil
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
        // Ordinary canvas omission consumes the same fitted camera as explicit
        // 95 (own official black-box profiles). Invalid explicit values retain
        // the existing eye-distance fallback; native/partial cameras do not
        // acquire a canvas default here.
        let perspectiveFOVDegrees = camera.perspectiveOverrideFOVDegrees
            ?? (camera.orthoWidth != nil && camera.orthoHeight != nil
                ? Self.orthographicCanvasDefaultFOVDegrees : nil)
        let authoredFOV = Self.authoredFOVRadians(perspectiveFOVDegrees)
        let fittedEyeDistance = authoredFOV.map {
            fittedHalfExtents.y / tan($0 * 0.5)
        }
        let usesFittedAuthoredFOV = safeOrigin.z <= camera.nearZ
            && fittedEyeDistance != nil
        let eyeDistance = safeOrigin.z > camera.nearZ
            ? safeOrigin.z
            : fittedEyeDistance ?? Self.perspectiveEyeDistance
        let eye = sceneCenter + SIMD3<Float>(0, 0, eyeDistance)
        if let staticWorld {
            let worldEye = staticWorld * SIMD4(eye, 1)
            perspectiveEyePosition = SIMD3(worldEye.x, worldEye.y, worldEye.z)
        } else { perspectiveEyePosition = eye }
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
        let canvasView = SceneMatrix.lookAt(eye: eye, center: sceneCenter, up: SIMD3(0, 1, 0))
        let view = staticView.map { canvasView * $0 } ?? canvasView
        cameraRight = SIMD3(view.columns.0.x, view.columns.1.x, view.columns.2.x)
        cameraUp = SIMD3(view.columns.0.y, view.columns.1.y, view.columns.2.y)
        cameraForward = -SIMD3(view.columns.0.z, view.columns.1.z, view.columns.2.z)
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

    /// Evaluate the same native camera frustum analytically: inverting its
    /// Float depth matrix loses far-plane precision for large far/near ratios.
    /// Preserve outside positions so captured drags remain continuous.
    func nativeCursorWorldPosition(_ normalized: SIMD2<Float>) -> SIMD3<Float>? {
        guard let plane = nativeFarPlane,
              normalized.x.isFinite, normalized.y.isFinite else { return nil }
        let point = perspectiveEyePosition + cameraForward * plane.z
            + cameraRight * (normalized.x * plane.x)
            + cameraUp * (normalized.y * plane.y)
        guard point.x.isFinite, point.y.isFinite, point.z.isFinite else { return nil }
        return point
    }

    /// xyz is an eye (w=1) or the parallel toward-viewer direction (w=0).
    /// Orthographic layers keep the canvas view, even in a native camera scene.
    func materialView(usesPerspective: Bool) -> SIMD4<Float> {
        usesPerspective ? SIMD4(perspectiveEyePosition, 1)
            : SIMD4(-simd_cross(orthographicViewBasis.right, orthographicViewBasis.up), 0)
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

    /// Local composition captures may replay through perspective. Group and
    /// other utility targets retain the screen-space policy; native-camera
    /// composition capture is not part of this profile.
    func resolvesPerspective(for layer: SceneRenderDescriptor.Layer) -> Bool {
        if layer.hasFramebufferMaterialSource { return defaultsToPerspective }
        if layer.utilityLayer != nil,
           defaultsToPerspective || !layer.hasPerspectiveGeometryConsumer { return false }
        if let resolved = dynamicValues?[.layer(layerID: layer.id, field: .perspective)],
           resolved.source != .authored, case let .bool(value) = resolved.value {
            return value
        }
        return resolvesPerspective(layerOverride: layer.usesPerspective)
    }

    func viewProjection(for layer: SceneRenderDescriptor.Layer) -> simd_float4x4 {
        viewProjection(usesPerspective: resolvesPerspective(for: layer))
    }

    /// Capture the same flat local background before replaying its texture
    /// through the output projection. Ordinary image/utility routes agree.
    func captureViewProjection(for layer: SceneRenderDescriptor.Layer) -> simd_float4x4 {
        if layer.hasFramebufferMaterialSource { return viewProjection(for: layer) }
        if layer.utilityLayer != nil, layer.hasPerspectiveGeometryConsumer {
            return orthographicViewProjection
        }
        return viewProjection(for: layer)
    }

    /// Resolve a prepared particle batch through the existing camera and basis.
    /// Other geometry profiles retain their current coordinate contract.
    func particleUniforms(
        layerModel: simd_float4x4,
        orientation: SceneParticleOrientation,
        orientationAxis: SIMD3<Float>?,
        usesPerspective: Bool,
        usesSceneCamera: Bool,
        inheritsNativeSceneCamera: Bool = false,
        layerUsesPerspective: Bool = false,
        viewportSize: SIMD2<Float>,
        sizeIsWorldSpace: Bool
    ) -> SceneParticleLayerUniforms {
        let nativeSprite = defaultsToPerspective && usesSceneCamera
            && (orientation == .screen || orientation == .worldScreen)
        // Root RopeTrail inherits only the native scene default. A definition's
        // explicit perspective bit keeps its previous projection/basis path.
        let nativeRope = defaultsToPerspective && inheritsNativeSceneCamera
            && !usesPerspective && layerUsesPerspective
        let nativeCoordinates = nativeSprite || nativeRope
        // The incoming particle model includes the canvas Y conversion.
        // Native geometry is authored Y-up, so remove that conversion
        // before both its center and its local billboard axes consume it.
        let model = nativeCoordinates
            ? layerModel * SceneMatrix.scale(SIMD3(1, -1, 1)) : layerModel
        let selectedPerspective = usesPerspective || nativeCoordinates
        // The orthographic projection is canvas-aligned even when the scene
        // also owns a tilted native camera. View axes must describe this VP,
        // independently of the particle's authored geometry orientation.
        let viewBasis = selectedPerspective
            ? basis(for: .screen, nativeSpriteCoordinates: nativeCoordinates)
            : orthographicViewBasis
        return SceneParticleLayerUniforms(
            viewProjection: viewProjection(usesPerspective: selectedPerspective),
            layerModel: model,
            basis: basis(for: orientation, layerModel: model,
                         orientationAxis: orientationAxis ?? SIMD3(0, 0, 1),
                         nativeSpriteCoordinates: nativeCoordinates),
            viewportSize: viewportSize,
            sizeIsWorldSpace: sizeIsWorldSpace,
            viewBasis: viewBasis
        )
    }

    func basis(
        for orientation: SceneParticleOrientation,
        fixedRight: SIMD3<Float> = SIMD3(1, 0, 0),
        fixedUp: SIMD3<Float> = SIMD3(0, -1, 0),
        layerModel: simd_float4x4? = nil,
        orientationAxis: SIMD3<Float> = SIMD3(0, 0, 1),
        nativeSpriteCoordinates: Bool = false
    ) -> SceneParticleOrientationBasis {
        let yDirection: Float = nativeSpriteCoordinates ? 1 : -1
        let visualUp = cameraUp * yDirection
        let uprightUp: SIMD3<Float>
        if orientation == .upright, let layerModel {
            // The particle layer model already converts authored Y to the
            // renderer convention. Keep this system axis independent of roll.
            uprightUp = SIMD3(layerModel.columns.1.x,
                              layerModel.columns.1.y, layerModel.columns.1.z)
        } else {
            uprightUp = SIMD3(0, -1, 0)
        }
        let fixed: (right: SIMD3<Float>, up: SIMD3<Float>, forward: SIMD3<Float>)
        if orientation.isFixed, let layerModel {
            fixed = orientation.fixedBasisVectors(axis: orientationAxis, layerModel: layerModel)
        } else {
            fixed = (fixedRight, fixedUp, simd_cross(fixedRight, fixedUp))
        }
        var basis = orientation.basis(
            cameraRight: cameraRight,
            cameraUp: visualUp,
            cameraForward: cameraForward,
            worldUp: uprightUp,
            fixedRight: fixed.right,
            fixedUp: fixed.up
        )
        if orientation == .screen, let layerModel {
            // Billboard axes are formed in the particle system's local frame.
            // Carry its transform through to the card, just as for its center.
            // Undo the authored Y conversion before applying that model.
            let linear = simd_float3x3(
                SIMD3(layerModel.columns.0.x, layerModel.columns.0.y, layerModel.columns.0.z),
                SIMD3(layerModel.columns.1.x, layerModel.columns.1.y, layerModel.columns.1.z) * yDirection,
                SIMD3(layerModel.columns.2.x, layerModel.columns.2.y, layerModel.columns.2.z)
            )
            let geometry = linear * simd_float3x3(
                basis.right, basis.up, simd_cross(basis.right, basis.up)
            )
            let localRight = basis.right * SIMD3<Float>(1, yDirection, 1)
            let localUp = basis.up * SIMD3<Float>(1, yDirection, 1)
            let localTrailNormal = simd_cross(localRight, localUp)
            basis = SceneParticleOrientation.fixed.basis(
                cameraRight: cameraRight, cameraUp: visualUp, cameraForward: cameraForward,
                fixedRight: geometry.columns.0, fixedUp: geometry.columns.1
            )
            basis.localGeometry = geometry
            basis.localTrailNormal = localTrailNormal
        }
        if orientation == .fixed, layerModel != nil {
            basis.localGeometry = simd_float3x3(fixed.right, fixed.up, fixed.forward)
            basis.localTrailNormal = SceneParticleOrientationBasis.normalized(
                orientationAxis, fallback: SIMD3(0, 0, 1)
            )
        }
        return basis
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

    /// Catalog defaults use the same native-camera admission as frame rendering.
    static func usesNativePerspective(
        camera: SceneRenderDescriptor.CameraDescriptor,
        nativePerspectiveOverride: NativePerspectiveOverride? = nil
    ) -> Bool {
        nativePerspectiveCamera(camera, override: nativePerspectiveOverride) != nil
    }

    static func acceptsNativePerspectiveProjection(
        camera: SceneRenderDescriptor.CameraDescriptor
    ) -> Bool {
        camera.orthoWidth == nil && camera.orthoHeight == nil
            && camera.nearZ.isFinite && camera.nearZ > 0
            && camera.farZ.isFinite && camera.farZ > camera.nearZ
    }

    private static func nativePerspectiveCamera(
        _ camera: SceneRenderDescriptor.CameraDescriptor,
        override: NativePerspectiveOverride?,
        staticEye: SIMD3<Float>? = nil,
        staticCenter: SIMD3<Float>? = nil,
        staticUp: SIMD3<Float>? = nil
    ) -> NativePerspectiveCamera? {
        guard acceptsNativePerspectiveProjection(camera: camera) else {
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
            eye = staticEye ?? fallbackEye
            center = staticCenter ?? fallbackCenter
            authoredUp = staticUp ?? fallbackUp
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
