"""Whole-image real Metal equivalence for ordinary advanced-blend copy regions.

The reference routes an identical unit quad through the actual custom-geometry
full capture. This proves renderer pixels and logical copy bytes, not App GPU
time, physical bandwidth, memory savings or official compatibility.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.scene_color_blend_capture_test_support import PROJECTION_SOURCE, projection_support

REPO = Path(__file__).resolve().parents[2]
SCENE = REPO / "MyWallpaperX/Core/SteamWorkshopScene"
HARNESS = Path(__file__).with_name("fixtures") / "SceneColorBlendCaptureRegionHarness.swift"
SOURCES = [SCENE / p for p in (
    "Rendering/Metal/SceneMetalPipeline.swift",
    "Rendering/Composition/SceneBlendModeShaderSource.swift",
    "Rendering/Composition/SceneLayerColorBlendPipeline.swift",
    "Rendering/Composition/SceneFramebufferSnapshot.swift",
    "Rendering/Composition/SceneMainPassEncoder.swift",
    "Resources/Textures/SceneResourceBudget.swift",
    "Diagnostics/ScenePerformanceCounterHub.swift",
    "Diagnostics/SceneGPUCensus.swift")]
SHADER = SCENE / "Rendering/Composition/SceneImageLayer.metal"
FOG = SHADER.with_name("SceneDistanceFog.metalh")


class SceneColorBlendCaptureRegionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which("swiftc") or not shutil.which("xcrun"):
            raise unittest.SkipTest("Swift/Metal toolchain unavailable")
        parent = Path(os.environ.get("MWX_BLEND_REGION_EVIDENCE", "/private/tmp/mwx-blend-region"))
        parent.mkdir(parents=True, exist_ok=True)
        paths = [Path(__file__), HARNESS, PROJECTION_SOURCE, *SOURCES, SHADER, FOG,
                 Path(__file__).with_name("scene_color_blend_capture_test_support.py")]
        identity = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
        with tempfile.TemporaryDirectory(prefix="blend-region-", dir=parent) as directory:
            root = Path(directory)
            support = root / "Projection.swift"
            support.write_text(projection_support())
            air, library, binary = root / "image.air", root / "image.metallib", root / "probe"
            commands = [
                ["xcrun", "--sdk", "macosx", "metal", "-c", str(SHADER), "-o", str(air)],
                ["xcrun", "--sdk", "macosx", "metallib", str(air), "-o", str(library)],
                ["swiftc", *map(str, SOURCES), str(support), str(HARNESS),
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
        (parent / "source-identity.json").write_text(json.dumps(identity, indent=2))
        (parent / "report.json").write_text(json.dumps(cls.result, indent=2))
        if cls.result.get("metalUnavailable"):
            raise unittest.SkipTest("Metal unavailable")

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


if __name__ == "__main__":
    unittest.main()
