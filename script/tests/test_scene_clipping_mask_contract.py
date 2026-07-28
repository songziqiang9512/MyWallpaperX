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
    SOURCE_ROOT / "Resources/SceneNamedTextureReference.swift",
    SOURCE_ROOT / "RenderGraph/SceneClippingMaskContract.swift",
]

HARNESS = r'''
import Foundation

struct SceneDocument {
    struct ShaderValue {
        let valueKind: String
        let userBinding: String?
        let components: [Double]?
    }
}

struct SceneEffectTextureInput {
    let value: String
}

struct SceneRenderDescriptor {
    struct EffectDescriptor {
        struct PassDescriptor {
            let passIndex: Int
            let texturePaths: [String]
            let textureSlots: [String?]
            let userTextureInputs: [SceneEffectTextureInput?]
            let combos: [String: Int]
            let constantShaderValues: [String: SceneDocument.ShaderValue]
        }

        let id: String
        let file: String
        let visible: Bool?
        let passes: [PassDescriptor]
    }
}

@main
enum Harness {
    static let path = "effects/workshop/2800594362/clipping_mask/effect.json"

    static func value(_ components: [Double]) -> SceneDocument.ShaderValue {
        .init(valueKind: components.count == 1 ? "number" : "vector",
              userBinding: nil, components: components)
    }

    static func effect(
        provider: Int = 42,
        path: String = Harness.path,
        variant: String = "a",
        slots: Int = 2,
        combos: [String: Int] = ["BLENDMODE": 5],
        constants: [String: SceneDocument.ShaderValue] = [:],
        userTexture: Bool = false
    ) -> SceneRenderDescriptor.EffectDescriptor {
        let reference = "_rt_imageLayerComposite_\(provider)_\(variant)"
        var textureSlots = [String?](repeating: nil, count: slots)
        textureSlots[1] = reference
        return .init(
            id: "7#effect#8",
            file: path,
            visible: true,
            passes: [.init(
                passIndex: 0,
                texturePaths: [reference],
                textureSlots: textureSlots,
                userTextureInputs: userTexture ? [nil, .init(value: "mask")] : [],
                combos: combos,
                constantShaderValues: constants
            )]
        )
    }

    static func summary(
        _ effect: SceneRenderDescriptor.EffectDescriptor
    ) -> [String: Any] {
        guard let declaration = SceneClippingMaskContract.declaration(for: effect) else {
            return ["accepted": false]
        }
        return [
            "accepted": true,
            "provider": declaration.providerLayerID,
            "blendMode": declaration.blendMode,
            "profile": declaration.profile.rawValue,
        ]
    }

    static func main() throws {
        let classicOpacity = effect(
            slots: 3,
            combos: [:],
            constants: ["Opacity": value([1])]
        )
        let weighted = effect(
            slots: 4,
            combos: [:],
            constants: [
                "0opacity": value([1]),
                "1texOffset": value([0]),
                "color": value([0, 0, 0]),
                "threshold": value([1]),
                "weight": value([1]),
            ]
        )
        let result: [String: Any] = [
            "classicDarken": summary(effect()),
            "classicOpacity": summary(classicOpacity),
            "weighted": summary(weighted),
            "lookalike": summary(effect(path: "effects/other/clipping_mask/effect.json")),
            "secondary": summary(effect(variant: "b")),
            "nonNeutralOpacity": summary(effect(
                slots: 3, combos: [:], constants: ["Opacity": value([0.5])]
            )),
            "unknownCombo": summary(effect(combos: ["BLENDMODE": 7])),
            "userTexture": summary(effect(userTexture: true)),
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneClippingMaskContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-clipping-mask-"
        )
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = directory / "scene-clipping-mask"
        compilation = subprocess.run(
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

    def test_observed_profiles_are_typed(self) -> None:
        self.assertEqual(
            self.result["classicDarken"],
            {"accepted": True, "provider": 42, "blendMode": 5, "profile": "classic"},
        )
        self.assertEqual(
            self.result["classicOpacity"],
            {"accepted": True, "provider": 42, "blendMode": 0, "profile": "classic"},
        )
        self.assertEqual(
            self.result["weighted"],
            {
                "accepted": True,
                "provider": 42,
                "blendMode": 0,
                "profile": "weightedNeutral",
            },
        )

    def test_unregistered_shapes_fail_closed(self) -> None:
        for key in (
            "lookalike",
            "secondary",
            "nonNeutralOpacity",
            "unknownCombo",
            "userTexture",
        ):
            self.assertEqual(self.result[key], {"accepted": False}, key)

    def test_planner_uses_content_fingerprints_not_sample_ids(self) -> None:
        planner = (
            SOURCE_ROOT / "RenderGraph/SceneAuthoredClippingMaskPlanner.swift"
        ).read_text(encoding="utf-8")
        self.assertIn(
            "82119d559341b8452ef12917733536fe24193c791f2efd3412fc21a7c5b1a16b",
            planner,
        )
        self.assertIn(
            "622e8dc7d63c4c7f6371d2f601f32dd442e2a26c8279853acdfee93aedf4c404",
            planner,
        )
        for sample_id in ("2902406982", "2938612768", "2974757317", "3768229922"):
            self.assertNotIn(sample_id, planner)


if __name__ == "__main__":
    unittest.main()
