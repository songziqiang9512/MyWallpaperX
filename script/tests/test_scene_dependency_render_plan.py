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
    SOURCE_ROOT / "Effects/SceneGradientColorRuntimePlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneClippingMaskContract.swift",
    SOURCE_ROOT / "RenderGraph/SceneDependencyRenderPlan.swift",
]

HARNESS_SOURCE = r'''
import Foundation

struct SceneDocument {
    struct ShaderValue {
        let valueKind: String
        let userBinding: String?
        let components: [Double]?

        init(
            valueKind: String = "number",
            userBinding: String? = nil,
            components: [Double]?
        ) {
            self.valueKind = valueKind
            self.userBinding = userBinding
            self.components = components
        }
    }
}
struct SceneUtilityLayer {
    enum Kind { case composition, project, fullscreen }
    let kind: Kind
}
struct SceneRenderDescriptor {
    struct EffectDescriptor {
        struct PassDescriptor {
            let passIndex: Int
            let texturePaths: [String]
            let textureSlots: [String?]
            let userTextureInputs: [Int?]
            let combos: [String: Int]
            let constantShaderValues: [String: SceneDocument.ShaderValue]

            init(
                passIndex: Int,
                texturePaths: [String] = [],
                textureSlots: [String?],
                userTextureInputs: [Int?] = [],
                combos: [String: Int],
                constantShaderValues: [String: SceneDocument.ShaderValue]
            ) {
                self.passIndex = passIndex
                self.texturePaths = texturePaths
                self.textureSlots = textureSlots
                self.userTextureInputs = userTextureInputs
                self.combos = combos
                self.constantShaderValues = constantShaderValues
            }
        }
        let id: String
        let file: String
        let visible: Bool?
        let passes: [PassDescriptor]
    }
    struct Layer {
        let id: Int
        let contentKind: String
        let utilityLayer: SceneUtilityLayer?
        let dependencyLayerIDs: [Int]
        let childLayerIDs: [Int]
        let visible: Bool?
        let effects: [EffectDescriptor]
    }
    let layers: [Layer]
    let renderOrderLayerIDs: [Int]
}

@main
enum Harness {
    static func main() throws {
        let provider = layer(1, kind: .composition, visible: false)
        let visibleConsumer = consumer(2, provider: 1, dependencies: [])
        let hiddenConsumer = consumer(3, provider: 1, visible: false)
        let cycleA = layer(4, kind: .composition, dependencies: [5])
        let cycleB = layer(5, kind: .composition, dependencies: [4])
        let forwardConsumer = consumer(6, provider: 7)
        let forwardProvider = layer(7, kind: .composition)
        let partialConsumer = consumer(8, provider: 1, extraEffect: true)
        let neutralOpacityConsumer = consumer(9, provider: 1, opacity: 1)
        let nonNeutralOpacityConsumer = consumer(10, provider: 1, opacity: 0.5)
        let unsupportedBlendConsumer = consumer(
            11,
            provider: 1,
            effectPath: "effects/blend/effect.json"
        )
        let lookalikeConsumer = consumer(
            16,
            provider: 1,
            effectPath: "effects/workshop/other/clipping_mask/effect.json"
        )
        let supportedGradientConsumer = gradientConsumer(12, provider: 1)
        let reversedGradientConsumer = gradientConsumer(13, provider: 1, reversed: true)
        let invalidGradientConsumer = gradientConsumer(14, provider: 1, axis: 2)
        let utilityConsumer = SceneRenderDescriptor.Layer(
            id: 15,
            contentKind: "composition",
            utilityLayer: .init(kind: .composition),
            dependencyLayerIDs: [1],
            childLayerIDs: [],
            visible: true,
            effects: [effect(id: 15, provider: 1)]
        )
        let projectUtilityConsumer = SceneRenderDescriptor.Layer(
            id: 17,
            contentKind: "project",
            utilityLayer: .init(kind: .project),
            dependencyLayerIDs: [1],
            childLayerIDs: [],
            visible: true,
            effects: [effect(id: 17, provider: 1)]
        )
        let childUtilityConsumer = SceneRenderDescriptor.Layer(
            id: 18,
            contentKind: "composition",
            utilityLayer: .init(kind: .composition),
            dependencyLayerIDs: [1],
            childLayerIDs: [99],
            visible: true,
            effects: [effect(id: 18, provider: 1)]
        )
        let extraDependencyUtilityConsumer = SceneRenderDescriptor.Layer(
            id: 19,
            contentKind: "composition",
            utilityLayer: .init(kind: .composition),
            dependencyLayerIDs: [1, 7],
            childLayerIDs: [],
            visible: true,
            effects: [effect(id: 19, provider: 1)]
        )
        let legacyNoiseProvider = SceneRenderDescriptor.Layer(
            id: 30,
            contentKind: "solid",
            utilityLayer: nil,
            dependencyLayerIDs: [],
            childLayerIDs: [],
            visible: false,
            effects: []
        )
        let legacyNoiseConsumer = SceneRenderDescriptor.Layer(
            id: 31,
            contentKind: "composition",
            utilityLayer: .init(kind: .composition),
            dependencyLayerIDs: [30],
            childLayerIDs: [],
            visible: true,
            effects: [proceduralNoiseEffect(id: 31, provider: 30)]
        )
        let missingProviderConsumer = consumer(32, provider: 999)
        let descriptor = SceneRenderDescriptor(
            layers: [
                provider, visibleConsumer, hiddenConsumer,
                cycleA, cycleB, forwardConsumer, forwardProvider, partialConsumer,
                neutralOpacityConsumer, nonNeutralOpacityConsumer, unsupportedBlendConsumer,
                supportedGradientConsumer, reversedGradientConsumer, invalidGradientConsumer,
                utilityConsumer, lookalikeConsumer, projectUtilityConsumer,
                childUtilityConsumer, extraDependencyUtilityConsumer,
                legacyNoiseProvider, legacyNoiseConsumer, missingProviderConsumer,
            ],
            renderOrderLayerIDs: [
                1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
                30, 31, 32,
            ]
        )
        let visibleLayerIDs: Set<Int> = [
            1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 31, 32,
        ]
        let plan = SceneDependencyRenderPlan(
            descriptor: descriptor,
            visibleLayerIDs: visibleLayerIDs,
            executableUtilityConsumerLayerIDs: [15, 31]
        )
        let defaultPlan = SceneDependencyRenderPlan(
            descriptor: descriptor,
            visibleLayerIDs: visibleLayerIDs
        )
        let matrixProviders = (10...15).map { layer($0, kind: .composition) }
        let matrixProviderIDs = [10, 10, 10, 11, 12, 13, 14, 15]
        let matrixConsumers = matrixProviderIDs.enumerated().map { offset, providerID in
            consumer(20 + offset, provider: providerID, visible: offset != 2)
        }
        let matrixLayers = matrixProviders + matrixConsumers
        let matrixDescriptor = SceneRenderDescriptor(
            layers: matrixLayers,
            renderOrderLayerIDs: matrixLayers.map(\.id)
        )
        let matrixVisible = Set(matrixLayers.compactMap {
            $0.visible == false ? nil : $0.id
        })
        let matrixPlan = SceneDependencyRenderPlan(
            descriptor: matrixDescriptor,
            visibleLayerIDs: matrixVisible
        )
        let parsed = [
            SceneNamedTextureReference.parse("_rt_imageLayerComposite_42")?.variant.rawValue ?? "nil",
            SceneNamedTextureReference.parse("_rt_imageLayerComposite_42_a")?.variant.rawValue ?? "nil",
            SceneNamedTextureReference.parse("_rt_imageLayerComposite_42_b")?.variant.rawValue ?? "nil",
        ]
        let legacyNoiseBinding = plan.bindingsByConsumerLayerID[31]
        let result: [String: Any] = [
            "parsedVariants": parsed,
            "invalidReference": SceneNamedTextureReference.parse("_rt_imageLayerComposite_bad_a") == nil,
            "referenceCount": plan.references.count,
            "namedConsumers": plan.namedReferenceConsumerLayerIDs.sorted(),
            "executableUtilityConsumers": plan.executableUtilityConsumerLayerIDs.sorted(),
            "requiredEffectConsumers": plan.requiredEffectConsumerLayerIDs.sorted(),
            "bindingConsumers": plan.bindingsByConsumerLayerID.keys.sorted(),
            "defaultUtilityBinding": defaultPlan.bindingsByConsumerLayerID[15] != nil,
            "requiredProviders": plan.requiredProviderLayerIDs.sorted(),
            "cycles": plan.cyclicLayerIDs.sorted(),
            "issues": plan.issues.map { "\($0.layerID):\($0.kind.rawValue):\($0.providerLayerID ?? -1)" },
            "matrixBindingCount": matrixPlan.bindingsByConsumerLayerID.count,
            "matrixRequiredProviders": matrixPlan.requiredProviderLayerIDs.sorted(),
            "legacyNoiseBinding": [
                "consumer": legacyNoiseBinding?.consumerLayerID ?? -1,
                "provider": legacyNoiseBinding?.providerLayerID ?? -1,
                "effect": legacyNoiseBinding?.slot.effectID ?? "",
                "pass": legacyNoiseBinding?.slot.passIndex ?? -1,
                "slot": legacyNoiseBinding?.slot.slotIndex ?? -1,
                "blend": legacyNoiseBinding?.blendMode ?? -1,
                "procedural": legacyNoiseBinding?.kind == .proceduralNoiseLayer,
            ],
            "legacyNoiseRejects": [
                "modern": proceduralBinding(effectPath: "effects/procedural_noise/effect.json") == nil,
                "visibleProvider": proceduralBinding(providerVisible: true) == nil,
                "wrongProviderKind": proceduralBinding(providerContentKind: "image") == nil,
                "secondary": proceduralBinding(variantSuffix: "b") == nil,
                "wrongEffect": proceduralBinding(effectPath: "effects/workshop/other/procedural_noise/effect.json") == nil,
                "wrongPass": proceduralBinding(passIndex: 1) == nil,
                "wrongSlot": proceduralBinding(slotIndex: 2) == nil,
                "wrongCombos": proceduralBinding(extraCombos: ["BLENDMODE": 5]) == nil,
                "extraReference": proceduralBinding(extraReference: true) == nil,
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func layer(
        _ id: Int,
        kind: SceneUtilityLayer.Kind? = nil,
        dependencies: [Int] = [],
        visible: Bool? = true
    ) -> SceneRenderDescriptor.Layer {
        .init(
            id: id,
            contentKind: kind == nil ? "image" : "composition",
            utilityLayer: kind.map(SceneUtilityLayer.init(kind:)),
            dependencyLayerIDs: dependencies,
            childLayerIDs: [],
            visible: visible,
            effects: []
        )
    }

    static func consumer(
        _ id: Int,
        provider: Int,
        dependencies: [Int]? = nil,
        visible: Bool? = true,
        extraEffect: Bool = false,
        opacity: Double? = nil,
        effectPath: String = "effects/workshop/2800594362/clipping_mask/effect.json"
    ) -> SceneRenderDescriptor.Layer {
        var effects = [effect(
            id: id,
            provider: provider,
            opacity: opacity,
            path: effectPath
        )]
        if extraEffect {
            effects.append(.init(id: "tint", file: "effects/tint/effect.json", visible: true, passes: []))
        }
        return .init(
            id: id,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: dependencies ?? [provider],
            childLayerIDs: [],
            visible: visible,
            effects: effects
        )
    }

    static func effect(
        id: Int,
        provider: Int,
        opacity: Double? = nil,
        path: String = "effects/workshop/2800594362/clipping_mask/effect.json"
    ) -> SceneRenderDescriptor.EffectDescriptor {
        .init(
            id: "effect-\(id)",
            file: path,
            visible: true,
            passes: [.init(
                passIndex: 0,
                texturePaths: ["_rt_imageLayerComposite_\(provider)_a"],
                textureSlots: opacity == nil
                    ? [nil, "_rt_imageLayerComposite_\(provider)_a"]
                    : [nil, "_rt_imageLayerComposite_\(provider)_a", nil],
                combos: opacity == nil ? ["BLENDMODE": 5] : [:],
                constantShaderValues: opacity.map {
                    ["Opacity": SceneDocument.ShaderValue(components: [$0])]
                } ?? [:]
            )]
        )
    }

    static func gradientConsumer(
        _ id: Int,
        provider: Int,
        reversed: Bool = false,
        axis: Int = 1
    ) -> SceneRenderDescriptor.Layer {
        let gradient = SceneRenderDescriptor.EffectDescriptor(
            id: "gradient-\(id)",
            file: "effects/workshop/2552475732/gradient_color/effect.json",
            visible: true,
            passes: [.init(
                passIndex: 0,
                textureSlots: [],
                combos: ["AXIS": axis, "BLENDMODE": 0],
                constantShaderValues: [
                    "Amount": .init(components: [1]),
                    "Color 1": .init(components: [1, 0, 0.2]),
                    "Color 2": .init(components: [0, 0, 1]),
                    "Hue Speed": .init(components: [0]),
                    "Opacity": .init(components: [1]),
                    "Oscillate": .init(components: [0]),
                ]
            )]
        )
        let clipping = effect(id: id, provider: provider)
        return .init(
            id: id,
            contentKind: "image",
            utilityLayer: nil,
            dependencyLayerIDs: [provider],
            childLayerIDs: [],
            visible: true,
            effects: reversed ? [clipping, gradient] : [gradient, clipping]
        )
    }

    static func proceduralNoiseEffect(
        id: Int,
        provider: Int,
        effectPath: String = "effects/workshop/2924967132/procedural_noise/effect.json",
        passIndex: Int = 0,
        slotIndex: Int = 3,
        variantSuffix: String = "a",
        extraCombos: [String: Int] = [:],
        extraReference: Bool = false
    ) -> SceneRenderDescriptor.EffectDescriptor {
        let path = "_rt_imageLayerComposite_\(provider)_\(variantSuffix)"
        var slots = Array<String?>(repeating: nil, count: 4)
        slots[slotIndex] = path
        if extraReference {
            slots[1] = "_rt_imageLayerComposite_\(provider)_a"
        }
        var combos = [
            "AB_TYPECOLOR": 3,
            "PERSPSWITCH": 1,
            "WRITEALPHA": 1,
        ]
        combos.merge(extraCombos) { _, new in new }
        return .init(
            id: "\(id)#effect#noise",
            file: effectPath,
            visible: true,
            passes: [.init(
                passIndex: passIndex,
                texturePaths: extraReference
                    ? [path, "_rt_imageLayerComposite_\(provider)_a"] : [path],
                textureSlots: slots,
                combos: combos,
                constantShaderValues: [:]
            )]
        )
    }

    static func proceduralBinding(
        providerVisible: Bool? = false,
        providerContentKind: String = "solid",
        effectPath: String = "effects/workshop/2924967132/procedural_noise/effect.json",
        passIndex: Int = 0,
        slotIndex: Int = 3,
        variantSuffix: String = "a",
        extraCombos: [String: Int] = [:],
        extraReference: Bool = false
    ) -> SceneDependencyRenderPlan.Binding? {
        let providerID = 90
        let consumerID = 91
        let provider = SceneRenderDescriptor.Layer(
            id: providerID,
            contentKind: providerContentKind,
            utilityLayer: nil,
            dependencyLayerIDs: [],
            childLayerIDs: [],
            visible: providerVisible,
            effects: []
        )
        let consumer = SceneRenderDescriptor.Layer(
            id: consumerID,
            contentKind: "composition",
            utilityLayer: .init(kind: .composition),
            dependencyLayerIDs: [providerID],
            childLayerIDs: [],
            visible: true,
            effects: [proceduralNoiseEffect(
                id: consumerID,
                provider: providerID,
                effectPath: effectPath,
                passIndex: passIndex,
                slotIndex: slotIndex,
                variantSuffix: variantSuffix,
                extraCombos: extraCombos,
                extraReference: extraReference
            )]
        )
        let descriptor = SceneRenderDescriptor(
            layers: [provider, consumer],
            renderOrderLayerIDs: [providerID, consumerID]
        )
        return SceneDependencyRenderPlan(
            descriptor: descriptor,
            visibleLayerIDs: [consumerID],
            executableUtilityConsumerLayerIDs: [consumerID]
        ).bindingsByConsumerLayerID[consumerID]
    }
}
'''


class SceneDependencyRenderPlanTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-dependency-plan-")
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = directory / "scene-dependency-plan"
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
        completed = subprocess.run(
            [str(cls.binary)], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_named_reference_variants_are_typed(self) -> None:
        self.assertEqual(self.result["parsedVariants"], ["unspecified", "a", "b"])
        self.assertTrue(self.result["invalidReference"])

    def test_image_and_composition_clipping_consumers_share_backward_binding(self) -> None:
        self.assertEqual(self.result["referenceCount"], 17)
        self.assertEqual(
            self.result["namedConsumers"],
            [2, 6, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 31, 32],
        )
        self.assertEqual(
            self.result["requiredEffectConsumers"],
            [2, 6, 8, 9, 12, 13, 14, 15, 31, 32],
        )
        self.assertEqual(self.result["executableUtilityConsumers"], [15, 31])
        self.assertEqual(
            self.result["bindingConsumers"],
            [2, 8, 9, 12, 13, 14, 15, 31],
        )
        self.assertFalse(self.result["defaultUtilityBinding"])
        self.assertEqual(self.result["requiredProviders"], [1, 30])

    def test_cycle_forward_and_invalid_clipping_contracts_fail_closed(self) -> None:
        self.assertEqual(self.result["cycles"], [4, 5])
        self.assertIn("2:dependencyMismatch:1", self.result["issues"])
        self.assertIn("6:forwardUtilityProvider:7", self.result["issues"])
        self.assertIn("32:missingProvider:999", self.result["issues"])
        self.assertIn("10:unsupportedConsumer:-1", self.result["issues"])
        self.assertNotIn("15:unsupportedConsumer:-1", self.result["issues"])
        self.assertIn("16:unsupportedConsumer:-1", self.result["issues"])
        for layer_id in (17, 18, 19):
            self.assertIn(
                f"{layer_id}:unsupportedConsumer:-1",
                self.result["issues"],
            )

    def test_matrix_shape_keeps_hidden_consumer_out_of_runtime_liveness(self) -> None:
        self.assertEqual(self.result["matrixBindingCount"], 7)
        self.assertEqual(self.result["matrixRequiredProviders"], [10, 11, 12, 13, 14, 15])

    def test_exact_legacy_procedural_dependency_is_typed_and_fail_closed(self) -> None:
        self.assertEqual(
            self.result["legacyNoiseBinding"],
            {
                "consumer": 31,
                "provider": 30,
                "effect": "31#effect#noise",
                "pass": 0,
                "slot": 3,
                "blend": 0,
                "procedural": True,
            },
        )
        self.assertTrue(all(self.result["legacyNoiseRejects"].values()))

if __name__ == "__main__":
    unittest.main()
