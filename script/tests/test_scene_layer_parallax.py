#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/SceneLayerParallax.swift"
MATRIX_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/SceneMatrix.swift"

HARNESS_SOURCE = r'''
import Foundation

struct SceneRenderDescriptor {
    struct Layer {
        let id: Int
        let parentID: Int?
        let parallaxDepthXY: [Float]?
        let disablesParallaxPropagation: Bool
    }
}

@main
enum Harness {
    static func main() throws {
        let nodes: [Int: SceneLayerParallax.Node] = [
            1: .init(id: 1, parentID: nil, depth: SIMD2(2, 3), propagatesToChildren: true),
            2: .init(id: 2, parentID: 1, depth: SIMD2(8, 9), propagatesToChildren: true),
            3: .init(id: 3, parentID: 2, depth: SIMD2(6, 7), propagatesToChildren: true),
            4: .init(id: 4, parentID: nil, depth: SIMD2(10, 11), propagatesToChildren: false),
            5: .init(id: 5, parentID: 4, depth: SIMD2(12, 13), propagatesToChildren: true),
            6: .init(id: 6, parentID: 5, depth: SIMD2(14, 15), propagatesToChildren: true),
            7: .init(id: 7, parentID: 8, depth: SIMD2(16, 17), propagatesToChildren: true),
            8: .init(id: 8, parentID: 7, depth: SIMD2(18, 19), propagatesToChildren: true)
        ]
        let configuration = SceneLayerParallax.Configuration(
            enabled: true, amount: 0.1, mouseInfluence: 0.5,
            orthoSize: SIMD2(1000, 500)
        )
        let disabled = SceneLayerParallax.Configuration(
            enabled: false, amount: 1, mouseInfluence: 1,
            orthoSize: SIMD2(1000, 500)
        )
        let center = SIMD2<Float>(500, 250)
        let depth = SceneLayerParallax.Resolution(sourceLayerID: 99, depth: SIMD2(2, 3))
        let xOnly = SceneLayerParallax.Resolution(sourceLayerID: 99, depth: SIMD2(2, 0))
        let zero = SceneLayerParallax.Resolution(sourceLayerID: 99, depth: .zero)

        var smoother = SceneParallaxPointerSmoother(delay: 1)
        smoother.setTarget(SIMD2(1, -1), timestamp: 0)
        let smoothFirst = smoother.advance(delta: 0.25)
        let smoothSecond = smoother.advance(delta: 0.25)
        smoother.setTarget(SIMD2(-1, 1), timestamp: 0.5)
        let smoothAfterInput = smoother.advance(delta: 0.25)

        let result: [String: Any] = [
            "root": vector(SceneLayerParallax.resolve(layerID: 1, nodesByID: nodes)?.depth),
            "inherited": vector(SceneLayerParallax.resolve(layerID: 3, nodesByID: nodes)?.depth),
            "inheritedSource": SceneLayerParallax.resolve(layerID: 3, nodesByID: nodes)?.sourceLayerID ?? -1,
            "blocked": vector(SceneLayerParallax.resolve(layerID: 5, nodesByID: nodes)?.depth),
            "blockedSource": SceneLayerParallax.resolve(layerID: 5, nodesByID: nodes)?.sourceLayerID ?? -1,
            "partialChain": vector(SceneLayerParallax.resolve(layerID: 6, nodesByID: nodes)?.depth),
            "cycle": vector(SceneLayerParallax.resolve(layerID: 7, nodesByID: nodes)?.depth),
            "missing": SceneLayerParallax.resolve(layerID: 404, nodesByID: nodes) == nil,
            "disabled": vector(SceneLayerParallax.offset(
                resolution: depth, configuration: disabled,
                layerPosition: center, mouseNormalized: SIMD2(1, -1)
            )),
            "zeroDepth": vector(SceneLayerParallax.offset(
                resolution: zero, configuration: configuration,
                layerPosition: center, mouseNormalized: SIMD2(1, -1)
            )),
            "axes": vector(SceneLayerParallax.offset(
                resolution: depth, configuration: configuration,
                layerPosition: center, mouseNormalized: SIMD2(1, -1)
            )),
            "xOnly": vector(SceneLayerParallax.offset(
                resolution: xOnly, configuration: configuration,
                layerPosition: center, mouseNormalized: SIMD2(1, -1)
            )),
            "position": vector(SceneLayerParallax.offset(
                resolution: depth, configuration: configuration,
                layerPosition: center + SIMD2(100, -50), mouseNormalized: .zero
            )),
            "smoothFirst": vector(smoothFirst),
            "smoothSecond": vector(smoothSecond),
            "smoothAfterInput": vector(smoothAfterInput)
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func vector(_ value: SIMD2<Float>?) -> [Float] {
        guard let value else { return [] }
        return [value.x, value.y]
    }
}
'''


class SceneLayerParallaxTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-parallax-")
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = directory / "scene-layer-parallax"
        subprocess.run(
            [swiftc, str(MATRIX_SOURCE), str(SOURCE), str(harness), "-o", str(cls.binary)],
            check=True, capture_output=True, text=True,
        )
        cls.result = cls.run_harness()

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    @classmethod
    def run_harness(cls) -> dict[str, object]:
        completed = subprocess.run(
            [str(cls.binary)], check=True, capture_output=True, text=True
        )
        return json.loads(completed.stdout)

    def test_authored_depth_resolution_and_offsets(self) -> None:
        self.assertEqual(self.result["root"], [2, 3])
        self.assertEqual(self.result["inherited"], [2, 3])
        self.assertEqual(self.result["inheritedSource"], 1)
        self.assertEqual(self.result["blocked"], [12, 13])
        self.assertEqual(self.result["blockedSource"], 5)
        self.assertEqual(self.result["partialChain"], [12, 13])
        self.assertIn(self.result["cycle"], ([16, 17], [18, 19]))
        self.assertTrue(self.result["missing"])
        self.assertEqual(self.result["disabled"], [0, 0])
        self.assertEqual(self.result["zeroDepth"], [0, 0])
        self.assertEqual(self.result["axes"], [-50, 37.5])
        self.assertEqual(self.result["xOnly"], [-50, 0])
        self.assertEqual(self.result["position"], [20, -15])

    def test_pointer_delay_smoothing(self) -> None:
        self.assertEqual(self.result["smoothFirst"], [0.25, -0.25])
        self.assertEqual(self.result["smoothSecond"], [0.625, -0.625])
        self.assertEqual(self.result["smoothAfterInput"], [0.21875, -0.21875])


if __name__ == "__main__":
    unittest.main()
