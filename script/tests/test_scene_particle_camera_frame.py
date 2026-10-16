#!/usr/bin/env python3

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SOURCE_ROOT / "Systems/Properties/SceneDynamicSnapshot.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Geometry/SceneMatrix.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Geometry/SceneLayerCursorGeometry.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Input/SceneCameraProjection.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Particles/SceneParticleRenderSupport.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleCameraFrame.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleCameraFrame+LayerCamera.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleWorldSpacePlan.swift",
]


HARNESS_SOURCE = r'''
import CoreGraphics
import Foundation
import simd

struct SceneRenderDescriptor {
    struct Layer {
        var id: Int = 0
        var cameraPath: CameraPath? = nil
        var visible = true
        struct CameraPath { let camera: String; let fov: Double? }
        let utilityLayer: Bool?
        let usesPerspective: Bool?
    }

    let camera: CameraDescriptor
    let renderOrderLayerIDs: [Int]

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

enum SceneLayerVisibility {
    static func isEffectivelyVisible(
        layerID: Int, in descriptor: SceneRenderDescriptor,
        layersByID: [Int: SceneRenderDescriptor.Layer], snapshot: SceneDynamicSnapshot
    ) -> Bool { layersByID[layerID]?.visible == true }
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
                "requiredEffectProjection": SceneLayerCursorGeometry.effectTextureProjectionInverse(mvp, required: true) != nil,
                "legacyRequiredEffectProjection": SceneLayerCursorGeometry.effectTextureProjectionInverse(legacyMVP, required: true) != nil,
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
        let result: [String: Any] = [
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
'''


class SceneParticleCameraFrameTests(unittest.TestCase):
    def test_image_card_direction_follows_world_not_projection(self) -> None:
        self.assertGreater(self.result["canvasPerspectiveCardTop"][1], 0)
        self.assertGreater(self.result["canvasOrthoCardTop"][1], 0)
        self.assertEqual(self.result["nativeCardDirection"], 1)
        self.assertEqual(self.result["nativeUtilityCardDirection"], -1)

    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-particle-camera-frame-"
        )
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = directory / "scene-particle-camera-frame"
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc",
                *(str(path) for path in SWIFT_SOURCES), str(harness),
                "-o", str(cls.binary),
            ],
            capture_output=True, text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(cls.binary)], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_native_polling_matches_official_far_plane_points(self):
        # Official own probe: FOV50, eye(0,0,10), 2268x1473, cursor y=736.
        for actual, expected in zip(self.result["pollingValues"],
                                    [[0, 3.165749073, -9990.00097656],
                                     [3589.904785156, 3.165749073, -9990.00097656]]):
            for value, reference in zip(actual, expected):
                self.assertAlmostEqual(value, reference, delta=0.01)
        for actual, full in zip(self.result["pollingHalfFar"], self.result["pollingValues"]):
            self.assertAlmostEqual(actual[0], full[0] / 2, delta=0.001)
            self.assertAlmostEqual(actual[1], full[1] / 2, delta=0.001)
            self.assertAlmostEqual(actual[2], -4990, delta=0.001)

    def test_native_polling_tracks_camera_zoom_resize_and_outside_drag(self):
        import math
        half = 5000 * math.tan(math.radians(25))
        for actual, expected in zip(self.result["pollingRotated"], [-4990, 2, -half * 2268 / 1473 * 0.5]):
            self.assertAlmostEqual(actual, expected, delta=0.001)
        self.assertAlmostEqual(self.result["pollingZoom"][0], self.result["pollingValues"][1][0] / 2, delta=0.001)
        self.assertAlmostEqual(self.result["pollingResize"][0], half, delta=0.001)
        self.assertAlmostEqual(self.result["pollingOutside"][0], self.result["pollingValues"][1][0] * 4, delta=0.01)
        self.assertEqual(self.result["pollingActiveCamera"], [0, 0, -9994])
        self.assertTrue(all(self.result["pollingInvalidRejected"]))

    def test_material_view_uses_projection_owner(self):
        self.assertEqual(self.result['materialViewOrtho'],[0,0,1])
        for key in ['materialViewOrthoParallel','materialViewPerspectiveEye','materialViewPanInvariant']:
            self.assertTrue(self.result[key],key)

    def test_cover_uses_drawable_aspect_without_letterboxing(self) -> None:
        self.assertAlmostEqual(self.result["coverHalfExtents"][0], 830.7692, places=3)
        self.assertAlmostEqual(self.result["coverHalfExtents"][1], 540, places=4)

    def test_both_projections_map_cover_center_and_boundary_to_ndc(self) -> None:
        for key in ("orthoCenterNDC", "perspectiveCenterNDC"):
            self.assertAlmostEqual(self.result[key][0], 0, places=5)
            self.assertAlmostEqual(self.result[key][1], 0, places=5)
        for key in ("orthoEdgeNDC", "perspectiveEdgeNDC"):
            self.assertAlmostEqual(self.result[key][0], 1, places=5)
            self.assertAlmostEqual(self.result[key][1], -1, places=5)
        self.assertTrue(self.result["selectedOrtho"])
        self.assertTrue(self.result["selectedPerspective"])

    def test_reverse_depth_preserves_xy_and_reverses_metal_depth(self) -> None:
        for standard, reverse in (
            ("perspectiveCenterNDC", "reversePerspectiveCenterNDC"),
            ("perspectiveEdgeNDC", "reversePerspectiveEdgeNDC"),
        ):
            self.assertAlmostEqual(
                self.result[standard][0], self.result[reverse][0], places=5
            )
            self.assertAlmostEqual(
                self.result[standard][1], self.result[reverse][1], places=5
            )
            self.assertAlmostEqual(
                self.result[standard][2] + self.result[reverse][2], 1, places=5
            )

    def test_authored_fov_preserves_canvas_extent_and_world_far_reach(self) -> None:
        for key in ("authoredFOVCenterNDC", "authoredFOVEdgeNDC"):
            self.assertTrue(all(value == value for value in self.result[key]))
        self.assertAlmostEqual(self.result["authoredFOVCenterNDC"][0], 0, places=5)
        self.assertAlmostEqual(self.result["authoredFOVCenterNDC"][1], 0, places=5)
        self.assertAlmostEqual(self.result["authoredFOVEdgeNDC"][0], 1, places=5)
        self.assertAlmostEqual(self.result["authoredFOVEdgeNDC"][1], -1, places=5)
        self.assertAlmostEqual(self.result["authoredFOVFarNDC"][2], 1, places=4)

    def test_ordinary_canvas_omitted_fov_matches_95_for_depth_and_tilt(self) -> None:
        import math
        self.assertEqual(len(self.result["defaultProjectionRows"]), 5)
        for index, row in enumerate(self.result["defaultProjectionRows"]):
            with self.subTest(profile=index):
                self.assertEqual(row["omitted"], row["explicit95"])
                self.assertAlmostEqual(row["eyeZ"], row["halfHeight"] / math.tan(math.radians(47.5)), delta=0.0001)
                self.assertGreater(abs(row["omitted"][0][0] - row["explicit50"][0]), 0.04)
                self.assertAlmostEqual(row["farNDC"], 1, places=4)
                for key in ("cursorLocal", "legacyCursorLocal"):
                    for actual, expected in zip(row[key], [0.2, -0.1, 0], strict=True):
                        self.assertAlmostEqual(actual, expected, places=4)
                self.assertTrue(row["requiredEffectProjection"])
                self.assertTrue(row["legacyRequiredEffectProjection"])

    def test_canvas_fov_keeps_flat_utility_and_general_fov_boundaries(self) -> None:
        for index, row in enumerate(self.result["defaultProjectionRows"]):
            with self.subTest(profile=index):
                self.assertTrue(row["flatUnchanged"])
                self.assertTrue(row["utilityUnchanged"])
                self.assertTrue(row["generalFOVKeepsCanvasPolicy"])

    def test_invalid_explicit_fov_keeps_existing_eye_distance_fallback(self) -> None:
        self.assertEqual(len(self.result["invalidFOVRows"]), 6)
        for row in self.result["invalidFOVRows"]:
            self.assertEqual(row[0], 1000)
            self.assertAlmostEqual(row[1], (750.2 - 605) / 605 * 1000 / 880, places=5)

    def test_default_fov_reuses_dynamic_pose_zoom_and_native_admission(self) -> None:
        import math
        for index, row in enumerate(self.result["dynamicFOVRows"]):
            with self.subTest(origin=index):
                self.assertTrue(row["matchesExplicit"])
                self.assertAlmostEqual(row["halfHeight"], 393 / 2.4, places=4)
                for component in row["canvasCenter"][:2]:
                    self.assertAlmostEqual(component, 0, places=5)
        self.assertEqual(self.result["dynamicFOVRows"][0]["origin"], [-100, 682, 500])
        self.assertEqual(self.result["dynamicFOVRows"][0]["eyeZ"], 500)
        for row in self.result["dynamicFOVRows"][1:]:
            self.assertAlmostEqual(row["eyeZ"], row["halfHeight"] / math.tan(math.radians(47.5)), delta=0.0001)
        self.assertTrue(self.result["nativeOverrideKeepsNativePolicy"])
        self.assertTrue(self.result["missingNativeFOVKeepsFallback"])
        self.assertTrue(self.result["missingNativeFOVKeepsExplicitOverride"])
        self.assertTrue(self.result["partialCanvasKeepsFallback"])

    def test_native_scene_uses_authored_camera_and_inherits_projection(self) -> None:
        self.assertAlmostEqual(self.result["nativeCenterNDC"][0], 0, places=5)
        self.assertAlmostEqual(self.result["nativeCenterNDC"][1], 0, places=5)
        for actual, expected in zip(
            self.result["nativeEye"], [-2.05772, 0.85240, 10.07242]
        ):
            self.assertAlmostEqual(actual, expected, places=5)
        self.assertTrue(self.result["nativeDefaultsToPerspective"])
        self.assertTrue(self.result["nativeOmittedLayerPerspective"])
        self.assertTrue(self.result["nativeLayerUsesPerspectiveProjection"])
        self.assertTrue(self.result["nativeUtilityUsesOrthoProjection"])
        self.assertFalse(self.result["utilityModelUsesPerspective"])
        self.assertTrue(self.result["utilityProjectionMatchesModel"])
        self.assertTrue(self.result["imageModelUsesPerspective"])
        self.assertTrue(self.result["imageProjectionMatchesModel"])
        self.assertFalse(self.result["nativeExplicitOrtho"])
        self.assertFalse(self.result["orthoDefaultsToPerspective"])

    def test_typed_perspective_uses_one_immutable_camera_policy(self) -> None:
        for key in ("typedPerspectiveMatrixMatchesStatic", "typedFlatMatrixMatchesStatic",
                    "typedSnapshotCaptureIsImmutable", "typedFalseOverridesNative",
                    "authoredSeedPreservesNativeDefault", "typedUtilityStaysScreenSpace",
                    "layerCameraRescuesMissingFallback", "layerCameraDefaultMatchesFrame",
                    "layerCameraFalseOverridesInherited", "hiddenLayerCameraFallsBack",
                    "wrongTypedValueKeepsStatic", "catalogDefaultMatchesNativeFrame",
                    "catalogDefaultMatchesOrthoFrame"):
            self.assertTrue(self.result[key], key)

    def test_native_camera_preserves_world_up_through_metal_clip_space(self) -> None:
        world_up = self.result["nativeWorldUpNDC"]
        world_down = self.result["nativeWorldDownNDC"]
        reverse_up = self.result["nativeReverseWorldUpNDC"]
        self.assertGreater(world_up[1], world_down[1])
        self.assertAlmostEqual(world_up[0], reverse_up[0], places=5)
        self.assertAlmostEqual(world_up[1], reverse_up[1], places=5)
        self.assertAlmostEqual(world_up[2] + reverse_up[2], 1, places=5)

    def test_native_camera_layer_overrides_saved_editor_view(self) -> None:
        self.assertEqual(self.result["activeCameraEye"], [0, 0, 6])
        self.assertAlmostEqual(self.result["activeCameraOriginNDC"][0], 0, places=5)
        self.assertAlmostEqual(self.result["activeCameraOriginNDC"][1], 0, places=5)
        self.assertGreater(self.result["activeCameraWorldUpNDC"][1], 0)

    def test_dynamic_2d_camera_origin_and_zoom_share_the_projection(self) -> None:
        self.assertAlmostEqual(
            self.result["dynamicCoverHalfExtents"][0],
            self.result["coverHalfExtents"][0] / 2.4,
            places=3,
        )
        self.assertAlmostEqual(
            self.result["dynamicCoverHalfExtents"][1],
            self.result["coverHalfExtents"][1] / 2.4,
            places=3,
        )
        for component in self.result["dynamicCenterNDC"][:2]:
            self.assertAlmostEqual(component, 0, places=5)
        for component in self.result["dynamicPerspectiveCenterNDC"][:2]:
            self.assertAlmostEqual(component, 0, places=5)
        self.assertAlmostEqual(self.result["dynamicEdgeNDC"][0], 1, places=5)
        self.assertAlmostEqual(self.result["dynamicEdgeNDC"][1], -1, places=5)
        self.assertEqual(self.result["dynamicCameraOrigin"], [-100, 682, 500])
        self.assertEqual(self.result["nonfiniteCameraOrigin"], [0, 0, 0])

    def test_camera_axes_match_we_global_particle_camera(self) -> None:
        self.assertEqual(self.result["cameraRight"], [1, 0, 0])
        self.assertEqual(self.result["cameraUp"], [0, 1, 0])
        self.assertEqual(self.result["cameraForward"], [0, 0, -1])
        for orientation in ("screen", "upright", "fixed"):
            self.assertEqual(self.result[f"{orientation}Right"], [1, 0, 0])
            self.assertEqual(self.result[f"{orientation}Up"], [0, -1, 0])

    def test_authored_top_and_right_keep_visual_orientation(self) -> None:
        for projection in ("ortho", "perspective"):
            for orientation in ("Screen", "Upright", "Fixed"):
                metrics = self.result[f"{projection}{orientation}Orientation"]
                self.assertGreater(metrics["topY"], metrics["bottomY"])
                self.assertGreater(metrics["rightX"], metrics["leftX"])

    def test_layer_model_flips_y_and_inherits_world_scale(self) -> None:
        self.assertAlmostEqual(self.result["layerCenter"][0], 105, places=5)
        self.assertAlmostEqual(self.result["layerCenter"][1], 193, places=5)
        self.assertAlmostEqual(self.result["inheritedScale"][0], 2, places=5)
        self.assertAlmostEqual(self.result["inheritedScale"][1], 3, places=5)
        self.assertLess(self.result["fallingNDCY"], self.result["stationaryNDCY"])

    def test_static_world_space_plan_and_direction_inverse(self) -> None:
        self.assertEqual(self.result["eligibleWorldSpaceLayers"], [1, 2])
        for actual, expected in zip(
            self.result["worldSpaceDirectionRoundTrip"],
            [12, -7, 0],
        ):
            self.assertAlmostEqual(actual, expected, places=4)

    def test_parallax_changes_draw_translation_without_force_basis_or_size(self) -> None:
        self.assertTrue(self.result["parallaxDirectionUnchanged"])
        self.assertTrue(self.result["parallaxScaleUnchanged"])
        for actual, expected in zip(self.result["parallaxExistingParticleDelta"], [60, -20, 0]):
            self.assertAlmostEqual(actual, expected, places=4)

    def test_invalid_dimensions_fail_closed(self) -> None:
        self.assertTrue(self.result["invalidPerspectiveIsIdentity"])


if __name__ == "__main__":
    unittest.main()
