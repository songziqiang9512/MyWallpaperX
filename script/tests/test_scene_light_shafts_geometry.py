#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SOURCES = [
    SCENE_ROOT / "Rendering/SceneMatrix.swift",
    SCENE_ROOT / "Rendering/SceneLightShaftsQuadGeometry.swift",
]


HARNESS = r'''
import Foundation
import simd

@main
enum Harness {
    static func close(_ lhs: SIMD4<Float>, _ rhs: SIMD4<Float>) -> Bool {
        simd_distance(lhs, rhs) < 0.001
    }

    static func main() throws {
        let extent = SceneLightShaftsQuadGeometry.baseExtent(
            canvasSize: SIMD2<Float>(3840, 2160)
        )
        let world = SceneMatrix.translation(SIMD3<Float>(100, 200, 0))
            * SceneMatrix.rotationZ(.pi / 2)
            * SceneMatrix.scale(SIMD3<Float>(2, 3, 1))
        let model = SceneLightShaftsQuadGeometry.modelMatrix(
            worldFrame: world,
            parallaxOffset: SIMD2<Float>(5, -7),
            canvasSize: SIMD2<Float>(3840, 2160)
        )
        let corners = model.map { matrix in
            [
                matrix * SIMD4<Float>(-0.5, -0.5, 0, 1),
                matrix * SIMD4<Float>(0.5, -0.5, 0, 1),
                matrix * SIMD4<Float>(-0.5, 0.5, 0, 1),
                matrix * SIMD4<Float>(0.5, 0.5, 0, 1),
            ]
        }
        let invalid = SceneLightShaftsQuadGeometry.baseExtent(
            canvasSize: SIMD2<Float>(.nan, 2160)
        ) == nil && SceneLightShaftsQuadGeometry.modelMatrix(
            worldFrame: SceneMatrix.identity(),
            parallaxOffset: .zero,
            canvasSize: SIMD2<Float>(0, 2160)
        ) == nil
        let result: [String: Bool] = [
            "halfCanvasExtent": extent == SIMD2<Float>(1920, 1080),
            "matrixOrderAndAllCorners": corners.map {
                $0.count == 4
                    && close($0[0], SIMD4<Float>(-1515, -1727, 0, 1))
                    && close($0[1], SIMD4<Float>(-1515, 2113, 0, 1))
                    && close($0[2], SIMD4<Float>(1725, -1727, 0, 1))
                    && close($0[3], SIMD4<Float>(1725, 2113, 0, 1))
            } ?? false,
            "invalidRejected": invalid,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneLightShaftsGeometryTests(unittest.TestCase):
    def test_half_canvas_quad_is_independent_from_effect_points(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")
        with tempfile.TemporaryDirectory(
            prefix="scene-light-shafts-geometry-"
        ) as directory:
            temporary = Path(directory)
            harness = temporary / "Harness.swift"
            binary = temporary / "scene-light-shafts-geometry"
            harness.write_text(HARNESS, encoding="utf-8")
            compilation = subprocess.run(
                [
                    "swiftc",
                    "-parse-as-library",
                    *(str(path) for path in SOURCES),
                    str(harness),
                    "-o",
                    str(binary),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(binary)],
                check=True,
                capture_output=True,
                text=True,
            )
        result = json.loads(completed.stdout)
        self.assertTrue(all(result.values()), result)


if __name__ == "__main__":
    unittest.main()
