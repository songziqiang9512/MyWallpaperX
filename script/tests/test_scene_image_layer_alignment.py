#!/usr/bin/env python3

from __future__ import annotations

import json
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
PIVOT_SOURCE = SCENE_ROOT / "Rendering/SceneImageLayerPivot.swift"
TRANSFORMS_SOURCE = SCENE_ROOT / "Rendering/SceneMetalRenderer+LayerTransforms.swift"

# Two real authored contracts:
# - 3767460992 layer 1016 is bottomleft, local origin (-64.43445, -87.21118),
#   size 68x68, scale (2.37499, 2.39018), parent center (960, 540).
# - 3122339805 root layer 79 is topleft at (653, 1080), size 653x30.
HARNESS_SOURCE = r'''
import Foundation
import simd

@main
enum Harness {
    static func main() throws {
        let names = [
            "center", "top", "topright", "right", "bottomright",
            "bottom", "bottomleft", "left", "topleft", "TopLeft", "unknown"
        ]
        let table = Dictionary(uniqueKeysWithValues: names.map {
            ($0, vector(SceneImageLayerPivot.unitOffset(alignment: $0)))
        })
        let result: [String: Any] = [
            "table": table,
            "missing": vector(SceneImageLayerPivot.unitOffset(alignment: nil)),
            "mediaCoverCenter": mediaCoverCenter(alignment: "center"),
            "mediaCoverBottomLeft": mediaCoverCenter(alignment: "bottomleft"),
            "audioWindowCenter": audioWindowCenter(alignment: "center"),
            "audioWindowTopLeft": audioWindowCenter(alignment: "topleft")
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func mediaCoverCenter(alignment: String) -> [Float] {
        let parentCenter = SIMD2<Float>(960, 540)
        let localOrigin = SIMD2<Float>(-64.43445, -87.21118)
        let size = SIMD2<Float>(68, 68)
        let scale = SIMD2<Float>(2.37499, 2.39018)
        let pivot = SceneImageLayerPivot.unitOffset(alignment: alignment)
        return vector(parentCenter + SIMD2(localOrigin.x, -localOrigin.y)
            + scale * SIMD2(size.x * pivot.x, -size.y * pivot.y))
    }

    static func audioWindowCenter(alignment: String) -> [Float] {
        let origin = SIMD2<Float>(653, 1080)
        let size = SIMD2<Float>(653, 30)
        let pivot = SceneImageLayerPivot.unitOffset(alignment: alignment)
        return vector(origin + SIMD2(size.x * pivot.x, -size.y * pivot.y))
    }

    static func vector(_ value: SIMD2<Float>) -> [Float] {
        [value.x, value.y]
    }
}
'''


class SceneImageLayerAlignmentTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("xcrun") is None:
            raise unittest.SkipTest("xcrun is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-image-alignment-"
        )
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        binary = directory / "scene-image-alignment"
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc",
                str(PIVOT_SOURCE), str(harness), "-o", str(binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary)], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        if hasattr(cls, "temporary_directory"):
            cls.temporary_directory.cleanup()

    def assert_vector(
        self, actual: object, expected: tuple[float, float], places: int = 4
    ) -> None:
        self.assertIsInstance(actual, list)
        assert isinstance(actual, list)
        self.assertEqual(len(actual), 2)
        self.assertAlmostEqual(actual[0], expected[0], places=places)
        self.assertAlmostEqual(actual[1], expected[1], places=places)

    def test_official_image_alignment_value_domain_maps_to_quad_edges(self) -> None:
        table = self.result["table"]
        expected = {
            "center": (0, 0),
            "top": (0, -0.5),
            "topright": (-0.5, -0.5),
            "right": (-0.5, 0),
            "bottomright": (-0.5, 0.5),
            "bottom": (0, 0.5),
            "bottomleft": (0.5, 0.5),
            "left": (0.5, 0),
            "topleft": (0.5, -0.5),
        }
        for name, vector in expected.items():
            self.assert_vector(table[name], vector)
        self.assert_vector(table["TopLeft"], expected["topleft"])

    def test_missing_and_unknown_alignment_keep_center_pivot(self) -> None:
        self.assert_vector(self.result["missing"], (0, 0))
        self.assert_vector(self.result["table"]["unknown"], (0, 0))

    def test_bottomleft_places_376_media_cover_on_its_parent_content(self) -> None:
        self.assert_vector(self.result["mediaCoverCenter"], (895.56555, 627.21118))
        # The authored bottom-left pivot moves the visible 68x68 quad center back
        # onto the 540x540 parent content instead of leaving it 64/87 units away.
        aligned = self.result["mediaCoverBottomLeft"]
        self.assertAlmostEqual(aligned[0], 976.3152, places=3)
        self.assertAlmostEqual(aligned[1], 545.9449, places=3)
        self.assertLess(abs(aligned[0] - 960), 17)
        self.assertLess(abs(aligned[1] - 540), 7)

    def test_topleft_places_312_window_inside_authored_local_bounds(self) -> None:
        self.assert_vector(self.result["audioWindowCenter"], (653, 1080))
        self.assert_vector(self.result["audioWindowTopLeft"], (979.5, 1095))

    def test_renderer_uses_image_alignment_only_for_non_text_layers(self) -> None:
        transforms = TRANSFORMS_SOURCE.read_text(encoding="utf-8")
        self.assertRegex(
            transforms,
            re.compile(
                r'layer\.contentKind == "text"'
                r"[\s\S]{0,400}SceneTextLayerPivot\.unitOffset"
                r"[\s\S]{0,300}SceneImageLayerPivot\.unitOffset"
                r"\(alignment:\s*layer\.imageAlignment\)"
            ),
        )
        self.assertRegex(
            transforms,
            re.compile(
                r"\* sizeScale"
                r"[\s\S]{0,100}\* SceneMatrix\.translation"
                r"\(SIMD3\(pivot\.x, pivot\.y, 0\)\)"
            ),
        )


if __name__ == "__main__":
    unittest.main()
