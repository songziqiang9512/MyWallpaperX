#!/usr/bin/env python3

"""Cursor QuickJS owners consume the current shared audio snapshot."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

try:
    from .scene_vector_vm_test_support import compile_vector_harness
except ImportError:
    from scene_vector_vm_test_support import compile_vector_harness


ROOT = Path(__file__).resolve().parents[2]
DEMAND_SOURCE = (
    ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+AudioDemand.swift"
)


CURSOR_HARNESS = r'''
@main
enum Harness {
    static func main() throws {
        let descriptor = SceneRenderDescriptor(layers: [
            layer(id: 10, index: 0), layer(id: 20, index: 1),
        ])
        let bindings = [
            standaloneBinding(layerID: 10, index: 0),
            borrowedBinding(layerID: 20, index: 1),
            siblingBinding(layerID: 20, index: 1),
        ]
        let projection = SceneScriptVectorProgram.project(
            descriptor: descriptor, scriptBindings: bindings
        )
        let candidate = try SceneScriptQuickJSProgramCandidate.compile(
            authoredDescriptor: descriptor,
            runtimeDescriptor: descriptor,
            scriptBindings: bindings,
            vectorProjection: projection,
            userPropertyDefinitions: [], timelineTargets: [],
            scalarExcludedTargets: [], stringExcludedTargets: [],
            admittedVectorPassTargets: [], generation: 41
        )
        let standaloneProjection = SceneScriptVectorProgram.project(
            descriptor: descriptor,
            scriptBindings: [standaloneBinding(layerID: 10, index: 0)]
        )
        let standaloneCandidate = try SceneScriptQuickJSProgramCandidate.compile(
            authoredDescriptor: descriptor,
            runtimeDescriptor: descriptor,
            scriptBindings: [standaloneBinding(layerID: 10, index: 0)],
            vectorProjection: standaloneProjection,
            userPropertyDefinitions: [], timelineTargets: [],
            scalarExcludedTargets: [], stringExcludedTargets: [],
            admittedVectorPassTargets: [], generation: 42
        )
        let frame = SceneScriptFrameInput(
            timing: .init(
                wallDate: Date(timeIntervalSince1970: 0),
                simulationFrameTime: 1.0 / 60.0, sceneTime: 2
            ),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        let firstAudio = audio(left: 0.25, right: 0.5, generation: 1)
        let first = candidate.cursorProgram.dispatch(
            batch: batch(down: true), frame: frame,
            userPropertiesJSON: "{}", audioSpectrum: firstAudio
        )
        let secondAudio = audio(left: 0.75, right: 0.8, generation: 2)
        let second = candidate.cursorProgram.dispatch(
            batch: batch(down: false), frame: frame,
            userPropertiesJSON: "{}", audioSpectrum: secondAudio
        )
        let borrowedTarget = SceneDynamicTarget.layer(
            layerID: 20, field: .origin
        )
        let sameGenerationDifferentPayload = audio(
            left: 0.05, right: 0.1, generation: 2
        )
        let borrowedFrame = candidate.vectorProgram.evaluate(
            inputs: [borrowedTarget: .vector3(1, 1, 1)],
            effectivePropertyValues: [:], frame: frame,
            audioSpectrum: sameGenerationDifferentPayload
        )
        let borrowedFrameXYZ: [Double]
        if case let .vector3(x, y, z)? = borrowedFrame.values[borrowedTarget] {
            borrowedFrameXYZ = [x, y, z]
        } else {
            borrowedFrameXYZ = [-1, -1, -1]
        }
        let firstByLayer = Dictionary(uniqueKeysWithValues:
            first.layerMutations.map { ($0.layerID, $0.origin) }
        )
        let secondByLayer = Dictionary(uniqueKeysWithValues:
            second.layerMutations.map { ($0.layerID, $0.origin) }
        )
        let payload: [String: Any] = [
            "cursorOwners": candidate.cursorProgram.ownerCount,
            "cursorOwnerIDs": candidate.cursorProgram.ownerLayerIDs.sorted(),
            "cursorConstructionComplete":
                candidate.constructionReport.isComplete,
            "cursorFailures":
                candidate.constructionReport.cursorFailures.keys
                    .map { String(describing: $0) }.sorted(),
            "borrowedRegistrationIDs": candidate.vectorProgram
                .cursorOwnerRegistrations.map(\.layerID).sorted(),
            "cursorHasAudio": candidate.cursorProgram.hasAudioConsumers,
            "vectorHasAudio": candidate.vectorProgram.hasAudioConsumers,
            "standaloneCursorHasAudio":
                standaloneCandidate.cursorProgram.hasAudioConsumers,
            "standaloneVectorHasAudio":
                standaloneCandidate.vectorProgram.hasAudioConsumers,
            "firstFailures": first.failures.count,
            "firstStandaloneX": firstByLayer[10]?.x ?? -1,
            "firstBorrowedX": firstByLayer[20]?.x ?? -1,
            "firstBorrowedY": firstByLayer[20]?.y ?? -1,
            "secondFailures": second.failures.count,
            "secondStandaloneX": secondByLayer[10]?.x ?? -1,
            "secondBorrowedX": secondByLayer[20]?.x ?? -1,
            "borrowedFrameFailures": borrowedFrame.failures.count,
            "borrowedFramePublished": borrowedFrame.values[borrowedTarget] != nil,
            "borrowedFrameXYZ": borrowedFrameXYZ,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload, options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }

    static func audio(
        left: Float, right: Float, generation: UInt64
    ) -> SceneAudioSpectrumSnapshot {
        SceneAudioSpectrumSnapshot(
            left: [left] + Array(repeating: 0, count: 15),
            right: [right] + Array(repeating: 0, count: 15),
            generation: generation
        )
    }

    static func batch(down: Bool) -> SceneScriptCursorFrameBatch {
        let hits = Dictionary(uniqueKeysWithValues: [10, 20].map { id in
            (id, SceneScriptCursorHit(
                layerID: id, worldPosition: .zero, localPosition: .zero
            ))
        })
        return .init(samples: [.init(
            hits: hits, pointerPosition: .zero,
            primaryButtonIsDown: down
        )], overflowed: false)
    }

    static func layer(id: Int, index: Int) -> SceneRenderDescriptor.Layer {
        .init(
            id: id, layerIndex: index, name: "owner-\(id)", visible: true,
            originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1],
            scaleHasScript: false, alpha: 1, effects: [],
            contentKind: id == 20 ? "image" : "composition",
            sizeWH: [100, 100],
            utilityLayer: id == 20 ? nil : .init(
                kind: .composition, copyBackground: false, passthrough: false
            )
        )
    }

    static func standaloneBinding(
        layerID: Int, index: Int
    ) -> SceneScriptBindingIR {
        .init(
            source: standaloneSource,
            owner: owner(layerID: layerID, index: index),
            targetPath: [.key("objects"), .index(index), .key("visible")],
            properties: [:], authoredValue: .bool(true), valueType: .boolean,
            wrapperKeys: ["script", "value"]
        )
    }

    static func borrowedBinding(
        layerID: Int, index: Int
    ) -> SceneScriptBindingIR {
        .init(
            source: borrowedSource,
            owner: owner(layerID: layerID, index: index),
            targetPath: [.key("objects"), .index(index), .key("origin")],
            properties: [:], authoredValue: .string("0 0 0"),
            valueType: .string, wrapperKeys: ["script", "value"]
        )
    }

    static func siblingBinding(
        layerID: Int, index: Int
    ) -> SceneScriptBindingIR {
        .init(
            source: siblingSource,
            owner: owner(layerID: layerID, index: index),
            targetPath: [.key("objects"), .index(index), .key("visible")],
            properties: [:], authoredValue: .bool(true),
            valueType: .boolean, wrapperKeys: ["script", "value"]
        )
    }

    static func owner(
        layerID: Int, index: Int
    ) -> SceneScriptBindingOwner {
        .init(
            kind: .object, objectIndex: index, objectID: layerID,
            effectIndex: nil, effectID: nil, passIndex: nil, passID: nil
        )
    }

    static let standaloneSource = """
    const audio = engine.registerAudioBuffers(16);
    export function cursorDown() {
        thisLayer.origin = new Vec3(audio.left[0], audio.right[0], 0);
    }
    export function cursorUp() {
        thisLayer.origin = new Vec3(audio.left[0], audio.right[0], 0);
    }
    """

    static let borrowedSource = """
    const audio = engine.registerAudioBuffers(16);
    export function update(value) {
        return new Vec3(audio.left[0], audio.right[0], value.z);
    }
    export function cursorDown() {
        thisLayer.origin = new Vec3(audio.left[0], audio.right[0], 0);
    }
    export function cursorUp() {
        thisLayer.origin = new Vec3(audio.left[0], audio.right[0], 0);
    }
    """

    static let siblingSource = """
    export function update(value) { return value; }
    export function mediaPlaybackChanged() { shared.media = true; }
    """
}
'''


DEMAND_HARNESS = r'''
import Foundation

struct FixtureProgram { let hasAudioConsumers: Bool }
struct FixtureSoundProgram { let bindings: [Int] }
struct SceneResolvedMaterialExecutionCapabilityCatalog {
    let hasAudioSpectrumConsumer: Bool
}
struct SceneDesktopWallpaperLaunchContext {
    let resolvedMaterialExecutionCapabilities:
        SceneResolvedMaterialExecutionCapabilityCatalog
    let propertyVectorScriptProgram: FixtureProgram
    let sceneScriptScalarProgram: FixtureProgram
    let sceneScriptStringProgram: FixtureProgram
    let sceneScriptCursorProgram: FixtureProgram
    let soundPlaybackProgram: FixtureSoundProgram
}
final class SceneAudioSpectrumInbox {
    static let shared = SceneAudioSpectrumInbox()
    private(set) var demand = false
    private(set) var includesCurrentProcess = false
    func setDemand(
        _ active: Bool, requiresCurrentProcessAudioCapture: Bool = false
    ) {
        demand = active
        includesCurrentProcess = active && requiresCurrentProcessAudioCapture
    }
}
final class SceneDesktopWallpaperHost {}

@main
enum Harness {
    static func main() {
        let context = SceneDesktopWallpaperLaunchContext(
            resolvedMaterialExecutionCapabilities: .init(
                hasAudioSpectrumConsumer: false
            ),
            propertyVectorScriptProgram: .init(hasAudioConsumers: false),
            sceneScriptScalarProgram: .init(hasAudioConsumers: false),
            sceneScriptStringProgram: .init(hasAudioConsumers: false),
            sceneScriptCursorProgram: .init(hasAudioConsumers: true),
            soundPlaybackProgram: .init(bindings: [1])
        )
        SceneDesktopWallpaperHost().updateAudioSpectrumDemand(
            context, hasParticleAudioConsumer: false
        )
        let payload: [String: Any] = [
            "demand": SceneAudioSpectrumInbox.shared.demand,
            "includesCurrentProcess":
                SceneAudioSpectrumInbox.shared.includesCurrentProcess,
        ]
        let data = try! JSONSerialization.data(
            withJSONObject: payload, options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneCursorAudioConsumerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temp_dir = tempfile.TemporaryDirectory(
            prefix="mwx-cursor-audio-consumer-"
        )
        temporary = Path(cls.temp_dir.name)
        cls.cursor_binary = compile_vector_harness(
            temporary_directory=temporary,
            harness_source=CURSOR_HARNESS,
            binary_name="scene-cursor-audio-consumer",
        )
        cls.cursor_result = json.loads(subprocess.run(
            [str(cls.cursor_binary)], check=True, capture_output=True, text=True
        ).stdout)
        demand_harness = temporary / "DemandHarness.swift"
        demand_harness.write_text(DEMAND_HARNESS, encoding="utf-8")
        cls.demand_binary = temporary / "scene-cursor-audio-demand"
        compilation = subprocess.run(
            [
                "xcrun", "swiftc", "-parse-as-library",
                str(DEMAND_SOURCE), str(demand_harness),
                "-o", str(cls.demand_binary),
            ],
            capture_output=True, text=True,
        )
        if compilation.returncode != 0:
            raise AssertionError(compilation.stdout + compilation.stderr)
        cls.demand_result = json.loads(subprocess.run(
            [str(cls.demand_binary)], check=True,
            capture_output=True, text=True,
        ).stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temp_dir.cleanup()

    def test_cursor_only_owner_participates_in_shared_demand(self) -> None:
        self.assertTrue(self.cursor_result["standaloneCursorHasAudio"])
        self.assertFalse(self.cursor_result["standaloneVectorHasAudio"])
        self.assertTrue(self.demand_result["demand"])
        self.assertTrue(self.demand_result["includesCurrentProcess"])

    def test_standalone_and_borrowed_callbacks_read_current_snapshot(self) -> None:
        self.assertEqual(self.cursor_result["cursorOwners"], 2)
        self.assertTrue(self.cursor_result["cursorConstructionComplete"])
        self.assertTrue(self.cursor_result["cursorHasAudio"])
        self.assertTrue(self.cursor_result["vectorHasAudio"])
        self.assertEqual(self.cursor_result["firstFailures"], 0)
        self.assertAlmostEqual(self.cursor_result["firstStandaloneX"], 0.25)
        self.assertAlmostEqual(self.cursor_result["firstBorrowedX"], 0.25)
        self.assertAlmostEqual(self.cursor_result["firstBorrowedY"], 0.5)
        self.assertEqual(self.cursor_result["secondFailures"], 0)
        self.assertAlmostEqual(self.cursor_result["secondStandaloneX"], 0.75)
        self.assertAlmostEqual(self.cursor_result["secondBorrowedX"], 0.75)

    def test_borrowed_owner_reuses_generation_in_later_vector_pass(self) -> None:
        self.assertEqual(self.cursor_result["borrowedFrameFailures"], 0)
        self.assertTrue(self.cursor_result["borrowedFramePublished"])
        self.assertAlmostEqual(self.cursor_result["borrowedFrameXYZ"][0], 0.75)
        self.assertAlmostEqual(self.cursor_result["borrowedFrameXYZ"][1], 0.8)
        self.assertEqual(self.cursor_result["borrowedFrameXYZ"][2], 1)


if __name__ == "__main__":
    unittest.main()
