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
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Geometry/SceneMatrix.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/ScenePreparedDirectDrawOutputGeometry.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Geometry/SceneDirectDrawOutputGeometry.swift",
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
        let centered = ScenePreparedDirectDrawOutputGeometry.centeredHalfCanvas
        let aligned = ScenePreparedDirectDrawOutputGeometry
            .topAlignedHalfCanvas(normalizedPerspectivePoints: [
                SIMD2<Float>(0.57282, 0.19584),
                SIMD2<Float>(0.38640, 0.19475),
                SIMD2<Float>(0.21953, 0.83065),
                SIMD2<Float>(0.76299, 0.83838),
            ])!
        let extent = SceneDirectDrawOutputGeometry.baseExtent(
            canvasSize: SIMD2<Float>(3840, 2160),
            contract: aligned
        )
        let world = SceneMatrix.translation(SIMD3<Float>(100, 200, 0))
            * SceneMatrix.rotationZ(.pi / 2)
            * SceneMatrix.scale(SIMD3<Float>(2, 3, 1))
        let centeredModel = SceneDirectDrawOutputGeometry.modelMatrix(
            worldFrame: world,
            parallaxOffset: SIMD2<Float>(5, -7),
            canvasSize: SIMD2<Float>(3840, 2160),
            contract: centered
        )
        let alignedModel = SceneDirectDrawOutputGeometry.modelMatrix(
            worldFrame: world,
            parallaxOffset: SIMD2<Float>(5, -7),
            canvasSize: SIMD2<Float>(3840, 2160),
            contract: aligned
        )
        let preservesExtent = centeredModel.flatMap { centeredMatrix in
            alignedModel.map { alignedMatrix in
            let centeredWidth = centeredMatrix * SIMD4<Float>(0.5, 0, 0, 1)
                - centeredMatrix * SIMD4<Float>(-0.5, 0, 0, 1)
            let alignedWidth = alignedMatrix * SIMD4<Float>(0.5, 0, 0, 1)
                - alignedMatrix * SIMD4<Float>(-0.5, 0, 0, 1)
            let centeredHeight = centeredMatrix * SIMD4<Float>(0, 0.5, 0, 1)
                - centeredMatrix * SIMD4<Float>(0, -0.5, 0, 1)
            let alignedHeight = alignedMatrix * SIMD4<Float>(0, 0.5, 0, 1)
                - alignedMatrix * SIMD4<Float>(0, -0.5, 0, 1)
            return close(centeredWidth, alignedWidth)
                && close(centeredHeight, alignedHeight)
            }
        } ?? false
        let alignsActiveTop = centeredModel.flatMap { centeredMatrix in
            alignedModel.map { alignedMatrix in
            let originalCarrierTop = centeredMatrix
                * SIMD4<Float>(0, 0.5, 0, 1)
            let authoredActiveTop = alignedMatrix
                * SIMD4<Float>(0, 0.5 - aligned.normalizedContentTopInset, 0, 1)
            return close(originalCarrierTop, authoredActiveTop)
            }
        } ?? false
        let invalid = SceneDirectDrawOutputGeometry.baseExtent(
            canvasSize: SIMD2<Float>(.nan, 2160),
            contract: aligned
        ) == nil && SceneDirectDrawOutputGeometry.modelMatrix(
            worldFrame: SceneMatrix.identity(),
            parallaxOffset: .zero,
            canvasSize: SIMD2<Float>(0, 2160),
            contract: aligned
        ) == nil && SceneDirectDrawOutputGeometry.modelMatrix(
            worldFrame: SceneMatrix.identity(),
            parallaxOffset: .zero,
            canvasSize: SIMD2<Float>(3840, 2160),
            contract: .init(
                canvasExtentScale: 0.5,
                normalizedContentTopInset: 0.75
            )
        ) == nil && ScenePreparedDirectDrawOutputGeometry
            .topAlignedHalfCanvas(normalizedPerspectivePoints: [
                SIMD2<Float>(0, 0), SIMD2<Float>(1, 0),
                SIMD2<Float>(1, 1), SIMD2<Float>(1.2, 1),
            ]) == nil
        let borderOverscan = ScenePreparedDirectDrawOutputGeometry
            .topAlignedHalfCanvas(normalizedPerspectivePoints: [
                SIMD2<Float>(-0.00204, 0.22119),
                SIMD2<Float>(0.60427, 0.21922),
                SIMD2<Float>(0.80427, 0.76922),
                SIMD2<Float>(0.20427, 0.76922),
            ]) != nil
        let excessiveOverscan = ScenePreparedDirectDrawOutputGeometry
            .topAlignedHalfCanvas(normalizedPerspectivePoints: [
                SIMD2<Float>(-0.02, 0.22119),
                SIMD2<Float>(0.60427, 0.21922),
                SIMD2<Float>(0.80427, 0.76922),
                SIMD2<Float>(0.20427, 0.76922),
            ]) == nil
        let result: [String: Bool] = [
            "halfCanvasExtent": extent == SIMD2<Float>(1920, 1080),
            "topAlignmentPreservesExtent": preservesExtent,
            "authoredActiveTopMatchesOriginalCarrierTop": alignsActiveTop,
            "invalidRejected": invalid,
            "borderOverscanAccepted": borderOverscan,
            "excessiveOverscanRejected": excessiveOverscan,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneDirectDrawOutputGeometryTests(unittest.TestCase):
    def test_prepared_top_alignment_preserves_half_canvas_scale(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")
        with tempfile.TemporaryDirectory(
            prefix="scene-direct-draw-output-geometry-"
        ) as directory:
            temporary = Path(directory)
            harness = temporary / "Harness.swift"
            binary = temporary / "scene-direct-draw-output-geometry"
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
