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
    SOURCE_ROOT / "Format/SceneScriptBindingDefinition.swift",
    SOURCE_ROOT / "Runtime/SceneTextureAnimationPlaybackPlan.swift",
    SOURCE_ROOT / "Runtime/SceneTextureAnimationScriptCompiler.swift",
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
        let textureAnimationScripts: [SceneTextureAnimationScriptDefinition]? = nil
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
    static let compactDayHash =
        "2fd0e22672675527167908de5535719726f8f07af5b24892ef31adfd412590a7"
    static let longMonthDateHash =
        "8420e0f255e350654503e24d87a8257dbec560a64ae09524966a5659f5b538cb"
    static let clockWithPeriodHash =
        "ef8b5597f44146180b337c0c0c732ea2e2d1238a7db561cdeab6ed9106599592"
    static let timeOfDayGreetingHash =
        "7d4275e4b3cbe9ff22cf4b21f694e121f803cebd230dea37c7269dd7a9de9c8c"

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
        let subsetSource = """
        export var scriptProperties = createScriptProperties()
            .addCheckbox({ name: 'twentyFourHours', value: true })
            .addCheckbox({ name: 'includeSeconds', value: false })
            .addText({ name: 'separator', value: ':' })
            .finish();

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
        let calendarSubsetSource = """
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
        let subsetDefinition = SceneTextScriptDefinition(
            source: subsetSource,
            properties: [
                "separator": .string(":"),
                "includeSeconds": .object([
                    "user": .string("seconds"),
                    "value": .bool(true),
                ]),
                "twentyFourHours": .bool(true),
            ]
        )
        let subsetProgram = SceneTextScriptCompiler.compile(descriptor: .init(layers: [
            .init(
                id: 506,
                contentKind: "text",
                parentID: nil,
                visible: true,
                text: "fallback",
                textScript: subsetDefinition
            ),
        ]))
        let subset12HourProgram = SceneTextScriptCompiler.compile(descriptor: .init(layers: [
            .init(
                id: 507,
                contentKind: "text",
                parentID: nil,
                visible: true,
                text: "fallback",
                textScript: .init(
                    source: subsetSource,
                    properties: [
                        "separator": .string(":"),
                        "includeSeconds": .bool(true),
                        "twentyFourHours": .bool(false),
                    ]
                )
            ),
        ]))
        let calendarSubsetProgram = calendarProgram(
            id: 508,
            source: calendarSubsetSource,
            properties: [
                "dayFirst": .bool(false),
                "monthMode": .string("2"),
                "padDay": .bool(true),
                "useSlash": .bool(false),
            ]
        )
        let numericCalendarSubsetProgram = calendarProgram(
            id: 509,
            source: calendarSubsetSource,
            properties: [
                "dayFirst": .bool(true),
                "monthMode": .string("1"),
                "padDay": .bool(true),
                "useSlash": .bool(true),
            ]
        )
        let unpaddedCalendarSubsetProgram = calendarProgram(
            id: 510,
            source: calendarSubsetSource,
            properties: [
                "dayFirst": .bool(true),
                "monthMode": .string("1"),
                "padDay": .bool(false),
                "useSlash": .bool(true),
            ]
        )
        let unsupportedLoop = SceneTextScriptCompiler.compile(descriptor: .init(layers: [
            .init(
                id: 606,
                contentKind: "text",
                parentID: nil,
                visible: true,
                text: "fallback",
                textScript: .init(
                    source: "export function update(value) { while (true) {} return value; }",
                    properties: [:]
                )
            ),
        ]))
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
        let compactDay = SceneTextScriptCompiler.compileVerifiedProfile(
            layerID: 501,
            authoredText: "DAY",
            sourceSHA256: compactDayHash,
            properties: dateProperties(
                showDay: true, month: "1", day: "1", delimiter: "/"
            )
        )
        let longMonthDate = SceneTextScriptCompiler.compileVerifiedProfile(
            layerID: 502,
            authoredText: "<Date>",
            sourceSHA256: longMonthDateHash,
            properties: dateProperties(
                showDay: false, month: "2", day: "1", delimiter: "",
                useDelimiter: false
            )
        )
        let clockWithPeriod = SceneTextScriptCompiler.compileVerifiedProfile(
            layerID: 503,
            authoredText: "12:34:56 am",
            sourceSHA256: clockWithPeriodHash,
            properties: [
                "delimiter": .string(":"),
                "displayDate": .bool(false),
                "showSeconds": .bool(false),
                "use24hFormat": .bool(false),
            ]
        )
        let clockWithDate = SceneTextScriptCompiler.compileVerifiedProfile(
            layerID: 504,
            authoredText: "fallback",
            sourceSHA256: clockWithPeriodHash,
            properties: [
                "delimiter": .string(":"),
                "displayDate": .bool(true),
                "showSeconds": .bool(true),
                "use24hFormat": .bool(true),
            ]
        )
        let timeOfDaySchedule = SceneTimeOfDaySchedule(
            dayStartHour: 0,
            nightStartHour: 12
        )
        let greeting = SceneTextScriptCompiler.compileVerifiedProfile(
            layerID: 505,
            authoredText: "fallback",
            sourceSHA256: timeOfDayGreetingHash,
            properties: [
                "dayText": .string("GOOD\nMORNING"),
                "nightText": .string("GOOD\nEVENING"),
            ],
            timeOfDaySchedule: timeOfDaySchedule
        )
        let greetingMissingSharedState = SceneTextScriptCompiler.compileVerifiedProfile(
            layerID: 605,
            authoredText: "fallback",
            sourceSHA256: timeOfDayGreetingHash,
            properties: [
                "dayText": .string("GOOD\nMORNING"),
                "nightText": .string("GOOD\nEVENING"),
            ]
        )
        let compactDayMissingProperty = SceneTextScriptCompiler.compileVerifiedProfile(
            layerID: 601,
            authoredText: "fallback",
            sourceSHA256: compactDayHash,
            properties: [
                "monthFormat": .string("1"),
                "dayFormat": .string("1"),
                "showDay": .bool(true),
                "alignVertical": .bool(false),
                "useDelimiter": .bool(true),
            ]
        )
        var longMonthDateExtraProperties = dateProperties(
            showDay: false, month: "2", day: "1", delimiter: ""
        )
        longMonthDateExtraProperties["unexpected"] = .bool(true)
        let longMonthDateExtraProperty = SceneTextScriptCompiler.compileVerifiedProfile(
            layerID: 602,
            authoredText: "fallback",
            sourceSHA256: longMonthDateHash,
            properties: longMonthDateExtraProperties
        )
        let clockWithPeriodMissingProperty = SceneTextScriptCompiler.compileVerifiedProfile(
            layerID: 603,
            authoredText: "fallback",
            sourceSHA256: clockWithPeriodHash,
            properties: [
                "delimiter": .string(":"),
                "showSeconds": .bool(false),
                "use24hFormat": .bool(false),
            ]
        )
        let clockWithPeriodExtraProperty = SceneTextScriptCompiler.compileVerifiedProfile(
            layerID: 604,
            authoredText: "fallback",
            sourceSHA256: clockWithPeriodHash,
            properties: [
                "delimiter": .string(":"),
                "displayDate": .bool(false),
                "showSeconds": .bool(false),
                "use24hFormat": .bool(false),
                "unexpected": .bool(true),
            ]
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
            bindings: clock.bindings + clock12.bindings + spacedDay.bindings + date.bindings
                + compactDay.bindings + longMonthDate.bindings
                + clockWithPeriod.bindings + clockWithDate.bindings + greeting.bindings
                + subsetProgram.bindings + subset12HourProgram.bindings
                + calendarSubsetProgram.bindings + numericCalendarSubsetProgram.bindings
                + unpaddedCalendarSubsetProgram.bindings,
            diagnostics: []
        )
        let values = SceneTextScriptRuntime.values(
            program: program,
            wallDate: utcDate(year: 2026, month: 7, day: 28, hour: 23, minute: 7, second: 5),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        let morningValues = SceneTextScriptRuntime.values(
            program: greeting,
            wallDate: utcDate(year: 2026, month: 7, day: 28, hour: 7, minute: 0, second: 0),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        let earlyMonthValues = SceneTextScriptRuntime.values(
            program: SceneTextScriptProgram(
                bindings: numericCalendarSubsetProgram.bindings
                    + unpaddedCalendarSubsetProgram.bindings,
                diagnostics: []
            ),
            wallDate: utcDate(year: 2026, month: 7, day: 8, hour: 7, minute: 0, second: 0),
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
            "compactDay": string(values[.text(layerID: 501, field: .content)]),
            "longMonthDate": string(values[.text(layerID: 502, field: .content)]),
            "clockWithPeriod": string(values[.text(layerID: 503, field: .content)]),
            "clockWithDate": string(values[.text(layerID: 504, field: .content)]),
            "greetingNight": string(values[.text(layerID: 505, field: .content)]),
            "greetingMorning": string(
                morningValues[.text(layerID: 505, field: .content)]
            ),
            "subsetClock": string(values[.text(layerID: 506, field: .content)]),
            "subsetClock12": string(values[.text(layerID: 507, field: .content)]),
            "subsetCalendar": string(values[.text(layerID: 508, field: .content)]),
            "subsetNumericCalendar": string(
                earlyMonthValues[.text(layerID: 509, field: .content)]
            ),
            "subsetUnpaddedCalendar": string(
                earlyMonthValues[.text(layerID: 510, field: .content)]
            ),
            "subsetProfile": subsetProgram.bindings.first?.profile.rawValue,
            "unsupportedLoop": unsupportedLoop.diagnostics.map { $0.code.rawValue },
            "greetingMissingSharedState": greetingMissingSharedState.diagnostics.map {
                $0.code.rawValue
            },
            "newProfileInvalid": [
                compactDayMissingProperty,
                longMonthDateExtraProperty,
                clockWithPeriodMissingProperty,
                clockWithPeriodExtraProperty,
            ].flatMap { $0.diagnostics.map { $0.code.rawValue } },
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
        delimiter: String,
        useDelimiter: Bool = true
    ) -> [String: SceneJSONValue] {
        [
            "monthFormat": .string(month),
            "dayFormat": .string(day),
            "showDay": .bool(showDay),
            "alignVertical": .bool(false),
            "useDelimiter": .bool(useDelimiter),
            "addDelimiter": .string(delimiter),
        ]
    }

    static func calendarProgram(
        id: Int,
        source: String,
        properties: [String: SceneJSONValue]
    ) -> SceneTextScriptProgram {
        SceneTextScriptCompiler.compile(descriptor: .init(layers: [
            .init(
                id: id,
                contentKind: "text",
                parentID: nil,
                visible: true,
                text: "fallback",
                textScript: .init(source: source, properties: properties)
            ),
        ]))
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
        self.assertEqual(self.payload["bindingCount"], 14)
        self.assertEqual(self.payload["clock"], "-23:07-")
        self.assertEqual(self.payload["clock12"], "-11:07-:05")
        self.assertEqual(self.payload["day"], "T U E S D A Y")
        self.assertEqual(self.payload["date"], "28 JUL 2026")
        self.assertEqual(self.payload["compactDay"], "TUE")
        self.assertEqual(self.payload["longMonthDate"], "28  JULY  2026")
        self.assertEqual(self.payload["clockWithPeriod"], "11:07 PM")
        self.assertEqual(self.payload["clockWithDate"], "23:07:05\n07/28/2026")
        self.assertEqual(self.payload["subsetClock"], "23:07:05")
        self.assertEqual(self.payload["subsetClock12"], "11:07:05")
        self.assertEqual(self.payload["subsetCalendar"], "Jul-28")
        self.assertEqual(self.payload["subsetNumericCalendar"], "08/07")
        self.assertEqual(self.payload["subsetUnpaddedCalendar"], "8/07")
        self.assertEqual(self.payload["subsetProfile"], "ecmaTextUpdateSubset")
        self.assertEqual(self.payload["greetingMorning"], "GOOD\nMORNING")
        self.assertEqual(self.payload["greetingNight"], "GOOD\nEVENING")

    def test_source_and_complete_property_shape_fail_closed(self) -> None:
        self.assertEqual(self.payload["parsedSource"], "unknown source")
        self.assertEqual(self.payload["invalid"], ["invalidProperties"])
        self.assertEqual(self.payload["greetingMissingSharedState"], ["missingSharedState"])
        self.assertEqual(
            self.payload["newProfileInvalid"],
            ["invalidProperties", "invalidProperties", "invalidProperties", "invalidProperties"],
        )
        self.assertEqual(self.payload["unknown"], ["unknownProfile"])
        self.assertEqual(self.payload["unsupportedLoop"], ["unknownProfile"])
        self.assertEqual(self.payload["directUnknown"], ["92:unknownProfile"])

    def test_scene_script_value_wins_without_duplicate_definition(self) -> None:
        self.assertEqual(self.payload["definitionCount"], 14)
        self.assertEqual(self.payload["resolved"], "-23:07-")
        self.assertEqual(self.payload["source"], "sceneScript")
        self.assertEqual(self.payload["runtimeDiagnostics"], 0)


if __name__ == "__main__":
    unittest.main()
