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
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectRenderPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneGraphRenderTargetPlan.swift",
]


HARNESS = r'''
import Foundation

struct SceneAuthoredEffectExecutionPlan {
    let layerID: Int
    let materialNodeCount: Int
    let logicalRenderTargetCount: Int
    let inputRole: SceneAuthoredEffectInputRole

    init(
        layerID: Int,
        materialNodeCount: Int,
        logicalRenderTargetCount: Int,
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) {
        self.layerID = layerID
        self.materialNodeCount = materialNodeCount
        self.logicalRenderTargetCount = logicalRenderTargetCount
        self.inputRole = inputRole
    }
}

@main
enum Harness {
    typealias Graph = SceneAuthoredEffectRenderPlan

    static func texture(
        _ kind: Graph.TextureKind,
        key: Graph.EffectKey? = nil,
        name: String? = nil
    ) -> Graph.TextureIdentity {
        .init(kind: kind, layerID: 10, effect: key, name: name)
    }

    static func target(
        _ identity: Graph.TextureIdentity,
        extent: Graph.TargetExtent,
        format: String = "rgba_backbuffer",
        unique: Bool = false
    ) -> Graph.RenderTarget {
        .init(
            texture: identity,
            extent: extent,
            format: format,
            declaredUnique: unique,
            clear: nil,
            uvs: nil,
            conditions: nil
        )
    }

    static func binding(_ identity: Graph.TextureIdentity, slot: Int) -> Graph.Binding {
        .init(slot: slot, authoredName: identity.name ?? "previous", texture: identity, conditions: nil)
    }

    static func node(
        _ index: Int,
        key: Graph.EffectKey,
        target: Graph.TextureIdentity,
        reads: [Graph.TextureIdentity]
    ) -> Graph.Node {
        .init(
            nodeIndex: index,
            effect: key,
            definitionPassIndex: index,
            materialOrdinal: index,
            instancePassIndex: index,
            kind: .material,
            materialPath: "materials/\(index).json",
            materialPassID: "materials/\(index).json#0",
            target: target,
            bindings: reads.enumerated().map { binding($0.element, slot: $0.offset) },
            commandSource: nil,
            commandTarget: nil,
            compose: nil,
            conditions: nil
        )
    }

    static func commandNode(
        _ index: Int,
        kind: Graph.NodeKind,
        key: Graph.EffectKey,
        source: Graph.TextureIdentity,
        target: Graph.TextureIdentity
    ) -> Graph.Node {
        .init(
            nodeIndex: index,
            effect: key,
            definitionPassIndex: index,
            materialOrdinal: nil,
            instancePassIndex: nil,
            kind: kind,
            materialPath: nil,
            materialPassID: nil,
            target: nil,
            bindings: [],
            commandSource: source,
            commandTarget: target,
            compose: nil,
            conditions: nil
        )
    }

    static func graph(
        targets: [Graph.RenderTarget],
        nodes: [Graph.Node],
        key: Graph.EffectKey,
        input: Graph.TextureIdentity,
        output: Graph.TextureIdentity
    ) -> Graph {
        .init(
            layerID: 10,
            effects: [.init(
                key: key,
                definitionPath: "effects/test/effect.json",
                input: input,
                output: output,
                nodeIndices: nodes.map(\.nodeIndex)
            )],
            renderTargets: targets,
            nodes: nodes,
            finalOutput: output,
            blockers: []
        )
    }

    static func failure(
        _ graph: Graph,
        materialNodeCount: Int? = nil,
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> String {
        let result = SceneGraphRenderTargetPlan.make(
            executionPlan: .init(
                layerID: graph.layerID,
                materialNodeCount: materialNodeCount ?? graph.nodes.count,
                logicalRenderTargetCount: graph.renderTargets.count,
                inputRole: inputRole
            ),
            graph: graph,
            inputWidth: 1920,
            inputHeight: 1080
        )
        switch result {
        case .success:
            return "success"
        case .failure(let reason):
            return reason.rawValue
        }
    }

    static func targetSummary(_ plan: SceneGraphRenderTargetPlan) -> [[String: Any]] {
        plan.logicalTargets.map { target in
            [
                "name": target.identity.name ?? "",
                "size": [target.extent.width, target.extent.height],
                "format": target.format.rawValue,
                "firstWrite": target.lifetime.firstWriteNodeIndex,
                "lastWrite": target.lifetime.lastWriteNodeIndex,
                "firstRead": target.lifetime.firstReadNodeIndex ?? -1,
                "lastRead": target.lifetime.lastReadNodeIndex ?? -1,
                "persistent": target.lifetime.requiresHistorySeed,
                "historySeed": target.lifetime.requiresHistorySeed,
            ]
        }
    }

    static func main() throws {
        let key = Graph.EffectKey(layerID: 10, effectIndex: 0, descriptorID: "10#effect#1")
        let input = texture(.layerSource)
        let output = texture(.effectOutput, key: key)
        let q1 = texture(.framebuffer, key: key, name: "q1")
        let q2 = texture(.framebuffer, key: key, name: "q2")
        let scaleFour = Graph.TargetExtent(kind: .scale, first: 4, second: nil)
        let inputExtent = Graph.TargetExtent(kind: .input, first: nil, second: nil)

        let standard = graph(
            targets: [target(q1, extent: scaleFour), target(q2, extent: scaleFour)],
            nodes: [
                node(0, key: key, target: q1, reads: [input]),
                node(1, key: key, target: q2, reads: [q1]),
                node(2, key: key, target: q1, reads: [q2]),
                node(3, key: key, target: output, reads: [q1, input]),
            ],
            key: key,
            input: input,
            output: output
        )
        let standardResult = SceneGraphRenderTargetPlan.make(
            executionPlan: .init(layerID: 10, materialNodeCount: 4, logicalRenderTargetCount: 2),
            graph: standard,
            inputWidth: 1920,
            inputHeight: 1080
        )
        guard case .success(let standardPlan) = standardResult else {
            fatalError("standard fixture rejected")
        }
        let rgba8888 = graph(
            targets: [
                target(q1, extent: scaleFour, format: "rgba8888"),
                target(q2, extent: scaleFour, format: "rgba8888"),
            ],
            nodes: standard.nodes,
            key: key,
            input: input,
            output: output
        )
        let rgba8888Result = SceneGraphRenderTargetPlan.make(
            executionPlan: .init(layerID: 10, materialNodeCount: 4, logicalRenderTargetCount: 2),
            graph: rgba8888,
            inputWidth: 1920,
            inputHeight: 1080
        )
        guard case .success(let rgba8888Plan) = rgba8888Result else {
            fatalError("rgba8888 fixture rejected")
        }

        let full = texture(.framebuffer, key: key, name: "full")
        let precise = graph(
            targets: [target(full, extent: inputExtent)],
            nodes: [
                node(0, key: key, target: full, reads: []),
                node(1, key: key, target: output, reads: [full, input]),
            ],
            key: key,
            input: input,
            output: output
        )
        let preciseResult = SceneGraphRenderTargetPlan.make(
            executionPlan: .init(layerID: 10, materialNodeCount: 2, logicalRenderTargetCount: 1),
            graph: precise,
            inputWidth: 1279,
            inputHeight: 719
        )
        guard case .success(let precisePlan) = preciseResult else {
            fatalError("precise fixture rejected")
        }
        let commands = graph(
            targets: [target(q1, extent: inputExtent), target(q2, extent: inputExtent)],
            nodes: [
                node(0, key: key, target: q1, reads: [input]),
                node(1, key: key, target: q2, reads: [input]),
                commandNode(2, kind: .copy, key: key, source: q1, target: q2),
                commandNode(3, kind: .swap, key: key, source: q1, target: q2),
                node(4, key: key, target: output, reads: [q1]),
            ],
            key: key,
            input: input,
            output: output
        )
        let commandsResult = SceneGraphRenderTargetPlan.make(
            executionPlan: .init(
                layerID: 10,
                materialNodeCount: 3,
                logicalRenderTargetCount: 2
            ),
            graph: commands,
            inputWidth: 1920,
            inputHeight: 1080
        )
        guard case .success(let commandsPlan) = commandsResult else {
            fatalError("command fixture rejected")
        }
        let incompatibleCommands = graph(
            targets: [target(q1, extent: inputExtent), target(q2, extent: scaleFour)],
            nodes: commands.nodes,
            key: key,
            input: input,
            output: output
        )
        let commandBeforeWrite = graph(
            targets: [target(q1, extent: inputExtent), target(q2, extent: inputExtent)],
            nodes: [
                commandNode(0, kind: .copy, key: key, source: q1, target: q2),
                node(1, key: key, target: q1, reads: [input]),
                node(2, key: key, target: output, reads: [q1]),
            ],
            key: key,
            input: input,
            output: output
        )

        let history = graph(
            targets: [target(q1, extent: scaleFour), target(q2, extent: scaleFour)],
            nodes: [
                node(0, key: key, target: q1, reads: [q2]),
                node(1, key: key, target: q2, reads: [q1]),
                node(2, key: key, target: output, reads: [q2, input]),
            ],
            key: key,
            input: input,
            output: output
        )
        let persistentHistory = graph(
            targets: [
                target(q1, extent: scaleFour, unique: true),
                target(q2, extent: scaleFour, unique: true),
            ],
            nodes: history.nodes,
            key: key,
            input: input,
            output: output
        )
        let persistentHistoryResult = SceneGraphRenderTargetPlan.make(
            executionPlan: .init(
                layerID: 10,
                materialNodeCount: 3,
                logicalRenderTargetCount: 2
            ),
            graph: persistentHistory,
            inputWidth: 1920,
            inputHeight: 1080
        )
        guard case .success(let persistentHistoryPlan) = persistentHistoryResult else {
            fatalError("persistent history fixture rejected")
        }
        let duplicate = graph(
            targets: [target(q1, extent: scaleFour), target(q1, extent: scaleFour)],
            nodes: standard.nodes,
            key: key,
            input: input,
            output: output
        )
        let incompleteIdentity = texture(.framebuffer, name: "orphan")
        let incomplete = graph(
            targets: [target(incompleteIdentity, extent: inputExtent)],
            nodes: [
                node(0, key: key, target: incompleteIdentity, reads: []),
                node(1, key: key, target: output, reads: [incompleteIdentity, input]),
            ],
            key: key,
            input: input,
            output: output
        )
        let unique = graph(
            targets: [target(full, extent: inputExtent, unique: true)],
            nodes: precise.nodes,
            key: key,
            input: input,
            output: output
        )
        let unsupportedFormat = graph(
            targets: [target(full, extent: inputExtent, format: "r8")],
            nodes: precise.nodes,
            key: key,
            input: input,
            output: output
        )
        let priorKey = Graph.EffectKey(
            layerID: 10,
            effectIndex: 0,
            descriptorID: "10#effect#0"
        )
        let priorOutput = texture(.effectOutput, key: priorKey)
        let roleMismatch = graph(
            targets: standard.renderTargets,
            nodes: standard.nodes,
            key: key,
            input: priorOutput,
            output: output
        )

        let result: [String: Any] = [
            "standardInput": standardPlan.input.kind.rawValue,
            "standardOutput": standardPlan.output.kind.rawValue,
            "standardInputExtent": [
                standardPlan.inputExtent.width, standardPlan.inputExtent.height,
            ],
            "standardTargets": targetSummary(standardPlan),
            "rgba8888Targets": targetSummary(rgba8888Plan),
            "preciseInputExtent": [
                precisePlan.inputExtent.width, precisePlan.inputExtent.height,
            ],
            "preciseTargets": targetSummary(precisePlan),
            "commandTargets": targetSummary(commandsPlan),
            "persistentHistoryTargets": targetSummary(persistentHistoryPlan),
            "commands": commandsPlan.commands.map {
                [
                    "node": $0.nodeIndex,
                    "kind": $0.kind.rawValue,
                    "source": $0.source.name ?? "",
                    "target": $0.target.name ?? "",
                ]
            },
            "incompatibleCommandFailure": failure(
                incompatibleCommands, materialNodeCount: 3
            ),
            "commandBeforeWriteFailure": failure(
                commandBeforeWrite, materialNodeCount: 2
            ),
            "historyFailure": failure(history),
            "duplicateFailure": failure(duplicate),
            "incompleteFailure": failure(incomplete),
            "uniqueFailure": failure(unique),
            "unsupportedFormatFailure": failure(unsupportedFormat),
            "countMismatchFailure": failure(standard, materialNodeCount: 3),
            "roleMismatchFailure": failure(roleMismatch),
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneGraphRenderTargetPlanTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-rt-plan-")
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = root / "scene-rt-plan"
        subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-o",
                str(cls.binary),
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

    def test_standard_blur_targets_preserve_extent_and_lifetime(self) -> None:
        self.assertEqual(self.result["standardInput"], "layerSource")
        self.assertEqual(self.result["standardOutput"], "effectOutput")
        self.assertEqual(self.result["standardInputExtent"], [1920, 1080])
        self.assertEqual(
            self.result["standardTargets"],
            [
                {
                    "name": "q1",
                    "size": [480, 270],
                    "format": "rgbaBackbuffer",
                    "firstWrite": 0,
                    "lastWrite": 2,
                    "firstRead": 1,
                    "lastRead": 3,
                    "persistent": False,
                    "historySeed": False,
                },
                {
                    "name": "q2",
                    "size": [480, 270],
                    "format": "rgbaBackbuffer",
                    "firstWrite": 1,
                    "lastWrite": 1,
                    "firstRead": 2,
                    "lastRead": 2,
                    "persistent": False,
                    "historySeed": False,
                },
            ],
        )

    def test_precise_blur_target_uses_exact_input_extent(self) -> None:
        self.assertEqual(self.result["preciseInputExtent"], [1279, 719])
        self.assertEqual(
            self.result["preciseTargets"],
            [
                {
                    "name": "full",
                    "size": [1279, 719],
                    "format": "rgbaBackbuffer",
                    "firstWrite": 0,
                    "lastWrite": 0,
                    "firstRead": 1,
                    "lastRead": 1,
                    "persistent": False,
                    "historySeed": False,
                }
            ],
        )

    def test_rgba8888_targets_preserve_authored_format(self) -> None:
        self.assertEqual(
            [target["format"] for target in self.result["rgba8888Targets"]],
            ["rgba8888", "rgba8888"],
        )

    def test_read_before_first_write_requires_history(self) -> None:
        self.assertEqual(self.result["historyFailure"], "historyRequired")
        self.assertEqual(self.result["commandBeforeWriteFailure"], "historyRequired")

    def test_unique_read_before_write_is_a_seeded_persistent_target(self) -> None:
        self.assertEqual(
            self.result["persistentHistoryTargets"],
            [
                {
                    "name": "q1",
                    "size": [480, 270],
                    "format": "rgbaBackbuffer",
                    "firstWrite": 0,
                    "lastWrite": 0,
                    "firstRead": 1,
                    "lastRead": 1,
                    "persistent": False,
                    "historySeed": False,
                },
                {
                    "name": "q2",
                    "size": [480, 270],
                    "format": "rgbaBackbuffer",
                    "firstWrite": 1,
                    "lastWrite": 1,
                    "firstRead": 0,
                    "lastRead": 2,
                    "persistent": True,
                    "historySeed": True,
                },
            ],
        )

    def test_copy_and_swap_extend_target_lifetimes_in_authored_order(self) -> None:
        self.assertEqual(
            self.result["commands"],
            [
                {"node": 2, "kind": "copy", "source": "q1", "target": "q2"},
                {"node": 3, "kind": "swap", "source": "q1", "target": "q2"},
            ],
        )
        self.assertEqual(
            self.result["commandTargets"],
            [
                {
                    "name": "q1",
                    "size": [1920, 1080],
                    "format": "rgbaBackbuffer",
                    "firstWrite": 0,
                    "lastWrite": 3,
                    "firstRead": 2,
                    "lastRead": 4,
                    "persistent": False,
                    "historySeed": False,
                },
                {
                    "name": "q2",
                    "size": [1920, 1080],
                    "format": "rgbaBackbuffer",
                    "firstWrite": 1,
                    "lastWrite": 3,
                    "firstRead": 3,
                    "lastRead": 3,
                    "persistent": False,
                    "historySeed": False,
                },
            ],
        )
        self.assertEqual(
            self.result["incompatibleCommandFailure"],
            "unsupportedTargetDescriptor",
        )

    def test_duplicate_and_incomplete_identities_fail_closed(self) -> None:
        self.assertEqual(self.result["duplicateFailure"], "duplicateTarget")
        self.assertEqual(self.result["incompleteFailure"], "incompleteIdentity")

    def test_unsupported_descriptor_and_execution_mismatch_fail_closed(self) -> None:
        self.assertEqual(self.result["uniqueFailure"], "success")
        self.assertEqual(
            self.result["unsupportedFormatFailure"], "unsupportedTargetDescriptor"
        )
        self.assertEqual(self.result["countMismatchFailure"], "executionMismatch")
        self.assertEqual(self.result["roleMismatchFailure"], "executionMismatch")


if __name__ == "__main__":
    unittest.main()
