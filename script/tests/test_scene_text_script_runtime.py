#!/usr/bin/env python3
"""Authored text bindings execute through the shared QuickJS and typed state."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from .scene_vector_vm_test_support import compile_vector_harness


HARNESS = r'''
@main
enum Harness {
    static let frozenDate = Date(timeIntervalSince1970: 1_785_280_025)
    static let utc = TimeZone(secondsFromGMT: 0)!

    final class Fixture {
        let domain: SceneScriptQuickJSDomain
        let program: SceneScriptStringProgram
        let runtime: SceneScriptDynamicLayerRuntime
        let parserDiagnostics: [SceneScriptBindingDiagnostic]
        let targets: [SceneDynamicTarget]
        var current: [SceneDynamicTarget: SceneDynamicValue]
        var frameIndex: UInt64 = 0

        init(_ wrappers: [[String: Any]], hiddenParent: Bool = false) throws {
            var objects: [[String: Any]] = []
            var layers: [SceneRenderDescriptor.Layer] = []
            if hiddenParent {
                objects.append(["id": 999, "visible": false])
                layers.append(.init(id: 999, layerIndex: 0, name: "hidden parent",
                    visible: false, originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1],
                    alpha: 1, effects: [], contentKind: "container"))
            }
            for (index, wrapper) in wrappers.enumerated() {
                let id = 100 + index
                var object: [String: Any] = ["id": id, "text": wrapper]
                if hiddenParent { object["parent"] = 999 }
                objects.append(object)
                layers.append(.init(id: id, layerIndex: layers.count, name: "text \(id)",
                    visible: true, originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1],
                    alpha: 1, effects: [], contentKind: "text",
                    text: wrapper["value"] as? String,
                    textStyle: .init(fontPath: nil, colorRGB: nil, pointSize: 32),
                    sizeWH: [300, 80], parentID: hiddenParent ? 999 : nil))
            }
            if hiddenParent { layers[0].childLayerIDs = Array(100..<(100 + wrappers.count)) }
            let parsed = SceneScriptBindingIRParser.parse(document: ["objects": objects])
            let descriptor = SceneRenderDescriptor(layers: layers)
            let domain = try SceneScriptQuickJSDomain()
            try domain.configureLayerCatalog(descriptor)
            self.domain = domain
            parserDiagnostics = parsed.diagnostics
            program = SceneScriptStringProgram.compile(domain: domain, descriptor: descriptor,
                scriptBindings: parsed.bindings, generation: 1)
            runtime = SceneScriptDynamicLayerRuntime(descriptor: descriptor,
                authoredMutationLayerIDs: Set(100..<(100 + wrappers.count)))
            targets = wrappers.indices.map { .text(layerID: 100 + $0, field: .content) }
            current = Dictionary(uniqueKeysWithValues: program.definitions.map {
                ($0.target, $0.authoredValue)
            })
        }

        func step(
            date: Date = Harness.frozenDate,
            properties: [String: SceneUserPropertyValue] = [:],
            userValues: [SceneDynamicTarget: SceneDynamicValue] = [:],
            timelineValues: [SceneDynamicTarget: SceneDynamicValue] = [:],
            media: SceneScriptMediaPropertiesEventInput? = nil,
            interruptBudget: UInt64? = nil
        ) throws -> [String: Any] {
            frameIndex += 1
            var inputs = current
            inputs.merge(userValues) { _, next in next }
            inputs.merge(timelineValues) { _, next in next }
            let frame = SceneScriptFrameInput(timing: .init(wallDate: date,
                simulationFrameTime: 1.0 / 60.0, sceneTime: Double(frameIndex) / 60),
                timeZone: Harness.utc)
            let result = program.evaluate(inputs: inputs, effectivePropertyValues: properties,
                propertyRevision: frameIndex, frame: frame,
                mediaPropertiesEvent: media, interruptBudget: interruptBudget)
            try runtime.apply(result.layerMutations).get()
            program.finalizeLayerMutations(committing: true)
            var scriptValues = result.values
            scriptValues.merge(runtime.snapshot().authoredLayerValues) { _, mutation in mutation }
            let resolved = SceneDynamicSnapshotResolver().resolve(frameIndex: frameIndex,
                generation: frameIndex, definitions: program.definitions,
                userValues: userValues, timelineValues: timelineValues,
                sceneScriptValues: scriptValues)
            current = Dictionary(uniqueKeysWithValues: targets.compactMap { target in
                resolved.snapshot[target].map { (target, $0.value) }
            })
            return [
                "bindings": program.bindings.count,
                "parserDiagnostics": parserDiagnostics.map { $0.code.rawValue },
                "values": targets.map { Harness.string(resolved.snapshot[$0]?.value) },
                "sources": targets.map { resolved.snapshot[$0]?.source.rawValue ?? "missing" },
                "failures": targets.map { result.failures[$0]?.code ?? "ok" },
                "mutations": result.layerMutations.count,
                "publications": result.values.count,
                "snapshotDiagnostics": resolved.diagnostics.count,
            ]
        }
    }

    static func wrapper(_ source: String, seed: String = "authored",
                        properties: [String: Any] = [:],
                        metadata: Bool = false) -> [String: Any] {
        var result: [String: Any] = ["script": source, "value": seed,
                                    "scriptproperties": properties]
        if metadata {
            result["label"] = "editor label"
            result["editor"] = ["collapsed": true]
        }
        return result
    }

    static func string(_ value: SceneDynamicValue?) -> String {
        if case let .string(text)? = value { return text }
        return "missing"
    }

    static func calendarProperties(dayFirst: Bool, monthMode: String,
                                   padDay: Bool, useSlash: Bool) -> [String: Any] {
        ["dayFirst": dayFirst, "monthMode": monthMode,
         "padDay": padDay, "useSlash": useSlash]
    }

    static func main() throws {
        let clocks = try Fixture([
            wrapper(clock, properties: [
                "separator": ["label": "delimiter", "value": ["value": ":"]],
                "includeSeconds": ["value": ["user": "seconds", "value": true]],
                "twentyFourHours": ["value": true],
                "unusedMetadata": ["editorOnly": ["label": "unused"]],
            ], metadata: true),
            wrapper(clock, properties: ["separator": ":", "includeSeconds": ["user": NSNull(), "value": true],
                                        "twentyFourHours": false]),
            wrapper(clock, properties: ["separator": "-", "includeSeconds": false,
                                        "twentyFourHours": true]),
            wrapper(explicitClock, properties: ["separator": ":"]),
            wrapper("""
                export function update(value) {
                    return new Date().getTime() + '|' + Date.now() + '|'
                        + new Date(0).getUTCFullYear();
                }
                """),
        ])
        let dateSemantics = try Fixture([wrapper("""
            export function update(value) {
                const saved = Date.prototype.toString;
                Date.prototype.toString = null;
                let called;
                try { called = Date(); } finally { Date.prototype.toString = saved; }
                class DerivedDate extends Date {}
                const derived = new DerivedDate();
                return JSON.stringify([called === new Date().toString(),
                    Date.UTC(1970, 0, 1), Date.parse('1970-01-01T00:00:00Z'),
                    new Date(undefined).toString(), new Date(0).constructor === Date,
                    derived instanceof DerivedDate, derived instanceof Date,
                    derived.getTime() === Date.now()]);
            }
            """)])
        let clockValues = try clocks.step(properties: ["seconds": .bool(true)])
        let clockWithoutSeconds = try clocks.step(properties: ["seconds": .bool(false)])
        let calendar = try Fixture([
            wrapper(calendarSource, properties: calendarProperties(
                dayFirst: false, monthMode: "2", padDay: true, useSlash: false)),
            wrapper(calendarSource, properties: calendarProperties(
                dayFirst: true, monthMode: "1", padDay: true, useSlash: true)),
            wrapper(calendarSource, properties: calendarProperties(
                dayFirst: true, monthMode: "1", padDay: false, useSlash: true)),
        ])
        let calendarValues = try calendar.step()
        var dateCalendar = Calendar(identifier: .gregorian)
        dateCalendar.timeZone = utc
        let earlyDate = dateCalendar.date(from: .init(year: 2026, month: 7,
            day: 8, hour: 7, minute: 0, second: 0))!
        let earlyCalendar = try calendar.step(date: earlyDate)
        let midnight = dateCalendar.date(from: .init(year: 2026, month: 7,
            day: 29, hour: 0, minute: 0, second: 0))!
        let midnightClock = try clocks.step(date: midnight, properties: ["seconds": .bool(true)])

        let equivalent = try Fixture([
            wrapper("""
                export function update(value) {
                    let digits = '';
                    for (let index = 0; index < 3; index += 1) { digits += index; }
                    return digits;
                }
                """),
            wrapper("export function update(renamed) { return [0, 1, 2].join(''); }"),
        ])
        let hidden = try Fixture([wrapper(
            "export function update(value) { return ['PREPARED', 'CHILD'].join(' '); }")],
            hiddenParent: true)

        let media = try Fixture([
            wrapper("""
                export let __workshopId = '1234567890';
                export function init(value) { return ''; }
                export function mediaPropertiesChanged(event) {
                    thisLayer.text = event.title;
                }
                """, seed: ""),
            wrapper("""
                export function mediaPropertiesChanged(renamed) {
                    thisLayer.text = renamed.artist
                }
                """, seed: "authored-artist"),
        ])
        let beforeMedia = try media.step()
        let zeroMedia = try media.step(media: .init(title: "invalid", artist: "invalid", generation: 0))
        let titleEvent = SceneScriptMediaPropertiesEventInput(
            title: "Track 名称", artist: "Artist", generation: 1)
        let mediaValues = try media.step(media: titleEvent)
        let repeatedMedia = try media.step(media: titleEvent)
        let clearedMedia = try media.step(media: .init(title: "", artist: "", generation: 2))
        let staleMedia = try media.step(media: titleEvent)

        let failures = try Fixture([
            wrapper("""
                let calls = 0;
                export function update(value) {
                    calls += 1;
                    if (calls > 1) { thisLayer.text = 'must-not-leak'; throw new Error('local'); }
                    return 'script:' + value;
                }
                """),
            wrapper("export function update(value) { while (true) {} }"),
            wrapper("export function update(value) { return 'healthy'; }"),
        ])
        let firstFailure = try failures.step(interruptBudget: 64)
        let changedLower = try failures.step(
            userValues: [failures.targets[0]: .string("user-2")],
            timelineValues: [failures.targets[0]: .string("timeline-2")],
            interruptBudget: 64)
        let disabledLower = try failures.step(
            timelineValues: [failures.targets[0]: .string("timeline-3")],
            interruptBudget: 64)

        let priority = try Fixture([wrapper(clock, properties: [
            "separator": ":", "includeSeconds": true, "twentyFourHours": true])])
        let priorityTarget = priority.targets[0]
        let priorityValues = try priority.step(
            userValues: [priorityTarget: .string("user")],
            timelineValues: [priorityTarget: .string("timeline")])
        let lowerPriority = SceneDynamicSnapshotResolver().resolve(frameIndex: 1,
            generation: 1, definitions: priority.program.definitions,
            userValues: [priorityTarget: .string("user")],
            timelineValues: [priorityTarget: .string("timeline")])

        let malformed = ["invalid", NSNull(), ["not-an-object"]] as [Any]
        let malformedProperties = malformed.map { value -> [String: Any] in
            let parsed = SceneScriptBindingIRParser.parse(document: ["objects": [[
                "id": 100, "text": ["script": clock, "value": "fallback", "scriptproperties": value],
            ]]])
            return ["bindings": parsed.bindings.count,
                    "diagnostics": parsed.diagnostics.map { $0.code.rawValue }]
        }
        let payload: [String: Any] = [
            "clocks": clockValues, "dateSemantics": try dateSemantics.step(),
            "clockWithoutSeconds": clockWithoutSeconds,
            "midnightClock": midnightClock,
            "calendar": calendarValues, "earlyCalendar": earlyCalendar,
            "equivalent": try equivalent.step(), "hidden": try hidden.step(),
            "beforeMedia": beforeMedia, "zeroMedia": zeroMedia,
            "media": mediaValues, "repeatedMedia": repeatedMedia,
            "clearedMedia": clearedMedia, "staleMedia": staleMedia,
            "firstFailure": firstFailure, "changedLower": changedLower,
            "disabledLower": disabledLower, "priority": priorityValues,
            "lowerPriority": ["value": string(lowerPriority.snapshot[priorityTarget]?.value),
                "source": lowerPriority.snapshot[priorityTarget]?.source.rawValue ?? "missing",
                "diagnostics": lowerPriority.diagnostics.count],
            "malformedProperties": malformedProperties,
        ]
        print(String(decoding: try JSONSerialization.data(withJSONObject: payload,
            options: [.sortedKeys]), as: UTF8.self))
    }

    static let clock = """
        export function update(previousText) {
            const now = new Date();
            var hours = now.getHours();
            if (!scriptProperties.twentyFourHours) {
                hours %= 12;
                if (hours == 0) { hours = 12; }
            }
            hours = ('00' + hours).slice(-2);
            const minutes = ('00' + now.getMinutes()).slice(-2);
            previousText = hours + scriptProperties.separator + minutes;
            if (scriptProperties.includeSeconds) {
                previousText += scriptProperties.separator + ('00' + now.getSeconds()).slice(-2);
            }
            return previousText;
        }
        """

    static let explicitClock = """
        export const scriptProperties = createScriptProperties()
            .addText({name: 'separator', value: '-'}).finish();
        export function update(renamed) {
            const stamp = new Date(Date.now());
            return [stamp.getHours(), stamp.getMinutes(), stamp.getSeconds()]
                .map(number => String(number).padStart(2, '0')).join(scriptProperties.separator);
        }
        """

    static let calendarSource = """
        let monthLabels;
        let separator;
        export function update(originalText) {
            if (scriptProperties.monthMode === 2) { return 'must-not-coerce'; }
            if (scriptProperties.monthMode == 2) {
                monthLabels = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
            } else {
                monthLabels = ['01', '02', '03', '04', '05', '06',
                    '07', '08', '09', '10', '11', '12'];
            }
            separator = scriptProperties.useSlash ? ['/'] : ['-'];
            const current = new Date();
            let dayNumber = current.getDate();
            if (dayNumber < 10 && scriptProperties.padDay) { dayNumber = '0' + dayNumber; }
            return scriptProperties.dayFirst
                ? dayNumber + separator + monthLabels[current.getMonth()]
                : monthLabels[current.getMonth()] + separator + dayNumber;
        }
        """
}
'''


class SceneTextScriptRuntimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        temporary = tempfile.TemporaryDirectory(prefix="mwx-text-script-vm-")
        cls.addClassCleanup(temporary.cleanup)
        binary = compile_vector_harness(Path(temporary.name), HARNESS, "text-script-runtime")
        execution = subprocess.run(
            [str(binary)], capture_output=True, text=True,
            env={**os.environ, "TZ": "UTC"},
        )
        if execution.returncode:
            raise AssertionError(execution.stdout + execution.stderr)
        cls.payload = json.loads(execution.stdout.strip().splitlines()[-1])

    def assert_clean(self, key: str, bindings: int) -> dict:
        result = self.payload[key]
        self.assertEqual(result["bindings"], bindings, result)
        self.assertEqual(result["parserDiagnostics"], [], result)
        self.assertEqual(result["failures"], ["ok"] * bindings, result)
        self.assertEqual(result["snapshotDiagnostics"], 0, result)
        return result

    def test_clock_properties_and_frozen_wall_date_use_the_real_vm(self) -> None:
        result = self.assert_clean("clocks", 5)
        self.assertEqual(result["values"], [
            "23:07:05", "11:07:05", "23-07", "23:07:05",
            "1785280025000|1785280025000|1970",
        ])
        without_seconds = self.assert_clean("clockWithoutSeconds", 5)
        self.assertEqual(without_seconds["values"][:4], [
            "23:07", "11:07:05", "23-07", "23:07:05",
        ])
        midnight = self.assert_clean("midnightClock", 5)
        self.assertEqual(midnight["values"][:4], ["00:00:00", "12:00:00", "00-00", "00:00:00"])

    def test_calendar_padding_arrays_and_ecmascript_equality(self) -> None:
        self.assertEqual(self.assert_clean("calendar", 3)["values"], ["Jul-28", "28/07", "28/07"])
        self.assertEqual(self.assert_clean("earlyCalendar", 3)["values"], ["Jul-08", "08/07", "8/07"])

    def test_equivalent_expressions_and_legal_loops_are_executed(self) -> None:
        self.assertEqual(self.assert_clean("equivalent", 2)["values"], ["012", "012"])

    def test_hidden_parent_does_not_remove_the_prepared_text_binding(self) -> None:
        self.assertEqual(self.assert_clean("hidden", 1)["values"], ["PREPARED CHILD"])

    def test_media_absence_generation_and_empty_clear_keep_their_distinct_meanings(self) -> None:
        for key in ("beforeMedia", "zeroMedia"):
            with self.subTest(key=key):
                self.assertEqual(self.assert_clean(key, 2)["values"], ["", "authored-artist"])
        self.assertEqual(self.assert_clean("media", 2)["values"], ["Track 名称", "Artist"])
        repeated = self.assert_clean("repeatedMedia", 2)
        self.assertEqual(repeated["values"], ["Track 名称", "Artist"])
        self.assertEqual(repeated["mutations"], 0)
        self.assertEqual(self.assert_clean("clearedMedia", 2)["values"], ["", ""])
        stale = self.assert_clean("staleMedia", 2)
        self.assertEqual(stale["values"], ["", ""])
        self.assertEqual(stale["mutations"], 0)

    def test_date_preserves_native_construction_and_function_call_semantics(self) -> None:
        result = self.assert_clean("dateSemantics", 1)
        self.assertEqual(json.loads(result["values"][0]),
                         [True, 0, 0, "Invalid Date", True, True, True, True])

    def test_exception_and_vm_budget_keep_lower_current_and_healthy_peer(self) -> None:
        first = self.payload["firstFailure"]
        self.assertEqual(first["bindings"], 3, first)
        self.assertEqual(first["parserDiagnostics"], [], first)
        self.assertEqual(first["failures"], ["ok", "budget-exceeded", "ok"], first)
        self.assertEqual(first["values"], ["script:authored", "authored", "healthy"], first)
        changed = self.payload["changedLower"]
        self.assertEqual(changed["failures"], ["exception", "ok", "ok"], changed)
        self.assertEqual(changed["values"], ["timeline-2", "authored", "healthy"], changed)
        self.assertEqual(changed["sources"][0], "timeline", changed)
        self.assertEqual(changed["mutations"], 0, changed)
        disabled = self.payload["disabledLower"]
        self.assertEqual(disabled["failures"], ["ok", "ok", "ok"], disabled)
        self.assertEqual(disabled["values"], ["timeline-3", "authored", "healthy"], disabled)
        for result in (first, changed, disabled):
            self.assertEqual(result["snapshotDiagnostics"], 0, result)

    def test_typed_script_output_has_priority_and_lower_lanes_remain_valid(self) -> None:
        result = self.assert_clean("priority", 1)
        self.assertEqual(result["values"], ["23:07:05"])
        self.assertEqual(result["sources"], ["sceneScript"])
        self.assertEqual(self.payload["lowerPriority"], {
            "value": "timeline", "source": "timeline", "diagnostics": 0,
        })

    def test_malformed_property_objects_are_rejected_by_the_format_entry(self) -> None:
        for result in self.payload["malformedProperties"]:
            with self.subTest(result=result):
                self.assertEqual(result, {"bindings": 0, "diagnostics": ["invalidProperties"]})


if __name__ == "__main__":
    unittest.main()
