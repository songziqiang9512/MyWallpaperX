#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
WEB_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Modules/SteamWorkshop/Web/Core"
SWIFT_SOURCES = [
    WEB_ROOT / "SteamWorkshopWebPropertyModels.swift",
    WEB_ROOT / "SteamWorkshopService+WebDisplayConditionParsing.swift",
    WEB_ROOT / "SteamWorkshopService+WebDisplayConditionSupport.swift",
]

HARNESS_SOURCE = r'''
import Foundation

final class SteamWorkshopService {}

@main
enum Harness {
    static func main() throws {
        let definitions = [
            SteamWorkshopWebPropertyDefinition(
                key: "mode",
                title: "Mode",
                kind: .combo,
                runtimeType: "combo",
                order: 0,
                minimumValue: nil,
                maximumValue: nil,
                allowsFractionalValues: false,
                fractionalPrecision: nil,
                displayCondition: nil,
                directoryMode: nil,
                fileType: nil,
                defaultValue: .string("1"),
                options: [
                    .init(label: "Automatic", value: .string("1"), displayCondition: "enabled.value == false"),
                    .init(label: "Custom", value: .string("2"), displayCondition: nil),
                ]
            )
        ]
        let values: [String: SteamWorkshopWebPropertyValue] = [
            "mode": .string("1"),
            "enabled": .bool(true),
            "amount": .number(10),
        ]
        let conditions = [
            "singleDigitFalse": "mode.value ==2",
            "singleDigitTrue": "mode.value ==1",
            "multiDigitTrue": "amount.value ==10",
            "negativeTrue": "amount.value > -0.5",
            "logicalTrue": "enabled.value && mode.value !=2",
            "comboTextTrue": "mode.text == 'Automatic'",
        ]
        var result = conditions.mapValues {
            SteamWorkshopService.evaluateWebDisplayCondition(
                $0,
                values: values,
                definitions: definitions
            )
        }
        let prepared = SteamWorkshopService.WebDisplayConditionInputs(
            values: values, definitions: definitions
        )
        result["preparedMatchesLegacy"] = conditions.mapValues {
            SteamWorkshopService.evaluateWebDisplayCondition($0, inputs: prepared)
        } == result
        result["hiddenSelectedOptionKeepsText"] = prepared.comboTextValues["mode"] == "Automatic"

        var edited = values
        edited["mode"] = .string("2")
        let updated = SteamWorkshopService.WebDisplayConditionInputs(
            values: edited, definitions: definitions
        )
        result["currentValueUpdatesText"] = SteamWorkshopService.evaluateWebDisplayCondition(
            "mode.text == 'Custom'", inputs: updated
        ) && !SteamWorkshopService.evaluateWebDisplayCondition("mode.text == 'Automatic'", inputs: updated)
        result["previousInputRemainsImmutable"] = SteamWorkshopService.evaluateWebDisplayCondition(
            "mode.text == 'Automatic'", inputs: prepared
        )
        let restored = SteamWorkshopService.WebDisplayConditionInputs(
            values: values, definitions: definitions
        )
        result["restoredDefaultUpdatesText"] = SteamWorkshopService.evaluateWebDisplayCondition(
            "mode.text == 'Automatic'", inputs: restored
        )

        edited.removeValue(forKey: "mode")
        let absent = SteamWorkshopService.WebDisplayConditionInputs(values: edited, definitions: definitions)
        result["absentCurrentKeepsUndefined"] = absent.comboTextValues["mode"] == "Automatic"
            && !SteamWorkshopService.evaluateWebDisplayCondition("mode.text == 'Automatic'", inputs: absent)
            && !SteamWorkshopService.evaluateWebDisplayCondition(
                "mode.text == 'Automatic'", values: edited, definitions: definitions
            )
        edited["mode"] = .string("unmatched")
        let unmatched = SteamWorkshopService.WebDisplayConditionInputs(values: edited, definitions: definitions)
        result["unmatchedOptionUsesCurrentText"] = unmatched.comboTextValues["mode"] == nil
            && SteamWorkshopService.evaluateWebDisplayCondition("mode.text == 'unmatched'", inputs: unmatched)
            && !SteamWorkshopService.evaluateWebDisplayCondition("mode.text == 'Automatic'", inputs: unmatched)

        let fallbacks = ["", "  ", "enabled.value ? true : false", "amount.value * 2", "(enabled.value", "amount.value >"]
        result["unsupportedAndMalformedFallbackParity"] = fallbacks.allSatisfy {
            SteamWorkshopService.evaluateWebDisplayCondition($0, inputs: prepared)
                && SteamWorkshopService.evaluateWebDisplayCondition($0, values: values, definitions: definitions)
        }
        let renamedDefinition = SteamWorkshopWebPropertyDefinition(
            key: "configuration", title: "Renamed", kind: .combo, runtimeType: "combo", order: 0,
            minimumValue: nil, maximumValue: nil, allowsFractionalValues: false, fractionalPrecision: nil,
            displayCondition: nil, directoryMode: nil, fileType: nil, defaultValue: .string("automatic"),
            options: [.init(label: "Renamed Automatic", value: .string("automatic"), displayCondition: nil)]
        )
        let renamed = SteamWorkshopService.WebDisplayConditionInputs(
            values: ["configuration": .string("automatic")], definitions: [renamedDefinition]
        )
        result["renamedKeyAndOptionKeepsSemantics"] = SteamWorkshopService.evaluateWebDisplayCondition(
            "configuration.value == 'automatic' && configuration.text == 'Renamed Automatic'", inputs: renamed
        ) && !SteamWorkshopService.evaluateWebDisplayCondition("mode.text == 'Automatic'", inputs: renamed)
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''

SCENE_PROJECTION_HARNESS = r'''
import Foundation

@MainActor final class SteamWorkshopService {}

@main enum SceneProjectionProbe {
    @MainActor static func main() throws {
        let service = SteamWorkshopService()
        var facts: [String: Bool] = [:]
        for (ordinal, modeKey) in ["mode", "renamed_selection"].enumerated() {
            let advancedValue = ordinal == 0 ? "advanced" : "alternate"
            let textCondition = ordinal == 0
                ? "\(modeKey).text == 'Advanced' && policy.value"
                : "policy.value && ('Advanced' == \(modeKey).text)"
            let catalog = SceneUserPropertyDefinitionParser().parse(properties: [
                "group": ["type": "group", "text": "Controls", "order": 0],
                "enabled": ["type": "bool", "value": true, "order": 1],
                modeKey: ["type": "combo", "value": "basic", "order": 2,
                    "condition": "enabled.value == false", "options": [
                        ["value": "basic", "label": "Basic"],
                        ["value": advancedValue, "label": "Advanced", "condition": "enabled.value == false"]
                    ]],
                "empty_mode": ["type": "combo", "order": 3,
                    "options": [["value": "", "label": "Empty"]]],
                "policy": ["type": "usershortcut", "value": true, "order": 4],
                "amount": ["type": "slider", "value": 1.0, "condition": textCondition, "order": 5],
                "choices": ["type": "combo", "value": "main", "order": 6, "options": [
                    ["value": "main", "label": "Main"],
                    ["value": "detail", "label": "Detail", "condition": "\(modeKey).text == 'Advanced'"]
                ]],
                "unsupported": ["type": "slider", "value": 1.0,
                    "condition": "enabled.value ? true : false", "order": 7],
                "malformed": ["type": "slider", "value": 1.0, "condition": "(enabled.value", "order": 8],
                "unknown": ["type": "slider", "value": 1.0, "condition": "missing.value", "order": 9]
            ])
            let actionable: Set<String> = ["amount", "choices", "unsupported", "malformed", "unknown"]
            let context = SteamWorkshopScenePropertyContext(
                catalog: catalog, actionableKeys: actionable, effectiveValues: catalog.defaultValues
            )
            let byKey = Dictionary(uniqueKeysWithValues: catalog.definitions.map { ($0.key, $0) })
            let initial = context.conditionInputs(values: catalog.defaultValues)
            var values = catalog.defaultValues
            values[modeKey] = .string(advancedValue)
            let edited = context.conditionInputs(values: values)
            let prefix = "variant\(ordinal)-"
            facts[prefix + "rowsPreserved"] = context.definitions.map(\.key)
                == ["group", "amount", "choices", "unsupported", "malformed", "unknown"]
            facts[prefix + "fullCatalogValues"] = initial.values["enabled"] == .bool(true)
                && initial.values["policy"] == .bool(true)
                && !context.definitions.contains { $0.key == modeKey || $0.key == "policy" }
            facts[prefix + "hiddenComboText"] = edited.comboTextValues[modeKey] == "Advanced"
                && service.shouldDisplaySceneProperty(byKey["amount"]!, inputs: edited)
            facts[prefix + "initialAndCurrentValues"] = !service.shouldDisplaySceneProperty(
                byKey["amount"]!, inputs: initial
            ) && initial.comboTextValues[modeKey] == "Basic"
                && service.shouldDisplaySceneProperty(byKey["amount"]!, inputs: edited)
            facts[prefix + "optionConditionsShareCurrentInput"] = service.visibleScenePropertyOptions(
                for: byKey["choices"]!, inputs: edited
            ).map(\.value) == [.string("main"), .string("detail")]
                && service.visibleScenePropertyOptions(for: byKey["choices"]!, inputs: initial)
                    .map(\.value) == [.string("main")]
            let restored = context.conditionInputs(values: catalog.defaultValues)
            facts[prefix + "resetDefaultInput"] = !service.shouldDisplaySceneProperty(
                byKey["amount"]!, inputs: restored
            ) && service.visibleScenePropertyOptions(for: byKey["choices"]!, inputs: restored)
                .map(\.value) == [.string("main")]
            values.removeValue(forKey: modeKey)
            let absent = context.conditionInputs(values: values)
            facts[prefix + "missingCurrentStaysUndefined"] = absent.comboTextValues[modeKey] == "Basic"
                && !service.shouldDisplaySceneProperty(byKey["amount"]!, inputs: absent)
            facts[prefix + "missingDefaultKeepsEmptyProjection"] = initial.comboTextValues["empty_mode"] == "Empty"
                && initial.values["empty_mode"] == nil
            facts[prefix + "fallbackAndAdjacentNegative"] = service.shouldDisplaySceneProperty(
                byKey["unsupported"]!, inputs: initial
            ) && service.shouldDisplaySceneProperty(byKey["malformed"]!, inputs: initial)
                && !service.shouldDisplaySceneProperty(byKey["unknown"]!, inputs: initial)
        }
        print(String(data: try JSONSerialization.data(withJSONObject: facts, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
'''


class WebDisplayConditionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-web-condition-")
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = directory / "web-condition"
        subprocess.run(
            [swiftc, *(str(path) for path in SWIFT_SOURCES), str(harness), "-o", str(cls.binary)],
            check=True,
            capture_output=True,
            text=True,
        )

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_numeric_boolean_and_combo_conditions(self) -> None:
        completed = subprocess.run(
            [str(self.binary)],
            check=True,
            capture_output=True,
            text=True,
        )
        result = json.loads(completed.stdout)
        self.assertFalse(result["singleDigitFalse"])
        self.assertTrue(result["singleDigitTrue"])
        self.assertTrue(result["multiDigitTrue"])
        self.assertTrue(result["negativeTrue"])
        self.assertTrue(result["logicalTrue"])
        self.assertTrue(result["comboTextTrue"])

    def test_prepared_inputs_preserve_current_default_option_and_failure_semantics(self) -> None:
        completed = subprocess.run(
            [str(self.binary)], check=True, capture_output=True, text=True,
        )
        result = json.loads(completed.stdout)
        for name in [
            "preparedMatchesLegacy", "hiddenSelectedOptionKeepsText", "currentValueUpdatesText",
            "previousInputRemainsImmutable", "restoredDefaultUpdatesText", "absentCurrentKeepsUndefined",
            "unmatchedOptionUsesCurrentText", "unsupportedAndMalformedFallbackParity",
            "renamedKeyAndOptionKeepsSemantics",
        ]:
            with self.subTest(name=name):
                self.assertTrue(result[name])


class SceneDisplayConditionProjectionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        from script.tests.test_scene_property_live_routing import method_body

        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-condition-")
        directory = Path(cls.temporary_directory.name)
        scene = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties"
        source = (REPOSITORY_ROOT / "MyWallpaperX/Modules/SteamWorkshop/Scene/SteamWorkshopSceneService+SceneProperties.swift").read_text()
        bridge = directory / "SceneConditions.swift"
        bridge.write_text(
            "import Foundation\n" + method_body(source, "struct SteamWorkshopScenePropertyContext {")
            + "\nextension SteamWorkshopService {\n"
            + "\n".join(method_body(source, signature) for signature in [
                "func shouldDisplaySceneProperty(", "func visibleScenePropertyOptions(",
            ]) + "\n}\n"
        )
        harness = directory / "Harness.swift"
        harness.write_text(SCENE_PROJECTION_HARNESS)
        cls.binary = directory / "scene-condition"
        subprocess.run(
            [swiftc, *map(str, SWIFT_SOURCES), str(scene / "SceneUserProperty.swift"),
             str(scene / "SceneUserPropertyDefinitionParser.swift"), str(bridge), str(harness),
             "-module-cache-path", str(directory / "cache"), "-o", str(cls.binary)],
            check=True, capture_output=True, text=True,
        )

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_scene_context_preserves_full_catalog_current_reset_and_option_semantics(self) -> None:
        result = subprocess.run([str(self.binary)], check=True, capture_output=True, text=True)
        facts = json.loads(result.stdout)
        self.assertEqual(len(facts), 18)
        self.assertTrue(all(facts.values()), {key: value for key, value in facts.items() if not value})


if __name__ == "__main__":
    unittest.main()
