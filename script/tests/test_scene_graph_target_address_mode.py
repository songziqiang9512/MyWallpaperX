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
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    SCENE_ROOT / "RenderGraph/AuthoredGraph/SceneAuthoredEffectRenderPlan.swift",
    SCENE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetPlan.swift",
    SCENE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetPlan+Clear.swift",
    SCENE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetPlan+Extent.swift",
]


HARNESS = r'''
import Foundation

struct SceneEffectStageExecutionPlan {
    let layerID: Int
    let materialNodeCount: Int
    let logicalRenderTargetCount: Int
    let inputRole: SceneAuthoredEffectInputRole
    let supportsUnifiedFullFrameComposeStage: Bool
}

@main
enum Harness {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias Plan = SceneGraphRenderTargetPlan

    static let layerID = 41
    static let key = Graph.EffectKey(
        layerID: layerID,
        effectIndex: 0,
        descriptorID: "address-mode-fixture"
    )
    static let input = identity(.layerSource)
    static let output = identity(.effectOutput, effect: key)
    static let first = identity(.framebuffer, effect: key, name: "first")
    static let second = identity(.framebuffer, effect: key, name: "second")
    static let extent = Graph.TargetExtent(
        width: 64,
        height: 64,
        fit: nil,
        scale: nil
    )

    static func identity(
        _ kind: Graph.TextureKind,
        effect: Graph.EffectKey? = nil,
        name: String? = nil
    ) -> Graph.TextureIdentity {
        .init(kind: kind, layerID: layerID, effect: effect, name: name)
    }

    static func target(
        _ identity: Graph.TextureIdentity,
        uvs: SceneJSONValue?
    ) -> Graph.RenderTarget {
        .init(
            texture: identity,
            extent: extent,
            format: "rgba8888",
            declaredUnique: false,
            clear: nil,
            uvs: uvs,
            conditions: nil
        )
    }

    static func binding(
        _ identity: Graph.TextureIdentity,
        slot: Int = 0
    ) -> Graph.Binding {
        .init(
            slot: slot,
            authoredName: identity.name ?? "previous",
            texture: identity,
            conditions: nil
        )
    }

    static func material(
        _ nodeIndex: Int,
        ordinal: Int,
        target: Graph.TextureIdentity,
        read: Graph.TextureIdentity
    ) -> Graph.Node {
        .init(
            nodeIndex: nodeIndex,
            effect: key,
            definitionPassIndex: nodeIndex,
            materialOrdinal: ordinal,
            instancePassIndex: ordinal,
            kind: .material,
            materialPath: "materials/shared.json",
            materialPassID: "materials/shared.json#0",
            target: target,
            bindings: [binding(read)],
            commandSource: nil,
            commandTarget: nil,
            compose: nil,
            conditions: nil
        )
    }

    static func command(
        _ nodeIndex: Int,
        kind: Graph.NodeKind,
        source: Graph.TextureIdentity,
        target: Graph.TextureIdentity
    ) -> Graph.Node {
        .init(
            nodeIndex: nodeIndex,
            effect: key,
            definitionPassIndex: nodeIndex,
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
        nodes: [Graph.Node]
    ) -> Graph {
        .init(
            layerID: layerID,
            effects: [.init(
                key: key,
                definitionPath: "effects/shared/effect.json",
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

    static func plan(
        _ graph: Graph,
        materialNodeCount: Int
    ) -> Result<Plan, Plan.Failure> {
        Plan.make(
            executionPlan: .init(
                layerID: layerID,
                materialNodeCount: materialNodeCount,
                logicalRenderTargetCount: graph.renderTargets.count,
                inputRole: .layerSource,
                supportsUnifiedFullFrameComposeStage: false
            ),
            graph: graph,
            inputWidth: 64,
            inputHeight: 64
        )
    }

    static func requirePlan(
        _ graph: Graph,
        materialNodeCount: Int
    ) -> Plan {
        guard case .success(let value) = plan(
            graph,
            materialNodeCount: materialNodeCount
        ) else {
            fatalError("expected address-mode plan")
        }
        return value
    }

    static func failure(
        _ graph: Graph,
        materialNodeCount: Int
    ) -> String {
        switch plan(graph, materialNodeCount: materialNodeCount) {
        case .success: return "success"
        case .failure(let failure): return failure.rawValue
        }
    }

    static func singleTargetGraph(_ uvs: SceneJSONValue?) -> Graph {
        graph(
            targets: [target(first, uvs: uvs)],
            nodes: [
                material(0, ordinal: 0, target: first, read: input),
                material(1, ordinal: 1, target: output, read: first),
            ]
        )
    }

    static func copyGraph() -> Graph {
        graph(
            targets: [
                target(first, uvs: nil),
                target(second, uvs: .string("repeat")),
            ],
            nodes: [
                material(0, ordinal: 0, target: first, read: input),
                command(1, kind: .copy, source: first, target: second),
                material(2, ordinal: 1, target: output, read: second),
            ]
        )
    }

    static func swapGraph(
        firstUVs: SceneJSONValue?,
        secondUVs: SceneJSONValue?
    ) -> Graph {
        graph(
            targets: [
                target(first, uvs: firstUVs),
                target(second, uvs: secondUVs),
            ],
            nodes: [
                material(0, ordinal: 0, target: first, read: input),
                material(1, ordinal: 1, target: second, read: input),
                command(2, kind: .swap, source: first, target: second),
                material(3, ordinal: 2, target: output, read: first),
            ]
        )
    }

    static func main() throws {
        let clampPlan = requirePlan(singleTargetGraph(nil), materialNodeCount: 2)
        let repeatPlan = requirePlan(
            singleTargetGraph(.string("repeat")),
            materialNodeCount: 2
        )
        let crossAddressCopy = requirePlan(copyGraph(), materialNodeCount: 2)
        let sameAddressSwap = requirePlan(
            swapGraph(
                firstUVs: .string("repeat"),
                secondUVs: .string("repeat")
            ),
            materialNodeCount: 3
        )
        let unsupported: [SceneJSONValue] = [
            .string("mirror"),
            .string("Repeat"),
            .bool(true),
            .number(1),
            .array([]),
        ]
        let result: [String: Any] = [
            "nilAddressMode": clampPlan.logicalTargets[0].addressMode.rawValue,
            "repeatAddressMode": repeatPlan.logicalTargets[0].addressMode.rawValue,
            "unsupportedFailures": unsupported.map {
                failure(singleTargetGraph($0), materialNodeCount: 2)
            },
            "copyCommands": crossAddressCopy.commands.map(\.kind.rawValue),
            "copyAddressModes": crossAddressCopy.logicalTargets.map {
                $0.addressMode.rawValue
            },
            "sameAddressSwapCommands": sameAddressSwap.commands.map(\.kind.rawValue),
            "differentAddressSwapFailure": failure(
                swapGraph(firstUVs: nil, secondUVs: .string("repeat")),
                materialNodeCount: 3
            ),
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneGraphTargetAddressModeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory()
        temporary_root = Path(cls.temporary_directory.name)
        harness_path = temporary_root / "main.swift"
        binary_path = temporary_root / "scene-graph-target-address-mode"
        harness_path.write_text(HARNESS, encoding="utf-8")
        compile_result = subprocess.run(
            [
                swiftc,
                "-parse-as-library",
                "-D",
                "SCENE_GRAPH_TESTING",
                *map(str, SWIFT_SOURCES),
                str(harness_path),
                "-o",
                str(binary_path),
            ],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
        )
        if compile_result.returncode != 0:
            raise AssertionError(compile_result.stderr)
        completed = subprocess.run(
            [str(binary_path)],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_nil_and_exact_repeat_normalize_to_typed_address_modes(self) -> None:
        self.assertEqual(self.result["nilAddressMode"], "clampToEdge")
        self.assertEqual(self.result["repeatAddressMode"], "repeatWrap")

    def test_unknown_and_non_string_values_fail_closed(self) -> None:
        self.assertEqual(
            self.result["unsupportedFailures"],
            ["unsupportedTargetDescriptor"] * 5,
        )

    def test_copy_requires_storage_compatibility_not_address_identity(self) -> None:
        self.assertEqual(self.result["copyCommands"], ["copy"])
        self.assertEqual(
            self.result["copyAddressModes"],
            ["clampToEdge", "repeatWrap"],
        )

    def test_swap_requires_matching_address_identity(self) -> None:
        self.assertEqual(self.result["sameAddressSwapCommands"], ["swap"])
        self.assertEqual(
            self.result["differentAddressSwapFailure"],
            "unsupportedTargetDescriptor",
        )


if __name__ == "__main__":
    unittest.main()
