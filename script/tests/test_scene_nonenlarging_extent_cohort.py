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
    SOURCE_ROOT / "RenderGraph/AuthoredGraph/SceneAuthoredEffectRenderPlan.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetPlan.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetPlan+Clear.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetPlan+Extent.swift",
]


HARNESS = r'''
import Foundation

struct SceneEffectStageExecutionPlan {
    let layerID: Int
    let renderGraph: SceneAuthoredEffectRenderPlan
    let materialNodeCount: Int
    let logicalRenderTargetCount: Int
    let inputRole: SceneAuthoredEffectInputRole

}

@main
enum Harness {
    typealias Graph = SceneAuthoredEffectRenderPlan

    static let inputWidth = 2_048
    static let inputHeight = 1_152

    static func texture(
        _ kind: Graph.TextureKind,
        layerID: Int,
        effect: Graph.EffectKey? = nil,
        name: String? = nil
    ) -> Graph.TextureIdentity {
        .init(kind: kind, layerID: layerID, effect: effect, name: name)
    }

    static func material(
        index: Int,
        effect: Graph.EffectKey,
        target: Graph.TextureIdentity,
        reads: [Graph.TextureIdentity]
    ) -> Graph.Node {
        .init(
            nodeIndex: index,
            effect: effect,
            definitionPassIndex: index,
            materialOrdinal: index,
            instancePassIndex: index,
            kind: .material,
            materialPath: "materials/extent-\(index).json",
            materialPassID: "materials/extent-\(index).json#0",
            target: target,
            bindings: reads.enumerated().map { slot, texture in
                .init(
                    slot: slot,
                    authoredName: texture.name ?? "previous",
                    texture: texture,
                    conditions: nil
                )
            },
            commandSource: nil,
            commandTarget: nil,
            compose: nil,
            conditions: nil
        )
    }

    static func copy(
        index: Int,
        effect: Graph.EffectKey,
        source: Graph.TextureIdentity,
        target: Graph.TextureIdentity
    ) -> Graph.Node {
        .init(
            nodeIndex: index,
            effect: effect,
            definitionPassIndex: index,
            materialOrdinal: nil,
            instancePassIndex: nil,
            kind: .copy,
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
        layerID: Int,
        firstExtent: Graph.TargetExtent,
        secondExtent: Graph.TargetExtent
    ) -> Graph {
        let key = Graph.EffectKey(
            layerID: layerID,
            effectIndex: 0,
            descriptorID: "\(layerID)#effect#extent"
        )
        let input = texture(.layerSource, layerID: layerID)
        let output = texture(.effectOutput, layerID: layerID, effect: key)
        let first = texture(
            .framebuffer, layerID: layerID, effect: key, name: "first"
        )
        let second = texture(
            .framebuffer, layerID: layerID, effect: key, name: "second"
        )
        let nodes = [
            material(index: 0, effect: key, target: first, reads: [input]),
            copy(index: 1, effect: key, source: first, target: second),
            material(index: 2, effect: key, target: output, reads: [second]),
        ]
        return .init(
            layerID: layerID,
            effects: [.init(
                key: key,
                definitionPath: "effects/extent/effect.json",
                input: input,
                output: output,
                nodeIndices: nodes.map(\.nodeIndex)
            )],
            renderTargets: [
                .init(
                    texture: first,
                    extent: firstExtent,
                    format: "rgba_backbuffer",
                    declaredUnique: true,
                    clear: nil,
                    uvs: nil,
                    conditions: nil
                ),
                .init(
                    texture: second,
                    extent: secondExtent,
                    format: "rgba_backbuffer",
                    declaredUnique: false,
                    clear: nil,
                    uvs: nil,
                    conditions: nil
                ),
            ],
            nodes: nodes,
            finalOutput: output,
            blockers: []
        )
    }

    static func positive(
        layerID: Int,
        extent: Graph.TargetExtent
    ) -> [[Int]] {
        let graph = graph(
            layerID: layerID,
            firstExtent: extent,
            secondExtent: extent
        )
        guard case let .success(plan) = SceneGraphRenderTargetPlan.make(
            graph: graph,
            inputRole: .layerSource,
            inputWidth: inputWidth,
            inputHeight: inputHeight
        ), plan.matchesSourceDeclarations(in: graph) else {
            return []
        }
        return plan.logicalTargets.map {
            [$0.extent.width, $0.extent.height]
        }.sorted { lhs, rhs in
            lhs.lexicographicallyPrecedes(rhs)
        }
    }

    static func rejection(
        layerID: Int,
        first: Graph.TargetExtent,
        second: Graph.TargetExtent
    ) -> String {
        switch SceneGraphRenderTargetPlan.make(
            graph: graph(
                layerID: layerID,
                firstExtent: first,
                secondExtent: second
            ),
            inputRole: .layerSource,
            inputWidth: inputWidth,
            inputHeight: inputHeight
        ) {
        case .success: return "accepted"
        case let .failure(failure): return failure.rawValue
        }
    }

    static func main() throws {
        let height360 = Graph.TargetExtent(
            width: nil, height: 360, fit: nil, scale: nil
        )
        let height180 = Graph.TargetExtent(
            width: nil, height: 180, fit: nil, scale: nil
        )
        let scale4 = Graph.TargetExtent(
            width: nil, height: nil, fit: nil, scale: 4
        )
        let scale2 = Graph.TargetExtent(
            width: nil, height: nil, fit: nil, scale: 2
        )
        let composed = Graph.TargetExtent(
            width: 1_000, height: nil, fit: 600, scale: 2
        )
        let composedMismatch = Graph.TargetExtent(
            width: 800, height: nil, fit: 600, scale: 2
        )
        let result: [String: Any] = [
            "heightOnly": positive(layerID: 901, extent: height360),
            "heightMismatch": rejection(
                layerID: 902, first: height360, second: height180
            ),
            "scaleFour": positive(layerID: 903, extent: scale4),
            "scaleFourMismatch": rejection(
                layerID: 904, first: scale4, second: scale2
            ),
            "widthFitScale": positive(layerID: 905, extent: composed),
            "widthFitScaleMismatch": rejection(
                layerID: 906, first: composed, second: composedMismatch
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


class SceneNonenlargingExtentCohortTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("xcrun") is None:
            raise unittest.SkipTest("xcrun is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-nonenlarging-extents-"
        )
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = root / "harness"
        subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-o",
                str(binary),
            ],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        completed = subprocess.run(
            [str(binary)],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_height_only_preserves_input_width_and_rejects_mismatch(self) -> None:
        self.assertEqual(self.result["heightOnly"], [[2048, 360], [2048, 360]])
        self.assertEqual(
            self.result["heightMismatch"],
            "unsupportedTargetDescriptor",
        )

    def test_scale_four_downsamples_both_axes_and_rejects_mismatch(self) -> None:
        self.assertEqual(self.result["scaleFour"], [[512, 288], [512, 288]])
        self.assertEqual(
            self.result["scaleFourMismatch"],
            "unsupportedTargetDescriptor",
        )

    def test_width_fit_scale_uses_authored_order_and_rejects_mismatch(self) -> None:
        self.assertEqual(self.result["widthFitScale"], [[260, 300], [260, 300]])
        self.assertEqual(
            self.result["widthFitScaleMismatch"],
            "unsupportedTargetDescriptor",
        )


if __name__ == "__main__":
    unittest.main()
