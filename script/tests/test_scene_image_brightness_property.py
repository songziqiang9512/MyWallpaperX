#!/usr/bin/env python3
"""Direct image brightness uses the real binding Program and value owner."""
from __future__ import annotations
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from script.tests.test_scene_property_live_update_state import SOURCE_ROOT, SWIFT_SOURCES

HARNESS = r'''
import Foundation

@main enum BrightnessPropertyHarness {
    static func property(_ key: String, seed: Double = 0.9) -> SceneUserPropertyDefinition {
        .init(key: key, title: "Brightness", kind: .slider, runtimeType: "slider",
            order: 0, index: nil, minimumValue: nil, maximumValue: nil, stepValue: nil,
            allowsFractionalValues: true, fractionalPrecision: 3, displayCondition: nil,
            defaultValue: .number(seed), options: [])
    }
    static func compile(_ key: String, resource: String, fallback: Double = 0.9,
                        seed: Double = 0.9, extra: [String: Any] = [:], text: Bool = false,
                        mixed: Bool = false) -> ScenePropertyBindingCompilation {
        let wrapper: [String: Any] = ["user": key, "value": fallback].merging(extra) { _, new in new }
        var object: [String: Any] = ["id": 16, "brightness": wrapper]
        object[text ? "text" : "image"] = text ? "self-owned text" : resource
        var objects = [object]
        if mixed { objects.append(["id": 17, "text": "unsupported", "brightness": wrapper]) }
        return ScenePropertyBindingCompiler().compile(
            report: SceneUserPropertyBindingParser().parse(root: ["objects": objects]),
            catalog: .init(definitions: [property(key, seed: seed)]))
    }
    static func main() throws {
        var facts: [String: Bool] = [:]
        for (key, resource) in [("level", "models/original.json"), ("renamedGain", "models/other.json")] {
            let target = SceneDynamicTarget.layer(layerID: 16, field: .brightness)
            let compiled = compile(key, resource: resource)
            let program = compiled.program
            func state() -> ScenePropertyLiveUpdateState {
                .init(program: program, effectiveValues: [key: .number(0.9)], activeConsumerTargets: [target])
            }
            facts[key + "-compiled"] = program.instructions.count == 1
                && program.rebuildRequiredPropertyKeys.isEmpty && compiled.diagnostics.isEmpty
            let data = try JSONEncoder().encode(compiled)
            facts[key + "-identity"] = try JSONDecoder().decode(ScenePropertyBindingCompilation.self, from: data) == compiled
            // The adjacent Double above exact Float.max still rounds to finite Float.max.
            let roundedFinite = Double(Float.greatestFiniteMagnitude).nextUp
            let finiteValues = [-Double.greatestFiniteMagnitude, -0.0, 0, 0.5, 1, 2, roundedFinite]
            for (i, value) in finiteValues.enumerated() {
                var live = state()
                let accepted = live.apply(.number(value), forPropertyKey: key)
                let snapshot = SceneDynamicSnapshotResolver().resolve(frameIndex: 1, generation: 1,
                    definitions: program.definitions, userValues: live.userValues).snapshot
                facts[key + "-finite-\(i)"] = accepted && live.revision == 1
                    && live.userValues[target] == .scalar(value)
                    && SceneDynamicLayerValues.brightness(layerID: 16, authoredValue: 0.9,
                        snapshot: snapshot) == Float(max(0, value))
            }
            var live = state()
            facts[key + "-edit"] = live.apply(.number(2), forPropertyKey: key) && live.revision == 1
            facts[key + "-noop"] = live.apply(.number(2), forPropertyKey: key) && live.revision == 1
            facts[key + "-reset"] = live.apply(.number(0.9), forPropertyKey: key)
                && live.userValues[target] == .scalar(0.9) && live.revision == 2
            for (i, bad) in [SceneUserPropertyValue.number(Double(Float.greatestFiniteMagnitude) * 2),
                             .number(.infinity), .number(.nan), .string("2")].enumerated() {
                let before = live
                facts[key + "-reject-\(i)"] = !live.apply(bad, forPropertyKey: key)
                    && live.revision == before.revision && live.effectiveValues == before.effectiveValues
                    && live.userValues == before.userValues
            }
            let overflow = Double(Float.greatestFiniteMagnitude) * 2
            facts[key + "-bad-fallback"] = compile(key, resource: resource, fallback: overflow)
                .program.rebuildRequiredPropertyKeys.contains(key)
            facts[key + "-bad-default"] = compile(key, resource: resource, seed: overflow)
                .program.rebuildRequiredPropertyKeys.contains(key)
            for (name, extra) in [("script", ["script": "export function update(v) { return v * 2; }"] as [String: Any]),
                                  ("animation", ["animation": ["frames": []]] as [String: Any])] {
                facts[key + "-" + name] = compile(key, resource: resource, extra: extra)
                    .program.rebuildRequiredPropertyKeys.contains(key)
            }
            let mixed = compile(key, resource: resource, mixed: true).program
            var mixedState = ScenePropertyLiveUpdateState(program: mixed,
                effectiveValues: [key: .number(0.9)], activeConsumerTargets: [target])
            facts[key + "-mixed"] = !mixedState.apply(.number(2), forPropertyKey: key)
                && mixedState.effectiveValues[key] == .number(0.9) && mixedState.revision == 0
            let callback = SceneDynamicTarget.layer(layerID: 99, field: .alpha)
            var unavailable = ScenePropertyLiveUpdateState(program: program,
                effectiveValues: [key: .number(0.9)], activeConsumerTargets: [target],
                scriptUserPropertyConsumerTargetsByKey: [key: [callback]])
            facts[key + "-callback"] = !unavailable.apply(.number(2), forPropertyKey: key)
                && unavailable.effectiveValues[key] == .number(0.9) && unavailable.revision == 0
            let priority = SceneDynamicSnapshotResolver().resolve(frameIndex: 2, generation: 2,
                definitions: program.definitions, userValues: [target: .scalar(2)],
                sceneScriptValues: [target: .scalar(0.7)]).snapshot
            facts[key + "-priority"] = priority[target]?.source == .sceneScript
                && SceneDynamicLayerValues.brightness(layerID: 16, authoredValue: 0.9, snapshot: priority) == 0.7
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: facts, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''

class SceneImageBrightnessPropertyTests(unittest.TestCase):
    def test_real_program_numeric_domain_and_atomic_live_updates(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc unavailable")
        with tempfile.TemporaryDirectory(prefix="mwx-image-brightness-") as directory:
            work = Path(directory)
            harness = work / "Harness.swift"
            harness.write_text(HARNESS)
            binary = work / "probe"
            compiled = subprocess.run(["swiftc", "-enable-upcoming-feature", "MemberImportVisibility",
                *map(str, SWIFT_SOURCES), str(SOURCE_ROOT / "Systems/Properties/SceneDynamicLayerValues.swift"),
                str(harness), "-module-cache-path", str(work / "cache"), "-o", str(binary)],
                capture_output=True, text=True)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            facts = json.loads(result.stdout)
            print(result.stdout.strip())
            self.assertTrue(facts)
            for name, accepted in facts.items():
                self.assertTrue(accepted, name)

if __name__ == "__main__":
    unittest.main()
