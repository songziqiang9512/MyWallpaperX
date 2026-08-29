#!/usr/bin/env python3

"""Cursor candidate collisions must retain a typed layer identity."""

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


HARNESS = r'''
@main
enum Harness {
    static func main() throws {
        let descriptor = SceneRenderDescriptor(layers: [
            layer(id: 10, index: 0, name: "standalone-borrowed"),
            layer(id: 20, index: 1, name: "borrowed-borrowed"),
            layer(id: 30, index: 2, name: "standalone-only"),
            layer(id: 40, index: 3, name: "borrowed-only"),
        ])
        let bindings = [
            standaloneBinding(layerID: 10, index: 0),
            vectorBinding(layerID: 10, index: 0, field: "origin"),
            vectorBinding(layerID: 20, index: 1, field: "origin"),
            vectorBinding(layerID: 20, index: 1, field: "scale"),
            standaloneBinding(layerID: 30, index: 2),
            vectorBinding(layerID: 40, index: 3, field: "origin"),
        ]
        let projection = SceneScriptVectorProgram.project(
            descriptor: descriptor,
            scriptBindings: bindings
        )
        let candidate = try SceneScriptQuickJSProgramCandidate.compile(
            authoredDescriptor: descriptor,
            runtimeDescriptor: descriptor,
            scriptBindings: bindings,
            vectorProjection: projection,
            userPropertyDefinitions: [],
            timelineTargets: [],
            scalarExcludedTargets: [],
            stringExcludedTargets: [],
            admittedVectorPassTargets: [],
            generation: 41
        )
        let report = candidate.constructionReport
        let frame = SceneScriptFrameInput(
            timing: .init(
                wallDate: Date(timeIntervalSince1970: 0),
                simulationFrameTime: 1.0 / 60.0,
                sceneTime: 2
            ),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        let cursorResult = candidate.cursorProgram.dispatch(
            batch: .init(samples: [.init(
                hits: [
                    30: hit(layerID: 30),
                    40: hit(layerID: 40),
                ],
                pointerPosition: .init(0.5, 0.5),
                primaryButtonIsDown: false
            )], overflowed: false),
            frame: frame,
            userPropertiesJSON: "{}"
        )
        let payload: [String: Any] = [
            "domainCommitted": candidate.domain != nil,
            "complete": report.isComplete,
            "vectorInstantiated": report.instantiatedVectorTargets.count,
            "cursorExpected": report.expectedCursorLayerIDs.sorted(),
            "cursorInstantiated": report.instantiatedCursorLayerIDs.sorted(),
            "cursorFailures": report.cursorFailures.keys.sorted(),
            "standaloneBorrowedCode": report.cursorFailures[10]?.code ?? "",
            "standaloneBorrowedMessage": failureMessage(
                report.cursorFailures[10]
            ),
            "borrowedBorrowedCode": report.cursorFailures[20]?.code ?? "",
            "borrowedBorrowedMessage": failureMessage(
                report.cursorFailures[20]
            ),
            "cursorOwners": candidate.cursorProgram.ownerLayerIDs.sorted(),
            "cursorOwnerCount": candidate.cursorProgram.ownerCount,
            "dispatchFailures": cursorResult.failures.keys.sorted(),
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }

    static func layer(
        id: Int,
        index: Int,
        name: String
    ) -> SceneRenderDescriptor.Layer {
        .init(
            id: id,
            layerIndex: index,
            name: name,
            visible: true,
            originXYZ: [0, 0, 0],
            scaleXYZ: [1, 1, 1],
            scaleHasScript: false,
            alpha: 1,
            effects: [],
            contentKind: "composition",
            sizeWH: [100, 100],
            utilityLayer: .init(
                kind: .composition,
                copyBackground: false,
                passthrough: false
            )
        )
    }

    static func standaloneBinding(
        layerID: Int,
        index: Int
    ) -> SceneScriptBindingIR {
        .init(
            source: standaloneSource,
            owner: .init(
                kind: .object,
                objectIndex: index,
                objectID: layerID,
                effectIndex: nil,
                effectID: nil,
                passIndex: nil,
                passID: nil
            ),
            targetPath: [
                .key("objects"), .index(index), .key("visible"),
            ],
            properties: [:],
            authoredValue: .bool(true),
            valueType: .boolean,
            wrapperKeys: ["script", "value"]
        )
    }

    static func vectorBinding(
        layerID: Int,
        index: Int,
        field: String
    ) -> SceneScriptBindingIR {
        .init(
            source: borrowedSource,
            owner: .init(
                kind: .object,
                objectIndex: index,
                objectID: layerID,
                effectIndex: nil,
                effectID: nil,
                passIndex: nil,
                passID: nil
            ),
            targetPath: [
                .key("objects"), .index(index), .key(field),
            ],
            properties: [:],
            authoredValue: .string(
                field == "scale" ? "1 1 1" : "0 0 0"
            ),
            valueType: .string,
            wrapperKeys: ["script", "value"]
        )
    }

    static func hit(layerID: Int) -> SceneScriptCursorHit {
        .init(
            layerID: layerID,
            worldPosition: .init(1, 2, 0),
            localPosition: .init(0.5, 0.5, 0)
        )
    }

    static func failureMessage(
        _ failure: SceneScriptScalarRuntimeFailure?
    ) -> String {
        guard case let .invalidArgument(message)? = failure else {
            return "wrong-failure"
        }
        return message
    }

    static let standaloneSource = """
    export function cursorEnter(event) {}
    """

    static let borrowedSource = """
    export function cursorEnter(event) {}
    export function update(value) { return value }
    """
}
'''


class SceneCursorCandidateCollisionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temp_dir = tempfile.TemporaryDirectory(
            prefix="mwx-cursor-candidate-collision-"
        )
        cls.binary = compile_vector_harness(
            temporary_directory=Path(cls.temp_dir.name),
            harness_source=HARNESS,
            binary_name="scene-cursor-candidate-collision",
        )

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temp_dir.cleanup()

    def test_cross_family_collisions_are_typed_and_disjoint_owners_survive(
        self,
    ) -> None:
        result = json.loads(subprocess.run(
            [str(self.binary)],
            check=True,
            capture_output=True,
            text=True,
        ).stdout)
        self.assertTrue(result["domainCommitted"])
        self.assertTrue(result["complete"])
        self.assertEqual(result["vectorInstantiated"], 4)
        self.assertEqual(result["cursorExpected"], [10, 20, 30])
        self.assertEqual(result["cursorInstantiated"], [30])
        self.assertEqual(result["cursorFailures"], [10, 20])
        self.assertEqual(result["standaloneBorrowedCode"], "invalid-argument")
        self.assertEqual(result["borrowedBorrowedCode"], "invalid-argument")
        self.assertEqual(
            result["standaloneBorrowedMessage"],
            "SceneScript cursor owner collision",
        )
        self.assertEqual(
            result["borrowedBorrowedMessage"],
            "SceneScript cursor owner collision",
        )
        self.assertEqual(result["cursorOwners"], [30, 40])
        self.assertEqual(result["cursorOwnerCount"], 2)
        self.assertEqual(result["dispatchFailures"], [])


if __name__ == "__main__":
    unittest.main()
