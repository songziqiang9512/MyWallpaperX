#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
DYNAMIC_SOURCE = SCENE_ROOT / "Properties/SceneDynamicSnapshot.swift"
LAYER_VALUES_SOURCE = SCENE_ROOT / "Properties/SceneDynamicLayerValues.swift"
RENDERER_SOURCE = SCENE_ROOT / "Rendering/SceneMetalRenderer.swift"
COMPOSITOR_SOURCE = SCENE_ROOT / "Rendering/SceneImageLayerCompositor.swift"
UTILITY_SOURCE = SCENE_ROOT / "Rendering/SceneUtilityLayerRenderer.swift"

HARNESS = r'''
import Foundation

@main
enum Harness {
    static func main() throws {
        let alpha = SceneDynamicTarget.layer(layerID: 7, field: .alpha)
        let otherAlpha = SceneDynamicTarget.layer(layerID: 8, field: .alpha)
        let color = SceneDynamicTarget.layer(layerID: 7, field: .color)
        let otherColor = SceneDynamicTarget.layer(layerID: 8, field: .color)
        let resolver = SceneDynamicSnapshotResolver()
        let dynamic = resolver.resolve(
            frameIndex: 1,
            generation: 1,
            definitions: [
                .init(target: alpha, valueType: .scalar, authoredValue: .scalar(0.6)),
                .init(target: otherAlpha, valueType: .scalar, authoredValue: .scalar(0.8)),
                .init(target: color, valueType: .vector3, authoredValue: .vector3(0.1, 0.2, 0.3)),
                .init(target: otherColor, valueType: .vector3, authoredValue: .vector3(0.2, 0.3, 0.4)),
            ],
            userValues: [
                alpha: .scalar(0.25),
                otherAlpha: .scalar(2),
                color: .vector3(-0.25, 0.5, 1.25),
                otherColor: .vector3(.infinity, 0.5, 0.5),
            ]
        ).snapshot
        let wrongType = resolver.resolve(
            frameIndex: 2,
            generation: 1,
            definitions: [
                .init(target: alpha, valueType: .string, authoredValue: .string("bad")),
                .init(target: color, valueType: .string, authoredValue: .string("bad")),
            ]
        ).snapshot
        let empty = SceneDynamicSnapshot.empty(frameIndex: 3)
        let payload: [String: Any] = [
            "dynamic": value(layerID: 7, authored: 0.6, snapshot: dynamic),
            "dynamicClamp": value(layerID: 8, authored: 0.6, snapshot: dynamic),
            "wrongLayer": value(layerID: 9, authored: 0.4, snapshot: dynamic),
            "wrongType": value(layerID: 7, authored: 0.3, snapshot: wrongType),
            "authored": value(layerID: 7, authored: 0.4, snapshot: empty),
            "authoredLow": value(layerID: 7, authored: -2, snapshot: empty),
            "authoredHigh": value(layerID: 7, authored: 3, snapshot: empty),
            "authoredNonFinite": value(layerID: 7, authored: .infinity, snapshot: empty),
            "default": value(layerID: 7, authored: nil, snapshot: empty),
            "colorDynamicClamp": components(colorValue(
                layerID: 7, authored: [0.6, 0.7, 0.8], snapshot: dynamic
            )),
            "colorNonFiniteFallback": components(colorValue(
                layerID: 8, authored: [0.6, 0.7, 0.8], snapshot: dynamic
            )),
            "colorWrongLayer": components(colorValue(
                layerID: 9, authored: [0.4, 0.5, 0.6], snapshot: dynamic
            )),
            "colorWrongType": components(colorValue(
                layerID: 7, authored: [0.3, 0.4, 0.5], snapshot: wrongType
            )),
            "colorAuthoredClamp": components(colorValue(
                layerID: 7, authored: [-0.2, 0.25, 1.2], snapshot: empty
            )),
            "colorAuthoredNonFinite": components(colorValue(
                layerID: 7, authored: [.nan, 0.5, 0.5], snapshot: empty
            )),
            "colorAuthoredPadded": components(colorValue(
                layerID: 7, authored: [0.2, 0.3], snapshot: empty
            )),
            "colorDefault": components(colorValue(
                layerID: 7, authored: nil, snapshot: empty
            )),
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func value(
        layerID: Int,
        authored: Double?,
        snapshot: SceneDynamicSnapshot
    ) -> Float {
        SceneDynamicLayerValues.alpha(
            layerID: layerID,
            authoredValue: authored,
            snapshot: snapshot
        )
    }

    static func colorValue(
        layerID: Int,
        authored: [Float]?,
        snapshot: SceneDynamicSnapshot
    ) -> SIMD3<Float> {
        SceneDynamicLayerValues.color(
            layerID: layerID,
            authoredValue: authored,
            snapshot: snapshot
        )
    }

    static func components(_ value: SIMD3<Float>) -> [Float] {
        [value.x, value.y, value.z]
    }
}
'''


class SceneDynamicLayerValuesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-dynamic-layer-values-"
        )
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = directory / "scene-dynamic-layer-values"
        compilation = subprocess.run(
            [
                "swiftc",
                str(DYNAMIC_SOURCE),
                str(LAYER_VALUES_SOURCE),
                str(harness),
                "-o",
                str(binary),
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
        cls.temporary_directory.cleanup()

    def test_dynamic_scalar_wins_and_is_clamped(self) -> None:
        self.assertEqual(self.result["dynamic"], 0.25)
        self.assertEqual(self.result["dynamicClamp"], 1)
        self.assertAlmostEqual(self.result["wrongLayer"], 0.4)

    def test_invalid_dynamic_value_falls_back_to_authored_alpha(self) -> None:
        self.assertAlmostEqual(self.result["wrongType"], 0.3)

    def test_authored_alpha_is_finite_clamped_and_defaults_to_one(self) -> None:
        self.assertAlmostEqual(self.result["authored"], 0.4)
        self.assertEqual(self.result["authoredLow"], 0)
        self.assertEqual(self.result["authoredHigh"], 1)
        self.assertEqual(self.result["authoredNonFinite"], 1)
        self.assertEqual(self.result["default"], 1)

    def test_dynamic_color_wins_clamps_and_rejects_non_finite_values(self) -> None:
        self.assert_color("colorDynamicClamp", [0, 0.5, 1])
        self.assert_color("colorNonFiniteFallback", [0.2, 0.3, 0.4])
        self.assert_color("colorWrongLayer", [0.4, 0.5, 0.6])

    def test_invalid_dynamic_color_falls_back_to_authored_color(self) -> None:
        self.assert_color("colorWrongType", [0.3, 0.4, 0.5])

    def test_authored_color_is_clamped_and_invalid_values_default_to_white(self) -> None:
        self.assert_color("colorAuthoredClamp", [0, 0.25, 1])
        self.assert_color("colorAuthoredNonFinite", [1, 1, 1])
        self.assert_color("colorAuthoredPadded", [0.2, 0.3, 1])
        self.assert_color("colorDefault", [1, 1, 1])

    def assert_color(self, key: str, expected: list[float]) -> None:
        self.assertEqual(len(self.result[key]), len(expected))
        for actual, wanted in zip(self.result[key], expected):
            self.assertAlmostEqual(actual, wanted, places=6)

    def test_renderer_consumes_snapshot_for_non_particle_layer_alpha(self) -> None:
        renderer = RENDERER_SOURCE.read_text(encoding="utf-8")
        image_case = renderer.split('case "image", "solid", "text":', 1)[1].split(
            'case "composition", "project", "fullscreen":', 1
        )[0]
        utility_case, particle_tail = renderer.split(
            'case "composition", "project", "fullscreen":', 1
        )[1].split('case "particle":', 1)
        particle_case = particle_tail.split("default:", 1)[0]
        self.assertIn("SceneDynamicLayerValues.alpha(", image_case)
        self.assertIn("SceneDynamicLayerValues.color(", image_case)
        self.assertIn("snapshot: frameContext.dynamicValues", image_case)
        self.assertIn("alpha: layerAlpha", image_case)
        self.assertIn("SceneDynamicLayerValues.alpha(", utility_case)
        self.assertIn("finalCompositeAlpha: layerAlpha", utility_case)
        self.assertNotIn("SceneDynamicLayerValues.alpha(", particle_case)
        self.assertNotIn("Float(layer.alpha ?? 1)", renderer)

        compositor = COMPOSITOR_SOURCE.read_text(encoding="utf-8")
        self.assertRegex(
            compositor,
            r'tint:\s*request\.layer\.contentKind\s*==\s*"solid"'
            r"[\s\S]{0,120}\?\s*request\.uniforms\.tint"
            r"[\s\S]{0,120}:\s*SIMD3\(repeating:\s*1\)",
        )

    def test_utility_capture_keeps_source_neutral_and_applies_alpha_once(self) -> None:
        utility = UTILITY_SOURCE.read_text(encoding="utf-8")
        self.assertIn("finalCompositeAlpha: Float", utility)
        self.assertIn("alpha: 1", utility)
        self.assertIn("finalCompositeAlpha: finalCompositeAlpha", utility)
        self.assertEqual(utility.count("finalCompositeAlpha: finalCompositeAlpha"), 1)
        self.assertNotIn("Float(layer.alpha ?? 1)", utility)


if __name__ == "__main__":
    unittest.main()
