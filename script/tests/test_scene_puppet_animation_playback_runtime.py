#!/usr/bin/env python3
"""Launch-owned Puppet positions freeze while hidden and sample once per cadence."""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from script.tests.test_scene_puppet_playback import SCENE_ROOT, SWIFT_SOURCES


HARNESS = r'''
import Foundation
import simd

enum SceneDynamicTarget: Hashable {
    case scriptInstanceProperty(layerID: Int, path: [String])
}
enum SceneDynamicValue { case bool(Bool), number(Double) }
struct SceneDynamicResolvedValue { let value: SceneDynamicValue }
enum Observation { static var visibilityReads = 0 }
struct SceneDynamicSnapshot {
    let values: [SceneDynamicTarget: SceneDynamicResolvedValue]
    subscript(target: SceneDynamicTarget) -> SceneDynamicResolvedValue? {
        Observation.visibilityReads += 1
        return values[target]
    }
}
func layer(id: Int = 10, animationID: Int = 1, rate: Double = 1,
           visible: Bool = true, binding: String? = "enabled") -> ScenePuppetAnimationLayer {
    .init(id: id, animationID: animationID, name: "track", additive: true,
        blend: 1, blendIn: false, blendOut: false, blendTime: 0,
        rate: rate, visible: visible, visibilityBinding: binding)
}
func animation(id: Int = 1, mode: String = "loop", fps: Float = 2,
               alpha: [[Float]]? = nil) -> SceneMdlPuppetAnimation {
    .init(id: id, name: "track", mode: mode, framesPerSecond: fps, frameCount: 4,
        transformsByBone: [(0...4).map { frame in
            .init(translation: SIMD3(Float(frame), 0, 0), rotation: .zero,
                scale: SIMD3(repeating: 1))
        }], alphaByBone: alpha)
}
func selection(_ layer: ScenePuppetAnimationLayer,
               _ animation: SceneMdlPuppetAnimation) -> ScenePuppetAnimationSelection {
    .init(clips: [.init(layer: layer, animation: animation)], composition: .layered)
}
func visible(_ entries: [Int: Bool]) -> SceneDynamicSnapshot {
    .init(values: Dictionary(uniqueKeysWithValues: entries.map { parent, value in
        (ScenePuppetAnimationPropertyTarget.visibility(layerID: parent, animationLayerID: 10),
         .init(value: .bool(value)))
    }))
}
func report(_ frame: ScenePuppetAnimationPlaybackRuntime.FrameSnapshot, layerID: Int = 42)
    -> [[Double]] {
    frame[layerID]!.samples.map { sample in
        sample.map { [Double($0.frameA), Double($0.frameB), Double($0.fraction)] } ?? []
    }
}
func registration(_ result: Result<Void, ScenePuppetAnimationPlaybackRuntime.Failure>) -> Bool {
    if case .success = result { return true }
    return false
}

@main enum Harness {
    static func main() throws {
        var output: [String: Any] = [:]
        let definition = selection(layer(), animation())
        let runtime = ScenePuppetAnimationPlaybackRuntime()
        try runtime.register(layerID: 42, selection: definition,
            authoredLayers: definition.clips.map(\.layer)).get()
        let first = runtime.advance(frameIndex: 0, sceneTime: 0.5, dynamicValues: visible([42: true]))
        let beforeHide = runtime.advance(frameIndex: 1, sceneTime: 1, dynamicValues: visible([42: true]))
        let hidden = runtime.advance(frameIndex: 2, sceneTime: 2, dynamicValues: visible([42: false]))
        _ = runtime.advance(frameIndex: 3, sceneTime: 10, dynamicValues: visible([42: false]))
        let resumed = runtime.advance(frameIndex: 4, sceneTime: 10.25, dynamicValues: visible([42: true]))
        let reads = Observation.visibilityReads
        let duplicate = runtime.advance(frameIndex: 4, sceneTime: 100, dynamicValues: visible([42: false]))
        let stale = runtime.advance(frameIndex: 3, sceneTime: 100, dynamicValues: visible([42: false]))
        output["hiddenResume"] = ["first": report(first), "beforeHide": report(beforeHide),
            "hidden": report(hidden), "resumed": report(resumed), "duplicate": report(duplicate),
            "stale": report(stale), "duplicateSceneTime": duplicate.sceneTime,
            "visibilityReadOnce": Observation.visibilityReads == reads,
            "oldSnapshotRetained": report(beforeHide) == [[2, 3, 0]]]

        let sameRegistration = registration(runtime.register(layerID: 42, selection: definition,
            authoredLayers: definition.clips.map(\.layer)))
        let afterRebuild = runtime.advance(frameIndex: 5, sceneTime: 10.5,
            dynamicValues: visible([42: true]))
        let changed = selection(layer(), animation(fps: 4))
        let conflict = registration(runtime.register(layerID: 42, selection: changed,
            authoredLayers: changed.clips.map(\.layer)))
        let changedAlpha = selection(layer(), animation(alpha: [[1, 1, 1, 1, 0.5]]))
        let alphaConflict = registration(runtime.register(layerID: 42, selection: changedAlpha,
            authoredLayers: changedAlpha.clips.map(\.layer)))
        let afterConflict = runtime.advance(frameIndex: 6, sceneTime: 10.75,
            dynamicValues: visible([42: true]))
        output["registration"] = ["same": sameRegistration, "afterRebuild": report(afterRebuild),
            "conflictAccepted": conflict, "alphaConflictAccepted": alphaConflict,
            "afterConflict": report(afterConflict)]

        let initialHidden = ScenePuppetAnimationPlaybackRuntime()
        try initialHidden.register(layerID: 42, selection: definition,
            authoredLayers: definition.clips.map(\.layer)).get()
        _ = initialHidden.advance(frameIndex: 0, sceneTime: 5, dynamicValues: visible([42: false]))
        _ = initialHidden.advance(frameIndex: 1, sceneTime: 8, dynamicValues: visible([42: false]))
        output["initialHiddenResume"] = report(initialHidden.advance(frameIndex: 2,
            sceneTime: 8.25, dynamicValues: visible([42: true])))

        var natural: [String: Bool] = [:]
        for mode in ["single", "loop", "mirror"] {
            for rate in [0.5, 1, 1.5] {
                let clip = selection(layer(rate: rate, binding: nil), animation(mode: mode))
                let owner = ScenePuppetAnimationPlaybackRuntime()
                try owner.register(layerID: 42, selection: clip,
                    authoredLayers: clip.clips.map(\.layer)).get()
                var matches = true
                for (index, time) in [2.75, 3.0, 4.25, 6.5].enumerated() {
                    let frame = owner.advance(frameIndex: UInt64(index), sceneTime: time,
                        dynamicValues: visible([:]))
                    matches = matches && frame[42]!.samples[0] == ScenePuppetAnimationEvaluator.frameSample(
                        sceneTime: time, rate: rate, animation: clip.clips[0].animation)
                }
                natural["\(mode)-\(rate)"] = matches
            }
        }
        output["naturalSamples"] = natural

        let parentOwner = ScenePuppetAnimationPlaybackRuntime()
        try parentOwner.register(layerID: 42, selection: definition,
            authoredLayers: definition.clips.map(\.layer)).get()
        try parentOwner.register(layerID: 77, selection: definition,
            authoredLayers: definition.clips.map(\.layer)).get()
        _ = parentOwner.advance(frameIndex: 0, sceneTime: 0, dynamicValues: visible([42: true, 77: true]))
        let independent = parentOwner.advance(frameIndex: 1, sceneTime: 0.25,
            dynamicValues: visible([42: false, 77: true]))
        output["parentIdentity"] = ["hidden": report(independent), "visible": report(independent, layerID: 77)]

        let authoredOwner = ScenePuppetAnimationPlaybackRuntime()
        let extra = layer(id: 9, visible: false, binding: nil)
        try authoredOwner.register(layerID: 42, selection: definition,
            authoredLayers: [extra, definition.clips[0].layer]).get()
        output["authoredPositionConflictAccepted"] = registration(authoredOwner.register(
            layerID: 42, selection: definition, authoredLayers: [definition.clips[0].layer]))

        let invalidVisibilityOwner = ScenePuppetAnimationPlaybackRuntime()
        try invalidVisibilityOwner.register(layerID: 42, selection: definition,
            authoredLayers: definition.clips.map(\.layer)).get()
        let missing = invalidVisibilityOwner.advance(frameIndex: 0, sceneTime: 5,
            dynamicValues: visible([:]))
        let wrong = invalidVisibilityOwner.advance(frameIndex: 1, sceneTime: 6,
            dynamicValues: .init(values: [ScenePuppetAnimationPropertyTarget.visibility(
                layerID: 42, animationLayerID: 10): .init(value: .number(1))]))
        let valid = invalidVisibilityOwner.advance(frameIndex: 2, sceneTime: 6.25,
            dynamicValues: visible([42: true]))
        output["invalidVisibility"] = ["missing": report(missing), "wrong": report(wrong),
            "restored": report(valid)]

        let initiallyEmpty = ScenePuppetAnimationPlaybackRuntime()
        let emptyFrame = initiallyEmpty.advance(frameIndex: 7, sceneTime: 2.5,
            dynamicValues: visible([:]))
        try initiallyEmpty.register(layerID: 42, selection: definition,
            authoredLayers: definition.clips.map(\.layer)).get()
        let filledEmpty = initiallyEmpty.advance(frameIndex: 7, sceneTime: 100,
            dynamicValues: visible([42: true]))
        output["pausedEmptyRegistration"] = ["oldFrameStaysEmpty": emptyFrame[42] == nil,
            "filled": report(filledEmpty), "sceneTime": filledEmpty.sceneTime]

        let lateParent = ScenePuppetAnimationPlaybackRuntime()
        try lateParent.register(layerID: 42, selection: definition,
            authoredLayers: definition.clips.map(\.layer)).get()
        let oldParent = lateParent.advance(frameIndex: 7, sceneTime: 2.5,
            dynamicValues: visible([42: true]))
        try lateParent.register(layerID: 77, selection: definition,
            authoredLayers: definition.clips.map(\.layer)).get()
        let readsBeforeFill = Observation.visibilityReads
        let filled = lateParent.advance(frameIndex: 7, sceneTime: 200,
            dynamicValues: visible([42: false, 77: true]))
        let readsAfterFill = Observation.visibilityReads
        let repeated = lateParent.advance(frameIndex: 7, sceneTime: 300,
            dynamicValues: visible([42: false, 77: false]))
        let readsAfterRepeat = Observation.visibilityReads
        let next = lateParent.advance(frameIndex: 8, sceneTime: 2.75,
            dynamicValues: visible([42: true, 77: true]))
        output["pausedLateRegistration"] = ["oldParent": report(oldParent),
            "retainedParent": report(filled), "newParent": report(filled, layerID: 77),
            "repeatedParent": report(repeated, layerID: 77), "sceneTime": filled.sceneTime,
            "onlyNewVisibilityRead": readsAfterFill - readsBeforeFill == 1,
            "repeatReadsNoVisibility": readsAfterRepeat == readsAfterFill,
            "oldSnapshotMissingNewParent": oldParent[77] == nil,
            "nextOldParent": report(next), "nextNewParent": report(next, layerID: 77)]
        print(String(decoding: try JSONSerialization.data(withJSONObject: output,
            options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


class PuppetAnimationPlaybackRuntimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if not shutil.which("swiftc"):
            raise unittest.SkipTest("Swift toolchain unavailable")
        with tempfile.TemporaryDirectory(prefix="mwx-puppet-playback-runtime-") as directory:
            root = Path(directory)
            source, binary = root / "runtime.swift", root / "runtime"
            source.write_text(HARNESS, encoding="utf-8")
            command = ["swiftc", *map(str, SWIFT_SOURCES),
                       str(SCENE_ROOT / "Systems/Puppet/ScenePuppetAnimationPlaybackRuntime.swift"),
                       str(SCENE_ROOT / "Systems/Properties/ScenePuppetAnimationPropertyTarget.swift"),
                       str(source), "-o", str(binary)]
            run = subprocess.run(command, capture_output=True, text=True, timeout=120)
            if run.returncode:
                raise RuntimeError(run.stdout + run.stderr)
            run = subprocess.run([str(binary)], capture_output=True, text=True, check=True, timeout=30)
            cls.result = json.loads(run.stdout)

    def test_hidden_position_freezes_and_resumes_current_cadence_only(self) -> None:
        result = self.result["hiddenResume"]
        self.assertEqual(result["first"], [[1, 2, 0]])
        self.assertEqual(result["beforeHide"], [[2, 3, 0]])
        self.assertEqual(result["hidden"], [[]])
        self.assertEqual(result["resumed"], [[2, 3, 0.5]])

    def test_initially_hidden_clip_starts_at_zero_before_resume(self) -> None:
        self.assertEqual(self.result["initialHiddenResume"], [[0, 1, 0.5]])

    def test_same_cadence_multi_consumer_and_stale_request_reuse_snapshot(self) -> None:
        result = self.result["hiddenResume"]
        self.assertEqual(result["duplicate"], result["resumed"])
        self.assertEqual(result["stale"], result["resumed"])
        self.assertEqual(result["duplicateSceneTime"], 10.25)
        self.assertTrue(result["visibilityReadOnce"])
        self.assertTrue(result["oldSnapshotRetained"])

    def test_rebuild_registration_keeps_position_and_conflicts_preserve_definition(self) -> None:
        result = self.result["registration"]
        self.assertTrue(result["same"])
        self.assertEqual(result["afterRebuild"], [[3, 4, 0]])
        self.assertFalse(result["conflictAccepted"])
        self.assertFalse(result["alphaConflictAccepted"])
        self.assertEqual(result["afterConflict"], [[3, 4, 0.5]])

    def test_single_loop_mirror_and_rates_preserve_natural_fractional_sampler(self) -> None:
        self.assertEqual(len(self.result["naturalSamples"]), 9)
        self.assertTrue(all(self.result["naturalSamples"].values()))

    def test_parent_layer_identity_prevents_visibility_cross_talk(self) -> None:
        self.assertEqual(self.result["parentIdentity"], {"hidden": [[]], "visible": [[0, 1, 0.5]]})

    def test_authored_position_is_part_of_immutable_registration(self) -> None:
        self.assertFalse(self.result["authoredPositionConflictAccepted"])

    def test_missing_or_wrong_visibility_stays_hidden_and_preserves_zero_position(self) -> None:
        self.assertEqual(self.result["invalidVisibility"],
                         {"missing": [[]], "wrong": [[]], "restored": [[0, 1, 0.5]]})

    def test_paused_cadence_late_registration_fills_only_missing_parent(self) -> None:
        empty = self.result["pausedEmptyRegistration"]
        self.assertTrue(empty["oldFrameStaysEmpty"])
        self.assertEqual(empty["filled"], [[1, 2, 0]])
        self.assertEqual(empty["sceneTime"], 2.5)
        result = self.result["pausedLateRegistration"]
        for name in ("oldParent", "retainedParent", "newParent", "repeatedParent"):
            with self.subTest(frame=name):
                self.assertEqual(result[name], [[1, 2, 0]])
        self.assertEqual(result["sceneTime"], 2.5)
        self.assertTrue(result["onlyNewVisibilityRead"])
        self.assertTrue(result["repeatReadsNoVisibility"])
        self.assertTrue(result["oldSnapshotMissingNewParent"])
        self.assertEqual(result["nextOldParent"], [[1, 2, 0.5]])
        self.assertEqual(result["nextNewParent"], [[1, 2, 0.5]])


if __name__ == "__main__":
    unittest.main()
