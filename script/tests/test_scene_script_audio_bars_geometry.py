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
    SCENE_ROOT / "Runtime/SceneAudioSpectrum.swift",
    SCENE_ROOT / "Runtime/SceneScriptAudioBarsPlan.swift",
    SCENE_ROOT / "Rendering/SceneScriptAudioBarsGeometry.swift",
]


HARNESS = r'''
import Foundation
import simd

@main
enum Harness {
    static func plan(
        barCount: Int = 64,
        audioResolution: Int = 64,
        width: Float,
        height: Float,
        depth: Float,
        xStep: Float,
        yStep: Float,
        angle: Float,
        alignment: SceneScriptAudioBarsPlan.Alignment = .centre,
        firstStep: SceneScriptAudioBarsPlan.FirstStepPolicy
    ) -> SceneScriptAudioBarsPlan {
        SceneScriptAudioBarsPlan(
            layerID: 7,
            sourceSHA256: "fixture-source",
            host: "fixture-host",
            modelPath: "fixture/model.json",
            materialPath: "fixture/material.json",
            texturePath: "fixture/texture.tex",
            barCount: barCount,
            audioResolution: audioResolution,
            channel: .average,
            widthMultiplier: width,
            heightMultiplier: height,
            depthMultiplier: depth,
            xStep: xStep,
            yStep: yStep,
            angleDegrees: angle,
            alignment: alignment,
            firstStepPolicy: firstStep
        )
    }

    static func vector(_ value: SIMD2<Float>) -> [Float] {
        [value.x, value.y]
    }

    static func vector(_ value: SIMD3<Float>) -> [Float] {
        [value.x, value.y, value.z]
    }

    static func translation(_ matrix: simd_float4x4?) -> [Float] {
        guard let matrix else { return [] }
        return [
            matrix.columns.3.x,
            matrix.columns.3.y,
            matrix.columns.3.z,
        ]
    }

    static func columns(_ matrix: simd_float4x4?) -> [[Float]] {
        guard let matrix else { return [] }
        return [
            [matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z],
            [matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z],
            [matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z],
        ]
    }

    static func main() throws {
        var left = Array(repeating: Float.zero, count: 64)
        var right = Array(repeating: Float.zero, count: 64)
        left[0] = 2
        right[0] = 4
        left[63] = 0.5
        right[63] = 1.5

        let horizontalPlan = plan(
            width: 2.5,
            height: 50,
            depth: 0,
            xStep: 20,
            yStep: 0,
            angle: 0,
            firstStep: .ownerAtBaseOrigin
        )
        let horizontal = SceneScriptAudioBarsGeometry.instances(
            plan: horizontalPlan,
            left64: left,
            right64: right
        )
        let horizontalFirst = horizontal?.first
        let horizontalLast = horizontal?.last
        let horizontalFirstModel = horizontalFirst.flatMap {
            SceneScriptAudioBarsGeometry.modelMatrix(
                authoredBaseOrigin: SIMD3(1286.96362, 115.16699, 0),
                sceneOrthoHeight: 2160,
                baseSize: SIMD2(4, 4),
                instance: $0
            )
        }
        let horizontalLastModel = horizontalLast.flatMap {
            SceneScriptAudioBarsGeometry.modelMatrix(
                authoredBaseOrigin: SIMD3(1286.96362, 115.16699, 0),
                sceneOrthoHeight: 2160,
                baseSize: SIMD2(4, 4),
                instance: $0
            )
        }

        let diagonalPlan = plan(
            width: 1,
            height: 50,
            depth: 1,
            xStep: 5.6,
            yStep: 11.3,
            angle: 60,
            firstStep: .advanceBeforeFirstBar
        )
        let flatSpectrum = SceneAudioSpectrumSnapshot(
            left: Array(repeating: 0, count: 16),
            right: Array(repeating: 0, count: 16),
            left64: Array(repeating: 1, count: 64),
            right64: Array(repeating: 1, count: 64),
            generation: 1
        )
        let diagonal = SceneScriptAudioBarsGeometry.instances(
            plan: diagonalPlan,
            spectrum: flatSpectrum
        )
        let diagonalFirst = diagonal?.first
        let diagonalLast = diagonal?.last
        let diagonalFirstModel = diagonalFirst.flatMap {
            SceneScriptAudioBarsGeometry.modelMatrix(
                authoredBaseOrigin: SIMD3(862.90399, 1453.27295, 0),
                sceneOrthoHeight: 2160,
                baseSize: SIMD2(4, 4),
                instance: $0
            )
        }

        let bottom = SceneScriptAudioBarsGeometry.instances(
            plan: plan(
                width: 1,
                height: 1,
                depth: 1,
                xStep: 0,
                yStep: 0,
                angle: 0,
                alignment: .bottom,
                firstStep: .ownerAtBaseOrigin
            ),
            left64: Array(repeating: 0, count: 64),
            right64: Array(repeating: 0, count: 64)
        )?.first
        let top = SceneScriptAudioBarsGeometry.instances(
            plan: plan(
                width: 1,
                height: 1,
                depth: 1,
                xStep: 0,
                yStep: 0,
                angle: 0,
                alignment: .top,
                firstStep: .ownerAtBaseOrigin
            ),
            left64: Array(repeating: 0, count: 64),
            right64: Array(repeating: 0, count: 64)
        )?.first

        let invalidPlanRejected = SceneScriptAudioBarsGeometry.instances(
            plan: plan(
                width: .nan,
                height: 1,
                depth: 1,
                xStep: 0,
                yStep: 0,
                angle: 0,
                firstStep: .ownerAtBaseOrigin
            ),
            left64: left,
            right64: right
        ) == nil
        let invalidBudgetRejected = SceneScriptAudioBarsGeometry.instances(
            plan: plan(
                barCount: 63,
                width: 1,
                height: 1,
                depth: 1,
                xStep: 0,
                yStep: 0,
                angle: 0,
                firstStep: .ownerAtBaseOrigin
            ),
            left64: left,
            right64: right
        ) == nil
        let invalidResolutionRejected = SceneScriptAudioBarsGeometry.instances(
            plan: plan(
                audioResolution: 32,
                width: 1,
                height: 1,
                depth: 1,
                xStep: 0,
                yStep: 0,
                angle: 0,
                firstStep: .ownerAtBaseOrigin
            ),
            left64: left,
            right64: right
        ) == nil
        let invalidArrayRejected = SceneScriptAudioBarsGeometry.instances(
            plan: horizontalPlan,
            left64: Array(repeating: 0, count: 63),
            right64: right
        ) == nil && SceneScriptAudioBarsGeometry.instances(
            plan: horizontalPlan,
            left64: Array(repeating: .infinity, count: 64),
            right64: right
        ) == nil
        let invalidBaseRejected = horizontalFirst.map {
            SceneScriptAudioBarsGeometry.modelMatrix(
                authoredBaseOrigin: SIMD3(.nan, 0, 0),
                sceneOrthoHeight: 2160,
                baseSize: SIMD2(4, 4),
                instance: $0
            ) == nil && SceneScriptAudioBarsGeometry.modelMatrix(
                authoredBaseOrigin: .zero,
                sceneOrthoHeight: 2160,
                baseSize: SIMD2(0, 4),
                instance: $0
            ) == nil && SceneScriptAudioBarsGeometry.modelMatrix(
                authoredBaseOrigin: .zero,
                sceneOrthoHeight: 0,
                baseSize: SIMD2(4, 4),
                instance: $0
            ) == nil
        } ?? false

        let result: [String: Any] = [
            "horizontalCount": horizontal?.count ?? -1,
            "horizontalFirstOffset": horizontalFirst.map {
                vector($0.originOffset)
            } ?? [],
            "horizontalLastOffset": horizontalLast.map {
                vector($0.originOffset)
            } ?? [],
            "horizontalFirstScale": horizontalFirst.map {
                vector($0.scale)
            } ?? [],
            "horizontalSecondHeight": horizontal?[1].scale.y ?? -1,
            "horizontalLastScale": horizontalLast.map {
                vector($0.scale)
            } ?? [],
            "horizontalFirstTranslation": translation(horizontalFirstModel),
            "horizontalLastTranslation": translation(horizontalLastModel),
            "horizontalFirstColumns": columns(horizontalFirstModel),
            "horizontalFirstAngle": horizontalFirst?.angleRadians ?? -1,
            "horizontalFirstPivot": horizontalFirst.map {
                vector($0.pivot)
            } ?? [],
            "diagonalCount": diagonal?.count ?? -1,
            "diagonalFirstOffset": diagonalFirst.map {
                vector($0.originOffset)
            } ?? [],
            "diagonalLastOffset": diagonalLast.map {
                vector($0.originOffset)
            } ?? [],
            "diagonalFirstScale": diagonalFirst.map {
                vector($0.scale)
            } ?? [],
            "diagonalFirstAngle": diagonalFirst?.angleRadians ?? -1,
            "diagonalFirstTranslation": translation(diagonalFirstModel),
            "diagonalFirstColumns": columns(diagonalFirstModel),
            "bottomPivot": bottom.map { vector($0.pivot) } ?? [],
            "topPivot": top.map { vector($0.pivot) } ?? [],
            "invalidPlanRejected": invalidPlanRejected,
            "invalidBudgetRejected": invalidBudgetRejected,
            "invalidResolutionRejected": invalidResolutionRejected,
            "invalidArrayRejected": invalidArrayRejected,
            "invalidBaseRejected": invalidBaseRejected,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneScriptAudioBarsGeometryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-script-audio-bars-geometry-"
        )
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = root / "scene-script-audio-bars-geometry"
        compilation = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                *(str(path) for path in SOURCES),
                str(harness),
                "-o",
                str(cls.binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(cls.binary)],
            check=True,
            capture_output=True,
            text=True,
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def assert_vector(
        self,
        actual: list[float],
        expected: list[float],
        places: int = 4,
    ) -> None:
        self.assertEqual(len(actual), len(expected), actual)
        for actual_value, expected_value in zip(actual, expected):
            self.assertAlmostEqual(actual_value, expected_value, places=places)

    def test_horizontal_profile_has_exact_budget_and_unclamped_average(self) -> None:
        self.assertEqual(self.result["horizontalCount"], 64)
        self.assert_vector(self.result["horizontalFirstOffset"], [0, 0, 0])
        self.assert_vector(self.result["horizontalLastOffset"], [1260, 0, 0])
        self.assert_vector(self.result["horizontalFirstScale"], [2.5, 150, 0])
        self.assertEqual(self.result["horizontalSecondHeight"], 0)
        self.assert_vector(self.result["horizontalLastScale"], [2.5, 50, 0])
        self.assertEqual(self.result["horizontalFirstAngle"], 0)
        self.assert_vector(self.result["horizontalFirstPivot"], [0, 0])

    def test_horizontal_first_and_last_models_use_base_origin_and_script_scale(self) -> None:
        self.assert_vector(
            self.result["horizontalFirstTranslation"],
            [1286.96362, 2044.83301, 0],
        )
        self.assert_vector(
            self.result["horizontalLastTranslation"],
            [2546.96362, 2044.83301, 0],
        )
        columns = self.result["horizontalFirstColumns"]
        self.assert_vector(columns[0], [10, 0, 0])
        self.assert_vector(columns[1], [0, -600, 0])
        self.assert_vector(columns[2], [0, 0, 0])

    def test_advance_before_first_bar_and_sixty_degree_override(self) -> None:
        self.assertEqual(self.result["diagonalCount"], 64)
        self.assert_vector(self.result["diagonalFirstOffset"], [5.6, 11.3, 0])
        self.assert_vector(self.result["diagonalLastOffset"], [358.4, 723.2, 0])
        self.assert_vector(self.result["diagonalFirstScale"], [1, 50, 1])
        self.assertAlmostEqual(
            self.result["diagonalFirstAngle"],
            3.141592653589793 / 3,
            places=5,
        )
        self.assert_vector(
            self.result["diagonalFirstTranslation"],
            [868.50399, 695.42705, 0],
        )
        columns = self.result["diagonalFirstColumns"]
        self.assert_vector(columns[0], [2, -3.4641016, 0])
        self.assert_vector(columns[1], [-173.20508, -100, 0])
        self.assert_vector(columns[2], [0, 0, 1])

    def test_alignment_maps_to_image_layer_pivots(self) -> None:
        self.assert_vector(self.result["bottomPivot"], [0, 0.5])
        self.assert_vector(self.result["topPivot"], [0, -0.5])

    def test_invalid_contracts_fail_as_a_whole(self) -> None:
        self.assertTrue(self.result["invalidPlanRejected"])
        self.assertTrue(self.result["invalidBudgetRejected"])
        self.assertTrue(self.result["invalidResolutionRejected"])
        self.assertTrue(self.result["invalidArrayRejected"])
        self.assertTrue(self.result["invalidBaseRejected"])


if __name__ == "__main__":
    unittest.main()
