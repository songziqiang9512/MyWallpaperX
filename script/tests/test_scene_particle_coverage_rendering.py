#!/usr/bin/env python3
"""Real Runtime geometry and independent hardware A2C/material readback."""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from script.tests.test_scene_particle_material_coverage import (
    BASE_HARNESS, NO_TIMESTAMP_OBSERVATION_SUPPORT, SWIFT_SOURCES,
)


FIXTURE = Path(__file__).resolve().parent / "fixtures/SceneParticleCoverageRenderingHarness.swift"
COVERAGE_MAIN = r'''
    static func main() throws {
        try printJSON(SceneParticleCoverageRenderingHarness.run())
    }

'''


class SceneParticleCoverageRenderingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if not swiftc:
            raise unittest.SkipTest("swiftc is unavailable")
        temporary = tempfile.TemporaryDirectory(prefix="mwx-particle-coverage-rendering-")
        cls.addClassCleanup(temporary.cleanup)
        directory = Path(temporary.name)
        source = BASE_HARNESS.read_text()
        start = source.index("    static func main() throws {")
        end = source.index("    static func renderDescriptor(", start)
        harness = directory / BASE_HARNESS.name
        harness.write_text(NO_TIMESTAMP_OBSERVATION_SUPPORT + source[:start] + COVERAGE_MAIN + source[end:])
        binary = directory / "coverage-rendering"
        compilation = subprocess.run([
            swiftc, "-D", "DEBUG", *(str(path) for path in SWIFT_SOURCES), str(harness),
            str(FIXTURE), str(FIXTURE.with_name("SceneParticleOffscreenReadbackHarness.swift")),
            "-framework", "Metal", "-framework", "CoreGraphics", "-framework", "ImageIO",
            "-module-cache-path", str(directory / "module-cache"), "-o", str(binary),
        ], capture_output=True, text=True)
        if compilation.returncode:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run([str(binary)], capture_output=True, text=True,
            env={**os.environ, "MWX_SCENE_PARTICLE_COMPONENT_OBSERVATION": "1"})
        if completed.returncode:
            raise RuntimeError(completed.stderr)
        cls.result = json.loads(completed.stdout)

    @staticmethod
    def pixels(row: dict[str, object]) -> list[list[int]]:
        values = row["actual"]
        return [values[index:index + 4] for index in range(0, len(values), 4)]

    def test_texture_and_particle_alpha_each_act_once_against_hardware_coverage(self) -> None:
        rows = self.result["coverage"]
        self.assertEqual(self.result["sampleCount"], 1)
        self.assertEqual(len(rows), 16, "Eight real Sprite alpha pairs with both depth attachment states")
        for row in rows:
            with self.subTest(texture=row["textureAlpha"], particle=row["particleAlpha"], depth=row["depth"]):
                self.assertTrue(row["encoded"], row)
                self.assertTrue(row["completed"], row)
                self.assertEqual(len(row["actual"]), 64 * 4)
                self.assertLessEqual(row["maximumByteError"], 1, row)

    def test_transparent_inputs_preserve_destination_and_opaque_inputs_preserve_rgb(self) -> None:
        for row in self.result["coverage"]:
            if row["textureAlpha"] == 0 or row["particleAlpha"] == 0:
                expected = [16, 24, 40, 102]
            elif row["textureAlpha"] == 255 and row["particleAlpha"] == 1:
                # (240,80,32) * particle RGB(.5,.75,1.25) * overbright1.2.
                expected = [144, 72, 48, 255]
            else:
                continue
            with self.subTest(texture=row["textureAlpha"], particle=row["particleAlpha"], depth=row["depth"]):
                for pixel in self.pixels(row):
                    self.assertEqual(pixel, expected)

    def test_covered_fragments_keep_straight_rgb_and_alpha_to_one(self) -> None:
        # Coverage decisions remain GPU-defined. Every stored pixel must be
        # untouched clear or full straight RGB, never alpha-attenuated RGB.
        allowed = ([16, 24, 40, 102], [144, 72, 48, 255])
        for row in self.result["coverage"]:
            with self.subTest(texture=row["textureAlpha"], particle=row["particleAlpha"], depth=row["depth"]):
                for pixel in self.pixels(row):
                    self.assertIn(pixel, allowed)

    def test_existing_translucent_and_additive_particles_keep_pma_output(self) -> None:
        rows = self.result["ordinary"]
        self.assertEqual(len(rows), 4)
        expected = {"translucent": [66, 43, 43, 162], "additive": [72, 52, 59, 162]}
        for row in rows:
            with self.subTest(mode=row["mode"], depth=row["depth"]):
                self.assertTrue(row["encoded"])
                self.assertTrue(row["completed"])
                self.assertLessEqual(row["maximumByteError"], 1, row)
                for pixel in self.pixels(row):
                    for actual, value in zip(pixel, expected[row["mode"]], strict=True):
                        self.assertAlmostEqual(actual, value, delta=1)

    def test_unrequested_coverage_pso_rejects_only_coverage_draw(self) -> None:
        rows = self.result["missing"]
        self.assertEqual(len(rows), 2)
        for row in rows:
            with self.subTest(depth=row["depth"]):
                self.assertTrue(row["unpreparedCoverageAttempted"])
                self.assertFalse(row["unpreparedCoverageEncoded"], row)
                self.assertTrue(row["encoded"], "Healthy PMA draw must still encode on the same encoder")
                self.assertTrue(row["completed"])
                self.assertLessEqual(row["maximumByteError"], 1, row)

    def test_shared_depth_attachment_does_not_change_no_depth_coverage(self) -> None:
        rows = self.result["coverage"]
        plain = {(row["textureAlpha"], row["particleAlpha"]): row for row in rows if not row["depth"]}
        shared = {(row["textureAlpha"], row["particleAlpha"]): row for row in rows if row["depth"]}
        self.assertEqual(len(plain), 8)
        self.assertEqual(plain.keys(), shared.keys())
        for key, row in plain.items():
            with self.subTest(alpha_pair=key):
                self.assertEqual(row["actual"], shared[key]["actual"])

    def test_runtime_live_rope_is_distinct_from_per_particle_trail_history(self) -> None:
        rows = {row["name"]: row for row in self.result["runtime"]}
        for name, live, instances, history in (
            ("acuteOpaque", 4, 21, False), ("zeroSpan", 4, 0, False),
            ("singleRope", 1, 0, False), ("movingSpriteTrail", 1, 1, False),
        ):
            with self.subTest(name=name):
                fact = rows[name]["facts"][0]
                self.assertEqual((fact["liveParticles"], fact["instances"], fact["history"]),
                                 (live, instances, history), fact)
                self.assertTrue(fact["requiredCoverage"], fact)
        trail = rows["movingRopeTrail"]
        fact = trail["facts"][0]
        self.assertEqual(fact["liveParticles"], 1)
        self.assertTrue(fact["history"])
        self.assertTrue(fact["inheritsNativeSceneCamera"])
        self.assertGreater(fact["instances"], 1)
        self.assertGreater(trail["changedPixels"], 0)
        for name in ("zeroSpan", "singleRope"):
            self.assertEqual(rows[name]["vertexCount"], 0)
            self.assertEqual(rows[name]["changedPixels"], 0)
            self.assertEqual(rows[name]["encoded"], [False])

    def test_runtime_material_draws_match_independent_hardware_coverage(self) -> None:
        rows = self.result["runtime"]
        self.assertEqual(len(rows), 24)
        for row in rows:
            with self.subTest(name=row["name"]):
                self.assertTrue(row["completed"], row)
                self.assertTrue(row["verticesFinite"], row)
                self.assertLessEqual(row["maximumByteError"], 1, row)
                for fact in row["facts"]:
                    self.assertEqual(fact["textureExtent"], [4, 16])
                    self.assertEqual(fact["actualRenderer"], fact["renderer"], fact)
                    self.assertEqual(fact["usesSceneCamera"], fact["renderer"] == "sprite", fact)
        for name in ("acutePartial", "acuteParticleZero", "acuteTextureZero"):
            row = next(row for row in rows if row["name"] == name)
            self.assertTrue(row["encoded"][0])
            self.assertLessEqual(set(row["histogram"]), {"16,24,40,102", "96,160,224,255"})
            if name != "acutePartial":
                self.assertEqual(row["changedPixels"], 0, row)

    def test_real_rope_joins_and_frozen_node_interiors_survive_the_production_vertex(self) -> None:
        rows = {row["name"]: row for row in self.result["runtime"]}
        rope = rows["acuteOpaque"]
        self.assertEqual(rope["vertexCount"], 21 * 4)
        self.assertLessEqual(rope["maximumJoinGapPixels"], 0.002)
        self.assertGreater(rope["changedPixels"], 0)
        for pixel in rope["nodePixels"]:
            self.assertEqual(pixel, [96, 160, 224, 255])
        self.assertEqual(rope["outsidePixels"], [[16, 24, 40, 102]] * 2)
        for name in ("renamedRibbon", "movingRopeTrail", "rope-back", "rope-backMirror",
                     "rope-noCullMirror", "ropetrail-back", "ropetrail-backMirror", "ropetrail-noCullMirror"):
            with self.subTest(name=name):
                self.assertLessEqual(rows[name]["maximumJoinGapPixels"], 0.002)
        renamed = rows["renamedRibbon"]
        self.assertEqual(renamed["histogram"], rope["histogram"])
        self.assertEqual(renamed["vertexBounds"], rope["vertexBounds"])
        self.assertEqual(renamed["nodePixels"], rope["nodePixels"])
        bounds = rows["movingSprite"]["vertexBounds"]
        # Authored size16 becomes ABI size8, spanning quad X[-.5,.5].
        # Aspect4/16 makes height32; the 128x96 logical canvas and target
        # have the same extent, so neither axis gains a raster scale.
        self.assertAlmostEqual(bounds[2] - bounds[0], 8, delta=0.001)
        self.assertAlmostEqual(bounds[3] - bounds[1], 32, delta=0.001)

    def test_authored_back_cull_and_no_cull_use_the_real_mirrored_geometry(self) -> None:
        rows = {row["name"]: row for row in self.result["runtime"]}
        for renderer in ("rope", "ropetrail", "spritetrail", "sprite"):
            for suffix, cull, mirrored in (("back", "back", False), ("backMirror", "back", True),
                                           ("noCullMirror", "none", True)):
                row = rows[f"{renderer}-{suffix}"]
                with self.subTest(name=row["name"]):
                    self.assertEqual(row["facts"][0]["cull"], cull)
                    self.assertEqual(row["mirrored"], mirrored)
                    self.assertEqual(row["encoded"], [True])
                    self.assertLessEqual(row["maximumByteError"], 1)
                    if suffix != "backMirror":
                        self.assertGreater(row["changedPixels"], 0)
        # Ribbon perpendiculars can preserve winding under a reflection. The
        # independent Sprite neighbor makes a no-op back-cull implementation fail.
        self.assertEqual(rows["sprite-backMirror"]["changedPixels"], 0)
        self.assertGreater(rows["sprite-noCullMirror"]["changedPixels"], 0)

    def test_missing_rope_coverage_pso_keeps_the_same_encoder_ordinary_peer_healthy(self) -> None:
        row = next(row for row in self.result["runtime"] if row["name"] == "missingPSO")
        self.assertEqual(row["encoded"], [False, True])
        self.assertEqual([fact["requiredCoverage"] for fact in row["facts"]], [True, False])
        self.assertEqual(row["facts"][0]["instances"], 21)
        self.assertEqual(row["peerPixel"], [192, 96, 48, 255])
        self.assertEqual(row["nodePixels"], [[16, 24, 40, 102]] * 18)
        self.assertGreater(row["changedPixels"], 0)
        self.assertLessEqual(row["maximumByteError"], 1)

    def test_overbright_above_sixty_four_reaches_the_real_fragment_without_saturation(self) -> None:
        row = next(row for row in self.result["runtime"] if row["name"] == "overbright65")
        self.assertEqual(row["facts"][0]["overbright"], 65)
        self.assertEqual(row["facts"][0]["textureRGBA"], [1, 2, 3, 255])
        self.assertEqual(row["encoded"], [True])
        for pixel in row["nodePixels"]:
            for actual, expected in zip(pixel, [65, 130, 195, 255], strict=True):
                self.assertAlmostEqual(actual, expected, delta=1)
        self.assertGreater(row["changedPixels"], 0)
        self.assertLessEqual(row["maximumByteError"], 1)

    def test_common_depth_writer_readonly_and_ordinary_blend_share_the_real_attachment(self) -> None:
        rows = self.result["runtimeDepth"]
        self.assertEqual(len(rows), 40)
        for row in rows:
            with self.subTest(name=row["name"]):
                self.assertTrue(row["completed"])
                self.assertTrue(row["usesDepthAttachment"])
                self.assertTrue(all(row["encoded"]), row)
                self.assertTrue(row["verticesFinite"])
                self.assertLessEqual(row["maximumByteError"], 1, row)
        for renderer in ("rope", "ropetrail", "spritetrail", "sprite"):
            group = {row["scenario"]: row for row in rows if row["renderer"] == renderer}
            writer, reader = group["writer"], group["reader"]
            self.assertGreater(writer["changedPixels"], 0)
            self.assertNotEqual(writer["histogram"], reader["histogram"])
            for scenario in ("writerFirst", "writerLast", "mixedReadonly", "readonlyDoesNotWrite",
                             "ordinaryReadonlyDoesNotWrite", "writeWithoutTest"):
                with self.subTest(renderer=renderer, scenario=scenario):
                    self.assertEqual(group[scenario]["histogram"], writer["histogram"])
            self.assertEqual(group["depthDisabled"]["histogram"], reader["histogram"])
            self.assertNotEqual(group["ordinaryReader"]["histogram"], reader["histogram"])
            self.assertEqual(writer["facts"][0]["depthTest"], True)
            self.assertEqual(writer["facts"][0]["depthWrite"], True)
            self.assertEqual(reader["facts"][0]["depthTest"], True)
            self.assertEqual(reader["facts"][0]["depthWrite"], False)
            self.assertEqual(group["mixedReadonly"]["facts"][1]["blend"], "translucent")
            self.assertFalse(group["mixedReadonly"]["facts"][1]["depthWrite"])
            self.assertFalse(group["writeWithoutTest"]["facts"][0]["depthTest"])
            self.assertTrue(group["writeWithoutTest"]["facts"][0]["depthWrite"])


if __name__ == "__main__":
    unittest.main()
