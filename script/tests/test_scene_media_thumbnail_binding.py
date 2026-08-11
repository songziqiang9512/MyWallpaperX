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
SOURCE = SCENE_ROOT / "Runtime/SceneMediaThumbnailBindingProgram.swift"
LAUNCH_SOURCE = SCENE_ROOT / "Runtime/SceneDesktopWallpaperHost+Launch.swift"

HARNESS = r'''
import Foundation

struct SceneEffectTextureInput: Equatable {
    enum Kind { case system, property }
    let kind: Kind
    let value: String
}

struct SceneDocument {
    struct ShaderValue {
        let userBinding: String?
        let components: [Double]?
    }
}

struct SceneRenderDescriptor {
    struct EffectDescriptor {
        struct PassDescriptor {
            let textureSlots: [String?]
            let userTextureInputs: [SceneEffectTextureInput?]
            let combos: [String: Int]
            let constantShaderValues: [String: SceneDocument.ShaderValue]
        }
        let file: String
        let visible: Bool?
        let passes: [PassDescriptor]
    }
    struct Layer {
        let id: Int
        let contentKind: String
        let effects: [EffectDescriptor]
        var isImageRenderable: Bool { contentKind == "image" || contentKind == "solid" }
    }
    let layers: [Layer]
}

enum SceneJSONValue: Equatable {}
enum SceneScriptBindingValueType { case boolean, number }
struct SceneScriptBindingOwner {
    enum Kind { case effect, object }
    let kind: Kind
    let objectID: Int?
    let effectIndex: Int?
}
struct SceneScriptBindingIR {
    let source: String
    let owner: SceneScriptBindingOwner
    let properties: [String: SceneJSONValue]
    let valueType: SceneScriptBindingValueType
    let targetKey: String
}

func effect(
    path: String = "effects/blend/effect.json",
    visible: Bool? = true,
    identity: String = "$mediaThumbnail",
    multiply: Double = 1,
    alpha: Double = 1
) -> SceneRenderDescriptor.EffectDescriptor {
    .init(
        file: path,
        visible: visible,
        passes: [.init(
            textureSlots: [nil, "authored/fallback"],
            userTextureInputs: [nil, .init(kind: .system, value: identity)],
            combos: ["BLENDMODE": 0, "TRANSFORMREPEAT": 2],
            constantShaderValues: [
                "multiply": .init(userBinding: nil, components: [multiply]),
                "alpha": .init(userBinding: nil, components: [alpha]),
            ]
        )]
    )
}

let visibilitySource = """
// comments and exported metadata do not change the event contract
export let metadata = 'fixture';
export function mediaThumbnailChanged(event) {
    thisObject.visible = event.hasThumbnail;
}
"""
let binding = SceneScriptBindingIR(
    source: visibilitySource,
    owner: .init(kind: .effect, objectID: 20, effectIndex: 0),
    properties: [:],
    valueType: .boolean,
    targetKey: "visible"
)
let descriptor = SceneRenderDescriptor(layers: [
    .init(id: 10, contentKind: "image", effects: [effect()]),
    .init(
        id: 20,
        contentKind: "solid",
        effects: [effect(path: "effects/workshop/fixture/blend/effect.json", visible: false)]
    ),
    .init(id: 30, contentKind: "solid", effects: [effect(visible: false)]),
    .init(id: 40, contentKind: "image", effects: [effect(identity: "$unclaimedMediaTexture")]),
    .init(id: 50, contentKind: "image", effects: [effect(multiply: 0.5)]),
    .init(id: 60, contentKind: "image", effects: [effect(path: "effects/color/effect.json")]),
    .init(id: 70, contentKind: "text", effects: [effect()]),
])
let program = SceneMediaThumbnailBindingCompiler.compile(
    descriptor: descriptor,
    scriptBindings: [binding]
)
let result: [String: Any] = [
    "accepted": program.currentLayerIDs.sorted(),
    "hasConsumers": program.hasConsumers,
    "report": program.reportLines(),
]
let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
'''


class SceneMediaThumbnailBindingTests(unittest.TestCase):
    def test_current_binding_compiler_is_shared_and_fail_closed(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")
        with tempfile.TemporaryDirectory(prefix="mwx-media-binding-") as directory:
            root = Path(directory)
            harness = root / "main.swift"
            harness.write_text(HARNESS, encoding="utf-8")
            binary = root / "binding"
            subprocess.run(
                ["swiftc", str(SOURCE), str(harness), "-o", str(binary)],
                check=True,
                cwd=ROOT,
            )
            result = json.loads(subprocess.check_output([str(binary)], text=True))
        self.assertEqual(result["accepted"], [10, 20])
        self.assertTrue(result["hasConsumers"])
        self.assertEqual(
            result["report"],
            [
                "mediaThumbnailCurrentBindingCount: 2",
                "mediaThumbnailCurrentBindingLayerIDs: 10,20",
            ],
        )

    def test_launch_uses_current_binding_compiler_without_transition_owner(self) -> None:
        launch = LAUNCH_SOURCE.read_text(encoding="utf-8")
        self.assertIn(
            "let mediaThumbnailBindings = SceneMediaThumbnailBindingCompiler.compile(",
            launch,
        )
        self.assertNotIn("SceneMediaThumbnailTransitionCompiler", launch)

        product_source = "\n".join(
            path.read_text(encoding="utf-8")
            for path in sorted(SCENE_ROOT.rglob("*.swift"))
        )
        for retired_identifier in (
            "SceneMediaThumbnailTransition",
            "$mediaPreviousThumbnail",
            "previousTransitionsByLayerID",
            "mediaThumbnailPreviousTransition",
            "mediaThumbnailPrevious",
        ):
            self.assertNotIn(retired_identifier, product_source)


if __name__ == "__main__":
    unittest.main()
