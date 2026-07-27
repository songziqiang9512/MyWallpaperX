#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SOURCE_ROOT / "Rendering/SceneMatrix.swift",
    SOURCE_ROOT / "Rendering/SceneUtilityLayer.swift",
    SOURCE_ROOT / "Rendering/SceneCaptureGeometry.swift",
]

HARNESS_SOURCE = r'''
import CoreGraphics
import Foundation
import simd

struct SceneTextureUVTransform {
    let origin: SIMD2<Float>
    let xAxis: SIMD2<Float>
    let yAxis: SIMD2<Float>
    nonisolated static let identity = SceneTextureUVTransform(
        origin: .zero, xAxis: SIMD2(1, 0), yAxis: SIMD2(0, 1)
    )
}

@main
enum Harness {
    static func main() throws {
        let viewport = CGSize(width: 1000, height: 800)
        let localMVP = SceneMatrix.translation(SIMD3<Float>(0.5, -0.25, 0))
            * SceneMatrix.scale(SIMD3<Float>(1, 0.5, 1))
        let local = SceneCaptureGeometryResolver.resolve(
            kind: .composition, layerMVP: localMVP, viewportSize: viewport
        )!
        let fullscreen = SceneCaptureGeometryResolver.resolve(
            kind: .fullscreen, layerMVP: localMVP, viewportSize: viewport
        )!
        let project = SceneCaptureGeometryResolver.resolve(
            kind: .project, layerMVP: localMVP, viewportSize: viewport
        )!
        let invalid = SceneCaptureGeometryResolver.resolve(
            kind: .composition,
            layerMVP: localMVP,
            viewportSize: CGSize(width: 0, height: 800)
        )
        let projected = SceneCaptureGeometryResolver.projectedPixelSize(
            layerMVP: SceneMatrix.scale(SIMD3<Float>(1.5, 0.25, 1)),
            viewportSize: viewport
        )
        let result: [String: Any] = [
            "localOrigin": vector(local.sourceUV.origin),
            "localXAxis": vector(local.sourceUV.xAxis),
            "localYAxis": vector(local.sourceUV.yAxis),
            "localSize": [local.pixelSize.width, local.pixelSize.height],
            "localOutput": matrix(local.outputMVP),
            "fullscreenOrigin": vector(fullscreen.sourceUV.origin),
            "fullscreenAxes": [
                fullscreen.sourceUV.xAxis.x, fullscreen.sourceUV.xAxis.y,
                fullscreen.sourceUV.yAxis.x, fullscreen.sourceUV.yAxis.y,
            ],
            "fullscreenSize": [fullscreen.pixelSize.width, fullscreen.pixelSize.height],
            "fullscreenOutput": matrix(fullscreen.outputMVP),
            "projectOutput": matrix(project.outputMVP),
            "invalidIsNil": invalid == nil,
            "projectedSize": projected.map { [$0.width, $0.height] } ?? [],
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func vector(_ value: SIMD2<Float>) -> [Float] { [value.x, value.y] }

    static func matrix(_ value: simd_float4x4) -> [Float] {
        [value.columns.0, value.columns.1, value.columns.2, value.columns.3]
            .flatMap { [$0.x, $0.y, $0.z, $0.w] }
    }
}
'''


class SceneCaptureGeometryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-capture-geometry-")
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = directory / "scene-capture-geometry"
        subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness), "-o", str(cls.binary),
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        completed = subprocess.run(
            [str(cls.binary)], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_composition_captures_its_projected_source_region(self) -> None:
        self.assertEqual(self.result["localOrigin"], [0.5, 0.5])
        self.assertEqual(self.result["localXAxis"], [0.5, 0])
        self.assertEqual(self.result["localYAxis"], [0, 0.25])
        self.assertEqual(self.result["localSize"], [500, 200])

    def test_composition_preserves_authored_output_transform(self) -> None:
        self.assertEqual(
            self.result["localOutput"],
            [1, 0, 0, 0, 0, 0.5, 0, 0, 0, 0, 1, 0, 0.5, -0.25, 0, 1],
        )

    def test_project_and_fullscreen_use_identity_full_frame_geometry(self) -> None:
        self.assertEqual(self.result["fullscreenOrigin"], [0, 0])
        self.assertEqual(self.result["fullscreenAxes"], [1, 0, 0, 1])
        self.assertEqual(self.result["fullscreenSize"], [1000, 800])
        full_target = [2, 0, 0, 0, 0, 2, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
        self.assertEqual(self.result["fullscreenOutput"], full_target)
        self.assertEqual(self.result["projectOutput"], full_target)

    def test_degenerate_viewport_is_rejected(self) -> None:
        self.assertTrue(self.result["invalidIsNil"])

    def test_projected_pixel_size_preserves_non_square_surface_extent(self) -> None:
        self.assertEqual(self.result["projectedSize"], [750, 100])


if __name__ == "__main__":
    unittest.main()
