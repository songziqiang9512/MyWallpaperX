#!/usr/bin/env python3
"""Project-owned bounded text scripts must stay data-driven and fail closed."""

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
    SOURCE_ROOT / "Format/SceneScriptBindingDefinition.swift",
    SOURCE_ROOT / "Properties/SceneDynamicSnapshot.swift",
    SOURCE_ROOT / "Text/SceneTextScriptDefinition.swift",
    SOURCE_ROOT / "Text/SceneTextScriptSubsetProgram.swift",
    SOURCE_ROOT / "Text/SceneTextScriptSubsetCompiler.swift",
    SOURCE_ROOT / "Text/SceneTextScriptSubsetRuntime.swift",
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
    static func main() throws {
        let clockSource = """
        export function update(previousText) {
            const now = new Date();
            var hours = now.getHours();
            if (!scriptProperties.twentyFourHours) {
                hours %= 12;
                if (hours == 0) {
                    hours = 12;
                }
            }
            hours = ("00" + hours).slice(-2);
            let minutes = ("00" + now.getMinutes()).slice(-2);
            previousText = hours + scriptProperties.separator + minutes;
            if (scriptProperties.includeSeconds) {
                let seconds = ("00" + now.getSeconds()).slice(-2);
                previousText += scriptProperties.separator + seconds;
            }
            return previousText;
        }
        """
        let calendarSource = """
        let monthLabels;
        var separator;

        export function update(originalText) {
            if (scriptProperties.monthMode === 2) {
                return "strict equality must not coerce";
            }
            if (scriptProperties.monthMode == 2) {
                monthLabels = [
                    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
                    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
                ]
            } else if (scriptProperties.monthMode == 1) {
                monthLabels = [
                    "01", "02", "03", "04", "05", "06",
                    "07", "08", "09", "10", "11", "12"
                ]
            } else {
                monthLabels = [
                    "January", "February", "March", "April", "May", "June",
                    "July", "August", "September", "October", "November", "December"
                ]
            }
            if (scriptProperties.useSlash == true) {
                separator = ["/"]
            }
            if (scriptProperties.useSlash == false) {
                separator = ["-"]
            }
            let current = new Date(); {
                var dayNumber = current.getDate();
                if (current.getDate() < 10 && scriptProperties.padDay) {
                    dayNumber = "0" + current.getDate()
                }
                if (scriptProperties.dayFirst) {
                    return dayNumber + separator + monthLabels[current.getMonth()];
                } else if (scriptProperties.dayFirst == false) {
                    return monthLabels[current.getMonth()] + separator + dayNumber;
                }
            }
        }
        """

        let validProgram = SceneTextScriptCompiler.compile(
            descriptor: SceneRenderDescriptor(layers: [
                textLayer(
                    id: 101,
                    text: "fallback-clock-24",
                    source: clockSource,
                    properties: [
                        "separator": .string(":"),
                        "includeSeconds": .object([
                            "user": .string("seconds"),
                            "value": .bool(true),
                        ]),
                        "twentyFourHours": .bool(true),
                    ]
                ),
                textLayer(
                    id: 102,
                    text: "fallback-clock-12",
                    source: clockSource,
                    properties: [
                        "separator": .string(":"),
                        "includeSeconds": .bool(true),
                        "twentyFourHours": .bool(false),
                    ]
                ),
                textLayer(
                    id: 103,
                    text: "fallback-calendar-label",
                    source: calendarSource,
                    properties: calendarProperties(
                        dayFirst: false,
                        monthMode: "2",
                        padDay: true,
                        useSlash: false
                    )
                ),
                textLayer(
                    id: 104,
                    text: "fallback-calendar-numeric",
                    source: calendarSource,
                    properties: calendarProperties(
                        dayFirst: true,
                        monthMode: "1",
                        padDay: true,
                        useSlash: true
                    )
                ),
                textLayer(
                    id: 105,
                    text: "fallback-calendar-unpadded",
                    source: calendarSource,
                    properties: calendarProperties(
                        dayFirst: true,
                        monthMode: "1",
                        padDay: false,
                        useSlash: true
                    )
                ),
            ])
        )
        let fixtureTimeZone = TimeZone(secondsFromGMT: 0)!
        let fixtureDate = utcDate(
            year: 2026,
            month: 7,
            day: 28,
            hour: 23,
            minute: 7,
            second: 5
        )
        let values = SceneTextScriptRuntime.values(
            program: validProgram,
            wallDate: fixtureDate,
            timeZone: fixtureTimeZone
        )
        let earlyMonthValues = SceneTextScriptRuntime.values(
            program: validProgram,
            wallDate: utcDate(
                year: 2026,
                month: 7,
                day: 8,
                hour: 7,
                minute: 0,
                second: 0
            ),
            timeZone: fixtureTimeZone
        )

        guard let priorityDefinition = validProgram.bindings.first(where: {
            $0.layerID == 101
        })?.definition else {
            throw HarnessError.missingPriorityBinding
        }
        let definitions = SceneDynamicDefinitionMerger.merge(
            propertyDefinitions: [priorityDefinition],
            timelineProgram: .init(bindings: [
                .init(definition: priorityDefinition),
            ]),
            textScriptProgram: validProgram,
            additionalDefinitions: [priorityDefinition]
        )
        let priorityTarget = SceneDynamicTarget.text(
            layerID: 101,
            field: .content
        )
        let priorityResolution = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 1,
            generation: 1,
            definitions: definitions,
            userValues: [priorityTarget: .string("user")],
            timelineValues: [priorityTarget: .string("timeline")],
            sceneScriptValues: values
        )
        let authoredResolution = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 2,
            generation: 1,
            definitions: definitions
        )

        let loopSource = """
        export function update(value) {
            while (true) {}
            return value;
        }
        """
        let statementBudgetSource = "export function update(value) {\n"
            + Array(repeating: "value += \"x\";", count: 128)
                .joined(separator: "\n")
            + "\nreturn value;\n}"
        let runtimeBudgetExpression = Array(
            repeating: "\"x\"",
            count: 260
        ).joined(separator: " + ")
        let runtimeBudgetSource = """
        export function update(value) {
            return value + \(runtimeBudgetExpression);
        }
        """
        let comparisonSource = """
        export function update(value) {
            if (new Date().getHours() >= 12) {
                return "late";
            }
            return value;
        }
        """
        let zeroParameterSource = """
        export function update() {
            return "not admitted";
        }
        """
        let sharedParameterSource = """
        export function update(value, sharedState) {
            return sharedState;
        }
        """

        let payload: [String: Any] = [
            "bindingCount": validProgram.bindings.count,
            "diagnosticCount": validProgram.diagnostics.count,
            "clock24": string(values[.text(layerID: 101, field: .content)]),
            "clock12": string(values[.text(layerID: 102, field: .content)]),
            "calendarLabel": string(values[.text(layerID: 103, field: .content)]),
            "calendarNumeric": string(
                earlyMonthValues[.text(layerID: 104, field: .content)]
            ),
            "calendarUnpadded": string(
                earlyMonthValues[.text(layerID: 105, field: .content)]
            ),
            "definitionCount": definitions.count,
            "definitionTargetCount": Set(definitions.map(\.target)).count,
            "priorityValue": string(priorityResolution.snapshot[priorityTarget]?.value),
            "prioritySource": priorityResolution.snapshot[priorityTarget]?.source.rawValue
                ?? "missing",
            "priorityDiagnostics": priorityResolution.diagnostics.count,
            "authoredValue": string(authoredResolution.snapshot[priorityTarget]?.value),
            "authoredSource": authoredResolution.snapshot[priorityTarget]?.source.rawValue
                ?? "missing",
            "rejections": [
                "loop": rejectionEvidence(id: 201, source: loopSource),
                "statementBudget": rejectionEvidence(
                    id: 202,
                    source: statementBudgetSource
                ),
                "comparison": rejectionEvidence(
                    id: 203,
                    source: comparisonSource
                ),
                "zeroParameter": rejectionEvidence(
                    id: 204,
                    source: zeroParameterSource
                ),
                "sharedParameter": rejectionEvidence(
                    id: 205,
                    source: sharedParameterSource
                ),
                "runtimeBudget": rejectionEvidence(
                    id: 206,
                    source: runtimeBudgetSource
                ),
            ],
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }

    static func textLayer(
        id: Int,
        text: String,
        source: String,
        properties: [String: SceneJSONValue] = [:]
    ) -> SceneRenderDescriptor.Layer {
        .init(
            id: id,
            contentKind: "text",
            parentID: nil,
            visible: true,
            text: text,
            textScript: .init(source: source, properties: properties)
        )
    }

    static func calendarProperties(
        dayFirst: Bool,
        monthMode: String,
        padDay: Bool,
        useSlash: Bool
    ) -> [String: SceneJSONValue] {
        [
            "dayFirst": .bool(dayFirst),
            "monthMode": .string(monthMode),
            "padDay": .bool(padDay),
            "useSlash": .bool(useSlash),
        ]
    }

    static func rejectionEvidence(
        id: Int,
        source: String
    ) -> [String: Any] {
        let authoredText = "fallback-\(id)"
        let target = SceneDynamicTarget.text(layerID: id, field: .content)
        let program = SceneTextScriptCompiler.compile(
            descriptor: .init(layers: [
                textLayer(id: id, text: authoredText, source: source),
            ])
        )
        let runtimeValues = SceneTextScriptRuntime.values(
            program: program,
            wallDate: utcDate(
                year: 2026,
                month: 7,
                day: 28,
                hour: 23,
                minute: 7,
                second: 5
            ),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        let authoredDefinition = SceneDynamicTargetDefinition(
            target: target,
            valueType: .string,
            authoredValue: .string(authoredText)
        )
        let resolution = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 3,
            generation: 1,
            definitions: [authoredDefinition],
            sceneScriptValues: runtimeValues
        )
        return [
            "bindingCount": program.bindings.count,
            "diagnostics": program.diagnostics.map { $0.code.rawValue },
            "runtimeValue": string(runtimeValues[target]),
            "authoredFallback": authoredText,
            "resolved": string(resolution.snapshot[target]?.value),
            "source": resolution.snapshot[target]?.source.rawValue ?? "missing",
            "resolutionDiagnostics": resolution.diagnostics.count,
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

    enum HarnessError: Error {
        case missingPriorityBinding
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

    def test_project_owned_subset_clock_and_calendar_execute(self) -> None:
        self.assertEqual(self.payload["bindingCount"], 5)
        self.assertEqual(self.payload["diagnosticCount"], 0)
        self.assertEqual(self.payload["clock24"], "23:07:05")
        self.assertEqual(self.payload["clock12"], "11:07:05")
        self.assertEqual(self.payload["calendarLabel"], "Jul-28")
        self.assertEqual(self.payload["calendarNumeric"], "08/07")
        self.assertEqual(self.payload["calendarUnpadded"], "8/07")

    def test_scene_script_priority_and_definition_deduplication(self) -> None:
        self.assertEqual(self.payload["definitionCount"], 5)
        self.assertEqual(self.payload["definitionTargetCount"], 5)
        self.assertEqual(self.payload["priorityValue"], "23:07:05")
        self.assertEqual(self.payload["prioritySource"], "sceneScript")
        self.assertEqual(self.payload["priorityDiagnostics"], 0)
        self.assertEqual(self.payload["authoredValue"], "fallback-clock-24")
        self.assertEqual(self.payload["authoredSource"], "authored")

    def test_loop_and_statement_budget_fail_closed(self) -> None:
        self.assert_compile_rejected("loop")
        self.assert_compile_rejected("statementBudget")

    def test_unadmitted_comparison_and_update_signatures_fail_closed(self) -> None:
        self.assert_compile_rejected("comparison")
        self.assert_compile_rejected("zeroParameter")
        self.assert_compile_rejected("sharedParameter")

    def test_runtime_step_budget_preserves_authored_fallback(self) -> None:
        evidence = self.payload["rejections"]["runtimeBudget"]
        self.assertEqual(evidence["bindingCount"], 1, evidence)
        self.assertEqual(evidence["diagnostics"], [], evidence)
        self.assertEqual(evidence["runtimeValue"], "missing", evidence)
        self.assertEqual(evidence["resolved"], evidence["authoredFallback"], evidence)
        self.assertEqual(evidence["source"], "authored", evidence)
        self.assertEqual(evidence["resolutionDiagnostics"], 0, evidence)

    def assert_compile_rejected(self, key: str) -> None:
        evidence = self.payload["rejections"][key]
        self.assertEqual(evidence["bindingCount"], 0, evidence)
        self.assertEqual(evidence["diagnostics"], ["unknownProfile"], evidence)
        self.assertEqual(evidence["runtimeValue"], "missing", evidence)
        self.assertEqual(evidence["resolved"], evidence["authoredFallback"], evidence)
        self.assertEqual(evidence["source"], "authored", evidence)
        self.assertEqual(evidence["resolutionDiagnostics"], 0, evidence)


if __name__ == "__main__":
    unittest.main()
