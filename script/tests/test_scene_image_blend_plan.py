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
    SOURCE_ROOT / "SceneEffectTextureInput.swift",
    SOURCE_ROOT / "SceneNamedTextureReference.swift",
    SOURCE_ROOT / "SceneFrameTextureRegistry.swift",
    SOURCE_ROOT / "SceneImageBlendRenderPlan.swift",
]

HARNESS_SOURCE = r'''
import Foundation

struct SceneDocument {
    struct ShaderValue {
        let valueKind: String
        let userBinding: String?
        let components: [Double]?
    }
}
struct SceneUtilityLayer {}
struct SceneRenderDescriptor {
    struct EffectDescriptor {
        struct PassDescriptor {
            let passIndex: Int
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
    struct Layer {
        let id: Int
        let contentKind: String
        let imagePath: String?
        let utilityLayer: SceneUtilityLayer?
        let dependencyLayerIDs: [Int]
        let childLayerIDs: [Int]
        let visible: Bool?
        let effects: [EffectDescriptor]
    }
    let layers: [Layer]
    let texturePropertyKeys: [String]
}

@main
enum Harness {
    static func main() throws {
        let provider = image(100, visible: false)
        let effectfulProvider = image(200, effects: [blend(provider: 100)])
        let valid = image(10, dependencies: [100], effects: [
            blend(provider: 100),
            blend(provider: 100, systemSource: true),
        ])
        let mismatch = image(11, effects: [blend(provider: 100)])
        let effectful = image(12, dependencies: [200], effects: [blend(provider: 200)])
        let boundValue = image(13, dependencies: [100], effects: [
            blend(provider: 100, boundMultiply: true),
        ])
        let transformed = image(14, dependencies: [100], effects: [
            blend(provider: 100, transform: true),
        ])
        let secondary = image(15, dependencies: [100], effects: [
            blend(provider: 100, variant: "b"),
        ])
        let defaulted = image(16, dependencies: [100], effects: [
            blend(provider: 100, omitAlpha: true, neutralTransformConstants: true),
        ])
        let propertyFallback = image(18, dependencies: [100], effects: [
            blend(provider: 100, propertySource: "newproperty25", scriptedAlpha: true),
        ])
        let secondPropertyFallback = image(20, dependencies: [100], effects: [
            blend(provider: 100, propertySource: "newproperty26"),
        ])
        let unplannedProperty = image(21, effects: [
            blend(provider: 100, propertySource: "declared-but-unplanned"),
        ])
        let unsupportedScript = image(19, dependencies: [100], effects: [
            blend(provider: 100, scriptedAlpha: true),
        ])
        let nonNeutralConstants = image(17, dependencies: [100], effects: [
            blend(provider: 100, omitAlpha: true, neutralTransformConstants: true,
                  blendScale: 0.5),
        ])
        let layers = [valid, mismatch, effectful, boundValue, transformed, secondary,
                      defaulted, nonNeutralConstants, propertyFallback,
                      unsupportedScript, secondPropertyFallback, unplannedProperty,
                      provider, effectfulProvider]
        let plan = SceneImageBlendRenderPlan(
            descriptor: .init(
                layers: layers,
                texturePropertyKeys: [
                    "newproperty25",
                    "newproperty26",
                    "declared-but-unplanned",
                    "declared-and-unused",
                ]
            ),
            visibleLayerIDs: Set(layers.compactMap { $0.visible == false ? nil : $0.id })
        )
        let operation = plan.operationsByConsumerLayerID[10]
        let result: [String: Any] = [
            "consumers": plan.operationsByConsumerLayerID.keys.sorted(),
            "provider": operation?.providerLayerID ?? -1,
            "multiply": operation?.multiply ?? -1,
            "alpha": operation?.alphaMultiply ?? -1,
            "writesAlpha": operation?.writesAlpha ?? false,
            "defaultAlpha": plan.operationsByConsumerLayerID[16]?.alphaMultiply ?? -1,
            "defaultWritesAlpha": plan.operationsByConsumerLayerID[16]?.writesAlpha ?? true,
            "propertyCandidates": plan.operationsByConsumerLayerID[18]?
                .textureSelection.candidates.map(\.reportToken) ?? [],
            "propertyUsesInitialAlpha": plan.operationsByConsumerLayerID[18]?
                .usesAuthoredInitialAlpha ?? false,
            "executedUserPropertyKeys": plan.executedUserPropertyKeys.sorted(),
            "report": plan.reportLines(),
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func image(
        _ id: Int,
        visible: Bool? = true,
        dependencies: [Int] = [],
        effects: [SceneRenderDescriptor.EffectDescriptor] = []
    ) -> SceneRenderDescriptor.Layer {
        .init(
            id: id,
            contentKind: "image",
            imagePath: "models/\(id).json",
            utilityLayer: nil,
            dependencyLayerIDs: dependencies,
            childLayerIDs: [],
            visible: visible,
            effects: effects
        )
    }

    static func blend(
        provider: Int,
        systemSource: Bool = false,
        propertySource: String? = nil,
        boundMultiply: Bool = false,
        transform: Bool = false,
        variant: String = "a",
        omitAlpha: Bool = false,
        scriptedAlpha: Bool = false,
        neutralTransformConstants: Bool = false,
        blendScale: Double = 1
    ) -> SceneRenderDescriptor.EffectDescriptor {
        let source: SceneEffectTextureInput? = if systemSource {
            SceneEffectTextureInput(kind: .system, value: "$mediaThumbnail")
        } else if let propertySource {
            SceneEffectTextureInput(kind: .property, value: propertySource)
        } else {
            nil
        }
        let target = "_rt_imageLayerComposite_\(provider)_\(variant)"
        var constants: [String: SceneDocument.ShaderValue] = [
            "multiply": .init(
                valueKind: boundMultiply ? "binding" : "number",
                userBinding: boundMultiply ? "strength" : nil,
                components: [1]
            ),
        ]
        if !omitAlpha {
            constants["alpha"] = .init(
                valueKind: scriptedAlpha ? "binding" : "number",
                userBinding: nil,
                components: [1]
            )
        }
        if neutralTransformConstants {
            constants["blendangle"] = .init(
                valueKind: "number", userBinding: nil, components: [0]
            )
            constants["blendoffset"] = .init(
                valueKind: "vector", userBinding: nil, components: [0, 0]
            )
            constants["blendscale"] = .init(
                valueKind: "number", userBinding: nil, components: [blendScale]
            )
        }
        return .init(
            id: "blend-\(provider)-\(systemSource)",
            file: "effects/blend/effect.json",
            visible: true,
            passes: [.init(
                passIndex: 0,
                textureSlots: [nil, target],
                userTextureInputs: source == nil ? [] : [nil, source],
                combos: [
                    "BLENDMODE": 0,
                    "WRITEALPHA": omitAlpha ? 0 : 1,
                    "TRANSFORMUV": transform ? 1 : 0,
                ],
                constantShaderValues: constants
            )]
        )
    }
}
'''


class SceneImageBlendPlanTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-image-blend-plan-")
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = directory / "image-blend-plan"
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness), "-o", str(cls.binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run([str(cls.binary)], check=True, capture_output=True, text=True)
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_hidden_forward_static_provider_is_planned(self) -> None:
        self.assertEqual(self.result["consumers"], [10, 16, 18, 20])
        self.assertEqual(self.result["provider"], 100)
        self.assertEqual(self.result["multiply"], 1)
        self.assertEqual(self.result["alpha"], 1)
        self.assertTrue(self.result["writesAlpha"])
        self.assertEqual(self.result["defaultAlpha"], 1)
        self.assertFalse(self.result["defaultWritesAlpha"])

    def test_property_provider_preserves_authored_layer_fallback(self) -> None:
        self.assertEqual(
            self.result["propertyCandidates"],
            ["property:newproperty25", "layer:100"],
        )
        self.assertTrue(self.result["propertyUsesInitialAlpha"])

    def test_executed_property_keys_exclude_declared_but_unplanned_properties(self) -> None:
        self.assertEqual(
            self.result["executedUserPropertyKeys"],
            ["newproperty25", "newproperty26"],
        )

    def test_media_bound_and_unsupported_operations_do_not_enter_static_plan(self) -> None:
        self.assertEqual(len(self.result["report"]), 5)
        self.assertIn("imageBlendPlannedCount: 4", self.result["report"])


if __name__ == "__main__":
    unittest.main()
