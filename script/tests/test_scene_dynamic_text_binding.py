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
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneUserProperty.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneScriptDynamicProviderHostContract.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneUserPropertyBindings.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneDynamicSnapshot.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/ScenePuppetAnimationPropertyTarget.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/ScenePropertyBindingProgram.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/ScenePropertyBindingCompiler+TargetMapping.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/ScenePropertyBindingProgramValidator.swift",
]

HARNESS = r'''
import Foundation

@main
enum Harness {
    static func main() throws {
        let bindings: [SceneUserPropertyBinding] = [
            binding("caption", .string("作者文字"), .content),
            binding("size", .number(12), .pointSize),
            binding("tint", .string("1 0.5 0.25"), .color),
        ]
        let catalog = SceneUserPropertyCatalog(definitions: [
            property("caption", .textInput, .string("默认文字")),
            property("size", .slider, .number(8)),
            property("tint", .color, .string("1 1 1")),
        ])
        let compilation = ScenePropertyBindingCompiler().compile(
            report: .init(bindings: bindings, diagnostics: []),
            catalog: catalog
        )
        let evaluation = compilation.program.evaluate(effectiveValues: [
            "caption": .string("第一行\n第二行"),
            "size": .number(24),
            "tint": .string("0.2 0.4 0.6"),
        ])
        let snapshot = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 1,
            generation: 7,
            definitions: compilation.program.definitions,
            userValues: evaluation.userValues
        ).snapshot
        let targets: [SceneDynamicTarget] = [
            .text(layerID: 42, field: .content),
            .text(layerID: 42, field: .pointSize),
            .text(layerID: 42, field: .color),
        ]
        let wrongKind = ScenePropertyBindingCompiler().compile(
            report: .init(bindings: [binding("caption", .string("x"), .content)], diagnostics: []),
            catalog: .init(definitions: [property("caption", .text, .string("x"))])
        )
        let conditional = ScenePropertyBindingCompiler().compile(
            report: .init(bindings: [binding(
                "caption", .string("x"), .content, condition: .bool(true)
            )], diagnostics: []),
            catalog: catalog
        )
        let hostShapes: [(String, SceneScriptDynamicProviderHostContract.HostKind, [String])] = [
            ("objectText/script+value", .objectText, ["script", "value"]),
            ("objectText/script+user+value", .objectText, ["script", "user", "value"]),
            ("objectText/script+scriptproperties+value", .objectText,
                ["script", "scriptproperties", "value"]),
            ("objectText/script+scriptproperties+user+value", .objectText,
                ["script", "scriptproperties", "user", "value"]),
            ("objectText/animation+script+value", .objectText,
                ["animation", "script", "value"]),
            ("objectText/script+scriptproperties", .objectText,
                ["script", "scriptproperties"]),
            ("objectVector/script+scriptproperties+user+value", .objectVector,
                ["script", "scriptproperties", "user", "value"]),
            ("objectVector/script+scriptproperties+value", .objectVector,
                ["script", "scriptproperties", "value"]),
            ("objectScalar/script+scriptproperties+user+value", .objectScalar,
                ["script", "scriptproperties", "user", "value"]),
            ("objectScalar/script+scriptproperties+value", .objectScalar,
                ["script", "scriptproperties", "value"]),
        ]
        let hostShapeSupport = Dictionary(uniqueKeysWithValues: hostShapes.map {
            ($0.0, SceneScriptDynamicProviderHostContract.supports(keys: $0.2, host: $0.1))
        })
        let textScript = "export function update(value) { return value; }"
        let fourKeyWrapper: [String: Any] = [
            "script": textScript,
            "scriptproperties": ["flag": true],
            "user": "probe_format",
            "value": "clock",
        ]
        var nullUserWrapper = fourKeyWrapper
        nullUserWrapper["user"] = NSNull()
        let wrapperShapes: [(String, [String: Any], SceneScriptDynamicProviderHostContract.HostKind)] = [
            ("objectText/4keys+string-user", fourKeyWrapper, .objectText),
            ("objectText/4keys+null-user", nullUserWrapper, .objectText),
            ("objectVisibility/4keys+string-user", fourKeyWrapper, .objectVisibility),
            ("objectVector/4keys+string-user", fourKeyWrapper, .objectVector),
            ("objectScalar/4keys+string-user", fourKeyWrapper, .objectScalar),
            ("objectText/3keys+string-user", [
                "script": textScript,
                "user": "probe_format",
                "value": "clock",
            ], .objectText),
        ]
        let wrapperShapeSupport = Dictionary(uniqueKeysWithValues: wrapperShapes.map {
            ($0.0, SceneScriptDynamicProviderHostContract.supports($0.1, host: $0.2))
        })
        func parsedTargets(_ object: [String: Any]) -> [String] {
            SceneUserPropertyBindingParser()
                .parse(root: ["objects": [object]])
                .bindings.map { String(describing: $0.target) }
        }
        let scriptPropertyTargets = parsedTargets([
            "id": 7,
            "text": [
                "script": textScript,
                "scriptproperties": [
                    "use24hFormat": ["user": "probe_format", "value": true],
                ],
                "value": "clock",
            ],
        ])
        let directTextTargets = parsedTargets([
            "id": 9,
            "text": ["user": "probe_caption", "value": "clock"],
        ])
        let scriptlessScriptPropertyTargets = parsedTargets([
            "id": 11,
            "text": [
                "scriptproperties": [
                    "use24hFormat": ["user": "probe_format", "value": true],
                ],
                "value": "clock",
            ],
        ])
        let payload: [String: Any] = [
            "targets": compilation.program.instructions.map { String(describing: $0.target) },
            "types": compilation.program.instructions.map { $0.valueType.rawValue },
            "rebuild": compilation.program.rebuildRequiredPropertyKeys,
            "diagnostics": compilation.diagnostics.map { $0.code.rawValue },
            "values": targets.map { snapshot[$0].map { String(describing: $0.value) } ?? "missing" },
            "sources": targets.map { snapshot[$0]?.source.rawValue ?? "missing" },
            "runtimeDiagnostics": evaluation.diagnostics.map { $0.code.rawValue },
            "wrongKindCount": wrongKind.program.instructions.count,
            "wrongKindCodes": wrongKind.diagnostics.map { $0.code.rawValue },
            "conditionalCount": conditional.program.instructions.count,
            "conditionalCodes": conditional.diagnostics.map { $0.code.rawValue },
            "hostShapeSupport": hostShapeSupport,
            "wrapperShapeSupport": wrapperShapeSupport,
            "scriptPropertyTargets": scriptPropertyTargets,
            "directTextTargets": directTextTargets,
            "scriptlessScriptPropertyTargets": scriptlessScriptPropertyTargets,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func binding(
        _ key: String,
        _ fallback: SceneUserPropertyValue,
        _ field: SceneUserPropertyBindingTarget.TextField,
        condition: SceneUserPropertyValue? = nil
    ) -> SceneUserPropertyBinding {
        .init(
            reference: .init(key: key, condition: condition),
            fallbackValue: fallback,
            path: .init(components: [.key("objects"), .index(0), .key(field.rawValue)]),
            target: .text(layerID: 42, field: field)
        )
    }

    static func property(
        _ key: String,
        _ kind: SceneUserPropertyKind,
        _ value: SceneUserPropertyValue
    ) -> SceneUserPropertyDefinition {
        .init(
            key: key, title: key, kind: kind, runtimeType: kind.rawValue,
            order: 0, index: nil, minimumValue: nil, maximumValue: nil,
            stepValue: nil, allowsFractionalValues: true, fractionalPrecision: nil,
            displayCondition: nil, defaultValue: value, options: []
        )
    }
}
'''


class SceneDynamicTextBindingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-dynamic-text-")
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = directory / "dynamic-text-binding"
        compilation = subprocess.run(
            ["swiftc", *(str(path) for path in SWIFT_SOURCES), str(harness), "-o", str(binary)],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        cls.result = json.loads(subprocess.run(
            [str(binary)], check=True, capture_output=True, text=True
        ).stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_direct_text_fields_compile_and_evaluate_without_rebuild(self) -> None:
        self.assertEqual(self.result["types"], ["vector3", "string", "scalar"])
        self.assertEqual(self.result["rebuild"], [])
        self.assertEqual(self.result["diagnostics"], [])
        self.assertEqual(
            sorted(self.result["values"]),
            sorted(['string("第一行\\n第二行")', "scalar(24.0)", "vector3(0.2, 0.4, 0.6)"]),
        )
        self.assertEqual(self.result["sources"], ["userProperty"] * 3)
        self.assertEqual(self.result["runtimeDiagnostics"], [])

    def test_static_text_label_kind_and_conditional_text_stay_fail_closed(self) -> None:
        self.assertEqual(self.result["wrongKindCount"], 0)
        self.assertEqual(self.result["wrongKindCodes"], ["propertyKindMismatch"])
        self.assertEqual(self.result["conditionalCount"], 0)
        self.assertIn("conditionalBinding", self.result["conditionalCodes"])

    def test_text_host_accepts_scripted_and_property_bound_wrappers(self) -> None:
        support = self.result["hostShapeSupport"]
        for admitted in (
            "objectText/script+value",
            "objectText/script+user+value",
            "objectText/script+scriptproperties+value",
            "objectText/script+scriptproperties+user+value",
            "objectVector/script+scriptproperties+user+value",
            "objectVector/script+scriptproperties+value",
            "objectScalar/script+scriptproperties+value",
        ):
            self.assertTrue(support[admitted], f"{admitted} must be admitted")
        for rejected in (
            "objectText/animation+script+value",
            "objectText/script+scriptproperties",
            "objectScalar/script+scriptproperties+user+value",
        ):
            self.assertFalse(support[rejected], f"{rejected} must stay rejected")

    def test_wrapper_level_host_contract_gates_the_string_user_key(self) -> None:
        support = self.result["wrapperShapeSupport"]
        self.assertTrue(support["objectText/4keys+string-user"])
        self.assertTrue(support["objectText/4keys+null-user"])
        self.assertTrue(support["objectVisibility/4keys+string-user"])
        self.assertTrue(support["objectText/3keys+string-user"])
        self.assertFalse(support["objectVector/4keys+string-user"])
        self.assertFalse(support["objectScalar/4keys+string-user"])

    def test_text_script_properties_route_and_direct_text_still_works(self) -> None:
        script_property = self.result["scriptPropertyTargets"]
        self.assertEqual(len(script_property), 1)
        self.assertIn("scriptProperty(layerID: 7", script_property[0])
        self.assertIn("scriptproperties", script_property[0])
        self.assertIn("use24hFormat", script_property[0])

        direct = self.result["directTextTargets"]
        self.assertEqual(len(direct), 1)
        self.assertIn("text(layerID: 9", direct[0])
        self.assertIn("content", direct[0])

        scriptless = self.result["scriptlessScriptPropertyTargets"]
        self.assertEqual(len(scriptless), 1)
        self.assertIn("unsupported", scriptless[0])


if __name__ == "__main__":
    unittest.main()
