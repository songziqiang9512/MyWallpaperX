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
    SOURCE_ROOT / "Properties/SceneUserProperty.swift",
    SOURCE_ROOT / "Properties/SceneUserPropertyBindings.swift",
    SOURCE_ROOT / "Properties/SceneDynamicSnapshot.swift",
    SOURCE_ROOT / "Properties/ScenePropertyBindingProgram.swift",
    SOURCE_ROOT / "Properties/ScenePropertyBindingCompiler+TargetMapping.swift",
    SOURCE_ROOT / "Properties/ScenePropertyBindingProgramValidator.swift",
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


if __name__ == "__main__":
    unittest.main()
