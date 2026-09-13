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
PLAYBACK_STATE_SOURCE = (
    SCENE_ROOT / "Rendering/ScenePuppetPlaybackState.swift"
).read_text(encoding="utf-8")
SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneMdlPuppetMeshReader.swift",
    SCENE_ROOT / "Format/SceneMdlPuppetRigReader.swift",
    SCENE_ROOT / "Format/SceneMdlPuppetAnimation.swift",
    SCENE_ROOT / "Format/ScenePuppetAnimationLayer.swift",
    SCENE_ROOT / "Rendering/SceneMatrix.swift",
    SCENE_ROOT / "Rendering/ScenePuppetAnimationSelection.swift",
    SCENE_ROOT / "Rendering/ScenePuppetAnimationEvaluator.swift",
    SCENE_ROOT / "Rendering/ScenePuppetAnimationEvaluator+Transforms.swift",
    SCENE_ROOT / "Rendering/ScenePuppetAnimationEvaluator+FrameSampling.swift",
]

HARNESS = r'''
import Foundation
import simd

func layer(
    id: Int = 10,
    animationID: Int = 100,
    additive: Bool = false,
    blend: Double = 1,
    rate: Double = 1,
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
        rate: rate,
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
    case .success(let selection?):
        return "selected:\(selection.composition.rawValue):"
            + selection.clips.map { String($0.animation.id) }.joined(separator: ",")
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
        let rootAnimation = SceneMdlPuppetAnimation(
            id: 200,
            name: "Root",
            mode: "loop",
            framesPerSecond: 2,
            frameCount: 2,
            transformsByBone: [
                [transform(translationX: 4), transform(translationX: 7), transform(translationX: 4)],
                [transform(translationX: 2), transform(translationX: 2), transform(translationX: 2)],
            ]
        )
        let mirrorAnimation = SceneMdlPuppetAnimation(
            id: 500,
            name: "Mirror",
            mode: "mirror",
            framesPerSecond: 2,
            frameCount: 2,
            transformsByBone: [
                [transform(translationX: 4), transform(translationX: 5), transform(translationX: 6)],
                [transform(translationX: 2), transform(translationX: 2), transform(translationX: 2)],
            ]
        )
        let overlappingAnimation = SceneMdlPuppetAnimation(
            id: 300,
            name: "Overlap",
            mode: "loop",
            framesPerSecond: 2,
            frameCount: 2,
            transformsByBone: [
                [transform(translationX: 4), transform(translationX: 4), transform(translationX: 4)],
                [transform(translationX: 2), transform(translationX: 3), transform(translationX: 2)],
            ]
        )
        let nonBindAnimation = SceneMdlPuppetAnimation(
            id: 400,
            name: "NonBind",
            mode: "loop",
            framesPerSecond: 2,
            frameCount: 2,
            transformsByBone: [
                [transform(translationX: 5), transform(translationX: 6), transform(translationX: 5)],
                [transform(translationX: 2), transform(translationX: 2), transform(translationX: 2)],
            ]
        )
        let set = SceneMdlPuppetAnimationSet(
            boneCount: 2,
            animations: [animation, rootAnimation, mirrorAnimation]
        )
        let mesh = SceneMdlPuppetMesh(
            version: "MDLV0023",
            vertexStride: 80,
            meshBlockOffset: 9,
            vertices: [
                .init(x: 2, y: 1, z: 0, u: 0.5, v: 0.25),
                .init(x: -6, y: -4, z: 0, u: 0.25, v: 0.75),
            ],
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
            vertexWeights: [
                .init(
                    boneIndices: SIMD4(1, 0, 0, 0),
                    boneWeights: SIMD4(1, 0, 0, 0)
                ),
                .init(
                    boneIndices: SIMD4(0, 0, 0, 0),
                    boneWeights: SIMD4(1, 0, 0, 0)
                ),
            ]
        )
        let evaluator = try ScenePuppetAnimationEvaluator(mesh: mesh, rig: rig)
        let frame0 = try evaluator.deformedPositions(animation: animation, frameIndex: 0)[0]
        let frame1Positions = try evaluator.deformedPositions(
            animation: animation,
            frameIndex: 1
        )
        let frame1 = frame1Positions[0]
        var scratchPositions = Array(
            repeating: SIMD2<Float>.zero,
            count: mesh.vertices.count
        )
        var localMatrixScratch = Array(
            repeating: matrix_identity_float4x4,
            count: evaluator.boneCount
        )
        var skinMatrixScratch = localMatrixScratch
        try scratchPositions.withUnsafeMutableBufferPointer { output in
            try evaluator.writeDeformedPositions(
                selection: ScenePuppetAnimationSelection(
                    clips: [.init(layer: layer(), animation: animation)],
                    composition: .singleAbsolute
                ),
                frameSamples: [.init(frameA: 1, frameB: 1)],
                into: output,
                localMatricesScratch: &localMatrixScratch,
                skinMatricesScratch: &skinMatrixScratch
            )
        }
        let expectedFrame1Bounds = frame1Positions.reduce(
            into: SIMD2<Float>(repeating: 0)
        ) { bounds, position in
            bounds.x = max(bounds.x, abs(position.x))
            bounds.y = max(bounds.y, abs(position.y))
        }
        let singleSelection = ScenePuppetAnimationSelection(
            clips: [.init(layer: layer(), animation: animation)],
            composition: .singleAbsolute
        )
        let frame1Bounds = try evaluator.maxAbsDeformedPosition(
            selection: singleSelection,
            frameSamples: [.init(frameA: 1, frameB: 1)]
        )
        let worldOverrideTransforms = try evaluator.boneTransforms(
            selection: singleSelection,
            frameSamples: [.init(frameA: 0, frameB: 0)],
            boneOverrides: [1: .world(SceneMatrix.translation(SIMD3(20, 0, 0)))]
        )
        let worldOverrideChildX = worldOverrideTransforms.world[1].columns.3.x
        let worldOverrideLocalX = worldOverrideTransforms.local[1].columns.3.x
        var nonFiniteOverride = matrix_identity_float4x4
        nonFiniteOverride.columns.0.x = .nan
        let nonFiniteRejected: Bool
        do {
            _ = try evaluator.boneTransforms(
                selection: singleSelection,
                frameSamples: [.init(frameA: 0, frameB: 0)],
                boneOverrides: [0: .local(nonFiniteOverride)]
            )
            nonFiniteRejected = false
        } catch {
            nonFiniteRejected = true
        }
        let staticAnimation = SceneMdlPuppetAnimation(
            id: 600,
            name: "Static",
            mode: "loop",
            framesPerSecond: 2,
            frameCount: 2,
            transformsByBone: [
                [transform(translationX: 4), transform(translationX: 4), transform(translationX: 4)],
                [transform(translationX: 2), transform(translationX: 2), transform(translationX: 2)],
            ]
        )
        let invariantEvaluator = try ScenePuppetAnimationEvaluator(
            mesh: mesh,
            rig: rig,
            additiveAnimations: [animation, staticAnimation]
        )
        let conservativeBounds = try invariantEvaluator.conservativeMaxAbsDeformedPosition(
            selection: singleSelection,
            frameSamplesBatch: [
                [.init(frameA: 0, frameB: 0)],
                [.init(frameA: 1, frameB: 1)],
            ]
        )
        let additiveSelection: ScenePuppetAnimationSelection
        switch ScenePuppetAnimationSelector.select(
            layers: [
                layer(id: 10, animationID: 100, additive: true),
                layer(id: 20, animationID: 200, additive: true),
            ],
            animationSet: set
        ) {
        case .success(let selection?): additiveSelection = selection
        default: fatalError("layered additive selection failed")
        }
        let additiveEvaluator = try ScenePuppetAnimationEvaluator(
            mesh: mesh,
            rig: rig,
            additiveAnimations: additiveSelection.clips.map(\.animation)
        )
        let additiveBoth = try additiveEvaluator.deformedPositions(
            selection: additiveSelection,
            frameIndices: [1, 1]
        )[0]
        let additiveChildOnly = try additiveEvaluator.deformedPositions(
            selection: additiveSelection,
            frameIndices: [1, nil]
        )[0]
        let additiveRootOnly = try additiveEvaluator.deformedPositions(
            selection: additiveSelection,
            frameIndices: [nil, 1]
        )[0]
        let overlapError: String
        do {
            _ = try ScenePuppetAnimationEvaluator(
                mesh: mesh,
                rig: rig,
                additiveAnimations: [animation, overlappingAnimation]
            )
            overlapError = "accepted"
        } catch let failure as ScenePuppetAnimationEvaluationFailure {
            overlapError = failure.description
        }
        let nonBindError: String
        do {
            _ = try ScenePuppetAnimationEvaluator(
                mesh: mesh,
                rig: rig,
                additiveAnimations: [nonBindAnimation]
            )
            nonBindError = "accepted"
        } catch let failure as ScenePuppetAnimationEvaluationFailure {
            nonBindError = failure.description
        }
        let mixedSelection = selectionResult([
            layer(id: 10, animationID: 100),
            layer(id: 11, animationID: 200, additive: true),
        ], set: set)
        let mixedEvaluator = try ScenePuppetAnimationEvaluator(
            mesh: mesh,
            rig: rig,
            additiveAnimations: [animation, rootAnimation]
        )
        let mixedBoth = try mixedEvaluator.deformedPositions(
            selection: ScenePuppetAnimationSelection(
                clips: [
                    .init(layer: layer(id: 10, animationID: 100), animation: animation),
                    .init(layer: layer(id: 11, animationID: 200, additive: true), animation: rootAnimation),
                ],
                composition: .layered
            ),
            frameIndices: [1, 1]
        )[0]
        let sampledEvaluator = try ScenePuppetAnimationEvaluator(
            mesh: mesh,
            rig: rig,
            additiveAnimations: [mirrorAnimation]
        )
        let mirrorPositions = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5].map {
            let sample = ScenePuppetAnimationEvaluator.frameSample(
                sceneTime: $0, rate: 1, animation: mirrorAnimation
            )
            return try! sampledEvaluator.deformedPositions(
                animation: mirrorAnimation,
                frameSample: sample
            )[0].x
        }
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
        let defaultBlendEdges = ScenePuppetAnimationLayer(
            id: 12,
            animationID: 100,
            name: "Default edges",
            additive: false,
            blend: 1,
            blendIn: nil,
            blendOut: nil,
            blendTime: nil,
            rate: 1,
            visible: true,
            visibilityBinding: nil
        )
        let payload: [String: Any] = [
            "selection": selectionResult([layer()], set: set),
            "inactive": selectionResult([layer(visible: false)], set: set),
            "mixed": selectionResult([
                layer(id: 10, animationID: 100),
                layer(id: 11, animationID: 200, additive: true),
            ], set: set),
            "mixedSelection": mixedSelection,
            "additive": selectionResult([layer(additive: true)], set: set),
            "blend": selectionResult([layer(blend: 0.5)], set: set),
            "fractionalRate": selectionResult([layer(rate: 0.8)], set: set),
            "zeroRate": selectionResult([layer(rate: 0)], set: set),
            "boundVisibility": selectionResult(
                [layer(visibilityBinding: "animate")], set: set
            ),
            "defaultBlendEdges": selectionResult([defaultBlendEdges], set: set),
            "unknown": selectionResult([layer(animationID: 999)], set: set),
            "frameIndices": [0.0, 0.6, 1.0].map {
                ScenePuppetAnimationEvaluator.frameIndex(
                    sceneTime: $0, rate: 1, animation: animation
                )
            },
            "mirrorFrameIndices": [0.0, 0.5, 1.0, 1.5, 2.0].map {
                ScenePuppetAnimationEvaluator.frameIndex(
                    sceneTime: $0, rate: 1, animation: mirrorAnimation
                )
            },
            "loopSamples": [0.0, 0.25, 0.5, 0.75, 1.0].map {
                let sample = ScenePuppetAnimationEvaluator.frameSample(
                    sceneTime: $0, rate: 1, animation: animation
                )
                return [sample.frameA, sample.frameB, sample.fraction]
            },
            "singleSamples": [0.0, 0.5, 1.0, 2.0].map {
                let singleAnimation = SceneMdlPuppetAnimation(
                    id: 501,
                    name: "Single",
                    mode: "single",
                    framesPerSecond: 2,
                    frameCount: 2,
                    transformsByBone: animation.transformsByBone
                )
                let sample = ScenePuppetAnimationEvaluator.frameSample(
                    sceneTime: $0, rate: 1, animation: singleAnimation
                )
                return [sample.frameA, sample.frameB, sample.fraction]
            },
            "mirrorSamples": [0.0, 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0].map {
                let sample = ScenePuppetAnimationEvaluator.frameSample(
                    sceneTime: $0, rate: 1, animation: mirrorAnimation
                )
                return [sample.frameA, sample.frameB, sample.fraction]
            },
            "mirrorPositions": mirrorPositions,
            "frame0": [frame0.x, frame0.y],
            "frame1": [frame1.x, frame1.y],
            "scratchFrame1": [scratchPositions[0].x, scratchPositions[0].y],
            "frame1Bounds": [frame1Bounds.x, frame1Bounds.y],
            "frame1BoundsMatch": frame1Bounds == expectedFrame1Bounds,
            "worldOverrideChildX": worldOverrideChildX,
            "worldOverrideLocalX": worldOverrideLocalX,
            "nonFiniteOverrideRejected": nonFiniteRejected,
            "conservativeBoundsCover": conservativeBounds.x >= expectedFrame1Bounds.x
                && conservativeBounds.y >= expectedFrame1Bounds.y,
            "dynamicAnimationTimeVarying": !invariantEvaluator.isTimeInvariant(animationID: 100),
            "staticAnimationTimeInvariant": invariantEvaluator.isTimeInvariant(animationID: 600),
            "additiveBoth": [additiveBoth.x, additiveBoth.y],
            "additiveChildOnly": [additiveChildOnly.x, additiveChildOnly.y],
            "additiveRootOnly": [additiveRootOnly.x, additiveRootOnly.y],
            "overlapError": overlapError,
            "nonBindError": nonBindError,
            "mixedBoth": [mixedBoth.x, mixedBoth.y],
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
        self.assertEqual(self.result["selection"], "selected:single-absolute:100")
        self.assertEqual(self.result["inactive"], "inactive")
        self.assertEqual(
            self.result["defaultBlendEdges"],
            "selected:single-absolute:100",
        )

    def test_bounded_additive_selection_and_unsupported_profiles(self) -> None:
        self.assertEqual(self.result["additive"], "selected:layered:100")
        self.assertEqual(
            self.result["mixed"],
            "selected:layered:100,200",
        )
        self.assertEqual(self.result["mixedSelection"], "selected:layered:100,200")
        self.assertEqual(
            self.result["blend"],
            "selected:single-absolute:100",
        )
        self.assertEqual(
            self.result["fractionalRate"],
            "selected:single-absolute:100",
        )
        self.assertIn(
            "outside the bounded playback profile",
            self.result["zeroRate"],
        )
        self.assertEqual(
            self.result["boundVisibility"],
            "selected:single-absolute:100",
        )
        self.assertIn("absent from the version-matched MDLA block", self.result["unknown"])

    def test_source_fps_sampling_preserves_intervals_and_interpolation(self) -> None:
        self.assertEqual(self.result["frameIndices"], [0, 1, 0])
        self.assertEqual(self.result["mirrorFrameIndices"], [0, 1, 2, 1, 0])
        self.assertEqual(
            self.result["loopSamples"],
            [[0, 1, 0.0], [0, 1, 0.5], [1, 2, 0.0], [1, 2, 0.5], [0, 1, 0.0]],
        )
        self.assertEqual(
            self.result["singleSamples"],
            [[0, 1, 0.0], [1, 2, 0.0], [1, 2, 1.0], [1, 2, 1.0]],
        )
        self.assertEqual(
            self.result["mirrorSamples"],
            [
                [0, 1, 0.0], [0, 1, 0.5], [1, 2, 0.0],
                [1, 2, 0.5], [2, 1, 0.0], [2, 1, 0.5],
                [1, 0, 0.0], [1, 0, 0.5], [0, 1, 0.0],
            ],
        )
        self.assertEqual(self.result["mirrorPositions"], [2.5, 3, 3.5, 4, 3.5, 3])

    def test_bind_identity_and_later_frame_movement(self) -> None:
        self.assertEqual(self.result["frame0"], [2, 1])
        self.assertEqual(self.result["frame1"], [5, 1])
        self.assertEqual(self.result["scratchFrame1"], self.result["frame1"])

    def test_world_override_is_parent_relative_and_nonfinite_is_rejected(self) -> None:
        self.assertAlmostEqual(self.result["worldOverrideChildX"], 20)
        self.assertAlmostEqual(self.result["worldOverrideLocalX"], 16)
        self.assertTrue(self.result["nonFiniteOverrideRejected"])

    def test_bounds_only_reduction_matches_deformed_positions(self) -> None:
        self.assertEqual(self.result["frame1Bounds"], [6, 4])
        self.assertTrue(self.result["frame1BoundsMatch"])
        self.assertTrue(self.result["conservativeBoundsCover"])

    def test_static_clip_signature_fact_is_conservative(self) -> None:
        self.assertTrue(self.result["dynamicAnimationTimeVarying"])
        self.assertTrue(self.result["staticAnimationTimeInvariant"])

    def test_world_geometry_has_no_load_time_pose_coverage_scan(self) -> None:
        self.assertNotIn("coverageSamples", PLAYBACK_STATE_SOURCE)
        self.assertNotIn("conservativeMaxAbsDeformedPosition(", PLAYBACK_STATE_SOURCE)
        self.assertNotIn("coverageExtent(", PLAYBACK_STATE_SOURCE)

    def test_layered_additive_bones_compose_and_visibility_is_per_clip(self) -> None:
        self.assertEqual(self.result["additiveBoth"], [8, 1])
        self.assertEqual(self.result["additiveChildOnly"], [5, 1])
        self.assertEqual(self.result["additiveRootOnly"], [5, 1])

    def test_layered_additive_overlap_and_non_bind_reference_are_composed(self) -> None:
        self.assertEqual(self.result["overlapError"], "accepted")
        self.assertEqual(self.result["nonBindError"], "accepted")
        self.assertEqual(self.result["mixedBoth"], [8, 1])

    def test_missing_and_malformed_optional_numbers_fail_closed(self) -> None:
        self.assertTrue(self.result["missingNumbersAreNil"])
        self.assertTrue(self.result["malformedNumbersAreNil"])


if __name__ == "__main__":
    unittest.main()
