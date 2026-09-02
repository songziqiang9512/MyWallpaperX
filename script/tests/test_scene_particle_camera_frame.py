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
    SOURCE_ROOT / "Rendering/SceneMatrix.swift",
    SOURCE_ROOT / "Rendering/SceneCameraProjection.swift",
    SOURCE_ROOT / "Particles/SceneParticleRenderSupport.swift",
    SOURCE_ROOT / "Particles/SceneParticleCameraFrame.swift",
    SOURCE_ROOT / "Particles/SceneParticleWorldSpacePlan.swift",
]


HARNESS_SOURCE = r'''
import CoreGraphics
import Foundation
import simd

struct SceneRenderDescriptor {
    struct CameraDescriptor {
        let eye: [Float]
        let center: [Float]
        let up: [Float]
        let orthoWidth: Float?
        let orthoHeight: Float?
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
            perspectiveOverrideFOVDegrees: nil,
            nearZ: 0.01, farZ: 10_000
        )
        let viewport = CGSize(width: 1280, height: 832)
        let frame = SceneParticleCameraFrame(camera: camera, viewportSize: viewport)
        let authoredFOVCamera = SceneRenderDescriptor.CameraDescriptor(
            eye: [0, 0, 0], center: [0, 0, -1], up: [0, 1, 0],
            orthoWidth: 1920, orthoHeight: 1080,
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
        let eligibleWorldSpaceLayers = SceneParticleStaticWorldSpacePlan.eligibleLayerIDs(
            nodes: [
                .init(
                    id: 1, parentID: nil,
                    hasAuthoredTransformMotion: false,
                    hasEffectiveParallaxMotion: false
                ),
                .init(
                    id: 2, parentID: 1,
                    hasAuthoredTransformMotion: false,
                    hasEffectiveParallaxMotion: false
                ),
                .init(
                    id: 3, parentID: nil,
                    hasAuthoredTransformMotion: true,
                    hasEffectiveParallaxMotion: false
                ),
                .init(
                    id: 4, parentID: 3,
                    hasAuthoredTransformMotion: false,
                    hasEffectiveParallaxMotion: false
                ),
                .init(
                    id: 5, parentID: nil,
                    hasAuthoredTransformMotion: false,
                    hasEffectiveParallaxMotion: true
                ),
                .init(
                    id: 6, parentID: 7,
                    hasAuthoredTransformMotion: false,
                    hasEffectiveParallaxMotion: false
                ),
                .init(
                    id: 7, parentID: 6,
                    hasAuthoredTransformMotion: false,
                    hasEffectiveParallaxMotion: false
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

        let invalidCamera = SceneRenderDescriptor.CameraDescriptor(
            eye: [], center: [], up: [], orthoWidth: 0, orthoHeight: 0,
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

        let result: [String: Any] = [
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

    def test_invalid_dimensions_fail_closed(self) -> None:
        self.assertTrue(self.result["invalidPerspectiveIsIdentity"])


if __name__ == "__main__":
    unittest.main()
