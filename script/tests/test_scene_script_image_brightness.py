#!/usr/bin/env python3
"""Image brightness scripts through the real QuickJS scalar and value owners."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests import scene_vector_vm_test_support as vm

SCENE = vm.SCENE
EXTRA_SOURCES = (
    SCENE / "Systems/Properties/SceneUserPropertyDefinitionParser.swift",
    SCENE / "Systems/Properties/ScenePropertyLiveUpdateState.swift",
    SCENE / "Systems/Properties/SceneDynamicLayerValues.swift",
)

HARNESS = r'''
@main enum ImageBrightnessScriptChecks {
    static let target = SceneDynamicTarget.layer(layerID: 16, field: .brightness)
    static let seed = 0.9
    static let passthrough = "export function update(value) { return value; }"
    static let frame = SceneScriptFrameInput(timing: .init(
        wallDate: Date(timeIntervalSince1970: 0), simulationFrameTime: 1.0 / 60.0,
        sceneTime: 2), timeZone: TimeZone(secondsFromGMT: 0)!)

    static func descriptor(resource: String = "models/self-owned.json",
                           brightness: Double? = seed) -> SceneRenderDescriptor {
        var layer = SceneRenderDescriptor.Layer(id: 16, layerIndex: 0,
            name: "self-owned image", visible: true, originXYZ: [0, 0, 0],
            scaleXYZ: [1, 1, 1], alpha: 1, effects: [])
        layer.imagePath = resource
        layer.brightness = brightness
        return .init(layers: [layer])
    }

    static func document(resource: String = "models/self-owned.json",
                         source: String = passthrough, key: String? = nil,
                         input: String = "gain", value: Double = seed,
                         extra: [String: Any] = [:]) -> [String: Any] {
        var wrapper: [String: Any] = ["value": value, "script": source]
        if let key {
            wrapper["scriptproperties"] = [input: ["user": key, "value": 2.0]]
        }
        wrapper.merge(extra) { _, replacement in replacement }
        return ["objects": [["id": 16, "image": resource, "brightness": wrapper]]]
    }

    static func bindings(_ document: [String: Any]) -> [SceneScriptBindingIR] {
        SceneScriptBindingIRParser.parse(document: document).bindings
    }

    static func changed(_ binding: SceneScriptBindingIR,
                        path: [SceneScriptBindingPathComponent]? = nil,
                        authored: SceneJSONValue? = nil,
                        type: SceneScriptBindingValueType? = nil,
                        kind: SceneScriptBindingOwner.Kind? = nil) -> SceneScriptBindingIR {
        .init(source: binding.source,
            owner: .init(kind: kind ?? binding.owner.kind,
                objectIndex: binding.owner.objectIndex, objectID: binding.owner.objectID,
                effectIndex: binding.owner.effectIndex, effectID: binding.owner.effectID,
                passIndex: binding.owner.passIndex, passID: binding.owner.passID),
            targetPath: path ?? binding.targetPath, properties: binding.properties,
            authoredValue: authored ?? binding.authoredValue,
            valueType: type ?? binding.valueType, wrapperKeys: binding.wrapperKeys,
            userPropertyKey: binding.userPropertyKey)
    }

    static func candidate(_ scene: SceneRenderDescriptor,
                          _ scripts: [SceneScriptBindingIR],
                          properties: [SceneUserPropertyDefinition] = [],
                          timeline: Set<SceneDynamicTarget> = [],
                          excluded: Set<SceneDynamicTarget> = []) throws
        -> SceneScriptQuickJSProgramCandidate {
        try .compile(authoredDescriptor: scene, runtimeDescriptor: scene,
            scriptBindings: scripts,
            vectorProjection: SceneScriptVectorProgram.project(descriptor: scene,
                scriptBindings: scripts), userPropertyDefinitions: properties,
            timelineTargets: timeline, scalarExcludedTargets: excluded,
            stringExcludedTargets: [], admittedVectorPassTargets: [], generation: 11)
    }

    static func snapshot(_ definitions: [SceneDynamicTargetDefinition],
                         script: [SceneDynamicTarget: SceneDynamicValue] = [:],
                         user: [SceneDynamicTarget: SceneDynamicValue] = [:])
        -> SceneDynamicSnapshot {
        SceneDynamicSnapshotResolver().resolve(frameIndex: 1, generation: 11,
            definitions: definitions, userValues: user, sceneScriptValues: script).snapshot
    }

    static func brightness(_ values: SceneDynamicSnapshot) -> Float {
        SceneDynamicLayerValues.brightness(layerID: 16, authoredValue: seed,
            snapshot: values)
    }

    static func source(input: String, variant: Int) -> String {
        let local = ["initial", "seedLevel", "authoredGain"][variant]
        let expression = ["\(local) * scriptProperties.\(input)",
            "scriptProperties.\(input) * \(local)",
            "(\(local) + \(local)) * (scriptProperties.\(input) / 2)"][variant]
        return """
        export var scriptProperties = createScriptProperties()
            .addSlider({name:'\(input)',value:2,min:0,max:4,integer:false}).finish();
        let \(local) = 0;
        export function init(authored) { \(local) = authored; }
        export function update(current) { return \(expression); }
        """
    }

    static func propertyFacts() throws -> [String: Bool] {
        var facts: [String: Bool] = [:]
        for (index, names) in [("level", "gain", "models/original.json"),
                              ("renamedLevel", "multiplier", "models/renamed.json"),
                              ("exposure", "factor", "images/unseen-resource.json")].enumerated() {
            let (key, input, resource) = names
            let scene = descriptor(resource: resource)
            let root = document(resource: resource, source: source(input: input, variant: index),
                key: key, input: input)
            let scripts = bindings(root)
            let catalog = SceneUserPropertyDefinitionParser().parse(properties: [
                key: ["type": "slider", "value": 2.0, "min": 0, "max": 4]])
            let compiled = ScenePropertyBindingCompiler().compile(
                report: SceneUserPropertyBindingParser().parse(root: root), catalog: catalog)
            let accepted = try candidate(scene, scripts, properties: catalog.definitions)
            let program = accepted.scalarProgram
            let report = accepted.constructionReport
            facts[key + "-single-owner"] = scripts.count == 1 && accepted.domain != nil
                && report.isComplete && report.expectedScalarTargets == [target]
                && report.instantiatedScalarTargets == [target]
                && report.expectedVectorTargets.isEmpty && report.expectedStringTargets.isEmpty
                && report.expectedCursorTargets.isEmpty && program.bindings.count == 1
                && program.definitions.count == 1 && program.inputTargets == [target]
            facts[key + "-property-input"] = compiled.diagnostics.isEmpty
                && compiled.program.rebuildRequiredPropertyKeys.isEmpty
                && compiled.program.instructions.count == 1
                && !program.activeLivePropertyInputTargets.isEmpty
            var live = ScenePropertyLiveUpdateState(program: compiled.program,
                effectiveValues: catalog.effectiveValues(overrides: [:]),
                activeConsumerTargets: program.activeLivePropertyInputTargets)
            let first = program.evaluate(inputs: [target: .scalar(seed)], frame: frame,
                effectivePropertyValues: live.effectiveValues, propertyRevision: live.revision)
            let firstSnapshot = snapshot(program.definitions, script: first.values)
            facts[key + "-script-snapshot-consumer"] = first.failures.isEmpty
                && first.values[target] == .scalar(seed * 2)
                && firstSnapshot[target]?.source == .sceneScript
                && brightness(firstSnapshot) == Float(seed * 2)
            let owner = program.bindings.first
            let applied = live.apply(.number(3), forPropertyKey: key)
            let second = program.evaluate(inputs: firstSnapshot.typedValues(
                    for: program.inputTargets, valueTypes: program.inputValueTypes), frame: frame,
                effectivePropertyValues: live.effectiveValues, propertyRevision: live.revision)
            let secondSnapshot = snapshot(program.definitions, script: second.values)
            facts[key + "-live-update"] = applied && live.revision == 1
                && live.effectiveValues[key] == .number(3)
                && program.bindings.first === owner && second.failures.isEmpty
                && second.values[target] == .scalar(seed * 3)
                && secondSnapshot[target]?.source == .sceneScript
                && brightness(secondSnapshot) == Float(seed * 3)
        }
        return facts
    }

    static func admissionFacts() throws -> [String: Bool] {
        var facts: [String: Bool] = [:]
        let scene = descriptor()
        let valid = bindings(document())[0]
        var cases: [(String, SceneRenderDescriptor, [SceneScriptBindingIR], Set<SceneDynamicTarget>)] = [
            ("wrong-host", scene, [changed(valid,
                path: [.key("objects"), .index(0), .key("gain")])], []),
            ("nested-path", scene, [changed(valid,
                path: [.key("objects"), .index(0), .key("nested"), .key("brightness")])], []),
            ("wrong-owner", scene, [changed(valid, kind: .pass)], []),
            ("wrong-fallback-type", scene, [changed(valid, authored: .string("0.9"), type: .string)], []),
            // These share the same Float rounding; identity still uses the authored Double.
            ("exact-fallback", scene, [changed(valid, authored: .number(seed.nextUp))], []),
            ("missing-fallback", descriptor(brightness: nil), [valid], []),
            ("duplicate", scene, [valid, valid], []),
            ("unknown-wrapper", scene, bindings(document(extra: ["extra": true])), []),
            ("user-wrapper", scene, bindings(document(extra: ["user": "level"])), []),
            ("animation-wrapper", scene, bindings(document(extra: ["animation": ["id": 1]])), []),
            ("timeline-collision", scene, [valid], [target]),
            ("timeline-animation-collision", scene,
                bindings(document(extra: ["animation": ["id": 1]])), [target]),
            ("positive-overflow-fallback", descriptor(brightness: 1e39),
                [changed(valid, authored: .number(1e39))], []),
            ("infinite-fallback", descriptor(brightness: .infinity),
                [changed(valid, authored: .number(.infinity))], []),
            ("signed-zero-fallback", descriptor(brightness: 0),
                [changed(valid, authored: .number(-0.0))], []),
        ]
        for kind in ["solid", "text", "particle", "camera"] {
            var unsupported = scene
            unsupported.layers[0].contentKind = kind
            cases.append(("non-image-" + kind, unsupported, [valid], []))
        }
        var puppet = scene; puppet.layers[0].puppetMeshPath = "models/own.mdl"
        var model = scene; model.layers[0].staticModelPath = "models/own-model.json"
        var dependency = scene; dependency.layers[0].dependencyLayerIDs = [22]
        var authoredDependency = scene; authoredDependency.layers[0].authoredDependencies = [22]
        cases += [("puppet", puppet, [valid], []), ("static-model", model, [valid], []),
                  ("dependency", dependency, [valid], []),
                  ("authored-dependency", authoredDependency, [valid], [])]
        for (name, input, scripts, timeline) in cases {
            let program = try candidate(input, scripts, timeline: timeline)
            facts[name + "-rejected"] = SceneScriptScalarProgram.projectedTargets(
                descriptor: input, scriptBindings: scripts, timelineTargets: timeline).isEmpty
                && program.constructionReport.expectedScalarTargets.isEmpty
                && program.constructionReport.instantiatedScalarTargets.isEmpty
                && program.scalarProgram.bindings.isEmpty
                && program.scalarProgram.definitions.isEmpty
        }
        // Launch admission passes absent prepared consumers through the existing exclusion lane.
        let requestSource = """
        thisScene.createLayer('models/unclaimed-brightness.json');
        export function update(value) { return value; }
        """
        let excludedBinding = bindings(document(source: requestSource))[0]
        var resourceScene = scene
        resourceScene.modelMaterialLinks = [.init(modelPath: "models/unclaimed-brightness.json")]
        let projection = SceneScriptVectorProgram.project(descriptor: resourceScene,
            scriptBindings: [excludedBinding])
        let planned = SceneScriptQuickJSProgramCandidate.plannedOwnerSources(
            authoredDescriptor: resourceScene, runtimeDescriptor: resourceScene,
            scriptBindings: [excludedBinding],
            vectorProjection: projection, plannedVectorTargets: projection.nonPassTargets,
            timelineTargets: [], scalarExcludedTargets: [target], stringExcludedTargets: [],
            excludedStandaloneCursorLayerIDs: [])
        let excluded = try candidate(resourceScene, [excludedBinding], excluded: [target])
        let domain = try SceneScriptQuickJSDomain()
        try domain.configureLayerCatalog(resourceScene)
        let construction = SceneScriptScalarProgram.compileCandidate(domain: domain,
            descriptor: resourceScene, scriptBindings: [excludedBinding], excludedTargets: [target],
            rejectedTargets: [], generation: 11)
        facts["missing-prepared-consumer-excluded"] = planned.isEmpty
            && excluded.constructionReport.expectedScalarTargets.isEmpty
            && excluded.constructionReport.instantiatedScalarTargets.isEmpty
            && excluded.scalarProgram.definitions.isEmpty
            && construction.requestedTargets.isEmpty && construction.instantiatedTargets.isEmpty
            && construction.program.bindings.isEmpty
            && SceneScriptScalarProgram.projectedDefinitions(descriptor: resourceScene,
                scriptBindings: [excludedBinding], excludedTargets: [target]).isEmpty
        facts["excluded-literal-requests-no-resource"] = excluded.domain != nil
            && excluded.domain?.dynamicImageRequestedModelPaths.isEmpty == true
            && SceneScriptDynamicImageReferenceAnalysis.references(in: requestSource,
                descriptor: resourceScene)?.map(\.modelPath) == ["models/unclaimed-brightness.json"]
        return facts
    }

    static func numericFacts() throws -> [String: Bool] {
        var facts: [String: Bool] = [:]
        let program = try candidate(descriptor(), bindings(document())).scalarProgram
        // The next Double above Float.max still rounds to finite Float.max.
        let roundedFinite = Double(Float.greatestFiniteMagnitude).nextUp
        for (index, value) in [-Double.greatestFiniteMagnitude, -0.0, 0, 0.5, 1, 2,
                               roundedFinite].enumerated() {
            let result = program.evaluate(inputs: [target: .scalar(value)], frame: frame)
            let values = snapshot(program.definitions, script: result.values)
            facts["numeric-domain-\(index)"] = result.failures.isEmpty
                && result.values[target] == .scalar(value)
                && values[target]?.source == .sceneScript
                && brightness(values) == Float(max(0, value))
        }
        for (name, value) in [("negative", -Double.greatestFiniteMagnitude),
                              ("hdr", 2.0), ("rounded-float-max", roundedFinite)] {
            let accepted = try candidate(descriptor(brightness: value),
                bindings(document(value: value))).scalarProgram
            facts["authored-" + name] = accepted.bindings.count == 1
                && accepted.definitions.first?.authoredValue == .scalar(value)
        }
        let source = """
        let calls = 0;
        export function update(value) { return ++calls === 2 ? 1e39 : 0.8; }
        """
        var scene = descriptor()
        scene.layers.append(.init(id: 17, layerIndex: 1, name: "healthy peer",
            visible: true, originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1],
            alpha: 0.25, effects: []))
        var root = document(source: source)
        var objects = root["objects"] as! [[String: Any]]
        objects.append(["id": 17, "image": "models/healthy-peer.json",
            "alpha": ["value": 0.25, "script": "export function update(value) { return 0.5; }"]])
        root["objects"] = objects
        let pair = try candidate(scene, bindings(root)).scalarProgram
        let peer = SceneDynamicTarget.layer(layerID: 17, field: .alpha)
        let inputs: [SceneDynamicTarget: SceneDynamicValue] = [target: .scalar(seed), peer: .scalar(0.25)]
        let warmed = pair.evaluate(inputs: inputs, frame: frame)
        let failed = pair.evaluate(inputs: inputs, frame: frame)
        let fallback = snapshot(pair.definitions, script: failed.values)
        let recovered = pair.evaluate(inputs: inputs, frame: frame)
        facts["overflow-local-fallback"] = pair.bindings.count == 2
            && warmed.values[target] == .scalar(0.8)
            && failed.failures[target]?.code == "bad-return" && failed.failures.count == 1
            && failed.values[target] == nil && failed.values[peer] == .scalar(0.5)
            && fallback[target]?.source == .authored && brightness(fallback) == Float(seed)
            && fallback[peer]?.source == .sceneScript
        facts["overflow-retries-and-recovers"] = !pair.disabledTargets.contains(target)
            && recovered.failures.isEmpty && recovered.values[target] == .scalar(0.8)
            && recovered.values[peer] == .scalar(0.5)
        return facts
    }

    static func main() throws {
        var facts = try propertyFacts()
        facts.merge(try admissionFacts()) { _, latest in latest }
        facts.merge(try numericFacts()) { _, latest in latest }
        print(String(decoding: try JSONSerialization.data(withJSONObject: facts,
            options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


def run_harness(directory: Path, source: str, name: str,
                extra_sources: tuple[Path, ...] = EXTRA_SOURCES) -> dict:
    inputs = [*dict.fromkeys([*vm.SWIFT_SOURCES, *extra_sources]),
              *vm.C_SOURCES, Path(vm.__file__), Path(__file__)]
    before = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
    binary = vm.compile_vector_harness(directory, source, name,
                                       extra_swift_sources=extra_sources)
    run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=25)
    (directory / "stdout.json").write_text(run.stdout)
    (directory / "stderr.log").write_text(run.stderr)
    after = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
    (directory / "inputs.json").write_text(json.dumps({
        "before": before, "after": after, "harnessSHA256": hashlib.sha256(source.encode()).hexdigest(),
        "exitCode": run.returncode,
    }, indent=2) + "\n")
    if before != after:
        raise AssertionError("source input changed during brightness script gate")
    if run.returncode:
        raise AssertionError(run.stderr)
    return json.loads(run.stdout)


class SceneScriptImageBrightnessTests(unittest.TestCase):
    def test_scalar_owner_live_properties_numeric_domain_and_local_failure(self) -> None:
        proof = os.environ.get("MWX_SCENE_PROPERTY_PROOF")
        if proof:
            directory = Path(proof)
            directory.mkdir(parents=True, exist_ok=True)
            facts = run_harness(directory, HARNESS, "image-brightness-script")
        else:
            with tempfile.TemporaryDirectory(prefix="mwx-image-brightness-script-") as temporary:
                facts = run_harness(Path(temporary), HARNESS, "image-brightness-script")
        self.assertTrue(facts)
        self.assertEqual([key for key, passed in facts.items() if passed is not True], [])


if __name__ == "__main__":
    unittest.main()
