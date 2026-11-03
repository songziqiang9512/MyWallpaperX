#!/usr/bin/env python3

from __future__ import annotations

import json
import math
import unittest
from pathlib import Path

from script.tests.scene_particle_render_test_support import run_particle_harness


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    REPOSITORY_ROOT / "script/tests/fixtures/SceneLayerPerspectiveSnapshotHarness.swift",
    Path(__file__).resolve().parents[2] / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneResourceBudget.swift",
    REPOSITORY_ROOT / "script/tests/fixtures/SceneParticleFixedGeometryHarness.swift",
    REPOSITORY_ROOT / "script/tests/fixtures/SceneParticleCameraRenderingHarness.swift",
    REPOSITORY_ROOT / "script/tests/fixtures/SceneParticleOffscreenReadbackHarness.swift",
    SOURCE_ROOT / "Systems/Input/SceneCameraProjection.swift",
    SOURCE_ROOT / "Systems/Particles/SceneParticleCameraFrame.swift",
    SOURCE_ROOT / "Systems/Particles/SceneParticleTrailRenderPlan.swift",
    SOURCE_ROOT / "Systems/Particles/SceneParticleTextureSource.swift",
    SOURCE_ROOT / "Resources/Assets/SceneResourceView.swift",
    SOURCE_ROOT / "Resources/Assets/SceneResourceView+Backing.swift",
    SOURCE_ROOT / "Resources/Assets/SceneResourceIndex.swift",
    SOURCE_ROOT / "Resources/Assets/SceneResourceIdentity.swift",
    SOURCE_ROOT / "Format/ScenePkgReader.swift",

    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/ScenePerformanceCounterHub.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/SceneGPUCensus.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureSampling.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureUVTransform.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureLookupIdentity.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureCandidate.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Geometry/SceneMatrix.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneFramebufferSnapshot.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleDefinition.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleInitializer.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleAudioResponsePlan.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleVortex.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRemapValue.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleReduceMovement.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleCollisionPlane.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticlePositionAroundControlPoint.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleDefinitionParser.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleDefinitionParser+Operator.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Particles/SceneParticleRenderSupport.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleBoids.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulationSupport.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulationDiagnostic.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleCapVelocity.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleControlPointForce.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticlePeriodicEmission.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleStepSnapshotRecorder.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRopeTrailPlan.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRopePlan.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Particles/SceneParticleMetalInstanceBuffer.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRefractionBinding.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Particles/SceneParticleShaderSource.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Particles/SceneParticleSamplerStateSet.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Particles/SceneParticleMetalPipeline.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Particles/SceneParticleDepthTargetPool.swift",
]


FIXTURE_ROOT = Path(__file__).with_name("fixtures")
HARNESS_SUPPORT_SOURCE = (FIXTURE_ROOT / "SceneParticleRenderingSupport.swift").read_text(encoding="utf-8")
HARNESS_SOURCE = HARNESS_SUPPORT_SOURCE + "".join(
    (FIXTURE_ROOT / name).read_text(encoding="utf-8")
    for name in (
        "SceneParticleRenderingHarness.swift",
        "SceneParticleRenderingDrawCases.swift",
        "SceneParticleRenderingTrailCases.swift",
        "SceneParticleRenderingRefractionSamplingCases.swift",
    )
)


class SceneParticleRenderingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.result = run_particle_harness(tuple(SWIFT_SOURCES), HARNESS_SOURCE)

    def test_sprite_rotation_matches_authored_basis_sign_and_mixed_axis_order(self) -> None:
        # Public stock ComputeParticleTangents through the existing production
        # normalizer + glslang/SPIRV-Cross was read back on Metal. Positive Z
        # turns the right vector toward -Y; (.2,-.4,.7) produces basis right
        # (.754306,-.631376,-.179960), up (.534191,.749596,-.390826).
        clockwise = self.result["clockwiseSpriteMarkers"]
        counterclockwise = self.result["counterclockwiseSpriteMarkers"]
        for value in [clockwise, counterclockwise]:
            self.assertEqual([value["width"], value["height"]], [128, 32])
            self.assertEqual([value["centerX2"], value["centerY2"]], [287, 319])
            self.assertAlmostEqual(value["redX1000"], value["greenX1000"], delta=1000)
        self.assertLess(clockwise["redY1000"], clockwise["greenY1000"])
        self.assertGreater(counterclockwise["redY1000"], counterclockwise["greenY1000"])
        mixed = self.result["mixedAxisSpriteMarkers"]
        self.assertAlmostEqual(mixed["width"], 32 * .754306 + 128 * .534191, delta=2)
        self.assertAlmostEqual(mixed["height"], 32 * .631376 + 128 * .749596, delta=2)
        self.assertAlmostEqual(mixed["greenX1000"] - mixed["redX1000"], 16 * .754306 * 1000, delta=1000)
        self.assertAlmostEqual(mixed["greenY1000"] - mixed["redY1000"], 16 * .631376 * 1000, delta=1000)
        self.assertEqual([mixed["centerX2"], mixed["centerY2"]], [287, 319])
        oriented = self.result["orientedSpriteMarkers"]
        self.assertEqual([oriented["width"], oriented["height"]], [32, 128])
        self.assertLess(oriented["redX1000"], oriented["greenX1000"])
        self.assertAlmostEqual(oriented["redY1000"], oriented["greenY1000"], delta=1000)
        refract = self.result["refractionContract"]
        self.assertEqual(refract["rotatedShiftedX"], [100, 90, 40, 255])
        self.assertEqual(refract["reverseRotatedShiftedX"], [100, 50, 40, 255])

    def test_fixed_sprite_geometry_preserves_full_model_transform(self) -> None:
        results = [r for r in self.result["fixedGeometry"] if not r["mode"].startswith("localScreen")]
        if not results:
            self.skipTest("Metal vertex readback is unavailable")
        oracle = json.loads((REPOSITORY_ROOT / "script/tests/fixtures/scene_particle_fixed_geometry.json").read_text())
        self.assertEqual(len(results), len(oracle["cases"]))
        for actual, expected in zip(results, oracle["cases"]):
            with self.subTest(mode=expected["mode"], case=expected["name"]):
                self.assertEqual((actual["name"], actual["mode"]), (expected["name"], expected["mode"]))
                # Full vertex positions cover reflection, shear, signed depth,
                # arbitrary fixed axes, translation, and singular transforms.
                # Existing world-size/world-fixed/world-screen/upright modes and
                # normalized refraction direction are explicit controls.
                for field in ["positions", "tangents"]:
                    for av, ev in zip(actual[field], expected[field]):
                        for a, e in zip(av, ev):
                            self.assertAlmostEqual(a, e, delta=0.00002)

    def test_local_screen_singular_geometry_keeps_gpu_outputs_finite(self) -> None:
        results = [r for r in self.result["fixedGeometry"] if r["mode"].startswith("localScreen")]
        self.assertEqual(len(results), 26)
        for row in results:
            with self.subTest(mode=row["mode"], case=row["name"]):
                for field in ["positions", "tangents"]:
                    self.assertTrue(all(math.isfinite(v) for values in row[field] for v in values))
        collapsed = next(r for r in results if r["mode"] == "localScreen" and r["name"] == "parallelXY")
        self.assertTrue(all(abs(p[0] - 0.1) < 0.00002 for p in collapsed["positions"]))

    def test_cpu_and_msl_instance_layouts_match(self) -> None:
        self.assertEqual(self.result["instanceStride"], 160)
        self.assertEqual(self.result["instanceAlignment"], 16)
        self.assertEqual(self.result["instanceOffsets"], [0, 16, 32, 48, 64, 80, 96, 112, 128, 144])
        self.assertEqual(self.result["uniformStride"], 272)
        self.assertEqual(self.result["uniformOffsets"], [0, 64, 128, 144, 160, 168, 176, 192, 208, 224, 240, 256])

    def test_lifetime_sprite_selection_and_frame_blending(self) -> None:
        self.assertEqual(self.result["sequence"]["current"], 2)
        self.assertTrue(self.result["finiteExtremesAreSafe"])
        self.assertTrue(self.result["invalidPhasesRejected"])
        self.assertEqual(self.result["sequence"]["next"], 2)
        self.assertAlmostEqual(self.result["sequence"]["mix"], 0.5, places=6)
        self.assertEqual(self.result["preparedTimeline"], self.result["sequence"])
        self.assertEqual(self.result["noBlend"], {"current": 2, "next": 2, "mix": 0})
        self.assertEqual(self.result["reverse"], self.result["sequence"])
        self.assertGreater(len(set(self.result["randomIndices"])), 1)
        self.assertTrue(self.result["randomNoBlend"])
        self.assertTrue(self.result["modeSequence"])
        self.assertTrue(self.result["modeRandom"])

    def test_sequence_last_frame_holds_until_cycle_boundary_on_gpu(self) -> None:
        rows = self.result["sequenceEndPixels"]
        self.assertEqual(len(rows), 24)
        for row in rows:
            with self.subTest(prepared=row["prepared"], blend=row["blend"], age=row["age"]):
                phase = row["age"] % 1
                blue = 1 if phase >= 0.5 else (phase * 2 if row["blend"] else 0)
                expected = [255 * blue, 0, 255 * (1 - blue), 255]
                self.assertEqual(len(row["bgra"]), 4)
                for actual, wanted in zip(row["bgra"], expected):
                    self.assertAlmostEqual(actual, wanted, delta=2)

    def test_orientation_bases_are_authored_and_orthonormal(self) -> None:
        self.assertTrue(self.result["orientationDefault"])
        self.assertEqual(self.result["trailFrame"], [0, 1, 0, -1, 1, 0])
        self.assertEqual(self.result["screenRight"], [1, 0, 0])
        self.assertEqual(self.result["screenUp"], [0, 1, 0])
        self.assertEqual(self.result["uprightRight"], [1, 0, 0])
        self.assertEqual(self.result["uprightUp"], [0, -1, 0])
        self.assertEqual(self.result["fixedRight"], [0, 1, 0])
        self.assertEqual(self.result["fixedUp"], [0, 0, 1])
        self.assertNotEqual(self.result["localFixedRight"], self.result["worldFixedRight"])
        self.assertEqual(self.result["worldFixedRight"], [1, 0, 0])
        self.assertEqual(self.result["worldFixedUp"], [0, -1, 0])


    def test_both_blend_states_compile_and_encode_instanced_draws(self) -> None:
        self.assertEqual(self.result["translucentBlend"], [True, True, True, True])
        self.assertEqual(self.result["additiveBlend"], [True, True, True, True])
        self.assertTrue(self.result["metalDraw"])

    def test_additive_fractional_alpha_is_applied_once(self) -> None:
        pixel = self.result["additiveFractionalAlphaPixel"]
        if not pixel:
            self.skipTest("Metal offscreen draw is unavailable")
        for channel in pixel:
            self.assertAlmostEqual(channel, 64, delta=2)





    def test_non_square_sprite_geometry_tracks_current_and_blended_frame_aspect(self) -> None:
        wide = self.result["spriteAspectBounds"]
        blended = self.result["blendedSpriteAspectBounds"]
        if not wide or not blended:
            self.skipTest("Metal offscreen draw is unavailable")
        self.assertGreater(wide["width"], wide["height"] * 1.8)
        self.assertGreater(blended["width"], blended["height"] * 1.1)
        self.assertLess(blended["width"], blended["height"] * 1.4)

    def test_sprite_size_is_width_based_and_center_does_not_move(self) -> None:
        square = self.result["squareSpriteBounds"]
        wide = self.result["spriteAspectBounds"]
        tall = self.result["tallSpriteBounds"]
        rotated = self.result["rotatedTallSpriteBounds"]
        scaled = self.result["scaledTallSpriteBounds"]
        blended = self.result["blendedSpriteAspectBounds"]
        self.assertTrue(square, "Metal GPU readback is required")
        self.assertEqual([square["width"], square["height"]], [32, 32])
        self.assertEqual([wide["width"], wide["height"]], [32, 16])
        self.assertEqual([tall["width"], tall["height"]], [32, 128])
        self.assertEqual([rotated["width"], rotated["height"]], [128, 32])
        self.assertEqual([scaled["width"], scaled["height"]], [64, 64])
        self.assertEqual(blended["width"], 32)
        self.assertAlmostEqual(blended["height"], 32 / 1.25, delta=1)
        for value in [wide, tall, rotated, blended]:
            self.assertEqual(value["centerX2"], square["centerX2"])
            self.assertEqual(value["centerY2"], square["centerY2"])
        self.assertEqual([scaled["centerX2"], scaled["centerY2"]], [191, 287])


    def test_upright_preserves_system_or_world_axis_under_camera_roll(self) -> None:
        contract = self.result["uprightGeometry"]
        rows = contract["rows"]
        for name, row in rows.items():
            with self.subTest(name=name):
                self.assertEqual(row["pixels"], row["expectedPixels"])
                self.assertGreater(row["pixels"]["width"], 0)
                self.assertGreater(row["pixels"]["height"], 0)
        for roll in [0, 89, 90, 91, 180]:
            for prefix in ["roll", "localRoll", "projectedRoll"]:
                self.assertEqual(rows[f"{prefix}{roll}"]["right"], [1, 0, 0])
                self.assertEqual(rows[f"{prefix}{roll}"]["up"], [0, -1, 0])
        for name in ["localRotated", "localScaled"]:
            for actual, expected in zip(rows[name]["up"], [1, 0, 0]):
                self.assertAlmostEqual(actual, expected, places=5)
        self.assertEqual(rows["worldRotated"]["up"], [0, -1, 0])
        self.assertEqual(rows["localMirrored"]["up"], [0, 1, 0])
        self.assertTrue(contract["fixedDirectionsUnchanged"])
        for actual, expected in zip(rows["screenRotated"]["up"], [1, 0, 0]):
            self.assertAlmostEqual(actual, expected, places=5)
        self.assertEqual(rows["screenWorldRotated"]["up"], [0, -1, 0])
        self.assertGreater(rows["screenRotated"]["pixels"]["width"],
                           rows["screenRotated"]["pixels"]["height"])
        self.assertAlmostEqual(rows["screenTilted"]["up"][1], -0.5, places=5)
        self.assertAlmostEqual(contract["screenRolledUp"][0], 1, places=5)

    def test_upright_sprite_trail_renders_under_roll_and_tilt(self) -> None:
        trails = self.result["uprightGeometry"]["trails"]
        for name, metrics in trails.items():
            with self.subTest(name=name):
                if name == "pole":
                    # The vertical card is viewed exactly edge-on; GPU completes
                    # and retains the clear target, without invented thickness.
                    self.assertEqual(metrics, {"width": 0, "height": 0})
                else:
                    self.assertGreater(metrics["width"], 0)
                    self.assertGreater(metrics["height"], 0)
                    self.assertLess(metrics["width"], 256)
                    self.assertLess(metrics["height"], 256)

    def test_upright_parallel_view_fallback_keeps_authoritative_axis(self) -> None:
        contract = self.result["uprightGeometry"]
        for prefix in ["pole", "degenerate"]:
            self.assertEqual(contract[f"{prefix}Right"], [1, 0, 0])
            self.assertEqual(contract[f"{prefix}Up"], [0, -1, 0])
        self.assertEqual(contract["rows"]["zeroAxis"]["up"], [0, -1, 0])

    def test_sprite_trails_align_and_stretch_along_velocity(self) -> None:
        horizontal = self.result["horizontalTrailBounds"]
        vertical = self.result["verticalTrailBounds"]
        rotated = self.result["rotatedTrailBounds"]
        self.assertGreater(horizontal["width"], horizontal["height"] * 2.5)
        self.assertGreater(vertical["height"], vertical["width"] * 2.5)
        self.assertGreater(rotated["height"], rotated["width"] * 2.5)

    def test_numeric_and_text_rotation_reach_distinct_gpu_geometry(self) -> None:
        numeric = self.result["numericRotationBounds"]
        text = self.result["textRotationBounds"]
        self.assertGreater(numeric["width"], 0)
        self.assertEqual(numeric, self.result["explicitZRotationBounds"])
        self.assertEqual(text, self.result["explicitXRotationBounds"])
        self.assertNotEqual(numeric, text)
        self.assertNotEqual(numeric, self.result["broadcastRotationBounds"])

    def test_omitted_trail_bounds_change_actual_gpu_extent_with_speed(self) -> None:
        bounds = self.result["defaultTrailBounds"]
        self.assertEqual(bounds["omitted"], bounds["explicit"])
        widths = [item["width"] for item in bounds["omitted"]]
        self.assertGreater(widths[1], widths[0] + 3)
        self.assertGreater(widths[2], widths[1] + 3)
        self.assertEqual(len({item["height"] for item in bounds["omitted"]}), 1)
        self.assertEqual(len({item["width"] for item in bounds["fixed"]}), 1)
        self.assertGreater(bounds["fixed"][0]["width"], 0)

    def test_general_worldspace_size_is_independent_of_layer_scale(self) -> None:
        baseline = self.result["worldIdentityWidth"]
        world = self.result["worldScaledWidth"]
        local = self.result["localScaledWidth"]
        mirror = self.result["worldMirroredWidth"]
        override = self.result["worldSizeOverrideWidth"]
        self.assertGreater(baseline["height"], 0)
        self.assertEqual(world["height"], baseline["height"])
        self.assertEqual(mirror["height"], baseline["height"])
        self.assertGreater(local["height"], world["height"] * 8)
        self.assertGreater(world["width"], baseline["width"] * 8)
        self.assertGreater(override["height"], world["height"] * 3)

    def test_sprite_trail_frame_aspect_changes_only_length_after_stretch_limits(self) -> None:
        bounds = self.result["trailAspectBounds"]
        square = bounds["square"]
        for name, factor in [("tall", 4), ("wide", 0.25), ("blended", 2),
                             ("minimum", 4), ("maximum", 6)]:
            with self.subTest(name=name):
                self.assertAlmostEqual(bounds[name]["width"], square["width"] * factor, delta=3)
                self.assertEqual(bounds[name]["height"], square["height"])
        self.assertGreater(bounds["wide"]["width"], 0)
        self.assertEqual(bounds["displacementTall"], bounds["displacementSquare"])

    def test_rope_trail_joins_have_no_gap_or_double_alpha(self) -> None:
        results = self.result["ropeTrailJoins"]
        self.assertEqual(len(results), 5)
        for result in results:
            with self.subTest(transform=result.get("transform")):
                self.assertTrue(result["completed"])
                self.assertTrue(result["jointCovered"])
                self.assertGreater(result["visiblePixels"], 1000)
                self.assertLessEqual(result["maximumAlpha"], 129)

    def test_rope_particle_joins_have_no_gap_or_double_alpha(self) -> None:
        results = self.result["ropeJoins"]
        self.assertEqual(len(results), 7)
        for result in results:
            with self.subTest(transform=result.get("transform")):
                self.assertTrue(result["completed"])
                self.assertTrue(result["jointCovered"])
                self.assertGreater(result["visiblePixels"], 1000)
                self.assertLessEqual(result["maximumAlpha"], 129)
        taper = results[5]["columnWidths"]
        self.assertLess(taper[0], taper[1])
        self.assertLess(taper[1], taper[2])
        self.assertGreater(taper[2], taper[3])
        self.assertGreater(taper[3], taper[4])
        self.assertLessEqual(taper[4], 2)

    def test_rope_trail_history_draws_a_multisegment_fading_path(self) -> None:
        contract = self.result["ropeTrailRender"]
        if not contract["available"]:
            self.skipTest("Metal offscreen draw is unavailable")
        self.assertEqual(contract["instanceCount"], 4)
        self.assertEqual(contract["horizontalSegments"], 2)
        self.assertEqual(contract["verticalSegments"], 2)
        self.assertGreater(contract["width"], 45)
        self.assertGreater(contract["height"], 45)
        self.assertGreater(contract["visiblePixels"], 400)
        self.assertGreater(contract["headAlpha"], contract["tailAlpha"] * 2)

    def test_rope_segment_endpoints_follow_the_transformed_history_displacement(self) -> None:
        contract = self.result["ropeTrailTransform"]
        if not contract["available"]:
            self.skipTest("Metal offscreen draw is unavailable")
        self.assertGreater(contract["visiblePixels"], 100)
        pixel_tolerance = 5 / 256 * 2
        self.assertLessEqual(
            abs(contract["observedTail"] - contract["expectedTail"]),
            pixel_tolerance,
        )
        self.assertLessEqual(
            abs(contract["observedHead"] - contract["expectedHead"]),
            pixel_tolerance,
        )

    def test_diagonal_rope_cross_section_is_perpendicular_in_wide_viewport_pixels(self) -> None:
        contract = self.result["ropeTrailAspect"]
        if not contract["available"]:
            self.skipTest("Metal offscreen draw is unavailable")
        self.assertGreater(contract["visiblePixels"], 100)
        self.assertGreater(contract["varianceRatio"], 4)
        self.assertGreater(contract["legacyAbsoluteDot"], 0.35)
        self.assertLess(contract["absoluteDot"], 0.12)

    def test_color_contract_adapts_r8_and_rg88_particle_textures(self) -> None:
        contract = self.result["colorContract"]
        raw = contract["rawR8"]
        adapted = contract["adaptedR8"]
        if not raw or not adapted:
            self.skipTest("Metal offscreen draw is unavailable")
        # 未适配的 r8Unorm 采样得 (r,0,0,1):BGRA 读回蓝/绿为 0、红为灰度。
        self.assertEqual(raw[0], 0)
        self.assertEqual(raw[1], 0)
        self.assertGreater(raw[2], 150)
        # R8 straight white/alpha becomes premultiplied white at the fragment boundary.
        self.assertGreater(adapted[0], 150)
        self.assertEqual(adapted[0], adapted[1])
        self.assertEqual(adapted[1], adapted[2])
        self.assertEqual(adapted[2], adapted[3])
        self.assertEqual(contract["rgMipCount"], 2)
        self.assertEqual(contract["rgPixel"], [128, 128, 128, 128])
        self.assertEqual(contract["rgSecondMip"], [16, 16, 16, 64])

    def test_straight_color_filtering_precedes_texture_coverage(self) -> None:
        rows = self.result["straightInterpolation"]
        self.assertEqual(len(rows), 160)
        for row in rows:
            with self.subTest(**{k: v for k, v in row.items() if k != "bgra"}):
                t, a = row["mix"], row["alpha"]
                coverage = t * a
                background = row["background"] * (1 if row["additive"] else 1 - coverage)
                gain = coverage * row["overbright"]
                expected = [(t * gain + background) * 255, background * 255,
                            ((1 - t) * gain + background) * 255, coverage * 255]
                self.assertEqual(len(row["bgra"]), 4)
                for observed, value in zip(row["bgra"], expected):
                    self.assertAlmostEqual(observed, min(255, value), delta=2)

    def test_in_flight_instance_slots_are_not_reused_until_completion(self) -> None:
        slots = self.result["instanceBufferSlots"]
        self.assertTrue(slots["available"])
        self.assertTrue(slots["firstSubmitted"])
        self.assertTrue(slots["secondSubmitted"])
        self.assertTrue(slots["thirdSubmitted"])
        self.assertTrue(slots["firstPreserved"])
        self.assertTrue(slots["grewForSecond"])
        self.assertTrue(slots["grewForThird"])
        self.assertTrue(slots["firstCompleted"])
        self.assertTrue(slots["reusedFirst"])
        self.assertTrue(slots["cleanupCompleted"])

    def test_uncommitted_particle_slots_are_cancelled_and_reusable(self) -> None:
        slots = self.result["instanceBufferPendingCancellation"]
        self.assertTrue(slots["available"])
        self.assertTrue(slots["pendingCancelled"])
        self.assertTrue(slots["pendingCleared"])
        self.assertTrue(slots["reusedAfterPending"])
        self.assertTrue(slots["marked"])
        self.assertTrue(slots["uncommittedCancelled"])
        self.assertTrue(slots["uncommittedCleared"])
        self.assertTrue(slots["reusedAfterSubmissionCancel"])
        self.assertTrue(slots["idempotentCancel"])
        self.assertTrue(slots["cancelInFlightRejected"])
        self.assertTrue(slots["inFlightCountPreserved"])
        self.assertTrue(slots["cancelAfterCompletionRejected"])
        self.assertTrue(slots["reusedAfterCompletion"])

    def test_retired_root_and_child_buffers_live_only_until_original_command_finishes(self) -> None:
        facts = self.result["topologyRetirement"]
        for name in (
            "available", "rootAndChildHaveDistinctOwners", "rootAndChildSubmitted",
            "pendingGPUKeepsRetiredOwners", "healthyPeerReusesOwner",
            "healthyPeerPendingCancelled", "retiredSubmissionCompleted",
            "completedGPUReleasesRootKey", "completedGPUReleasesChildKey",
            "unsubmittedRootAndChildArmed", "unsubmittedReservationsCancelled",
            "cancelledCommandReleasesRootKey", "cancelledCommandReleasesChildKey",
            "peerSurvivesBothRetirements",
        ):
            with self.subTest(fact=name):
                self.assertTrue(facts[name])

    def test_refraction_mask_and_particle_alpha_attenuate_displacement(self) -> None:
        value = self.result["refractionContract"]
        # The 8x8 framebuffer has a 20/texel blue gradient. Full displacement
        # is two texels (amount 0.25 screen UV). Mask changes the sampled location; particle alpha
        # changes both location and compositing coverage. Albedo alpha only
        # changes coverage. These are independent authored channels.
        expected = {
            "maskedOut": 100, "halfMask": 120, "halfAlpha": 110,
            "halfMaskHalfAlpha": 105, "zeroAlpha": 100, "halfAlbedo": 120,
        }
        for name, blue in expected.items():
            with self.subTest(name=name):
                self.assertEqual(len(value[name]), 4)
                self.assertLessEqual(abs(value[name][0] - blue), 1)
                self.assertLessEqual(abs(value[name][1] - 70), 1)
                self.assertEqual(value[name][2:], [40, 255])

    def test_refraction_samples_the_preceding_framebuffer(self) -> None:
        contract = self.result["refractionContract"]
        neutral = contract["neutral"]
        shifted = contract["shifted"]
        if not neutral or not shifted:
            self.skipTest("Metal refraction draw is unavailable")
        # The center's original BGRA is [100,70,40,255]. A neutral normal must
        # preserve it; +X moves the sampled blue gradient toward larger values.
        self.assertLessEqual(max(abs(a - b) for a, b in zip(
            neutral, [100, 70, 40, 255]
        )), 2)
        self.assertGreater(shifted[0], neutral[0] + 15)
        self.assertEqual(shifted[1], neutral[1])

    def test_rope_trail_refraction_rotates_normal_axes_into_path_space(self) -> None:
        contract = self.result["refractionContract"]
        neutral = contract["trailNeutral"]
        along = contract["trailAlong"]
        across = contract["trailAcross"]
        if not neutral or not along or not across:
            self.skipTest("Metal refraction draw is unavailable")
        # Public REFRACT packing combines both particle axes against each
        # view axis. For rightward trail geometry, +normalY samples left;
        # +normalX samples down. It is not the UV-to-position Jacobian.
        self.assertLess(along[0], neutral[0] - 15)
        self.assertLessEqual(abs(along[1] - neutral[1]), 2)
        self.assertGreater(across[1], neutral[1] + 8)
        self.assertLessEqual(abs(across[0] - neutral[0]), 2)

    def test_sprite_refraction_amount_is_independent_of_texture_aspect(self) -> None:
        value = self.result["refractionContract"]
        self.assertTrue(value["tallShiftedX"])
        self.assertEqual(value["tallShiftedX"], value["shifted"])
        self.assertEqual(value["squareShiftedY"], value["tallShiftedY"])
        self.assertGreater(value["squareShiftedY"][1], value["neutral"][1])

    def test_rope_trail_refraction_amount_is_independent_of_uv_span_and_stretch(self) -> None:
        value = self.result["refractionContract"]
        self.assertTrue(value["fullSpanShortStretch"])
        self.assertLess(value["fullSpanShortStretch"][0], value["magnitudeNeutral"][0] - 15)
        self.assertEqual(value["fullSpanShortStretch"], value["fullSpanLongStretch"])
        self.assertEqual(value["fullSpanShortStretch"], value["halfSpanLongStretch"])

    def test_refraction_basis_matches_public_shader_direction_contract(self) -> None:
        # RGBA32Float oracle from public ComputeParticleTangents and
        # ComputeScreenRefractionTangents through the production compiler.
        expected = [
            [1,0,0,1], [0,1,-1,0], [0,-1,1,0],
            [.75430655,.53419143,-.63137633,.74959618],
            [.70710677,-.5,0,.70710677], [1,0,0,.70710677],
            [.66062647,.65408611,-.63137633,.74959618],
            [.63137633,-.74959624,.75430655,.53419149],
        ]
        actual = self.result["refractionBasisCases"]
        self.assertEqual(len(actual), 13)
        # Size, aspect, anisotropic layer scale, position and projection depth
        # do not set Sprite REFRACT strength. A tilted native camera supplies
        # its own view basis, independent of the fixed particle orientation.
        expected += [expected[3]] * 5
        for index, (observed, reference) in enumerate(zip(actual, expected)):
            with self.subTest(index=index):
                self.assertEqual(len(observed), 4)
                for component, target in zip(observed, reference):
                    self.assertAlmostEqual(component, target, delta=0.00001)

    def test_trail_refraction_directions_remain_bounded_at_joins_and_collapses(self) -> None:
        values = self.result["refractionTrailBasisCases"]
        self.assertEqual(len(values), 7)
        for value in values[:3]:
            self.assertEqual(len(value), 4)
            self.assertTrue(all(-1.00001 <= component <= 1.00001 for component in value))
        for actual, expected in zip(values[:2], [[0,1,-1,0],[0,-1,1,0]]):
            for component, target in zip(actual, expected):
                self.assertAlmostEqual(component, target, delta=0.00001)
        # Completed zero-area geometry leaves the clear target untouched.
        # Failure to compile/encode/complete returns [] instead of this marker.
        for value in values[3:]:
            self.assertEqual(value, [99,99,99,99])

    def test_tex_flags_select_filter_and_address_modes_without_cross_talk(self) -> None:
        values = self.result["texSampling"]
        self.assertEqual(values["default"], {
            "filter": "linear",
            "address": "clampToEdge",
            "clampBorderFallback": False,
        })
        self.assertEqual(values["flags0"], {
            "filter": "linear",
            "address": "repeatWrap",
            "clampBorderFallback": False,
        })
        self.assertEqual(values["flags1"]["filter"], "nearest")
        self.assertEqual(values["flags1"]["address"], "repeatWrap")
        self.assertEqual(values["flags2"]["filter"], "linear")
        self.assertEqual(values["flags2"]["address"], "clampToEdge")
        self.assertEqual(values["flags3"]["filter"], "nearest")
        self.assertEqual(values["flags3"]["address"], "clampToEdge")
        self.assertEqual(values["flags4"], values["flags0"])
        self.assertEqual(values["alphaPriority"], values["flags0"])
        self.assertEqual(values["flags8"]["address"], "clampToEdge")
        self.assertTrue(values["flags8"]["clampBorderFallback"])

    def test_repeat_sampler_restores_sprite_frame_uvs_beyond_one(self) -> None:
        pixels = self.result["samplerPixels"]
        clamp = pixels["clamp"]
        repeat = pixels["repeat"]
        if not clamp or not repeat:
            self.skipTest("Metal sampler draw is unavailable")
        # Frame UV V=1...2:clamp collapses onto the red lower edge,repeat wraps
        # into the green/red atlas instead of stretching that edge across the quad.
        self.assertGreater(clamp[2], 240)
        self.assertLess(clamp[1], 5)
        self.assertGreater(repeat[1], clamp[1] + 40)
        self.assertNotEqual(repeat, clamp)

    def test_sampler_uses_authored_mip_chain_and_preserves_single_level_textures(
        self,
    ) -> None:
        pixels = self.result["mipSamplerPixels"]
        linear = pixels["linear"]
        nearest = pixels["nearest"]
        single_level = pixels["singleLevel"]
        if not linear or not nearest or not single_level:
            self.skipTest("Metal mip sampler draw is unavailable")
        # BGRA: the minified multi-level texture selects green lower mips,
        # while the single-level texture remains blue at LOD0.
        self.assertGreater(linear[1], 240)
        self.assertLess(linear[2], 5)
        self.assertGreater(nearest[1], 240)
        self.assertLess(nearest[2], 5)
        self.assertGreater(single_level[0], 240)
        self.assertLess(single_level[1], 5)


if __name__ == "__main__":
    unittest.main()
