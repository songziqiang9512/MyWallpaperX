#!/usr/bin/env python3
"""Isolation rebase must move every validated previous-input binding."""

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
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectStageRebase.swift",
]


HARNESS = r'''
import Foundation

enum SceneAuthoredEffectChainPlanner {
    typealias Graph = SceneAuthoredEffectRenderPlan
}

@main
enum Harness {
    typealias Graph = SceneAuthoredEffectRenderPlan

    static func graph(includePreviousBindings: Bool) -> Graph {
        let layerID = 42
        let priorKey = Graph.EffectKey(
            layerID: layerID, effectIndex: 0, descriptorID: "42#effect#0"
        )
        let effectKey = Graph.EffectKey(
            layerID: layerID, effectIndex: 1, descriptorID: "42#effect#1"
        )
        let prior = Graph.TextureIdentity(
            kind: .effectOutput, layerID: layerID, effect: priorKey, name: nil
        )
        let output = Graph.TextureIdentity(
            kind: .effectOutput, layerID: layerID, effect: effectKey, name: nil
        )
        let half = Graph.TextureIdentity(
            kind: .framebuffer, layerID: layerID,
            effect: effectKey, name: "_rt_half"
        )
        let previous = includePreviousBindings
            ? [Graph.Binding(
                slot: 0, authoredName: "previous",
                texture: prior, conditions: nil
            )]
            : []
        let nodes = [
            Graph.Node(
                nodeIndex: 0, effect: effectKey, definitionPassIndex: 0,
                materialOrdinal: 0, instancePassIndex: 0, kind: .material,
                materialPath: "materials/downsample.json",
                materialPassID: "materials/downsample.json#0",
                target: half, bindings: previous,
                commandSource: nil, commandTarget: nil,
                compose: nil, conditions: nil
            ),
            Graph.Node(
                nodeIndex: 1, effect: effectKey, definitionPassIndex: 1,
                materialOrdinal: 1, instancePassIndex: 1, kind: .material,
                materialPath: "materials/combine.json",
                materialPassID: "materials/combine.json#0",
                target: output,
                bindings: [
                    Graph.Binding(
                        slot: 0, authoredName: "_rt_half",
                        texture: half, conditions: nil
                    ),
                ] + previous.map {
                    Graph.Binding(
                        slot: 1, authoredName: $0.authoredName,
                        texture: $0.texture, conditions: nil
                    )
                },
                commandSource: nil, commandTarget: nil,
                compose: nil, conditions: nil
            ),
        ]
        return Graph(
            layerID: layerID,
            effects: [.init(
                key: effectKey,
                definitionPath: "effects/shine/effect.json",
                input: prior,
                output: output,
                nodeIndices: [0, 1]
            )],
            renderTargets: [.init(
                texture: half,
                extent: .init(kind: .scale, first: 2, second: nil),
                format: "rgba_backbuffer",
                declaredUnique: false,
                clear: nil,
                uvs: nil,
                conditions: nil
            )],
            nodes: nodes,
            finalOutput: output,
            blockers: []
        )
    }

    static func main() throws {
        let original = graph(includePreviousBindings: true)
        let rebased = SceneAuthoredEffectChainPlanner.rebaseStageToLayerSource(original)
        let layerSource = SceneAuthoredEffectInputValidator.layerSource(layerID: 42)
        let previousBindings = rebased?.nodes.flatMap(\.bindings).filter {
            $0.authoredName == "previous"
        } ?? []
        let result: [String: Any] = [
            "rebased": rebased != nil,
            "effectInputIsLayerSource": rebased?.effects.first?.input == layerSource,
            "previousBindingCount": previousBindings.count,
            "allPreviousBindingsRebased": previousBindings.allSatisfy {
                $0.texture == layerSource
            },
            "framebufferBindingPreserved":
                rebased?.nodes[1].bindings.first?.texture.kind == .framebuffer,
            "missingPreviousRejected":
                SceneAuthoredEffectChainPlanner.rebaseStageToLayerSource(
                    graph(includePreviousBindings: false)
                ) == nil,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneAuthoredEffectStageRebaseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-effect-stage-rebase-"
        )
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        cls.binary = root / "scene-effect-stage-rebase"
        harness.write_text(HARNESS, encoding="utf-8")
        compilation = subprocess.run(
            [
                "swiftc",
                *(str(source) for source in SWIFT_SOURCES),
                str(harness),
                "-o",
                str(cls.binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_all_previous_bindings_move_together(self) -> None:
        completed = subprocess.run(
            [str(self.binary)],
            check=True,
            capture_output=True,
            text=True,
        )
        self.assertEqual(
            json.loads(completed.stdout),
            {
                "allPreviousBindingsRebased": True,
                "effectInputIsLayerSource": True,
                "framebufferBindingPreserved": True,
                "missingPreviousRejected": True,
                "previousBindingCount": 2,
                "rebased": True,
            },
        )


if __name__ == "__main__":
    unittest.main()
