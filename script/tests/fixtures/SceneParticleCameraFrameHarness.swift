import CoreGraphics
import Foundation
import simd

struct SceneRenderDescriptor {
    struct Layer {
        var id: Int = 0
        var cameraPath: CameraPath? = nil
        var visible = true
        var parentID: Int? = nil
        var displayScriptOwnership: DisplayScriptOwnership? = nil
        struct CameraPath { let camera: String; let fov: Double? }
        struct DisplayScriptOwnership {
            let visible: Bool
            let alpha: Bool
            var isEmpty: Bool { !visible && !alpha }
            var fields: [String] {
                (visible ? ["visible"] : []) + (alpha ? ["alpha"] : [])
            }
        }
        let utilityLayer: Bool?
        let usesPerspective: Bool?
        var hasPerspectiveGeometryConsumer = false
        var hasFramebufferMaterialSource = false
    }

    let camera: CameraDescriptor
    let renderOrderLayerIDs: [Int]
    var layers: [Layer] = []

    struct CameraDescriptor {
        let eye: [Float]
        let center: [Float]
        let up: [Float]
        let orthoWidth: Float?
        let orthoHeight: Float?
        let fovDegrees: Float?
        let perspectiveOverrideFOVDegrees: Float?
        let nearZ: Float
        let farZ: Float
    }
}

@main
enum Harness {
    static func main() throws {
        let camera = SceneRenderDescriptor.CameraDescriptor(
            eye: [0, 0, 0], center: [0, 0, -1], up: [0, 1, 0],
            orthoWidth: 1920, orthoHeight: 1080,
            fovDegrees: nil,
            perspectiveOverrideFOVDegrees: nil,
            nearZ: 0.01, farZ: 10_000
        )
        let viewport = CGSize(width: 1280, height: 832)
        let frame = SceneParticleCameraFrame(camera: camera, viewportSize: viewport)
        let authoredFOVCamera = SceneRenderDescriptor.CameraDescriptor(
            eye: [0, 0, 0], center: [0, 0, -1], up: [0, 1, 0],
            orthoWidth: 1920, orthoHeight: 1080,
            fovDegrees: nil,
            perspectiveOverrideFOVDegrees: 21,
            nearZ: 0.01, farZ: 10_000
        )
        let authoredFOVFrame = SceneParticleCameraFrame(
            camera: authoredFOVCamera,
            viewportSize: viewport
        )
        let dynamicOrigin = SIMD3<Float>(-100, 682, 500)
        let dynamicFrame = SceneParticleCameraFrame(
            camera: camera,
            viewportSize: viewport,
            cameraOrigin: dynamicOrigin,
            cameraZoom: 2.4
        )
        // The three own official profiles prove omission/95 output equality.
        // Cover resize, zoom and cursor round trips below are project regressions.
        func canvasCamera(_ size: SIMD2<Float>, fov: Float?, generalFOV: Float? = nil)
            -> SceneRenderDescriptor.CameraDescriptor {
            .init(eye: [0, 0, 0], center: [0, 0, -1], up: [0, 1, 0],
                  orthoWidth: size.x, orthoHeight: size.y,
                  fovDegrees: generalFOV, perspectiveOverrideFOVDegrees: fov,
                  nearZ: 0.01, farZ: 10_000)
        }
        let defaultProfiles: [(SIMD2<Float>, CGSize, Float)] = [
            (SIMD2(1210, 786), CGSize(width: 1210, height: 786), 1),
            (SIMD2(720, 786), CGSize(width: 720, height: 786), 1),
            (SIMD2(605, 393), CGSize(width: 605, height: 393), 0.5),
            (SIMD2(1210, 786), CGSize(width: 960, height: 960), 1),
            (SIMD2(1210, 786), CGSize(width: 1600, height: 600), 1),
        ]
        let defaultProjectionRows: [[String: Any]] = defaultProfiles.map { size, viewport, depthScale in
            let omitted = SceneParticleCameraFrame(camera: canvasCamera(size, fov: nil), viewportSize: viewport)
            let explicit = SceneParticleCameraFrame(camera: canvasCamera(size, fov: 95), viewportSize: viewport)
            let contrast = SceneParticleCameraFrame(camera: canvasCamera(size, fov: 50), viewportSize: viewport)
            let generalOnly = SceneParticleCameraFrame(camera: canvasCamera(size, fov: nil, generalFOV: 50), viewportSize: viewport)
            let card = SceneMatrix.translation(SIMD3(size.x * 0.62, size.y * 0.66, 120 * depthScale))
                * SceneMatrix.rotationX(.pi / 6) * SceneMatrix.rotationY(.pi / 4)
                * SceneMatrix.scale(SIMD3(157.3 * depthScale, -117.9 * depthScale, 1))
            let local = SIMD4<Float>(0.2, -0.1, 0, 1)
            let mvp = omitted.perspectiveViewProjection * card
            let clip = mvp * local
            let hit = SceneLayerCursorGeometry.layerPoint(
                mouseNormalized: SIMD2(clip.x, clip.y) / clip.w,
                modelViewProjection: mvp)
            let legacyFrame = SceneParticleCameraFrame(camera: canvasCamera(size, fov: 0), viewportSize: viewport)
            let legacyMVP = legacyFrame.perspectiveViewProjection * card
            let legacyClip = legacyMVP * local
            let legacyHit = SceneLayerCursorGeometry.layerPoint(
                mouseNormalized: SIMD2(legacyClip.x, legacyClip.y) / legacyClip.w,
                modelViewProjection: legacyMVP)
            let positive = SIMD4<Float>(size.x * 0.38, size.y * 0.66, 120 * depthScale, 1)
            let negative = SIMD4<Float>(size.x * 0.15, size.y * 0.66, -120 * depthScale, 1)
            let flat = SceneRenderDescriptor.Layer(utilityLayer: nil, usesPerspective: false)
            let utility = SceneRenderDescriptor.Layer(utilityLayer: true, usesPerspective: true)
            return [
                "eyeZ": omitted.perspectiveEyePosition.z,
                "halfHeight": omitted.coverHalfExtents.y,
                "omitted": [ndc(omitted.perspectiveViewProjection, positive), ndc(omitted.perspectiveViewProjection, negative), ndc(mvp, local)],
                "explicit95": [ndc(explicit.perspectiveViewProjection, positive), ndc(explicit.perspectiveViewProjection, negative), ndc(explicit.perspectiveViewProjection * card, local)],
                "explicit50": ndc(contrast.perspectiveViewProjection, positive),
                "flatUnchanged": omitted.viewProjection(for: flat) == contrast.viewProjection(for: flat),
                "utilityUnchanged": omitted.viewProjection(for: utility) == contrast.viewProjection(for: utility),
                "generalFOVKeepsCanvasPolicy": generalOnly.perspectiveViewProjection == omitted.perspectiveViewProjection,
                "cursorLocal": hit.map(vector3) as Any? ?? NSNull(),
                "legacyCursorLocal": legacyHit.map(vector3) as Any? ?? NSNull(),
                "requiredEffectProjection": SceneLayerCursorGeometry.effectTextureProjectionInverse(
                    inverseModelViewProjection: SceneLayerCursorGeometry.preciseInverseModelViewProjection(mvp),
                    required: true) != nil,
                "legacyRequiredEffectProjection": SceneLayerCursorGeometry.effectTextureProjectionInverse(
                    inverseModelViewProjection: SceneLayerCursorGeometry.preciseInverseModelViewProjection(legacyMVP),
                    required: true) != nil,
                "farNDC": ndc(omitted.perspectiveViewProjection, SIMD4(size.x * 0.5, size.y * 0.5, -10_000, 1))[2],
            ]
        }
        let ordinarySize = SIMD2<Float>(1210, 786)
        let ordinaryViewport = CGSize(width: 1210, height: 786)
        let invalidFOVRows = [Float.nan, .infinity, -1, 0, 180, 200].map { value in
            let invalid = SceneParticleCameraFrame(camera: canvasCamera(ordinarySize, fov: value), viewportSize: ordinaryViewport)
            return [invalid.perspectiveEyePosition.z,
                    ndc(invalid.perspectiveViewProjection, SIMD4<Float>(750.2, 518.76, 120, 1))[0]]
        }
        let dynamicFOVRows: [[String: Any]] = [SIMD3<Float>(-100, 682, 500), SIMD3(-12, 30, 0), SIMD3(4, -9, -10)].map { origin in
            let omitted = SceneParticleCameraFrame(camera: canvasCamera(ordinarySize, fov: nil),
                viewportSize: ordinaryViewport, cameraOrigin: origin, cameraZoom: 2.4)
            let explicit = SceneParticleCameraFrame(camera: canvasCamera(ordinarySize, fov: 95),
                viewportSize: ordinaryViewport, cameraOrigin: origin, cameraZoom: 2.4)
            return ["matchesExplicit": omitted.perspectiveViewProjection == explicit.perspectiveViewProjection,
                    "origin": vector3(omitted.cameraOrigin), "eyeZ": omitted.perspectiveEyePosition.z,
                    "halfHeight": omitted.coverHalfExtents.y,
                    "canvasCenter": ndc(omitted.perspectiveViewProjection,
                        SIMD4(ordinarySize.x * 0.5 + origin.x, ordinarySize.y * 0.5 + origin.y, 0, 1))]
        }
        func nativePolicyCamera(_ fov: Float?, override: Float?) -> SceneRenderDescriptor.CameraDescriptor {
            .init(eye: [0, 0, 10], center: [0, 0, 0], up: [0, 1, 0],
                  orthoWidth: nil, orthoHeight: nil, fovDegrees: fov,
                  perspectiveOverrideFOVDegrees: override, nearZ: 0.01, farZ: 10_000)
        }
        let nativePolicy = SceneParticleCameraFrame(camera: nativePolicyCamera(50, override: nil), viewportSize: ordinaryViewport)
        let nativePolicyWithOverride = SceneParticleCameraFrame(camera: nativePolicyCamera(50, override: 95), viewportSize: ordinaryViewport)
        let missingNativeFOV = SceneParticleCameraFrame(camera: nativePolicyCamera(nil, override: nil), viewportSize: ordinaryViewport)
        let missingNativeFOVWithOverride = SceneParticleCameraFrame(camera: nativePolicyCamera(nil, override: 95), viewportSize: ordinaryViewport)
        let partialCanvas = SceneParticleCameraFrame(camera: .init(
            eye: [0, 0, 0], center: [0, 0, -1], up: [0, 1, 0],
            orthoWidth: 1210, orthoHeight: nil, fovDegrees: nil,
            perspectiveOverrideFOVDegrees: nil, nearZ: 0.01, farZ: 10_000), viewportSize: ordinaryViewport)
        let center = SIMD4<Float>(960, 540, 0, 1)
        let edge = SIMD4<Float>(
            960 + frame.coverHalfExtents.x,
            540 + frame.coverHalfExtents.y,
            0,
            1
        )
        let dynamicCenter = SIMD4<Float>(
            960 + dynamicOrigin.x, 540 + dynamicOrigin.y, 0, 1
        )
        let dynamicEdge = SIMD4<Float>(
            dynamicCenter.x + dynamicFrame.coverHalfExtents.x,
            dynamicCenter.y + dynamicFrame.coverHalfExtents.y,
            0,
            1
        )

        let scaledWorld = SceneMatrix.translation(SIMD3(100, 200, 0))
            * SceneMatrix.rotationZ(.pi / 6)
            * SceneMatrix.scale(SIMD3(2, 3, 1))
        let layerModel = SceneParticleCameraFrame.particleLayerModel(
            worldFrame: scaledWorld,
            parallaxOffset: SIMD2(5, -7)
        )
        let worldSpaceFrame = SceneParticleWorldSpaceFrame(worldFrame: scaledWorld)!
        let localDirection = worldSpaceFrame.localDirection(SIMD3(12, -7, 0))
        let reprojectedDirection = scaledWorld * SIMD4<Float>(
            Float(localDirection.x), Float(localDirection.y), Float(localDirection.z), 0
        )
        // Camera parallax is a draw translation, including for a mirrored,
        // rotated, non-uniform parent frame. It must not change force basis.
        let authoredWorld = SceneMatrix.translation(SIMD3(120, 80, 0))
            * SceneMatrix.rotationZ(0.7) * SceneMatrix.scale(SIMD3(-2, 3, 1))
        let drawLeft = SceneParticleCameraFrame.particleLayerModel(
            worldFrame: authoredWorld, parallaxOffset: SIMD2(-35, 12))
        let drawRight = SceneParticleCameraFrame.particleLayerModel(
            worldFrame: authoredWorld, parallaxOffset: SIMD2(25, -8))
        let directionLeft = SceneParticleWorldSpaceFrame(worldFrame: drawLeft)!
            .localDirection(SIMD3(12, -7, 0))
        let directionRight = SceneParticleWorldSpaceFrame(worldFrame: drawRight)!
            .localDirection(SIMD3(12, -7, 0))
        let existingParticle = SIMD4<Float>(11, -9, 0, 1)
        let drawDelta = drawRight * existingParticle - drawLeft * existingParticle
        let eligibleWorldSpaceLayers = SceneParticleStaticWorldSpacePlan.eligibleLayerIDs(
            nodes: [
                .init(
                    id: 1, parentID: nil,
                    hasAuthoredTransformMotion: false
                ),
                .init(
                    id: 2, parentID: 1,
                    hasAuthoredTransformMotion: false
                ),
                .init(
                    id: 3, parentID: nil,
                    hasAuthoredTransformMotion: true
                ),
                .init(
                    id: 4, parentID: 3,
                    hasAuthoredTransformMotion: false
                ),
                .init(
                    id: 6, parentID: 7,
                    hasAuthoredTransformMotion: false
                ),
                .init(
                    id: 7, parentID: 6,
                    hasAuthoredTransformMotion: false
                ),
            ]
        ).sorted()
        let inheritedScale = SceneParticleCameraFrame.billboardScale(
            inheritedFrom: layerModel
        )
        let stationary = layerModel * SIMD4<Float>(0, 0, 0, 1)
        let falling = layerModel * SIMD4<Float>(0, -10, 0, 1)
        let stationaryNDC = ndc(frame.orthographicViewProjection, stationary)
        let fallingNDC = ndc(frame.orthographicViewProjection, falling)
        let screenBasis = frame.basis(for: .screen)
        let uprightBasis = frame.basis(for: .upright)
        let fixedBasis = frame.basis(for: .fixed)
        let sceneCenter = SIMD3<Float>(960, 540, 0)

        let nativeCamera = SceneRenderDescriptor.CameraDescriptor(
            eye: [-2.05772, 0.85240, 10.07242],
            center: [-1.83970, 0.51670, 9.15603],
            up: [0, 1, 0],
            orthoWidth: nil, orthoHeight: nil,
            fovDegrees: 50,
            perspectiveOverrideFOVDegrees: nil,
            nearZ: 0.01, farZ: 10_000
        )
        let nativeFrame = SceneParticleCameraFrame(
            camera: nativeCamera,
            viewportSize: viewport
        )
        let activeCameraWorld = SceneMatrix.translation(SIMD3(0, 0, 6))
        let activeCameraOverride = SceneParticleCameraFrame.NativePerspectiveOverride(
            worldFrame: activeCameraWorld,
            fovDegrees: 50
        )!
        let activeCameraFrame = SceneParticleCameraFrame(
            camera: nativeCamera,
            viewportSize: viewport,
            nativePerspectiveOverride: activeCameraOverride
        )
        let inheritedNativeLayer = SceneRenderDescriptor.Layer(
            utilityLayer: nil,
            usesPerspective: nil
        )
        let nativeUtilityLayer = SceneRenderDescriptor.Layer(
            utilityLayer: true,
            usesPerspective: nil
        )
        let explicitUtilityLayer = SceneRenderDescriptor.Layer(
            utilityLayer: true, usesPerspective: true
        )
        let nativeMaterialSourceLayer = SceneRenderDescriptor.Layer(
            utilityLayer: true, usesPerspective: true,
            hasFramebufferMaterialSource: true
        )
        let explicitImageLayer = SceneRenderDescriptor.Layer(
            utilityLayer: nil, usesPerspective: true
        )
        let nativeCenter = SIMD4<Float>(
            nativeCamera.center[0], nativeCamera.center[1],
            nativeCamera.center[2], 1
        )
        let nativeWorldUp = SIMD4<Float>(
            SIMD3(nativeCenter.x, nativeCenter.y, nativeCenter.z)
                + nativeFrame.cameraUp * 0.1,
            1
        )
        let nativeWorldDown = SIMD4<Float>(
            SIMD3(nativeCenter.x, nativeCenter.y, nativeCenter.z)
                - nativeFrame.cameraUp * 0.1,
            1
        )

        let invalidCamera = SceneRenderDescriptor.CameraDescriptor(
            eye: [], center: [], up: [], orthoWidth: 0, orthoHeight: 0,
            fovDegrees: nil,
            perspectiveOverrideFOVDegrees: nil,
            nearZ: 0, farZ: 0
        )
        let invalidFrame = SceneParticleCameraFrame(
            camera: invalidCamera,
            viewportSize: .zero
        )
        let nonfiniteOriginFrame = SceneParticleCameraFrame(
            camera: camera,
            viewportSize: viewport,
            cameraOrigin: SIMD3(.nan, 4, 5)
        )

        func pollingFrame(far: Float, eye: [Float] = [0, 0, 10],
                          center: [Float] = [0, 0, 0], zoom: Float = 1,
                          viewport: CGSize = CGSize(width: 2268, height: 1473)) -> SceneParticleCameraFrame {
            SceneParticleCameraFrame(camera: .init(
                eye: eye, center: center, up: [0, 1, 0],
                orthoWidth: nil, orthoHeight: nil, fovDegrees: 50,
                perspectiveOverrideFOVDegrees: nil, nearZ: 0.01, farZ: far
            ), viewportSize: viewport, cameraZoom: zoom)
        }
        let polling = pollingFrame(far: 10_000)
        let cursorSamples = [SIMD2<Float>(0, 1 / 1473), SIMD2(0.5, 1 / 1473)]
        let pollingValues = cursorSamples.map { vector3(polling.nativeCursorWorldPosition($0)!) }
        let pollingHalfFar = cursorSamples.map { vector3(pollingFrame(far: 5000).nativeCursorWorldPosition($0)!) }
        let rotatedPolling = pollingFrame(far: 5000, eye: [10, 2, 0], center: [0, 2, 0])

        let perspectiveTarget = SceneDynamicTarget.layer(layerID: 91, field: .perspective)
        let scriptedLayer = SceneRenderDescriptor.Layer(id: 91, utilityLayer: nil, usesPerspective: false)
        func perspectiveSnapshot(_ value: SceneDynamicValue, source: SceneDynamicSource = .sceneScript) -> SceneDynamicSnapshot {
            SceneDynamicSnapshotResolver().resolve(frameIndex: 1, generation: 1,
                definitions: [.init(target: perspectiveTarget, valueType: .bool, authoredValue: .bool(false))],
                sceneScriptValues: source == .sceneScript ? [perspectiveTarget: value] : [:]).snapshot
        }
        var scriptSnapshot = perspectiveSnapshot(.bool(true))
        let scriptedFrame = SceneParticleCameraFrame(camera: camera, viewportSize: viewport, dynamicValues: scriptSnapshot)
        scriptSnapshot = perspectiveSnapshot(.bool(false))
        let flatFrame = SceneParticleCameraFrame(camera: camera, viewportSize: viewport, dynamicValues: scriptSnapshot)
        let nativeFlatFrame = SceneParticleCameraFrame(camera: nativeCamera, viewportSize: viewport, dynamicValues: scriptSnapshot)
        let authoredSeed = perspectiveSnapshot(.bool(false), source: .authored)
        let nativeInheritedFrame = SceneParticleCameraFrame(camera: nativeCamera, viewportSize: viewport, dynamicValues: authoredSeed)
        let inheritedLayer = SceneRenderDescriptor.Layer(id: 91, utilityLayer: nil, usesPerspective: nil)
        let utilityOverride = SceneRenderDescriptor.Layer(id: 91, utilityLayer: true, usesPerspective: true)
        var composition = utilityOverride
        composition.hasPerspectiveGeometryConsumer = true
        let invalidSnapshot = perspectiveSnapshot(.scalar(1))
        let wrongTypedFrame = SceneParticleCameraFrame(camera: camera, viewportSize: viewport, dynamicValues: invalidSnapshot)
        let missingFOVCamera = SceneRenderDescriptor.CameraDescriptor(
            eye: [0, 0, 0], center: [0, 0, 0], up: [0, 1, 0],
            orthoWidth: nil, orthoHeight: nil, fovDegrees: nil,
            perspectiveOverrideFOVDegrees: nil, nearZ: 0.1, farZ: 5000
        )
        var cameraLayer = SceneRenderDescriptor.Layer(id: 7,
            cameraPath: .init(camera: "default", fov: 60),
            utilityLayer: nil, usesPerspective: nil)
        let cameraDescriptor = SceneRenderDescriptor(camera: missingFOVCamera, renderOrderLayerIDs: [7])
        let cameraWorld = SceneMatrix.translation(SIMD3<Float>(10, 20, 30))
        let selectedCamera = SceneParticleCameraFrame.nativePerspectiveOverride(
            descriptor: cameraDescriptor, layersByID: [7: cameraLayer],
            worldFrames: [7: cameraWorld], dynamicValues: .empty(frameIndex: 0))
        let layerCameraFrame = SceneParticleCameraFrame(camera: missingFOVCamera,
            viewportSize: viewport, nativePerspectiveOverride: selectedCamera)
        let layerCameraFlatFrame = SceneParticleCameraFrame(camera: missingFOVCamera,
            viewportSize: viewport, nativePerspectiveOverride: selectedCamera,
            dynamicValues: scriptSnapshot)
        cameraLayer.visible = false
        let hiddenCamera = SceneParticleCameraFrame.nativePerspectiveOverride(
            descriptor: cameraDescriptor, layersByID: [7: cameraLayer],
            worldFrames: [7: cameraWorld], dynamicValues: .empty(frameIndex: 0))
        let parentWorld = SceneMatrix.translation(SIMD3<Float>(1, 2, -8))
            * SceneMatrix.rotationZ(0.3) * SceneMatrix.scale(SIMD3(2, 0.5, 1))
        let ropeWorld = parentWorld * SceneMatrix.translation(SIMD3(0.2, -0.1, -3))
        let ropeModel = SceneParticleCameraFrame.particleLayerModel(
            worldFrame: ropeWorld, parallaxOffset: .zero)
        func ropeUniforms(_ camera: SceneParticleCameraFrame,
                          _ layer: SceneRenderDescriptor.Layer,
                          flag: Bool = false, eligible: Bool = true,
                          sprite: Bool = false) -> SceneParticleLayerUniforms {
            camera.particleUniforms(layerModel: ropeModel, orientation: .screen,
                orientationAxis: nil, usesPerspective: flag, usesSceneCamera: sprite,
                inheritsNativeSceneCamera: eligible,
                layerUsesPerspective: camera.resolvesPerspective(for: layer),
                viewportSize: SIMD2(Float(viewport.width), Float(viewport.height)),
                sizeIsWorldSpace: false)
        }
        func sameCoordinates(_ a: SceneParticleLayerUniforms,
                             _ b: SceneParticleLayerUniforms) -> Bool {
            a.viewProjection == b.viewProjection && a.layerModel == b.layerModel
                && a.basisRight == b.basisRight && a.basisUp == b.basisUp
                && a.viewRight == b.viewRight && a.viewUp == b.viewUp
        }
        let nativeRope = ropeUniforms(nativeFrame, inheritedLayer)
        let ropePolicy = [
            "nativeProjection": nativeRope.viewProjection == nativeFrame.perspectiveViewProjection,
            "parentWorldPreserved": nativeRope.layerModel == ropeWorld,
            "nativeViewUp": nativeRope.viewUp == SIMD4(nativeFrame.cameraUp, 0),
            "authoredSeedInherits": sameCoordinates(nativeRope, ropeUniforms(nativeInheritedFrame, inheritedLayer)),
            "staticFalseKeepsLegacy": sameCoordinates(ropeUniforms(nativeFrame, scriptedLayer),
                ropeUniforms(nativeFrame, scriptedLayer, eligible: false)),
            "typedFalseKeepsLegacy": sameCoordinates(ropeUniforms(nativeFlatFrame, inheritedLayer),
                ropeUniforms(nativeFlatFrame, inheritedLayer, eligible: false)),
            "flags4KeepsLegacy": sameCoordinates(ropeUniforms(nativeFrame, scriptedLayer, flag: true),
                ropeUniforms(nativeFrame, scriptedLayer, flag: true, eligible: false)),
            "orthoKeepsLegacy": sameCoordinates(ropeUniforms(frame, inheritedLayer),
                ropeUniforms(frame, inheritedLayer, eligible: false)),
            "canvasFlags4KeepsLegacy": sameCoordinates(ropeUniforms(frame, inheritedLayer, flag: true),
                ropeUniforms(frame, inheritedLayer, flag: true, eligible: false)),
            "spriteKeepsLegacy": sameCoordinates(ropeUniforms(nativeFlatFrame, inheritedLayer, sprite: true),
                ropeUniforms(nativeFlatFrame, inheritedLayer, eligible: false, sprite: true)),
            "ineligibleStaysFlat": ropeUniforms(nativeFrame, inheritedLayer, eligible: false).viewProjection
                == nativeFrame.orthographicViewProjection,
        ]
        let rolled = SceneParticleCameraFrame(camera: nativeCamera, viewportSize: viewport,
            nativePerspectiveOverride: .init(worldFrame: SceneMatrix.rotationX(.pi / 3)
                * SceneMatrix.rotationZ(.pi / 4), fovDegrees: 60))
        let axisCases: [(String, SceneParticleCameraFrame, Bool, Bool)] = [
            ("native-slant-flat", nativeFrame, false, false), ("native-roll-flat", rolled, false, false),
            ("native-inherited", rolled, false, true), ("native-flag4", rolled, true, false),
            ("canvas-flag4", frame, true, false), ("canvas-flat", frame, false, false)]
        let selectedVPAxes = axisCases.map { name, camera, flag, native -> [String: Any] in
            let uniforms = ropeUniforms(camera, native ? inheritedLayer : scriptedLayer, flag: flag)
            let perspective = flag || native
            let right = perspective ? camera.cameraRight : SIMD3<Float>(1, 0, 0)
            let up = perspective ? camera.cameraUp * (native ? 1 : -1) : SIMD3<Float>(0, -1, 0)
            let r = uniforms.viewProjection * uniforms.viewRight, u = uniforms.viewProjection * uniforms.viewUp
            let sprite = ropeUniforms(camera, scriptedLayer, flag: flag, eligible: false)
            let geometry = camera.basis(for: .screen, layerModel: sprite.layerModel).localGeometry!
            let upSign: Float = perspective && camera.defaultsToPerspective && !native ? -1 : 1
            return ["name": name, "axes": uniforms.viewRight == SIMD4(right, 0)
                && uniforms.viewUp == SIMD4(up, 0),
                "projection": uniforms.viewProjection == camera.viewProjection(usesPerspective: perspective),
                "plane": abs(r.z) < 0.00001 && abs(r.w) < 0.00001
                    && abs(u.z) < 0.00001 && abs(u.w) < 0.00001,
                "signedXY": r.x > 0 && abs(r.y) < 0.00001 && abs(u.x) < 0.00001 && u.y * upSign > 0,
                "spriteGeometry": sprite.spriteRight == SIMD4(geometry.columns.0, 0)
                    && sprite.spriteUp == SIMD4(geometry.columns.1, 0)
                    && sprite.spriteForward == SIMD4(geometry.columns.2, 0)]
        }
        let result: [String: Any] = [
            "staticCameraTransforms": staticCameraTransformChecks(),
            "nativeLayerSelection": nativeLayerSelectionChecks(camera: missingFOVCamera),
            "ropeCameraPolicy": ropePolicy,
            "selectedVPAxes": selectedVPAxes,
            "defaultProjectionRows": defaultProjectionRows,
            "invalidFOVRows": invalidFOVRows,
            "dynamicFOVRows": dynamicFOVRows,
            "nativeOverrideKeepsNativePolicy": nativePolicy.perspectiveViewProjection == nativePolicyWithOverride.perspectiveViewProjection,
            "missingNativeFOVKeepsFallback": !missingNativeFOV.defaultsToPerspective && missingNativeFOV.perspectiveEyePosition.z == 1000,
            "missingNativeFOVKeepsExplicitOverride": !missingNativeFOVWithOverride.defaultsToPerspective
                && missingNativeFOVWithOverride.perspectiveViewProjection == SceneParticleCameraFrame(
                    camera: canvasCamera(ordinarySize, fov: 95), viewportSize: ordinaryViewport).perspectiveViewProjection,
            "partialCanvasKeepsFallback": partialCanvas.perspectiveEyePosition.z == 1000,
            "layerCameraRescuesMissingFallback": !SceneParticleCameraFrame.usesNativePerspective(camera: missingFOVCamera)
                && layerCameraFrame.defaultsToPerspective,
            "layerCameraDefaultMatchesFrame": SceneParticleCameraFrame.usesNativePerspective(
                camera: missingFOVCamera, nativePerspectiveOverride: selectedCamera) == layerCameraFrame.defaultsToPerspective,
            "layerCameraFalseOverridesInherited": !layerCameraFlatFrame.resolvesPerspective(for: inheritedLayer),
            "hiddenLayerCameraFallsBack": hiddenCamera == nil,
            "typedPerspectiveMatrixMatchesStatic": scriptedFrame.viewProjection(for: scriptedLayer) == frame.perspectiveViewProjection,
            "typedFlatMatrixMatchesStatic": flatFrame.viewProjection(for: scriptedLayer) == frame.orthographicViewProjection,
            "typedSnapshotCaptureIsImmutable": scriptedFrame.resolvesPerspective(for: scriptedLayer),
            "typedFalseOverridesNative": !nativeFlatFrame.resolvesPerspective(for: inheritedLayer),
            "authoredSeedPreservesNativeDefault": nativeInheritedFrame.resolvesPerspective(for: inheritedLayer),
            "typedUtilityStaysScreenSpace": !scriptedFrame.resolvesPerspective(for: utilityOverride),
            "compositionStaticOutputIsPerspective": frame.viewProjection(for: composition)
                == frame.perspectiveViewProjection,
            "compositionTypedOutputIsPerspective": scriptedFrame.viewProjection(for: composition)
                == frame.perspectiveViewProjection,
            "compositionTypedFalseRestoresFlat": flatFrame.viewProjection(for: composition)
                == frame.orthographicViewProjection,
            "compositionCaptureRemainsFlat": scriptedFrame.captureViewProjection(for: composition)
                == frame.orthographicViewProjection,
            "compositionNativeRemainsUnsupported": !nativeFrame.resolvesPerspective(for: composition),
            "nativeMaterialSourceCamera": [
                "usesPerspective": nativeFrame.resolvesPerspective(for: nativeMaterialSourceLayer),
                "output": ndc(nativeFrame.viewProjection(for: nativeMaterialSourceLayer), nativeWorldUp),
                "capture": ndc(nativeFrame.captureViewProjection(for: nativeMaterialSourceLayer), nativeWorldUp),
                "ordinaryOutputStaysFlat": nativeFrame.viewProjection(for: composition)
                    == nativeFrame.orthographicViewProjection,
                "ordinaryCaptureStaysFlat": nativeFrame.captureViewProjection(for: composition)
                    == nativeFrame.orthographicViewProjection,
            ],
            "ordinaryImageCaptureFollowsOutput": scriptedFrame.captureViewProjection(for: scriptedLayer)
                == scriptedFrame.viewProjection(for: scriptedLayer),
            "wrongTypedValueKeepsStatic": !wrongTypedFrame.resolvesPerspective(for: scriptedLayer),
            "catalogDefaultMatchesNativeFrame": SceneParticleCameraFrame.usesNativePerspective(camera: nativeCamera) == nativeFrame.defaultsToPerspective,
            "catalogDefaultMatchesOrthoFrame": SceneParticleCameraFrame.usesNativePerspective(camera: camera) == frame.defaultsToPerspective,

            "pollingValues": pollingValues,
            "pollingHalfFar": pollingHalfFar,
            "pollingRotated": vector3(rotatedPolling.nativeCursorWorldPosition(.init(0.5, 0))!),
            "pollingZoom": vector3(pollingFrame(far: 10_000, zoom: 2).nativeCursorWorldPosition(.init(0.5, 0))!),
            "pollingResize": vector3(pollingFrame(far: 10_000, viewport: CGSize(width: 1473, height: 1473)).nativeCursorWorldPosition(.init(0.5, 0))!),
            "pollingOutside": vector3(polling.nativeCursorWorldPosition(.init(2, -2))!),
            "pollingActiveCamera": vector3(activeCameraFrame.nativeCursorWorldPosition(.zero)!),
            "pollingInvalidRejected": [
                polling.nativeCursorWorldPosition(.init(.nan, 0)) == nil,
                polling.nativeCursorWorldPosition(.init(0, .infinity)) == nil,
                pollingFrame(far: 0).nativeCursorWorldPosition(.zero) == nil,
                pollingFrame(far: .infinity).nativeCursorWorldPosition(.zero) == nil,
                frame.nativeCursorWorldPosition(.zero) == nil,
            ],
            "canvasPerspectiveCardTop": ndc(frame.perspectiveViewProjection,
                center + SIMD4(0, 10 * SceneCameraProjection.imageCardYDirection(
                    usesPerspective: true, sceneOrthoHeight: camera.orthoHeight), 0, 0)),
            "canvasOrthoCardTop": ndc(frame.orthographicViewProjection,
                center + SIMD4(0, 10 * SceneCameraProjection.imageCardYDirection(
                    usesPerspective: false, sceneOrthoHeight: camera.orthoHeight), 0, 0)),
            "nativeCardDirection": SceneCameraProjection.imageCardYDirection(
                usesPerspective: true, sceneOrthoHeight: nil),
            "nativeUtilityCardDirection": SceneCameraProjection.imageCardYDirection(
                usesPerspective: false, sceneOrthoHeight: nil),
            "coverHalfExtents": vector2(frame.coverHalfExtents),
            "dynamicCoverHalfExtents": vector2(dynamicFrame.coverHalfExtents),
            "orthoCenterNDC": ndc(frame.orthographicViewProjection, center),
            "orthoEdgeNDC": ndc(frame.orthographicViewProjection, edge),
            "dynamicCenterNDC": ndc(
                dynamicFrame.orthographicViewProjection, dynamicCenter
            ),
            "dynamicPerspectiveCenterNDC": ndc(
                dynamicFrame.perspectiveViewProjection, dynamicCenter
            ),
            "dynamicEdgeNDC": ndc(
                dynamicFrame.orthographicViewProjection, dynamicEdge
            ),
            "dynamicCameraOrigin": vector3(dynamicFrame.cameraOrigin),
            "nonfiniteCameraOrigin": vector3(nonfiniteOriginFrame.cameraOrigin),
            "perspectiveCenterNDC": ndc(frame.perspectiveViewProjection, center),
            "perspectiveEdgeNDC": ndc(frame.perspectiveViewProjection, edge),
            "reversePerspectiveCenterNDC": ndc(
                frame.reverseDepthPerspectiveViewProjection, center
            ),
            "reversePerspectiveEdgeNDC": ndc(
                frame.reverseDepthPerspectiveViewProjection, edge
            ),
            "authoredFOVCenterNDC": ndc(
                authoredFOVFrame.perspectiveViewProjection, center
            ),
            "authoredFOVEdgeNDC": ndc(
                authoredFOVFrame.perspectiveViewProjection, edge
            ),
            "authoredFOVFarNDC": ndc(
                authoredFOVFrame.perspectiveViewProjection,
                SIMD4<Float>(960, 540, -10_000, 1)
            ),
            "selectedOrtho": frame.viewProjection(usesPerspective: false)
                == frame.orthographicViewProjection,
            "selectedPerspective": frame.viewProjection(usesPerspective: true)
                == frame.perspectiveViewProjection,
            "nativeCenterNDC": ndc(
                nativeFrame.perspectiveViewProjection, nativeCenter
            ),
            "nativeWorldUpNDC": ndc(
                nativeFrame.perspectiveViewProjection, nativeWorldUp
            ),
            "nativeWorldDownNDC": ndc(
                nativeFrame.perspectiveViewProjection, nativeWorldDown
            ),
            "nativeReverseWorldUpNDC": ndc(
                nativeFrame.reverseDepthPerspectiveViewProjection,
                nativeWorldUp
            ),
            "nativeEye": vector3(nativeFrame.perspectiveEyePosition),
            "activeCameraEye": vector3(activeCameraFrame.perspectiveEyePosition),
            "activeCameraOriginNDC": ndc(
                activeCameraFrame.perspectiveViewProjection,
                SIMD4<Float>(0, 0, 0, 1)
            ),
            "activeCameraWorldUpNDC": ndc(
                activeCameraFrame.perspectiveViewProjection,
                SIMD4<Float>(0, 1, 0, 1)
            ),
            "nativeDefaultsToPerspective": nativeFrame.defaultsToPerspective,
            "utilityModelUsesPerspective": frame.resolvesPerspective(for: explicitUtilityLayer),
            "utilityProjectionMatchesModel": frame.viewProjection(for: explicitUtilityLayer)
                == frame.viewProjection(usesPerspective: frame.resolvesPerspective(for: explicitUtilityLayer)),
            "imageModelUsesPerspective": frame.resolvesPerspective(for: explicitImageLayer),
            "imageProjectionMatchesModel": frame.viewProjection(for: explicitImageLayer)
                == frame.viewProjection(usesPerspective: frame.resolvesPerspective(for: explicitImageLayer)),
            "nativeOmittedLayerPerspective": nativeFrame.resolvesPerspective(
                layerOverride: nil
            ),
            "nativeLayerUsesPerspectiveProjection": nativeFrame.viewProjection(
                for: inheritedNativeLayer
            ) == nativeFrame.perspectiveViewProjection,
            "nativeUtilityUsesOrthoProjection": nativeFrame.viewProjection(
                for: nativeUtilityLayer
            ) == nativeFrame.orthographicViewProjection,
            "materialViewOrtho": vector3(SIMD3(nativeFrame.materialView(usesPerspective:false).x,nativeFrame.materialView(usesPerspective:false).y,nativeFrame.materialView(usesPerspective:false).z)),
            "materialViewOrthoParallel": nativeFrame.materialView(usesPerspective:false).w == 0,
            "materialViewPerspectiveEye": nativeFrame.materialView(usesPerspective:true) == SIMD4(nativeFrame.perspectiveEyePosition,1),
            "materialViewPanInvariant": dynamicFrame.materialView(usesPerspective:false) == frame.materialView(usesPerspective:false),
            "nativeExplicitOrtho": nativeFrame.resolvesPerspective(
                layerOverride: false
            ),
            "orthoDefaultsToPerspective": frame.defaultsToPerspective,
            "cameraRight": vector3(frame.cameraRight),
            "cameraUp": vector3(frame.cameraUp),
            "cameraForward": vector3(frame.cameraForward),
            "screenRight": vector3(screenBasis.right),
            "screenUp": vector3(screenBasis.up),
            "uprightRight": vector3(uprightBasis.right),
            "uprightUp": vector3(uprightBasis.up),
            "fixedRight": vector3(fixedBasis.right),
            "fixedUp": vector3(fixedBasis.up),
            "orthoScreenOrientation": orientationMetrics(
                basis: screenBasis,
                viewProjection: frame.orthographicViewProjection,
                center: sceneCenter
            ),
            "orthoUprightOrientation": orientationMetrics(
                basis: uprightBasis,
                viewProjection: frame.orthographicViewProjection,
                center: sceneCenter
            ),
            "orthoFixedOrientation": orientationMetrics(
                basis: fixedBasis,
                viewProjection: frame.orthographicViewProjection,
                center: sceneCenter
            ),
            "perspectiveScreenOrientation": orientationMetrics(
                basis: screenBasis,
                viewProjection: frame.perspectiveViewProjection,
                center: sceneCenter
            ),
            "perspectiveUprightOrientation": orientationMetrics(
                basis: uprightBasis,
                viewProjection: frame.perspectiveViewProjection,
                center: sceneCenter
            ),
            "perspectiveFixedOrientation": orientationMetrics(
                basis: fixedBasis,
                viewProjection: frame.perspectiveViewProjection,
                center: sceneCenter
            ),
            "layerCenter": vector4(stationary),
            "inheritedScale": vector2(inheritedScale),
            "worldSpaceDirectionRoundTrip": vector3(SIMD3(
                reprojectedDirection.x,
                reprojectedDirection.y,
                reprojectedDirection.z
            )),
            "eligibleWorldSpaceLayers": eligibleWorldSpaceLayers,
            "parallaxDirectionUnchanged": directionLeft == directionRight,
            "parallaxExistingParticleDelta": vector3(SIMD3(drawDelta.x, drawDelta.y, drawDelta.z)),
            "parallaxScaleUnchanged": SceneParticleCameraFrame.billboardScale(inheritedFrom: drawLeft)
                == SceneParticleCameraFrame.billboardScale(inheritedFrom: drawRight),
            "stationaryNDCY": stationaryNDC[1],
            "fallingNDCY": fallingNDC[1],
            "invalidPerspectiveIsIdentity": invalidFrame.perspectiveViewProjection
                == SceneMatrix.identity(),
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    private static func staticCameraTransformChecks() -> [String: Any] {
        let viewport = CGSize(width: 800, height: 600)
        let saved = SceneRenderDescriptor.CameraDescriptor(eye: [80, -60, 0], center: [80, -60, -1],
            up: [0, 1, 0], orthoWidth: 800, orthoHeight: 600, fovDegrees: nil,
            perspectiveOverrideFOVDegrees: nil, nearZ: 0.01, farZ: 10000)
        let base = SceneParticleCameraFrame(camera: saved, viewportSize: viewport)
        let canonical = SceneParticleCameraFrame(camera: saved, viewportSize: viewport,
            staticEye: .zero, staticCenter: SIMD3(0, 0, -1), staticUp: SIMD3(0, 1, 0))
        let delta = SIMD3<Float>(25 * 4, 125 - 25, 0)
        let shifted = SceneParticleCameraFrame(camera: saved, viewportSize: viewport,
            staticEye: delta, staticCenter: delta + SIMD3(0, 0, -1), staticUp: SIMD3(0, 1, 0))
        let markers = [SIMD3<Float>(173, 117, 0), SIMD3<Float>(631, 449, 0)]
        let shiftedNDC = markers.map { ndc(shifted.orthographicViewProjection, SIMD4($0, 1)) }
        let pixels = shiftedNDC.map { [($0[0] + 1) * 400, (1 - $0[1]) * 300] }
        let recovered = shiftedNDC.map { point in
            SceneLayerCursorGeometry.layerPoint(mouseNormalized: SIMD2(point[0], point[1]),
                modelViewProjection: shifted.orthographicViewProjection)
        }
        let path = SceneParticleCameraFrame(camera: saved, viewportSize: viewport,
            cameraOrigin: SIMD3(23, -17, 9), cameraZoom: 1.7)
        let pathAndDefaults = SceneParticleCameraFrame(camera: saved, viewportSize: viewport,
            cameraOrigin: SIMD3(23, -17, 9), cameraZoom: 1.7,
            staticEye: .zero, staticCenter: SIMD3(0, 0, -1), staticUp: SIMD3(0, 1, 0))
        let rolled = SceneParticleCameraFrame(camera: saved, viewportSize: viewport,
            staticEye: .zero, staticCenter: SIMD3(0, 0, -1), staticUp: SIMD3(1, 0, 0))
        let tilted = SceneParticleCameraFrame(camera: saved, viewportSize: viewport,
            staticEye: .zero, staticCenter: SIMD3(0, 1, -1), staticUp: SIMD3(0, 1, 0))
        func uniforms(_ camera: SceneParticleCameraFrame) -> SceneParticleLayerUniforms {
            camera.particleUniforms(layerModel: SceneParticleCameraFrame.particleLayerModel(
                worldFrame: matrix_identity_float4x4, parallaxOffset: .zero), orientation: .screen,
                orientationAxis: nil, usesPerspective: false, usesSceneCamera: false,
                viewportSize: SIMD2(800, 600), sizeIsWorldSpace: true)
        }
        func near(_ a: SIMD4<Float>, _ b: SIMD4<Float>) -> Bool { simd_length(a-b) < 0.00003 }
        let roll = uniforms(rolled), tilt = uniforms(tilted)
        let diagonal = Float(1 / sqrt(2.0))
        let native = SceneRenderDescriptor.CameraDescriptor(eye: [7, 3, 12], center: [1, -2, 0],
            up: [0, 1, 0], orthoWidth: nil, orthoHeight: nil, fovDegrees: 50,
            perspectiveOverrideFOVDegrees: nil, nearZ: 0.1, farZ: 100)
        let nativeBase = SceneParticleCameraFrame(camera: native, viewportSize: viewport)
        let nativeSeeded = SceneParticleCameraFrame(camera: native, viewportSize: viewport,
            staticEye: SIMD3(7, 3, 12), staticCenter: SIMD3(1, -2, 0), staticUp: SIMD3(0, 1, 0))
        let selectedCamera = SceneParticleCameraFrame.NativePerspectiveOverride(
            worldFrame: SceneMatrix.translation(SIMD3(2, -1, 9)) * SceneMatrix.rotationY(0.25), fovDegrees: 60)!
        let selected = SceneParticleCameraFrame(camera: native, viewportSize: viewport,
            nativePerspectiveOverride: selectedCamera)
        let selectedSeeded = SceneParticleCameraFrame(camera: native, viewportSize: viewport,
            staticEye: SIMD3(7, 3, 12), staticCenter: SIMD3(1, -2, 0), staticUp: SIMD3(0, 1, 0),
            nativePerspectiveOverride: selectedCamera)
        return ["pixels": pixels, "recovered": recovered.map { $0.map(vector3) ?? [] }, "facts": [
            "canonicalDoesNotUseSavedEye": base.orthographicViewProjection == canonical.orthographicViewProjection
                && base.perspectiveViewProjection == canonical.perspectiveViewProjection,
            "oldPathAndZoom": path.orthographicViewProjection == pathAndDefaults.orthographicViewProjection
                && path.perspectiveViewProjection == pathAndDefaults.perspectiveViewProjection,
            "rollScreenAxes": near(roll.viewRight, SIMD4(0, -1, 0, 0))
                && near(roll.viewUp, SIMD4(-1, 0, 0, 0)) && near(roll.basisRight, roll.viewRight)
                && near(roll.basisUp, roll.viewUp),
            "tiltScreenAxes": near(tilt.viewRight, SIMD4(1, 0, 0, 0))
                && near(tilt.viewUp, SIMD4(0, -diagonal, -diagonal, 0))
                && near(tilt.basisRight, tilt.viewRight) && near(tilt.basisUp, tilt.viewUp),
            "materialSharesView": near(rolled.materialView(usesPerspective: false), SIMD4(0, 0, 1, 0))
                && near(tilted.materialView(usesPerspective: false), SIMD4(0, -diagonal, diagonal, 0)),
            "nativeSavedDefaults": nativeBase.perspectiveViewProjection == nativeSeeded.perspectiveViewProjection
                && nativeBase.perspectiveEyePosition == SIMD3(7, 3, 12),
            "nativeSelectedOverride": selected.perspectiveViewProjection == selectedSeeded.perspectiveViewProjection
                && selected.perspectiveEyePosition == SIMD3(2, -1, 9),
        ]]
    }

    private static func nativeLayerSelectionChecks(
        camera: SceneRenderDescriptor.CameraDescriptor
    ) -> [String: Bool] {
        let older = SceneRenderDescriptor.Layer(id: 7,
            cameraPath: .init(camera: "default", fov: 60),
            utilityLayer: nil, usesPerspective: nil)
        let newer = SceneRenderDescriptor.Layer(id: 9,
            cameraPath: .init(camera: "DEFAULT", fov: 45), parentID: 10,
            utilityLayer: nil, usesPerspective: nil)
        let parent = SceneRenderDescriptor.Layer(id: 10,
            utilityLayer: nil, usesPerspective: nil)
        let editor = SceneRenderDescriptor.Layer(id: 11,
            cameraPath: .init(camera: "editor", fov: 30),
            utilityLayer: nil, usesPerspective: nil)
        let hidden = SceneRenderDescriptor.Layer(id: 12,
            cameraPath: .init(camera: "default", fov: 30), visible: false,
            utilityLayer: nil, usesPerspective: nil)
        let byID = [7: older, 9: newer, 10: parent, 11: editor, 12: hidden]
        let worlds = byID.mapValues { SceneMatrix.translation(SIMD3<Float>(0, 0, Float($0.id))) }
        func select(
            layers: [Int: SceneRenderDescriptor.Layer]? = nil,
            frames: [Int: simd_float4x4]? = nil,
            order: [Int] = [7, 9, 10, 11, 12, 404],
            snapshot: SceneDynamicSnapshot = .empty(frameIndex: 1)
        ) -> SceneParticleCameraFrame.NativePerspectiveOverride? {
            let layers = layers ?? byID
            return SceneParticleCameraFrame.nativePerspectiveOverride(
                descriptor: .init(camera: camera, renderOrderLayerIDs: order,
                    layers: Array(layers.values)),
                layersByID: layers, worldFrames: frames ?? worlds, dynamicValues: snapshot)
        }
        func snapshot(_ target: SceneDynamicTarget, _ value: SceneDynamicValue) -> SceneDynamicSnapshot {
            SceneDynamicSnapshotResolver().resolve(frameIndex: 2, generation: 1,
                definitions: [.init(target: target, valueType: value.valueType,
                    authoredValue: value)], sceneScriptValues: [target: value]).snapshot
        }
        var hiddenParent = byID
        hiddenParent[10]?.visible = false
        var cyclicParent = byID
        cyclicParent[10]?.parentID = 9
        var missingFOV = byID
        missingFOV[9]?.cameraPath = .init(camera: "default", fov: nil)
        let parentVisibility = SceneDynamicTarget.layer(layerID: 10, field: .visibility)
        let winner = select()
        return [
            "reverseOrderSkipsHiddenAndOtherCameraKinds": winner?.eye.z == 9 && winner?.fovDegrees == 45,
            "reverseOrderChangesWinner": select(order: [9, 7])?.eye.z == 7,
            "hiddenParentSkipsCamera": select(layers: hiddenParent)?.eye.z == 7,
            "dynamicParentVisibilitySkipsCamera": select(snapshot: snapshot(parentVisibility, .bool(false)))?.eye.z == 7,
            "dynamicParentVisibilityOverridesAuthored": select(layers: hiddenParent,
                snapshot: snapshot(parentVisibility, .bool(true)))?.eye.z == 9,
            "parentCycleSkipsCamera": select(layers: cyclicParent)?.eye.z == 7,
            "noDefaultCameraFallsBack": select(order: [10, 11, 12, 404]) == nil,
            "selectedMissingWorldDoesNotPickOlderCamera": select(frames: [7: worlds[7]!]) == nil,
            "selectedMissingFOVDoesNotPickOlderCamera": select(layers: missingFOV) == nil,
            "selectedDynamicFOVIsConsumed": select(snapshot: snapshot(
                .layer(layerID: 9, field: .fov), .scalar(80)))?.fovDegrees == 80,
        ]
    }

    private static func ndc(_ matrix: simd_float4x4, _ point: SIMD4<Float>) -> [Float] {
        let clip = matrix * point
        return [clip.x / clip.w, clip.y / clip.w, clip.z / clip.w]
    }

    private static func vector2(_ value: SIMD2<Float>) -> [Float] {
        [value.x, value.y]
    }

    private static func vector3(_ value: SIMD3<Float>) -> [Float] {
        [value.x, value.y, value.z]
    }

    private static func vector4(_ value: SIMD4<Float>) -> [Float] {
        [value.x, value.y, value.z, value.w]
    }

    private static func orientationMetrics(
        basis: SceneParticleOrientationBasis,
        viewProjection: simd_float4x4,
        center: SIMD3<Float>
    ) -> [String: Float] {
        let top = ndc(viewProjection, SIMD4(center + basis.up * 10, 1))
        let bottom = ndc(viewProjection, SIMD4(center - basis.up * 10, 1))
        let authoredRight = ndc(viewProjection, SIMD4(center + basis.right * 10, 1))
        let authoredLeft = ndc(viewProjection, SIMD4(center - basis.right * 10, 1))
        return [
            "topY": top[1],
            "bottomY": bottom[1],
            "rightX": authoredRight[0],
            "leftX": authoredLeft[0],
        ]
    }
}
