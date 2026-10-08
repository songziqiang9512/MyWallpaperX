#!/usr/bin/env python3
"""Compile production model transforms; inherited parallax moves one assembly."""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [SCENE / path for path in (
    "Rendering/Geometry/SceneMatrix.swift",
    "Systems/Input/SceneLayerParallax.swift",
    "Systems/Input/SceneCameraProjection.swift",
    "Rendering/Geometry/SceneLayerScreenAnchor.swift",
    "Rendering/Geometry/SceneImageLayerPivot.swift",
    "Rendering/Geometry/SceneTextLayerPivot.swift",
    "Rendering/Geometry/SceneDirectDrawOutputGeometry.swift",
    "Rendering/Particles/SceneParticleRenderSupport.swift",
    "Systems/Particles/SceneParticleCameraFrame.swift",
    "Rendering/Frame/SceneMetalRenderer+LayerTransforms.swift",
)]

HARNESS = r'''
import Foundation
import simd

// Only the descriptor/renderer shell is synthetic. Resolution, formula,
// four model consumers and their matrix/geometry dependencies are product code.
struct SceneRenderDescriptor {
    struct CameraDescriptor {
        var eye: [Float] = [0, 0, 1], center: [Float] = [0, 0, 0]
        var up: [Float] = [0, 1, 0]
        var orthoWidth: Float? = 1000, orthoHeight: Float? = 500
        var fovDegrees: Float?, perspectiveOverrideFOVDegrees: Float?
        var nearZ: Float = 0.01, farZ: Float = 10000
    }
    struct TextStyle {
        var screenAnchor: String?, horizontalAlignment: String?, verticalAlignment: String?
        var decorationInset: Float = 0, padding: Float = 0
    }
    struct Layer {
        let id: Int
        var parentID: Int? = nil
        var parallaxDepthXY: [Float]? = [2, 3]
        var disablesParallaxPropagation = false
        var renderSizeWH: [Float]? = [80, 60]
        var contentKind = "image"
        var textStyle: TextStyle?, imageAlignment: String?
        var utilityLayer: Bool?, usesPerspective: Bool?
    }
    var camera = CameraDescriptor()
}
struct SceneMetalRenderer {
    var renderDescriptor = SceneRenderDescriptor()
    let parallaxByLayerID: [Int: SceneLayerParallax.Resolution]
}

@main enum Harness {
    static func main() throws {
        let root = SceneRenderDescriptor.Layer(id: 1)
        let image = SceneRenderDescriptor.Layer(id: 2, parentID: 1, parallaxDepthXY: [9, 8])
        let puppet = SceneRenderDescriptor.Layer(id: 3, parentID: 2)
        let particle = SceneRenderDescriptor.Layer(id: 4, parentID: 1, contentKind: "particle")
        let direct = SceneRenderDescriptor.Layer(id: 5, parentID: 1)
        let blocker = SceneRenderDescriptor.Layer(id: 6, disablesParallaxPropagation: true)
        let independent = SceneRenderDescriptor.Layer(id: 7, parentID: 6, parallaxDepthXY: [4, -2])
        let layers = [root, image, puppet, particle, direct, blocker, independent]
        let resolutions = SceneLayerParallax.resolveAll(
            layersByID: Dictionary(uniqueKeysWithValues: layers.map { ($0.id, $0) })
        )
        let renderer = SceneMetalRenderer(parallaxByLayerID: resolutions)
        let mouse = SIMD2<Float>(0.25, -0.5)
        func config(_ enabled: Bool) -> SceneLayerParallax.Configuration {
            .init(enabled: enabled, amount: 0.1, mouseInfluence: 0.5,
                  orthoSize: SIMD2(1000, 500), cameraPosition: SIMD2(500, 250), worldYDown: true)
        }
        func frame(_ x: Float, _ y: Float, _ angle: Float = 0) -> simd_float4x4 {
            SceneMatrix.translation(SIMD3(x, y, 7)) * SceneMatrix.rotationZ(angle)
                * SceneMatrix.scale(SIMD3(1.3, 0.8, 1))
        }
        let frames: [Int: simd_float4x4] = [
            1: frame(650, 180, 0.3), 2: frame(670, 195, -0.2),
            3: frame(720, 230, 0.6), 4: frame(590, 220, -0.4),
            5: frame(620, 135, 0.5), 6: frame(100, 80), 7: frame(130, 120)
        ]
        func models(_ layer: SceneRenderDescriptor.Layer, _ world: [Int: simd_float4x4],
                    _ enabled: Bool) -> [simd_float4x4] {
            let configuration = config(enabled)
            return [
                renderer.imageModelMatrix(for: layer, worldFramesByLayerID: world,
                    parallaxMouseNormalized: mouse, configuration: configuration,
                    visibleHalfExtents: SIMD2(500, 250), usesPerspective: false),
                renderer.geometryModelMatrix(for: layer, worldFramesByLayerID: world,
                    authoredSize: SIMD2(80, 60), parallaxMouseNormalized: mouse,
                    configuration: configuration, visibleHalfExtents: SIMD2(500, 250),
                    usesPerspective: false),
                renderer.particleModelMatrix(for: layer, worldFramesByLayerID: world,
                    parallaxMouseNormalized: mouse, configuration: configuration),
                renderer.directDrawOutputModelMatrix(for: layer, worldFramesByLayerID: world,
                    parallaxMouseNormalized: mouse, configuration: configuration)!
            ]
        }
        let points = [SIMD4<Float>(0, 0, 0, 1), SIMD4(0.2, -0.3, 1, 1), SIMD4(-0.5, 0.5, 0, 1)]
        func offsets(_ layer: SceneRenderDescriptor.Layer, _ world: [Int: simd_float4x4]) -> [[Float]] {
            zip(models(layer, world, true), models(layer, world, false)).flatMap { active, plain in
                points.map { point in
                    let delta = active * point - plain * point
                    return [delta.x, delta.y, delta.z, delta.w]
                }
            }
        }
        var movedChild = frames
        movedChild[3] = frame(870, 110, 0.6)
        var movedParent = frames
        movedParent[1] = frame(750, 140, 0.3)
        var missingParent = frames
        missingParent.removeValue(forKey: 1)
        var missingBoth = missingParent
        missingBoth.removeValue(forKey: 3)
        let beforeActive = models(puppet, frames, true)
        let afterActive = models(puppet, movedChild, true)
        let beforePlain = models(puppet, frames, false)
        let afterPlain = models(puppet, movedChild, false)
        let childMotionResidual = (0..<4).flatMap { index in
            points.map { point in
                let extra = (afterActive[index] * point - beforeActive[index] * point)
                    - (afterPlain[index] * point - beforePlain[index] * point)
                return [extra.x, extra.y, extra.z, extra.w]
            }
        }
        let result: [String: Any] = [
            "inheritedSources": [image, puppet, particle, direct].map { resolutions[$0.id]!.sourceLayerID },
            "assemblyOffsets": [image, puppet, particle, direct].map { offsets($0, frames) },
            "rootOffsets": offsets(root, frames),
            "blockedSource": resolutions[independent.id]!.sourceLayerID,
            "blockedOffsets": offsets(independent, frames),
            "movedChildOffsets": offsets(puppet, movedChild),
            "childMotionResidual": childMotionResidual,
            "nextFrameOffsets": offsets(puppet, movedParent),
            "missingParentOffsets": offsets(puppet, missingParent),
            "missingBothOffsets": offsets(puppet, missingBoth)
        ]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
                     as: UTF8.self))
    }
}
'''


class SceneInheritedParallaxGeometryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        with tempfile.TemporaryDirectory(prefix="mwx-inherited-parallax-") as directory:
            path = Path(directory)
            harness, binary = path / "Harness.swift", path / "run"
            harness.write_text(HARNESS, encoding="utf-8")
            compiled = subprocess.run(
                [swiftc, *map(str, SWIFT_SOURCES), str(harness), "-o", str(binary)],
                capture_output=True, text=True, timeout=120,
            )
            if compiled.returncode:
                raise RuntimeError(compiled.stderr)
            completed = subprocess.run(
                [str(binary)], check=True, capture_output=True, text=True, timeout=30,
            )
            cls.result = json.loads(completed.stdout)

    def assert_offsets(self, rows: list[list[float]], xy: list[float]) -> None:
        self.assertEqual(len(rows), 12)  # Four production consumers, three points each.
        for index, row in enumerate(rows):
            self.assertEqual(len(row), 4)
            for actual, expected in zip(row, [*xy, 0, 0]):
                self.assertAlmostEqual(actual, expected, delta=0.001, msg=f"probe {index}")

    def test_four_consumers_share_inherited_source_displacement(self) -> None:
        self.assertEqual(self.result["inheritedSources"], [1, 1, 1, 1])
        # Pointer drift (-62.5, -62.5); source (650,180) minus camera
        # (500,250), depth (2,3), amount 0.1 => (17.5, -39.75).
        for offsets in self.result["assemblyOffsets"]:
            self.assert_offsets(offsets, [17.5, -39.75])

    def test_child_motion_keeps_assembly_relative_composition(self) -> None:
        self.assert_offsets(self.result["movedChildOffsets"], [17.5, -39.75])
        self.assert_offsets(self.result["childMotionResidual"], [0, 0])

    def test_root_and_blocked_chain_keep_own_position_formula(self) -> None:
        self.assert_offsets(self.result["rootOffsets"], [17.5, -39.75])
        self.assertEqual(self.result["blockedSource"], 7)
        self.assert_offsets(self.result["blockedOffsets"], [-173, 38.5])

    def test_next_call_reads_current_source_world_frame(self) -> None:
        self.assert_offsets(self.result["nextFrameOffsets"], [37.5, -51.75])

    def test_missing_source_frame_does_not_borrow_child_position(self) -> None:
        self.assert_offsets(self.result["missingParentOffsets"], [0, 0])
        self.assert_offsets(self.result["missingBothOffsets"], [0, 0])


if __name__ == "__main__":
    unittest.main()
