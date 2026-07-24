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
    SOURCE_ROOT / "Properties/SceneDynamicSnapshot.swift",
    SOURCE_ROOT / "RenderGraph/SceneEffectTextureInput.swift",
    SOURCE_ROOT / "Effects/SceneXRayRuntimePlan.swift",
]

HARNESS_SOURCE = r'''
import Foundation
import simd

struct SceneDocument {
    struct ShaderValue {
        let valueKind: String
        let userBinding: String?
        let components: [Double]?
    }
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

    struct Layer {
        let id: Int
        let effects: [EffectDescriptor]
    }
}

struct SceneXRayEffectTextures {
    let effectID: String
    let blendTexturePath: String
    let haloTexturePath: String?
    let opacityMaskPath: String?
    let blendPropertyKey: String?
    let haloPropertyKey: String?
    let blendUVScale: SIMD2<Float>
    let opacityUVScale: SIMD2<Float>

    func matches(_ declaration: SceneXRayRuntimePlanner.Declaration) -> Bool {
        effectID == declaration.effectID
            && blendTexturePath == declaration.blendTexturePath
            && haloTexturePath == declaration.haloTexturePath
            && opacityMaskPath == declaration.opacityMaskPath
            && blendPropertyKey == declaration.blendPropertyKey
            && haloPropertyKey == declaration.haloPropertyKey
    }
}

@main
enum Harness {
    static let visibilityTarget = SceneDynamicTarget.effectVisibility(
        layerID: 42,
        effectIndex: 0
    )
    static let sizeTarget = SceneDynamicTarget.effectConstant(
        layerID: 42,
        effectIndex: 0,
        passIndex: 0,
        name: "size"
    )
    static let multiplyTarget = SceneDynamicTarget.effectConstant(
        layerID: 42,
        effectIndex: 0,
        passIndex: 0,
        name: "multiply"
    )

    static func value(
        _ components: [Double],
        kind: String = "number",
        binding: String? = nil
    ) -> SceneDocument.ShaderValue {
        .init(valueKind: kind, userBinding: binding, components: components)
    }

    static func effect(
        id: String = "42#effect#7",
        file: String = "effects/xray/effect.json",
        visible: Bool? = true,
        combos: [String: Int] = ["BLENDMODE": 0, "OPACITYMASK": 1],
        textureSlots: [String?] = [nil, "blend.tex", "halo.tex", "mask.tex"],
        texturePaths: [String] = ["blend.tex", "halo.tex", "mask.tex"],
        userTextureInputs: [SceneEffectTextureInput?] = [
            nil,
            SceneEffectTextureInput(kind: .property, value: "bottom"),
            SceneEffectTextureInput(kind: .property, value: "xraystyle"),
        ],
        values: [String: SceneDocument.ShaderValue] = [
            "size": value([0.4], kind: "binding", binding: "user.size"),
            "multiply": value([1.25], kind: "binding", binding: "user.multiply"),
        ]
    ) -> SceneRenderDescriptor.EffectDescriptor {
        .init(
            id: id,
            file: file,
            visible: visible,
            passes: [
                .init(
                    passIndex: 0,
                    texturePaths: texturePaths,
                    textureSlots: textureSlots,
                    userTextureInputs: userTextureInputs,
                    combos: combos,
                    constantShaderValues: values
                )
            ]
        )
    }

    static func layer(
        effects: [SceneRenderDescriptor.EffectDescriptor] = [effect()]
    ) -> SceneRenderDescriptor.Layer {
        .init(id: 42, effects: effects)
    }

    static func snapshot(
        visible: Bool = true,
        size: Double = 0.4,
        multiply: Double = 1.25
    ) -> SceneDynamicSnapshot {
        let definitions = [
            SceneDynamicTargetDefinition(
                target: visibilityTarget,
                valueType: .bool,
                authoredValue: .bool(true)
            ),
            SceneDynamicTargetDefinition(
                target: sizeTarget,
                valueType: .scalar,
                authoredValue: .scalar(0.4)
            ),
            SceneDynamicTargetDefinition(
                target: multiplyTarget,
                valueType: .scalar,
                authoredValue: .scalar(1.25)
            ),
        ]
        return SceneDynamicSnapshotResolver().resolve(
            frameIndex: 1,
            generation: 1,
            definitions: definitions,
            userValues: [
                visibilityTarget: .bool(visible),
                sizeTarget: .scalar(size),
                multiplyTarget: .scalar(multiply),
            ]
        ).snapshot
    }

    static func resources(
        effectID: String = "42#effect#7"
    ) -> SceneXRayEffectTextures {
        .init(
            effectID: effectID,
            blendTexturePath: "blend.tex",
            haloTexturePath: "halo.tex",
            opacityMaskPath: "mask.tex",
            blendPropertyKey: "bottom",
            haloPropertyKey: "xraystyle",
            blendUVScale: SIMD2(0.5, 0.75),
            opacityUVScale: SIMD2(0.25, 0.5)
        )
    }

    static func main() throws {
        let authoredLayer = layer()
        let declaration = SceneXRayRuntimePlanner.declaration(for: authoredLayer)
        let plan = SceneXRayRuntimePlanner.plan(
            for: authoredLayer,
            resources: resources(),
            snapshot: snapshot(size: 0.25, multiply: 2.5),
            pointerIsInside: true
        )
        let fallbackPlan = SceneXRayRuntimePlanner.plan(
            for: authoredLayer,
            resources: resources(),
            snapshot: snapshot(size: 2),
            pointerIsInside: true
        )
        let result: [String: Any] = [
            "declaration": declaration != nil,
            "blendPath": declaration?.blendTexturePath ?? "",
            "haloPath": declaration?.haloTexturePath ?? "",
            "opacityPath": declaration?.opacityMaskPath ?? "",
            "blendProperty": declaration?.blendPropertyKey ?? "",
            "haloProperty": declaration?.haloPropertyKey ?? "",
            "fallbackSize": declaration?.fallbackSize ?? -1,
            "fallbackMultiply": declaration?.fallbackMultiply ?? -1,
            "consumerCount": SceneXRayRuntimePlanner.liveConsumerTargets(
                for: authoredLayer
            ).count,
            "dynamicSize": plan?.size ?? -1,
            "dynamicMultiply": plan?.multiply ?? -1,
            "fallbackDynamicSize": fallbackPlan?.size ?? -1,
            "blendScale": [plan?.blendUVScale.x ?? -1, plan?.blendUVScale.y ?? -1],
            "outsideRejected": SceneXRayRuntimePlanner.plan(
                for: authoredLayer,
                resources: resources(),
                snapshot: snapshot(),
                pointerIsInside: false
            ) == nil,
            "hiddenRejected": SceneXRayRuntimePlanner.plan(
                for: authoredLayer,
                resources: resources(),
                snapshot: snapshot(visible: false),
                pointerIsInside: true
            ) == nil,
            "resourceMismatchRejected": SceneXRayRuntimePlanner.plan(
                for: authoredLayer,
                resources: resources(effectID: "other"),
                snapshot: snapshot(),
                pointerIsInside: true
            ) == nil,
            "unknownComboRejected": SceneXRayRuntimePlanner.declaration(
                for: layer(effects: [effect(combos: ["UNSUPPORTED": 1])])
            ) == nil,
            "duplicateRejected": SceneXRayRuntimePlanner.declaration(
                for: layer(effects: [effect(), effect(id: "duplicate")])
            ) == nil,
            "shapeRejected": SceneXRayRuntimePlanner.declaration(
                for: layer(effects: [
                    effect(
                        textureSlots: [nil, "blend.tex", nil],
                        texturePaths: ["blend.tex"],
                        userTextureInputs: [
                            nil,
                            nil,
                            SceneEffectTextureInput(
                                kind: .property,
                                value: "xraystyle"
                            ),
                        ]
                    )
                ])
            ) == nil,
            "boundMultiplyAccepted": SceneXRayRuntimePlanner.declaration(
                for: layer(effects: [
                    effect(values: [
                        "size": value([0.4]),
                        "multiply": value(
                            [1],
                            kind: "binding",
                            binding: "user.multiply"
                        ),
                    ])
                ])
            ) != nil,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneXRayPlannerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-xray-planner-")
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = root / "xray-planner"
        compilation = subprocess.run(
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
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(cls.binary)],
            check=True,
            capture_output=True,
            text=True,
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_exact_declaration_and_dynamic_size_are_planned(self) -> None:
        self.assertTrue(self.result["declaration"])
        self.assertEqual(self.result["blendPath"], "blend.tex")
        self.assertEqual(self.result["haloPath"], "halo.tex")
        self.assertEqual(self.result["opacityPath"], "mask.tex")
        self.assertEqual(self.result["blendProperty"], "bottom")
        self.assertEqual(self.result["haloProperty"], "xraystyle")
        self.assertAlmostEqual(self.result["fallbackSize"], 0.4)
        self.assertAlmostEqual(self.result["fallbackMultiply"], 1.25)
        self.assertEqual(self.result["consumerCount"], 3)
        self.assertAlmostEqual(self.result["dynamicSize"], 0.25)
        self.assertAlmostEqual(self.result["dynamicMultiply"], 2.5)
        self.assertEqual(self.result["blendScale"], [0.5, 0.75])

    def test_out_of_range_dynamic_size_falls_back_to_authored_value(self) -> None:
        self.assertAlmostEqual(self.result["fallbackDynamicSize"], 0.4)

    def test_pointer_visibility_and_resource_identity_gate_execution(self) -> None:
        self.assertTrue(self.result["outsideRejected"])
        self.assertTrue(self.result["hiddenRejected"])
        self.assertTrue(self.result["resourceMismatchRejected"])

    def test_unknown_or_ambiguous_shapes_fail_closed(self) -> None:
        self.assertTrue(self.result["unknownComboRejected"])
        self.assertTrue(self.result["duplicateRejected"])
        self.assertTrue(self.result["shapeRejected"])
        self.assertTrue(self.result["boundMultiplyAccepted"])


if __name__ == "__main__":
    unittest.main()
