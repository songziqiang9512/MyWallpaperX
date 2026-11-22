#!/usr/bin/env python3
"""Raw authored width bindings must reach the existing live text snapshot."""

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_scene_property_live_update_state import SWIFT_SOURCES, SOURCE_ROOT

WIDTH_SOURCES = [*SWIFT_SOURCES, SOURCE_ROOT / "Systems/Properties/SceneUserPropertyDefinitionParser.swift"]


HARNESS = r'''
import Foundation

@main enum Harness {
    static func main() throws {
        func property(_ key: String, _ minimum: Double = 700,
                      _ maximum: Double = 2000, _ kind: String = "slider") -> [String: Any] {
            ["type": kind, "value": 790, "min": minimum, "max": maximum]
        }
        func object(_ id: Int, _ key: String, _ changes: [String: Any] = [:]) -> [String: Any] {
            var result: [String: Any] = [
                "id": id, "text": "Long authored title", "limitwidth": true,
                "maxwidth": ["user": key, "value": 790],
            ]
            result.merge(changes) { _, new in new }
            return result
        }
        func compile(_ objects: [[String: Any]], _ properties: [String: Any]) -> ScenePropertyBindingProgram {
            let report = SceneUserPropertyBindingParser().parse(root: ["objects": objects])
            let catalog = SceneUserPropertyDefinitionParser().parse(properties: properties)
            return ScenePropertyBindingCompiler().compile(report: report, catalog: catalog).program
        }
        let targets = Set([363, 220, 488, 222].map {
            SceneDynamicTarget.text(layerID: $0, field: .maxWidth)
        })
        let program = compile([
            object(363, "titleWidth"), object(220, "titleWidth"),
            object(488, "artistWidth"), object(222, "artistWidth"),
        ], ["titleWidth": property("titleWidth"), "artistWidth": property("artistWidth")])
        let decoded = try JSONDecoder().decode(ScenePropertyBindingProgram.self,
                                               from: JSONEncoder().encode(program))
        var state = ScenePropertyLiveUpdateState(program: decoded,
            effectiveValues: ["titleWidth": .number(790), "artistWidth": .number(790)],
            activeConsumerTargets: targets)
        let titleAccepted = state.apply(.number(1200), forPropertyKey: "titleWidth")
        let artistAccepted = state.apply(.number(700), forPropertyKey: "artistWidth")
        let values = decoded.evaluate(effectiveValues: state.effectiveValues).userValues
        let fourValues = [363, 220].allSatisfy { values[.text(layerID: $0, field: .maxWidth)] == .scalar(1200) }
            && [488, 222].allSatisfy { values[.text(layerID: $0, field: .maxWidth)] == .scalar(700) }
        let before = state.effectiveValues
        let badValuesRejected = !state.apply(.number(2001), forPropertyKey: "titleWidth")
            && !state.apply(.number(.infinity), forPropertyKey: "titleWidth")
            && !state.apply(.string("900"), forPropertyKey: "titleWidth")
            && state.effectiveValues == before
        var missingConsumer = ScenePropertyLiveUpdateState(program: decoded,
            effectiveValues: before, activeConsumerTargets: targets.subtracting([
                .text(layerID: 220, field: .maxWidth)
            ]))
        let missingConsumerRejected = !missingConsumer.apply(.number(1000), forPropertyKey: "titleWidth")
            && missingConsumer.effectiveValues == before
        let rejected: [(String, [[String: Any]], [String: Any])] = [
            ("nonText", [object(1, "width", ["text": NSNull()])], ["width": property("width")]),
            ("unlimited", [object(1, "width", ["limitwidth": false])], ["width": property("width")]),
            ("script", [object(1, "width", ["maxwidth": ["user": "width", "value": 790, "script": "export function update(){return 800;}"]])], ["width": property("width")]),
            ("timeline", [object(1, "width", ["maxwidth": ["user": "width", "value": 790, "animation": [:]]])], ["width": property("width")]),
            ("missingDefinition", [object(1, "width")], [:]),
            ("wrongKind", [object(1, "width")], ["width": property("width", 700, 2000, "bool")]),
            ("zeroDomain", [object(1, "width")], ["width": property("width", 0)]),
            ("oversizedDomain", [object(1, "width")], ["width": property("width", 700, 20000)]),
            ("badDefault", [object(1, "width")], ["width": ["type": "slider", "value": 20000, "min": 700, "max": 2000]]),
            ("zeroFallback", [object(1, "width", ["maxwidth": ["user": "width", "value": 0]])], ["width": property("width")]),
        ]
        var negatives: [String: Bool] = [:]
        for (name, objects, properties) in rejected {
            let candidate = compile(objects, properties)
            negatives[name] = candidate.rebuildRequiredPropertyKeys.contains("width")
                && candidate.instructions.isEmpty
        }
        let result: [String: Any] = [
            "fourTargets": Set(program.definitions.map(\.target)) == targets,
            "noRebuild": program.rebuildRequiredPropertyKeys.isEmpty,
            "liveFanout": titleAccepted && artistAccepted && fourValues,
            "badValuesRejected": badValuesRejected,
            "missingConsumerRejected": missingConsumerRejected,
            "negativeCases": negatives,
        ]
        print(String(data: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
'''


class SceneTextWidthPropertyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-text-width-property-")
        root = Path(cls.temporary.name)
        source = root / "main.swift"
        source.write_text(HARNESS)
        binary = root / "width"
        subprocess.run(["swiftc", "-parse-as-library", *map(str, WIDTH_SOURCES),
                        str(source), "-o", str(binary)], check=True, text=True)
        cls.result = json.loads(subprocess.check_output([str(binary)], text=True))

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def test_raw_width_binding_reaches_both_consumers(self):
        for key in ("fourTargets", "noRebuild", "liveFanout"):
            with self.subTest(key=key):
                self.assertTrue(self.result[key])

    def test_failed_updates_are_atomic(self):
        self.assertTrue(self.result["badValuesRejected"])
        self.assertTrue(self.result["missingConsumerRejected"])

    def test_unsupported_width_routes_keep_rebuild(self):
        for name, rejected in self.result["negativeCases"].items():
            with self.subTest(name=name):
                self.assertTrue(rejected)


if __name__ == "__main__":
    unittest.main()
