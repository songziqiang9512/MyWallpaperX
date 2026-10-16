#!/usr/bin/env python3
"""Return-only scene scalar owners use the real VM and Bloom snapshot consumer."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests import scene_vector_vm_test_support as vm

EXTRA_SOURCES = (
    vm.SCENE / "Rendering/Composition/SceneBloomPostProcess.swift",
    vm.SCENE / "Resources/Textures/SceneResourceBudget.swift",
    vm.SCENE / "Systems/Properties/SceneUserPropertyDefinitionParser.swift",
)
# Only the existing lightweight descriptor carrier gains the production field;
# the configuration and its resolver below are compiled from their full source.
PREAMBLE = vm.SWIFT_PREAMBLE.replace(
    "    struct Camera {\n", "    struct Camera {\n        var bloom = SceneBloomConfiguration.disabled\n", 1)

HARNESS = r'''
@main enum SceneBloomScriptChecks {
    static let target = SceneDynamicTarget.scene(.bloomStrength)
    static let peer = SceneDynamicTarget.layer(layerID: 41, field: .alpha)
    static let seed = 0.4
    static func frame(_ time: Double = 1, delta: Double = 0.05) -> SceneScriptFrameInput {
        .init(timing: .init(wallDate: Date(timeIntervalSince1970: 0),
            simulationFrameTime: delta, sceneTime: time), timeZone: TimeZone(secondsFromGMT: 0)!)
    }
    static func descriptor(name: String = "neighbour", resource: String = "models/own.json",
                           hdr: Bool = false) -> SceneRenderDescriptor {
        var layer = SceneRenderDescriptor.Layer(id: 41, layerIndex: 0, name: name,
            visible: true, originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1], alpha: 0.5, effects: [])
        layer.imagePath = resource
        var scene = SceneRenderDescriptor(layers: [layer])
        scene.camera.bloom = .init(enabled: true, strength: Float(seed), threshold: 0.65,
            tint: SIMD3(1, 1, 1), hdr: hdr ? .init(strength: 1, threshold: 1,
                scatter: 0.7, feather: 0.5, iterations: 4) : nil)
        return scene
    }
    static func document(_ source: String, value: Any = seed,
                         field: String = "bloomstrength", extra: [String: Any] = [:],
                         withPeer: Bool = false) -> [String: Any] {
        var wrapper: [String: Any] = ["script": source, "value": value]
        wrapper.merge(extra) { _, new in new }
        var root: [String: Any] = ["general": [field: wrapper]]
        if withPeer {
            root["objects"] = [["id": 41, "image": "models/own.json",
                "alpha": ["value": 0.5,
                    "script": "export function update(level){return level + .125;}"]]]
        }
        return root
    }
    static func bindings(_ document: [String: Any]) -> [SceneScriptBindingIR] {
        SceneScriptBindingIRParser.parse(document: document).bindings
    }
    static func candidate(_ scene: SceneRenderDescriptor, _ scripts: [SceneScriptBindingIR],
                          timeline: Set<SceneDynamicTarget> = [],
                          excluded: Set<SceneDynamicTarget> = [],
                          properties: [SceneUserPropertyDefinition] = []) throws
        -> SceneScriptQuickJSProgramCandidate {
        try .compile(authoredDescriptor: scene, runtimeDescriptor: scene,
            scriptBindings: scripts, vectorProjection: SceneScriptVectorProgram.project(
                descriptor: scene, scriptBindings: scripts), userPropertyDefinitions: properties,
            timelineTargets: timeline, scalarExcludedTargets: excluded,
            stringExcludedTargets: [], admittedVectorPassTargets: [], generation: 9)
    }
    static func snapshot(_ definitions: [SceneDynamicTargetDefinition],
                         _ values: [SceneDynamicTarget: SceneDynamicValue]) -> SceneDynamicSnapshot {
        SceneDynamicSnapshotResolver().resolve(frameIndex: 1, generation: 9,
            definitions: definitions, sceneScriptValues: values).snapshot
    }
    static func close(_ actual: SceneDynamicValue?, _ expected: Double) -> Bool {
        guard case let .scalar(value)? = actual else { return false }
        return abs(value - expected) < 0.000001
    }
    static func audio(_ left: Float, _ right: Float, generation: UInt64) -> SceneAudioSpectrumSnapshot {
        .init(left: .init(repeating: left, count: 16),
            right: .init(repeating: right, count: 16), generation: generation)
    }
    static func audioFacts() throws -> [String: Bool] {
        var facts: [String: Bool] = [:]
        for (i, names) in [("pulse", "seedLevel", "models/own.json"),
                          ("spectrum", "baseline", "images/renamed.json"),
                          ("bands", "初值", "models/equivalent.json")].enumerated() {
            let (buffer, variable, resource) = names
            let formula = ["\(variable) + \(buffer).average[0] * 2 + engine.frametime",
                "engine.frametime + 2 * \(buffer).average[0] + \(variable)",
                "(\(variable) + engine.frametime) + (\(buffer).average[0] + \(buffer).average[0])"][i]
            let source = """
            const \(buffer) = engine.registerAudioBuffers(16);
            let \(variable) = 0;
            export function init(authored) { \(variable) = authored + .25; }
            export function update(current) { return \(formula); }
            """
            let scene = descriptor(name: "own-\(i)", resource: resource)
            let accepted = try candidate(scene, bindings(document(source)))
            let program = accepted.scalarProgram
            let report = accepted.constructionReport
            facts["audio-\(i)-unique-scene-identity"] = report.isComplete
                && report.expectedScalarTargets == [target]
                && report.instantiatedScalarTargets == [target]
                && report.expectedVectorTargets.isEmpty && report.expectedStringTargets.isEmpty
                && report.expectedCursorTargets.isEmpty && program.bindings.count == 1
                && program.bindings.first?.layerID == nil && program.hasAudioConsumers
            let first = program.evaluate(inputs: [target: .scalar(seed)], frame: frame(),
                audioSpectrum: audio(0.125, 0.375, generation: 1))
            let firstSnapshot = snapshot(program.definitions, first.values)
            facts["audio-\(i)-typed-consumer"] = first.failures.isEmpty
                && close(first.values[target], 1.2) && firstSnapshot[target]?.source == .sceneScript
                && abs(Double(scene.camera.bloom.resolving(firstSnapshot).strength) - 1.2) < 0.000001
            program.bindings.forEach { $0.commitLayerMutations() }
            let second = program.evaluate(inputs: [target: .scalar(seed)],
                frame: frame(2, delta: 0.1), audioSpectrum: audio(0, 0.5, generation: 2))
            facts["audio-\(i)-init-once-and-new-audio-delta"] = second.failures.isEmpty
                && close(second.values[target], 1.25)
            let retired = program.retire(layerIDs: [41], frame: frame(), userPropertiesJSON: "{}")
            facts["audio-\(i)-layer-retirement-does-not-retire-scene"] = retired.isEmpty
                && !program.retiredTargets.contains(target)
            let outcomes = program.teardown(frame: frame(), userPropertiesJSON: "{}")
            facts["audio-\(i)-shared-teardown"] = outcomes.count == 1
                && outcomes.allSatisfy { $0.snapshot.isQuiescent }
        }
        return facts
    }
    static func admissionFacts() throws -> [String: Bool] {
        let scene = descriptor()
        let pass = "export function update(value){return value;}"
        let valid = bindings(document(pass))
        var cases: [(String, SceneRenderDescriptor, [SceneScriptBindingIR], Set<SceneDynamicTarget>)] = [
            ("wrong-path", scene, bindings(document(pass, field: "bloomthreshold")), []),
            ("wrong-type", scene, bindings(document(pass, value: "0.4")), []),
            ("bool-fallback", scene, bindings(document(pass, value: true)), []),
            ("extra-wrapper", scene, bindings(document(pass, extra: ["unused": 1])), []),
            ("scriptproperties-wrapper", scene, bindings(document(pass, extra: ["scriptproperties": [:]])), []),
            ("user-wrapper", scene, bindings(document(pass, extra: ["user": "gain"])), []),
            ("animation-wrapper", scene, bindings(document(pass, extra: ["animation": [:]])), []),
            ("hdr-consumer", descriptor(hdr: true), valid, []),
            ("timeline-competition", scene, valid, [target]),
            ("duplicate", scene, valid + valid, []),
            ("float-overflow-seed", scene, bindings(document(pass, value: 1e300)), []),
        ]
        let b = valid[0]
        cases.append(("wrong-owner", scene, [.init(source: b.source,
            owner: .init(kind: .object, objectIndex: 0, objectID: 41,
                effectIndex: nil, effectID: nil, passIndex: nil, passID: nil),
            targetPath: b.targetPath, properties: b.properties, authoredValue: b.authoredValue,
            valueType: b.valueType, wrapperKeys: b.wrapperKeys)], []))
        var facts: [String: Bool] = [:]
        for (name, d, scripts, timeline) in cases {
            let accepted = try candidate(d, scripts, timeline: timeline)
            facts[name] = accepted.scalarProgram.bindings.isEmpty
                && !accepted.constructionReport.expectedScalarTargets.contains(target)
                && !accepted.scalarProgram.definitions.contains { $0.target == target }
        }
        let excluded = try candidate(scene, valid, excluded: [target])
        facts["late-exclusion"] = excluded.scalarProgram.bindings.isEmpty
            && excluded.constructionReport.expectedScalarTargets.isEmpty
        let ordinary = try candidate(scene, bindings(document(pass, withPeer: true)))
        facts["layer-keeps-real-source"] = ordinary.scalarProgram.bindings.first { $0.target == peer }?.layerID == 41
        return facts
    }
    static func failureFacts() throws -> [String: Bool] {
        var facts: [String: Bool] = [:]
        let scene = descriptor()
        for (name, expression) in [("nan", "NaN"), ("infinity", "Infinity"),
                                   ("float-overflow", "1e300")] {
            let accepted = try candidate(scene, bindings(document(
                "export function update(value){return \(expression);}", withPeer: true)))
            let result = accepted.scalarProgram.evaluate(inputs: [target: .scalar(seed), peer: .scalar(0.5)], frame: frame())
            let resolved = snapshot(accepted.scalarProgram.definitions, result.values)
            facts[name + "-local-fallback"] = result.failures[target]?.code == "bad-return"
                && result.values[target] == nil && close(result.values[peer], 0.625)
                && resolved[target]?.source == .authored
                && scene.camera.bloom.resolving(resolved).strength == Float(seed)
        }
        let recovered = try candidate(scene, bindings(document("""
            let count=0; export function update(v){ count++; return count===2 ? 1e300 : .8; }
            """, withPeer: true))).scalarProgram
        let inputs: [SceneDynamicTarget: SceneDynamicValue] = [target: .scalar(seed), peer: .scalar(0.5)]
        let warm = recovered.evaluate(inputs: inputs, frame: frame())
        let bad = recovered.evaluate(inputs: inputs, frame: frame(2))
        let healthy = recovered.evaluate(inputs: inputs, frame: frame(3))
        facts["bad-return-recovers"] = close(warm.values[target], 0.8)
            && bad.values[target] == nil && !recovered.disabledTargets.contains(target)
            && healthy.failures.isEmpty && close(healthy.values[target], 0.8)
        let stale = try candidate(scene, bindings(document("export function update(v){return v+1;}"))).scalarProgram
        stale.bindings.first?.invalidate()
        let staleResult = stale.evaluate(inputs: [target: .scalar(seed)], frame: frame())
        facts["stale-owner"] = staleResult.values[target] == nil && !staleResult.failures.isEmpty
        return facts
    }
    static func effectsFacts() throws -> [String: Bool] {
        var facts: [String: Bool] = [:]
        let scene = descriptor()
        let operations = [
            ("borrowed-layer", "export function update(v){thisScene.getLayer(0).alpha=.125;return 2;}"),
            ("init-effect", "export function init(v){thisScene.getLayer(0).alpha=.125;return 2;} export function update(v){return v;}"),
            ("topology", "export function update(v){thisScene.createLayer({name:'generated',text:'own'});return 2;}"),
            ("media-callback", "export function mediaPlaybackChanged(e){thisScene.getLayer(0).alpha=.125;} export function update(v){return 2;}"),
            ("property-refresh", "export function applyUserProperties(e){thisScene.getLayer(0).alpha=.125;} export function update(v){return 2;}"),
            ("throw", "export function update(v){throw new Error('own failure');}"),
        ]
        let catalog = SceneUserPropertyDefinitionParser().parse(properties: [
            "toggle": ["type": "bool", "value": false]])
        for (name, source) in operations {
            let accepted = try candidate(scene, bindings(document(source, withPeer: true)), properties: catalog.definitions)
            let program = accepted.scalarProgram
            let result = program.evaluate(inputs: [target: .scalar(seed), peer: .scalar(0.5)],
                frame: frame(), effectivePropertyValues: ["toggle": .bool(true)], propertyRevision: 1,
                targetFilter: name == "property-refresh" ? target : nil,
                propertyRefresh: name == "property-refresh", userPropertiesJSON: "{\"toggle\":true}",
                mediaPlaybackEvent: name == "media-callback" ? .init(state: 1, generation: 1) : nil)
            facts[name + "-rejects-complete-bundle"] = result.failures[target] != nil
                && result.values[target] == nil && result.ownerEffects.allSatisfy { $0.ownerTarget != target }
                && result.layerMutations.isEmpty && result.materialFunctionMutations.isEmpty
                && result.animationMutations.isEmpty
                && program.bindings.first { $0.target == target }?.pendingLayerTopologyIdentity == nil
            if name != "property-refresh" {
                facts[name + "-healthy-peer"] = close(result.values[peer], 0.625)
            }
            // Reading a prepared borrowed handle remains legal; the failed
            // owner's staged writes must not change the committed mirror.
            let observer = try SceneScriptValueOwner(domain: accepted.domain!, source:
                "export function update(v){return thisScene.getLayer(0).alpha;}",
                target: target, valueType: .scalar, effectNames: [], generation: 9, budget: .default)
            let observed = try observer.evaluate(input: .scalar(seed), frame: frame(),
                scriptPropertiesJSON: "", userPropertiesJSON: "{}",
                expectedGeneration: 9, interruptBudget: nil).get()
            facts[name + "-rollback-mirror"] = observed.value == .scalar(0.5)
        }
        let noLayer = try candidate(scene, bindings(document("""
            export function update(v){let rejected=false;try{void thisLayer.id;}catch(e){rejected=e instanceof TypeError;}return rejected?1:0;}
            """))).scalarProgram
        facts["scene-has-no-current-layer"] = close(noLayer.evaluate(inputs: [target: .scalar(seed)], frame: frame()).values[target], 1)
        let discovery = try candidate(scene, bindings(document("""
            export function update(v){if(false)thisScene.createLayer('models/own.json');return v;}
            """)))
        facts["scene-does-not-discover-images"] = discovery.domain?.dynamicImageRequestedModelPaths.isEmpty == true
        return facts
    }
    static func main() throws {
        var facts = try audioFacts()
        facts.merge(try admissionFacts()) { _, new in new }
        facts.merge(try failureFacts()) { _, new in new }
        facts.merge(try effectsFacts()) { _, new in new }
        print(String(decoding: try JSONSerialization.data(withJSONObject: facts, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


def run_harness(directory: Path) -> dict:
    inputs = [*dict.fromkeys([*vm.SWIFT_SOURCES, *EXTRA_SOURCES]), *vm.C_SOURCES,
              Path(vm.__file__), Path(__file__)]
    before = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
    binary = vm.compile_vector_harness(directory, HARNESS, "scene-bloom-script",
                                       extra_swift_sources=EXTRA_SOURCES, preamble=PREAMBLE)
    result = subprocess.run([str(binary)], text=True, capture_output=True, timeout=25)
    (directory / "stdout.json").write_text(result.stdout)
    (directory / "stderr.log").write_text(result.stderr)
    after = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
    (directory / "inputs.json").write_text(json.dumps({"before": before, "after": after,
        "harnessSHA256": hashlib.sha256(HARNESS.encode()).hexdigest(), "exitCode": result.returncode}, indent=2) + "\n")
    if before != after:
        raise AssertionError("scene bloom script source inputs changed during gate")
    if result.returncode:
        raise AssertionError(result.stderr)
    return json.loads(result.stdout)


class SceneScriptSceneBloomStrengthTests(unittest.TestCase):
    def test_scene_scalar_audio_publication_and_return_only_transaction(self) -> None:
        proof = os.environ.get("MWX_SCENE_BLOOM_SCRIPT_PROOF")
        if proof:
            directory = Path(proof)
            directory.mkdir(parents=True, exist_ok=True)
            facts = run_harness(directory)
        else:
            with tempfile.TemporaryDirectory(prefix="mwx-scene-bloom-script-") as temporary:
                facts = run_harness(Path(temporary))
        self.assertTrue(facts)
        self.assertEqual([name for name, passed in facts.items() if passed is not True], [], facts)


if __name__ == "__main__":
    unittest.main()
