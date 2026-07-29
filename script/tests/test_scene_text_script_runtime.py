#!/usr/bin/env python3
"""Verified text-script profiles must feed live text through the dynamic snapshot."""

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
    SOURCE_ROOT / "Properties/SceneDynamicSnapshot.swift",
    SOURCE_ROOT / "Text/SceneTextScriptDefinition.swift",
    SOURCE_ROOT / "Text/SceneTextScriptProgram.swift",
    SOURCE_ROOT / "Text/SceneTextScriptCompiler.swift",
    SOURCE_ROOT / "Text/SceneTextScriptRuntime.swift",
    SOURCE_ROOT / "Properties/SceneDynamicDefinitionMerger.swift",
    SOURCE_ROOT / "Rendering/SceneLayerVisibility.swift",
]

HARNESS = r'''
import Foundation

struct SceneRenderDescriptor {
    struct Layer {
        let id: Int
        let contentKind: String
        let parentID: Int?
        let visible: Bool?
        let text: String?
        let textScript: SceneTextScriptDefinition?
    }
    let layers: [Layer]
}

struct SceneTimelineBinding {
    let definition: SceneDynamicTargetDefinition
}

struct SceneTimelineProgram {
    let bindings: [SceneTimelineBinding]
}

@main
enum Harness {
    static let clockHash =
        "ebf5e5f476ec0a0e35c9dd5c77a9691e23468d24b58a465488157c9e026e4912"
    static let spacedDayHash =
        "dca4b368c3630dec922fd4015afec4962069827b2d45d18af83ff3ab80608f67"
    static let dateHash =
        "2bca0f3a950267440fe733611caee5481f7d60617b318a78ffd60235e29ce1bb"

    static func main() throws {
        let parsed = SceneTextScriptDefinition.parse([
            "value": "fallback",
            "script": "unknown source",
            "scriptproperties": [
                "delimiter": ["user": "separator", "value": ":"],
                "showSeconds": false,
                "use24hFormat": true,
            ],
        ])
        let clock = SceneTextScriptCompiler.compileVerifiedProfile(
            layerID: 68,
            authoredText: "12:34",
            sourceSHA256: clockHash,
            properties: parsed!.properties
        )
        let clock12 = SceneTextScriptCompiler.compileVerifiedProfile(
            layerID: 69,
            authoredText: "12:34",
            sourceSHA256: clockHash,
            properties: [
                "delimiter": .string(":"),
                "showSeconds": .bool(true),
                "use24hFormat": .bool(false),
            ]
        )
        let spacedDay = SceneTextScriptCompiler.compileVerifiedProfile(
            layerID: 76,
            authoredText: "DAY",
            sourceSHA256: spacedDayHash,
            properties: dateProperties(showDay: true, month: "1", day: "2", delimiter: "/")
        )
        let date = SceneTextScriptCompiler.compileVerifiedProfile(
            layerID: 82,
            authoredText: "<Date>",
            sourceSHA256: dateHash,
            properties: dateProperties(showDay: false, month: "2", day: "2", delimiter: "")
        )
        let invalid = SceneTextScriptCompiler.compileVerifiedProfile(
            layerID: 90,
            authoredText: "fallback",
            sourceSHA256: clockHash,
            properties: [
                "delimiter": .string(":"),
                "showSeconds": .bool(false),
                "use24hFormat": .bool(true),
                "unexpected": .bool(true),
            ]
        )
        let unknown = SceneTextScriptCompiler.compileVerifiedProfile(
            layerID: 91,
            authoredText: "fallback",
            sourceSHA256: String(repeating: "0", count: 64),
            properties: [:]
        )
        let directUnknown = SceneTextScriptCompiler.compile(descriptor: .init(layers: [
            .init(
                id: 92,
                contentKind: "text",
                parentID: nil,
                visible: true,
                text: "fallback",
                textScript: parsed
            ),
            .init(
                id: 93,
                contentKind: "text",
                parentID: nil,
                visible: false,
                text: "hidden",
                textScript: parsed
            ),
        ]))

        let program = SceneTextScriptProgram(
            bindings: clock.bindings + clock12.bindings + spacedDay.bindings + date.bindings,
            diagnostics: []
        )
        let values = SceneTextScriptRuntime.values(
            program: program,
            wallDate: utcDate(year: 2026, month: 7, day: 28, hour: 23, minute: 7, second: 5),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        let definitions = SceneDynamicDefinitionMerger.merge(
            propertyDefinitions: [clock.bindings[0].definition],
            timelineProgram: .init(bindings: [
                .init(definition: clock.bindings[0].definition),
            ]),
            textScriptProgram: program
        )
        let target = SceneDynamicTarget.text(layerID: 68, field: .content)
        let snapshot = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 1,
            generation: 1,
            definitions: definitions,
            userValues: [target: .string("user")],
            timelineValues: [target: .string("timeline")],
            sceneScriptValues: values
        )

        let payload: [String: Any] = [
            "parsedSource": parsed?.source ?? "missing",
            "bindingCount": program.bindings.count,
            "clock": string(values[.text(layerID: 68, field: .content)]),
            "clock12": string(values[.text(layerID: 69, field: .content)]),
            "day": string(values[.text(layerID: 76, field: .content)]),
            "date": string(values[.text(layerID: 82, field: .content)]),
            "invalid": invalid.diagnostics.map { $0.code.rawValue },
            "unknown": unknown.diagnostics.map { $0.code.rawValue },
            "directUnknown": directUnknown.diagnostics.map { "\($0.layerID):\($0.code.rawValue)" },
            "definitionCount": definitions.count,
            "resolved": snapshot.snapshot[target].map { string($0.value) } ?? "missing",
            "source": snapshot.snapshot[target]?.source.rawValue ?? "missing",
            "runtimeDiagnostics": snapshot.diagnostics.count,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func dateProperties(
        showDay: Bool,
        month: String,
        day: String,
        delimiter: String
    ) -> [String: SceneJSONValue] {
        [
            "monthFormat": .string(month),
            "dayFormat": .string(day),
            "showDay": .bool(showDay),
            "alignVertical": .bool(false),
            "useDelimiter": .bool(true),
            "addDelimiter": .string(delimiter),
        ]
    }

    static func utcDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        second: Int
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: .init(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        ))!
    }

    static func string(_ value: SceneDynamicValue?) -> String {
        guard case let .string(value) = value else { return "missing" }
        return value
    }
}
'''


class SceneTextScriptRuntimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-text-script-")
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = directory / "text-script-runtime"
        compilation = subprocess.run(
            ["swiftc", *(str(path) for path in SWIFT_SOURCES), str(harness), "-o", str(binary)],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        execution = subprocess.run([str(binary)], capture_output=True, text=True, check=True)
        cls.payload = json.loads(execution.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_verified_profiles_produce_expected_local_calendar_text(self) -> None:
        self.assertEqual(self.payload["bindingCount"], 4)
        self.assertEqual(self.payload["clock"], "-23:07-")
        self.assertEqual(self.payload["clock12"], "-11:07-:05")
        self.assertEqual(self.payload["day"], "T U E S D A Y")
        self.assertEqual(self.payload["date"], "28 JUL 2026")

    def test_source_and_complete_property_shape_fail_closed(self) -> None:
        self.assertEqual(self.payload["parsedSource"], "unknown source")
        self.assertEqual(self.payload["invalid"], ["invalidProperties"])
        self.assertEqual(self.payload["unknown"], ["unknownProfile"])
        self.assertEqual(self.payload["directUnknown"], ["92:unknownProfile"])

    def test_scene_script_value_wins_without_duplicate_definition(self) -> None:
        self.assertEqual(self.payload["definitionCount"], 4)
        self.assertEqual(self.payload["resolved"], "-23:07-")
        self.assertEqual(self.payload["source"], "sceneScript")
        self.assertEqual(self.payload["runtimeDiagnostics"], 0)


if __name__ == "__main__":
    unittest.main()
