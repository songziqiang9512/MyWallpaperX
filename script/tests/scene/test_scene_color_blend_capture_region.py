"""Whole-image real Metal equivalence for ordinary advanced-blend copy regions.

The reference routes an identical unit quad through the actual custom-geometry
full capture. This proves renderer pixels and logical copy bytes, not App GPU
time, physical bandwidth, memory savings or official compatibility.
"""
import base64
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.support.scene_color_blend_capture_test_support import PROJECTION_SOURCE, projection_support

REPO = Path(__file__).resolve().parents[3]
SCENE = REPO / "MyWallpaperX/Core/SteamWorkshopScene"
HARNESS = (Path(__file__).resolve().parents[1] / "fixtures") / "SceneColorBlendCaptureRegionHarness.swift"
SOURCES = [SCENE / p for p in (
    "Runtime/Frame/SceneMaterialRenderState.swift",
    "Compilation/Material/SceneMaterialRenderState+Compilation.swift",
    "Rendering/Metal/SceneMetalPipeline.swift",
    "Rendering/Composition/SceneBlendModeShaderSource.swift",
    "Rendering/Composition/SceneLayerColorBlendPipeline.swift",
    "Rendering/Composition/SceneFramebufferSnapshot.swift",
    "Rendering/Composition/SceneMainPassEncoder.swift",
    "Rendering/Composition/SceneImageLayerMainPassRenderer.swift",
    "Resources/Textures/SceneResourceBudget.swift",
    "Diagnostics/ScenePerformanceCounterHub.swift",
    "Diagnostics/SceneGPUCensus.swift",
    "Diagnostics/SceneEffectExecutionFrameTrace.swift",
    "Diagnostics/SceneEffectExecutionTelemetry.swift")]
SHADER = SCENE / "Rendering/Composition/SceneImageLayer.metal"
FOG = SHADER.with_name("SceneDistanceFog.metalh")


def triangle_edge_coverages(clip_xy, width, height):
    # Exact pixel-square intersection area, independent of Metal's sample positions.
    triangle = [((x + 1) * width / 2, (1 - y) * height / 2) for x, y in clip_xy]
    edges = []
    for y in range(height):
        for x in range(width):
            polygon = triangle
            for axis, bound, sign in ((0, x, 1), (0, x + 1, -1),
                                      (1, y, 1), (1, y + 1, -1)):
                clipped = []
                for a, b in zip(polygon, polygon[1:] + polygon[:1]):
                    da, db = (a[axis] - bound) * sign, (b[axis] - bound) * sign
                    if (da >= 0) != (db >= 0):
                        fraction = da / (da - db)
                        clipped.append(tuple(u + fraction * (v - u) for u, v in zip(a, b)))
                    if db >= 0:
                        clipped.append(b)
                polygon = clipped
            area = abs(sum(a[0] * b[1] - a[1] * b[0]
                           for a, b in zip(polygon, polygon[1:] + polygon[:1]))) / 2
            if 1e-9 < area < 1 - 1e-9:
                edges.append((y * width + x, area))
    return edges


def resolved_pixels(row):
    data = base64.b64decode(row["resolvedBGRA"])
    return [(data[i + 2], data[i + 1], data[i], data[i + 3]) for i in range(0, len(data), 4)]


class SceneColorBlendCaptureRegionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which("swiftc") or not shutil.which("xcrun"):
            raise unittest.SkipTest("Swift/Metal toolchain unavailable")
        parent = Path(os.environ.get("MWX_BLEND_REGION_EVIDENCE", "/private/tmp/mwx-blend-region"))
        parent.mkdir(parents=True, exist_ok=True)
        paths = [Path(__file__), HARNESS, PROJECTION_SOURCE, *SOURCES, SHADER, FOG,
                 (Path(__file__).resolve().parents[1] / "support/scene_color_blend_capture_test_support.py")]
        identity = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
        with tempfile.TemporaryDirectory(prefix="blend-region-", dir=parent) as directory:
            root = Path(directory)
            support = root / "Projection.swift"
            support.write_text(projection_support())
            air, library, binary = root / "image.air", root / "image.metallib", root / "probe"
            commands = [
                ["xcrun", "--sdk", "macosx", "metal", "-c", str(SHADER), "-o", str(air)],
                ["xcrun", "--sdk", "macosx", "metallib", str(air), "-o", str(library)],
                ["swiftc", "-DDEBUG", *map(str, SOURCES), str(support), str(HARNESS),
                 "-module-cache-path", str(root / "cache"), "-o", str(binary)],
                [str(binary), str(library), str(FOG)]]
            outputs = []
            for command in commands:
                ran = subprocess.run(command, capture_output=True, text=True, timeout=180)
                outputs.append(ran.stdout + ran.stderr)
                if ran.returncode:
                    (parent / "failure.log").write_text("\n".join(outputs))
                    raise AssertionError(ran.stdout + ran.stderr)
            cls.result = json.loads(outputs[-1])
            assert identity == {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}, "source identity drift"
        resolve = cls.result.get("multisampleResolve", {})
        if resolve.get("supported"):
            edges = triangle_edge_coverages(resolve["triangleClipXY"], *resolve["size"])
            resolve["analyticEdgePixels"] = len(edges)
            for row in resolve["rows"]:
                pixels = resolved_pixels(row)
                row["edgeCoverageMAE"] = sum(abs(pixels[index][0] / 128 - area)
                                             for index, area in edges) / len(edges)
        (parent / "source-identity.json").write_text(json.dumps(identity, indent=2))
        (parent / "report.json").write_text(json.dumps(cls.result, indent=2))
        if cls.result.get("metalUnavailable"):
            raise AssertionError("Metal unavailable: large target qualification was not executed")

    def test_all_modes_and_transform_variants_preserve_every_target_byte(self):
        rows = [r for r in self.result["rows"] if "equal" in r]
        self.assertEqual(len(rows), 23 * 19 * 2 + 6)
        for row in rows:
            with self.subTest(name=row["name"], mode=row["mode"], hdr=row["hdr"]):
                self.assertTrue(row["equal"], row)
                self.assertTrue(row["capacityEqual"], row)
                if "referenceFullCapture" in row:
                    self.assertTrue(row["referenceFullCapture"], row)
                self.assertEqual(row["copies"], 2 if row["name"].startswith("consecutive") else 1)

    def test_copy_bytes_measure_actual_region_and_uncertain_projection_keeps_full_copy(self):
        for row in self.result["rows"]:
            if "fullBytes" not in row:
                self.assertEqual((row["copies"], row["bytes"]), (0, 0))
            elif row["fallback"] or row["name"] == "full-viewport":
                self.assertEqual(row["bytes"], row["fullBytes"], row)
            else:
                self.assertGreater(row["bytes"], 0, row)
                self.assertLess(row["bytes"], row["fullBytes"], row)

    def test_alpha_zero_modes_that_ignore_opacity_still_capture_and_change_pixels(self):
        for row in self.result["rows"]:
            if row.get("mode") in (5, 10) and not row["fallback"]:
                self.assertEqual(row["copies"], 1, row)
                # Some devices rasterize no covered pixels for enormous finite
                # vertices. Keep copy/draw and byte-equivalence coverage there;
                # ordinary transforms retain the independent visible assertion.
                if not row["name"].startswith(("giant-", "large-")):
                    self.assertTrue(row["changed"], row)

    def test_zero_opacity_keeps_hdr_background_with_nonfinite_straight_color(self):
        rows = self.result["transparentHDR"]
        self.assertEqual({(row["mode"], row["full"]) for row in rows},
                         {(15, False), (15, True), (31, False), (31, True)})
        for row in rows:
            self.assertTrue(row["backgroundPreserved"], row)
            if row["full"]:
                self.assertEqual(row["copies"], 1)

    def test_large_finite_unit_quad_bounds_keep_the_entire_viewport_strip(self):
        for row in self.result["rows"]:
            if row["name"].startswith("giant-"):
                x, y, width, height = row["region"]
                if row["name"].endswith("-x"):
                    self.assertEqual((x, width), (0, 67), row)
                else:
                    self.assertEqual((y, height), (0, 43), row)

    def test_equivalent_matrix_and_renamed_inputs_have_same_copy_footprint(self):
        rows = {(r["name"], r.get("mode"), r["hdr"]): r for r in self.result["rows"]}
        for hdr in (False, True):
            for mode in range(1, 20):
                self.assertEqual(rows["fractional", mode, hdr]["bytes"],
                                 rows["renamed-equivalent-matrix", mode, hdr]["bytes"])

    def test_current_attachment_quad_matches_frozen_prefix_and_removes_the_copy(self):
        rows = self.result["attachmentRows"]
        self.assertEqual(len(rows), 10)
        for row in rows:
            with self.subTest(name=row["name"], hdr=row["hdr"]):
                self.assertTrue(row["equal"] and row["changed"] and row["aliasRejected"], row)
                uses_attachment = row["deviceSupportsAttachment"] and row["name"] not in (
                    "perspective", "composition-with-child")
                if uses_attachment:
                    self.assertEqual((row["copies"], row["bytes"], row["capacity"]), (0, 0, 0), row)
                else:
                    self.assertEqual(row["copies"], row["referenceCopies"], row)
                    self.assertGreater(row["bytes"], 0, row)

    def test_terminal_quad_rebinds_read_only_depth_after_color_pass(self):
        for row in self.result["terminalDepth"]:
            self.assertTrue(row["completed"] and row["drawn"] and row["missingRejected"], row)
            self.assertEqual(row["left"], [0, 128, 255, 255] if row["writer"] else [255, 0, 0, 255], row)
            self.assertEqual(row["right"], [255, 0, 0, 255], row)
            self.assertEqual(row["farPeer"], [0, 255, 0, 255], row)

    def test_bounded_mesh_preserves_frozen_pixels_and_falls_back_without_current_projection(self):
        rows = self.result["geometryRows"]
        self.assertEqual(len(rows), 12)
        for row in rows:
            with self.subTest(name=row["name"]):
                self.assertTrue(row["equal"] and row["changed"] and row["capacityEqual"], row)
                self.assertEqual(row["copies"], 1, row)
                if row["name"] in ("varying-w", "stale-pose", "group"):
                    self.assertEqual(row["bytes"], row["fullBytes"], row)
                else:
                    self.assertGreater(row["bytes"], 0, row)
                    self.assertLess(row["bytes"], row["fullBytes"], row)

    def test_repeated_attachment_reads_and_finish_keep_pixels_without_extra_passes(self):
        rows = self.result["repeatedAttachmentReads"]
        self.assertEqual([row["clears"] for row in rows], [True, False])
        for row in rows:
            self.assertEqual((row["firstPasses"], row["laterPasses"]), (1, 0), row)
            for key in ("readable", "finished", "completed", "samePixels"):
                self.assertTrue(row[key], row)

    def test_single_clear_main_pass_resolves_multisample_color_and_preserves_reverse_depth(self):
        result = self.result["multisampleResolve"]
        if not result["supported"]:
            self.skipTest("the device does not support Apple memoryless 2× attachments")
        if self.result["unsupportedEight"]["device"].split()[:2] == ["Apple", "M4"]:
            self.assertTrue(result["supportsFour"])
        for check in ("historyRejected", "differentSizeRejected", "singleColorRejected", "readRejected"):
            self.assertTrue(result[check], check)
        rows = result["rows"]
        self.assertEqual([row["samples"] for row in rows], [1, 2, 4] if result["supportsFour"] else [1, 2])
        self.assertEqual(result["analyticEdgePixels"], 102)
        width, height = result["size"]
        for row in rows:
            samples = row["samples"]
            with self.subTest(samples=samples):
                for check in ("finished", "completed", "reused", "offscreenBeforeClear",
                              "actualResolveTarget", "lateSelectionRejected"):
                    self.assertTrue(row[check], check)
                self.assertFalse(row["reopened"])
                self.assertEqual((row["opens"], row["targetSamples"]), (1, 1))
                self.assertEqual(row["passDetails"]["depthSamples"], str(samples))
                self.assertEqual(row["passDetails"]["depthClear"], "0.0")
                if samples > 1:
                    self.assertEqual(row["passDetails"]["depthStore"], "0")
                    self.assertEqual(row["passDetails"]["colorStore"], "2")
                pixels = resolved_pixels(row)
                self.assertEqual(len(pixels), width * height)
                self.assertIn((128, 0, 0, 128), pixels)
                self.assertIn((0, 255, 0, 255), pixels)
                mixed = 0
                for index, rgba in enumerate(pixels):
                    near = round(rgba[0] * samples / 128) / samples
                    far = 1 - near
                    # Each nearer covered sample keeps its red PMA value and occludes green.
                    expected = (128 * near, 255 * far, 0, 128 * near + 255 * far)
                    error = max(abs(a - b) for a, b in zip(rgba, expected))
                    self.assertLessEqual(error, 1.5, (index % width, index // width, rgba, expected))
                    mixed += 0 < near < 1
                if samples == 1:
                    self.assertEqual(mixed, 0)
                else:
                    self.assertGreater(mixed, 8)
                if samples == 4:
                    for x, y, expected in ((11, 24, (32, 191, 0, 223)), (16, 23, (96, 64, 0, 159))):
                        actual = pixels[y * width + x]
                        self.assertLessEqual(max(abs(a - b) for a, b in zip(actual, expected)), 1,
                                             (x, y, actual, expected))
        single, double, *four = [row["edgeCoverageMAE"] for row in rows]
        self.assertLess(double, single)
        if four:
            self.assertLessEqual(four[0], double * 0.9)

    def test_unsupported_eight_sample_request_renders_the_single_sample_pipeline(self):
        result = self.result["unsupportedEight"]
        if result["device"].split()[:2] == ["Apple", "M4"]:
            self.assertFalse(result["supported"], result)
        if result["supported"]:
            self.skipTest("the Metal device supports 8×")
        self.assertEqual([row["requested"] for row in result["rows"]], [1, 8])
        for row in result["rows"]:
            self.assertEqual((row["preparedSamples"], row["attachmentSamples"], row["outputSamples"]),
                             (1, 1, 1), row)
            self.assertTrue(row["bound"] and row["finished"] and row["completed"], row)
        self.assertTrue(result["matchesSingleSample"] and result["visible"], result)

    def test_large_group_target_mode_31_draws_visible_pixels(self):
        result = self.result.get("largeGroupBlend", {})
        self.assertTrue(result.get("available", False), result)
        reference, large = result.get("reference", {}), result.get("large", {})
        for row in (reference, large):
            for key in ("available", "prepared", "drawn", "finished", "completed"):
                self.assertTrue(row.get(key, False), row)
            self.assertEqual(row["mode"], 31)
            self.assertEqual(row["copies"], 1, row)
            self.assertEqual(row["outside"], [64, 32, 16, 255], row)
            # Fixed pixel positive control for the production additive mode 31;
            # do not duplicate its shader formula in the fixture.
            self.assertLessEqual(max(abs(a - b) for a, b in zip(
                row["center"], [72, 48, 48, 255])), 1, row)
            self.assertNotEqual(row["center"], row["outside"], row)
        self.assertEqual(large["size"], 5000)
        self.assertEqual(large["capacity"], 5000 * 5000 * 4)
        self.assertEqual(large["center"], reference["center"], result)
        self.assertGreater(large["copyBytes"], 0, large)
        self.assertLess(large["copyBytes"], large["capacity"], large)


if __name__ == "__main__":
    unittest.main()
