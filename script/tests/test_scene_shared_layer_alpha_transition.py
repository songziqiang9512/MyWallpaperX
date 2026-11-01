#!/usr/bin/env python3
"""Shared alpha uses the production Bool/scalar QuickJS domain and typed state."""
from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from .scene_vector_vm_test_support import SCENE, VM, compile_vector_harness


HARNESS = r'''
@main enum Harness {
    final class Fixture {
        let candidate: SceneScriptQuickJSProgramCandidate
        let scheduler: SceneScriptMediaFrameCoordinator
        let writerTarget: SceneDynamicTarget
        let targets: [SceneDynamicTarget]
        let definitions: [SceneDynamicTargetDefinition]
        let parserDiagnostics: [SceneScriptBindingDiagnostic]
        var transaction = SceneEvaluationTransaction()
        var frameIndex: UInt64 = 0
        var sceneTime: Double = 0

        init(_ alphaWrappers: [[String: Any]], writer: String = Harness.writer,
             renamed: Bool = false, writerUtility: SceneUtilityLayer.Kind? = nil,
             writerVisible: Bool = true, writerDependencies: Bool = false,
             writerModel: Bool = false) throws {
            let writerID = renamed ? 71 : 11
            let visibilityTarget = SceneDynamicTarget.layer(layerID: writerID, field: .visibility)
            writerTarget = visibilityTarget
            let firstAlphaID = renamed ? 930 : 100
            var objects: [[String: Any]] = [["id": writerID,
                "visible": ["value": writerVisible, "script": writer]]]
            var layers: [SceneRenderDescriptor.Layer] = [
                .init(id: writerID, layerIndex: 0, name: renamed ? "toggle renamed" : "toggle",
                    visible: writerVisible, originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1],
                    alpha: 1, effects: [])]
            if let kind = writerUtility {
                let image = "models/util/\(kind.rawValue)layer.json"
                objects[0]["image"] = image
                layers[0].contentKind = kind.rawValue
                layers[0].imagePath = image
                layers[0].utilityLayer = .init(kind: kind, copyBackground: false,
                    passthrough: false)
            }
            if writerModel {
                let model = renamed ? "models/alternate-controller.mdl" : "models/controller.mdl"
                objects[0]["model"] = model
                layers[0].contentKind = "model"
                layers[0].staticModelPath = model
            }
            for (index, wrapper) in alphaWrappers.enumerated() {
                let id = firstAlphaID + index
                let image = renamed ? "materials/alternate-\(index).json" : "materials/image-\(index).json"
                objects.append(["id": id, "image": image, "alpha": wrapper])
                layers.append(.init(id: id, layerIndex: layers.count,
                    name: renamed ? "renamed image \(index)" : "image \(index)",
                    visible: true, originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1],
                    alpha: wrapper["value"] as? Double, effects: [], imagePath: image))
            }
            if writerDependencies {
                objects[0]["dependencies"] = [firstAlphaID]
                layers[0].dependencyLayerIDs = [firstAlphaID]
            }
            let parsed = SceneScriptBindingIRParser.parse(document: ["objects": objects])
            parserDiagnostics = parsed.diagnostics
            let descriptor = SceneRenderDescriptor(layers: layers)
            candidate = try SceneScriptQuickJSProgramCandidate.compile(
                authoredDescriptor: descriptor, runtimeDescriptor: descriptor,
                scriptBindings: parsed.bindings,
                vectorProjection: SceneScriptVectorProgram.project(
                    descriptor: descriptor, scriptBindings: parsed.bindings),
                userPropertyDefinitions: [Harness.property("enabled", .bool),
                    Harness.property("ceiling", .slider), Harness.property("percentage", .slider)],
                timelineTargets: [], scalarExcludedTargets: [], stringExcludedTargets: [],
                admittedVectorPassTargets: [], generation: 1)
            scheduler = SceneScriptMediaFrameCoordinator(vectorProgram: candidate.vectorProgram,
                stringProgram: candidate.stringProgram, scalarProgram: candidate.scalarProgram)
            targets = alphaWrappers.indices.map { .layer(layerID: firstAlphaID + $0, field: .alpha) }
            let programDefinitions = candidate.vectorProgram.definitions + candidate.scalarProgram.definitions
            let claimed = Set(programDefinitions.map(\.target))
            let authored = SceneScriptDynamicLayerRuntime(descriptor: descriptor,
                authoredMutationLayerIDs: []).authoredLayerDefinitions
            definitions = programDefinitions + authored.filter {
                $0.target == visibilityTarget && !claimed.contains($0.target)
            }
        }

        func step(_ delta: Double, enabled: Bool = true, ceiling: Double? = nil,
                  percentage: Double? = nil, revision: UInt64 = 1,
                  userValues: [SceneDynamicTarget: SceneDynamicValue] = [:],
                  timelineValues: [SceneDynamicTarget: SceneDynamicValue] = [:]) -> [String: Any] {
            frameIndex += 1
            sceneTime += delta
            let frame = SceneScriptFrameInput(timing: .init(
                wallDate: Date(timeIntervalSince1970: 0),
                simulationFrameTime: delta, sceneTime: sceneTime))
            var properties: [String: SceneUserPropertyValue] = ["enabled": .bool(enabled)]
            if let ceiling { properties["ceiling"] = .number(ceiling) }
            if let percentage { properties["percentage"] = .number(percentage) }
            let json = SceneScriptPropertyInputCodec.userPropertiesJSON(
                values: properties, kinds: ["enabled": .bool, "ceiling": .slider, "percentage": .slider])
            let previous = transaction.previousValues(for: Set(definitions.map(\.target)),
                userValues: userValues, timelineValues: timelineValues)
            let preliminary = SceneDynamicSnapshotResolver().resolve(
                frameIndex: frameIndex, generation: 0, definitions: definitions,
                userValues: userValues, timelineValues: timelineValues,
                sceneScriptValues: previous).snapshot
            let vectorInputs = preliminary.values(for: candidate.vectorProgram.inputTargets)
            let scalarInputs = preliminary.values(for: candidate.scalarProgram.inputTargets)
            let initialized = scheduler.initialize(vectorInputs: vectorInputs, stringInputs: [:],
                scalarInputs: scalarInputs, effectivePropertyValues: properties,
                frame: frame, userPropertiesJSON: json, audioSpectrum: .silent)
            let result = scheduler.evaluate(vectorInputs: vectorInputs, stringInputs: [:],
                scalarInputs: scalarInputs, effectivePropertyValues: properties,
                frame: frame, userPropertiesJSON: json, propertyRevision: revision,
                events: .init(playback: nil, properties: nil, thumbnail: nil, timeline: nil),
                audioSpectrum: .silent, initializationFailures: initialized.failures)
            candidate.vectorProgram.finalizeLayerMutations(committing: true)
            candidate.scalarProgram.finalizeLayerMutations(committing: true)
            candidate.stringProgram.finalizeLayerMutations(committing: true)
            scheduler.finalizeInitializations()
            var values = previous
            values.merge(result.vector.values) { _, next in next }
            values.merge(result.scalar.values) { _, next in next }
            let resolution = transaction.evaluate(frameIndex: frameIndex,
                definitions: definitions, userValues: userValues, timelineValues: timelineValues,
                sceneScriptValues: values)
            var report = committed()
            report["failures"] = targets.map { result.scalar.failures[$0]?.code ?? "ok" }
            report["vectorFailures"] = result.vector.failures.count
            report["initializationFailures"] = initialized.failures.count
            report["snapshotDiagnostics"] = resolution.diagnostics.count
            report["scalarPublications"] = result.scalar.values.count
            report["boolPublications"] = result.vector.values.count
            report["disabled"] = targets.map { candidate.scalarProgram.disabledTargets.contains($0) }
            return report
        }

        func committed() -> [String: Any] {
            let snapshot = transaction.committedSnapshot
            return ["values": targets.map { Harness.scalar(snapshot?[$0]?.value) },
                "sources": targets.map { snapshot?[$0]?.source.rawValue ?? "missing" },
                "frameIndex": snapshot?.frameIndex ?? 0,
                "generation": snapshot?.generation ?? 0,
                "complete": candidate.constructionReport.isComplete,
                "scalarOwners": candidate.scalarProgram.bindings.count,
                "boolOwners": candidate.vectorProgram.bindings.count,
                "writerVisible": snapshot?[writerTarget]?.value == .bool(true),
                "writerSource": snapshot?[writerTarget]?.source.rawValue ?? "missing",
                "writerIdle": candidate.vectorProgram.bindings.first?.owner.requiresFrameEvaluation == false,
                "writerNeedsInitialization": candidate.vectorProgram.bindings.first?.owner.needsInitialization == true,
                "parserDiagnostics": parserDiagnostics.map { $0.code.rawValue }]
        }
    }

    static let writer = """
        export function init(value) { shared.enabled=true; return value; }
        export function applyUserProperties(properties) {
            if ('enabled' in properties) shared.enabled=properties.enabled;
        }
        """

    static func property(_ key: String, _ kind: SceneUserPropertyKind) -> SceneUserPropertyDefinition {
        .init(key: key, title: key, kind: kind, runtimeType: kind.rawValue, order: 0,
            index: nil, minimumValue: nil, maximumValue: nil, stepValue: nil,
            allowsFractionalValues: true, fractionalPrecision: nil, displayCondition: nil,
            defaultValue: nil, options: [])
    }

    static func scalar(_ value: SceneDynamicValue?) -> Double {
        guard case let .scalar(number)? = value else { return -999 }
        return number
    }

    static func wrapper(_ source: String, seed: Double = 0,
                        properties: [String: Any] = [:]) -> [String: Any] {
        ["value": seed, "script": source, "scriptproperties": properties]
    }

    static func ramp(inverse: Bool = false, equivalent: Bool = false) -> String {
        if equivalent {
            return """
                export function update(opacity) {
                    const flagKey=['en','abled'].join('');
                    const active=shared[flagKey]===\(inverse ? "false" : "true");
                    let next=opacity;
                    for(let i=0;i<(active?2:6);i++) next+=(active?1:-1)*engine.frametime;
                    return Math.max(0,Math.min(scriptProperties.cap,next));
                }
                """
        }
        return """
            export function update(value) {
                if (shared.enabled == \(inverse ? "false" : "true")) {
                    value += engine.frametime * 2;
                    if (value >= scriptProperties.cap) value = scriptProperties.cap;
                } else {
                    value -= engine.frametime * 6;
                    if (value <= 0) value = 0;
                }
                return value;
            }
            """
    }

    static func progression(_ renamed: Bool) throws -> [[String: Any]] {
        let f = try Fixture([
            wrapper(ramp(equivalent: renamed), properties: ["cap": 1]),
            wrapper(ramp(inverse: true, equivalent: renamed), seed: 1, properties: ["cap": 1])
        ], renamed: renamed)
        return [f.step(0.1), f.step(0.1),
            f.step(0.05, enabled: false, revision: 2),
            f.step(0.1, enabled: false, revision: 2), f.step(1, revision: 3)]
    }

    static func main() throws {
        var out: [String: Any] = [:]
        let initialized = try Fixture([wrapper(ramp(), properties: ["cap": 1])],
            writer: "export function init(v){shared.enabled=true;return v;}")
        out["initialization"] = [initialized.step(0.1), initialized.step(0.1)]
        out["projectModuleOnly"] = try [false, true].map { seed in
            let project = try Fixture([wrapper(ramp(), properties: ["cap": 1])],
                writer: "shared={enabled:true};", writerUtility: .project, writerVisible: seed)
            return [project.step(0.1), project.step(0.1)]
        }
        for shape in ["dependentProject", "model"] {
            out[shape + "ModuleOnly"] = try [false, true].map { renamed in
                let flag = renamed ? "renamedSwitch" : "enabled"
                var source = ramp().replacingOccurrences(of: "enabled", with: flag)
                if renamed { source = source.replacingOccurrences(of: "value", with: "opacity") }
                let fixture = try Fixture([wrapper(source, properties: ["cap": 1])],
                    writer: "shared={\(flag):true};", renamed: renamed,
                    writerUtility: shape == "dependentProject" ? .project : nil,
                    writerDependencies: shape == "dependentProject", writerModel: shape == "model")
                return [fixture.step(0.1), fixture.step(0.1)]
            }
        }
        out["dependencyCompositionCallbacks"] = try [false, true].map { renamed in
            let fixture = try Fixture([wrapper(ramp(equivalent: renamed), properties: ["cap": 1])],
                writer: """
                    shared={enabled:true};
                    export function applyUserProperties(properties) {
                        if ('enabled' in properties) shared.enabled=properties.enabled;
                    }
                    export function update(value) { return false; }
                    """, renamed: renamed, writerUtility: .composition, writerDependencies: true)
            return [fixture.step(0.1), fixture.step(0.1, enabled: false, revision: 2)]
        }
        out["progression"] = try progression(false)
        out["equivalent"] = try progression(true)

        let live = try Fixture([wrapper(ramp(), properties: [
            "cap": ["value": ["user": "ceiling", "value": 1]]])])
        out["liveUpper"] = [live.step(0.25, ceiling: 0.8), live.step(0.25, ceiling: 0.8),
            live.step(0.1, ceiling: 0.3, revision: 2),
            live.step(0.1, ceiling: 0.9, revision: 3)]

        let percentage = try Fixture([wrapper("""
            export var scriptProperties = createScriptProperties()
                .addSlider({name:'cap',value:50,min:0,max:100,integer:false}).finish();
            export function update(value) {
                return shared.enabled ? Math.min(value+engine.frametime*2,scriptProperties.cap/100) : 0;
            }
            """, properties: ["cap": ["value": ["user": "percentage", "value": 50]]])])
        out["nestedFallback"] = [percentage.step(0.4),
            percentage.step(0.2, percentage: 75, revision: 2),
            percentage.step(0.1, percentage: 25, revision: 3)]

        let failed = try Fixture([
            wrapper("export function update(v){shared.failedWrites=7;throw new Error('one owner');}", seed: 0.4),
            wrapper("export function update(v){return shared.failedWrites/10;}"),
            wrapper("""
                export function update(v){
                    shared.attempts=(shared.attempts||0)+1;
                    if(shared.attempts===1)return {};
                    return v+0.1;
                }
                """, seed: 0.3)
        ])
        out["exceptionLocality"] = [failed.step(0.1), failed.step(0.1)]

        let limited = try Fixture([
            wrapper("export function update(v){shared.beforeBudget=2;while(true){}return v;}", seed: 0.6),
            wrapper("export function update(v){return shared.beforeBudget/10;}")])
        out["budgetLocality"] = [limited.step(0.1), limited.step(0.1)]

        let cached = try Fixture([wrapper("""
            export function update(v) {
                shared.alphaUpdates=(shared.alphaUpdates||0)+1;
                return shared.alphaUpdates/10;
            }
            """)])
        let first = cached.step(0.1)
        // Session owns whether to evaluate. These reads exercise the real
        // committed typed state; they deliberately do not call a VM owner.
        let rereads = (0..<4).map { _ in cached.committed() }
        out["committedReads"] = ["first": first, "rereads": rereads, "next": cached.step(0.1)]

        let priority = try Fixture([wrapper("export function update(v){return shared.enabled?v+0.2:v;}")])
        let target = priority.targets[0]
        out["typedPriority"] = priority.step(0.1,
            userValues: [target: .scalar(0.4)], timelineValues: [target: .scalar(0.7)])
        print(String(data: try JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
'''


class SharedLayerAlphaTransitionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-shared-alpha-vm-")
        cls.addClassCleanup(cls.temporary.cleanup)
        binary = compile_vector_harness(
            Path(cls.temporary.name), HARNESS, "shared-alpha-vm",
            extra_swift_sources=(VM / "SceneScriptMediaFrameCoordinator.swift",
                                 SCENE / "Systems/Properties/SceneEvaluationTransaction.swift"),
        )
        run = subprocess.run([str(binary)], check=True, capture_output=True,
                             text=True, timeout=30)
        cls.result = json.loads(run.stdout)

    def assert_values(self, report: dict, expected: list[float]) -> None:
        self.assertTrue(report["complete"])
        self.assertEqual(report["parserDiagnostics"], [])
        self.assertEqual(report["boolOwners"], 1)
        self.assertEqual(report["scalarOwners"], len(expected))
        self.assertEqual(report["vectorFailures"], 0)
        self.assertEqual(report["initializationFailures"], 0)
        self.assertEqual(report["snapshotDiagnostics"], 0)
        for actual, value in zip(report["values"], expected, strict=True):
            self.assertAlmostEqual(actual, value, places=7)

    def test_bool_init_and_live_shared_toggle_drive_two_and_six_rates(self) -> None:
        expected = [[0.2, 0.4], [0.4, 0], [0.1, 0.1], [0, 0.3], [1, 0]]
        for report, values in zip(self.result["progression"], expected, strict=True):
            self.assert_values(report, values)
            self.assertEqual(report["failures"], ["ok", "ok"])
            self.assertEqual(report["sources"], ["sceneScript", "sceneScript"])

    def test_bool_initialization_precedes_scalar_without_property_callback(self) -> None:
        for report, value in zip(self.result["initialization"], [0.2, 0.4], strict=True):
            self.assert_values(report, [value])
            self.assertEqual(report["failures"], ["ok"])

    def test_project_module_only_shared_seed_keeps_authored_visibility(self) -> None:
        for seed, frames in zip([False, True], self.result["projectModuleOnly"], strict=True):
            for report, value in zip(frames, [0.2, 0.4], strict=True):
                self.assert_values(report, [value])
                self.assertEqual(report["failures"], ["ok"])
                self.assertEqual(report["boolPublications"], 0)
                self.assertEqual(report["writerVisible"], seed)
                self.assertEqual(report["writerSource"], "authored")
                self.assertTrue(report["writerIdle"])
                self.assertFalse(report["writerNeedsInitialization"])

    def test_dependent_project_module_keeps_shared_initialization(self) -> None:
        self.assert_module_only_writer("dependentProjectModuleOnly")

    def test_model_module_keeps_shared_initialization(self) -> None:
        self.assert_module_only_writer("modelModuleOnly")

    def test_dependency_composition_callbacks_publish_bool_with_shared_state(self) -> None:
        for renamed, frames in zip([False, True], self.result["dependencyCompositionCallbacks"], strict=True):
            with self.subTest(renamed=renamed):
                for report, value in zip(frames, [0.2, 0], strict=True):
                    self.assert_values(report, [value])
                    self.assertEqual(report["failures"], ["ok"])
                    self.assertEqual(report["boolPublications"], 1)
                    self.assertFalse(report["writerVisible"])
                    self.assertEqual(report["writerSource"], "sceneScript")
                    self.assertFalse(report["writerIdle"])
                    self.assertFalse(report["writerNeedsInitialization"])

    def assert_module_only_writer(self, key: str) -> None:
        for renamed, frames in zip([False, True], self.result[key], strict=True):
            with self.subTest(renamed=renamed,
                             alpha=[frame["values"] for frame in frames],
                             owners=[frame["boolOwners"] for frame in frames]):
                for report, value in zip(frames, [0.2, 0.4], strict=True):
                    self.assert_values(report, [value])
                    self.assertEqual(report["failures"], ["ok"])
                    self.assertEqual(report["boolPublications"], 0)
                    self.assertTrue(report["writerVisible"])
                    self.assertEqual(report["writerSource"], "authored")
                    self.assertTrue(report["writerIdle"])
                    self.assertFalse(report["writerNeedsInitialization"])

    def test_renamed_resources_and_equivalent_loop_and_bracket_access(self) -> None:
        for original, alternate in zip(self.result["progression"], self.result["equivalent"], strict=True):
            self.assert_values(alternate, original["values"])
            self.assertEqual(alternate["failures"], ["ok", "ok"])

    def test_live_upper_limit_replaces_fallback_without_recompilation(self) -> None:
        for report, value in zip(self.result["liveUpper"], [0.5, 0.8, 0.3, 0.5], strict=True):
            self.assert_values(report, [value])
            self.assertEqual(report["failures"], ["ok"])

    def test_nested_user_fallback_keeps_author_units_before_javascript(self) -> None:
        for report, value in zip(self.result["nestedFallback"], [0.5, 0.75, 0.25], strict=True):
            self.assert_values(report, [value])
            self.assertEqual(report["failures"], ["ok"])

    def test_exception_is_local_and_shared_writes_are_not_rolled_back(self) -> None:
        first, second = self.result["exceptionLocality"]
        self.assert_values(first, [0.4, 0.7, 0.3])
        self.assertEqual(first["failures"], ["exception", "ok", "bad-return"])
        self.assertEqual(first["disabled"], [True, False, False])
        self.assertEqual(first["sources"], ["authored", "sceneScript", "authored"])
        self.assert_values(second, [0.4, 0.7, 0.4])
        self.assertEqual(second["failures"], ["ok", "ok", "ok"])
        self.assertEqual(second["scalarPublications"], 2)

    def test_budget_exhaustion_keeps_healthy_peer_and_prior_shared_write(self) -> None:
        first, second = self.result["budgetLocality"]
        self.assert_values(first, [0.6, 0.2])
        self.assertEqual(first["failures"], ["budget-exceeded", "ok"])
        self.assertEqual(first["disabled"], [True, False])
        self.assert_values(second, [0.6, 0.2])
        self.assertEqual(second["scalarPublications"], 1)

    def test_committed_snapshot_reads_do_not_reenter_update(self) -> None:
        result = self.result["committedReads"]
        self.assert_values(result["first"], [0.1])
        for reread in result["rereads"]:
            self.assertEqual(reread["values"], result["first"]["values"])
            self.assertEqual(reread["frameIndex"], result["first"]["frameIndex"])
            self.assertEqual(reread["generation"], result["first"]["generation"])
        self.assert_values(result["next"], [0.2])

    def test_scalar_result_publishes_through_typed_snapshot_priority(self) -> None:
        report = self.result["typedPriority"]
        self.assert_values(report, [0.9])
        self.assertEqual(report["sources"], ["sceneScript"])
        self.assertEqual(report["failures"], ["ok"])


if __name__ == "__main__":
    unittest.main()
