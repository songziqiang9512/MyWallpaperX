#!/usr/bin/env python3

from __future__ import annotations

import unittest
import os
import ast
import tempfile
from pathlib import Path

from script.tests.scene_particle_render_test_support import run_particle_harness
from script.tests.test_scene_particle_rendering import SWIFT_SOURCES
from script.tests.scene_particle_runtime_configuration_cases import _declaration


# Reuse the runtime gate's maintained leaves; frame decisions below are the
# complete production particle frame owner and MainPassEncoder sources.
ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
RUNTIME_TEST = Path(__file__).with_name("test_scene_particle_runtime.py")
RUNTIME_FIXTURE = Path(__file__).with_name("fixtures") / "SceneParticleRuntimeHarness.swift"
CAMERA_FIXTURE = Path(__file__).with_name("fixtures") / "SceneParticleCameraRenderingHarness.swift"
TELEMETRY_SOURCE = SCENE / "Diagnostics/SceneFramePerformanceTelemetry.swift"
# Evaluate only the maintained path-list expression. Importing the Runtime test
# module would also resolve unrelated real-sample caches at module import time.
runtime_module = RUNTIME_TEST.read_text()
runtime_sources = next(node.value for node in ast.parse(runtime_module).body
                       if isinstance(node, ast.Assign)
                       and any(isinstance(target, ast.Name) and target.id == "SWIFT_SOURCES"
                               for target in node.targets))
RUNTIME_SOURCES = eval(ast.get_source_segment(runtime_module, runtime_sources), {
    "Path": Path, "__file__": str(RUNTIME_TEST),
    "SOURCE_ROOT": SCENE, "REPOSITORY_ROOT": ROOT,
})
CAMERA_SWIFT_SOURCES = tuple(dict.fromkeys(
    path.resolve() for path in [*SWIFT_SOURCES, *RUNTIME_SOURCES,
        SCENE / "Rendering/Particles/SceneParticleMetalPipeline+Frame.swift",
        SCENE / "Rendering/Composition/SceneMainPassEncoder.swift"]
    if path.name not in {"SceneLayerPerspectiveSnapshotHarness.swift", CAMERA_FIXTURE.name}
))
runtime_support = RUNTIME_FIXTURE.read_text()
CAMERA_HARNESS_SOURCE = runtime_support.split("@main", 1)[0] + _declaration(
    runtime_support, "struct SceneMetalRenderer {"
) + "\n" + _declaration(
    TELEMETRY_SOURCE.read_text(), "nonisolated struct SceneParticlePerformanceObservation:"
) + r'''
extension SceneMetalRenderer {
    struct StaticModelFrame {
        struct Depth { let acquisition: SceneParticleDepthTargetPool.Acquisition }
    }
}
// No graph pin enters this camera gate; its signature is peripheral to particles.
final class SceneGraphRenderTargetResidencyPin {
    func release() { fatalError("graph-pin lifetime is outside the camera gate") }
}
extension SceneRenderDescriptor.Layer {
    init(utilityLayer: Bool?, usesPerspective: Bool?) {
        self.init(id: 0, name: nil, contentKind: "particle", particlePath: nil,
            particleInstanceOverride: nil, parentID: nil, visible: true, alpha: 1)
        self.utilityLayer = utilityLayer; self.usesPerspective = usesPerspective
    }
}
extension SceneRenderDescriptor.CameraDescriptor {
    init(eye: [Float], center: [Float], up: [Float], orthoWidth: Float?, orthoHeight: Float?,
         fovDegrees: Float?, perspectiveOverrideFOVDegrees: Float?, nearZ: Float, farZ: Float) {
        self.init()
        self.eye = eye; self.center = center; self.up = up
        self.orthoWidth = orthoWidth; self.orthoHeight = orthoHeight
        self.fovDegrees = fovDegrees; self.perspectiveOverrideFOVDegrees = perspectiveOverrideFOVDegrees
        self.nearZ = nearZ; self.farZ = farZ
    }
}
''' + CAMERA_FIXTURE.read_text().replace(
    "    #if MWX_PARTICLE_CAMERA_DEPTH_PROBES\n", ""
).replace("    #endif // MWX_PARTICLE_CAMERA_DEPTH_PROBES\n", "") + r'''
@main enum CameraHarness {
    static func main() throws {
        var result = SceneParticleCameraRenderingHarness.run()
        result["refractionDepth"] = SceneParticleCameraRenderingHarness.refractionDepthProfiles()
        result["commonCull"] = SceneParticleCameraRenderingHarness.commonCullProfiles()
        result["particleVariantDemand"] = SceneParticleCameraRenderingHarness.particleVariantDemand()
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''
CAMERA_HARNESS_SOURCE += "\nextension CameraHarness {\n" + "\n".join(
    _declaration(runtime_support, marker) for marker in [
        "    static func writeAnimatedTEX(",
        "    static func appendUInt32(",
        "    static func appendFloat32(",
    ]
) + "\n}\n"


class SceneParticleCameraRenderingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        previous = os.environ.get("MWX_PARTICLE_CAMERA_READBACK_DIR")
        if previous is None:
            temporary = tempfile.TemporaryDirectory(prefix="mwx-particle-camera-readbacks-")
            cls.addClassCleanup(temporary.cleanup)
            os.environ["MWX_PARTICLE_CAMERA_READBACK_DIR"] = temporary.name
        try:
            cls.result = run_particle_harness(CAMERA_SWIFT_SOURCES, CAMERA_HARNESS_SOURCE)
        finally:
            if previous is None:
                os.environ.pop("MWX_PARTICLE_CAMERA_READBACK_DIR", None)

    def test_readonly_refraction_keeps_pixels_and_avoids_depth_for_both_orders(self) -> None:
        rows = self.result["refractionDepth"]["readonly"]
        self.assertEqual(len(rows), 4, rows)
        for row in rows:
            with self.subTest(variant=row["variant"], order=row["order"]):
                self.assertTrue(row["completed"], row)
                self.assertTrue(row["equalPixels"], row)
                self.assertGreater(row["changedPixels"], 30, row)
                self.assertEqual(row["depthBytes"], [0, 0], row)
                self.assertEqual(row["hasLease"], [False, False], row)

    def test_mixed_writer_refraction_reader_retains_depth_across_snapshot(self) -> None:
        rows = self.result["refractionDepth"]["mixed"]
        self.assertEqual(len(rows), 4, rows)
        self.assertEqual(self.result["refractionDepth"]["compiledVariants"], [
            "ordinary/alphatocoverage/depth", "ordinary/translucent/depth",
            "refraction/additive/depth", "refraction/additive/plain",
            "refraction/translucent/depth", "refraction/translucent/plain",
        ])
        for row in rows:
            with self.subTest(variant=row["variant"], order=row["order"]):
                self.assertTrue(row["completed"], row)
                self.assertTrue(all(row["hasLease"]), row)
                self.assertTrue(all(value > 0 for value in row["depthBytes"]), row)
                self.assertEqual(row["onCenter"], row["writerCenter"], row)
                self.assertEqual(row["greenProbePixels"], [0, 0], row)
                for pixel in row["coveragePixels"]:
                    self.assertEqual(pixel, [255, 0, 0, 255], row)
                if row["order"] == "writer-first":
                    self.assertNotEqual(row["offCenter"], row["writerCenter"], row)
                    self.assertGreater(row["differentPixels"], 20, row)
                else:
                    self.assertEqual(row["offCenter"], row["writerCenter"], row)

    def test_refraction_depth_elision_preserves_perspective_and_clip(self) -> None:
        self.assertAlmostEqual(self.result["refractionDepth"]["nearDepth"], 0, places=5)
        self.assertAlmostEqual(self.result["refractionDepth"]["farDepth"], 1, places=5)
        self.assertAlmostEqual(self.result["refractionDepth"]["fov90Edge"], 1, places=5)
        rows = self.result["refractionDepth"]["clip"]
        self.assertEqual(len(rows), 10, rows)
        for row in rows:
            with self.subTest(variant=row["variant"], geometry=row["geometry"]):
                self.assertTrue(row["completed"], row)
                self.assertTrue(row["sameMVP"], row)
                self.assertTrue(row["equalPixels"], row)
                self.assertEqual(row["depthBytes"], [0, 0], row)
                if row["geometry"] == "behind-eye":
                    self.assertEqual(row["changedPixels"], 0, row)
                    self.assertEqual(row["outsideCorners"], 4, row)
                else:
                    self.assertGreater(row["changedPixels"], 5, row)
                    if row["geometry"].startswith("cross-"):
                        self.assertGreater(row["outsideCorners"], 0, row)
                        self.assertLess(row["outsideCorners"], 4, row)
                    else:
                        self.assertEqual(row["outsideCorners"], 0, row)

    def test_dormant_child_requirements_feed_only_actual_pipeline_variants(self) -> None:
        rows = self.result["particleVariantDemand"]
        self.assertEqual(len(rows), 3, rows)
        expected = {
            "ordinary": ["ordinary/translucent/plain"],
            "readonly": ["refraction/translucent/plain"],
            "mixed": ["ordinary/additive/depth", "ordinary/additive/plain",
                      "ordinary/alphatocoverage/depth", "ordinary/alphatocoverage/plain",
                      "ordinary/translucent/depth", "refraction/translucent/depth",
                      "refraction/translucent/plain"],
        }
        for row in rows:
            with self.subTest(scenario=row["scenario"]):
                self.assertTrue(row["completed"], row)
                self.assertEqual(row["initialInstances"], 0, row)
                self.assertGreater(row["laterBatches"], 0, row)
                self.assertEqual(row["required"], expected[row["scenario"]], row)
                self.assertEqual(row["compiledBefore"], row["required"], row)
                self.assertEqual(row["compiledAfter"], row["compiledBefore"], row)
                if row["scenario"] == "mixed":
                    self.assertGreaterEqual(row["writerIndex"], 0, row)
                    self.assertLess(row["writerIndex"], row["readerIndex"], row)
                    self.assertTrue(row["hasLease"], row)
                    self.assertGreater(row["depthBytes"], 0, row)
                    self.assertEqual(row["center"], [255, 255, 255, 255], row)
                else:
                    self.assertFalse(row["hasLease"], row)
                    self.assertEqual(row["depthBytes"], 0, row)
                self.assertEqual(row["refractionUsesSceneCamera"],
                                 [] if row["scenario"] == "ordinary" else [False], row)

    def test_metal_right_handed_perspective_matches_scene_camera(self) -> None:
        self.assertAlmostEqual(self.result["nearNDC"][2], 0, places=5)
        self.assertAlmostEqual(self.result["farNDC"][2], 1, places=5)
        for actual, expected in zip(self.result["sceneCenterNDC"], [0, 0, 0.99992]):
            self.assertAlmostEqual(actual, expected, places=4)
        for actual, expected in zip(self.result["sceneTopRightNDC"][:2], [1, 1]):
            self.assertAlmostEqual(actual, expected, places=5)
        self.assertTrue(self.result["invalidPerspectiveIsIdentity"])


    def test_depth_state_rejects_far_fragment_and_overbright_scales_rgb_only(self) -> None:
        pixel = self.result["depthAndOverbrightPixel"]
        if not pixel:
            self.skipTest("Metal depth draw is unavailable")
        self.assertEqual(pixel[0], 0)
        self.assertEqual(pixel[1], 0)
        self.assertAlmostEqual(pixel[2], 128, delta=2)
        self.assertEqual(pixel[3], 255)
        self.assertEqual(
            self.result["depthTargetLease"],
            {
                "rejectsFourth": True,
                "reusesReleased": True,
                "completionReleased": True,
            },
        )


    def test_normal_cull_maps_to_back_faces_and_nocull_remains_two_sided(self) -> None:
        contract = self.result["cullContract"]
        if not contract.get("frontBackCull"):
            self.skipTest("Metal offscreen draw is unavailable")
        self.assertGreater(contract["frontBackCull"][3], 240)
        self.assertEqual(contract["reversedBackCull"], [0, 0, 0, 0])
        self.assertGreater(contract["reversedNoCull"][3], 240)

    def test_common_cull_preserves_actual_sprite_fixed_trail_geometry_and_frame_capture(self) -> None:
        rows = self.result["commonCull"]
        self.assertEqual(len(rows), 18, rows)
        for row in rows:
            with self.subTest(geometry=row["name"], perspective=row["perspective"]):
                self.assertTrue(row["completed"], row)
                self.assertFalse(row["hasDepth"], row)
                self.assertTrue(row["sameBackCoverage"], row)
                self.assertTrue(row["sameNoneCoverage"], row)
                # size20/2 gives 10x10; the rolled 15x5 rectangle covers 74
                # pixel centers on the 64-grid, with no centers on an edge.
                expected_area = 74 if row["name"] == "local-anisotropic-rolled" else 100
                self.assertEqual(row["ordinaryNoneCount"], expected_area, row)
                if row["expectedFront"] is not None:
                    self.assertTrue(all((area > 0) == row["expectedFront"]
                                        for area in row["spriteProjectedAreas"]), row)
                for prefix in ("ordinary", "refraction"):
                    if row["expectedFront"] is True:
                        self.assertEqual(row[prefix + "BackCount"], row[prefix + "NoneCount"], row)
                    elif row["expectedFront"] is False:
                        self.assertEqual(row[prefix + "BackCount"], 0, row)


    def test_projected_screen_sprites_keep_depth_test_and_write_independent(self) -> None:
        rows = self.result["projectedSpriteProfiles"].get("rows", [])
        self.assertEqual(len(rows), 8, "Real Metal readback for three cameras and native flag-off is required")
        expected = {
            "testWrite": [0, 0, 255, 255],
            "writeDisabled": [0, 255, 0, 255],
            "testDisabled": [0, 255, 0, 255],
            "bothDisabled": [0, 255, 0, 255],
            "writeWithoutTest": [0, 0, 255, 255],
            "farFirst": [0, 0, 255, 255],
        }
        for row in rows:
            with self.subTest(camera=row["camera"], space=row["space"]):
                self.assertGreater(row["nearDepth"], 0)
                self.assertLess(row["farDepth"], 1)
                self.assertLess(row["nearDepth"], row["farDepth"])
            for case, pixel in expected.items():
                with self.subTest(camera=row["camera"], space=row["space"], case=case):
                    self.assertEqual(row[case], pixel)


    def test_projected_screen_sprites_preserve_front_and_back_winding(self) -> None:
        rows = self.result["projectedSpriteProfiles"].get("rows", [])
        self.assertEqual(len(rows), 8, "Real Metal readback for three cameras and native flag-off is required")
        for row in rows:
            for case in ["frontBackCull", "reversedBackCull", "reversedNoCull"]:
                with self.subTest(camera=row["camera"], space=row["space"], case=case):
                    self.assertEqual(len(row[case]), 4)
                    if case == "reversedBackCull":
                        self.assertEqual(row[case], [0, 0, 0, 0])
                    else:
                        self.assertEqual(row[case][3], 255)


    def test_projected_screen_sprites_keep_texture_top_above_bottom(self) -> None:
        rows = self.result["projectedSpriteProfiles"].get("rows", [])
        self.assertEqual(len(rows), 8, "Real Metal readback for three cameras and native flag-off is required")
        for row in rows:
            for case, color_channel, opposite in [("topMarker", 2, 0), ("bottomMarker", 0, 2)]:
                with self.subTest(camera=row["camera"], space=row["space"], marker=case):
                    pixel = row[case]
                    self.assertEqual(len(pixel), 4)
                    self.assertEqual(pixel[3], 255)
                    self.assertGreater(pixel[color_channel], 200)
                    self.assertLess(pixel[opposite], 55)

    def test_native_rope_history_keeps_3d_endpoints_joins_and_texture_sides(self) -> None:
        rows = self.result["nativeRopeProfiles"]
        self.assertEqual(len(rows), 3, rows)
        for row in rows:
            with self.subTest(case=row.get("name")):
                self.assertTrue(row["completed"], row)
                self.assertEqual(row["instanceCount"], 2)
                self.assertTrue(row["preservesWorldModel"])
                self.assertGreater(row["visiblePixels"], 70)
                self.assertLessEqual(row["maximumAlpha"], 129)
                self.assertTrue(all(alpha >= 100 for alpha in row["pathAlpha"]), row)
                self.assertGreater(row["redPixels"], 15)
                self.assertGreater(row["bluePixels"], 15)
                for actual, expected in zip(row["bounds"], row["expectedBounds"], strict=True):
                    self.assertAlmostEqual(actual, expected, delta=8)
        self.assertEqual(rows[0]["pixelSHA256"], rows[1]["pixelSHA256"])
        self.assertGreater(rows[0]["bounds"][2] - rows[0]["bounds"][0],
                           (rows[2]["bounds"][2] - rows[2]["bounds"][0]) * 1.4)

    def test_native_rope_screen_width_stays_local_near_basis_projection_singularity(self) -> None:
        rows = self.result["ropeProjectionConditioning"]
        self.assertEqual(len(rows), 8, "Real production camera/shader/Metal readback is required")
        for row in rows:
            with self.subTest(case=row.get("name")):
                self.assertTrue(row["completed"], row)
                self.assertEqual(row["instanceCount"], 1)
                self.assertTrue(row["inputFinite"], row)
                self.assertTrue(row["preservesWorldModel"], row)
                for anchor_w in row["anchorW"]:
                    self.assertAlmostEqual(anchor_w, 10, places=4)
                # A singular width solution may decline this unsafe quad;
                # it must not paint unrelated pixels across the viewport.
                self.assertEqual(row["outsidePixels"], 0, row)
                if row["name"].startswith("safe-"):
                    self.assertGreater(row["visiblePixels"], 5, row)
                    self.assertAlmostEqual(row["maximumAlpha"], 128, delta=1)



if __name__ == "__main__":
    unittest.main()
