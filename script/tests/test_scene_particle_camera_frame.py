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
    SOURCE_ROOT / "Rendering/Geometry/SceneLayerVisibility.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleWorldSpacePlan.swift",
]


HARNESS_SOURCE = (Path(__file__).parent / "fixtures/SceneParticleCameraFrameHarness.swift").read_text(
    encoding="utf-8"
)


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

    def test_root_rope_camera_inherits_only_the_native_default(self) -> None:
        policy = self.result["ropeCameraPolicy"]
        self.assertEqual(len(policy), 11)
        for key, value in policy.items():
            with self.subTest(policy=key):
                self.assertTrue(value)

    def test_view_axes_follow_selected_projection_without_changing_sprite_geometry(self):
        self.assertEqual(len(self.result["selectedVPAxes"]), 6)
        for row in self.result["selectedVPAxes"]:
            for key in ("axes", "projection", "plane", "signedXY", "spriteGeometry"):
                with self.subTest(case=row["name"], field=key):
                    self.assertTrue(row[key], row)

    def test_typed_perspective_uses_one_immutable_camera_policy(self) -> None:
        for key in ("typedPerspectiveMatrixMatchesStatic", "typedFlatMatrixMatchesStatic",
                    "typedSnapshotCaptureIsImmutable", "typedFalseOverridesNative",
                    "authoredSeedPreservesNativeDefault", "typedUtilityStaysScreenSpace",
                    "layerCameraRescuesMissingFallback", "layerCameraDefaultMatchesFrame",
                    "layerCameraFalseOverridesInherited", "hiddenLayerCameraFallsBack",
                    "wrongTypedValueKeepsStatic", "catalogDefaultMatchesNativeFrame",
                    "catalogDefaultMatchesOrthoFrame"):
            self.assertTrue(self.result[key], key)

    def test_local_composition_separates_flat_capture_from_typed_output(self) -> None:
        for key in ("compositionStaticOutputIsPerspective", "compositionTypedOutputIsPerspective",
                    "compositionTypedFalseRestoresFlat", "compositionCaptureRemainsFlat",
                    "compositionNativeRemainsUnsupported", "ordinaryImageCaptureFollowsOutput"):
            self.assertTrue(self.result[key], key)

    def test_native_material_source_keeps_native_output_and_capture_projection(self) -> None:
        result = self.result["nativeMaterialSourceCamera"]
        self.assertTrue(result["usesPerspective"])
        self.assertEqual(result["output"], self.result["nativeWorldUpNDC"])
        self.assertEqual(result["capture"], result["output"])
        self.assertTrue(result["ordinaryOutputStaysFlat"])
        self.assertTrue(result["ordinaryCaptureStaysFlat"])

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

    def test_native_camera_selection_preserves_order_visibility_and_fallback(self) -> None:
        checks = self.result["nativeLayerSelection"]
        for name in (
            "reverseOrderSkipsHiddenAndOtherCameraKinds",
            "reverseOrderChangesWinner",
            "hiddenParentSkipsCamera",
            "dynamicParentVisibilitySkipsCamera",
            "dynamicParentVisibilityOverridesAuthored",
            "parentCycleSkipsCamera",
            "noDefaultCameraFallsBack",
            "selectedMissingWorldDoesNotPickOlderCamera",
            "selectedMissingFOVDoesNotPickOlderCamera",
            "selectedDynamicFOVIsConsumed",
        ):
            with self.subTest(case=name):
                self.assertTrue(checks[name])

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
