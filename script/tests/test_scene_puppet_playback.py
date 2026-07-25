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
SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneMdlPuppetMeshReader.swift",
    SCENE_ROOT / "Format/SceneMdlPuppetRigReader.swift",
    SCENE_ROOT / "Format/SceneMdlPuppetAnimation.swift",
    SCENE_ROOT / "Format/ScenePuppetAnimationLayer.swift",
    SCENE_ROOT / "Rendering/SceneMatrix.swift",
    SCENE_ROOT / "Rendering/ScenePuppetAnimationEvaluator.swift",
]

HARNESS = r'''
import Foundation
import simd

func layer(
    id: Int = 10,
    animationID: Int = 100,
    additive: Bool = false,
    blend: Double = 1,
    visible: Bool? = true,
    visibilityBinding: String? = nil
) -> ScenePuppetAnimationLayer {
    ScenePuppetAnimationLayer(
        id: id,
        animationID: animationID,
        name: "Idle",
        additive: additive,
        blend: blend,
        blendIn: false,
        blendOut: false,
        blendTime: 0.5,
        rate: 1,
        visible: visible,
        visibilityBinding: visibilityBinding
    )
}

func transform(translationX: Float) -> SceneMdlPuppetAnimation.Transform {
    .init(
        translation: SIMD3(translationX, 0, 0),
        rotation: .zero,
        scale: SIMD3(repeating: 1)
    )
}

func selectionResult(
    _ layers: [ScenePuppetAnimationLayer],
    set: SceneMdlPuppetAnimationSet
) -> String {
    switch ScenePuppetAnimationSelector.select(layers: layers, animationSet: set) {
    case .success(let selection?): return "selected:\(selection.animation.id)"
    case .success(nil): return "inactive"
    case .failure(let failure): return failure.description
    }
}

@main
enum Harness {
    static func main() throws {
        let animation = SceneMdlPuppetAnimation(
            id: 100,
            name: "Idle",
            mode: "loop",
            framesPerSecond: 2,
            frameCount: 2,
            transformsByBone: [
                [transform(translationX: 4), transform(translationX: 4), transform(translationX: 4)],
                [transform(translationX: 2), transform(translationX: 5), transform(translationX: 2)],
            ]
        )
        let set = SceneMdlPuppetAnimationSet(boneCount: 2, animations: [animation])
        let mesh = SceneMdlPuppetMesh(
            version: "MDLV0023",
            vertexStride: 80,
            meshBlockOffset: 9,
            vertices: [.init(x: 2, y: 1, z: 0, u: 0.5, v: 0.25)],
            indices: [0, 0, 0]
        )
        let rootBind: [Float] = [
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            4, 0, 0, 1,
        ]
        let childBind: [Float] = [
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            2, 0, 0, 1,
        ]
        let rig = SceneMdlPuppetRig(
            bones: [
                .init(parentIndex: -1, bindLocalMatrixColumnMajor: rootBind),
                .init(parentIndex: 0, bindLocalMatrixColumnMajor: childBind),
            ],
            vertexWeights: [.init(
                boneIndices: SIMD4(1, 0, 0, 0),
                boneWeights: SIMD4(1, 0, 0, 0)
            )]
        )
        let evaluator = try ScenePuppetAnimationEvaluator(mesh: mesh, rig: rig)
        let frame0 = try evaluator.deformedPositions(animation: animation, frameIndex: 0)[0]
        let frame1 = try evaluator.deformedPositions(animation: animation, frameIndex: 1)[0]
        let missingNumbers = ScenePuppetAnimationLayer.parse([
            ["id": 10, "animation": 100]
        ])[0]
        let malformedNumbers = ScenePuppetAnimationLayer.parse([
            [
                "id": 11,
                "animation": 100,
                "blend": ["value": ["unexpected": 1]],
                "blendtime": NSNull(),
                "rate": "fast",
            ]
        ])[0]
        let payload: [String: Any] = [
            "selection": selectionResult([layer()], set: set),
            "inactive": selectionResult([layer(visible: false)], set: set),
            "multi": selectionResult([layer(id: 10), layer(id: 11)], set: set),
            "additive": selectionResult([layer(additive: true)], set: set),
            "blend": selectionResult([layer(blend: 0.5)], set: set),
            "boundVisibility": selectionResult(
                [layer(visibilityBinding: "animate")], set: set
            ),
            "unknown": selectionResult([layer(animationID: 999)], set: set),
            "frameIndices": [0.0, 0.6, 1.0].map {
                ScenePuppetAnimationEvaluator.frameIndex(
                    sceneTime: $0, rate: 1, animation: animation
                )
            },
            "frame0": [frame0.x, frame0.y],
            "frame1": [frame1.x, frame1.y],
            "missingNumbersAreNil": missingNumbers.blend == nil
                && missingNumbers.blendTime == nil
                && missingNumbers.rate == nil,
            "malformedNumbersAreNil": malformedNumbers.blend == nil
                && malformedNumbers.blendTime == nil
                && malformedNumbers.rate == nil,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class ScenePuppetPlaybackTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-puppet-playback-")
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = directory / "puppet-playback"
        compilation = subprocess.run(
            ["swiftc", *map(str, SWIFT_SOURCES), str(harness), "-o", str(binary)],
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

    def test_strict_single_clip_selection(self) -> None:
        self.assertEqual(self.result["selection"], "selected:100")
        self.assertEqual(self.result["inactive"], "inactive")

    def test_unknown_mixing_and_dynamic_visibility_fail_closed(self) -> None:
        self.assertIn("require unsupported mixing", self.result["multi"])
        self.assertIn("outside the strict single-clip profile", self.result["additive"])
        self.assertIn("outside the strict single-clip profile", self.result["blend"])
        self.assertIn("property-bound visibility", self.result["boundVisibility"])
        self.assertIn("absent from MDLA0006", self.result["unknown"])

    def test_fixed_step_sampling_wraps_without_interpolation(self) -> None:
        self.assertEqual(self.result["frameIndices"], [0, 1, 0])

    def test_bind_identity_and_later_frame_movement(self) -> None:
        self.assertEqual(self.result["frame0"], [2, 1])
        self.assertEqual(self.result["frame1"], [5, 1])

    def test_missing_and_malformed_optional_numbers_fail_closed(self) -> None:
        self.assertTrue(self.result["missingNumbersAreNil"])
        self.assertTrue(self.result["malformedNumbersAreNil"])


if __name__ == "__main__":
    unittest.main()
